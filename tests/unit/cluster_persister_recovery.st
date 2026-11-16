"EXPECT: ok 4"
"Recovery from the persisted root (cluster plan Task 25; cluster/persister.st and Task 24's read
 path; proto_db tests/unit/test_cluster_persistence.py and test_cluster_durability.py at
 v2.0.0rc4, ported to the shared tier: the storage is one directory every node opens, so an
 object-store outage is the persisters' writes dropped (PersistSeams dropWrites:), and a wiped disk
 is the node's acceptor log moved aside, cluster/<id>.roots.lostN; the records stay in the shared
 segments). Real coordinators over one PBInProcessNetwork (_cluster_commit.st,
 _cluster_persist.st). Every wait is a condition with a deadline of 20 s; no duration is asserted.
 (1) Every acceptor log lost after a sync: a cluster restarted over the directory reads the
 persisted root, commits on it, and persists that commit
 (persistence::test_a_restarted_cluster_on_empty_disks_recovers_from_the_object_store).
 (2) A majority of logs lost before the newest commits were persisted, the survivor kept: the
 persisted state is intact, and the operator's forced rejoins recover every commit from the
 survivor (persistence::test_losing_a_majority_before_persistence_loses_only_unpersisted_commits).
 (3) The same loss with the survivor down: the forced quorum refounds from the persisted state
 (the unpersisted commits are lost), and the survivor's newer roots are superseded when it comes
 back (persistence::test_losing_a_majority_with_the_survivor_outside_the_quorum_rolls_back_to_the_persisted_state).
 (4) The same with the survivor partitioned and its persister stopped: the refounded lineage's
 labels are above the dead branch's head, on the survivor and in the log it restarts from
 (durability::test_a_node_restarted_after_a_refound_never_reloads_the_dead_branch)."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_cluster_commit'.
Import from: '_cluster_persist'.

| c base kit dir out ids force start dead r |
c := Check new.
base := FileSystem temp / ('pbst-cluster-persister-recovery-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
SeamRound setUp.
SeamSpace setUp.
PersistSeams setUp.
ids := #('n0' 'n1' 'n2').

"A kit over aDirectory, every space open, 'db' created with counter 0, n commits over the three
 nodes, then sync: on each: { the kit. the commit results. the sync results }."
start := [:aDirectory :n | | k res |
  k := Persist kitDir: aDirectory lag: 600000.
  k openAll.
  res := { Persist create: k on: 'n0' counter: 0 }.
  res := res , (Persist commits: n over: ids kit: k).
  { k. res asSet asArray. ids collect: [:id | Persist sync: (k space: id) within: 10000] }].
"anId revived and forced to rejoin once it is rejoining (the operator's decision, R49)."
force := [:k :anId | | ok |
  k revive: anId.
  ok := k waitUntil: [((k node: anId) stats at: 'rejoining')].
  ok ifTrue: [(k node: anId) forceRejoin].
  ok].

Persist step: '(1)'.
dir := base / 'empty'.
out := start value: dir value: 9.
kit := out first.
out := out allButFirst.
kit shutdown.
ids do: [:id | (dir / 'cluster' / (id , '.roots')) renameTo: id , '.roots.lost1'].
kit := Persist kitDir: dir lag: 600000.
kit openAll.
out := out , { kit waitUntil: [(Persist counterIn: (kit space: 'n1')) = 9].
  (ids inject: 0 into: [:a :id | a + ((kit node: id) stats at: 'storage_root_reads')]) > 0.
  Persist run: (kit db: 'db' on: 'n2') retries: 3. kit waitUntil: [(Persist counterIn: (kit space: 'n0')) = 10].
  Persist sync: (kit space: 'n2') within: 10000. Persist persistedCounterIn: dir }.
c that: 'a cluster restarted with every acceptor log lost recovers from the persisted root'
  is: out equals: #(#(#ok) #(nil nil nil) true true #ok true nil 10).
kit shutdown.

Persist step: '(2)'.
dir := base / 'majority'.
out := start value: dir value: 4.
kit := out first.
out := out allButFirst , { Persist persistedCounterIn: dir }.
PersistSeams dropWrites: ids.
out := out , { (Persist commits: 5 over: #('n0' 'n1') kit: kit) asSet asArray }.
kit wipe: 'n0'.
kit wipe: 'n2'.
kit down: 'n1'.
PersistSeams dropWrites: #().
out := out , { Persist persistedCounterIn: dir }.
kit revive: 'n1'.
out := out , { force value: kit value: 'n0'. kit waitUntil: [((kit node: 'n0') stats at: 'rejoining') not].
  kit waitUntil: [(Persist counterIn: (kit space: 'n1')) = 9] }.
out := out , { force value: kit value: 'n2'. kit waitUntil: [((kit node: 'n2') stats at: 'rejoining') not].
  kit waitUntil: [(Persist counterIn: (kit space: 'n2')) = 9 and: [(Persist counterIn: (kit space: 'n0')) = 9]] }.
out := out , { Persist run: (kit db: 'db' on: 'n2') retries: 3. kit waitUntil: [(Persist counterIn: (kit space: 'n1')) = 10].
  Persist sync: (kit space: 'n1') within: 15000. Persist persistedCounterIn: dir }.
c that: 'losing a majority before persistence loses only unpersisted commits, and the survivor recovers them all'
  is: out equals: #(#(#ok) #(nil nil nil) 4 #(#ok) 4 true true true true true true #ok true nil 10).
kit shutdown.

Persist step: '(3)'.
dir := base / 'outside'.
out := start value: dir value: 4.
kit := out first.
out := out allButFirst.
PersistSeams dropWrites: ids.
out := out , { (Persist commits: 5 over: #('n0' 'n1') kit: kit) asSet asArray }.
kit wipe: 'n0'.
kit wipe: 'n2'.
kit down: 'n1'.
PersistSeams dropWrites: #().
out := out , { force value: kit value: 'n0'. force value: kit value: 'n2'.
  kit waitUntil: [#('n0' 'n2') allSatisfy: [:id | ((kit node: id) stats at: 'rejoining') not]].
  kit waitUntil: [(Persist counterIn: (kit space: 'n0')) = 4].
  Persist run: (kit db: 'db' on: 'n2') retries: 3 }.
kit revive: 'n1'.
out := out , { kit waitUntil: [(Persist counterIn: (kit space: 'n1')) = 5 and: [(Persist counterIn: (kit space: 'n0')) = 5]].
  Persist sync: (kit space: 'n2') within: 15000. Persist persistedCounterIn: dir }.
c that: 'losing a majority with the survivor outside the quorum rolls back to the persisted state'
  is: out equals: #(#(#ok) #(nil nil nil) #(#ok) true true true true #ok true nil 5).
kit shutdown.

Persist step: '(4)'.
dir := base / 'dead'.
out := start value: dir value: 4.
kit := out first.
out := out allButFirst.
PersistSeams dropWrites: ids.
out := out , { (Persist commits: 5 over: #('n0' 'n1') kit: kit) asSet asArray.
  kit waitUntil: [(Persist counterIn: (kit space: 'n1')) = 9] }.
dead := (kit node: 'n1') committedRoot.
kit wipe: 'n0'.
kit wipe: 'n2'.
kit network partition: #(#('n0' 'n2') #('n1')).
out := out , { kit settle: (kit space: 'n1') _persister stop }.
PersistSeams dropWrites: #().
out := out , { force value: kit value: 'n0'. force value: kit value: 'n2'.
  kit waitUntil: [#('n0' 'n2') allSatisfy: [:id | ((kit node: id) stats at: 'rejoining') not]].
  kit waitUntil: [(Persist counterIn: (kit space: 'n0')) = 4].
  Persist run: (kit db: 'db' on: 'n2') retries: 3 }.
kit network heal.
out := out , { Persist run: (kit db: 'db' on: 'n2') retries: 3. kit waitUntil: [(Persist counterIn: (kit space: 'n1')) = 6] }.
r := (kit node: 'n1') committedRoot.
out := out , { r label > dead label. r key ~= dead key }.
kit restart: 'n1'.
r := (kit node: 'n1') committedRoot.
out := out , { r notNil and: [r label > dead label and: [r key ~= dead key]]. Persist counterIn: (kit space: 'n1') }.
c that: 'a node restarted after a refound never reloads the dead branch'
  is: out equals: #(#(#ok) #(nil nil nil) #(#ok) true true true true true true #ok #ok true true true true 6).
kit shutdown.

base deleteAll.
c report displayNl.
