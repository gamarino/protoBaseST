"EXPECT: ok 6"
"Reads in cluster mode across restarts, forgotten roots and lost logs (cluster plan Task 24 and
 its fix round 1; space.st _snapshotRecord, _confirm, _committedRecord; proto_db transactions.py
 at v2.0.0rc4 _read_storage_root and coordinator.py current_root, recover_root, attach,
 force_rejoin). Real coordinators over one PBInProcessNetwork, each node a space over its own
 cluster-mode storage of one shared directory (_cluster_commit.st, _cluster_reads.st). Every wait
 is a condition with a deadline of 20 s, or a Future settled within 40 s; no duration is
 asserted.
 (1) L18: a node restarted after missing commits reads at or above the newest root the cluster
 committed before any commit of its own, and (2) its snapshots never go backwards across ten
 restarts (a regression guard: the confirmation and the logged committed root both give it).
 (3) Task 16, review I2: after a majority loss and forceRejoin on the survivor, the readers'
 committed root is no longer the dropped root R, and the survivor's next snapshot runs the
 confirmation first and does not start from R. (4) Fix round 1, review I3: a space reopened on the
 same coordinator reads the committed root of its log, not the one the node held in memory for
 the log it replaced; after the majority loss and forceRejoin on that survivor, its reads never
 start from R. (5) Fix round 1, review I1: a node whose acceptor log lost its unsynced committed
 entry in a power loss knows no committed root; a snapshot taken while its confirmation is in
 progress (held before it asks for a permission) recovers the peers' committed root instead of reading the persisted root (the empty
 space), and later snapshots never go below it. (6) The same node, cut off from its peers: the
 recovery fails (written to stderr), the persisted root is read once and taken as committed, so
 its next snapshot neither recovers nor reads the storage again; a persisted root read from a tier
 detached meanwhile is counted and says nothing."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_cluster_commit'.
Import from: '_cluster_reads'.

| c base kit db0 v r1 rootR n1 out acc rec notes firsts lastRead clusterEpoch setup rejoin gate a b
  lost reads trimmed infos detached |
c := Check new.
base := FileSystem temp / ('pbst-cluster-reads-restarts-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
SeamRound setUp.
SeamSpace setUp.

kit := Reads kit: CommitKit dir: base / 'restarts' acquire: 8000.
kit openAll.
db0 := (kit space: 'n0') newDatabase: 'db'.
db0 run: [:t | t setRootObject: 'counter' value: 0].

Reads step: '(1)'.
"(1) and (2): ten restarts of n0; on every other one n1 commits while n0 is down."
firsts := OrderedCollection new.
lastRead := (kit space: 'n0') _snapshotRecord epoch.
1 to: 10 do: [:i | | space |
  kit down: 'n0'.
  i odd ifTrue: [(kit db: 'db' on: 'n1') run: Reads incr].
  clusterEpoch := (kit space: 'n1') committedEpoch.
  kit up: 'n0'.
  space := kit open: 'n0'.
  rec := space _snapshotRecord.
  firsts add: { rec epoch >= clusterEpoch. rec epoch >= lastRead }.
  lastRead := rec epoch.
  space openDatabase: 'db'.
  lastRead := lastRead max: space _snapshotRecord epoch].
c that: 'L18: a node restarted after missing commits reads at or above the newest root the cluster committed, before any commit of its own'
  is: (firsts allSatisfy: [:x | x first]) equals: true.
c that: 'a snapshot never goes backwards across ten restarts'
  is: (firsts allSatisfy: [:x | x last]) equals: true.
kit shutdown.

"The majority loss of (3) and (4), on aKit: every node accepted r1. With n0 and n1 unable to talk
 (n2 talks to both), n0 commits R with n2; n1 learns R committed from n2's answer to its recovery
 query only (no replicate nor release of R reaches it, so its accepted root stays r1). Answers
 { v. r1. R. { n1's acceptor knows R committed. its accepted root is r1. its readers read R } }."
setup := [:aKit | | db value first dropped |
  aKit openAll.
  db := (aKit space: 'n0') newDatabase: 'db'.
  db run: [:t | t setRootObject: 'counter' value: 0].
  db run: Reads incr.
  value := Reads counter: db.
  first := (aKit node: 'n0') committedRoot.
  aKit waitUntil: [aKit ids allSatisfy: [:id | | x | x := (aKit node: id) acceptorState accepted. x notNil and: [x key = first key]]].
  aKit network partition: #(#('n0' 'n2') #('n1' 'n2')).
  db run: [:t | t setRootObject: 'counter' value: 1000].
  dropped := (aKit node: 'n0') committedRoot.
  aKit waitUntil: [| x | x := (aKit node: 'n2') acceptorState committed. x notNil and: [x key = dropped key]].
  aKit settle: (aKit node: 'n1') _recover.
  aKit waitUntil: [| x | x := (aKit node: 'n1') acceptorState. x committed notNil and: [x committed key = dropped key]].
  { value. first. dropped. { (aKit node: 'n1') acceptorState committed key = dropped key.
    (aKit node: 'n1') acceptorState accepted key = first key. (aKit node: 'n1') committedRoot key = dropped key } }].

"n0 and n2 lose their logs while the partition holds; healed and forced, they rejoin with n1's
 roots; then forceRejoin on n1, the survivor."
rejoin := [:aKit |
  #('n0' 'n2') do: [:id | aKit down: id].
  aKit network heal.
  #('n0' 'n2') do: [:id |
    (aKit dir / 'cluster' / (id , '.roots')) renameTo: id , '.roots.lost'.
    aKit up: id.
    aKit open: id].
  #('n0' 'n2') do: [:id | (aKit node: id) forceRejoin].
  aKit waitUntil: [#('n0' 'n2') allSatisfy: [:id | ((aKit node: id) stats at: 'rejoining') not]].
  (aKit node: 'n1') forceRejoin].

Reads step: '(3)'.
kit := Reads kit: CommitKit dir: base / 'drop' acquire: 8000.
out := setup value: kit.
v := out first. r1 := out at: 2. rootR := out at: 3. acc := out at: 4.
n1 := kit node: 'n1'.
rejoin value: kit.
kit waitUntil: [n1 acceptorState committed isNil and: [n1 committedRoot isNil or: [n1 committedRoot key ~= rootR key]]].
notes := SeamSpace notes size.
out := { n1 acceptorState needsConfirmation. n1 committedRoot isNil or: [n1 committedRoot key ~= rootR key] }.
rec := (kit space: 'n1') _snapshotRecord.
out := out , { (Reads notesAfter: notes prefix: 'n1 confirm') size >= 1. rec notNil and: [rec pointer ~= rootR record pointer].
  Reads counterIn: (kit space: 'n1') }.
c that: 'I2: after forceRejoin on the survivor, its readers no longer read the dropped root R, and its next snapshot confirms first and does not start from R'
  is: { acc. out } equals: { #(true true true). { true. true. true. true. v } }.
kit shutdown.

Reads step: '(4)'.
"(4) As (3), but n1's space is closed and reopened on the same coordinator before the majority
 loss: its log's committed root is not R (R was learnt from an answer, never logged)."
kit := Reads kit: CommitKit dir: base / 'reattach' acquire: 8000.
out := setup value: kit.
v := out first. r1 := out at: 2. rootR := out at: 3. acc := out at: 4.
n1 := kit node: 'n1'.
(kit space: 'n1') close.
kit open: 'n1'.
out := { kit waitUntil: [| x | x := n1 acceptorState committed.
    x notNil and: [n1 committedRoot notNil and: [n1 committedRoot key = x key]]].
  n1 committedRoot notNil and: [n1 committedRoot key ~= rootR key] }.
rejoin value: kit.
rec := (kit space: 'n1') _snapshotRecord.
out := out , { rec notNil and: [rec pointer ~= rootR record pointer]. Reads counterIn: (kit space: 'n1').
  n1 committedRoot isNil or: [n1 committedRoot key ~= rootR key] }.
c that: 'I3: a space reopened on the same coordinator reads its log''s committed root, not the replaced log''s; after forceRejoin on that survivor it never reads R'
  is: { acc. out } equals: { #(true true true). { true. true. true. v. true } }.
kit shutdown.

Reads step: '(5)'.
"(5) n0 makes the cluster's first commit (no committed entry of n0's log is synced before its
 accepted one: the trace of codes shows it) and goes down at once; the power loss takes the
 unsynced committed entry. n0 restarts; its confirmation is held (after the coordinator recorded
 that it started, before it asks for a permission) while a snapshot runs on another actor, its
 acceptor holding what the recovery teaches it (so the snapshot reads the root the recovery
 published to the readers before it answered)."
kit := Reads kit: GateKit dir: base / 'loss' acquire: 8000.
kit openAll.
(kit space: 'n0') newDatabase: 'db'.
rootR := (kit node: 'n0') committedRoot.
kit waitUntil: [#('n1' 'n2') allSatisfy: [:id | | x | x := (kit node: id) committedRoot. x notNil and: [x key = rootR key]]].
kit down: 'n0'.
lost := Reads losePower: kit dir / 'cluster' / 'n0.roots' suffix: '.before-loss'.
"A copy of the log the power loss left, for (6)."
trimmed := (PBFramedLog read: kit dir / 'cluster' / 'n0.roots' kind: PBAcceptorLog logKind) payloads.
kit up: 'n0'.
notes := SeamSpace notes size.
gate := Future new.
SeamSpace holdConfirmationOf: 'n0' until: gate.
kit open: 'n0'.
a := ReadWorker new asActor snapshotOf: (kit space: 'n0').
out := { lost. ((Reads codesOf: kit dir / 'cluster' / 'n0.roots') includes: 2) not. kit waitUntil: [(kit node: 'n0') needsConfirmation not] }.
GateAcceptor closeHearsay: 'n0'.
b := kit settle: (ReadWorker new asActor snapshotOf: (kit space: 'n0')).
out := out , { (kit node: 'n0') acceptorState committed isNil. (GateAcceptor held: 'n0 hearsay') >= 1 }.
GateAcceptor openHearsay: 'n0'.
out := out , { b first. (b first = #ok and: [b last notNil and: [b last epoch >= rootR epoch]]). (kit space: 'n0') listDatabases.
  (kit space: 'n0') committedEpoch >= rootR epoch. (kit node: 'n0') stats at: 'storage_root_reads' ifAbsent: [0] }.
gate resolve: true.
a := kit settle: a.
out := out , { a first. (a first = #ok and: [a last notNil and: [a last epoch >= rootR epoch]]). [:x | x notNil and: [x epoch >= rootR epoch]] value: (kit space: 'n0') _snapshotRecord.
  Reads notesAfter: notes prefix: 'n0 confirm' }.
c that: 'I1: a node whose log lost its committed entry recovers the peers'' committed root while its confirmation waits, never the persisted root'
  is: { out. GateAcceptor timedOut } equals: { { 1. true. true. true. true. #ok. true. #('db'). true. 0. #ok. true. true. #('n0 confirm' 'n0 confirm held') }. 0 }.

Reads step: '(6)'.
"(6) n0 again with the log the power loss left, cut off from n1 and n2, its space opened with a
 lockTimeout of 1000 ms: the confirmation times out, the recovery fails, the persisted root (the
 storage holds none before the persister, Task 25) is read once."
kit down: 'n0'.
(kit dir / 'cluster' / 'n0.roots') renameTo: 'n0.roots.after-loss'.
[| log | log := PBFramedLog openAppend: kit dir / 'cluster' / 'n0.roots' kind: PBAcceptorLog logKind.
 [trimmed do: [:p | log append: p sync: false]. log sync] ensure: [log close]] value.
kit network partition: #(#('n0') #('n1' 'n2')).
kit up: 'n0'.
kit open: 'n0' lockTimeout: 1000.
"A persisted root read from a tier that is no longer attached says nothing (proto_db current_root)."
((kit node: 'n0') _observePersisted: rootR from: Object new) wait.
detached := { (kit node: 'n0') committedRoot. (kit node: 'n0') stats at: 'storage_root_reads' ifAbsent: [0] }.
notes := SeamSpace notes size.
rec := (kit space: 'n0') _snapshotRecord.
reads := (kit node: 'n0') stats at: 'storage_root_reads' ifAbsent: [0].
infos := (Reads notesAfter: notes prefix: 'n0 info') collect: [:x |
  { x includesSubstring: 'recovery from the peers failed'. x includesSubstring: 'witnesses needed answered the recovery query' }].
out := { detached. rec. reads - detached last. infos. (Reads notesAfter: notes prefix: 'n0 warn') collect: [:x | x includesSubstring: 'within 1000 ms'] }.
notes := SeamSpace notes size.
rec := (kit space: 'n0') _snapshotRecord.
out := out , { rec. ((kit node: 'n0') stats at: 'storage_root_reads' ifAbsent: [0]) - reads. SeamSpace notes size - notes.
  (kit space: 'n0') listDatabases }.
c that: 'I1: cut off, a node that knows no committed root reads the persisted root once, and its next snapshot neither recovers nor reads the storage'
  is: out equals: { #(nil 1). nil. 1. #(#(true true)). #(true). nil. 0. 0. #() }.
kit network heal.
kit shutdown.

base deleteAll.
c report.
