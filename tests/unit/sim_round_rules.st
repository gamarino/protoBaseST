"EXPECT: ok 11"
"The commit round as a pure state machine (cluster/holder.st, PBCoordinatorCore round:in:now:;
 proto_db transactions.py _run_round, _permit_round, _keep, _take_kept, _await_retries; spec 5.6,
 D-LIVE-2, CC11, CC18, R121, H7) in the simulator: every node commits through its PBRoundState,
 against the product coordinator core. The families, the round's shell and the planted wrong
 rules are in _round.st. (1) Hot-key read-modify-write on 3 nodes does not starve a member
 (proto_db test_cluster_permit_hot_key, D-LIVE-2): every member commits at least once per 50
 virtual rounds, with one client per member and with two (two committed rounds under one
 permission, real acks: the retry builds on the root the permission just committed). (2) A
 reserve refusal sends nothing and is retryable (test_cluster_send_reserve). (3) A build longer
 than the belief (Review Focus 2): every round refused, nothing sent, the conflict names
 leaseDuration, sendReserve and the build time. (4) The group bound (CC11) leaves the rest
 queued and they commit next round; the first round re-commits its base first and builds on the
 re-commit under the same permission. (5) A stale base requeues and abandons the term. (6)
 Unknown is never retried. (7) PlantNoReserve fails (2). (8) PlantNoKeep fails (1). (9) Hot-key
 clients beside blind writers on every node, each held retry 2 ms (virtual) after its conflict:
 still fair (a held retry is awaited by its caller; a blind commit does not take its round).
 (10) A conflict in a round that ends unknown gets its own conflict: its client ends. (11) A
 commit on a minority node ends PBTimeoutError (spec 5.7): its client ends."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_round'.

| c out fair |
c := Check new.
"Fair (D-LIVE-2, proto_db test_hot_key_increments_never_starve_a_member): every member commits
 at least once per 50 virtual rounds, the fewest acknowledged commits of a member are at least
 0.3 of the most, and no acknowledged commit is lost."
fair := [:o | (o first allSatisfy: [:g | g <= 50]) and: [(o second allSatisfy: [:a | a > 0])
  and: [(o second inject: o second first into: [:m :a | m min: a]) >= (0.3 * (o second inject: 0 into: [:m :a | m max: a]))
  and: [(o at: 5) = 0]]]].

"(1)"
out := { RoundFamilies hotKey: RoundRules new seed: 1 clients: 1. RoundFamilies hotKey: RoundRules new seed: 2 clients: 2 }.
('hot key: longest gaps ' , (out collect: [:o | o first]) printString , ', acks ' , (out collect: [:o | o second]) printString
  , ', permits with two committed rounds ' , (out collect: [:o | o at: 3]) printString
  , ', re-commits ' , (out collect: [:o | o at: 4]) printString) displayNl.
c that: 'hot-key read-modify-write on 3 nodes does not starve a member ({ one client. two clients }: fair, two rounds committed under one permission)'
  is: { fair value: out first. fair value: out last. (out last at: 3) > 0 }
  equals: { true. true. true }.

"(2)"
out := RoundFamilies reserve: RoundRules new seed: 1.
c that: 'reserve refusal sends nothing and is retryable ({ outcome. conflict naming sendReserve. sends of the refused root. sends_refused_reserve. replications })'
  is: out
  equals: { #acknowledged. true. 0. 1. 1 }.

"(3)"
out := RoundFamilies buildLonger: RoundRules new seed: 1.
c that: 'build longer than the belief ({ outcome. attempts. the CC18 text. replicates. refusals counted: none, the permission expired })'
  is: out
  equals: { #none. 5. true. 0. 0 }.

"(4)"
out := RoundFamilies groupBound: RoundRules new seed: 1.
('group bound: acknowledged per round ' , (out at: 3) printString) displayNl.
c that: 'the group bound leaves the rest queued and they commit next round ({ outcomes. refusals. more than one round, the first partial. re-commit then build under one permission })'
  is: { out first. out at: 2. (out at: 3) size > 1 and: [(out at: 3) first between: 1 and: 4]. out at: 4 }
  equals: { #(#acknowledged #acknowledged #acknowledged #acknowledged #acknowledged). 0. true. true }.

"(5)"
out := RoundFamilies stale: RoundRules new seed: 1.
c that: 'a stale base requeues and abandons the term ({ a. b. #stale at n1. reported unknown. attempts of a. a term abandoned })'
  is: out
  equals: { #acknowledged. #acknowledged. true. true. 1. true }.

"(6)"
out := RoundFamilies unknown: RoundRules new seed: 1.
c that: 'unknown is never retried ({ u. attempts. a permitHeld error. reported. v })'
  is: out
  equals: { #unknown. 1. false. #unknown. #acknowledged }.

"(7)"
out := RoundFamilies reserve: PlantNoReserve new seed: 1.
c that: 'PlantNoReserve is caught (the refused root is handed to the replication; no CC18 refusal)'
  is: { out at: 2. (out at: 3) > 0. out at: 4 }
  equals: { false. true. 0 }.

"(8)"
out := RoundFamilies hotKey: PlantNoKeep new seed: 1 clients: 1.
('PlantNoKeep: longest gaps ' , out first printString , ', acks ' , out second printString) displayNl.
c that: 'PlantNoKeep is caught (a member starves for more than 50 rounds)'
  is: (fair value: out)
  equals: false.

"(9)"
out := RoundFamilies hotKey: RoundRules new seed: 3 clients: 1 blind: 1 heldDelay: 2000.
('hot key beside blind writers: longest gaps ' , out first printString , ', acks ' , out second printString
  , ', permits with two committed rounds ' , (out at: 3) printString , ', lost ' , (out at: 5) printString) displayNl.
c that: 'hot-key clients beside blind writers, held retries 2 ms late, do not starve a member'
  is: (fair value: out)
  equals: true.

"(10)"
c that: 'a conflict in a round that ends unknown gets its own conflict ({ h. its error. a })'
  is: (RoundFamilies conflictInUnknown: RoundRules new seed: 1)
  equals: { #none. true. #unknown }.

"(11)"
c that: 'a commit on a minority node ends PBTimeoutError ({ outcome. error })'
  is: (RoundFamilies minority: RoundRules new seed: 1)
  equals: { #failed. true }.

c report.
