"-- cluster/rejoin.st: the rejoin of an empty acceptor log, forceRejoin, the confirmation flag --

The rejoin of proto_db's ClusterCoordinator (cluster/coordinator.py at v2.0.0rc3: _rejoin,
_rejoin_round, _gather, _rejoin_decision, _rejoin_answers, _complete_rejoin, _publish_rejoin,
_block_rejoin, _on_ballot_query, force_rejoin, needs_confirmation and confirmed; CP 'A node that
lost its disk', rulings R51 and R78a, lessons L13, L14 and L18) as rule methods of
PBCoordinatorCore over the values of core.st, acceptor.st, proposer.st, holder.st and this module.
proto_db's rejoin is a thread that waits on its queries; here each wait is a phase of a PBRejoin
value, kept in PBNodeState rejoin, and a PBTimer. Nothing here reads a clock: t is the node's
clock (CC3).

  Starting. A log without the rejoined marker (kind 4) leaves a voter with other voters
    rejoining (acceptor.st acceptStart:in:now:): it grants nothing, acknowledges nothing and
    answers 'empty' (acceptor.st). When its acceptor reports so (dispatchAcceptorDecided:,
    proposer.st, calls rejoinCheck:now:effects:), the dispatcher starts the rejoin
    (_rejoinStart:now:effects:), unless the acceptor's tier failed or the node is fenced.
  A round (proto_db _rejoin_round). A plain gather (ballot 0): 'query' (rid, inc, ballot, vs) to
    every other voter; an attempt ends when each voter asked answered, or at requestTimeout,
    and a voter that has not answered is asked again, gatherAttempts attempts in all (proto_db
    _gather and GATHER_ATTEMPTS; each attempt a new rid, an answer to another rid or of another
    incarnation never counted). Then rejoinDecision:forced:in: (proto_db _rejoin_decision):
    loaded answers are the states 'ok' and 'empty', witnesses the 'ok' ones; forced, majority - 1
    loaded answers ('forced'); every other voter loaded, none with an accepted root, none
    reporting a promised term: 'new' (a cluster's first start, R51); the same with a term
    reported and too few witnesses: 'rootless'; rejoinAnswersNeeded:forced: witnesses
    (min(V - 1, V - majority + 1)): 'witnesses'; else nothing (the round is retried).
    'new' and 'forced' complete on the plain answers. 'witnesses' and 'rootless' go through the
    ballot round (R78a): rejoinBallotFor:in: is ballotAfter of the highest promise and label the
    answers report, the highest term the acceptor saw and the hint, at this node's rank; a
    second gather asks with it, an 'ok' answer that does not echo it counts as 'unknown' (its
    answer did not follow a durable promise of the ballot), and the decision must again be
    'witnesses' or 'rootless', else the rejoin is blocked ('too few members confirmed the
    rejoin ballot ... durably; it asks again') and retried. Counted rejoin_ballots.
  Completing (proto_db _complete_rejoin). Of the counted answers: learnt, the highest promise
    and label (the ballot included); the highest accepted root; the highest committed root
    (forced: none above that accepted root). The records of the accepted root are in the shared
    storage (L11): no fetch; its SpaceRoot is probed (PBProbeRoot, a protoBaseST addition: an
    unreadable one blocks the rejoin, with the reason, and it is retried). The acceptor then
    takes PBRejoinLearnt: it appends the promise of learnt, the accepted root and the rejoined
    marker, in that order, each synced, and only then adopts them (PBGrantState restore:seen:,
    the floor learnt, seen the promises only, so termsSeen stays 0 for a first start, R51), the
    committed root as committed knowledge (not accepted, not logged), and the rejoin ballot
    (rejoinBallot, never lowered). When that step comes back (PBAcceptorDecided), the rejoin
    ends: counted rejoins, the hint raised to learnt, and the waiters of the proposer go on. A
    discarded step (its append failed: the tier failed, R57) blocks the rejoin for good.
  Retrying. A round that decides nothing, a blocked ballot round and an unreadable root are
    retried after requestTimeout (proto_db's wait in _rejoin): a retry of a query, never a
    wait that makes anything safe (L13). rejoinBlockedIn: is proto_db's stats rejoin_blocked.
  The witness (proto_db _on_ballot_query): a query with a ballot to an 'ok' acceptor promises the
    ballot (PBGrantState promise:; a lower grant it ends makes the node suspect for its term),
    appends the promise synced when it is above the logged one, and answers after the sync,
    echoing the ballot, with its accepted and committed roots read in the same step. Any other
    state answers as a plain query (ballot 0); a fenced node answers no ballot query.
  forceRejoin (PBRejoinWanted, proto_db force_rejoin): the operator's decision after the loss of
    a majority of acceptor logs. On a node not rejoined yet (its acceptor's last report, or
    none yet), its rejoin, running or to come, completes with the answers of majority - 1
    loaded members after a plain round ('forced'); always, the acceptor takes PBForceRejoin,
    which on a rejoined acceptor (a survivor) forgets a committed root that orders above its
    accepted root and asks for a confirmation again.
  The confirmation flag (L18, proto_db needs_confirmation and confirmed): PBAcceptorState
    needsConfirmation is true after every attach (a new acceptor state); PBConfirmed, which the
    space sends as its confirmation round starts (one attempt per attach, proto_db
    _read_storage_root), clears it.

Every value here is immutable: built once by its class-side constructor; with: answers a new
value."

Import from: 'protobase/errors'.
Import from: 'protobase/cluster/members'.
Import from: 'protobase/cluster/rootlog'.
Import from: 'protobase/cluster/protocol'.
Import from: 'protobase/cluster/config'.
Import from: 'protobase/cluster/lease'.
Import from: 'protobase/cluster/core'.
Import from: 'protobase/cluster/acceptor'.
Import from: 'protobase/cluster/proposer'.
Import from: 'protobase/cluster/owner'.
Import from: 'protobase/cluster/holder'.

"=== Events ==================================================================="

"--- PBRejoinLearnt (an acceptor event) ---"

PBCoreEvent subclass: #PBRejoinLearnt instanceVariableNames: 'learnt seen accepted committed ballot'.

"What a rejoin learnt (proto_db _complete_rejoin): aLearnt, the highest promise and label of the
 counted answers and the ballot; aSeen, the highest of their promises only; anAccepted, the
 highest accepted root (a PBLabeledRoot or nil); aCommitted, the highest committed root (or nil);
 aBallot, the ballot its answers confirmed (0 for 'new' and 'forced'). Integers >= 0."
PBRejoinLearnt class >> learnt: aLearnt seen: aSeen accepted: anAccepted committed: aCommitted ballot: aBallot
  ({ aLearnt. aSeen. aBallot } allSatisfy: [:n | n isInteger and: [n >= 0]]) ifFalse: [
    ^ PBValidationError signal: 'PBRejoinLearnt: learnt, seen and ballot are Integers >= 0'].
  ({ anAccepted. aCommitted } allSatisfy: [:r | r isNil or: [r isClassObject not and: [r class == PBLabeledRoot]]]) ifFalse: [
    ^ PBValidationError signal: 'PBRejoinLearnt: the roots are PBLabeledRoots or nil'].
  ^ self basicNew _setLearnt: aLearnt seen: aSeen accepted: anAccepted committed: aCommitted ballot: aBallot.

PBRejoinLearnt class >> isAcceptorEvent
  ^ true.

PBRejoinLearnt >> _setLearnt: aLearnt seen: aSeen accepted: anAccepted committed: aCommitted ballot: aBallot
  "Runs once, on a fresh instance."
  learnt isNil ifFalse: [^ PBUserError signal: 'PBRejoinLearnt is immutable'].
  learnt := aLearnt.
  seen := aSeen.
  accepted := anAccepted.
  committed := aCommitted.
  ballot := aBallot.
  ^ self.

PBRejoinLearnt >> learnt
  ^ learnt.

PBRejoinLearnt >> seen
  ^ seen.

PBRejoinLearnt >> accepted
  ^ accepted.

PBRejoinLearnt >> committed
  ^ committed.

PBRejoinLearnt >> ballot
  ^ ballot.

PBRejoinLearnt >> acceptWith: aCore in: anAcceptorState now: t
  ^ aCore acceptRejoinLearnt: self in: anAcceptorState now: t.

PBRejoinLearnt >> printOn: aStream
  aStream nextPutAll: 'PBRejoinLearnt('; print: learnt; nextPutAll: ', '; nextPutAll: (PBCoreValue textOf: accepted);
    nextPutAll: ', ballot '; print: ballot; nextPut: $).

"--- PBForceRejoin (an acceptor event) ---"

"The acceptor's half of forceRejoin (proto_db force_rejoin on a survivor)."
PBCoreEvent subclass: #PBForceRejoin.

PBForceRejoin class >> isAcceptorEvent
  ^ true.

PBForceRejoin >> acceptWith: aCore in: anAcceptorState now: t
  ^ aCore acceptForceRejoin: self in: anAcceptorState now: t.

"--- PBConfirmed (a dispatcher and acceptor event) ---"

"The space starts the confirmation round of this attach (proto_db confirmed(), called once per
 attach before _commit_under_lease)."
PBCoreEvent subclass: #PBConfirmed.

PBConfirmed class >> isAcceptorEvent
  ^ true.

PBConfirmed >> dispatchWith: aCore in: aNodeState now: t
  ^ aCore dispatchConfirmed: self in: aNodeState now: t.

PBConfirmed >> acceptWith: aCore in: anAcceptorState now: t
  ^ aCore acceptConfirmed: self in: anAcceptorState now: t.

"=== PBRejoinAnswer ==========================================================="

"One answer to a rejoin's query (proto_db _on_answer's answers, promised, states and ballots of a
 waiter): from, accepted and committed (PBLabeledRoots or nil), certain, promised, state ('ok',
 'empty', 'learner' or 'unknown') and ballot (the ballot it echoes, 0 for a plain answer)."
PBProposerValue subclass: #PBRejoinAnswer.

PBRejoinAnswer class >> fieldNames
  ^ #(#from #accepted #committed #certain #promised #state #ballot).

"The answer aMessage (an 'answer' PBClusterMessage)."
PBRejoinAnswer class >> from: aMessage
  ^ self _from: (Dictionary new
    at: #from put: aMessage from; at: #accepted put: (PBClusterMessage rootFrom: (aMessage at: 'root'));
    at: #committed put: (PBClusterMessage rootFrom: (aMessage at: 'committed')); at: #certain put: (aMessage at: 'certain');
    at: #promised put: (aMessage at: 'promised'); at: #state put: (aMessage at: 'state'); at: #ballot put: (aMessage at: 'ballot');
    yourself).

PBRejoinAnswer >> from
  ^ self _at: #from.

PBRejoinAnswer >> accepted
  ^ self _at: #accepted.

PBRejoinAnswer >> committed
  ^ self _at: #committed.

PBRejoinAnswer >> certain
  ^ self _at: #certain.

PBRejoinAnswer >> promised
  ^ self _at: #promised.

PBRejoinAnswer >> state
  ^ self _at: #state.

PBRejoinAnswer >> ballot
  ^ self _at: #ballot.

"The highest label this answer reports: its promise, its accepted and committed roots' labels."
PBRejoinAnswer >> highestLabel
  | n |
  n := self promised.
  self accepted notNil ifTrue: [n := n max: self accepted label].
  self committed notNil ifTrue: [n := n max: self committed label].
  ^ n.

"=== PBRejoin ================================================================="

"A rejoin of this node (proto_db _rejoin's thread and its state _rejoin_forced, _rejoin_blocked):
 phase (#idle: none runs, a forceRejoin waits for it; #gather; #probe: the adopted root's
 SpaceRoot is probed; #adopt: the acceptor takes what was learnt; #retry: the next round waits
 for its timer; #failed: the tier failed), forced, blocked (why it cannot complete, or nil),
 ballot (of the gather, 0 for a plain one), attempt (of the gather), rid and targets (of its
 attempt), token (of its timer or probe), answers (PBRejoinAnswers of the gather, one per
 member) and pending (the PBRejoinLearnt to adopt)."
PBProposerValue subclass: #PBRejoin.

PBRejoin class >> fieldNames
  ^ #(#phase #forced #blocked #ballot #attempt #rid #targets #token #answers #pending).

"No rejoin running, not forced."
PBRejoin class >> idle
  ^ self _from: (Dictionary new
    at: #phase put: #idle; at: #forced put: false; at: #blocked put: nil; at: #ballot put: 0; at: #attempt put: 0;
    at: #rid put: nil; at: #targets put: #(); at: #token put: nil; at: #answers put: #(); at: #pending put: nil; yourself).

PBRejoin >> phase
  ^ self _at: #phase.

PBRejoin >> isForced
  ^ self _at: #forced.

"Why the rejoin cannot complete now (proto_db stats rejoin_blocked), or nil."
PBRejoin >> blocked
  ^ self _at: #blocked.

PBRejoin >> ballot
  ^ self _at: #ballot.

PBRejoin >> attempt
  ^ self _at: #attempt.

PBRejoin >> rid
  ^ self _at: #rid.

"The members the current attempt asked, a fresh Array."
PBRejoin >> targets
  ^ (self _at: #targets) copy.

PBRejoin >> token
  ^ self _at: #token.

"The answers of the gather, one per member, a fresh Array."
PBRejoin >> answers
  ^ (self _at: #answers) copy.

PBRejoin >> pending
  ^ self _at: #pending.

"This rejoin with anAnswer recorded, replacing an earlier one of its sender."
PBRejoin >> answered: anAnswer
  ^ self with: { #answers -> (((self _at: #answers) reject: [:a | a from = anAnswer from]) copyWith: anAnswer) }.

"Whether anId answered the gather."
PBRejoin >> hasAnswerFrom: anId
  ^ (self _at: #answers) anySatisfy: [:a | a from = anId].

PBRejoin >> printOn: aStream
  aStream nextPutAll: 'PBRejoin('; nextPutAll: self phase; nextPutAll: ', ballot '; print: self ballot; nextPut: $).

"=== PBCoordinatorCore: the decision ==========================================="

"The other voters of the node of s (proto_db _other_voters)."
PBCoordinatorCore >> _otherVoters: s
  ^ s config membership voters reject: [:v | v = s config nodeId].

"The witness answers from other voters a rejoin needs (proto_db _rejoin_answers): V - majority +
 1 of the V voters, every other voter when fewer (min(V - 1, V - majority + 1)): any majority that
 granted a term or acknowledged a root holds majority - 1 voters besides this node, and that many
 answers of the V - 1 others always include one of them. Forced: majority - 1."
PBCoordinatorCore >> rejoinAnswersNeeded: s forced: isForced
  | membership |
  membership := s config membership.
  isForced ifTrue: [^ membership majority - 1].
  ^ (self _otherVoters: s) size min: membership voters size - membership majority + 1.

"proto_db _rejoin_decision: { the ids of the answers that count. how } (#forced, #new, #rootless
 or #witnesses), or nil when someAnswers (PBRejoinAnswers) are not enough. Only other voters'
 answers count; 'unknown' and 'learner' never do."
PBCoordinatorCore >> rejoinDecision: someAnswers forced: isForced in: s
  | others loaded witnesses |
  others := self _otherVoters: s.
  loaded := someAnswers select: [:a | (others includes: a from) and: [a state = 'ok' or: [a state = 'empty']]].
  witnesses := loaded select: [:a | a state = 'ok'].
  isForced ifTrue: [
    ^ loaded size >= (self rejoinAnswersNeeded: s forced: true)
      ifTrue: [{ loaded collect: [:a | a from]. #forced }] ifFalse: [nil]].
  (loaded size = others size and: [loaded allSatisfy: [:a | a accepted isNil]]) ifTrue: [
    "A new cluster: no root accepted, no term seen (R51). A lease granted before the first
     commit leaves its term at its granters: rootless, which takes the ballot round."
    (loaded allSatisfy: [:a | a promised = 0]) ifTrue: [^ { loaded collect: [:a | a from]. #new }].
    witnesses size < (self rejoinAnswersNeeded: s forced: false) ifTrue: [^ { loaded collect: [:a | a from]. #rootless }]].
  witnesses size >= (self rejoinAnswersNeeded: s forced: false) ifTrue: [^ { witnesses collect: [:a | a from]. #witnesses }].
  ^ nil.

"The ballot of a rejoin's ballot round (proto_db _rejoin_round, R78a): above every promise and
 label someAnswers report, the highest term this node's acceptor saw and its hint, at its rank."
PBCoordinatorCore >> rejoinBallotFor: someAnswers in: s
  | floor view |
  floor := someAnswers inject: 0 into: [:m :a | m max: a highestLabel].
  view := s acceptorView.
  view notNil ifTrue: [floor := floor max: view grants highestSeen].
  floor := floor max: (self _hintsIn: s) hint.
  ^ PBMembership ballotAfter: floor rank: s config rank.

"proto_db _gather with a ballot: an 'ok' answer that does not echo aBallot did not follow a
 durable promise of it, so it counts as 'unknown'."
PBCoordinatorCore >> _confirming: aBallot answers: someAnswers
  ^ someAnswers collect: [:a |
    (a state = 'ok' and: [a ballot ~= aBallot]) ifTrue: [a with: { #state -> 'unknown' }] ifFalse: [a]].

"=== PBCoordinatorCore: the rounds ============================================="

"The node's rejoin, a PBRejoin (idle when none ran yet)."
PBCoordinatorCore >> _rejoinIn: s
  ^ s rejoin isNil ifTrue: [PBRejoin idle] ifFalse: [s rejoin].

"Why the rejoin of the node of s cannot complete (proto_db stats rejoin_blocked: only while it
 rejoins), or nil."
PBCoordinatorCore >> rejoinBlockedIn: s
  (s acceptorView isNil or: [s acceptorView isRejoined or: [s rejoin isNil]]) ifTrue: [^ nil].
  ^ s rejoin blocked.

"The acceptor reported (s acceptorView): a log without the rejoined marker starts a rejoin
 (proto_db _attach_locked starts its thread), unless one runs, its tier failed or the node is
 fenced; a rejoined acceptor ends the rejoin (counted rejoins when its adoption came back, the
 hint raised to what it learnt)."
PBCoordinatorCore >> rejoinCheck: s now: t effects: fx
  | view r h |
  view := s acceptorView.
  view isNil ifTrue: [^ s].
  r := s rejoin.
  view isRejoined ifTrue: [
    r isNil ifTrue: [^ s].
    r phase = #adopt ifFalse: [^ s with: { #rejoin -> nil }].
    fx add: (PBCount stat: 'rejoins').
    h := self _hintsIn: s.
    ^ s with: { #rejoin -> nil. #hints -> (h with: { #hint -> (h hint max: r pending learnt) }) }].
  (r notNil and: [r phase ~= #idle]) ifTrue: [^ s].
  (view tierFailed notNil or: [s fenced notNil]) ifTrue: [^ s].
  ^ self _rejoinStart: (s with: { #rejoin -> (self _rejoinIn: s) }) now: t effects: fx.

"The rejoin starts: its first round (proto_db _rejoin's loop)."
PBCoordinatorCore >> _rejoinStart: s now: t effects: fx
  ^ self rejoinRound: s now: t effects: fx.

"proto_db _rejoin_round: a plain gather first."
PBCoordinatorCore >> rejoinRound: s now: t effects: fx
  ^ self _gather: 0 in: s now: t effects: fx.

"A gather of answers to queries carrying aBallot (proto_db _gather): no answer yet."
PBCoordinatorCore >> _gather: aBallot in: s now: t effects: fx
  | r |
  r := (self _rejoinIn: s) with: { #phase -> #gather. #ballot -> aBallot. #attempt -> 0. #answers -> #(). #pending -> nil }.
  ^ self _rejoinAsk: (s with: { #rejoin -> r }) now: t effects: fx.

"One attempt of the gather: the query to every other voter that has not answered, a new rid, a
 timer of requestTimeout."
PBCoordinatorCore >> _rejoinAsk: s now: t effects: fx
  | r missing rid pair msg |
  r := s rejoin.
  missing := (self _otherVoters: s) reject: [:id | r hasAnswerFrom: id].
  rid := s nextRid.
  pair := self _token: #rejoin in: (s with: { #nextRid -> (rid + 1) }).
  msg := PBClusterMessage type: 'query' from: s config nodeId fields: {
    'rid' -> rid. 'inc' -> s inc. 'ballot' -> r ballot. 'vs' -> s config membership fingerprint }.
  missing do: [:id | fx add: (PBSend to: id message: msg)].
  fx add: (PBTimer after: s config requestTimeout token: pair last event: #rejoin).
  ^ pair first with: { #rejoin -> (r with: { #attempt -> (r attempt + 1). #rid -> rid. #targets -> missing. #token -> pair last }) }.

"An answer to the rejoin's current attempt (its rid; the caller dropped one of another
 incarnation): recorded when its sender was asked; the attempt ends once every member it asked
 answered. Answers nil when aMessage answers no rejoin of s."
PBCoordinatorCore >> rejoinAnswered: aMessage in: s now: t effects: fx
  | r state |
  r := s rejoin.
  (r notNil and: [r phase = #gather and: [r rid = (aMessage at: 'rid')]]) ifFalse: [^ nil].
  (r targets includes: aMessage from) ifFalse: [^ s].
  r := r answered: (PBRejoinAnswer from: aMessage).
  state := s with: { #rejoin -> r }.
  (r targets allSatisfy: [:id | r hasAnswerFrom: id]) ifFalse: [^ state].
  ^ self _attemptEnded: state now: t effects: fx.

"The rejoin's timer: an attempt's requestTimeout passed, or a retry is due. One whose token is
 not the current one is ignored."
PBCoordinatorCore >> rejoinTimer: anEvent in: s now: t effects: fx
  | r view |
  r := s rejoin.
  (r notNil and: [r token = anEvent token]) ifFalse: [^ s].
  r phase = #gather ifTrue: [^ self _attemptEnded: s now: t effects: fx].
  r phase = #retry ifFalse: [^ s].
  view := s acceptorView.
  "proto_db _rejoin stops when the tier failed (or the coordinator stopped)."
  (view isNil or: [view tierFailed notNil or: [s fenced notNil]]) ifTrue: [
    ^ s with: { #rejoin -> (r with: { #phase -> #failed. #token -> nil }) }].
  ^ self rejoinRound: s now: t effects: fx.

"An attempt ended: the members that did not answer are asked again, up to gatherAttempts
 attempts in all; then the gather is over."
PBCoordinatorCore >> _attemptEnded: s now: t effects: fx
  | r missing |
  r := s rejoin.
  missing := (self _otherVoters: s) reject: [:id | r hasAnswerFrom: id].
  (missing notEmpty and: [r attempt < s config gatherAttempts]) ifTrue: [^ self _rejoinAsk: s now: t effects: fx].
  ^ self _gathered: s now: t effects: fx.

"The gather is over (proto_db _rejoin_round). A plain one decides: nothing, a retry; 'new' or
 'forced', complete; 'witnesses' or 'rootless', the ballot round. A ballot round must decide
 'witnesses' or 'rootless' again on the answers that echo its ballot, else the rejoin is blocked
 and retried."
PBCoordinatorCore >> _gathered: s now: t effects: fx
  | r answers decision |
  r := s rejoin.
  r ballot = 0 ifTrue: [
    answers := r answers.
    decision := self rejoinDecision: answers forced: r isForced in: s.
    decision isNil ifTrue: [^ self _rejoinRetry: s after: s config requestTimeout now: t effects: fx].
    (decision last = #witnesses or: [decision last = #rootless]) ifTrue: [
      ^ self _ballotRound: decision answers: answers in: s now: t effects: fx].
    ^ self _completeRejoin: decision answers: answers ballot: 0 in: s now: t effects: fx].
  answers := self _confirming: r ballot answers: r answers.
  decision := self rejoinDecision: answers forced: false in: s.
  (decision notNil and: [decision last = #witnesses or: [decision last = #rootless]]) ifFalse: [
    ^ self _rejoinRetry: (self _block: 'too few members confirmed the rejoin ballot ' , r ballot printString
      , ' durably; it asks again' in: s) after: s config requestTimeout now: t effects: fx].
  fx add: (PBCount stat: 'rejoin_ballots').
  ^ self _completeRejoin: decision answers: answers ballot: r ballot in: s now: t effects: fx.

"The ballot round (R78a): a gather asking every other voter to promise a fresh ballot first."
PBCoordinatorCore >> _ballotRound: aDecision answers: someAnswers in: s now: t effects: fx
  ^ self _gather: (self rejoinBallotFor: someAnswers in: s) in: s now: t effects: fx.

"s with its rejoin blocked for aReason (proto_db _block_rejoin)."
PBCoordinatorCore >> _block: aReason in: s
  ^ s with: { #rejoin -> ((self _rejoinIn: s) with: { #blocked -> aReason }) }.

"The next round after someMicros of this node's clock (proto_db _rejoin's wait between rounds:
 a retry, never a wait for safety, L13)."
PBCoordinatorCore >> _rejoinRetry: s after: someMicros now: t effects: fx
  | pair |
  pair := self _token: #rejoin in: s.
  fx add: (PBTimer after: someMicros token: pair last event: #rejoin).
  ^ pair first with: { #rejoin -> ((self _rejoinIn: pair first) with: { #phase -> #retry. #token -> pair last. #pending -> nil }) }.

"proto_db _complete_rejoin: what the counted answers of aDecision teach (learnt, the highest
 promise and label, aBallot included; seen, their promises only; the highest accepted root; the
 highest committed root, none above that accepted root when forced). The accepted root's SpaceRoot
 is probed first when it has one."
PBCoordinatorCore >> _completeRejoin: aDecision answers: someAnswers ballot: aBallot in: s now: t effects: fx
  | counted learnt seen best committed learn pair |
  counted := someAnswers select: [:a | aDecision first includes: a from].
  learnt := counted inject: aBallot into: [:m :a | m max: a highestLabel].
  seen := counted inject: 0 into: [:m :a | m max: a promised].
  best := nil.
  committed := nil.
  counted do: [:a |
    best := PBRootOrder max: best with: a accepted.
    committed := PBRootOrder max: committed with: a committed].
  (aDecision last = #forced and: [committed notNil and: [(PBRootOrder compare: committed with: best) > 0]]) ifTrue: [
    "A majority loss may have lost the commits above the root the bare majority accepted."
    committed := nil].
  learn := PBRejoinLearnt learnt: learnt seen: seen accepted: best committed: committed ballot: aBallot.
  (best isNil or: [best record isNil]) ifTrue: [^ self _adopt: learn in: s effects: fx].
  pair := self _token: #rejoin in: s.
  fx add: (PBProbeRoot root: best token: pair last).
  ^ pair first with: { #rejoin -> ((self _rejoinIn: pair first) with: { #phase -> #probe. #token -> pair last. #pending -> learn }) }.

"The acceptor logs and adopts what the rejoin learnt (PBRejoinLearnt)."
PBCoordinatorCore >> _adopt: aLearnt in: s effects: fx
  fx add: (PBToAcceptor event: aLearnt).
  ^ s with: { #rejoin -> ((self _rejoinIn: s) with: { #phase -> #adopt. #token -> nil. #pending -> aLearnt }) }.

"The probe of the adopted root's SpaceRoot came back (the rejoin's token: answers nil
 otherwise): readable, the acceptor adopts it; else the rejoin is blocked, with the reason, and
 retried."
PBCoordinatorCore >> rejoinProbed: anEvent in: s now: t effects: fx
  | r root |
  r := s rejoin.
  (r notNil and: [r phase = #probe and: [r token = anEvent token]]) ifFalse: [^ nil].
  anEvent isReadable ifTrue: [^ self _adopt: r pending in: (self _block: nil in: s) effects: fx].
  root := r pending accepted.
  ^ self _rejoinRetry: (self _block: 'the shared storage cannot read the SpaceRoot of the root it adopts (label '
    , root label printString , ', epoch ' , root epoch printString , '); it asks again' in: s)
    after: s config requestTimeout now: t effects: fx.

"The acceptor discarded the step of aStep (its append failed: the tier failed, R57): when it was
 the rejoin's adoption, the rejoin is blocked for good (proto_db _complete_rejoin's failed write).
 Answers s otherwise."
PBCoordinatorCore >> rejoinDiscarded: aStep in: s
  | r |
  r := s rejoin.
  (r notNil and: [r phase = #adopt and: [aStep appends anySatisfy: [:a | a kind = #rejoined]]]) ifFalse: [^ s].
  ^ s with: { #rejoin -> (r with: { #phase -> #failed. #token -> nil.
    #blocked -> 'writing its acceptor log failed; close and reopen the space on a healthy disk' }) }.

"=== PBCoordinatorCore: forceRejoin and the confirmation ======================="

"proto_db force_rejoin: on a node whose acceptor has not reported rejoined (rejoining, or not
 reported yet), its rejoin, running or to come, is forced; the acceptor's half (PBForceRejoin)
 always follows, and acts on a survivor only."
PBCoordinatorCore >> dispatchRejoinWanted: anEvent in: s now: t
  | view state |
  view := s acceptorView.
  state := s.
  (view isNil or: [view isRejoined not]) ifTrue: [
    state := s with: { #rejoin -> ((self _rejoinIn: s) with: { #forced -> true }) }].
  ^ PBStep state: state effects: { PBToAcceptor event: PBForceRejoin new }.

"proto_db force_rejoin on a survivor (loaded and rejoined): a committed root that orders above
 every root it accepted names a commit lost with the other logs; it is forgotten (memory only:
 it was learnt from an answer, never logged), and the node confirms again (L18)."
PBCoordinatorCore >> acceptForceRejoin: anEvent in: s now: t
  | state |
  (s fenced notNil or: [s isRejoined not]) ifTrue: [^ self _unchangedAcceptor: s].
  (s committed notNil and: [s accepted isNil or: [(PBRootOrder compare: s committed with: s accepted) > 0]]) ifFalse: [
    ^ self _unchangedAcceptor: s].
  state := s with: { #committed -> nil. #confirmed -> false }.
  ^ PBAcceptorStep state: state appends: #() reply: { PBPublishAcceptor state: state }.

"The space starts the confirmation round of this attach: its acceptor records it."
PBCoordinatorCore >> dispatchConfirmed: anEvent in: s now: t
  ^ PBStep state: s effects: { PBToAcceptor event: anEvent }.

"proto_db confirmed(): needsConfirmation is false until the next attach (or forceRejoin)."
PBCoordinatorCore >> acceptConfirmed: anEvent in: s now: t
  s needsConfirmation ifFalse: [^ self _unchangedAcceptor: s].
  ^ PBAcceptorStep state: (s with: { #confirmed -> true }) appends: #() reply: #().

"=== PBCoordinatorCore: the acceptor's rules ===================================="

"proto_db _complete_rejoin's writes and _publish_rejoin: the promise of learnt, the accepted root
 and the rejoined marker, appended in that order and synced, then adopted: the floor learnt and
 the promises seen (restore:seen:), the accepted root, the committed root as committed knowledge
 only, the rejoin ballot (never lowered). A rejoined, failed or fenced acceptor takes nothing."
PBCoordinatorCore >> acceptRejoinLearnt: anEvent in: s now: t
  | appends state label reply triple |
  (s fenced notNil or: [s isRejoined or: [s tierFailed notNil]]) ifTrue: [^ self _unchangedAcceptor: s].
  appends := OrderedCollection new.
  anEvent learnt > 0 ifTrue: [appends add: (PBLogAppend kind: #promise label: anEvent learnt root: nil sync: true)].
  anEvent accepted notNil ifTrue: [
    appends add: (PBLogAppend kind: #accepted label: anEvent accepted label root: anEvent accepted record sync: true)].
  "Last: the log now holds what the node must know."
  appends add: (PBLogAppend kind: #rejoined label: 0 root: nil sync: true).
  state := (s withGrants: (s grants restore: anEvent learnt seen: anEvent seen) suspectTerm: s suspectTerm rejoined: true
      tierFailed: s tierFailed loggedPromise: (s loggedPromise max: anEvent learnt))
    with: { #rejoinBallot -> (s rejoinBallot max: anEvent ballot) }.
  label := 0.
  reply := OrderedCollection new.
  anEvent accepted notNil ifTrue: [
    state := self _observeAccepted: anEvent accepted in: state.
    label := anEvent accepted label].
  anEvent committed notNil ifTrue: [
    triple := self _learnCommitted: anEvent committed accept: false logged: false in: state.
    state := triple first.
    reply addAll: triple last.
    label := label max: anEvent committed label].
  reply addFirst: (PBPublishAcceptor state: state).
  ^ PBAcceptorStep state: state appends: appends asArray reply: reply asArray vote: nil learnt: label.

"proto_db _on_ballot_query: an 'ok' acceptor promises aMessage's ballot (a lower grant it ends:
 suspect for its term), appends the promise synced when above the logged one, and answers after
 the sync, echoing the ballot; the roots it reports are read in the same step, so no acceptance
 falls between (R55). Any other state answers as a plain query. A fenced node answers no ballot
 query (proto_db _enqueue)."
PBCoordinatorCore >> _ballotQuery: aMessage in: s now: t
  | ballot pair next appends |
  s fenced notNil ifTrue: [^ self _unchangedAcceptor: s].
  (self _witnessStateIn: s) = 'ok' ifFalse: [^ self _plainQuery: aMessage in: s].
  ballot := aMessage at: 'ballot'.
  pair := s grants promise: ballot.
  next := s withGrants: pair first suspectTerm: (s suspectTerm max: pair last) rejoined: s isRejoined
    tierFailed: s tierFailed loggedPromise: (s loggedPromise max: ballot).
  appends := ballot > s loggedPromise
    ifTrue: [{ PBLogAppend kind: #promise label: ballot root: nil sync: true }]
    ifFalse: [#()].
  ^ PBAcceptorStep state: next appends: appends
    reply: { PBSend to: aMessage from message: (self _answer: aMessage state: 'ok' ballot: ballot in: next) }.
