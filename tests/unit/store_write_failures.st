"EXPECT: ok 38"
"The write side's failure policy (plan Task 17; ProtoBase FileStorage: an OSError while
 writing leaves the instance failed), driven through the storage's seams, never by killing a
 process: a failure of the file system at a chosen step (a record append, the segment sync,
 the directory sync after creating the segment, space.root.tmp, the rename, the directory
 sync after the rename) is PBUnexpectedError and leaves the storage failed, so every later
 write is refused while reads keep working. What is on disk after each failure is what a
 crash at that step leaves: records appended before it read back, and space.root is the old
 root until the rename and the new one after it; a fresh storage opens the space and
 publishes over it. Also: a write that starts while another is in progress on the same
 storage is PBUserError and writes nothing (one writer at a time), and a close during a write
 past its last check lets it complete, then closes the storage (store_close_race.st covers
 the checks)."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_seams'.

| c base dir st x y z p1 p2 publish spaceRoot fresh inner outer env |
c := Check new.
base := FileSystem temp / ('pbst-store-failures-' , Smalltalk pid printString).
base deleteAll.
spaceRoot := [:aStorage |
  aStorage save: (PBSpaceRoot _unsavedWithState: (PBFrozenDict withAssociations: { 'databases' -> PBDictionary new }))].
publish := [:aStorage :aPointer :anEpoch |
  aStorage replaceRoot: (PBRootRecord segment: aPointer segmentBytes offset: aPointer offset epoch: anEpoch)].

"--- a record append fails ---"
st := SeamStorage path: (base / 'append') pathString.
x := PBObject withAll: { 'x' -> 1 }.
st save: x.
st writer beforeAppend: [FileSystemError signal: 'injected failure in append:'].
y := PBObject withAll: { 'y' -> 2 }.
c that: 'an append failure' signals: PBUnexpectedError containing: 'injected failure in append:' during: [st save: y].
c that: 'fails the storage' is: st isFailed equals: true.
c that: 'the atom is not saved' is: y pointer equals: nil.
c that: 'a later save is refused' signals: PBUnexpectedError containing: 'earlier write' during: [
  st save: (PBObject withAll: { 'z' -> 3 })].
c that: 'and a flush' signals: PBUnexpectedError containing: 'earlier write' during: [st flushSegment].
c that: 'a record appended before reads back' is: ((PBTypeRegistry unloadedAtomFor: 19 at: x pointer storage: st) at: 'x') equals: 1.
st close.

"--- the segment sync fails ---"
st := SeamStorage path: (base / 'sync') pathString.
st save: (PBObject withAll: { 'x' -> 1 }).
st writer beforeSync: [FileSystemError signal: 'injected failure in sync'].
c that: 'a sync failure' signals: PBUnexpectedError containing: 'syncing the segment' during: [st flushSegment].
c that: 'fails the storage' is: st isFailed equals: true.
st close.

"--- the directory sync after creating the segment fails ---"
st := SeamStorage path: (base / 'dirsync') pathString.
st failOn: #_syncDirectory call: 1.
c that: 'a directory sync failure' signals: PBUnexpectedError containing: 'after creating the segment' during: [
  st save: (PBObject withAll: { 'x' -> 1 })].
c that: 'fails the storage' is: st isFailed equals: true.
st close.

"--- publishing: each step fails in turn, after a publish of epoch 1 ---"
#( #(#_writeRootTemp: 2 'tmp') #(#_replaceRootFile 2 'rename') #(#_syncDirectory 3 'dirsync-root') ) do: [:case |
  | sel renamed |
  sel := case at: 1.
  renamed := sel = #_syncDirectory.
  dir := base / ('root-' , (case at: 3)).
  st := SeamStorage path: dir pathString.
  "The failing publish is the second (the call of each root seam numbered 2); the
   directory is also synced once after the segment is created, so its sync is call 3."
  st failOn: sel call: (case at: 2).
  st tryLockRoot.
  p1 := spaceRoot value: st.
  publish value: st value: p1 value: 1.
  p2 := spaceRoot value: st.
  c that: (case at: 3) , ': the publish fails' signals: PBUnexpectedError containing: 'injected failure' during: [
    publish value: st value: p2 value: 2].
  c that: (case at: 3) , ': the storage is failed' is: st isFailed equals: true.
  c that: (case at: 3) , ': space.root is ' , (renamed ifTrue: ['the new root'] ifFalse: ['the old root'])
    is: { st readRoot epoch. st readRoot pointer } equals: (renamed ifTrue: [{ 2. p2 }] ifFalse: [{ 1. p1 }]).
  c that: (case at: 3) , ': a later publish is refused' signals: PBUnexpectedError containing: 'earlier write' during: [
    publish value: st value: p2 value: st readRoot epoch + 1].
  st close.
  "A fresh storage opens the space as a crash at that step leaves it, and publishes over it."
  fresh := PBFileStorage path: dir pathString.
  c that: (case at: 3) , ': a fresh storage opens it' is: fresh readRoot epoch equals: (renamed ifTrue: [2] ifFalse: [1]).
  fresh tryLockRoot.
  z := spaceRoot value: fresh.
  publish value: fresh value: z value: fresh readRoot epoch + 1.
  c that: (case at: 3) , ': and publishes over it' is: fresh readRoot pointer equals: z.
  fresh close].

"--- one writer at a time ---"
st := SeamStorage path: (base / 'one-writer') pathString.
st save: (PBObject withAll: { 'x' -> 1 }).
env := PBAtomEnvelope tag: 19 oid: (ByteArray fromHex: '07070707070707070707070707070707') state: (PBFrozenDict withAssociations: { 'n' -> 1 }).
st writer beforeAppend: [
  st writer beforeAppend: nil.
  inner := [st pushAtom: env. 'no error'] on: PBUserError do: [:e | e messageText]].
outer := st pushAtom: env.
c that: 'a write during another is refused' isTrue: (inner includesSubstring: 'one actor at a time').
c that: 'the outer write succeeds' is: (st loadAt: outer expecting: 19) oid equals: env oid.
c that: 'the refused write wrote nothing' is: (st recordsOfSegment: st currentSegment) size equals: 2.
c that: 'the storage is not failed' is: st isFailed equals: false.
st close.

"--- close during a write ---"
st := SeamStorage path: (base / 'close') pathString.
st save: (PBObject withAll: { 'x' -> 1 }).
st writer beforeAppend: [st close].
"The append is past the write's last check: it completes, and the close it owes is made
 when it ends."
outer := st pushAtom: env.
c that: 'a write past its last check completes despite a close' is: outer segmentBytes equals: st writer segment.
c that: 'is not a failure' is: st isFailed equals: false.
c that: 'the storage is closed when it ends' is: { st isClosed. st currentSegment. st writer isClosed } equals: { true. nil. true }.
fresh := PBFileStorage path: (base / 'close') pathString.
c that: 'the record is there' is: (fresh loadAt: outer expecting: 19) oid equals: env oid.
fresh close.
c that: 'a write after close' signals: PBClosedError during: [st pushAtom: env].
c that: 'a flush after close' signals: PBClosedError during: [st flushSegment].
base deleteAll.
c report displayNl.
