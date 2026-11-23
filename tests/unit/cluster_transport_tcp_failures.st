"EXPECT: ok 8"
"PBTcpTransport (cluster/transport.st): the failure paths of closing and accepting (final review
 M1, M9, M10).

 M1: every actor of the transport settles its Future ended when its last turn ends, and stop
 chains on those Futures, so an ended left unsettled hangs stop wait. A close that signals must
 not leave it so: protoST signals on closing a Socket without a descriptor (the listener's note in
 _acceptOne), and a close can fail like any system call. (1) A reader whose connection's close
 signals an Error: its last turn ends normally and ended settles. (2) A sender stopped while its
 connection's close signals: stop answers ended, settled. (3) A sender whose drain turn finds the
 queue closed and its close signals: ended settles. (4) The same three with a close that signals
 MessageNotUnderstood (a bug, which the transport passes on as everywhere else): the error
 reaches the caller, and ended is settled all the same.

 M9: each socket is closed exactly once, whoever closes it first: stop or the reader's last turn
 for an accepted connection, stop or the drain for a sender's. IOStream >> close is not atomic
 (its closed flag is a plain instance variable), so two threads closing one socket could both
 release its descriptor, the second perhaps after the number was given to another descriptor.
 (5) A stopped transport's registered reader, closed by stop and then by its last turn: one close;
 stop's Future settles once the reader ended. (6) A sender stopped, then drained: one close.

 M10: an accept that fails at once (EMFILE, for example) must not make the listener spin, one
 stderr line per turn without a pause. (7) The listener's step answers #failed for a failed accept,
 which its turn answers with a timer of pollInterval before the next turn, never an immediate
 one; #idle when no connection came. (8) A transport whose listener fails every accept still stops.
 (9) The pause itself: a listener whose accept fails, its proxy replaced by a TurnRecorder, runs
 one turn on the program thread. The recorder signals TurnSent, a Notification, at each run it is
 sent; the test's handler around the turn catches it only when the next turn is sent inside the
 turn (the spin), on the program thread; sent by the timer, on a worker, no handler of the test is
 on that stack and the Notification answers nil. So the check is the handler's verdict, not a
 time: the turn must return without sending, and the timer's send must come (waited for without a
 deadline: the runner's timeout bounds it). Removing the timer branch of _PBTcpListener >> run
 fails it.

 Test seams, in this file only: FakeSocket and FailingServer stand in for a Socket and a
 ServerSocket (the transport's actors call only close, nextBytes:, timeout: and acceptTimeout: on
 them); the test installs them through the actors' constructors and instVarNamed:put:, and calls
 the actor methods (run, drain) from the program thread, so each step is certain. Whether a Future
 is settled is read without waiting: resolve: of a settled Future is a no-op (protoST), so a probe
 value resolved into it comes back only when it was pending. No duration is asserted."
Import from: 'protobase'.
Import from: 'net'.
Import from: '_check'.

"A socket stand-in whose close counts and then does what its mode says: #ok, #error (signals an
 Error) or #bug (sends a message nothing understands)."
Object subclass: #FakeSocket instanceVariableNames: 'mode closes'.

FakeSocket class >> mode: aSymbol
  ^ self basicNew setMode: aSymbol.

FakeSocket >> setMode: aSymbol
  mode := aSymbol.
  closes := Atom on: 0.

FakeSocket >> closes
  ^ closes value.

FakeSocket >> close
  closes swap: [:n | n + 1].
  mode == #error ifTrue: [^ Error signal: 'injected: the close failed'].
  mode == #bug ifTrue: [^ self aSelectorNothingUnderstands].
  ^ self.

FakeSocket >> timeout: aMillis
  ^ self.

"The end of the stream at once."
FakeSocket >> nextBytes: anInteger
  ^ nil.

"A server socket stand-in whose every accept fails at once."
Object subclass: #FailingServer.

FailingServer >> acceptTimeout: aMillis
  ^ Error signal: 'injected: too many open files'.

FailingServer >> close
  ^ self.

"Signalled by a TurnRecorder at each turn it is sent."
Notification subclass: #TurnSent.

"A stand-in for the listener's actor proxy: counts the turns sent to it."
Object subclass: #TurnRecorder instanceVariableNames: 'calls'.

TurnRecorder class >> new
  ^ self basicNew setCalls.

TurnRecorder >> setCalls
  calls := Atom on: 0.

TurnRecorder >> calls
  ^ calls value.

TurnRecorder >> run
  calls swap: [:n | n + 1].
  TurnSent new signal.
  ^ self.

| c membership settled peer t b reader sender fake outcome queueOf runOf listener frame stopped recorder sync |
c := Check new.
membership := [:pairs | PBMembership peers: (pairs collect: [:p | PBPeer nodeId: p first host: '127.0.0.1' port: p last]) voters: nil].
"Whether aFuture had settled: resolve: of a settled Future is a no-op, so the probe comes back
 only when it was pending (and the Future is settled from then on)."
settled := [:aFuture | aFuture resolve: #probe. aFuture wait ~~ #probe].
"A closed queue that counts as draining, holding aFrame: what a drain turn finds after stop."
queueOf := [:aFrame | (_PBSendQueue new with: aFrame limit: PBClusterFrame maxFrameBytes) closed].
frame := PBClusterFrame encode: (PBClusterMessage type: 'reject' from: 'a' fields: { 'term' -> 1. 'rid' -> 1. 'inc' -> 0.
  'root' -> nil. 'certain' -> false. 'reason' -> 'x'. 'highest' -> 0. 'remaining' -> 0 }) to: 'b' key: nil.
"A transport that is not started: its readers' and senders' turns end at once."
t := PBTcpTransport withListener: (ServerSocket listenOn: 0 host: '127.0.0.1') requestTimeout: 60000.
peer := PBPeer nodeId: 'b' host: '127.0.0.1' port: 1.

"(1) to (4): M1."
outcome := #('error' 'bug') collect: [:mode | | r s1 s2 results |
  results := OrderedCollection new.
  fake := FakeSocket mode: mode asSymbol.
  r := _PBTcpReader transport: t socket: fake nodeId: 'a' key: nil handler: [:m | nil].
  results add: ([r run. #returned] on: Error do: [:e | e return: #signalled]).
  results add: (settled value: r ended).
  s1 := _PBTcpSender transport: t peer: peer.
  (s1 instVarNamed: 'link') swap: [:x | { FakeSocket mode: mode asSymbol. nil }].
  results add: ([s1 stop. #returned] on: Error do: [:e | e return: #signalled]).
  results add: (settled value: (s1 instVarNamed: 'ended')).
  s2 := _PBTcpSender transport: t peer: peer.
  (s2 instVarNamed: 'link') swap: [:x | { FakeSocket mode: mode asSymbol. nil }].
  (s2 instVarNamed: 'queue') swap: [:x | (queueOf value: frame)].
  results add: ([s2 drain. #returned] on: Error do: [:e | e return: #signalled]).
  results add: (settled value: (s2 instVarNamed: 'ended')).
  results asArray].
c that: '(1)-(3) a close that signals an Error: each last turn and stop end normally, and every ended settles'
  is: outcome first equals: { #returned. true. #returned. true. #returned. true }.
c that: '(4) a close that signals MessageNotUnderstood: the error reaches the caller, and every ended settles all the same'
  is: outcome last equals: { #signalled. true. #signalled. true. #signalled. true }.

"(5) M9: stop and the reader's last turn both close the accepted connection; it is closed once."
b := PBTcpTransport withListener: (ServerSocket listenOn: 0 host: '127.0.0.1') requestTimeout: 60000.
b start: 'b' peers: (membership value: { { 'a'. 1 }. { 'b'. b port } }) key: nil handler: [:m | nil].
fake := FakeSocket mode: #ok.
reader := _PBTcpReader transport: b socket: fake nodeId: 'b' key: nil handler: [:m | nil].
(b instVarNamed: 'inbound') swap: [:old | old with: fake reader: reader].
stopped := b stop.
reader run.
c that: '(5) an accepted connection closed by stop and by its reader''s last turn is closed once; stop settles'
  is: { fake closes. stopped wait. settled value: reader ended } equals: { 1. true. true }.

"(6) M9: a sender stopped, then drained: its connection is closed once."
sender := _PBTcpSender transport: t peer: peer.
fake := FakeSocket mode: #ok.
(sender instVarNamed: 'link') swap: [:x | { fake. nil }].
(sender instVarNamed: 'queue') swap: [:x | (_PBSendQueue new with: frame limit: PBClusterFrame maxFrameBytes)].
sender stop.
sender drain.
c that: '(6) a sender''s connection closed by stop and by the drain that finds the queue closed is closed once'
  is: { fake closes. settled value: (sender instVarNamed: 'ended') } equals: { 1. true }.

"(7) M10: the listener's steps."
b := PBTcpTransport withListener: (ServerSocket listenOn: 0 host: '127.0.0.1') requestTimeout: 60000.
b start: 'b' peers: (membership value: { { 'a'. 1 }. { 'b'. b port } }) key: nil handler: [:m | nil].
listener := _PBTcpListener transport: b server: FailingServer new.
c that: '(7) a failed accept is the step #failed (the next turn waits pollInterval), no connection within the timeout #idle'
  is: { listener _acceptOne. (_PBTcpListener transport: b server: (ServerSocket listenOn: 0 host: '127.0.0.1')) _acceptOne }
  equals: #(#failed #idle).

"(9) M10: the next turn after a failed accept is sent by the timer, not inside the turn."
listener := _PBTcpListener transport: b server: FailingServer new.
recorder := TurnRecorder new.
listener instVarNamed: 'proxy' put: recorder.
sync := [listener run. #deferred] on: TurnSent do: [:e | e return: #sentInsideTheTurn].
[recorder calls >= 1] whileFalse: [(Future after: 10) wait].
c that: '(9) after a failed accept the turn returns without sending the next one; the timer sends it, once'
  is: { sync. recorder calls } equals: { #deferred. 1 }.

"(8) M10: the running listener of b fails every accept from now on; b still stops."
runOf := (b instVarNamed: 'run') value.
runOf listener instVarNamed: 'server' put: FailingServer new.
stopped := b stop.
c that: '(8) a transport whose listener fails every accept stops, its listener ended'
  is: { stopped wait. settled value: runOf listener ended } equals: #(true true).

c that: 'the transports that were stopped report it'
  is: { b isRunning. t isRunning } equals: #(false false).
c report displayNl.
