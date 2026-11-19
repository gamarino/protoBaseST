"EXPECT: timer audit ok"
"The timer audit (index and rules: sim_timer_audit.st, _audit.st): the timerTable row permitFloor at
 1/2 of its default at the even ranks, 2 times at the odd ones; the mixed workload on 3 and 5 members, seeds 1-30. The checker passes every run."
Import from: 'protobase'.
Import from: '_sim'.
Import from: '_audit'.

AuditFamilies audit: 'permitFloor' mode: #skewed part: 1.
