"_seams.st: storages and segment writers that fail at a chosen step (a helper of the store
 tests and of tests/interop/_st_write_space.st). The failures are deterministic: no process is
 killed and nothing depends on timing. A tearing seam writes a prefix of its bytes and then
 fails, which leaves on disk what a crash during that write leaves.

  SeamWriter        a PBSegmentWriter: beforeAppend:, beforeSync: run a block first (to fail
                    or to act meanwhile); tearNextAppendAt: n writes the first n bytes of the
                    next record and fails; syncs counts the syncs asked of it
  TornHeaderWriter  a PBSegmentWriter whose header write stops after 11 bytes and fails
  SeamStorage       a PBFileStorage: failOn: aSelector call: n (the n-th call of the seam
                    _syncDirectory, _writeRootTemp: or _replaceRootFile fails);
                    tearNextSegmentHeader; tearRootTempAt: n (space.root.tmp gets the first
                    n bytes of the root, then the write fails); writers (every SeamWriter
                    made, in order), writer (the last); logged (what _log: received)"

Import from: 'protobase'.

PBSegmentWriter subclass: #SeamWriter instanceVariableNames: 'beforeAppend beforeSync tearAt syncs'.
SeamWriter >> beforeAppend: aBlock
  beforeAppend := aBlock.
SeamWriter >> beforeSync: aBlock
  beforeSync := aBlock.
SeamWriter >> tearNextAppendAt: n
  tearAt := n.
SeamWriter >> syncs
  ^ syncs ifNil: [0].
SeamWriter >> append: aByteArray
  | n |
  beforeAppend isNil ifFalse: [beforeAppend value].
  tearAt isNil ifFalse: [
    n := tearAt.
    tearAt := nil.
    super append: (aByteArray copyFrom: 1 to: n).
    ^ FileSystemError signal: 'injected failure: a torn record'].
  ^ super append: aByteArray.
SeamWriter >> sync
  beforeSync isNil ifFalse: [beforeSync value].
  syncs := self syncs + 1.
  ^ super sync.

PBSegmentWriter subclass: #TornHeaderWriter.
TornHeaderWriter class >> _appendHeader: aByteArray to: aBinaryFile
  aBinaryFile append: (aByteArray copyFrom: 1 to: 11).
  ^ FileSystemError signal: 'injected failure: a torn segment header'.

PBFileStorage subclass: #SeamStorage instanceVariableNames: 'failing calls made tornHeader tornRootTemp logged'.
SeamStorage >> failOn: aSelector call: n
  failing := { aSelector. n }.
  calls := Dictionary new.
SeamStorage >> tearNextSegmentHeader
  tornHeader := true.
SeamStorage >> tearRootTempAt: n
  tornRootTemp := n.
SeamStorage >> writers
  ^ made ifNil: [made := OrderedCollection new].
SeamStorage >> writer
  ^ self writers last.
SeamStorage >> logged
  ^ logged ifNil: [logged := OrderedCollection new].
SeamStorage >> _log: aString
  self logged add: aString.
SeamStorage >> _seam: aSelector
  | n |
  failing isNil ifTrue: [^ self].
  n := (calls at: aSelector ifAbsent: [0]) + 1.
  calls at: aSelector put: n.
  ((failing at: 1) = aSelector and: [(failing at: 2) = n]) ifTrue: [
    ^ FileSystemError signal: 'injected failure in ' , aSelector].
SeamStorage >> _newSegmentWriter: aByteArray
  | w |
  tornHeader == true ifTrue: [
    tornHeader := false.
    ^ TornHeaderWriter create: aByteArray file: (self _segmentFile: aByteArray)].
  w := SeamWriter create: aByteArray file: (self _segmentFile: aByteArray).
  self writers add: w.
  ^ w.
SeamStorage >> _syncDirectory
  self _seam: #_syncDirectory.
  ^ super _syncDirectory.
SeamStorage >> _writeRootTemp: aByteArray
  | n |
  self _seam: #_writeRootTemp:.
  tornRootTemp isNil ifFalse: [
    n := tornRootTemp.
    tornRootTemp := nil.
    super _writeRootTemp: (aByteArray copyFrom: 1 to: n).
    ^ FileSystemError signal: 'injected failure: a torn space.root.tmp'].
  ^ super _writeRootTemp: aByteArray.
SeamStorage >> _replaceRootFile
  self _seam: #_replaceRootFile.
  ^ super _replaceRootFile.
