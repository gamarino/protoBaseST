"EXPECT: timer audit ok"
"The timer audit (index and rules: sim_timer_audit.st, _audit.st): the timerTable row leaseDuration at
 10 times its default at every member; the mixed workload on 3 and 5 members, part 1 of 3 of the 60 runs (runs 1, 1 + 3, ...). The checker passes every run."
Import from: 'protobase'.
Import from: '_sim'.
Import from: '_audit'.

AuditFamilies audit: 'leaseDuration' mode: #tenfold part: 1.
