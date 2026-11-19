"EXPECT: ok 5"
"A space closed while one of its commits is in flight (cluster plan Task 23, Review Focus 1;
 cluster/round.st PBClusterRound >> close, holder.st PBRoundClosed). Three coordinators over one
 PBInProcessNetwork, each node a space over its own cluster-mode storage of one shared directory;
 a seam of n0's round (_cluster_commit.st) withholds one step for ever, the test closes n0's space
 and the commit's run: ends: (1) the base withheld (nothing built): PBClosedError; (2) the root
 built, its send withheld (nothing left the node): PBClosedError; (3) the replicate left the node,
 its answer withheld: PBOutcomeUnknownError (durability::test_a_commit_racing_the_close_of_the_
 space_has_an_unknown_outcome). Nothing hangs: each run: settles within 120 s. Between cases n0's
 space is opened again. (4) A commit through a closed space is PBClosedError and replicates
 nothing, also once the node's space was opened again (acceptor_writes::test_a_commit_whose_space_
 was_reopened_replicates_nothing). (5) After every space is closed and every node restarted (new
 coordinators over the same acceptor logs) and one commit made, the commit of unknown outcome is
 in every node's committed root or in none."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_cluster_commit'.

| c base kit db seam w out r closing replications where last before |
c := Check new.
base := FileSystem temp / ('pbst-cluster-close-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
SeamRound setUp.
kit := CommitKit ids: #('n0' 'n1' 'n2') dir: base
  options: (Dictionary new at: #leaseDuration put: 3000; at: #driftMargin put: 2000; at: #requestTimeout put: 300; yourself).
kit openAll.
db := (kit space: 'n0') newDatabase: 'db'.
db run: [:t | t setRootObject: 'counter' value: 0. t setRootObject: 'tokens' value: PBDictionary new].

"aSetUp (on n0's fresh seam) withholds a step; the commit of aToken waits at aNote; n0's space is
 closed: { the run:'s outcome. the close's }. n0's space is opened again."
closing := [:aToken :aSetUp :aNote | | s result closed |
  s := SeamRound resetSeamOf: 'n0'.
  aSetUp value: s.
  w := Worker new asActor.
  out := w once: (kit db: 'db' on: 'n0') block: (CommitKit incr: aToken tag: 'close') retries: 0.
  kit waitUntil: [(s calls: { aNote }) notEmpty].
  closed := kit settle: (Worker new asActor close: (kit space: 'n0')).
  result := kit settle: out.
  kit open: 'n0'.
  last := result.
  { result first. result at: 2. closed }].

"(1)"
c that: 'closed before the build: PBClosedError'
  is: (closing value: 'before-build' value: [:s | s holdBase swap: [:x | true]] value: 'base held')
  equals: { #error. #PBClosedError. true }.

"(2)"
c that: 'closed after the build, before the send: PBClosedError'
  is: (closing value: 'after-build' value: [:s | s holdSend swap: [:x | true]] value: 'send held')
  equals: { #error. #PBClosedError. true }.

"(3) also, as rc4's racing-close test: the text says it may or may not take effect, n1 accepted
 the root (its acceptor's accepted root holds the token), and n0 is not wedged by the early
 #unknown done: its replication was counted and it is healthy, not fenced."
before := (kit node: 'n0') stats at: 'replications'.
r := closing value: 'left' value: [:s | s holdAnswer swap: [:x | true]] value: 'answer held'.
c that: 'closed once the replicate left: PBOutcomeUnknownError'
  is: { r. ((last at: 3) includesSubstring: 'may or may not take effect').
    kit waitUntil: [| a | a := (kit node: 'n1') acceptorState accepted.
      (a notNil and: [a record notNil]) and: [(kit root: 'tokens' of: 'db' in: ((kit space: 'n1') _spaceRootAt: a record)) has: 'left']].
    kit waitUntil: [((kit node: 'n0') stats at: 'replications') > before].
    (kit node: 'n0') isFenced. (kit node: 'n0') stats at: 'healthy' }
  equals: { { #error. #PBOutcomeUnknownError. true }. true. true. true. false. true }.

"(4)"
replications := (kit node: 'n0') stats at: 'replications'.
(kit space: 'n0') close.
r := kit settle: (Worker new asActor once: db block: (CommitKit incr: 'closed' tag: 'closed') retries: 0).
kit open: 'n0'.
c that: 'a commit through a closed space, also once the node''s space was opened again, is PBClosedError and replicates nothing'
  is: { r first. r at: 2. (kit settle: (Worker new asActor once: db block: (CommitKit incr: 'closed-2' tag: 'closed') retries: 0)) at: 2.
    ((kit node: 'n0') stats at: 'replications') - replications }
  equals: { #error. #PBClosedError. #PBClosedError. 0 }.

"(5)"
kit shutdown.
SeamRound setUp.
kit start.
kit openAll.
(Worker new asActor once: (kit db: 'db' on: 'n1') block: (CommitKit incr: 'after-restart' tag: 'restart') retries: 30) wait.
kit waitUntil: [kit ids allSatisfy: [:id | | root |
  root := kit committedSpaceRoot: id.
  root notNil and: [(kit root: 'tokens' of: 'db' in: root) has: 'after-restart']]].
"#all, #none or #some: where the token is among the nodes' committed roots."
where := [:token | | present |
  present := kit ids collect: [:id | (kit root: 'tokens' of: 'db' in: (kit committedSpaceRoot: id)) has: token].
  (present allSatisfy: [:p | p]) ifTrue: [#all] ifFalse: [(present noneSatisfy: [:p | p]) ifTrue: [#none] ifFalse: [#some]]].
c that: 'after a restart, the commit of unknown outcome is in every node''s committed root or in none; the closed ones in none'
  is: { #(#all #none) includes: (where value: 'left'). where value: 'before-build'. where value: 'after-build'. where value: 'closed' }
  equals: { true. #none. #none. #none }.

kit shutdown.
base deleteAll.
c report.
