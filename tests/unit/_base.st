"_base.st: the rules, the simulator and the planted wrong rules of the base-choice scenario families
 (sim_base_choice.st, sim_base_seeds_a.st, sim_base_seeds_b.st; a helper: the runner never runs
 files whose name starts with _). Test support, not product (CC13): each plant is a subclass
 overriding one rule method of the product rules.

  BaseRules                  the product rules (PBCoordinatorCore), every decision recorded.
  BaseSim                    a PBSim whose script can run a block when a node's synthetic commit
                             reaches a stage (the permit, the base decision, a replication
                             outcome), before the simulator acts on it, and can hand a node a
                             dispatcher event (a PBRecoverWanted).
  PlantRecoveryWaitsAll      a recovery round waits for every voter (proto_db plant
                             recovery_waits_all): with a voter down it lasts requestTimeout.
  PlantRecoveryEveryIgnored  every = true ends at a majority too (recovery_every_ignored, M6).
  PlantC1NoFloor             the recovery result alone is the base of an uncertain lease
                             (c1_no_floor, re-review 2 C1, R127).
  PlantBaseTwice             the owner issues while a permission is outstanding (O1's pipeline
                             check dropped): one base issued twice (R79, L28), over the real
                             replication and base choice."

Import from: 'protobase'.
Import from: '_sim'.

"=== The rules ==============================================================="

PBCoordinatorCore subclass: #BaseRules.

BaseRules subclass: #PlantRecoveryWaitsAll.

PlantRecoveryWaitsAll >> recoveryDone: aChoice in: s
  ^ aChoice answers size >= (s config membership voters reject: [:v | v = s config nodeId]) size.

BaseRules subclass: #PlantRecoveryEveryIgnored.

PlantRecoveryEveryIgnored >> recoveryDone: aChoice in: s
  ^ super recoveryDone: (aChoice with: { #every -> false }) in: s.

BaseRules subclass: #PlantC1NoFloor.

PlantC1NoFloor >> phase1Floor: aRoot
  ^ false.

BaseRules subclass: #PlantBaseTwice.

PlantBaseTwice >> _pipelineFull: anOwnership in: s
  ^ false.

"=== BaseSim =================================================================="

PBSim subclass: #BaseSim instanceVariableNames: 'hooks decisions recovered'.

"aBlock runs (with the outcome) the next time a synthetic commit at anId reaches aStage
 ('permit': its permission; 'base': its base decision; 'replicate' or 'recommit': a
 replication's outcome), before the simulator acts on it. Once."
BaseSim >> on: aStage at: anId do: aBlock
  hooks isNil ifTrue: [hooks := OrderedCollection new].
  hooks add: { aStage. anId. aBlock }.

"{ node id. token. outcome. virtual time } of every base decision (or error), in order."
BaseSim >> decisions
  decisions isNil ifTrue: [decisions := OrderedCollection new].
  ^ decisions.

"{ node id. outcome. virtual time } of every PBRecoverWanted settled, in order."
BaseSim >> recovered
  recovered isNil ifTrue: [recovered := OrderedCollection new].
  ^ recovered.

"Steps every event due at or before aTime (at most n steps), then stands at aTime: unlike
 runUntil:steps:, an idle queue does not carry virtual time to a held message's delivery."
BaseSim >> runTo: aTime steps: n
  n timesRepeat: [ | next |
    next := nil.
    queue do: [:e | ((e at: 1) notNil and: [(self _isPaused: (e at: 3)) not and: [next isNil or: [(e at: 1) < next]]]) ifTrue: [next := e at: 1]].
    (next isNil or: [next > aTime]) ifTrue: [now := now max: aTime. ^ self].
    self step].

"anEvent dispatched at anId now."
BaseSim >> dispatch: anEvent at: anId
  self _schedule: #dispatch node: (self nodeAt: anId) payload: anEvent at: now.

"The synced #accepted entries of anId's disk, as PBLabeledRoot keys."
BaseSim >> syncedAcceptedOf: anId
  | disk entries |
  disk := self diskOf: anId.
  entries := disk payloads copyFrom: 1 to: disk syncedSize.
  ^ ((PBAcceptorLog decode: entries path: 'check') entries select: [:e | e kind = 1])
    collect: [:e | (PBLabeledRoot label: e label record: e root) key].

"The replicate messages anId sent (traced), as their pred texts."
BaseSim >> predsSentBy: anId
  ^ (self trace select: [:l | l includesSubstring: anId , '   -> PBSend('])
    select: [:l | l includesSubstring: 'replicate from ' , anId].

BaseSim >> _settle: aWaiter outcome: anOutcome at: aNode
  | hook |
  (aWaiter isArray and: [aWaiter first = 'recover']) ifTrue: [
    self _trace: aNode id , ' recovered ' , anOutcome printString.
    ^ self recovered add: { aNode id. anOutcome. now }].
  (aWaiter first = 'base') ifTrue: [self decisions add: { aNode id. aWaiter at: 2. anOutcome. now }].
  hooks isNil ifFalse: [
    hook := hooks detect: [:h | h first = aWaiter first and: [(h at: 2) = aNode id]] ifNone: [nil].
    hook notNil ifTrue: [
      hooks remove: hook.
      (hook at: 3) value: anOutcome]].
  ^ super _settle: aWaiter outcome: anOutcome at: aNode.

"=== The scenario families ==================================================="

Object subclass: #BaseFamilies.

"The root r1 every pre-formed log holds accepted and committed: label 4096, epoch 1."
BaseFamilies class >> r1
  ^ PBLabeledRoot label: 4096
    record: (PBRootRecord segment: (ByteArray withAll: ((1 to: 16) asArray collect: [:i | 238])) offset: 1 epoch: 1).

"A BaseSim of the members someIds formed before, startup grace 0, the rules aRules, options
 aDictionary on top. Each log holds the rejoined marker; those of someKnowing also hold r1
 accepted and committed."
BaseFamilies class >> sim: aRules seed: n ids: someIds knowing: someKnowing options: aDictionary
  | logs opts |
  logs := Dictionary new.
  someIds do: [:id |
    logs at: id put: ((someKnowing includes: id)
      ifTrue: [{ PBLogAppend kind: #accepted label: self r1 label root: self r1 record sync: true.
        PBLogAppend kind: #committed label: self r1 label root: self r1 record sync: true.
        PBLogAppend kind: #rejoined label: 0 root: nil sync: true }]
      ifFalse: [{ PBLogAppend kind: #rejoined label: 0 root: nil sync: true }])].
  opts := Dictionary new.
  opts at: #startupGrace put: 0.
  aDictionary keysAndValuesDo: [:k :v | opts at: k put: v].
  ^ BaseSim seed: n ids: someIds rules: aRules options: opts logs: logs.

"Options making every member of five a voter (the default voters are the first three)."
BaseFamilies class >> fiveVoters
  ^ Dictionary new at: #voters put: self five; yourself.

BaseFamilies class >> three
  ^ #('n0' 'n1' 'n2').

BaseFamilies class >> five
  ^ #('n0' 'n1' 'n2' 'n3' 'n4').

"aSim commits aToken at anId and runs until it is resolved (or n steps)."
BaseFamilies class >> commit: aToken at: anId in: aSim
  aSim commit: aToken at: anId.
  aSim runUntil: [(aSim outcomeOf: aToken) ~= #pending] steps: 300000.
  ^ aSim outcomeOf: aToken.

BaseFamilies class >> run: aSim until: anEnd
  aSim runTo: anEnd steps: 2000000.

"A violation of the simulator's checker (an Error whose text names the seed), as its text; nil
 when aBlock ran without one. Any other Error is signalled on."
BaseFamilies class >> violationOf: aBlock
  ^ [aBlock value. nil] on: Error do: [:e |
    ((e messageText ifNil: ['']) includesSubstring: 'PBSim seed') ifFalse: [e signal].
    e messageText].

"The base decisions at anId, their outcomes only."
BaseFamilies class >> decisionsAt: anId in: aSim
  ^ (aSim decisions select: [:d | d first = anId]) collect: [:d | d at: 3].

"--- 1. the C1 schedule: an acknowledged R' is never dropped ---"

"{ violation text or nil. lease of n0 uncertain with root R'. base n0 decided. preds n0 sent }:
 the reviewer's reproduction of re-review 2, C1 (CP 725-780), as a fixed schedule. Five voters
 n0..n4 (a..e) hold r1. e (n4) owns a term T' granted by b and c, its clock then stands still (a
 rate fault: its permission stays valid on its own clock) and it replicates R': b accepts at
 once, c's copy is delayed. The promises to e lapse on b's and d's clocks (c's clock runs at half
 speed, so c refuses a's request busy). a (n0) owns T from b and d: phase 1 reports R'
 (uncertain). a's recovery round is answered by c and d only (b's and e's answers are late):
 it ends at a majority of witnesses with r1. Then e's delayed replicate reaches c, c's ack
 reaches e: R' is acknowledged. a's base must be R' (the phase-1 floor, R127): its re-commit and
 its commit, accepted by c and d, extend R', and the chains converge with R' in them (S4)."
BaseFamilies class >> c1: aRules seed: n
  | sim d hold arrival out leaseOk |
  sim := self sim: aRules seed: n ids: self five knowing: self five options: self fiveVoters.
  d := (sim nodeAt: 'n0') config leaseDuration.
  "R' reaches c 1 ms after a starts its commit: past its recovery round, before its replicates."
  hold := d + 101000.
  out := Array new: 4.
  leaseOk := false.
  out at: 1 put: (self violationOf: [
    sim clockRate: 'n2' rate: 1/2.
    sim partition: #(#('n4' 'n1' 'n2') #('n0' 'n3')).
    sim on: 'base' at: 'n4' do: [:decision |
      "e's timer stands still; its copy for c is delayed."
      sim clockRate: 'n4' rate: 0.
      sim delay: 'n4' to: 'n2' by: hold.
      arrival := sim now + hold].
    sim commit: 'rp' at: 'n4'.
    sim runUntil: [(sim rootOf: 'rp') notNil and: [(sim syncedAcceptedOf: 'n1') includes: (sim rootOf: 'rp') key]] steps: 300000.
    "e's late answers: it never takes part in a's recovery before c and d."
    sim delay: 'n4' to: 'n0' by: 10 * d.
    sim heal.
    self run: sim until: arrival - 1000.
    sim on: 'permit' at: 'n0' do: [:permission |
      | own |
      own := (sim nodeAt: 'n0') state ownership.
      leaseOk := own notNil and: [own lease isCertain not and: [own lease root notNil
        and: [own lease root key = (sim rootOf: 'rp') key]]].
      "b's answer to a's recovery comes late."
      sim delay: 'n1' to: 'n0' by: 10 * d].
    sim on: 'base' at: 'n0' do: [:decision |
      "a's replicates reach c after e's delayed R'."
      sim delay: 'n0' to: 'n2' by: ((arrival - sim now) + 1000 max: 0)].
    sim commit: 'x' at: 'n0'.
    sim runUntil: [(sim outcomeOf: 'rp') ~= #pending and: [(sim outcomeOf: 'x') ~= #pending]] steps: 2000000.
    out at: 3 put: (self decisionsAt: 'n0' in: sim).
    out at: 4 put: (sim predsSentBy: 'n0').
    sim clockRate: 'n4' rate: 1.
    sim clockRate: 'n2' rate: 1.
    sim converge: 2000000.
    ((sim outcomeOf: 'rp') = #acknowledged and: [(sim outcomeOf: 'x') = #acknowledged]) ifFalse: [
      sim fail: 'C1 schedule: rp ' , (sim outcomeOf: 'rp') , ', x ' , (sim outcomeOf: 'x')]]).
  out at: 2 put: leaseOk.
  ^ out.

"--- 3. M6: every waits for the holder that knows the commit ---"

"{ result of c's recovery. c's committed root is R }: re-review 2, M6. Three voters hold r1; a
 (n0) commits R with b; its done and its release do not reach c (n2). c's recovery with every
 is answered by b first (b accepted R and does not know it committed: its done from a was lost
 too), then by a, whose answer is late: it must wait for a's answer and learn R committed."
BaseFamilies class >> m6: aRules seed: n
  | sim d result |
  sim := self sim: aRules seed: n ids: self three knowing: self three options: Dictionary new.
  d := (sim nodeAt: 'n0') config leaseDuration.
  sim partition: #(#('n0' 'n1') #('n2')).
  sim on: 'replicate' at: 'n0' do: [:outcome | sim partition: #(#('n0') #('n1') #('n2'))].
  self commit: 'r' at: 'n0' in: sim.
  self run: sim until: sim now + 1000.
  sim heal.
  sim delay: 'n0' to: 'n2' by: 100000.
  sim dispatch: (PBRecoverWanted every: true waiter: { 'recover'. 'n2' }) at: 'n2'.
  sim runUntil: [sim recovered notEmpty] steps: 300000.
  result := sim recovered isEmpty ifTrue: [nil] ifFalse: [sim recovered first at: 2].
  "The committed roots the round learnt reach c's acceptor in the steps after the settle."
  self run: sim until: sim now + 1000.
  ^ { result. (sim nodeAt: 'n2') committed notNil and: [(sim nodeAt: 'n2') committed key = (sim rootOf: 'r') key] }.

"--- 4. refound only when nothing is known ---"

"{ fresh. known. persisted }, each { outcome of a. its root's label. stale decisions at the
 committer. storage root reads at the committer }: (fresh) no log knows a root and nothing is
 persisted: the first base is stale (refound, terms raised by refoundStep), the next term builds
 on the empty space; (known) n0 and n1 hold r1, n2 nothing: n2's uncertain lease recovers r1, no
 storage read, no refound; (persisted) no log knows a root, the shared storage holds P: refound
 from P, the commit is built on P."
BaseFamilies class >> refound: aRules seed: n
  | runs p |
  runs := OrderedCollection new.
  p := PBLabeledRoot label: 4096 record: (PBRootRecord segment: (ByteArray withAll: ((1 to: 16) asArray collect: [:i | 221])) offset: 9 epoch: 7).
  #(#fresh #known #persisted) do: [:kind | | sim at root |
    sim := self sim: aRules seed: n ids: self three knowing: (kind = #known ifTrue: [#('n0' 'n1')] ifFalse: [#()])
      options: Dictionary new.
    kind = #persisted ifTrue: [sim persist: p].
    at := kind = #known ifTrue: ['n2'] ifFalse: ['n0'].
    self commit: 'a' at: at in: sim.
    sim converge: 2000000.
    root := sim rootOf: 'a'.
    runs add: { sim outcomeOf: 'a'. root isNil ifTrue: [nil] ifFalse: [root label].
      ((self decisionsAt: at in: sim) select: [:o | (o isKindOf: PBBaseDecision) and: [o outcome = #stale]]) size.
      sim countOf: 'storage_root_reads' at: at.
      kind = #persisted ifTrue: [(sim committedChainOf: at) includes: (sim keyText: p)] ifFalse: [nil] }].
  ^ runs asArray.

"--- 5. the strict form of R79/L28 ---"

"{ violation text or nil. outcome of c. outcome of b2 }: three voters hold r1; n0 (a) owns a term
 and committed a0. b (n1) holds a permission on a0, builds Rb at a0's epoch + 3 and replicates
 it: only its own acceptance is made (it is cut off), then it crashes. c (n2) asks a for a
 permission: the product waits for b's (O1, DEPTH 0); PlantBaseTwice issues c one on a0 too,
 and c's Rc (epoch + 1) commits with a. b restarts and commits b2: its phase 1 ranks its own Rb
 (same label, higher epoch) above Rc. With the plant the run must fail S4 at convergence (Rc
 acknowledged, not in the chains); the product never issues the second permission, and the
 chains converge."
BaseFamilies class >> baseTwice: aRules seed: n
  | sim d out |
  sim := self sim: aRules seed: n ids: self three knowing: self three options: Dictionary new.
  d := (sim nodeAt: 'n0') config leaseDuration.
  out := Array new: 3.
  out at: 1 put: (self violationOf: [
    self commit: 'a0' at: 'n0' in: sim.
    sim epochStep: 3 at: 'n1'.
    sim on: 'base' at: 'n1' do: [:decision | sim partition: #(#('n1') #('n0' 'n2'))].
    sim commit: 'b' at: 'n1'.
    sim runUntil: [(sim rootOf: 'b') notNil and: [(sim syncedAcceptedOf: 'n1') includes: (sim rootOf: 'b') key]] steps: 300000.
    sim crash: 'n1' unsynced: #keep.
    self commit: 'c' at: 'n2' in: sim.
    out at: 2 put: (sim outcomeOf: 'c').
    self run: sim until: sim now + (2 * d).
    sim restart: 'n1'.
    sim heal.
    self commit: 'b2' at: 'n1' in: sim.
    out at: 3 put: (sim outcomeOf: 'b2').
    sim converge: 2000000]).
  ^ out.

"--- 6. seeds under drops and clock skew ---"

"{ seeds with a violation. recoveries. stale decisions. re-commits. the first violation's text or
 nil. acknowledged commits unlearned before z } over someSeeds: three
 members formed with empty logs (the first commit refounds), drops 1/10, duplicates 1/20, delays
 up to 2 ms, reordering, n1's clock 10 % fast and n2's 10 % slow; four commits at members drawn
 by the seed, one member crashing (#any) and restarting between them; then, without faults, a
 last commit z that must be acknowledged (a commit every member learns: with acks and done
 reports dropped, a quiet cluster may otherwise never learn a commit made; how many acknowledged
 commits were still unlearned, faults ended and the queue drained, before z is counted); then convergence: no fork,
 every acknowledged commit in every chain (S4), every unknown one in all or none, none in none
 (H7)."
BaseFamilies class >> seeds: someSeeds rules: aRulesBlock
  | failed recoveries stale recommits first unlearned |
  failed := 0. recoveries := 0. stale := 0. recommits := 0. first := nil. unlearned := 0.
  someSeeds do: [:n | | sim text pick |
    sim := self sim: aRulesBlock value seed: n ids: self three knowing: #() options: Dictionary new.
    sim faults: (PBSimFaults drop: 1/10 duplicate: 1/20 delay: 2000 reorder: true).
    sim clockRate: 'n1' rate: 11/10.
    sim clockRate: 'n2' rate: 9/10.
    pick := Random seed: n * 7919 + 17.
    text := self violationOf: [
      #('a' 'b' 'c' 'd') doWithIndex: [:token :i | | id |
        id := self three at: (pick nextInt: 3).
        (sim nodeAt: id) isUp ifFalse: [sim restart: id].
        i = 3 ifTrue: [ | victim |
          victim := self three at: (pick nextInt: 3).
          victim ~= id ifTrue: [sim crash: victim unsynced: #any. sim restart: victim]].
        sim commit: token at: id.
        sim runUntil: [(sim outcomeOf: token) ~= #pending] steps: 300000].
      "A commit every member learns (checkConverged's premise): the faults end, every member is
       up and a last commit 'z' must be acknowledged; its chain holds every acknowledged one."
      sim heal.
      sim faults: PBSimFaults none.
      self three do: [:id | (sim nodeAt: id) isUp ifFalse: [sim restart: id]].
      "Drained without faults, the commits still unlearned are the liveness gap."
      sim runUntil: [false] steps: 2000000.
      unlearned := unlearned + (self unlearnedIn: sim).
      (self commit: 'z' at: (self three at: (pick nextInt: 3)) in: sim) = #acknowledged ifFalse: [
        sim fail: 'the last commit z is ' , (sim outcomeOf: 'z')].
      sim converge: 2000000].
    text notNil ifTrue: [failed := failed + 1. first isNil ifTrue: [first := text]].
    self three do: [:id | recoveries := recoveries + (sim countOf: 'recoveries' at: id)].
    stale := stale + (sim decisions select: [:d | ((d at: 3) isKindOf: PBBaseDecision) and: [(d at: 3) outcome = #stale]]) size.
    recommits := recommits + (sim trace select: [:l | l includesSubstring: ' re-commits ']) size].
  ^ { failed. recoveries. stale. recommits. first. unlearned }.

"The acknowledged commits of aSim that some live member's committed chain does not hold, asked
 once the faults ended and the queue drained (the liveness gap D54 leaves under faults: no
 re-replication, committed knowledge lost with a crash; a later commit learns them). Reported,
 not asserted: it depends on the schedule."
BaseFamilies class >> unlearnedIn: aSim
  | live chains |
  live := aSim ids select: [:id | (aSim nodeAt: id) isUp].
  chains := live collect: [:id | aSim committedChainOf: id].
  ^ (aSim commitOrder select: [:token | | root |
    root := aSim rootOf: token.
    (aSim outcomeOf: token) = #acknowledged and: [root notNil
      and: [chains anySatisfy: [:ch | (ch includes: (aSim keyText: root)) not]]]]) size.
