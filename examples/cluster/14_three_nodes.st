"EXPECT: 14 three nodes ok (9 checks)"
"Cluster lesson 14: three coordinators in one process, one shared directory.
 Tutorial chapter: docs/tutorial/14-a-three-node-cluster.md

 What it teaches:
 - a cluster member is a PBClusterCoordinator: its node id, the list of every member (PBPeer)
   and its options (durations in milliseconds);
 - PBInProcessNetwork carries the messages of members that live in one process;
 - every member opens the same directory with PBFileStorage clusterPath:, and
   PBObjectSpace storage:coordinator: attaches the member's acceptor log,
   cluster/<node id>.roots, to its coordinator;
 - a brand-new cluster forms by itself: each member's empty log is answered 'new' by the
   others and gets its rejoined marker; stats reports it healthy and no longer rejoining;
 - a write permission comes from the owner of a term, and the low 12 bits of the term are the
   owner's rank.

 It never asserts a duration: a wait is a condition polled with a deadline of 60 s, which only
 turns a hang into a failure.

 Run it: STPATH=<repository>/src protost 14_three_nodes.st"
Import from: 'protobase'.
Import from: '../tutorial/_lesson'.

| lesson dir ids peers network options nodes spaces until stats permit owners done |
lesson := Lesson named: '14 three nodes'.
dir := FileSystem temp / ('pbst-cluster-14-' , Smalltalk pid printString).
dir deleteAll.

"Three members. In one process the host and port are not used, but every member is named."
ids := #('n0' 'n1' 'n2').
peers := ids collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 7400].
network := PBInProcessNetwork new.

"Short timers, so the lesson runs quickly: they decide liveness only, never safety."
options := [:id | Dictionary new
  at: #leaseDuration put: 600;
  at: #requestTimeout put: 100;
  at: #transport put: network endpoint;
  yourself].

nodes := ids collect: [:id | PBClusterCoordinator nodeId: id peers: peers options: (options value: id)].
nodes do: [:node | node start].
lesson check: 'every coordinator runs' isTrue: (nodes allSatisfy: [:node | node isRunning]).

"Every member opens the same directory; each attaches its own acceptor log."
spaces := nodes collect: [:node |
  PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: node].
lesson check: 'each node has its acceptor log in cluster/'
  isTrue: (ids allSatisfy: [:id | (dir / 'cluster' / (id , '.roots')) exists]).
lesson check: 'the space is empty' is: spaces first listDatabases equals: #().

"A new cluster forms by itself: each empty log is completed as a first start."
"Waiting is a condition polled every 10 ms, for at most 60 s; never a fixed sleep."
until := [:aBlock | | deadline |
  deadline := Time millisecondClockValue + 60000.
  [aBlock value or: [Time millisecondClockValue > deadline]] whileFalse: [(Future after: 10) wait].
  aBlock value].
lesson check: 'every node finishes joining'
  isTrue: (until value: [nodes allSatisfy: [:node | (node stats at: 'rejoining') not]]).
stats := nodes collect: [:node | node stats].
lesson check: 'every node is healthy' isTrue: (stats allSatisfy: [:s | (s at: 'healthy') and: [(s at: 'fenced') not]]).
lesson check: 'no rejoin needed a ballot' isTrue: (stats allSatisfy: [:s | (s at: 'rejoin_ballots') = 0]).

"A write permission. The commit path asks for it (Task 23); here we ask by hand, to watch."
permit := nodes first _permit waitWithin: 60000.
lesson say: 'term ' , permit term printString , ', owner ' , permit owner.
lesson check: 'the low 12 bits of the term are the owner''s rank'
  is: permit term \\ 4096 equals: (ids indexOf: permit owner) - 1.
lesson check: 'the owner issued it'
  isTrue: ((nodes detect: [:node | node nodeId = permit owner]) stats at: 'permits_issued') >= 1.
"Nothing was sent under it: the permission ends #none, and the owner may issue the next."
done := (nodes first _done: permit outcome: #none) waitWithin: 60000.
lesson check: 'the permission is ended' is: done equals: true.

spaces do: [:space | space close].
nodes do: [:node | node stop waitWithin: 60000].
dir deleteAll.
lesson finish.
