"-- cluster/acceptor.st: the acceptor's rules, phase 1: grants, refusals, renewals, releases --

The acceptor side of proto_db's ClusterCoordinator (cluster/coordinator.py at v2.0.0rc3:
_route, _work, _on_request, _decide, _refusal, _on_release, the plain query of _route and the
first-start marker of _attach_locked) as rule methods of PBCoordinatorCore, over the pure
values of lease.st (PBGrantState) and core.st (PBAcceptorState, PBAcceptorStep). The acceptor
lane 'decides, makes its write durable, publishes, then replies, in arrival order'
(coordinator.py:1791): each rule answers one PBAcceptorStep whose appends the shell makes
durable before it performs the reply (R55, R81).

  The dispatcher's handlers: core.st's dispatchReceived: checks the sender and the voter-set
    fingerprint (proto_db _route); receivedQuery:in:now: hands the message to the acceptor lane
    (PBToAcceptor). receivedRequest:, receivedRenew: and receivedRelease: (in:now:) are
    proposer.st's only: they keep the fairness hints, then hand the message here. A plain
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
    1884). A ballot query is the rejoin's: rejoin.st's witness rule (R78a).
  acceptStart:in:now: (proto_db _attach_locked after the restore): a log without the rejoined
    marker on a learner or the only voter gets the marker (synced): there is nobody to learn
    from. The startup grace and the restore are PBAcceptorState config:logged:now:'s, once,
    when the node starts; a start delivered again changes nothing. The committed root restored
    from the log is published (PBPublishCommitted), as proto_db's attach restores _committed.
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

PBCoreEvent subclass: #PBLearnCommitted instanceVariableNames: 'root accept logged'.

"The dispatcher learnt aRoot (a PBLabeledRoot) committed (proto_db _observe_committed outside the
 acceptor lane: the base of a certain permit, the committed root a grant carries, the holder's
 own commit point). acceptBoolean: the root is also accepted knowledge (accept=True; a grant's
 committed root is not, accept=False). logBoolean: a newer committed root is appended to the
 log (#committed, no sync, R67), as proto_db logs the holder's own commit and not a permit's or
 a grant's committed root."
PBLearnCommitted class >> root: aRoot accept: acceptBoolean logged: logBoolean
  (aRoot isClassObject not and: [aRoot class == PBLabeledRoot]) ifFalse: [
    ^ PBValidationError signal: 'PBLearnCommitted: a root is a PBLabeledRoot, not ' , aRoot printString].
  ((acceptBoolean == true or: [acceptBoolean == false]) and: [logBoolean == true or: [logBoolean == false]]) ifFalse: [
    ^ PBValidationError signal: 'PBLearnCommitted: accept and logged are Booleans'].
  ^ self basicNew _setRoot: aRoot accept: acceptBoolean logged: logBoolean.

PBLearnCommitted class >> isAcceptorEvent
  ^ true.

PBLearnCommitted >> _setRoot: aRoot accept: acceptBoolean logged: logBoolean
  "Runs once, on a fresh instance."
  root isNil ifFalse: [^ PBUserError signal: 'PBLearnCommitted is immutable'].
  root := aRoot.
  accept := acceptBoolean.
  logged := logBoolean.
  ^ self.

PBLearnCommitted >> root
  ^ root.

"Whether the root is also accepted knowledge."
PBLearnCommitted >> isAccepted
  ^ accept.

"Whether a newer committed root is appended to the log."
PBLearnCommitted >> isLogged
  ^ logged.

PBLearnCommitted >> acceptWith: aCore in: anAcceptorState now: t
  ^ aCore acceptLearnCommitted: self in: anAcceptorState now: t.

PBLearnCommitted >> printOn: aStream
  aStream nextPutAll: 'PBLearnCommitted('; nextPutAll: (PBCoreValue textOf: root);
    nextPutAll: (accept ifTrue: [', accepted'] ifFalse: ['']); nextPutAll: (logged ifTrue: [', logged'] ifFalse: ['']); nextPut: $).

"=== PBCoordinatorCore: the dispatcher's handlers ==========================="

"A wire number of seconds (#number) for someMicros, an Integer of microseconds. The inbound
 direction (a received reject's remaining) is microsFromWire: (proposer.st)."
PBCoordinatorCore class >> wireSeconds: someMicros
  ^ (someMicros / 1000000) asFloat.

"The acceptor lane takes requests, renewals, releases and queries (proto_db _route). The
 handlers of requests, renewals and releases are defined once, in proposer.st, which keeps the
 fairness hints before it hands the message to the lane. proto_db answers a plain query on the
 dispatcher; here the acceptor answers it from its own state (CC2), after the steps queued
 before it: a timing difference only, and its answer reports durable state only."
PBCoordinatorCore >> receivedQuery: anEvent in: aNodeState now: t
  ^ PBStep state: (self _queryHint: anEvent message in: aNodeState) effects: { PBToAcceptor event: anEvent }.

"proto_db _on_ballot_query raises the hint to the ballot it promises: here the dispatcher does,
 when its view of the acceptor is a witness ('ok', not fenced) that will promise it."
PBCoordinatorCore >> _queryHint: aMessage in: s
  | ballot view h |
  ballot := aMessage at: 'ballot'.
  view := s acceptorView.
  (ballot > 0 and: [view notNil and: [view fenced isNil and: [(self _witnessStateIn: view) = 'ok']]]) ifFalse: [^ s].
  h := self _hintsIn: s.
  ^ s with: { #hints -> (h with: { #hint -> (h hint max: ballot) }) }.

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

"proto_db _on_release: frees the sender's grant, closes the term here; a held release teaches
 the committed root it carries (accepted knowledge too, appended #committed without a sync when
 newer, R67). This node's own release raises no suspicion and teaches nothing (proto_db release
 and _close_attempt call only PeerGrants.on_release)."
PBCoordinatorCore >> acceptRelease: anEvent in: s now: t
  | m pair state learnt appends reply committed |
  "A fenced node drops the lane's messages (proto_db _enqueue)."
  s fenced notNil ifTrue: [^ self _unchangedAcceptor: s].
  m := anEvent message.
  pair := s grants release: m from inc: (m at: 'inc') term: (m at: 'term') now: t.
  m from = s config nodeId ifTrue: [
    ^ PBAcceptorStep state: (s withGrants: pair first suspectTerm: s suspectTerm rejoined: s isRejoined
        tierFailed: s tierFailed loggedPromise: s loggedPromise)
      appends: #() reply: #()].
  state := s withGrants: pair first suspectTerm: (s suspectTerm max: pair last) rejoined: s isRejoined
    tierFailed: s tierFailed loggedPromise: s loggedPromise.
  learnt := 0.
  appends := #().
  reply := #().
  (m at: 'held') ifTrue: [
    committed := PBClusterMessage rootFrom: (m at: 'committed').
    "In proto_db's order: the grant it ended taints first, the committed root it teaches may
     clear that (a root of that term or later), an uncertain release taints again."
    committed notNil ifTrue: [
      pair := self _learnCommitted: committed accept: true logged: true in: state.
      state := pair first.
      appends := pair at: 2.
      reply := pair last.
      learnt := committed label].
    (m at: 'certain') ifFalse: [
      "The holder may have published something it could not replicate: whatever its term
       decided is unknown here until a root of that term or later arrives."
      state := state with: { #suspectTerm -> (state suspectTerm max: (m at: 'term')) }]].
  ^ PBAcceptorStep state: state appends: appends reply: reply vote: nil learnt: learnt.

"What this acceptor's answers are worth (proto_db _witness_state): 'unknown' when its tier
 failed, 'learner', 'empty' while it rejoins, else 'ok'."
PBCoordinatorCore >> _witnessStateIn: s
  s tierFailed notNil ifTrue: [^ 'unknown'].
  (s config membership isVoter: s config nodeId) ifFalse: [^ 'learner'].
  s isRejoined ifFalse: [^ 'empty'].
  ^ 'ok'.

"The answer of a query (proto_db _route): a plain one (ballot 0) here, a ballot one is the
 rejoin's witness rule (rejoin.st _ballotQuery:in:now:, R78a)."
PBCoordinatorCore >> acceptQuery: anEvent in: s now: t
  | m |
  m := anEvent message.
  (m at: 'ballot') = 0 ifFalse: [^ self _ballotQuery: m in: s now: t].
  ^ self _plainQuery: m in: s.

"The plain answer to the query aMessage (proto_db _route, ballot 0): what this acceptor's
 state is worth (_witnessStateIn:), its roots and promise unless 'unknown'."
PBCoordinatorCore >> _plainQuery: aMessage in: s
  ^ PBAcceptorStep state: s appends: #()
    reply: { PBSend to: aMessage from message: (self _answer: aMessage state: (self _witnessStateIn: s) ballot: 0 in: s) }.

"The answer to the query aMessage in aState, echoing aBallot (proto_db _on_answer's fields):
 'unknown' reports no root, certain false, promised 0."
PBCoordinatorCore >> _answer: aMessage state: aState ballot: aBallot in: s
  | known |
  known := aState ~= 'unknown'.
  "promised: the lease activity this node knows of and the accepted root's label, not the
   committed root's label nor a floor restored from such labels (R51)."
  ^ PBClusterMessage type: 'answer' from: s config nodeId fields: {
    'rid' -> (aMessage at: 'rid'). 'inc' -> (aMessage at: 'inc').
    'root' -> (known ifTrue: [PBClusterMessage rootValue: s accepted] ifFalse: [nil]).
    'committed' -> (known ifTrue: [PBClusterMessage rootValue: s committed] ifFalse: [nil]).
    'certain' -> (known and: [s suspectTerm = 0]).
    'promised' -> (known
      ifTrue: [s grants termsSeen max: (s accepted isNil ifTrue: [0] ifFalse: [s accepted label])]
      ifFalse: [0]).
    'state' -> aState. 'ballot' -> aBallot }.

"proto_db _attach_locked: a learner, or a voter without another voter, has nothing to learn
 before it serves (D54), so a log without the rejoined marker gets it. A voter with other
 voters rejoins (rejoin.st). The grace and the restore are not rebuilt (Task 9 ruling)."
PBCoordinatorCore >> acceptStart: anEvent in: s now: t
  | membership id published |
  "proto_db _attach_locked restores _committed from the log: the node knows it committed from
   the start, so the restored committed root is published (again, harmlessly, on a start
   delivered twice)."
  published := s committed isNil ifTrue: [#()] ifFalse: [{ PBPublishCommitted root: s committed }].
  membership := s config membership.
  id := s config nodeId.
  (s isRejoined or: [(membership isVoter: id) and: [membership voters anySatisfy: [:v | v ~= id]]]) ifTrue: [
    ^ PBAcceptorStep state: s appends: #() reply: published].
  ^ PBAcceptorStep
    state: (s withGrants: s grants suspectTerm: s suspectTerm rejoined: true tierFailed: s tierFailed loggedPromise: s loggedPromise)
    appends: { PBLogAppend kind: #rejoined label: 0 root: nil sync: true } reply: published.

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


"=== PBCoordinatorCore: acceptance and committed knowledge ===================="

"proto_db _learn_label: a root labelled aLabel is known, so a suspicion it answers (aTerm at or
 below aLabel) is cleared: answers the suspicion left (0: none)."
PBCoordinatorCore >> _learnLabel: aLabel clears: aTerm
  ^ (aTerm > 0 and: [aLabel >= aTerm]) ifTrue: [0] ifFalse: [aTerm].

"proto_db _observe_accepted: s with aRoot (a PBLabeledRoot) learnt, and adopted as the accepted
 root when it orders after it (memory only)."
PBCoordinatorCore >> _observeAccepted: aRoot in: s
  | state |
  state := s with: { #suspectTerm -> (self _learnLabel: aRoot label clears: s suspectTerm) }.
  (PBRootOrder compare: aRoot with: s accepted) <= 0 ifTrue: [^ state].
  ^ state with: { #accepted -> aRoot }.

"proto_db _observe_committed: { state. adopted }: s with aRoot learnt (accepted knowledge too
 when isAccept) and adopted as the committed root when it orders after it."
PBCoordinatorCore >> _observeCommitted: aRoot accept: isAccept in: s
  | state |
  state := isAccept
    ifTrue: [self _observeAccepted: aRoot in: s]
    ifFalse: [s with: { #suspectTerm -> (self _learnLabel: aRoot label clears: s suspectTerm) }].
  (PBRootOrder compare: aRoot with: s committed) <= 0 ifTrue: [^ { state. false }].
  ^ { state with: { #committed -> aRoot }. true }.

"{ state. appends. reply }: aRoot learnt committed in s; a newer committed root is published
 (PBPublishCommitted) and, when isLogged, appended #committed without a sync (R67). A tier that
 failed takes no append (R57: proto_db's write fails and the first failure is kept); the
 knowledge stays in memory, as proto_db's."
PBCoordinatorCore >> _learnCommitted: aRoot accept: isAccept logged: isLogged in: s
  | pair |
  pair := self _observeCommitted: aRoot accept: isAccept in: s.
  pair last ifFalse: [^ { pair first. #(). #() }].
  ^ { pair first.
    (isLogged and: [s tierFailed isNil])
      ifTrue: [{ PBLogAppend kind: #committed label: aRoot label root: aRoot record sync: false }]
      ifFalse: [#()].
    { PBPublishCommitted root: aRoot } }.

"The dispatcher learnt a root committed (PBLearnCommitted). A fenced node learns nothing (its
 lanes drop their messages)."
PBCoordinatorCore >> acceptLearnCommitted: anEvent in: s now: t
  | triple |
  s fenced notNil ifTrue: [^ self _unchangedAcceptor: s].
  triple := self _learnCommitted: anEvent root accept: anEvent isAccepted logged: anEvent isLogged in: s.
  ^ PBAcceptorStep state: triple first appends: (triple at: 2) reply: triple last vote: nil learnt: anEvent root label.

"proto_db _on_done (the acceptor lane): a done 'committed' teaches its root, accepted knowledge
 too, appended #committed without a sync when newer. A fenced node drops it."
PBCoordinatorCore >> acceptDone: anEvent in: s now: t
  | m root triple |
  s fenced notNil ifTrue: [^ self _unchangedAcceptor: s].
  m := anEvent message.
  root := PBClusterMessage rootFrom: (m at: 'root').
  ((m at: 'outcome') = 'committed' and: [root notNil]) ifFalse: [^ self _unchangedAcceptor: s].
  triple := self _learnCommitted: root accept: true logged: true in: s.
  ^ PBAcceptorStep state: triple first appends: (triple at: 2) reply: triple last vote: nil learnt: root label.

"Whether aRoot and another are different roots of one label and epoch (proto_db _siblings: two
 roots built on one base in one term). Either may be nil."
PBCoordinatorCore >> _siblings: aRoot of: another
  ^ aRoot notNil and: [another notNil and: [aRoot label = another label and: [aRoot epoch = another epoch
    and: [aRoot key ~= another key]]]].

"proto_db _may_accept: whether aRoot (labelled aTerm) built on aPred (a PBLabeledRoot or nil)
 under permission aSeq may be accepted by the acceptor s: it may vote (no refusal of its state),
 no higher term was granted here (the ballot rule), it is not older than the accepted root, and
 the chain rule (V2', Raft's log matching on roots): a root built on a root of its own term is
 taken only when it is the accepted root again (a duplicate) or its pred IS the accepted root;
 only the first root of a term (its pred labelled below it) may follow an accepted root of an
 older term, or reach an acceptor that accepted nothing, under the ballot rule alone. A seq
 below the highest accepted in the term and a sibling of the accepted root are refused."
PBCoordinatorCore >> _mayAccept: aRoot term: aTerm pred: aPred seq: aSeq in: s
  | firstOfTerm accepted order |
  ((self _refusalIn: s) isNil and: [self _ballotAllows: aTerm in: s]) ifFalse: [^ false].
  firstOfTerm := aPred notNil and: [aPred label < aRoot label].
  accepted := s accepted.
  accepted isNil ifTrue: [^ firstOfTerm].
  "Two roots of one term on one base: two holders of one term (the owner's sequencing broke).
   Refused, never a protocol violation (D50, S3)."
  (self _siblings: aRoot of: accepted) ifTrue: [^ false].
  order := PBRootOrder compare: aRoot with: accepted.
  order <= 0 ifTrue: [^ order = 0].
  "A root of a newer term: only its first root, built on a base out of phase 1. A later root of
   that term extends a root this node does not hold (V2')."
  accepted label ~= aRoot label ifTrue: [^ firstOfTerm].
  ((s seqSeen at: 1) = aRoot label and: [aSeq < (s seqSeen at: 2)]) ifTrue: [^ false].
  ^ self _extends: accepted with: aPred.

"The ballot rule: no term above aTerm was granted by the acceptor s (proto_db granted_top)."
PBCoordinatorCore >> _ballotAllows: aTerm in: s
  ^ s grants grantedTop <= aTerm.

"V2' (log matching on roots): a later root of the accepted root's term is taken only when its
 pred (aPred, nil when unknown) IS anAccepted; a pred that is a sibling of it is refused."
PBCoordinatorCore >> _extends: anAccepted with: aPred
  (aPred isNil or: [self _siblings: aPred of: anAccepted]) ifTrue: [^ false].
  ^ (PBRootOrder compare: aPred with: anAccepted) = 0.

"{ term. seq } after a root of aLabel under permission aSeq was accepted (proto_db _note_seq:
 the greater pair)."
PBCoordinatorCore >> _seqSeen: aPair after: aLabel seq: aSeq
  ((aLabel > (aPair at: 1)) or: [aLabel = (aPair at: 1) and: [aSeq > (aPair at: 2)]]) ifTrue: [^ { aLabel. aSeq }].
  ^ aPair.

"The ack of the replication aMessage: ok, the accepted root of s, never a durable copy here
 (stored false: proto_db's shared-storage path claims none)."
PBCoordinatorCore >> _ack: aMessage ok: isOk in: s
  ^ PBClusterMessage type: 'ack' from: s config nodeId fields: {
    'term' -> (aMessage at: 'term'). 'rid' -> (aMessage at: 'rid'). 'inc' -> (aMessage at: 'inc'). 'ok' -> isOk.
    'root' -> (PBClusterMessage rootValue: s accepted). 'stored' -> false }.

"proto_db _apply_replicate over a shared storage (CP 1.7 step 8): the root is valid when it is
 known, labelled with the message's term, not the empty space, and whole (chunks 0: a
 protoBaseST node never takes records messages, CC7, so a replication in chunks is never
 complete here); it is accepted under _mayAccept:term:pred:seq:in:. One synced #accepted
 append, then the publication (PBPublishAcceptor, and the committed root the message teaches,
 memory only), then ack(ok, stored = false). A refusal is ack(ok = false), counted refused. A
 fenced node refuses (proto_db _refuse_queued). The holder's own replication (CC1) is decided
 by the same rule; its ack is the step's vote, it is not counted, and it teaches no committed
 root (proto_db replicate's own acceptance)."
PBCoordinatorCore >> acceptReplicate: anEvent in: s now: t
  | m own root pred term ok state reply learnt committed triple ack appends |
  m := anEvent message.
  own := m from = s config nodeId.
  term := m at: 'term'.
  root := PBClusterMessage rootFrom: (m at: 'root').
  pred := PBClusterMessage rootFrom: (m at: 'pred').
  ok := s fenced isNil and: [root notNil and: [root record notNil and: [root label = term and: [(m at: 'chunks') = 0
    and: [self _mayAccept: root term: term pred: pred seq: (m at: 'seq') in: s]]]]].
  ok ifFalse: [
    ack := self _ack: m ok: false in: s.
    own ifTrue: [^ PBAcceptorStep state: s appends: #() reply: #() vote: ack].
    ^ PBAcceptorStep state: s appends: #() reply: { PBCount stat: 'refused'. PBSend to: m from message: ack }].
  state := self _observeAccepted: root in: s.
  state := state with: { #seqSeen -> (self _seqSeen: state seqSeen after: term seq: (m at: 'seq')) }.
  learnt := term.
  reply := OrderedCollection new.
  appends := OrderedCollection with: (PBLogAppend kind: #accepted label: term root: root record sync: true).
  own ifFalse: [
    committed := PBClusterMessage rootFrom: (m at: 'committed').
    committed notNil ifTrue: [
      triple := self _learnCommitted: committed accept: true logged: false in: state.
      state := triple first.
      appends addAll: (triple at: 2).
      reply addAll: triple last.
      learnt := learnt max: committed label].
    reply add: (PBCount stat: 'accepted')].
  reply addFirst: (PBPublishAcceptor state: state).
  ack := self _ack: m ok: true in: state.
  own ifTrue: [^ PBAcceptorStep state: state appends: appends asArray reply: reply asArray vote: ack learnt: learnt].
  reply add: (PBSend to: m from message: ack).
  ^ PBAcceptorStep state: state appends: appends asArray reply: reply asArray vote: nil learnt: learnt.
