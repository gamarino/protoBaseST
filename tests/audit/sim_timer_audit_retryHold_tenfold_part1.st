"EXPECT: timer audit ok"
"The timer audit (index and rules: sim_timer_audit.st, _audit.st): the timerTable row retryHold at
 10 times its default at every member; the mixed workload on 3 and 5 members, seeds 1-30. The checker passes every run."
Import from: 'protobase'.
Import from: '../unit/_sim'.
Import from: '_audit'.

AuditFamilies audit: 'retryHold' mode: #tenfold part: 1.
