"EXPECT: ok 11"
"PBTcpTransport (cluster/transport.st): length-prefixed frames over TCP (proto_db
 cluster/transport.py TcpTransport), one listener actor, one reader actor per accepted
 connection, one sender actor per peer. Every transport listens on 127.0.0.1, port 0, through
 withListener:, so its port is known before the membership is built. (1) Three transports
 exchange 100 messages with each other peer, every one delivered, in order per sender. (2) A
 connection that sends message-not-a-map.bin is closed by the receiver, and the next valid
 frame, on a new connection, arrives. (3) A length over 64 MiB (message-oversized.bin, the 4
 length bytes alone) closes the connection: the reader never waits for the body. (4) Frames
 split into 3-byte writes and frames coalesced in one write are all delivered, in order. (5) A
 peer that accepts and never reads (a black hole) does not delay the 100 messages to a live
 peer (lesson L7): the sender toward the hole is blocked in a write with a 10-minute timeout,
 and stop wakes it. (6) Two different keys: nothing is delivered and frames_rejected counts the
 refusals (Review Focus 4). (7) A message to a peer not yet listening is dropped, and once the
 peer listens a later one arrives. (8) A send after stop is a silent drop. (9) A transport starts
 once; a message to an unknown peer or to the node itself is dropped and counted. (10) listenOn:
 host: binds a free port for port 0 and refuses a port in use. (11) A peer restarts on its port:
 the frames written into the old, dead connection are lost (as in proto_db), the write that
 fails is retried at once on a new connection, and nothing is dropped. Every transport but
 those of check (10) has a 60 s connect and write timeout (requestTimeout:), so no outcome
 depends on how fast a loaded machine connects or writes. Every wait is for a
 condition with a generous deadline (60 s at least) that turns a hang into a failure; nothing
 asserts a duration. A raw socket's read has a 60 s timeout, so a connection the receiver
 failed to close fails the check instead of hanging."
Import from: 'protobase'.
Import from: 'net'.
Import from: '_check'.

"A handler that keeps every message it is given, in an Atom (readers run on several threads)."
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

"The terms of the messages from anId, in arrival order."
Inbox >> termsFrom: anId
  ^ (items value select: [:m | m from = anId]) collect: [:m | m at: 'term'].

Inbox >> handler
  ^ [:m | self add: m].

"A peer that accepts one connection and never reads from it."
Object subclass: #Hole.

Hole >> acceptOn: aServer
  ^ aServer accept.

| c request listen membership await stats vectors ids ts inboxes raw rawRead ok a b hole holeServer held big
  key2 reserved port server delivered before frames t0 |
c := Check new.
request := [:from :t | PBClusterMessage type: 'request' from: from fields: { 'term' -> t. 'rid' -> t. 'inc' -> 0. 'vs' -> 0 }].
listen := [PBTcpTransport withListener: (ServerSocket listenOn: 0 host: '127.0.0.1') requestTimeout: 60000].
"The membership of anArray of { id. port }."
membership := [:pairs | PBMembership peers: (pairs collect: [:p | PBPeer nodeId: p first host: '127.0.0.1' port: p last]) voters: nil].
"Whether aBlock became true within the deadline (60 s at least), checked every 10 ms."
await := [:aBlock |
  | tries |
  tries := 0.
  [aBlock value or: [tries >= 6000]] whileFalse: [(Future after: 10) wait. tries := tries + 1].
  aBlock value].
stats := [:t :name | t stats at: name].
vectors := '../conformance/vectors/' asFileReference.
"A raw connection to aTransport."
raw := [:aTransport | (Socket connectTo: '127.0.0.1' port: aTransport port timeout: 60000) timeout: 60000; yourself].
"What a read of one byte answers on aSocket: nil when the peer closed it, else what came."
rawRead := [:aSocket | [aSocket nextBytes: 1] on: Error do: [:e | e class name]].

"(1) Three transports, 100 messages to each other peer."
ids := #('n0' 'n1' 'n2').
ts := ids collect: [:id | listen value].
inboxes := ids collect: [:id | Inbox new].
1 to: 3 do: [:i | (ts at: i) start: (ids at: i)
  peers: (membership value: ((1 to: 3) asArray collect: [:j | { ids at: j. (ts at: j) port }]))
  key: nil handler: (inboxes at: i) handler].
1 to: 100 do: [:t |
  1 to: 3 do: [:i | 1 to: 3 do: [:j | i = j ifFalse: [(ts at: i) send: (request value: (ids at: i) value: t) to: (ids at: j)]]]].
await value: [inboxes allSatisfy: [:box | box size >= 200]].
ok := (1 to: 3) asArray collect: [:i |
  (1 to: 3) allSatisfy: [:j | i = j or: [((inboxes at: i) termsFrom: (ids at: j)) = (1 to: 100) asArray]]].
c that: 'three transports on port 0 exchange 100 messages with each peer, all delivered in order'
  is: { inboxes collect: [:box | box size]. ok. ts collect: [:t | stats value: t value: 'frames_sent']. (ts at: 1) port ~= (ts at: 2) port }
  equals: { #(200 200 200). #(true true true). #(200 200 200). true }.

"(2) A frame that is not a map closes its connection, not the listener."
b := ts at: 2.
held := raw value: b.
held nextPutBytes: (vectors / 'invalid' / 'message-not-a-map.bin') binaryContents.
before := rawRead value: held.
held close.
held := raw value: b.
held nextPutBytes: (vectors / 'cluster' / 'messages' / 'request.frame') binaryContents.
await value: [(inboxes at: 2) size >= 201].
c that: 'a connection sending message-not-a-map.bin is closed and the next valid frame on a new connection arrives'
  is: { before. (inboxes at: 2) size. (inboxes at: 2) items last type. stats value: b value: 'frames_rejected'.
    stats value: b value: 'connections_dropped' }
  equals: { nil. 201. 'request'. 1. 1 }.
held close.

"(3) An oversized length closes the connection without reading a body."
held := raw value: b.
held nextPutBytes: (vectors / 'invalid' / 'message-oversized.bin') binaryContents.
c that: 'a length over 64 MiB closes the connection before any body byte is read'
  is: { rawRead value: held. stats value: b value: 'frames_rejected'. stats value: b value: 'connections_dropped' }
  equals: #(nil 2 2).
held close.

"(4) Frames split across writes and coalesced in one write."
frames := (1 to: 10) asArray collect: [:t | PBClusterFrame encode: (request value: 'x' value: 1000 + t) to: 'n1' key: nil].
held := raw value: b.
held nextPutBytes: ((frames copyFrom: 1 to: 5) inject: ByteArray new into: [:all :f | all , f]).
t0 := (frames copyFrom: 6 to: 10) inject: ByteArray new into: [:all :f | all , f].
1 to: t0 size by: 3 do: [:i | held nextPutBytes: (t0 copyFrom: i to: (i + 2 min: t0 size))].
await value: [((inboxes at: 2) termsFrom: 'x') size >= 10].
c that: 'frames split across 3-byte writes and coalesced in one write are delivered in order'
  is: ((inboxes at: 2) termsFrom: 'x') equals: ((1001 to: 1010) asArray).
held close.
ts do: [:t | (t stop) waitWithin: 60000].

"(5) A black-holed peer does not delay the messages to a live peer (L7)."
holeServer := ServerSocket listenOn: 0 host: '127.0.0.1'.
hole := Hole new asActor acceptOn: holeServer.
a := PBTcpTransport withListener: (ServerSocket listenOn: 0 host: '127.0.0.1') requestTimeout: 600000.
b := listen value.
inboxes := { Inbox new. Inbox new }.
a start: 'a' peers: (membership value: { { 'a'. a port }. { 'b'. b port }. { 'hole'. holeServer port } })
  key: nil handler: (inboxes at: 1) handler.
b start: 'b' peers: (membership value: { { 'a'. a port }. { 'b'. b port }. { 'hole'. holeServer port } })
  key: nil handler: (inboxes at: 2) handler.
big := PBClusterMessage type: 'records' from: 'a' fields: { 'term' -> 1. 'rid' -> 1. 'inc' -> 0. 'index' -> 0.
  'records' -> { { ByteArray new: 16. 0. ByteArray new: 1048576 } } }.
"About 40 MiB toward the hole: far beyond the socket buffers, so its sender blocks in a write."
40 timesRepeat: [a send: big to: 'hole'].
1 to: 100 do: [:t | a send: (request value: 'a' value: t) to: 'b'].
await value: [(inboxes at: 2) size >= 100].
"The hole's sender is blocked: fewer than its 40 frames are written once b has all 100."
c that: 'a black-holed peer does not stop 100 messages to the live peer'
  is: { (inboxes at: 2) terms. (stats value: a value: 'frames_sent') < 140. ((a stop) waitWithin: 60000). ((b stop) waitWithin: 60000) }
  equals: { (1 to: 100) asArray. true. true. true }.
(hole waitWithin: 60000) close.
holeServer close.

"(6) Two different keys: nothing delivered, frames rejected."
a := listen value. b := listen value.
inboxes := { Inbox new. Inbox new }.
key2 := { ByteArray withAll: ((1 to: 32) asArray collect: [:i | i * 3 \\ 256]). ByteArray withAll: ((1 to: 32) asArray collect: [:i | i * 5 \\ 256]) }.
a start: 'a' peers: (membership value: { { 'a'. a port }. { 'b'. b port } }) key: key2 first handler: (inboxes at: 1) handler.
b start: 'b' peers: (membership value: { { 'a'. a port }. { 'b'. b port } }) key: key2 last handler: (inboxes at: 2) handler.
1 to: 5 do: [:t | a send: (request value: 'a' value: t) to: 'b'. b send: (request value: 'b' value: t) to: 'a'].
await value: [(stats value: a value: 'frames_rejected') > 0 and: [(stats value: b value: 'frames_rejected') > 0]].
"Every frame each side sent is accounted for (written or dropped) before nothing delivered is asserted."
await value: [{ a. b } allSatisfy: [:t | (stats value: t value: 'frames_sent') + (stats value: t value: 'frames_dropped') >= 5]].
c that: 'two different keys: nothing is delivered and frames_rejected counts the refusals'
  is: { (inboxes at: 1) size. (inboxes at: 2) size. (stats value: a value: 'frames_rejected') > 0. (stats value: b value: 'frames_rejected') > 0.
    (stats value: b value: 'connections_dropped') > 0 }
  equals: { 0. 0. true. true. true }.
(a stop) waitWithin: 60000. (b stop) waitWithin: 60000.

"(7) A peer not yet listening: dropped, then a later message arrives."
reserved := ServerSocket listenOn: 0 host: '127.0.0.1'.
port := reserved port.
reserved close.
a := listen value.
inboxes := { Inbox new. Inbox new }.
a start: 'a' peers: (membership value: { { 'a'. a port }. { 'b'. port } }) key: nil handler: (inboxes at: 1) handler.
a send: (request value: 'a' value: 1) to: 'b'.
await value: [(stats value: a value: 'frames_dropped') >= 1].
before := stats value: a value: 'frames_dropped'.
server := ServerSocket listenOn: port host: '127.0.0.1'.
b := PBTcpTransport withListener: server requestTimeout: 60000.
b start: 'b' peers: (membership value: { { 'a'. a port }. { 'b'. port } }) key: nil handler: (inboxes at: 2) handler.
await value: [(inboxes at: 2) size > 0 or: [a send: (request value: 'a' value: 2) to: 'b'. false]].
c that: 'a message to a peer not yet listening is dropped, and a later one arrives once it listens'
  is: { before >= 1. (inboxes at: 2) size > 0. (inboxes at: 2) terms asSet asArray }
  equals: { true. true. #(2) }.

"(8) A send after stop is a silent drop."
(a stop) waitWithin: 60000.
before := a stats.
a send: (request value: 'a' value: 3) to: 'b'.
c that: 'a send after stop is a silent drop'
  is: { a stats = before. ((a stop) waitWithin: 60000) }
  equals: { true. true }.
(b stop) waitWithin: 60000.

"(9) start is refused twice and after stop; an unknown peer is dropped and counted."
a := listen value.
a start: 'a' peers: (membership value: { { 'a'. a port } }) key: nil handler: [:m | nil].
a send: (request value: 'a' value: 1) to: 'nobody'.
a send: (request value: 'a' value: 1) to: 'a'.
c that: 'a transport starts once; a message to an unknown peer or to itself is dropped and counted'
  is: { [a start: 'a' peers: (membership value: { { 'a'. a port } }) key: nil handler: [:m | nil]. 'started'] on: PBValidationError do: [:e | 'refused'].
    stats value: a value: 'frames_dropped'. ((a stop) waitWithin: 60000).
    [a start: 'a' peers: (membership value: { { 'a'. a port } }) key: nil handler: [:m | nil]. 'started'] on: PBValidationError do: [:e | 'refused'] }
  equals: #('refused' 2 true 'refused').

"(10) listenOn:host: binds port 0; a port in use is refused."
a := PBTcpTransport listenOn: 0 host: '127.0.0.1'.
c that: 'listenOn:host: binds a free port for port 0 and refuses a port in use'
  is: { a port > 0. a requestTimeout. [PBTcpTransport listenOn: a port host: '127.0.0.1'. 'bound'] on: PBValidationError do: [:e | 'refused'].
    [PBTcpTransport listenOn: 0 host: '127.0.0.1' requestTimeout: 0. 'built'] on: PBValidationError do: [:e | 'refused'].
    ((a stop) waitWithin: 60000) }
  equals: #(true 1000 'refused' 'refused' true).

"(11) A restarted peer: only the frames written into the dead connection are lost."
a := listen value. b := listen value.
port := b port.
inboxes := { Inbox new. Inbox new }.
a start: 'a' peers: (membership value: { { 'a'. a port }. { 'b'. port } }) key: nil handler: (inboxes at: 1) handler.
b start: 'b' peers: (membership value: { { 'a'. a port }. { 'b'. port } }) key: nil handler: (inboxes at: 2) handler.
a send: (request value: 'a' value: 1) to: 'b'.
await value: [(inboxes at: 2) size >= 1].
(b stop) waitWithin: 60000.
b := PBTcpTransport withListener: (ServerSocket listenOn: port host: '127.0.0.1') requestTimeout: 60000.
inboxes := { inboxes first. Inbox new }.
b start: 'b' peers: (membership value: { { 'a'. a port }. { 'b'. port } }) key: nil handler: (inboxes at: 2) handler.
"One frame at a time: each is written (or dropped) before the next is sent."
2 to: 30 do: [:t |
  a send: (request value: 'a' value: t) to: 'b'.
  await value: [(stats value: a value: 'frames_sent') + (stats value: a value: 'frames_dropped') >= t]].
await value: [(inboxes at: 2) terms includes: 30].
t0 := (inboxes at: 2) terms.
c that: 'after a peer restarts, only frames written into the dead connection are lost: the failed write is retried on a new one'
  is: { stats value: a value: 'frames_dropped'. stats value: a value: 'frames_sent'. t0 notEmpty and: [t0 = (t0 first to: 30) asArray] }
  equals: { 0. 30. true }.
(a stop) waitWithin: 60000. (b stop) waitWithin: 60000.

c report displayNl.
