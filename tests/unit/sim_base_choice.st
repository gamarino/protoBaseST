"EXPECT: ok 7"
"The base of a term's first root (cluster/holder.st, CP 1.6, proto_db _lease_base,
 _phase_1_floor, _commit_base) in the simulator (_sim.st), proto_db
 test_cluster_recovery_base and the strict form of test_cluster_permit_incarnations'
 R79 boundary. The families, the hooked simulator and the planted wrong rules are in _base.st;
 the product rules choose every base. (1) The C1 schedule of CP 725-780 (a slow timer and a
 delayed message): an uncertain lease's recovery round ends at a majority of witnesses that
 have not accepted R'; the phase-1 floor makes R' the base; R' is acknowledged afterwards and
 stays in every committed chain. (2) Removed: I1 (proto_db _BaseUnreachable) arises only on a
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

| c out r1 slow |
c := Check new.
r1 := BaseFamilies r1.

"(1)"
out := BaseFamilies c1: BaseRules new seed: 1.
c that: 'C1: R'' is acknowledged and never dropped ({ violation. lease uncertain on R''. a base on R'' re-committed })'
  is: { out first. out at: 2.
    ((out at: 3) anySatisfy: [:d | (d isKindOf: PBBaseDecision) and: [d outcome = #ok and: [d needsCommit and: [d base key ~= r1 key]]]]) }
  equals: { nil. true. true }.


"(3)"
out := BaseFamilies m6: BaseRules new seed: 1.
c that: 'M6: every waits for the holder that knows the commit ({ known. c committed R })'
  is: { out first notNil and: [out first first]. out last }
  equals: { true. true }.

"(4)"
out := BaseFamilies refound: BaseRules new seed: 1.
c that: 'refound only when nothing is known ({ fresh. known. persisted }: outcome, label above the step, stale, reads, on P)'
  is: (out collect: [:run | { run first. (run at: 2) notNil and: [(run at: 2) >= PBMembership refoundStep]. run at: 3. (run at: 4) > 0. run at: 5 }])
  equals: { { #acknowledged. true. 1. true. nil }. { #acknowledged. false. 0. false. nil }. { #acknowledged. true. 1. true. true } }.

"(5)"
c that: 'the strict R79/L28 form ({ product: violation, c, b2 }. { plant: S4 at convergence })'
  is: { BaseFamilies baseTwice: BaseRules new seed: 1.
    ((BaseFamilies baseTwice: PlantBaseTwice new seed: 1) first ifNil: ['']) includesSubstring: 'S4: the acknowledged commit ''c''' }
  equals: { { nil. #acknowledged. #acknowledged }. true }.

"(6) A recovery round with a voter down ends at a majority of witnesses, at once."
slow := [:rules | | sim d decided |
  sim := BaseFamilies sim: rules seed: 1 ids: BaseFamilies three knowing: #('n0' 'n1') options: Dictionary new.
  sim crash: 'n1' unsynced: #keep.
  BaseFamilies commit: 'a' at: 'n2' in: sim.
  decided := (sim decisions detect: [:e | e first = 'n2'] ifNone: [nil]).
  { sim outcomeOf: 'a'. sim countOf: 'recoveries' at: 'n2'.
    decided notNil and: [(decided at: 4) < (sim nodeAt: 'n2') config requestTimeout] }].
c that: 'PlantRecoveryWaitsAll is caught ({ product: outcome, recoveries, decided before requestTimeout }. { plant })'
  is: { slow value: BaseRules new. slow value: PlantRecoveryWaitsAll new }
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
