"EXPECT: ok 7"
"Acceptance, the commit point and committed knowledge (cluster/acceptor.st, cluster/holder.st)
 in the simulator (_sim.st), proto_db test_cluster_acceptor_writes, _acceptor_durability,
 _durability, _chain_rule, _voters and test_cluster_root_certainty. The scenario families, the
 checking simulator (AcceptSim: every ok ack backed by a synced acceptance of its root, every
 root published committed or acknowledged accepted by a majority of the voters' synced logs,
 certain leases never below an acknowledged commit) and the planted wrong rules are in
 _accept.st; the base choice is a stand-in (Task 14). Every node starts over a log holding the
 rejoined marker, startup grace 0, and the checker runs after every step. Each check runs the
 product rules over its seeds (nothing fails) and one planted rule (caught on every seed).
 (1) Ack only after the synced append: under drops, duplicates, delays and reordering no ok ack
 precedes its synced acceptance; an acceptor crashing between the sync and its reply holds the
 root accepted after its restart, never acked it, and the commit completes without it.
 PlantAckBeforeSync is caught. (2) A power loss drops only unsynced #committed entries; a crash
 with the page cache written back restores the committed root; the chains converge.
 PlantCommittedUnlogged is caught. (3) A holder paused for 10 belief periods resumes and
 replicates under its old permission: nothing it sends is accepted (the ballot rule), its
 commit is not acknowledged; the newer owner commits. PlantNoBallotRule is caught. (4) Log
 matching: a root of the accepted term not built on the accepted root is refused until its
 pred is accepted. PlantNoLogMatching is caught. (5) Learners never count: a learner owns and
 commits; a learner's ok ack never completes a commit without a voter majority; no learner
 accepts. PlantLearnerCounts is caught. (6) A member configured with another voter set never
 helps a quorum: it drops the replicate (config_mismatches), its own requests get no grant.
 PlantNoFingerprint is caught. (7) The four certainty schedules of D45 amendment 6:
 release-carried certainty is never a commit point (L8). PlantReleaseTeachesAccepted is caught
 on the uncertain-release schedule."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_accept'.

| c seeds plantSeeds lost |
c := Check new.
seeds := (1 to: 8) asArray.
plantSeeds := #(1 2).

c that: 'ack only after the synced append ({ problems under faults. crash schedule failures }, then plant caught)'
  is: { AcceptFamilies ackAfterSync: [AcceptRules new] seeds: seeds.
    plantSeeds collect: [:n | ((AcceptFamilies ackAfterSync: [PlantAckBeforeSync new] seeds: { n }) first) > 0] }
  equals: { #(0 0). #(true true) }.

c that: 'power loss drops only unsynced committed knowledge ({ failed. seeds that lost one }, plant)'
  is: { (lost := AcceptFamilies powerLoss: [AcceptRules new] seeds: seeds) first. lost last > 0.
    (AcceptFamilies powerLoss: [PlantCommittedUnlogged new] seeds: plantSeeds) first }
  equals: { 0. true. plantSeeds size }.

c that: 'the old term''s roots are refused after a promise ({ failed. acknowledged }, plant)'
  is: { AcceptFamilies pausedHolder: [AcceptRules new] seeds: seeds.
    AcceptFamilies pausedHolder: [PlantNoBallotRule new] seeds: plantSeeds }
  equals: { #(0 0). { plantSeeds size. plantSeeds size } }.

c that: 'log matching refuses a root not built on the accepted chain (failed, plant)'
  is: { AcceptFamilies logMatching: [AcceptRules new] seeds: seeds.
    AcceptFamilies logMatching: [PlantNoLogMatching new] seeds: plantSeeds }
  equals: { 0. plantSeeds size }.

c that: 'learners never count ({ failed. counted }, plant)'
  is: { AcceptFamilies learners: [AcceptRules new] seeds: seeds.
    AcceptFamilies learners: [PlantLearnerCounts new] seeds: plantSeeds }
  equals: { #(0 0). { plantSeeds size. plantSeeds size } }.

c that: 'a member of another voter set never helps a quorum ({ failed. helped }, plant)'
  is: { AcceptFamilies voterSets: [AcceptRules new] seeds: seeds.
    AcceptFamilies voterSets: [PlantNoFingerprint new] seeds: plantSeeds }
  equals: { #(0 0). { plantSeeds size. plantSeeds size } }.

c that: 'release-carried certainty is never a commit point (schedules failed per seed, plant)'
  is: { #(1 2) collect: [:n | AcceptFamilies certainty: [AcceptRules new] schedules: #(1 2 3 4) seed: n].
    plantSeeds collect: [:n | AcceptFamilies certainty: [PlantReleaseTeachesAccepted new] schedules: #(3) seed: n] }
  equals: { #(0 0). #(1 1) }.

c report displayNl.
