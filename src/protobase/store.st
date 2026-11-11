"-- store.st: PBFileStorage and PBSegmentReader, the file storage, read side --

The space directory of ProtoBase's FileStorage (proto_db/storage/file.py at
v2.0.0rc1; format spec v2.0.0rc1, 'Segments and records' and 'Root records'):

  space.root        the published root (PBRootRecord), replaced atomically
  space.root.tmp    the scratch file of a publish in progress; never read
  <uuid-hex>.seg    append-only segments: a 26-byte header, then records

  PBFileStorage path: aString           opens (creating the directory if needed)
  aStorage readRoot                     the PBRootRecord on disk, or nil
  aStorage loadAt: aPointer expecting: aTag
                                        the PBAtomEnvelope of the ATOM record at
                                        aPointer; its references resolve lazily
  aStorage refTo: bytes offset: n tag: t
                                        the resolver of PBCodec: an unloaded atom
  aStorage recordsOfSegment: aUUID      the record walk of a segment
  aStorage close                        later reads signal PBClosedError

Opening checks what ProtoBase checks: a path that exists and is not a
directory is PBValidationError; a directory holding cluster/ (a cluster
node's space) is PBNotSupportedError, since clusters are outside the
prototype (design spec 10.5); a corrupt space.root, a missing segment or a
damaged record at the root pointer is PBCorruptionError. A missing space.root
is an empty space.

Each segment is read through one PBSegmentReader, which holds a BinaryFile
(positioned reads only: nothing here moves a file position) and checks the
segment header once, when it opens: the header's UUID must be the one the
file is named by (format spec, 'Segment header'). The readers are cached in an
Atom over a PBFrozenDict (segment hex -> reader), replaced by compare-and-swap,
never changed in place, so concurrent loads never lock. Two loads that open
the same segment at once both open a reader; the first installed wins and the
other closes its own. Every record is checked against its CRCs when read.

This module writes nothing: the write side (segments, publishing the root
under the owner lock) is Task 17."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/registry'.
Import from: 'protobase/codec'.
Import from: 'protobase/framing'.

"=== PBSegmentReader ========================================================"

"The read side of one segment file: its UUID (16 bytes), its open BinaryFile and
 its decoded header."
Object subclass: #PBSegmentReader instanceVariableNames: 'segment file header'.

"A reader of the segment aUUID (16 bytes) in the file aFileReference. A missing
 file is PBCorruptionError (a pointer names a segment that is not there), and so
 is a header that does not decode or whose UUID is not aUUID; a header version
 other than 2, 3 or 4 is PBNotSupportedError. The file is closed on any refusal."
PBSegmentReader class >> segment: aUUID file: aFileReference
  | bytes file header ok |
  bytes := _PBFrame uuidBytes: aUUID.
  bytes isNil ifTrue: [
    ^ PBValidationError signal: 'PBSegmentReader: a segment UUID or 16 bytes was expected, not ' , aUUID printString].
  file := [BinaryFile open: aFileReference options: #(#read)]
    on: FileSystemError do: [:e |
      (e isKindOf: FileDoesNotExist) ifTrue: [
        ^ PBCorruptionError signal: 'PBSegmentReader: the segment ' , bytes hex asLowercase , ' is missing'].
      ^ PBUnexpectedError signal: 'PBSegmentReader: cannot open the segment ' , bytes hex asLowercase , ': ' , e messageText].
  ok := false.
  [header := PBSegmentHeader decode: (file readAt: 0 size: PBSegmentHeader byteSize).
   header segment = bytes ifFalse: [
     ^ PBCorruptionError signal: 'PBSegmentReader: the segment file ' , bytes hex asLowercase
       , '.seg has the header of the segment ' , header segmentHex].
   ok := true] ensure: [ok ifFalse: [file close]].
  ^ self basicNew _setSegment: bytes file: file header: header.

PBSegmentReader >> _setSegment: aByteArray file: aBinaryFile header: aHeader
  "Runs once, on a fresh instance."
  segment isNil ifFalse: [^ PBUserError signal: 'PBSegmentReader is initialised once'].
  segment := aByteArray.
  file := aBinaryFile.
  header := aHeader.
  ^ self.

"The segment's UUID, 16 bytes."
PBSegmentReader >> segment
  ^ segment.

PBSegmentReader >> segmentHex
  ^ segment hex asLowercase.

"The PBSegmentHeader read when the reader opened."
PBSegmentReader >> header
  ^ header.

"The size of the segment file now (it may grow while a writer appends)."
PBSegmentReader >> size
  ^ file size.

"{ PBRecordHeader. payload } of the verified record at anOffset (from the start
 of the file). An offset inside the segment header, a truncated record, a bad
 magic, kind or CRC is PBCorruptionError."
PBSegmentReader >> recordAt: anOffset
  | where headerBytes recordHeader payload |
  ((_PBFrame isInt: anOffset) and: [anOffset >= 0]) ifFalse: [
    ^ PBValidationError signal: 'PBSegmentReader recordAt: an offset >= 0 was expected, not ' , anOffset printString].
  where := ' at ' , self segmentHex , ':' , anOffset printString.
  anOffset < PBSegmentHeader byteSize ifTrue: [^ PBCorruptionError signal: 'PBSegmentReader: no record' , where].
  headerBytes := file readAt: anOffset size: PBRecordHeader byteSize.
  headerBytes size < PBRecordHeader byteSize ifTrue: [
    ^ PBCorruptionError signal: 'PBSegmentReader: truncated record header' , where].
  recordHeader := [PBRecordHeader decode: headerBytes] on: PBCorruptionError do: [:e |
    ^ PBCorruptionError signal: e messageText , where].
  anOffset + PBRecordHeader byteSize + recordHeader length > file size ifTrue: [
    ^ PBCorruptionError signal: 'PBSegmentReader: truncated record payload' , where].
  payload := file readAt: anOffset + PBRecordHeader byteSize size: recordHeader length.
  payload := [recordHeader payloadIn: payload at: 1] on: PBCorruptionError do: [:e |
    ^ PBCorruptionError signal: e messageText , where].
  ^ { recordHeader. payload }.

"Every record from offset 26 to the end of the file, in order: an Array of
 { offset. PBRecordHeader. payload }. A record that fails its checks, a torn
 tail included, is PBCorruptionError: the walk never skips bytes."
PBSegmentReader >> records
  | out offset end |
  out := OrderedCollection new.
  offset := PBSegmentHeader byteSize.
  end := file size.
  [offset < end] whileTrue: [
    | record |
    record := self recordAt: offset.
    out add: { offset. record at: 1. record at: 2 }.
    offset := offset + PBRecordHeader byteSize + (record at: 1) length].
  ^ out asArray.

"Closes the file (idempotent)."
PBSegmentReader >> close
  file close.

PBSegmentReader >> printOn: aStream
  self isClassObject ifTrue: [^ aStream nextPutAll: self name].
  aStream nextPutAll: 'PBSegmentReader('; nextPutAll: self segmentHex; nextPut: $).

"=== PBFileStorage =========================================================="

"A space directory, read side. directory is its FileReference, readers an Atom
 over a PBFrozenDict (segment hex -> PBSegmentReader), closed an Atom over a
 Boolean."
Object subclass: #PBFileStorage instanceVariableNames: 'directory readers closed'.

PBFileStorage class >> rootFileName
  ^ 'space.root'.

PBFileStorage class >> segmentSuffix
  ^ '.seg'.

"The storage of the space directory aPath (a String or a FileReference), created
 when missing. The published root is validated (its record is read and
 checked) before the storage is answered."
PBFileStorage class >> path: aPath
  | dir storage ok |
  ((aPath isString and: [aPath isSymbol not and: [aPath notEmpty]]) or: [aPath isKindOf: FileReference]) ifFalse: [
    ^ PBValidationError signal: 'PBFileStorage path: a path was expected, not ' , aPath printString].
  dir := aPath isString ifTrue: [aPath asFileReference] ifFalse: [aPath].
  (dir exists and: [dir isDirectory not]) ifTrue: [
    ^ PBValidationError signal: 'PBFileStorage: ' , dir pathString , ' exists and is not a directory'].
  (dir / 'cluster') exists ifTrue: [
    ^ PBNotSupportedError signal: 'PBFileStorage: ' , dir pathString
      , ' holds cluster/, the space of a cluster node: clusters are not supported by protoBaseST'].
  [dir ensureCreateDirectory] on: FileSystemError do: [:e |
    ^ PBUnexpectedError signal: 'PBFileStorage: cannot create the space directory ' , dir pathString , ': ' , e messageText].
  storage := self basicNew _setDirectory: dir.
  ok := false.
  [storage _validateRoot. ok := true] ensure: [ok ifFalse: [storage close]].
  ^ storage.

PBFileStorage >> _setDirectory: aFileReference
  "Runs once, on a fresh instance."
  directory isNil ifFalse: [^ PBUserError signal: 'PBFileStorage is initialised once'].
  directory := aFileReference.
  readers := Atom on: (PBFrozenDict withAssociations: #()).
  closed := Atom on: false.
  ^ self.

"The space directory, a FileReference."
PBFileStorage >> directory
  ^ directory.

PBFileStorage >> isClosed
  ^ closed value.

PBFileStorage >> _checkOpen
  closed value ifTrue: [^ PBClosedError signal: 'PBFileStorage: the storage is closed'].

"The root record the root file holds now (written by any process), or nil when
 the space has none. A corrupt root is PBCorruptionError."
PBFileStorage >> readRoot
  | file bytes |
  self _checkOpen.
  file := directory / self class rootFileName.
  bytes := [file binaryContents] on: FileSystemError do: [:e |
    (e isKindOf: FileDoesNotExist) ifTrue: [^ nil].
    ^ PBUnexpectedError signal: 'PBFileStorage: cannot read ' , file pathString , ': ' , e messageText].
  ^ PBRootRecord decode: bytes.

PBFileStorage >> _validateRoot
  | root |
  root := self readRoot.
  root isNil ifFalse: [self recordAt: root pointer].

"{ PBRecordHeader. payload } of the verified record at aPointer, of any kind."
PBFileStorage >> recordAt: aPointer
  | reader |
  (aPointer isKindOf: PBAtomPointer) ifFalse: [
    ^ PBValidationError signal: 'PBFileStorage: a PBAtomPointer was expected, not ' , aPointer printString].
  self _checkOpen.
  reader := self _readerFor: aPointer segmentBytes.
  ^ self _whileOpen: [reader recordAt: aPointer offset].

"The PBAtomEnvelope of the ATOM record at aPointer, read through a reference
 tagged aTag: the record must be an ATOM (a BLOB is PBCorruptionError) and its
 envelope must pass PBAtomEnvelope decode:expecting:resolver:, with this
 storage resolving its references (refTo:offset:tag:)."
PBFileStorage >> loadAt: aPointer expecting: aTag
  | record |
  record := self recordAt: aPointer.
  (record at: 1) isAtom ifFalse: [
    ^ PBCorruptionError signal: 'PBFileStorage: the record at ' , aPointer printString , ' is a BLOB, not an ATOM'].
  ^ PBAtomEnvelope decode: (record at: 2) expecting: aTag resolver: self.

"The resolver of PBCodec fromWire:resolver: (Task 7): the reference to the
 record at offset anOffset of the segment aSegmentBytes, of the type aTag, is an
 unloaded atom of that type's class (PBTypeRegistry unloadedAtomFor:at:storage:),
 which loads its record through this storage on first use."
PBFileStorage >> refTo: aSegmentBytes offset: anOffset tag: aTag
  ^ PBTypeRegistry unloadedAtomFor: aTag
    at: (PBAtomPointer segment: aSegmentBytes offset: anOffset)
    storage: self.

"The records of the segment aUUID (a UUID, its 16 bytes or its 32 hexadecimal
 digits), walked from offset 26: an Array of { offset. PBRecordHeader. payload }."
PBFileStorage >> recordsOfSegment: aUUID
  | bytes reader |
  bytes := (aUUID isString and: [aUUID isSymbol not and: [aUUID size = 32]])
    ifTrue: [[ByteArray fromHex: aUUID] on: Error do: [:e | nil]]
    ifFalse: [_PBFrame uuidBytes: aUUID].
  (bytes isKindOf: ByteArray) ifFalse: [
    ^ PBValidationError signal: 'PBFileStorage recordsOfSegment: a segment UUID was expected, not ' , aUUID printString].
  self _checkOpen.
  reader := self _readerFor: bytes.
  ^ self _whileOpen: [reader records].

"The number of segment readers open now (one per segment read since the open)."
PBFileStorage >> openSegmentCount
  ^ readers value size.

"The cached reader of the segment aByteArray, opened (and its header checked)
 on first use."
PBFileStorage >> _readerFor: aByteArray
  | hex mine |
  hex := aByteArray hex asLowercase.
  (readers value at: hex ifAbsent: [nil]) ifNotNil: [:cached | ^ cached].
  mine := PBSegmentReader segment: aByteArray file: directory / (hex , self class segmentSuffix).
  [| current installed |
   current := readers value.
   installed := current at: hex ifAbsent: [nil].
   installed isNil ifFalse: [mine close. ^ self _unlessClosed: installed].
   readers value: (PBFrozenDict withAssociations: current associations , { hex -> mine }) ifCurrent: current]
    whileFalse.
  ^ self _unlessClosed: mine.

"aReader, unless the storage is closed: a close that ran while aReader was being
 installed may have missed it, so it is closed here and PBClosedError signalled."
PBFileStorage >> _unlessClosed: aReader
  closed value ifTrue: [aReader close. ^ PBClosedError signal: 'PBFileStorage: the storage is closed'].
  ^ aReader.

"aBlock's value. An Error from a reader the storage closed meanwhile is
 PBClosedError; a failure of the file system is PBUnexpectedError (ProtoBase:
 an OSError while reading is ProtoUnexpectedError)."
PBFileStorage >> _whileOpen: aBlock
  ^ aBlock on: Error do: [:e |
    (e isKindOf: PBDBError) ifTrue: [e pass].
    closed value ifTrue: [^ PBClosedError signal: 'PBFileStorage: the storage was closed during a read'].
    (e isKindOf: FileSystemError) ifTrue: [^ PBUnexpectedError signal: 'PBFileStorage: a read failed: ' , e messageText].
    e pass].

"Closes every segment reader; later loads, walks and root reads signal
 PBClosedError. Idempotent."
PBFileStorage >> close
  closed value: true ifCurrent: false.
  readers value do: [:reader | reader close].

PBFileStorage >> printOn: aStream
  self isClassObject ifTrue: [^ aStream nextPutAll: self name].
  aStream nextPutAll: 'PBFileStorage('; nextPutAll: directory pathString; nextPut: $).
