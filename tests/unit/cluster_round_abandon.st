"EXPECT: ok 2"
"The commit round's last resort keeps nothing of the commits it settles (final review M4;
 cluster/round.st PBClusterRound >> _abandon:). Three coordinators over one PBInProcessNetwork
 (_cluster_commit.st). A seam of n0's round withholds the replicate's answer, so the commit is
 built (its build time noted in the round's builds, keyed by its PBCommitEntry, which holds the
 transaction) and its root has left the node. An error planted in a block the round runs on its
 runner (_later:) takes the last resort: (1) the run: ends in PBOutcomeUnknownError (its root
 may have left); (2) the round's builds and sentAt are empty afterwards, so the abandoned entry
 and its transaction are not kept for the life of the space. Every wait is a condition with a
 deadline of 60 s; no duration is asserted."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_cluster_commit'.

| c base kit db seam w out r round |
c := Check new.
base := FileSystem temp / ('pbst-cluster-abandon-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
SeamRound setUp.
kit := CommitKit ids: #('n0' 'n1' 'n2') dir: base
  options: (Dictionary new at: #leaseDuration put: 3000; at: #driftMargin put: 2000; at: #requestTimeout put: 300; yourself).
kit openAll.
db := (kit space: 'n0') newDatabase: 'db'.
db run: [:t | t setRootObject: 'counter' value: 0. t setRootObject: 'tokens' value: PBDictionary new].

seam := SeamRound resetSeamOf: 'n0'.
seam holdAnswer swap: [:x | true].
w := Worker new asActor.
out := w once: db block: (CommitKit incr: 'abandoned' tag: 'abandon') retries: 0.
kit waitUntil: [(seam calls: #('answer held')) notEmpty].
round := SeamRound roundOf: 'n0'.
round _later: [Error signal: 'planted failure of the round'].
r := kit settle: out.
c that: 'the last resort settles the built commit as unknown'
  is: { r first. r at: 2. ((r at: 3) includesSubstring: 'planted failure of the round') }
  equals: { #error. #PBOutcomeUnknownError. true }.
c that: 'the last resort keeps no build of the commits it settled, and no send time'
  is: { (round instVarNamed: 'builds') value isEmpty. (round instVarNamed: 'sentAt') value }
  equals: { true. nil }.

kit shutdown.
base deleteAll.
c report.
