"_audit.st: the timer audit (tests/audit/sim_timer_audit_<row>_<mode>_part<i>.st, and its index
 tests/unit/sim_timer_audit.st; a helper: the runner never runs files whose name starts with _).
 Test support, not product (CC12, CC13). It imports the simulator's helpers by name (_sim,
 _round): from tests/unit, the working directory; from tests/audit, STPATH (the runner adds
 tests/unit for the audit's files). One name per helper: protoST loads a module once per name.

  AuditConfig    a PBClusterConfig whose one timer row (a name of PBClusterConfig timerTable) is
                 scaled by a factor: the options derive as the product derives them from the
                 option set to the scaled value (leaseDuration scaled moves the default margin,
                 belief, reserve, startup grace and idle end with it), and the constants of the
                 protocol and the derived timers (renewalLeft, permitFloor, permissionDeadline:,
                 idleEnd, wakeSpread, the straggle, turnSilence, gatherAttempts, the held
                 retries) answer the scaled value. Built without the constructor's validation:
                 the audit runs the rules with values the constructor refuses too, since those
                 refusals guard liveness (the R78b belief, R121's reserve), never safety (L4: the
                 lease carries no safety, the ballots fence). Durations are rounded to whole
                 microseconds; counts and the straggle factor to whole numbers, at least 1. Two
                 values have no room: driftMargin scaled to leaseDuration or more leaves no
                 belief, so it is capped at leaseDuration - 1 us (a belief of 1 us: no lease is
                 usable); ownerIdleRelease is off by default, so the audit scales a reference
                 of 500 ms (proto_db's tests' value).
  AuditFamilies  the mixed workload: 3 or 5 members (all voters), formed before (each log the
                 rejoined marker); drops of 5 % of the messages (delays of up to 1 ms, each link
                 in order); from the end of the longest startup grace, every member commits
                 twice, one commit at a time, all members at once; after a drawn number of
                 resolved commits a drawn member crashes (#drop: power loss, its disk kept) and
                 restarts up to 500 ms later. Then the faults end, every member runs, the queue
                 drains, and a last commit z is asked. Each phase is bounded in virtual time and
                 in steps (AuditFamilies bounds; a renewal
                 storm after a lost renewal, gamarino/ProtoDB#1, kept as proto_db rc3
                 behaviour, can keep a queue busy): liveness may suffer, safety may not. When
                 z is acknowledged and every live member shows the same committed head (they
                 have caught up, AuditFamilies caughtUp:), the checks are the strict ones
                 (checkConverged); otherwise the safety checks that do not need the members to
                 have caught up (checkSafe). The checker of every step (S1,
                 sibling roots, sync before reply) runs in both."

Import from: 'protobase'.
Import from: '_sim'.
Import from: '_round'.

"=== AuditConfig =============================================================="

PBClusterConfig subclass: #AuditConfig instanceVariableNames: 'row factor'.

"The timer rows the audit scales: every name of PBClusterConfig timerTable."
AuditConfig class >> rows
  ^ PBClusterConfig timerTable collect: [:r | r first].

"The configuration of anId among somePeers (voters someVoters, nil: the default) with the
 timer aRow scaled by aFactor (a Number > 0)."
AuditConfig class >> nodeId: anId peers: somePeers voters: someVoters row: aRow factor: aFactor
  | options base |
  (self rows includes: aRow) ifFalse: [^ Error signal: 'AuditConfig: no timer row ' , aRow printString].
  options := Dictionary new.
  someVoters isNil ifFalse: [options at: #voters put: someVoters].
  "The membership and rank, validated by the product."
  base := PBClusterConfig nodeId: anId peers: somePeers options: options.
  ^ self basicNew
    _setMembership: base membership nodeId: anId durations: (self durationsFor: aRow factor: aFactor)
      authKey: nil seed: nil transport: nil clock: nil;
    setRow: aRow factor: aFactor;
    yourself.

"The durations of the options (microseconds), derived as PBClusterConfig nodeId:peers:options:
 derives them from defaults, with the option of aRow set to its default scaled by aFactor."
AuditConfig class >> durationsFor: aRow factor: aFactor
  | scale duration margin belief request reserve grace low high acquire interval lag idle |
  scale := [:name :x | name = aRow ifTrue: [(x * aFactor) rounded] ifFalse: [x]].
  duration := scale value: 'leaseDuration' value: 2000000.
  margin := scale value: 'driftMargin' value: (duration * 2 + 2) // 3.
  margin := margin min: duration - 1.
  belief := duration - margin.
  request := scale value: 'requestTimeout' value: 250000.
  reserve := scale value: 'sendReserve' value: (request min: belief // 4).
  grace := scale value: 'startupGrace' value: duration + margin.
  low := scale value: 'backoff' value: 1000.
  high := scale value: 'backoff' value: 50000.
  acquire := scale value: 'acquireTimeout' value: 30000000.
  interval := (scale value: 'persist' value: 50000) max: 1.
  lag := scale value: 'persist' value: 1000000.
  idle := aRow = 'ownerIdleRelease' ifTrue: [(500000 * aFactor) rounded max: 1] ifFalse: [nil].
  ^ Dictionary new
    at: #leaseDuration put: duration;
    at: #driftMargin put: margin;
    at: #requestTimeout put: request;
    at: #sendReserve put: reserve;
    at: #acquireTimeout put: acquire;
    at: #backoffLow put: low;
    at: #backoffHigh put: high;
    at: #startupGrace put: grace;
    at: #persistInterval put: interval;
    at: #persistLag put: lag;
    at: #ownerIdleRelease put: idle;
    yourself.

AuditConfig >> setRow: aRow factor: aFactor
  row := aRow.
  factor := aFactor.

AuditConfig >> row
  ^ row.

AuditConfig >> factor
  ^ factor.

"aValue (microseconds) scaled when aName is the audited row."
AuditConfig >> _micros: aValue row: aName
  ^ aName = row ifTrue: [(aValue * factor) rounded] ifFalse: [aValue].

"aCount scaled when aName is the audited row: a whole number, at least 1."
AuditConfig >> _count: aCount row: aName
  ^ aName = row ifTrue: [(aCount * factor) rounded max: 1] ifFalse: [aCount].

AuditConfig >> renewalLeft
  ^ row = 'renewal' ifTrue: [super renewalLeft * factor] ifFalse: [super renewalLeft].

AuditConfig >> permitFloor
  ^ row = 'permitFloor' ifTrue: [super permitFloor * factor] ifFalse: [super permitFloor].

AuditConfig >> permissionDeadline: aValid
  ^ self _micros: (super permissionDeadline: aValid) row: 'permissionDeadline'.

AuditConfig >> idleEnd
  ^ self _micros: super idleEnd row: 'idleEnd'.

AuditConfig >> wakeSpread
  ^ self _micros: super wakeSpread row: 'wakeSpread'.

AuditConfig >> minStraggle
  ^ self _micros: super minStraggle row: 'straggle'.

AuditConfig >> straggleFactor
  ^ self _count: super straggleFactor row: 'straggle'.

AuditConfig >> turnSilence
  ^ self _micros: super turnSilence row: 'turnSilence'.

AuditConfig >> gatherAttempts
  ^ self _count: super gatherAttempts row: 'gatherAttempts'.

AuditConfig >> retryHold
  ^ self _micros: super retryHold row: 'retryHold'.

AuditConfig >> retryWait
  ^ self _micros: super retryWait row: 'retryHold'.

AuditConfig >> permitRetries
  ^ self _count: super permitRetries row: 'retryHold'.

"Every timer accessor of a configuration, in a fixed order (factor 1 must answer the product's)."
AuditConfig class >> timersOf: aConfig
  ^ { aConfig leaseDuration. aConfig driftMargin. aConfig belief. aConfig renewalLeft. aConfig permitFloor.
    aConfig idleEnd. aConfig ownerIdleRelease. aConfig requestTimeout. aConfig sendReserve.
    aConfig permissionDeadline: 123456. aConfig startupGrace. aConfig backoffLow. aConfig backoffHigh.
    aConfig wakeSpread. aConfig minStraggle. aConfig straggleFactor. aConfig turnSilence. aConfig acquireTimeout.
    aConfig gatherAttempts. aConfig persistInterval. aConfig persistLag. aConfig retryHold. aConfig retryWait.
    aConfig permitRetries }.

"=== AuditFamilies ============================================================"

Object subclass: #AuditFamilies.

AuditFamilies class >> ids: aSize
  ^ aSize = 3 ifTrue: [#('n0' 'n1' 'n2')] ifFalse: [#('n0' 'n1' 'n2' 'n3' 'n4')].

"The factor of the member of rank r under aMode: #tenth (1/10 at every member), #tenfold (10 at
 every member) or #skewed (1/2 at the even ranks, 2 at the odd ones); #one, 1."
AuditFamilies class >> factor: aMode rank: r
  aMode = #tenth ifTrue: [^ 1/10].
  aMode = #tenfold ifTrue: [^ 10].
  aMode = #skewed ifTrue: [^ r even ifTrue: [1/2] ifFalse: [2]].
  "The defaults (the index's comparison, not an audit mode)."
  aMode = #one ifTrue: [^ 1].
  ^ Error signal: 'AuditFamilies: a mode is #tenth, #tenfold or #skewed, not ' , aMode printString.

"A PBSim of aSize members running the product rules, aRow scaled under aMode."
AuditFamilies class >> sim: aRow mode: aMode size: aSize seed: n
  | ids logs voters |
  ids := self ids: aSize.
  logs := Dictionary new.
  ids do: [:id | logs at: id put: { PBLogAppend kind: #rejoined label: 0 root: nil sync: true }].
  voters := aSize = 3 ifTrue: [nil] ifFalse: [ids].
  ^ PBSim seed: n ids: ids rules: PBCoordinatorCore new
    configs: [:id :peers | AuditConfig nodeId: id peers: peers voters: voters row: aRow
      factor: (self factor: aMode rank: (ids indexOf: id) - 1)]
    logs: logs.

"Steps aSim until aBlock answers true (before each step), nothing is due, n steps ran or the
 virtual time passed anEnd; answers the steps run."
AuditFamilies class >> run: aSim until: aBlock steps: n end: anEnd
  1 to: n do: [:i |
    (aBlock value or: [aSim now > anEnd]) ifTrue: [^ i - 1].
    aSim step ifFalse: [^ i - 1]].
  ^ n.

"The bounds of one run's phases: { steps. virtual microseconds } of the workload, of each drain,
 and of the last commit. A healthy run takes some thousands of steps in a few virtual seconds;
 a run whose timer leaves no liveness (no lease usable, no permission issued, a renewal storm)
 stops at these bounds and is checked as it stands. (A bound on steps without a resolved commit
 was tried and dropped: it ended healthy runs during a crash's recovery, and their z then failed,
 leaving them to the weaker checkSafe.)"
AuditFamilies class >> bounds
  ^ #(#(8000 15000000) #(2000 3000000) #(4000 8000000)).

"Whether the members of aSim have caught up, so the strict checks (checkConverged) apply: every
 live member shows the same committed head and has learnt every acknowledged or published root
 (checkSafe finds no pair not yet learnt; it also signals any violation of its rules). Both are
 needed: a proposer answers acknowledged a step before its own acceptor records the root, when
 every head is still the older one; and a drain bounded in steps can end with a done or a learn
 still in flight (or a renewal storm, gamarino/ProtoDB#1, holding the queue). Judging such a
 run by the strict rules would report a member's lag as a lost commit."
AuditFamilies class >> caughtUp: aSim
  | heads |
  heads := (aSim ids select: [:id | (aSim nodeAt: id) isUp])
    collect: [:id | (aSim nodeAt: id) committed ifNotNil: [:k | aSim keyText: k]].
  ^ heads asSet size <= 1 and: [aSim checker checkSafe = 0].

"The end of a run, the strict-or-safe gate: the strict checks (checkConverged) when z was
 acknowledged and the members have caught up (caughtUp:), else the safety checks that do not
 need them to have (checkSafe). Answers { strict. (root, node) pairs not yet learnt }; a
 violation signals. A real divergence is never taken for a lag: forked heads fail checkHeads in
 either form, and a head that does not precede a lost acknowledged or published root fails
 checkSafe (sim_checker_plants.st plants both)."
AuditFamilies class >> judge: aSim z: isAcknowledged
  (isAcknowledged and: [self caughtUp: aSim]) ifTrue: [
    aSim checker checkConverged.
    ^ #(true 0)].
  ^ { false. aSim checker checkSafe }.

"A RoundSim of aSize members whose commits run through the product's commit round (the reader of
 retryHold, retryWait and permitRetries), aRow scaled under aMode, each log formed over r1
 committed (RoundFamilies r1); a held retry is queued 20 ms (virtual) after its conflict: past a
 hold of 1/10 of the default (10 ms), within the default's (100 ms)."
AuditFamilies class >> roundSim: aRow mode: aMode size: aSize seed: n
  | ids logs voters sim |
  ids := self ids: aSize.
  logs := Dictionary new.
  ids do: [:id | logs at: id put: {
    PBLogAppend kind: #accepted label: RoundFamilies r1 label root: RoundFamilies r1 record sync: true.
    PBLogAppend kind: #committed label: RoundFamilies r1 label root: RoundFamilies r1 record sync: true.
    PBLogAppend kind: #rejoined label: 0 root: nil sync: true }].
  voters := aSize = 3 ifTrue: [nil] ifFalse: [ids].
  sim := RoundSim seed: n ids: ids rules: PBCoordinatorCore new
    configs: [:id :peers | AuditConfig nodeId: id peers: peers voters: voters row: aRow
      factor: (self factor: aMode rank: (ids indexOf: id) - 1)]
    logs: logs.
  sim heldDelay: 20000.
  ^ sim.

"The rows whose workload is the commit round's (roundSim:mode:size:seed:)."
AuditFamilies class >> roundRows
  ^ #('retryHold').

"aToken committed at anId, asked at aTime: a synthetic transaction of PBSim, or a hot
 read-modify-write of the commit round (10 retries, 1 ms builds; z is a blind write)."
AuditFamilies class >> commit: aToken at: anId time: aTime in: aSim
  (aSim isKindOf: RoundSim) ifFalse: [^ aSim commit: aToken at: anId time: aTime].
  ^ aSim run: aToken at: anId hot: aToken ~= 'z' builds: #(1000) retries: 10 time: aTime.

"Whether anError is the acquire timeout (PBCoordinatorCore _timeOut:because:in:effects: when
 acquireTimeout passes: a PBTimeoutError, 'could not obtain a write permission within')."
AuditFamilies class >> isAcquireTimeout: anError
  ^ (anError isKindOf: PBTimeoutError)
    and: [(anError messageText ifNil: ['']) includesSubstring: 'could not obtain a write permission within'].

"The probe of aRow, after the workload, before the faults end: a schedule under which the core
 reads the row's timer, and the count that shows it did; nil for a row with none. acquireTimeout:
 the last running member that owns no lease (an owner commits under its lease and never waits
 for a permit), alone in a partition, commits 'probe' and waits up to 6 s (virtual): 1 when the
 commit timed out (#failed: a PBTimeoutError, 3 s at 1/10), else 0 (still waiting at 30 s and
 more); only that timeout counts (isAcquireTimeout:), not any failed outcome. gatherAttempts: the last member loses its disk and restarts while the second member is
 alone in a partition, for 4 s: the largest gather attempt its rejoin reached (the gather asks
 the silent member again up to gatherAttempts attempts). retryHold: the holds of a kept
 permission that ran out (RoundSim holdsExpired). Answers { the count. the steps it ran }."
AuditFamilies class >> probe: aRow in: aSim
  | ids m k end most r steps |
  ids := aSim ids.
  m := ids last.
  "Only the rows with a probe restart the last member (if it is the workload's crashed member,
   still down) before the faults end: the others restart it after the heal, as before."
  (#('acquireTimeout' 'gatherAttempts') includes: aRow) ifTrue: [
    (aSim nodeAt: m) isUp ifFalse: [aSim restart: m]].
  aRow = 'acquireTimeout' ifTrue: [
    m := ids reverse detect: [:id | | node |
        node := aSim nodeAt: id.
        node isUp and: [node state ownership isNil]]
      ifNone: [m].
    aSim partition: { ids copyWithout: m. { m } }.
    aSim commit: 'probe' at: m.
    end := aSim now + 6000000.
    steps := self run: aSim until: [(aSim outcomeOf: 'probe') ~= #pending] steps: 30000 end: end.
    ^ { (self isAcquireTimeout: (aSim failureOf: 'probe')) ifTrue: [1] ifFalse: [0]. steps }].
  aRow = 'gatherAttempts' ifTrue: [
    k := ids at: 2.
    aSim crash: m keepDisk: false.
    aSim partition: { ids reject: [:id | id = k]. { k } }.
    aSim restart: m.
    most := 0.
    end := aSim now + 4000000.
    steps := self run: aSim until: [
        r := (aSim nodeAt: m) state rejoin.
        (r notNil and: [r phase = #gather]) ifTrue: [most := most max: r attempt].
        false]
      steps: 30000 end: end.
    ^ { most. steps }].
  aRow = 'retryHold' ifTrue: [^ { aSim holdsExpired. 0 }].
  ^ #(nil 0).

"One run: { violation text or nil. z acknowledged. commits acknowledged. (root, node) pairs not
 learnt (checkSafe; 0 when the strict checks ran). steps run. strict checks ran. the probe's
 count (nil: the row has no probe) }."
AuditFamilies class >> run: aRow mode: aMode size: aSize seed: n
  | sim ids pick start pending left resolved crashAt victim restartAt token violation z acked behind steps b tick strict probe out |
  sim := (self roundRows includes: aRow)
    ifTrue: [self roundSim: aRow mode: aMode size: aSize seed: n]
    ifFalse: [self sim: aRow mode: aMode size: aSize seed: n].
  ids := sim ids.
  sim faults: (PBSimFaults drop: 1/20 duplicate: 0 delay: 1000 reorder: false).
  pick := Random seed: n * 7919 + 17.
  start := (ids inject: 0 into: [:m :id | m max: (sim nodeAt: id) config startupGrace]) + 1000.
  pending := Dictionary new.
  left := Dictionary new.
  ids do: [:id | left at: id put: 2].
  resolved := 0.
  crashAt := (pick nextInt: ids size * 2) - 1.
  victim := nil.
  restartAt := nil.
  token := 0.
  behind := 0.
  steps := 0.
  strict := false.
  probe := nil.
  b := self bounds.
  violation := [
    steps := steps + (self run: sim until: [
      ids do: [:id | | p |
        p := pending at: id ifAbsent: [nil].
        (p notNil and: [(sim outcomeOf: p) ~= #pending]) ifTrue: [
          pending removeKey: id. resolved := resolved + 1. p := nil].
        (p isNil and: [(sim nodeAt: id) isUp and: [(left at: id) > 0]]) ifTrue: [
          token := token + 1.
          p := 'c' , token printString.
          pending at: id put: p.
          left at: id put: (left at: id) - 1.
          self commit: p at: id time: (sim now max: start) in: sim]].
      (victim isNil and: [resolved >= crashAt]) ifTrue: [
        victim := ids at: (pick nextInt: ids size).
        sim crash: victim keepDisk: true.
        pending removeKey: victim ifAbsent: [nil].
        restartAt := sim now + (pick nextInt: 500000)].
      (restartAt notNil and: [sim now >= restartAt]) ifTrue: [sim restart: victim. restartAt := nil].
      victim notNil and: [restartAt isNil and: [pending isEmpty and: [ids allSatisfy: [:id | (left at: id) = 0]]]]]
      steps: (b at: 1) first end: start + (b at: 1) last).
    out := self probe: aRow in: sim.
    probe := out first.
    steps := steps + out last.
    sim heal.
    sim faults: PBSimFaults none.
    ids do: [:id | (sim nodeAt: id) isUp ifFalse: [sim restart: id]].
    steps := steps + (self run: sim until: [false] steps: (b at: 2) first end: sim now + (b at: 2) last).
    self commit: 'z' at: (ids at: (pick nextInt: ids size)) time: sim now in: sim.
    steps := steps + (self run: sim until: [(sim outcomeOf: 'z') ~= #pending] steps: (b at: 3) first end: sim now + (b at: 3) last).
    tick := 0.
    steps := steps + (self run: sim until: [
        tick := tick + 1.
        tick \\ 32 = 0 and: [(sim outcomeOf: 'z') = #acknowledged and: [self caughtUp: sim]]]
      steps: (b at: 2) first end: sim now + (b at: 2) last).
    z := (sim outcomeOf: 'z') = #acknowledged.
    out := self judge: sim z: z.
    strict := out first.
    behind := out last.
    nil] on: Error do: [:e |
      ((e messageText ifNil: ['']) includesSubstring: 'PBSim seed') ifFalse: [e signal].
      e messageText].
  acked := (sim commitOrder select: [:k | (sim outcomeOf: k) = #acknowledged]) size.
  ^ { violation. z == true. acked. behind. steps. strict. probe }.

"{ runs. violations. runs whose z was acknowledged. commits acknowledged. (root, node) pairs
 not learnt. the first violation's text or nil. steps. runs that got the strict checks. the
 probe's count summed (nil: no probe) } of aRow under aMode over someRuns, each a { size. seed }
 pair."
AuditFamilies class >> row: aRow mode: aMode runs: someRuns
  | runs failed zs acked behind first steps strict probe |
  runs := 0. failed := 0. zs := 0. acked := 0. behind := 0. first := nil. steps := 0. strict := 0. probe := nil.
  someRuns do: [:r | | out |
    out := self run: aRow mode: aMode size: r first seed: r last.
    runs := runs + 1.
    (out at: 1) notNil ifTrue: [
      failed := failed + 1.
      first isNil ifTrue: [first := aRow , ' ' , aMode , ' ' , r first printString , ' nodes: ' , (out at: 1)]].
    (out at: 2) ifTrue: [zs := zs + 1].
    acked := acked + (out at: 3).
    behind := behind + (out at: 4).
    steps := steps + (out at: 5).
    (out at: 6) ifTrue: [strict := strict + 1].
    (out at: 7) notNil ifTrue: [probe := (probe ifNil: [0]) + (out at: 7)]].
  ^ { runs. failed. zs. acked. behind. first. steps. strict. probe }.

"The modes of the audit, in order."
AuditFamilies class >> modes
  ^ #(#tenth #tenfold #skewed).

"The runs of one row and mode: { size. seed } for 3 and 5 members, seeds 1-30 (60 runs)."
AuditFamilies class >> allRuns
  | all |
  all := OrderedCollection new.
  #(3 5) do: [:size | (1 to: 30) do: [:seed | all add: { size. seed }]].
  ^ all asArray.

"The number of files the runs of aRow under aMode are split into, so that each file stays under
 the runner's time limit (some 250 s): a row whose timer leaves no liveness runs every phase to
 its bound, and the renewal at 10 times renews on every grant (a renewal storm by construction).
 Measured wall clock per run: 1-2 s for most; renewal at tenfold 21-28 s; permitFloor at tenfold
 ~11 s; driftMargin at tenfold 5-8 s; renewal skewed and requestTimeout at tenfold up to 13 s.
 Fix round 1 (serial, under an outside load of 14 to 22): ownerIdleRelease skewed took 309 s in one
 file and leaseDuration tenfold 281 s in its part 2 of 2, so they are split in 2 and 3."
AuditFamilies class >> partsOf: aRow mode: aMode
  | key |
  key := aRow , ' ' , aMode.
  #(#('renewal tenfold' 8) #('permitFloor tenfold' 6) #('renewal skewed' 3)
    #('requestTimeout tenfold' 2) #('leaseDuration tenfold' 3) #('driftMargin tenth' 2)
    #('driftMargin skewed' 2) #('permissionDeadline tenfold' 2) #('driftMargin tenfold' 3)
    #('backoff tenth' 2) #('ownerIdleRelease skewed' 2)) do: [:e |
      e first = key ifTrue: [^ e last]].
  ^ 1.

"The runs of part i (1-based) of aRow under aMode: every n-th run of allRuns from the i-th, so
 that 3- and 5-member runs share the parts alike."
AuditFamilies class >> runsOf: aRow mode: aMode part: i
  | n all |
  n := self partsOf: aRow mode: aMode.
  all := self allRuns.
  ^ ((1 to: all size) select: [:k | (k - 1) \\ n = (i - 1)]) asArray collect: [:k | all at: k].

"The file (in tests/audit) of part i of the audit of aRow under aMode:
 sim_timer_audit_<row>_<mode>_part<i>.st."
AuditFamilies class >> fileFor: aRow mode: aMode part: i
  ^ 'sim_timer_audit_' , aRow , '_' , aMode , '_part' , i printString , '.st'.

"The call the file of part i of the audit of aRow under aMode makes."
AuditFamilies class >> callFor: aRow mode: aMode part: i
  ^ 'AuditFamilies audit: ''' , aRow , ''' mode: #' , aMode , ' part: ' , i printString , '.'.

"The row-modes that keep no liveness by construction, so their runs get checkSafe alone and
 acknowledge nothing (declared, and asserted: a run that acknowledges a commit or gets the
 strict checks makes the declaration stale and fails the part): driftMargin at 10 times (the
 belief capped at 1 us: no lease is usable), permitFloor at 10 times (the floor above any lease
 left: no permission is issued), sendReserve at 10 times (the reserve above any permission:
 nothing is sent)."
AuditFamilies class >> safetyOnly
  ^ #('driftMargin tenfold' 'permitFloor tenfold' 'sendReserve tenfold').

"The rows no core rule reads yet: { row. the task that adds its reader }. Their runs equal the
 defaults' (sim_timer_audit.st asserts it, and that no source of the cluster but config.st names
 the timer), so the declaration fails once a reader appears."
AuditFamilies class >> notExercised
  ^ #(#('persist' 'Task 20' #('persistInterval' 'persistLag'))).

"The floors of part i of aRow under aMode: { runs that got the strict checks. commits
 acknowledged } (proto_db's min_acked: an empty run proves nothing). nil for a part of a
 safety-only row-mode; a part without a declared floor fails loudly."
AuditFamilies class >> floorOf: aRow mode: aMode part: i
  | key |
  (self safetyOnly includes: aRow , ' ' , aMode) ifTrue: [^ nil].
  key := self floorKey: aRow mode: aMode part: i.
  self floors do: [:e | e first = key ifTrue: [^ e allButFirst]].
  ^ Error signal: 'AuditFamilies: no floor declared for ' , key.

"The key of part i of aRow under aMode in floors: 'row mode i'."
AuditFamilies class >> floorKey: aRow mode: aMode part: i
  ^ aRow , ' ' , aMode , ' ' , i printString.

"The keys floors must declare, exactly: every part of every row-mode but the safety-only ones
 (the index, sim_timer_audit.st, checks floors against it)."
AuditFamilies class >> floorKeys
  | keys |
  keys := OrderedCollection new.
  AuditConfig rows do: [:row | self modes do: [:mode |
    (self safetyOnly includes: row , ' ' , mode) ifFalse: [
      1 to: (self partsOf: row mode: mode) do: [:i | keys add: (self floorKey: row mode: mode part: i)]]]].
  ^ keys asArray.

"{ 'row mode part'. strict runs. commits acknowledged } per part: that part's own measured
 counts (the runs are deterministic per seed). Measured serially in task-17-report.md: Fix
 round 1's data pass, and Fix round 2's re-measured parts for acquireTimeout (non-owner probe),
 retryHold (every attempt writing its token), leaseDuration tenfold and ownerIdleRelease skewed
 (re-split). A run that moves to checkSafe, or a commit no longer acknowledged, fails its part."
AuditFamilies class >> floors
  ^ {
    { 'acquireTimeout skewed 1'. 60. 517 }.
    { 'acquireTimeout tenfold 1'. 60. 517 }.
    { 'acquireTimeout tenth 1'. 60. 450 }.
    { 'backoff skewed 1'. 60. 459 }.
    { 'backoff tenfold 1'. 59. 457 }.
    { 'backoff tenth 1'. 28. 216 }.
    { 'backoff tenth 2'. 28. 206 }.
    { 'driftMargin skewed 1'. 19. 206 }.
    { 'driftMargin skewed 2'. 22. 208 }.
    { 'driftMargin tenth 1'. 29. 235 }.
    { 'driftMargin tenth 2'. 28. 225 }.
    { 'gatherAttempts skewed 1'. 60. 454 }.
    { 'gatherAttempts tenfold 1'. 57. 451 }.
    { 'gatherAttempts tenth 1'. 60. 453 }.
    { 'idleEnd skewed 1'. 60. 456 }.
    { 'idleEnd tenfold 1'. 60. 454 }.
    { 'idleEnd tenth 1'. 60. 460 }.
    { 'leaseDuration skewed 1'. 58. 449 }.
    { 'leaseDuration tenfold 1'. 15. 138 }.
    { 'leaseDuration tenfold 2'. 17. 142 }.
    { 'leaseDuration tenfold 3'. 17. 142 }.
    { 'leaseDuration tenth 1'. 60. 465 }.
    { 'ownerIdleRelease skewed 1'. 30. 234 }.
    { 'ownerIdleRelease skewed 2'. 30. 225 }.
    { 'ownerIdleRelease tenfold 1'. 60. 454 }.
    { 'ownerIdleRelease tenth 1'. 60. 468 }.
    { 'permissionDeadline skewed 1'. 60. 454 }.
    { 'permissionDeadline tenfold 1'. 25. 207 }.
    { 'permissionDeadline tenfold 2'. 27. 206 }.
    { 'permissionDeadline tenth 1'. 60. 472 }.
    { 'permitFloor skewed 1'. 60. 454 }.
    { 'permitFloor tenth 1'. 60. 454 }.
    { 'persist skewed 1'. 60. 454 }.
    { 'persist tenfold 1'. 60. 454 }.
    { 'persist tenth 1'. 60. 454 }.
    { 'renewal skewed 1'. 17. 138 }.
    { 'renewal skewed 2'. 16. 134 }.
    { 'renewal skewed 3'. 17. 143 }.
    { 'renewal tenfold 1'. 3. 42 }.
    { 'renewal tenfold 2'. 3. 40 }.
    { 'renewal tenfold 3'. 4. 45 }.
    { 'renewal tenfold 4'. 4. 42 }.
    { 'renewal tenfold 5'. 5. 45 }.
    { 'renewal tenfold 6'. 5. 42 }.
    { 'renewal tenfold 7'. 3. 47 }.
    { 'renewal tenfold 8'. 3. 36 }.
    { 'renewal tenth 1'. 60. 459 }.
    { 'requestTimeout skewed 1'. 60. 457 }.
    { 'requestTimeout tenfold 1'. 29. 230 }.
    { 'requestTimeout tenfold 2'. 29. 236 }.
    { 'requestTimeout tenth 1'. 60. 467 }.
    { 'retryHold skewed 1'. 59. 464 }.
    { 'retryHold tenfold 1'. 58. 467 }.
    { 'retryHold tenth 1'. 59. 475 }.
    { 'sendReserve skewed 1'. 60. 462 }.
    { 'sendReserve tenth 1'. 60. 468 }.
    { 'startupGrace skewed 1'. 60. 453 }.
    { 'startupGrace tenfold 1'. 60. 454 }.
    { 'startupGrace tenth 1'. 60. 451 }.
    { 'straggle skewed 1'. 59. 444 }.
    { 'straggle tenfold 1'. 60. 456 }.
    { 'straggle tenth 1'. 60. 460 }.
    { 'turnSilence skewed 1'. 60. 457 }.
    { 'turnSilence tenfold 1'. 59. 451 }.
    { 'turnSilence tenth 1'. 60. 453 }.
    { 'wakeSpread skewed 1'. 60. 450 }.
    { 'wakeSpread tenfold 1'. 60. 458 }.
    { 'wakeSpread tenth 1'. 60. 448 } }.

"The bounds of the probe's count per run, { min. max } (nil: the row has no probe): the count
 shows the probe made the core read the timer, and that 1/10 and 10 times differ.
 acquireTimeout: at 1/10 (3 s) the probe commit times out in every run, at 10 times (300 s) and
 skewed (the last member at 1/2: 15 s) in none. gatherAttempts: at 1/10 (one attempt) the gather
 never asks again; at 10 times (30 attempts) it asks again through the 4 s; skewed: the last
 member at 1/2 (2 attempts). retryHold: at 1/10 (a 10 ms hold) holds run out before the held
 retry (20 ms) queues; at 10 times (1 s) and skewed (50 ms, 200 ms) none does. Measured over the
 60 runs (Fix round 1): acquireTimeout 60, 0, 0; gatherAttempts 60, 1026, 120; retryHold 347, 0, 0
 (at 1/10, 10 times, skewed)."
AuditFamilies class >> probeBounds: aRow mode: aMode
  | key |
  key := aRow , ' ' , aMode.
  #(#('acquireTimeout tenth' 1 1) #('acquireTimeout tenfold' 0 0) #('acquireTimeout skewed' 0 0)
    #('gatherAttempts tenth' 1 1) #('gatherAttempts tenfold' 4 30) #('gatherAttempts skewed' 2 2)
    #('retryHold tenth' 1 1000) #('retryHold tenfold' 0 0) #('retryHold skewed' 0 0)) do: [:e |
      e first = key ifTrue: [^ e allButFirst]].
  ^ nil.

"The reasons part i of the audit of aRow under aMode fails, given its counts out
 (row:mode:runs:): a violation; a declared floor missed; a safety-only declaration gone stale;
 a probe count out of its bounds. Empty when it passes."
AuditFamilies class >> failuresOf: out row: aRow mode: aMode part: i
  | failures runs floor bounds |
  failures := OrderedCollection new.
  runs := out at: 1.
  (out at: 2) > 0 ifTrue: [failures add: (out at: 2) printString , ' violations'].
  runs = 0 ifTrue: [failures add: 'no runs'].
  floor := self floorOf: aRow mode: aMode part: i.
  floor isNil
    ifTrue: [
      ((out at: 8) > 0 or: [(out at: 4) > 0]) ifTrue: [
        failures add: 'declared safety-only, yet ' , (out at: 8) printString , ' strict runs and '
          , (out at: 4) printString , ' commits acknowledged: the declaration is stale']]
    ifFalse: [
      (out at: 8) < floor first ifTrue: [
        failures add: 'strict runs ' , (out at: 8) printString , ' below the floor ' , floor first printString].
      (out at: 4) < floor last ifTrue: [
        failures add: 'commits acknowledged ' , (out at: 4) printString , ' below the floor ' , floor last printString]].
  bounds := self probeBounds: aRow mode: aMode.
  bounds notNil ifTrue: [
    ((out at: 9) isNil or: [(out at: 9) < (bounds first * runs) or: [(out at: 9) > (bounds last * runs)]]) ifTrue: [
      failures add: 'probe count ' , (out at: 9) printString , ' outside ' , (bounds first * runs) printString , '..'
        , (bounds last * runs) printString]].
  ^ failures asArray.

"Part i of the audit of aRow under aMode (allRuns, split by partsOf:mode:): prints one line for
 the timer (and the first violation and every failure, if any); answers the test's last line."
AuditFamilies class >> audit: aRow mode: aMode part: i
  | out n failures |
  n := self partsOf: aRow mode: aMode.
  out := self row: aRow mode: aMode runs: (self runsOf: aRow mode: aMode part: i).
  Transcript show: 'timer ' , aRow , ' at ' , aMode , ' (part ' , i printString , ' of ' , n printString , '): '
    , (out at: 1) printString , ' runs, ' , (out at: 2) printString , ' violations, '
    , (out at: 8) printString , ' strict, z acknowledged in ' , (out at: 3) printString
    , ', commits acknowledged ' , (out at: 4) printString
    , ', (root, node) pairs not yet learnt ' , (out at: 5) printString
    , ', probe ' , (out at: 9) printString , ', steps ' , (out at: 7) printString; cr.
  (out at: 6) notNil ifTrue: [Transcript show: 'FIRST VIOLATION ' , (out at: 6); cr].
  failures := self failuresOf: out row: aRow mode: aMode part: i.
  failures do: [:f | Transcript show: 'FAILED: ' , f; cr].
  ^ failures isEmpty ifTrue: ['timer audit ok'] ifFalse: ['timer audit failed'].
