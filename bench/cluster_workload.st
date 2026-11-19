"cluster_workload.st: committed transactions per second of protoBaseST in cluster mode, one
 process per member, and the same workload in standalone mode for comparison. run_cluster.sh
 drives it; it is not a test.

  cluster_workload.st standalone <out> <space> <profile>
  cluster_workload.st node <id> <out> <space> <profile> <nodes>

 Profiles (TOTAL transactions in all, split evenly over the members; CLUSTER_SCALE multiplies
 TOTAL, default 120):
   tiny      one writer per process; member j (0-based, in id order) commits TOTAL / nodes
             transactions, each reading its own root Dictionary 'kv-<j>', setting one new key k
             (k = j * each + i, value k \\ 1000) and writing it back. No two transactions of the
             cluster conflict (disjoint roots), but every one needs a write permission.
   conc-hot  four writers per process (actors), every writer of every member incrementing key 0
             of the shared root 'hot' (read-modify-write: conflicts, retried by run:retries: 1000).
   m3-idx0, m3-idx1, m3-idx3
             the query workload M3 (bench/query_workload.st, plan Task 4b): the root 'people' is
             M1's dictionary of 600 records with the plan's indexes (bench/_query_bench.st); one
             writer per process; member j commits changes j * each to j * each + each - 1 (TOTAL
             at most 600), each a blind write: a new dictionary holding the change alone, never
             reading the root, merged by the commit onto the current version, which maintains its
             indexes; a retryable conflict (a permission refused for its send reserve, a commit
             of another member first) is retried by run:retries: 1000, counted as attempts. The keys are distinct, so the final content does not depend on the order of
             the commits. The verifier validates 'people', counts the records the changes wrote
             (id >= 600) and computes M1's checksum (QueryBench checksumOf:); the expected
             checksum is proto_db's for the same commits, which the caller passes in
             CLUSTER_M3_EXPECTED as '<rows>:<commits>:<checksum>' (bench/run_query.sh M3 does): a run
             without it fails; the verifier's checksum is then that same triple.
 A standalone run is one process with the TOTAL of the profile and the writers of one member.

 A node binds a PBTcpTransport on 127.0.0.1 (port 0), writes <out>/<id>.port, waits for
 <out>/peers ('<id> <port>' per member), starts its coordinator with proto_db's default options
 (a 2000 ms lease, a 250 ms request timeout), opens the shared space (PBFileStorage clusterPath:)
 and waits until it has joined. n0 creates the database 'bench' and its roots, then writes
 <out>/created; every other member waits for it and passes a barrier (newDatabase:) so that it
 knows 'bench'. Each writes <out>/<id>.ready, waits for <out>/go, and runs its transactions: that
 is the only timed part. It then writes <out>/<id>.result, one line of 'key=value' pairs:
   commits      the transactions it committed, counted: one per run: that returned normally
                (never the number it was asked to make)
   attempts     the block runs (attempts - commits = retries)
   t0, t1       Time utcMicroseconds at the start and at the end of its transactions (one clock
                for every process of the machine)
   save_us, saves
                the root-independent work of design spec 7.2: the microseconds the space's
                cluster round spent saving the atoms of each commit it was handed, before it
                asked for a permission, and the number of commits it timed (BenchRound below)
   build_us, replication_us, critical
                the deltas over the timed part of the coordinator's stats 'critical' ('build':
                validation, merge, path copy and the new root; 'replication': from the send of
                the replicate to the commit settled) and 'critical_commits'
   reserve_refusals, permits
                the deltas of 'sends_refused_reserve' and 'permit_requests_sent'
   rss_kb       the process's peak resident set so far (VmHWM of /proc/self/status), read after
                its transactions
 n0 then waits for <out>/verify, commits a read barrier (a root '_read_barrier' of 'bench',
 which no profile counts), reads the space through the cluster and writes <out>/verify.result:
 'count=<transactions found> checksum=<...> expected=<...>'; a checksum other than the expected
 one is a failure. The runner compares count with the sum of every member's commits. Every
 member then waits for <out>/stop, closes its space, stops its coordinator and exits 0.

 A standalone run (PBFileStorage path:, no coordinator) writes the same <out>/s.result (no
 save, build or replication figures) and verifies on a new space over the directory after
 closing it, as bench/tx_workload.st does.

 Failures: a PBOutcomeUnknownError, a PBConflictError or PBTimeoutError that escapes run:'s
 retries, or any other error writes <out>/<id>.error and exits 1: the runner refuses the run.
 Every wait on a file is bounded (300 s); no duration is asserted."
Import from: 'protobase'.
Import from: '_query_bench'.

"The split of the root-independent work: PBClusterRound >> enqueue: saves the atoms of the
 commit, then hands the core PBRoundEnqueued (cluster/round.st); the time between the two is the
 save. The round runs on the space's runner actor, one message at a time."
Object subclass: #BenchSplit instanceVariableNames: '' classVariableNames: 'Micros Count'.

BenchSplit class >> reset
  Micros := Atom on: 0.
  Count := Atom on: 0.

BenchSplit class >> add: anInteger
  Micros swap: [:old | old + anInteger].
  Count swap: [:old | old + 1].

BenchSplit class >> micros
  ^ Micros value.

BenchSplit class >> count
  ^ Count value.

BenchSplit reset.

PBClusterRound subclass: #BenchRound instanceVariableNames: 'enqueuedAt'.

BenchRound >> enqueue: anEntry
  enqueuedAt := Time microsecondClockValue.
  ^ super enqueue: anEntry.

BenchRound >> _handle: anEvent
  ((anEvent isKindOf: PBRoundEnqueued) and: [enqueuedAt notNil]) ifTrue: [
    BenchSplit add: Time microsecondClockValue - enqueuedAt.
    enqueuedAt := nil].
  ^ super _handle: anEvent.

PBObjectSpace subclass: #BenchSpace instanceVariableNames: ''.

BenchSpace >> _newClusterRound: aPublisher proxy: aCell
  ^ BenchRound space: self publisher: aPublisher proxy: aCell.

"One writer, driven as an actor: answers { block runs. commits }, a commit counted when run:
 returns normally."
Object subclass: #BenchWriter instanceVariableNames: 'attempts commits'.

BenchWriter >> hot: each db: aDb
  attempts := 0.
  commits := 0.
  each timesRepeat: [
    aDb run: [:tr | | d |
      attempts := attempts + 1.
      d := tr getRootObject: 'hot'.
      tr setRootObject: 'hot' value: (d setAt: 0 value: (d getAt: 0) + 1)]
      retries: 1000.
    commits := commits + 1].
  ^ { attempts. commits }.

| args role id out spaceDir profile nodes scale total each writers fail say writeFile until
  waitFor ids peers rank listener transport node space db options stats0 stats1 t0 t1 attempts
  commits line delta crit expected checksumOf tinyRun hotRun setupRoots m3 m3Run peakRss |
args := Smalltalk arguments.
role := args isEmpty ifTrue: [''] ifFalse: [args first].
(role = 'standalone' and: [args size = 4]) | (role = 'node' and: [args size = 6]) ifFalse: [
  'usage: cluster_workload.st standalone <out> <space> <profile> | node <id> <out> <space> <profile> <nodes>' displayNl.
  Smalltalk exit: 2].
role = 'standalone'
  ifTrue: [id := 's'. out := (args at: 2) asFileReference. spaceDir := args at: 3. profile := args at: 4. nodes := 1]
  ifFalse: [id := args at: 2. out := (args at: 3) asFileReference. spaceDir := args at: 4. profile := args at: 5.
    nodes := (args at: 6) asInteger].

writeFile := [:aName :aText |
  (out / (aName , '.tmp')) contents: aText , (String with: Character lf).
  FileSystem replace: (out / (aName , '.tmp')) pathString with: (out / aName) pathString].
say := [:aText | Stdio stderr nextPutAll: id , ': ' , aText , (String with: Character lf); flush].
fail := [:aText |
  say value: 'FAILED: ' , aText.
  [writeFile value: id , '.error' value: aText] on: Error do: [:e | e return: nil].
  Smalltalk exit: 1].
until := [:aBlock :aSeconds | | deadline |
  deadline := Time millisecondClockValue + (aSeconds * 1000).
  [aBlock value or: [Time millisecondClockValue > deadline]] whileFalse: [(Future after: 2) wait].
  aBlock value].
waitFor := [:aName |
  (until value: [(out / aName) exists] value: 300) ifFalse: [fail value: 'no ' , aName , ' within 300 s']].

(#('tiny' 'conc-hot' 'm3-idx0' 'm3-idx1' 'm3-idx3') includes: profile) ifFalse: [fail value: 'unknown profile ' , profile].
m3 := profile beginsWith: 'm3-'.
"Every member registers M3's extractor: a merge onto the indexed current runs it in whichever
 member's commit builds the merge."
m3 ifTrue: [QueryBench indexesOf: (profile copyFrom: 4 to: profile size)].
(nodes notNil and: [nodes >= 1]) ifFalse: [fail value: 'nodes must be a positive Integer'].
scale := ((Smalltalk getenv: 'CLUSTER_SCALE') ifNil: ['1']) asInteger.
total := 120 * scale.
total \\ nodes = 0 ifFalse: [fail value: 'the total ' , total printString , ' does not split over ' , nodes printString , ' members'].
writers := profile = 'tiny' ifTrue: [1] ifFalse: [4].
each := total // nodes.
each \\ writers = 0 ifFalse: [fail value: 'the transactions of a member do not split over its writers'].
(m3 and: [total > 600]) ifTrue: [fail value: 'M3 writes distinct keys of 600: at most 600 transactions, not ' , total printString].
peakRss := [(('/proc/self/status' asFileReference contents lines detect: [:l | l beginsWith: 'VmHWM:']) subStrings at: 2)].

"The checksum the read-back must give, for the profile, the member count and each."
expected := m3
  ifTrue: [(Smalltalk getenv: 'CLUSTER_M3_EXPECTED') ifNil: [fail value: 'M3 needs CLUSTER_M3_EXPECTED, proto_db''s rows:commits:checksum']]
  ifFalse: [profile = 'tiny'
  ifTrue: [| s |
    s := 0.
    0 to: nodes - 1 do: [:j | 1 to: each do: [:i | | k | k := j * each + i. s := s + (k * (k \\ 1000))]].
    total printString , ':' , s printString]
  ifFalse: ['1:' , total printString]].
"Answers { count. checksum } of the transaction tr, for the profile."
checksumOf := [:tr |
  m3
    ifTrue: [| people c |
      people := tr getRootObject: 'people'.
      people validate.
      c := 0.
      people keysAndValuesDo: [:k :v | (v at: 'id') >= 600 ifTrue: [c := c + 1]].
      { c. people count printString , ':' , c printString , ':' , (QueryBench checksumOf: people) printString }]
    ifFalse: [profile = 'tiny'
    ifTrue: [| c s |
      c := 0. s := 0.
      0 to: nodes - 1 do: [:j |
        (tr getRootObject: 'kv-' , j printString) keysAndValuesDo: [:k :v | c := c + 1. s := s + (k * v)]].
      { c. c printString , ':' , s printString }]
    ifFalse: [| n | n := (tr getRootObject: 'hot') getAt: 0. { n. '1:' , n printString }]]].
"M3: member j's blind writes; answers { block runs. commits }."
m3Run := [:aDb :j | | runs done |
  runs := 0. done := 0.
  0 to: each - 1 do: [:i | | change |
    change := QueryBench change: j * each + i size: 600.
    aDb run: [:tr |
      runs := runs + 1.
      tr setRootObject: 'people' value: (tr newDictionary setAt: (change at: 1) value: (change at: 2))]
      retries: 1000.
    done := done + 1].
  { runs. done }].
"The member's transactions; answer { block runs. commits }, a commit counted when run: returns
 normally (never the number planned: the runner checks the sum against the run's total)."
tinyRun := [:aDb :j | | runs done |
  runs := 0. done := 0.
  1 to: each do: [:i | | k |
    k := j * each + i.
    aDb run: [:tr | | d |
      runs := runs + 1.
      d := tr getRootObject: 'kv-' , j printString.
      tr setRootObject: 'kv-' , j printString value: (d setAt: k value: k \\ 1000)].
    done := done + 1].
  { runs. done }].
hotRun := [:aDb | | actors futures |
  actors := (1 to: writers) collect: [:w | BenchWriter new asActor].
  futures := actors collect: [:a | a hot: each // writers db: aDb].
  futures inject: #(0 0) into: [:acc :f | | r | r := f wait. { (acc at: 1) + (r at: 1). (acc at: 2) + (r at: 2) }]].
"The database's roots, set by one untimed transaction."
setupRoots := [:aDb |
  aDb run: [:tr |
    0 to: nodes - 1 do: [:j | tr setRootObject: 'kv-' , j printString value: tr newDictionary].
    tr setRootObject: 'hot' value: (tr newDictionary setAt: 0 value: 0).
    m3 ifTrue: [tr setRootObject: 'people' value: (QueryBench people: 600 plan: (profile copyFrom: 4 to: profile size))]]].

role = 'standalone' ifTrue: [
  [space := PBObjectSpace storage: (PBFileStorage path: spaceDir).
   db := space newDatabase: 'bench'.
   setupRoots value: db.
   writeFile value: id , '.ready' value: 'ok'.
   waitFor value: 'go'.
   t0 := Time utcMicroseconds.
   attempts := m3 ifTrue: [m3Run value: db value: 0] ifFalse: [
     profile = 'tiny' ifTrue: [tinyRun value: db value: 0] ifFalse: [hotRun value: db]].
   t1 := Time utcMicroseconds.
   commits := attempts at: 2.
   attempts := attempts at: 1.
   space close.
   space := PBObjectSpace storage: (PBFileStorage path: spaceDir).
   line := checksumOf value: (space openDatabase: 'bench') newTransaction.
   space close]
    on: Error do: [:e | fail value: e class name , ': ' , e messageText printString].
  (line at: 2) = expected ifFalse: [fail value: 'checksum ' , (line at: 2) , ', expected ' , expected].
  writeFile value: id , '.result' value: 'commits=' , commits printString , ' attempts=' , attempts printString
    , ' t0=' , t0 printString , ' t1=' , t1 printString , ' rss_kb=' , peakRss value.
  writeFile value: 'verify.result' value: 'count=' , (line at: 1) printString , ' checksum=' , (line at: 2)
    , ' expected=' , expected.
  Smalltalk exit: 0].

"A member of the cluster."
listener := ServerSocket listenOn: 0 host: '127.0.0.1'.
transport := PBTcpTransport withListener: listener.
writeFile value: id , '.port' value: transport port printString.
waitFor value: 'peers'.
peers := (((out / 'peers') contents lines reject: [:l | l trimSeparators isEmpty])
  collect: [:l | | words | words := l subStrings. PBPeer nodeId: (words at: 1) host: '127.0.0.1' port: (words at: 2) asInteger]) asArray.
peers size = nodes ifFalse: [fail value: 'peers names ' , peers size printString , ' members, not ' , nodes printString].
ids := (peers collect: [:p | p nodeId]) asSortedCollection asArray.
rank := (ids indexOf: id) - 1.
rank < 0 ifTrue: [fail value: id , ' is not in peers'].
options := Dictionary new at: #transport put: transport; yourself.
[node := PBClusterCoordinator nodeId: id peers: peers options: options.
 node start.
 space := BenchSpace storage: (PBFileStorage clusterPath: spaceDir) coordinator: node]
  on: Error do: [:e | fail value: 'start: ' , e class name , ': ' , e messageText printString].
(until value: [(node stats at: 'rejoining') not] value: 300) ifFalse: [fail value: 'not joined within 300 s'].
[rank = 0
  ifTrue: [
    db := space newDatabase: 'bench'.
    setupRoots value: db.
    writeFile value: 'created' value: id]
  ifFalse: [
    waitFor value: 'created'.
    space newDatabase: 'scratch-' , id.
    db := space openDatabase: 'bench']]
  on: Error do: [:e | fail value: 'setup: ' , e class name , ': ' , e messageText printString].
writeFile value: id , '.ready' value: 'ok'.
waitFor value: 'go'.

stats0 := node stats.
BenchSplit reset.
t0 := Time utcMicroseconds.
attempts := [m3 ifTrue: [m3Run value: db value: rank] ifFalse: [
    profile = 'tiny' ifTrue: [tinyRun value: db value: rank] ifFalse: [hotRun value: db]]]
  on: Error do: [:e | fail value: 'commit: ' , e class name , ': ' , e messageText printString].
t1 := Time utcMicroseconds.
stats1 := node stats.
commits := attempts at: 2.
attempts := attempts at: 1.
delta := [:k | (stats1 at: k) - (stats0 at: k)].
crit := [:k | ((((stats1 at: 'critical') at: k) - ((stats0 at: 'critical') at: k)) * 1000000.0) rounded].
writeFile value: id , '.result' value: 'commits=' , commits printString , ' attempts=' , attempts printString
  , ' t0=' , t0 printString , ' t1=' , t1 printString
  , ' save_us=' , BenchSplit micros printString , ' saves=' , BenchSplit count printString
  , ' build_us=' , (crit value: 'build') printString , ' replication_us=' , (crit value: 'replication') printString
  , ' critical=' , (delta value: 'critical_commits') printString
  , ' reserve_refusals=' , (delta value: 'sends_refused_reserve') printString
  , ' permits=' , (delta value: 'permit_requests_sent') printString
  , ' rss_kb=' , peakRss value.
say value: 'committed ' , commits printString , ' in ' , ((t1 - t0) // 1000) printString , ' ms'.

rank = 0 ifTrue: [
  waitFor value: 'verify'.
  [db run: [:tr | tr setRootObject: '_read_barrier' value: true].
   line := checksumOf value: db newTransaction]
    on: Error do: [:e | fail value: 'verify: ' , e class name , ': ' , e messageText printString].
  (line at: 2) = expected ifFalse: [fail value: 'checksum ' , (line at: 2) , ', expected ' , expected].
  writeFile value: 'verify.result' value: 'count=' , (line at: 1) printString , ' checksum=' , (line at: 2)
    , ' expected=' , expected].

waitFor value: 'stop'.
space close.
node stop waitWithin: 60000.
Smalltalk exit: 0.
