"EXPECT: 14 three nodes over TCP ok (5 checks)"
"Cluster lesson 14, second half: the same three coordinators, now talking over TCP on localhost.
 Tutorial chapter: docs/tutorial/14-a-three-node-cluster.md

 What it teaches:
 - without the #transport option a coordinator listens on its PBPeer's host and port with a
   PBTcpTransport; here each transport is made first, on port 0, so that the operating system
   picks free ports and the peer list can name them (a deployment writes fixed ports instead);
 - nothing else changes: the same directory, the same attach, the same permissions;
 - the transports count their frames (frames_sent, frames_rejected).

 Every wait is a condition with a deadline of 60 s; no duration is asserted.

 Run it: STPATH=<repository>/src protost 14_three_nodes_tcp.st"
Import from: 'protobase'.
Import from: '../tutorial/_lesson'.

| lesson dir ids transports peers nodes spaces until permit sent |
lesson := Lesson named: '14 three nodes over TCP'.
dir := FileSystem temp / ('pbst-cluster-14tcp-' , Smalltalk pid printString).
dir deleteAll.
until := [:aBlock | | deadline |
  deadline := Time millisecondClockValue + 60000.
  [aBlock value or: [Time millisecondClockValue > deadline]] whileFalse: [(Future after: 10) wait].
  aBlock value].

"One listening transport per member, on a port the system picks."
ids := #('n0' 'n1' 'n2').
transports := ids collect: [:id | PBTcpTransport withListener: (ServerSocket listenOn: 0 host: '127.0.0.1')].
peers := (1 to: 3) collect: [:i | PBPeer nodeId: (ids at: i) host: '127.0.0.1' port: (transports at: i) port].
lesson say: 'ports ' , (peers collect: [:p | p port]) printString.

nodes := (1 to: 3) collect: [:i |
  PBClusterCoordinator nodeId: (ids at: i) peers: peers options: (Dictionary new
    at: #leaseDuration put: 600;
    at: #requestTimeout put: 100;
    at: #transport put: (transports at: i);
    yourself)].
nodes do: [:node | node start].
spaces := nodes collect: [:node |
  PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: node].
lesson check: 'every node finishes joining over TCP'
  isTrue: (until value: [nodes allSatisfy: [:node | (node stats at: 'rejoining') not]]).
lesson check: 'every node is healthy' isTrue: (nodes allSatisfy: [:node | node stats at: 'healthy']).

permit := (nodes at: 2) _permit waitWithin: 60000.
lesson say: 'n1 holds a permission of term ' , permit term printString , ' from ' , permit owner.
lesson check: 'a permission is issued over TCP' is: permit term \\ 4096 equals: (ids indexOf: permit owner) - 1.
((nodes at: 2) _done: permit outcome: #none) waitWithin: 60000.

sent := transports inject: 0 into: [:sum :t | sum + (t stats at: 'frames_sent')].
lesson check: 'frames travelled' isTrue: sent > 0.
lesson check: 'no frame was rejected'
  is: (transports inject: 0 into: [:sum :t | sum + (t stats at: 'frames_rejected')]) equals: 0.

spaces do: [:space | space close].
nodes do: [:node | node stop waitWithin: 60000].
dir deleteAll.
lesson finish.
