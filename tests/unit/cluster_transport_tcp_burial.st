"EXPECT: ok 3"
"PBTcpTransport (cluster/transport.st) never buries a waiting actor under a connection. A wait
 nested in a block (here inside ensure:, as a commit's wait is) blocks its worker, which runs other
 actors' messages on top of it until they end (protoST LANGUAGE 10.4, D56); the waiting message
 resumes only when the message run on top of it returns. In protoBaseST 0.2.0 to 0.3.0 the
 listener's accept loop and each reader's read loop were one endless message for the life of the
 transport or the connection, so a reader admitted while an actor waited could run on top of that
 actor and keep it buried until the transport stopped. Every message of the transport now ends
 (one accept or one read with a short timeout, then the actor sends itself the next turn), so a
 waiting actor resumes after the turn on top of it.

 Five transports on 127.0.0.1, each started with every other as a peer. (1) Eight actors wait
 inside ensure: on one Future while every transport connects to every other (20 connections
 accepted and 20 frames delivered); the Future is then resolved and every actor must answer while
 every transport still runs. (2) The same with the 20 connections already open and idle: eight
 new actors wait while 20 more frames travel on them. (3) The same with a raw connection to each
 transport that sends nothing (its reader only polls) and a sixth peer, never listening, that
 each transport keeps failing to reach: eight more actors wait while 20 more frames travel.

 Not buried is proved by completion, not by time: the program waits for each actor without a
 deadline, before any transport stops; a buried actor keeps the program waiting until the test
 runner's timeout fails it. Every other wait is for a condition, checked every 10 ms, without a
 deadline either. tests/unit/cluster_transport_tcp_burial_one_worker.sh runs this file with
 PROTOST_WORKERS=1, where every nested wait of the program shares one worker; the old transport
 hung there in every run."
Import from: 'protobase'.
Import from: 'net'.
Import from: '_check'.

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

| c ids ts delivered listen membership await request sendAll waiters raws verdicts unreachable gate vs verdict |
c := Check new.
ids := #('n0' 'n1' 'n2' 'n3' 'n4').
delivered := Atom on: 0.
listen := [PBTcpTransport withListener: (ServerSocket listenOn: 0 host: '127.0.0.1') requestTimeout: 60000].
membership := [:pairs | PBMembership peers: (pairs collect: [:p | PBPeer nodeId: p first host: '127.0.0.1' port: p last]) voters: nil].
"Until aBlock is true, checked every 10 ms; no deadline (the runner's timeout bounds the test)."
await := [:aBlock | [aBlock value] whileFalse: [(Future after: 10) wait]].
request := [:from :t | PBClusterMessage type: 'request' from: from fields: { 'term' -> t. 'rid' -> t. 'inc' -> 0. 'vs' -> 0 }].
"Every transport sends one frame to every other: 20 frames."
sendAll := [:t |
  1 to: ids size do: [:i | 1 to: ids size do: [:j | i = j ifFalse: [
    (ts at: i) send: (request value: (ids at: i) value: t) to: (ids at: j)]]]].
"Eight actors waiting inside ensure: on aFuture, once every one has entered its wait."
waiters := [:aFuture |
  | entered actors |
  entered := Atom on: 0.
  actors := (1 to: 8) asArray collect: [:i | (Waiter entered: entered) asActor nestedWaitFor: aFuture].
  await value: [entered value = 8].
  actors].
"Resolves aFuture, then waits for every actor of anArray without a deadline: the answers, and
 whether every transport was still running when the last one answered."
verdicts := [:aFuture :anArray |
  | answers |
  aFuture resolve: true.
  answers := anArray collect: [:v | v wait].
  { answers. ts allSatisfy: [:t | t isRunning] }].

unreachable := ServerSocket listenOn: 0 host: '127.0.0.1'.
ts := ids collect: [:id | listen value].
1 to: ids size do: [:i | (ts at: i) start: (ids at: i)
  peers: (membership value: (((1 to: ids size) asArray collect: [:j | { ids at: j. (ts at: j) port }])
    copyWith: { 'gone'. unreachable port }))
  key: nil handler: [:m | delivered swap: [:n | n + 1]]].
"The sixth peer's port is closed: every connect to it is refused."
unreachable close.

"(1) Connections accepted while the actors wait."
gate := Future new.
vs := waiters value: gate.
sendAll value: 1.
await value: [delivered value >= 20].
verdict := verdicts value: gate value: vs.
('waiting actors resumed while 20 connections were accepted: ' , (verdict first count: [:x | x == #resumed]) printString , ' of 8')
  displayNl.
c that: 'eight actors waiting in blocks while 20 connections are accepted all resume, every transport running'
  is: verdict equals: { (1 to: 8) asArray collect: [:i | #resumed]. true }.

"(2) Open, idle connections: the readers' turns run while the actors wait."
gate := Future new.
vs := waiters value: gate.
sendAll value: 2.
await value: [delivered value >= 40].
verdict := verdicts value: gate value: vs.
('waiting actors resumed over 20 open connections: ' , (verdict first count: [:x | x == #resumed]) printString , ' of 8')
  displayNl.
c that: 'eight actors waiting in blocks while frames travel on 20 open connections all resume, every transport running'
  is: verdict equals: { (1 to: 8) asArray collect: [:i | #resumed]. true }.

"(3) A silent raw connection to each transport, and a peer every transport fails to reach."
raws := ts collect: [:t | Socket connectTo: '127.0.0.1' port: t port timeout: 60000].
ts do: [:t | t send: (request value: 'x' value: 3) to: 'gone'].
gate := Future new.
vs := waiters value: gate.
sendAll value: 3.
ts do: [:t | t send: (request value: 'x' value: 4) to: 'gone'].
await value: [delivered value >= 60].
verdict := verdicts value: gate value: vs.
('waiting actors resumed beside silent connections and an unreachable peer: '
  , (verdict first count: [:x | x == #resumed]) printString , ' of 8') displayNl.
c that: 'eight actors waiting in blocks beside silent connections and an unreachable peer all resume, every transport running'
  is: verdict equals: { (1 to: 8) asArray collect: [:i | #resumed]. true }.

ts do: [:t | t stop wait].
raws do: [:s | s close].
verdict := c report.
verdict displayNl.
(verdict beginsWith: 'ok') ifFalse: [Smalltalk exit: 1].
verdict
