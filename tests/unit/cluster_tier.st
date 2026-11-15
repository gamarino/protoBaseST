"EXPECT: ok 38"
"The shared tier and the cluster storage mode (cluster/tier.st, store.st clusterPath:, space.st
 storage:coordinator:; proto_db cluster/persister.py PlainTier and _node_log, transactions.py
 ObjectSpace(coordinator=)).
 (1) The log name of a node id (CC21, Review Focus 5): an id matching [A-Za-z0-9._-]{1,64} is
 its own name, any other the hex of its UTF-8 bytes, as proto_db's _node_log; the log of '..' is
 the file '...roots' inside cluster/. (2) A second tier of the same node over the same
 directory is PBUserError naming cluster/n0.roots.lock, and the first is unaffected (Review
 Focus 3). (3) A log holding a kind-5 entry (a tiered node's) is refused (CC15). (4) persist:
 (CC19): a cluster root is written, never one at or below the persisted root in the order of
 roots (false), #busy while this test holds space.lock (no wait, no sleep), a plain SpaceRoot
 refused in cluster mode; readPersisted answers the label and the cluster epoch of a cluster
 root, label 0 and the storage epoch of a plain one; canRead:. (5) The mode refusals (CC20).
 (6) A new log and its directories are synced when it opens (proto_db
 test_a_new_acceptor_log_and_its_directories_survive_a_power_loss, observed through the
 _syncDirectory: seam, then a reload). (7) The space: no coordinator without one (proto_db
 test_space_without_coordinator_has_none); storage:coordinator: attaches the node's tier to a
 one-member coordinator, reads a cluster root, and close detaches it and releases the log; the
 attach identity rule of proto_db _attach_locked (the same storage is a no-op, another storage
 refused)."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_cluster_shell'.

PBAcceptorLog subclass: #SeamLog instanceVariableNames: '' classVariableNames: 'Synced'.
SeamLog class >> _setSynced: anAtom
  Synced := anAtom.
SeamLog class >> synced
  ^ Synced.
SeamLog class >> _syncDirectory: aFileReference
  Synced swap: [:old | old , { aFileReference pathString }].
  ^ super _syncDirectory: aFileReference.
SeamLog _setSynced: (Atom on: #()).
PBSharedTier subclass: #SeamTier.
_PBAcceptor subclass: #GatedAcceptor instanceVariableNames: '' classVariableNames: 'Gate Trace'.
GatedAcceptor class >> _setGate: aFuture trace: anAtom
  Gate := aFuture.
  Trace := anAtom.
GatedAcceptor class >> gate
  ^ Gate.
GatedAcceptor class >> trace
  ^ Trace.
GatedAcceptor >> finish
  Gate wait.
  Trace swap: [:old | old , #('finish')].
  ^ super finish.
GatedAcceptor _setGate: Future new trace: (Atom on: #()).
SeamTier class >> logClass
  ^ SeamLog.

| c base dir st tier other rec p1 p2 p3 r1 r2 r3 lockFile held plain kit node space s2 w t2 t3 st3 framed d closing p4 kit2 node2 space2 detached trace |
c := Check new.
base := FileSystem temp / ('pbst-cluster-tier-' , Smalltalk pid printString).
base deleteAll.
"A labelled root at the pointer aPointer, label aLabel and cluster epoch anEpoch."
"aBlock run with the storage aStorage, which is closed afterwards (refusal blocks, M6)."
closing := [:aStorage :aBlock | [aBlock value: aStorage] ensure: [aStorage close]].
rec := [:aPointer :aLabel :anEpoch |
  PBLabeledRoot label: aLabel record: (PBRootRecord segment: aPointer segmentBytes offset: aPointer offset epoch: anEpoch)].

"--- (1) log names ---"
c that: 'a safe id is its own name' is: (PBSharedTier logName: 'n0') equals: 'n0'.
c that: 'a non-ASCII id is the hex of its UTF-8' is: (PBSharedTier logName: 'nœud') equals: '6ec5937564'.
c that: 'an id with a slash is hex' is: (PBSharedTier logName: 'a/b') equals: '612f62'.
c that: 'an id of 65 characters is hex' is: (PBSharedTier logName: (String new: 65 withAll: $a))
  equals: ((1 to: 65) inject: '' into: [:acc :i | acc , '61']).
dir := base / 'names'.
st := PBFileStorage clusterPath: dir pathString.
tier := PBSharedTier storage: st nodeId: '..'.
c that: 'the log of .. is ...roots inside cluster/' is: { tier logPath basename. tier logPath parent pathString }
  equals: { '...roots'. (dir / 'cluster') realPath pathString }.
tier close.
st close.

"--- (2) a second tier of one node ---"
dir := base / 'twice'.
st := PBFileStorage clusterPath: dir pathString.
tier := PBSharedTier storage: st nodeId: 'n0'.
c that: 'a second tier of n0 is refused naming its lock file' signals: PBUserError containing: 'cluster/n0.roots.lock' during: [
  closing value: (PBFileStorage clusterPath: dir pathString) value: [:s | PBSharedTier storage: s nodeId: 'n0']].
tier logPromise: 5.
c that: 'the first tier is unaffected' is: tier loadRoots promise equals: 5.
tier close.
st close.

"--- (3) a tiered node's log ---"
dir := base / 'kind5'.
framed := PBFramedLog openAppend: (dir / 'cluster' / 'n0.roots') kind: PBAcceptorLog logKind.
framed append: #[5] , (ByteArray new: 92) sync: true.
framed close.
st := PBFileStorage clusterPath: dir pathString.
c that: 'a log with a kind-5 entry is refused' signals: PBNotSupportedError containing: 'kind 5 or 6' during: [
  PBSharedTier storage: st nodeId: 'n0'].
lockFile := BinaryFile open: dir / 'cluster' / 'n0.roots.lock' options: #(#read #write #create).
c that: 'the refusal released its lock' is: lockFile tryLock equals: true.
lockFile unlock.
lockFile close.
st close.

"--- (4) persist:, readPersisted, canRead: ---"
dir := base / 'persist'.
st := PBFileStorage clusterPath: dir pathString.
tier := PBSharedTier storage: st nodeId: 'n0'.
c that: 'an empty space has no persisted root' is: tier readPersisted equals: nil.
p1 := st save: (PBSpaceRoot databases: PBDictionary new term: 7 epoch: 1 previous: nil).
p2 := st save: (PBSpaceRoot databases: PBDictionary new term: 7 epoch: 2 previous: nil).
p3 := st save: (PBSpaceRoot databases: PBDictionary new term: 9 epoch: 3 previous: nil).
r1 := rec value: p1 value: 7 value: 1.
r2 := rec value: p2 value: 7 value: 2.
r3 := rec value: p3 value: 9 value: 3.
c that: 'persist writes a cluster root' is: { tier persist: r1. tier persist: r2. tier readPersisted key. st readRoot epoch. st holdsRootLock }
  equals: { true. true. r2 key. 2. false }.
c that: 'persist never goes backwards' is: { tier persist: r1. tier persist: r2. st readRoot epoch. st readRoot pointer }
  equals: { false. false. 2. p2 }.
lockFile := BinaryFile open: dir / PBFileStorage lockFileName options: #(#read #write #create).
held := lockFile tryLock.
c that: 'persist is #busy while space.lock is held' is: { held. tier persist: r3. st readRoot epoch } equals: { true. #busy. 2 }.
lockFile unlock.
lockFile close.
c that: 'then it persists' is: { tier persist: r3. tier readPersisted key } equals: { true. r3 key }.
plain := st save: (PBSpaceRoot databases: PBDictionary new).
c that: 'a plain SpaceRoot is refused in cluster mode' signals: PBValidationError containing: 'cluster_term' during: [
  tier persist: (rec value: plain value: 10 value: 4)].
c that: 'the refusal wrote nothing and released the lock' is: { st readRoot epoch. st holdsRootLock } equals: { 3. false }.
p4 := st save: (PBSpaceRoot databases: PBDictionary new term: 11 epoch: 5 previous: nil).
c that: 'persist refuses a label that is not its SpaceRoot''s' signals: PBValidationError containing: 'carries cluster_term 11' during: [
  tier persist: (rec value: p4 value: 12 value: 5)].
c that: 'persist refuses an epoch that is not its SpaceRoot''s' signals: PBValidationError containing: 'cluster_epoch 5' during: [
  tier persist: (rec value: p4 value: 11 value: 6)].
c that: 'the mismatches wrote nothing and released the lock' is: { st readRoot epoch. st holdsRootLock. tier persist: (rec value: p4 value: 11 value: 5) }
  equals: { 3. false. true }.
c that: 'canRead: a written root' is: (tier canRead: r3) equals: true.
c that: 'canRead: a root at no record' is: (tier canRead: (PBLabeledRoot label: 9 record: (PBRootRecord
  segment: p3 segmentBytes offset: 999999 epoch: 4))) equals: false.
tier close.
st close.
c that: 'canRead: on a closed storage signals PBClosedError' signals: PBClosedError during: [tier canRead: r3].
"A plain space: label 0, the storage epoch."
dir := base / 'plain'.
st := PBFileStorage path: dir pathString.
p1 := st save: (PBSpaceRoot databases: PBDictionary new).
st tryLockRoot.
st replaceRoot: (PBRootRecord segment: p1 segmentBytes offset: p1 offset epoch: 1).
st unlockRoot.
st close.
st := PBFileStorage clusterPath: dir pathString.
tier := PBSharedTier storage: st nodeId: 'n0'.
c that: 'readPersisted of a plain space is label 0' is: tier readPersisted key equals: (PBLabeledRoot label: 0
  record: (PBRootRecord segment: p1 segmentBytes offset: p1 offset epoch: 1)) key.
tier close.
st close.

"--- (5) the mode refusals ---"
dir := base / 'modes'.
c that: 'storage: refuses a cluster-mode storage' signals: PBValidationError containing: 'storage:coordinator:' during: [
  closing value: (PBFileStorage clusterPath: dir pathString) value: [:s | PBObjectSpace storage: s]].
kit := ShellKit ids: #('n0').
node := kit node: 'n0'.
node start.
c that: 'storage:coordinator: refuses a plain storage' signals: PBValidationError containing: 'clusterPath:' during: [
  closing value: (PBFileStorage path: (base / 'modes-plain') pathString) value: [:s | PBObjectSpace storage: s coordinator: node]].
c that: 'storage:coordinator: refuses what is not a coordinator' signals: PBValidationError containing: 'PBClusterCoordinator' during: [
  closing value: (PBFileStorage clusterPath: (base / 'modes-nocoord') pathString) value: [:s | PBObjectSpace storage: s coordinator: 'n0']].
c that: 'a tier needs a cluster-mode storage' signals: PBValidationError containing: 'clusterPath:' during: [
  closing value: (PBFileStorage path: (base / 'modes-plain2') pathString) value: [:s | PBSharedTier storage: s nodeId: 'n0']].

"--- (6) a new log and its directories are synced ---"
dir := base / 'synced'.
st := PBFileStorage clusterPath: dir pathString.
tier := SeamTier storage: st nodeId: 'a'.
tier logPromise: 5 * 4096.
tier logAccepted: r3.
tier logRejoined.
tier close.
d := { (dir / 'cluster') realPath pathString. dir realPath pathString }.
tier := PBSharedTier storage: st nodeId: 'a'.
c that: 'a new acceptor log and its directories are synced' is: { SeamLog synced value. tier loadRoots promise.
  tier loadRoots accepted key. tier loadRoots isRejoined } equals: { d. 5 * 4096. r3 key. true }.
tier close.
st close.

"--- (7) the space ---"
space := PBObjectSpace storage: (PBFileStorage path: (base / 'nocoord') pathString).
c that: 'a space opened without a coordinator has none' is: space coordinator equals: nil.
space close.
dir := base / 'bare'.
st := PBFileStorage clusterPath: dir pathString.
p1 := st save: (PBSpaceRoot databases: PBDictionary new term: 4 epoch: 1 previous: nil).
st tryLockRoot.
st replaceRoot: (PBRootRecord segment: p1 segmentBytes offset: p1 offset epoch: 1).
st unlockRoot.
st close.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
c that: 'a space without a coordinator refuses a cluster root' signals: PBNotSupportedError containing: 'storage:coordinator:' during: [
  space listDatabases].
space close.
dir := base / 'space'.
"A cluster root persisted by another node, w."
st := PBFileStorage clusterPath: dir pathString.
w := PBSharedTier storage: st nodeId: 'w'.
p1 := st save: (PBSpaceRoot databases: PBDictionary new term: 4 epoch: 1 previous: nil).
w persist: (rec value: p1 value: 4 value: 1).
w close.
st close.
"A refusal above that did not refuse (a mutation) leaves no tier attached for what follows."
(node _detach) wait.
space := PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: node.
c that: 'storage:coordinator: attaches the node''s tier and reads a cluster root' is: { space coordinator == node.
  space listDatabases. node acceptorState isAttached.
  (PBAcceptorLog decode: (PBFramedLog read: dir / 'cluster' / 'n0.roots' kind: PBAcceptorLog logKind) payloads path: 'n0') isRejoined }
  equals: { true. #(). true. true }.
c that: 'a second space of the node over the directory is refused at its lock' signals: PBUserError containing: 'cluster/n0.roots.lock' during: [
  closing value: (PBFileStorage clusterPath: dir pathString) value: [:s | PBObjectSpace storage: s coordinator: node]].
t2 := PBSharedTier storage: space storage nodeId: 'x'.
c that: 'a tier over the attached storage is a no-op' is: ([(node _attach: t2) wait] on: PBDBError do: [:e | e return: e class name])
  equals: true.
st3 := PBFileStorage clusterPath: (base / 'space-other') pathString.
t3 := PBSharedTier storage: st3 nodeId: 'n0'.
c that: 'a tier over another storage is refused' signals: PBValidationError containing: 'another storage' during: [
  (node _attach: t3) wait].
c that: 'detaching a tier not attached detaches nothing' is: { (node _detach: t3) wait. node acceptorState isAttached } equals: { nil. true }.
t2 close.
t3 close.
st3 close.
space close.
s2 := PBFileStorage clusterPath: dir pathString.
tier := PBSharedTier storage: s2 nodeId: 'n0'.
c that: 'close detached the tier and released its log' is: { node acceptorState isAttached. tier loadRoots isRejoined } equals: { false. true }.
tier close.
s2 close.
node stop waitWithin: 60000.

"A detach while the node stops settles only once the acceptor step in progress has finished
 (M4): GatedAcceptor holds stop's finish step until the test releases it; the order of the trace
 is fixed by the code (a Future already settled runs thenDo: at once)."
kit2 := ShellKit ids: #('n0').
node2 := kit2 node: 'n0' options: Dictionary new rules: PBCoordinatorCore new acceptorClass: GatedAcceptor.
node2 start.
dir := base / 'stopping'.
space2 := PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: node2.
trace := GatedAcceptor trace.
w := node2 stop.
detached := node2 _detach: nil.
detached thenDo: [:x | trace swap: [:old | old , #('detached')]].
trace swap: [:old | old , #('released')].
GatedAcceptor gate resolve: true.
w waitWithin: 60000.
detached waitWithin: 60000.
c that: 'a detach during a stop settles after the acceptor step in progress' is: trace value equals: #('released' 'finish' 'detached').
space2 close.
s2 := PBFileStorage clusterPath: dir pathString.
c that: 'a space closed after its node stopped releases its log' is: ((PBSharedTier storage: s2 nodeId: 'n0') close; yourself) class equals: PBSharedTier.
s2 close.
base deleteAll.
c report displayNl.
