"EXPECT: ok 7"
"The proposer's rules (cluster/proposer.st) in the simulator (_sim.st): acquiring, owning,
 renewing, releasing and the fairness hints (proto_db test_cluster_terms, _renewal, _fairness,
 _coordinator). The scenarios and the planted rules are in _plants.st; every node starts over a
 log holding the rejoined marker (a cluster formed before), startup grace 0, and the simulator's
 checker runs after every step (S1, and L5 with watchLeases). Families 1 and 2 (seeds 1-200
 under drop/dup/reorder) are sim_leases_terms_a.st's and
 sim_leases_terms_b.st's, the other plants sim_leases_plants.st's.
 (3) The lease runs from the send, not the win (L5, seeds 1-10): a win 533 ms after the send
 on the holder's clock is valid until the send + the belief, so the next owner's lease never
 overlaps it. A grant arriving after the belief is not a win: the simulator cannot schedule it
 (timers fire punctually), cluster_proposer_rules.st checks it directly. (4) Clock rates 2/3
 to 3/2 keep S1: an owner at rate 2/3, cut off, believes its lease no longer than the granters
 at 3/2 promise it, and another member takes the next term (seeds 1-6). (5) Releases name the
 longest waiter and the turns rotate (D-LIVE-1): 300 terms with appends costing 3 ms to sync, no
 member owns more than 60 % of them, and terms are named and taken. (6) A cancel does not end
 the back-off of a refused request: 150 cancels in 300 ms cost n1 at most 20 attempts (seeds
 1-3). (7) Replies of another incarnation are dropped and counted (L12, seeds 1-20). (8) The
 plant PlantWindowFromWin (the lease valid for the belief from the win) makes family 3 fail.
 (9) The plant PlantCancelWakes (a cancel ends the back-off, proto_db's cancel_wakes) makes
 family 6 fail."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_sim'.
Import from: '_plants'.

| c fair |
c := Check new.
c that: 'the lease runs from the send, not the win ({ seeds failed. seeds where both owned })'
  is: (LeaseFamilies window: LeaseRules seeds: (1 to: 10)) equals: #(0 10).
c that: 'clock rates 2/3 to 3/2 keep S1 ({ seeds failed. seeds where another member took over })'
  is: (LeaseFamilies drift: LeaseRules seeds: (1 to: 6)) equals: #(0 6).
fair := LeaseFamilies fairness: LeaseRules seed: 1 terms: 300.
c that: 'releases name the longest waiter and the turns rotate'
  is: { fair first <= 60. (fair at: 2) > 0. (fair at: 3) > 0 } equals: #(true true true).
c that: 'a cancel does not end the back-off of a refused request'
  is: (LeaseFamilies cancels: LeaseRules seeds: (1 to: 3)) <= 20 equals: true.
c that: 'replies of another incarnation are dropped ({ seeds owned. seeds uncounted })'
  is: (LeaseFamilies incarnations: LeaseRules seeds: (1 to: 20)) equals: #(0 0).
c that: 'the plant PlantWindowFromWin fails family 3'
  is: (LeaseFamilies window: PlantWindowFromWin seeds: (1 to: 10)) first > 0 equals: true.
c that: 'the plant PlantCancelWakes fails family 6'
  is: (LeaseFamilies cancels: PlantCancelWakes seeds: (1 to: 3)) > 20 equals: true.
c report displayNl.
