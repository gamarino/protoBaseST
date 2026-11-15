"EXPECT: checker plants ok 15"
"The checker's self-tests: the outcome rules of the simulator's convergence check (PBSimChecker
 checkHistory:, the rules of proto_db's assert_outcomes_resolved and the counter its tests
 compare; the same method checkConverged runs on the history PBSim derives) detect each
 workload plant of proto_db's tests/support/plant_defects.py that applies here, fed as a
 synthetic history. The control history (commits c-1 to c-20 from three members, c-16 an
 unknown outcome that took effect, every member's counter equal to its tokens) passes; each
 plant changes it as plant_defects.py changes its workload or its reader, and must fail with
 the rule that names it:
   lost         c-16 unknown and applied, c-17's increment lost, its token kept: the tokens
                balance, the counter does not (counter).
   lost_token   c-17 acknowledged but writes nothing of its own (S4).
   fork         c-16 unknown, shown by a member, then erased from history by c-17 (fork: a
                commit a member showed is lost).
   stray        c-12 also writes the token stray-0, which no commit reported (stray).
   split        c-16 unknown and applied; n0's reader does not show it (unknown resolved on
                some members only).
   blind_lost   a blind workload (no counter): every member's reader loses the oldest token
                (S4).
   check_lost   after the faults (n0 down), every live member loses the oldest acknowledged
                commit (S4, proto_db check_after_faults).
   renewal      an unknown commit resolved differently on one member (proto_db renewal_split):
                of five members only n3 shows c-6.
 The plants slow_recovery, readers_lost and forced_lost do not apply: a recovery-time bound on
 wall-clock runs (N3) and two readers of real-process tests (history readers, forced
 replication failures; Phase C, Task 20). The product plants of plant_defects.py are ported
 as rule plants with their families (sim_lessons.st).

 The simulator-level plants start from a converged product run (CheckerFamilies run:commits:,
 whose checkConverged is their control) and plant a state in it, so the history PBSim derives,
 checkSafe and the timer audit's strict-or-safe gate (AuditFamilies judge:z:) are each shown to
 fail:
   recommit_lost   t re-commits its base (RecommitRules); every head moves back to the
                   re-commit root, t's own root dropped: the re-commit credits t nothing (S4).
   recommit_none   the same with t answered none: no false H7; the published root lost (fork).
   safe_lost       every head moves to a known root on a's root, past b's acknowledged root:
                   checkSafe fails it ('does not precede it'). Its control safe_behind (one head
                   at a's root, before b's) is counted as not yet learnt, not failed.
   gate_fork       z acknowledged, one head forks from the others': the gate's divergence check
                   (diverge), never taken for a lag.
   gate_lost       z acknowledged, every head past b's lost root: the gate signals checkSafe's
                   S4. Its controls: a converged run gets the strict checks, a member behind gets
                   checkSafe and is counted.
   stray_published every member publishes a root the simulator never built
                   (applyPublishCommitted:): stray.
   fork_published  b unknown, applied and published, then every head moves to a root on a's:
                   a commit a member showed is lost (P1, fork)."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_sim'.
Import from: '_plants'.
Import from: '../audit/_audit'.

| sim c tokens base violation history detected plants out control fresh sims recommit text lost stray |
sim := PBSim seed: 1 ids: #('n0' 'n1' 'n2') rules: PBCoordinatorCore new options: Dictionary new.
tokens := (1 to: 20) collect: [:i | 'c-' , i printString].

"A history of the members someIds, each holding someTokens (an id -> tokens Dictionary when
 aBoolean says the members differ), c-16 unknown, the rest acknowledged; aCounter answers each
 member's counter from its tokens (nil: no counter)."
history := [:someIds :present :unknown :counter | | h |
  h := PBSimHistory members: someIds present: present.
  h acked: (tokens reject: [:t | unknown includes: t]).
  h unknown: unknown.
  someIds do: [:m | | v |
    v := counter value: m value: (present at: m).
    v notNil ifTrue: [h value: v at: m]].
  h].
base := [:someIds | | d | d := Dictionary new. someIds do: [:m | d at: m put: tokens asSet]. d].
violation := [:h | [sim checker checkHistory: h. nil] on: Error do: [:e |
  ((e messageText ifNil: ['']) beginsWith: 'PBSim seed') ifFalse: [e signal].
  e messageText]].

c := Check new.
control := history value: #('n0' 'n1' 'n2') value: (base value: #('n0' 'n1' 'n2')) value: #('c-16')
  value: [:m :ts | ts size].
control observed: tokens.
c that: 'the control history passes' is: (violation value: control) equals: nil.

plants := OrderedCollection new.
"lost: c-17's increment is lost while its token is kept; c-16 unknown took effect."
plants add: { 'lost'. 'counter: n0 counts 19 commits, its committed chain holds 20'.
  history value: #('n0' 'n1' 'n2') value: (base value: #('n0' 'n1' 'n2')) value: #('c-16')
    value: [:m :ts | ts size - 1] }.
"lost_token: c-17 acknowledged, nothing of it written."
plants add: { 'lost_token'. 'S4: the acknowledged commit ''c-17'' is not in the committed chain of n0'.
  history value: #('n0' 'n1' 'n2')
    value: (Dictionary new at: 'n0' put: (tokens copyWithout: 'c-17'); at: 'n1' put: (tokens copyWithout: 'c-17');
      at: 'n2' put: (tokens copyWithout: 'c-17'); yourself)
    value: #('c-16') value: [:m :ts | ts size] }.
"fork: c-16 unknown, shown by a member during the run, erased by c-17."
out := history value: #('n0' 'n1' 'n2')
  value: (Dictionary new at: 'n0' put: (tokens copyWithout: 'c-16'); at: 'n1' put: (tokens copyWithout: 'c-16');
    at: 'n2' put: (tokens copyWithout: 'c-16'); yourself)
  value: #('c-16') value: [:m :ts | ts size].
out observed: tokens.
plants add: { 'fork'. 'fork: the commit ''c-16'' that a member showed is not in the committed chain of n0: history lost it'. out }.
"stray: c-12 also writes stray-0."
plants add: { 'stray'. 'stray: the committed chain of n0 holds ''stray-0'', which no acknowledged or unknown commit wrote'.
  history value: #('n0' 'n1' 'n2')
    value: (Dictionary new at: 'n0' put: (tokens copyWith: 'stray-0'); at: 'n1' put: (tokens copyWith: 'stray-0');
      at: 'n2' put: (tokens copyWith: 'stray-0'); yourself)
    value: #('c-16') value: [:m :ts | ts size] }.
"split: n0's reader does not show the unknown c-16."
plants add: { 'split'. 'the unknown commit ''c-16'' is in the committed chain of #(''n1'' ''n2'') only'.
  history value: #('n0' 'n1' 'n2')
    value: (Dictionary new at: 'n0' put: (tokens copyWithout: 'c-16'); at: 'n1' put: tokens; at: 'n2' put: tokens; yourself)
    value: #('c-16') value: [:m :ts | ts size] }.
"blind_lost: no counter; every member's reader loses the oldest token."
plants add: { 'blind_lost'. 'S4: the acknowledged commit ''c-1'' is not in the committed chain of n0'.
  history value: #('n0' 'n1' 'n2')
    value: (Dictionary new at: 'n0' put: (tokens copyWithout: 'c-1'); at: 'n1' put: (tokens copyWithout: 'c-1');
      at: 'n2' put: (tokens copyWithout: 'c-1'); yourself)
    value: #('c-16') value: [:m :ts | nil] }.
"check_lost: n0 is down; every live member loses the oldest acknowledged commit; the counter
 still counts it."
plants add: { 'check_lost'. 'S4: the acknowledged commit ''c-1'' is not in the committed chain of n1'.
  history value: #('n1' 'n2')
    value: (Dictionary new at: 'n1' put: (tokens copyWithout: 'c-1'); at: 'n2' put: (tokens copyWithout: 'c-1'); yourself)
    value: #('c-16') value: [:m :ts | ts size + 1] }.
"renewal_split: of five members only n3 shows the unknown c-6."
plants add: { 'renewal'. 'the unknown commit ''c-6'' is in the committed chain of #(''n3'') only'.
  history value: #('n0' 'n1' 'n2' 'n3' 'n4')
    value: (Dictionary new at: 'n0' put: (tokens copyWithout: 'c-6'); at: 'n1' put: (tokens copyWithout: 'c-6');
      at: 'n2' put: (tokens copyWithout: 'c-6'); at: 'n3' put: tokens; at: 'n4' put: (tokens copyWithout: 'c-6'); yourself)
    value: #('c-6') value: [:m :ts | ts size] }.

detected := 0.
plants do: [:p | | text |
  text := violation value: (p at: 3).
  Transcript show: 'plant ' , p first , ': ' , (text isNil ifTrue: ['NOT DETECTED'] ifFalse: [(text lines at: 1)]); cr.
  c that: 'the plant ' , p first , ' is detected' is: (text notNil and: [text includesSubstring: (p at: 2)]) equals: true.
  (text notNil and: [text includesSubstring: (p at: 2)]) ifTrue: [detected := detected + 1]].
"--- The simulator-level plants: the derived history, checkSafe and the audit's gate ---"
"Each starts from a converged product run (CheckerFamilies run:commits:, its checkConverged the
 control) and plants one state; each must fail with the rule that names it."
fresh := [CheckerFamilies run: PBCoordinatorCore new commits: #('a' 'b')].
sims := OrderedCollection new.

"recommit_lost (review I1): every commit re-commits its base first (RecommitRules); t is
 acknowledged, its own root R built on the re-commit R'. Every member's head moves back to R'
 (R dropped). R' holds none of t's effect and credits t nothing: S4."
sim := CheckerFamilies run: RecommitRules new commits: #('t').
recommit := sim recommitRootOf: 't'.
c that: 'recommit_lost: t re-committed its base, and its own root is built on the re-commit'
  is: { recommit notNil. recommit notNil and: [(sim chainFrom: (sim keyText: (sim rootOf: 't'))) includes: (sim keyText: recommit)] }
  equals: #(true true).
CheckerFamilies heads: sim to: recommit.
c that: 'recommit_lost: no member holds t through its re-commit'
  is: (sim ids select: [:m | (sim history presentAt: m) includes: 't']) asArray equals: #().
sims add: { 'recommit_lost'. 'S4: the acknowledged commit ''t'''. CheckerFamilies violationOf: [sim checker checkConverged] }.
"recommit_none (review I1, H7): the same, t answered none: no false H7 (the re-commit credits t
 nothing); the loss of t's published root is the fork of history it is (P1)."
sim _end: 't' as: #none.
text := CheckerFamilies violationOf: [sim checker checkConverged].
c that: 'recommit_none: no H7 for a commit only its re-commit is in' is: ((text ifNil: ['']) includesSubstring: 'H7') equals: false.
sims add: { 'recommit_none'. 'fork: the commit ''t'''. text }.

"safe_lost (review I3): every member's head moves to a known root F on a's root, so b's
 acknowledged root is in no chain and no head precedes it: checkSafe fails it."
sim := fresh value.
lost := sim declare: (sim rootOf: 'a').
CheckerFamilies heads: sim to: lost.
sims add: { 'safe_lost'. 'does not precede it'. CheckerFamilies violationOf: [sim checker checkSafe] }.
"safe_behind (control): one member's head is a's root, before b's: counted as not yet learnt."
sim := fresh value.
(sim nodeAt: 'n2') committed: (sim rootOf: 'a').
out := nil.
text := CheckerFamilies violationOf: [out := sim checker checkSafe].
c that: 'safe_behind: a member whose head precedes b is behind, not failed' is: { text. out notNil and: [out > 0] } equals: #(nil true).

"gate_fork (review I3): z acknowledged, one member's head forks from the others': the gate must
 not take the divergence for a lag (checkHeads)."
sim := fresh value.
(sim nodeAt: 'n1') committed: (sim declare: (sim rootOf: 'a')).
sims add: { 'gate_fork'. 'diverge'. CheckerFamilies violationOf: [AuditFamilies judge: sim z: true] }.
"gate_lost (review I3): z acknowledged, every head moved past b's lost root (equal heads): the
 gate's catch-up test signals checkSafe's S4."
sim := fresh value.
CheckerFamilies heads: sim to: (sim declare: (sim rootOf: 'a')).
sims add: { 'gate_lost'. 'does not precede it'. CheckerFamilies violationOf: [AuditFamilies judge: sim z: true] }.
"gate controls: caught up, the strict checks; a member behind, checkSafe and a lag."
sim := fresh value.
c that: 'gate: a converged run gets the strict checks' is: (AuditFamilies judge: sim z: true) equals: #(true 0).
(sim nodeAt: 'n2') committed: (sim rootOf: 'a').
out := AuditFamilies judge: sim z: true.
c that: 'gate: a member behind gets checkSafe and is counted' is: { out first. out last > 0 } equals: #(false true).

"stray_published (review I3): every member publishes a root the simulator never built
 (fabricate:, through applyPublishCommitted:): a stray write."
sim := fresh value.
stray := sim fabricate: (sim rootOf: 'b').
sim ids do: [:m | sim publish: stray at: m].
sims add: { 'stray_published'. 'stray: the committed chain of n0 holds ''root ' , (sim keyText: stray) , ''''.
  CheckerFamilies violationOf: [sim checker checkConverged] }.
"fork_published (review I3, P1): b unknown but applied and published; then every head moves to a
 known root on a's: a commit a member showed is lost."
sim := fresh value.
sim _end: 'b' as: #unknown.
CheckerFamilies heads: sim to: (sim declare: (sim rootOf: 'a')).
sims add: { 'fork_published'. 'fork: the commit ''b'''. CheckerFamilies violationOf: [sim checker checkConverged] }.

sims do: [:p | | t |
  t := p at: 3.
  Transcript show: 'plant ' , p first , ': ' , (t isNil ifTrue: ['NOT DETECTED'] ifFalse: [(t lines at: 1)]); cr.
  c that: 'the plant ' , p first , ' is detected' is: (t notNil and: [t includesSubstring: (p at: 2)]) equals: true.
  (t notNil and: [t includesSubstring: (p at: 2)]) ifTrue: [detected := detected + 1]].
out := c report.
out displayNl.
(out beginsWith: 'ok') ifTrue: ['checker plants ok ' , detected printString] ifFalse: ['checker plants failed'].
