"-- cluster/acceptor.st: the acceptor's rules, phase 1: grants, refusals, renewals, releases --

The acceptor side of proto_db's ClusterCoordinator (cluster/coordinator.py at v2.0.0rc3:
_route, _work, _on_request, _decide, _refusal, _on_release, the plain query of _route and the
first-start marker of _attach_locked) as rule methods of PBCoordinatorCore, over the pure
values of lease.st (PBGrantState) and core.st (PBAcceptorState, PBAcceptorStep). The acceptor
lane 'decides, makes its write durable, publishes, then replies, in arrival order'
(coordinator.py:1791): each rule answers one PBAcceptorStep whose appends the shell makes
durable before it performs the reply (R55, R81).

  The dispatcher's routing (proto_db _route): a message whose sender is not another member is
    dropped (so a non-member never reaches PBGrantState, whose rankOf: refuses it); a
    request, renew, query, replicate or store of another voter-set fingerprint (vs, D54) is
    dropped and counted (PBCount stat: 'config_mismatches'); a request, renew, release or
    query goes to the acceptor lane (PBToAcceptor).
  acceptRequest:in:now:, acceptRenew:in:now: (proto_db _on_request, _decide): a refusal of the
    acceptor's state first (fenced, learner, tier_failed, rejoining, in proto_db _refusal's
    order), then PBGrantState decideRequest: or renew: (bad_ballot, starting, stale_term,
    busy, term_taken). A grant of a term above loggedPromise appends a synced promise; a
    renewal or a duplicate of a term already logged appends nothing (D50). The reply is a
    grant (accepted root, committed root, certain) or a reject (accepted root, certain, reason,
    highest, remaining). A grant that ended another one before its time makes the node
    suspect for that term.
  acceptRelease:in:now: (proto_db _on_release): PBGrantState release:inc:term:now:; suspect for
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
    later request is refused tier_failed and every query answered unknown.

Not representable here: proto_db's no_storage refusal (no acceptor log attached). An acceptor
state exists only over a loaded log (PBAcceptorState config:logged:now:); before the attach
the shell has no acceptor (Task 20). A request from this node itself (its own vote, CC1) is
the proposer's (Task 11) and is dropped here as proto_db's _route drops it.

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

"=== PBCoordinatorCore: the dispatcher's routing ============================="

"The types whose vs must be this node's voter-set fingerprint (proto_db _FINGERPRINTED)."
PBCoordinatorCore class >> fingerprintedTypes
  ^ #('request' 'renew' 'query' 'replicate' 'store').

"The types the dispatcher hands to the acceptor lane (proto_db _route; a release's fairness
 part is the proposer's, Task 11)."
PBCoordinatorCore class >> acceptorLaneTypes
  ^ #('request' 'renew' 'release' 'query').

"A wire number of seconds (#number) for someMicros, an Integer of microseconds."
PBCoordinatorCore class >> wireSeconds: someMicros
  ^ (someMicros / 1000000) asFloat.

"Whether aMessage comes from another member of aConfig (proto_db _route drops the rest)."
PBCoordinatorCore >> _fromPeer: aMessage in: aConfig
  ^ aMessage from ~= aConfig nodeId and: [aConfig membership ids includes: aMessage from].

"proto_db _route: unknown senders dropped, a voter-set mismatch dropped and counted, the
 acceptor's messages handed to its lane."
PBCoordinatorCore >> dispatchReceived: anEvent in: aNodeState now: t
  | m |
  m := anEvent message.
  (self _fromPeer: m in: aNodeState config) ifFalse: [^ self _unchanged: aNodeState].
  ((self class fingerprintedTypes includes: m type) and: [(m at: 'vs') ~= aNodeState config membership fingerprint]) ifTrue: [
    "Configured with another voter set (D54): two sets could form two disjoint majorities, so
     nothing it asks for is granted, answered or accepted here."
    ^ PBStep state: aNodeState effects: { PBCount stat: 'config_mismatches' }].
  (self class acceptorLaneTypes includes: m type) ifTrue: [
    ^ PBStep state: aNodeState effects: { PBToAcceptor event: anEvent }].
  ^ self _unchanged: aNodeState.

"=== PBCoordinatorCore: the acceptor's rules ================================="

"A message on the acceptor lane, by type (proto_db _work). A sender that is not another member
 is dropped before any rule (the dispatcher drops it already; the lane does not trust that)."
PBCoordinatorCore >> acceptReceived: anEvent in: anAcceptorState now: t
  | type |
  (self _fromPeer: anEvent message in: anAcceptorState config) ifFalse: [^ self _unchangedAcceptor: anAcceptorState].
  type := anEvent message type.
  type = 'request' ifTrue: [^ self acceptRequest: anEvent in: anAcceptorState now: t].
  type = 'renew' ifTrue: [^ self acceptRenew: anEvent in: anAcceptorState now: t].
  type = 'release' ifTrue: [^ self acceptRelease: anEvent in: anAcceptorState now: t].
  type = 'query' ifTrue: [^ self acceptQuery: anEvent in: anAcceptorState now: t].
  ^ self _unchangedAcceptor: anAcceptorState.

PBCoordinatorCore >> acceptRequest: anEvent in: anAcceptorState now: t
  ^ self _decide: anEvent in: anAcceptorState now: t renew: false.

PBCoordinatorCore >> acceptRenew: anEvent in: anAcceptorState now: t
  ^ self _decide: anEvent in: anAcceptorState now: t renew: true.

"Why this acceptor may not vote now, or nil (proto_db _refusal, in its order; no_storage is
 not representable, see the module comment)."
PBCoordinatorCore >> _refusalIn: s
  s fenced notNil ifTrue: [^ 'fenced'].
  (s config membership isVoter: s config nodeId) ifFalse: [^ 'learner'].
  s tierFailed notNil ifTrue: [^ 'tier_failed'].
  s isRejoined ifFalse: [^ 'rejoining'].
  ^ nil.

"The reject of the request or renewal aMessage (proto_db make_message 'reject')."
PBCoordinatorCore >> _reject: aMessage reason: aReason highest: aHighest remaining: someMicros suspect: aSuspect in: s
  ^ PBClusterMessage type: 'reject' from: s config nodeId fields: {
    'term' -> (aMessage at: 'term'). 'rid' -> (aMessage at: 'rid'). 'inc' -> (aMessage at: 'inc').
    'root' -> (PBClusterMessage rootValue: s accepted). 'certain' -> (aSuspect = 0). 'reason' -> aReason.
    'highest' -> aHighest. 'remaining' -> (self class wireSeconds: (0 max: someMicros)) }.

"proto_db _on_request and _decide: the decision, the promise made durable before the reply,
 the reply."
PBCoordinatorCore >> _decide: anEvent in: s now: t renew: isRenew
  | m term refusal decision suspect appends next reply |
  m := anEvent message.
  term := m at: 'term'.
  refusal := self _refusalIn: s.
  refusal notNil ifTrue: [
    ^ PBAcceptorStep state: s appends: #() reply: { PBSend to: m from message: (self _reject: m reason: refusal
      highest: s grants highestSeen remaining: 0 suspect: s suspectTerm in: s) }].
  decision := isRenew
    ifTrue: [s grants renew: m from inc: (m at: 'inc') term: term now: t config: s config]
    ifFalse: [s grants decideRequest: m from inc: (m at: 'inc') term: term now: t config: s config].
  "A grant ended before its holder released it: its outcome is not known here."
  suspect := s suspectTerm max: decision endedTerm.
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
        'certain' -> (suspect = 0) }].
  next := s withGrants: decision newState suspectTerm: suspect rejoined: s isRejoined tierFailed: s tierFailed
    loggedPromise: (s loggedPromise max: (appends isEmpty ifTrue: [0] ifFalse: [decision promiseToLog])).
  ^ PBAcceptorStep state: next appends: appends reply: { PBSend to: m from message: reply }.

"proto_db _on_release (its grant part): frees the sender's grant, closes the term here."
PBCoordinatorCore >> acceptRelease: anEvent in: s now: t
  | m pair suspect |
  m := anEvent message.
  pair := s grants release: m from inc: (m at: 'inc') term: (m at: 'term') now: t.
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
