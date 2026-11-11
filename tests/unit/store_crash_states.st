"EXPECT: ok 21"
"Crash states on disk (plan Task 17 review, I3), each put there by a seam that writes a prefix
 of its bytes and then fails, exactly what a crash during that write leaves (no process is
 killed, nothing depends on timing): a torn record at the end of the owned segment, a segment
 whose header is torn (a crash while it was created), a torn space.root.tmp, and an unsynced
 tail (records appended after the last publish, never published). Each starts from a space
 published at epoch 1. In every case the space reopens at that root, its record loads, a fresh
 storage publishes epoch 2 over it, and the space reopens there; the crash leftovers stay as
 they are (never read, never truncated). tests/interop/crash_states_to_py.sh hands the same
 states to ProtoBase."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_seams'.

| c base sr dir st p1 recover segs |
c := Check new.
base := FileSystem temp / ('pbst-crash-states-' , Smalltalk pid printString).
base deleteAll.
sr := [:s | s save: (PBSpaceRoot _unsavedWithState: (PBFrozenDict withAssociations: { 'databases' -> PBDictionary new }))].
"A space at aDir published at epoch 1 by a SeamStorage left open, answered with p1 set."
segs := [:aDir | (aDir children select: [:f | f basename endsWith: '.seg']) size].
recover := [:aLabel :aDir |
  | fresh p2 |
  fresh := PBFileStorage path: aDir pathString.
  c that: aLabel , ': reopens at epoch 1' is: { fresh readRoot epoch. fresh readRoot pointer } equals: { 1. p1 }.
  c that: aLabel , ': the root record loads' isTrue:
    ((fresh loadAt: fresh readRoot pointer expecting: PBFileStorage spaceRootTag) state includesKey: 'databases').
  fresh tryLockRoot.
  p2 := sr value: fresh.
  fresh replaceRoot: (PBRootRecord segment: p2 segmentBytes offset: p2 offset epoch: 2).
  fresh close.
  fresh := PBFileStorage path: aDir pathString.
  c that: aLabel , ': a fresh storage published over it' is: { fresh readRoot epoch. fresh readRoot pointer } equals: { 2. p2 }.
  fresh close].
"Opens a SeamStorage on aName and publishes epoch 1."
st := nil.
dir := nil.
p1 := nil.

"--- a torn record ---"
dir := base / 'record'.
st := SeamStorage path: dir pathString.
st tryLockRoot.
p1 := sr value: st.
st replaceRoot: (PBRootRecord segment: p1 segmentBytes offset: p1 offset epoch: 1).
st writer tearNextAppendAt: 9.
c that: 'record: the append fails' signals: PBUnexpectedError containing: 'torn record' during: [
  st save: (PBObject withAll: { 'lost' -> true })].
c that: 'record: the segment ends in a torn record' signals: PBCorruptionError containing: 'truncated' during: [
  st recordsOfSegment: st currentSegment].
st close.
recover value: 'record' value: dir.

"--- a torn segment header ---"
dir := base / 'header'.
st := SeamStorage path: dir pathString.
st tryLockRoot.
p1 := sr value: st.
st replaceRoot: (PBRootRecord segment: p1 segmentBytes offset: p1 offset epoch: 1).
st close.
st := SeamStorage path: dir pathString.
st tearNextSegmentHeader.
c that: 'header: the segment creation fails' signals: PBUnexpectedError containing: 'torn segment header' during: [
  st save: (PBObject withAll: { 'lost' -> true })].
c that: 'header: a second segment file is left' is: (segs value: dir) equals: 2.
c that: 'header: holding 11 bytes' is: ((dir children detect: [:f | (f basename endsWith: '.seg') and: [f size = 11]] ifNone: [nil]) notNil) equals: true.
st close.
recover value: 'header' value: dir.

"--- a torn space.root.tmp ---"
dir := base / 'roottmp'.
st := SeamStorage path: dir pathString.
st tryLockRoot.
p1 := sr value: st.
st replaceRoot: (PBRootRecord segment: p1 segmentBytes offset: p1 offset epoch: 1).
st tearRootTempAt: 6.
c that: 'roottmp: the publish fails' signals: PBUnexpectedError containing: 'torn space.root.tmp' during: [
  | p |
  p := sr value: st.
  st replaceRoot: (PBRootRecord segment: p segmentBytes offset: p offset epoch: 2)].
c that: 'roottmp: space.root.tmp holds 6 bytes' is: (dir / 'space.root.tmp') size equals: 6.
st close.
recover value: 'roottmp' value: dir.
c that: 'roottmp: the next publish replaced it' is: (dir / 'space.root.tmp') exists equals: false.

"--- an unsynced tail ---"
dir := base / 'tail'.
st := SeamStorage path: dir pathString.
st tryLockRoot.
p1 := sr value: st.
st replaceRoot: (PBRootRecord segment: p1 segmentBytes offset: p1 offset epoch: 1).
st save: (PBObject withAll: { 'unpublished' -> 1 }).
st save: (PBObject withAll: { 'unpublished' -> 2 }).
c that: 'tail: two records after the root, never synced' is: st writer syncs equals: 1.
st close.
recover value: 'tail' value: dir.

base deleteAll.
c report displayNl.
