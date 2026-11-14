"EXPECT: ok 7"
"The owner's rules O1-O8 at DEPTH 0 and abandoned terms (cluster/owner.st) in the simulator
 (_sim.st), with the holder side of a permit request (proto_db test_cluster_permit_backoff,
 _deferral, _incarnations and test_cluster_coordinator). The scenarios, the stand-in for the
 replication (Tasks 13-14) and the planted rules are in _permits.st; every node starts over a log
 holding the rejoined marker, startup grace 0, and the checker runs after every step.
 (1) First come, first served, own threads included: n0 issues in the order the requests arrived,
 its own commits among the others'; and a deferred request asks the busy owner as soon as it is
 known (yield_to_owner). (2) A restarted holder's done never retires a permission it did not hold
 (L12): the new incarnation drops the old permit unanswered, its done is an unknown outcome and
 the owner abandons the term, issuing nothing more in it. (3) A dead holder's late done (L29, O6):
 no done by valid + requestTimeout abandons the term (suspect, permit_no 'abandoned' to the queue,
 an uncertain release), the late done changes nothing; a lease expiring with a permission out
 abandons too. (4) The minority side times out with PBTimeoutError and commits nothing; a
 refusal, or a silence, forgets the owner only for the term asked under. (5) A faulty owner
 issuing one base twice (R79, L28): with PlantBaseTwice the checker reports the two roots of one
 label and epoch that S4 then rests on (a strict expected failure, as proto_db keeps it); the
 product rules issue the second permission only on the first one's root. (6) PlantSilenceForgets
 fails family 4. (7) PlantHintForgotten fails family 4."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_sim'.
Import from: '_plants'.
Import from: '_permits'.

| c |
c := Check new.
c that: 'first come first served, own threads included ({ failed. misordered. deferred not served })'
  is: (PermitFamilies firstCome: PermitRules seeds: (1 to: 5)) equals: #(0 0 0).
c that: 'a restarted holder''s done never retires a permission it did not hold ({ failed. answered. kept. issued })'
  is: (PermitFamilies restarted: PermitRules seeds: (1 to: 5)) equals: #(0 0 0 0).
c that: 'a dead holder''s late done ({ failed. no abandon. certain. third or not refused. changed. expiry })'
  is: (PermitFamilies lateDone: PermitRules seeds: (1 to: 3)) equals: #(0 0 0 0 0 0).
c that: 'minority side times out; owners are forgotten only for the term asked under'
  is: (PermitFamilies minority: PermitRules seeds: (1 to: 3)) equals: #(0 0 0 0).
c that: 'a faulty owner issuing one base twice ({ product violations. plant violates })'
  is: { PermitFamilies baseTwice: PermitRules seeds: (1 to: 5). (PermitFamilies baseTwice: PlantBaseTwice seeds: (1 to: 5)) > 0 }
  equals: #(0 true).
c that: 'the plant PlantSilenceForgets fails family 4'
  is: ((PermitFamilies minority: PlantSilenceForgets seeds: (1 to: 2)) at: 3) > 0 equals: true.
c that: 'the plant PlantHintForgotten fails family 4'
  is: ((PermitFamilies minority: PlantHintForgotten seeds: (1 to: 2)) at: 2) > 0 equals: true.
c report displayNl.
