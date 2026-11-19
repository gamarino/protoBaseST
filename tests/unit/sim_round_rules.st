"EXPECT: ok 27"
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
 commit on a minority node ends PBTimeoutError (spec 5.7): its client ends.
 A base read failing after the permission expired (rc4 C3; proto_db test_cluster_lease_read.py,
 R212, R231, R233, R238L): (12) a commit's base read failing with exactly PBUnexpectedError after
 the permission expired is a retryable PBConflictError caused by it, nothing sent, the
 permission ending none, and the client's retry commits; (13) a subclass of PBUnexpectedError
 keeps its meaning; (14) under a valid permission the error stands; (15) a failed tier keeps its
 own error; (16) a base re-commit whose read fails sent nothing (none, not unknown); (17) the
 same after the permission expired is a retryable conflict; (18) a re-commit whose root was
 sent is never a retryable conflict (unknown). (19) to (24): the plants of those rules are
 caught. (25) A base re-commit that cannot read its base's SpaceRoot on shared storage (rc4:
 proto_db _commit_base's _load_space before its replicate) sent nothing: the permission ends
 none, the term is kept, and the commit ends with the read error; (26) the same read
 outliving the permission is a retryable conflict, and the retry commits. (27) An entry's build
 error that is not a PBDBError (ZeroDivide, an extractor's exception in a merge; indexed queries
 Task 4b, the maintainer's decision of 2026-11-19), under a valid permission and after it
 expired, on several seeds: it fails that commit alone, never turned into a conflict, and the
 commit queued after it in the same round commits (a deviation from rc4's _permit_round, which
 fails the whole round)."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_round'.

| c out fair U expired honest poisoned reread reexpired resent |
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
  is: { PBSimSoak same: [:n | fair value: (n = 1 ifTrue: [out first] ifFalse: [RoundFamilies hotKey: RoundRules new seed: n clients: 1])] over: #(1).
    PBSimSoak same: [:n | | o | o := n = 2 ifTrue: [out last] ifFalse: [RoundFamilies hotKey: RoundRules new seed: n clients: 2].
      { fair value: o. (o at: 3) > 0 }] over: #(2) }
  equals: { true. #(true true) }.

"(2)"
c that: 'reserve refusal sends nothing and is retryable ({ outcome. conflict naming sendReserve. sends of the refused root. sends_refused_reserve. replications })'
  is: (PBSimSoak same: [:n | RoundFamilies reserve: RoundRules new seed: n] over: #(1))
  equals: { #acknowledged. true. 0. 1. 1 }.

"(3)"
c that: 'build longer than the belief ({ outcome. attempts. the CC18 text. replicates. refusals counted: none, the permission expired })'
  is: (PBSimSoak same: [:n | RoundFamilies buildLonger: RoundRules new seed: n] over: #(1))
  equals: { #none. 5. true. 0. 0 }.

"(4)"
out := RoundFamilies groupBound: RoundRules new seed: 1.
('group bound: acknowledged per round ' , (out at: 3) printString) displayNl.
c that: 'the group bound leaves the rest queued and they commit next round ({ outcomes. refusals. more than one round, the first partial. re-commit then build under one permission })'
  is: (PBSimSoak same: [:n | | o | o := n = 1 ifTrue: [out] ifFalse: [RoundFamilies groupBound: RoundRules new seed: n].
    { o first. o at: 2. (o at: 3) size > 1 and: [(o at: 3) first between: 1 and: 4]. o at: 4 }] over: #(1))
  equals: { #(#acknowledged #acknowledged #acknowledged #acknowledged #acknowledged). 0. true. true }.

"(5)"
c that: 'a stale base requeues and abandons the term ({ a. b. #stale at n1. reported unknown. attempts of a. a term abandoned })'
  is: (PBSimSoak same: [:n | RoundFamilies stale: RoundRules new seed: n] over: #(1))
  equals: { #acknowledged. #acknowledged. true. true. 1. true }.

"(6)"
c that: 'unknown is never retried ({ u. attempts. a permitHeld error. reported. v })'
  is: (PBSimSoak same: [:n | RoundFamilies unknown: RoundRules new seed: n] over: #(1))
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
  is: (PBSimSoak same: [:n | fair value: (n = 3 ifTrue: [out] ifFalse: [RoundFamilies hotKey: RoundRules new seed: n clients: 1 blind: 1 heldDelay: 2000])] over: #(3))
  equals: true.

"(10)"
c that: 'a conflict in a round that ends unknown gets its own conflict ({ h. its error. a })'
  is: (PBSimSoak same: [:n | RoundFamilies conflictInUnknown: RoundRules new seed: n] over: #(1))
  equals: { #none. true. #unknown }.

"(11)"
c that: 'a commit on a minority node ends PBTimeoutError ({ outcome. error })'
  is: (PBSimSoak same: [:n | RoundFamilies minority: RoundRules new seed: n] over: #(1))
  equals: { #failed. true }.

"(12) to (18): rc4 C3. { outcome. attempts. first error's class. it is the planted error itself.
 a retryable conflict caused by it with proto_db's text. replicates under the failed permission.
 its report }"
U := [:text | PBUnexpectedError new messageText: text; yourself].
expired := PBSimSoak same: [:n | RoundFamilies baseRead: RoundRules new seed: n kind: #entry error: (U value: 'Reading segment x failed after 3 attempt(s): store unreachable') tierFailed: false late: true] over: #(1).
c that: 'a base read failing with exactly PBUnexpectedError after the permission expired is a retryable conflict, nothing sent ({ outcome. attempts. first error. the planted error. the conflict caused by it. replicates under the permission. its report })'
  is: expired
  equals: { #acknowledged. 2. PBConflictError. false. true. 0. #none }.

"(13)"
out := PBSimSoak same: [:n | { RoundFamilies baseRead: RoundRules new seed: n kind: #entry error: (PBOutcomeUnknownError new messageText: 'planted outcome unknown'; yourself) tierFailed: false late: true.
  RoundFamilies baseRead: RoundRules new seed: n kind: #entry error: (PlantedUnexpectedSubclass new messageText: 'planted subclass'; yourself) tierFailed: false late: true }] over: #(1).
c that: 'a subclass of PBUnexpectedError is never made retryable ({ PBOutcomeUnknownError. another subclass })'
  is: out
  equals: { { #unknown. 1. PBOutcomeUnknownError. true. false. 0. #none }. { #failed. 1. PlantedUnexpectedSubclass. true. false. 0. #none } }.

"(14)"
honest := PBSimSoak same: [:n | RoundFamilies baseRead: RoundRules new seed: n kind: #entry error: (U value: 'store unreachable') tierFailed: false late: false] over: #(1).
c that: 'a base read failing under a valid permission stays an honest PBUnexpectedError ({ outcome. attempts. first error. the planted error. converted. replicates. report })'
  is: honest
  equals: { #failed. 1. PBUnexpectedError. true. false. 0. #none }.

"(15)"
poisoned := PBSimSoak same: [:n | RoundFamilies baseRead: RoundRules new seed: n kind: #entry error: (U value: 'Writing manifest failed: disk full') tierFailed: true late: true] over: #(1).
c that: 'a failed tier keeps its own error under an expired permission ({ outcome. attempts. first error. the planted error. converted. replicates. report })'
  is: poisoned
  equals: { #failed. 1. PBUnexpectedError. true. false. 0. #none }.

"(16)"
reread := PBSimSoak same: [:n | RoundFamilies baseRead: RoundRules new seed: n kind: #recommit error: (U value: 'store unreachable') tierFailed: false late: false] over: #(1).
c that: 'a base re-commit whose read fails sent nothing: the permission ends none, not unknown, and the error stands ({ outcome. attempts. first error. the planted error. converted. replicates. report })'
  is: reread
  equals: { #failed. 1. PBUnexpectedError. true. false. 0. #none }.

"(17)"
reexpired := PBSimSoak same: [:n | RoundFamilies baseRead: RoundRules new seed: n kind: #recommit error: (U value: 'store unreachable') tierFailed: false late: true] over: #(1).
c that: 'a base re-commit read failing after the permission expired is a retryable conflict, nothing sent ({ outcome. attempts. first error. the planted error. the conflict caused by it. replicates. report })'
  is: reexpired
  equals: { #acknowledged. 2. PBConflictError. false. true. 0. #none }.

"(18)"
resent := PBSimSoak same: [:n | RoundFamilies recommitSent: RoundRules new seed: n] over: #(1).
c that: 'a base re-commit that sent its root is never a retryable conflict ({ outcome. one PBOutcomeUnknownError. the replication. it was the re-commit. report. reported after the permission ended })'
  is: resent
  equals: { #unknown. true. PBOutcomeUnknownError. true. #unknown. true }.

"(19)"
out := { RoundFamilies baseRead: PlantExpiredUnexpected new seed: 1 kind: #entry error: (U value: 'store unreachable') tierFailed: false late: true.
  RoundFamilies baseRead: PlantExpiredUnexpected new seed: 1 kind: #recommit error: (U value: 'store unreachable') tierFailed: false late: true }.
c that: 'PlantExpiredUnexpected is caught (an expired permission''s failed base read is not retryable: the client ends failed, not converted)'
  is: (out collect: [:o | { o first. o at: 5 }])
  equals: { { #failed. false }. { #failed. false } }.

"(20)"
out := RoundFamilies baseRead: PlantUnexpectedSubclasses new seed: 1 kind: #entry error: (PBOutcomeUnknownError new messageText: 'planted outcome unknown'; yourself) tierFailed: false late: true.
c that: 'PlantUnexpectedSubclasses is caught (an unknown outcome became a retryable conflict, retried)'
  is: { out first. out at: 4. out at: 5 }
  equals: { #acknowledged. false. true }.

"(21)"
out := { RoundFamilies baseRead: PlantPoisonedConverted new seed: 1 kind: #entry error: (U value: 'Writing manifest failed: disk full') tierFailed: true late: true.
  RoundFamilies baseRead: RoundRules new seed: 1 kind: #entry error: (U value: 'Writing manifest failed: disk full') tierFailed: true late: true event: HiddenTierFailure }.
c that: 'PlantPoisonedConverted and HiddenTierFailure are caught (a failed tier''s error became a retryable conflict)'
  is: (out collect: [:o | { o first. o at: 5 }])
  equals: { { #acknowledged. true }. { #acknowledged. true } }.

"(22)"
out := RoundFamilies baseRead: PlantValidityIgnored new seed: 1 kind: #entry error: (U value: 'store unreachable') tierFailed: false late: false.
c that: 'PlantValidityIgnored is caught (a read failing under a valid permission became a retryable conflict, held and retried)'
  is: { out first. out at: 3. out at: 4 }
  equals: { #acknowledged. PBConflictError. false }.

"(23)"
out := { RoundFamilies baseRead: PlantRecommitSentEarly new seed: 1 kind: #recommit error: (U value: 'store unreachable') tierFailed: false late: false.
  RoundFamilies baseRead: PlantRecommitSentEarly new seed: 1 kind: #recommit error: (U value: 'store unreachable') tierFailed: false late: true }.
c that: 'PlantRecommitSentEarly is caught (a re-commit whose read failed ended its permission unknown, not converted)'
  is: (out collect: [:o | { o at: 5. o last }])
  equals: { { false. #unknown }. { false. #unknown } }.

"(24)"
out := RoundFamilies recommitSent: PlantRecommitNeverSent new seed: 1.
c that: 'PlantRecommitNeverSent is caught (a re-commit whose root was sent ended its permission none)'
  is: (out at: 5)
  equals: #none.

"(25), (26): { outcome. attempts. the read error itself. a retryable conflict caused by it.
 replicates under the permission. its report. terms abandoned at n0 }"
c that: 'a base re-commit that cannot read its base sent nothing: none, the term kept, the read error ({ outcome. attempts. the read error. converted. replicates. report. terms abandoned })'
  is: (PBSimSoak same: [:n | RoundFamilies unreadableBase: RoundRules new seed: n late: false] over: #(1))
  equals: { #failed. 1. true. false. 0. #none. 0 }.

c that: 'a base re-commit whose read of its base outlives the permission is a retryable conflict, the term kept, and the retry commits ({ outcome. attempts. the read error. converted. replicates. report. terms abandoned })'
  is: (PBSimSoak same: [:n | RoundFamilies unreadableBase: RoundRules new seed: n late: true] over: #(1))
  equals: { #acknowledged. 2. false. true. 0. #none. 0 }.

"(27) { the two outcomes, sorted. attempts of the failed commit. its first error's class. the
 planted error itself. the other commit saw the error }, valid permission then expired"
c that: 'an entry''s build error that is not a PBDBError fails it alone, never a conflict; the other entry of the round commits ({ outcomes. attempts. error class. the planted error. the other saw it })'
  is: (PBSimSoak same: [:n | { RoundFamilies buildErrorAlone: RoundRules new seed: n error: (ZeroDivide new messageText: 'ZeroDivide'; yourself) late: false.
      RoundFamilies buildErrorAlone: RoundRules new seed: n error: (ZeroDivide new messageText: 'ZeroDivide'; yourself) late: true }] over: #(1 2 3 4 5))
  equals: { { #('acknowledged' 'failed'). 1. ZeroDivide. true. false }. { #('acknowledged' 'failed'). 1. ZeroDivide. true. false } }.

c report.
