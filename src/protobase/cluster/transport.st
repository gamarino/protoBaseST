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
                        black-holed peer delays nobody else). Connections are one-way: a node
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

This module is a shell, not part of the core: the sender reads the monotonic clock for its
reconnection back-off (plan, 'Time': the shells read Time microsecondClockValue).

Every value here is immutable; the transports keep their state in Atoms created by their
initialisers."

Import from: 'net'.
Import from: 'protobase/errors'.
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
 actor."
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
    listener: (_PBTcpListener transport: self server: listener) asHighPriorityActor.
  (run value: current ifCurrent: nil) ifFalse: [
    ^ PBValidationError signal: 'This transport was already started'].
  current listener run.

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
 the readers), closes each sender's queue and connection (which wakes a sender blocked in a
 write), then answers a Future that settles once the listener, every reader it started and
 every sender have finished."
PBTcpTransport >> stop
  | current done closed senders |
  [current := run value.
   (current isKindOf: Future) ifTrue: [^ current].
   done := Future new.
   run value: done ifCurrent: current] whileFalse.
  current isNil ifTrue: [listener close. done resolve: true. ^ done].
  closed := inbound swap: [:old | old closed].
  listener close.
  closed sockets do: [:each | each close].
  senders := current senders values asArray collect: [:each | each stop].
  "The listener's finish runs after its accept loop ends (mailbox order): every reader it
   started is registered by then, and a reader's finish runs after its run (mailbox order)."
  (self class _settled: current listener finish) thenDo: [:x |
    (self class _allSettled: (inbound value readers collect: [:each | each finish]) , senders)
      thenDo: [:y | done resolve: true]].
  ^ done.

PBTcpTransport >> _isRunning: aRunValue
  ^ aRunValue isClassObject not and: [aRunValue class == _PBTransportRun].

PBTcpTransport >> isRunning
  ^ self _isRunning: run value.

"Starts a reader actor for aSocket, accepted by the listener, unless the transport stopped: the
 socket and its reader are registered before the reader runs, so stop either closes the socket
 or this method sees the transport closed and closes it."
PBTcpTransport >> _admit: aSocket
  | current old reader |
  current := run value.
  (self _isRunning: current) ifFalse: [aSocket close. ^ self].
  reader := (_PBTcpReader transport: self socket: aSocket nodeId: current nodeId key: current key handler: current handler)
    asHighPriorityActor.
  [old := inbound value.
   old isClosed ifTrue: [aSocket close. ^ self].
   inbound value: (old with: aSocket reader: reader) ifCurrent: old] whileFalse.
  reader run.

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

"The reader actors of those sockets."
_PBInbound >> readers
  ^ entries collect: [:each | each last].

_PBInbound >> with: aSocket reader: aReader
  ^ self class basicNew _setClosed: closed entries: (entries copyWith: { aSocket. aReader }).

_PBInbound >> without: aSocket
  ^ self class basicNew _setClosed: closed entries: (entries reject: [:each | each first == aSocket]).

_PBInbound >> closed
  ^ self class basicNew _setClosed: true entries: entries.

"=== the listener actor ==================================================="

Object subclass: #_PBTcpListener instanceVariableNames: 'transport server'.

_PBTcpListener class >> transport: aTransport server: aServerSocket
  ^ self basicNew _setTransport: aTransport server: aServerSocket.

_PBTcpListener >> _setTransport: aTransport server: aServerSocket
  "Runs once, on a fresh instance."
  transport isNil ifFalse: [^ PBUserError signal: '_PBTcpListener is immutable'].
  transport := aTransport.
  server := aServerSocket.
  ^ self.

"Accepts connections until the transport stops, handing each to the transport (_admit:). stop
 closes the listening socket, which wakes the accept; an accept that fails while the transport
 runs is written to stderr and the loop goes on (proto_db _accept)."
_PBTcpListener >> run
  [ | socket failure |
    failure := nil.
    socket := [server accept] on: Error do: [:e |
      (e isKindOf: MessageNotUnderstood) ifTrue: [e pass].
      failure := e messageText.
      nil].
    transport isRunning ifFalse: [
      "An accept that stop's close woke answers a Socket without a descriptor (protoST 0.12.0),
       whose close signals: it holds nothing to release."
      socket isNil ifFalse: [[socket close] on: Error do: [:e |
        (e isKindOf: MessageNotUnderstood) ifTrue: [e pass].
        nil]].
      ^ true].
    socket isNil
      ifTrue: [transport class _warn: 'accepting a connection failed: ' , failure printString]
      ifFalse: [transport _admit: socket]] repeat.

"Answers once run has returned (mailbox order)."
_PBTcpListener >> finish
  ^ true.

"=== the reader actor (one per accepted connection) ======================="

Object subclass: #_PBTcpReader instanceVariableNames: 'transport socket nodeId key handler'.

_PBTcpReader class >> transport: aTransport socket: aSocket nodeId: anId key: aKeyOrNil handler: aBlock
  ^ self basicNew _setTransport: aTransport socket: aSocket nodeId: anId key: aKeyOrNil handler: aBlock.

_PBTcpReader >> _setTransport: aTransport socket: aSocket nodeId: anId key: aKeyOrNil handler: aBlock
  "Runs once, on a fresh instance."
  transport isNil ifFalse: [^ PBUserError signal: '_PBTcpReader is immutable'].
  transport := aTransport.
  socket := aSocket.
  nodeId := anId.
  key := aKeyOrNil.
  handler := aBlock.
  ^ self.

"Reads frames until the connection ends, a frame is refused or the transport stops; the
 connection is closed on every way out."
_PBTcpReader >> run
  [self _readFrames] ensure: [
    socket close.
    transport _retire: socket].
  ^ true.

"Answers once run has returned (mailbox order)."
_PBTcpReader >> finish
  ^ true.

"Each frame: the 4 length bytes, the length checked (lengthFrom:) before the body is read, the
 body, then the message decoded and delivered as it is read (CC5). A PBClusterProtocolError
 closes the connection (counted); the end of the stream, a read error or a stopped transport end
 the loop."
_PBTcpReader >> _readFrames
  [ | head message |
    head := self _readExactly: 4 from: socket.
    head isNil ifTrue: [^ self].
    message := [ | body |
        body := self _readExactly: (PBClusterFrame lengthFrom: head) from: socket.
        body isNil ifTrue: [^ self].
        PBClusterFrame decodeBody: body to: nodeId key: key]
      on: PBClusterProtocolError do: [:e |
        transport _rejected: e.
        ^ self].
    transport isRunning ifFalse: [^ self].
    transport _deliver: message to: handler] repeat.

"The next n bytes of aSocket, or nil when the stream ends (or fails) first. nextBytes: may answer
 fewer bytes than asked (plan Task 1: a short read at the end of the stream), so this loops until
 it has n."
_PBTcpReader >> _readExactly: n from: aSocket
  | stream got chunk |
  n = 0 ifTrue: [^ ByteArray new].
  stream := nil.
  got := 0.
  [got < n] whileTrue: [
    chunk := [aSocket nextBytes: n - got] on: Error do: [:e |
      (e isKindOf: MessageNotUnderstood) ifTrue: [e pass].
      nil].
    (chunk isNil or: [chunk isEmpty]) ifTrue: [^ nil].
    (got = 0 and: [chunk size = n]) ifTrue: [^ chunk].
    stream isNil ifTrue: [stream := WriteStream on: ByteArray new].
    stream nextPutAll: chunk.
    got := got + chunk size].
  ^ stream contents.

"=== the sender actor (one per peer) ======================================"

Object subclass: #_PBTcpSender instanceVariableNames: 'transport peer queue link proxy'.

"The sender toward aPeer (a PBPeer): its queue (an Atom on a _PBSendQueue), its connection (an
 Atom on { socket or nil. end of the back-off in microseconds or nil }) and its actor proxy."
_PBTcpSender class >> transport: aTransport peer: aPeer
  | sender |
  sender := self basicNew.
  ^ sender _setTransport: aTransport peer: aPeer queue: (Atom on: _PBSendQueue new) link: (Atom on: #(nil nil))
    proxy: sender asHighPriorityActor.

_PBTcpSender >> _setTransport: aTransport peer: aPeer queue: aQueueAtom link: aLinkAtom proxy: aProxy
  "Runs once, on a fresh instance."
  transport isNil ifFalse: [^ PBUserError signal: '_PBTcpSender is immutable'].
  transport := aTransport.
  peer := aPeer.
  queue := aQueueAtom.
  link := aLinkAtom.
  proxy := aProxy.
  ^ self.

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

"Writes the queued frames, oldest first, until the queue is empty or closed (an actor method)."
_PBTcpSender >> drain
  | frame |
  [[(frame := self _take) notNil] whileTrue: [self _write: frame]] on: Error do: [:e |
    "A stray error must not leave the queue draining with no drain running: offer: would never
     start one again and the peer would be cut off. It is reported, the connection is dropped,
     and the next offer: starts a new drain."
    transport class _warn: 'the sender to ' , peer nodeId printString , ' failed: ' , e messageText.
    self _discard: link value first.
    queue swap: [:old | old idle].
    ^ false].
  queue value isClosed ifTrue: [self _closeLink].
  ^ true.

"The oldest queued frame, removed; nil (and the queue no longer draining) when it is empty, or
 nil when it is closed."
_PBTcpSender >> _take
  | old |
  [old := queue value.
   old isClosed ifTrue: [^ nil].
   queue value: old withoutFirst ifCurrent: old] whileFalse.
  ^ old size = 0 ifTrue: [nil] ifFalse: [old first].

"Writes aFrame on the connection, connecting first when there is none (with requestTimeout), as
 proto_db's _send_loop: a failed write closes the connection and the frame is written once more
 on a fresh one, at once; a frame is dropped and counted when there is no connection (a failed
 connect, or its back-off) or when the retry fails too. Only a failed connect starts a back-off."
_PBTcpSender >> _write: aFrame
  | socket |
  2 timesRepeat: [
    socket := self _connection.
    socket isNil ifTrue: [^ transport _count: 'frames_dropped'].
    (self _put: aFrame on: socket) ifTrue: [^ transport _count: 'frames_sent'].
    self _discard: socket].
  transport _count: 'frames_dropped'.

"Whether aFrame was written on aSocket (false when the write signals: a reset, a closed peer, a
 timeout, or stop closing the socket)."
_PBTcpSender >> _put: aFrame on: aSocket
  [aSocket nextPutBytes: aFrame] on: Error do: [:e |
    (e isKindOf: MessageNotUnderstood) ifTrue: [e pass].
    ^ false].
  ^ true.

"Closes aSocketOrNil after a failed write and forgets the connection, keeping the back-off of an
 earlier failed connect (proto_db keeps failed_at)."
_PBTcpSender >> _discard: aSocketOrNil
  aSocketOrNil isNil ifFalse: [aSocketOrNil close].
  link swap: [:old | { nil. old last }].

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
  socket timeout: transport requestTimeout.
  link value: { socket. nil } ifCurrent: current.
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

_PBTcpSender >> _closeLink
  | socket |
  socket := link value first.
  socket isNil ifFalse: [socket close].

"Closes the queue (its frames are discarded) and the connection, which wakes a write in
 progress; answers a Future that settles once the actor has finished what it was doing."
_PBTcpSender >> stop
  queue swap: [:old | old closed].
  self _closeLink.
  ^ proxy finish.

"Answers once the drain in progress, if any, has returned (mailbox order)."
_PBTcpSender >> finish
  self _closeLink.
  ^ true.

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

"This queue without its oldest frame; empty, it is no longer draining."
_PBSendQueue >> withoutFirst
  frames isEmpty ifTrue: [^ self class basicNew _setFrames: #() bytes: 0 draining: false closed: closed].
  ^ self class basicNew _setFrames: (frames copyFrom: 2 to: frames size) bytes: bytes - frames first size
    draining: true closed: closed.

"This queue, not draining (its frames kept)."
_PBSendQueue >> idle
  ^ self class basicNew _setFrames: frames bytes: bytes draining: false closed: closed.

"Closed, its frames discarded."
_PBSendQueue >> closed
  ^ self class basicNew _setFrames: #() bytes: 0 draining: draining closed: true.
