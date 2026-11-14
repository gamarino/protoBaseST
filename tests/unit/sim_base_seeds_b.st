"EXPECT: ok 1"
"The base choice under faults (cluster/holder.st, CP 1.6), seeds 101-200 of the 200 of the
 brief's seeds family (sim_base_seeds_a.st and sim_base_seeds_b.st split them, each under the
 runner's time limit). Three members formed with empty logs, so the first commit of every seed
 refounds; drops, duplicates, delays, reordering, one clock 10 % fast and one 10 % slow, a
 member crashing (#any) and restarting between commits (_base.st BaseFamilies seeds:rules:).
 No seed violates the simulator's checks (S1, sibling roots, sync before reply) or the
 convergence checks (no fork, S4, unknown in all or none, H7); the run exercised recovery
 rounds, stale (refound) bases and re-commits. Each seed ends, without faults, with a last commit
 that must be acknowledged, so every member learns the newest commit before the checks."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_base'.

| c out |
c := Check new.
out := BaseFamilies seeds: (101 to: 200) rules: [BaseRules new].
c that: 'seeds 101-200 under drops and clock skew ({ violations. recoveries ran. stale bases. re-commits. first violation })'
  is: { out first. (out at: 2) > 0. (out at: 3) > 0. (out at: 4) > 0. out at: 5 }
  equals: { 0. true. true. true. nil }.
c report.
