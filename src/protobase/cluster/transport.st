"-- cluster/transport.st: the message transports of the cluster coordinator --

proto_db cluster/transport.py at v2.0.0rc3 (decision D45). A transport delivers protocol
messages (PBClusterMessage) between members, best effort: send:to: never blocks on the network
and never signals for a network failure; a message may be lost, and the lease protocol
tolerates loss, duplication and reordering (P5). The coordinator never relies on delivery for
safety. Every frame is a PBClusterFrame, authenticated when the member has a key (CC4).

  PBClusterTransport    the protocol both transports follow:
                          start: aNodeId peers: aMembership key: aKeyOrNil handler: aBlock
                            begin receiving; aBlock gets each valid, decoded message
                          send: aMessage to: aNodeId
                            frame the message for aNodeId and hand it on; never blocks
                          stop
                            stop receiving and sending; answers a Future that settles (with
                            true) once nothing more is delivered and every actor of the
                            transport has finished; idempotent
                          stats
                            a Dictionary of frames_sent, frames_dropped, frames_rejected,
                            connections_dropped (CC24: snake_case String keys)
  PBInProcessNetwork    peers inside one process, for tests: drop and duplicate faults drawn
  PBInProcessTransport  from a seeded generator, partitions into groups, and crashes (a stopped
                        endpoint neither sends nor receives). Each endpoint delivers on one
                        actor of its own, one message at a time, in arrival order.
  PBTcpTransport        length-prefixed frames over TCP. One listener actor (high band)
                        accepts; one reader actor (high band) per accepted connection reads
                        frames and calls the handler; one sender actor (high band) per peer
                        drains that peer's queue over one outbound connection (lesson L7: a
                        black-holed peer delays nobody else). Every turn of these actors ends
                        (see below). Connections are one-way: a node
                        sends only on its own outbound connections and reads only from
                        accepted ones, so a reply travels on the replier's own connection.

The reader checks the length (PBClusterFrame lengthFrom:) before it reads, or allocates, the
body. Any PBClusterProtocolError on a connection closes that connection and is counted in
frames_rejected and connections_dropped. Each valid frame is delivered as it is read (CC5):
proto_db's loss of the other messages of the same 64 KiB read as a bad frame is a property of
its reads, not reproduced.

The handler is called on the reader actor of each connection, so on several threads at once
with several peers (proto_db calls it on its one listener thread); it must not block on the
network and must be safe to call concurrently (the coordinator forwards each message to its
dispatcher actor). A PBDBError it signals is written to stderr and delivery goes on (proto_db
_deliver); any other error ends that connection's reader.

Every turn of a TCP actor ends (protoBaseST 0.4.0). A wait nested in a block blocks its worker,
which runs other actors' turns on top of it until they end (protoST LANGUAGE 10.4, D56), so one
turn that never ended could keep a waiting actor (a commit waits inside ensure:) buried until the
transport stopped; in 0.2.0 to 0.3.0 the accept loop and each connection's read loop were such
turns. Now the listener's turn is one accept, waiting at most pollInterval; a reader's turn reads
and delivers for at most pollInterval (its reads time out after pollInterval, and a frame read in
part waits in the reader's state for the next turn); a sender's turn writes for at most
pollInterval, each write waiting at most pollInterval (protoST 0.16.1 and protoIO 0.7.1 bound a
whole write by its timeout and report the bytes it wrote), the rest of a frame continuing in the
next turn. Each actor then sends itself the next turn while there is work, so a waiting actor
resumes once the turn on top of it ends: after at most pollInterval plus one network wait, which
is one read timeout for a reader (more only for a peer that trickles a frame, see readChunk), and
one write wait of at most pollInterval or one connect, bounded by requestTimeout, for a sender.
These turns also starve no other actor: a worker that is not waiting runs every message an actor
sends itself in the same turn (protoST STATUS D59), but each of these turns blocks in I/O (an
accept, a read or a write with a timeout), and the pool adds a worker while one is blocked in
I/O, so the rest of the program runs there, with one worker too. stop does not rely on mailbox
order: each actor settles its own Future, ended, when its last turn ends, and stop chains on them.
What travels and in what order is unchanged: the same bytes, every frame of a connection
delivered in arrival order, the same counters, errors, reconnects and timeouts (a frame's write
still fails after requestTimeout of writing, see _PBTcpSender >> _advance:).

This module is a shell, not part of the core: the sender reads the monotonic clock for its
reconnection back-off and the time its writes take, every TCP actor the length of its turns, and
the listener waits on a timer (Future after:) before the turn that follows a failed accept (plan,
'Time': the shells
read Time microsecondClockValue).

Every value here is immutable; the transports keep their state in Atoms created by their
initialisers (a reader's frame read so far and a sender's frame being written included)."

Import from: 'net'.
Import from: 'protobase/errors'.
Import from: 'protobase/floor'.
Import from: 'protobase/cluster/members'.
Import from: 'protobase/cluster/protocol'.

"=== PBClusterTransport ==================================================="

Object subclass: #PBClusterTransport instanceVariableNames: 'counters'.

"The names of the counters of stats, in the order counters holds them."
PBClusterTransport class >> statNames
  ^ #('frames_sent' 'frames_dropped' 'frames_rejected' 'connections_dropped').

"A fresh Atom holding one zero per stat."
PBClusterTransport class >> _newCounters
  ^ Atom on: (self statNames collect: [:each | 0]).

"PBValidationError unless aNodeId is a member of aMembership, aKeyOrNil is nil or a ByteArray of
 at least PBClusterFrame tagSize bytes (CC4) and aBlock takes one argument."
PBClusterTransport class >> _checkNode: aNodeId peers: aMembership key: aKeyOrNil handler: aBlock
  (aMembership isClassObject not and: [aMembership class == PBMembership]) ifFalse: [
    ^ PBValidationError signal: 'A transport''s peers are a PBMembership, not ' , aMembership printString].
  aMembership rankOf: aNodeId.
  (aKeyOrNil isNil or: [(aKeyOrNil isKindOf: ByteArray) and: [aKeyOrNil size >= PBClusterFrame tagSize]]) ifFalse: [
    ^ PBValidationError signal: 'A cluster key is nil or a ByteArray of at least ' , PBClusterFrame tagSize printString , ' bytes'].
  (aBlock notNil and: [(aBlock respondsTo: #numArgs) and: [aBlock numArgs = 1]]) ifFalse: [
    ^ PBValidationError signal: 'A transport''s handler is a one-argument block, not ' , aBlock printString].

"aString on stderr, prefixed with the transport; never signals (the convention of
 PBFramedLog _warn: for a recoverable condition)."
PBClusterTransport class >> _warn: aString
  [Stdio stderr nextPutAll: self name , ': ' , aString; lf; flush] on: Error do: [:e | nil].

"Closes aSocketOrNil (a Socket or a ServerSocket); never signals for a failed close, which is
 written to stderr: a close that fails holds nothing the transport could still release (protoST
 signals on closing a Socket without a descriptor, see _PBTcpListener >> _acceptOne).
 MessageNotUnderstood passes, as everywhere in this file. The callers settle their ended Futures
 in an ensure: around it, so not even that error leaves stop waiting (final review M1)."
PBClusterTransport class >> _close: aSocketOrNil
  aSocketOrNil isNil ifTrue: [^ self].
  [aSocketOrNil close] on: Error do: [:e |
    (e isKindOf: MessageNotUnderstood) ifTrue: [e pass].
    self _warn: 'closing a connection failed: ' , e messageText].

"A Future that resolves (with true) once aFuture settles, whether it resolves or is rejected."
PBClusterTransport class >> _settled: aFuture
  | settled |
  settled := Future new.
  aFuture thenDo: [:x | settled resolve: true]; catch: [:e | settled resolve: true].
  ^ settled.

"A Future that resolves (with true) once every Future of anArray has settled."
PBClusterTransport class >> _allSettled: anArray
  | done |
  done := Future new.
  anArray isEmpty ifTrue: [done resolve: true. ^ done].
  (Future whenAll: (anArray collect: [:f | self _settled: f])) thenDo: [:x | done resolve: true].
  ^ done.

"The counters: frames_sent (frames handed to the network or written to a socket),
 frames_dropped (outgoing frames lost: an unknown peer, a full queue, a failed connect or
 write, the back-off, a fault or partition of the in-process network, a stopped receiver),
 frames_rejected (received frames refused: malformed, oversized, unauthenticated) and
 connections_dropped (connections closed after a rejected frame)."
PBClusterTransport >> stats
  | values d |
  values := counters value.
  d := Dictionary new.
  1 to: values size do: [:i | d at: (self class statNames at: i) put: (values at: i)].
  ^ d.

PBClusterTransport >> _count: aName
  | i |
  i := self class statNames indexOf: aName.
  counters swap: [:values |
    | copy |
    copy := values copy.
    copy at: i put: (values at: i) + 1.
    copy].

"Calls aBlock with aMessage; a PBDBError it signals is written to stderr, not passed on
 (proto_db _deliver)."
PBClusterTransport >> _deliver: aMessage to: aBlock
  [aBlock value: aMessage] on: PBDBError do: [:e |
    self class _warn: 'handling a ' , aMessage type printString , ' message failed: ' , e messageText].

"=== the in-process network ==============================================="

Object subclass: #PBInProcessNetwork instanceVariableNames: 'endpoints groups faults random'.

"A network without faults whose generator is seeded with 1."
PBInProcessNetwork class >> new
  ^ self seed: 1.

"A network without faults whose drops and duplicates are drawn from a generator seeded with
 anInteger (a Lehmer generator, so a seed gives one sequence of draws)."
PBInProcessNetwork class >> seed: anInteger
  anInteger isInteger ifFalse: [
    ^ PBValidationError signal: 'PBInProcessNetwork seed: an Integer, not ' , anInteger printString].
  ^ self basicNew
    _setEndpoints: (Atom on: Dictionary new)
    groups: (Atom on: nil)
    faults: (Atom on: #(0 0))
    random: (Atom on: anInteger \\ 2147483646 + 1).

PBInProcessNetwork >> _setEndpoints: anAtom groups: aGroupsAtom faults: aFaultsAtom random: aRandomAtom
  "Runs once, on a fresh instance."
  endpoints isNil ifFalse: [^ PBUserError signal: 'PBInProcessNetwork is immutable'].
  endpoints := anAtom.
  groups := aGroupsAtom.
  faults := aFaultsAtom.
  random := aRandomAtom.
  ^ self.

"A new, unstarted endpoint on this network."
PBInProcessNetwork >> endpoint
  ^ PBInProcessTransport network: self.

"From now on, each frame is dropped with probability aDrop and, if not, delivered twice with
 probability aDuplicate (numbers from 0 to 1; proto_db set_faults). PBValidationError otherwise."
PBInProcessNetwork >> drop: aDrop duplicate: aDuplicate
  ({ aDrop. aDuplicate } allSatisfy: [:p | p isNumber and: [p >= 0 and: [p <= 1]]]) ifFalse: [
    ^ PBValidationError signal: 'Faults are probabilities from 0 to 1, not ' , { aDrop. aDuplicate } printString].
  faults swap: [:old | { aDrop. aDuplicate }].

"From now on, frames flow only between members of the same group (anArray of collections of
 node ids); a node in no group is cut off from every other (proto_db partition)."
PBInProcessNetwork >> partition: anArray
  | split |
  split := anArray asArray collect: [:group | group asArray collect: [:id | id]].
  groups swap: [:old | split].

"Removes the partition."
PBInProcessNetwork >> heal
  groups swap: [:old | nil].

"Registers anEndpoint as the node anId; PBValidationError when another endpoint runs as anId."
PBInProcessNetwork >> _register: anId endpoint: anEndpoint
  | old new |
  [old := endpoints value.
   ((old at: anId ifAbsent: [nil]) ifNil: [anEndpoint]) == anEndpoint ifFalse: [
     ^ PBValidationError signal: 'Node ' , anId printString , ' is already running on this network'].
   new := old copy.
   new at: anId put: anEndpoint.
   endpoints value: new ifCurrent: old] whileFalse.

PBInProcessNetwork >> _unregister: anId endpoint: anEndpoint
  endpoints swap: [:old |
    (old at: anId ifAbsent: [nil]) == anEndpoint
      ifTrue: [| new | new := old copy. new removeKey: anId. new]
      ifFalse: [old]].

"Whether a frame may travel from aSource to aTarget under the current partition."
PBInProcessNetwork >> _connected: aSource to: aTarget
  | split |
  split := groups value.
  (split isNil or: [aSource = aTarget]) ifTrue: [^ true].
  ^ split anySatisfy: [:group | (group includes: aSource) and: [group includes: aTarget]].

"The next draw of the generator, a Fraction from 0 (included) to 1 (excluded)."
PBInProcessNetwork >> _draw
  ^ (random swap: [:x | x * 48271 \\ 2147483647]) - 1 / 2147483646.

"Routes aFrame from the endpoint anEndpoint, running as aSource, to the node aTarget (proto_db
 _route); answers the number of copies handed to the target, 0 when the frame is dropped."
PBInProcessNetwork >> _route: aFrame from: aSource endpoint: anEndpoint to: aTarget
  | registered target fault copies |
  registered := endpoints value.
  target := registered at: aTarget ifAbsent: [nil].
  fault := faults value.
  ((registered at: aSource ifAbsent: [nil]) == anEndpoint and: [target notNil
      and: [self _connected: aSource to: aTarget]]) ifFalse: [^ 0].
  ((fault at: 1) > 0 and: [self _draw < (fault at: 1)]) ifTrue: [^ 0].
  copies := ((fault at: 2) > 0 and: [self _draw < (fault at: 2)]) ifTrue: [2] ifFalse: [1].
  copies timesRepeat: [target _enqueue: aFrame].
  ^ copies.

"=== PBInProcessTransport =================================================="

PBClusterTransport subclass: #PBInProcessTransport instanceVariableNames: 'network run'.

PBInProcessTransport class >> network: aNetwork
  ^ self basicNew _setNetwork: aNetwork run: (Atom on: nil) counters: self _newCounters.

PBInProcessTransport >> _setNetwork: aNetwork run: aRunAtom counters: aCountersAtom
  "Runs once, on a fresh instance."
  network isNil ifFalse: [^ PBUserError signal: 'PBInProcessTransport is immutable'].
  network := aNetwork.
  run := aRunAtom.
  counters := aCountersAtom.
  ^ self.

"See PBClusterTransport. PBValidationError for a bad argument, an endpoint started twice or
 after stop, or a node id another endpoint of the network runs as."
PBInProcessTransport >> start: aNodeId peers: aMembership key: aKeyOrNil handler: aBlock
  | inbox current |
  self class _checkNode: aNodeId peers: aMembership key: aKeyOrNil handler: aBlock.
  inbox := (_PBInProcessInbox transport: self nodeId: aNodeId key: aKeyOrNil handler: aBlock) asHighPriorityActor.
  current := _PBTransportRun nodeId: aNodeId key: aKeyOrNil handler: aBlock inbox: inbox senders: nil listener: nil.
  (run value: current ifCurrent: nil) ifFalse: [
    ^ PBValidationError signal: 'This endpoint was already started'].
  [network _register: aNodeId endpoint: self] on: PBValidationError do: [:e |
    run value: nil ifCurrent: current.
    e pass].

"See PBClusterTransport. PBClusterProtocolError when the frame would exceed the limit;
 PBValidationError when aMessage is not a PBClusterMessage. A silent no-op before start and
 after stop."
PBInProcessTransport >> send: aMessage to: aNodeId
  | current running frame |
  current := run value.
  running := self _isRunning: current.
  frame := PBClusterFrame encode: aMessage to: aNodeId key: (running ifTrue: [current key] ifFalse: [nil]).
  running ifFalse: [^ self].
  (network _route: frame from: current nodeId endpoint: self to: aNodeId) = 0
    ifTrue: [self _count: 'frames_dropped']
    ifFalse: [self _count: 'frames_sent'].

"See PBClusterTransport. The crash of the node: in-flight frames to it are dropped and it sends
 nothing more; a stopped endpoint is never restarted (a restarted node uses a new endpoint)."
PBInProcessTransport >> stop
  | current done |
  [current := run value.
   (current isKindOf: Future) ifTrue: [^ current].
   done := Future new.
   run value: done ifCurrent: current] whileFalse.
  current isNil ifTrue: [done resolve: true. ^ done].
  network _unregister: current nodeId endpoint: self.
  (self class _settled: current inbox finish) thenDo: [:x | done resolve: true].
  ^ done.

"Whether aRunValue, a value of run, is a running transport's."
PBInProcessTransport >> _isRunning: aRunValue
  ^ aRunValue isClassObject not and: [aRunValue class == _PBTransportRun].

PBInProcessTransport >> isRunning
  ^ self _isRunning: run value.

"Hands aFrame to the inbox actor, unless the endpoint stopped."
PBInProcessTransport >> _enqueue: aFrame
  | current |
  current := run value.
  (self _isRunning: current) ifTrue: [current inbox deliver: aFrame].

"=== the run of a started transport ======================================="

Object subclass: #_PBTransportRun instanceVariableNames: 'nodeId key handler inbox senders listener'.

"What a started transport runs with: its node id, key and handler; for an in-process endpoint
 its inbox actor; for a TCP transport its senders (peer id -> _PBTcpSender) and its listener
 (a _PBTcpListener)."
_PBTransportRun class >> nodeId: anId key: aKeyOrNil handler: aBlock inbox: anInbox senders: aDictionary listener: aListener
  ^ self basicNew _setNodeId: anId key: aKeyOrNil handler: aBlock inbox: anInbox senders: aDictionary listener: aListener.

_PBTransportRun >> _setNodeId: anId key: aKeyOrNil handler: aBlock inbox: anInbox senders: aDictionary listener: aListener
  "Runs once, on a fresh instance."
  nodeId isNil ifFalse: [^ PBUserError signal: '_PBTransportRun is immutable'].
  nodeId := anId.
  key := aKeyOrNil.
  handler := aBlock.
  inbox := anInbox.
  senders := aDictionary.
  listener := aListener.
  ^ self.

_PBTransportRun >> nodeId
  ^ nodeId.

_PBTransportRun >> key
  ^ key.

_PBTransportRun >> handler
  ^ handler.

_PBTransportRun >> inbox
  ^ inbox.

_PBTransportRun >> senders
  ^ senders.

_PBTransportRun >> listener
  ^ listener.

"=== the inbox actor of an in-process endpoint ==========================="

Object subclass: #_PBInProcessInbox instanceVariableNames: 'transport nodeId key handler'.

_PBInProcessInbox class >> transport: aTransport nodeId: anId key: aKeyOrNil handler: aBlock
  ^ self basicNew _setTransport: aTransport nodeId: anId key: aKeyOrNil handler: aBlock.

_PBInProcessInbox >> _setTransport: aTransport nodeId: anId key: aKeyOrNil handler: aBlock
  "Runs once, on a fresh instance."
  transport isNil ifFalse: [^ PBUserError signal: '_PBInProcessInbox is immutable'].
  transport := aTransport.
  nodeId := anId.
  key := aKeyOrNil.
  handler := aBlock.
  ^ self.

"Decodes aFrame for this node and calls the handler, unless the endpoint stopped. A frame that
 does not decode (PBClusterProtocolError: malformed, another key) is counted in frames_rejected
 and dropped."
_PBInProcessInbox >> deliver: aFrame
  | message |
  transport isRunning ifFalse: [^ false].
  message := [PBClusterFrame decode: aFrame to: nodeId key: key] on: PBClusterProtocolError do: [:e |
    transport _count: 'frames_rejected'.
    transport class _warn: nodeId printString , ' dropped a malformed message: ' , e messageText.
    nil].
  message isNil ifTrue: [^ false].
  transport _deliver: message to: handler.
  ^ true.

"Answers once every frame queued before it was handled (mailbox order)."
_PBInProcessInbox >> finish
  ^ true.

"=== TCP =================================================================="

PBClusterTransport subclass: #PBTcpTransport instanceVariableNames: 'listener port requestTimeout run inbound'.

"The default timeout, in milliseconds, of a connect or a write: 1000, proto_db's connect_timeout
 and send_timeout, with which its coordinator builds its TcpTransport."
PBTcpTransport class >> defaultRequestTimeout
  ^ 1000.

"The base of the reconnection back-off, in microseconds (proto_db reconnect_backoff, 0.1 s): after
 a failed connect, frames to that peer are dropped for a time drawn from this base to twice it."
PBTcpTransport class >> backoffBase
  ^ 100000.

"The longest a turn of the listener or of a reader waits for the network, in milliseconds: 50,
 the listener's accept timeout and the read timeout of every accepted connection. It is also the
 time after which a turn of any actor of the transport stops starting new work. Every turn ends
 and the actor sends itself the next one, so a wait nested in a block (LANGUAGE 10.4) that runs a
 turn on top of itself resumes once that turn ends, never only when the transport stops. A turn
 that waits in vain costs one wake-up per interval for the listener and for each open connection.
 Nothing safe depends on it: it bounds only how long a turn keeps its worker."
PBTcpTransport class >> pollInterval
  ^ 50.

"The most bytes one read of a frame's body asks for: 1024. A read answers as soon as that many
 bytes arrived, so an ordinary frame takes one read per KiB, each from what the socket already
 holds; a peer that sends a byte just inside every read timeout keeps one read, and the turn
 making it, for at most this many read timeouts (51 s)."
PBTcpTransport class >> readChunk
  ^ 1024.

"The most bytes one write of a sender asks for: 65536 (64 KiB). A larger frame is written in
 pieces of this size, one after the other on the same connection, so no step copies more than this
 much of a frame; the bytes on the wire are the frame's, in order."
PBTcpTransport class >> writeChunk
  ^ 65536.

"A transport listening on aHost, port aPort (0 picks a free port; read it back with port).
 PBValidationError when the address cannot be listened on."
PBTcpTransport class >> listenOn: aPort host: aHost
  ^ self listenOn: aPort host: aHost requestTimeout: self defaultRequestTimeout.

PBTcpTransport class >> listenOn: aPort host: aHost requestTimeout: aMillis
  | server |
  (aPort isInteger and: [(aPort between: 0 and: 65535) and: [aHost isString]]) ifFalse: [
    ^ PBValidationError signal: 'PBTcpTransport listenOn:host: a port from 0 to 65535 and a String host, not '
      , { aPort. aHost } printString].
  self _checkTimeout: aMillis.
  server := [ServerSocket listenOn: aPort host: aHost] on: Error do: [:e |
    (e isKindOf: MessageNotUnderstood) ifTrue: [e pass].
    ^ PBValidationError signal: 'Cannot listen on ' , aHost , ':' , aPort printString , ': ' , e messageText].
  ^ self withListener: server requestTimeout: aMillis.

PBTcpTransport class >> _checkTimeout: aMillis
  (aMillis isInteger and: [aMillis > 0 and: [aMillis <= SmallInteger maxVal]]) ifFalse: [
    ^ PBValidationError signal: 'requestTimeout must be a positive Integer number of milliseconds, not ' , aMillis printString].

"A transport over aServerSocket, already listening (for tests that publish ports first)."
PBTcpTransport class >> withListener: aServerSocket
  ^ self withListener: aServerSocket requestTimeout: self defaultRequestTimeout.

"The same, with aMillis (a positive Integer of milliseconds) as the timeout of every connect and
 write (proto_db connect_timeout and send_timeout; the coordinator passes requestTimeout)."
PBTcpTransport class >> withListener: aServerSocket requestTimeout: aMillis
  (aServerSocket isKindOf: ServerSocket) ifFalse: [
    ^ PBValidationError signal: 'PBTcpTransport withListener: a ServerSocket, not ' , aServerSocket printString].
  self _checkTimeout: aMillis.
  ^ self basicNew
    _setListener: aServerSocket port: aServerSocket port requestTimeout: aMillis
    run: (Atom on: nil) inbound: (Atom on: _PBInbound new) counters: self _newCounters.

PBTcpTransport >> _setListener: aServerSocket port: aPort requestTimeout: aMillis run: aRunAtom inbound: anInboundAtom counters: aCountersAtom
  "Runs once, on a fresh instance."
  listener isNil ifFalse: [^ PBUserError signal: 'PBTcpTransport is immutable'].
  listener := aServerSocket.
  port := aPort.
  requestTimeout := aMillis.
  run := aRunAtom.
  inbound := anInboundAtom.
  counters := aCountersAtom.
  ^ self.

"The port the transport listens on (proto_db address)."
PBTcpTransport >> port
  ^ port.

PBTcpTransport >> requestTimeout
  ^ requestTimeout.

"See PBClusterTransport; aMembership gives each peer's host and port. PBValidationError for a bad
 argument, or a transport started twice or after stop."
PBTcpTransport >> start: aNodeId peers: aMembership key: aKeyOrNil handler: aBlock
  | senders current |
  self class _checkNode: aNodeId peers: aMembership key: aKeyOrNil handler: aBlock.
  senders := Dictionary new.
  aMembership ids do: [:id |
    id = aNodeId ifFalse: [senders at: id put: (_PBTcpSender transport: self peer: (aMembership peerNamed: id))]].
  current := _PBTransportRun nodeId: aNodeId key: aKeyOrNil handler: aBlock inbox: nil senders: senders
    listener: (_PBTcpListener transport: self server: listener).
  (run value: current ifCurrent: nil) ifFalse: [
    ^ PBValidationError signal: 'This transport was already started'].
  current listener begin.

"See PBClusterTransport. PBClusterProtocolError when the frame would exceed the limit;
 PBValidationError when aMessage is not a PBClusterMessage. A silent no-op before start and
 after stop; a message to an unknown peer or to the node itself is dropped and counted."
PBTcpTransport >> send: aMessage to: aNodeId
  | current running frame sender |
  current := run value.
  running := self _isRunning: current.
  frame := PBClusterFrame encode: aMessage to: aNodeId key: (running ifTrue: [current key] ifFalse: [nil]).
  running ifFalse: [^ self].
  sender := current senders at: aNodeId ifAbsent: [nil].
  sender isNil ifTrue: [^ self _count: 'frames_dropped'].
  sender offer: frame.

"See PBClusterTransport. Closes the listening socket and every accepted connection (which wakes
 the readers; each connection is closed once, by stop or by its reader, _PBTcpReader >>
 closeSocket), closes each sender's queue and connection (which wakes a sender blocked in a
 write), then answers a Future that settles once the listener, every reader it started and
 every sender have finished. Each of those actors settles its own Future, ended, when its last
 turn ends; stop chains on them and never waits. The listener's last turn ends only after the
 transport stopped, and _admit: runs inside the listener's turns, so every reader the listener
 ever started is registered in inbound before the listener's ended settles: a reader still
 registered then is waited for, and one no longer registered has already closed its connection
 and retired (its ended settles right after). A sender's ended settles at once when it was idle
 at stop (stop closed its connection), else when its drain turn sees the closed queue."
PBTcpTransport >> stop
  | current done closed senders |
  [current := run value.
   (current isKindOf: Future) ifTrue: [^ current].
   done := Future new.
   run value: done ifCurrent: current] whileFalse.
  current isNil ifTrue: [[self class _close: listener] ensure: [done resolve: true]. ^ done].
  closed := inbound swap: [:old | old closed].
  self class _close: listener.
  closed readers do: [:each | each closeSocket].
  senders := current senders values asArray collect: [:each | each stop].
  (self class _settled: current listener ended) thenDo: [:x |
    (self class _allSettled: (inbound value readers collect: [:each | each ended]) , senders)
      thenDo: [:y | done resolve: true]].
  ^ done.

PBTcpTransport >> _isRunning: aRunValue
  ^ aRunValue isClassObject not and: [aRunValue class == _PBTransportRun].

PBTcpTransport >> isRunning
  ^ self _isRunning: run value.

"Starts a reader actor for aSocket, accepted by the listener, unless the transport stopped: the
 socket and its reader are registered before the reader runs, so stop either closes the socket
 or this method sees the transport closed and closes it. Reads on aSocket wait at most
 pollInterval (a reader's turn ends then; the frame read so far is kept for the next turn)."
PBTcpTransport >> _admit: aSocket
  | current old reader |
  current := run value.
  (self _isRunning: current) ifFalse: [self class _close: aSocket. ^ self].
  [aSocket timeout: self class pollInterval] on: Error do: [:e |
    (e isKindOf: MessageNotUnderstood) ifTrue: [e pass].
    self class _close: aSocket.
    ^ self class _warn: 'admitting a connection failed: ' , e messageText].
  reader := _PBTcpReader transport: self socket: aSocket nodeId: current nodeId key: current key handler: current handler.
  [old := inbound value.
   old isClosed ifTrue: [self class _close: aSocket. ^ self].
   inbound value: (old with: aSocket reader: reader) ifCurrent: old] whileFalse.
  reader begin.

"Forgets aSocket, whose reader has ended (so a long-lived transport keeps only its open
 connections)."
PBTcpTransport >> _retire: aSocket
  inbound swap: [:old | old without: aSocket].

"Counts a rejected frame and the connection it closes."
PBTcpTransport >> _rejected: anError
  self _count: 'frames_rejected'.
  self _count: 'connections_dropped'.
  self class _warn: 'dropped a connection after a malformed frame: ' , anError messageText.

"=== the accepted connections of a TCP transport =========================="

Object subclass: #_PBInbound instanceVariableNames: 'closed entries'.

"No connection accepted yet, open."
_PBInbound class >> new
  ^ self basicNew _setClosed: false entries: #().

_PBInbound >> _setClosed: aBoolean entries: anArray
  "Runs once, on a fresh instance."
  closed isNil ifFalse: [^ PBUserError signal: '_PBInbound is immutable'].
  closed := aBoolean.
  entries := anArray.
  ^ self.

_PBInbound >> isClosed
  ^ closed.

"The accepted sockets whose readers have not ended."
_PBInbound >> sockets
  ^ entries collect: [:each | each first].

"The readers (_PBTcpReader) of those sockets."
_PBInbound >> readers
  ^ entries collect: [:each | each last].

_PBInbound >> with: aSocket reader: aReader
  ^ self class basicNew _setClosed: closed entries: (entries copyWith: { aSocket. aReader }).

_PBInbound >> without: aSocket
  ^ self class basicNew _setClosed: closed entries: (entries reject: [:each | each first == aSocket]).

_PBInbound >> closed
  ^ self class basicNew _setClosed: true entries: entries.

"=== the listener actor ==================================================="

Object subclass: #_PBTcpListener instanceVariableNames: 'transport server proxy ended'.

"The listener over aServerSocket: its actor proxy (high band) and ended, the Future its last turn
 settles."
_PBTcpListener class >> transport: aTransport server: aServerSocket
  | listener |
  listener := self basicNew.
  ^ listener _setTransport: aTransport server: aServerSocket proxy: listener asHighPriorityActor ended: Future new.

_PBTcpListener >> _setTransport: aTransport server: aServerSocket proxy: aProxy ended: aFuture
  "Runs once, on a fresh instance."
  transport isNil ifFalse: [^ PBUserError signal: '_PBTcpListener is immutable'].
  transport := aTransport.
  server := aServerSocket.
  proxy := aProxy.
  ended := aFuture.
  ^ self.

"Sends the first turn (once, from start:)."
_PBTcpListener >> begin
  proxy run.

"A Future that settles (with true) once the listener's last turn has ended: after the transport
 stopped, every connection it accepted handed to the transport (_admit:)."
_PBTcpListener >> ended
  ^ ended.

"One turn of the listener (an actor method): one accept, waiting at most pollInterval, then the
 next turn sent to the proxy while the transport runs, as proto_db's _accept loop. stop closes the
 listening socket, which wakes the accept; an accept that fails while the transport runs is
 written to stderr and the next turn tries again (proto_db _accept), pollInterval later: an
 accept that fails at once (EMFILE, for example) would otherwise make the listener spin, one
 stderr line per turn without a pause (final review M10). The pause is a timer, not a wait inside
 the turn, so the turn still ends at once. ended settles when no next turn is due, also when this
 one ends by an error."
_PBTcpListener >> run
  | step |
  step := #stopped.
  [step := self _acceptOne] ensure: [step == #stopped ifTrue: [ended resolve: true]].
  step == #failed ifTrue: [(Future after: PBTcpTransport pollInterval) thenDo: [:x | proxy run]. ^ true].
  step == #stopped ifFalse: [proxy run].
  ^ true.

"Accepts one connection, if one comes within pollInterval, and hands it to the transport.
 Answers #accepted (a connection was handed on), #idle (none came within pollInterval), #failed
 (the accept failed while the transport runs; written to stderr) or #stopped (the transport no
 longer runs: no next turn)."
_PBTcpListener >> _acceptOne
  | socket failure |
  transport isRunning ifFalse: [^ #stopped].
  failure := nil.
  socket := [server acceptTimeout: PBTcpTransport pollInterval] on: Error do: [:e |
    (e isKindOf: MessageNotUnderstood) ifTrue: [e pass].
    failure := e messageText.
    nil].
  transport isRunning ifFalse: [
    "An accept that stop's close woke answers a Socket without a descriptor (protoST 0.12.0),
     whose close signals: it holds nothing to release."
    socket isNil ifFalse: [[socket close] on: Error do: [:e |
      (e isKindOf: MessageNotUnderstood) ifTrue: [e pass].
      nil]].
    ^ #stopped].
  failure isNil ifFalse: [
    transport class _warn: 'accepting a connection failed: ' , failure printString.
    ^ #failed].
  "nil: no connection within pollInterval."
  socket isNil ifTrue: [^ #idle].
  transport _admit: socket.
  ^ #accepted.

"=== the reader actor (one per accepted connection) ======================="

Object subclass: #_PBTcpReader instanceVariableNames: 'transport socket nodeId key handler proxy partial ended closing'.

"The reader of aSocket: its actor proxy (high band), partial (an Atom on the frame read so far,
 kept from one turn to the next) and ended, the Future its last turn settles. partial holds
 { length or nil while the 4 length bytes are read. bytes read of the length or of the body.
 pieces }, where pieces is nil or { the last ByteArray read. the pieces before it }; closing, an
 Atom that becomes true when the connection is closed (closeSocket)."
_PBTcpReader class >> transport: aTransport socket: aSocket nodeId: anId key: aKeyOrNil handler: aBlock
  | reader |
  reader := self basicNew.
  ^ reader _setTransport: aTransport socket: aSocket nodeId: anId key: aKeyOrNil handler: aBlock
    proxy: reader asHighPriorityActor partial: (Atom on: #(nil 0 nil)) ended: Future new closing: (Atom on: false).

_PBTcpReader >> _setTransport: aTransport socket: aSocket nodeId: anId key: aKeyOrNil handler: aBlock proxy: aProxy partial: aPartialAtom ended: aFuture closing: aClosingAtom
  "Runs once, on a fresh instance."
  transport isNil ifFalse: [^ PBUserError signal: '_PBTcpReader is immutable'].
  transport := aTransport.
  socket := aSocket.
  nodeId := anId.
  key := aKeyOrNil.
  handler := aBlock.
  proxy := aProxy.
  partial := aPartialAtom.
  ended := aFuture.
  closing := aClosingAtom.
  ^ self.

"Sends the first turn (once, from _admit:)."
_PBTcpReader >> begin
  proxy run.

"A Future that settles (with true) once the reader's last turn has closed the connection."
_PBTcpReader >> ended
  ^ ended.

"One turn of the reader (an actor method): reads and delivers frames for at most pollInterval
 (_readTurn), then sends the next turn to the proxy while the connection goes on. One actor, one
 turn at a time: the frames of a connection are delivered in arrival order. When the connection
 ends, a frame is refused or the transport stops, the connection is closed and forgotten and ended
 settles, also when this turn ends by an error (a handler's error that is not a PBDBError ends the
 connection's reader, as before)."
_PBTcpReader >> run
  | again |
  again := false.
  [again := self _readTurn] ensure: [again ifFalse: [
    [self closeSocket.
     transport _retire: socket] ensure: [ended resolve: true]]].
  again ifTrue: [proxy run].
  ^ true.

"Closes the connection, once, whoever asks first: the reader's last turn or stop. IOStream >>
 close is not atomic (its closed flag is a plain instance variable), so two threads closing one
 socket could both release its descriptor, the second perhaps after the number was given to
 another descriptor (final review M9); the compare-and-set of closing lets exactly one of them
 close it. A close that fails is written to stderr (PBClusterTransport _close:)."
_PBTcpReader >> closeSocket
  (closing value: true ifCurrent: false) ifFalse: [^ self].
  transport class _close: socket.

"Reads until a read waits pollInterval in vain or pollInterval has passed since the turn began;
 answers whether the connection goes on."
_PBTcpReader >> _readTurn
  | deadline step |
  deadline := Time microsecondClockValue + (PBTcpTransport pollInterval * 1000).
  [transport isRunning ifFalse: [^ false].
   step := self _readStep.
   step == #ended ifTrue: [^ false].
   step == #waiting ifTrue: [^ true].
   Time microsecondClockValue < deadline] whileTrue.
  ^ true.

"One step of the frame read so far (partial): the 4 length bytes, the length checked (lengthFrom:)
 before any body byte is read, then the body, at most readChunk bytes per read, then the message
 decoded and delivered as it is read (CC5). Answers #read (bytes read, or a frame delivered),
 #waiting (nothing arrived within the read timeout: partial is kept, so a frame split over a
 pause is read on) or #ended (the end of the stream, a read error, a refused frame or a stopped
 transport). A PBClusterProtocolError ends the connection and is counted (_rejected:). nextBytes:
 answers fewer bytes than asked only at the end of the stream (plan Task 1), and the next read
 then answers nil; a read that times out consumes nothing (the bytes that came stay in the
 socket's buffer for the next read)."
_PBTcpReader >> _readStep
  | state length got pieces want chunk timedOut |
  state := partial value.
  length := state at: 1.
  got := state at: 2.
  pieces := state at: 3.
  want := length isNil ifTrue: [4 - got] ifFalse: [length - got min: PBTcpTransport readChunk].
  want > 0 ifTrue: [
    timedOut := false.
    chunk := [socket nextBytes: want] on: Error do: [:e |
      (e isKindOf: MessageNotUnderstood) ifTrue: [e pass].
      timedOut := e isKindOf: ConnectionTimedOut.
      nil].
    timedOut ifTrue: [^ #waiting].
    (chunk isNil or: [chunk isEmpty]) ifTrue: [^ #ended].
    got := got + chunk size.
    pieces := { chunk. pieces }].
  length isNil ifTrue: [
    got < 4 ifTrue: [partial swap: [:old | { nil. got. pieces }]. ^ #read].
    length := [PBClusterFrame lengthFrom: (self class _join: pieces size: 4)] on: PBClusterProtocolError do: [:e |
      transport _rejected: e.
      ^ #ended].
    partial swap: [:old | { length. 0. nil }].
    ^ #read].
  got < length ifTrue: [partial swap: [:old | { length. got. pieces }]. ^ #read].
  partial swap: [:old | #(nil 0 nil)].
  ^ self _deliverBody: (self class _join: pieces size: length).

"Decodes aBody and delivers the message, unless the frame is refused (counted, the connection
 ends) or the transport stopped."
_PBTcpReader >> _deliverBody: aBody
  | message |
  message := [PBClusterFrame decodeBody: aBody to: nodeId key: key] on: PBClusterProtocolError do: [:e |
    transport _rejected: e.
    ^ #ended].
  transport isRunning ifFalse: [^ #ended].
  transport _deliver: message to: handler.
  ^ #read.

"The n bytes of pieces (see the class side's transport:...: the last piece first), as one
 ByteArray."
_PBTcpReader class >> _join: pieces size: n
  | all stream rest |
  n = 0 ifTrue: [^ ByteArray new].
  (pieces notNil and: [(pieces at: 2) isNil]) ifTrue: [^ pieces at: 1].
  all := OrderedCollection new.
  rest := pieces.
  [rest notNil] whileTrue: [all addFirst: (rest at: 1). rest := rest at: 2].
  stream := WriteStream on: ByteArray new.
  all do: [:each | stream nextPutAll: each].
  ^ stream contents.

"=== the sender actor (one per peer) ======================================"

Object subclass: #_PBTcpSender instanceVariableNames: 'transport peer queue link writing proxy ended'.

"The sender toward aPeer (a PBPeer): its queue (an Atom on a _PBSendQueue), its connection (an
 Atom on { socket or nil. end of the back-off in microseconds or nil }), writing (an Atom on the
 frame being written, { frame. bytes written. attempt, 1 or 2. microseconds of writing left },
 or nil), its actor proxy (high
 band) and ended, the Future that settles once it has finished after stop."
_PBTcpSender class >> transport: aTransport peer: aPeer
  | sender |
  sender := self basicNew.
  ^ sender _setTransport: aTransport peer: aPeer queue: (Atom on: _PBSendQueue new) link: (Atom on: #(nil nil))
    writing: (Atom on: nil) proxy: sender asHighPriorityActor ended: Future new.

_PBTcpSender >> _setTransport: aTransport peer: aPeer queue: aQueueAtom link: aLinkAtom writing: aWritingAtom proxy: aProxy ended: aFuture
  "Runs once, on a fresh instance."
  transport isNil ifFalse: [^ PBUserError signal: '_PBTcpSender is immutable'].
  transport := aTransport.
  peer := aPeer.
  queue := aQueueAtom.
  link := aLinkAtom.
  writing := aWritingAtom.
  proxy := aProxy.
  ended := aFuture.
  ^ self.

"A Future that settles (with true) once the sender has finished after stop."
_PBTcpSender >> ended
  ^ ended.

"Queues aFrame (called on the sender's thread, never blocks). The queue holds at most
 PBClusterFrame maxFrameBytes bytes: older frames are dropped, and counted, to make room; the
 newest is always kept. Starts the actor's drain unless it is draining."
_PBTcpSender >> offer: aFrame
  | old new |
  [old := queue value.
   old isClosed ifTrue: [^ self].
   new := old with: aFrame limit: PBClusterFrame maxFrameBytes.
   queue value: new ifCurrent: old] whileFalse.
  old size + 1 - new size timesRepeat: [transport _count: 'frames_dropped'].
  old isDraining ifFalse: [proxy drain].

"One turn of the drain (an actor method): writes the queued frames, oldest first, for at most
 pollInterval (_drainTurn), then sends the next turn to the proxy while frames remain. The queue
 counts as draining from the offer that starts a drain until a turn finds it empty, so at most
 one turn is queued or running at a time and no frame is stranded. A turn that ends by an error
 its steps did not catch gives the drain up (_drainFailed): the next offer starts a new one."
_PBTcpSender >> drain
  | again |
  again := nil.
  [again := self _drainTurn] ensure: [again isNil ifTrue: [self _drainFailed]].
  again ifTrue: [proxy drain].
  ^ true.

"Takes steps until the queue is empty or closed, or pollInterval has passed since the turn began;
 answers whether another turn is due. A step waits for the network at most once, for one connect
 (bounded by requestTimeout) or one write of at most writeChunk bytes (bounded by pollInterval,
 see _advance:). When the queue is found
 closed (stop), the connection is closed and ended settles."
_PBTcpSender >> _drainTurn
  | deadline step |
  deadline := Time microsecondClockValue + (PBTcpTransport pollInterval * 1000).
  [step := self _drainStep.
   step == #closed ifTrue: [[self _closeLink] ensure: [ended resolve: true]. ^ false].
   step == #empty ifTrue: [^ false].
   Time microsecondClockValue < deadline] whileTrue.
  ^ true.

"One step: the frame being written goes on (writing), or the oldest queued frame starts. Answers
 #wrote, #empty (the queue was empty and is no longer draining) or #closed (a frame left unwritten
 by stop is dropped and counted, as the write stop's close interrupted was). A stray error while
 writing one frame drops and counts that frame only, drops the connection, and the drain goes on:
 only _take, finding the queue empty, ends it, so no frame is stranded behind it.
 MessageNotUnderstood is caught here on purpose (unlike the other guards of this file, which pass
 it on): the sender must survive a bug in one write, and the error is written to stderr."
_PBTcpSender >> _drainStep
  | work frame |
  queue value isClosed ifTrue: [^ self _abandonWriting].
  work := writing value.
  work isNil ifTrue: [
    frame := self _take.
    frame isNil ifTrue: [^ queue value isClosed ifTrue: [self _abandonWriting] ifFalse: [#empty]].
    work := { frame. 0. 1. transport requestTimeout * 1000 }].
  [self _advance: work] on: Error do: [:e |
    transport class _warn: 'writing a frame to ' , peer nodeId printString , ' failed: ' , e messageText.
    self _discard: link value first.
    writing swap: [:old | nil].
    transport _count: 'frames_dropped'].
  ^ #wrote.

"Drops the frame being written, if any, and counts it; answers #closed."
_PBTcpSender >> _abandonWriting
  writing value isNil ifFalse: [
    writing swap: [:old | nil].
    transport _count: 'frames_dropped'].
  ^ #closed.

"The oldest queued frame, removed; nil (and the queue no longer draining) when it is empty, or
 nil when it is closed."
_PBTcpSender >> _take
  | old |
  [old := queue value.
   old isClosed ifTrue: [^ nil].
   queue value: old withoutFirst ifCurrent: old] whileFalse.
  ^ old size = 0 ifTrue: [nil] ifFalse: [old first].

"Writes the next piece of aWork's frame ({ frame. bytes written. attempt, 1 or 2. microseconds of
 waiting left }), at most writeChunk bytes, on the connection, connecting first when there is
 none (with requestTimeout), as proto_db's _send_loop writes the frame: a failed write closes the
 connection and the frame is written once more, whole, on a fresh one, at once; a frame is dropped
 and counted when there is no connection (a failed connect, or its back-off) or when the retry
 fails too. Only a failed connect starts a back-off. The frame is counted in frames_sent once its
 last byte is written.

 Each attempt may spend requestTimeout in all writing the frame, as the one write of 0.2.0 to
 0.3.0 and proto_db's sendall did; that time is spread over writes that each wait at most
 pollInterval, so a turn of the sender ends while a slow peer reads. The time each write takes is
 taken from what is left; the time between two writes is not, so a busy worker never fails a
 frame its peer is reading. A write that times out has written exactly bytesWritten leading bytes
 (protoST 0.16.1, protoIO 0.7.1): the unwritten rest stays in writing, and the next step writes
 it on the same connection; once no time is left, the attempt fails as a failed write does. Any
 other failed write, or a timeout that does not say how many bytes it wrote, fails the attempt at
 once."
_PBTcpSender >> _advance: aWork
  | frame offset attempt left socket end piece started outcome written |
  frame := aWork at: 1.
  offset := aWork at: 2.
  attempt := aWork at: 3.
  left := aWork at: 4.
  socket := self _connection.
  socket isNil ifTrue: [
    writing swap: [:old | nil].
    ^ transport _count: 'frames_dropped'].
  end := offset + PBTcpTransport writeChunk min: frame size.
  piece := (offset = 0 and: [end = frame size]) ifTrue: [frame] ifFalse: [frame copyFrom: offset + 1 to: end].
  started := Time microsecondClockValue.
  outcome := self _put: piece on: socket timeout: (left + 999 // 1000 min: PBTcpTransport pollInterval).
  left := left - (Time microsecondClockValue - started).
  written := outcome == #written ifTrue: [piece size] ifFalse: [outcome].
  (written isInteger and: [offset + written = frame size]) ifTrue: [
    writing swap: [:old | nil].
    ^ transport _count: 'frames_sent'].
  (written isInteger and: [left > 0]) ifTrue: [
    writing swap: [:old | { frame. offset + written. attempt. left }].
    ^ self].
  self _discard: socket.
  attempt = 1
    ifTrue: [writing swap: [:old | { frame. 0. 2. transport requestTimeout * 1000 }]]
    ifFalse: [
      writing swap: [:old | nil].
      transport _count: 'frames_dropped'].

"Writes aBytes on aSocket, waiting at most aMillis: answers #written, the number of leading bytes
 written when the write timed out (ConnectionTimedOut bytesWritten), or #failed when the write
 signals anything else (a reset, a closed peer, stop closing the socket) or a timeout without a
 count."
_PBTcpSender >> _put: aBytes on: aSocket timeout: aMillis
  [aSocket timeout: aMillis.
   aSocket nextPutBytes: aBytes] on: Error do: [:e |
    (e isKindOf: MessageNotUnderstood) ifTrue: [e pass].
    ^ ((e isKindOf: ConnectionTimedOut) and: [e bytesWritten isInteger])
      ifTrue: [e bytesWritten]
      ifFalse: [#failed]].
  ^ #written.

"Forgets the connection aSocketOrNil after a failed write and closes it, keeping the back-off of
 an earlier failed connect (proto_db keeps failed_at). Only while it is still the connection in
 link: stop may have taken it out and closed it already (_closeLink), and a socket is closed once."
_PBTcpSender >> _discard: aSocketOrNil
  | current |
  aSocketOrNil isNil ifTrue: [^ self].
  [current := link value.
   current first == aSocketOrNil ifFalse: [^ self].
   link value: { nil. current last } ifCurrent: current] whileFalse.
  transport class _close: aSocketOrNil.

"The open connection to the peer, connecting when there is none and the back-off is over; nil
 when there is no connection to write on."
_PBTcpSender >> _connection
  | current socket |
  current := link value.
  current first isNil ifFalse: [^ current first].
  queue value isClosed ifTrue: [^ nil].
  (current last notNil and: [Time microsecondClockValue < current last]) ifTrue: [^ nil].
  socket := [Socket connectTo: peer host port: peer port timeout: transport requestTimeout] on: Error do: [:e |
    (e isKindOf: MessageNotUnderstood) ifTrue: [e pass].
    nil].
  socket isNil ifTrue: [self _failConnect. ^ nil].
  "Only this actor sets a connection in link, and stop takes one out only when there is one, so
   this compare-and-set cannot lose; were it to, the socket is closed and not used."
  (link value: { socket. nil } ifCurrent: current) ifFalse: [transport class _close: socket. ^ nil].
  "stop closes the queue, then the socket in link: either it saw this socket, or this sees the
   closed queue."
  queue value isClosed ifTrue: [self _closeLink. ^ nil].
  ^ socket.

"Starts the back-off after a failed connect: a time from backoffBase to twice it (proto_db: a
 fixed reconnect_backoff; the jitter is protoBaseST's)."
_PBTcpSender >> _failConnect
  | random jitter |
  random := ByteArray randomBytes: 2.
  jitter := (random at: 1) * 256 + (random at: 2).
  link swap: [:old | { nil. Time microsecondClockValue + PBTcpTransport backoffBase
    + (PBTcpTransport backoffBase * jitter // 65536) }].

"Takes the connection out of link and closes it, if there is one. Both the drain and stop (from
 the caller's thread) call this; the compare-and-set lets exactly one of them close a connection,
 as _PBTcpReader >> closeSocket does for an accepted one (final review M9). A close that fails is
 written to stderr (PBClusterTransport _close:)."
_PBTcpSender >> _closeLink
  | current |
  [current := link value.
   current first isNil ifTrue: [^ self].
   link value: { nil. current last } ifCurrent: current] whileFalse.
  transport class _close: current first.

"After a drain turn that an uncaught error ended: the queue no longer counts as draining, so the
 next offer starts a drain (the frame being written, if any, goes on then); when the queue is
 closed, ended settles."
_PBTcpSender >> _drainFailed
  | now |
  now := queue swap: [:old | old notDraining].
  now isClosed ifTrue: [[self _closeLink] ensure: [ended resolve: true]].

"Closes the queue (its frames are discarded) and the connection, which wakes a write in
 progress; answers ended, a Future that settles once the actor has finished: at once when no
 drain was queued or running (the queue was not draining), else when the drain's turn sees the
 closed queue."
_PBTcpSender >> stop
  | now |
  now := queue swap: [:old | old closed].
  [self _closeLink] ensure: [now isDraining ifFalse: [ended resolve: true]].
  ^ ended.

"=== the queue of a sender ================================================"

Object subclass: #_PBSendQueue instanceVariableNames: 'frames bytes draining closed'.

"Empty, idle, open."
_PBSendQueue class >> new
  ^ self basicNew _setFrames: #() bytes: 0 draining: false closed: false.

_PBSendQueue >> _setFrames: anArray bytes: anInteger draining: aBoolean closed: aClosedBoolean
  "Runs once, on a fresh instance."
  frames isNil ifFalse: [^ PBUserError signal: '_PBSendQueue is immutable'].
  frames := anArray.
  bytes := anInteger.
  draining := aBoolean.
  closed := aClosedBoolean.
  ^ self.

_PBSendQueue >> size
  ^ frames size.

_PBSendQueue >> first
  ^ frames first.

_PBSendQueue >> isDraining
  ^ draining.

_PBSendQueue >> isClosed
  ^ closed.

"This queue with aFrame added last and draining, and the oldest frames removed while the total
 exceeds aLimit bytes (never the new one)."
_PBSendQueue >> with: aFrame limit: aLimit
  | kept total |
  kept := frames copyWith: aFrame.
  total := bytes + aFrame size.
  [total > aLimit and: [kept size > 1]] whileTrue: [
    total := total - kept first size.
    kept := kept copyFrom: 2 to: kept size].
  ^ self class basicNew _setFrames: kept bytes: total draining: true closed: closed.

"This queue, no longer draining (after a drain turn that failed)."
_PBSendQueue >> notDraining
  ^ self class basicNew _setFrames: frames bytes: bytes draining: false closed: closed.

"This queue without its oldest frame; empty, it is no longer draining."
_PBSendQueue >> withoutFirst
  frames isEmpty ifTrue: [^ self class basicNew _setFrames: #() bytes: 0 draining: false closed: closed].
  ^ self class basicNew _setFrames: (frames copyFrom: 2 to: frames size) bytes: bytes - frames first size
    draining: true closed: closed.

"Closed, its frames discarded."
_PBSendQueue >> closed
  ^ self class basicNew _setFrames: #() bytes: 0 draining: draining closed: true.
