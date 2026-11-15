"EXPECT: ok 6"
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
 PBCorruptionError naming the violation, counted replication_failures."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_cluster_shell'.

PBEffect subclass: #PlantedFault.

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

"An acceptor that plants the rules' plant as its accepted root before its own replication (the
 corrupted state of proto_db's x4)."
_PBAcceptor subclass: #PlantingAcceptor.

PlantingAcceptor >> handle: anEvent
  | clash |
  ((anEvent isKindOf: PBReceived) and: [anEvent message type = 'replicate' and: [anEvent message from = cells config nodeId]])
    ifTrue: [
      clash := rules plant value.
      (clash notNil and: [rules plant value: nil ifCurrent: clash]) ifTrue: [
        cells acceptorState swap: [:s | s with: { #accepted -> clash }]]].
  ^ super handle: anEvent.

| n c kit three nodes rules out a b f r p base root clash n0end vs barrier |
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
kit := ShellKit ids: three.
rules := ArmedRules armed: nil.
nodes := three collect: [:id | id = 'n0'
  ifTrue: [kit node: id options: Dictionary new rules: rules acceptorClass: PlantingAcceptor]
  ifFalse: [kit node: id]].
nodes do: [:x | x start].
(1 to: 3) do: [:i | ((nodes at: i) _attach: (MemoryTier served: (three at: i) trace: kit trace)) waitWithin: 60000].
p := (kit settle: nodes first _permit) at: 2.
base := (kit settle: (nodes first _baseFor: p)) at: 2.
clash := kit rootUnder: p on: base base offset: 99.
root := kit rootUnder: p on: base base offset: 1.
rules plant value: clash ifCurrent: nil.
r := kit settle: (nodes first _replicate: root under: p).
c that: 'a protocol violation after the root was sent is reported as PBCorruptionError, not an unknown outcome'
  is: { p class name. r first. (r at: 2) class name.
    (((r at: 2) isKindOf: Exception) and: [(r at: 2) messageText includesSubstring: 'Protocol violation']).
    (nodes first stats at: 'replication_failures') >= 1. nodes first isFenced }
  equals: { #PBPermission. #error. #PBCorruptionError. true. true. false }.
kit stopAll: nodes.

c report displayNl.
