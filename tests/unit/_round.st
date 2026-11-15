"_round.st: the simulator of the commit round and the planted wrong rules of the round scenario
 families (sim_round_rules.st; a helper: the runner never runs files whose name starts with _).
 Test support, not product (CC13): each plant is a subclass overriding one rule method of the
 product rules.

  RoundRules      the product rules (PBCoordinatorCore).
  PlantNoReserve  proto_db plant no_reserve: the round sends its root whatever time is left
                  (the reserve check of R121 dropped from mayReplicate:now:).
  PlantNoKeep     proto_db plant nokeep: a round whose conflicted commits will retry at once
                  ends its permission instead of keeping it for them (D-LIVE-2 lost).
  RoundSim        a PBSim whose nodes commit through the round state machine
                  (PBCoordinatorCore round:in:now:): one PBRoundState per incarnation, the
                  round's effects performed by this shell (PBAskPermit, PBAskBase, PBBuild,
                  PBReplicate, PBReportDone, PBSettle of an entry, the hold PBTimer), each
                  answer handed back to the round as its event; holdsExpired counts the
                  holds of a kept permission that ran out (the timer audit's retryHold row).
  RoundFamilies   the scenario families.

The clients. run:at:hot:builds:retries: is a transaction of a client that retries a conflict up
to n times (Database.run): each attempt is a PBRoundEntry (willRetry while retries are left)
whose snapshot is the newest root its node knows committed when the attempt is enqueued (the
published committed root, or a root this node's rounds learnt committed: a base decided #ok
with no commit needed, a root its replication committed). Its build takes the virtual
microseconds of builds (one per attempt, the last repeated). A hot transaction (a
read-modify-write of one key) conflicts at its build unless the hot key is unchanged since its
snapshot (the base's last hot write is the snapshot's: hotVersionOf:); one made with hot: #always
always conflicts; any other never conflicts (a blind write, which leaves the hot key as it was). A conflict marked permitHeld is retried at once (from the root the permission
committed); another conflict after retryBackoff; PBOutcomeUnknownError and anything else end the
transaction (never retried). loop:at:hot:builds:retries: runs such transactions one after the
other until stopLoops.

Rounds are counted cluster-wide: one per PBAskBase (every round asks for its base). The
fairness measure of D-LIVE-2 (longestGapOf:upTo:) is in those virtual rounds, never in time."

Import from: 'protobase'.
Import from: '_sim'.

"=== The rules ==============================================================="

PBCoordinatorCore subclass: #RoundRules.

RoundRules subclass: #PlantNoReserve.

PlantNoReserve >> mayReplicate: s now: t
  ^ self _belowRejoinBallot: s.

RoundRules subclass: #PlantNoKeep.

PlantNoKeep >> _keep: s hold: someMicros now: t effects: fx
  ^ self _endPermission: s now: t effects: fx.

"=== RoundSim ================================================================"

PBSim subclass: #RoundSim instanceVariableNames: 'rounds txs inRound waiters known started acks baseDelays onReplicate replicates reports settles decisions stopped recommits heldDelay hotVersions expired'.

RoundSim >> rounds
  rounds isNil ifTrue: [rounds := Dictionary new].
  ^ rounds.

RoundSim >> txs
  txs isNil ifTrue: [txs := Dictionary new].
  ^ txs.

RoundSim >> known
  known isNil ifTrue: [known := Dictionary new].
  ^ known.

"{ round index. node id. token. hot } of every acknowledged transaction, in order (hot: its
 hot flag, true for a read-modify-write of the hot key)."
RoundSim >> acks
  acks isNil ifTrue: [acks := OrderedCollection new].
  ^ acks.

"{ node id. permission. root. pred. round index. outcome (nil while pending) } of every
 PBReplicate, in order."
RoundSim >> replicates
  replicates isNil ifTrue: [replicates := OrderedCollection new].
  ^ replicates.

"{ node id. permission. outcome. virtual time } of every PBReportDone, in order."
RoundSim >> reports
  reports isNil ifTrue: [reports := OrderedCollection new].
  ^ reports.

"{ node id. token. attempt. outcome. virtual time. round index } of every entry settled."
RoundSim >> settles
  settles isNil ifTrue: [settles := OrderedCollection new].
  ^ settles.

"{ node id. decision (or error). virtual time } of every base decision handed to a round."
RoundSim >> decisions
  decisions isNil ifTrue: [decisions := OrderedCollection new].
  ^ decisions.

"The keys (keyText:) of the unchanged roots built for re-commits."
RoundSim >> recommits
  recommits isNil ifTrue: [recommits := Set new].
  ^ recommits.

RoundSim >> baseDelays
  baseDelays isNil ifTrue: [baseDelays := Dictionary new].
  ^ baseDelays.

"Rounds started cluster-wide (PBAskBase effects)."
RoundSim >> started
  started isNil ifTrue: [started := 0].
  ^ started.

"The PBRoundState of anId's incarnation."
RoundSim >> roundOf: anId
  ^ self rounds at: anId.

"How long a client waits before retrying a conflict that is not permitHeld (Database.run's
 back-off): 5 ms."
RoundSim >> retryBackoff
  ^ 5000.

"The newest root anId knows committed."
RoundSim >> knownAt: anId
  ^ PBRootOrder max: (self nodeAt: anId) committed with: (self known at: anId ifAbsent: [nil]).

RoundSim >> _know: aRoot at: aNode
  self known at: aNode id put: (PBRootOrder max: (self known at: aNode id ifAbsent: [nil]) with: aRoot).

"The errors aToken's attempts got, in order."
RoundSim >> errorsOf: aToken
  ^ ((self txs at: aToken) at: #errors) asArray.

"How many attempts aToken made."
RoundSim >> attemptsOf: aToken
  ^ (self txs at: aToken) at: #attempt.

"The roots aToken's attempts built, in order."
RoundSim >> rootsOf: aToken
  ^ ((self txs at: aToken) at: #roots) asArray.

"--- the script ---"

"The next base decision asked at anId is asked someMicros later (a round runner slow between its
 permit and its base: a stop of its thread), once."
RoundSim >> delayBase: someMicros at: anId
  self baseDelays at: anId put: someMicros.

"aBlock runs (with the node id) when the next PBReplicate is performed, before it is handed to
 the node; once."
RoundSim >> onReplicate: aBlock
  onReplicate := aBlock.

"Steps every event due at or before aTime (at most n steps), then stands at aTime: unlike
 runUntil:steps:, an idle queue does not carry virtual time to a later event."
RoundSim >> runTo: aTime steps: n
  n timesRepeat: [ | next |
    next := nil.
    queue do: [:e | ((e at: 1) notNil and: [(self _isPaused: (e at: 3)) not and: [next isNil or: [(e at: 1) < next]]]) ifTrue: [next := e at: 1]].
    (next isNil or: [next > aTime]) ifTrue: [now := now max: aTime. ^ self].
    self step].

"No loop client starts a new transaction from now on."
RoundSim >> stopLoops
  stopped := true.

"A transaction aToken of a client at anId (see the module comment)."
RoundSim >> run: aToken at: anId hot: isHot builds: someMicros retries: n
  ^ self run: aToken at: anId hot: isHot builds: someMicros retries: n then: nil.

RoundSim >> run: aToken at: anId hot: isHot builds: someMicros retries: n then: aBlock
  ^ self run: aToken at: anId hot: isHot builds: someMicros retries: n then: aBlock caller: aToken.

"As run:at:hot:builds:retries:, its first attempt queued at aTime (not before now)."
RoundSim >> run: aToken at: anId hot: isHot builds: someMicros retries: n time: aTime
  self run: aToken at: anId hot: isHot builds: someMicros retries: n then: nil caller: aToken time: aTime.

"aCaller: the client (proto_db entry.thread) every attempt of aToken names."
RoundSim >> run: aToken at: anId hot: isHot builds: someMicros retries: n then: aBlock caller: aCaller
  ^ self run: aToken at: anId hot: isHot builds: someMicros retries: n then: aBlock caller: aCaller time: now.

RoundSim >> run: aToken at: anId hot: isHot builds: someMicros retries: n then: aBlock caller: aCaller time: aTime
  | tx |
  aTime < now ifTrue: [^ Error signal: 'RoundSim run: a time not before now'].
  (self nodeAt: anId) isUp ifFalse: [^ Error signal: 'RoundSim: ' , anId , ' is not running'].
  (commits includesKey: aToken) ifTrue: [^ Error signal: 'RoundSim: the token ' , aToken printString , ' is taken'].
  commits at: aToken put: #pending.
  commitOrder add: aToken.
  tx := Dictionary new.
  tx at: #node put: anId; at: #hot put: isHot; at: #builds put: someMicros; at: #retries put: n; at: #attempt put: 0;
    at: #snapshot put: nil; at: #errors put: OrderedCollection new; at: #roots put: OrderedCollection new; at: #then put: aBlock;
    at: #caller put: aCaller.
  self txs at: aToken put: tx.
  self _trace: anId , ' run ' , aToken printString.
  aTime = now ifTrue: [^ self _attempt: aToken].
  self _schedule: #client node: (self nodeAt: anId) payload: aToken at: aTime.

"A client at anId that runs transactions anId-1, anId-2, ... one after the other until stopLoops
 (name distinguishes several clients of one node)."
RoundSim >> loop: aName at: anId hot: isHot builds: someMicros retries: n
  | next count |
  count := 0.
  next := nil.
  next := [
    (stopped == true or: [(self nodeAt: anId) isUp not]) ifFalse: [
      count := count + 1.
      self run: aName , '-' , count printString at: anId hot: isHot builds: someMicros retries: n then: next caller: aName]].
  next value.

RoundSim >> _attempt: aToken
  | tx node entry |
  tx := self txs at: aToken.
  node := self nodeAt: (tx at: #node).
  node isUp ifFalse: [^ self].
  tx at: #attempt put: (tx at: #attempt) + 1.
  tx at: #snapshot put: (self knownAt: node id).
  entry := PBRoundEntry token: { 'tx'. aToken. tx at: #attempt } caller: (tx at: #caller) willRetry: (tx at: #retries) > 0 deadline: nil.
  self _schedule: #round node: node payload: (PBRoundEnqueued entry: entry) at: now.

RoundSim >> _txEnd: aToken as: aStatus
  | then |
  self _end: aToken as: aStatus.
  then := (self txs at: aToken) at: #then.
  then isNil ifFalse: [then value].

RoundSim >> _txSettled: aToken attempt: k outcome: anOutcome at: aNode
  | tx |
  tx := self txs at: aToken.
  self settles add: { aNode id. aToken. k. anOutcome. now. self started }.
  anOutcome == true ifTrue: [
    self acks add: { self started. aNode id. aToken. (tx at: #hot) == true }.
    ^ self _txEnd: aToken as: #acknowledged].
  anOutcome == false ifTrue: [^ self _txEnd: aToken as: #failed].
  (tx at: #errors) add: anOutcome.
  (anOutcome isKindOf: PBConflictError) ifTrue: [
    (tx at: #retries) > 0 ifFalse: [^ self _txEnd: aToken as: #none].
    tx at: #retries put: (tx at: #retries) - 1.
    anOutcome permitHeld ifTrue: [
      self heldDelay = 0 ifTrue: [^ self _attempt: aToken].
      ^ self _schedule: #client node: aNode payload: aToken at: now + self heldDelay].
    ^ self _schedule: #client node: aNode payload: aToken at: now + self retryBackoff].
  (anOutcome isKindOf: PBOutcomeUnknownError) ifTrue: [^ self _txEnd: aToken as: #unknown].
  ^ self _txEnd: aToken as: #failed.

"--- the scheduler ---"

RoundSim >> _isRoundTimer: anEvent
  ^ (anEvent at: 2) = #timer and: [((anEvent at: 5) at: 2) isKindOf: PBRoundEvent].

RoundSim >> _start: aNode
  super _start: aNode.
  self rounds at: aNode id put: (PBRoundState config: aNode config).

RoundSim >> _run: anEvent
  | kind node |
  kind := anEvent at: 2.
  (kind = #round or: [kind = #client or: [self _isRoundTimer: anEvent]]) ifFalse: [^ super _run: anEvent].
  node := self nodeAt: (anEvent at: 3).
  (node isUp and: [node gen = (anEvent at: 4)]) ifFalse: [^ self _trace: node id , ' gone, dropped ' , kind].
  kind = #client ifTrue: [^ self _attempt: (anEvent at: 5)].
  ^ self _round: (kind = #round ifTrue: [anEvent at: 5] ifFalse: [(anEvent at: 5) at: 2]) at: node.

RoundSim >> _round: anEvent at: aNode
  | local state step |
  local := aNode clock localAt: now.
  state := (self rounds at: aNode id) withRejoinBallot: aNode acceptor rejoinBallot.
  ((anEvent isKindOf: PBHoldExpired) and: [state phase = #held and: [anEvent token = state holdToken]])
    ifTrue: [expired := self holdsExpired + 1].
  self _trace: aNode id , ' round ' , anEvent printString , ' [clock ' , local printString , ']'.
  step := rules round: anEvent in: state now: local.
  self rounds at: aNode id put: step state.
  inRound := true.
  self _apply: step effects at: aNode.
  inRound := false.

RoundSim >> _toRound: anEvent at: aNode
  self _schedule: #round node: aNode payload: anEvent at: now.

RoundSim >> _nextWaiter
  waiters isNil ifTrue: [waiters := 0].
  waiters := waiters + 1.
  ^ waiters.

"--- the shell of the round ---"

RoundSim >> applyAskPermit: anAsk
  self _schedule: #dispatch node: current payload: (PBPermitWanted waiter: { 'round-permit'. self _nextWaiter }) at: now.

RoundSim >> applyAskBase: anAsk
  | delay |
  started := self started + 1.
  delay := self baseDelays at: current id ifAbsent: [0].
  self baseDelays at: current id put: 0.
  self _schedule: #dispatch node: current
    payload: (PBBaseWanted permission: anAsk permission waiter: { 'round-base'. self _nextWaiter }) at: now + delay.

"A root of the stamp { label. epoch } on aBase, its pred link recorded."
RoundSim >> _stamped: aStamp on: aBase at: aNode
  ^ self _stamped: aStamp on: aBase at: aNode hot: false.

"isHot: the root writes the hot key (its hot version is itself), else it keeps its base's."
RoundSim >> _stamped: aStamp on: aBase at: aNode hot: isHot
  | root |
  offsets := offsets + 1.
  root := PBLabeledRoot label: aStamp first record: (PBRootRecord segment: aNode segment offset: offsets epoch: aStamp last).
  preds at: (self keyText: root) put: (self keyText: aBase).
  hotVersions isNil ifTrue: [hotVersions := Dictionary new].
  hotVersions at: (self keyText: root) put: (isHot ifTrue: [self keyText: root] ifFalse: [self hotVersionOf: aBase]).
  ^ root.

"The key of the last root that wrote the hot key in aRoot's chain (a root no build made, such as
 a pre-formed log's: its own key; nil for nil)."
RoundSim >> hotVersionOf: aRoot
  aRoot isNil ifTrue: [^ nil].
  hotVersions isNil ifTrue: [hotVersions := Dictionary new].
  ^ hotVersions at: (self keyText: aRoot) ifAbsent: [self keyText: aRoot].

"The virtual time at which aNode's clock has advanced by someMicros."
RoundSim >> _after: someMicros at: aNode
  ^ aNode clock globalAt: (aNode clock localAt: now) + someMicros.

RoundSim >> applyBuild: aBuild
  | entry tx micros snapshot root token |
  entry := aBuild entry.
  entry isNil ifTrue: [
    "proto_db _commit_base: an unchanged root on the base."
    root := self _stamped: aBuild stamp on: aBuild base at: current.
    self recommits add: (self keyText: root).
    self _trace: current id , ' re-commits ' , (PBCoreValue textOf: aBuild base) , ' as ' , (PBCoreValue textOf: root).
    ^ self _toRound: (PBBuilt entry: nil root: root micros: 0) at: current].
  token := entry token at: 2.
  tx := self txs at: token.
  micros := (tx at: #builds) at: ((tx at: #attempt) min: (tx at: #builds) size).
  snapshot := tx at: #snapshot.
  ((tx at: #hot) == #always or: [(tx at: #hot) == true and: [snapshot isNil or: [(self hotVersionOf: snapshot) ~= (self hotVersionOf: aBuild base)]]]) ifTrue: [
    self _trace: current id , ' ' , token printString , ' conflicts (read ' , (PBCoreValue textOf: snapshot) , ', base '
      , (PBCoreValue textOf: aBuild base) , ')'.
    ^ self _schedule: #round node: current
      payload: (PBBuildConflict entry: entry error: (PBConflictError new messageText: 'the hot key changed after the transaction read it'; yourself))
      at: (self _after: micros at: current)].
  root := self _stamped: aBuild stamp on: aBuild base at: current hot: (tx at: #hot) == true.
  commitRoots at: token put: root.
  (tx at: #roots) add: root.
  self _trace: current id , ' built ' , (PBCoreValue textOf: root) , ' on ' , (PBCoreValue textOf: aBuild base) , ' for ' , token printString.
  self _schedule: #round node: current payload: (PBBuilt entry: entry root: root micros: micros) at: (self _after: micros at: current).

RoundSim >> applyReplicate: aReplicate
  | hook |
  self replicates add: { current id. aReplicate permission. aReplicate root. aReplicate pred. self started. nil }.
  onReplicate notNil ifTrue: [
    hook := onReplicate.
    onReplicate := nil.
    hook value: current id].
  self _schedule: #dispatch node: current
    payload: (PBReplicateWanted permission: aReplicate permission root: aReplicate root pred: aReplicate pred
      waiter: { 'round-rep'. self replicates size. aReplicate root }) at: now.

RoundSim >> applyReportDone: aReport
  self reports add: { current id. aReport permission. aReport outcome. now }.
  self _schedule: #dispatch node: current
    payload: (PBDoneReport permission: aReport permission outcome: aReport outcome root: aReport root) at: now.

"A round's timer keeps its deadline on the node's clock, as the core's (clockRate: moves it)."
RoundSim >> applyTimer: aTimer
  | deadline |
  inRound == true ifFalse: [^ super applyTimer: aTimer].
  deadline := (current clock localAt: now) + aTimer after.
  self _schedule: #timer node: current payload: { deadline. aTimer event } at: (current clock globalAt: deadline).

RoundSim >> _settle: aWaiter outcome: anOutcome at: aNode
  | kind |
  kind := aWaiter first.
  kind = 'round-permit' ifTrue: [^ self _toRound: (PBPermitted permission: anOutcome) at: aNode].
  kind = 'round-base' ifTrue: [
    self decisions add: { aNode id. anOutcome. now }.
    ((anOutcome isKindOf: PBBaseDecision) and: [anOutcome isOk and: [anOutcome needsCommit not]]) ifTrue: [
      self _know: anOutcome base at: aNode].
    ^ self _toRound: (PBBaseDecided decision: anOutcome) at: aNode].
  kind = 'round-rep' ifTrue: [
    (self replicates at: (aWaiter at: 2)) at: 6 put: anOutcome.
    anOutcome = #committed ifTrue: [self _know: (aWaiter at: 3) at: aNode].
    ^ self _toRound: (PBReplicated outcome: anOutcome) at: aNode].
  kind = 'tx' ifTrue: [^ self _txSettled: (aWaiter at: 2) attempt: (aWaiter at: 3) outcome: anOutcome at: aNode].
  ^ super _settle: aWaiter outcome: anOutcome at: aNode.

"--- measures ---"

"The longest run of rounds (counted cluster-wide) that anId went without an acknowledged hot
 commit, over the rounds 0 to aRound."
RoundSim >> longestGapOf: anId upTo: aRound
  | last gap |
  last := 0.
  gap := 0.
  self acks do: [:a |
    ((a at: 2) = anId and: [(a at: 4) and: [a first <= aRound]]) ifTrue: [
      gap := gap max: a first - last.
      last := a first]].
  ^ gap max: aRound - last.

"How long a client takes to retry a permitHeld conflict (its fn run again), virtual
 microseconds; 0 by default."
"How many holds of a kept permission ran out (their PBHoldExpired found the round still held
 under that hold: the held retries had not all queued within max(min(retryHold, the time
 left), retryWait))."
RoundSim >> holdsExpired
  ^ expired ifNil: [0].

RoundSim >> heldDelay
  heldDelay isNil ifTrue: [heldDelay := 0].
  ^ heldDelay.

RoundSim >> heldDelay: someMicros
  heldDelay := someMicros.

"proto_db test_cluster_permit_hot_key's lost updates: acknowledged commits whose root is not in
 the committed chain of the newest root committed anywhere (after convergence)."
RoundSim >> lostUpdates
  | top chain k |
  top := nil.
  ids do: [:id | top := PBRootOrder max: top with: (self nodeAt: id) committed].
  chain := Set new.
  k := top isNil ifTrue: [nil] ifFalse: [self keyText: top].
  [k notNil and: [(chain includes: k) not]] whileTrue: [chain add: k. k := preds at: k ifAbsent: [nil]].
  ^ (self acks select: [:a | (chain includes: (self keyText: (commitRoots at: (a at: 3)))) not]) size.

"How many hot transactions of anId were acknowledged."
RoundSim >> acksOf: anId
  ^ (self acks select: [:a | (a at: 2) = anId and: [a at: 4]]) size.

"How many permissions committed two rounds or more (several rounds under one permission, each
 replication acknowledged by the voters; the re-commit of a base is not a round's)."
RoundSim >> permitsWithSeveralCommits
  | per |
  per := Dictionary new.
  self replicates do: [:r | ((r at: 6) = #committed and: [(self recommits includes: (self keyText: (r at: 3))) not]) ifTrue: [ | key |
    key := (r at: 1) , ' ' , (r at: 2) term printString , '#' , (r at: 2) seq printString.
    per at: key put: (per at: key ifAbsent: [0]) + 1]].
  ^ (per values select: [:n | n >= 2]) size.

"=== The scenario families ==================================================="

Object subclass: #RoundFamilies.

RoundFamilies class >> three
  ^ #('n0' 'n1' 'n2').

"The root r1 every pre-formed log holds: label 4096, epoch 1."
RoundFamilies class >> r1
  ^ PBLabeledRoot label: 4096
    record: (PBRootRecord segment: (ByteArray withAll: ((1 to: 16) asArray collect: [:i | 238])) offset: 1 epoch: 1).

"A RoundSim of three members formed before, startup grace 0, the rules aRules, options
 aDictionary on top. Each log holds the rejoined marker and r1 accepted; with isCommitted, r1
 committed too."
RoundFamilies class >> sim: aRules seed: n committed: isCommitted options: aDictionary
  | logs opts |
  logs := Dictionary new.
  self three do: [:id | | appends |
    appends := OrderedCollection new.
    appends add: (PBLogAppend kind: #accepted label: self r1 label root: self r1 record sync: true).
    isCommitted ifTrue: [appends add: (PBLogAppend kind: #committed label: self r1 label root: self r1 record sync: true)].
    appends add: (PBLogAppend kind: #rejoined label: 0 root: nil sync: true).
    logs at: id put: appends asArray].
  opts := Dictionary new.
  opts at: #startupGrace put: 0.
  aDictionary keysAndValuesDo: [:k :v | opts at: k put: v].
  ^ RoundSim seed: n ids: self three rules: aRules options: opts logs: logs.

RoundFamilies class >> resolve: someTokens in: aSim
  aSim runUntil: [someTokens allSatisfy: [:k | (aSim outcomeOf: k) ~= #pending]] steps: 2000000.

"The text of anError, '' for nil."
RoundFamilies class >> textOf: anError
  anError isNil ifTrue: [^ ''].
  ^ anError messageText ifNil: [''].

"--- 1. hot key: no member starves (D-LIVE-2) ---"

"{ longest gap of each member (rounds without an acknowledged hot commit, over the first 200
 rounds). acknowledged hot commits of each member. permissions that committed two rounds.
 re-commits. lost updates }: modelled on proto_db test_cluster_permit_hot_key at DEPTH 0; a
 model, not a port (proto_db's test is threaded; here a client is a sequence of events and a
 transaction's snapshot is the newest root its node knows committed when it queues, as
 Database.run reads it). Three members, lease 2400 ms, requestTimeout 100 ms; k clients per
 member each run hot read-modify-writes of one key (10 retries, 1 ms builds), one after the
 other, and b blind writers per member (commits that never conflict, 1 ms builds) beside them;
 a permitHeld retry is queued after d virtual microseconds (its fn run again). A transaction
 reads its snapshot before it queues for a permission; by its turn another member has
 committed, so its first round conflicts, always. It commits only through a retry that starts
 from the root the permission carries, built while the permission is still held. The runs stop
 at 200 rounds and converge (no fork, S4, H7); lost updates are acknowledged commits missing
 from the committed chain (proto_db's no-lost-update counter)."
RoundFamilies class >> hotKey: aRules seed: n clients: k
  ^ self hotKey: aRules seed: n clients: k blind: 0 heldDelay: 0.

RoundFamilies class >> hotKey: aRules seed: n clients: k blind: b heldDelay: d
  | sim opts limit |
  opts := Dictionary new.
  opts at: #leaseDuration put: 2400; at: #requestTimeout put: 100.
  sim := self sim: aRules seed: n committed: true options: opts.
  sim heldDelay: d.
  limit := 200.
  self three do: [:id |
    1 to: k do: [:i | sim loop: id , 'c' , i printString at: id hot: true builds: #(1000) retries: 10].
    1 to: b do: [:i | sim loop: id , 'b' , i printString at: id hot: false builds: #(1000) retries: 10]].
  sim runUntil: [sim started >= limit] steps: 3000000.
  sim stopLoops.
  sim converge: 3000000.
  ^ { self three collect: [:id | sim longestGapOf: id upTo: limit].
    self three collect: [:id | sim acksOf: id].
    sim permitsWithSeveralCommits.
    sim recommits size.
    sim lostUpdates }.

"--- 2. a reserve refusal sends nothing and is retryable ---"

"{ outcome. the first attempt's error is a PBConflictError, not permitHeld, naming sendReserve.
 PBReplicates of the refused root. sends_refused_reserve at n0. replications at n0 }: proto_db
 test_cluster_send_reserve. n0's commit builds for 600 ms on its first attempt, which leaves less
 than sendReserve (166 ms) of any permission (at most the belief, 666 ms): the round refuses to
 send, truthfully; the retry (1 ms) commits."
RoundFamilies class >> reserve: aRules seed: n
  | sim first refused |
  sim := self sim: aRules seed: n committed: true options: Dictionary new.
  sim run: 'a' at: 'n0' hot: false builds: #(600000 1000) retries: 3.
  self resolve: #('a') in: sim.
  first := (sim errorsOf: 'a') isEmpty ifTrue: [nil] ifFalse: [(sim errorsOf: 'a') first].
  refused := (sim rootsOf: 'a') first.
  sim converge: 2000000.
  ^ { sim outcomeOf: 'a'.
    (first isKindOf: PBConflictError) and: [first permitHeld not and: [(self textOf: first) includesSubstring: 'sendReserve']].
    (sim replicates select: [:r | (sim keyText: (r at: 3)) = (sim keyText: refused)]) size.
    sim countOf: 'sends_refused_reserve' at: 'n0'.
    sim countOf: 'replications' at: 'n0' }.

"--- 3. a build longer than the belief (Review Focus 2) ---"

"{ outcome. attempts. the last error names leaseDuration, sendReserve and the build time.
 PBReplicates. sends_refused_reserve at n0 }: every attempt of n0's commit builds for 700 ms,
 longer than any permission (the belief, 666 ms): every round is refused, nothing is ever sent,
 and the client ends after its retries with the reserve refusal's text (CC18), not silently.
 The permission has expired by then, so no refusal is counted (proto_db counts
 sends_refused_reserve only for a valid permission)."
RoundFamilies class >> buildLonger: aRules seed: n
  | sim last |
  sim := self sim: aRules seed: n committed: true options: Dictionary new.
  sim run: 'a' at: 'n0' hot: false builds: #(700000) retries: 4.
  self resolve: #('a') in: sim.
  last := (sim errorsOf: 'a') isEmpty ifTrue: [nil] ifFalse: [(sim errorsOf: 'a') last].
  sim converge: 2000000.
  ^ { sim outcomeOf: 'a'. sim attemptsOf: 'a'.
    #('leaseDuration' 'sendReserve' '700 ms') allSatisfy: [:w | (self textOf: last) includesSubstring: w].
    sim replicates size.
    sim countOf: 'sends_refused_reserve' at: 'n0' }.

"--- 4. the group bound leaves the rest queued; they commit next round ---"

"{ outcomes. sends_refused_reserve at n0. acknowledged per round (in order). the first
 permission's re-commit then round, under it, the round built on the re-commit }: CC11. The logs
 hold r1 accepted, not committed: the first round re-commits it (R50) and then builds on the
 re-commit (two replications under one permission, real acks). Five commits of n0, queued at
 once, build for 150 ms each: before each build after the first, the round goes on only while
 the permission has sendReserve + the longest build left; the rest go back to the head of the
 queue, not as attempts (no retries are left), and commit in a later round. Without the bound the
 round's last build would leave less than sendReserve, and the whole round would be refused."
RoundFamilies class >> groupBound: aRules seed: n
  | sim tokens perRound first second |
  sim := self sim: aRules seed: n committed: false options: Dictionary new.
  tokens := #('g1' 'g2' 'g3' 'g4' 'g5').
  tokens do: [:k | sim run: k at: 'n0' hot: false builds: #(150000) retries: 0].
  self resolve: tokens in: sim.
  perRound := OrderedCollection new.
  ((sim acks collect: [:a | a first]) asSet asSortedCollection: [:a :b | a <= b]) do: [:r |
    perRound add: (sim acks select: [:a | a first = r]) size].
  first := sim replicates size >= 1 ifTrue: [sim replicates first] ifFalse: [nil].
  second := sim replicates size >= 2 ifTrue: [sim replicates at: 2] ifFalse: [nil].
  sim converge: 2000000.
  ^ { tokens collect: [:k | sim outcomeOf: k].
    sim countOf: 'sends_refused_reserve' at: 'n0'.
    perRound asArray.
    (first notNil and: [second notNil]) and: [(first at: 2) == (second at: 2)
      and: [(sim keyText: (first at: 4)) = (sim keyText: self r1)
      and: [(sim keyText: (second at: 4)) = (sim keyText: (first at: 3))
      and: [(first at: 6) = #committed and: [(second at: 6) = #committed]]]]] }.

"--- 5. a stale base requeues and abandons the term ---"

"{ outcome of a. outcome of b. a #stale decision at n1. the stale permission reported #unknown.
 attempts of a. terms abandoned }: proto_db _permit_round (base None). n1's round runner stops
 between its permit and its base choice for 3 leaseDurations; meanwhile n1's permission ends, its
 term is abandoned, and n2 commits b under a later term, which n1 learns. n1's base is then
 superseded (#stale): nothing is sent, a goes back to the queue (not as an attempt: it has no
 retries), the permission ends unknown, and a commits under a fresh permission."
RoundFamilies class >> stale: aRules seed: n
  | sim d staleReport |
  sim := self sim: aRules seed: n committed: true options: Dictionary new.
  d := (sim nodeAt: 'n0') config leaseDuration.
  sim delayBase: 3 * d at: 'n1'.
  sim run: 'a' at: 'n1' hot: false builds: #(1000) retries: 0.
  sim runTo: d + (d // 5) steps: 2000000.
  sim run: 'b' at: 'n2' hot: false builds: #(1000) retries: 0.
  self resolve: #('a' 'b') in: sim.
  staleReport := sim reports detect: [:r | (r at: 1) = 'n1'] ifNone: [nil].
  sim converge: 2000000.
  ^ { sim outcomeOf: 'a'. sim outcomeOf: 'b'.
    (sim decisions anySatisfy: [:x | (x at: 1) = 'n1' and: [((x at: 2) isKindOf: PBBaseDecision) and: [(x at: 2) outcome = #stale]]]).
    staleReport notNil and: [(staleReport at: 3) = #unknown].
    sim attemptsOf: 'a'.
    (self three inject: 0 into: [:sum :id | sum + (sim countOf: 'terms_abandoned' at: id)]) > 0 }.

"--- 6. unknown is never retried ---"

"{ outcome of u. attempts of u. a permitHeld error. n0's last report. outcome of v }: n0's commit
 u (5 retries) replicates; once its replicate is handed over, n0 is cut off, so no majority
 acknowledges within the permission: u ends PBOutcomeUnknownError, its client never retries it,
 the round reports unknown. After the heal, v at n1 commits; convergence then checks that u is
 in every committed chain or in none."
RoundFamilies class >> unknown: aRules seed: n
  | sim last |
  sim := self sim: aRules seed: n committed: true options: Dictionary new.
  sim onReplicate: [:id | sim partition: #(#('n0') #('n1' 'n2'))].
  sim run: 'u' at: 'n0' hot: false builds: #(1000) retries: 5.
  self resolve: #('u') in: sim.
  last := (sim reports select: [:r | (r at: 1) = 'n0']) asArray.
  sim heal.
  sim run: 'v' at: 'n1' hot: false builds: #(1000) retries: 5.
  self resolve: #('v') in: sim.
  sim converge: 2000000.
  ^ { sim outcomeOf: 'u'. sim attemptsOf: 'u'.
    (sim errorsOf: 'u') anySatisfy: [:e | (e isKindOf: PBConflictError) and: [e permitHeld]].
    last isEmpty ifTrue: [nil] ifFalse: [last last at: 3].
    sim outcomeOf: 'v' }.

"--- 7. every commit gets an outcome (spec 5.7) ---"

"{ outcome of h. h's error is its own conflict. outcome of a }: in one round of n0, a builds and
 h (no retries left, a read that always conflicts) conflicts; once the PBReplicate is handed
 over, n0 is cut off and the replication ends #unknown. a ends PBOutcomeUnknownError; h, not
 part of what was sent, gets its own conflict, so its client ends instead of waiting."
RoundFamilies class >> conflictInUnknown: aRules seed: n
  | sim |
  sim := self sim: aRules seed: n committed: true options: Dictionary new.
  sim onReplicate: [:id | sim partition: #(#('n0') #('n1' 'n2'))].
  sim run: 'a' at: 'n0' hot: false builds: #(1000) retries: 0.
  sim run: 'h' at: 'n0' hot: #always builds: #(1000) retries: 0.
  self resolve: #('a' 'h') in: sim.
  ^ { sim outcomeOf: 'h'.
    (sim errorsOf: 'h') size = 1 and: [(sim errorsOf: 'h') first isKindOf: PBConflictError].
    sim outcomeOf: 'a' }.

"{ outcome of m. its error is a PBTimeoutError }: n0 is cut off from the start; its commit m
 waits for a permission no majority can grant, which ends PBTimeoutError (acquireTimeout): the
 round settles its batch with that error, so the client ends."
RoundFamilies class >> minority: aRules seed: n
  | sim |
  sim := self sim: aRules seed: n committed: true options: Dictionary new.
  sim partition: #(#('n0') #('n1' 'n2')).
  sim run: 'm' at: 'n0' hot: false builds: #(1000) retries: 0.
  self resolve: #('m') in: sim.
  ^ { sim outcomeOf: 'm'. (sim errorsOf: 'm') anySatisfy: [:x | x isKindOf: PBTimeoutError] }.
