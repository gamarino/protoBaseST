"EXPECT: ok 10"
"Commits through the coordinator (cluster plan Task 23; cluster/round.st PBClusterRound over the
 core's round:in:now:, round.st, transactions.st run:). Real coordinators over one
 PBInProcessNetwork, each node a space over its own cluster-mode storage of one shared directory.
 Every wait is a condition with a deadline of 60 s (or a Future settled within 120 s); no
 duration is asserted. Seams (_cluster_commit.st) stop or gate one step of one node's round.
 (1) One node: newDatabase: and five commits count critical_commits 6, with build and
 replication seconds (proto_db transactions::test_commits_under_a_single_node_cluster).
 (2) A base with the snapshot's epoch but another root is validated, not taken as the snapshot
 (durability::test_a_base_with_the_snapshot_epoch_but_another_root_is_validated): the build
 compares the record's pointer, never its epoch. (3) R231, the Task 22b carry-over: a build whose
 write poisoned the tier after its permission expired keeps its PBUnexpectedError (the shell
 reads the storage's isFailed when the failure is observed; the HidesTierFailure plant, a shell
 that always says false, turns it into a retryable conflict). (4) D-LIVE-2 held retries and R148:
 two commits of one node in one round on one key: the second conflicts, is held (permitHeld)
 and its run: retries at once and finishes; every permit of that node follows the done of the
 permission before it. (5) Three nodes, two workers each, 100 run: increments of one counter:
 the counter is 100, every run: finished, none unknown. (6) Every node's committed root holds
 the commits of every node. (7) L11: the records of every replicated root were flushed to the
 shared storage before its replicate left the node, and no cluster commit published a root
 under them (space.root untouched) (durability::test_a_holder_never_ships_own_records_it_has_not_
 made_durable_locally, transactions::test_records_reach_the_storage_before_the_replication_and_
 no_root_is_published_under_it). (8) CC18: a build longer than the belief never commits; run:
 ends, after its retries, in PBConflictError naming leaseDuration. (9) A holder paused past its
 lease between the core's check and the send never replicates: the node refuses the stale
 permission, #none, a retryable conflict, nothing committed
 (transactions::test_a_holder_paused_past_its_lease_never_replicates). (10) The commit point is
 the majority acknowledgement: with one node stopped a commit still commits (two of three), and
 with two stopped a first commit ends unknown or in PBTimeoutError, and the next in PBTimeoutError naming
 acquireTimeout's bound, with no sleep
 (transactions::test_the_commit_point_is_the_majority_acknowledgement; rc4 R148's text)."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_cluster_commit'.

| c base kit one space db r st seam tr rec1 rec2 sr ptr workers results w1 w2 counters tokens out before
  prefixes cm first |
c := Check new.
base := FileSystem temp / ('pbst-cluster-commit-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
SeamRound setUp.

"--- one node -------------------------------------------------------------"
one := CommitKit ids: #('s0') dir: base / 'one'
  options: (Dictionary new at: #leaseDuration put: 3000; at: #driftMargin put: 2000; at: #requestTimeout put: 300; yourself).
space := one open: 's0' segmentMaxBytes: 256.
one waitUntil: [((one node: 's0') stats at: 'rejoining') not].
db := space newDatabase: 'db'.
db run: [:t | t setRootObject: 'counter' value: 0. t setRootObject: 'tokens' value: PBDictionary new].
1 to: 4 do: [:i | db run: (CommitKit incr: 's0-' , i printString tag: 's0')].
st := (one node: 's0') stats.
"(1)"
c that: 'one node: newDatabase and five commits count critical_commits 6, build and replication seconds summed'
  is: { st at: 'critical_commits'. ((st at: 'critical') at: 'build') > 0. ((st at: 'critical') at: 'replication') > 0.
    (db run: [:t | t getRootObject: 'counter']) }
  equals: { 6. true. true. 4 }.

"(2)"
rec1 := space _snapshotRecord.
sr := space _spaceRootAt: rec1.
tr := db newTransaction.
tr setRootObject: 'counter' value: (tr getRootObject: 'counter') + 1.
r := (sr databases getAt: 'db').
ptr := space storage save: (PBSpaceRoot databases: (sr databases setAt: 'db' value: (PBDatabaseRoot objects: (r objects setAt: 'counter' value: 99)
    mutables: r mutables version: r version + 1 committedAt: r committedAt origin: r origin previous: r))
  term: 1 epoch: rec1 epoch previous: sr).
rec2 := PBRootRecord segment: ptr segmentBytes offset: ptr offset epoch: rec1 epoch.
(tr instVarNamed: 'bookkeeping') swap: [:x | x withState: #committing].
c that: 'a base with the snapshot''s epoch but another root is validated (a conflict); the snapshot itself is not'
  is: { [tr _buildOn: rec2 stamp: { 1. rec1 epoch + 1 }. #built] on: PBConflictError do: [:e | e return: #conflict].
    [(tr _buildOn: rec1 stamp: { 1. rec1 epoch + 1 }) clusterEpoch] on: Error do: [:e | e return: e class name] }
  equals: { #conflict. rec1 epoch + 1 }.
(tr instVarNamed: 'bookkeeping') swap: [:x | x withState: #aborted].

"(3) the build sleeps past the belief (1000 ms), then its storage creates a segment and fails."
seam := SeamRound seamOf: 's0'.
seam buildDelay swap: [:x | 1300].
seam poison swap: [:x | one storage: 's0'].
w1 := Worker new asActor.
r := one settle: (w1 once: db block: (CommitKit incr: 's0-poison' tag: 's0') retries: 0).
c that: 'R231: a build whose write poisoned the tier after the permission expired keeps its PBUnexpectedError'
  is: { r first. r at: 2. (one storage: 's0') isFailed }
  equals: { #error. #PBUnexpectedError. true }.
one shutdown.

"--- three nodes ----------------------------------------------------------"
kit := CommitKit ids: #('n0' 'n1' 'n2') dir: base / 'three'
  options: (Dictionary new at: #leaseDuration put: 3000; at: #driftMargin put: 2000; at: #requestTimeout put: 300;
    at: #acquireTimeout put: 8000; yourself).
kit openAll.
kit ids do: [:id | (kit storage: id) trace: (SeamRound seamOf: id) trace].
db := kit space: 'n0'.
db := db newDatabase: 'db'.
db run: [:t | t setRootObject: 'counter' value: 0. t setRootObject: 'tokens' value: PBDictionary new].

"(4) the first permit of n0 waits for the gate, so both commits join its round."
seam := SeamRound resetSeamOf: 'n0'.
(kit storage: 'n0') trace: seam trace.
seam permitGate swap: [:x | Future new].
before := seam permitGate value.
w1 := Worker new asActor.
w2 := Worker new asActor.
results := { w1 once: db block: (CommitKit incr: 'h-1' tag: 'h') retries: 5. w2 once: db block: (CommitKit incr: 'h-2' tag: 'h') retries: 5 }.
kit waitUntil: [| rs | rs := (SeamRound roundOf: 'n0') roundState. rs batch size + rs queue size = 2].
before resolve: true.
results := results collect: [:f | kit settle: f].
"Then a commit queued while a round replicates (its answer gated): the permission ends with a
 done and the queue asks the next permit in the same step (R148: the done first)."
seam answerGate swap: [:x | Future new].
before := seam answerGate value.
out := { w1 once: db block: (CommitKit incr: 'g-1' tag: 'g') retries: 5 }.
kit waitUntil: [(seam calls: #('answer held' 'replicate')) size >= 1 and: [(seam calls: #('permit')) size = 1
  and: [(SeamRound roundOf: 'n0') roundState phase = #replicate]]].
out := out , { w2 once: db block: (CommitKit incr: 'g-2' tag: 'g') retries: 5 }.
kit waitUntil: [(SeamRound roundOf: 'n0') roundState queue size = 1].
before resolve: true.
out := out collect: [:f | kit settle: f].
c that: 'D-LIVE-2: the second commit of a round on one key is held, retried at once, and finishes; R148: each permit after the done before it'
  is: { results collect: [:x | x first]. out collect: [:x | x first]. seam held value >= 1. (seam calls: #('permit')) size >= 2.
    seam doneBeforeEachPermit }
  equals: { #(#ok #ok). #(#ok #ok). true. true. true }.

"(5)"
prefixes := #('a0' 'b0' 'a1' 'b1' 'a2' 'b2').
workers := prefixes collect: [:p | Worker new asActor].
results := (1 to: 6) collect: [:i |
  (workers at: i) increments: (kit db: 'db' on: (kit ids at: i + 1 // 2)) count: (i <= 4 ifTrue: [17] ifFalse: [16])
    prefix: (prefixes at: i) retries: 60].
results := results collect: [:f | kit settle: f].
c that: 'three nodes, six workers, 100 run: increments: every run: acknowledged, none unknown, no other error'
  is: { (results inject: 0 into: [:n :x | n + x first size]). (results inject: 0 into: [:n :x | n + (x at: 2) size]).
    (results inject: #() into: [:n :x | n , (x at: 3)]) }
  equals: { 100. 0. #() }.

"(6)"
c that: 'every node''s committed root holds the commits of every node: the counter is 104 (100 and the four of (4))'
  is: (kit waitUntil: [kit ids allSatisfy: [:id | | root |
      root := kit committedSpaceRoot: id.
      root notNil and: [(kit root: 'counter' of: 'db' in: root) = 104 and: [
        prefixes allSatisfy: [:p | (kit root: 'tokens' of: 'db' in: root) has: p , '-1']]]]])
  equals: true.

"(7)"
c that: 'L11: every replicate of every node follows the flush of its records; no cluster commit publishes space.root'
  is: (kit ids collect: [:id | | s | s := SeamRound seamOf: id.
    { (s calls: #('replicate')) notEmpty or: [id ~= 'n0']. s flushedBeforeEachReplicate. (s calls: #('publish')) size }])
  equals: { { true. true. 0 }. { true. true. 0 }. { true. true. 0 } }.

"(8)"
seam := SeamRound resetSeamOf: 'n1'.
seam buildDelay swap: [:x | 1300].
w1 := Worker new asActor.
r := kit settle: (w1 once: (kit db: 'db' on: 'n1') block: (CommitKit incr: 'slow' tag: 'slow') retries: 1).
c that: 'CC18: a build longer than the belief ends, after its retries, in PBConflictError naming leaseDuration'
  is: { r first. r at: 2. ((r at: 3) includesSubstring: 'leaseDuration'). ((r at: 3) includesSubstring: 'Nothing was replicated') }
  equals: { #error. #PBConflictError. true. true }.
seam buildDelay swap: [:x | nil].

"(9) the send waits for a gate the test opens once the permission is no longer valid."
seam := SeamRound resetSeamOf: 'n2'.
(kit storage: 'n2') trace: seam trace.
seam pauseSend swap: [:x | Future new].
before := seam pauseSend value.
w1 := Worker new asActor.
out := w1 once: (kit db: 'db' on: 'n2') block: (CommitKit incr: 'paused' tag: 'paused') retries: 0.
kit waitUntil: [(seam calls: #('send paused')) notEmpty].
st := (SeamRound roundOf: 'n2') roundState permission.
kit waitUntil: [(st isValidAt: (kit node: 'n2') _now) not].
before resolve: true.
r := kit settle: out.
c that: 'a holder paused past its lease never replicates: #none, a retryable conflict, nothing committed'
  is: { r first. r at: 2. seam calls: #('send resumed' 'answered none' 'answered committed').
    db run: [:t | (t getRootObject: 'tokens') has: 'paused'] }
  equals: { #error. #PBConflictError. #('send resumed' 'answered none'). false }.

"(10)"
(kit space: 'n2') close.
(kit node: 'n2') stop waitWithin: 60000.
w1 := Worker new asActor.
r := kit settle: (w1 once: db block: (CommitKit incr: 'two-of-three' tag: 'm') retries: 20).
cm := r first.
(kit space: 'n1') close.
(kit node: 'n1') stop waitWithin: 60000.
"rc4's shape: the first one-of-three attempt may still find n0's term owned, replicate and find
 no majority (PBOutcomeUnknownError), time out, or start with less than the send reserve left
 (or as the permission ends), so nothing is sent and, at retries: 0, a PBConflictError surfaces
 (re-review N1). Whatever it answers, it never reaches n0's committed root. The second, the term
 ended, times out."
r := kit settle: (w1 once: db block: (CommitKit incr: 'one-of-three-a' tag: 'm') retries: 0).
first := { r first.
  #(#PBOutcomeUnknownError #PBTimeoutError #PBConflictError) includes: (r at: 2) asSymbol.
  ((db newTransaction getRootObject: 'tokens') has: 'one-of-three-a') }.
r := kit settle: (w1 once: db block: (CommitKit incr: 'one-of-three-b' tag: 'm') retries: 0).
c that: 'the commit point is a majority: two of three commit; one of three ends in PBTimeoutError naming acquireTimeout'
  is: { cm. first. r first. r at: 2. ((r at: 3) includesSubstring: 'within 8000 ms') }
  equals: { #ok. { #error. true. false }. #error. #PBTimeoutError. true }.

kit shutdown.
base deleteAll.
c report.
