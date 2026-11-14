"-- cluster/acceptor.st: the acceptor's rules, phase 1: grants, refusals, renewals, releases --

The acceptor side of proto_db's ClusterCoordinator (cluster/coordinator.py at v2.0.0rc3:
_route, _work, _on_request, _decide, _refusal, _on_release, the plain query of _route and the
first-start marker of _attach_locked) as rule methods of PBCoordinatorCore, over the pure
values of lease.st (PBGrantState) and core.st (PBAcceptorState, PBAcceptorStep). The acceptor
lane 'decides, makes its write durable, publishes, then replies, in arrival order'
(coordinator.py:1791): each rule answers one PBAcceptorStep whose appends the shell makes
durable before it performs the reply (R55, R81).

  The dispatcher's handlers: core.st's dispatchReceived: checks the sender and the voter-set
    fingerprint (proto_db _route); receivedRequest:, receivedRenew:, receivedRelease: and
    receivedQuery: (in:now:) hand the message to the acceptor lane (PBToAcceptor). A plain
    query is answered by the acceptor, where proto_db answers it on the dispatcher (a timing
    difference only, docs/deviations.md).
  acceptRequest:in:now:, acceptRenew:in:now: (proto_db _on_request, _decide): a fenced node
    answers nothing (proto_db _enqueue); a refusal of the acceptor's state first (learner,
    tier_failed, rejoining, in proto_db _refusal's order), then PBGrantState decideRequest: or renew: (bad_ballot, starting, stale_term,
    busy, term_taken). A grant of a term above loggedPromise appends a synced promise; a
    renewal or a duplicate of a term already logged appends nothing (D50). The reply is a
    grant (accepted root, committed root, certain) or a reject (accepted root, certain, reason,
    highest, remaining) and every grant to a peer counts grants_given. A grant that ended another one
    before its time makes the node suspect for that term.
  acceptRelease:in:now: (proto_db _on_release; dropped when fenced): PBGrantState release:inc:term:now:; suspect for
    an expired grant it ended, and for the term of a held release that is not certain. The
    committed root a release teaches is acceptance knowledge (Task 13).
  acceptQuery:in:now: (the plain query of proto_db _route, ballot 0): the answer of state
    'unknown' (tier failed: root, committed nil, certain false, promised 0), 'learner',
    'empty' (rejoining) or 'ok', promised max(termsSeen, accepted label) (coordinator.py:1852,
    1884). A ballot query is the rejoin's (Task 16, R78a).
  acceptStart:in:now: (proto_db _attach_locked after the restore): a log without the rejoined
    marker on a learner or the only voter gets the marker (synced): there is nobody to learn
    from. The startup grace and the restore are PBAcceptorState config:logged:now:'s, once,
    when the node starts; a start delivered again changes nothing.
  acceptSuspect:in:now: (PBSuspect term:): the dispatcher's suspicion (an abandoned term, a
    replication whose outcome it cannot know) raises the acceptor's suspectTerm, which every
    grant, reject and answer reports as certain = false.
  acceptAppendFailed:in:now: (PBAppendFailed reason:): the shell could not make an append
    durable. The step that asked for it is never replied (a grant whose promise is not
    durable is withdrawn); the tier fails for good (R57, the first failure kept), so every
    later request is refused tier_failed and every query answered unknown. The shell discards
    the failed step's state (core.st, PBAcceptorStep), so loggedPromise never holds a promise
    that was not written.

Not representable here: proto_db's no_storage refusal (no acceptor log attached). An acceptor
state exists only over a loaded log (PBAcceptorState config:logged:now:); before the attach
the shell has no acceptor (Task 20).

This node's own messages (CC1, proposer.st): its own request and renewal are decided by
_decide: as a peer's (proto_db _open_attempt and _renew decide the own vote with the same
grant rules, after _refusal), and the step sends nothing: the grant or reject is the step's vote
(PBAcceptorStep vote), which the dispatcher reads from the step handed back. Its own release or
cancel frees its grant and closes the term (proto_db release and _close_attempt call
PeerGrants.on_release) and raises no suspicion: proto_db discards what on_release answers there.

Wire time: a reject's remaining is a number of seconds (#number, a Float in proto_db): the
core's microseconds are converted when the message is built (wireSeconds:)."

Import from: 'protobase/errors'.
Import from: 'protobase/cluster/members'.
Import from: 'protobase/cluster/rootlog'.
Import from: 'protobase/cluster/protocol'.
Import from: 'protobase/cluster/config'.
Import from: 'protobase/cluster/lease'.
Import from: 'protobase/cluster/core'.

"=== Acceptor events ========================================================="

PBCoreEvent subclass: #PBSuspect instanceVariableNames: 'term'.

"The dispatcher cannot know the outcome of aTerm (an Integer > 0): the acceptor reports
 certain = false until a later rule clears it."
PBSuspect class >> term: aTerm
  (aTerm isInteger and: [aTerm > 0]) ifFalse: [
    ^ PBValidationError signal: 'PBSuspect: a term is an Integer > 0, not ' , aTerm printString].
  ^ self basicNew _setTerm: aTerm.

PBSuspect class >> isAcceptorEvent
  ^ true.

PBSuspect >> _setTerm: aTerm
  "Runs once, on a fresh instance."
  term isNil ifFalse: [^ PBUserError signal: 'PBSuspect is immutable'].
  term := aTerm.
  ^ self.

PBSuspect >> term
  ^ term.

PBSuspect >> acceptWith: aCore in: anAcceptorState now: t
  ^ aCore acceptSuspect: self in: anAcceptorState now: t.

PBSuspect >> printOn: aStream
  aStream nextPutAll: 'PBSuspect('; print: term; nextPut: $).

PBCoreEvent subclass: #PBAppendFailed instanceVariableNames: 'reason'.

"The acceptor shell could not make an append of its last step durable, for aReason (a
 non-empty String): that step's reply is never performed."
PBAppendFailed class >> reason: aReason
  (aReason isString and: [aReason notEmpty]) ifFalse: [
    ^ PBValidationError signal: 'PBAppendFailed: a reason is a non-empty String, not ' , aReason printString].
  ^ self basicNew _setReason: aReason asString.

PBAppendFailed class >> isAcceptorEvent
  ^ true.

PBAppendFailed >> _setReason: aReason
  "Runs once, on a fresh instance."
  reason isNil ifFalse: [^ PBUserError signal: 'PBAppendFailed is immutable'].
  reason := aReason.
  ^ self.

PBAppendFailed >> reason
  ^ reason.

PBAppendFailed >> acceptWith: aCore in: anAcceptorState now: t
  ^ aCore acceptAppendFailed: self in: anAcceptorState now: t.

PBAppendFailed >> printOn: aStream
  aStream nextPutAll: 'PBAppendFailed('; nextPutAll: reason; nextPut: $).

"=== PBCoordinatorCore: the dispatcher's handlers ==========================="

"A wire number of seconds (#number) for someMicros, an Integer of microseconds. The inbound
 direction (a received reject's remaining) is microsFromWire: (proposer.st)."
PBCoordinatorCore class >> wireSeconds: someMicros
  ^ (someMicros / 1000000) asFloat.

"The acceptor lane takes requests, renewals, releases and queries (proto_db _route; a release's
 fairness part is the proposer's, Task 11). proto_db answers a plain query on the dispatcher;
 here the acceptor answers it from its own state (CC2), after the steps queued before it: a
 timing difference only, and its answer reports durable state only."
PBCoordinatorCore >> receivedRequest: anEvent in: aNodeState now: t
  ^ PBStep state: aNodeState effects: { PBToAcceptor event: anEvent }.

PBCoordinatorCore >> receivedRenew: anEvent in: aNodeState now: t
  ^ PBStep state: aNodeState effects: { PBToAcceptor event: anEvent }.

PBCoordinatorCore >> receivedRelease: anEvent in: aNodeState now: t
  ^ PBStep state: aNodeState effects: { PBToAcceptor event: anEvent }.

PBCoordinatorCore >> receivedQuery: anEvent in: aNodeState now: t
  ^ PBStep state: aNodeState effects: { PBToAcceptor event: anEvent }.

"=== PBCoordinatorCore: the acceptor's rules ================================="

PBCoordinatorCore >> acceptRequest: anEvent in: anAcceptorState now: t
  ^ self _decide: anEvent in: anAcceptorState now: t renew: false.

PBCoordinatorCore >> acceptRenew: anEvent in: anAcceptorState now: t
  ^ self _decide: anEvent in: anAcceptorState now: t renew: true.

"Why this acceptor may not vote now, or nil (proto_db _refusal, in its order). fenced is not
 a reply here: a fenced node sends nothing (proto_db _enqueue drops the lane's messages once
 fenced; its 'fenced' reject only answers a message queued before the fence, which a serial lane
 whose state holds the fence cannot have). no_storage is not representable (module comment)."
PBCoordinatorCore >> _refusalIn: s
  (s config membership isVoter: s config nodeId) ifFalse: [^ 'learner'].
  s tierFailed notNil ifTrue: [^ 'tier_failed'].
  s isRejoined ifFalse: [^ 'rejoining'].
  ^ nil.

"The step answering the request or renewal m with aReply (a grant or reject message) and
 someCounts: sent to its sender, or, for this node's own request, the step's vote (CC1)."
PBCoordinatorCore >> _answer: m with: aReply in: next appends: appends counts: someCounts
  m from = next config nodeId ifTrue: [
    ^ PBAcceptorStep state: next appends: appends reply: someCounts vote: aReply].
  ^ PBAcceptorStep state: next appends: appends reply: { PBSend to: m from message: aReply } , someCounts.

"The reject of the request or renewal aMessage (proto_db make_message 'reject')."
PBCoordinatorCore >> _reject: aMessage reason: aReason highest: aHighest remaining: someMicros suspect: aSuspect in: s
  ^ PBClusterMessage type: 'reject' from: s config nodeId fields: {
    'term' -> (aMessage at: 'term'). 'rid' -> (aMessage at: 'rid'). 'inc' -> (aMessage at: 'inc').
    'root' -> (PBClusterMessage rootValue: s accepted). 'certain' -> (aSuspect = 0). 'reason' -> aReason.
    'highest' -> aHighest. 'remaining' -> (self class wireSeconds: (0 max: someMicros)) }.

"proto_db _on_request and _decide: the decision, the promise made durable before the reply,
 the reply."
PBCoordinatorCore >> _decide: anEvent in: s now: t renew: isRenew
  | m term refusal decision suspect appends next reply counts |
  s fenced notNil ifTrue: [^ self _unchangedAcceptor: s].
  m := anEvent message.
  term := m at: 'term'.
  refusal := self _refusalIn: s.
  refusal notNil ifTrue: [
    ^ self _answer: m with: (self _reject: m reason: refusal highest: s grants highestSeen remaining: 0
      suspect: s suspectTerm in: s) in: s appends: #() counts: #()].
  decision := isRenew
    ifTrue: [s grants renew: m from inc: (m at: 'inc') term: term now: t config: s config]
    ifFalse: [s grants decideRequest: m from inc: (m at: 'inc') term: term now: t config: s config].
  "A grant ended before its holder released it: its outcome is not known here."
  suspect := s suspectTerm max: decision endedTerm.
  counts := #().
  decision verdict = #grant
    ifFalse: [
      appends := #().
      reply := self _reject: m reason: decision reason highest: decision highest remaining: decision remaining
        suspect: suspect in: s]
    ifTrue: [
      "A term at or below the promise already logged needs no write (a renewal or a duplicate,
       D50): the log keeps only the highest promise."
      appends := decision promiseToLog > s loggedPromise
        ifTrue: [{ PBLogAppend kind: #promise label: decision promiseToLog root: nil sync: true }]
        ifFalse: [#()].
      reply := PBClusterMessage type: 'grant' from: s config nodeId fields: {
        'term' -> term. 'rid' -> (m at: 'rid'). 'inc' -> (m at: 'inc').
        'root' -> (PBClusterMessage rootValue: s accepted). 'committed' -> (PBClusterMessage rootValue: s committed).
        'certain' -> (suspect = 0) }.
      "Every grant to a peer, renewals and duplicates included (proto_db _decide,
       grants_given); this node's own vote is not counted (proto_db _open_attempt and _renew
       decide it without _decide)."
      counts := m from = s config nodeId ifTrue: [#()] ifFalse: [{ PBCount stat: 'grants_given' }]].
  next := s withGrants: decision newState suspectTerm: suspect rejoined: s isRejoined tierFailed: s tierFailed
    loggedPromise: (s loggedPromise max: (appends isEmpty ifTrue: [0] ifFalse: [decision promiseToLog])).
  ^ self _answer: m with: reply in: next appends: appends counts: counts.

"proto_db _on_release (its grant part): frees the sender's grant, closes the term here. This
 node's own release raises no suspicion (proto_db release and _close_attempt discard what
 PeerGrants.on_release answers)."
PBCoordinatorCore >> acceptRelease: anEvent in: s now: t
  | m pair suspect |
  "A fenced node drops the lane's messages (proto_db _enqueue)."
  s fenced notNil ifTrue: [^ self _unchangedAcceptor: s].
  m := anEvent message.
  pair := s grants release: m from inc: (m at: 'inc') term: (m at: 'term') now: t.
  m from = s config nodeId ifTrue: [
    ^ PBAcceptorStep state: (s withGrants: pair first suspectTerm: s suspectTerm rejoined: s isRejoined
        tierFailed: s tierFailed loggedPromise: s loggedPromise)
      appends: #() reply: #()].
  suspect := s suspectTerm max: pair last.
  ((m at: 'held') and: [(m at: 'certain') not]) ifTrue: [
    "The holder may have published something it could not replicate: whatever its term
     decided is unknown here until a root of that term or later arrives."
    suspect := suspect max: (m at: 'term')].
  ^ PBAcceptorStep state: (s withGrants: pair first suspectTerm: suspect rejoined: s isRejoined tierFailed: s tierFailed
      loggedPromise: s loggedPromise)
    appends: #() reply: #().

"What this acceptor's answers are worth (proto_db _witness_state): 'unknown' when its tier
 failed, 'learner', 'empty' while it rejoins, else 'ok'."
PBCoordinatorCore >> _witnessStateIn: s
  s tierFailed notNil ifTrue: [^ 'unknown'].
  (s config membership isVoter: s config nodeId) ifFalse: [^ 'learner'].
  s isRejoined ifFalse: [^ 'empty'].
  ^ 'ok'.

"The answer of a plain query (proto_db _route, ballot 0). A ballot query is the rejoin's
 promise (R78a, Task 16): not answered here."
PBCoordinatorCore >> acceptQuery: anEvent in: s now: t
  | m state known answer |
  m := anEvent message.
  (m at: 'ballot') = 0 ifFalse: [^ self _unchangedAcceptor: s].
  state := self _witnessStateIn: s.
  known := state ~= 'unknown'.
  "promised: the lease activity this node knows of and the accepted root's label, not the
   committed root's label nor a floor restored from such labels (R51)."
  answer := PBClusterMessage type: 'answer' from: s config nodeId fields: {
    'rid' -> (m at: 'rid'). 'inc' -> (m at: 'inc').
    'root' -> (known ifTrue: [PBClusterMessage rootValue: s accepted] ifFalse: [nil]).
    'committed' -> (known ifTrue: [PBClusterMessage rootValue: s committed] ifFalse: [nil]).
    'certain' -> (known and: [s suspectTerm = 0]).
    'promised' -> (known
      ifTrue: [s grants termsSeen max: (s accepted isNil ifTrue: [0] ifFalse: [s accepted label])]
      ifFalse: [0]).
    'state' -> state. 'ballot' -> 0 }.
  ^ PBAcceptorStep state: s appends: #() reply: { PBSend to: m from message: answer }.

"proto_db _attach_locked: a learner, or a voter without another voter, has nothing to learn
 before it serves (D54), so a log without the rejoined marker gets it. A voter with other
 voters rejoins (Task 16). The grace and the restore are not rebuilt (Task 9 ruling)."
PBCoordinatorCore >> acceptStart: anEvent in: s now: t
  | membership id |
  s isRejoined ifTrue: [^ self _unchangedAcceptor: s].
  membership := s config membership.
  id := s config nodeId.
  ((membership isVoter: id) and: [membership voters anySatisfy: [:v | v ~= id]]) ifTrue: [
    ^ self _unchangedAcceptor: s].
  ^ PBAcceptorStep
    state: (s withGrants: s grants suspectTerm: s suspectTerm rejoined: true tierFailed: s tierFailed loggedPromise: s loggedPromise)
    appends: { PBLogAppend kind: #rejoined label: 0 root: nil sync: true } reply: #().

PBCoordinatorCore >> acceptSuspect: anEvent in: s now: t
  ^ PBAcceptorStep
    state: (s withGrants: s grants suspectTerm: (s suspectTerm max: anEvent term) rejoined: s isRejoined
      tierFailed: s tierFailed loggedPromise: s loggedPromise)
    appends: #() reply: #().

"proto_db _tier_failed: the first failure is kept; the acceptor refuses from now on (R57)."
PBCoordinatorCore >> acceptAppendFailed: anEvent in: s now: t
  ^ PBAcceptorStep
    state: (s withGrants: s grants suspectTerm: s suspectTerm rejoined: s isRejoined
      tierFailed: (s tierFailed isNil ifTrue: [anEvent reason] ifFalse: [s tierFailed]) loggedPromise: s loggedPromise)
    appends: #() reply: #().
