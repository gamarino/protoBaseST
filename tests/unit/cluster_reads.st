"EXPECT: ok 11"
"Reads in cluster mode (cluster plan Task 24; space.st _snapshotRecord, _confirm, committedEpoch;
 proto_db transactions.py at v2.0.0rc4 _read_storage_root, committed_epoch and coordinator.py
 current_root, needs_confirmation). Real coordinators over one PBInProcessNetwork, each node a
 space over its own cluster-mode storage of one shared directory (_cluster_commit.st). Every wait
 is a condition with a deadline of 60 s (or a Future settled within 120 s); no duration is
 asserted. GateAcceptor holds the acceptor of a node at the learning of its own commit (the
 PBLearnCommitted of the commit point) until the test opens the gate, so the order of the
 acceptor's publish and the commit's settle is fixed, not raced.
 (1) Transactions read the committed root, not the storage: ten commits over two nodes, read on
 both, with at most four storage root reads and no root published under them by a commit
 (proto_db transactions::test_transactions_read_the_committed_root_not_the_storage).
 (2) Read-your-writes: a commit returns after its node's readers see its root, also while the
 node's acceptor has not learnt it yet. (3) The readers' committed root never goes backwards
 when the acceptor publishes an older root after the commit point published a newer one, and
 committedEpoch is monotonic on every node over the commits. (4) CC9: newDatabase: on one node
 is visible on another after that node's own barrier commit (newDatabase: itself, and a run:
 writing '_read_barrier'), with the done of the first lost to it and its acceptor held.
 (5) A node cut off reads its stale committed root, never an older storage root; after the heal
 the next commit's done reaches it (transactions::test_storage_root_reads_never_make_reads_go_
 backwards). (6) L18: a node restarted after missing commits reads at or above the newest root
 the cluster committed before any commit of its own, and (7) its snapshots never go backwards
 across ten restarts. (8) Task 16, review I2: after a majority loss and forceRejoin on the
 survivor, the readers' committed root is no longer the dropped root R, and the survivor's next
 snapshot runs the confirmation first and does not start from R. (9) A space opened while no
 majority has a space gets no permission: its confirmation fails, logged, and the read starts
 from the committed root it knows; once a majority opens, every member commits
 (transactions::test_a_space_opened_while_no_majority_has_a_space_gets_no_permission_until_one_does).
 (10) A confirmation in progress succeeds once a majority opens its spaces, with no warning
 (transactions::test_a_confirmation_in_progress_succeeds_once_a_majority_opens_its_spaces).
 (11) A first newDatabase: whose recovery query goes unanswered conflicts, nothing created, and
 its retry creates the database once
 (transactions::test_a_setup_new_database_whose_recovery_query_goes_unanswered_conflicts_and_is_retried)."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_cluster_commit'.

"=== seams ===================================================================="

"An acceptor that, while its node has a gate (a Future), waits for it before it learns its own
 commit (the PBLearnCommitted of the commit point: accepted and logged). Held counts the events
 held, Learnt the events it went on with."
_PBAcceptor subclass: #GateAcceptor instanceVariableNames: '' classVariableNames: 'Gates Held Learnt'.

GateAcceptor class >> setUp
  Gates := Atom on: Dictionary new.
  Held := Atom on: Dictionary new.
  Learnt := Atom on: Dictionary new.

GateAcceptor class >> _bump: anAtom at: anId
  anAtom swap: [:d | | copy | copy := d copy. copy at: anId put: (d at: anId ifAbsent: [0]) + 1. copy].

GateAcceptor class >> held: anId
  ^ Held value at: anId ifAbsent: [0].

GateAcceptor class >> learnt: anId
  ^ Learnt value at: anId ifAbsent: [0].

"Holds anId's next own-commit learning (and every one after it) until the gate opens."
GateAcceptor class >> close: anId
  Gates swap: [:d | | copy | copy := d copy. copy at: anId put: Future new. copy].

"Lets the held learning of anId go on, and holds the next one."
GateAcceptor class >> step: anId
  | old |
  old := Gates value at: anId.
  self close: anId.
  old resolve: true.

"Opens anId's gate for good."
GateAcceptor class >> open: anId
  | old |
  old := Gates value at: anId ifAbsent: [nil].
  Gates swap: [:d | | copy | copy := d copy. copy removeKey: anId ifAbsent: [nil]. copy].
  old isNil ifFalse: [old resolve: true].

GateAcceptor >> handle: anEvent
  | gate result |
  ((anEvent isKindOf: PBLearnCommitted) and: [anEvent isAccepted and: [anEvent isLogged]]) ifFalse: [^ super handle: anEvent].
  gate := Gates value at: cells config nodeId ifAbsent: [nil].
  gate isNil ifFalse: [
    GateAcceptor _bump: Held at: cells config nodeId.
    gate wait].
  result := super handle: anEvent.
  GateAcceptor _bump: Learnt at: cells config nodeId.
  ^ result.

GateAcceptor setUp.

"A transport that, once armed, drops the first two 'answer' messages sent to n0, noting who sent
 them (Dropped)."
PBInProcessTransport subclass: #DropEndpoint instanceVariableNames: '' classVariableNames: 'Armed Dropped'.

DropEndpoint class >> setUp
  Armed := Atom on: false.
  Dropped := Atom on: #().

DropEndpoint class >> arm
  Armed swap: [:x | true].

DropEndpoint class >> dropped
  ^ Dropped value.

DropEndpoint >> send: aMessage to: aNodeId
  | drop |
  drop := false.
  (Armed value and: [aNodeId = 'n0' and: [aMessage type = 'answer']]) ifTrue: [
    Dropped swap: [:d | drop := d size < 2. drop ifTrue: [d copyWith: aMessage from] ifFalse: [d]]].
  drop ifTrue: [^ self].
  ^ super send: aMessage to: aNodeId.

DropEndpoint setUp.

"An actor client: the counter of a space's database 'db', read by its first snapshot."
Object subclass: #Opener.

Opener >> counterIn: aSpace
  ^ Reads counterIn: aSpace.

CommitKit subclass: #GateKit.

GateKit >> acceptorClass
  ^ GateAcceptor.

CommitKit subclass: #DropKit.

DropKit >> endpointFor: anId
  ^ DropEndpoint network: self network.

"=== helpers ==================================================================="

Object subclass: #Reads.

"The counter of aDatabase as a new transaction of it reads it (nil when the database is not known)."
Reads class >> counter: aDatabase
  | tr v |
  tr := aDatabase newTransaction.
  v := tr getRootObject: 'counter'.
  tr abort.
  ^ v.

"The counter of the database 'db' of aSpace, or the error's class name."
Reads class >> counterIn: aSpace
  ^ [self counter: (aSpace openDatabase: 'db')] on: Error do: [:e | e return: e class name].

"aString on stderr with the monotonic milliseconds: where a run is, never asserted."
Reads class >> step: aString
  [Stdio stderr nextPutAll: 'cluster_reads ' , Time millisecondClockValue printString , ' ' , aString; lf; flush] on: Error do: [:e | nil].

Reads class >> incr
  ^ [:t | t setRootObject: 'counter' value: (t getRootObject: 'counter') + 1].

"aDatabase run: incr, retried on PBConflictError and PBTimeoutError up to n times: #ok or the
 last error's class name."
Reads class >> run: aDatabase retries: n
  | last |
  1 to: n do: [:i |
    last := [aDatabase run: self incr retries: 20. nil] on: Error do: [:e | e return: e].
    last isNil ifTrue: [^ #ok].
    ((last isKindOf: PBConflictError) or: [last isKindOf: PBTimeoutError]) ifFalse: [^ last class name]].
  ^ last class name.

"The notes of SeamSpace after the first n that start with aPrefix."
Reads class >> notesAfter: n prefix: aPrefix
  | all |
  all := SeamSpace notes.
  ^ (all copyFrom: n + 1 to: all size) select: [:x | x beginsWith: aPrefix].

| c base kit opts db0 db1 db2 s0 s1 v reads publishes r1 steps ryw r out stale epochs firsts lastRead
  clusterEpoch rec rootR acc n1 notes before lonely f done waited dbL older learnt |
c := Check new.
base := FileSystem temp / ('pbst-cluster-reads-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
SeamRound setUp.
SeamSpace setUp.
opts := [:acquire | Dictionary new at: #leaseDuration put: 1500; at: #driftMargin put: 1000; at: #requestTimeout put: 300;
  at: #acquireTimeout put: acquire; yourself].

kit := GateKit ids: #('n0' 'n1' 'n2') dir: base / 'reads' options: (opts value: 8000).
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
reads := #('n0' 'n1') inject: 0 into: [:n :id | n + (((kit storage: id) instVarNamed: 'trace') value select: [:x | x = 'read root']) size].
publishes := kit ids inject: 0 into: [:n :id | n + (((kit storage: id) instVarNamed: 'trace') value select: [:x | x = 'publish']) size].
c that: 'the committed root, not the storage: ten commits over two nodes are read on both, at most four storage root reads, no root published by a commit'
  is: { Reads counter: db1. kit waitUntil: [(Reads counter: db0) = 10]. reads <= 4. publishes }
  equals: { 10. true. true. 0 }.

Reads step: '(2)'.
"(2) n0's acceptor is held at the learning of its own commit."
GateAcceptor close: 'n0'.
before := GateAcceptor held: 'n0'.
db0 run: Reads incr.
r1 := (kit node: 'n0') committedRoot.
ryw := { Reads counter: db0. (kit waitUntil: [(GateAcceptor held: 'n0') > before]).
  (kit node: 'n0') acceptorState committed epoch < r1 epoch }.
c that: 'read-your-writes: a commit returns after its readers see its root, before its acceptor learnt it'
  is: ryw equals: { 11. true. true }.

Reads step: '(3)'.
"(3) While the acceptor still holds the learning of r1, it publishes the older root it knows (what
 its learning of an older root does after the commit point published a newer one); then it
 learns r1."
older := (kit node: 'n0') acceptorState committed.
((kit node: 'n0') instVarNamed: 'cells') publishCommitted: (PBPublishCommitted root: older).
steps := { (kit node: 'n0') committedRoot key = r1 key. s0 committedEpoch = r1 epoch. older epoch < r1 epoch }.
learnt := GateAcceptor learnt: 'n0'.
GateAcceptor open: 'n0'.
steps := steps , { kit waitUntil: [(GateAcceptor learnt: 'n0') > learnt]. (kit node: 'n0') committedRoot key = r1 key }.
epochs := OrderedCollection new.
1 to: 6 do: [:i | | space |
  space := kit space: (kit ids at: i - 1 \\ 3 + 1).
  (kit db: 'db' on: space coordinator nodeId) run: Reads incr.
  epochs add: (kit ids collect: [:id | (kit space: id) committedEpoch])].
c that: 'never backwards: the readers'' committed root stays at the commit point''s while the acceptor publishes an older root; committedEpoch is monotonic on every node'
  is: { steps. (1 to: 3) allSatisfy: [:k | (2 to: epochs size) allSatisfy: [:j | ((epochs at: j) at: k) >= ((epochs at: j - 1) at: k)]] }
  equals: { #(true true true true true). true }.

Reads step: '(4)'.
"(4) n1 and n2 cannot talk; n0 talks to both. n2's newDatabase: and its done never reach n1; n1's
 acceptor is held at the learning of each of its own commits (opened before its next one: a
 replication waits for the holder's own acceptance)."
kit network partition: #(#('n0' 'n2') #('n0' 'n1')).
GateAcceptor close: 'n1'.
(kit space: 'n2') newDatabase: 'from-n2'.
(kit space: 'n1') newDatabase: 'from-n1'.
out := { (kit space: 'n1') listDatabases includes: 'from-n2' }.
GateAcceptor open: 'n1'.
(kit space: 'n2') newDatabase: 'from-n2-again'.
GateAcceptor close: 'n1'.
db1 run: [:t | t setRootObject: '_read_barrier' value: true].
out := out , { (kit space: 'n1') listDatabases includes: 'from-n2-again' }.
GateAcceptor open: 'n1'.
kit network heal.
c that: 'CC9: a database made on one node is visible on another after that node''s own barrier commit (newDatabase:, run: writing _read_barrier)'
  is: out equals: #(true true).

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
c that: 'storage root reads never make reads go backwards: a cut-off node reads its stale committed root, then the next commit''s'
  is: { stale. kit waitUntil: [(Reads counter: db1) = (v + 4)]. (s1 openDatabase: 'db') history first version = (db0 history first version) }
  equals: { v. true. true }.

Reads step: '(6)'.
"(6) and (7): ten restarts of n0; on every other one n1 commits while n0 is down."
firsts := OrderedCollection new.
lastRead := s0 _snapshotRecord epoch.
1 to: 10 do: [:i | | space |
  kit down: 'n0'.
  i odd ifTrue: [(kit db: 'db' on: 'n1') run: Reads incr].
  clusterEpoch := (kit space: 'n1') committedEpoch.
  kit up: 'n0'.
  space := kit open: 'n0'.
  rec := space _snapshotRecord.
  firsts add: { rec epoch >= clusterEpoch. rec epoch >= lastRead }.
  lastRead := rec epoch.
  db0 := space openDatabase: 'db'.
  lastRead := lastRead max: space _snapshotRecord epoch].
c that: 'L18: a node restarted after missing commits reads at or above the newest root the cluster committed, before any commit of its own'
  is: (firsts allSatisfy: [:x | x first]) equals: true.
c that: 'a snapshot never goes backwards across ten restarts'
  is: (firsts allSatisfy: [:x | x last]) equals: true.

Reads step: '(8)'.
"(8) Every node accepted r1. With n0 and n1 unable to talk (n2 talks to both), n0 commits R with
 n2; n1 learns R committed from n2's recovery answer only (no replicate nor release of R reaches
 it, so its accepted root stays r1). n0 and n2 lose their logs while the partition holds; forced,
 they rejoin with n1's r1. forceRejoin on n1, the survivor, drops R."
db0 := (kit space: 'n0') openDatabase: 'db'.
db0 run: Reads incr.
v := Reads counter: db0.
r1 := (kit node: 'n0') committedRoot.
kit waitUntil: [kit ids allSatisfy: [:id | | a | a := (kit node: id) acceptorState accepted. a notNil and: [a key = r1 key]]].
kit network partition: #(#('n0' 'n2') #('n1' 'n2')).
db0 run: [:t | t setRootObject: 'counter' value: 1000].
rootR := (kit node: 'n0') committedRoot.
n1 := kit node: 'n1'.
kit waitUntil: [| a | a := (kit node: 'n2') acceptorState committed. a notNil and: [a key = rootR key]].
kit settle: (n1 _want: [:token :s | PBRecoverWanted every: false waiter: token] kind: #recover).
kit waitUntil: [| a | a := n1 acceptorState. a committed notNil and: [a committed key = rootR key]].
acc := { n1 acceptorState committed key = rootR key. n1 acceptorState accepted key = r1 key. n1 committedRoot key = rootR key }.
#('n0' 'n2') do: [:id | kit down: id].
kit network heal.
#('n0' 'n2') do: [:id |
  (kit dir / 'cluster' / (id , '.roots')) renameTo: id , '.roots.lost'.
  kit up: id.
  kit open: id].
#('n0' 'n2') do: [:id | (kit node: id) forceRejoin].
kit waitUntil: [#('n0' 'n2') allSatisfy: [:id | ((kit node: id) stats at: 'rejoining') not]].
n1 forceRejoin.
kit waitUntil: [n1 acceptorState committed isNil].
notes := SeamSpace notes size.
out := { n1 acceptorState needsConfirmation. n1 committedRoot isNil or: [n1 committedRoot key ~= rootR key] }.
rec := (kit space: 'n1') _snapshotRecord.
out := out , { (Reads notesAfter: notes prefix: 'n1 confirm') size >= 1. rec notNil and: [rec pointer ~= rootR record pointer].
  Reads counterIn: (kit space: 'n1') }.
c that: 'I2: after forceRejoin on the survivor, its readers no longer read the dropped root R, and its next snapshot confirms first and does not start from R'
  is: { acc. out } equals: { #(true true true). { true. true. true. true. v } }.
kit shutdown.

Reads step: '(9)'.
"(9) A cluster that ran before, restarted with only n0's space open."
kit := CommitKit ids: #('n0' 'n1' 'n2') dir: base / 'majority' options: (opts value: 3000).
kit openAll.
((kit space: 'n0') newDatabase: 'db') run: [:t | t setRootObject: 'counter' value: 0].
kit shutdown.
kit start.
notes := SeamSpace notes size.
lonely := kit open: 'n0'.
dbL := lonely openDatabase: 'db'.
out := { (Reads notesAfter: notes prefix: 'n0 warn') collect: [:x |
    { x includesSubstring: 'Confirming the committed root'. x includesSubstring: 'could not obtain a write permission' }].
  kit ids allSatisfy: [:id | ((kit node: id) stats at: 'grants_given') = 0].
  #('n1' 'n2') allSatisfy: [:id | ((kit node: id) stats at: 'grants_refused_no_storage') >= 1].
  [dbL run: Reads incr retries: 0. #committed] on: PBTimeoutError do: [:e | e return: #timeout] }.
notes := SeamSpace notes size.
kit open: 'n1'.
out := out , { Reads run: (kit db: 'db' on: 'n1') retries: 5. Reads run: dbL retries: 5.
  (Reads notesAfter: notes prefix: 'n0 warn') , (Reads notesAfter: notes prefix: 'n1 warn'). Reads counter: dbL }.
c that: 'a space opened while no majority has a space gets no permission until one does'
  is: out equals: { #(#(true true)). true. true. #timeout. #ok. #ok. #(). 2 }.
kit shutdown.

Reads step: '(10)'.
"(10) The same restart: n0's confirmation waits for a permission until n1 opens its space."
kit := CommitKit ids: #('n0' 'n1' 'n2') dir: base / 'majority' options: (opts value: 30000).
notes := SeamSpace notes size.
lonely := kit open: 'n0'.
f := Opener new asActor counterIn: lonely.
done := Atom on: false.
f thenDo: [:x | done swap: [:o | true]]; catch: [:e | done swap: [:o | true]].
waited := { kit waitUntil: [#('n1' 'n2') allSatisfy: [:id | ((kit node: id) stats at: 'grants_refused_no_storage') >= 1]].
  done value not }.
kit open: 'n1'.
out := { kit settle: f. Reads run: (kit db: 'db' on: 'n1') retries: 5. Reads run: (lonely openDatabase: 'db') retries: 5.
  (Reads notesAfter: notes prefix: 'n0 warn') , (Reads notesAfter: notes prefix: 'n1 warn'). Reads counterIn: lonely }.
c that: 'a confirmation in progress succeeds once a majority opens its spaces'
  is: { waited. out } equals: { #(true true). { 2. #ok. #ok. #(). 4 } }.
kit shutdown.

Reads step: '(11)'.
"(11)"
kit := DropKit ids: #('n0' 'n1' 'n2') dir: base / 'drop' options: (opts value: 8000).
kit openAll.
DropEndpoint arm.
r := [(kit space: 'n0') newDatabase: 'db'. #created] on: PBConflictError do: [:e |
  e return: (e messageText includesSubstring: 'witnesses needed answered the recovery query')].
out := { r. kit waitUntil: [DropEndpoint dropped size = 2]. DropEndpoint dropped asSortedCollection asArray.
  (kit space: 'n0') listDatabases }.
r := nil.
1 to: 5 do: [:i | r isNil ifTrue: [
  r := [(kit space: 'n0') newDatabase: 'db'. #created] on: PBConflictError do: [:e | e return: nil]]].
((kit space: 'n0') openDatabase: 'db') run: [:t | t setRootObject: 'counter' value: 0].
out := out , { r. Reads run: ((kit space: 'n0') openDatabase: 'db') retries: 5. (kit space: 'n0') listDatabases.
  Reads counterIn: (kit space: 'n0') }.
c that: 'a setup newDatabase: whose recovery query goes unanswered conflicts, creates nothing, and its retry creates the database once'
  is: out equals: { true. true. #('n1' 'n2'). #(). #created. #ok. #('db'). 1 }.
kit shutdown.

base deleteAll.
c report.
