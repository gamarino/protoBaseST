"EXPECT: ok 8"
"PBTcpTransport (cluster/transport.st): a sender toward a peer that reads slowly, or not at all.
 Each write waits at most pollInterval, so a sender's turn ends while the peer is slow; protoST
 0.16.1 (protoIO 0.7.1) bounds a whole write by its timeout and reports, in ConnectionTimedOut
 bytesWritten, exactly how many leading bytes it wrote. A frame's attempt may still spend
 requestTimeout in all writing, as before: a timed-out write keeps the unwritten rest of the
 frame for the next step on the same connection while time is left, and once none is left the
 attempt fails exactly as the one whole-frame write of 0.2.0 to 0.3.0 failed.

 (1) Eight actors wait inside ensure: while the transport's sender writes a 16 MiB frame toward
 a peer that never reads (it does not even accept: the kernel completes the connection), with a
 one-hour requestTimeout: each must resume while the frame is still being written, and stop then
 drops and counts the frame. Before, the sender's one write kept its worker for up to
 requestTimeout, and a waiting actor that ran it on top of its wait stayed buried as long (that
 transport hangs here, with one worker and with the default pool). This check runs first, while
 the pool has only the workers that the transport's own blocked turns add.
 (2) The steps of one sender (_PBTcpSender >> _drainStep), called from the program thread with
 the same frame in its writing state, toward a peer that has accepted the connection and reads
 nothing: steps go on until one ends with fewer than writeChunk new bytes and the same attempt,
 which only a write that timed out does (a write that does not time out writes its whole piece).
 The frame is not finished, and nothing was sent or dropped. Then an actor reads the whole frame
 on that connection while the steps go on: the peer receives exactly the frame's bytes, once,
 the frame counts as sent, and nothing was dropped.
 (3) The same frame through a running transport whose requestTimeout is 300 ms, toward a peer
 that accepts and never reads: the first attempt fails after its 300 ms, the connection is
 closed and the frame written once more, whole, on a new connection, which fails too; the frame
 is dropped and counted, nothing counts as sent, and the peer saw two connections, each carrying
 a leading part of the frame and then ending (as 0.2.0 to 0.3.0 and proto_db's _send_loop do).
 tests/unit/cluster_transport_tcp_slow_reader_one_worker.sh runs this file with
 PROTOST_WORKERS=1.

 16 MiB is more than a loopback connection's kernel buffers hold for a peer that reads nothing
 (on Linux the send buffer grows to tcp_wmem's maximum, 4 MiB by default, and the receive window
 does not open while the peer does not read), so the frame cannot be finished before its peer
 reads.

 Nothing is decided by time: every wait is for a condition, or for an actor's answer, without a
 deadline, and a sender that loses or repeats bytes, or a waiter that stays buried, keeps the
 test waiting or fails a check. The runner's timeout turns a hang into a failure."
Import from: 'protobase'.
Import from: 'net'.
Import from: '_check'.

"Reads n bytes from a socket, as a peer that starts reading late."
Object subclass: #Drainer.

Drainer >> read: n from: aSocket
  ^ aSocket nextBytes: n.

"Accepts one connection, then answers what it reads until the stream ends."
Object subclass: #Hole.

Hole >> acceptOn: aServer
  ^ aServer accept.

Hole >> upToEndOf: aSocket
  | stream chunk |
  stream := WriteStream on: ByteArray new.
  [chunk := aSocket nextBytes: 65536.
   chunk notNil and: [chunk notEmpty]] whileTrue: [stream nextPutAll: chunk].
  ^ stream contents.

"An actor that waits inside a block, as a commit waits inside ensure:."
Object subclass: #Waiter instanceVariableNames: 'entered'.

Waiter class >> entered: anAtom
  ^ self basicNew setEntered: anAtom.

Waiter >> setEntered: anAtom
  entered := anAtom.

Waiter >> nestedWaitFor: aFuture
  entered swap: [:n | n + 1].
  [aFuture wait] ensure: [].
  ^ #resumed.

| c membership await senderOf frame a server sender peerSocket writing timedOut before after reading
  stats t server2 hole first second firstBytes secondBytes gate entered waiters answers |
c := Check new.
membership := [:pairs | PBMembership peers: (pairs collect: [:p | PBPeer nodeId: p first host: '127.0.0.1' port: p last]) voters: nil].
"Until aBlock is true, checked every 10 ms; no deadline (the runner's timeout bounds the test)."
await := [:aBlock | [aBlock value] whileFalse: [(Future after: 10) wait]].
stats := [:tr | { tr stats at: 'frames_sent'. tr stats at: 'frames_dropped' }].
"The bytes 0 to 250, repeated, 16 MiB: a byte lost, repeated or moved breaks the pattern, as 251
 divides neither writeChunk nor any power of two. The peers here read raw bytes and never decode,
 so the frame goes straight to the sender's queue (offer:, which send:to: calls once it has
 encoded a message)."
frame := ByteArray withAll: ((0 to: 250) asArray).
[frame size < 16777216] whileTrue: [frame := frame , frame].
frame := frame copyFrom: 1 to: 16777216.
"The sender of a started transport toward the peer 'slow'."
senderOf := [:tr | (tr instVarNamed: 'run') value senders at: 'slow'].

"(1) Waiting actors are not buried under a sender writing to a peer that never reads."
server := ServerSocket listenOn: 0 host: '127.0.0.1'.
a := PBTcpTransport withListener: (ServerSocket listenOn: 0 host: '127.0.0.1') requestTimeout: 3600000.
a start: 'a' peers: (membership value: { { 'a'. a port }. { 'slow'. server port } }) key: nil handler: [:m | nil].
gate := Future new.
entered := Atom on: 0.
waiters := (1 to: 8) asArray collect: [:i | (Waiter entered: entered) asActor nestedWaitFor: gate].
await value: [entered value = 8].
sender := senderOf value: a.
sender offer: frame.
writing := sender instVarNamed: 'writing'.
await value: [writing value notNil].
gate resolve: true.
answers := waiters collect: [:w | w wait].
c that: 'eight actors waiting in blocks resume while the sender writes to a peer that never reads'
  is: answers equals: ((1 to: 8) asArray collect: [:i | #resumed]).
c that: 'the frame was still being written, on its first attempt, when they resumed'
  is: { writing value notNil. stats value: a } equals: #(true #(0 0)).
a stop wait.
c that: 'stop drops and counts the frame being written' is: (stats value: a) equals: #(0 1).
server close.

"(2) The steps of one sender toward a peer that reads nothing, then reads it all."
server := ServerSocket listenOn: 0 host: '127.0.0.1'.
a := PBTcpTransport withListener: (ServerSocket listenOn: 0 host: '127.0.0.1') requestTimeout: 3600000.
a start: 'a' peers: (membership value: { { 'a'. a port }. { 'slow'. server port } }) key: nil handler: [:m | nil].
sender := _PBTcpSender transport: a peer: (PBPeer nodeId: 'slow' host: '127.0.0.1' port: server port).
writing := sender instVarNamed: 'writing'.
writing swap: [:old | { frame. 0. 1. a requestTimeout * 1000 }].
"The first step connects, then writes."
sender _drainStep.
peerSocket := server accept.
peerSocket timeout: 600000.
timedOut := false.
[timedOut] whileFalse: [
  before := writing value.
  sender _drainStep.
  after := writing value.
  timedOut := after notNil and: [(after at: 3) = 1
    and: [(after at: 2) - (before at: 2) < PBTcpTransport writeChunk]]].
c that: 'a write that timed out keeps the rest of the frame, on the same attempt, unfinished'
  is: { (after at: 2) < frame size. after at: 3. stats value: a } equals: #(true 1 #(0 0)).
reading := Drainer new asActor read: frame size from: peerSocket.
[writing value isNil] whileFalse: [sender _drainStep].
c that: 'the peer reads exactly the frame, once, on the first connection' is: reading wait = frame equals: true.
c that: 'the frame counts as sent and nothing was dropped' is: (stats value: a) equals: #(1 0).
sender stop wait.
peerSocket close. server close.
a stop wait.

"(3) A 300 ms requestTimeout toward a peer that accepts and never reads."
server2 := ServerSocket listenOn: 0 host: '127.0.0.1'.
t := PBTcpTransport withListener: (ServerSocket listenOn: 0 host: '127.0.0.1') requestTimeout: 300.
t start: 'a' peers: (membership value: { { 'a'. t port }. { 'slow'. server2 port } }) key: nil handler: [:m | nil].
hole := Hole new asActor.
first := hole acceptOn: server2.
second := hole acceptOn: server2.
(senderOf value: t) offer: frame.
first := first wait.
first timeout: 600000.
second := second wait.
second timeout: 600000.
await value: [((stats value: t) at: 2) = 1].
c that: 'both attempts fail: the frame is dropped and counted, nothing is sent' is: (stats value: t) equals: #(0 1).
firstBytes := (hole upToEndOf: first) wait.
secondBytes := (hole upToEndOf: second) wait.
c that: 'each connection carried a part of the frame from its start, then ended'
  is: { firstBytes size > 0. firstBytes size < frame size. firstBytes = (frame copyFrom: 1 to: firstBytes size).
    secondBytes size > 0. secondBytes size < frame size. secondBytes = (frame copyFrom: 1 to: secondBytes size) }
  equals: #(true true true true true true).
first close. second close. server2 close.
t stop wait.

answers := c report.
answers displayNl.
(answers beginsWith: 'ok') ifFalse: [Smalltalk exit: 1].
answers
