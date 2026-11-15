"_plants.st: the test rules of the proposer's scenario families and the planted wrong rules
 that prove each family can fail (a helper: the runner never runs files whose name starts with
 _). Test support, not product (CC13): each plant is a subclass overriding one rule method.

  LeaseRules            the product rules, with owner.st's permissions replaced: an owner settles
                        each queued local waiter at once with #leased, so its demand ends and
                        terms change hands, and no waiter asks an owner for a permission (every
                        one acquires); it records every request sent.
  PlantMinorityWins     an attempt not lost counts as won at its close (one owner per term
                        under drop/dup/reorder: two valid leases at once).
  PlantSharedBallot     every proposer asks the ballots of rank 0 (two proposers never share
                        a ballot).
  PlantWindowFromWin    the lease is valid for the belief from the win, not from the send (L5:
                        the lease runs from the send, not the win).
  PlantNoDriftMargin    the lease is valid for leaseDuration from the send (clock rates 2/3 to
                        3/2 keep S1: two valid leases at once).
  PlantNoTurns          a release names nobody (releases name the longest waiter and the turns
                        rotate, D-LIVE-1).
  PlantCancelWakes      any release ends the back-off, a lost attempt's cancel included
                        (proto_db's cancel_wakes).
  PlantAnyIncarnation   a reply of another incarnation is taken (replies of another incarnation
                        are dropped, L12).
  PlantLateDoneAsNone   a permission without a done by its deadline is retired as 'none' (O5:
                        the next permission reuses its base) instead of abandoning the term (O6,
                        L29: a dying holder's replication may still be accepted).

 The lessons' schedules that have no family of their own are here too (LessonFamilies, for
 sim_lessons.st): L29's dying holder. So are the simulator-level checker plants'
 (sim_checker_plants.st) rules and builder: RecommitRules (every commit re-commits its base
 first, the product's re-commit path) and CheckerFamilies (a converged three-member run, and the
 plant that moves every member's head)."

Import from: 'protobase'.

PBCoordinatorCore subclass: #LeaseRules instanceVariableNames: 'requests'.

LeaseRules class >> new
  ^ self basicNew setUp.

LeaseRules >> setUp
  requests := OrderedCollection new.

"{ sender. term } of every request sent, in order."
LeaseRules >> requests
  ^ requests asArray.

LeaseRules >> dispatch: anEvent in: aNodeState now: t
  | step |
  step := super dispatch: anEvent in: aNodeState now: t.
  step effects do: [:e |
    ((e isKindOf: PBSend) and: [e message type = 'request']) ifTrue: [
      (requests anySatisfy: [:r | r first = e message from and: [r last = (e message at: 'term')]]) ifFalse: [
        requests add: { e message from. e message at: 'term' }]]].
  ^ step.

"In place of owner.st's permissions (the lease families need terms to change hands): every local
 waiter queued at the ownership is served at once with #leased."
LeaseRules >> _issue: s now: t effects: fx
  | own state |
  own := s ownership.
  own queue isEmpty ifTrue: [^ s].
  state := s.
  own queue do: [:e | (e at: 4) notNil ifTrue: [state := self _settle: (e at: 4) with: #leased in: state effects: fx]].
  ^ state with: { #ownership -> (state ownership with: { #queue -> #() }) }.

"Nobody asks an owner for a permission (owner.st's holder side): every waiter acquires, as the
 lease families of Task 11 measure."
LeaseRules >> _ownerToAsk: s
  ^ nil.

LeaseRules subclass: #PlantMinorityWins.

PlantMinorityWins >> _won: anAttempt
  ^ anAttempt state ~= #lost.

LeaseRules subclass: #PlantSharedBallot.

PlantSharedBallot >> ballotFor: aNodeState
  ^ (super ballotFor: aNodeState) - aNodeState config rank.

LeaseRules subclass: #PlantWindowFromWin.

PlantWindowFromWin >> _leaseEnd: anAttempt in: s now: t
  ^ t + s config belief.

LeaseRules subclass: #PlantNoDriftMargin.

PlantNoDriftMargin >> _leaseEnd: anAttempt in: s now: t
  ^ anAttempt sentAt + s config leaseDuration.

LeaseRules subclass: #PlantNoTurns.

PlantNoTurns >> _nextTurn: aHints
  ^ { nil. aHints }.

LeaseRules subclass: #PlantCancelWakes.

PlantCancelWakes >> _endsBackOff: aHints since: someMarks
  ^ (super _endsBackOff: aHints since: someMarks) or: [aHints wakeups ~= (someMarks at: 1)].

LeaseRules subclass: #PlantAnyIncarnation.

PlantAnyIncarnation >> _isStale: aMessage in: s
  ^ false.

"=== The scenario families ==================================================="

"One run of a family: a PBSim of three members formed before (each log the rejoined marker),
 startup grace 0, and the synthetic demand that drives it."
Object subclass: #LeaseRun instanceVariableNames: 'sim tokens count'.

LeaseRun class >> rules: aRules seed: n options: aDictionary
  ^ self basicNew setRules: aRules seed: n options: aDictionary.

LeaseRun >> setRules: aRules seed: n options: aDictionary
  | ids logs opts |
  ids := #('n0' 'n1' 'n2').
  logs := Dictionary new.
  ids do: [:id | logs at: id put: { PBLogAppend kind: #rejoined label: 0 root: nil sync: true }].
  opts := Dictionary new.
  opts at: #startupGrace put: 0.
  aDictionary keysAndValuesDo: [:k :v | opts at: k put: v].
  sim := PBSim seed: n ids: ids rules: aRules options: opts logs: logs.
  tokens := Dictionary new.
  count := 0.

LeaseRun >> sim
  ^ sim.

"Every node of someIds that runs and has no commit pending asks a new one, gap us from now: a
 node that owns a term too when owners is true."
LeaseRun >> demandAt: someIds gap: gap owners: owners
  someIds do: [:id | | node token |
    node := sim nodeAt: id.
    token := tokens at: id ifAbsent: [nil].
    (node isUp and: [node state notNil and: [(owners or: [node state ownership isNil])
        and: [token isNil or: [(sim outcomeOf: token) ~= #pending]]]]) ifTrue: [
      count := count + 1.
      token := 'c' , count printString.
      tokens at: id put: token.
      sim commit: token at: id time: sim now + gap]].

"Steps under that demand until aBlock answers true or nothing is due."
LeaseRun >> until: aBlock demandAt: someIds gap: gap owners: owners
  [aBlock value] whileFalse: [
    self demandAt: someIds gap: gap owners: owners.
    sim step ifFalse: [^ self]].

LeaseRun >> ownerships
  ^ sim ids inject: 0 into: [:a :id | a + (sim countOf: 'ownerships' at: id)].

LeaseRun >> owns: anId
  | node |
  node := sim nodeAt: anId.
  ^ node isUp and: [node state notNil and: [node state ownership notNil]].

"The families: each answers what its checks count over the seeds; a violation the checker
 reports (S1, L5: an Error whose text starts with 'PBSim seed') is a failed seed, and any other
 Error is signalled on, never counted as a plant's failure."
Object subclass: #LeaseFamilies.

"Whether aBlock ended with a violation of the checker (true) or ran through (false)."
LeaseFamilies class >> violates: aBlock
  ^ [aBlock value. false] on: Error do: [:e |
    (e messageText beginsWith: 'PBSim seed') ifTrue: [true] ifFalse: [e pass]].

"{ seeds whose run failed the checker. seeds where two members asked the same term. seeds that
 owned fewer than four terms }: under drop 1/10, duplicate 1/20, delay up to 2 ms and reorder,
 every member wants a lease until four terms were owned (or 5 s of virtual time ran)."
LeaseFamilies class >> terms: aRulesClass seeds: someSeeds
  | failed shared stalled |
  failed := 0.
  shared := 0.
  stalled := 0.
  someSeeds do: [:seed | | rules run bad |
    rules := aRulesClass new.
    run := LeaseRun rules: rules seed: seed options: Dictionary new.
    run sim faults: (PBSimFaults drop: 1/10 duplicate: 1/20 delay: 2000 reorder: true).
    run sim checker watchLeases.
    bad := self violates: [run until: [run ownerships >= 4 or: [run sim now > 5000000]] demandAt: run sim ids gap: 0 owners: false].
    bad ifTrue: [failed := failed + 1].
    (bad not and: [run ownerships < 4]) ifTrue: [stalled := stalled + 1].
    ((rules requests collect: [:r | r last]) asSet size = rules requests size) ifFalse: [shared := shared + 1]].
  ^ { failed. shared. stalled }.

"{ seeds failed. seeds where both n0 and n1 owned }: the lease runs from the send, not the win
 (L5). n0 (clock rate 2/3) asks; the grants of n1 and n2 (rate 3/2) reach it 800 ms of virtual
 time later, 533 ms of its clock: a win within its requestTimeout (600 ms of its clock) and
 before its belief (666 ms of its clock). n0 is cut off; n1 asks at 1.4 s, after the granters'
 promise (2 s of their clocks, 1.33 s of virtual time) ended. A lease measured from the win
 would still be valid at n0 then. (A grant arriving after the belief cannot be scheduled here,
 the simulator fires timers punctually: cluster_proposer_rules.st checks that case directly.)"
LeaseFamilies class >> window: aRulesClass seeds: someSeeds
  | failed both |
  failed := 0.
  both := 0.
  someSeeds do: [:seed | | out |
    out := self window: aRulesClass seed: seed.
    out first notNil ifTrue: [failed := failed + 1].
    out last ifTrue: [both := both + 1]].
  ^ { failed. both }.

"One seed of window:seeds:: { the violation's text or nil. both n0 and n1 owned }."
LeaseFamilies class >> window: aRulesClass seed: seed
  | run n1 text |
  run := LeaseRun rules: aRulesClass new seed: seed options: (Dictionary new at: #requestTimeout put: 600; yourself).
  run sim clockRate: 'n0' rate: 2/3; clockRate: 'n1' rate: 3/2; clockRate: 'n2' rate: 3/2.
  run sim delay: 'n1' to: 'n0' by: 800000; delay: 'n2' to: 'n0' by: 800000.
  run sim checker watchLeases.
  n1 := false.
  text := [
    run sim commit: 'a' at: 'n0'.
    run sim runUntil: [(run owns: 'n0') or: [run sim now > 1200000]] steps: 100000.
    run sim partition: #(#('n0') #('n1' 'n2')).
    run sim commit: 'b' at: 'n1' time: 1400000.
    run sim runUntil: [n1 := n1 or: [run owns: 'n1']. run sim now > 2500000] steps: 100000.
    nil] on: Error do: [:e |
      (e messageText beginsWith: 'PBSim seed') ifTrue: [e messageText] ifFalse: [e pass]].
  ^ { text. (run sim countOf: 'ownerships' at: 'n0') > 0 and: [n1] }.

"{ seeds failed. seeds where another member owned while the first owner was cut off }: one
 member (clock rate 2/3, the others 3/2) owns with a commit every 20 ms; it is cut off from the
 others, which want leases too, for 4 s of virtual time (S1 and L5 under the drift bound)."
LeaseFamilies class >> drift: aRulesClass seeds: someSeeds
  | failed taken |
  failed := 0.
  taken := 0.
  someSeeds do: [:seed | | run ids slow others bad end other |
    run := LeaseRun rules: aRulesClass new seed: seed options: Dictionary new.
    ids := run sim ids.
    slow := ids at: seed \\ 3 + 1.
    others := ids reject: [:id | id = slow].
    ids do: [:id | run sim clockRate: id rate: (id = slow ifTrue: [2/3] ifFalse: [3/2])].
    run sim checker watchLeases.
    other := false.
    bad := self violates: [
      run until: [(run owns: slow) or: [run sim now > 2000000]] demandAt: { slow } gap: 20000 owners: true.
      run sim partition: { { slow }. others }.
      end := run sim now + 4000000.
      run until: [other := other or: [others anySatisfy: [:id | run owns: id]]. run sim now > end]
        demandAt: ids gap: 20000 owners: true].
    bad ifTrue: [failed := failed + 1].
    other ifTrue: [taken := taken + 1]].
  ^ { failed. taken }.

"{ the largest share of the ownerships won by one member, in percent. turns_named. turns_taken }:
 every member wants a lease whenever it owns none, appends cost 3 ms to sync, until n terms
 were owned (D-LIVE-1)."
LeaseFamilies class >> fairness: aRulesClass seed: seed terms: n
  | run named taken |
  run := LeaseRun rules: aRulesClass new seed: seed options: Dictionary new.
  run sim syncCost: 3000.
  run sim checker watchLeases.
  run until: [run ownerships >= n or: [run sim now > 600000000]] demandAt: run sim ids gap: 0 owners: false.
  named := run sim ids inject: 0 into: [:a :id | a + (run sim countOf: 'turns_named' at: id)].
  taken := run sim ids inject: 0 into: [:a :id | a + (run sim countOf: 'turns_taken' at: id)].
  ^ { (run sim ids inject: 0 into: [:a :id | a max: (run sim countOf: 'ownerships' at: id)]) * 100 // (run ownerships max: 1).
    named. taken }.

"The most attempts n1 made over the seeds, in the 300 ms during which n2's cancels (releases
 not held) reach it every 2 ms while n0 owns with a commit every 20 ms: a cancel must not end
 the back-off of a refused request."
LeaseFamilies class >> cancels: aRulesClass seeds: someSeeds
  | most |
  most := 0.
  someSeeds do: [:seed | | run sim t1 before inc |
    run := LeaseRun rules: aRulesClass new seed: seed options: Dictionary new.
    sim := run sim.
    sim checker watchLeases.
    run until: [(run owns: 'n0') or: [sim now > 2000000]] demandAt: #('n0') gap: 20000 owners: true.
    sim commit: 'wanting' at: 'n1'.
    t1 := sim now.
    before := sim countOf: 'attempts' at: 'n1'.
    inc := (sim nodeAt: 'n2') state inc.
    0 to: 149 do: [:k |
      sim inject: (PBClusterMessage type: 'release' from: 'n2' fields: { 'term' -> 2. 'inc' -> inc. 'root' -> nil.
        'committed' -> nil. 'certain' -> false. 'held' -> false. 'next' -> nil. 'more' -> true }) to: 'n1' at: t1 + (k * 2000)].
    run until: [sim now > (t1 + 300000)] demandAt: #('n0') gap: 20000 owners: true.
    most := most max: (sim countOf: 'attempts' at: 'n1') - before].
  ^ most.

"{ seeds where n0 owned. seeds where n0 counted fewer than two stale replies }: n1 and n2 are
 down; n0 asks; grants that match its attempt's term and rid but carry another incarnation
 arrive from both (L12)."
LeaseFamilies class >> incarnations: aRulesClass seeds: someSeeds
  | owned uncounted |
  owned := 0.
  uncounted := 0.
  someSeeds do: [:seed | | run sim att inc end |
    run := LeaseRun rules: aRulesClass new seed: seed options: Dictionary new.
    sim := run sim.
    sim crash: 'n1' keepDisk: true; crash: 'n2' keepDisk: true.
    sim commit: 'a' at: 'n0'.
    sim runUntil: [(sim nodeAt: 'n0') state proposer notNil and: [(sim nodeAt: 'n0') state proposer attempt notNil]] steps: 10000.
    att := (sim nodeAt: 'n0') state proposer attempt.
    inc := (sim nodeAt: 'n0') state inc + 1.
    #('n1' 'n2') do: [:from |
      sim inject: (PBClusterMessage type: 'grant' from: from fields: { 'term' -> att term. 'rid' -> att rid. 'inc' -> inc.
        'root' -> nil. 'committed' -> nil. 'certain' -> true }) to: 'n0' at: sim now + 1000].
    end := sim now + 200000.
    sim runUntil: [(run owns: 'n0') or: [sim now > end]] steps: 100000.
    (run owns: 'n0') ifTrue: [owned := owned + 1].
    (sim countOf: 'stale_replies' at: 'n0') < 2 ifTrue: [uncounted := uncounted + 1]].
  ^ { owned. uncounted }.

"=== L29: a dying holder vs done =============================================="

PBCoordinatorCore subclass: #PlantLateDoneAsNone.

PlantLateDoneAsNone >> _permissionLate: anIssued in: s now: t effects: fx
  | own |
  own := s ownership.
  ^ self _issue: (s with: { #ownership -> (own with: { #pipeline -> (own pipeline reject: [:e | e == anIssued]) }) })
    now: t effects: fx.

Object subclass: #LessonFamilies.

"{ violation text or nil. terms n0 abandoned. outcome of c. outcome of b }: L29, O6. Three members
 formed before (startup grace 0), no faults, the rules aRules. n0 owns (its commit a); n1 asks
 it for a permission (commit b), builds its root and replicates it, and dies right after the
 send (paused: its acceptor, its done and its replies wait); n2 asks n0 (commit c) 50 ms before
 n1's deadline and waits behind n1's permission. With no done by valid + requestTimeout, n0
 abandons the term, so c commits in a later term; retiring n1's permission as 'none' instead (O5)
 issues its base again to n2, whose root carries the label and epoch of n1's, which n1 sent and
 n0 and n2 accepted: two roots of one label and epoch (the checker's sibling rule). n1 resumes
 once c is resolved (or at 4 s) and the run converges."
LessonFamilies class >> lateDone: aRules seed: n
  | ids logs opts sim violation seen sent |
  ids := #('n0' 'n1' 'n2').
  logs := Dictionary new.
  ids do: [:id | logs at: id put: { PBLogAppend kind: #rejoined label: 0 root: nil sync: true }].
  opts := Dictionary new.
  opts at: #startupGrace put: 0.
  sim := PBSim seed: n ids: ids rules: aRules options: opts logs: logs.
  violation := [:aBlock | [aBlock value. nil] on: Error do: [:e |
    ((e messageText ifNil: ['']) beginsWith: 'PBSim seed') ifFalse: [e signal].
    e messageText]].
  ^ { violation value: [
      sim commit: 'a' at: 'n0'.
      sim runUntil: [(sim outcomeOf: 'a') ~= #pending] steps: 100000.
      sim commit: 'b' at: 'n1'.
      seen := 0.
      sent := false.
      [sent or: [sim step not]] whileFalse: [ | lines |
        lines := sim trace.
        seen + 1 to: lines size do: [:i | ((lines at: i) includesSubstring: 'replicate from n1') ifTrue: [sent := true]].
        seen := lines size].
      sent ifFalse: [sim fail: 'n1 never replicated b'].
      sim pause: 'n1'.
      "n2 asks 50 ms before n1's deadline: a fresh request, so a permission issued at the
       deadline is valid on arrival (one asked long before would be expired by then, L5)."
      sim commit: 'c' at: 'n2' time: (sim nodeAt: 'n0') state ownership pipeline first deadline - 50000.
      sim runUntil: [(sim outcomeOf: 'c') ~= #pending or: [sim now > 4000000]] steps: 200000.
      sim resume: 'n1'.
      sim runUntil: [(sim outcomeOf: 'c') ~= #pending] steps: 200000.
      sim converge: 200000].
    sim countOf: 'terms_abandoned' at: 'n0'.
    sim outcomeOf: 'c'.
    sim outcomeOf: 'b' }.

"=== The checker's plants at the simulator's level (sim_checker_plants.st) ===="

PBCoordinatorCore subclass: #RecommitRules.

"Every base decision needs a commit first (proto_db _commit_base): the base is the permission's
 root (the empty space when it has none), re-committed unchanged, the commit's own root built on
 that re-commit. Not a plant: the product's re-commit path on every commit."
RecommitRules >> dispatchBaseWanted: anEvent in: s now: t
  | root |
  root := anEvent permission root.
  root isNil ifTrue: [root := PBLabeledRoot label: 0 record: nil].
  ^ PBStep state: s effects: { PBSettle waiter: anEvent waiter
    outcome: (PBBaseDecision base: root needsCommit: true outcome: #ok) }.

Object subclass: #CheckerFamilies.

"A PBSim of three members formed before (startup grace 0) running aRules: the commits
 someTokens at n0, one after the other, then converged (checkConverged, the control)."
CheckerFamilies class >> run: aRules commits: someTokens
  | ids logs opts sim |
  ids := #('n0' 'n1' 'n2').
  logs := Dictionary new.
  ids do: [:id | logs at: id put: { PBLogAppend kind: #rejoined label: 0 root: nil sync: true }].
  opts := Dictionary new.
  opts at: #startupGrace put: 0.
  sim := PBSim seed: 1 ids: ids rules: aRules options: opts logs: logs.
  someTokens do: [:k |
    sim commit: k at: 'n0'.
    sim runUntil: [(sim outcomeOf: k) ~= #pending] steps: 200000].
  sim converge: 200000.
  ^ sim.

"The text of the violation aBlock signals, nil when it signals none."
CheckerFamilies class >> violationOf: aBlock
  ^ [aBlock value. nil] on: Error do: [:e | e messageText].

"The plant: every live member of aSim shows aRoot as its committed head."
CheckerFamilies class >> heads: aSim to: aRoot
  aSim ids do: [:id | (aSim nodeAt: id) isUp ifTrue: [(aSim nodeAt: id) committed: aRoot]].
