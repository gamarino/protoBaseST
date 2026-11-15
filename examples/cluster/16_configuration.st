"EXPECT: 16 configuration ok (12 checks)"
"Cluster lesson 16: the options, the rules among them, the timer table and the stats.
 Tutorial chapter: docs/tutorial/16-operating-a-cluster.md

 What it teaches:
 - the defaults derived from leaseDuration: driftMargin, sendReserve, startupGrace;
 - the rules that refuse a configuration at construction (sendReserve, authKey, unknown names);
 - PBClusterConfig timerTable, one row per timer;
 - stats: the health keys and the counters, with proto_db's names;
 - a member restarted over a log that served before needs its full startup grace: a shorter one
   is refused when the space attaches (L17).

 Every wait is a condition with a deadline of 60 s; no duration is asserted.

 Run it: STPATH=<repository>/src protost 16_configuration.st"
Import from: 'protobase'.
Import from: '../tutorial/_lesson'.

| lesson peers config refuse dir network make nodes spaces until stats restarted |
lesson := Lesson named: '16 configuration'.
peers := #('n0' 'n1' 'n2') collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 7400].
refuse := [:options | PBClusterConfig nodeId: 'n0' peers: peers options: options].

"The defaults (accessors answer microseconds): proto_db's, a 2 s lease."
config := PBClusterConfig nodeId: 'n0' peers: peers options: Dictionary new.
lesson check: 'leaseDuration, requestTimeout, acquireTimeout by default'
  is: { config leaseDuration. config requestTimeout. config acquireTimeout } equals: #(2000000 250000 30000000).

"A short lease for tests: what is derived from it."
config := PBClusterConfig nodeId: 'n0' peers: peers options: (Dictionary new
  at: #leaseDuration put: 600; at: #requestTimeout put: 100; yourself).
lesson check: 'margin, belief, sendReserve, startupGrace'
  is: { config driftMargin. config belief. config sendReserve. config startupGrace }
  equals: #(400000 200000 50000 1000000).

"Refused at construction."
lesson check: 'a 600 ms lease with the default 250 ms request timeout' signals: PBValidationError containing: 'belief'
  during: [refuse value: (Dictionary new at: #leaseDuration put: 600; yourself)].
lesson check: 'a send reserve above a quarter of the belief' signals: PBValidationError containing: 'sendReserve'
  during: [refuse value: (Dictionary new at: #leaseDuration put: 600; at: #requestTimeout put: 100; at: #sendReserve put: 60; yourself)].
lesson check: 'an authentication key shorter than 32 bytes' signals: PBValidationError containing: 'authKey'
  during: [refuse value: (Dictionary new at: #authKey put: (ByteArray new: 16); yourself)].
lesson check: 'an option nobody knows' signals: PBValidationError containing: 'Unknown cluster option'
  during: [refuse value: (Dictionary new at: #leaseDurationMs put: 600; yourself)].

"The timer table: name, default, what it drives."
lesson check: 'one row per timer, the lease first'
  is: { PBClusterConfig timerTable size. PBClusterConfig timerTable first first } equals: #(19 'leaseDuration').

"A running cluster, to read its stats."
dir := FileSystem temp / ('pbst-cluster-16-' , Smalltalk pid printString).
dir deleteAll.
until := [:aBlock | | deadline |
  deadline := Time millisecondClockValue + 60000.
  [aBlock value or: [Time millisecondClockValue > deadline]] whileFalse: [(Future after: 10) wait].
  aBlock value].
network := PBInProcessNetwork new.
make := [:id :extra | | o |
  o := Dictionary new at: #leaseDuration put: 600; at: #requestTimeout put: 100;
    at: #transport put: network endpoint; yourself.
  extra keysAndValuesDo: [:k :v | o at: k put: v].
  PBClusterCoordinator nodeId: id peers: peers options: o].
nodes := #('n0' 'n1' 'n2') collect: [:id | make value: id value: Dictionary new].
nodes do: [:node | node start].
spaces := nodes collect: [:node |
  PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: node].
until value: [nodes allSatisfy: [:node | (node stats at: 'rejoining') not]].
stats := nodes first stats.
lesson check: 'the health keys'
  is: (#('healthy' 'fenced' 'tier_failed' 'rejoining' 'rejoin_blocked' 'failure') collect: [:k | stats at: k])
  equals: { true. false. false. false. nil. nil }.
lesson check: 'the counters start at zero or count what happened'
  isTrue: (#('grants_given' 'permits_issued' 'rejoins' 'terms_abandoned') allSatisfy: [:k | (stats at: k) >= 0]).

"n2 restarts with a startup grace of 0 over its log, which served before: refused (L17)."
(nodes at: 3) stop waitWithin: 60000.
(spaces at: 3) close.
restarted := make value: 'n2' value: (Dictionary new at: #startupGrace put: 0; yourself).
restarted start.
lesson check: 'a short startup grace over a log that served is refused' signals: PBValidationError containing: 'startupGrace'
  during: [PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: restarted].
restarted stop waitWithin: 60000.
restarted := make value: 'n2' value: Dictionary new.
restarted start.
spaces at: 3 put: (PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: restarted).
lesson check: 'with the default grace it attaches' isTrue: (spaces at: 3) coordinator == restarted.
lesson check: 'and serves' isTrue: (until value: [(restarted stats at: 'rejoining') not]).

spaces do: [:space | space close].
{ nodes at: 1. nodes at: 2. restarted } do: [:node | node stop waitWithin: 60000].
dir deleteAll.
lesson finish.
