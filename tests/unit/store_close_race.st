"EXPECT: ok 32"
"close (or unlockRoot) from another actor while a publish is in progress (plan Task 17 review,
 C1). close never releases the root lock under a write: it is owed to the write in progress,
 which completes it when it ends, so no other writer can take the lock and write
 space.root.tmp while this storage still renames it. The other actor is run deterministically
 inside a seam of the publish, never by timing:
 - inside the rename seam (the publish past its last check): the other storage's tryLockRoot
   answers false; the publish completes and answers its record; the storage is closed after it,
   its lock released, and the space reopens at the new root;
 - inside space.root.tmp's seam (before the rename): the publish stops with PBClosedError,
   nothing is renamed, the space reopens at the old root, and the other storage publishes;
 - unlockRoot inside the rename seam is refused (logged, the lock kept) and the publish
   completes.
 - close inside newSegmentId (a first push choosing its segment): the push stops with
   PBClosedError before any segment file is created (review round 2, m1);
 - [replaceRoot:] ensure: [unlockRoot] with a close completed by the publish: unlockRoot
   answers false and logs nothing (the close released the lock; m2);
 - a close requested during a write that then fails at the file-system level: the storage
   ends failed and closed, its lock released (m3);
 - a close requested during flushSegment with sealed segments pending: every segment writer
   is closed when the flush ends (m3).
 The first case is the reviewer's reproduction (task-17-review-closerace.st), where the other
 writer then wrote a half space.root.tmp that the publish renamed over space.root."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_seams'.

PBFileStorage subclass: #CloseRace instanceVariableNames: 'duringRename duringTemp duringSegmentId logged'.
CloseRace >> duringRename: aBlock
  duringRename := aBlock.
CloseRace >> duringTemp: aBlock
  duringTemp := aBlock.
CloseRace >> logged
  ^ logged.
CloseRace >> _log: aString
  logged := aString.
CloseRace >> _replaceRootFile
  duringRename isNil ifFalse: [ | b | b := duringRename. duringRename := nil. b value].
  ^ super _replaceRootFile.
CloseRace >> duringSegmentId: aBlock
  duringSegmentId := aBlock.
CloseRace >> newSegmentId
  duringSegmentId isNil ifFalse: [ | b | b := duringSegmentId. duringSegmentId := nil. b value].
  ^ super newSegmentId.
CloseRace >> _writeRootTemp: aByteArray
  super _writeRootTemp: aByteArray.
  duringTemp isNil ifFalse: [ | b | b := duringTemp. duringTemp := nil. b value].

| c base st other sr p1 p2 r took fresh ss |
c := Check new.
base := FileSystem temp / ('pbst-close-race-' , Smalltalk pid printString).
base deleteAll.
sr := [:s | s save: (PBSpaceRoot _unsavedWithState: (PBFrozenDict withAssociations: { 'databases' -> PBDictionary new }))].

"--- close during the rename ---"
st := CloseRace path: (base / 'rename') pathString.
st tryLockRoot.
p1 := sr value: st.
st replaceRoot: (PBRootRecord segment: p1 segmentBytes offset: p1 offset epoch: 1).
p2 := sr value: st.
other := PBFileStorage path: (base / 'rename') pathString.
st duringRename: [
  st close.
  took := other tryLockRoot.
  took ifTrue: [
    "What the reviewer's other writer did once it held the lock: a half space.root.tmp."
    (BinaryFile open: base / 'rename' / 'space.root.tmp' options: #(#write #create #truncate))
      writeAt: 0 bytes: #[1 2 3 4 5 6 7]; close]].
r := st replaceRoot: (PBRootRecord segment: p2 segmentBytes offset: p2 offset epoch: 2).
c that: 'rename: the other storage could not take the lock' is: took equals: false.
c that: 'rename: the publish completes' is: r epoch equals: 2.
c that: 'rename: the storage is closed after it' is: st isClosed equals: true.
c that: 'rename: its lock is released' is: other tryLockRoot equals: true.
other close.
fresh := PBFileStorage path: (base / 'rename') pathString.
c that: 'rename: the space reopens at the new root' is: { fresh readRoot epoch. fresh readRoot pointer } equals: { 2. p2 }.
fresh close.

"--- close while space.root.tmp is written ---"
st := CloseRace path: (base / 'temp') pathString.
st tryLockRoot.
p1 := sr value: st.
st replaceRoot: (PBRootRecord segment: p1 segmentBytes offset: p1 offset epoch: 1).
p2 := sr value: st.
other := PBFileStorage path: (base / 'temp') pathString.
st duringTemp: [
  st close.
  took := other tryLockRoot].
c that: 'temp: the publish stops' signals: PBClosedError during: [
  st replaceRoot: (PBRootRecord segment: p2 segmentBytes offset: p2 offset epoch: 2)].
c that: 'temp: the other storage could not take the lock meanwhile' is: took equals: false.
c that: 'temp: the storage is closed' is: st isClosed equals: true.
c that: 'temp: nothing was renamed' is: other readRoot epoch equals: 1.
c that: 'temp: the lock is released' is: other tryLockRoot equals: true.
p2 := sr value: other.
c that: 'temp: the other storage publishes' is: (other replaceRoot: (PBRootRecord segment: p2 segmentBytes offset: p2 offset epoch: 2)) epoch equals: 2.
other close.
fresh := PBFileStorage path: (base / 'temp') pathString.
c that: 'temp: the space reopens at that root' is: fresh readRoot pointer equals: p2.
fresh close.

"--- unlockRoot during the rename ---"
st := CloseRace path: (base / 'unlock') pathString.
st tryLockRoot.
p1 := sr value: st.
other := PBFileStorage path: (base / 'unlock') pathString.
st duringRename: [
  st unlockRoot.
  took := other tryLockRoot].
r := st replaceRoot: (PBRootRecord segment: p1 segmentBytes offset: p1 offset epoch: 1).
c that: 'unlock: refused during the write' is: took equals: false.
c that: 'unlock: and logged' isTrue: ((st logged ifNil: ['']) includesSubstring: 'write is in progress').
c that: 'unlock: the lock is kept' is: st holdsRootLock equals: true.
c that: 'unlock: the publish completes' is: r epoch equals: 1.
st unlockRoot.
c that: 'unlock: released after the write' is: other tryLockRoot equals: true.
other close.
st close.

"--- close while a first push chooses its segment (m1) ---"
st := CloseRace path: (base / 'segment') pathString.
st duringSegmentId: [st close].
c that: 'segment: the push stops' signals: PBClosedError during: [st save: (PBObject withAll: { 'x' -> 1 })].
c that: 'segment: no segment file was created' is: ((base / 'segment') children select: [:f | f basename endsWith: '.seg']) size equals: 0.
c that: 'segment: the storage is closed' is: st isClosed equals: true.

"--- [replaceRoot:] ensure: [unlockRoot] with a close completed by the publish (m2) ---"
st := CloseRace path: (base / 'ensure') pathString.
st tryLockRoot.
p1 := sr value: st.
st duringRename: [st close].
r := [st replaceRoot: (PBRootRecord segment: p1 segmentBytes offset: p1 offset epoch: 1)] ensure: [took := st unlockRoot].
c that: 'ensure: the publish completes' is: r epoch equals: 1.
c that: 'ensure: unlockRoot answers false' is: took equals: false.
c that: 'ensure: and logs nothing' is: st logged equals: nil.

"--- a close requested during a write that then fails (m3) ---"
ss := SeamStorage path: (base / 'closefail') pathString.
ss tryLockRoot.
ss save: (PBObject withAll: { 'x' -> 1 }).
ss writer beforeAppend: [ss close. FileSystemError signal: 'injected failure after a close'].
c that: 'closefail: the write fails' signals: PBUnexpectedError containing: 'after a close' during: [
  ss save: (PBObject withAll: { 'y' -> 2 })].
c that: 'closefail: the storage is failed and closed' is: { ss isFailed. ss isClosed } equals: #(true true).
c that: 'closefail: its segment is closed' is: ss writer isClosed equals: true.
other := PBFileStorage path: (base / 'closefail') pathString.
c that: 'closefail: its lock is released' is: other tryLockRoot equals: true.
other close.

"--- a close requested during flushSegment with sealed segments pending (m3) ---"
ss := SeamStorage path: (base / 'closeflush') pathString segmentMaxBytes: 400.
ss tryLockRoot.
ss save: (PBList new extend: (1 to: 100) asArray).
c that: 'closeflush: several segments are pending' isTrue: ss writers size > 2.
ss writers first beforeSync: [ss close].
ss flushSegment.
c that: 'closeflush: the storage is closed' is: ss isClosed equals: true.
c that: 'closeflush: every segment writer is closed' isTrue: (ss writers allSatisfy: [:w | w isClosed]).
c that: 'closeflush: every one was synced first' isTrue: (ss writers allSatisfy: [:w | w syncs >= 1]).
other := PBFileStorage path: (base / 'closeflush') pathString.
c that: 'closeflush: its lock is released' is: other tryLockRoot equals: true.
other close.
base deleteAll.
c report displayNl.
