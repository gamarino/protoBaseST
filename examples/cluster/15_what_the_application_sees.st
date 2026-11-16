"EXPECT: 15 what the application sees ok (8 checks)"
"Cluster lesson 15: the failures of 15_losing_members.st, seen by an application that only calls
 run:. Tutorial chapter: docs/tutorial/15-failures-and-recovery.md

 What it teaches:
 - with one voter of three down, run: commits as before;
 - with two down, a commit gets no write permission: run: ends in PBTimeoutError, 'could not
   obtain a write permission within 8000 ms', and run: never retries it. The first commit after
   the loss may instead end unknown (PBOutcomeUnknownError: the member still owned its term,
   sent the root, and could not count a majority) or, once its permission ran short, in a
   conflict that run: retries into the same timeout;
 - once a member comes back on its disk, commits go through again (after its startup grace);
 - the token each commit writes settles what the errors leave open: an acknowledged commit is
   present, a timed-out one is absent, an unknown one is present or absent, and the counter
   counts exactly the tokens present.

 Stopping a coordinator is a crash for this lesson: its endpoint stops and its disk stays. The
 lease is 3000 ms, so a commit's build and replication fit in the belief on a loaded machine, and
 acquireTimeout is 8000 ms, longer than the restarted member's startup grace (5 s). Every wait is
 a condition with a deadline; no duration is asserted.

 Run it: STPATH=<repository>/src protost 15_what_the_application_sees.st"
Import from: 'protobase'.
Import from: '../tutorial/_lesson'.

| lesson dir ids peers network make nodes spaces until db commit first second later attempt restarted tr tokens |
lesson := Lesson named: '15 what the application sees'.
dir := FileSystem temp / ('pbst-cluster-15a-' , Smalltalk pid printString).
dir deleteAll.
until := [:aBlock | | deadline |
  deadline := Time millisecondClockValue + 60000.
  [aBlock value or: [Time millisecondClockValue > deadline]] whileFalse: [(Future after: 10) wait].
  aBlock value].
ids := #('n0' 'n1' 'n2').
peers := ids collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 7400].
network := PBInProcessNetwork new.
make := [:id | PBClusterCoordinator nodeId: id peers: peers options: (Dictionary new
  at: #leaseDuration put: 3000;
  at: #requestTimeout put: 100;
  at: #acquireTimeout put: 8000;
  at: #transport put: network endpoint;
  yourself)].
nodes := ids collect: [:id | make value: id].
nodes do: [:node | node start].
spaces := nodes collect: [:node |
  PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: node].
until value: [nodes allSatisfy: [:node | (node stats at: 'rejoining') not]].
db := (spaces at: 1) newDatabase: 'shop'.
db run: [:t | t setRootObject: 'counter' value: 0. t setRootObject: 'tokens' value: PBDictionary new].

"One commit as an application makes it: the counter + 1 and its own token. Answers #committed,
 or the error run: ended in, as { class name. text }."
commit := [:aDatabase :token |
  [aDatabase run: [:t |
      t setRootObject: 'counter' value: (t getRootObject: 'counter') + 1.
      t setRootObject: 'tokens' value: ((t getRootObject: 'tokens') setAt: token value: true)].
    #committed]
    on: PBTimeoutError, PBOutcomeUnknownError, PBConflictError
    do: [:e | e return: { e class name. e messageText }]].

"All three members up."
lesson check: 'with every member up, run: commits' is: (commit value: ((spaces at: 2) openDatabase: 'shop') value: 'a') equals: #committed.

"A voter dies: n0 and n1 are still two of three."
(nodes at: 3) stop waitWithin: 60000.
lesson check: 'with one voter down, run: still commits' is: (commit value: db value: 'b') equals: #committed.

"A second voter dies: n0 is alone, one of three."
(nodes at: 2) stop waitWithin: 60000.
first := commit value: db value: 'c'.
lesson check: 'the first commit after the loss ends unknown or timed out, never committed'
  isTrue: (first ~= #committed and: [#(#PBOutcomeUnknownError #PBTimeoutError) includes: first first asSymbol]).
second := commit value: db value: 'd'.
lesson check: 'the next ends in PBTimeoutError: no write permission'
  isTrue: (second first = #PBTimeoutError and: [second last includesSubstring: 'could not obtain a write permission within 8000 ms']).
lesson say: second first , ': ' , second last.

"n1 comes back on its intact disk. Until its startup grace ends it grants nothing, so the
 application tries again, as it would after any PBTimeoutError."
(spaces at: 2) close.
restarted := make value: 'n1'.
restarted start.
spaces at: 2 put: (PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: restarted).
later := nil.
attempt := 0.
[later ~= #committed and: [attempt < 5]] whileTrue: [
  attempt := attempt + 1.
  later := commit value: db value: 'e'.
  (later ~= #committed and: [later first ~= #PBTimeoutError]) ifTrue: [attempt := 5]].
lesson check: 'with n1 back, run: commits again' is: later equals: #committed.

"The tokens settle what the errors left open."
tr := db newTransaction.
tokens := tr getRootObject: 'tokens'.
lesson check: 'every acknowledged commit is present' isTrue: (#('a' 'b' 'e') allSatisfy: [:k | tokens has: k]).
lesson check: 'the timed-out commit is absent' isTrue: (tokens has: 'd') not.
lesson check: 'the counter counts exactly the tokens present (none applied twice)'
  is: (tr getRootObject: 'counter') equals: tokens size.
lesson say: 'commit c ended in ' , first first , '; its token is present: ' , (tokens has: 'c') printString.
tr abort.

spaces do: [:space | space close].
{ nodes at: 1. restarted } do: [:node | node stop waitWithin: 60000].
dir deleteAll.
lesson finish.
