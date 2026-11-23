"EXPECT: ok 8"
"PBTcpTransport (cluster/transport.st): a frame that arrives in parts, with read timeouts in
 between, is read on, never dropped. A reader's reads time out after pollInterval, so that its
 turn ends (cluster_transport_tcp_burial.st); a timeout in the middle of a frame means no more
 bytes yet, not the end of the connection: the frame read so far stays in the reader's state for
 the next turn, and the bytes that came during the timed-out read stay in the socket's buffer.

 (A) One reader's steps (_PBTcpReader >> _readStep), called from the program thread on a
 connection whose other end the test writes, so each timeout is certain: the step answers
 #waiting only when its read timed out. (1) Two of the four length bytes: the step waits; the
 other two: the length is read. (2) 1,500 bytes of a 3,084-byte body: one readChunk (1,024 bytes)
 is read, then the step waits, holding 1,024 bytes; the rest: the frame is delivered whole, once.
 (3) The next frame on the same connection, written whole, is delivered: the connection went on.
 Nothing was rejected.

 (B) The same frame through a running transport's reader actor: a raw connection to it writes
 the length and 1,500 body bytes, the test waits until the reader holds the first 1,024 body
 bytes (its read of the next 1,024 then times out every pollInterval while nothing more comes),
 then writes the rest: the frame is delivered whole, the connection stays open and nothing is
 rejected. Part (A) proves what a timeout keeps; part (B) proves the actor's turns carry it.

 Every wait is for a condition, checked every 10 ms, without a deadline: a frame that is lost
 keeps the test waiting until the runner's timeout fails it."
Import from: 'protobase'.
Import from: 'net'.
Import from: '_check'.

"A handler that keeps every message it is given, in an Atom (readers run on several threads)."
Object subclass: #Inbox instanceVariableNames: 'items'.

Inbox class >> new
  ^ self basicNew setItems.

Inbox >> setItems
  items := Atom on: #().

Inbox >> items
  ^ items value.

Inbox >> handler
  ^ [:m | items swap: [:all | all copyWith: m]].

| c b inbox membership await message frame frame2 server client accepted reader steps raw readerOf partialOf |
c := Check new.
membership := [:pairs | PBMembership peers: (pairs collect: [:p | PBPeer nodeId: p first host: '127.0.0.1' port: p last]) voters: nil].
"Until aBlock is true, checked every 10 ms; no deadline (the runner's timeout bounds the test)."
await := [:aBlock | [aBlock value] whileFalse: [(Future after: 10) wait]].
message := [:term :n | PBClusterMessage type: 'reject' from: 'a' fields: { 'term' -> term. 'rid' -> 1. 'inc' -> 0.
  'root' -> nil. 'certain' -> false. 'reason' -> (String new: n withAll: $x). 'highest' -> 0. 'remaining' -> 0 }].
frame := PBClusterFrame encode: (message value: 1 value: 3000) to: 'b' key: nil.
frame2 := PBClusterFrame encode: (message value: 2 value: 10) to: 'b' key: nil.

inbox := Inbox new.
b := PBTcpTransport withListener: (ServerSocket listenOn: 0 host: '127.0.0.1') requestTimeout: 60000.
b start: 'b' peers: (membership value: { { 'a'. 1 }. { 'b'. b port } }) key: nil handler: inbox handler.

"(A) The steps of one reader, on a connection the test accepted itself."
server := ServerSocket listenOn: 0 host: '127.0.0.1'.
client := Socket connectTo: '127.0.0.1' port: server port timeout: 60000.
accepted := server accept.
accepted timeout: PBTcpTransport pollInterval.
reader := _PBTcpReader transport: b socket: accepted nodeId: 'b' key: nil handler: inbox handler.
client nextPutBytes: (frame copyFrom: 1 to: 2).
steps := OrderedCollection new.
steps add: reader _readStep.
client nextPutBytes: (frame copyFrom: 3 to: 4).
steps add: reader _readStep.
c that: 'a timeout inside the length bytes waits, and the length is read once they all came'
  is: { steps asArray. (reader instVarNamed: 'partial') value first } equals: { #(#waiting #read). frame size - 4 }.

steps := OrderedCollection new.
client nextPutBytes: (frame copyFrom: 5 to: 1504).
steps add: reader _readStep.
steps add: reader _readStep.
c that: 'a timeout inside the body waits, holding the body read so far'
  is: { steps asArray. ((reader instVarNamed: 'partial') value at: 2). inbox items size }
  equals: #(#(#read #waiting) 1024 0).
client nextPutBytes: (frame copyFrom: 1505 to: frame size).
steps := OrderedCollection new.
[inbox items size = 0] whileTrue: [steps add: reader _readStep].
c that: 'the rest of the body completes the frame, delivered once and whole'
  is: { steps asArray. inbox items size. (inbox items first at: 'reason') size. (inbox items first at: 'term') }
  equals: #(#(#read #read #read) 1 3000 1).
client nextPutBytes: frame2.
steps := OrderedCollection new.
[inbox items size = 1] whileTrue: [steps add: reader _readStep].
c that: 'the next frame on the same connection is delivered'
  is: { steps asArray. inbox items size. (inbox items last at: 'term') } equals: #(#(#read #read) 2 2).
c that: 'nothing was rejected' is: { b stats at: 'frames_rejected'. b stats at: 'connections_dropped' } equals: #(0 0).
client close. accepted close. server close.

"(B) The same frame through the transport's own reader actor."
raw := Socket connectTo: '127.0.0.1' port: b port timeout: 60000.
readerOf := [(b instVarNamed: 'inbound') value readers].
await value: [readerOf value size = 1].
partialOf := [(readerOf value first instVarNamed: 'partial') value].
raw nextPutBytes: (frame copyFrom: 1 to: 1504).
await value: [(partialOf value at: 2) = 1024].
c that: 'the reader actor holds the first 1024 body bytes and has delivered nothing more'
  is: { partialOf value first. inbox items size } equals: { frame size - 4. 2 }.
raw nextPutBytes: (frame copyFrom: 1505 to: frame size).
await value: [inbox items size = 3].
c that: 'the frame split by a pause is delivered whole by the reader actor'
  is: { (inbox items last at: 'reason') size. (inbox items last at: 'term') } equals: #(3000 1).
raw nextPutBytes: frame2.
await value: [inbox items size = 4].
c that: 'the connection stays open, its reader goes on, and nothing was rejected'
  is: { readerOf value size. (inbox items last at: 'term'). b stats at: 'frames_rejected'. b stats at: 'connections_dropped' }
  equals: #(1 2 0 0).

b stop wait.
raw close.
steps := c report.
steps displayNl.
(steps beginsWith: 'ok') ifFalse: [Smalltalk exit: 1].
steps
