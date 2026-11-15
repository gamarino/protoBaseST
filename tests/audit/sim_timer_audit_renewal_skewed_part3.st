"EXPECT: timer audit ok"
"The timer audit (index and rules: sim_timer_audit.st, _audit.st): the timerTable row renewal at
 1/2 of its default at the even ranks, 2 times at the odd ones; the mixed workload on 3 and 5 members, part 3 of 3 of the 60 runs (runs 3, 3 + 3, ...). The checker passes every run."
Import from: 'protobase'.
Import from: '_sim'.
Import from: '_audit'.

AuditFamilies audit: 'renewal' mode: #skewed part: 3.
