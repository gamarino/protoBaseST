"EXPECT: ok 6"
"The public reads of a cluster member (final review M2; proto_db ClusterCoordinator's healthy,
 owner, cluster_size, voters, is_voter, majority and persister.stats()). Three coordinators
 over one PBInProcessNetwork (_cluster_commit.st), plus a fourth configuration with a learner.
 (1) clusterSize, voters (sorted), isVoter and majority, as the membership states them; a learner
 is not a voter. (2) owner: once n0 commits, n0 names itself, and n1 learns n0 as the owner from
 the done n0 broadcasts. (3) isHealthy is true on a running node and equals stats at: 'healthy'.
 (4) persisterStats on a space with a coordinator answers the persister's counters (after
 sync:, roots_written >= 1 and persisted_epoch the space's persistedEpoch); a standalone space
 answers nil. (5) Once n2 is fenced, isHealthy is false, as stats says. Every wait is a condition
 with a deadline of 60 s; no duration is asserted."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_cluster_commit'.

| c base kit db peers learner st plain ps |
c := Check new.
base := FileSystem temp / ('pbst-cluster-public-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
SeamRound setUp.
kit := CommitKit ids: #('n2' 'n0' 'n1') dir: base / 'space'
  options: (Dictionary new at: #leaseDuration put: 3000; at: #driftMargin put: 2000; at: #requestTimeout put: 300; yourself).
kit openAll.

"(1)"
peers := #('a' 'b' 'c' 'd') collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 7900].
learner := PBClusterCoordinator nodeId: 'd' peers: peers options: (Dictionary new at: #voters put: #('a' 'b' 'c'); yourself).
c that: 'clusterSize, voters, isVoter and majority, as the membership states them'
  is: { (kit node: 'n0') clusterSize. (kit node: 'n0') voters. (kit node: 'n0') isVoter. (kit node: 'n0') majority.
    learner clusterSize. learner voters. learner isVoter. learner majority }
  equals: { 3. #('n0' 'n1' 'n2'). true. 2. 4. #('a' 'b' 'c'). false. 2 }.

"(2)"
db := (kit space: 'n0') newDatabase: 'db'.
db run: [:t | t setRootObject: 'counter' value: 1].
c that: 'owner: the committer names itself, and a peer learns it from the done'
  is: { (kit node: 'n0') owner. kit waitUntil: [(kit node: 'n1') owner = 'n0'] }
  equals: { 'n0'. true }.

"(3)"
c that: 'isHealthy on a running node is stats at: healthy'
  is: { (kit node: 'n0') isHealthy. ((kit node: 'n0') stats at: 'healthy') }
  equals: { true. true }.

"(4)"
(kit space: 'n0') sync: 60000.
ps := (kit space: 'n0') persisterStats.
plain := PBObjectSpace storage: (PBFileStorage path: (base / 'plain') pathString).
c that: 'persisterStats: the persister''s counters on a cluster space, nil on a standalone one'
  is: { (ps at: 'roots_written') >= 1. (ps at: 'persisted_epoch') = (kit space: 'n0') persistedEpoch.
    ps == ((kit space: 'n0') persisterStats). plain persisterStats }
  equals: { true. true. false. nil }.
plain close.

"(5)"
((kit node: 'n2') instVarNamed: 'cells') acceptor value _fault: 'planted fault for isHealthy'.
kit waitUntil: [(kit node: 'n2') isFenced].
c that: 'a fenced node is not healthy, as stats says'
  is: { (kit node: 'n2') isHealthy. ((kit node: 'n2') stats at: 'healthy') }
  equals: { false. false }.
c that: 'the fenced node still states the membership'
  is: { (kit node: 'n2') clusterSize. (kit node: 'n2') majority }
  equals: { 3. 2 }.

kit shutdown.
base deleteAll.
c report.
