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
  aStorage flushSegment                 makes the owned segment durable (sync)
  aStorage currentSegment               the owned segment's 16 bytes, or nil
  aStorage tryLockRoot                  true when it took the root lock (flock
                                        on space.lock), false when another
                                        holder has it
  aStorage unlockRoot                   releases it, best effort: a failure is
                                        logged to stderr, never signalled
  aStorage replaceRoot: aPBRootRecord   publishes aPBRootRecord as space.root
  aStorage isCluster                    whether the space belongs to a cluster
  aStorage newSegmentId                 the UUID the owned segment is named by

The owned segment. A storage writes only into the one segment it created: the
first record pushed creates <uuid hex>.seg, named by a fresh UUID4
(newSegmentId), with #create #exclusive (a file of that name already there is
a loud failure, never an append to another writer's segment), writes the
format-4 header, syncs the file, and syncs the directory once, so the new
name is durable before any root can reference it. Every later record is
appended to it. Nothing appended is ever truncated or rewritten: a pointer
pushAtom: answers stays valid for the life of the storage (the atom keeps it
in its saved cell), and a record no published root reaches is an orphan,
harmless, as in ProtoBase. An orphan may repeat the oid of a reachable record
(the loser of a lost race on an atom's saved cell writes one), so any tool
that scans segments by oid (checker, compaction, replication) considers only
the records reachable from a root.

Publishing (replaceRoot:), in the order the format spec makes normative: the
caller holds the root lock (tryLockRoot; PBUserError otherwise); the owned
segment is synced first (data reaches the disk strictly before the root that
references it); the record at the new root's pointer must be a SpaceRoot
that passes its checks; the current space.root is read and checked (a version
the reader does not know is an error, never a reason to overwrite); the new
epoch must be the current one plus one (1 for a space without a root),
PBConflictError otherwise; a space that belongs to a cluster (a cluster/
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
space.root is read again (the publisher's step 8, plan Task 18).

One writer at a time. The write operations (pushAtom:, flushSegment,
replaceRoot:) are made by one actor, the space's publisher (plan Task 18),
one at a time; the storage takes no lock to serialise them. A write operation
that starts while another is in progress on the same storage is refused at
once with PBUserError and writes nothing (an Atom over a Boolean, set by
compare-and-swap: a refusal, never a wait). close does not wait for a write
in progress either: it marks the storage closed, which the write checks
before each step and before the rename that commits a publish; a write that
loses that race signals PBClosedError, and the steps it already made stay as
they are (records are orphans; a renamed root is published). The space closes
its storage through its publisher, between commits (plan Task 18).

The root lock is the format's inter-process protocol, the OS advisory lock
ProtoBase's root_lock takes on space.lock, so protoST and Python publishers
exclude each other. It belongs to the open file: tryLockRoot opens space.lock
per acquisition and unlockRoot closes it, as ProtoBase does; it is not
re-entrant (a second tryLockRoot while this storage holds it is
PBLockingError, ProtoBase's refusal).

The seams a test overrides to fail at a chosen step (crash-consistency tests
never kill a process): newSegmentId, _newSegmentWriter:, _syncDirectory,
_writeRootTemp:, _replaceRootFile, and PBSegmentWriter's append: and sync.

Durability is ProtoBase's default mode, fsync; segment rollover (a size cap,
implementation-specific) is not implemented: one storage writes one segment."

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

"The write side of the segment a storage owns: its UUID (16 bytes), its
 BinaryFile (opened for writing only: reads go through a PBSegmentReader, as
 for any segment) and dirty, an Atom over a Boolean, true while records were
 appended since the last sync. Made only by PBFileStorage, whose publisher is
 its one writer."
Object subclass: #PBSegmentWriter instanceVariableNames: 'segment file dirty'.

"Creates the segment file aFileReference for the segment aByteArray (16
 bytes): #create #exclusive, so an existing file of that name is
 FileAlreadyExists and is left untouched; writes the format-4 header and syncs
 the file. A failure of the file system passes to the caller (PBFileStorage
 turns it into PBUnexpectedError); the file is closed on any failure."
PBSegmentWriter class >> create: aByteArray file: aFileReference
  | file ok |
  file := self _openFile: aFileReference.
  ok := false.
  [file append: (PBSegmentHeader encodeSegment: aByteArray).
   file sync.
   ok := true] ensure: [ok ifFalse: [file close]].
  ^ self basicNew _setSegment: aByteArray file: file.

"The seam that creates a segment file (tests override it)."
PBSegmentWriter class >> _openFile: aFileReference
  ^ BinaryFile open: aFileReference options: #(#write #create #exclusive).

PBSegmentWriter >> _setSegment: aByteArray file: aBinaryFile
  "Runs once, on a fresh instance."
  segment isNil ifFalse: [^ PBUserError signal: 'PBSegmentWriter is initialised once'].
  segment := aByteArray.
  file := aBinaryFile.
  dirty := Atom on: false.
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
  ^ offset.

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

"A space directory. directory is its FileReference; the others are Atom cells:
 readers over a PBFrozenDict (segment hex -> PBSegmentReader), closed over a
 Boolean, writer over nil or the PBSegmentWriter of the owned segment, writing
 over a Boolean (a write operation in progress), failed over nil or the text
 of the write failure that ended writing, and rootLock over nil or the open
 BinaryFile of space.lock whose OS lock this storage holds."
Object subclass: #PBFileStorage instanceVariableNames: 'directory readers closed writer writing failed rootLock'.

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
  (dir / self clusterDirectoryName) exists ifTrue: [
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
  writer := Atom on: nil.
  writing := Atom on: false.
  failed := Atom on: nil.
  rootLock := Atom on: nil.
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

"=== PBFileStorage, write side =============================================="

"Saves anAtom into this storage, with every atom it refers to that is not
 saved yet, dependents first (PBAtom >> _saveInto:), and answers its
 PBAtomPointer. An atom saved here already answers its pointer and writes
 nothing; one stored in another storage is PBValidationError."
PBFileStorage >> save: anAtom
  (anAtom isClassObject not and: [anAtom isKindOf: PBAtom]) ifFalse: [
    ^ PBValidationError signal: 'PBFileStorage save: a PBAtom was expected, not ' , anAtom printString].
  ^ anAtom _saveInto: self.

"Appends the ATOM record of anEnvelope to the owned segment (created by the
 first push) and answers its PBAtomPointer, valid for the life of the storage.
 The record is not durable until flushSegment (or replaceRoot:) syncs it."
PBFileStorage >> pushAtom: anEnvelope
  | record |
  (anEnvelope isKindOf: PBAtomEnvelope) ifFalse: [
    ^ PBValidationError signal: 'PBFileStorage pushAtom: a PBAtomEnvelope was expected, not ' , anEnvelope printString].
  record := PBRecordHeader encodeKind: PBRecordHeader atomKind payload: anEnvelope encode.
  ^ self _writeOperation: [
    | w offset |
    w := self _ownedSegment.
    offset := self _write: [w append: record] what: 'appending a record to the segment ' , w segmentHex.
    PBAtomPointer segment: w segment offset: offset].

"Makes every record pushed so far durable: syncs the owned segment (nothing
 to do before the first push)."
PBFileStorage >> flushSegment
  self _writeOperation: [self _syncOwnedSegment].

"The UUID (16 bytes) of the segment this storage writes, or nil before its
 first push (ProtoBase current_segment)."
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
  closed value ifTrue: [
    self _releaseRootLock.
    ^ PBClosedError signal: 'PBFileStorage: the storage is closed'].
  ^ true.

"Releases the root lock, best effort: it never signals. A failure to unlock or
 to close space.lock, or a call while the lock is not held, is written to
 stderr (closing the file releases the OS lock in any case)."
PBFileStorage >> unlockRoot
  rootLock value isNil ifTrue: [
    ^ self _log: 'unlockRoot: the root lock is not held by this storage'].
  self _releaseRootLock.

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

"aString on stderr, prefixed with the storage; never signals."
PBFileStorage >> _log: aString
  [Stdio stderr nextPutAll: self printString , ': ' , aString; lf; flush] on: Error do: [:e | nil].

"Whether the space belongs to a cluster: its directory holds cluster/, or the
 SpaceRoot of its current root carries a cluster_term (not nil)."
PBFileStorage >> isCluster
  self _checkOpen.
  ^ (self _clusterReasonAt: self readRoot) notNil.

"Why the space is a cluster node's, with the root record aRootRecord current
 (nil: none), or nil when it is not."
PBFileStorage >> _clusterReasonAt: aRootRecord
  | term |
  (directory / self class clusterDirectoryName) exists ifTrue: [
    ^ 'its directory holds ' , self class clusterDirectoryName , '/'].
  aRootRecord isNil ifTrue: [^ nil].
  term := (self loadAt: aRootRecord pointer expecting: self class spaceRootTag) state
    at: 'cluster_term' ifAbsent: [nil].
  term isNil ifTrue: [^ nil].
  ^ 'its SpaceRoot at ' , aRootRecord pointer printString , ' carries the cluster_term ' , term printString.

"The tag of the SpaceRoot records a root record points to."
PBFileStorage class >> spaceRootTag
  ^ PBTypeRegistry aliasOf: 'proto_db.transactions.SpaceRoot'.

"Publishes aPBRootRecord as the space's root and answers it (see the module
 comment for the order of the steps). Needs the root lock (PBUserError).
 Refused, with nothing written: a pointer that is not a valid SpaceRoot record
 (PBCorruptionError), an epoch other than the current one plus one
 (PBConflictError), a cluster node's space (PBNotSupportedError)."
PBFileStorage >> replaceRoot: aPBRootRecord
  (aPBRootRecord isKindOf: PBRootRecord) ifFalse: [
    ^ PBValidationError signal: 'PBFileStorage replaceRoot: a PBRootRecord was expected, not ' , aPBRootRecord printString].
  ^ self _writeOperation: [
    | current expected reason |
    rootLock value isNil ifTrue: [
      ^ PBUserError signal: 'PBFileStorage replaceRoot: needs the root lock (tryLockRoot)'].
    self _syncOwnedSegment.
    self loadAt: aPBRootRecord pointer expecting: self class spaceRootTag.
    current := self readRoot.
    expected := current isNil ifTrue: [1] ifFalse: [current epoch + 1].
    aPBRootRecord epoch = expected ifFalse: [
      ^ PBConflictError signal: 'PBFileStorage replaceRoot: the root epoch is '
        , (current isNil ifTrue: ['none'] ifFalse: [current epoch printString])
        , ', so the publish writes epoch ' , expected printString , ', not ' , aPBRootRecord epoch printString].
    reason := self _clusterReasonAt: current.
    reason isNil ifFalse: [
      ^ PBNotSupportedError signal: 'PBFileStorage: ' , directory pathString , ' is the space of a cluster node ('
        , reason , '): it is written only through the cluster, and clusters are not supported by protoBaseST'].
    self _write: [self _writeRootTemp: aPBRootRecord encode]
      what: 'writing ' , self class rootTempFileName.
    self _checkOpen.
    self _write: [self _replaceRootFile]
      what: 'replacing ' , self class rootFileName.
    self _write: [self _syncDirectory]
      what: 'syncing the space directory after replacing ' , self class rootFileName.
    aPBRootRecord].

"The writer of the owned segment, created on first use: the file (named by
 newSegmentId), its header and sync, then one sync of the directory. Runs
 inside a write operation."
PBFileStorage >> _ownedSegment
  | w id hex |
  w := writer value.
  w isNil ifFalse: [^ w].
  id := _PBFrame uuidBytes: self newSegmentId.
  id isNil ifTrue: [^ PBUserError signal: 'PBFileStorage newSegmentId must answer a UUID'].
  hex := id hex asLowercase.
  w := self _write: [self _newSegmentWriter: id] what: 'creating the segment ' , hex.
  (writer value: w ifCurrent: nil) ifFalse: [
    w close.
    ^ PBUnexpectedError signal: 'PBFileStorage: the owned segment was created twice'].
  closed value ifTrue: [
    self close.
    ^ PBClosedError signal: 'PBFileStorage: the storage is closed'].
  self _write: [self _syncDirectory] what: 'syncing the space directory after creating the segment ' , hex.
  ^ w.

"The seam that creates the writer of the owned segment aByteArray."
PBFileStorage >> _newSegmentWriter: aByteArray
  ^ PBSegmentWriter create: aByteArray file: (self _segmentFile: aByteArray).

PBFileStorage >> _syncOwnedSegment
  | w |
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
  | reason |
  self _checkOpen.
  reason := failed value.
  reason isNil ifFalse: [
    ^ PBUnexpectedError signal: 'PBFileStorage: an earlier write to ' , directory pathString , ' failed (' , reason
      , '): this storage accepts no more writes; open a new storage'].

"aBlock's value, as the one write operation in progress on this storage: a
 write operation that starts while another is in progress is PBUserError
 (one writer at a time, see the module comment), and so is any write on a
 failed storage (PBUnexpectedError) or a closed one (PBClosedError)."
PBFileStorage >> _writeOperation: aBlock
  self _checkWritable.
  (writing value: true ifCurrent: false) ifFalse: [
    ^ PBUserError signal: 'PBFileStorage: a write is in progress on this storage: its writes are made by one actor at a time (the space''s publisher)'].
  ^ [self _checkWritable. aBlock value] ensure: [writing value: false ifCurrent: true].

"aBlock's value, one step of a write described by aString. A failure that is
 not a PBDBError leaves the storage failed (the first failure is kept) and is
 PBUnexpectedError; on a storage closed meanwhile it is PBClosedError."
PBFileStorage >> _write: aBlock what: aString
  ^ aBlock on: Error do: [:e |
    (e isKindOf: PBDBError) ifTrue: [e pass].
    closed value ifTrue: [^ PBClosedError signal: 'PBFileStorage: the storage was closed during ' , aString].
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

"Closes every segment reader and empties the cache, closes the owned segment
 and releases the root lock; later loads, walks, root reads and writes signal
 PBClosedError. Idempotent. The flag is set first, so a load that installs a
 reader after the cache is emptied sees it (_unlessClosed:), and so does a
 write that creates the owned segment (_ownedSegment). close does not wait
 for a write in progress (see the module comment)."
PBFileStorage >> close
  | empty taken w |
  closed value: true ifCurrent: false.
  empty := PBFrozenDict withAssociations: #().
  [taken := readers value.
   readers value: empty ifCurrent: taken] whileFalse.
  taken do: [:reader | reader close].
  [w := writer value.
   writer value: nil ifCurrent: w] whileFalse.
  w isNil ifFalse: [w close].
  self _releaseRootLock.

PBFileStorage >> printOn: aStream
  aStream nextPutAll: 'PBFileStorage('; nextPutAll: directory pathString; nextPut: $).
