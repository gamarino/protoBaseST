"_node.st: one cluster member in a process of its own, the node of the real-process tests
 (tests/cluster/_cluster.sh drives it; a helper, never run as a test).

  _node.st worker <id> <out> <space> <n> <after> <mark>
  _node.st verifier <id> <out> <space>

 Every member listens on a PBTcpTransport bound to port 0 on 127.0.0.1 and writes the port the
 system picked to <out>/<id>.port (written to a .tmp file, then renamed over it). It then waits
 for <out>/peers, which the driver writes once every member wrote its port: a line
 'voters <id>...' and a line '<id> <port>' per member. The coordinator takes the option values of
 examples/cluster/14_cluster_commits.st: a lease of 3000 ms, the default drift margin, a
 requestTimeout of 100 ms, and an acquireTimeout of 8000 ms. Its space is PBFileStorage
 clusterPath: <space>, the directory every member shares.

 A worker commits, with run:, increments of the root 'counter' of the database 'shop', each one
 recording a token unique to it ('<id>-<i>') in the root dictionary 'tokens'. Before a commit
 starts, its token is appended to <out>/<id>.attempt; when it ends, to <out>/<id>.acked (run:
 returned) or <out>/<id>.unknown (PBOutcomeUnknownError: the commit may have been applied). Each
 line is appended and synced (BinaryFile append: + sync) before the next step, so a kill -9 never
 loses a line of a token whose outcome the node learnt. A PBConflictError (after run:'s own 100
 retries) or a PBTimeoutError (no permission within acquireTimeout) left nothing outside the node
 (tutorial chapter 14): the same token is committed again, at most 200 times. Any other error is
 a failure: it is written to <out>/<id>.error and the process exits 1.

 The first worker of the voters line creates 'shop' (counter 0, tokens empty) and writes
 <out>/created; every other worker waits for it, then commits newDatabase: '<id>-scratch', a
 barrier (tutorial chapter 14), so that it knows 'shop' before it opens it.

 A worker runs <n> commits. With <mark> 'owner' (or 'voter'), from its 10th acknowledgement on,
 after each one, a worker that serves the current term (or, for 'voter', a voter that does not)
 tries to create <out>/mark exclusively (#create #exclusive: one process wins, in any order) and
 writes its id there, with the term it serves ('<id> <term>', 0 for 'voter'). The worker that
 holds the mark goes on committing past <n> until <out>/killed exists: the driver kills it with
 kill -9 while it commits. With <after> > 0 a worker then waits for <out>/killed and commits
 <after> more: commits made after the death of a member. It writes <out>/<id>.done ('acked A
 unknown U conflicts C timeouts T committed_label L', L the label, the term, of the newest root
 its node knows committed), waits for <out>/stop (it stays a member until every worker is done:
 a majority of voters must stay up), closes its space, stops its node and exits 0.

 The verifier is a learner (not in the voters line), so it never takes part in a majority. It
 waits for <out>/verify, then commits newDatabase: '<id>-scratch' and a '_read_barrier' root in
 'shop' (barriers: it knows every commit acknowledged before them), reads 'counter' and
 'tokens', and writes <out>/<id>.present (each token of every <out>/*.attempt file that 'tokens'
 holds, one per line) and then <out>/<id>.result ('counter C count K', K the size of 'tokens').
 It then waits for <out>/stop as a worker does.

 Every wait on a file is bounded (300 s; 540 s for stop): a hang becomes an error naming the
 file. No duration is asserted."
Import from: 'protobase'.

| args role id out spaceDir n after markMode fail say waitFor writeFile appendTo files
  peerLines voters peers transport node space db acked unknown conflicts timeouts retrying
  commit holdsMark markTried tryMark i until |
args := Smalltalk arguments.
args size < 4 ifTrue: [
  'usage: _node.st worker <id> <out> <space> <n> <after> <mark> | verifier <id> <out> <space>' displayNl.
  Smalltalk exit: 2].
role := args at: 1.
id := args at: 2.
out := (args at: 3) asFileReference.
spaceDir := args at: 4.
files := Dictionary new.

"Appends aLine to <out>/<aName>, synced; the file is opened once (one appender per file)."
appendTo := [:aName :aLine | | f |
  f := files at: aName ifAbsent: [
    files at: aName put: (BinaryFile open: (out / aName) options: #(#append #create))].
  f append: (aLine , (String with: Character lf)) utf8Encoded.
  f sync].
"Writes <out>/<aName> whole: a .tmp file, then renamed over it, so a reader sees all or nothing."
writeFile := [:aName :aText |
  (out / (aName , '.tmp')) contents: aText.
  FileSystem replace: (out / (aName , '.tmp')) pathString with: (out / aName) pathString].
say := [:aText | Stdio stderr nextPutAll: id , ': ' , aText , (String with: Character lf); flush].
fail := [:aText |
  say value: 'FAILED: ' , aText.
  [writeFile value: id , '.error' value: aText , (String with: Character lf)] on: Error do: [:e | e return: nil].
  Smalltalk exit: 1].
until := [:aBlock :aSeconds | | deadline |
  deadline := Time millisecondClockValue + (aSeconds * 1000).
  [aBlock value or: [Time millisecondClockValue > deadline]] whileFalse: [(Future after: 20) wait].
  aBlock value].
waitFor := [:aName :aSeconds |
  (until value: [(out / aName) exists] value: aSeconds) ifFalse: [
    fail value: 'no ' , aName , ' within ' , aSeconds printString , ' s']].

(#('worker' 'verifier') includes: role) ifFalse: [fail value: 'unknown role ' , role].
role = 'worker' ifTrue: [
  args size = 7 ifFalse: [fail value: 'a worker takes <id> <out> <space> <n> <after> <mark>'].
  n := (args at: 5) asInteger.
  after := (args at: 6) asInteger.
  markMode := args at: 7.
  (#('none' 'owner' 'voter') includes: markMode) ifFalse: [fail value: 'unknown mark ' , markMode]].

"The listener first, on a port the system picks; then the peers the driver names."
transport := PBTcpTransport withListener: (ServerSocket listenOn: 0 host: '127.0.0.1').
writeFile value: id , '.port' value: transport port printString , (String with: Character lf).
waitFor value: 'peers' value: 300.
peerLines := (out / 'peers') contents lines collect: [:l | l subStrings].
peerLines := peerLines reject: [:words | words isEmpty].
voters := ((peerLines detect: [:words | words first = 'voters'] ifNone: [fail value: 'peers names no voters'])
  allButFirst) asArray.
peers := ((peerLines reject: [:words | words first = 'voters'])
  collect: [:words | PBPeer nodeId: (words at: 1) host: '127.0.0.1' port: (words at: 2) asInteger]) asArray.
say value: 'peers ' , (peers collect: [:p | p nodeId , ':' , p port printString]) printString.

node := PBClusterCoordinator nodeId: id peers: peers options: (Dictionary new
  at: #leaseDuration put: 3000;
  at: #requestTimeout put: 100;
  at: #acquireTimeout put: 8000;
  at: #voters put: voters;
  at: #transport put: transport;
  yourself).
node start.
space := PBObjectSpace storage: (PBFileStorage clusterPath: spaceDir) coordinator: node.
(until value: [(node stats at: 'rejoining') not] value: 300) ifFalse: [
  fail value: 'the node did not finish joining within 300 s'].
say value: 'joined'.

acked := 0. unknown := 0. conflicts := 0. timeouts := 0.
"Answers aBlock's value; a PBConflictError or PBTimeoutError (nothing left the node) runs it
 again, at most 200 times. aBlock answers non-nil."
retrying := [:aBlock :aWhat | | value tries |
  value := nil. tries := 0.
  [value isNil] whileTrue: [
    tries := tries + 1.
    tries > 200 ifTrue: [fail value: aWhat , ': no commit after 200 conflicts or timeouts'].
    value := [[aBlock value]
        on: PBConflictError do: [:e | conflicts := conflicts + 1. say value: aWhat , ': ' , e messageText. e return: nil]]
      on: PBTimeoutError do: [:e | timeouts := timeouts + 1. say value: aWhat , ': ' , e messageText. e return: nil]].
  value].

role = 'verifier' ifTrue: [ | counter tokens present tr |
  waitFor value: 'verify' value: 540.
  retrying value: [space newDatabase: id , '-scratch'. true] value: 'newDatabase: ' , id , '-scratch'.
  db := space openDatabase: 'shop'.
  retrying value: [db run: [:t | t setRootObject: '_read_barrier' value: true] retries: 100. true]
    value: '_read_barrier'.
  tr := db newTransaction.
  counter := tr getRootObject: 'counter'.
  tokens := tr getRootObject: 'tokens'.
  present := OrderedCollection new.
  (out children select: [:f | f basename endsWith: '.attempt']) do: [:f |
    f contents lines do: [:token |
      (token notEmpty and: [(tokens getAt: token) notNil]) ifTrue: [present add: token]]].
  tr abort.
  writeFile value: id , '.present' value: (present inject: '' into: [:acc :t | acc , t , (String with: Character lf)]).
  writeFile value: id , '.result' value: 'counter ' , counter printString , ' count ' , tokens count printString
    , (String with: Character lf).
  say value: 'verified: counter ' , counter printString , ', ' , present size printString , ' tokens present'].

role = 'worker' ifTrue: [
  "The database: the first voter creates it; the others wait, then pass a barrier."
  id = voters first
    ifTrue: [
      retrying value: [db := space newDatabase: 'shop'] value: 'newDatabase: shop'.
      retrying value: [db run: [:t |
          t setRootObject: 'counter' value: 0.
          t setRootObject: 'tokens' value: t newDictionary] retries: 100. true]
        value: 'shop setup'.
      writeFile value: 'created' value: id , (String with: Character lf)]
    ifFalse: [
      waitFor value: 'created' value: 300.
      retrying value: [space newDatabase: id , '-scratch'. true] value: 'newDatabase: ' , id , '-scratch'.
      db := space openDatabase: 'shop'].

  "One commit of aToken: attempt, then acked or unknown, each line synced."
  commit := [:aToken | | outcome |
    appendTo value: id , '.attempt' value: aToken.
    outcome := retrying value: [
        [db run: [:t |
            t setRootObject: 'counter' value: (t getRootObject: 'counter') + 1.
            t setRootObject: 'tokens' value: ((t getRootObject: 'tokens') setAt: aToken value: id)]
          retries: 100.
         #acked]
          on: PBOutcomeUnknownError do: [:e | say value: aToken , ' unknown: ' , e messageText. e return: #unknown]]
      value: aToken.
    outcome = #acked
      ifTrue: [acked := acked + 1. appendTo value: id , '.acked' value: aToken]
      ifFalse: [unknown := unknown + 1. appendTo value: id , '.unknown' value: aToken]].

  holdsMark := false.
  markTried := false.
  "From the 10th acknowledgement on, an eligible worker tries once to take the mark."
  tryMark := [ | ownership serving eligible f |
    (markMode ~= 'none' and: [markTried not and: [acked >= 10]]) ifTrue: [
      ownership := node nodeState ownership.
      serving := ownership notNil and: [ownership isServingAt: Time microsecondClockValue].
      eligible := markMode = 'owner'
        ifTrue: [serving]
        ifFalse: [(voters includes: id) and: [serving not]].
      eligible ifTrue: [
        markTried := true.
        f := [BinaryFile open: (out / 'mark') options: #(#write #create #exclusive)]
          on: FileAlreadyExists do: [:e | e return: nil].
        f isNil ifFalse: [
          f append: (id , ' ' , (serving ifTrue: [ownership term] ifFalse: [0]) printString
            , (String with: Character lf)) utf8Encoded.
          f sync.
          f close.
          holdsMark := true.
          say value: 'took the mark (' , markMode , ') after ' , acked printString , ' acknowledgements']]]].

  i := 0.
  [i < n or: [holdsMark and: [(out / 'killed') exists not]]] whileTrue: [
    i := i + 1.
    commit value: id , '-' , i printString.
    tryMark value].
  holdsMark ifTrue: [fail value: 'the mark holder was not killed'].
  after > 0 ifTrue: [
    waitFor value: 'killed' value: 300.
    after timesRepeat: [
      i := i + 1.
      commit value: id , '-' , i printString]].
  writeFile value: id , '.done' value: 'acked ' , acked printString , ' unknown ' , unknown printString
    , ' conflicts ' , conflicts printString , ' timeouts ' , timeouts printString
    , ' committed_label ' , node committedRoot label printString , (String with: Character lf).
  say value: 'done: acked ' , acked printString , ', unknown ' , unknown printString].

waitFor value: 'stop' value: 540.
files do: [:f | f close].
space close.
(node stop waitWithin: 60000).
say value: 'stopped'.
Smalltalk exit: 0.
