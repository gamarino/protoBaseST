"EXPECT: ok 6"
"A coordinator whose start fails (final review M6; cluster/coordinator.st PBClusterCoordinator >>
 start; proto_db ClusterCoordinator.start: the transport's failure leaves the coordinator
 'stopped', its workers stopped, and the error raised). (1) An in-process endpoint that starts and
 then signals (a half-started transport): start signals that error, the endpoint is stopped
 again, and the node is not running. (2) A second start is refused naming the stopped node, not
 'was started before'; stop answers a Future that resolves; a permit asked of it is
 PBClosedError. (3) The TCP transport on a port in use (PBTcpTransport listenOn:host: refuses
 it): start signals PBValidationError, and the second start is refused as in (2). Nothing waits
 for time: every Future is settled within 60 s."
Import from: 'protobase'.
Import from: '_check'.

PBInProcessTransport subclass: #HalfStartEndpoint.

HalfStartEndpoint >> start: aNodeId peers: aMembership key: aKeyOrNil handler: aBlock
  super start: aNodeId peers: aMembership key: aKeyOrNil handler: aBlock.
  ^ PBUnexpectedError signal: 'planted: the transport failed after it started'.

| c peers node endpoint r held tcpPeers outcome |
c := Check new.
"{ #ok } when aBlock answers, else { error class name. its text }."
outcome := [:aBlock | [aBlock value. { #ok }] on: Error do: [:e | e return: { e class name. e messageText }]].

"(1)"
peers := #('n0' 'n1' 'n2') collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 7700].
endpoint := HalfStartEndpoint network: PBInProcessNetwork new.
node := PBClusterCoordinator nodeId: 'n0' peers: peers options: (Dictionary new
  at: #leaseDuration put: 600; at: #driftMargin put: 400; at: #requestTimeout put: 100; at: #transport put: endpoint; yourself).
r := outcome value: [node start].
c that: 'a failed start signals the transport''s error; the half-started endpoint is stopped; the node is not running'
  is: { r. endpoint isRunning. node isRunning }
  equals: { { #PBUnexpectedError. 'planted: the transport failed after it started' }. false. false }.

"(2)"
r := outcome value: [node start].
c that: 'a second start is refused naming the stopped node'
  is: { r first. ((r at: 2) includesSubstring: 'is stopped'). ((r at: 2) includesSubstring: 'was started before') }
  equals: { #PBUserError. true. false }.
c that: 'stop after a failed start resolves; a permit is PBClosedError'
  is: { (node stop waitWithin: 60000). [node _permit waitWithin: 60000. #permitted] on: PBClosedError do: [:e | e return: #closed] }
  equals: { true. #closed }.

"(3)"
held := PBTcpTransport listenOn: 0 host: '127.0.0.1'.
tcpPeers := { PBPeer nodeId: 'n0' host: '127.0.0.1' port: held port. PBPeer nodeId: 'n1' host: '127.0.0.1' port: held port + 1 }.
node := PBClusterCoordinator nodeId: 'n0' peers: tcpPeers options: (Dictionary new
  at: #leaseDuration put: 600; at: #driftMargin put: 400; at: #requestTimeout put: 100; yourself).
r := outcome value: [node start].
c that: 'on a port in use start signals PBValidationError and the node is not running'
  is: { r first. node isRunning }
  equals: { #PBValidationError. false }.
r := outcome value: [node start].
c that: 'and a second start is refused naming the stopped node'
  is: { r first. ((r at: 2) includesSubstring: 'is stopped') }
  equals: { #PBUserError. true }.
c that: 'the listener holding the port stops'
  is: ((held stop) waitWithin: 60000)
  equals: true.

c report.
