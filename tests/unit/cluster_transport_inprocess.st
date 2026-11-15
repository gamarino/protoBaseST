"EXPECT: ok 9"
"PBInProcessNetwork and PBInProcessTransport (cluster/transport.st): peers inside one process
 (proto_db cluster/transport.py InProcessNetwork, InProcessTransport). Every message is put in
 a frame by its sender (PBClusterFrame encode:to:key:, with the sender's key) and decoded by
 its receiver (with the receiver's key), so the codec runs on every message and the receiver
 gets a new PBClusterMessage, never the sender's. (1) Twenty messages from n0 arrive at n1
 decoded and in order. (2) A reply travels on the replier's own endpoint. (3) A keyed endpoint
 and an unkeyed one drop each other's frames, counted in frames_rejected, one each. (4) After
 the Future stop answers has settled, nothing more is delivered: messages to the stopped node
 are dropped and counted by their sender. (5) The drop and duplicate faults. (6) A partition
 drops what crosses it and heal ends it. (7) A stopped (crashed) node neither sends nor
 receives. (8) What is not a PBClusterMessage is refused before anything is sent. (9) A
 PBDBError signalled by the handler for one message is logged on stderr, and delivery goes on
 with the next one. Every wait is for a condition with a generous deadline that turns a hang
 into a failure; nothing asserts a duration. The tests of the fault-injecting network that
 delay messages have no counterpart here: delays and reordering are the simulator's
 (PBSimFaults delay:reorder:, in virtual time), where they cannot make a test depend on timing."
Import from: 'protobase'.
Import from: '_check'.

"A handler that keeps every message it is given, in an Atom (handlers run on another thread)."
Object subclass: #Inbox instanceVariableNames: 'items'.

Inbox class >> new
  ^ self basicNew setItems.

Inbox >> setItems
  items := Atom on: #().

Inbox >> add: aMessage
  items swap: [:all | all copyWith: aMessage].

Inbox >> items
  ^ items value.

Inbox >> size
  ^ items value size.

Inbox >> terms
  ^ items value collect: [:m | m at: 'term'].

Inbox >> handler
  ^ [:m | self add: m].

| c peers members request await stats net a b ia ib sent got reply keyed key before stopped probe |
c := Check new.
peers := #('n0' 'n1') collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 0].
members := PBMembership peers: peers voters: nil.
request := [:from :t | PBClusterMessage type: 'request' from: from fields: { 'term' -> t. 'rid' -> t. 'inc' -> 0. 'vs' -> 0 }].
"Whether aBlock became true within the deadline (60 s at least), checked every 10 ms."
await := [:aBlock |
  | tries |
  tries := 0.
  [aBlock value or: [tries >= 6000]] whileFalse: [(Future after: 10) wait. tries := tries + 1].
  aBlock value].
stats := [:t :name | t stats at: name].
"Two started endpoints n0 and n1 of a new network, with their inboxes."
key := ByteArray withAll: ((1 to: 32) asArray collect: [:i | i * 11 \\ 256]).

"(1) In order and decoded."
net := PBInProcessNetwork seed: 1.
a := net endpoint. b := net endpoint. ia := Inbox new. ib := Inbox new.
a start: 'n0' peers: members key: nil handler: ia handler.
b start: 'n1' peers: members key: nil handler: ib handler.
sent := (1 to: 20) asArray collect: [:t | request value: 'n0' value: t].
sent do: [:m | a send: m to: 'n1'].
await value: [ib size >= 20].
got := ib items.
c that: 'without faults, 20 messages from n0 arrive at n1 decoded and in order'
  is: { ib terms. got first == sent first. got first encode = sent first encode. got first from. stats value: a value: 'frames_sent' }
  equals: { (1 to: 20) asArray. false. true. 'n0'. 20 }.
(a stop) waitWithin: 60000. (b stop) waitWithin: 60000.

"(2) A reply travels on the replier's own endpoint."
net := PBInProcessNetwork new.
a := net endpoint. b := net endpoint. ia := Inbox new. ib := Inbox new.
reply := [:m | ib add: m.
  b send: (PBClusterMessage type: 'permit_req' from: 'n1' fields: { 'term' -> (m at: 'term'). 'rid' -> 1. 'inc' -> 0 }) to: m from].
a start: 'n0' peers: members key: nil handler: ia handler.
b start: 'n1' peers: members key: nil handler: reply.
a send: (request value: 'n0' value: 7) to: 'n1'.
await value: [ia size >= 1].
c that: 'a reply travels on the replier''s own endpoint'
  is: { ia items first type. ia items first from. ia terms. stats value: a value: 'frames_sent'. stats value: b value: 'frames_sent' }
  equals: { 'permit_req'. 'n1'. #(7). 1. 1 }.
(a stop) waitWithin: 60000. (b stop) waitWithin: 60000.

"(3) A keyed endpoint and an unkeyed one drop each other's frames."
net := PBInProcessNetwork new.
a := net endpoint. b := net endpoint. ia := Inbox new. ib := Inbox new.
a start: 'n0' peers: members key: key handler: ia handler.
b start: 'n1' peers: members key: nil handler: ib handler.
a send: (request value: 'n0' value: 1) to: 'n1'.
b send: (request value: 'n1' value: 1) to: 'n0'.
await value: [(stats value: a value: 'frames_rejected') >= 1 and: [(stats value: b value: 'frames_rejected') >= 1]].
c that: 'a keyed endpoint and an unkeyed one drop each other''s frames'
  is: { stats value: a value: 'frames_rejected'. stats value: b value: 'frames_rejected'. ia size. ib size.
    stats value: a value: 'connections_dropped' }
  equals: #(1 1 0 0 0).
(a stop) waitWithin: 60000. (b stop) waitWithin: 60000.

"(4) Nothing is delivered once the Future of stop has settled."
net := PBInProcessNetwork new.
a := net endpoint. b := net endpoint. ia := Inbox new. ib := Inbox new.
a start: 'n0' peers: members key: nil handler: ia handler.
b start: 'n1' peers: members key: nil handler: ib handler.
1 to: 50 do: [:t | a send: (request value: 'n0' value: t) to: 'n1'].
stopped := (b stop) waitWithin: 60000.
before := ib size.
1 to: 3 do: [:t | a send: (request value: 'n0' value: 100 + t) to: 'n1'].
c that: 'stop delivers nothing more: later messages are dropped and counted by their sender'
  is: { stopped. ib size = before. ib terms = ((1 to: before) asArray). stats value: a value: 'frames_dropped'.
    ((b stop) waitWithin: 60000) }
  equals: { true. true. true. 3. true }.
(a stop) waitWithin: 60000.

"(5) Drop and duplicate faults."
net := PBInProcessNetwork seed: 2.
a := net endpoint. b := net endpoint. ia := Inbox new. ib := Inbox new.
a start: 'n0' peers: members key: nil handler: ia handler.
b start: 'n1' peers: members key: nil handler: ib handler.
net drop: 1 duplicate: 0.
a send: (request value: 'n0' value: 1) to: 'n1'.
net drop: 0 duplicate: 1.
a send: (request value: 'n0' value: 2) to: 'n1'.
"A probe sent after them, without faults, arrives after anything they delivered (one inbox, in order)."
net drop: 0 duplicate: 0.
a send: (request value: 'n0' value: 3) to: 'n1'.
await value: [ib terms includes: 3].
c that: 'the drop fault loses a message and the duplicate fault delivers one twice'
  is: { ib terms. stats value: a value: 'frames_dropped'. stats value: a value: 'frames_sent' }
  equals: { #(2 2 3). 1. 2 }.
(a stop) waitWithin: 60000. (b stop) waitWithin: 60000.

"(6) Partition and heal."
net := PBInProcessNetwork new.
a := net endpoint. b := net endpoint. ia := Inbox new. ib := Inbox new.
a start: 'n0' peers: members key: nil handler: ia handler.
b start: 'n1' peers: members key: nil handler: ib handler.
net partition: #(#('n0') #('n1')).
a send: (request value: 'n0' value: 1) to: 'n1'.
b send: (request value: 'n1' value: 1) to: 'n0'.
net heal.
a send: (request value: 'n0' value: 2) to: 'n1'.
b send: (request value: 'n1' value: 3) to: 'n0'.
await value: [ib size >= 1 and: [ia size >= 1]].
c that: 'a partition drops what crosses it and heal ends it'
  is: { ib terms. ia terms. stats value: a value: 'frames_dropped'. stats value: b value: 'frames_dropped' }
  equals: #(#(2) #(3) 1 1).
(a stop) waitWithin: 60000. (b stop) waitWithin: 60000.

"(7) A crashed (stopped) node neither sends nor receives; a third node shows the network works."
net := PBInProcessNetwork new.
members := PBMembership peers: (#('n0' 'n1' 'n2') collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 0]) voters: nil.
a := net endpoint. b := net endpoint. probe := net endpoint. ia := Inbox new. ib := Inbox new.
a start: 'n0' peers: members key: nil handler: ia handler.
b start: 'n1' peers: members key: nil handler: ib handler.
probe start: 'n2' peers: members key: nil handler: [:m | nil].
(b stop) waitWithin: 60000.
a send: (request value: 'n0' value: 1) to: 'n1'.
b send: (request value: 'n1' value: 1) to: 'n0'.
probe send: (request value: 'n2' value: 9) to: 'n0'.
await value: [ia size >= 1].
c that: 'a crashed node neither sends nor receives'
  is: { ia terms. ib size. stats value: a value: 'frames_dropped'. stats value: b value: 'frames_sent'.
    stats value: b value: 'frames_dropped' }
  equals: #(#(9) 0 1 0 0).
(a stop) waitWithin: 60000. (probe stop) waitWithin: 60000.

"(8) Every message goes through the wire encoding: what is not a message is refused."
net := PBInProcessNetwork new.
a := net endpoint. b := net endpoint. ib := Inbox new.
a start: 'n0' peers: members key: nil handler: [:m | nil].
b start: 'n1' peers: members key: nil handler: ib handler.
c that: 'a message goes through the wire encoding: what is not a PBClusterMessage is refused'
  signals: PBValidationError containing: 'PBClusterMessage'
  during: [a send: (MessagePackMap withAll: { 'v' -> 13. 'type' -> 'nonsense'. 'from' -> 'n0' }) to: 'n1'].

"(9) A handler's PBDBError is logged and delivery goes on (proto_db _deliver)."
(b stop) waitWithin: 60000.
b := net endpoint. ib := Inbox new.
b start: 'n1' peers: members key: nil handler: [:m |
  (m at: 'term') = 1 ifTrue: [PBClusterProtocolError signal: 'the done message lacks its copies'].
  ib add: m].
a send: (request value: 'n0' value: 1) to: 'n1'.
a send: (request value: 'n0' value: 2) to: 'n1'.
await value: [ib size >= 1].
c that: 'a PBDBError signalled by the handler is logged and the next message is delivered'
  is: { ib terms. stats value: b value: 'frames_rejected' }
  equals: #(#(2) 0).
(a stop) waitWithin: 60000. (b stop) waitWithin: 60000.

c report displayNl.
