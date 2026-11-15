"EXPECT: 15 losing members ok (6 checks)"
"Cluster lesson 15: a voter dies, then the owner dies, then the owner comes back.
 Tutorial chapter: docs/tutorial/15-failures-and-recovery.md

 What it teaches:
 - a cluster of three voters keeps issuing write permissions with one voter down: two of three
   is a majority;
 - with two of three down nothing is issued: the survivor's request ends in PBTimeoutError at
   its acquireTimeout. A minority never writes;
 - a member restarted on its intact disk (a new incarnation, its acceptor log restored) is a
   voter again at once, grants again once its startup grace has passed, and the cluster issues
   permissions again,
   under a higher term: a term is never reused.

 Stopping a coordinator is a crash for this lesson: its endpoint stops, so it neither sends nor
 receives. The disk stays. Every wait is a condition with a deadline; no duration is asserted.

 Run it: STPATH=<repository>/src protost 15_losing_members.st"
Import from: 'protobase'.
Import from: '../tutorial/_lesson'.

| lesson dir ids peers network options make nodes spaces until first second attempt outcome restarted third |
lesson := Lesson named: '15 losing members'.
dir := FileSystem temp / ('pbst-cluster-15-' , Smalltalk pid printString).
dir deleteAll.
until := [:aBlock | | deadline |
  deadline := Time millisecondClockValue + 60000.
  [aBlock value or: [Time millisecondClockValue > deadline]] whileFalse: [(Future after: 10) wait].
  aBlock value].
ids := #('n0' 'n1' 'n2').
peers := ids collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 7400].
network := PBInProcessNetwork new.
"acquireTimeout is short so that the minority's request ends quickly; it is liveness only."
options := [Dictionary new
  at: #leaseDuration put: 600;
  at: #requestTimeout put: 100;
  at: #acquireTimeout put: 2000;
  at: #transport put: network endpoint;
  yourself].
make := [:id | PBClusterCoordinator nodeId: id peers: peers options: options value].
nodes := ids collect: [:id | make value: id].
nodes do: [:node | node start].
spaces := nodes collect: [:node |
  PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: node].
until value: [nodes allSatisfy: [:node | (node stats at: 'rejoining') not]].

"n0 asks first, so n0 owns the first term."
first := (nodes at: 1) _permit waitWithin: 60000.
((nodes at: 1) _done: first outcome: #none) waitWithin: 60000.
lesson check: 'n0 owns the first term' is: first owner equals: 'n0'.

"A voter dies. n0 and n1 are still two of three voters."
(nodes at: 3) stop waitWithin: 60000.
second := (nodes at: 2) _permit waitWithin: 60000.
((nodes at: 2) _done: second outcome: #none) waitWithin: 60000.
lesson check: 'with one voter down a permission is still issued' isTrue: second term >= first term.

"The owner dies too. n1 is alone: one of three is no majority."
(nodes at: 1) stop waitWithin: 60000.
outcome := [(nodes at: 2) _permit waitWithin: 60000. #granted]
  on: PBTimeoutError do: [:e | e return: #timeout].
lesson check: 'a minority gets no permission: PBTimeoutError' is: outcome equals: #timeout.

"n0 restarts on its intact disk: a new coordinator, a new space over the same directory."
(spaces at: 1) close.
restarted := make value: 'n0'.
restarted start.
spaces at: 1 put: (PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: restarted).
lesson check: 'its acceptor log is restored, no rejoin needed'
  isTrue: (until value: [(restarted stats at: 'rejoining') not]).
lesson check: 'its restored log needs no rejoin ballot' is: (restarted stats at: 'rejoin_ballots') equals: 0.

"Until n0's startup grace ends it refuses grants; n1 asks until a permission comes."
third := nil.
attempt := 0.
[third isNil and: [attempt < 20]] whileTrue: [
  attempt := attempt + 1.
  third := [(nodes at: 2) _permit waitWithin: 60000] on: PBTimeoutError do: [:e | e return: nil]].
lesson check: 'n0 and n1 issue permissions again, under a higher term'
  isTrue: (third notNil and: [third term > second term]).
lesson say: 'terms: ' , { first term. second term. third term } printString.
((nodes at: 2) _done: third outcome: #none) waitWithin: 60000.

spaces do: [:space | space close].
{ restarted. nodes at: 2 } do: [:node | node stop waitWithin: 60000].
dir deleteAll.
lesson finish.
