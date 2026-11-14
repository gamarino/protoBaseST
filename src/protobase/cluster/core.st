"-- cluster/core.st: the vocabulary of the coordinator core: events, effects, steps, states --

The sans-IO core of proto_db's ClusterCoordinator (cluster/coordinator.py, the logic of
_route, _on_message and the acceptor lane, D50 'Message lanes'), as the plan's architecture
states it: one stateless rules object, PBCoordinatorCore, answers for an event, a state value
and a time now (an Integer of microseconds of the node's monotonic clock, PBClusterConfig's
unit, CC3) a step: the new state value and the effects a shell performs. Nothing here reads a
clock, a socket or a file, sends, logs or waits.

  Events (PBCoreEvent): PBReceived message: (a PBClusterMessage that arrived), PBTimerFired
    token: event: (a PBTimer came due), PBStartNode, PBStopNode, PBPermitWanted waiter: (a
    local commit wants a write permission), PBBaseWanted permission: waiter: (the base of a
    commit under a permission), PBReplicateWanted permission: root: waiter: (replicate a built
    root), PBDoneReport permission: outcome: (the outcome a holder reports, #committed,
    #unknown or #none: proto_db's done outcomes), PBRejoinWanted (the operator's forceRejoin)
    and PBAcceptorDecided step: (an acceptor step whose appends are durable, handed back to the
    dispatcher: the reply to this node's own vote and acceptance travels this way, CC1).
  Effects (PBEffect): PBSend to: message:, PBToAcceptor event: (an event for this node's own
    acceptor, never through the transport: CC1), PBLogAppend kind: label: root: sync: (an
    acceptor-log entry: only in the appends of an acceptor step), PBTimer after: token: event:
    (a PBTimerFired token: event: after that many microseconds of the node's clock; the token
    names one timer and the rules ignore a fired timer whose token is no longer the current
    one, so a shell never cancels), PBSettle waiter: outcome:, PBPublishCommitted root: (the
    committed root readers see), PBPublishAcceptor state: (the acceptor's snapshot, CC2) and
    PBFence reason: (the node is fenced for the life of the process). An effect answers
    applyTo: aShell, which sends aShell the one message of its kind (applySend:,
    applyToAcceptor:, applyTimer:, applySettle:, applyPublishCommitted:,
    applyPublishAcceptor:, applyFence:); a PBLogAppend is written by the acceptor shell from
    its step, never applied.
  PBStep           state: effects: (the answer of dispatch:in:now:). A PBLogAppend among its
                   effects is PBValidationError: only the acceptor writes its log.
  PBAcceptorStep   state: appends: reply: (the answer of accept:in:now:): the shell writes the
                   appends in order, syncs, and only once every append that asks for a sync is
                   durable performs the reply effects (atomic acceptor steps, R55, R81, R81b),
                   then hands the step to the dispatcher (PBAcceptorDecided).
  PBNodeState      the dispatcher's state of one node: config, inc (this incarnation, as
                   proto_db's random _inc), acceptorView (the acceptor state last handed back,
                   for hints only: CC2), hints, proposer, ownership, waiters, suspectTerm,
                   fenced, rejoin, nextRid (proto_db _rids starts at 1).
  PBAcceptorState  the acceptor's state of one node (spec 5.3): config, grants (a PBGrantState:
                   promises are durable acceptor state, CC2), accepted and committed (a
                   PBLabeledRoot or nil), seqSeen ({ term. seq } of the highest permission
                   accepted), suspectTerm, rejoined (the log holds the rejoined marker),
                   rejoinBallot, tierFailed and fenced.
  PBCoordinatorCore  dispatch: anEvent in: aNodeState now: t and accept: anEvent in:
                   anAcceptorState now: t. The event picks its rule method by double dispatch
                   (dispatchWith:in:now:, acceptWith:in:now:), one per event class, never by
                   doesNotUnderstand:. A rule method this module defines answers the state
                   unchanged with no effect: the rules of each concern are the methods of
                   acceptor.st, proposer.st, owner.st, holder.st and rejoin.st, and a planted
                   defect is a test subclass overriding one of them (CC13).

Every value here is immutable: built once by its class-side constructor; a 'with' answers a new
value."

Import from: 'protobase/errors'.
Import from: 'protobase/framing'.
Import from: 'protobase/cluster/members'.
Import from: 'protobase/cluster/rootlog'.
Import from: 'protobase/cluster/protocol'.
Import from: 'protobase/cluster/config'.
Import from: 'protobase/cluster/lease'.

"=== PBCoreValue: the text of the core's values ==============================="

Object subclass: #PBCoreValue.

"A short text of aValue for a trace or a log line: a message by its type and sender, a root by
 label, epoch and offset, a permission by term, seq and owner, anything else by printString."
PBCoreValue class >> textOf: aValue
  aValue isNil ifTrue: [^ 'nil'].
  (aValue isKindOf: PBClusterMessage) ifTrue: [^ aValue type , ' from ' , aValue from].
  (aValue isKindOf: PBLabeledRoot) ifTrue: [
    ^ 'root ' , aValue label printString , '/' , aValue epoch printString , '@'
      , (aValue record isNil ifTrue: ['empty'] ifFalse: [aValue record offset printString])].
  (aValue isKindOf: PBPermission) ifTrue: [
    ^ 'permission ' , aValue term printString , '#' , aValue seq printString , ' of ' , aValue owner].
  ^ aValue printString.

"A non-nil argument named aName of aClass's constructor, else PBValidationError."
PBCoreValue class >> _present: aValue named: aName
  aValue isNil ifTrue: [^ PBValidationError signal: self name , ': ' , aName , ' is required'].
  ^ aValue.

PBCoreValue >> printOn: aStream
  aStream nextPutAll: self class name.

"=== Events ==================================================================="

PBCoreValue subclass: #PBCoreEvent.

"Sends aCore the dispatcher rule of this event's class."
PBCoreEvent >> dispatchWith: aCore in: aNodeState now: t
  ^ self subclassResponsibility.

"Sends aCore the acceptor rule of this event's class: only a received message and a start reach
 an acceptor; any other event is PBValidationError."
PBCoreEvent >> acceptWith: aCore in: anAcceptorState now: t
  ^ PBValidationError signal: 'An acceptor takes a PBReceived or a PBStartNode, not ' , self printString.

"--- PBReceived ---"

PBCoreEvent subclass: #PBReceived instanceVariableNames: 'message'.

"aMessage, a PBClusterMessage that arrived (a valid frame, PBClusterFrame decode:to:key:)."
PBReceived class >> message: aMessage
  (aMessage isKindOf: PBClusterMessage) ifFalse: [
    ^ PBValidationError signal: 'PBReceived: a message is a PBClusterMessage, not ' , aMessage printString].
  ^ self basicNew _setMessage: aMessage.

PBReceived >> _setMessage: aMessage
  "Runs once, on a fresh instance."
  message isNil ifFalse: [^ PBUserError signal: 'PBReceived is immutable'].
  message := aMessage.
  ^ self.

PBReceived >> message
  ^ message.

PBReceived >> dispatchWith: aCore in: aNodeState now: t
  ^ aCore dispatchReceived: self in: aNodeState now: t.

PBReceived >> acceptWith: aCore in: anAcceptorState now: t
  ^ aCore acceptReceived: self in: anAcceptorState now: t.

PBReceived >> printOn: aStream
  aStream nextPutAll: 'PBReceived('; nextPutAll: (PBCoreValue textOf: message); nextPut: $).

"--- PBTimerFired ---"

PBCoreEvent subclass: #PBTimerFired instanceVariableNames: 'token event'.

"The timer aToken (the token of its PBTimer) came due, carrying anEvent (its PBTimer's event)."
PBTimerFired class >> token: aToken event: anEvent
  ^ self basicNew _setToken: (self _present: aToken named: 'token') event: (self _present: anEvent named: 'event').

PBTimerFired >> _setToken: aToken event: anEvent
  "Runs once, on a fresh instance."
  token isNil ifFalse: [^ PBUserError signal: 'PBTimerFired is immutable'].
  token := aToken.
  event := anEvent.
  ^ self.

PBTimerFired >> token
  ^ token.

PBTimerFired >> event
  ^ event.

PBTimerFired >> dispatchWith: aCore in: aNodeState now: t
  ^ aCore dispatchTimerFired: self in: aNodeState now: t.

PBTimerFired >> printOn: aStream
  aStream nextPutAll: 'PBTimerFired('; nextPutAll: (PBCoreValue textOf: token); nextPutAll: ' ';
    nextPutAll: (PBCoreValue textOf: event); nextPut: $).

"--- PBStartNode, PBStopNode, PBRejoinWanted ---"

PBCoreEvent subclass: #PBStartNode.

PBStartNode >> dispatchWith: aCore in: aNodeState now: t
  ^ aCore dispatchStartNode: self in: aNodeState now: t.

PBStartNode >> acceptWith: aCore in: anAcceptorState now: t
  ^ aCore acceptStart: self in: anAcceptorState now: t.

PBCoreEvent subclass: #PBStopNode.

PBStopNode >> dispatchWith: aCore in: aNodeState now: t
  ^ aCore dispatchStopNode: self in: aNodeState now: t.

PBCoreEvent subclass: #PBRejoinWanted.

PBRejoinWanted >> dispatchWith: aCore in: aNodeState now: t
  ^ aCore dispatchRejoinWanted: self in: aNodeState now: t.

"--- PBPermitWanted ---"

PBCoreEvent subclass: #PBPermitWanted instanceVariableNames: 'waiter'.

"A local commit wants a write permission; aWaiter is settled (PBSettle) with a PBPermission or
 the error that ends the wait."
PBPermitWanted class >> waiter: aWaiter
  ^ self basicNew _setWaiter: (self _present: aWaiter named: 'waiter').

PBPermitWanted >> _setWaiter: aWaiter
  "Runs once, on a fresh instance."
  waiter isNil ifFalse: [^ PBUserError signal: 'PBPermitWanted is immutable'].
  waiter := aWaiter.
  ^ self.

PBPermitWanted >> waiter
  ^ waiter.

PBPermitWanted >> dispatchWith: aCore in: aNodeState now: t
  ^ aCore dispatchPermitWanted: self in: aNodeState now: t.

PBPermitWanted >> printOn: aStream
  aStream nextPutAll: 'PBPermitWanted('; nextPutAll: (PBCoreValue textOf: waiter); nextPut: $).

"--- PBBaseWanted ---"

PBCoreEvent subclass: #PBBaseWanted instanceVariableNames: 'permission waiter'.

"The base of a commit under aPermission (CP 1.6); aWaiter is settled with the base decision."
PBBaseWanted class >> permission: aPermission waiter: aWaiter
  (aPermission isKindOf: PBPermission) ifFalse: [
    ^ PBValidationError signal: 'PBBaseWanted: a permission is a PBPermission, not ' , aPermission printString].
  ^ self basicNew _setPermission: aPermission waiter: (self _present: aWaiter named: 'waiter').

PBBaseWanted >> _setPermission: aPermission waiter: aWaiter
  "Runs once, on a fresh instance."
  permission isNil ifFalse: [^ PBUserError signal: 'PBBaseWanted is immutable'].
  permission := aPermission.
  waiter := aWaiter.
  ^ self.

PBBaseWanted >> permission
  ^ permission.

PBBaseWanted >> waiter
  ^ waiter.

PBBaseWanted >> dispatchWith: aCore in: aNodeState now: t
  ^ aCore dispatchBaseWanted: self in: aNodeState now: t.

PBBaseWanted >> printOn: aStream
  aStream nextPutAll: 'PBBaseWanted('; nextPutAll: (PBCoreValue textOf: permission); nextPutAll: ', ';
    nextPutAll: (PBCoreValue textOf: waiter); nextPut: $).

"--- PBReplicateWanted ---"

PBCoreEvent subclass: #PBReplicateWanted instanceVariableNames: 'permission root waiter'.

"Replicate aRoot (a PBLabeledRoot, built under aPermission) to the voters (CP 1.7); aWaiter is
 settled with the outcome (#committed, #unknown or #none, H7)."
PBReplicateWanted class >> permission: aPermission root: aRoot waiter: aWaiter
  (aPermission isKindOf: PBPermission) ifFalse: [
    ^ PBValidationError signal: 'PBReplicateWanted: a permission is a PBPermission, not ' , aPermission printString].
  (aRoot isKindOf: PBLabeledRoot) ifFalse: [
    ^ PBValidationError signal: 'PBReplicateWanted: a root is a PBLabeledRoot, not ' , aRoot printString].
  ^ self basicNew _setPermission: aPermission root: aRoot waiter: (self _present: aWaiter named: 'waiter').

PBReplicateWanted >> _setPermission: aPermission root: aRoot waiter: aWaiter
  "Runs once, on a fresh instance."
  permission isNil ifFalse: [^ PBUserError signal: 'PBReplicateWanted is immutable'].
  permission := aPermission.
  root := aRoot.
  waiter := aWaiter.
  ^ self.

PBReplicateWanted >> permission
  ^ permission.

PBReplicateWanted >> root
  ^ root.

PBReplicateWanted >> waiter
  ^ waiter.

PBReplicateWanted >> dispatchWith: aCore in: aNodeState now: t
  ^ aCore dispatchReplicateWanted: self in: aNodeState now: t.

PBReplicateWanted >> printOn: aStream
  aStream nextPutAll: 'PBReplicateWanted('; nextPutAll: (PBCoreValue textOf: permission); nextPutAll: ', ';
    nextPutAll: (PBCoreValue textOf: root); nextPutAll: ', '; nextPutAll: (PBCoreValue textOf: waiter); nextPut: $).

"--- PBDoneReport ---"

PBCoreEvent subclass: #PBDoneReport instanceVariableNames: 'permission outcome'.

"The holder of aPermission reports its outcome: #committed, #unknown or #none (proto_db done's
 outcome strings)."
PBDoneReport class >> outcomes
  ^ #(#committed #unknown #none).

PBDoneReport class >> permission: aPermission outcome: anOutcome
  (aPermission isKindOf: PBPermission) ifFalse: [
    ^ PBValidationError signal: 'PBDoneReport: a permission is a PBPermission, not ' , aPermission printString].
  (self outcomes includes: anOutcome) ifFalse: [
    ^ PBValidationError signal: 'PBDoneReport: an outcome is #committed, #unknown or #none, not ' , anOutcome printString].
  ^ self basicNew _setPermission: aPermission outcome: anOutcome.

PBDoneReport >> _setPermission: aPermission outcome: anOutcome
  "Runs once, on a fresh instance."
  permission isNil ifFalse: [^ PBUserError signal: 'PBDoneReport is immutable'].
  permission := aPermission.
  outcome := anOutcome.
  ^ self.

PBDoneReport >> permission
  ^ permission.

PBDoneReport >> outcome
  ^ outcome.

PBDoneReport >> dispatchWith: aCore in: aNodeState now: t
  ^ aCore dispatchDoneReport: self in: aNodeState now: t.

PBDoneReport >> printOn: aStream
  aStream nextPutAll: 'PBDoneReport('; nextPutAll: (PBCoreValue textOf: permission); nextPutAll: ', ';
    nextPutAll: outcome; nextPut: $).

"--- PBAcceptorDecided ---"

PBCoreEvent subclass: #PBAcceptorDecided instanceVariableNames: 'step'.

"aStep, a PBAcceptorStep of this node's acceptor whose appends are durable and whose reply was
 performed."
PBAcceptorDecided class >> step: aStep
  (aStep isKindOf: PBAcceptorStep) ifFalse: [
    ^ PBValidationError signal: 'PBAcceptorDecided: a step is a PBAcceptorStep, not ' , aStep printString].
  ^ self basicNew _setStep: aStep.

PBAcceptorDecided >> _setStep: aStep
  "Runs once, on a fresh instance."
  step isNil ifFalse: [^ PBUserError signal: 'PBAcceptorDecided is immutable'].
  step := aStep.
  ^ self.

PBAcceptorDecided >> step
  ^ step.

PBAcceptorDecided >> dispatchWith: aCore in: aNodeState now: t
  ^ aCore dispatchAcceptorDecided: self in: aNodeState now: t.

"=== Effects =================================================================="

PBCoreValue subclass: #PBEffect.

"Sends aShell the one apply message of this effect's kind."
PBEffect >> applyTo: aShell
  ^ self subclassResponsibility.

"--- PBSend ---"

PBEffect subclass: #PBSend instanceVariableNames: 'to message'.

"Send aMessage (a PBClusterMessage) to the member aNodeId."
PBSend class >> to: aNodeId message: aMessage
  (aNodeId isString and: [aNodeId notEmpty]) ifFalse: [
    ^ PBValidationError signal: 'PBSend: a receiver is a node id, not ' , aNodeId printString].
  (aMessage isKindOf: PBClusterMessage) ifFalse: [
    ^ PBValidationError signal: 'PBSend: a message is a PBClusterMessage, not ' , aMessage printString].
  ^ self basicNew _setTo: aNodeId asString message: aMessage.

PBSend >> _setTo: aNodeId message: aMessage
  "Runs once, on a fresh instance."
  to isNil ifFalse: [^ PBUserError signal: 'PBSend is immutable'].
  to := aNodeId.
  message := aMessage.
  ^ self.

PBSend >> to
  ^ to.

PBSend >> message
  ^ message.

PBSend >> applyTo: aShell
  ^ aShell applySend: self.

PBSend >> printOn: aStream
  aStream nextPutAll: 'PBSend('; nextPutAll: to; nextPutAll: ', '; nextPutAll: (PBCoreValue textOf: message); nextPut: $).

"--- PBToAcceptor ---"

PBEffect subclass: #PBToAcceptor instanceVariableNames: 'event'.

"Hand anEvent (a PBReceived or a PBStartNode) to this node's own acceptor (CC1)."
PBToAcceptor class >> event: anEvent
  ((anEvent isKindOf: PBReceived) or: [anEvent isKindOf: PBStartNode]) ifFalse: [
    ^ PBValidationError signal: 'PBToAcceptor: an acceptor takes a PBReceived or a PBStartNode, not ' , anEvent printString].
  ^ self basicNew _setEvent: anEvent.

PBToAcceptor >> _setEvent: anEvent
  "Runs once, on a fresh instance."
  event isNil ifFalse: [^ PBUserError signal: 'PBToAcceptor is immutable'].
  event := anEvent.
  ^ self.

PBToAcceptor >> event
  ^ event.

PBToAcceptor >> applyTo: aShell
  ^ aShell applyToAcceptor: self.

PBToAcceptor >> printOn: aStream
  aStream nextPutAll: 'PBToAcceptor('; print: event; nextPut: $).

"--- PBLogAppend ---"

PBEffect subclass: #PBLogAppend instanceVariableNames: 'kind label root sync'.

"An acceptor-log entry (PBAcceptorLog encode:label:root:): aKind #accepted, #committed, #promise
 or #rejoined, the label (or promised term) anInteger >= 0, the root a PBRootRecord or nil (the
 empty space; a promise and a rejoined marker carry none), and whether the reply waits for its
 sync (proto_db syncs accepted roots, promises and the marker; a committed entry rides on the
 next sync, R67)."
PBLogAppend class >> kind: aKind label: anInteger root: aRootRecordOrNil sync: aBoolean
  (#(#accepted #committed #promise #rejoined) includes: aKind) ifFalse: [
    ^ PBValidationError signal: 'PBLogAppend: a kind is #accepted, #committed, #promise or #rejoined, not ' , aKind printString].
  (anInteger isInteger and: [anInteger >= 0]) ifFalse: [
    ^ PBValidationError signal: 'PBLogAppend: a label is an Integer >= 0, not ' , anInteger printString].
  (aRootRecordOrNil isNil or: [aRootRecordOrNil isKindOf: PBRootRecord]) ifFalse: [
    ^ PBValidationError signal: 'PBLogAppend: a root is a PBRootRecord or nil, not ' , aRootRecordOrNil printString].
  (aRootRecordOrNil notNil and: [aKind = #promise or: [aKind = #rejoined]]) ifTrue: [
    ^ PBValidationError signal: 'PBLogAppend: a ' , aKind , ' entry carries no root'].
  (aBoolean == true or: [aBoolean == false]) ifFalse: [
    ^ PBValidationError signal: 'PBLogAppend: sync is a Boolean, not ' , aBoolean printString].
  ^ self basicNew _setKind: aKind asSymbol label: anInteger root: aRootRecordOrNil sync: aBoolean.

PBLogAppend >> _setKind: aKind label: anInteger root: aRootRecordOrNil sync: aBoolean
  "Runs once, on a fresh instance."
  kind isNil ifFalse: [^ PBUserError signal: 'PBLogAppend is immutable'].
  kind := aKind.
  label := anInteger.
  root := aRootRecordOrNil.
  sync := aBoolean.
  ^ self.

PBLogAppend >> kind
  ^ kind.

PBLogAppend >> label
  ^ label.

"The PBRootRecord, or nil."
PBLogAppend >> root
  ^ root.

PBLogAppend >> sync
  ^ sync.

"The 41-byte payload of the entry (PBAcceptorLog encode:label:root:)."
PBLogAppend >> payload
  ^ PBAcceptorLog encode: kind label: label root: root.

PBLogAppend >> printOn: aStream
  aStream nextPutAll: 'PBLogAppend('; nextPutAll: kind; nextPutAll: ' '; print: label;
    nextPutAll: (root isNil ifTrue: [''] ifFalse: [' epoch ' , root epoch printString , '@' , root offset printString]);
    nextPutAll: (sync ifTrue: [' sync'] ifFalse: ['']); nextPut: $).

"--- PBTimer ---"

PBEffect subclass: #PBTimer instanceVariableNames: 'after token event'.

"PBTimerFired token: aToken event: anEvent after someMicros (an Integer >= 0) of the node's
 clock."
PBTimer class >> after: someMicros token: aToken event: anEvent
  (someMicros isInteger and: [someMicros >= 0]) ifFalse: [
    ^ PBValidationError signal: 'PBTimer: after is an Integer >= 0 of microseconds, not ' , someMicros printString].
  ^ self basicNew _setAfter: someMicros token: (self _present: aToken named: 'token') event: (self _present: anEvent named: 'event').

PBTimer >> _setAfter: someMicros token: aToken event: anEvent
  "Runs once, on a fresh instance."
  after isNil ifFalse: [^ PBUserError signal: 'PBTimer is immutable'].
  after := someMicros.
  token := aToken.
  event := anEvent.
  ^ self.

"Microseconds of the node's clock."
PBTimer >> after
  ^ after.

PBTimer >> token
  ^ token.

PBTimer >> event
  ^ event.

"The event the timer delivers when it comes due."
PBTimer >> fired
  ^ PBTimerFired token: token event: event.

PBTimer >> applyTo: aShell
  ^ aShell applyTimer: self.

PBTimer >> printOn: aStream
  aStream nextPutAll: 'PBTimer('; print: after; nextPutAll: ' us, '; nextPutAll: (PBCoreValue textOf: token);
    nextPutAll: ' '; nextPutAll: (PBCoreValue textOf: event); nextPut: $).

"--- PBSettle ---"

PBEffect subclass: #PBSettle instanceVariableNames: 'waiter outcome'.

"Settle aWaiter (of a PBPermitWanted, PBBaseWanted or PBReplicateWanted) with anOutcome."
PBSettle class >> waiter: aWaiter outcome: anOutcome
  ^ self basicNew _setWaiter: (self _present: aWaiter named: 'waiter') outcome: (self _present: anOutcome named: 'outcome').

PBSettle >> _setWaiter: aWaiter outcome: anOutcome
  "Runs once, on a fresh instance."
  waiter isNil ifFalse: [^ PBUserError signal: 'PBSettle is immutable'].
  waiter := aWaiter.
  outcome := anOutcome.
  ^ self.

PBSettle >> waiter
  ^ waiter.

PBSettle >> outcome
  ^ outcome.

PBSettle >> applyTo: aShell
  ^ aShell applySettle: self.

PBSettle >> printOn: aStream
  aStream nextPutAll: 'PBSettle('; nextPutAll: (PBCoreValue textOf: waiter); nextPutAll: ', ';
    nextPutAll: (PBCoreValue textOf: outcome); nextPut: $).

"--- PBPublishCommitted ---"

PBEffect subclass: #PBPublishCommitted instanceVariableNames: 'root'.

"Publish aRoot (a PBLabeledRoot) as the committed root readers see."
PBPublishCommitted class >> root: aRoot
  (aRoot isKindOf: PBLabeledRoot) ifFalse: [
    ^ PBValidationError signal: 'PBPublishCommitted: a root is a PBLabeledRoot, not ' , aRoot printString].
  ^ self basicNew _setRoot: aRoot.

PBPublishCommitted >> _setRoot: aRoot
  "Runs once, on a fresh instance."
  root isNil ifFalse: [^ PBUserError signal: 'PBPublishCommitted is immutable'].
  root := aRoot.
  ^ self.

PBPublishCommitted >> root
  ^ root.

PBPublishCommitted >> applyTo: aShell
  ^ aShell applyPublishCommitted: self.

PBPublishCommitted >> printOn: aStream
  aStream nextPutAll: 'PBPublishCommitted('; nextPutAll: (PBCoreValue textOf: root); nextPut: $).

"--- PBPublishAcceptor ---"

PBEffect subclass: #PBPublishAcceptor instanceVariableNames: 'state'.

"Publish aState (a PBAcceptorState) as the acceptor's snapshot (CC2)."
PBPublishAcceptor class >> state: aState
  (aState isKindOf: PBAcceptorState) ifFalse: [
    ^ PBValidationError signal: 'PBPublishAcceptor: a state is a PBAcceptorState, not ' , aState printString].
  ^ self basicNew _setState: aState.

PBPublishAcceptor >> _setState: aState
  "Runs once, on a fresh instance."
  state isNil ifFalse: [^ PBUserError signal: 'PBPublishAcceptor is immutable'].
  state := aState.
  ^ self.

PBPublishAcceptor >> state
  ^ state.

PBPublishAcceptor >> applyTo: aShell
  ^ aShell applyPublishAcceptor: self.

"--- PBFence ---"

PBEffect subclass: #PBFence instanceVariableNames: 'reason'.

"Fence the node for the life of the process, for aReason (a String)."
PBFence class >> reason: aReason
  (aReason isString and: [aReason notEmpty]) ifFalse: [
    ^ PBValidationError signal: 'PBFence: a reason is a non-empty String, not ' , aReason printString].
  ^ self basicNew _setReason: aReason asString.

PBFence >> _setReason: aReason
  "Runs once, on a fresh instance."
  reason isNil ifFalse: [^ PBUserError signal: 'PBFence is immutable'].
  reason := aReason.
  ^ self.

PBFence >> reason
  ^ reason.

PBFence >> applyTo: aShell
  ^ aShell applyFence: self.

PBFence >> printOn: aStream
  aStream nextPutAll: 'PBFence('; nextPutAll: reason; nextPut: $).

"=== Steps ===================================================================="

Object subclass: #PBStep instanceVariableNames: 'state effects'.

"The answer of a dispatcher rule: aState (a PBNodeState) and anArray of effects, performed in
 order. A PBLogAppend is PBValidationError here: only an acceptor step writes the log."
PBStep class >> state: aState effects: anArray
  (aState isKindOf: PBNodeState) ifFalse: [
    ^ PBValidationError signal: 'PBStep: a state is a PBNodeState, not ' , aState printString].
  (anArray isArray and: [anArray allSatisfy: [:e | (e isKindOf: PBEffect) and: [(e isKindOf: PBLogAppend) not]]]) ifFalse: [
    ^ PBValidationError signal: 'PBStep: the effects are an Array of effects other than PBLogAppend, not ' , anArray printString].
  ^ self basicNew _setState: aState effects: anArray copy.

PBStep >> _setState: aState effects: anArray
  "Runs once, on a fresh instance."
  state isNil ifFalse: [^ PBUserError signal: 'PBStep is immutable'].
  state := aState.
  effects := anArray.
  ^ self.

PBStep >> state
  ^ state.

"A fresh Array."
PBStep >> effects
  ^ effects copy.

Object subclass: #PBAcceptorStep instanceVariableNames: 'state appends reply'.

"The answer of an acceptor rule: aState (a PBAcceptorState), anArray of PBLogAppend written in
 order, and the reply effects (no PBLogAppend), performed only once every append that asks for
 a sync is durable."
PBAcceptorStep class >> state: aState appends: anArray reply: aReplyArray
  (aState isKindOf: PBAcceptorState) ifFalse: [
    ^ PBValidationError signal: 'PBAcceptorStep: a state is a PBAcceptorState, not ' , aState printString].
  (anArray isArray and: [anArray allSatisfy: [:e | e isKindOf: PBLogAppend]]) ifFalse: [
    ^ PBValidationError signal: 'PBAcceptorStep: the appends are an Array of PBLogAppend, not ' , anArray printString].
  (aReplyArray isArray and: [aReplyArray allSatisfy: [:e | (e isKindOf: PBEffect) and: [(e isKindOf: PBLogAppend) not]]]) ifFalse: [
    ^ PBValidationError signal: 'PBAcceptorStep: the reply is an Array of effects other than PBLogAppend, not ' , aReplyArray printString].
  ^ self basicNew _setState: aState appends: anArray copy reply: aReplyArray copy.

PBAcceptorStep >> _setState: aState appends: anArray reply: aReplyArray
  "Runs once, on a fresh instance."
  state isNil ifFalse: [^ PBUserError signal: 'PBAcceptorStep is immutable'].
  state := aState.
  appends := anArray.
  reply := aReplyArray.
  ^ self.

PBAcceptorStep >> state
  ^ state.

"A fresh Array."
PBAcceptorStep >> appends
  ^ appends copy.

"A fresh Array."
PBAcceptorStep >> reply
  ^ reply copy.

"=== PBNodeState ============================================================="

Object subclass: #PBNodeState instanceVariableNames: 'config inc acceptorView hints proposer ownership waiters suspectTerm fenced rejoin nextRid'.

"The state of the node of aConfig (a PBClusterConfig) at the start of its incarnation anInteger
 (>= 0, below 2^62 as proto_db's _inc): no acceptor view, hint, attempt, ownership, waiter or
 rejoin yet; not suspect, not fenced; the next request id is 1."
PBNodeState class >> config: aConfig inc: anInteger
  (aConfig isKindOf: PBClusterConfig) ifFalse: [
    ^ PBValidationError signal: 'PBNodeState: a config is a PBClusterConfig, not ' , aConfig printString].
  (anInteger isInteger and: [anInteger >= 0 and: [anInteger < (2 raisedTo: 62)]]) ifFalse: [
    ^ PBValidationError signal: 'PBNodeState: an incarnation is an Integer in [0, 2^62), not ' , anInteger printString].
  ^ self basicNew _setConfig: aConfig inc: anInteger acceptorView: nil hints: nil proposer: nil ownership: nil
    waiters: #() suspectTerm: 0 fenced: nil rejoin: nil nextRid: 1.

PBNodeState >> _setConfig: aConfig inc: anInteger acceptorView: aView hints: someHints proposer: aProposer ownership: anOwnership waiters: anArray suspectTerm: aTerm fenced: aReason rejoin: aRejoin nextRid: aRid
  "Runs once, on a fresh instance."
  config isNil ifFalse: [^ PBUserError signal: 'PBNodeState is immutable'].
  config := aConfig.
  inc := anInteger.
  acceptorView := aView.
  hints := someHints.
  proposer := aProposer.
  ownership := anOwnership.
  waiters := anArray.
  suspectTerm := aTerm.
  fenced := aReason.
  rejoin := aRejoin.
  nextRid := aRid.
  ^ self.

PBNodeState >> config
  ^ config.

PBNodeState >> inc
  ^ inc.

"The PBAcceptorState last handed back by the acceptor (PBAcceptorDecided), or nil: for hints
 only, never to decide a grant or an acceptance (CC2)."
PBNodeState >> acceptorView
  ^ acceptorView.

"The fairness and owner hints, nil until learnt."
PBNodeState >> hints
  ^ hints.

"The running lease attempt, or nil."
PBNodeState >> proposer
  ^ proposer.

"The ownership of a term (answers term), or nil."
PBNodeState >> ownership
  ^ ownership.

"The local waiters, a fresh Array."
PBNodeState >> waiters
  ^ waiters copy.

"A term whose outcome this node could not know, 0 when none (proto_db _suspect_term)."
PBNodeState >> suspectTerm
  ^ suspectTerm.

"The reason the node is fenced, or nil."
PBNodeState >> fenced
  ^ fenced.

"The running rejoin, or nil."
PBNodeState >> rejoin
  ^ rejoin.

PBNodeState >> nextRid
  ^ nextRid.

"This state with anOwnership (nil: none)."
PBNodeState >> withOwnership: anOwnership
  ^ self class basicNew _setConfig: config inc: inc acceptorView: acceptorView hints: hints proposer: proposer
    ownership: anOwnership waiters: waiters suspectTerm: suspectTerm fenced: fenced rejoin: rejoin nextRid: nextRid.

PBNodeState >> printOn: aStream
  aStream nextPutAll: 'PBNodeState('; nextPutAll: config nodeId; nextPutAll: ', inc '; print: inc; nextPut: $).

"=== PBAcceptorState ========================================================="

Object subclass: #PBAcceptorState instanceVariableNames: 'config grants accepted committed seqSeen suspectTerm rejoined rejoinBallot tierFailed fenced'.

"The acceptor of the node of aConfig started at t over aLoggedRoots (what its acceptor log holds,
 PBAcceptorLog load): the grant state refuses every request until t + startupGrace and honours
 the logged promise and the accepted root's label (PBGrantState initial:now:, restore:,
 coordinator.py _attach_locked); accepted, committed and rejoined are the log's."
PBAcceptorState class >> config: aConfig logged: aLoggedRoots now: t
  (aConfig isKindOf: PBClusterConfig) ifFalse: [
    ^ PBValidationError signal: 'PBAcceptorState: a config is a PBClusterConfig, not ' , aConfig printString].
  (aLoggedRoots isKindOf: PBLoggedRoots) ifFalse: [
    ^ PBValidationError signal: 'PBAcceptorState: the logged roots are a PBLoggedRoots, not ' , aLoggedRoots printString].
  ^ self basicNew _setConfig: aConfig grants: ((PBGrantState initial: aConfig now: t) restore: aLoggedRoots)
    accepted: aLoggedRoots accepted committed: aLoggedRoots committed seqSeen: #(0 0) suspectTerm: 0
    rejoined: aLoggedRoots isRejoined rejoinBallot: 0 tierFailed: nil fenced: nil.

PBAcceptorState >> _setConfig: aConfig grants: aGrantState accepted: anAccepted committed: aCommitted seqSeen: aPair suspectTerm: aTerm rejoined: aBoolean rejoinBallot: aBallot tierFailed: aFailure fenced: aReason
  "Runs once, on a fresh instance."
  config isNil ifFalse: [^ PBUserError signal: 'PBAcceptorState is immutable'].
  config := aConfig.
  grants := aGrantState.
  accepted := anAccepted.
  committed := aCommitted.
  seqSeen := aPair.
  suspectTerm := aTerm.
  rejoined := aBoolean.
  rejoinBallot := aBallot.
  tierFailed := aFailure.
  fenced := aReason.
  ^ self.

PBAcceptorState >> config
  ^ config.

"The PBGrantState: what this node promised."
PBAcceptorState >> grants
  ^ grants.

"The highest root accepted here (a PBLabeledRoot), or nil."
PBAcceptorState >> accepted
  ^ accepted.

"The newest root known committed here (a PBLabeledRoot), or nil."
PBAcceptorState >> committed
  ^ committed.

"{ term. seq } of the highest permission whose root was accepted here, a fresh Array."
PBAcceptorState >> seqSeen
  ^ seqSeen copy.

PBAcceptorState >> suspectTerm
  ^ suspectTerm.

"Whether the log holds the rejoined marker (kind 4): without it the node is rejoining."
PBAcceptorState >> isRejoined
  ^ rejoined.

"The ballot of this incarnation's last rejoin, 0 when none (proto_db _rejoin_ballot)."
PBAcceptorState >> rejoinBallot
  ^ rejoinBallot.

"The write failure that made the tier fail, or nil."
PBAcceptorState >> tierFailed
  ^ tierFailed.

"The reason the node is fenced, or nil."
PBAcceptorState >> fenced
  ^ fenced.

PBAcceptorState >> printOn: aStream
  aStream nextPutAll: 'PBAcceptorState('; nextPutAll: config nodeId; nextPutAll: ', '; print: grants; nextPut: $).

"=== PBCoordinatorCore ======================================================="

"The rules, stateless: PBCoordinatorCore new is the product rules object."
Object subclass: #PBCoordinatorCore.

"The step of the dispatcher of aNodeState for anEvent at t (microseconds of its clock): a
 PBStep. A rule that answers anything else is PBUnexpectedError."
PBCoordinatorCore >> dispatch: anEvent in: aNodeState now: t
  | step |
  (anEvent isKindOf: PBCoreEvent) ifFalse: [
    ^ PBValidationError signal: 'PBCoordinatorCore: an event is a PBCoreEvent, not ' , anEvent printString].
  (aNodeState isKindOf: PBNodeState) ifFalse: [
    ^ PBValidationError signal: 'PBCoordinatorCore: a dispatcher state is a PBNodeState, not ' , aNodeState printString].
  t isInteger ifFalse: [^ PBValidationError signal: 'PBCoordinatorCore: now is an Integer of microseconds, not ' , t printString].
  step := anEvent dispatchWith: self in: aNodeState now: t.
  (step isKindOf: PBStep) ifFalse: [
    ^ PBUnexpectedError signal: 'The rule for ' , anEvent printString , ' answered ' , step printString , ', not a PBStep'].
  ^ step.

"The step of the acceptor of anAcceptorState for anEvent (a PBReceived or a PBStartNode) at t:
 a PBAcceptorStep. A rule that answers anything else is PBUnexpectedError."
PBCoordinatorCore >> accept: anEvent in: anAcceptorState now: t
  | step |
  (anEvent isKindOf: PBCoreEvent) ifFalse: [
    ^ PBValidationError signal: 'PBCoordinatorCore: an event is a PBCoreEvent, not ' , anEvent printString].
  (anAcceptorState isKindOf: PBAcceptorState) ifFalse: [
    ^ PBValidationError signal: 'PBCoordinatorCore: an acceptor state is a PBAcceptorState, not ' , anAcceptorState printString].
  t isInteger ifFalse: [^ PBValidationError signal: 'PBCoordinatorCore: now is an Integer of microseconds, not ' , t printString].
  step := anEvent acceptWith: self in: anAcceptorState now: t.
  (step isKindOf: PBAcceptorStep) ifFalse: [
    ^ PBUnexpectedError signal: 'The acceptor rule for ' , anEvent printString , ' answered ' , step printString , ', not a PBAcceptorStep'].
  ^ step.

"aNodeState unchanged, with no effect."
PBCoordinatorCore >> _unchanged: aNodeState
  ^ PBStep state: aNodeState effects: #().

"anAcceptorState unchanged: nothing appended, no reply."
PBCoordinatorCore >> _unchangedAcceptor: anAcceptorState
  ^ PBAcceptorStep state: anAcceptorState appends: #() reply: #().

"--- the dispatcher's rule methods, one per event (the rules of each concern override them) ---"

"A message of a peer (coordinator.py _route): the routing by type is the rules' of acceptor.st,
 proposer.st, owner.st and holder.st."
PBCoordinatorCore >> dispatchReceived: anEvent in: aNodeState now: t
  ^ self _unchanged: aNodeState.

"A timer came due; a token that is not current is ignored by the rule that set it."
PBCoordinatorCore >> dispatchTimerFired: anEvent in: aNodeState now: t
  ^ self _unchanged: aNodeState.

PBCoordinatorCore >> dispatchStartNode: anEvent in: aNodeState now: t
  ^ self _unchanged: aNodeState.

PBCoordinatorCore >> dispatchStopNode: anEvent in: aNodeState now: t
  ^ self _unchanged: aNodeState.

PBCoordinatorCore >> dispatchPermitWanted: anEvent in: aNodeState now: t
  ^ self _unchanged: aNodeState.

PBCoordinatorCore >> dispatchBaseWanted: anEvent in: aNodeState now: t
  ^ self _unchanged: aNodeState.

PBCoordinatorCore >> dispatchReplicateWanted: anEvent in: aNodeState now: t
  ^ self _unchanged: aNodeState.

PBCoordinatorCore >> dispatchDoneReport: anEvent in: aNodeState now: t
  ^ self _unchanged: aNodeState.

PBCoordinatorCore >> dispatchRejoinWanted: anEvent in: aNodeState now: t
  ^ self _unchanged: aNodeState.

PBCoordinatorCore >> dispatchAcceptorDecided: anEvent in: aNodeState now: t
  ^ self _unchanged: aNodeState.

"--- the acceptor's rule methods ---"

"A message for the acceptor lane (request, renew, release, replicate, a ballot query, done:
 coordinator.py _route): the routing by type is acceptor.st's."
PBCoordinatorCore >> acceptReceived: anEvent in: anAcceptorState now: t
  ^ self _unchangedAcceptor: anAcceptorState.

PBCoordinatorCore >> acceptStart: anEvent in: anAcceptorState now: t
  ^ self _unchangedAcceptor: anAcceptorState.
