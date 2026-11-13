"-- store.st: PBFileStorage, PBSegmentReader and PBSegmentWriter, the file storage --

The space directory of ProtoBase's FileStorage (proto_db/storage/file.py at
v2.0.0rc1; format spec v2.0.0rc1, 'Segments and records' and 'Root records'):

  space.root        the published root (PBRootRecord), replaced atomically
  space.root.tmp    the scratch file of a publish in progress; never read
  space.lock        the file whose OS lock (flock) excludes root publishers
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
  aStorage close                        later reads and writes signal
                                        PBClosedError; releases the root lock

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

Write side (format spec v2.0.0rc1, 'A minimal external writer (file
storage)'; ProtoBase FileStorage push_atom, flush and publish_root):

  aStorage save: anAtom                 saves anAtom and every unsaved atom it
                                        refers to, dependents first (PBAtom >>
                                        _saveInto:), and answers its pointer
  aStorage pushAtom: aPBAtomEnvelope    appends one ATOM record to the owned
                                        segment and answers its PBAtomPointer
  aStorage flushSegment                 makes the owned segments durable (sync)
  aStorage currentSegment               the 16 bytes of the segment receiving
                                        records, or nil
  aStorage tryLockRoot                  true when it took the root lock (flock
                                        on space.lock), false when another
                                        holder has it
  aStorage unlockRoot                   releases it, best effort: a failure is
                                        logged to stderr, never signalled
  aStorage replaceRoot: aPBRootRecord   publishes aPBRootRecord as space.root
  aStorage isCluster                    whether the space belongs to a cluster
  aStorage newSegmentId                 the UUID a new owned segment is named by
  PBFileStorage path: p segmentMaxBytes: n
                                        a storage whose segments roll over
                                        before n bytes (default 256 MiB)

The owned segments. A storage writes only into segments it created: the first
record pushed creates <uuid hex>.seg, named by a fresh UUID4 (newSegmentId),
with #create #exclusive (a file of that name already there is a loud failure,
never an append to another writer's segment), writes the format-4 header,
syncs the file, and syncs the directory once, so the new name is durable
before any root can reference it. Later records are appended to it until it
would exceed segmentMaxBytes (ProtoBase's segment_max_bytes, 256 MiB by
default): a segment holding a record is then sealed, never written again, and
a new segment is started the same way (a single larger record goes alone in
its segment), as ProtoBase's FileStorage rolls over. A sealed segment is kept
open until the next sync, which every publish makes first. Nothing appended is ever truncated or rewritten: a pointer
pushAtom: answers stays valid for the life of the storage (the atom keeps it
in its saved cell), and a record no published root reaches is an orphan,
harmless, as in ProtoBase. An orphan may repeat the oid of a reachable record
(the loser of a lost race on an atom's saved cell writes one), so any tool
that scans segments by oid (checker, compaction, replication) considers only
the records reachable from a root.

Publishing (replaceRoot:), in the order the format spec makes normative: the
caller holds the root lock (tryLockRoot; PBUserError otherwise); every
segment written since its last sync is synced first (data reaches the disk strictly before the root that
references it); the record at the new root's pointer must be a SpaceRoot
that passes its checks; the current space.root is read and checked (a version
the reader does not know is an error, never a reason to overwrite); the new
epoch, the epoch of the root the commit was validated against and built on
plus one (1 for a space that had none; replaceRoot: says which root that is),
must be the current one plus one, PBConflictError otherwise (a commit built on
a root that moved since is stale); a space that belongs to a cluster (a cluster/
directory, or a current SpaceRoot with a cluster_term) is PBNotSupportedError,
since such a space is written only through the cluster and clusters are
outside the prototype (design spec 10.5). Then space.root.tmp is written and
synced, renamed over space.root (FileSystem replace:with:), and the directory
is synced. The publish is durable once replaceRoot: returns.

Failure policy (ProtoBase's): a failure of the file system while creating,
appending to or syncing the segment, or while writing, renaming or syncing
the root, is PBUnexpectedError and leaves the storage failed: every later
pushAtom:, flushSegment and replaceRoot: is PBUnexpectedError, so no later
root can reference a record whose write was lost (reads keep working; open a
new storage to write again). After a failure in the rename or in the
directory sync that follows it, the outcome of that publish is unknown until
space.root is read again (the publisher's step 8, publisher.st).

One writer at a time. The write operations (pushAtom:, flushSegment,
replaceRoot:) are made by one actor, the space's publisher (publisher.st),
one at a time; the storage takes no lock to serialise them. A write operation
that starts while another is in progress on the same storage is refused at
once with PBUserError and writes nothing (the storage state, an Atom changed
by compare-and-swap: a refusal, never a wait). close never waits either, and
never releases the root lock under a write: during one it only requests the
close, which the write completes when it ends ('The storage state', at the
write side below). unlockRoot during a write is refused.

The root lock is the format's inter-process protocol, the OS advisory lock
ProtoBase's root_lock takes on space.lock, so protoST and Python publishers
exclude each other. It belongs to the open file: tryLockRoot opens space.lock
per acquisition and unlockRoot closes it, as ProtoBase does; it is not
re-entrant (a second tryLockRoot while this storage holds it is
PBLockingError, ProtoBase's refusal).

The seams a test overrides to fail at a chosen step (crash-consistency tests
never kill a process): newSegmentId, _newSegmentWriter:, _syncDirectory,
_writeRootTemp:, _replaceRootFile, _log:, and PBSegmentWriter's append:, sync
and class-side _appendHeader:to:.

Durability is ProtoBase's default mode, fsync."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/registry'.
Import from: 'protobase/codec'.
Import from: 'protobase/framing'.
Import from: 'uuid'.

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

"=== PBSegmentWriter ========================================================"

"The write side of a segment a storage owns: its UUID (16 bytes), its
 BinaryFile (opened for writing only: reads go through a PBSegmentReader, as
 for any segment), dirty, an Atom over a Boolean, true while records were
 appended since the last sync, and end, an Atom over the size of the segment
 (the offset the next record starts at). Made only by PBFileStorage, whose
 write operations run one at a time."
Object subclass: #PBSegmentWriter instanceVariableNames: 'segment file dirty end'.

"Creates the segment file aFileReference for the segment aByteArray (16
 bytes): #create #exclusive, so an existing file of that name is
 FileAlreadyExists and is left untouched; writes the format-4 header and syncs
 the file. A failure of the file system passes to the caller (PBFileStorage
 turns it into PBUnexpectedError); the file is closed on any failure."
PBSegmentWriter class >> create: aByteArray file: aFileReference
  | file ok |
  file := self _openFile: aFileReference.
  ok := false.
  [self _appendHeader: (PBSegmentHeader encodeSegment: aByteArray) to: file.
   file sync.
   ok := true] ensure: [ok ifFalse: [file close]].
  ^ self basicNew _setSegment: aByteArray file: file.

"The seam that writes the segment header (tests override it to tear it)."
PBSegmentWriter class >> _appendHeader: aByteArray to: aBinaryFile
  aBinaryFile append: aByteArray.

"The seam that creates a segment file (tests override it)."
PBSegmentWriter class >> _openFile: aFileReference
  ^ BinaryFile open: aFileReference options: #(#write #create #exclusive).

PBSegmentWriter >> _setSegment: aByteArray file: aBinaryFile
  "Runs once, on a fresh instance."
  segment isNil ifFalse: [^ PBUserError signal: 'PBSegmentWriter is initialised once'].
  segment := aByteArray.
  file := aBinaryFile.
  dirty := Atom on: false.
  end := Atom on: PBSegmentHeader byteSize.
  ^ self.

"The segment's UUID, 16 bytes."
PBSegmentWriter >> segment
  ^ segment.

PBSegmentWriter >> segmentHex
  ^ segment hex asLowercase.

"Appends aByteArray (one framed record) and answers the offset where it
 starts. A seam: tests override it to fail at a chosen record."
PBSegmentWriter >> append: aByteArray
  | offset |
  dirty value: true ifCurrent: false.
  offset := file append: aByteArray.
  end value: offset + aByteArray size ifCurrent: end value.
  ^ offset.

"The size of the segment: its header and the records appended."
PBSegmentWriter >> end
  ^ end value.

"Whether no record was appended yet (only the header is there)."
PBSegmentWriter >> holdsNoRecord
  ^ end value <= PBSegmentHeader byteSize.

"Makes every record appended so far durable (sync: data and metadata); does
 nothing when none was appended since the last sync. The flag is cleared
 before the sync, so a record appended meanwhile marks the segment dirty
 again. A seam: tests override it to fail."
PBSegmentWriter >> sync
  (dirty value: false ifCurrent: true) ifTrue: [file sync].

"Closes the file (idempotent)."
PBSegmentWriter >> close
  file close.

PBSegmentWriter >> isClosed
  ^ file isClosed.

PBSegmentWriter >> printOn: aStream
  aStream nextPutAll: 'PBSegmentWriter('; nextPutAll: self segmentHex; nextPut: $).

"=== PBFileStorage =========================================================="

"A space directory. directory is its FileReference and segmentMax the size cap
 of a segment; the others are Atom cells: readers over a PBFrozenDict (segment
 hex -> PBSegmentReader); state over the storage's state (see 'The storage
 state' in the module comment): #idle, #closed, or { #writing. token } and
 { #closeRequested. token }, where token identifies the write operation in
 progress; writer over nil or the PBSegmentWriter of the segment receiving
 records; sealed over an Array of the segments rolled away from that are not
 synced yet; failed over nil or the text of the write failure that ended
 writing; rootLock over nil or the open BinaryFile of space.lock whose OS lock
 this storage holds."
Object subclass: #PBFileStorage instanceVariableNames: 'directory segmentMax readers state writer sealed failed rootLock lastPush'.

PBFileStorage class >> rootFileName
  ^ 'space.root'.

PBFileStorage class >> segmentSuffix
  ^ '.seg'.

PBFileStorage class >> rootTempFileName
  ^ 'space.root.tmp'.

PBFileStorage class >> lockFileName
  ^ 'space.lock'.

"The subdirectory that marks the space of a cluster node."
PBFileStorage class >> clusterDirectoryName
  ^ 'cluster'.

"ProtoBase's segment_max_bytes default: 256 MiB."
PBFileStorage class >> defaultSegmentMaxBytes
  ^ 256 * 1024 * 1024.

"The storage of the space directory aPath (a String or a FileReference), created
 when missing, with ProtoBase's default segment cap. The published root is
 validated (its record is read and checked) before the storage is answered."
PBFileStorage class >> path: aPath
  ^ self path: aPath segmentMaxBytes: self defaultSegmentMaxBytes.

"As path:, with segments rolled over before they exceed anInteger bytes (a
 single larger record gets a segment of its own). anInteger must exceed the
 size of a segment header and a record header (ProtoBase's check)."
PBFileStorage class >> path: aPath segmentMaxBytes: anInteger
  | dir storage ok |
  ((_PBFrame isInt: anInteger) and: [anInteger > (PBSegmentHeader byteSize + PBRecordHeader byteSize)]) ifFalse: [
    ^ PBValidationError signal: 'PBFileStorage: segmentMaxBytes must be an Integer greater than '
      , (PBSegmentHeader byteSize + PBRecordHeader byteSize) printString , ', not ' , anInteger printString].
  ((aPath isString and: [aPath isSymbol not and: [aPath notEmpty]]) or: [aPath isKindOf: FileReference]) ifFalse: [
    ^ PBValidationError signal: 'PBFileStorage path: a path was expected, not ' , aPath printString].
  dir := aPath isString ifTrue: [aPath asFileReference] ifFalse: [aPath].
  (dir exists and: [dir isDirectory not]) ifTrue: [
    ^ PBValidationError signal: 'PBFileStorage: ' , dir pathString , ' exists and is not a directory'].
  (dir / self clusterDirectoryName) exists ifTrue: [
    ^ PBNotSupportedError signal: 'PBFileStorage: ' , dir pathString
      , ' holds cluster/, the space of a cluster node: clusters are not supported by protoBaseST'].
  [dir ensureCreateDirectory] on: FileSystemError do: [:e |
    ^ PBUnexpectedError signal: 'PBFileStorage: cannot create the space directory ' , dir pathString , ': ' , e messageText].
  storage := self basicNew _setDirectory: dir segmentMaxBytes: anInteger.
  ok := false.
  [storage _validateRoot. ok := true] ensure: [ok ifFalse: [storage close]].
  ^ storage.

PBFileStorage >> _setDirectory: aFileReference segmentMaxBytes: anInteger
  "Runs once, on a fresh instance."
  directory isNil ifFalse: [^ PBUserError signal: 'PBFileStorage is initialised once'].
  directory := aFileReference.
  segmentMax := anInteger.
  readers := Atom on: (PBFrozenDict withAssociations: #()).
  state := Atom on: #idle.
  writer := Atom on: nil.
  sealed := Atom on: #().
  failed := Atom on: nil.
  rootLock := Atom on: nil.
  lastPush := Atom on: nil.
  ^ self.

"The size cap of a segment (segmentMaxBytes)."
PBFileStorage >> segmentMaxBytes
  ^ segmentMax.

"The kind of the storage state: #idle, #writing, #closeRequested or #closed."
PBFileStorage >> _stateKind
  | s |
  s := state value.
  ^ s isArray ifTrue: [s first] ifFalse: [s].

"The space directory, a FileReference."
PBFileStorage >> directory
  ^ directory.

"Whether the storage is closed, or closing: a close requested during a write
 is completed by that write when it ends, and no new operation starts
 meanwhile."
PBFileStorage >> isClosed
  | kind |
  kind := self _stateKind.
  ^ kind == #closed or: [kind == #closeRequested].

PBFileStorage >> _checkOpen
  self isClosed ifTrue: [^ PBClosedError signal: 'PBFileStorage: the storage is closed'].

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
  ^ PBAtomEnvelope decode: (record at: 2) at: aPointer expecting: aTag
    resolver: (_PBLoadResolver storage: self chain: aChain).

"The resolver of PBCodec fromWire:resolver: (Task 7): the reference to the
 record at offset anOffset of the segment aSegmentBytes, of the type aTag, is an
 unloaded atom of that type's class (PBTypeRegistry unloadedAtomFor:at:storage:),
 which loads its record through this storage on first use."
PBFileStorage >> refTo: aSegmentBytes offset: anOffset tag: aTag
  ^ PBTypeRegistry unloadedAtomFor: aTag
    at: (PBAtomPointer segment: aSegmentBytes offset: anOffset)
    storage: self.

"=== PBFileStorage, write side ==============================================

 The storage state (an Atom, changed only by compare-and-swap; no lock, no
 wait). A write operation (pushAtom:, flushSegment, replaceRoot:, and the
 release of unlockRoot) moves it from #idle to { #writing. token }, its own
 token, and back when it ends; one that finds another state is refused at once
 (PBUserError while a write is in progress, PBClosedError once closed). close
 moves #idle to #closed and releases everything itself (readers, segments, the
 root lock); during a write it only moves the state to { #closeRequested.
 token } and returns: the release is owed by the write, which performs it when
 it ends (the last one out closes). So the root lock is never released under a
 write, and no other writer can take it and write space.root.tmp while this
 storage still renames it. A write stops with PBClosedError at the checks
 before its append and before its rename (a publish then renames nothing);
 past the rename a publish completes and is reported. The token identifies the
 write operation, not an actor: protoST has no actor identity, so the root
 lock, like the writes, belongs to the storage; one actor (the space's
 publisher) makes its writes."

"Saves anAtom into this storage, with every atom it refers to that is not
 saved yet, dependents first (PBAtom >> _saveInto:), and answers its
 PBAtomPointer. An atom saved here already answers its pointer and writes
 nothing; one stored in another storage is PBValidationError."
PBFileStorage >> save: anAtom
  (anAtom isClassObject not and: [anAtom isKindOf: PBAtom]) ifFalse: [
    ^ PBValidationError signal: 'PBFileStorage save: a PBAtom was expected, not ' , anAtom printString].
  ^ anAtom _saveInto: self.

"Appends the ATOM record of anEnvelope to the segment receiving records
 (created by the first push, and again on each rollover) and answers its
 PBAtomPointer, valid for the life of the storage. The record is not durable
 until flushSegment (or replaceRoot:) syncs it."
PBFileStorage >> pushAtom: anEnvelope
  | record payload |
  (anEnvelope isKindOf: PBAtomEnvelope) ifFalse: [
    ^ PBValidationError signal: 'PBFileStorage pushAtom: a PBAtomEnvelope was expected, not ' , anEnvelope printString].
  payload := anEnvelope encode.
  record := PBRecordHeader encodeKind: PBRecordHeader atomKind payload: payload.
  ^ self _writeOperation: [
    | w offset ptr |
    self _stopIfCloseRequested: 'before choosing the segment'.
    w := self _segmentFor: record size.
    self _stopIfCloseRequested: 'before appending a record'.
    offset := self _write: [w append: record] what: 'appending a record to the segment ' , w segmentHex.
    ptr := PBAtomPointer segment: w segment offset: offset.
    lastPush value: { ptr. anEnvelope tag. payload } ifCurrent: lastPush value.
    ptr].

"Makes every record pushed so far durable: syncs every segment written since
 its last sync (nothing to do before the first push)."
PBFileStorage >> flushSegment
  self _writeOperation: [self _syncSegments].

"The UUID (16 bytes) of the segment receiving records, or nil before the first
 push (ProtoBase current_segment)."
PBFileStorage >> currentSegment
  | w |
  w := writer value.
  ^ w isNil ifTrue: [nil] ifFalse: [w segment].

"The UUID a new owned segment is named by: a fresh version-4 UUID. A seam,
 overridden only by tests that inject a name."
PBFileStorage >> newSegmentId
  ^ UUID new.

"Takes the root lock without waiting: true when this storage now holds it,
 false when another holder (a process, or another storage of this process)
 has it. The lock is the OS lock on space.lock, opened #(#read #write
 #create) for this acquisition and closed when it is released. Not
 re-entrant: PBLockingError when this storage holds it already."
PBFileStorage >> tryLockRoot
  | lockFile file took |
  self _checkOpen.
  rootLock value isNil ifFalse: [
    ^ PBLockingError signal: 'PBFileStorage tryLockRoot: this storage holds the root lock already (it is not re-entrant)'].
  lockFile := directory / self class lockFileName.
  file := [BinaryFile open: lockFile options: #(#read #write #create)] on: FileSystemError do: [:e |
    ^ PBUnexpectedError signal: 'PBFileStorage: cannot open ' , lockFile pathString , ': ' , e messageText].
  took := [file tryLock] on: Error do: [:e |
    file close.
    ^ PBUnexpectedError signal: 'PBFileStorage: cannot lock ' , lockFile pathString , ': ' , e messageText].
  took ifFalse: [file close. ^ false].
  (rootLock value: file ifCurrent: nil) ifFalse: [
    "Another actor of this storage installed a lock file meanwhile: the OS lock
     excludes a second holder, so that one is not held; release ours."
    file close.
    ^ PBLockingError signal: 'PBFileStorage tryLockRoot: another tryLockRoot of this storage ran at the same time'].
  self isClosed ifTrue: [
    "A close that released before this install missed the lock: release it
     here once the close is complete (a requested close releases it when its
     write ends)."
    self _stateKind == #closed ifTrue: [self _releaseRootLock].
    ^ PBClosedError signal: 'PBFileStorage: the storage is closed'].
  ^ true.

"Releases the root lock, best effort: it never signals, and answers whether
 it released it. It is refused (logged, the lock kept) while a write is in
 progress on this storage: the lock covers the whole publish. On a closed
 storage it answers false silently: the close released the lock (the pattern
 [replaceRoot: r] ensure: [unlockRoot] meets this when a close was completed by
 the publish). A failure to unlock or to close space.lock, or a call on an open
 storage while the lock is not held, is written to stderr (closing the file
 releases the OS lock in any case)."
PBFileStorage >> unlockRoot
  | s mine |
  mine := { #writing. Object new }.
  "The answer follows from one reading of the state (Task 17 review, round 3):
   idle is swapped for this call's write mark, retried when the swap is lost to
   another state change, as close does; a write in progress refuses (logged);
   closed or a close requested answers false silently. Before, a write that
   ended between two readings made the call answer false without unlocking or
   logging."
  [s := state value.
   s == #idle and: [(state value: mine ifCurrent: s) not]] whileTrue.
  s == #idle ifFalse: [
    (s isArray and: [s first == #writing]) ifTrue: [
      self _log: 'unlockRoot refused: a write is in progress on this storage; the root lock is kept'.
      ^ false].
    "Closed, or a close requested: the close releases the lock."
    ^ false].
  ^ [rootLock value isNil
      ifTrue: [self _log: 'unlockRoot: the root lock is not held by this storage'. false]
      ifFalse: [self _releaseRootLock. true]]
    ensure: [self _endWrite: mine].

PBFileStorage >> _releaseRootLock
  | file |
  [file := rootLock value.
   file isNil ifTrue: [^ self].
   rootLock value: nil ifCurrent: file] whileFalse.
  [file unlock] on: Error do: [:e | self _log: 'unlocking ' , self class lockFileName , ' failed: ' , e messageText].
  [file close] on: Error do: [:e | self _log: 'closing ' , self class lockFileName , ' failed: ' , e messageText].

"Whether this storage holds the root lock now."
PBFileStorage >> holdsRootLock
  ^ rootLock value notNil.

"aString on stderr, prefixed with the storage; never signals. A seam: tests
 capture it."
PBFileStorage >> _log: aString
  [Stdio stderr nextPutAll: self printString , ': ' , aString; lf; flush] on: Error do: [:e | nil].

"Whether the space belongs to a cluster: its directory holds cluster/, or the
 SpaceRoot of its current root carries a cluster_term (not nil)."
PBFileStorage >> isCluster
  self _checkOpen.
  ^ (self _clusterReasonAt: self readRoot) notNil.

"Why the space is a cluster node's, with the root record aRootRecord current
 (nil: none), or nil when it is not. The SpaceRoot is read as an atom of this
 storage (PBTypeRegistry unloadedAtomFor:at:storage:), the one the publisher
 decoded to build the commit when the atom cache holds it."
PBFileStorage >> _clusterReasonAt: aRootRecord
  | term |
  (directory / self class clusterDirectoryName) exists ifTrue: [
    ^ 'its directory holds ' , self class clusterDirectoryName , '/'].
  aRootRecord isNil ifTrue: [^ nil].
  term := (PBTypeRegistry unloadedAtomFor: self class spaceRootTag at: aRootRecord pointer storage: self)
    stateAt: 'cluster_term'.
  term isNil ifTrue: [^ nil].
  ^ 'its SpaceRoot at ' , aRootRecord pointer printString , ' carries the cluster_term ' , term printString.

"Refuses (PBCorruptionError) a pointer that is not a valid SpaceRoot record
 (replaceRoot:). The record this storage pushed last is checked by reading it
 back, its framing and CRC verified (PBSegmentReader >> recordAt:, ProtoBase
 publish_root's _fetch_record), and comparing its payload with the bytes
 encoded from the SpaceRoot envelope: what the publisher just saved, checked
 against the disk at least as strictly as ProtoBase does, without decoding it
 again. Any other pointer is decoded in full as a SpaceRoot (loadAt:expecting:)."
PBFileStorage >> _checkRootRecordAt: aPointer
  | last record |
  last := lastPush value.
  ((last notNil and: [(last at: 1) = aPointer])
    and: [(PBTypeRegistry nameOfTag: (last at: 2)) = (PBTypeRegistry nameOfTag: self class spaceRootTag)])
    ifFalse: [^ self loadAt: aPointer expecting: self class spaceRootTag].
  record := self recordAt: aPointer.
  ((record at: 1) isAtom and: [(record at: 2) = (last at: 3)]) ifFalse: [
    ^ PBCorruptionError signal: 'PBFileStorage: the record at ' , aPointer printString
      , ' does not hold the bytes of the SpaceRoot written there'].
  ^ self.

"The tag of the SpaceRoot records a root record points to."
PBFileStorage class >> spaceRootTag
  ^ PBTypeRegistry aliasOf: 'proto_db.transactions.SpaceRoot'.

"Publishes aPBRootRecord as the space's root and answers it (see the module
 comment for the order of the steps). Its epoch is the epoch of the root the
 commit was validated against and built on, plus one (1 for a space that had
 none). The publisher (publisher.st) reads that root under the root lock and
 validates every read against it, as ProtoBase's _standalone_round, so a root
 that moved since the transaction started is validated, never overwritten. A
 writer that publishes without such a validation must take the epoch of the
 root it built on, read before its changes, and never a root read again under
 the lock, which would pass this check and overwrite a newer commit. Under the
 lock this check only catches a writer that ignores the lock (format spec,
 minimal writer, step 5). Needs the root lock (PBUserError). Refused, with
 nothing written: a pointer that is not a valid SpaceRoot record
 (PBCorruptionError), an epoch other than the current one plus one
 (PBConflictError), a cluster node's space (PBNotSupportedError)."
PBFileStorage >> replaceRoot: aPBRootRecord
  (aPBRootRecord isKindOf: PBRootRecord) ifFalse: [
    ^ PBValidationError signal: 'PBFileStorage replaceRoot: a PBRootRecord was expected, not ' , aPBRootRecord printString].
  ^ self _writeOperation: [
    | current expected reason |
    rootLock value isNil ifTrue: [
      ^ PBUserError signal: 'PBFileStorage replaceRoot: needs the root lock (tryLockRoot)'].
    self _syncSegments.
    self _checkRootRecordAt: aPBRootRecord pointer.
    current := self readRoot.
    expected := current isNil ifTrue: [1] ifFalse: [current epoch + 1].
    aPBRootRecord epoch = expected ifFalse: [
      ^ PBConflictError signal: 'PBFileStorage replaceRoot: the root epoch is '
        , (current isNil ifTrue: ['none'] ifFalse: [current epoch printString])
        , ', so a commit built on it publishes epoch ' , expected printString , ', not '
        , aPBRootRecord epoch printString , ': the commit was built on another root'].
    reason := self _clusterReasonAt: current.
    reason isNil ifFalse: [
      ^ PBNotSupportedError signal: 'PBFileStorage: ' , directory pathString , ' is the space of a cluster node ('
        , reason , '): it is written only through the cluster, and clusters are not supported by protoBaseST'].
    self _write: [self _writeRootTemp: aPBRootRecord encode]
      what: 'writing ' , self class rootTempFileName.
    self _stopIfCloseRequested: 'before replacing ' , self class rootFileName , ': nothing was published'.
    self _write: [self _replaceRootFile]
      what: 'replacing ' , self class rootFileName.
    self _write: [self _syncDirectory]
      what: 'syncing the space directory after replacing ' , self class rootFileName.
    aPBRootRecord].

"The writer of the segment that receives a record of aSize bytes. The first
 one is created on first use; a segment that holds a record and would exceed
 the cap with this one is sealed (kept until its next sync) and a new segment
 started, as ProtoBase's _reserve. Runs inside a write operation."
PBFileStorage >> _segmentFor: aSize
  | w |
  w := writer value.
  (w notNil and: [w holdsNoRecord not and: [w end + aSize > segmentMax]]) ifTrue: [
    self _seal: w.
    w := nil].
  w isNil ifTrue: [w := self _startSegment].
  ^ w.

"Moves aWriter, the segment receiving records, to the sealed segments: it is
 never written again, and is synced and closed by the next sync."
PBFileStorage >> _seal: aWriter
  | list |
  writer value: nil ifCurrent: aWriter.
  [list := sealed value.
   sealed value: (list copyWith: aWriter) ifCurrent: list] whileFalse.

"Creates a new owned segment (named by newSegmentId): the file, its header and
 sync, then one sync of the directory, so the new name is durable before any
 root can reference it. Runs inside a write operation."
PBFileStorage >> _startSegment
  | w id hex |
  id := _PBFrame uuidBytes: self newSegmentId.
  id isNil ifTrue: [^ PBUserError signal: 'PBFileStorage newSegmentId must answer a UUID'].
  hex := id hex asLowercase.
  self _stopIfCloseRequested: 'before creating the segment ' , hex.
  w := self _write: [self _newSegmentWriter: id] what: 'creating the segment ' , hex.
  writer value: w ifCurrent: nil.
  self _write: [self _syncDirectory] what: 'syncing the space directory after creating the segment ' , hex.
  ^ w.

"The seam that creates the writer of the owned segment aByteArray."
PBFileStorage >> _newSegmentWriter: aByteArray
  ^ PBSegmentWriter create: aByteArray file: (self _segmentFile: aByteArray).

"Syncs every segment written since its last sync (ProtoBase: seg.synced <
 seg.written): the sealed ones first, each closed once synced, then the one
 receiving records."
PBFileStorage >> _syncSegments
  | list w |
  [(list := sealed value) isEmpty] whileFalse: [
    | first |
    first := list first.
    self _write: [first sync] what: 'syncing the segment ' , first segmentHex.
    sealed value: (list copyFrom: 2 to: list size) ifCurrent: list.
    first close].
  w := writer value.
  w isNil ifTrue: [^ self].
  self _write: [w sync] what: 'syncing the segment ' , w segmentHex.

"The seam that makes the space directory's entries durable."
PBFileStorage >> _syncDirectory
  FileSystem syncDirectory: directory.

"The seam that writes aByteArray to space.root.tmp (created or emptied) and
 syncs it."
PBFileStorage >> _writeRootTemp: aByteArray
  | file |
  file := BinaryFile open: directory / self class rootTempFileName options: #(#write #create #truncate).
  [file writeAt: 0 bytes: aByteArray.
   file sync] ensure: [file close].

"The seam that renames space.root.tmp over space.root, atomically."
PBFileStorage >> _replaceRootFile
  FileSystem replace: directory / self class rootTempFileName with: directory / self class rootFileName.

PBFileStorage >> _checkWritable
  self _checkOpen.
  self _checkNotFailed.

PBFileStorage >> _checkNotFailed
  | reason |
  reason := failed value.
  reason isNil ifFalse: [
    ^ PBUnexpectedError signal: 'PBFileStorage: an earlier write to ' , directory pathString , ' failed (' , reason
      , '): this storage accepts no more writes; open a new storage'].

"aBlock's value, as the one write operation in progress on this storage (see
 'The storage state' above): one that finds a write in progress is PBUserError
 (one writer at a time), and so is a write on a closed storage (PBClosedError)
 or a failed one (PBUnexpectedError). When it ends it moves the state back to
 #idle, or, when a close was requested meanwhile, completes that close."
PBFileStorage >> _writeOperation: aBlock
  | s mine |
  self _checkWritable.
  mine := { #writing. Object new }.
  s := state value.
  (s == #idle and: [state value: mine ifCurrent: s]) ifFalse: [
    self _checkOpen.
    ^ PBUserError signal: 'PBFileStorage: a write is in progress on this storage: its writes are made by one actor at a time (the space''s publisher)'].
  ^ [self _checkNotFailed. aBlock value] ensure: [self _endWrite: mine].

"Ends the write operation whose state is aState: back to #idle, or, when a
 close was requested during it, #closed and the release the close owes."
PBFileStorage >> _endWrite: aState
  | s |
  (state value: #idle ifCurrent: aState) ifTrue: [^ self].
  s := state value.
  ((s isArray and: [s first == #closeRequested]) and: [(s at: 2) == (aState at: 2)]) ifFalse: [
    ^ PBUnexpectedError signal: 'PBFileStorage: the state of a write changed under it: ' , s printString].
  state value: #closed ifCurrent: s.
  self _release.

"PBClosedError when a close was requested during the write in progress (a check
 made before a step that may not start once the storage is closing)."
PBFileStorage >> _stopIfCloseRequested: aString
  self _stateKind == #closeRequested ifTrue: [
    ^ PBClosedError signal: 'PBFileStorage: the storage was closed during a write, ' , aString].

"aBlock's value, one step of a write described by aString. A failure that is
 not a PBDBError leaves the storage failed (the first failure is kept) and is
 PBUnexpectedError. A PBDBError passes without failing the storage: the steps
 signal one only before they write anything (an argument or state check), so
 none can follow a partial write; a step that could must not signal a
 PBDBError after writing, or it would let a later root reference a lost
 write. (Wider than ProtoBase, which fails on OSError only: any error of a
 step may follow a partial write.)"
PBFileStorage >> _write: aBlock what: aString
  ^ aBlock on: Error do: [:e |
    (e isKindOf: PBDBError) ifTrue: [e pass].
    failed value: aString , ': ' , e messageText ifCurrent: nil.
    ^ PBUnexpectedError signal: 'PBFileStorage: ' , aString , ' failed: ' , e messageText
      , '; this storage accepts no more writes'].

"Whether a write failed, which ended writing through this storage."
PBFileStorage >> isFailed
  ^ failed value notNil.

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
  self isClosed ifTrue: [
    "A requested close releases the readers when its write ends."
    self _stateKind == #closed ifTrue: [self _release].
    ^ PBClosedError signal: 'PBFileStorage: the storage is closed'].
  ^ aReader.

"aBlock's value. An Error from a reader the storage closed meanwhile is
 PBClosedError; a failure of the file system is PBUnexpectedError (ProtoBase:
 an OSError while reading is ProtoUnexpectedError)."
PBFileStorage >> _whileOpen: aBlock
  ^ aBlock on: Error do: [:e |
    (e isKindOf: PBDBError) ifTrue: [e pass].
    self isClosed ifTrue: [^ PBClosedError signal: 'PBFileStorage: the storage was closed during a read'].
    (e isKindOf: FileSystemError) ifTrue: [^ PBUnexpectedError signal: 'PBFileStorage: a read failed: ' , e messageText].
    e pass].

"Closes the storage: later loads, walks, root reads and writes signal
 PBClosedError. Idempotent, and it never waits. On an idle storage it closes
 every segment reader and segment and releases the root lock at once; during a
 write it requests the close, which that write completes when it ends (see
 'The storage state'), so the root lock is never released under a publish."
PBFileStorage >> close
  | s |
  [s := state value.
   s == #closed ifTrue: [^ self].
   s == #idle
     ifTrue: [(state value: #closed ifCurrent: s) ifTrue: [^ self _release]]
     ifFalse: [
       s first == #closeRequested ifTrue: [^ self].
       (state value: { #closeRequested. s at: 2 } ifCurrent: s) ifTrue: [^ self]].
   true] whileTrue.

"The release a close owes, once the state is #closed: every reader closed and
 the cache emptied, every segment closed, the root lock released. Idempotent:
 each part is taken from its cell by compare-and-swap, so a reader or a lock
 installed after a release is released by a later one (_unlessClosed:,
 tryLockRoot)."
PBFileStorage >> _release
  | empty taken w list |
  empty := PBFrozenDict withAssociations: #().
  [taken := readers value.
   readers value: empty ifCurrent: taken] whileFalse.
  taken do: [:reader | reader close].
  [w := writer value.
   writer value: nil ifCurrent: w] whileFalse.
  w isNil ifFalse: [w close].
  [list := sealed value.
   sealed value: #() ifCurrent: list] whileFalse.
  list do: [:each | each close].
  self _releaseRootLock.

PBFileStorage >> printOn: aStream
  aStream nextPutAll: 'PBFileStorage('; nextPutAll: directory pathString; nextPut: $).
