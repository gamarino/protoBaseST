"-- cluster/coordinator.st: the coordinator shell: a running cluster node --

proto_db cluster/coordinator.py at v2.0.0rc3 (ClusterCoordinator: start, stop, stats, attach,
detach, force_rejoin, fence, the dispatcher thread and the acceptor lane), as the shell around
the sans-IO core (core.st and the rule modules): the shell reads the clock, holds the state
values in Atoms, performs the effects and turns failures into the fence. It decides nothing the
core decides (spec 5.4).

  PBClusterCoordinator  one member of a cluster. nodeId:peers:options: (PBClusterConfig's
                        options; #transport, a started-nowhere PBClusterTransport, is the test
                        seam, else a PBTcpTransport listens on the member's port with
                        requestTimeout). start opens the transport and starts the node with no
                        acceptor log: until _attach: aTier a request is refused no_storage and a
                        plain query answered unknown (core.st config:detachedAt:). stop settles
                        every pending Future (a replication in flight #unknown, never #none;
                        the rest rejected with PBClosedError) and answers a Future that settles
                        once the transport stopped. stats (CC24, proto_db's snake_case names),
                        forceRejoin, committedRoot (a PBLabeledRoot read from an Atom, never a
                        message), committedEpoch, needsConfirmation, isFenced, nodeId, config.
                        The round runner's interface answers Futures and never waits: _permit
                        (a PBPermission), _baseFor: (a PBBaseDecision), _replicate:under:
                        (#committed, #none or #unknown), _done:outcome:[root:] and _confirmed.
                        The tier's: _attach: aTier, _detach: aTier and _detach (Futures).
  _PBDispatcher         an actor of the high band (spec 5.4): runs dispatch:in:now: over the
                        PBNodeState of the node's Atom, one event at a time, and performs the
                        step's effects in order: PBSend through the transport, PBToAcceptor to
                        the acceptor actor, PBTimer as (Future after: ms) thenDo: sending the
                        PBTimerFired back, PBSettle on the Future of its waiter, PBPublishCommitted
                        into the committed Atom (the higher root; nil drops it), PBCount into the counters, PBFence, and the tier
                        reads (PBReadPersisted, PBProbeRoot) to the acceptor, which owns the tier.
                        A message whose sender is not another member is dropped and counted
                        messages_ignored before the rules see it (Task 19 (b)). The transport's
                        handler only forwards each message here, so it never signals and is safe
                        on several reader actors at once (Task 19 (a), (f)).
  _PBAcceptor           an actor of the high band holding the tier: runs accept:in:now: over
                        the PBAcceptorState of its Atom; writes the step's appends in order
                        through the tier; only then publishes the state to the Atom (readers and
                        stats read it there, CC2), then performs the reply effects, then hands
                        the step to the dispatcher (PBAcceptorDecided): the atomic acceptor step
                        (R55, R81). An append that fails on the tier (a PBDBError or a
                        FileSystemError, proto_db's ProtoDBError or OSError) discards the step: the
                        state before it is kept, none of its reply is performed, the dispatcher
                        gets PBAcceptorDiscarded and the acceptor PBAppendFailed, both built from
                        one reason (review m), so the tier fails for good (R57).

Errors on the actors (proto_db _work and _on_message): a PBDBError a rule signals (proto_db's
ProtoDBError: a protocol violation, a malformed value) is written to stderr and that message
dropped, the node kept; a local request's waiter is rejected with it. The fence (proto_db fence,
_check_healthy): any other error escaping either actor fences the node for the life of the
process; the acceptor reads the fence from its Atom before each step, so an event queued before
a dispatcher fence is never granted nor acknowledged. The first reason is kept in an Atom; the node and acceptor
states take it (PBNodeState #fenced, PBAcceptorState withFenced:), so the acceptor refuses
every grant, renewal and release (it sends nothing for them) and answers a replication with
ack(ok = false); the dispatcher performs nothing more but that lane, and every waiter is
settled: a permit, base or later commit gets PBUnexpectedError naming the cause ('Node n is
fenced after an internal failure: ...'), a replication in flight #unknown (its root may have
left the node).

The tier (Task 21's PBSharedTier, or a test double) answers storage (the identity attach: and
detach: compare, proto_db _attach_locked), loadRoots (a PBLoggedRoots),
logAccepted: and logCommitted: (a PBLabeledRoot), logPromise: (a term), logRejoined,
readPersisted (a PBLabeledRoot or nil) and canRead: (a PBLabeledRoot). Every call is made on the
acceptor actor, which owns the log (PBAcceptorLog is not serialised). _attach: builds a fresh
PBLoggedRoots from loadRoots at every attach, even over the same disk (review N4), and refuses a
startupGrace below leaseDuration + driftMargin over a log that is not empty (L17, proto_db
_attach_locked); _detach hands the dispatcher PBLogDetached naming the log detached (m10).

This module is a shell: it reads the monotonic clock (Time microsecondClockValue, or the
#clock option, a block answering microseconds) and uses Future after: for the timers. The
incarnation is drawn at start from ByteArray randomBytes: 8, masked to 62 bits (the #seed
option seeds a Random instead, for tests).

Every value here is immutable: the coordinator and its actors keep their state in Atoms created
by their initialisers."

Import from: 'net'.
Import from: 'protobase/errors'.
Import from: 'protobase/cluster/members'.
Import from: 'protobase/cluster/rootlog'.
Import from: 'protobase/cluster/protocol'.
Import from: 'protobase/cluster/config'.
Import from: 'protobase/cluster/transport'.
Import from: 'protobase/cluster/lease'.
Import from: 'protobase/cluster/core'.
Import from: 'protobase/cluster/acceptor'.
Import from: 'protobase/cluster/proposer'.
Import from: 'protobase/cluster/owner'.
Import from: 'protobase/cluster/holder'.
Import from: 'protobase/cluster/rejoin'.

"=== _PBNodeCells: the shared cells of one node ============================="

Object subclass: #_PBNodeCells instanceVariableNames: 'config node acceptorState committed counters fence stopped waiters dispatcher acceptor transport dispatchMax tokens critical'.

"The names of the counters stats always reports (0 until counted): every PBCount of the rules,
 and messages_ignored, the shell's."
_PBNodeCells class >> statNames
  ^ #('accepted' 'acquired' 'attempts' 'config_mismatches' 'deferrals' 'deferral_timeouts' 'dispatch_slow' 'grants_given'
      'grants_refused_no_storage' 'lost_attempts' 'messages_ignored' 'ownerships' 'permit_requests_retried'
      'permit_requests_sent' 'permits_foreign_dropped' 'permits_held' 'permits_issued' 'permits_refused'
      'recoveries' 'refused' 'rejoin_ballots' 'rejoins' 'renewal_failures' 'renewals' 'replication_failures'
      'replications' 'sends_refused_reserve' 'stale_replies' 'storage_root_reads' 'terms_abandoned'
      'terms_fenced' 'terms_released_idle_local' 'turns_named' 'turns_taken' 'critical_commits').

"The stages of a commit's critical section stats reports under 'critical' (summed seconds; the
 commit round counts them, Task 23): the build (validation, merge and path copy, proto_db's
 validation, replay and path_copy together) and the replication."
_PBNodeCells class >> criticalNames
  ^ #('build' 'replication').

_PBNodeCells class >> config: aConfig
  | zero |
  zero := Dictionary new.
  self statNames do: [:name | zero at: name put: 0].
  ^ self basicNew _setConfig: aConfig node: (Atom on: nil) acceptorState: (Atom on: nil) committed: (Atom on: nil)
    counters: (Atom on: zero) fence: (Atom on: nil) stopped: (Atom on: false) waiters: (Atom on: Dictionary new)
    dispatcher: (Atom on: nil) acceptor: (Atom on: nil) transport: (Atom on: nil) dispatchMax: (Atom on: 0)
    tokens: (Atom on: 0) critical: (Atom on: (self criticalNames collect: [:k | 0])).

_PBNodeCells >> _setConfig: aConfig node: aNode acceptorState: anAcceptorState committed: aCommitted counters: aCounters fence: aFence stopped: aStopped waiters: aWaiters dispatcher: aDispatcher acceptor: anAcceptor transport: aTransport dispatchMax: aMax tokens: aTokens critical: aCritical
  "Runs once, on a fresh instance."
  config isNil ifFalse: [^ PBUserError signal: '_PBNodeCells is immutable'].
  config := aConfig.
  node := aNode.
  acceptorState := anAcceptorState.
  committed := aCommitted.
  counters := aCounters.
  fence := aFence.
  stopped := aStopped.
  waiters := aWaiters.
  dispatcher := aDispatcher.
  acceptor := anAcceptor.
  transport := aTransport.
  dispatchMax := aMax.
  tokens := aTokens.
  critical := aCritical.
  ^ self.

_PBNodeCells >> config
  ^ config.

"The Atoms: the PBNodeState, the published PBAcceptorState, the committed PBLabeledRoot, the
 counters (a Dictionary), the fence reason (nil: healthy), whether stopped, the waiters (token ->
 { kind. Future }), the actor proxies and the transport, the longest dispatch (microseconds),
 the last waiter token."
_PBNodeCells >> node
  ^ node.

_PBNodeCells >> acceptorState
  ^ acceptorState.

_PBNodeCells >> committed
  ^ committed.

_PBNodeCells >> counters
  ^ counters.

_PBNodeCells >> fence
  ^ fence.

_PBNodeCells >> stopped
  ^ stopped.

_PBNodeCells >> waiters
  ^ waiters.

_PBNodeCells >> dispatcher
  ^ dispatcher.

_PBNodeCells >> acceptor
  ^ acceptor.

_PBNodeCells >> transport
  ^ transport.

_PBNodeCells >> dispatchMax
  ^ dispatchMax.

"The summed microseconds of each stage of criticalNames, an Array in that order."
_PBNodeCells >> critical
  ^ critical.

"A new waiter token: an Integer, never repeated in this coordinator."
_PBNodeCells >> nextToken
  ^ tokens swap: [:n | n + 1].

"The node's clock: microseconds of the monotonic clock, or of the #clock seam."
_PBNodeCells >> now
  ^ config clock isNil ifTrue: [Time microsecondClockValue] ifFalse: [config clock value].

_PBNodeCells >> isStopped
  ^ stopped value.

_PBNodeCells >> isFenced
  ^ fence value notNil.

"Adds one to the counter aName."
_PBNodeCells >> count: aName
  counters swap: [:d | | copy | copy := d copy. copy at: aName put: (d at: aName ifAbsent: [0]) + 1. copy].

"Records aReason as the fence, unless one is kept already; answers whether this call fenced."
_PBNodeCells >> fenceFor: aReason
  ^ fence value: aReason ifCurrent: nil.

"The text of anError for a reason (its class and message, as proto_db repr)."
_PBNodeCells >> describe: anError
  ^ anError class name , ': ' , (anError messageText ifNil: ['(no message)']).

_PBNodeCells >> fencedText
  ^ 'Node ' , config nodeId , ' is fenced after an internal failure: ' , fence value.

_PBNodeCells >> fencedError
  ^ PBUnexpectedError new messageText: self fencedText; yourself.

_PBNodeCells >> closedError
  ^ PBClosedError new messageText: 'Node ' , config nodeId , ' is stopped (or not started)'; yourself.

"The readers' committed root (the committed Atom) after aPublish (a PBPublishCommitted): the
 higher of the two roots in the order of roots (PBRootOrder), so it never goes backwards when an
 older root is published after a newer one (the acceptor's learning after the commit point's
 publish, Task 24); nil drops it (the acceptor forgot its committed root, review I2)."
_PBNodeCells >> publishCommitted: aPublish
  aPublish isDrop ifTrue: [^ committed swap: [:old | nil]].
  ^ committed swap: [:old | PBRootOrder max: old with: aPublish root].

"aString on stderr, prefixed with the node; never signals."
_PBNodeCells >> warn: aString
  [Stdio stderr nextPutAll: 'PBClusterCoordinator ' , config nodeId , ': ' , aString; lf; flush] on: Error do: [:e | nil].

"Registers aFuture of aKind under aToken."
_PBNodeCells >> register: aToken kind: aKind future: aFuture
  waiters swap: [:d | | copy | copy := d copy. copy at: aToken put: { aKind. aFuture }. copy].

"Removes and answers the waiter of aToken ({ kind. Future }), nil when none."
_PBNodeCells >> take: aToken
  | old new entry |
  [old := waiters value.
   entry := old at: aToken ifAbsent: [nil].
   entry isNil ifTrue: [^ nil].
   new := old copy.
   new removeKey: aToken.
   waiters value: new ifCurrent: old] whileFalse.
  ^ entry.

"Removes and answers every waiter, an Array of { kind. Future }."
_PBNodeCells >> takeAll
  | old |
  [old := waiters value.
   waiters value: Dictionary new ifCurrent: old] whileFalse.
  ^ old values asArray.

"Settles every waiter as the node ends (stopped or fenced): a replication in flight #unknown,
 never #none (its root may have left the node, Task 13 review note (g)); the rest rejected with
 anError."
_PBNodeCells >> settleAllWith: anError
  self takeAll do: [:w |
    (w first = #replicate) ifTrue: [(w at: 2) resolve: #unknown].
    (w first = #roundReplicate) ifTrue: [(w at: 2) resolve: (PBOutcomeUnknownError new messageText: 'Node ' , config nodeId
      , ': the node ended while the root was being replicated (' , anError messageText
      , '); it may or may not take effect'; yourself)].
    (#(#replicate #roundReplicate) includes: w first) ifFalse: [(w at: 2) rejectWith: anError]].

"=== _PBDispatcher =========================================================="

Object subclass: #_PBDispatcher instanceVariableNames: 'cells rules'.

_PBDispatcher class >> cells: someCells rules: aRules
  ^ self basicNew _setCells: someCells rules: aRules.

_PBDispatcher >> _setCells: someCells rules: aRules
  "Runs once, on a fresh instance."
  cells isNil ifFalse: [^ PBUserError signal: '_PBDispatcher is immutable'].
  cells := someCells.
  rules := aRules.
  ^ self.

"A message from the transport (its handler only forwards here): a sender that is not another
 member is dropped and counted (proto_db _route: 'ignored a ... message from unknown sender')."
_PBDispatcher >> receive: aMessage
  | config |
  config := cells config.
  (aMessage from ~= config nodeId and: [config membership ids includes: aMessage from]) ifFalse: [
    cells count: 'messages_ignored'.
    ^ false].
  ^ self handle: (PBReceived message: aMessage).

"Registers aFuture of aKind (#permit, #base, #replicate) under aToken, then dispatches the event
 anEventBlock answers for the token and the node state (built here, on the dispatcher: a
 replication's pred is the one the rules bind to its permission at that moment). A stopped node
 rejects it with PBClosedError, a fenced one with PBUnexpectedError naming the cause."
_PBDispatcher >> want: anEventBlock kind: aKind token: aToken future: aFuture
  | event |
  cells isStopped ifTrue: [aFuture rejectWith: cells closedError. ^ false].
  cells isFenced ifTrue: [aFuture rejectWith: cells fencedError. ^ false].
  event := [anEventBlock value: aToken value: cells node value] on: Error do: [:e | aFuture rejectWith: e. nil].
  event isNil ifTrue: [^ false].
  cells register: aToken kind: aKind future: aFuture.
  ^ self _handle: event waiter: aToken.

"Dispatches anEvent, then settles aFuture with true; rejected with PBClosedError once stopped,
 with PBUnexpectedError once fenced, or with the PBDBError the rules signalled for it."
_PBDispatcher >> post: anEvent future: aFuture
  | token |
  cells isStopped ifTrue: [aFuture rejectWith: cells closedError. ^ false].
  cells isFenced ifTrue: [aFuture rejectWith: cells fencedError. ^ false].
  token := cells nextToken.
  cells register: token kind: #post future: aFuture.
  (self _handle: anEvent waiter: token) ifTrue: [(cells take: token) ifNotNil: [:w | (w at: 2) resolve: true]].
  ^ true.

"One event: the rules' step, its state into the Atom, its effects in order."
_PBDispatcher >> handle: anEvent
  ^ self _handle: anEvent waiter: nil.

"handle: (proto_db _on_message, _route). A PBDBError (proto_db's ProtoDBError) the rules'
 decision signals, before anything changed, is written to stderr and the event dropped, the node
 kept; when the event is a local request (aTokenOrNil, its waiter), the waiter is rejected with
 it, as proto_db raises it to its caller. Any other error of the decision, and any error while
 its effects are performed (the state is already published, so state and effects would
 diverge), fences the node: a replication in flight then settles #unknown (H7). Answers whether
 the step was performed."
_PBDispatcher >> _handle: anEvent waiter: aTokenOrNil
  | start step failure |
  cells isStopped ifTrue: [^ false].
  cells isFenced ifTrue: [^ self _handleFenced: anEvent].
  start := Time microsecondClockValue.
  failure := [step := rules dispatch: anEvent in: cells node value now: cells now. nil] on: Error do: [:e | e return: e].
  failure notNil ifTrue: [
    self _noteDispatch: Time microsecondClockValue - start.
    (failure isKindOf: PBDBError) ifFalse: [
      self fence: 'the dispatcher, handling ' , anEvent printString , ': ' , (cells describe: failure).
      ^ false].
    cells warn: 'handling ' , anEvent printString , ' failed: ' , (cells describe: failure).
    aTokenOrNil notNil ifTrue: [(cells take: aTokenOrNil) ifNotNil: [:w | (w at: 2) rejectWith: failure]].
    ^ false].
  cells node swap: [:old | step state].
  failure := [step effects do: [:e | e applyTo: self]. nil] on: Error do: [:e | e return: e].
  self _noteDispatch: Time microsecondClockValue - start.
  failure isNil ifTrue: [^ true].
  self fence: 'the dispatcher, performing the effects of ' , anEvent printString , ': ' , (cells describe: failure).
  ^ false.

"The longest step, and the steps over 10 ms counted dispatch_slow (proto_db DISPATCH_SLOW)."
_PBDispatcher >> _noteDispatch: someMicros
  cells dispatchMax swap: [:m | m max: someMicros].
  someMicros > 10000 ifTrue: [cells count: 'dispatch_slow'].

"A fenced node sends nothing (proto_db _enqueue, _refuse_queued): only a peer's replicate,
 store or query reaches the fenced acceptor, which acknowledges a replication with ok = false
 and answers a plain query; every other event is dropped."
_PBDispatcher >> _handleFenced: anEvent
  | m |
  (anEvent isKindOf: PBReceived) ifFalse: [^ false].
  m := anEvent message.
  (#('replicate' 'store' 'query') includes: m type) ifFalse: [^ false].
  cells acceptor value handle: anEvent.
  ^ true.

"The node is fenced for aReason (the first kept): its state and its acceptor's take the fence,
 and every waiter is settled."
_PBDispatcher >> fence: aReason
  (cells fenceFor: aReason) ifTrue: [cells warn: 'fenced after an internal failure: ' , aReason].
  cells node swap: [:s | s fenced isNil ifTrue: [s with: { #fenced -> cells fence value }] ifFalse: [s]].
  cells acceptor value fence: cells fence value.
  cells settleAllWith: cells fencedError.
  ^ true.

"stop: every waiter settled (a replication #unknown, the rest PBClosedError)."
_PBDispatcher >> stopNode
  cells settleAllWith: cells closedError.
  ^ true.

"--- the effects ---"

_PBDispatcher >> applySend: aSend
  cells transport value send: aSend message to: aSend to.

_PBDispatcher >> applyToAcceptor: aToAcceptor
  cells acceptor value handle: aToAcceptor event.

"The timer's microseconds rounded up to milliseconds (never early); the PBTimerFired comes back
 as an event of this actor."
_PBDispatcher >> applyTimer: aTimer
  | ms proxy fired |
  ms := aTimer after + 999 // 1000 max: 0.
  proxy := cells dispatcher value.
  fired := aTimer fired.
  (Future after: ms) thenDo: [:x | proxy handle: fired].

"The waiter's Future: a replication's PBOutcomeUnknownError is #unknown (the commit round's,
 #roundReplicate, keeps the error itself as the value, its text the case's); another Exception
 rejects it; any other outcome resolves it. A waiter this shell did not register (or settled
 already) is ignored."
_PBDispatcher >> applySettle: aSettle
  | w outcome |
  w := cells take: aSettle waiter.
  w isNil ifTrue: [^ self].
  outcome := aSettle outcome.
  (w first = #replicate and: [outcome isKindOf: PBOutcomeUnknownError]) ifTrue: [^ (w at: 2) resolve: #unknown].
  (w first = #roundReplicate and: [outcome isKindOf: PBOutcomeUnknownError]) ifTrue: [^ (w at: 2) resolve: outcome].
  (outcome isKindOf: Exception) ifTrue: [^ (w at: 2) rejectWith: outcome].
  (w at: 2) resolve: outcome.

_PBDispatcher >> applyPublishCommitted: aPublish
  cells publishCommitted: aPublish.

_PBDispatcher >> applyPublishAcceptor: aPublish
  ^ self.

_PBDispatcher >> applyFence: aFence
  self fence: aFence reason.

_PBDispatcher >> applyCount: aCount
  cells count: aCount stat.

_PBDispatcher >> applyReadPersisted: aRead
  cells acceptor value readPersisted: aRead token.

_PBDispatcher >> applyProbeRoot: aProbe
  cells acceptor value probe: aProbe root token: aProbe token.

"=== _PBAcceptor ============================================================"

Object subclass: #_PBAcceptor instanceVariableNames: 'cells rules tier'.

_PBAcceptor class >> cells: someCells rules: aRules
  ^ self basicNew _setCells: someCells rules: aRules tier: (Atom on: nil).

_PBAcceptor >> _setCells: someCells rules: aRules tier: aTierAtom
  "Runs once, on a fresh instance."
  cells isNil ifFalse: [^ PBUserError signal: '_PBAcceptor is immutable'].
  cells := someCells.
  rules := aRules.
  tier := aTierAtom.
  ^ self.

"One acceptor event (proto_db _work). The fence is read from the shared Atom first: a fence the
 dispatcher raised while this event was queued is adopted before anything is decided, so a
 fenced node never grants nor acknowledges (proto_db _refusal reads _failure at decision time).
 A PBDBError the rules' decision signals (proto_db's ProtoDBError) is written to stderr and the
 message dropped, the node kept; for this node's own request or replicate the dispatcher is
 handed PBOwnStepFailed with the error at once, so the waiter behind it is settled now, as
 proto_db raises it to the caller of permit() or replicate(). Any other error of the decision,
 and any error after it (the appends aside, which fail the tier: _append:), fences the node."
_PBAcceptor >> handle: anEvent
  | failure step |
  cells isStopped ifTrue: [^ false].
  cells isFenced ifTrue: [self fence: cells fence value].
  failure := [step := rules accept: anEvent in: cells acceptorState value now: cells now. nil] on: Error do: [:e | e return: e].
  failure notNil ifTrue: [
    (failure isKindOf: PBDBError) ifFalse: [
      self _fault: 'the acceptor, handling ' , anEvent printString , ': ' , (cells describe: failure).
      ^ false].
    cells warn: 'the acceptor, handling ' , anEvent printString , ', failed: ' , (cells describe: failure).
    ((anEvent isKindOf: PBReceived) and: [anEvent message from = cells config nodeId]) ifTrue: [
      cells dispatcher value handle: (PBOwnStepFailed message: anEvent message error: failure)].
    ^ false].
  failure := [self _perform: step of: anEvent. nil] on: Error do: [:e | e return: e].
  failure isNil ifTrue: [^ true].
  self _fault: 'the acceptor, performing the step of ' , anEvent printString , ': ' , (cells describe: failure).
  ^ false.

"The atomic acceptor step (CC2): the appends in order, then the state published, then the
 reply, then the step to the dispatcher. A failed append discards the step."
_PBAcceptor >> _step: anEvent
  ^ self _perform: (rules accept: anEvent in: cells acceptorState value now: cells now) of: anEvent.

"The step decided for anEvent performed: the appends, the state, the reply, the report."
_PBAcceptor >> _perform: step of: anEvent
  | failure |
  failure := self _writeAll: step appends.
  failure notNil ifTrue: [^ self _discard: step of: anEvent reason: failure].
  cells acceptorState swap: [:old | step state].
  step reply do: [:e | e applyTo: self].
  cells dispatcher value handle: (PBAcceptorDecided step: step).

"The appends of a step, in order: nil once all are written, else the reason of the first
 that failed (the rest are not written)."
_PBAcceptor >> _writeAll: someAppends
  someAppends do: [:a | | failure |
    failure := self _append: a.
    failure notNil ifTrue: [^ failure]].
  ^ nil.

"Writes anAppend through the tier: nil, or the reason a tier write failed (a PBDBError or a
 FileSystemError: proto_db ProtoDBError or OSError). Any other error is not the tier's: it
 escapes, and fences the node."
_PBAcceptor >> _append: anAppend
  | t |
  t := tier value.
  "The rules append nothing with no log attached (acceptor.st); were one asked, nil's
   doesNotUnderstand: would escape and fence the node."
  ^ [self _write: anAppend on: t. nil] on: Error do: [:e |
    ((e isKindOf: PBDBError) or: [e isKindOf: FileSystemError])
      ifTrue: [e return: (cells describe: e)]
      ifFalse: [e pass]].

_PBAcceptor >> _write: anAppend on: aTier
  | kind |
  kind := anAppend kind.
  kind = #accepted ifTrue: [^ aTier logAccepted: (PBLabeledRoot label: anAppend label record: anAppend root)].
  kind = #committed ifTrue: [^ aTier logCommitted: (PBLabeledRoot label: anAppend label record: anAppend root)].
  kind = #promise ifTrue: [^ aTier logPromise: anAppend label].
  kind = #rejoined ifTrue: [^ aTier logRejoined].
  ^ PBUnexpectedError signal: 'an acceptor append of an unknown kind ' , kind printString.

"A step of anEvent whose append failed: discarded (the state before it kept, none of its
 reply), the dispatcher told (PBAcceptorDiscarded) and the acceptor's tier failed
 (PBAppendFailed). Both carry aReason, the one value (review m: the reason the dispatcher reports
 and the tier failure the acceptor keeps never differ). A peer's replication or store is then
 decided again over the failed tier, which refuses it: ack(ok = false), counted refused (proto_db
 _accept_replicate after _tier_failed: 'the replication is refused, never acknowledged'). A
 grant whose promise failed stays unanswered (proto_db _on_request), and this node's own
 acceptance is withdrawn by the dispatcher (PBAcceptorDiscarded)."
_PBAcceptor >> _discard: aStep of: anEvent reason: aReason
  cells warn: 'an acceptor log write failed, the tier fails: ' , aReason.
  cells dispatcher value handle: (PBAcceptorDiscarded step: aStep reason: aReason).
  self _step: (PBAppendFailed reason: aReason).
  ((anEvent isKindOf: PBReceived) and: [(#('replicate' 'store') includes: anEvent message type)
      and: [anEvent message from ~= cells config nodeId]]) ifTrue: [self _step: anEvent].

"An error escaped the acceptor: the node is fenced."
_PBAcceptor >> _fault: aReason
  cells fenceFor: aReason.
  self fence: cells fence value.
  cells dispatcher value fence: cells fence value.

"The acceptor state takes the fence (the first reason kept) and is published."
_PBAcceptor >> fence: aReason
  cells acceptorState swap: [:s | s withFenced: aReason].
  ^ true.

"Attaches aTier (proto_db attach, _attach_locked): a fresh PBLoggedRoots from its loadRoots (N4),
 the startupGrace check (L17), the acceptor state attached (carry-over (b)), then the start
 step over that log (the rejoined marker of a learner or lone voter, the committed root
 published), reported to the dispatcher. The tier attached already: true at once (a no-op);
 another while one is attached: PBValidationError, before its roots are loaded."
_PBAcceptor >> attach: aTier
  | loaded logged config restart current |
  cells isStopped ifTrue: [^ cells closedError signal].
  "proto_db _attach_locked 1081-1084, before load_roots: the tier attached already, or a tier
   over the same storage object (tier storage), is a no-op; another is refused."
  current := tier value.
  current notNil ifTrue: [
    (current == aTier or: [current storage == aTier storage]) ifTrue: [^ true].
    ^ PBValidationError signal: 'This coordinator already serves another storage'].
  config := cells config.
  loaded := aTier loadRoots.
  logged := PBLoggedRoots accepted: loaded accepted committed: loaded committed promise: loaded promise top: loaded top
    rejoined: loaded isRejoined dataEntryCount: loaded dataEntryCount entries: loaded entries.
  restart := config leaseDuration + config driftMargin.
  (logged isRejoined and: [config startupGrace < restart and: [config membership ids size > 1]]) ifTrue: [
    ^ PBValidationError signal: 'Node ' , config nodeId , ': startupGrace=' , (config startupGrace / 1000) printString
      , ' ms is accepted only on a cluster''s first start; this node''s acceptor log shows it has served the cluster before, so it may have granted a lease that is still running. Start it with a startupGrace of at least leaseDuration + driftMargin = '
      , (restart / 1000) printString , ' ms (the default)'].
  cells acceptorState swap: [:s | s attached: logged].
  tier value: aTier ifCurrent: nil.
  self handle: PBStartNode new.
  ^ true.

"Detaches the tier (proto_db detach): the acceptor state detached, the dispatcher handed
 PBLogDetached naming the log detached (m10), then the detached state. Answers the tier
 detached, nil when none was attached; the caller closes it."
_PBAcceptor >> detach
  | t old detached |
  t := tier value.
  t isNil ifTrue: [^ nil].
  old := cells acceptorState value.
  detached := old detached.
  tier value: nil ifCurrent: t.
  cells acceptorState swap: [:s | detached].
  cells dispatcher value handle: (PBLogDetached log: old log).
  cells dispatcher value handle: (PBAcceptorDecided step: (PBAcceptorStep state: detached appends: #() reply: #())).
  ^ t.

"Detaches aTier (proto_db detach(tier)): only when it is the tier attached, or a tier over the
 same storage object (the identity rule of attach:); else nothing is detached and the answer is
 nil."
_PBAcceptor >> detach: aTier
  | t |
  t := tier value.
  (t notNil and: [t == aTier or: [t storage == aTier storage]]) ifFalse: [^ nil].
  ^ self detach.

"The persisted root, read on the tier for the dispatcher (PBStorageRead)."
_PBAcceptor >> readPersisted: aToken
  | t root failure |
  t := tier value.
  root := nil.
  failure := nil.
  t isNil
    ifTrue: [failure := PBClosedError new messageText: 'Node ' , cells config nodeId , ' has no tier attached'; yourself]
    ifFalse: [[root := t readPersisted] on: Error do: [:e | failure := e]].
  cells dispatcher value handle: (PBStorageRead token: aToken root: root failure: failure).

"Whether aRoot is readable on the tier, for the dispatcher (PBRootProbed)."
_PBAcceptor >> probe: aRoot token: aToken
  | t readable |
  t := tier value.
  readable := t notNil and: [[t canRead: aRoot] on: Error do: [:e | false]].
  cells dispatcher value handle: (PBRootProbed token: aToken readable: readable).

"Answers once the acceptor step in progress has run (mailbox order): an acceptance being logged
 finishes before stop answers; the steps queued behind it are dropped (handle: once stopped)."
_PBAcceptor >> finish
  ^ true.

"--- the reply effects ---"

_PBAcceptor >> applySend: aSend
  cells transport value send: aSend message to: aSend to.

_PBAcceptor >> applyCount: aCount
  cells count: aCount stat.

_PBAcceptor >> applyPublishCommitted: aPublish
  cells publishCommitted: aPublish.

"The state is published before the reply (_step:)."
_PBAcceptor >> applyPublishAcceptor: aPublish
  ^ self.

_PBAcceptor >> applyFence: aFence
  self _fault: aFence reason.

_PBAcceptor >> applyToAcceptor: anEffect
  ^ PBUnexpectedError signal: 'an acceptor step answered ' , anEffect printString.

_PBAcceptor >> applyTimer: anEffect
  ^ PBUnexpectedError signal: 'an acceptor step answered ' , anEffect printString.

_PBAcceptor >> applySettle: anEffect
  ^ PBUnexpectedError signal: 'an acceptor step answered ' , anEffect printString.

"=== PBClusterCoordinator ==================================================="

Object subclass: #PBClusterCoordinator instanceVariableNames: 'config rules acceptorClass cells run'.

"The member anId of the cluster anArrayOfPBPeer with aDictionary's options (PBClusterConfig)."
PBClusterCoordinator class >> nodeId: anId peers: anArrayOfPBPeer options: aDictionary
  ^ self nodeId: anId peers: anArrayOfPBPeer options: aDictionary rules: PBCoordinatorCore new acceptorClass: _PBAcceptor.

"The test seam: other rules (a subclass of PBCoordinatorCore) and acceptor actor class (a
 subclass of _PBAcceptor)."
PBClusterCoordinator class >> nodeId: anId peers: anArrayOfPBPeer options: aDictionary rules: aRules acceptorClass: aClass
  | config |
  config := PBClusterConfig nodeId: anId peers: anArrayOfPBPeer options: aDictionary.
  ^ self basicNew _setConfig: config rules: aRules acceptorClass: aClass cells: (_PBNodeCells config: config) run: (Atom on: nil).

PBClusterCoordinator >> _setConfig: aConfig rules: aRules acceptorClass: aClass cells: someCells run: aRunAtom
  "Runs once, on a fresh instance."
  config isNil ifFalse: [^ PBUserError signal: 'PBClusterCoordinator is immutable'].
  config := aConfig.
  rules := aRules.
  acceptorClass := aClass.
  cells := someCells.
  run := aRunAtom.
  ^ self.

PBClusterCoordinator >> config
  ^ config.

PBClusterCoordinator >> nodeId
  ^ config nodeId.

"An incarnation in [0, 2^62): from the #seed option's Random, else 8 secure random bytes."
PBClusterCoordinator >> _drawInc
  | n |
  config seed notNil ifTrue: [^ ((Random seed: config seed) nextInt: 1073741823) - 1].
  n := (ByteArray randomBytes: 8) inject: 0 into: [:acc :b | acc * 256 + b].
  ^ n bitAnd: (1 bitShift: 62) - 1.

"Starts the node (proto_db start): the actors, the transport, the node with no acceptor log.
 Answers self. PBUserError when started before or stopped."
PBClusterCoordinator >> start
  | dispatcher acceptor transport now proxy |
  (run value: #starting ifCurrent: nil) ifFalse: [
    ^ PBUserError signal: 'Node ' , config nodeId , ' was started before (a stopped coordinator is not restarted)'].
  now := cells now.
  cells node swap: [:old | PBNodeState config: config inc: self _drawInc].
  cells acceptorState swap: [:old | PBAcceptorState config: config detachedAt: now].
  dispatcher := (_PBDispatcher cells: cells rules: rules) asHighPriorityActor.
  acceptor := (acceptorClass cells: cells rules: rules) asHighPriorityActor.
  cells dispatcher swap: [:old | dispatcher].
  cells acceptor swap: [:old | acceptor].
  transport := config transport ifNil: [
    PBTcpTransport listenOn: (config membership peerNamed: config nodeId) port
      host: (config membership peerNamed: config nodeId) host requestTimeout: config requestTimeout // 1000].
  cells transport swap: [:old | transport].
  proxy := dispatcher.
  "The handler only forwards (Task 19 (a), (f)): a send to an actor proxy enqueues and answers a
   Future, and never signals; the dispatcher keeps each connection's order."
  transport start: config nodeId peers: config membership key: config authKey handler: [:m | proxy receive: m].
  run value: #running ifCurrent: #starting.
  dispatcher handle: PBStartNode new.
  ^ self.

PBClusterCoordinator >> isRunning
  ^ run value = #running and: [cells isStopped not].

"Stops the node (proto_db stop): every pending Future settled (a replication in flight #unknown,
 the rest PBClosedError), the acceptor step in progress finished (the steps queued behind the
 stop are dropped, as proto_db's lanes return once not running), then the transport stopped. Answers a Future that resolves (with true) once all that is done;
 idempotent. Never waits."
PBClusterCoordinator >> stop
  | current done d a |
  [current := run value.
   (current isKindOf: Future) ifTrue: [^ current].
   done := Future new.
   run value: done ifCurrent: current] whileFalse.
  cells stopped swap: [:old | true].
  current = #running ifFalse: [done resolve: true. ^ done].
  d := cells dispatcher value stopNode.
  a := cells acceptor value finish.
  (PBClusterTransport _allSettled: { d. a }) thenDo: [:x |
    (PBClusterTransport _settled: cells transport value stop) thenDo: [:y | done resolve: true]].
  ^ done.

"--- the tier ---"

"Attaches aTier (Task 21's PBSharedTier, or a test double): a Future that resolves with true (also
 for the tier attached already, a no-op), or is rejected (PBValidationError for another tier
 while one is attached, or for a startupGrace below leaseDuration + driftMargin over a log that
 is not empty, L17; PBClosedError when not running)."
PBClusterCoordinator >> _attach: aTier
  | f |
  self isRunning ifFalse: [f := Future new. f rejectWith: cells closedError. ^ f].
  ^ cells acceptor value attach: aTier.

"Detaches the tier: a Future of the tier detached (nil when none was)."
PBClusterCoordinator >> _detach
  | f |
  self isRunning ifFalse: [f := Future new. f resolve: nil. ^ f].
  ^ cells acceptor value detach.

"Detaches aTier (proto_db detach(tier), what PBObjectSpace close calls): a Future of the tier
 detached, nil when aTier (or a tier over its storage) was not the one attached. On a node that
 is stopping, the Future resolves with nil once the stop has settled, so the acceptor step in
 progress has finished before the caller closes the tier's log (proto_db detach takes _log_lock);
 it is chained on stop's Future, never waited. Before start, nil at once. A nil tier is
 PBValidationError, before anything is sent (in the acceptor it would fence the node)."
PBClusterCoordinator >> _detach: aTier
  | f current |
  aTier isNil ifTrue: [^ PBValidationError signal: 'Node ' , config nodeId , ': _detach: takes the tier to detach, not nil'].
  self isRunning ifTrue: [^ cells acceptor value detach: aTier].
  f := Future new.
  current := run value.
  (current isKindOf: Future)
    ifTrue: [(PBClusterTransport _settled: current) thenDo: [:x | f resolve: nil]]
    ifFalse: [f resolve: nil].
  ^ f.

"--- the operator ---"

"proto_db force_rejoin (PBRejoinWanted)."
PBClusterCoordinator >> forceRejoin
  self isRunning ifFalse: [^ PBClosedError signal: 'Node ' , config nodeId , ' is not running'].
  cells dispatcher value handle: PBRejoinWanted new.
  ^ self.

"--- the round runner's interface: Futures, never a wait ---"

PBClusterCoordinator >> _want: aBlock kind: aKind
  | f token |
  f := Future new.
  self isRunning ifFalse: [f rejectWith: cells closedError. ^ f].
  token := cells nextToken.
  cells dispatcher value want: aBlock kind: aKind token: token future: f.
  ^ f.

"A write permission: a Future of a PBPermission, rejected with PBTimeoutError (acquireTimeout),
 PBUnexpectedError (fenced) or PBClosedError (stopped)."
PBClusterCoordinator >> _permit
  ^ self _want: [:token :s | PBPermitWanted waiter: token] kind: #permit.

"The base of a commit under aPermission: a Future of a PBBaseDecision."
PBClusterCoordinator >> _baseFor: aPermission
  ^ self _want: [:token :s | PBBaseWanted permission: aPermission waiter: token] kind: #base.

"Replicates aLabeledRoot under aPermission on the pred the rules bind to it (predFor:in:): a
 Future of #committed, #none or #unknown."
PBClusterCoordinator >> _replicate: aLabeledRoot under: aPermission
  | core |
  core := rules.
  ^ self _want: [:token :s | PBReplicateWanted permission: aPermission root: aLabeledRoot
      pred: (core predFor: aPermission in: s) waiter: token] kind: #replicate.

"As _replicate:under:, for the commit round (cluster/round.st): a Future of #committed, #none or
 the PBOutcomeUnknownError itself (its text proto_db's for the case; also when the node ends with
 the replication in flight), never #unknown; rejected as _replicate:under: is (a protocol
 violation, a root not built for the permission, fenced, stopped)."
PBClusterCoordinator >> _replicateRound: aLabeledRoot under: aPermission
  | core |
  core := rules.
  ^ self _want: [:token :s | PBReplicateWanted permission: aPermission root: aLabeledRoot
      pred: (core predFor: aPermission in: s) waiter: token] kind: #roundReplicate.

"--- the commit round's reads (cluster/round.st) ---"

"The rules (a PBCoordinatorCore): the commit round runs round:in:now: of the same core."
PBClusterCoordinator >> _rules
  ^ rules.

"The node's clock (microseconds; the #clock option's when set): the round's now."
PBClusterCoordinator >> _now
  ^ cells now.

"Adds one to the counter aName (a PBCount of the round)."
PBClusterCoordinator >> _count: aName
  cells count: aName.

"One commit's critical section (proto_db record_critical): counted critical_commits, its build
 and replication microseconds added to stats' 'critical'."
PBClusterCoordinator >> _recordCritical: buildMicros replication: replicationMicros
  cells count: 'critical_commits'.
  cells critical swap: [:old | { (old at: 1) + buildMicros. (old at: 2) + replicationMicros }].

"Ends aPermission with anOutcome (#committed, #unknown or #none): a Future resolved once
 dispatched."
PBClusterCoordinator >> _done: aPermission outcome: aSymbol
  ^ self _done: aPermission outcome: aSymbol root: nil.

PBClusterCoordinator >> _done: aPermission outcome: aSymbol root: aRootOrNil
  ^ self _post: [PBDoneReport permission: aPermission outcome: aSymbol root: aRootOrNil].

"The space starts its confirmation round (proto_db confirmed())."
PBClusterCoordinator >> _confirmed
  ^ self _post: [PBConfirmed new].

"A Future resolved with true once the event anEventBlock builds is dispatched; rejected with the
 error building it signals, PBClosedError when not running (also when it races the stop), or
 PBUnexpectedError when fenced."
PBClusterCoordinator >> _post: anEventBlock
  | f event |
  f := Future new.
  self isRunning ifFalse: [f rejectWith: cells closedError. ^ f].
  event := [anEventBlock value] on: Error do: [:e | f rejectWith: e. e return: nil].
  event isNil ifTrue: [^ f].
  cells dispatcher value post: event future: f.
  ^ f.

"--- what readers see ---"

"The newest committed root this node knows (a PBLabeledRoot), nil when none: what a snapshot of
 the node's space starts from (proto_db known_root). It never goes backwards, but for forceRejoin
 on a survivor, which drops a root lost with the other logs (nil until the node learns another)."
PBClusterCoordinator >> committedRoot
  ^ cells committed value.

"The commit round's commit point (cluster/round.st): aLabeledRoot, just committed by this node,
 is published to the readers before the commit settles, so a commit reads its own write; the
 acceptor learns it later (PBLearnCommitted), and publishing it then changes nothing."
PBClusterCoordinator >> _publishCommitted: aLabeledRoot
  cells publishCommitted: (PBPublishCommitted root: aLabeledRoot).

"The space read the persisted root aLabeledRoot because this node knows no committed root
 (proto_db current_root's storage read): counted storage_root_reads, and published to the readers
 as committed (it is: only committed roots are persisted), so later reads never go below it."
PBClusterCoordinator >> _observePersisted: aLabeledRoot
  cells count: 'storage_root_reads'.
  aLabeledRoot isNil ifFalse: [self _publishCommitted: aLabeledRoot].

"The epoch of committedRoot, 0 when none."
PBClusterCoordinator >> committedEpoch
  | root |
  root := cells committed value.
  ^ root isNil ifTrue: [0] ifFalse: [root epoch].

PBClusterCoordinator >> needsConfirmation
  | s |
  s := cells acceptorState value.
  ^ s isNil or: [s needsConfirmation].

PBClusterCoordinator >> isFenced
  ^ cells isFenced.

"The published acceptor state, nil before start (for tests and diagnostics)."
PBClusterCoordinator >> acceptorState
  ^ cells acceptorState value.

"The dispatcher's state, nil before start."
PBClusterCoordinator >> nodeState
  ^ cells node value.

"The counters (CC24) and the health of the node (proto_db stats): healthy, fenced, tier_failed,
 persisting, rejoining, rejoin_blocked, failure, dispatch_seconds_max; critical_commits and
 critical (a Dictionary of summed seconds, 'build' and 'replication', criticalNames). A fresh
 Dictionary."
PBClusterCoordinator >> stats
  | d s v failure rejoining |
  d := cells counters value copy.
  s := cells node value.
  v := cells acceptorState value.
  failure := cells fence value ifNil: [v isNil ifTrue: [nil] ifFalse: [v tierFailed]].
  rejoining := v notNil and: [v isAttached and: [v isRejoined not and: [failure isNil]]].
  d at: 'healthy' put: failure isNil;
    at: 'fenced' put: cells isFenced;
    at: 'tier_failed' put: (v notNil and: [v tierFailed notNil]);
    at: 'persisting' put: true;
    at: 'rejoining' put: rejoining;
    at: 'rejoin_blocked' put: ((rejoining and: [s notNil]) ifTrue: [rules rejoinBlockedIn: s] ifFalse: [nil]);
    at: 'failure' put: failure;
    at: 'dispatch_seconds_max' put: cells dispatchMax value / 1000000.0.
  d at: 'critical' put: (Dictionary new
    at: 'build' put: (cells critical value at: 1) / 1000000.0;
    at: 'replication' put: (cells critical value at: 2) / 1000000.0; yourself).
  ^ d.

PBClusterCoordinator >> printOn: aStream
  aStream nextPutAll: 'PBClusterCoordinator('; nextPutAll: config nodeId; nextPut: $).
