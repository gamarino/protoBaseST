"EXPECT: ok 5"
"Reads in cluster mode, the committed root (cluster plan Task 24; space.st _snapshotRecord,
 committedEpoch; proto_db transactions.py at v2.0.0rc4 _read_storage_root, committed_epoch and
 coordinator.py current_root). Real coordinators over one PBInProcessNetwork, each node a space
 over its own cluster-mode storage of one shared directory (_cluster_commit.st, _cluster_reads.st).
 Every wait is a condition with a deadline of 20 s, or a Future settled within 40 s; no duration
 is asserted. GateAcceptor defers a node's learning of its own commit (the PBLearnCommitted of
 the commit point) until the test opens the gate, 20 s at most, so the order of the acceptor's
 publish and the commit's settle is fixed, not raced; the commits made while a gate is closed run
 on a ReadWorker actor, so a commit that does not return shows up as { #hung. ... } or as an
 expired gate, never as a hang.
 (1) Transactions read the committed root, not the storage: ten commits over two nodes, read on
 both, with at most four storage root reads made for transactions (the storages' readRoot
 calls less the persisters' reads, since Task 25) and no root published by a commit (every
 publish is a persister's write)
 (proto_db transactions::test_transactions_read_the_committed_root_not_the_storage).
 (2) Read-your-writes: a commit returns after its node's readers see its root, also while the
 node's acceptor has not learnt it yet: the readers held the root when the commit was settled.
 (3) The readers' committed root never goes backwards when the acceptor publishes an older root
 after the commit point published a newer one, and committedEpoch is monotonic on every node
 over the commits. (4) CC9: newDatabase: on one node is visible on another after that node's own
 barrier commit (newDatabase: itself, and a run: writing '_read_barrier'), with the done of the
 first lost to it and its acceptor held. (5) A node cut off reads its stale committed root, never
 an older storage root; after the heal the next commit's done reaches it
 (transactions::test_storage_root_reads_never_make_reads_go_backwards)."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_cluster_commit'.
Import from: '_cluster_reads'.

| c base kit db0 db1 s0 s1 v reads publishes r1 steps ryw out stale epochs before older learnt w settled |
c := Check new.
base := FileSystem temp / ('pbst-cluster-reads-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
SeamRound setUp.
SeamSpace setUp.

kit := Reads kit: GateKit dir: base / 'reads' acquire: 8000.
kit openAll.
kit ids do: [:id | (kit storage: id) trace: (Atom on: #())].

Reads step: '(1)'.
"(1)"
s0 := kit space: 'n0'.
s1 := kit space: 'n1'.
db0 := s0 newDatabase: 'db'.
db0 run: [:t | t setRootObject: 'counter' value: 0].
db1 := kit db: 'db' on: 'n1'.
0 to: 9 do: [:i | (i \\ 2 = 0 ifTrue: [db0] ifFalse: [db1]) run: Reads incr].
"The storage root reads made for transactions: every readRoot of the storages of n0 and n1 (their
 traces), less the persisters' (since Task 25; proto_db's RecordingStorage skips the persister
 threads' reads too): a refresh reads once, a persist: that took the root lock and published
 reads twice (its order check and replaceRoot:'s epoch check; roots_written), one refused reads
 once (roots_behind), a #busy one reads nothing. The persister counts a read
 after it, so the difference is waited for, never sampled once. Every publish of space.root is a
 write of a persister (its 'roots_written'), none a commit's."
reads := [#('n0' 'n1') inject: 0 into: [:n :id | | st |
  st := (kit space: id) _persister stats.
  n + (((kit storage: id) instVarNamed: 'trace') value count: [:x | x = 'read root'])
    - ((st at: 'refreshes') + (2 * (st at: 'roots_written')) + (st at: 'roots_behind'))]].
publishes := [kit ids inject: 0 into: [:n :id | n + (((kit storage: id) instVarNamed: 'trace') value select: [:x | x = 'publish']) size]].
c that: 'the committed root, not the storage: ten commits over two nodes are read on both, at most four storage root reads, no root published by a commit'
  is: { Reads counter: db1. kit waitUntil: [(Reads counter: db0) = 10]. kit waitUntil: [reads value <= 4].
    kit waitUntil: [publishes value = (kit ids inject: 0 into: [:n :id | n + ((kit space: id) _persister stats at: 'roots_written')])] }
  equals: { 10. true. true. true }.

Reads step: '(2)'.
"(2) n0's acceptor is held at the learning of its own commit; the commit runs on a worker."
GateAcceptor close: 'n0'.
before := GateAcceptor held: 'n0'.
settled := (SeamRound seamOf: 'n0') settles value size.
w := kit settle: (ReadWorker new asActor run: Reads incr on: db0).
r1 := (kit node: 'n0') committedRoot.
ryw := { w. Reads counter: db0. (kit waitUntil: [(GateAcceptor held: 'n0') > before]).
  (kit node: 'n0') acceptorState committed epoch < r1 epoch.
  ((SeamRound seamOf: 'n0') settles value copyFrom: settled + 1 to: (SeamRound seamOf: 'n0') settles value size).
  GateAcceptor timedOut }.
c that: 'read-your-writes: a commit returns after its readers see its root, before its acceptor learnt it'
  is: ryw equals: { #ok. 11. true. true. #(true). 0 }.

Reads step: '(3)'.
"(3) While the acceptor still holds the learning of r1, it publishes the older root it knows (what
 its learning of an older root does after the commit point published a newer one); then it
 learns r1."
older := (kit node: 'n0') acceptorState committed.
((kit node: 'n0') instVarNamed: 'cells') publishCommitted: (PBPublishCommitted root: older).
steps := { (kit node: 'n0') committedRoot key = r1 key. s0 committedEpoch = r1 epoch. older epoch < r1 epoch }.
learnt := GateAcceptor learnt: 'n0'.
GateAcceptor open: 'n0'.
steps := steps , { kit waitUntil: [(GateAcceptor learnt: 'n0') > learnt]. (kit node: 'n0') committedRoot key = r1 key.
  GateAcceptor timedOut }.
epochs := OrderedCollection new.
1 to: 6 do: [:i | | space |
  space := kit space: (kit ids at: i - 1 \\ 3 + 1).
  (kit db: 'db' on: space coordinator nodeId) run: Reads incr.
  epochs add: (kit ids collect: [:id | (kit space: id) committedEpoch])].
c that: 'never backwards: the readers'' committed root stays at the commit point''s while the acceptor publishes an older root; committedEpoch is monotonic on every node'
  is: { steps. (1 to: 3) allSatisfy: [:k | (2 to: epochs size) allSatisfy: [:j | ((epochs at: j) at: k) >= ((epochs at: j - 1) at: k)]] }
  equals: { { true. true. true. true. true. 0 }. true }.

Reads step: '(4)'.
"(4) n1 and n2 cannot talk; n0 talks to both. n2's newDatabase: and its done never reach n1; n1's
 learning of each of its own commits is deferred; they run on a worker."
kit network partition: #(#('n0' 'n2') #('n0' 'n1')).
GateAcceptor close: 'n1'.
(kit space: 'n2') newDatabase: 'from-n2'.
out := { kit settle: (ReadWorker new asActor newDatabase: 'from-n1' in: (kit space: 'n1')).
  (kit space: 'n1') listDatabases includes: 'from-n2' }.
GateAcceptor open: 'n1'.
(kit space: 'n2') newDatabase: 'from-n2-again'.
GateAcceptor close: 'n1'.
out := out , { kit settle: (ReadWorker new asActor run: [:t | t setRootObject: '_read_barrier' value: true] on: db1).
  (kit space: 'n1') listDatabases includes: 'from-n2-again' }.
GateAcceptor open: 'n1'.
kit network heal.
c that: 'CC9: a database made on one node is visible on another after that node''s own barrier commit (newDatabase:, run: writing _read_barrier)'
  is: { out. GateAcceptor timedOut } equals: { #(#ok true #ok true). 0 }.

Reads step: '(5)'.
"(5)"
db0 run: Reads incr.
v := Reads counter: db0.
kit waitUntil: [(Reads counter: db1) = v].
kit network partition: #(#('n0' 'n2') #('n1')).
3 timesRepeat: [db0 run: Reads incr].
stale := Reads counter: db1.
kit network heal.
db0 run: Reads incr.
c that: 'storage root reads never make reads go backwards: a cut-off node reads its stale committed root, then the next commit''s done reaches it'
  is: { stale. kit waitUntil: [(Reads counter: db1) = (v + 4)]. (s1 openDatabase: 'db') history first version = (db0 history first version) }
  equals: { v. true. true }.
kit shutdown.

base deleteAll.
c report.
