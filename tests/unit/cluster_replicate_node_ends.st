"EXPECT: ok 4"
"The node ends while the commit round's replicate is in flight (final review I2;
 coordinator.st _PBNodeCells >> settleAllWith:, the #roundReplicate waiter). Three coordinators
 over one PBInProcessNetwork, each node a space over its own cluster-mode storage of one shared
 directory. The peers' acks to n0 are dropped (AckHoldEndpoint), so the round's replicate leaves
 n0, n1 accepts its root, and n0's #roundReplicate waiter stays pending: no majority is ever
 counted, and the lease (600 s, a belief of 200 s) is far longer than any step of the test, so the
 permission's own end never decides it first. Then (1) n0's coordinator is stopped (an operator
 stop), or (2) n0 is fenced (an error escaping its acceptor, _PBAcceptor >> _fault:, the path a
 planted acceptor fault takes). In both cases the run: ends in PBOutcomeUnknownError with the
 coordinator's text for a node that ended mid-replication, never PBClosedError (which
 _nothingSent: would read as 'nothing was replicated'). Each case first asserts the waiter is
 pending and the root left the node (n1's accepted root holds the commit's token). Waits are
 conditions with a deadline (60 s; a Future settled within 120 s); no duration is asserted."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_cluster_commit'.

PBInProcessTransport subclass: #AckHoldEndpoint instanceVariableNames: '' classVariableNames: 'Hold'.

"The node ids whose incoming acks every endpoint drops from now on."
AckHoldEndpoint class >> hold: anArray
  Hold := Atom on: anArray.

AckHoldEndpoint >> send: aMessage to: aNodeId
  ((Hold value includes: aNodeId) and: [aMessage type = 'ack']) ifTrue: [^ self].
  ^ super send: aMessage to: aNodeId.

AckHoldEndpoint hold: #().

CommitKit subclass: #AckHoldKit.

AckHoldKit >> endpointFor: anId
  ^ AckHoldEndpoint network: self network.

| c base run ending |
c := Check new.
base := FileSystem temp / ('pbst-cluster-replicate-ends-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.

"aName's kit: a commit of n0 whose replicate left the node and waits for acks that never come;
 anEnding (a block of the kit) ends n0. Answers { the waiter was pending and the root left n0.
 the run:'s outcome. its text }."
run := [:aName :anEnding | | kit db seam w out r pending left |
  SeamRound setUp.
  AckHoldEndpoint hold: #().
  kit := AckHoldKit ids: #('n0' 'n1' 'n2') dir: base / aName
    options: (Dictionary new at: #leaseDuration put: 600000; at: #driftMargin put: 400000; at: #requestTimeout put: 300;
      at: #startupGrace put: 0; yourself).
  kit openAll.
  db := (kit space: 'n0') newDatabase: 'db'.
  db run: [:t | t setRootObject: 'counter' value: 0. t setRootObject: 'tokens' value: PBDictionary new].
  seam := SeamRound resetSeamOf: 'n0'.
  AckHoldEndpoint hold: #('n0').
  w := Worker new asActor.
  out := w once: db block: (CommitKit incr: aName tag: aName) retries: 0.
  left := kit waitUntil: [| a | a := (kit node: 'n1') acceptorState accepted.
    (seam calls: #('replicate')) notEmpty and: [(a notNil and: [a record notNil])
      and: [(kit root: 'tokens' of: 'db' in: ((kit space: 'n1') _spaceRootAt: a record)) has: aName]]].
  pending := ((((kit node: 'n0') instVarNamed: 'cells') waiters value) values collect: [:x | x first]) includes: #roundReplicate.
  anEnding value: kit.
  r := kit settle: out.
  AckHoldEndpoint hold: #().
  kit shutdown.
  { left & pending & (seam calls: #('answered PBClosedError' 'answered PBUnexpectedError')) isEmpty. r first. r at: 2.
    (r at: 3) ifNil: [''] }].

"(1)"
ending := run value: 'stopped' value: [:kit | ((kit node: 'n0') stop) waitWithin: 60000].
c that: 'stopped mid-replication: the waiter was pending, the root left the node, and run: ends in PBOutcomeUnknownError'
  is: (ending first: 3)
  equals: { true. #error. #PBOutcomeUnknownError }.
c that: 'stopped mid-replication: the text names the node ending and the stop'
  is: { ((ending at: 4) includesSubstring: 'the node ended while the root was being replicated').
    ((ending at: 4) includesSubstring: 'is stopped'). ((ending at: 4) includesSubstring: 'may or may not take effect') }
  equals: { true. true. true }.

"(2)"
ending := run value: 'fenced' value: [:kit |
  ((kit node: 'n0') instVarNamed: 'cells') acceptor value _fault: 'planted fault in the acceptor shell'.
  kit waitUntil: [(kit node: 'n0') isFenced]].
c that: 'fenced mid-replication: the waiter was pending, the root left the node, and run: ends in PBOutcomeUnknownError'
  is: (ending first: 3)
  equals: { true. #error. #PBOutcomeUnknownError }.
c that: 'fenced mid-replication: the text names the node ending and the fence'
  is: { ((ending at: 4) includesSubstring: 'the node ended while the root was being replicated').
    ((ending at: 4) includesSubstring: 'planted fault in the acceptor shell') }
  equals: { true. true }.

base deleteAll.
c report.
