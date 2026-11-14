"EXPECT: ok 5"
"The planted rules of _plants.st that sim_leases.st does not run, each making its family of
 sim_leases_terms.st and sim_leases.st fail (CC13), each through a violation the checker reports
 or the family's own count: (1) PlantMinorityWins (an attempt not lost counts as won at its
 close) fails family 1, one owner per term under drop/dup/reorder. (2) PlantSharedBallot (every
 member asks the ballots of rank 0) fails family 2, two proposers never share a ballot. (3)
 PlantNoDriftMargin (the lease valid for leaseDuration from the send) fails family 4, clock rates
 2/3 to 3/2 keep S1. (4) PlantNoTurns (a release names nobody) fails family 5, the turns rotate:
 one member keeps re-winning its own term. (5) PlantAnyIncarnation (a reply of another
 incarnation taken) fails family 7."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_sim'.
Import from: '_plants'.

| c |
c := Check new.
c that: 'PlantMinorityWins fails family 1'
  is: (LeaseFamilies terms: PlantMinorityWins seeds: (1 to: 20)) first > 0 equals: true.
c that: 'PlantSharedBallot fails family 2'
  is: ((LeaseFamilies terms: PlantSharedBallot seeds: (1 to: 10)) at: 2) > 0 equals: true.
c that: 'PlantNoDriftMargin fails family 4'
  is: (LeaseFamilies drift: PlantNoDriftMargin seeds: (1 to: 3)) first > 0 equals: true.
c that: 'PlantNoTurns fails family 5'
  is: (LeaseFamilies fairness: PlantNoTurns seed: 1 terms: 20) first > 60 equals: true.
c that: 'PlantAnyIncarnation fails family 7'
  is: (LeaseFamilies incarnations: PlantAnyIncarnation seeds: (1 to: 5)) first > 0 equals: true.
c report displayNl.
