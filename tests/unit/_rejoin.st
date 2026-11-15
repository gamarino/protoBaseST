"_rejoin.st: the rules, the simulator and the planted wrong rules of the rejoin scenario families
 (sim_rejoin.st; a helper: the runner never runs files whose name starts with _). Test support,
 not product (CC13): each plant is a subclass overriding one rule method of the product rules.

  RejoinRules                the product rules (PBCoordinatorCore, through BaseRules: every base
                             decision recorded).
  RejoinSim                  a BaseSim whose script can also hold a node's own acceptance of its
                             replicate (proto_db's holder descheduled between its broadcast and its
                             own accept: holdOwnReplicateAt:, releaseHeld), drop the messages of
                             one type on one link (drop:from:to:), and record every message sent
                             (sent).
  PlantRejoinByWaiting       the rejoin of rulings R53/R54 that L13 replaced: it waits
                             restartGrace (leaseDuration + driftMargin) on its own clock, then
                             completes on the answers of a plain round, without a ballot.
  PlantReplicateBelowBallot  a holder replicates under a term below its rejoin ballot (L14's
                             refusal at the send dropped)."

Import from: 'protobase'.
Import from: '_sim'.
Import from: '_base'.

"=== The rules ==============================================================="

BaseRules subclass: #RejoinRules.

RejoinRules subclass: #PlantRejoinByWaiting.

"The rejoin waits restartGrace on this node's clock before its first round (R53/R54)."
PlantRejoinByWaiting >> _rejoinStart: s now: t effects: fx
  ^ self _rejoinRetry: s after: s config leaseDuration + s config driftMargin now: t effects: fx.

"The plain round's answers complete the rejoin: no ballot."
PlantRejoinByWaiting >> _ballotRound: aDecision answers: someAnswers in: s now: t effects: fx
  ^ self _completeRejoin: aDecision answers: someAnswers ballot: 0 in: s now: t effects: fx.

RejoinRules subclass: #PlantReplicateBelowBallot.

PlantReplicateBelowBallot >> _belowRejoinBallot: aPermission in: s
  ^ false.

"=== RejoinSim ================================================================"

BaseSim subclass: #RejoinSim instanceVariableNames: 'holding held drops sent stops stopped'.

"From now on the replicate anId sends to its own acceptor is held (not queued on its lane) until
 releaseHeld."
RejoinSim >> holdOwnReplicateAt: anId
  holding := anId.
  held isNil ifTrue: [held := OrderedCollection new].

"Queues every held acceptance on its node's lane, in order, and holds no more."
RejoinSim >> releaseHeld
  | list |
  holding := nil.
  list := held isNil ifTrue: [#()] ifFalse: [held asArray].
  held := OrderedCollection new.
  list do: [:pair |
    | node |
    node := self nodeAt: pair first.
    (node isUp and: [node gen = (pair at: 2)]) ifTrue: [
      self _trace: node id , ' released its held acceptance'.
      node lane addLast: pair last.
      self _runLane: node]].

"From now on every message of aType from fromId to toId is held in the network (not queued on
 the link, so later messages overtake it) until releaseMessages."
RejoinSim >> hold: aType from: fromId to: toId
  stops isNil ifTrue: [stops := OrderedCollection new].
  stops add: { aType. fromId. toId }.

"Sends every held message now, in order, and holds no more."
RejoinSim >> releaseMessages
  | list sender |
  list := stopped isNil ifTrue: [#()] ifFalse: [stopped asArray].
  stops := nil.
  stopped := OrderedCollection new.
  sender := current.
  list do: [:pair |
    current := self nodeAt: pair first.
    self _trace: 'released ' , pair first , ' -> ' , pair last to , ' ' , pair last message type.
    super _send: pair last at: self now].
  current := sender.

"From now on every message of aType from fromId to toId is lost."
RejoinSim >> drop: aType from: fromId to: toId
  drops isNil ifTrue: [drops := OrderedCollection new].
  drops add: { aType. fromId. toId }.

"No message is lost by drop:from:to: any more."
RejoinSim >> undrop
  drops := nil.

"{ from. to. message } of every message sent (dropped or not), in order."
RejoinSim >> sent
  ^ sent isNil ifTrue: [#()] ifFalse: [sent asArray].

RejoinSim >> applyToAcceptor: aToAcceptor
  | e |
  e := aToAcceptor event.
  (holding = current id and: [(e isKindOf: PBReceived) and: [e message type = 'replicate' and: [e message from = current id]]])
    ifTrue: [
      self _trace: current id , ' holds its own acceptance of ' , (PBCoreValue textOf: e message).
      ^ held add: { current id. current gen. e }].
  ^ super applyToAcceptor: aToAcceptor.

RejoinSim >> _send: aSend at: aTime
  sent isNil ifTrue: [sent := OrderedCollection new].
  sent add: { current id. aSend to. aSend message }.
  (drops notNil and: [drops anySatisfy: [:d | d first = aSend message type and: [(d at: 2) = current id and: [d last = aSend to]]]])
    ifTrue: [^ self _trace: 'lost ' , current id , ' -> ' , aSend to , ' ' , aSend message type , ' (scripted)'].
  (stops notNil and: [stops anySatisfy: [:d | d first = aSend message type and: [(d at: 2) = current id and: [d last = aSend to]]]])
    ifTrue: [
      stopped isNil ifTrue: [stopped := OrderedCollection new].
      stopped add: { current id. aSend }.
      ^ self _trace: 'held ' , current id , ' -> ' , aSend to , ' ' , aSend message type , ' (scripted)'].
  ^ super _send: aSend at: aTime.

"=== The scenario families ==================================================="

Object subclass: #RejoinFamilies.

"A RejoinSim of three members, startup grace 0, the rules aRules: each id of aLogs starts over
 its Array of PBLogAppend, the others over an empty log."
RejoinFamilies class >> sim: aRules seed: n logs: aLogs
  ^ RejoinSim seed: n ids: BaseFamilies three rules: aRules
    options: (Dictionary new at: #startupGrace put: 0; yourself) logs: aLogs.

"A RejoinSim of three members formed before, each log holding r1 accepted and committed and the
 rejoined marker."
RejoinFamilies class >> formed: aRules seed: n
  | r1 logs |
  r1 := BaseFamilies r1.
  logs := Dictionary new.
  BaseFamilies three do: [:id |
    logs at: id put: { PBLogAppend kind: #accepted label: r1 label root: r1 record sync: true.
      PBLogAppend kind: #committed label: r1 label root: r1 record sync: true.
      PBLogAppend kind: #rejoined label: 0 root: nil sync: true }].
  ^ self sim: aRules seed: n logs: logs.

"aSim with every link 1 ms long: an owner whose renewals the members refuse (they promised a
 rejoin ballot) renews again at once until its lease ends (deviations.md, the open item on a
 lost renewal); at one round per 2 ms that is a few hundred rounds, not hundreds of thousands."
RejoinFamilies class >> lagged: aSim
  aSim ids do: [:a | aSim ids do: [:b | a = b ifFalse: [aSim delay: a to: b by: 1000]]].
  ^ aSim.

RejoinFamilies class >> isRejoined: anId in: aSim
  | node |
  node := aSim nodeAt: anId.
  ^ node isUp and: [node acceptor isRejoined].

"--- 1. the R78a schedule ---"

"{ violation text or nil. outcome of a. outcome of b. rejoin ballots at n2 }: proto_db
 test_r7_a_rejoin_is_safe_whatever_the_rate_of_the_wiped_nodes_timer (probe_drift_boundary).
 Three voters hold r1. a (n0) owns a term T and replicates R: it is descheduled between its
 broadcast and its own accept (its own acceptance held), b (n1) never gets R, c (n2) accepts it
 and acknowledges (the ack held in the network: c's later messages overtake it). c loses its
 disk and restarts with its timer rate times as fast; with isStall a's timer stands still from
 then on (a clock fault P5 admits: its permission stays valid on its own clock) until c's ack
 has arrived. Once c has rejoined, a's own acceptance runs, then the held ack arrives (what a
 sends b and c from then on is lost, so what it learns stays with it); a is cut off and its
 timer runs again. Then b commits b with c. The product: c's rejoin is a ballot that a and b promise
 before they answer, so a's own acceptance and every later acceptance of R are refused: R is
 never committed and b builds on r1. A rejoin that waits for time instead completes on answers
 that miss R; with a's timer standing still, a then counts c's old ack: R is acknowledged and b
 builds on r1 without it (S4)."
RejoinFamilies class >> r78a: aRules seed: n rate: aRate stall: isStall
  | sim d out |
  sim := self formed: aRules seed: n.
  d := (sim nodeAt: 'n0') config leaseDuration.
  out := Array new: 4.
  out at: 1 put: (BaseFamilies violationOf: [
    sim holdOwnReplicateAt: 'n0'.
    sim drop: 'replicate' from: 'n0' to: 'n1'.
    sim hold: 'ack' from: 'n2' to: 'n0'.
    sim commit: 'a' at: 'n0'.
    sim runUntil: [(sim rootOf: 'a') notNil and: [(sim syncedAcceptedOf: 'n2') includes: (sim rootOf: 'a') key]] steps: 300000.
    sim runUntil: [(sim nodeAt: 'n2') isLaneBusy not] steps: 1000.
    isStall ifTrue: [sim clockRate: 'n0' rate: 0].
    sim crash: 'n2' keepDisk: false.
    sim clockRate: 'n2' rate: aRate.
    sim restart: 'n2'.
    sim runUntil: [self isRejoined: 'n2' in: sim] steps: 2000000.
    sim releaseHeld.
    BaseFamilies run: sim until: sim now + 1000.
    "Whatever a learns from the ack stays with a (its done, release and replicates lost)."
    #('done' 'release' 'replicate') do: [:type | #('n1' 'n2') do: [:to | sim drop: type from: 'n0' to: to]].
    sim releaseMessages.
    BaseFamilies run: sim until: sim now + 1000.
    "a is cut off before its timer runs again: its renewals, refused by the ballot's promises,
     would otherwise be retried at once until its lease ends (deviations.md, the open item on
     a lost renewal)."
    sim partition: #(#('n0') #('n1' 'n2')).
    isStall ifTrue: [sim clockRate: 'n0' rate: 1].
    sim runUntil: [(sim outcomeOf: 'a') ~= #pending] steps: 2000000.
    out at: 2 put: (sim outcomeOf: 'a').
    "a's term ends while it is cut off (the same open item)."
    BaseFamilies run: sim until: sim now + (2 * d).
    out at: 3 put: (BaseFamilies commit: 'b' at: 'n1' in: sim).
    sim undrop.
    sim converge: 2000000]).
  out at: 4 put: (sim countOf: 'rejoin_ballots' at: 'n2').
  ^ out.

"{ n2 rejoined. rejoin ballots at n2 }: proto_db's literal R78a check (test_r7_a_..., 'no clock
 advance at all'): three voters hold r1, n2 loses its disk, and every clock stands still (rate
 0) from its restart on. A rejoin by ballot completes on messages alone (L13); one that waits for
 time never does."
RejoinFamilies class >> frozen: aRules seed: n
  | sim |
  sim := self formed: aRules seed: n.
  sim crash: 'n2' keepDisk: false.
  sim ids do: [:id | sim clockRate: id rate: 0].
  sim restart: 'n2'.
  sim runUntil: [self isRejoined: 'n2' in: sim] steps: 200000.
  ^ { self isRejoined: 'n2' in: sim. sim countOf: 'rejoin_ballots' at: 'n2' }.

"--- 2. a cluster's first start, and a late first start ---"

"{ violation. rejoin ballots of n0..n2. rejoins of n0..n2. the highest termsSeen of the acceptors
 once every member rejoined. outcome of a }: proto_db test_i1_a_genuine_first_start_with_a_grace_of_zero_does_not_wait.
 Three members start on empty logs, nobody asks for a term: each rejoin is 'new' (R51),
 without a ballot, and leaves termsSeen 0; then a commit is acknowledged."
RejoinFamilies class >> firstStart: aRules seed: n
  | sim out ids |
  sim := self sim: aRules seed: n logs: Dictionary new.
  ids := sim ids.
  out := Array new: 5.
  out at: 1 put: (BaseFamilies violationOf: [
    sim runUntil: [ids allSatisfy: [:id | self isRejoined: id in: sim]] steps: 200000.
    out at: 4 put: (ids inject: 0 into: [:a :id | a max: (sim nodeAt: id) acceptor grants termsSeen]).
    out at: 5 put: (BaseFamilies commit: 'a' at: 'n1' in: sim).
    sim converge: 2000000]).
  out at: 2 put: (ids collect: [:id | sim countOf: 'rejoin_ballots' at: id]).
  out at: 3 put: (ids collect: [:id | sim countOf: 'rejoins' at: id]).
  ^ out.

"{ violation. n0 asked a term before the others started. rejoin ballots of n1 and n2. outcome of
 a. the rejoin ballot of n1 and n2 above the term n0 asked }: proto_db
 test_a_late_first_start_member_after_a_term_was_requested_completes_by_ballot. n0 finished its
 first start (its log holds the rejoined marker only); n1 and n2, still empty, are down. n0 asks
 for a term (a commit), then n1 and n2 start: every member answers and none accepted a root,
 but n0 reports its term ('rootless'), so each rejoin goes through the ballot round, confirmed by
 n0, and completes; then a commits."
RejoinFamilies class >> lateStart: aRules seed: n
  | sim out asked |
  sim := self sim: aRules seed: n logs: (Dictionary new at: 'n0' put: { PBLogAppend kind: #rejoined label: 0 root: nil sync: true }; yourself).
  out := Array new: 5.
  out at: 1 put: (BaseFamilies violationOf: [
    sim crash: 'n1' keepDisk: false.
    sim crash: 'n2' keepDisk: false.
    sim commit: 'a' at: 'n0'.
    BaseFamilies run: sim until: sim now + 300000.
    asked := (sim nodeAt: 'n0') acceptor grants termsSeen.
    out at: 2 put: asked > 0.
    sim restart: 'n1'.
    sim restart: 'n2'.
    sim runUntil: [(self isRejoined: 'n1' in: sim) and: [self isRejoined: 'n2' in: sim]] steps: 2000000.
    out at: 5 put: (#('n1' 'n2') collect: [:id | (sim nodeAt: id) acceptor rejoinBallot > asked]).
    sim runUntil: [(sim outcomeOf: 'a') ~= #pending] steps: 2000000.
    out at: 4 put: (sim outcomeOf: 'a').
    sim converge: 2000000]).
  out at: 3 put: (#('n1' 'n2') collect: [:id | sim countOf: 'rejoin_ballots' at: id]).
  ^ out.

"{ violation. outcomes of a, b, c. ballots of n1 and n2. n1's term for c above its term for b.
 the ranks of the terms of b's and c's permissions }: proto_db test_cluster_root_certainty.py (two wiped
 acknowledgers of five; a wiped acknowledger requesting the lease builds on the committed root)
 and test_cluster_terms.py (a wiped granter never lets two roots share a label; a wiped proposer
 never wins its own ballot twice). Five voters hold r1. n0 commits a; n1 and n2, two of its
 acknowledgers, lose their disks and rejoin (one ballot each); once n0's ownership ended idle,
 n1 acquires a term and commits b, so its base must be a (S4 at every step). n1 loses its disk again and rejoins; it commits c under a term
 above the one it owned for b (S1 at every step: no term is owned twice)."
RejoinFamilies class >> wiped: aRules seed: n
  | sim out terms |
  sim := self lagged: (BaseFamilies sim: aRules seed: n ids: BaseFamilies five knowing: BaseFamilies five options: BaseFamilies fiveVoters).
  out := Array new: 5.
  terms := OrderedCollection new.
  out at: 1 put: (BaseFamilies violationOf: [
    out at: 2 put: (OrderedCollection with: (BaseFamilies commit: 'a' at: 'n0' in: sim)).
    #('n1' 'n2') do: [:id | sim crash: id keepDisk: false].
    #('n1' 'n2') do: [:id | sim restart: id].
    sim runUntil: [#('n1' 'n2') allSatisfy: [:id | self isRejoined: id in: sim]] steps: 2000000.
    out at: 3 put: (#('n1' 'n2') collect: [:id | sim countOf: 'rejoin_ballots' at: id]).
    "n0's ownership ends idle: n1 asks for the lease itself."
    BaseFamilies run: sim until: sim now + (3 * (sim nodeAt: 'n0') config leaseDuration).
    sim on: 'permit' at: 'n1' do: [:permission | terms add: permission term].
    (out at: 2) add: (BaseFamilies commit: 'b' at: 'n1' in: sim).
    sim crash: 'n1' keepDisk: false.
    sim restart: 'n1'.
    sim runUntil: [self isRejoined: 'n1' in: sim] steps: 2000000.
    BaseFamilies run: sim until: sim now + (3 * (sim nodeAt: 'n0') config leaseDuration).
    sim on: 'permit' at: 'n1' do: [:permission | terms add: permission term].
    (out at: 2) add: (BaseFamilies commit: 'c' at: 'n1' in: sim).
    sim converge: 2000000]).
  out at: 2 put: (out at: 2) asArray.
  out at: 4 put: (terms size = 2 and: [terms last > terms first]).
  out at: 5 put: (terms collect: [:term | term \\ PBMembership maxMembers]) asArray.
  ^ out.

"--- 3. a rejoined node never replicates below its ballot (L14) ---"

"{ violation. outcome of x. replicates n2 sent under a term below its rejoin ballot. n2's rejoin
 ballot above the owner's term }: proto_db test_probe_inflight_a_granter_wiped_during_a_lease and
 the L14 refusal of replicate. Three voters hold r1; n0 owns a term T0 and commits a0. n2 loses
 its disk and restarts; n0's next commit a1 reaches it while it rejoins (it learns that n0 owns
 T0; its queries are late by 20 ms; every link takes 1 ms, lagged:). Its rejoin ballot B > T0 is promised by n0 and n1. n2 then
 commits x: it asks n0, whose lease of T0 is still valid on its clock, for a permission, and gets
 one of T0. The product sends nothing under T0 < B (#none: a retryable conflict); the plant sends
 the replicate, which n0 and n1 refuse (the ballot rule): an unknown outcome that ends the term."
RejoinFamilies class >> belowBallot: aRules seed: n
  | sim out term below |
  sim := self lagged: (self formed: aRules seed: n).
  out := Array new: 4.
  out at: 1 put: (BaseFamilies violationOf: [
    BaseFamilies commit: 'a0' at: 'n0' in: sim.
    term := (sim nodeAt: 'n0') state ownership term.
    sim crash: 'n2' keepDisk: false.
    sim delay: 'n2' to: 'n0' by: 20000.
    sim delay: 'n2' to: 'n1' by: 20000.
    sim restart: 'n2'.
    BaseFamilies commit: 'a1' at: 'n0' in: sim.
    sim runUntil: [self isRejoined: 'n2' in: sim] steps: 2000000.
    sim delay: 'n2' to: 'n0' by: 1000.
    sim delay: 'n2' to: 'n1' by: 1000.
    out at: 4 put: (sim nodeAt: 'n2') acceptor rejoinBallot > term.
    out at: 2 put: (BaseFamilies commit: 'x' at: 'n2' in: sim).
    sim converge: 2000000]).
  below := sim sent select: [:e | e first = 'n2' and: [(e last type = 'replicate')
    and: [(e last at: 'term') < (sim nodeAt: 'n2') acceptor rejoinBallot]]].
  out at: 3 put: below size.
  ^ out.

"--- 4. losing a majority of acceptor logs ---"

"{ n0 and n2 rejoined before forceRejoin. after it: n0's accepted root is r1 and its committed
 root is not R. the error of b's base names forceRejoin. after forceRejoin on n1: its committed
 root dropped and needsConfirmation. outcome of c }: proto_db test_x3_majority_disk_loss_needs_force_rejoin,
 _majority_loss and test_y3_the_guard_names_its_remedy_and_force_rejoin_on_the_survivor_applies_it.
 Three voters hold r1. n0 commits R with n2 while n1 is cut off; n1 then learns R committed from
 a recovery answer only (its accepted root stays r1). n0 and n2 lose their disks: their answers
 are empty and n1 alone is too few witnesses, so neither rejoins. The operator forces both
 rejoins: they adopt n1's r1, and no committed root above it. n1's next commit finds its base r1
 below the committed root R it knows: PBCorruptionError naming forceRejoin. forceRejoin on n1
 (a survivor) forgets R and asks for a confirmation; the next commit builds on r1. R is lost:
 this is outside the failure model, so no convergence check runs."
RejoinFamilies class >> majorityLoss: aRules seed: n
  | sim d out r error |
  sim := self lagged: (self formed: aRules seed: n).
  d := (sim nodeAt: 'n0') config leaseDuration.
  out := Array new: 6.
  sim partition: #(#('n0' 'n2') #('n1')).
  BaseFamilies commit: 'a' at: 'n0' in: sim.
  r := sim rootOf: 'a'.
  BaseFamilies run: sim until: sim now + d.
  sim heal.
  sim dispatch: (PBRecoverWanted every: false waiter: { 'recover'. 'n1' }) at: 'n1'.
  sim runUntil: [sim recovered notEmpty and: [(sim nodeAt: 'n1') acceptor committed notNil
    and: [(sim nodeAt: 'n1') acceptor committed key = r key]]] steps: 100000.
  ((sim nodeAt: 'n1') acceptor committed key = r key and: [(sim nodeAt: 'n1') acceptor accepted key = BaseFamilies r1 key]) ifFalse: [
    ^ sim fail: 'majority loss: n1 should know R committed and have accepted r1'].
  sim crash: 'n0' keepDisk: false.
  sim crash: 'n2' keepDisk: false.
  sim restart: 'n0'.
  sim restart: 'n2'.
  BaseFamilies run: sim until: sim now + (2 * d).
  out at: 1 put: (#('n0' 'n2') collect: [:id | self isRejoined: id in: sim]).
  sim dispatch: PBRejoinWanted new at: 'n0'.
  sim dispatch: PBRejoinWanted new at: 'n2'.
  sim runUntil: [(self isRejoined: 'n0' in: sim) and: [self isRejoined: 'n2' in: sim]] steps: 2000000.
  out at: 2 put: { (sim nodeAt: 'n0') acceptor accepted key = BaseFamilies r1 key.
    (sim nodeAt: 'n0') acceptor committed isNil or: [(sim nodeAt: 'n0') acceptor committed key ~= r key] }.
  BaseFamilies commit: 'b' at: 'n1' in: sim.
  error := (BaseFamilies decisionsAt: 'n1' in: sim) detect: [:o | o isKindOf: PBCorruptionError] ifNone: [nil].
  out at: 3 put: (error notNil and: [error messageText includesSubstring: 'forceRejoin']).
  sim dispatch: PBRejoinWanted new at: 'n1'.
  sim runUntil: [(sim nodeAt: 'n1') acceptor committed isNil] steps: 100000.
  out at: 4 put: { (sim nodeAt: 'n1') acceptor committed isNil. (sim nodeAt: 'n1') acceptor needsConfirmation }.
  out at: 5 put: (BaseFamilies commit: 'c' at: 'n1' in: sim).
  out at: 6 put: (sim outcomeOf: 'b').
  ^ out.
