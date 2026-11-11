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
                                        (map keys at once: loadAt:expecting:within:)
  aStorage refTo: bytes offset: n tag: t
                                        the resolver of PBCodec: an unloaded atom
  aStorage recordsOfSegment: aUUID      the diagnostic walk of a complete segment
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
other closes its own. close sets the closed flag before it empties the cache,
and a load re-reads the flag after it installs a reader, so a reader installed
while close runs is closed by the load that installed it (PBClosedError). A
read under a reader that close closes meanwhile is PBClosedError too: protoST's
BinaryFile keeps its descriptor until the read in progress returns. Every
record is checked against its CRCs when read. The seams PBFileStorage >>
_openReader: and PBSegmentReader class >> _openFile: open a reader and its
file; tests override them to force each interleaving.

The space is read by pointer only (the root, then each reference), as ProtoBase
reads it: a segment is never scanned. A file storage never truncates a segment,
so the tail of one may be torn by a crash, or growing under a live writer;
nothing published points there. recordsOfSegment: is not a read path: it is
the walk of a complete segment for the conformance runner and diagnostics, and
it reports a torn tail or an append in progress as PBCorruptionError by design.

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
  file := [self _openFile: aFileReference]
    on: FileSystemError do: [:e |
      (e isKindOf: FileDoesNotExist) ifTrue: [
        ^ PBCorruptionError signal: 'PBSegmentReader: the segment ' , bytes hex asLowercase , ' is missing'].
      ^ PBUnexpectedError signal: 'PBSegmentReader: cannot open the segment ' , bytes hex asLowercase , ': ' , e messageText].
  ok := false.
  [header := self _headerIn: file of: bytes.
   header segment = bytes ifFalse: [
     ^ PBCorruptionError signal: 'PBSegmentReader: the segment file ' , bytes hex asLowercase
       , '.seg has the header of the segment ' , header segmentHex].
   ok := true] ensure: [ok ifFalse: [file close]].
  ^ self basicNew _setSegment: bytes file: file header: header.

"The seam that opens a segment file for reading (tests override it)."
PBSegmentReader class >> _openFile: aFileReference
  ^ BinaryFile open: aFileReference options: #(#read).

"The PBSegmentHeader at the start of aBinaryFile, the segment aByteArray. Its
 refusals name the segment; a failure of the file system is PBUnexpectedError."
PBSegmentReader class >> _headerIn: aBinaryFile of: aByteArray
  | hex bytes |
  hex := aByteArray hex asLowercase.
  bytes := [aBinaryFile readAt: 0 size: PBSegmentHeader byteSize] on: FileSystemError do: [:e |
    ^ PBUnexpectedError signal: 'PBSegmentReader: cannot read the header of the segment ' , hex , ': ' , e messageText].
  ^ [PBSegmentHeader decode: bytes] on: PBDBError do: [:e |
    e class signal: e messageText , ' in the segment ' , hex].

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
 { offset. PBRecordHeader. payload }. The walk of a complete segment, for the
 conformance runner and diagnostics, not a read path (see the module comment):
 a record that fails its checks, a torn tail or an append in progress included,
 is PBCorruptionError, since the walk never skips bytes. A tolerant walk for
 recovery tooling would be another selector."
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

PBSegmentReader >> isClosed
  ^ file isClosed.

PBSegmentReader >> printOn: aStream
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
  ^ self loadAt: aPointer expecting: aTag within: { aPointer }.

"As loadAt:expecting:, as part of decoding the records whose pointers aChain
 lists (aPointer last; PBAtom >> _envelopeWithin:): the references are
 resolved by a _PBLoadResolver that loads map keys within that chain."
PBFileStorage >> loadAt: aPointer expecting: aTag within: aChain
  | record |
  record := self recordAt: aPointer.
  (record at: 1) isAtom ifFalse: [
    ^ PBCorruptionError signal: 'PBFileStorage: the record at ' , aPointer printString , ' is a BLOB, not an ATOM'].
  ^ PBAtomEnvelope decode: (record at: 2) expecting: aTag resolver: (_PBLoadResolver storage: self chain: aChain).

"The resolver of PBCodec fromWire:resolver: (Task 7): the reference to the
 record at offset anOffset of the segment aSegmentBytes, of the type aTag, is an
 unloaded atom of that type's class (PBTypeRegistry unloadedAtomFor:at:storage:),
 which loads its record through this storage on first use."
PBFileStorage >> refTo: aSegmentBytes offset: anOffset tag: aTag
  ^ PBTypeRegistry unloadedAtomFor: aTag
    at: (PBAtomPointer segment: aSegmentBytes offset: anOffset)
    storage: self.

"=== _PBLoadResolver ========================================================="

"The resolver of one record's decoding: references become unloaded atoms of
 its storage (refTo:offset:tag:), and a map key that is a reference is loaded
 at once, within the chain of the records being decoded (loadKey:), since a
 key is identified by its oid. Made per load, never shared, never kept by the
 atoms it makes."
Object subclass: #_PBLoadResolver instanceVariableNames: 'storage chain'.

_PBLoadResolver class >> storage: aStorage chain: anArray
  ^ self basicNew _setStorage: aStorage chain: anArray.

_PBLoadResolver >> _setStorage: aStorage chain: anArray
  "Runs once, on a fresh instance."
  storage isNil ifFalse: [^ PBUserError signal: '_PBLoadResolver is initialised once'].
  storage := aStorage.
  chain := anArray.
  ^ self.

_PBLoadResolver >> refTo: aSegmentBytes offset: anOffset tag: aTag
  ^ storage refTo: aSegmentBytes offset: anOffset tag: aTag.

"Loads anAtom, a map key just decoded, within the chain (PBCorruptionError
 when its record is one being decoded)."
_PBLoadResolver >> loadKey: anAtom
  anAtom pointer isNil ifFalse: [anAtom _envelopeWithin: chain].

"The records of the segment aUUID (a UUID, its 16 bytes or its 32 hexadecimal
 digits), walked from offset 26: an Array of { offset. PBRecordHeader. payload }.
 A diagnostic of a complete segment, not how the space is read: a torn tail or
 an append in progress is PBCorruptionError (PBSegmentReader >> records)."
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

"The number of segment readers cached now (one per segment read since the open;
 0 once closed)."
PBFileStorage >> openSegmentCount
  ^ readers value size.

"The cached reader of the segment aByteArray, opened (and its header checked)
 on first use."
PBFileStorage >> _readerFor: aByteArray
  | hex mine |
  hex := aByteArray hex asLowercase.
  (readers value at: hex ifAbsent: [nil]) ifNotNil: [:cached | ^ cached].
  mine := self _openReader: aByteArray.
  [| current installed |
   current := readers value.
   installed := current at: hex ifAbsent: [nil].
   installed isNil ifFalse: [mine close. ^ self _unlessClosed: installed].
   readers value: (PBFrozenDict withAssociations: current associations , { hex -> mine }) ifCurrent: current]
    whileFalse.
  ^ self _unlessClosed: mine.

"The seam that opens the reader of the segment aByteArray on a cache miss (tests
 override it to force the interleavings of the module comment)."
PBFileStorage >> _openReader: aByteArray
  ^ PBSegmentReader segment: aByteArray file: (self _segmentFile: aByteArray).

"The file of the segment aByteArray: <uuid-hex>.seg in the space directory."
PBFileStorage >> _segmentFile: aByteArray
  ^ directory / (aByteArray hex asLowercase , self class segmentSuffix).

"aReader, an installed reader, unless the storage is closed: a close that ran
 while aReader was being installed may have missed it, so the cache is emptied
 again (which closes aReader) and PBClosedError signalled."
PBFileStorage >> _unlessClosed: aReader
  closed value ifTrue: [
    self close.
    ^ PBClosedError signal: 'PBFileStorage: the storage is closed'].
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

"Closes every segment reader and empties the cache; later loads, walks and root
 reads signal PBClosedError. Idempotent. The flag is set first, so a load that
 installs a reader after the cache is emptied sees it (_unlessClosed:)."
PBFileStorage >> close
  | empty taken |
  closed value: true ifCurrent: false.
  empty := PBFrozenDict withAssociations: #().
  [taken := readers value.
   readers value: empty ifCurrent: taken] whileFalse.
  taken do: [:reader | reader close].

PBFileStorage >> printOn: aStream
  aStream nextPutAll: 'PBFileStorage('; nextPutAll: directory pathString; nextPut: $).
