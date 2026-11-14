"_plants.st: the test rules of the proposer's scenario families and the planted wrong rules
 that prove each family can fail (a helper: the runner never runs files whose name starts with
 _). Test support, not product (CC13): each plant is a subclass overriding one rule method.

  LeaseRules            the product rules, with a stand-in for owner.st's permissions (Task 12):
                        an owner settles each queued local waiter at once with #leased, so its
                        demand ends and terms change hands; it records every request sent.
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
                        are dropped, L12)."

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

"A stand-in for owner.st (Task 12): every local waiter queued at the ownership is served."
LeaseRules >> _issue: s now: t effects: fx
  | own |
  own := s ownership.
  own queue isEmpty ifTrue: [^ s].
  own queue do: [:w | fx add: (PBSettle waiter: w outcome: #leased)].
  ^ s with: { #ownership -> (own with: { #queue -> #() }) }.

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
  someSeeds do: [:seed | | run n1 bad |
    run := LeaseRun rules: aRulesClass new seed: seed options: (Dictionary new at: #requestTimeout put: 600; yourself).
    run sim clockRate: 'n0' rate: 2/3; clockRate: 'n1' rate: 3/2; clockRate: 'n2' rate: 3/2.
    run sim delay: 'n1' to: 'n0' by: 800000; delay: 'n2' to: 'n0' by: 800000.
    run sim checker watchLeases.
    n1 := false.
    bad := self violates: [
      run sim commit: 'a' at: 'n0'.
      run sim runUntil: [(run owns: 'n0') or: [run sim now > 1200000]] steps: 100000.
      run sim partition: #(#('n0') #('n1' 'n2')).
      run sim commit: 'b' at: 'n1' time: 1400000.
      run sim runUntil: [n1 := n1 or: [run owns: 'n1']. run sim now > 2500000] steps: 100000].
    bad ifTrue: [failed := failed + 1].
    ((run sim countOf: 'ownerships' at: 'n0') > 0 and: [n1]) ifTrue: [both := both + 1]].
  ^ { failed. both }.

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
