"EXPECT: ok 30"
"PBFileStorage replaceRoot: and the root lock (plan Task 17): two publishes give epochs 1
 and 2. A publish needs the root lock, writes the current epoch plus one (any other epoch is
 PBConflictError, and nothing is written), and refuses a pointer that is not a SpaceRoot
 record. The lock is space.lock's OS lock: a second storage on the same directory is
 excluded until the first releases it, the lock is not re-entrant, unlockRoot never
 signals, and close releases it. Two storages publish in turn on one directory, each from
 its own segment."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_seams'.

| c base st other spaceRootAt r1 r2 r3 p1 p2 p3 obj |
c := Check new.
base := FileSystem temp / ('pbst-store-publish-' , Smalltalk pid printString).
base deleteAll.

"An empty SpaceRoot (no databases), saved into aStorage: its pointer."
spaceRootAt := [:aStorage |
  aStorage save: (PBSpaceRoot _unsavedWithState: (PBFrozenDict withAssociations: { 'databases' -> PBDictionary new }))].

st := SeamStorage path: base pathString.
p1 := spaceRootAt value: st.
c that: 'a publish needs the root lock' signals: PBUserError containing: 'root lock' during: [
  st replaceRoot: (PBRootRecord segment: p1 segmentBytes offset: p1 offset epoch: 1)].
c that: 'and wrote nothing' is: st readRoot equals: nil.
c that: 'tryLockRoot' is: st tryLockRoot equals: true.
c that: 'holdsRootLock' is: st holdsRootLock equals: true.
c that: 'not re-entrant' signals: PBLockingError during: [st tryLockRoot].
c that: 'the first epoch is 1, not 2' signals: PBConflictError containing: 'epoch' during: [
  st replaceRoot: (PBRootRecord segment: p1 segmentBytes offset: p1 offset epoch: 2)].
c that: 'and nothing was written' is: { st readRoot. (base / 'space.root.tmp') exists } equals: { nil. false }.
r1 := st replaceRoot: (PBRootRecord segment: p1 segmentBytes offset: p1 offset epoch: 1).
c that: 'the first publish: epoch 1' is: st readRoot epoch equals: 1.
p2 := spaceRootAt value: st.
r2 := st replaceRoot: (PBRootRecord segment: p2 segmentBytes offset: p2 offset epoch: 2).
c that: 'the second publish: epoch 2' is: { st readRoot epoch. st readRoot pointer } equals: { 2. p2 }.
c that: 'an old epoch is a conflict' signals: PBConflictError during: [
  st replaceRoot: (PBRootRecord segment: p1 segmentBytes offset: p1 offset epoch: 2)].
c that: 'a skipped epoch is a conflict' signals: PBConflictError during: [
  st replaceRoot: (PBRootRecord segment: p1 segmentBytes offset: p1 offset epoch: 4)].
obj := PBObject withAll: { 'x' -> 1 }.
st save: obj.
c that: 'a pointer to another type is refused' signals: PBCorruptionError during: [
  st replaceRoot: (PBRootRecord segment: obj pointer segmentBytes offset: obj pointer offset epoch: 3)].
c that: 'a pointer to no record is refused' signals: PBCorruptionError during: [
  st replaceRoot: (PBRootRecord segment: p1 segmentBytes offset: p1 offset + 1 epoch: 3)].
c that: 'a pointer to a missing segment is refused' signals: PBCorruptionError containing: 'missing' during: [
  st replaceRoot: (PBRootRecord segment: (ByteArray new: 16) offset: 26 epoch: 3)].
c that: 'not a root record' signals: PBValidationError during: [st replaceRoot: p1].
c that: 'the root is still epoch 2' is: st readRoot epoch equals: 2.

"A second storage on the same directory."
other := PBFileStorage path: base pathString.
c that: 'is excluded while the first holds the lock' is: other tryLockRoot equals: false.
st unlockRoot.
c that: 'unlockRoot released it' is: st holdsRootLock equals: false.
c that: 'unlockRoot when not held does not signal' is: (st unlockRoot; holdsRootLock) equals: false.
c that: 'it logs why (captured, so the run stays silent)' isTrue: (st logged last includesSubstring: 'not held').
c that: 'the second storage takes it' is: other tryLockRoot equals: true.
c that: 'and the first is excluded' is: st tryLockRoot equals: false.
p3 := spaceRootAt value: other.
c that: 'from its own segment' isTrue: other currentSegment ~= st currentSegment.
r3 := other replaceRoot: (PBRootRecord segment: p3 segmentBytes offset: p3 offset epoch: 3).
c that: 'the first storage reads epoch 3' is: { st readRoot epoch. st readRoot pointer } equals: { 3. p3 }.
c that: 'the first storage cannot publish without the lock' signals: PBUserError during: [
  st replaceRoot: (PBRootRecord segment: p2 segmentBytes offset: p2 offset epoch: 3)].
other close.
c that: 'close released the lock' is: st tryLockRoot equals: true.
"st built a commit on epoch 2 (start epoch + 1 = 3); another storage published 3 meanwhile:
 the commit is stale and refused, never written over the newer root (no lost update)."
c that: 'a commit built on a stale root is refused' signals: PBConflictError during: [
  st replaceRoot: (PBRootRecord segment: p2 segmentBytes offset: p2 offset epoch: 3)].
c that: 'and the newer root stays' is: st readRoot pointer equals: p3.
st close.
c that: 'a closed storage: tryLockRoot' signals: PBClosedError during: [st tryLockRoot].
c that: 'a closed storage: replaceRoot:' signals: PBClosedError during: [
  st replaceRoot: (PBRootRecord segment: p2 segmentBytes offset: p2 offset epoch: 4)].
base deleteAll.
c report displayNl.
