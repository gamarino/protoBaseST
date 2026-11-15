"EXPECT: timer audit ok"
"The timer audit (tests/audit/_audit.st): for each row of PBClusterConfig timerTable, the mixed workload (3
 and 5 members, commits from every member, 5 % of the messages dropped, one crash with the disk
 kept) with the timer at 1/10 of its default, at 10 times, and skewed per member (1/2 at the even
 ranks, 2 at the odd ones), seeds 1-30 each: the checker passes every run (liveness may suffer,
 safety may not). The 3240 runs live in tests/audit, a run of their own (tests/run_tests.sh
 tests/audit, or --audit with the default set; the default run skips them): each row and mode in
 parts, tests/audit/sim_timer_audit_<row>_<mode>_part<i>.st (one part, or more where a row's runs
 are slow, AuditFamilies partsOf:mode:), each under the runner's time limit; each prints one line
 for its timer. This file is their index, in the default run, and checks the audit's own
 configuration, so a missing or renamed audit file fails the default run:
 (1) every row, mode and part has its file in tests/audit, and the file audits that part; the
     parts of a row and mode hold its 60 runs, each once;
 (2) at factor 1, AuditConfig answers every timer as the product configuration does (the
     audit's derivation of the defaults is the product's; ownerIdleRelease at its 500 ms
     reference);
 (3) at factor 10, every row changes what AuditConfig answers (each row's knob is wired to a
     timer the rules read; the row persist has no reader before the persister, Task 20, so its
     runs equal the defaults' until then);
 (4) one run per mode of the row leaseDuration on 3 members, seed 1, passes the checker;
 (5) the product's derived timers are the rows' defaults: renewalLeft half the belief,
     permitFloor a quarter of it, permissionDeadline: valid + requestTimeout."
Import from: 'protobase'.
Import from: '_check'.
Import from: '../audit/_audit'.

| c peers config missing uncovered same changed runs product |
c := Check new.
missing := OrderedCollection new.
uncovered := OrderedCollection new.
AuditConfig rows do: [:row |
  AuditFamilies modes do: [:mode | | n held |
    n := AuditFamilies partsOf: row mode: mode.
    held := OrderedCollection new.
    1 to: n do: [:i | | file |
      file := FileReference path: '../audit/' , (AuditFamilies fileFor: row mode: mode part: i).
      (file exists and: [file contents includesSubstring: (AuditFamilies callFor: row mode: mode part: i)])
        ifFalse: [missing add: file pathString].
      held addAll: (AuditFamilies runsOf: row mode: mode part: i)].
    (held size = 60 and: [held asSet size = 60 and: [held asSet = AuditFamilies allRuns asSet]])
      ifFalse: [uncovered add: row , ' ' , mode]]].
c that: '(1) every row, mode and part has its audit file' is: missing asArray equals: #().
c that: '(1) the parts of every row and mode hold its 60 runs once' is: uncovered asArray equals: #().
c that: '(1) the rows are those of timerTable' is: AuditConfig rows size equals: 18.

peers := (1 to: 3) asArray collect: [:i | PBPeer nodeId: 'n' , (i - 1) printString host: '127.0.0.1' port: 7000 + i].
config := [:row :f | AuditConfig nodeId: 'n1' peers: peers voters: nil row: row factor: f].
same := AuditConfig rows reject: [:row |
  (AuditConfig timersOf: (config value: row value: 1)) = (AuditConfig timersOf: (PBClusterConfig nodeId: 'n1' peers: peers
    options: (row = 'ownerIdleRelease' ifTrue: [Dictionary new at: #ownerIdleRelease put: 500; yourself] ifFalse: [Dictionary new])))].
c that: '(2) factor 1 answers the product''s timers (rows that differ)' is: same asArray equals: #().
changed := AuditConfig rows select: [:row |
  (AuditConfig timersOf: (config value: row value: 10)) = (AuditConfig timersOf: (config value: row value: 1))].
c that: '(3) factor 10 changes every row (rows unchanged)' is: changed asArray equals: #().

runs := AuditFamilies modes collect: [:mode | (AuditFamilies run: 'leaseDuration' mode: mode size: 3 seed: 1) first].
c that: '(4) leaseDuration, 3 members, seed 1, every mode: no violation' is: runs asArray equals: #(nil nil nil).
product := PBClusterConfig nodeId: 'n1' peers: peers options: Dictionary new.
c that: '(5) renewalLeft, permitFloor, permissionDeadline: of the product'
  is: { product renewalLeft. product permitFloor. product permissionDeadline: 400000 }
  equals: { 666666 / 2. 666666 / 4. 650000 }.
(c report = 'ok 7') ifTrue: ['timer audit ok'] ifFalse: [c report displayNl. 'timer audit failed'].
