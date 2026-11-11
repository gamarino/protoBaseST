"EXPECT: ok 12"
"PBFileStorage replaceRoot: refuses a cluster node's space (design spec 10.5; format spec,
 'A minimal external writer', step 6), with nothing written: a cluster/ directory created
 after the storage opened, and a current SpaceRoot that carries a cluster_term (a space
 committed by a cluster node, written here with the test builder). isCluster says so in
 both cases; a SpaceRoot whose cluster_term is nil is not a cluster's."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_spaces'.

| c base dir st p b ref spaceRootAt |
c := Check new.
base := FileSystem temp / ('pbst-store-cluster-' , Smalltalk pid printString).
base deleteAll.
spaceRootAt := [:aStorage |
  aStorage save: (PBSpaceRoot _unsavedWithState: (PBFrozenDict withAssociations: { 'databases' -> PBDictionary new }))].

"cluster/ created after the open."
dir := base / 'late'.
st := PBFileStorage path: dir pathString.
p := spaceRootAt value: st.
c that: 'not a cluster yet' is: st isCluster equals: false.
st tryLockRoot.
(dir / 'cluster') ensureCreateDirectory.
c that: 'isCluster' is: st isCluster equals: true.
c that: 'cluster/ refuses the publish' signals: PBNotSupportedError containing: 'cluster/' during: [
  st replaceRoot: (PBRootRecord segment: p segmentBytes offset: p offset epoch: 1)].
c that: 'nothing was published' is: { st readRoot. (dir / 'space.root.tmp') exists } equals: { nil. false }.
c that: 'the storage can still write' is: (st flushSegment; isFailed) equals: false.
st close.

"A current SpaceRoot with a cluster_term."
b := SpaceBuilder segment: (ByteArray fromHex: '5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c').
ref := b add: 6 oid: 2 state: { 'root' -> nil. 'count' -> 0. 'indexes' -> nil }.
ref := b add: 17 oid: 3 state: { 'databases' -> ref. 'cluster_term' -> 7. 'cluster_epoch' -> 1. 'cluster_previous' -> nil }.
dir := b writeTo: base / 'term' root: ref.
st := PBFileStorage path: dir pathString.
c that: 'a cluster_term: isCluster' is: st isCluster equals: true.
p := spaceRootAt value: st.
st tryLockRoot.
c that: 'a cluster_term refuses the publish' signals: PBNotSupportedError containing: 'cluster_term 7' during: [
  st replaceRoot: (PBRootRecord segment: p segmentBytes offset: p offset epoch: 2)].
c that: 'the root is unchanged' is: { st readRoot epoch. st readRoot pointer } equals: { 1. ref pointer }.
st close.

"A nil cluster_term is not a cluster's."
b := SpaceBuilder segment: (ByteArray fromHex: '5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d').
ref := b add: 6 oid: 2 state: { 'root' -> nil. 'count' -> 0. 'indexes' -> nil }.
ref := b add: 17 oid: 3 state: { 'databases' -> ref. 'cluster_term' -> nil }.
dir := b writeTo: base / 'nilterm' root: ref.
st := PBFileStorage path: dir pathString.
c that: 'a nil cluster_term: not a cluster' is: st isCluster equals: false.
p := spaceRootAt value: st.
st tryLockRoot.
c that: 'it publishes' is: (st replaceRoot: (PBRootRecord segment: p segmentBytes offset: p offset epoch: 2)) epoch equals: 2.
c that: 'over the builder''s root' is: st readRoot pointer equals: p.
st close.
c that: 'a closed storage: isCluster' signals: PBClosedError during: [st isCluster].
base deleteAll.
c report displayNl.
