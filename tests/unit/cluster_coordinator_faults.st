"EXPECT: ok 9"
"The coordinator shell's faults (cluster/coordinator.st, Task 20 fix round 1), over
 PBInProcessNetwork and MemoryTier (_cluster_shell.st). The order of the events is controlled by
 test doubles, never by timing: every wait is a condition with a deadline of 60 s.
 (1) A fence raised on the dispatcher while a peer's request waits in the acceptor's mailbox: the
 acceptor (held at a gate until the fence has landed) reads the fence before it decides, so it
 neither grants, rejects nor writes a promise (review I1; proto_db _refusal reads _failure at
 decision time); the fenced dispatcher then drops a peer's permit request and want, and only
 the fenced acceptor answers (a plain query). (2) A fence raised on the dispatcher reaches the acceptor state with no acceptor
 event behind it (the dispatcher hands the acceptor the fence), and the request it interrupted is
 rejected with PBUnexpectedError. (3) A peer's message whose rule signals a PBDBError (a done
 teaching a root that clashes with the accepted one: PBRootOrder's protocol violation) is
 dropped, the node not fenced (proto_db _work logs a ProtoDBError and carries on; review I2), and
 the cluster still commits. (4) A replication whose root is not labelled with its permission's
 term is rejected PBValidationError to its caller, the node not fenced (review M2). (5) A
 protocol violation after the root was sent is not an unknown outcome (proto_db
 test_x4_a_protocol_violation_after_the_root_was_sent_is_not_an_unknown_outcome): with a sibling
 of the root planted as the holder's accepted root, the replication is rejected with
 PBCorruptionError naming the violation, counted replication_failures; the same with the sibling
 planted as its committed root (proto_db _observe_committed, coordinator.py 1725). (6) A
 PBDBError while the effects of a step are performed (after its state was published) fences the
 node, and a replication whose voters were sent the root settles #unknown; on the acceptor, an
 error in the reply of a step it decided fences too (review N1). (7) A
 PBDBError in the acceptor's decision of this node's own request or replicate is handed to the
 dispatcher (PBOwnStepFailed): the permit waiter is rejected with it, the replication with the
 protocol violation, at once (review N2; proto_db raises it to the caller)."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_cluster_shell'.

PBEffect subclass: #PlantedFault.

PBEffect subclass: #PlantedDBFault.

PlantedDBFault >> applyTo: aShell
  ^ PBValidationError signal: 'planted effect failure'.

PlantedFault >> applyTo: aShell
  ^ Error signal: 'planted dispatcher fault'.

PBCoordinatorCore subclass: #ArmedRules instanceVariableNames: 'armed gate plant'.

ArmedRules class >> armed: aSymbol
  ^ self basicNew setArmed: (Atom on: aSymbol) gate: Future new plant: (Atom on: nil).

ArmedRules >> setArmed: anAtom gate: aFuture plant: aPlantAtom
  armed := anAtom.
  gate := aFuture.
  plant := aPlantAtom.

ArmedRules >> gate
  ^ gate.

ArmedRules >> arm: aSymbol
  armed swap: [:old | aSymbol].

ArmedRules >> plant
  ^ plant.

"Whether the fault armed for aSymbol fires now (once)."
ArmedRules >> fire: aSymbol
  ^ armed value: nil ifCurrent: aSymbol.

"A peer's request: handed to the acceptor, then a fault on the dispatcher."
ArmedRules >> dispatchReceived: anEvent in: s now: t
  | step m |
  m := anEvent message.
  step := super dispatchReceived: anEvent in: s now: t.
  (m type = 'request' and: [m from ~= s config nodeId and: [self fire: #request]]) ifFalse: [^ step].
  ^ PBStep state: step state effects: step effects , { PlantedFault new }.

"A replication: its sends, then a PBDBError while its effects are performed (armed #effects)."
ArmedRules >> dispatchReplicateWanted: anEvent in: s now: t
  | step |
  step := super dispatchReplicateWanted: anEvent in: s now: t.
  (self fire: #effects) ifFalse: [^ step].
  ^ PBStep state: step state effects: step effects , { PlantedDBFault new }.

"The acceptor's decision of this node's own request (armed #ownRequest: PBValidationError) or
 own replicate (armed #ownReplicate: PBCorruptionError) signals."
ArmedRules >> accept: anEvent in: s now: t
  ((anEvent isKindOf: PBReceived) and: [anEvent message from = s config nodeId]) ifTrue: [
    (anEvent message type = 'request' and: [self fire: #ownRequest]) ifTrue: [
      ^ PBValidationError signal: 'planted own request failure'].
    (anEvent message type = 'replicate' and: [self fire: #ownReplicate]) ifTrue: [
      ^ PBCorruptionError signal: 'Protocol violation: planted own acceptance failure']].
  ((anEvent isKindOf: PBReceived) and: [anEvent message type = 'request' and: [self fire: #acceptEffects]]) ifTrue: [
    | step |
    step := super accept: anEvent in: s now: t.
    ^ PBAcceptorStep state: step state appends: step appends reply: step reply , { PlantedDBFault new }
      vote: step vote learnt: step learnt].
  ^ super accept: anEvent in: s now: t.

ArmedRules >> dispatchConfirmed: anEvent in: s now: t
  (self fire: #confirmed) ifTrue: [^ PBStep state: s effects: { PlantedFault new }].
  ^ super dispatchConfirmed: anEvent in: s now: t.

"An acceptor held at the rules' gate before it handles a peer's request."
_PBAcceptor subclass: #GatedAcceptor.

GatedAcceptor >> handle: anEvent
  ((anEvent isKindOf: PBReceived) and: [anEvent message type = 'request' and: [anEvent message from ~= cells config nodeId]])
    ifFalse: [^ super handle: anEvent].
  rules gate wait.
  ^ super handle: anEvent.

"An acceptor that plants the rules' plant, { #accepted or #committed. a root }, in its state
 before its own replication (the corrupted state of proto_db's x4)."
_PBAcceptor subclass: #PlantingAcceptor.

PlantingAcceptor >> handle: anEvent
  | clash |
  ((anEvent isKindOf: PBReceived) and: [anEvent message type = 'replicate' and: [anEvent message from = cells config nodeId]])
    ifTrue: [
      clash := rules plant value.
      (clash notNil and: [rules plant value: nil ifCurrent: clash]) ifTrue: [
        cells acceptorState swap: [:s | s with: { clash first -> clash last }]]].
  ^ super handle: anEvent.

| x4 n c kit three nodes rules out a b f r p base root clash n0end vs barrier |
c := Check new.
three := #('n0' 'n1' 'n2').

"--- (1) a dispatcher fence while a request waits in the acceptor's mailbox ---"
kit := ShellKit ids: three.
rules := ArmedRules armed: #request.
nodes := three collect: [:id | id = 'n2'
  ifTrue: [kit node: id options: Dictionary new rules: rules acceptorClass: GatedAcceptor]
  ifFalse: [kit node: id]].
a := three collect: [:id | MemoryTier served: id trace: kit trace].
nodes do: [:x | x start].
(1 to: 3) do: [:i | ((nodes at: i) _attach: (a at: i)) waitWithin: 60000].
out := kit commitOn: nodes first offset: 1.
f := kit waitUntil: [(nodes at: 3) isFenced].
rules gate resolve: true.
b := kit waitUntil: [(nodes at: 3) acceptorState fenced notNil].
"A fenced dispatcher drops a peer's own-lane messages (proto_db _enqueue refuses them): a permit
 request and a want reach no rule (the node state is left as it was); a plain query, answered by the fenced acceptor, is the barrier."
vs := nodes first config membership fingerprint.
n0end := (nodes at: 3) nodeState.
n := (kit trace value select: [:l | l beginsWith: 'n2 send answer to n0']) size.
nodes first config transport send: (PBClusterMessage type: 'permit_req' from: 'n0' fields: { 'term' -> 1. 'rid' -> 5. 'inc' -> 1 }) to: 'n2'.
nodes first config transport send: (PBClusterMessage type: 'want' from: 'n0' fields: #()) to: 'n2'.
nodes first config transport send: (PBClusterMessage type: 'query' from: 'n0' fields: { 'rid' -> 76. 'inc' -> 1. 'ballot' -> 0. 'vs' -> vs }) to: 'n2'.
barrier := kit waitUntil: [(kit trace value select: [:l | l beginsWith: 'n2 send answer to n0']) size > n].
c that: 'a fenced dispatcher drops a peer''s permit request and want; the fenced acceptor answers a plain query'
  is: { barrier. kit trace value select: [:l | (l beginsWith: 'n2 send') and: [(l beginsWith: 'n2 send answer') not
    and: [(l beginsWith: 'n2 send ack') not]]]. (nodes at: 3) nodeState == n0end }
  equals: { true. #(). true }.
c that: 'a fence raised on the dispatcher stops a request queued before it: nothing granted, rejected or written'
  is: { out first. f. b. kit trace value select: [:l | (l beginsWith: 'n2 send grant') or: [l beginsWith: 'n2 send reject']].
    (a at: 3) payloads size. ((nodes at: 3) acceptorState fenced includesSubstring: 'planted dispatcher fault') }
  equals: { #committed. true. true. #(). 1. true }.
kit stopAll: nodes.

"--- (2) the dispatcher hands the acceptor its fence ---"
kit := ShellKit ids: three.
rules := ArmedRules armed: #confirmed.
n0end := kit node: 'n2' options: Dictionary new rules: rules acceptorClass: _PBAcceptor.
n0end start.
(n0end _attach: (MemoryTier served: 'n2' trace: kit trace)) waitWithin: 60000.
r := kit settle: n0end _confirmed.
f := kit waitUntil: [n0end acceptorState fenced notNil].
c that: 'a dispatcher fence reaches the acceptor state with no acceptor event behind it; the request is refused'
  is: { r first. (r at: 2) class name. f. n0end isFenced. n0end stats at: 'fenced' }
  equals: { #error. #PBUnexpectedError. true. true. true }.
n0end stop waitWithin: 60000.

"--- (3), (4) a PBDBError in a rule drops the message, never fences ---"
kit := ShellKit ids: three.
nodes := three collect: [:id | kit node: id].
nodes do: [:x | x start].
(1 to: 3) do: [:i | ((nodes at: i) _attach: (MemoryTier served: (three at: i) trace: kit trace)) waitWithin: 60000].
out := kit commitOn: nodes first offset: 1.
root := out at: 3.
f := kit waitUntil: [(nodes at: 2) acceptorState accepted notNil and: [(nodes at: 2) acceptorState accepted key = root key]].
clash := PBLabeledRoot label: root label record: (PBRootRecord segment: (ByteArray new: 16) offset: 999 epoch: root epoch).
vs := nodes first config membership fingerprint.
nodes first config transport send: (PBClusterMessage type: 'done' from: 'n0' fields: { 'term' -> root label. 'seq' -> 1.
  'inc' -> 1. 'outcome' -> 'committed'. 'root' -> (PBClusterMessage rootValue: clash). 'copies' -> #(). 'ranges' -> nil }) to: 'n1'.
nodes first config transport send: (PBClusterMessage type: 'query' from: 'n0' fields: { 'rid' -> 77. 'inc' -> 1. 'ballot' -> 0. 'vs' -> vs }) to: 'n1'.
barrier := kit waitUntil: [kit trace value anySatisfy: [:l | l beginsWith: 'n1 send answer to n0']].
r := kit commitOn: nodes first offset: 2.
c that: 'a peer''s message whose rule signals a PBDBError is dropped; the node is not fenced and the cluster commits'
  is: { out first. f. barrier. (nodes at: 2) isFenced. (nodes at: 2) stats at: 'healthy'. r first.
    (nodes at: 2) acceptorState accepted key = (r at: 3) key }
  equals: { #committed. true. true. false. true. #committed. true }.
p := (kit settle: nodes first _permit) at: 2.
base := (kit settle: (nodes first _baseFor: p)) at: 2.
r := kit settle: (nodes first _replicate: (PBLabeledRoot label: p term + 1
  record: (PBRootRecord segment: (ByteArray new: 16) offset: 5 epoch: base base epoch + 1)) under: p).
(nodes first _done: p outcome: #none) waitWithin: 60000.
c that: 'a replication whose root is not labelled with its term is refused to its caller; the node is not fenced'
  is: { r first. (r at: 2) class name. nodes first isFenced. (kit commitOn: nodes first offset: 6) first }
  equals: { #error. #PBValidationError. false. #committed }.
kit stopAll: nodes.

"--- (5) x4: a protocol violation after the root was sent ---"
x4 := [:where | | k ns rl pp bb cl rt rr |
  k := ShellKit ids: three.
  rl := ArmedRules armed: nil.
  ns := three collect: [:id | id = 'n0'
    ifTrue: [k node: id options: Dictionary new rules: rl acceptorClass: PlantingAcceptor]
    ifFalse: [k node: id]].
  ns do: [:x | x start].
  (1 to: 3) do: [:i | ((ns at: i) _attach: (MemoryTier served: (three at: i) trace: k trace)) waitWithin: 60000].
  pp := (k settle: ns first _permit) at: 2.
  bb := (k settle: (ns first _baseFor: pp)) at: 2.
  cl := k rootUnder: pp on: bb base offset: 99.
  rt := k rootUnder: pp on: bb base offset: 1.
  rl plant value: { where. cl } ifCurrent: nil.
  rr := k settle: (ns first _replicate: rt under: pp).
  rr := { pp class name. rr first. (rr at: 2) class name.
    (((rr at: 2) isKindOf: Exception) and: [(rr at: 2) messageText includesSubstring: 'Protocol violation']).
    (ns first stats at: 'replication_failures') >= 1. ns first isFenced }.
  k stopAll: ns.
  rr].
c that: 'a protocol violation after the root was sent is reported as PBCorruptionError, not an unknown outcome'
  is: (x4 value: #accepted)
  equals: { #PBPermission. #error. #PBCorruptionError. true. true. false }.
c that: 'a replicated root clashing with the committed root the holder knows is reported as PBCorruptionError (proto_db _observe_committed)'
  is: (x4 value: #committed)
  equals: { #PBPermission. #error. #PBCorruptionError. true. true. false }.

"--- (6) an error while the effects of a step are performed fences; a replication sent is #unknown ---"
kit := ShellKit ids: three.
rules := ArmedRules armed: nil.
nodes := three collect: [:id | id = 'n0'
  ifTrue: [kit node: id options: Dictionary new rules: rules acceptorClass: _PBAcceptor]
  ifFalse: [id = 'n2'
    ifTrue: [kit node: id options: Dictionary new rules: (ArmedRules armed: #acceptEffects) acceptorClass: _PBAcceptor]
    ifFalse: [kit node: id]]].
nodes do: [:x | x start].
(1 to: 3) do: [:i | ((nodes at: i) _attach: (MemoryTier served: (three at: i) trace: kit trace)) waitWithin: 60000].
p := (kit settle: nodes first _permit) at: 2.
base := (kit settle: (nodes first _baseFor: p)) at: 2.
rules arm: #effects.
r := kit settle: (nodes first _replicate: (kit rootUnder: p on: base base offset: 1) under: p).
c that: 'a PBDBError while the effects of a step are performed fences the node; the replication sent is #unknown'
  is: { r. nodes first isFenced. kit trace value anySatisfy: [:l | l beginsWith: 'n0 send replicate'].
    kit waitUntil: [(nodes at: 3) isFenced]. (nodes at: 3) acceptorState fenced notNil and: [(nodes at: 3) acceptorState fenced includesSubstring: 'planted effect failure'] }
  equals: { #(#ok #unknown). true. true. true. true }.
kit stopAll: nodes.

"--- (7) a PBDBError in the acceptor's decision of an own message settles its waiter at once ---"
kit := ShellKit ids: three.
rules := ArmedRules armed: #ownRequest.
nodes := three collect: [:id | id = 'n0'
  ifTrue: [kit node: id options: Dictionary new rules: rules acceptorClass: _PBAcceptor]
  ifFalse: [kit node: id]].
nodes do: [:x | x start].
(1 to: 3) do: [:i | ((nodes at: i) _attach: (MemoryTier served: (three at: i) trace: kit trace)) waitWithin: 60000].
a := kit settle: nodes first _permit.
p := (kit settle: nodes first _permit) at: 2.
base := (kit settle: (nodes first _baseFor: p)) at: 2.
rules arm: #ownReplicate.
r := kit settle: (nodes first _replicate: (kit rootUnder: p on: base base offset: 1) under: p).
c that: 'a PBDBError in the acceptor''s decision of an own request or replicate settles its waiter with it; the node is not fenced'
  is: { a first. (a at: 2) class name. ((a at: 2) isKindOf: Exception) ifTrue: [(a at: 2) messageText] ifFalse: [nil].
    r first. (r at: 2) class name. ((r at: 2) isKindOf: Exception) ifTrue: [(r at: 2) messageText] ifFalse: [nil]. nodes first isFenced }
  equals: { #error. #PBValidationError. 'planted own request failure'. #error. #PBCorruptionError.
    'Protocol violation: planted own acceptance failure'. false }.
kit stopAll: nodes.

c report displayNl.
