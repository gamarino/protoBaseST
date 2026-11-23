"EXPECT: ok 6"
"PBTcpTransport (cluster/transport.st) starves no other actor while its connections are open and
 idle. Every turn of the listener and of each reader ends after one accept or one read that waits
 at most pollInterval, and the actor then sends itself the next turn. A worker that is not
 waiting runs, in one turn, every message of the actor it picked, including the ones the actor
 sends itself meanwhile (protoST STATUS D59), so a service actor that kept re-sending itself
 without ever blocking would keep its worker for good, and with PROTOST_WORKERS=1 nothing else,
 timers included, would ever run again. The transport's turns block in I/O (an accept or a read
 with a timeout), and the pool adds a worker while a worker is blocked in I/O, so the rest of the
 program runs there. This test is the guard on that property: it fails, by a hang, if a transport
 turn ever re-sends itself without blocking.

 Two transports on 127.0.0.1, each the other's peer: a sends one frame to b, so b's reader of
 that connection is open and polls; a raw socket opened on a, that never sends, keeps a second
 reader polling; both listeners poll. Nothing is sent after that. Then, from the program thread,
 with no deadline: (1) eight actors, none of which ever waits, each compute a sum and answer it;
 (2) a relay of 2,000 hops through four actors, sent without any wait, settles a Future at its
 last hop; (3) a timer (Future after: 1) settles; (4) the eight actors are asked again, in a
 burst of 400 messages. Each must complete while both transports run and both connections stay
 open (checks 5 and 6).

 Progress is proved by completion, never by time: the program waits for each answer without a
 deadline, and a starved actor keeps it waiting until the test runner's timeout fails it. The
 only other waits are for a condition, checked every 10 ms, without a deadline.
 tests/unit/cluster_transport_tcp_starvation_one_worker.sh runs this file with
 PROTOST_WORKERS=1, where the transport's turns and every other actor share one worker unless
 the pool grows."
Import from: 'protobase'.
Import from: 'net'.
Import from: '_check'.

"An actor that never waits: it computes and answers."
Object subclass: #Summer.

Summer >> sumTo: n
  | total |
  total := 0.
  1 to: n do: [:i | total := total + i].
  ^ total.

"One hop of a relay: sends the rest of the hops to the next actor, without waiting, and settles
 aFuture at the last one."
Object subclass: #Hop instanceVariableNames: 'next'.

Hop >> next: anActor
  next := anActor.

Hop >> hops: n settle: aFuture
  n = 0 ifTrue: [aFuture resolve: true. ^ true].
  next hops: n - 1 settle: aFuture.
  ^ true.

| c a b delivered listen membership await raw summers answers relay hops done timer inboundOpen |
c := Check new.
delivered := Atom on: 0.
listen := [PBTcpTransport withListener: (ServerSocket listenOn: 0 host: '127.0.0.1') requestTimeout: 60000].
membership := [:pairs | PBMembership peers: (pairs collect: [:p | PBPeer nodeId: p first host: '127.0.0.1' port: p last]) voters: nil].
"Until aBlock is true, checked every 10 ms; no deadline (the runner's timeout bounds the test)."
await := [:aBlock | [aBlock value] whileFalse: [(Future after: 10) wait]].
"The accepted connections of a transport whose readers have not ended."
inboundOpen := [:t | (t instVarNamed: 'inbound') value sockets size].

a := listen value. b := listen value.
a start: 'a' peers: (membership value: { { 'a'. a port }. { 'b'. b port } }) key: nil handler: [:m | delivered swap: [:n | n + 1]].
b start: 'b' peers: (membership value: { { 'a'. a port }. { 'b'. b port } }) key: nil handler: [:m | delivered swap: [:n | n + 1]].
a send: (PBClusterMessage type: 'request' from: 'a' fields: { 'term' -> 1. 'rid' -> 1. 'inc' -> 0. 'vs' -> 0 }) to: 'b'.
await value: [delivered value = 1].
raw := Socket connectTo: '127.0.0.1' port: a port timeout: 60000.
await value: [(inboundOpen value: a) = 1].

"(1) Eight actors that never wait."
summers := (1 to: 8) asArray collect: [:i | Summer new asActor].
answers := summers collect: [:s | (s sumTo: 100000) wait].
c that: 'eight actors that never wait answer while the transports poll idle connections'
  is: answers equals: ((1 to: 8) asArray collect: [:i | 5000050000]).

"(2) A relay of 2,000 hops among four actors, none of which waits."
hops := (1 to: 4) asArray collect: [:i | Hop new].
relay := hops collect: [:h | h asActor].
"Each hop's next actor is set before any message is sent to the relay."
1 to: 4 do: [:i | (hops at: i) next: (relay at: i \\ 4 + 1)].
done := Future new.
(relay at: 1) hops: 2000 settle: done.
c that: 'a relay of 2000 hops completes while the transports poll' is: done wait equals: true.

"(3) A timer settles."
timer := [(Future after: 1) wait. #settled] value.
c that: 'a timer settles while the transports poll' is: timer equals: #settled.

"(4) A burst of 400 messages to the same eight actors."
answers := ((1 to: 400) asArray collect: [:i | (summers at: i - 1 \\ 8 + 1) sumTo: i]) collect: [:f | f wait].
c that: 'a burst of 400 messages to actors that never wait is answered'
  is: answers equals: ((1 to: 400) asArray collect: [:i | i * (i + 1) // 2]).

c that: 'both transports still run' is: { a isRunning. b isRunning } equals: #(true true).
c that: 'the frame was delivered once, and both polled connections are still open'
  is: { delivered value. inboundOpen value: a. inboundOpen value: b } equals: #(1 1 1).

a stop wait. b stop wait.
raw close.
answers := c report.
answers displayNl.
(answers beginsWith: 'ok') ifFalse: [Smalltalk exit: 1].
answers
