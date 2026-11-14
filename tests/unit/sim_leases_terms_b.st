"EXPECT: ok 3"
"Families 1 and 2 of the proposer's rules (cluster/proposer.st) in the simulator (_sim.st),
 over seeds 101-200 (sim_leases_terms_a.st holds seeds 1-100) with every member wanting a lease under drop 1/10, duplicate 1/20, delay up
 to 2 ms and reorder, until four terms were owned (proto_db test_cluster_terms; the scenario is
 _plants.st's LeaseFamilies terms:seeds:, the checker runs after every step with watchLeases).
 (1) One owner per term under drop/dup/reorder: no seed violates S1 or L5. (2) Two proposers
 never share a ballot: no term is asked by two members. (3) Every seed makes progress: four
 terms owned within 5 s of virtual time. Their plants (PlantMinorityWins, PlantSharedBallot)
 are sim_leases_plants.st's. Split from sim_leases.st, and in two halves, to keep each file well
 under half the runner's per-test budget."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_sim'.
Import from: '_plants'.

| c terms |
c := Check new.
terms := LeaseFamilies terms: LeaseRules seeds: (101 to: 200).
c that: 'one owner per term under drop/dup/reorder (seeds failed)' is: terms first equals: 0.
c that: 'two proposers never share a ballot (seeds with a shared term)' is: (terms at: 2) equals: 0.
c that: 'every seed owns four terms (seeds stalled)' is: terms last equals: 0.
c report displayNl.
