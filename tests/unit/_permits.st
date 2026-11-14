"_permits.st: the test rules of the owner's scenario families (sim_permits.st) and the planted
 wrong rules that prove each family can fail (a helper: the runner never runs files whose name
 starts with _). Test support, not product (CC13): each plant is a subclass overriding one rule
 method.

  PermitRules          the product rules, with a stand-in for holder.st (Tasks 13-14): the base
                       of a commit is its permission's root (the empty space when unknown), and
                       a replication commits, at once or after a hold of the node's clock; it
                       logs the arrivals, issues, settles and sends of every node, and the
                       terms abandoned with their reasons.
  PlantBaseTwice       the owner issues while a permission is outstanding (O1's pipeline check
                       dropped): one base issued twice (R79, L28).
  PlantSilenceForgets  a permit request that got no answer forgets the owner whatever term the
                       hint names now (proto_db's plant silence_forgets).
  PlantHintForgotten   a refusal forgets its sender as owner whatever term the hint names now
                       (proto_db's plant hint_forgotten: the old term <= hint condition)."

Import from: 'protobase'.
Import from: '_sim'.
Import from: '_plants'.

PBCoordinatorCore subclass: #PermitRules instanceVariableNames: 'holds log abandons serial'.

PermitRules class >> new
  ^ self basicNew setUp.

PermitRules >> setUp
  holds := Dictionary new.
  log := OrderedCollection new.
  abandons := OrderedCollection new.
  serial := 0.

"Every replication at anId commits someMicros of its clock after it was asked (0: at once)."
PermitRules >> hold: anId for: someMicros
  holds at: anId put: someMicros.

"{ node. t. kind. detail. extra } in dispatch order: #arrival (a permit_req received, detail its
 sender; or a permit wanted locally, detail the node), #issue (a permit sent or a permission of
 this node's own ownership settled, detail the holder), #settle (detail the outcome, extra the
 waiter) and #send (detail the message, extra the receiver)."
PermitRules >> log
  ^ log asArray.

"{ node. t. reason } of every term abandoned."
PermitRules >> abandons
  ^ abandons asArray.

PermitRules >> dispatch: anEvent in: aNodeState now: t
  | step id |
  id := aNodeState config nodeId.
  ((anEvent isKindOf: PBReceived) and: [anEvent message type = 'permit_req']) ifTrue: [
    log add: { id. t. #arrival. anEvent message from. nil }].
  (anEvent isKindOf: PBPermitWanted) ifTrue: [log add: { id. t. #arrival. id. nil }].
  step := super dispatch: anEvent in: aNodeState now: t.
  step effects do: [:e |
    (e isKindOf: PBSend) ifTrue: [
      log add: { id. t. #send. e message. e to }.
      e message type = 'permit' ifTrue: [log add: { id. t. #issue. e to. nil }]].
    (e isKindOf: PBSettle) ifTrue: [
      log add: { id. t. #settle. e outcome. e waiter }.
      ((e outcome isKindOf: PBPermission) and: [e outcome owner = id]) ifTrue: [log add: { id. t. #issue. id. nil }]]].
  ^ step.

"The stand-in for the base choice (Task 14): the permission's root, the empty space when unknown."
PermitRules >> dispatchBaseWanted: anEvent in: s now: t
  | root |
  root := anEvent permission root.
  root isNil ifTrue: [root := PBLabeledRoot label: 0 record: nil].
  ^ PBStep state: s effects: { PBSettle waiter: anEvent waiter outcome: (PBBaseDecision base: root needsCommit: false outcome: #ok) }.

"The stand-in for the replication (Task 13): it commits at once, or after the node's hold."
PermitRules >> dispatchReplicateWanted: anEvent in: s now: t
  | hold |
  hold := holds at: s config nodeId ifAbsent: [0].
  hold = 0 ifTrue: [^ PBStep state: s effects: { PBSettle waiter: anEvent waiter outcome: #committed }].
  serial := serial + 1.
  ^ PBStep state: s effects: { PBTimer after: hold token: { #hold. serial } event: { #hold. anEvent waiter } }.

PermitRules >> dispatchTimerFired: anEvent in: s now: t
  (anEvent event isArray and: [anEvent event first = #hold]) ifTrue: [
    ^ PBStep state: s effects: { PBSettle waiter: (anEvent event at: 2) outcome: #committed }].
  ^ super dispatchTimerFired: anEvent in: s now: t.

PermitRules >> _abandon: s why: aText now: t effects: fx
  (s ownership notNil and: [s ownership isAbandoned not]) ifTrue: [abandons add: { s config nodeId. t. aText }].
  ^ super _abandon: s why: aText now: t effects: fx.

PermitRules subclass: #PlantBaseTwice.

PlantBaseTwice >> _pipelineFull: anOwnership in: s
  ^ false.

PermitRules subclass: #PlantSilenceForgets.

PlantSilenceForgets >> _silenceForgets: anAsk in: aHints
  ^ true.

PermitRules subclass: #PlantHintForgotten.

PlantHintForgotten >> _refusalForgets: anAsk from: aSender in: aHints
  ^ aHints ownerNode = aSender.

"=== The scenario families ==================================================="

"The families: each answers counts over the seeds; a violation the checker reports is a failed
 seed (LeaseFamilies violates:), any other Error is signalled on."
Object subclass: #PermitFamilies.

"The log entries of aRules of aKind at anId."
PermitFamilies class >> log: aRules kind: aKind at: anId
  ^ aRules log select: [:e | (e at: 3) = aKind and: [(e at: 1) = anId]].

"The messages of aType anId sent (to anyone), in order."
PermitFamilies class >> sent: aType by: anId in: aRules
  ^ ((self log: aRules kind: #send at: anId) select: [:e | (e at: 4) type = aType]) collect: [:e | e at: 4].

"The settle entries of aRules at anId whose waiter is the permit waiter of aToken."
PermitFamilies class >> settles: aToken at: anId in: aRules
  ^ (self log: aRules kind: #settle at: anId) select: [:e | (e at: 5) = { 'permit'. aToken }].

"Runs aSim until virtual time anEnd or until nothing is due."
PermitFamilies class >> run: aSim until: anEnd
  aSim runUntil: [aSim now >= anEnd] steps: 1000000.

"n0 owns a term and committed 'a' (its done reached the others): the run of three members, the
 rules aRules, with aDictionary as options."
PermitFamilies class >> owned: aRules seed: n options: aDictionary
  | run sim |
  run := LeaseRun rules: aRules seed: n options: aDictionary.
  sim := run sim.
  sim commit: 'a' at: 'n0'.
  sim runUntil: [(sim outcomeOf: 'a') ~= #pending] steps: 100000.
  self run: sim until: sim now + 10000.
  ^ run.

"{ seeds failed. seeds where n0 issued in another order than its requests arrived. seeds where
 the deferred request was not served by the busy owner within leaseDuration / 4 }. Order: n0
 owns; every holder takes 5 ms; n1, n0, n2, n0, n1, n2 ask 1 ms apart (n0's own threads among
 the others). Deferral (proto_db test_a_deferred_request_is_served_by_the_busy_owner): a
 release named n2, whose request was seen, so n1 would defer up to leaseDuration; n0 takes a
 term and keeps committing every 5 ms; n1 asks n0 as soon as it learns that n0 owns."
PermitFamilies class >> firstCome: aRulesClass seeds: someSeeds
  | failed misordered late |
  failed := 0.
  misordered := 0.
  late := 0.
  someSeeds do: [:seed | | rules run sim t1 arrivals issues node start settle bad |
    rules := aRulesClass new.
    run := self owned: rules seed: seed options: Dictionary new.
    sim := run sim.
    sim ids do: [:id | rules hold: id for: 5000].
    bad := LeaseFamilies violates: [
      t1 := sim now + 10000.
      #('n1' 'n0' 'n2' 'n0' 'n1' 'n2') doWithIndex: [:id :i |
        sim commit: 'b' , i printString at: id time: t1 + ((i - 1) * 1000)].
      sim runUntil: [(1 to: 6) allSatisfy: [:i | (sim outcomeOf: 'b' , i printString) ~= #pending]] steps: 100000].
    bad ifTrue: [failed := failed + 1].
    arrivals := (self log: rules kind: #arrival at: 'n0') collect: [:e | e at: 4].
    issues := (self log: rules kind: #issue at: 'n0') collect: [:e | e at: 4].
    (bad not and: [arrivals = issues and: [arrivals = #('n0' 'n1' 'n0' 'n2' 'n0' 'n1' 'n2')]]) ifFalse: [
      misordered := misordered + 1].
    rules := aRulesClass new.
    run := LeaseRun rules: rules seed: seed options: Dictionary new.
    sim := run sim.
    rules hold: 'n0' for: 5000.
    node := sim nodeAt: 'n1'.
    node state: (node state with: { #hints -> ((rules _hintsIn: node state) with: { #turn -> #('n2' 0 0) }) }).
    bad := LeaseFamilies violates: [
      sim commit: 'w' at: 'n1'.
      sim runUntil: [(sim countOf: 'deferrals' at: 'n1') > 0] steps: 100000.
      start := sim now.
      run until: [(sim outcomeOf: 'w') ~= #pending or: [sim now > (start + 4000000)]] demandAt: #('n0') gap: 5000 owners: true].
    bad ifTrue: [failed := failed + 1].
    settle := (self settles: 'w' at: 'n1' in: rules) detect: [:e | (e at: 4) isKindOf: PBPermission] ifNone: [nil].
    (bad not and: [settle notNil and: [(settle at: 4) owner = 'n0' and: [(settle at: 2) - start < 500000]]]) ifFalse: [
      late := late + 1]].
  ^ { failed. misordered. late }.

"{ seeds failed. seeds where the restarted n1 answered or took the permit of its previous
 incarnation. seeds where the done of the new incarnation did not abandon the term at once. seeds
 where n0 issued another permission in that term }: n0 owns; n1 holds a permission (its
 replication never ends) and restarts on its disk; the permit is delivered again to the new
 incarnation; then a done of the new incarnation for that permission reaches n0 (proto_db
 test_a_restarted_holder_drops_a_permit_of_its_previous_incarnation and
 test_an_owner_counts_a_done_only_from_the_incarnation_it_issued_to, L12)."
PermitFamilies class >> restarted: aRulesClass seeds: someSeeds
  | failed answered kept issued |
  failed := 0.
  answered := 0.
  kept := 0.
  issued := 0.
  someSeeds do: [:seed | | rules run sim permit before bad inc term abandons |
    rules := aRulesClass new.
    run := self owned: rules seed: seed options: Dictionary new.
    sim := run sim.
    rules hold: 'n1' for: 100000000.
    bad := LeaseFamilies violates: [
      sim commit: 'b' at: 'n1'.
      sim runUntil: [((self settles: 'b' at: 'n1' in: rules) anySatisfy: [:e | (e at: 4) isKindOf: PBPermission])] steps: 100000.
      permit := (self sent: 'permit' by: 'n0' in: rules) last.
      term := permit at: 'term'.
      before := sim countOf: 'permits_issued' at: 'n0'.
      sim crash: 'n1' keepDisk: true.
      sim restart: 'n1'.
      sim inject: permit to: 'n1' at: sim now + 1000.
      self run: sim until: sim now + 20000.
      inc := (sim nodeAt: 'n1') state inc.
      sim inject: (PBClusterMessage type: 'done' from: 'n1' fields: { 'term' -> term. 'seq' -> (permit at: 'seq'). 'inc' -> inc.
        'outcome' -> 'none'. 'root' -> nil. 'copies' -> #(). 'ranges' -> nil }) to: 'n0' at: sim now + 1000.
      self run: sim until: sim now + 20000].
    bad ifTrue: [failed := failed + 1].
    (bad not and: [(sim countOf: 'permits_foreign_dropped' at: 'n1') = 1 and: [(self sent: 'done' by: 'n1' in: rules) isEmpty
        and: [(self settles: 'b' at: 'n1' in: rules) size = 1]]]) ifFalse: [answered := answered + 1].
    abandons := rules abandons select: [:e | e first = 'n0'].
    (bad not and: [abandons size = 1 and: [abandons first last = 'unknown']]) ifFalse: [kept := kept + 1].
    (bad not and: [(sim countOf: 'permits_issued' at: 'n0') = before
        and: [((self sent: 'permit' by: 'n0' in: rules) select: [:m | (m at: 'term') = term]) size = 1]]) ifFalse: [
      issued := issued + 1]].
  ^ { failed. answered. kept. issued }.

"{ seeds failed. seeds where the silent holder's permission did not abandon its term at valid +
 requestTimeout. seeds where a release of that term was certain. seeds where n0 issued a third
 permission in that term, or the queued n2 was not refused 'abandoned'. seeds where the late done
 changed anything at the owner. seeds where a lease expiring with a permission out did not
 abandon the term, or released it as certain }. L29, O6: n0 owns; n1 holds a permission for 2 s
 (a dying holder); n2 asks 5 ms after n1. Then the late done of n1 arrives. Lease expiry (proto_db
 test_an_owner_whose_lease_expires_with_a_permission_outstanding_releases_as_uncertain): n1
 holds, n0 is cut off from the others: its renewals fail and its lease ends first."
PermitFamilies class >> lateDone: aRulesClass seeds: someSeeds
  | failed noAbandon certain third changed expiry |
  failed := 0. noAbandon := 0. certain := 0. third := 0. changed := 0. expiry := 0.
  someSeeds do: [:seed | | rules run sim term issuedAt abandons releases refusals bad before after permit |
    rules := aRulesClass new.
    run := self owned: rules seed: seed options: Dictionary new.
    sim := run sim.
    rules hold: 'n1' for: 2000000.
    bad := LeaseFamilies violates: [
      sim commit: 'b' at: 'n1'.
      sim runUntil: [(self sent: 'permit' by: 'n0' in: rules) notEmpty] steps: 100000.
      permit := (self sent: 'permit' by: 'n0' in: rules) last.
      term := permit at: 'term'.
      issuedAt := sim now.
      sim commit: 'c' at: 'n2' time: sim now + 5000.
      sim runUntil: [(rules abandons anySatisfy: [:e | e first = 'n0']) or: [sim now > (issuedAt + 3000000)]] steps: 100000.
      before := (sim nodeAt: 'n0') state.
      sim runUntil: [(self sent: 'done' by: 'n1' in: rules) notEmpty or: [sim now > (issuedAt + 3000000)]] steps: 100000.
      self run: sim until: sim now + 5000.
      after := (sim nodeAt: 'n0') state].
    bad ifTrue: [failed := failed + 1].
    abandons := rules abandons select: [:e | e first = 'n0'].
    (bad not and: [abandons size = 1 and: [(abandons first last endsWith: 'timed out')
        and: [(abandons first at: 2) - issuedAt > ((permit at: 'valid') * 1000000 + 250000)]]]) ifFalse: [noAbandon := noAbandon + 1].
    releases := (self sent: 'release' by: 'n0' in: rules) select: [:m | (m at: 'term') = term and: [m at: 'held']].
    (releases notEmpty and: [releases allSatisfy: [:m | (m at: 'certain') not]]) ifFalse: [certain := certain + 1].
    refusals := (self sent: 'permit_no' by: 'n0' in: rules) select: [:m | (m at: 'term') = term].
    (((self sent: 'permit' by: 'n0' in: rules) select: [:m | (m at: 'term') = term]) size = 1
        and: [(refusals collect: [:m | m at: 'reason']) asArray = #('abandoned')]) ifFalse: [third := third + 1].
    (bad not and: [(self sent: 'done' by: 'n1' in: rules) notEmpty and: [before ownership = after ownership
        and: [(sim countOf: 'terms_abandoned' at: 'n0') = 1]]]) ifFalse: [changed := changed + 1].
    rules := aRulesClass new.
    run := self owned: rules seed: seed options: Dictionary new.
    sim := run sim.
    rules hold: 'n1' for: 2000000.
    bad := LeaseFamilies violates: [
      sim commit: 'b' at: 'n1'.
      sim runUntil: [(self sent: 'permit' by: 'n0' in: rules) notEmpty] steps: 100000.
      term := (self sent: 'permit' by: 'n0' in: rules) last at: 'term'.
      sim partition: #(#('n0') #('n1' 'n2')).
      issuedAt := sim now.
      sim runUntil: [(rules abandons anySatisfy: [:e | e first = 'n0']) or: [sim now > (issuedAt + 3000000)]] steps: 100000].
    bad ifTrue: [failed := failed + 1].
    abandons := rules abandons select: [:e | e first = 'n0'].
    releases := (self sent: 'release' by: 'n0' in: rules) select: [:m | (m at: 'term') = term and: [m at: 'held']].
    (bad not and: [abandons size = 1 and: [(abandons first last beginsWith: 'lease expired')
        and: [releases notEmpty and: [releases allSatisfy: [:m | (m at: 'certain') not]]]]]) ifFalse: [expiry := expiry + 1]].
  ^ { failed. noAbandon. certain. third. changed. expiry }.

"{ seeds failed. seeds where n0's own commit did not end in PBTimeoutError within 1 ms of its
 deadline. seeds where it was issued a permission }: a waiter queued at its own node's ownership
 (proto_db: _permission_from_owner leaves the queue at the deadline and permit raises, the
 ownership holding _local). acquireTimeout 300 ms; n0 owns; n1 holds a permission for 2 s, so
 the pipeline is full; n0 then commits 'x'."
PermitFamilies class >> localTimeout: aRulesClass seeds: someSeeds
  | failed late issued |
  failed := 0. late := 0. issued := 0.
  someSeeds do: [:seed | | rules run sim bad arrival settles start |
    rules := aRulesClass new.
    run := self owned: rules seed: seed options: (Dictionary new at: #acquireTimeout put: 300; yourself).
    sim := run sim.
    rules hold: 'n1' for: 2000000.
    bad := LeaseFamilies violates: [
      sim commit: 'b' at: 'n1'.
      sim runUntil: [(self sent: 'permit' by: 'n0' in: rules) notEmpty] steps: 100000.
      start := sim now.
      sim commit: 'x' at: 'n0'.
      sim runUntil: [(sim outcomeOf: 'x') ~= #pending or: [sim now > (start + 2000000)]] steps: 100000].
    bad ifTrue: [failed := failed + 1].
    arrival := ((self log: rules kind: #arrival at: 'n0') select: [:e | (e at: 4) = 'n0']) last at: 2.
    settles := self settles: 'x' at: 'n0' in: rules.
    (bad not and: [settles size = 1 and: [((settles first at: 4) isKindOf: PBTimeoutError)
        and: [((settles first at: 2) - arrival) between: 300000 and: 301000]]]) ifFalse: [late := late + 1].
    (settles anySatisfy: [:e | (e at: 4) isKindOf: PBPermission]) ifTrue: [issued := issued + 1]].
  ^ { failed. late. issued }.

"{ seeds where the minority side did not end in PBTimeoutError without a commit. seeds where
 a refusal of an older term's request forgot the owner learnt since. seeds where silence about
 an older term forgot the owner learnt since. seeds where silence did not forget the owner of
 the term asked under }. Minority (CP 1.9, proto_db test_a_minority_cannot_acquire_while_the_
 majority_can): acquireTimeout 3 s; n0 owns and commits every 20 ms; n1, which learnt that n0
 owns, is cut off and commits: its request to n0 gets no answer, it forgets n0, tries to own and
 times out. The hints (proto_db test_a_refusal_of_an_older_terms_request_keeps_the_owner_learnt_
 since, test_a_silent_owner_is_forgotten_only_for_the_term_asked_under): n0 is down; a renewal
 of n0's T1 reaches n1; n1 commits and asks n0 under T1; a renewal of T2 reaches n1 (learnt) or
 not; then n0's refusal of the T1 request, or a leaseDuration of silence."
PermitFamilies class >> minority: aRulesClass seeds: someSeeds
  | notTimedOut refusal silenceLearnt silenceKept |
  notTimedOut := 0. refusal := 0. silenceLearnt := 0. silenceKept := 0.
  someSeeds do: [:seed | | rules run sim asked settle t1 t2 hint |
    rules := aRulesClass new.
    run := LeaseRun rules: rules seed: seed options: (Dictionary new at: #acquireTimeout put: 3000; yourself).
    sim := run sim.
    run until: [(sim nodeAt: 'n1') state hints notNil and: [(sim nodeAt: 'n1') state hints ownerNode = 'n0']]
      demandAt: #('n0') gap: 20000 owners: true.
    sim partition: #(#('n1') #('n0' 'n2')).
    sim commit: 'm' at: 'n1'.
    asked := sim now.
    run until: [(sim outcomeOf: 'm') ~= #pending or: [sim now > (asked + 6000000)]] demandAt: #('n0') gap: 20000 owners: true.
    settle := (self settles: 'm' at: 'n1' in: rules) detect: [:e | true] ifNone: [nil].
    ((sim outcomeOf: 'm') = #failed and: [settle notNil and: [((settle at: 4) isKindOf: PBTimeoutError)
        and: [((settle at: 2) - asked between: 3000000 and: 3500000) and: [(sim countOf: 'ownerships' at: 'n1') = 0
        and: [(self sent: 'permit_req' by: 'n1' in: rules) notEmpty]]]]]) ifFalse: [notTimedOut := notTimedOut + 1].
    t1 := PBMembership ballotAfter: 0 rank: 0.
    t2 := PBMembership ballotAfter: t1 rank: 0.
    #(#refusal #learnt #silent) do: [:how |
      rules := aRulesClass new.
      run := LeaseRun rules: rules seed: seed options: Dictionary new.
      sim := run sim.
      sim crash: 'n0' keepDisk: true.
      self renew: t1 to: 'n1' in: sim.
      self run: sim until: sim now + 10000.
      sim commit: 'h' at: 'n1'.
      sim runUntil: [(self asks: t1 at: 'n1' in: sim) notEmpty] steps: 100000.
      how = #silent ifFalse: [self renew: t2 to: 'n1' in: sim. self run: sim until: sim now + 10000].
      how = #refusal ifTrue: [
        sim inject: (PBClusterMessage type: 'permit_no' from: 'n0' fields: { 'term' -> t2.
          'rid' -> (self asks: t1 at: 'n1' in: sim) first rid. 'inc' -> (sim nodeAt: 'n1') state inc. 'reason' -> 'not_owner' })
          to: 'n1' at: sim now + 1000].
      sim runUntil: [(self asks: t1 at: 'n1' in: sim) isEmpty] steps: 100000.
      hint := (sim nodeAt: 'n1') state hints.
      how = #refusal ifTrue: [(hint ownerTerm = t2 and: [hint ownerNode = 'n0']) ifFalse: [refusal := refusal + 1]].
      how = #learnt ifTrue: [(hint ownerTerm = t2 and: [hint ownerNode = 'n0']) ifFalse: [silenceLearnt := silenceLearnt + 1]].
      how = #silent ifTrue: [(hint ownerTerm = t1 and: [hint ownerNode isNil]) ifFalse: [silenceKept := silenceKept + 1]]]].
  ^ { notTimedOut. refusal. silenceLearnt. silenceKept }.

"A renewal of aTerm by n0 (rank 0) delivered to anId now."
PermitFamilies class >> renew: aTerm to: anId in: aSim
  aSim inject: (PBClusterMessage type: 'renew' from: 'n0' fields: { 'term' -> aTerm. 'rid' -> 1. 'inc' -> 7.
    'vs' -> (aSim nodeAt: anId) config membership fingerprint }) to: anId at: aSim now.

"The permit requests anId has outstanding under aTerm."
PermitFamilies class >> asks: aTerm at: anId in: aSim
  | state |
  state := (aSim nodeAt: anId) state.
  state holder isNil ifTrue: [^ #()].
  ^ state holder asks select: [:a | a term = aTerm].

"{ seeds where the checker reported a violation. seeds where it was the sibling-roots rule (two
 different roots carry one label and epoch) }: n0 owns; every holder takes 5 ms; n1 asks, and n2
 1 ms later. This is the stand-in form of R79/L28: an owner issuing one base twice gives two
 roots of one label and epoch (the simulator builds each at the base's epoch + 1), which the
 checker reports at once. proto_db's strict form (phase 1 ranks the uncommitted sibling of a
 higher epoch above the commit, S4 at convergence) needs the replication and base choice of
 Tasks 13-14."
PermitFamilies class >> baseTwice: aRulesClass seeds: someSeeds
  | failed siblings |
  failed := 0.
  siblings := 0.
  someSeeds do: [:seed | | rules run sim t1 text |
    rules := aRulesClass new.
    run := self owned: rules seed: seed options: Dictionary new.
    sim := run sim.
    sim ids do: [:id | rules hold: id for: 5000].
    text := [
      t1 := sim now + 10000.
      sim commit: 'b' at: 'n1' time: t1.
      sim commit: 'c' at: 'n2' time: t1 + 1000.
      sim runUntil: [(sim outcomeOf: 'b') ~= #pending and: [(sim outcomeOf: 'c') ~= #pending]] steps: 100000.
      self run: sim until: sim now + 10000.
      nil] on: Error do: [:e | (e messageText beginsWith: 'PBSim seed') ifTrue: [e messageText] ifFalse: [e pass]].
    text notNil ifTrue: [failed := failed + 1].
    (text notNil and: [text includesSubstring: 'two different roots carry label']) ifTrue: [siblings := siblings + 1]].
  ^ { failed. siblings }.
