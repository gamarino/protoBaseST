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
    commit under a permission), PBReplicateWanted permission: root: pred: waiter: (replicate a
    built root), PBDoneReport permission: outcome: root: (the outcome a holder reports, #committed,
    #unknown or #none: proto_db's done outcomes, and the root it committed), PBRejoinWanted (the operator's forceRejoin)
    PBAcceptorDecided step: (an acceptor step whose appends are durable, handed back to the
    dispatcher: the reply to this node's own vote and acceptance travels this way, CC1) and
    PBAcceptorDiscarded step: reason: (an acceptor step whose append failed, discarded by the
    shell, and the failure's text, the reason it gives PBAppendFailed: the dispatcher withdraws
    the own vote it carried).
  Effects (PBEffect): PBSend to: message:, PBToAcceptor event: (an event for this node's own
    acceptor, never through the transport: CC1), PBLogAppend kind: label: root: sync: (an
    acceptor-log entry: only in the appends of an acceptor step), PBTimer after: token: event:
    (a PBTimerFired token: event: after that many microseconds of the node's clock; the token
    names one timer and the rules ignore a fired timer whose token is no longer the current
    one, so a shell never cancels), PBSettle waiter: outcome:, PBPublishCommitted root: (the
    committed root readers see), PBPublishAcceptor state: (the acceptor's snapshot, CC2),
    PBFence reason: (the node is fenced for the life of the process) and PBCount stat: (add one
    to the named counter of the node's stats, proto_db's snake_case name, CC24). An effect
    answers applyTo: aShell, which sends aShell the one message of its kind (applySend:,
    applyToAcceptor:, applyTimer:, applySettle:, applyPublishCommitted:,
    applyPublishAcceptor:, applyFence:, applyCount:); a PBLogAppend is written by the acceptor
    shell from its step, never applied.
  PBStep           state: effects: (the answer of dispatch:in:now:). A PBLogAppend among its
                   effects is PBValidationError: only the acceptor writes its log.
  PBAcceptorStep   state: appends: reply: vote: (the answer of accept:in:now:): the shell
                   writes the appends in order, syncs, and only once every append that asks for
                   a sync is durable performs the reply effects (atomic acceptor steps, R55,
                   R81, R81b), then hands the step to the dispatcher (PBAcceptorDecided). vote
                   is the grant or reject of this node's own request or renewal, or the ack of
                   its own replication (CC1: a node never sends to itself), nil for any other
                   step; learnt is the highest label of a root the step observed accepted or
                   committed (proto_db _learn_label), 0 when none. A step whose append fails is
                   discarded: the shell keeps the acceptor state it had before that step,
                   performs none of its reply, hands the acceptor PBAppendFailed (acceptor.st)
                   before anything else, so the state never holds what the log does not, and
                   hands the dispatcher PBAcceptorDiscarded with the step and that reason.
  PBNodeState      the dispatcher's state of one node: config, inc (this incarnation, as
                   proto_db's random _inc), acceptorView (the acceptor state last handed back,
                   for hints only: CC2), hints, proposer, ownership, waiters, suspectTerm,
                   fenced, rejoin, nextRid (proto_db _rids starts at 1), holder (the
                   holder side of permissions, owner.st); with: answers a copy
                   with some of them replaced.
  PBAcceptorState  the acceptor's state of one node (spec 5.3): config, grants (a PBGrantState:
                   promises are durable acceptor state, CC2), accepted and committed (a
                   PBLabeledRoot or nil), seqSeen ({ term. seq } of the highest permission
                   accepted), suspectTerm, rejoined (the log holds the rejoined marker),
                   rejoinBallot, tierFailed, fenced, log (the PBLoggedRoots of the log it
                   is attached to: the log's identity) and loggedPromise (the highest promise
                   written to that log, proto_db _logged_promise = (tier, term)).
  PBCoordinatorCore  dispatch: anEvent in: aNodeState now: t and accept: anEvent in:
                   anAcceptorState now: t. The event picks its rule method by double dispatch
                   (dispatchWith:in:now:, acceptWith:in:now:), one per event class, never by
                   doesNotUnderstand:. A received message passes the checks of proto_db
                   _route (dispatchReceived:: a sender that is another member, the voter-set
                   fingerprint) and then goes to the handler of its type, if a module defines
                   one: received<Type>:in:now: on the dispatcher, accept<Type>:in:now: on the
                   acceptor (handlerFor:prefix:; 'permit_req' -> receivedPermitReq:in:now:), so
                   each concern adds its types without replacing the checks. A rule method
                   this module defines answers the state
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

"Whether events of this class go to a node's acceptor (PBToAcceptor, accept:in:now:): false
 here. A module that adds an acceptor event defines it true on its class side and the event's
 acceptWith:in:now:, without editing this module."
PBCoreEvent class >> isAcceptorEvent
  ^ false.

"Sends aCore the acceptor rule of this event's class; an event that is no acceptor event is
 PBValidationError."
PBCoreEvent >> acceptWith: aCore in: anAcceptorState now: t
  ^ PBValidationError signal: 'An acceptor takes no ' , self printString , ' (its class is not an acceptor event)'.

"--- PBReceived ---"

PBCoreEvent subclass: #PBReceived instanceVariableNames: 'message'.

"aMessage, a PBClusterMessage that arrived (a valid frame, PBClusterFrame decode:to:key:)."
PBReceived class >> message: aMessage
  (aMessage isKindOf: PBClusterMessage) ifFalse: [
    ^ PBValidationError signal: 'PBReceived: a message is a PBClusterMessage, not ' , aMessage printString].
  ^ self basicNew _setMessage: aMessage.

PBReceived class >> isAcceptorEvent
  ^ true.

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

PBStartNode class >> isAcceptorEvent
  ^ true.

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

PBCoreEvent subclass: #PBReplicateWanted instanceVariableNames: 'permission root pred waiter'.

"Replicate aRoot (a PBLabeledRoot, built under aPermission on aPred, the PBLabeledRoot it was
 built on: the base, or the root last sent under the permission, proto_db lease.sent) to the
 voters (CP 1.7); aWaiter is settled with the outcome (#committed, #unknown or #none, H7)."
PBReplicateWanted class >> permission: aPermission root: aRoot pred: aPred waiter: aWaiter
  (aPermission isKindOf: PBPermission) ifFalse: [
    ^ PBValidationError signal: 'PBReplicateWanted: a permission is a PBPermission, not ' , aPermission printString].
  (aRoot isKindOf: PBLabeledRoot) ifFalse: [
    ^ PBValidationError signal: 'PBReplicateWanted: a root is a PBLabeledRoot, not ' , aRoot printString].
  (aPred isKindOf: PBLabeledRoot) ifFalse: [
    ^ PBValidationError signal: 'PBReplicateWanted: a pred is a PBLabeledRoot, not ' , aPred printString].
  ^ self basicNew _setPermission: aPermission root: aRoot pred: aPred waiter: (self _present: aWaiter named: 'waiter').

PBReplicateWanted >> _setPermission: aPermission root: aRoot pred: aPred waiter: aWaiter
  "Runs once, on a fresh instance."
  permission isNil ifFalse: [^ PBUserError signal: 'PBReplicateWanted is immutable'].
  permission := aPermission.
  root := aRoot.
  pred := aPred.
  waiter := aWaiter.
  ^ self.

PBReplicateWanted >> permission
  ^ permission.

PBReplicateWanted >> root
  ^ root.

"The root aRoot was built on."
PBReplicateWanted >> pred
  ^ pred.

PBReplicateWanted >> waiter
  ^ waiter.

PBReplicateWanted >> dispatchWith: aCore in: aNodeState now: t
  ^ aCore dispatchReplicateWanted: self in: aNodeState now: t.

PBReplicateWanted >> printOn: aStream
  aStream nextPutAll: 'PBReplicateWanted('; nextPutAll: (PBCoreValue textOf: permission); nextPutAll: ', ';
    nextPutAll: (PBCoreValue textOf: root); nextPutAll: ' on '; nextPutAll: (PBCoreValue textOf: pred); nextPutAll: ', ';
    nextPutAll: (PBCoreValue textOf: waiter); nextPut: $).

"--- PBDoneReport ---"

PBCoreEvent subclass: #PBDoneReport instanceVariableNames: 'permission outcome root'.

"The holder of aPermission reports its outcome: #committed, #unknown or #none (proto_db done's
 outcome strings)."
PBDoneReport class >> outcomes
  ^ #(#committed #unknown #none).

"As permission:outcome:root:, with no root."
PBDoneReport class >> permission: aPermission outcome: anOutcome
  ^ self permission: aPermission outcome: anOutcome root: nil.

"The holder of aPermission reports anOutcome and aRoot (a PBLabeledRoot or nil), the root it
 committed: proto_db finish(permission) reads permission.committed, which the caller set."
PBDoneReport class >> permission: aPermission outcome: anOutcome root: aRoot
  (aPermission isKindOf: PBPermission) ifFalse: [
    ^ PBValidationError signal: 'PBDoneReport: a permission is a PBPermission, not ' , aPermission printString].
  (self outcomes includes: anOutcome) ifFalse: [
    ^ PBValidationError signal: 'PBDoneReport: an outcome is #committed, #unknown or #none, not ' , anOutcome printString].
  (aRoot isNil or: [aRoot isClassObject not and: [aRoot class == PBLabeledRoot]]) ifFalse: [
    ^ PBValidationError signal: 'PBDoneReport: a root is a PBLabeledRoot or nil, not ' , aRoot printString].
  ^ self basicNew _setPermission: aPermission outcome: anOutcome root: aRoot.

PBDoneReport >> _setPermission: aPermission outcome: anOutcome root: aRoot
  "Runs once, on a fresh instance."
  permission isNil ifFalse: [^ PBUserError signal: 'PBDoneReport is immutable'].
  permission := aPermission.
  outcome := anOutcome.
  root := aRoot.
  ^ self.

PBDoneReport >> permission
  ^ permission.

PBDoneReport >> outcome
  ^ outcome.

"The root committed under the permission (a PBLabeledRoot), or nil."
PBDoneReport >> root
  ^ root.

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

"--- PBAcceptorDiscarded ---"

PBCoreEvent subclass: #PBAcceptorDiscarded instanceVariableNames: 'step reason'.

"aStep, a PBAcceptorStep of this node's acceptor whose append failed: the shell discarded it
 (nothing of it is durable, its reply was never performed). aReason, a non-empty String, is the
 failure (the reason of the PBAppendFailed the acceptor is handed): proto_db names it in the
 text of an own acceptance that could not be made durable."
PBAcceptorDiscarded class >> step: aStep reason: aReason
  (aStep isKindOf: PBAcceptorStep) ifFalse: [
    ^ PBValidationError signal: 'PBAcceptorDiscarded: a step is a PBAcceptorStep, not ' , aStep printString].
  ((aReason isKindOf: String) and: [aReason notEmpty]) ifFalse: [
    ^ PBValidationError signal: 'PBAcceptorDiscarded: a reason is a non-empty String, not ' , aReason printString].
  ^ self basicNew _setStep: aStep reason: aReason.

PBAcceptorDiscarded >> _setStep: aStep reason: aReason
  "Runs once, on a fresh instance."
  step isNil ifFalse: [^ PBUserError signal: 'PBAcceptorDiscarded is immutable'].
  step := aStep.
  reason := aReason.
  ^ self.

PBAcceptorDiscarded >> step
  ^ step.

PBAcceptorDiscarded >> reason
  ^ reason.

PBAcceptorDiscarded >> dispatchWith: aCore in: aNodeState now: t
  ^ aCore dispatchAcceptorDiscarded: self in: aNodeState now: t.

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

"Hand anEvent, an event whose class isAcceptorEvent (PBReceived, PBStartNode, and those later
 modules add), to this node's own acceptor (CC1)."
PBToAcceptor class >> event: anEvent
  ((anEvent isKindOf: PBCoreEvent) and: [anEvent class isAcceptorEvent]) ifFalse: [
    ^ PBValidationError signal: 'PBToAcceptor: an acceptor event is one whose class isAcceptorEvent, not ' , anEvent printString].
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

"--- PBCount ---"

PBEffect subclass: #PBCount instanceVariableNames: 'stat'.

"Add one to the node's counter aName (proto_db's stats name, a snake_case String, CC24)."
PBCount class >> stat: aName
  (aName isString and: [aName notEmpty]) ifFalse: [
    ^ PBValidationError signal: 'PBCount: a stat is a non-empty String, not ' , aName printString].
  ^ self basicNew _setStat: aName asString.

PBCount >> _setStat: aName
  "Runs once, on a fresh instance."
  stat isNil ifFalse: [^ PBUserError signal: 'PBCount is immutable'].
  stat := aName.
  ^ self.

PBCount >> stat
  ^ stat.

PBCount >> applyTo: aShell
  ^ aShell applyCount: self.

PBCount >> printOn: aStream
  aStream nextPutAll: 'PBCount('; nextPutAll: stat; nextPut: $).

"=== Steps ===================================================================="

Object subclass: #PBStep instanceVariableNames: 'state effects'.

"The answer of a dispatcher rule: aState (a PBNodeState, or the PBRoundState of a commit round:
 holder.st round:in:now:) and anArray of effects, performed in order. A PBLogAppend is
 PBValidationError here: only an acceptor step writes the log."
PBStep class >> state: aState effects: anArray
  ((aState isKindOf: PBNodeState) or: [aState isKindOf: PBRoundState]) ifFalse: [
    ^ PBValidationError signal: 'PBStep: a state is a PBNodeState or a PBRoundState, not ' , aState printString].
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

Object subclass: #PBAcceptorStep instanceVariableNames: 'state appends reply vote learnt'.

"The answer of an acceptor rule: aState (a PBAcceptorState), anArray of PBLogAppend written in
 order, and the reply effects (no PBLogAppend), performed only once every append that asks for
 a sync is durable; no own vote, no label learnt."
PBAcceptorStep class >> state: aState appends: anArray reply: aReplyArray
  ^ self state: aState appends: anArray reply: aReplyArray vote: nil learnt: 0.

"As state:appends:reply:, with aVote: the grant or reject of this node's own request or renewal,
 or the ack of its own replication (CC1), nil for any other step; no label learnt."
PBAcceptorStep class >> state: aState appends: anArray reply: aReplyArray vote: aVote
  ^ self state: aState appends: anArray reply: aReplyArray vote: aVote learnt: 0.

"As state:appends:reply:vote:, with aLabel (an Integer >= 0): the highest label of a root this
 step observed accepted or committed, 0 when none (proto_db _learn_label: the dispatcher clears
 a suspicion of its own that the label answers, and raises its hint). The dispatcher reads both
 from the step handed back."
PBAcceptorStep class >> state: aState appends: anArray reply: aReplyArray vote: aVote learnt: aLabel
  (aState isKindOf: PBAcceptorState) ifFalse: [
    ^ PBValidationError signal: 'PBAcceptorStep: a state is a PBAcceptorState, not ' , aState printString].
  (anArray isArray and: [anArray allSatisfy: [:e | e isKindOf: PBLogAppend]]) ifFalse: [
    ^ PBValidationError signal: 'PBAcceptorStep: the appends are an Array of PBLogAppend, not ' , anArray printString].
  (aReplyArray isArray and: [aReplyArray allSatisfy: [:e | (e isKindOf: PBEffect) and: [(e isKindOf: PBLogAppend) not]]]) ifFalse: [
    ^ PBValidationError signal: 'PBAcceptorStep: the reply is an Array of effects other than PBLogAppend, not ' , aReplyArray printString].
  (aVote isNil or: [(aVote isKindOf: PBClusterMessage) and: [#('grant' 'reject' 'ack') includes: aVote type]]) ifFalse: [
    ^ PBValidationError signal: 'PBAcceptorStep: a vote is a grant, reject or ack message or nil, not ' , aVote printString].
  (aLabel isInteger and: [aLabel >= 0]) ifFalse: [
    ^ PBValidationError signal: 'PBAcceptorStep: a label learnt is an Integer >= 0, not ' , aLabel printString].
  ^ self basicNew _setState: aState appends: anArray copy reply: aReplyArray copy vote: aVote learnt: aLabel.

PBAcceptorStep >> _setState: aState appends: anArray reply: aReplyArray vote: aVote learnt: aLabel
  "Runs once, on a fresh instance."
  state isNil ifFalse: [^ PBUserError signal: 'PBAcceptorStep is immutable'].
  state := aState.
  appends := anArray.
  reply := aReplyArray.
  vote := aVote.
  learnt := aLabel.
  ^ self.

PBAcceptorStep >> state
  ^ state.

"A fresh Array."
PBAcceptorStep >> appends
  ^ appends copy.

"A fresh Array."
PBAcceptorStep >> reply
  ^ reply copy.

"The grant or reject of this node's own request or renewal, the ack of its own replication, or
 nil."
PBAcceptorStep >> vote
  ^ vote.

"The highest label of a root this step observed accepted or committed, 0 when none."
PBAcceptorStep >> learnt
  ^ learnt.

"=== PBNodeState ============================================================="

Object subclass: #PBNodeState instanceVariableNames: 'config inc acceptorView hints proposer ownership waiters suspectTerm fenced rejoin nextRid holder'.

"The state of the node of aConfig (a PBClusterConfig) at the start of its incarnation anInteger
 (>= 0, below 2^62 as proto_db's _inc): no acceptor view, hint, attempt, ownership, waiter or
 rejoin yet; not suspect, not fenced; the next request id is 1."
PBNodeState class >> config: aConfig inc: anInteger
  (aConfig isKindOf: PBClusterConfig) ifFalse: [
    ^ PBValidationError signal: 'PBNodeState: a config is a PBClusterConfig, not ' , aConfig printString].
  (anInteger isInteger and: [anInteger >= 0 and: [anInteger < (2 raisedTo: 62)]]) ifFalse: [
    ^ PBValidationError signal: 'PBNodeState: an incarnation is an Integer in [0, 2^62), not ' , anInteger printString].
  ^ self basicNew _setConfig: aConfig inc: anInteger acceptorView: nil hints: nil proposer: nil ownership: nil
    waiters: #() suspectTerm: 0 fenced: nil rejoin: nil nextRid: 1 holder: nil.

PBNodeState >> _setConfig: aConfig inc: anInteger acceptorView: aView hints: someHints proposer: aProposer ownership: anOwnership waiters: anArray suspectTerm: aTerm fenced: aReason rejoin: aRejoin nextRid: aRid holder: aHolder
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
  holder := aHolder.
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

"The holder side of permissions (owner.st PBHolder: the permit requests out, the waiters'
 deadlines, the permits seen), nil until used."
PBNodeState >> holder
  ^ holder.

"This state with anOwnership (nil: none)."
PBNodeState >> withOwnership: anOwnership
  ^ self with: { #ownership -> anOwnership }.

"This state with the fields someAssociations name (#acceptorView, #hints, #proposer,
 #ownership, #waiters, #suspectTerm, #fenced, #rejoin, #nextRid, #holder) replaced by their values; the
 rest unchanged. Another name, or waiters that are not an Array, is PBValidationError."
PBNodeState >> with: someAssociations
  | d |
  d := Dictionary new.
  d at: #acceptorView put: acceptorView; at: #hints put: hints; at: #proposer put: proposer;
    at: #ownership put: ownership; at: #waiters put: waiters; at: #suspectTerm put: suspectTerm;
    at: #fenced put: fenced; at: #rejoin put: rejoin; at: #nextRid put: nextRid; at: #holder put: holder.
  someAssociations do: [:a |
    (d includesKey: a key) ifFalse: [^ PBValidationError signal: 'PBNodeState has no field ' , a key printString].
    d at: a key put: a value].
  (d at: #waiters) isArray ifFalse: [
    ^ PBValidationError signal: 'PBNodeState: the waiters are an Array, not ' , (d at: #waiters) printString].
  ^ self class basicNew _setConfig: config inc: inc acceptorView: (d at: #acceptorView) hints: (d at: #hints)
    proposer: (d at: #proposer) ownership: (d at: #ownership) waiters: (d at: #waiters) copy
    suspectTerm: (d at: #suspectTerm) fenced: (d at: #fenced) rejoin: (d at: #rejoin) nextRid: (d at: #nextRid)
    holder: (d at: #holder).

PBNodeState >> printOn: aStream
  aStream nextPutAll: 'PBNodeState('; nextPutAll: config nodeId; nextPutAll: ', inc '; print: inc; nextPut: $).

"=== PBAcceptorState ========================================================="

Object subclass: #PBAcceptorState instanceVariableNames: 'config grants accepted committed seqSeen suspectTerm rejoined rejoinBallot tierFailed fenced log loggedPromise confirmed'.

"The acceptor of the node of aConfig started at t over aLoggedRoots (what its acceptor log holds,
 PBAcceptorLog load): the grant state refuses every request until t + startupGrace and honours
 the logged promise and the accepted root's label (PBGrantState initial:now:, restore:,
 coordinator.py _attach_locked); committed, rejoined and the logged promise are the log's
 (proto_db _logged_promise = (tier, promised)), and aLoggedRoots is the log's identity. The
 accepted root is the higher, in root order, of the logged accepted and committed roots: a
 root known committed is accepted knowledge (proto_db _attach_locked observes the committed
 root with accept=True). A new acceptor state needs a confirmation (L18, proto_db
 needs_confirmation is reset at every attach)."
PBAcceptorState class >> config: aConfig logged: aLoggedRoots now: t
  (aConfig isKindOf: PBClusterConfig) ifFalse: [
    ^ PBValidationError signal: 'PBAcceptorState: a config is a PBClusterConfig, not ' , aConfig printString].
  (aLoggedRoots isKindOf: PBLoggedRoots) ifFalse: [
    ^ PBValidationError signal: 'PBAcceptorState: the logged roots are a PBLoggedRoots, not ' , aLoggedRoots printString].
  ^ self basicNew _setConfig: aConfig grants: ((PBGrantState initial: aConfig now: t) restore: aLoggedRoots)
    accepted: (PBRootOrder max: aLoggedRoots accepted with: aLoggedRoots committed) committed: aLoggedRoots committed
    seqSeen: #(0 0) suspectTerm: 0 rejoined: aLoggedRoots isRejoined rejoinBallot: 0 tierFailed: nil fenced: nil log: aLoggedRoots
    loggedPromise: { aLoggedRoots. aLoggedRoots promise }.

PBAcceptorState >> _setConfig: aConfig grants: aGrantState accepted: anAccepted committed: aCommitted seqSeen: aPair suspectTerm: aTerm rejoined: aBoolean rejoinBallot: aBallot tierFailed: aFailure fenced: aReason log: aLog loggedPromise: aPromise
  "Runs once, on a fresh instance: not confirmed yet."
  ^ self _setConfig: aConfig grants: aGrantState accepted: anAccepted committed: aCommitted seqSeen: aPair
    suspectTerm: aTerm rejoined: aBoolean rejoinBallot: aBallot tierFailed: aFailure fenced: aReason log: aLog
    loggedPromise: aPromise confirmed: false.

PBAcceptorState >> _setConfig: aConfig grants: aGrantState accepted: anAccepted committed: aCommitted seqSeen: aPair suspectTerm: aTerm rejoined: aBoolean rejoinBallot: aBallot tierFailed: aFailure fenced: aReason log: aLog loggedPromise: aPromise confirmed: isConfirmed
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
  log := aLog.
  loggedPromise := aPromise.
  confirmed := isConfirmed.
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

"Whether this node has still to confirm its storage root (L18, proto_db needs_confirmation):
 true from the attach (a new acceptor state) until the space starts its confirmation round
 (PBConfirmed), and again after forceRejoin."
PBAcceptorState >> needsConfirmation
  ^ confirmed not.

"The PBLoggedRoots of the log this acceptor is attached to: the identity of that log."
PBAcceptorState >> log
  ^ log.

"The highest promise written to the attached log (loaded with it, or appended by a step whose
 append was durable), 0 when none or when the promise recorded was written to another log
 (proto_db _logged_promise[0] is tier): a grant of a term at or below it appends no promise
 (proto_db _on_request, D50)."
PBAcceptorState >> loggedPromise
  ^ loggedPromise first == log ifTrue: [loggedPromise last] ifFalse: [0].

"This state with aGrantState, aTerm as suspectTerm, aBoolean as rejoined, aFailure as
 tierFailed (nil: none) and aPromise as the promise written to the attached log; the rest
 unchanged."
PBAcceptorState >> withGrants: aGrantState suspectTerm: aTerm rejoined: aBoolean tierFailed: aFailure loggedPromise: aPromise
  ^ self class basicNew _setConfig: config grants: aGrantState accepted: accepted committed: committed seqSeen: seqSeen
    suspectTerm: aTerm rejoined: aBoolean rejoinBallot: rejoinBallot tierFailed: aFailure fenced: fenced log: log
    loggedPromise: { log. aPromise } confirmed: confirmed.

"This state with the fields someAssociations name (#accepted, #committed, #seqSeen,
 #suspectTerm, #rejoinBallot, #confirmed) replaced by their values; the rest unchanged. Another
 name is PBValidationError."
PBAcceptorState >> with: someAssociations
  | d |
  d := Dictionary new.
  d at: #accepted put: accepted; at: #committed put: committed; at: #seqSeen put: seqSeen; at: #suspectTerm put: suspectTerm;
    at: #rejoinBallot put: rejoinBallot; at: #confirmed put: confirmed.
  someAssociations do: [:a |
    (d includesKey: a key) ifFalse: [^ PBValidationError signal: 'PBAcceptorState has no field ' , a key printString].
    d at: a key put: a value].
  ^ self class basicNew _setConfig: config grants: grants accepted: (d at: #accepted) committed: (d at: #committed)
    seqSeen: (d at: #seqSeen) copy suspectTerm: (d at: #suspectTerm) rejoined: rejoined rejoinBallot: (d at: #rejoinBallot)
    tierFailed: tierFailed fenced: fenced log: log loggedPromise: loggedPromise confirmed: (d at: #confirmed).

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

"The step of the acceptor of anAcceptorState for anEvent (an acceptor event) at t:
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

"The types whose vs must be this node's voter-set fingerprint (proto_db _FINGERPRINTED)."
PBCoordinatorCore class >> fingerprintedTypes
  ^ #('request' 'renew' 'query' 'replicate' 'store').

"The selector of the handler of messages of aType: aPrefix, the type in camel case (each '_'
 starts a capital), then ':in:now:'. 'permit_req' with 'received' is #receivedPermitReq:in:now:."
PBCoordinatorCore class >> handlerFor: aType prefix: aPrefix
  | out up |
  out := WriteStream on: String new.
  out nextPutAll: aPrefix.
  up := true.
  aType do: [:ch |
    ch = $_
      ifTrue: [up := true]
      ifFalse: [out nextPut: (up ifTrue: [ch asUppercase] ifFalse: [ch]). up := false]].
  out nextPutAll: ':in:now:'.
  ^ out contents asSymbol.

"Whether aMessage comes from another member of aConfig (proto_db _route drops the rest)."
PBCoordinatorCore >> _fromPeer: aMessage in: aConfig
  ^ aMessage from ~= aConfig nodeId and: [aConfig membership ids includes: aMessage from].

"Whether aMessage comes from a member of aConfig, this node included."
PBCoordinatorCore >> _fromMember: aMessage in: aConfig
  ^ aConfig membership ids includes: aMessage from.

"A message of a peer (coordinator.py _route): a sender that is not another member is dropped; a
 fingerprinted type of another voter set is dropped and counted (config_mismatches, D54); the
 rest goes to the handler of its type (received<Type>:in:now:, defined by the module of its
 concern), and a type no module handles is ignored."
PBCoordinatorCore >> dispatchReceived: anEvent in: aNodeState now: t
  | m handler |
  m := anEvent message.
  (self _fromPeer: m in: aNodeState config) ifFalse: [^ self _unchanged: aNodeState].
  ((self class fingerprintedTypes includes: m type) and: [(m at: 'vs') ~= aNodeState config membership fingerprint]) ifTrue: [
    "Configured with another voter set (D54): two sets could form two disjoint majorities, so
     nothing it asks for is granted, answered or accepted here."
    ^ PBStep state: aNodeState effects: { PBCount stat: 'config_mismatches' }].
  handler := self class handlerFor: m type prefix: 'received'.
  (self respondsTo: handler) ifFalse: [^ self _unchanged: aNodeState].
  ^ self perform: handler with: anEvent with: aNodeState with: t.

"A timer came due; a token that is not current is ignored by the rule that set it."
PBCoordinatorCore >> dispatchTimerFired: anEvent in: aNodeState now: t
  ^ self _unchanged: aNodeState.

"The node starts (proto_db start, then _attach_locked): its acceptor runs its start step
 (acceptStart:in:now:) over the log it was built on. A later concern that adds to the start
 keeps this effect."
PBCoordinatorCore >> dispatchStartNode: anEvent in: aNodeState now: t
  ^ PBStep state: aNodeState effects: { PBToAcceptor event: anEvent }.

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

PBCoordinatorCore >> dispatchAcceptorDecided: anEvent in: aNodeState now: t
  ^ self _unchanged: aNodeState.

PBCoordinatorCore >> dispatchAcceptorDiscarded: anEvent in: aNodeState now: t
  ^ self _unchanged: aNodeState.

"--- the acceptor's rule methods ---"

"A message for the acceptor lane (proto_db _work): one from a sender that is not a member is
 dropped (the dispatcher drops it already; the lane does not trust that), the rest goes to the
 handler of its type (accept<Type>:in:now:), and a type no module handles is ignored. A message
 of this node itself is taken: the dispatcher never forwards one it received (it drops them,
 as proto_db _route), so only its own vote, renewal and release reach the lane from it (CC1),
 and they are decided by the rules that decide a peer's."
PBCoordinatorCore >> acceptReceived: anEvent in: anAcceptorState now: t
  | handler |
  (self _fromMember: anEvent message in: anAcceptorState config) ifFalse: [^ self _unchangedAcceptor: anAcceptorState].
  handler := self class handlerFor: anEvent message type prefix: 'accept'.
  (self respondsTo: handler) ifFalse: [^ self _unchangedAcceptor: anAcceptorState].
  ^ self perform: handler with: anEvent with: anAcceptorState with: t.

PBCoordinatorCore >> acceptStart: anEvent in: anAcceptorState now: t
  ^ self _unchangedAcceptor: anAcceptorState.
