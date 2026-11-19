"EXPECT: ok 8"
"The base of a term's first root (cluster/holder.st, CP 1.6, proto_db _lease_base,
 _phase_1_floor, _commit_base) in the simulator (_sim.st), proto_db
 test_cluster_recovery_base and the strict form of test_cluster_permit_incarnations'
 R79 boundary. The families, the hooked simulator and the planted wrong rules are in _base.st;
 the product rules choose every base. (1) The C1 schedule of CP 725-780 (a slow timer and a
 delayed message): an uncertain lease's recovery round ends at a majority of witnesses that
 have not accepted R'; the phase-1 floor makes R' the base; R' is acknowledged afterwards and
 stays in every committed chain; at seed 1, as the reviewer reproduced it, a re-commits R' first
 (the soak, PBST_SIM_SEEDS, raises the seed-free part only). (2) Removed: I1 (proto_db _BaseUnreachable) arises only on a
 local-records tier (Phase D); over shared storage an unreadable base fails its re-commit build,
 nothing sent (rc4 R233, sim_round_rules.st (25), (26)). (3) M6: a
 recovery with every waits for the holder that knows the commit, and learns it. (4) Refound
 only when nothing is known: a fresh cluster refounds once (stale, terms raised by refoundStep),
 a cluster where some member knows r1 recovers it without reading the storage, and a cluster
 whose logs know nothing refounds from the persisted root. (5) The strict R79/L28 form: with
 PlantBaseTwice phase 1 ranks the uncommitted higher-epoch sibling above the commit and the run
 fails S4 at convergence; the product does not. (6)-(8) PlantRecoveryWaitsAll (a recovery with
 a voter down lasts requestTimeout), PlantRecoveryEveryIgnored (M6 misses the commit) and
 PlantC1NoFloor (C1 drops R': S4) are each caught by their schedule. The seeds family is in sim_base_seeds_a.st and sim_base_seeds_b.st."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_base'.

| c out r1 slow c1 onRp |
c := Check new.
r1 := BaseFamilies r1.
c1 := BaseFamilies c1: BaseRules new seed: 1.

"(1)"
onRp := [:o :mustRecommit | (o at: 3) anySatisfy: [:d | (d isKindOf: PBBaseDecision) and: [d outcome = #ok
  and: [(mustRecommit not or: [d needsCommit]) and: [d base key ~= r1 key]]]]].
c that: 'C1: R'' is acknowledged and never dropped ({ violation. lease uncertain on R''. a base on R'' })'
  is: (PBSimSoak same: [:n | | o |
    o := n = 1 ifTrue: [c1] ifFalse: [BaseFamilies c1: BaseRules new seed: n].
    { o first. o at: 2. onRp value: o value: false }] over: #(1))
  equals: { nil. true. true }.
"The reviewer's schedule as reproduced at seed 1: a's base on R' is a re-commit (R' not yet
 learnt committed). Another seed may let a learn R' committed first and build on it directly
 (seeds 8 and 10 of the Task 30 soak), so this one is not raised by the soak."
c that: 'C1 at seed 1: a re-commits R'' before its commit'
  is: (onRp value: c1 value: true)
  equals: true.


"(3)"
c that: 'M6: every waits for the holder that knows the commit ({ known. c committed R })'
  is: (PBSimSoak same: [:n | | o | o := BaseFamilies m6: BaseRules new seed: n. { o first notNil and: [o first first]. o last }] over: #(1))
  equals: { true. true }.

"(4)"
c that: 'refound only when nothing is known ({ fresh. known. persisted }: outcome, label above the step, stale, reads, on P)'
  is: (PBSimSoak same: [:n | (BaseFamilies refound: BaseRules new seed: n) collect: [:run |
    { run first. (run at: 2) notNil and: [(run at: 2) >= PBMembership refoundStep]. run at: 3. (run at: 4) > 0. run at: 5 }]] over: #(1))
  equals: { { #acknowledged. true. 1. true. nil }. { #acknowledged. false. 0. false. nil }. { #acknowledged. true. 1. true. true } }.

"(5)"
c that: 'the strict R79/L28 form ({ product: violation, c, b2 }. { plant: S4 at convergence })'
  is: { PBSimSoak same: [:n | BaseFamilies baseTwice: BaseRules new seed: n] over: #(1).
    ((BaseFamilies baseTwice: PlantBaseTwice new seed: 1) first ifNil: ['']) includesSubstring: 'S4: the acknowledged commit ''c''' }
  equals: { { nil. #acknowledged. #acknowledged }. true }.

"(6) A recovery round with a voter down ends at a majority of witnesses, at once."
slow := [:rules :seed | | sim d decided |
  sim := BaseFamilies sim: rules seed: seed ids: BaseFamilies three knowing: #('n0' 'n1') options: Dictionary new.
  sim crash: 'n1' unsynced: #keep.
  BaseFamilies commit: 'a' at: 'n2' in: sim.
  decided := (sim decisions detect: [:e | e first = 'n2'] ifNone: [nil]).
  { sim outcomeOf: 'a'. sim countOf: 'recoveries' at: 'n2'.
    decided notNil and: [(decided at: 4) < (sim nodeAt: 'n2') config requestTimeout] }].
c that: 'PlantRecoveryWaitsAll is caught ({ product: outcome, recoveries, decided before requestTimeout }. { plant })'
  is: { PBSimSoak same: [:n | slow value: BaseRules new value: n] over: #(1). slow value: PlantRecoveryWaitsAll new value: 1 }
  equals: { { #acknowledged. 1. true }. { #acknowledged. 1. false } }.

"(7)"
out := BaseFamilies m6: PlantRecoveryEveryIgnored new seed: 1.
c that: 'PlantRecoveryEveryIgnored is caught (c does not learn the commit)'
  is: out last
  equals: false.

"(8)"
out := BaseFamilies c1: PlantC1NoFloor new seed: 1.
c that: 'PlantC1NoFloor is caught (S4 at convergence: R'' dropped)'
  is: ((out first ifNil: ['']) includesSubstring: 'S4: the acknowledged commit ''rp''')
  equals: true.

c report.
