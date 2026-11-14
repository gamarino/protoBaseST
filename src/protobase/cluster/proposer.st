"-- cluster/proposer.st: the proposer's rules: acquiring, owning, renewing, releasing, fairness --

The proposer side of proto_db's ClusterCoordinator (cluster/coordinator.py at v2.0.0rc3:
permit's loop, _become_owner, _await_turn, _open_attempt, _close_attempt, _back_off, release,
_own_loop_body, _renew, _on_reply and the fairness hints _note_wanting, _note_request,
_note_release, _next_turn) as rule methods of PBCoordinatorCore over the values of lease.st,
core.st and this module. proto_db's threads wait on a condition; here each wait is a phase of
the state value and a PBTimer, and every event that would notify the condition re-evaluates the
phase (_poke:now:effects:). Nothing here reads a clock: t is the node's clock (CC3).

  Acquiring (CP 1.5, proto_db permit then _become_owner). A PBPermitWanted queues its waiter;
    while this node owns no term and runs no acquisition, the first waiter starts one
    (PBProposer): local head-of-queue asks only. Each round of it:
    1. waits while the acceptor has not reported, or reports it rejoining (_await_rejoin);
    2. defers while a release named another member's turn (_await_turn, D-LIVE-1): until
       that member's request is seen here and its attempt or lease ends, at most leaseDuration
       after its request, or turnSilence when its request is not seen; a member nobody queues
       first broadcasts want. Counted: deferrals, deferral_timeouts;
    3. opens an attempt (PBAttempt) for ballotFor: (the ballot of this node's rank above the
       highest term its acceptor saw, the hint, and the labels of its accepted and committed
       roots), counted attempts (and turns_taken when the release named it). Its own vote is
       decided by its own acceptor (PBToAcceptor with its request, CC1), which answers it in
       the step's vote (PBAcceptorStep vote, handed back in PBAcceptorDecided); a step whose
       promise append failed is handed back in PBAcceptorDiscarded, and the own grant becomes
       the refusal 'promise_failed' (proto_db _promise failing). A learner has no vote (D54).
       request(term, rid, inc, vs) goes to the other voters;
    4. records the replies (proto_db _on_reply): every reply raises the hint (its term and
       highest, its root's label); a reply to another incarnation is dropped and counted
       stale_replies (L12); a reply from a member that is not a voter, or to another attempt,
       is never recorded (D54; PBAttempt counts a peer once). The attempt closes when decided,
       at requestTimeout, or, once a majority answered an undecided attempt, after
       max(minStraggle, straggleFactor x the time those replies took) (R39);
    5. wins when a majority granted and the clock is still before the attempt's validUntil:
       (the send + the belief, L5) and no granter knows a root labelled with this term or later
       (then the hint rises and the round is lost). The lease's root and certainty are the
       attempt's bestRoot:suspect: with the acceptor's accepted root (a voter) and the node's
       suspicion. Counted acquired and ownerships; this node becomes the owner (PBOwnership)
       and its waiters join the ownership's queue;
    6. loses otherwise: counted lost_attempts; its own grant of the term is released (the
       cancel to its own acceptor) and the cancel (release, held false, certain false, more
       true) is broadcast; then the back-off (proto_db _back_off): the jittered delay
       min(backoffHigh, backoffLow x 2^failures) x [1/2, 1), drawn from the hints' generator,
       then up to the refusals' busyRemaining (at most leaseDuration). Progress (a held
       release, a newly learnt owner) ends the whole wait; any other release (a cancel) ends
       only the busy extension; a woken member the release did not name waits a random spread
       of up to wakeSpread. Then the next round.
  Owning (proto_db _own_loop_body, _renew, release). While it owns a term: the lease expiring
    ends it ('expired'); no demand for idleEnd ends it ('idle'); with ownerIdleRelease, no
    local demand for that long ends it ('idle_local', counted terms_released_idle_local).
    Otherwise, while there is demand (a waiter queued, or one within leaseDuration / 2), it
    renews when less than half the belief is left: renew(term, rid, inc, vs) to the other
    voters and its own acceptor, closed as an attempt; a renewal won before its validUntil:
    extends the lease to the later of the two ends (counted renewals), else counted
    renewal_failures, and the term goes on. The ending releases the lease: the release (held
    true) carries the accepted and committed roots, certain (the node is not suspect), next
    (the member seen waiting longest, taken out of the queue, counted turns_named) and more
    (local waiters remain), goes to the other members and frees its own grant; the local
    waiters still queued start a new acquisition. Permissions (rule O1) are issued by
    _issue:now:effects:, owner.st's (Task 12); here it issues none.
  Fairness and owner hints (PBHints, timing only: never a grant or an acceptance). Learnt from
    request, want and release messages (the dispatcher forwards request, renew and release to
    the acceptor lane as acceptor.st does). The owner hint is learnt only from messages proving
    a term was won: a renewal here (a plain request may lose), and this node's own win.

Timing differences from proto_db (no safety rule reads them): the fairness and wake-up part of
a release is taken by the dispatcher when the release arrives (proto_db notes the fairness at
once and counts the wake-up on the acceptor lane); an owner re-evaluates its renewal and ends
on every queued waiter (proto_db's ownership thread sleeps until its timer or a notify).
Acquisition here is proto_db's permit without its first step, the permission of a known owner
(_permission_from_owner, with _await_turn's yield_to_owner and the deadline of
acquireTimeout): owner.st (Task 12) adds them. The committed root a grant carries
(_observe_committed) is acceptance knowledge (Task 13).

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

"=== PBProposerValue: an immutable record of named fields ====================="

Object subclass: #PBProposerValue instanceVariableNames: 'values'.

"The names of the fields of this class's values (Symbols)."
PBProposerValue class >> fieldNames
  ^ self subclassResponsibility.

"A value holding the fields of aDictionary (every name of fieldNames, no other)."
PBProposerValue class >> _from: aDictionary
  ^ self basicNew _setValues: aDictionary.

PBProposerValue >> _setValues: aDictionary
  "Runs once, on a fresh instance."
  values isNil ifFalse: [^ PBUserError signal: self class name , ' is immutable'].
  (aDictionary keys asSet = self class fieldNames asSet) ifFalse: [
    ^ PBValidationError signal: self class name , ': the fields are ' , self class fieldNames printString].
  values := aDictionary copy.
  ^ self.

PBProposerValue >> _at: aName
  ^ values at: aName.

"This value with the fields someAssociations name (name -> value) replaced; another name is
 PBValidationError."
PBProposerValue >> with: someAssociations
  | d |
  d := values copy.
  someAssociations do: [:a |
    (d includesKey: a key) ifFalse: [^ PBValidationError signal: self class name , ' has no field ' , a key printString].
    d at: a key put: a value].
  ^ self class _from: d.

PBProposerValue >> printOn: aStream
  aStream nextPutAll: self class name.

"=== PBHints ================================================================="

"The fairness and owner hints of a node, and its random draws (proto_db _hint, _owner_hint,
 _waiting, _wanting_since, _turn, _my_turn, _registered, _wakeups, _progress, _rng): timing
 only, never a grant or an acceptance."
PBProposerValue subclass: #PBHints.

PBHints class >> fieldNames
  ^ #(#hint #ownerTerm #ownerNode #waiting #wantingSince #turn #myTurn #registered #wakeups #progress #draw).

"No hint yet; the generator seeded with anInteger (an Integer >= 0: the incarnation, which the
 shell draws from its seeded Random)."
PBHints class >> seed: anInteger
  (anInteger isInteger and: [anInteger >= 0]) ifFalse: [
    ^ PBValidationError signal: 'PBHints: a seed is an Integer >= 0, not ' , anInteger printString].
  ^ self _from: (Dictionary new
    at: #hint put: 0; at: #ownerTerm put: 0; at: #ownerNode put: nil; at: #waiting put: #();
    at: #wantingSince put: #(); at: #turn put: nil; at: #myTurn put: false; at: #registered put: false;
    at: #wakeups put: 0; at: #progress put: 0; at: #draw put: anInteger \\ 2147483646 + 1; yourself).

"The highest term this node knows of from replies, releases and roots (proto_db _hint)."
PBHints >> hint
  ^ self _at: #hint.

"The term of the newest owner learnt (0: none) and that owner's id, nil when unknown."
PBHints >> ownerTerm
  ^ self _at: #ownerTerm.

PBHints >> ownerNode
  ^ self _at: #ownerNode.

"{ member. since } of the members queued as wanting the lease (proto_db _waiting), a fresh Array."
PBHints >> waiting
  ^ (self _at: #waiting) copy.

"{ member. since } of the members that wanted the lease since they were last served."
PBHints >> wantingSince
  ^ (self _at: #wantingSince) copy.

"{ member. named. seen } of the turn a release named (seen: when its request was seen, nil
 before), or nil."
PBHints >> turn
  | turn |
  turn := self _at: #turn.
  ^ turn isNil ifTrue: [nil] ifFalse: [turn copy].

"Whether a release named this node's turn."
PBHints >> myTurn
  ^ self _at: #myTurn.

"Whether the other members queue this node (it asked, or said want, since it was last served)."
PBHints >> registered
  ^ self _at: #registered.

"Releases received (any), and progress (held releases): the wake marks of a back-off."
PBHints >> wakeups
  ^ self _at: #wakeups.

PBHints >> progress
  ^ self _at: #progress.

"The state of the generator (Park-Miller, in [1, 2^31 - 2])."
PBHints >> draw
  ^ self _at: #draw.

"{ wakeups. progress. ownerTerm. ownerNode } now (proto_db _wake_marks)."
PBHints >> marks
  ^ { self wakeups. self progress. self ownerTerm. self ownerNode }.

"=== PBProposer =============================================================="

"A running acquisition (proto_db permit's loop around _become_owner): phase (#rejoin, #turn,
 #attempt, #backoff, #busy, #spread), the open attempt (a PBAttempt, or nil), the lost rounds so
 far (failures), the wake marks of the round, the token of its timer and the phase and time it
 ends, when its attempt started
 and whether it waits for stragglers, the ends of the back-off and of its busy extension, and
 whether this round's deferral was counted."
PBProposerValue subclass: #PBProposer.

PBProposer class >> fieldNames
  ^ #(#phase #attempt #failures #marks #token #wakeAt #startedAt #straggling #backoffEnd #busyEnd #waited).

"An acquisition about to run its first round."
PBProposer class >> start
  ^ self _from: (Dictionary new
    at: #phase put: #start; at: #attempt put: nil; at: #failures put: 0; at: #marks put: { 0. 0. 0. nil };
    at: #token put: nil; at: #wakeAt put: nil; at: #startedAt put: 0; at: #straggling put: false; at: #backoffEnd put: 0;
    at: #busyEnd put: 0; at: #waited put: false; yourself).

PBProposer >> phase
  ^ self _at: #phase.

PBProposer >> attempt
  ^ self _at: #attempt.

PBProposer >> failures
  ^ self _at: #failures.

PBProposer >> marks
  ^ (self _at: #marks) copy.

PBProposer >> token
  | token |
  token := self _at: #token.
  ^ token isNil ifTrue: [nil] ifFalse: [token copy].

"{ phase. end } of the timer of token: the phase it ends and when."
PBProposer >> wakeAt
  | at |
  at := self _at: #wakeAt.
  ^ at isNil ifTrue: [nil] ifFalse: [at copy].

PBProposer >> startedAt
  ^ self _at: #startedAt.

PBProposer >> straggling
  ^ self _at: #straggling.

PBProposer >> backoffEnd
  ^ self _at: #backoffEnd.

PBProposer >> busyEnd
  ^ self _at: #busyEnd.

PBProposer >> waited
  ^ self _at: #waited.

PBProposer >> printOn: aStream
  aStream nextPutAll: 'PBProposer('; nextPutAll: self phase; nextPutAll: ', '; print: self attempt; nextPut: $).

"=== PBOwnership ============================================================="

"This node's ownership of a won term (proto_db _Ownership at DEPTH 0): the lease; the FIFO of
 permission requests, each { node. rid. inc. waiter } (waiter: the local waiter of one of this
 node's own commits, nil for a member's permit_req); the last demand and the last local demand;
 the running renewal (a PBAttempt, or nil) with its start and straggling; the token of its timer;
 the last permission number issued (seq), the pipeline of issued permissions not yet retired
 (PBIssued, oldest first: at most one at DEPTH 0), the base (the newest root it knows committed
 in its term, nil when unknown) and whether that base is known committed; and whether the term
 was abandoned (owner.st)."
PBProposerValue subclass: #PBOwnership.

PBOwnership class >> fieldNames
  ^ #(#lease #queue #lastDemand #lastLocal #renewal #renewStarted #straggling #token #seq #pipeline #base #committed
      #abandoned).

"The ownership of aLease from t, with no request queued, aRoot as its base (the lease's phase-1
 value, a PBLabeledRoot or nil: unknown), known committed when isCommitted."
PBOwnership class >> lease: aLease base: aRoot committed: isCommitted now: t
  (aLease isKindOf: PBLease) ifFalse: [
    ^ PBValidationError signal: 'PBOwnership: a lease is a PBLease, not ' , aLease printString].
  ^ self _from: (Dictionary new
    at: #lease put: aLease; at: #queue put: #(); at: #lastDemand put: t; at: #lastLocal put: t;
    at: #renewal put: nil; at: #renewStarted put: 0; at: #straggling put: false; at: #token put: nil;
    at: #seq put: 0; at: #pipeline put: #(); at: #base put: aRoot; at: #committed put: isCommitted;
    at: #abandoned put: false; yourself).

PBOwnership >> lease
  ^ self _at: #lease.

PBOwnership >> term
  ^ self lease term.

"The permission requests not yet issued, { node. rid. inc. waiter or nil } each, a fresh Array."
PBOwnership >> queue
  ^ (self _at: #queue) collect: [:e | e copy].

PBOwnership >> lastDemand
  ^ self _at: #lastDemand.

PBOwnership >> lastLocal
  ^ self _at: #lastLocal.

PBOwnership >> renewal
  ^ self _at: #renewal.

PBOwnership >> renewStarted
  ^ self _at: #renewStarted.

PBOwnership >> straggling
  ^ self _at: #straggling.

PBOwnership >> token
  | token |
  token := self _at: #token.
  ^ token isNil ifTrue: [nil] ifFalse: [token copy].

"The number of the last permission issued in the term, 0 before the first."
PBOwnership >> seq
  ^ self _at: #seq.

"The issued permissions not yet retired (PBIssued), oldest first, a fresh Array."
PBOwnership >> pipeline
  ^ (self _at: #pipeline) copy.

"The newest root the owner knows committed in its term (a PBLabeledRoot), nil when unknown."
PBOwnership >> base
  ^ self _at: #base.

"Whether the base is known committed (a permit on it is then certain)."
PBOwnership >> isCommitted
  ^ self _at: #committed.

PBOwnership >> isAbandoned
  ^ self _at: #abandoned.

"Whether permissions may be issued at t (proto_db serving): not abandoned, the lease valid."
PBOwnership >> isServingAt: t
  ^ self isAbandoned not and: [self lease isValidAt: t].

"The issued permission aSeq of aNode in the pipeline, or nil (proto_db entry)."
PBOwnership >> entryOf: aNode seq: aSeq
  ^ (self _at: #pipeline) detect: [:e | e node = aNode and: [e seq = aSeq]] ifNone: [nil].

PBOwnership >> printOn: aStream
  aStream nextPutAll: 'PBOwnership('; print: self lease; nextPut: $).

"=== PBCoordinatorCore: helpers =============================================="

"The range of a draw: a draw is an Integer in [0, drawRange)."
PBCoordinatorCore class >> drawRange
  ^ 2147483646.

"The cap of microsFromWire: (2^52 us, about 142 years)."
PBCoordinatorCore class >> wireMicrosCap
  ^ 4503599627370496.

"The microseconds of a wire number of seconds (a received reject's remaining), total: a
 non-finite number (the wire accepts +Infinity, a valid float64) or one of wireMicrosCap
 microseconds or more answers wireMicrosCap, which every caller clamps (proto_db: busy =
 min(busy_remaining, D)). It inverts wireSeconds: exactly for every value tested up to 2^51
 microseconds; near 2^52 the product of a float64 can round to one off (4375678581963491)."
PBCoordinatorCore class >> microsFromWire: aSeconds
  | micros |
  aSeconds isFinite ifFalse: [^ self wireMicrosCap].
  micros := aSeconds * 1000000.
  micros >= self wireMicrosCap ifTrue: [^ self wireMicrosCap].
  ^ micros rounded.

PBCoordinatorCore >> _hintsIn: s
  ^ s hints isNil ifTrue: [PBHints seed: s inc] ifFalse: [s hints].

"{ x. hints }: x drawn in [0, drawRange) from aHints' generator, and the hints after the draw."
PBCoordinatorCore >> _draw: aHints
  | next |
  next := aHints draw * 48271 \\ 2147483647.
  ^ { next - 1. aHints with: { #draw -> next } }.

"{ state. token }: a new timer token of aKind (#proposer or #owner) and s with its counter
 advanced: tokens and request ids share nextRid, so neither repeats within an incarnation."
PBCoordinatorCore >> _token: aKind in: s
  ^ { s with: { #nextRid -> (s nextRid + 1) }. { aKind. s nextRid } }.

"The highest suspect term of the node: the dispatcher's and its acceptor's."
PBCoordinatorCore >> _suspectIn: s
  ^ s acceptorView isNil ifTrue: [s suspectTerm] ifFalse: [s suspectTerm max: s acceptorView suspectTerm].

PBCoordinatorCore >> _others: s
  ^ s config membership ids reject: [:id | id = s config nodeId].

"aMessage to every other member (proto_db _broadcast)."
PBCoordinatorCore >> _broadcast: aMessage in: s effects: fx
  (self _others: s) do: [:id | fx add: (PBSend to: id message: aMessage)].

"aMessage to every other voter (proto_db _send_voters: only votes count, D54)."
PBCoordinatorCore >> _sendVoters: aMessage in: s effects: fx
  (s config membership voters reject: [:id | id = s config nodeId]) do: [:id | fx add: (PBSend to: id message: aMessage)].

"The release (held) or cancel (not held) of aTerm (proto_db release and _close_attempt), with the
 accepted and committed roots the acceptor last reported."
PBCoordinatorCore >> _release: aTerm in: s held: isHeld certain: isCertain next: aNext more: isMore
  | view |
  view := s acceptorView.
  ^ PBClusterMessage type: 'release' from: s config nodeId fields: {
    'term' -> aTerm. 'inc' -> s inc.
    'root' -> (view isNil ifTrue: [nil] ifFalse: [PBClusterMessage rootValue: view accepted]).
    'committed' -> (view isNil ifTrue: [nil] ifFalse: [PBClusterMessage rootValue: view committed]).
    'certain' -> isCertain. 'held' -> isHeld. 'next' -> aNext. 'more' -> isMore }.

"The step of a rule: aBlock answers the new state, adding the effects to the collection it takes."
PBCoordinatorCore >> _step: aBlock
  | fx state |
  fx := OrderedCollection new.
  state := aBlock value: fx.
  ^ PBStep state: state effects: fx asArray.

"=== PBCoordinatorCore: the ballot ==========================================="

"The ballot of the next attempt of the node of aNodeState (CP 1.5 step 2, coordinator.py
 _open_attempt): the smallest term of its rank above the highest term its acceptor saw, the
 hint, and the labels of its accepted and committed roots (the acceptor's last report, CC2:
 a hint, which the acceptors' rules check)."
PBCoordinatorCore >> ballotFor: aNodeState
  | view floor |
  view := aNodeState acceptorView.
  floor := (self _hintsIn: aNodeState) hint.
  view notNil ifTrue: [
    floor := floor max: view grants highestSeen.
    view accepted notNil ifTrue: [floor := floor max: view accepted label].
    view committed notNil ifTrue: [floor := floor max: view committed label]].
  ^ PBMembership ballotAfter: floor rank: aNodeState config rank.

"The end of a lease won by anAttempt, on this node's clock: its send + the belief (L5,
 PBAttempt validUntil:), never its win."
PBCoordinatorCore >> _leaseEnd: anAttempt in: s now: t
  ^ anAttempt validUntil: s config.

"=== PBCoordinatorCore: the local demand ====================================="

"A local commit wants a permission (proto_db permit, then _permission_from_owner): its deadline
 is acquireTimeout from now; it is queued at this node's ownership while that one serves, else
 it asks the owner the hint names (owner.st _ask:), else it joins the waiters, the first of
 which starts an acquisition."
PBCoordinatorCore >> dispatchPermitWanted: anEvent in: s now: t
  ^ self _step: [:fx | | own state |
    state := self _expect: anEvent waiter in: s now: t.
    own := state ownership.
    (own notNil and: [own isServingAt: t])
      ifTrue: [self _ownLoop: (self _issue: (self _queueLocal: { anEvent waiter } in: state now: t) now: t effects: fx)
        now: t effects: fx]
      ifFalse: [
        (self _ownerToAsk: state) notNil
          ifTrue: [self _ask: anEvent waiter in: state now: t effects: fx]
          ifFalse: [self _wantLease: (state with: { #waiters -> (state waiters copyWith: anEvent waiter) }) now: t effects: fx]]].

"Starts an acquisition when waiters wait, no term is owned and none runs."
PBCoordinatorCore >> _wantLease: s now: t effects: fx
  (s proposer notNil or: [s ownership notNil or: [s waiters isEmpty]]) ifTrue: [^ s].
  ^ self _round: (s with: { #proposer -> PBProposer start }) now: t effects: fx.

"=== PBCoordinatorCore: one round of the acquisition ========================="

"proto_db permit's loop: not while the acceptor rejoins (_await_rejoin; nor before it reported),
 then the permission of the owner the hint names (_permission_from_owner: the waiters ask it,
 owner.st, and the acquisition ends), then the turn (the wake marks taken first, as permit
 takes them before _become_owner)."
PBCoordinatorCore >> _round: s now: t effects: fx
  | p view |
  p := s proposer.
  view := s acceptorView.
  (view isNil or: [view isRejoined not]) ifTrue: [^ self _awaitRejoin: s now: t effects: fx].
  (self _ownerToAsk: s) notNil ifTrue: [^ self _askAll: (s with: { #proposer -> nil }) now: t effects: fx].
  ^ self _awaitTurn: (s with: { #proposer -> (p with: { #marks -> (self _hintsIn: s) marks. #waited -> false }) })
    now: t effects: fx.

"proto_db _await_rejoin: the waiters wait while the acceptor rejoins (nor before it reported); one
 whose deadline passed meanwhile ends in PBTimeoutError. Woken by the acceptor's report, or by a
 timer at the earliest deadline."
PBCoordinatorCore >> _awaitRejoin: s now: t effects: fx
  | state deadline p |
  state := self _expire: s because: 'its acceptor log was empty' now: t effects: fx.
  state waiters isEmpty ifTrue: [^ state with: { #proposer -> nil }].
  p := state proposer with: { #phase -> #rejoin }.
  deadline := self _deadlineIn: state.
  deadline isNil ifTrue: [^ state with: { #proposer -> (p with: { #token -> nil. #wakeAt -> nil }) }].
  ^ self _sleep: (state with: { #proposer -> p }) until: deadline now: t effects: fx.

"proto_db _await_turn with yield_to_owner (a permission request): defer while a release named
 another member's turn; once another member is known to own a term, stop deferring and back off
 (proto_db _become_owner answers (False, 0)), so that the next round asks that owner; at the
 earliest waiter's deadline, attempt (the attempt that follows reports the timeout)."
PBCoordinatorCore >> _awaitTurn: s now: t effects: fx
  | h p turn end deadline |
  (self _ownerToAsk: s) notNil ifTrue: [^ self _retry: s busy: 0 now: t effects: fx].
  h := self _hintsIn: s.
  p := s proposer.
  turn := h turn.
  turn isNil ifTrue: [^ self _openAttempt: s now: t effects: fx].
  end := (turn at: 3) notNil
    ifTrue: [(turn at: 3) + s config leaseDuration]
    ifFalse: [(turn at: 2) + s config turnSilence].
  t >= end ifTrue: [
    fx add: (PBCount stat: 'deferral_timeouts').
    ^ self _openAttempt: (s with: { #hints -> (h with: { #turn -> nil }) }) now: t effects: fx].
  deadline := self _deadlineIn: s.
  (deadline notNil and: [t >= deadline]) ifTrue: [^ self _openAttempt: s now: t effects: fx].
  deadline notNil ifTrue: [end := end min: deadline].
  p waited ifFalse: [
    fx add: (PBCount stat: 'deferrals').
    p := p with: { #waited -> true }].
  h registered ifFalse: [
    "Nobody queues this node: it says so before deferring, or no release would ever name it."
    h := h with: { #registered -> true }.
    self _broadcast: (PBClusterMessage type: 'want' from: s config nodeId fields: #()) in: s effects: fx].
  ^ self _sleep: (s with: { #hints -> h. #proposer -> (p with: { #phase -> #turn }) }) until: end now: t effects: fx.

"proto_db _open_attempt: the ballot, the own vote through this node's acceptor (CC1), the
 request to the other voters."
PBCoordinatorCore >> _openAttempt: s now: t effects: fx
  | h config term rid request |
  config := s config.
  h := self _hintsIn: s.
  term := self ballotFor: s.
  rid := s nextRid.
  fx add: (PBCount stat: 'attempts').
  h myTurn ifTrue: [
    fx add: (PBCount stat: 'turns_taken').
    h := h with: { #myTurn -> false }].
  "Every member that receives the request queues this node."
  h := h with: { #registered -> true }.
  request := PBClusterMessage type: 'request' from: config nodeId fields: {
    'term' -> term. 'rid' -> rid. 'inc' -> s inc. 'vs' -> config membership fingerprint }.
  (config membership isVoter: config nodeId) ifTrue: [fx add: (PBToAcceptor event: (PBReceived message: request))].
  self _sendVoters: request in: s effects: fx.
  ^ self _awaitReplies: (s with: { #hints -> h. #nextRid -> (rid + 1) })
    attempt: (PBAttempt term: term rid: rid sentAt: t voters: config membership voters size) now: t effects: fx.

"The attempt waits for its replies until requestTimeout (proto_db _close_attempt)."
PBCoordinatorCore >> _awaitReplies: s attempt: anAttempt now: t effects: fx
  ^ self _sleep: (s with: { #proposer -> (s proposer with: { #phase -> #attempt. #attempt -> anAttempt.
      #startedAt -> t. #straggling -> false }) }) until: t + s config requestTimeout now: t effects: fx.

"How long the replies of an attempt started at aStart are awaited once a majority answered
 (R39), within its request timeout."
PBCoordinatorCore >> _straggleFrom: aStart in: s now: t
  ^ 0 max: ((s config minStraggle max: s config straggleFactor * (t - aStart)) min: aStart + s config requestTimeout - t).

"The open attempt took a reply: it closes when decided; a majority of replies to an undecided
 one starts the wait for the stragglers."
PBCoordinatorCore >> _attemptAnswered: s now: t effects: fx
  | p |
  p := s proposer.
  p attempt state = #pending ifFalse: [^ self _closeAttempt: s now: t effects: fx].
  (p attempt replies >= p attempt needed and: [p straggling not]) ifFalse: [^ s].
  ^ self _sleep: (s with: { #proposer -> (p with: { #straggling -> true }) })
    until: t + (self _straggleFrom: p startedAt in: s now: t) now: t effects: fx.

"Whether t is still before anAttempt's validUntil: (L5): a majority granted after the belief
 from the send (a late timer, a slow dispatcher) is not a win, of an attempt or a renewal."
PBCoordinatorCore >> _inTime: anAttempt in: s now: t
  ^ t < (self _leaseEnd: anAttempt in: s now: t).

"Whether anAttempt is won (a majority of the voters granted)."
PBCoordinatorCore >> _won: anAttempt
  ^ anAttempt state = #won.

"proto_db _close_attempt: a win before the attempt's validUntil: with no granter's root labelled
 at or above its term owns the term; anything else is a lost round."
PBCoordinatorCore >> _closeAttempt: s now: t effects: fx
  | a h view own pair label state |
  a := s proposer attempt.
  h := self _hintsIn: s.
  h := h with: { #hint -> (h hint max: a highestSeen) }.
  state := s with: { #hints -> h }.
  ((self _won: a) and: [self _inTime: a in: s now: t]) ifTrue: [
    view := s acceptorView.
    own := ((s config membership isVoter: s config nodeId) and: [view notNil]) ifTrue: [view accepted] ifFalse: [nil].
    pair := a bestRoot: own suspect: (self _suspectIn: s) > 0.
    label := pair first isNil ifTrue: [0] ifFalse: [pair first label].
    label < a term ifTrue: [^ self _own: a root: pair first certain: pair last in: state now: t effects: fx].
    "A granter knows a root labelled with this term or later (a cluster that reused low terms):
     a root of this lease would not order after it. The next round asks higher."
    state := state with: { #hints -> (h with: { #hint -> (h hint max: label) }) }].
  ^ self _lose: state now: t effects: fx.

"The won attempt makes this node the owner of its term (proto_db _become_owner): the base is
 the lease's root, known committed when the lease is certain and this node knows that very root
 committed; its waiters are queued (proto_db's threads loop back to _permission_from_owner)."
PBCoordinatorCore >> _own: anAttempt root: aRoot certain: isCertain in: s now: t effects: fx
  | lease view committed state |
  lease := PBLease term: anAttempt term validUntil: (self _leaseEnd: anAttempt in: s now: t) root: aRoot certain: isCertain.
  view := s acceptorView.
  committed := isCertain and: [aRoot notNil and: [view notNil and: [view committed notNil and: [view committed key = aRoot key]]]].
  fx add: (PBCount stat: 'acquired'); add: (PBCount stat: 'ownerships').
  state := s with: { #proposer -> nil. #waiters -> #().
    #ownership -> (PBOwnership lease: lease base: aRoot committed: committed now: t).
    #hints -> ((self _hintsIn: s) with: { #ownerTerm -> anAttempt term. #ownerNode -> s config nodeId }) }.
  state := self _queueLocal: s waiters in: state now: t.
  ^ self _ownLoop: (self _issue: state now: t effects: fx) now: t effects: fx.

"A lost round: the cancel of its term, then the back-off (proto_db _close_attempt, _back_off)."
PBCoordinatorCore >> _lose: s now: t effects: fx
  | a cancel |
  a := s proposer attempt.
  fx add: (PBCount stat: 'lost_attempts').
  cancel := self _release: a term in: s held: false certain: false next: nil more: true.
  "Its own grant of the term ends (proto_db PeerGrants.on_release of its own vote)."
  fx add: (PBToAcceptor event: (PBReceived message: cancel)).
  self _broadcast: cancel in: s effects: fx.
  ^ self _retry: s busy: (a busyRemaining min: s config leaseDuration) now: t effects: fx.

"After a lost round, or a deferral that yielded to a known owner (proto_db permit): every waiter
 whose deadline passed ends in PBTimeoutError; the rest back off, or the acquisition ends when
 none is left."
PBCoordinatorCore >> _retry: s busy: someMicros now: t effects: fx
  | state |
  state := self _expire: s because: 'no majority granted it' now: t effects: fx.
  state waiters isEmpty ifTrue: [^ state with: { #proposer -> nil }].
  ^ self _backOff: state busy: someMicros now: t effects: fx.

"proto_db _back_off: the jittered exponential delay, extended to the refusals' busy remaining,
 never past the earliest waiter's deadline (remaining)."
PBCoordinatorCore >> _backOff: s busy: someMicros now: t effects: fx
  | p pair base delay busy deadline |
  p := s proposer.
  pair := self _draw: (self _hintsIn: s).
  base := s config backoffHigh min: s config backoffLow * (2 raisedTo: (p failures min: 30)).
  delay := base * (self class drawRange + pair first) // (2 * self class drawRange).
  busy := delay max: someMicros.
  deadline := self _deadlineIn: s.
  deadline notNil ifTrue: [
    delay := delay min: (0 max: deadline - t).
    busy := busy min: (0 max: deadline - t)].
  ^ self _backingOff: (s with: { #hints -> pair last. #proposer -> (p with: { #phase -> #backoff. #attempt -> nil.
      #backoffEnd -> (t + delay). #busyEnd -> (t + busy) }) }) now: t effects: fx.

"Whether what arrived since the marks ends the back-off itself: progress (a held release, a
 newly learnt owner), never a cancel (N7, M2)."
PBCoordinatorCore >> _endsBackOff: aHints since: someMarks
  ^ aHints progress ~= (someMarks at: 2) or: [aHints ownerTerm ~= (someMarks at: 3) or: [aHints ownerNode ~= (someMarks at: 4)]].

"The back-off waits: progress ends it all, any release ends the busy extension."
PBCoordinatorCore >> _backingOff: s now: t effects: fx
  | p h progressed woken |
  p := s proposer.
  h := self _hintsIn: s.
  progressed := self _endsBackOff: h since: p marks.
  p phase = #backoff ifTrue: [
    (progressed not and: [t < p backoffEnd]) ifTrue: [^ self _sleep: s until: p backoffEnd now: t effects: fx].
    progressed ifFalse: [p := p with: { #phase -> #busy }]].
  woken := progressed or: [h wakeups ~= (p marks at: 1)].
  (p phase = #busy and: [woken not and: [t < p busyEnd]]) ifTrue: [
    ^ self _sleep: (s with: { #proposer -> p }) until: p busyEnd now: t effects: fx].
  ^ self _wake: (s with: { #proposer -> p }) woken: woken now: t effects: fx.

"The proposer sleeps in its phase until anEnd: a timer of its own, unless the current one
 already ends that phase then."
PBCoordinatorCore >> _sleep: s until: anEnd now: t effects: fx
  | p pair state |
  p := s proposer.
  (p token notNil and: [p wakeAt = { p phase. anEnd }]) ifTrue: [^ s].
  pair := self _token: #proposer in: s.
  state := pair first.
  fx add: (PBTimer after: (0 max: anEnd - t) token: pair last event: #proposer).
  ^ state with: { #proposer -> (p with: { #token -> pair last. #wakeAt -> { p phase. anEnd } }) }.

"The back-off ended: a woken member that the release did not name adds a random spread of up to
 wakeSpread, then the next round."
PBCoordinatorCore >> _wake: s woken: isWoken now: t effects: fx
  | p pair state |
  p := s proposer with: { #failures -> (s proposer failures + 1) }.
  state := s with: { #proposer -> p }.
  (isWoken and: [(self _hintsIn: s) myTurn not]) ifFalse: [^ self _round: state now: t effects: fx].
  pair := self _draw: (self _hintsIn: s).
  state := state with: { #hints -> pair last. #proposer -> (p with: { #phase -> #spread }) }.
  ^ self _sleep: state until: t + (pair first * s config wakeSpread // self class drawRange) now: t effects: fx.

"Every event that would notify proto_db's condition re-evaluates a waiting acquisition."
PBCoordinatorCore >> _poke: s now: t effects: fx
  | p |
  p := s proposer.
  p isNil ifTrue: [^ s].
  p phase = #rejoin ifTrue: [^ self _round: s now: t effects: fx].
  p phase = #turn ifTrue: [^ self _awaitTurn: s now: t effects: fx].
  (p phase = #backoff or: [p phase = #busy]) ifTrue: [^ self _backingOff: s now: t effects: fx].
  ^ s.

"=== PBCoordinatorCore: replies =============================================="

"Whether the reply aMessage answers another incarnation of this node (L12)."
PBCoordinatorCore >> _isStale: aMessage in: s
  ^ (aMessage at: 'inc') ~= s inc.

"proto_db _on_reply: a grant or reject from aMessage's sender (this node itself for its own
 vote)."
PBCoordinatorCore >> _onReply: aMessage in: s now: t effects: fx
  | h root state |
  h := self _hintsIn: s.
  h := h with: { #hint -> (h hint max: (aMessage at: 'term')) }.
  aMessage type = 'reject' ifTrue: [h := h with: { #hint -> (h hint max: (aMessage at: 'highest')) }].
  (self _isStale: aMessage in: s) ifTrue: [
    "A reply to a previous incarnation of this node, whose request ids restarted at 1."
    fx add: (PBCount stat: 'stale_replies').
    ^ s with: { #hints -> h }].
  root := PBClusterMessage rootFrom: (aMessage at: 'root').
  root notNil ifTrue: [h := h with: { #hint -> (h hint max: root label) }].
  state := s with: { #hints -> h }.
  "A learner's reply is never a vote (D54): PBAttempt does not filter, as LeaseAttempt."
  (s config membership isVoter: aMessage from) ifFalse: [^ state].
  ^ self _record: aMessage root: root in: state now: t effects: fx.

"Whether aMessage answers anAttempt (its rid and term)."
PBCoordinatorCore >> _reply: aMessage answers: anAttempt
  ^ anAttempt notNil and: [anAttempt rid = (aMessage at: 'rid') and: [anAttempt term = (aMessage at: 'term')]].

"anAttempt with the grant or reject aMessage (its root aRoot)."
PBCoordinatorCore >> _attempt: anAttempt with: aMessage root: aRoot
  aMessage type = 'grant' ifTrue: [
    ^ anAttempt withGrant: aMessage from root: aRoot committed: (PBClusterMessage rootFrom: (aMessage at: 'committed'))
      certain: (aMessage at: 'certain')].
  ^ anAttempt withReject: aMessage from reason: (aMessage at: 'reason') highest: (aMessage at: 'highest')
    remaining: (self class microsFromWire: (aMessage at: 'remaining')).

"The voter's reply recorded in the attempt it answers: the acquisition's, or the renewal's."
PBCoordinatorCore >> _record: aMessage root: aRoot in: s now: t effects: fx
  | p own |
  p := s proposer.
  (p notNil and: [p phase = #attempt and: [self _reply: aMessage answers: p attempt]]) ifTrue: [
    ^ self _attemptAnswered: (s with: { #proposer -> (p with: { #attempt -> (self _attempt: p attempt with: aMessage root: aRoot) }) })
      now: t effects: fx].
  own := s ownership.
  (own notNil and: [self _reply: aMessage answers: own renewal]) ifTrue: [
    ^ self _renewalAnswered: (s with: { #ownership -> (own with: { #renewal -> (self _attempt: own renewal with: aMessage root: aRoot) }) })
      now: t effects: fx].
  ^ s.

PBCoordinatorCore >> receivedGrant: anEvent in: s now: t
  ^ self _step: [:fx | self _onReply: anEvent message in: s now: t effects: fx].

PBCoordinatorCore >> receivedReject: anEvent in: s now: t
  ^ self _step: [:fx | self _onReply: anEvent message in: s now: t effects: fx].

"The acceptor's step is durable: its state is the dispatcher's view (CC2) and its vote, if any,
 is this node's own reply."
PBCoordinatorCore >> dispatchAcceptorDecided: anEvent in: s now: t
  ^ self _step: [:fx | | state |
    state := s with: { #acceptorView -> anEvent step state }.
    anEvent step vote notNil ifTrue: [state := self _onReply: anEvent step vote in: state now: t effects: fx].
    self _poke: state now: t effects: fx].

"The acceptor could not make the promise of this node's own grant durable (proto_db _promise
 failing): the own vote is the refusal 'promise_failed' (highest the term, remaining 0)."
PBCoordinatorCore >> dispatchAcceptorDiscarded: anEvent in: s now: t
  ^ self _step: [:fx | | vote |
    vote := anEvent step vote.
    (vote notNil and: [vote type = 'grant'])
      ifTrue: [self _onReply: (PBClusterMessage type: 'reject' from: vote from fields: {
          'term' -> (vote at: 'term'). 'rid' -> (vote at: 'rid'). 'inc' -> (vote at: 'inc'). 'root' -> nil.
          'certain' -> false. 'reason' -> 'promise_failed'. 'highest' -> (vote at: 'term'). 'remaining' -> 0 })
        in: s now: t effects: fx]
      ifFalse: [s]].

"=== PBCoordinatorCore: owning ==============================================="

"proto_db _own_loop_body at DEPTH 0: a permission past its deadline abandons the term (O6); an
 abandoned term ends; the lease expiring ends the term, abandoning it first when a permission is
 out (O6); the term ends idle only with an empty pipeline (O8); else it renews, or sleeps until
 the next of its deadlines. Nothing while a renewal runs."
PBCoordinatorCore >> _ownLoop: s now: t effects: fx
  | own c lease idle release remaining demand waits pair state late queued |
  own := s ownership.
  (own isNil or: [own renewal notNil]) ifTrue: [^ s].
  c := s config.
  state := self _expireQueued: s now: t effects: fx.
  own := state ownership.
  late := own pipeline detect: [:e | t > e deadline] ifNone: [nil].
  late notNil ifTrue: [
    state := self _abandon: state why: 'permission ' , late seq printString , ' of ' , late node , ' timed out' now: t effects: fx.
    own := state ownership].
  own isAbandoned ifTrue: [^ self _endOwnership: state now: t effects: fx].
  lease := own lease.
  idle := c idleEnd.
  release := c ownerIdleRelease.
  (lease isValidAt: t) ifFalse: [
    own pipeline isEmpty ifFalse: [
      "The lease ended with a permission whose outcome this owner does not know yet: abandoned,
       so the release is uncertain (proto_db review I3)."
      state := self _abandon: state why: 'lease expired with permission ' , own pipeline first seq printString , ' of '
        , own pipeline first node , ' outstanding' now: t effects: fx].
    ^ self _endOwnership: state now: t effects: fx].
  (own pipeline isEmpty and: [own queue isEmpty and: [t - own lastDemand > idle]]) ifTrue: [
    ^ self _endOwnership: state now: t effects: fx].
  (own pipeline isEmpty and: [release notNil and: [t - own lastLocal > release]]) ifTrue: [
    "Serving only other members (R80): one of them takes the term. _issue: issues nothing new
     past the threshold, so the outstanding permission drains first."
    fx add: (PBCount stat: 'terms_released_idle_local').
    ^ self _endOwnership: state now: t effects: fx].
  remaining := lease remainingAt: t.
  demand := own pipeline notEmpty or: [own queue notEmpty or: [2 * (t - own lastDemand) <= c leaseDuration]].
  "Renewed when half of the belief is left (R78b)."
  (demand and: [2 * remaining < c belief]) ifTrue: [^ self _renew: state now: t effects: fx].
  waits := OrderedCollection new.
  waits add: (demand ifTrue: [1000 max: (2 * remaining - c belief + 1) // 2] ifFalse: [idle]).
  own pipeline notEmpty
    ifTrue: [waits add: (1000 max: (own pipeline inject: own pipeline first deadline into: [:m :e | m min: e deadline]) - t)]
    ifFalse: [own queue isEmpty ifTrue: [waits add: (1000 max: idle - (t - own lastDemand))]].
  (release notNil and: [own pipeline isEmpty]) ifTrue: [waits add: (1000 max: release - (t - own lastLocal))].
  queued := self _queuedDeadlineIn: state.
  queued notNil ifTrue: [waits add: queued - t].
  pair := self _token: #owner in: state.
  state := pair first.
  fx add: (PBTimer after: (waits inject: waits first into: [:m :w | m min: w]) token: pair last event: #owner).
  ^ state with: { #ownership -> (state ownership with: { #token -> pair last }) }.

"proto_db _renew: the same term asked again of every voter, its own vote included."
PBCoordinatorCore >> _renew: s now: t effects: fx
  | own c rid renew pair state |
  own := s ownership.
  c := s config.
  rid := s nextRid.
  renew := PBClusterMessage type: 'renew' from: c nodeId fields: {
    'term' -> own term. 'rid' -> rid. 'inc' -> s inc. 'vs' -> c membership fingerprint }.
  (c membership isVoter: c nodeId) ifTrue: [fx add: (PBToAcceptor event: (PBReceived message: renew))].
  self _sendVoters: renew in: s effects: fx.
  pair := self _token: #owner in: (s with: { #nextRid -> (rid + 1) }).
  state := pair first.
  fx add: (PBTimer after: c requestTimeout token: pair last event: #owner).
  ^ state with: { #ownership -> (own with: {
    #renewal -> (PBAttempt term: own term rid: rid sentAt: t voters: c membership voters size).
    #renewStarted -> t. #straggling -> false. #token -> pair last }) }.

"The renewal took a reply: as an attempt's (_attemptAnswered:)."
PBCoordinatorCore >> _renewalAnswered: s now: t effects: fx
  | own pair state |
  own := s ownership.
  own renewal state = #pending ifFalse: [^ self _closeRenewal: s now: t effects: fx].
  (own renewal replies >= own renewal needed and: [own straggling not]) ifFalse: [^ s].
  pair := self _token: #owner in: s.
  state := pair first.
  fx add: (PBTimer after: (self _straggleFrom: own renewStarted in: s now: t) token: pair last event: #owner).
  ^ state with: { #ownership -> (state ownership with: { #straggling -> true. #token -> pair last }) }.

"A renewal won before its validUntil: extends the lease; any other outcome leaves it. Then the
 ownership goes on (proto_db _renew, then the loop). The waiters that arrived while the lease
 had lapsed join the queue of the renewed lease (proto_db permit loops back to the owner)."
PBCoordinatorCore >> _closeRenewal: s now: t effects: fx
  | own a lease state |
  own := s ownership.
  a := own renewal.
  lease := own lease.
  ((self _won: a) and: [self _inTime: a in: s now: t])
    ifTrue: [
      fx add: (PBCount stat: 'renewals').
      own := own with: { #renewal -> nil.
        #lease -> (PBLease term: lease term validUntil: (lease validUntil max: (self _leaseEnd: a in: s now: t))
          root: lease root certain: lease isCertain) }.
      state := self _queueLocal: s waiters in: (s with: { #ownership -> own. #waiters -> #() }) now: t.
      state := self _issue: state now: t effects: fx]
    ifFalse: [
      fx add: (PBCount stat: 'renewal_failures').
      state := s with: { #ownership -> (own with: { #renewal -> nil }) }].
  ^ self _ownLoop: state now: t effects: fx.

"The ownership ends (proto_db _refuse_queue with 'ending'): the members queued are refused, its
 queued local waiters wait again (they see the ownership end), the lease is released, and they
 start a new acquisition."
PBCoordinatorCore >> _endOwnership: s now: t effects: fx
  | own state locals |
  own := s ownership.
  locals := self _refuse: own queue reason: 'ending' term: own term in: s effects: fx.
  state := s with: { #ownership -> nil. #waiters -> (locals , s waiters) }.
  state := self _releaseLease: own lease in: state now: t effects: fx.
  ^ self _wantLease: state now: t effects: fx.

"proto_db release: the member seen waiting longest gets the turn and this node defers to it
 like every other member; the release closes the term everywhere, its own grant included."
PBCoordinatorCore >> _releaseLease: aLease in: s now: t effects: fx
  | h more pair successor release |
  h := self _hintsIn: s.
  "proto_db _acquirers > 0: a thread of this node still in permit."
  more := s waiters notEmpty or: [s holder notNil and: [s holder asks notEmpty]].
  pair := self _nextTurn: h.
  successor := pair first.
  h := pair last with: { #registered -> more. #myTurn -> false.
    #turn -> (successor isNil ifTrue: [nil] ifFalse: [{ successor. t. nil }]) }.
  successor notNil ifTrue: [fx add: (PBCount stat: 'turns_named')].
  release := self _release: aLease term in: s held: true certain: (self _suspectIn: s) = 0 next: successor more: more.
  fx add: (PBToAcceptor event: (PBReceived message: release)).
  self _broadcast: release in: s effects: fx.
  ^ s with: { #hints -> h }.

"=== PBCoordinatorCore: fairness and owner hints ============================="

"{ member. hints }: the member seen waiting longest (by the time it first wanted, then its id),
 taken out of the queue of aHints (proto_db _next_turn), or nil."
PBCoordinatorCore >> _nextTurn: aHints
  | best |
  best := aHints waiting inject: nil into: [:b :e |
    (b isNil or: [(e at: 2) < (b at: 2) or: [(e at: 2) = (b at: 2) and: [(e at: 1) < (b at: 1)]]]) ifTrue: [e] ifFalse: [b]].
  best isNil ifTrue: [^ { nil. aHints }].
  ^ { best first. aHints with: { #waiting -> (aHints waiting reject: [:e | e first = best first]) } }.

"aHints with aMember queued as wanting the lease at the place it first wanted it since it was
 last served (proto_db _note_wanting); this node and non-members are ignored."
PBCoordinatorCore >> _noteWanting: aMember in: aHints of: s now: t
  | since wanting waiting |
  (aMember = s config nodeId or: [(s config membership ids includes: aMember) not]) ifTrue: [^ aHints].
  wanting := aHints wantingSince.
  (wanting anySatisfy: [:e | e first = aMember]) ifFalse: [wanting := wanting copyWith: { aMember. t }].
  since := (wanting detect: [:e | e first = aMember]) last.
  waiting := aHints waiting.
  (waiting anySatisfy: [:e | e first = aMember]) ifFalse: [waiting := waiting copyWith: { aMember. since }].
  ^ aHints with: { #wantingSince -> wanting. #waiting -> waiting }.

"proto_db _note_owner: a message of the lease term aTerm proves it was won."
PBCoordinatorCore >> _noteOwner: aTerm in: aHints of: s
  | rank ids |
  aTerm > aHints ownerTerm ifFalse: [^ aHints].
  rank := aTerm \\ PBMembership maxMembers.
  ids := s config membership ids.
  ^ aHints with: { #ownerTerm -> aTerm. #ownerNode -> (rank < ids size ifTrue: [ids at: rank + 1] ifFalse: [nil]) }.

"proto_db _note_request, then the acceptor lane: a request of aMember means it wants the
 lease, and if this node defers to it, its turn is being taken."
PBCoordinatorCore >> receivedRequest: anEvent in: s now: t
  ^ self _step: [:fx | | m h turn |
    m := anEvent message.
    h := self _noteWanting: m from in: (self _hintsIn: s) of: s now: t.
    turn := h turn.
    (turn notNil and: [turn first = m from and: [(turn at: 3) isNil]]) ifTrue: [
      h := h with: { #turn -> { m from. turn at: 2. t } }].
    fx add: (PBToAcceptor event: anEvent).
    self _poke: (s with: { #hints -> h }) now: t effects: fx].

"Only a renewal proves its term was won (proto_db _on_request with renew): the owner hint, then
 the acceptor lane."
PBCoordinatorCore >> receivedRenew: anEvent in: s now: t
  ^ self _step: [:fx |
    fx add: (PBToAcceptor event: anEvent).
    self _poke: (s with: { #hints -> (self _noteOwner: (anEvent message at: 'term') in: (self _hintsIn: s) of: s) })
      now: t effects: fx].

"proto_db _note_release at once, the wake-up of _on_release, then the acceptor lane (the grant
 it ends): a release or a cancel of the sender."
PBCoordinatorCore >> receivedRelease: anEvent in: s now: t
  ^ self _step: [:fx | | m from h root successor ids |
    m := anEvent message.
    from := m from.
    ids := s config membership ids.
    h := self _hintsIn: s.
    (m at: 'held')
      ifTrue: [
        "Served."
        h := h with: { #waiting -> (h waiting reject: [:e | e first = from]).
          #wantingSince -> (h wantingSince reject: [:e | e first = from]) }.
        (m at: 'more') ifTrue: [h := self _noteWanting: from in: h of: s now: t]]
      ifFalse: [
        "A lost attempt still wants the lease."
        h := self _noteWanting: from in: h of: s now: t].
    (h turn notNil and: [h turn first = from]) ifTrue: [h := h with: { #turn -> nil }].
    (m at: 'held') ifTrue: [
      successor := m at: 'next'.
      (successor notNil and: [(ids includes: successor) not]) ifTrue: [successor := nil].
      "Its turn is named (its place is kept)."
      successor notNil ifTrue: [h := h with: { #waiting -> (h waiting reject: [:e | e first = successor]) }].
      successor = s config nodeId
        ifTrue: [
          "This node's turn: the others took it out of their queues."
          h := h with: { #turn -> nil. #myTurn -> true. #registered -> false }]
        ifFalse: [h := h with: { #turn -> (successor isNil ifTrue: [nil] ifFalse: [{ successor. t. nil }]) }]].
    "The sender's accepted root is a hint."
    root := PBClusterMessage rootFrom: (m at: 'root').
    root notNil ifTrue: [h := h with: { #hint -> (h hint max: root label) }].
    "Any release may free the peer that refused this node: a cancel ends only the busy extension
     of its back-off, a holder's release ends it all."
    h := h with: { #wakeups -> (h wakeups + 1).
      #progress -> ((m at: 'held') ifTrue: [h progress + 1] ifFalse: [h progress]) }.
    fx add: (PBToAcceptor event: anEvent).
    self _poke: (s with: { #hints -> h }) now: t effects: fx].

"proto_db _route's want: the sender is queued as wanting the lease."
PBCoordinatorCore >> receivedWant: anEvent in: s now: t
  ^ PBStep state: (s with: { #hints -> (self _noteWanting: anEvent message from in: (self _hintsIn: s) of: s now: t) })
    effects: #().

"=== PBCoordinatorCore: timers ==============================================="

"A timer of the proposer (#proposer) or of the ownership (#owner); one whose token is no longer
 the current one is ignored."
PBCoordinatorCore >> dispatchTimerFired: anEvent in: s now: t
  ^ self _step: [:fx | | p own |
    p := s proposer.
    own := s ownership.
    (anEvent event = #proposer and: [p notNil and: [p token = anEvent token]])
      ifTrue: [
        p phase = #turn ifTrue: [self _awaitTurn: s now: t effects: fx] ifFalse: [
        p phase = #attempt ifTrue: [self _closeAttempt: s now: t effects: fx] ifFalse: [
        (p phase = #backoff or: [p phase = #busy]) ifTrue: [self _backingOff: s now: t effects: fx] ifFalse: [
        (p phase = #spread or: [p phase = #rejoin]) ifTrue: [self _round: s now: t effects: fx] ifFalse: [s]]]]]
      ifFalse: [
        (anEvent event = #owner and: [own notNil and: [own token = anEvent token]])
          ifTrue: [own renewal notNil ifTrue: [self _closeRenewal: s now: t effects: fx] ifFalse: [self _ownLoop: s now: t effects: fx]]
          ifFalse: [
            anEvent event = #ask
              ifTrue: [self _askTimer: anEvent in: s now: t effects: fx]
              ifFalse: [s]]]].
