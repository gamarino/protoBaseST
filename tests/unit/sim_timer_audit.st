"EXPECT: timer audit ok"
"The timer audit (tests/audit/_audit.st): for each row of PBClusterConfig timerTable, the mixed workload (3
 and 5 members, commits from every member, 5 % of the messages dropped, one crash with the disk
 kept) with the timer at 1/10 of its default, at 10 times, and skewed per member (1/2 at the even
 ranks, 2 at the odd ones), seeds 1-30 each: the checker passes every run (liveness may suffer,
 safety may not). The 3420 runs live in tests/audit, a run of their own (tests/run_tests.sh
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
     permitFloor a quarter of it, renewBackoffFloor requestTimeout / 4 (at least 1 ms; Task 19b,
     R149a, its floors measured in Task 30), permissionDeadline: valid + requestTimeout;
 (6) the safety-only row-modes (AuditFamilies safetyOnly) are listed and real; their parts
     assert that they acknowledge nothing;
 (7) the rows not exercised yet (AuditFamilies notExercised: persist, until Task 20) have no
     reader in the cluster's sources but config.st, and their runs equal the run at factor 1:
     once a reader appears, the declaration fails here.
 (8) AuditFamilies floors declares exactly the parts of floorKeys (none missing, extra,
     misspelt or twice), each with two integer counts.
 Each part asserts its own coverage (AuditFamilies failuresOf:row:mode:part:): no violation,
 its own measured floors of strict runs and acknowledged commits, and the probe's bounds where
 the row has one."
Import from: 'protobase'.
Import from: '_check'.
Import from: '../audit/_audit'.

| c peers config missing uncovered same changed runs product expected present sources stale equal declared wanted |
c := Check new.
missing := OrderedCollection new.
uncovered := OrderedCollection new.
expected := Set new.
AuditConfig rows do: [:row |
  AuditFamilies modes do: [:mode | | n held |
    n := AuditFamilies partsOf: row mode: mode.
    held := OrderedCollection new.
    1 to: n do: [:i | | file lines |
      expected add: (AuditFamilies fileFor: row mode: mode part: i).
      file := FileReference path: '../audit/' , (AuditFamilies fileFor: row mode: mode part: i).
      lines := file exists ifTrue: [file lines collect: [:l | l trimSeparators]] ifFalse: [#()].
      (lines notEmpty and: [lines first = '"EXPECT: timer audit ok"'
          and: [lines includes: (AuditFamilies callFor: row mode: mode part: i)]])
        ifFalse: [missing add: file pathString]].
      1 to: n do: [:i | held addAll: (AuditFamilies runsOf: row mode: mode part: i)].
    (held size = 60 and: [held asSet size = 60 and: [held asSet = AuditFamilies allRuns asSet]])
      ifFalse: [uncovered add: row , ' ' , mode]]].
c that: '(1) every row, mode and part has its audit file (EXPECT line, its call on a line of its own)'
  is: missing asArray equals: #().
present := ((FileReference path: '../audit') files collect: [:f | f basename])
  select: [:b | b beginsWith: 'sim_timer_audit_'].
c that: '(1) tests/audit holds no audit file beyond those (stale or extra)'
  is: (present reject: [:b | expected includes: b]) asArray equals: #().
c that: '(1) the parts of every row and mode hold its 60 runs once' is: uncovered asArray equals: #().
c that: '(1) the rows are those of timerTable' is: AuditConfig rows size equals: 19.

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
c that: '(5) renewalLeft, permitFloor, renewBackoffFloor, permissionDeadline: of the product'
  is: { product renewalLeft. product permitFloor. product renewBackoffFloor. product permissionDeadline: 400000 }
  equals: { 666666 / 2. 666666 / 4. 62500. 650000 }.
"(6) the safety-only row-modes: declared, each a real row and mode; their parts assert it."
Transcript show: 'safety-only (checkSafe alone, no commit acknowledged; asserted by their parts): ';
  show: (AuditFamilies safetyOnly inject: '' into: [:a :k | a isEmpty ifTrue: [k] ifFalse: [a , ', ' , k]]); cr.
c that: '(6) every safety-only declaration names a row and a mode'
  is: (AuditFamilies safetyOnly reject: [:k | | parts |
    parts := k subStrings: ' '.
    (AuditConfig rows includes: parts first) and: [AuditFamilies modes includes: parts last asSymbol]]) asArray
  equals: #().
"(7) the rows not exercised yet: no source of the cluster but config.st names their timers, and
 their runs equal the run at factor 1 (3 and 5 members, seed 1), at 1/10 and at 10 times."
sources := (FileReference path: '../../src/protobase/cluster') files select: [:f | f extension = 'st' and: [f basename ~= 'config.st']].
stale := OrderedCollection new.
equal := OrderedCollection new.
AuditFamilies notExercised do: [:e |
  Transcript show: 'not exercised until ' , (e at: 2) , ': ' , e first; cr.
  sources do: [:f | (e at: 3) do: [:name |
    (f contents includesSubstring: name) ifTrue: [stale add: e first , ' (' , name , ' in ' , f basename , ')']]].
  #(3 5) do: [:size | | one |
    one := AuditFamilies run: e first mode: #one size: size seed: 1.
    #(#tenth #tenfold) do: [:mode |
      (AuditFamilies run: e first mode: mode size: size seed: 1) = one ifFalse: [equal add: e first , ' ' , mode , ' ' , size printString]]]].
c that: '(7) no cluster source but config.st reads a not-exercised row''s timer (else the declaration is stale)'
  is: stale asArray equals: #().
c that: '(7) a not-exercised row''s runs equal the run at factor 1' is: equal asArray equals: #().
"(8) floors declares exactly one floor for every part of every row-mode but the safety-only
 ones: no part missing, no key extra (a misspelt key, a stale part, a safety-only row-mode), no
 key twice; each floor is two counts."
declared := AuditFamilies floors collect: [:e | e first].
wanted := AuditFamilies floorKeys.
c that: '(8) every part has a floor (missing keys)' is: (wanted reject: [:k | declared includes: k]) equals: #().
c that: '(8) every floor names a part (extra or misspelt keys)' is: (declared reject: [:k | wanted includes: k]) equals: #().
c that: '(8) no part has two floors' is: declared size = declared asSet size equals: true.
c that: '(8) every floor is { key. strict runs. commits acknowledged } of integers'
  is: ((AuditFamilies floors reject: [:e | e size = 3 and: [(e at: 2) isInteger and: [(e at: 3) isInteger]]]) collect: [:e | e first])
  equals: #().
(c report = 'ok 15') ifTrue: ['timer audit ok'] ifFalse: [c report displayNl. 'timer audit failed'].
