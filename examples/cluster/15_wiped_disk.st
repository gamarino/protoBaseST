"EXPECT: 15 wiped disk ok (7 checks)"
"Cluster lesson 15, second program: a member loses its acceptor log and rejoins by a ballot.
 Tutorial chapter: docs/tutorial/15-failures-and-recovery.md

 What it teaches:
 - a member whose log is gone (here: moved aside, as a wiped disk would leave it) restarts
   rejoining: it grants nothing and acknowledges nothing until it has rejoined;
 - since the others report a term they promised, the rejoin is not a first start: it runs a
   ballot round (stats rejoin_ballots), whose promises shut out every older term whatever the
   clocks say, then logs the promise, the accepted root and the rejoined marker;
 - the rejoined member serves again: the cluster issues permissions with it;
 - a second space for a member that is already attached is refused at the lock of its log,
   cluster/<id>.roots.lock (a double start).

 Every wait is a condition with a deadline of 60 s; no duration is asserted.

 Run it: STPATH=<repository>/src protost 15_wiped_disk.st"
Import from: 'protobase'.
Import from: '../tutorial/_lesson'.

| lesson dir ids peers network make nodes spaces until permit log fresh stats ballot later second |
lesson := Lesson named: '15 wiped disk'.
dir := FileSystem temp / ('pbst-cluster-15w-' , Smalltalk pid printString).
dir deleteAll.
until := [:aBlock | | deadline |
  deadline := Time millisecondClockValue + 60000.
  [aBlock value or: [Time millisecondClockValue > deadline]] whileFalse: [(Future after: 10) wait].
  aBlock value].
ids := #('n0' 'n1' 'n2').
peers := ids collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 7400].
network := PBInProcessNetwork new.
make := [:id | PBClusterCoordinator nodeId: id peers: peers options: (Dictionary new
  at: #leaseDuration put: 600;
  at: #requestTimeout put: 100;
  at: #transport put: network endpoint;
  yourself)].
nodes := ids collect: [:id | make value: id].
nodes do: [:node | node start].
spaces := nodes collect: [:node |
  PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: node].
until value: [nodes allSatisfy: [:node | (node stats at: 'rejoining') not]].

"A term is promised and served, so the voters' logs now hold a promise."
permit := (nodes at: 1) _permit waitWithin: 60000.
((nodes at: 1) _done: permit outcome: #none) waitWithin: 60000.

"A second space for n0 while n0 is attached: refused at its log's lock."
second := PBFileStorage clusterPath: dir pathString.
lesson check: 'a double start is refused at the log''s lock'
  signals: PBUserError containing: 'cluster/n0.roots.lock'
  during: [PBObjectSpace storage: second coordinator: (nodes at: 1)].
second close.

"n2 crashes, and its acceptor log is lost."
(nodes at: 3) stop waitWithin: 60000.
(spaces at: 3) close.
log := dir / 'cluster' / 'n2.roots'.
log renameTo: 'n2.roots.lost'.
lesson check: 'n2''s log is gone' isTrue: log exists not.

"n2 restarts over an empty log."
fresh := make value: 'n2'.
fresh start.
spaces at: 3 put: (PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: fresh).
lesson check: 'n2 rejoins' isTrue: (until value: [(fresh stats at: 'rejoins') >= 1]).
stats := fresh stats.
lesson check: 'the rejoin was a ballot, not a first start' isTrue: (stats at: 'rejoin_ballots') >= 1.
ballot := fresh acceptorState rejoinBallot.
lesson say: 'rejoin ballot ' , ballot printString , ' (rank ' , (ballot \\ 4096) printString , '), above term '
  , permit term printString.
lesson check: 'the ballot is above every term the others reported' isTrue: ballot > permit term.
lesson check: 'n2 is healthy and no longer rejoining'
  isTrue: ((stats at: 'healthy') and: [(stats at: 'rejoining') not]).

"The cluster issues permissions with n2 again."
later := fresh _permit waitWithin: 60000.
(fresh _done: later outcome: #none) waitWithin: 60000.
lesson check: 'a permission after the rejoin' isTrue: later term > permit term.

spaces do: [:space | space close].
{ nodes at: 1. nodes at: 2. fresh } do: [:node | node stop waitWithin: 60000].
dir deleteAll.
lesson finish.
