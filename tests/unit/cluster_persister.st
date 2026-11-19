"EXPECT: ok 9"
"The persister, persistedEpoch and sync: (cluster plan Task 25; cluster/persister.st, space.st,
 PBSharedTier persist:, PBRoundRunner persist:; proto_db cluster/persister.py and transactions.py
 sync and persisted_epoch at v2.0.0rc4). Real coordinators over one PBInProcessNetwork, each node
 a space over its own cluster-mode storage of one shared directory (_cluster_commit.st,
 _cluster_persist.st). Every wait is a condition with a deadline of 20 s, or a Future settled
 within 40 s; no duration is asserted, and every overlap is forced by a seam, never by a race. The
 kits run with persistLag 600 s, so a node writes only the roots it committed, except in (7).
 (1) After commits on every node and sync: 10000 on the last committer, space.root holds the
 root that node committed: the root the read path reads back (PBSharedTier readPersisted, what
 Task 24's snapshot reads when recovery fails) is the node's committed root, label, epoch and
 pointer; no storage holds the root lock.
 (2) The checklist row: persistedEpoch >= committedEpoch >= the commits (an epoch floor, rc4:
 a base re-commit adds an epoch), the persisted counter is exact, and only the persisters
 publish space.root (persistence::test_commits_are_persisted_asynchronously_and_sync_waits_for_them).
 (3) The checklist row: sync: on the last committer, both epochs, the persisted value without the
 cluster's reads, and the next transaction on another node starts at its committedEpoch
 (transactions::test_sync_waits_for_the_persisted_epoch_and_exposes_both_epochs).
 (4) Never backwards (CC19, rc4's shape): with n0's write of R1 held, n0 commits R2; n1, which
 knows R2 committed and did not commit it, writes nothing over two passes of its persister (only
 the committer writes before persistLag, D44); n1's round runner then persists R2 first (the
 tier's persist: on n1's one writer); the tier refuses R1 and R2 again; released, n0's persister
 is refused (roots_behind), reads R2 back, and space.root stays R2.
 (5) sync: while another holder keeps the root lock ends PBTimeoutError naming the persisted
 epoch, each attempt #busy; once released, sync: returns.
 (6) One writer per storage (Task 21 review I1): a commit's pushAtom: is held in progress on n0's
 round runner (GateStorage) while n0's persister is made to write; the write waits behind it on
 the runner, so afterwards n0's storage holds no root lock, the persister counted no error, and a
 later persist (sync:) succeeds. Every step after the release runs bounded (Persist within:do:):
 a root lock kept by a write made beside the commit's shows up as a failed check, never a hang.
 (7) A stopped node's commit (its own persister's write dropped, waited for before it stops) is persisted by another node
 after persistLag (200 ms here): sync: on that node returns and space.root reaches the commit
 (outcome only).
 (8) The checklist row: an unexpected persister failure (a plain Error in every pass of n2's
 persister) stops persisting on n2 only: unhealthy, not persisting, not fenced, the failure named;
 with n1 cut off n2 still accepts and acquires, and n2's sync: fails at once with
 PBUnexpectedError naming the persister
 (durability::test_an_unexpected_persister_failure_stops_persisting_but_not_voting).
 (9) The checklist row: sync: promises local persistence only. n2 drops every message that would
 tell it of another member's commit unprompted (MuteEndpoint) and no persister writes (so n2's
 refresh cannot learn a newer persisted root either): after n0's commit, n2's sync: returns at
 its own knowledge and n2 still reads the old value; a commit that writes nothing (a run: of an
 empty block, a bare commit) teaches it nothing; a barrier commit on n2 that writes reads every
 acknowledged commit
 (transactions::test_sync_promises_local_persistence_and_a_commit_on_the_reader_sees_every_acknowledged_commit)."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_cluster_commit'.
Import from: '_cluster_persist'.

| c base kit out r1 r2 holder hold push w runnerN1 written publishes e epoch tr accepted s mark n1Writes n1Mark cycles |
c := Check new.
base := FileSystem temp / ('pbst-cluster-persister-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
SeamRound setUp.
SeamSpace setUp.
PersistSeams setUp.

Persist step: '(1)-(3)'.
kit := Persist kitDir: base / 'a' lag: 600000.
kit openAll.
kit ids do: [:id | (kit storage: id) trace: (Atom on: #())].
s := Persist create: kit on: 'n0' counter: 0.
"12 commits over the three nodes, n2 last."
out := (Persist commits: 12 over: #('n0' 'n1' 'n2') kit: kit) copyWith: s.
r1 := Persist sync: (kit space: 'n2') within: 10000.
r2 := (kit space: 'n2') _tier readPersisted.
c that: 'after commits and sync: 10000, space.root holds the root the node committed, as the read path reads it back'
  is: { out asSet asArray. r1. r2 key = (kit node: 'n2') committedRoot key. r2 epoch = (kit space: 'n2') committedEpoch.
    r2 label = (kit node: 'n2') committedRoot label. r2 record version.
    kit ids collect: [:id | (kit storage: id) holdsRootLock] }
  equals: { #(#ok). nil. true. true. true. 4. #(false false false) }.

written := (kit ids collect: [:id | (kit space: id) _persister stats at: 'roots_written']) inject: 0 into: [:a :b | a + b].
publishes := (kit ids collect: [:id | ((kit storage: id) instVarNamed: 'trace') value count: [:x | x = 'publish']])
  inject: 0 into: [:a :b | a + b].
c that: 'commits are persisted asynchronously and sync: waits for them: persistedEpoch >= committedEpoch >= 14, the persisted counter is 12, and only the persisters publish space.root'
  is: { (kit space: 'n2') persistedEpoch >= (kit space: 'n2') committedEpoch. (kit space: 'n2') committedEpoch >= 14.
    Persist persistedCounterIn: base / 'a'. written > 0. publishes = written.
    kit ids allSatisfy: [:id | ((kit space: id) _persister stats at: 'errors') = 0] }
  equals: { true. true. 12. true. true. true }.

"(3) 5 more commits, n1 last; sync: on n1."
out := Persist commits: 5 over: #('n2' 'n1' 'n0') kit: kit.
r1 := Persist sync: (kit space: 'n1') within: 10000.
epoch := (kit space: 'n1') committedEpoch.
r2 := kit waitUntil: [(kit space: 'n0') committedEpoch >= epoch].
tr := (kit space: 'n0') openDatabase: 'db'.
tr := tr newTransaction.
s := tr _spaceRoot clusterEpoch = (kit space: 'n0') committedEpoch.
tr abort.
c that: 'sync: waits for the persisted epoch and exposes both epochs'
  is: { out asSet asArray. r1. (kit space: 'n1') persistedEpoch >= epoch. epoch >= 19. Persist persistedCounterIn: base / 'a'.
    r2. s.
    [PBObjectSpace storage: (PBFileStorage path: (base / 'a') pathString). #opened] on: PBNotSupportedError do: [:x | x return: #refused] }
  equals: { #(#ok). nil. true. true. 17. true. true. #refused }.

Persist step: '(4)'.
"(4) n0's next write is held; n0 commits R1, then R2; n1's round runner persists R2 first."
n1Writes := [| st | st := (kit space: 'n1') _persister stats. (st at: 'roots_written') + (st at: 'roots_behind')].
n1Mark := n1Writes value.
hold := Future new.
mark := PersistSeams notes size.
PersistSeams holdWritesOf: 'n0' until: hold.
out := { Persist run: (kit db: 'db' on: 'n0') retries: 3 }.
r1 := (kit node: 'n0') committedRoot.
out := out , { kit waitUntil: [PersistSeams noted: 'n0 write held' after: mark] }.
out := out , { Persist run: (kit db: 'db' on: 'n0') retries: 3 }.
r2 := (kit node: 'n0') committedRoot.
out := out , { kit waitUntil: [| x | x := (kit node: 'n1') committedRoot. x notNil and: [x key = r2 key]] }.
cycles := (kit space: 'n1') _persister stats at: 'cycles'.
out := out , { kit waitUntil: [((kit space: 'n1') _persister stats at: 'cycles') >= (cycles + 2)]. n1Writes value - n1Mark }.
runnerN1 := (kit space: 'n1') instVarNamed: 'runner'.
out := out , { kit settle: (runnerN1 persist: r2). kit settle: (runnerN1 persist: r1). kit settle: (runnerN1 persist: r2) }.
hold resolve: true.
out := out , { kit waitUntil: [((kit space: 'n0') _persister stats at: 'roots_behind') >= 1].
  kit waitUntil: [(kit space: 'n0') _persister persistedRoot key = r2 key] }.
c that: 'the persister never goes backwards: a higher root persisted first refuses the lower one, and the equal one; before persistLag only the committer writes'
  is: out , { (kit space: 'n0') _tier readPersisted key = r2 key. (PBRootOrder compare: r2 with: r1) }
  equals: #(#ok true #ok true true 0 true false false true true true 1).

Persist step: '(5)'.
"(5) Another holder keeps the root lock."
holder := PBFileStorage clusterPath: (base / 'a') pathString.
out := { holder tryLockRoot. Persist run: (kit db: 'db' on: 'n0') retries: 3 }.
e := [(kit space: 'n0') sync: 500. nil] on: Error do: [:x | x return: x class name , ': ' , x messageText].
out := out , { e notNil and: [(e beginsWith: 'PBTimeoutError: ') and: [e includesSubstring: 'The persisted epoch is']].
  ((kit space: 'n0') _persister stats at: 'roots_busy') >= 1.
  (kit space: 'n0') persistedEpoch < (kit space: 'n0') committedEpoch }.
holder unlockRoot.
holder close.
out := out , { Persist sync: (kit space: 'n0') within: 10000. (kit space: 'n0') persistedEpoch >= (kit space: 'n0') committedEpoch }.
c that: 'sync: with the root lock held by a peer ends PBTimeoutError, then returns once it is released'
  is: out equals: #(true #ok true true true nil true).

Persist step: '(6)'.
"(6) n0's persister holds its next write; n0 commits R1 (its write held); a commit's pushAtom:
 is then held in progress on n0's round runner, and only then n0's persister writes R1."
hold := Future new.
mark := PersistSeams notes size.
PersistSeams holdWritesOf: 'n0' until: hold.
out := { Persist run: (kit db: 'db' on: 'n0') retries: 3. kit waitUntil: [PersistSeams noted: 'n0 write held' after: mark] }.
push := Future new.
(kit storage: 'n0') gatePushes: push.
w := Worker new asActor once: (kit db: 'db' on: 'n0')
  block: [:t | t setRootObject: 'counter' value: (t getRootObject: 'counter') + 1. t setRootObject: 'note' value: t newList]
  retries: 20.
out := out , { kit waitUntil: [PersistSeams noted: 'n0 push gated' after: mark] }.
hold resolve: true.
out := out , { kit waitUntil: [PersistSeams noted: 'n0 write sent' after: mark] }.
out := out , { PersistSeams noted: 'n0 push released' after: mark }.
push resolve: true.
out := out , { (kit settle: w) first }.
out := out , { kit waitUntil: [(kit space: 'n0') persistedEpoch >= (kit node: 'n0') committedEpoch].
  (kit storage: 'n0') holdsRootLock. (kit space: 'n0') _persister stats at: 'errors'.
  Persist within: 30000 do: [Persist run: (kit db: 'db' on: 'n0') retries: 3].
  Persist within: 15000 do: [Persist sync: (kit space: 'n0') within: 10000]. (kit storage: 'n0') holdsRootLock.
  (kit space: 'n0') _persister stats at: 'errors' }.
c that: 'one writer per storage: a persist made while a commit write is in progress on the node waits behind it, the root lock is released, and a later persist succeeds'
  is: out equals: #(#ok true true true false #ok true false 0 #ok nil false 0).
Persist within: 60000 do: [kit shutdown].

Persist step: '(7)'.
"(7) persistLag 200 ms; n0's writes are dropped; n0 commits, then stops."
kit := Persist kitDir: base / 'b' lag: 200.
kit openAll.
PersistSeams dropWrites: #('n0').
s := Persist create: kit on: 'n0' counter: 41.
r1 := (kit node: 'n0') committedRoot.
out := { s. kit waitUntil: [#('n1' 'n2') allSatisfy: [:id | (kit node: id) committedEpoch >= r1 epoch]].
  "n0's persister has tried to write its commit (and was dropped) before n0 stops: its low band
   pass runs one persistInterval after the commit, so it is waited for, never assumed."
  kit waitUntil: [PersistSeams noted: 'n0 write dropped'] }.
kit down: 'n0'.
PersistSeams dropWrites: #().
out := out , { Persist sync: (kit space: 'n1') within: 10000. Persist sync: (kit space: 'n2') within: 10000.
  (PBRootOrder compare: (Persist persistedIn: base / 'b') with: r1) >= 0. Persist persistedCounterIn: base / 'b' }.
c that: 'a stopped node''s commits are persisted by another node after persistLag'
  is: out equals: #(#ok true true nil nil true 41).
kit shutdown.

Persist step: '(8)'.
kit := Persist kitDir: base / 'c' lag: 600000.
kit openAll.
s := Persist create: kit on: 'n0' counter: 0.
PersistSeams breakPasses: #('n2').
out := { s. Persist run: (kit db: 'db' on: 'n0') retries: 3. kit waitUntil: [((kit node: 'n2') stats at: 'healthy') not] }.
s := (kit node: 'n2') stats.
out := out , { (s at: 'failure') notNil and: [(s at: 'failure') includesSubstring: 'upload queue corrupted'].
  s at: 'healthy'. s at: 'persisting'. s at: 'fenced'. kit waitUntil: [(kit space: 'n2') _persister isRunning not] }.
kit network partition: #(#('n0' 'n2') #('n1')).
accepted := (kit node: 'n2') stats at: 'accepted'.
out := out , { Persist run: (kit db: 'db' on: 'n0') retries: 3. ((kit node: 'n2') stats at: 'accepted') > accepted.
  Persist run: (kit db: 'db' on: 'n2') retries: 3. kit waitUntil: [(Persist counterIn: (kit space: 'n0')) = 3] }.
e := [(kit space: 'n2') sync: 5000. nil] on: Error do: [:x | x return: x class name , ': ' , x messageText].
out := out , { e notNil and: [(e beginsWith: 'PBUnexpectedError: ') and: [e includesSubstring: 'persister failed']] }.
PersistSeams breakPasses: #().
kit network heal.
c that: 'an unexpected persister failure stops persisting but not voting'
  is: out equals: #(#ok #ok true true false false false true #ok true #ok true true).
kit shutdown.

Persist step: '(9)'.
kit := Persist kitDir: base / 'd' lag: 600000.
kit openAll.
out := { Persist create: kit on: 'n0' counter: 0. Persist run: (kit db: 'db' on: 'n0') retries: 3.
  kit waitUntil: [(Persist counterIn: (kit space: 'n2')) = 1] }.
out := out , (kit ids collect: [:id | Persist sync: (kit space: id) within: 10000]).
out := out , { kit waitUntil: [(kit node: 'n2') nodeState ownership isNil] }.
MuteEndpoint arm: true.
PersistSeams dropWrites: kit ids.
out := out , { Persist run: (kit db: 'db' on: 'n0') retries: 3. Persist sync: (kit space: 'n2') within: 5000.
  Persist counterIn: (kit space: 'n2') }.
out := out , { [(kit db: 'db' on: 'n2') run: [:t | nil] retries: 3. (kit db: 'db' on: 'n2') newTransaction commit. #ok]
    on: Error do: [:x | x return: x class name].
  Persist counterIn: (kit space: 'n2') }.
out := out , { [(kit db: 'db' on: 'n2') run: [:t | t setRootObject: 'barrier' value: ((t getRootObject: 'barrier') ifNil: [0]) + 1]
      retries: 3. #ok] on: Error do: [:x | x return: x class name].
  Persist counterIn: (kit space: 'n2'). MuteEndpoint muted notEmpty }.
MuteEndpoint arm: false.
PersistSeams dropWrites: #().
c that: 'sync: promises local persistence, and a commit on the reader sees every acknowledged commit'
  is: out equals: #(#ok #ok true nil nil nil true #ok nil 1 #ok 1 #ok 2 true).
kit shutdown.

base deleteAll.
c report displayNl.
