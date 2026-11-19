"EXPECT: timer audit ok"
"The timer audit (index and rules: sim_timer_audit.st, _audit.st): the timerTable row ownerIdleRelease at
 1/2 of its default at the even ranks, 2 times at the odd ones; the mixed workload on 3 and 5 members, part 2 of 2 of the 60 runs (runs 2, 2 + 2, ...). The checker passes every run."
Import from: 'protobase'.
Import from: '_sim'.
Import from: '_audit'.

AuditFamilies audit: 'ownerIdleRelease' mode: #skewed part: 2.
