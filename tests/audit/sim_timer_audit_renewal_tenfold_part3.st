"EXPECT: timer audit ok"
"The timer audit (index and rules: sim_timer_audit.st, _audit.st): the timerTable row renewal at
 10 times its default at every member; the mixed workload on 3 and 5 members, part 3 of 8 of the 60 runs (runs 3, 3 + 8, ...). The checker passes every run."
Import from: 'protobase'.
Import from: '../unit/_sim'.
Import from: '_audit'.

AuditFamilies audit: 'renewal' mode: #tenfold part: 3.
