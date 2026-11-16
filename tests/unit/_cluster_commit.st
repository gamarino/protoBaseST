"_cluster_commit.st: helpers of the cluster commit tests (cluster_commit_path.st,
 cluster_close_inflight.st; a helper: the runner never runs files whose name starts with _).
 Test support, not product: each seam is a subclass overriding one shell method.

  TraceStorage  a PBFileStorage (cluster mode) that notes 'push', 'flush' and 'publish' in its
                trace (an Atom over an Array) when one is set; poison: true makes the next
                segment it creates fail with a FileSystemError, which leaves the storage failed
                (store.st's failure policy). Opened with a small segmentMaxBytes when it is to
                be poisoned, so that a build creates a segment.
  RoundSeam     the seams of one node's round, every field an Atom the test sets: trace (the
                calls of the shell: 'permit', 'done', 'base held', 'send held', 'replicate',
                'answer held', 'paused <outcome>'), permitGate and answerGate (a Future: the
                permit, or the replicate's answer, is handed on only once it resolves),
                holdBase, holdSend, holdAnswer (the base, the send or the answer withheld for
                ever), pauseSend (the send deferred until the Future it holds resolves),
                buildDelay (milliseconds a build sleeps first), poison (a TraceStorage poisoned
                after that sleep), hideTier (the HidesTierFailure plant: the shell reports the
                tier never failed), held (the permitHeld conflicts settled).
  SeamRound     a PBClusterRound that applies the RoundSeam of its node (Seams, by node id);
                Rounds keeps the last round made for each node.
  SeamSpace     a PBObjectSpace whose cluster round is a SeamRound.
  Worker        an actor client: once:block:retries: answers { #ok. value } or { #error. class
                name. text }; increments:... runs a counter workload with a token per commit.
  SeamSpace     also notes, in SeamSpace notes, each confirmation it starts ('<id> confirm') and
                each warning it writes ('<id> warn <text>'), for the cluster read tests.
  CommitKit     a cluster of coordinators over one PBInProcessNetwork and one space directory
                each node opens with its own TraceStorage; waits are conditions with a
                deadline of 60 s (waitUntil:, settle:), never a duration asserted. restart:
                closes a node's space, stops it and starts a new coordinator of that id (a new
                incarnation) over the same acceptor log, then reopens its space. Seams of a
                subclass: endpointFor: (the transport of a node) and acceptorClass."
Import from: 'protobase'.

PBFileStorage subclass: #TraceStorage instanceVariableNames: 'trace poison'.

TraceStorage >> trace: anAtom
  trace := anAtom.

TraceStorage >> poison: aBoolean
  poison := aBoolean.

TraceStorage >> note: aString
  trace isNil ifFalse: [trace swap: [:old | old copyWith: aString]].

TraceStorage >> pushAtom: anEnvelope
  self note: 'push'.
  ^ super pushAtom: anEnvelope.

TraceStorage >> flushSegment
  self note: 'flush'.
  ^ super flushSegment.

TraceStorage >> replaceRoot: aRecord
  self note: 'publish'.
  ^ super replaceRoot: aRecord.

TraceStorage >> readRoot
  self note: 'read root'.
  ^ super readRoot.

TraceStorage >> _newSegmentWriter: aByteArray
  poison == true ifTrue: [^ FileSystemError signal: 'injected failure: the disk is gone'].
  ^ super _newSegmentWriter: aByteArray.

Object subclass: #RoundSeam instanceVariableNames: 'trace permitGate answerGate holdBase holdSend holdAnswer pauseSend buildDelay poison hideTier held'.

RoundSeam class >> new
  ^ self basicNew setUp.

RoundSeam >> setUp
  trace := Atom on: #().
  permitGate := Atom on: nil.
  answerGate := Atom on: nil.
  holdBase := Atom on: false.
  holdSend := Atom on: false.
  holdAnswer := Atom on: false.
  pauseSend := Atom on: nil.
  buildDelay := Atom on: nil.
  poison := Atom on: nil.
  hideTier := Atom on: false.
  held := Atom on: 0.

RoundSeam >> trace ^ trace.
RoundSeam >> permitGate ^ permitGate.
RoundSeam >> answerGate ^ answerGate.
RoundSeam >> holdBase ^ holdBase.
RoundSeam >> holdSend ^ holdSend.
RoundSeam >> holdAnswer ^ holdAnswer.
RoundSeam >> pauseSend ^ pauseSend.
RoundSeam >> buildDelay ^ buildDelay.
RoundSeam >> poison ^ poison.
RoundSeam >> hideTier ^ hideTier.
RoundSeam >> held ^ held.

RoundSeam >> note: aString
  trace swap: [:old | old copyWith: aString].

"The calls of trace that are one of someNames, in order."
RoundSeam >> calls: someNames
  ^ trace value select: [:x | someNames includes: x].

"A Future that settles as aFuture does, once aGate has resolved."
RoundSeam >> after: aGate pipe: aFuture
  | out |
  out := Future new.
  aGate thenDo: [:x | aFuture thenDo: [:v | out resolve: v]; catch: [:e | out rejectWith: e]].
  ^ out.

"Whether every 'replicate' of the trace follows a 'flush' made after the replicate before it."
RoundSeam >> flushedBeforeEachReplicate
  | flushed |
  flushed := false.
  trace value do: [:x |
    x = 'flush' ifTrue: [flushed := true].
    x = 'replicate' ifTrue: [flushed ifFalse: [^ false]. flushed := false]].
  ^ true.

"Whether the n-th 'permit' of the trace (n > 1) follows at least n - 1 'done' (R148: a
 permission's done reaches the node before the next permit asks)."
RoundSeam >> doneBeforeEachPermit
  | dones permits |
  dones := 0.
  permits := 0.
  trace value do: [:x |
    x = 'done' ifTrue: [dones := dones + 1].
    x = 'permit' ifTrue: [
      permits := permits + 1.
      dones < (permits - 1) ifTrue: [^ false]]].
  ^ true.

PBClusterRound subclass: #SeamRound instanceVariableNames: '' classVariableNames: 'Seams Rounds'.

SeamRound class >> setUp
  Seams := Atom on: Dictionary new.
  Rounds := Atom on: Dictionary new.

"The RoundSeam of the node anId (made on first use)."
SeamRound class >> seamOf: anId
  | found |
  found := Seams value at: anId ifAbsent: [nil].
  found notNil ifTrue: [^ found].
  found := RoundSeam new.
  Seams swap: [:d | | copy | copy := d copy. copy at: anId put: found. copy].
  ^ Seams value at: anId.

"A fresh RoundSeam for anId, replacing its old one."
SeamRound class >> resetSeamOf: anId
  Seams swap: [:d | | copy | copy := d copy. copy at: anId put: RoundSeam new. copy].
  ^ Seams value at: anId.

SeamRound class >> roundOf: anId
  ^ Rounds value at: anId ifAbsent: [nil].

SeamRound class >> space: aSpace publisher: aPublisher proxy: aCell
  | round |
  round := super space: aSpace publisher: aPublisher proxy: aCell.
  Rounds swap: [:d | | copy | copy := d copy. copy at: aSpace coordinator nodeId put: round. copy].
  ^ round.

SeamRound >> seam
  ^ SeamRound seamOf: self coordinator nodeId.

SeamRound >> _askPermit
  | gate |
  self seam note: 'permit'.
  gate := self seam permitGate value.
  gate isNil ifTrue: [^ super _askPermit].
  self seam permitGate swap: [:x | nil].
  ^ self seam after: gate pipe: super _askPermit.

SeamRound >> _sendDone: aPermission outcome: anOutcome root: aRoot
  self seam note: 'done'.
  ^ super _sendDone: aPermission outcome: anOutcome root: aRoot.

SeamRound >> _askBase: aPermission
  self seam holdBase value ifTrue: [self seam note: 'base held'. ^ Future new].
  ^ super _askBase: aPermission.

SeamRound >> _build: aBuild
  | ms |
  ms := self seam buildDelay value.
  ms isNil ifFalse: [(Future after: ms) wait].
  self seam poison value isNil ifFalse: [self seam poison value poison: true].
  ^ super _build: aBuild.

SeamRound >> _tierFailed
  self seam hideTier value ifTrue: [^ false].
  ^ super _tierFailed.

SeamRound >> _send: aReplicate
  | gate |
  self seam holdSend value ifTrue: [self seam note: 'send held'. ^ self].
  gate := self seam pauseSend value.
  gate isNil ifTrue: [^ super _send: aReplicate].
  self seam pauseSend swap: [:x | nil].
  self seam note: 'send paused'.
  gate thenDo: [:x | self _later: [self _pausedSend: aReplicate]].

SeamRound >> _pausedSend: aReplicate
  self seam note: 'send resumed'.
  ^ self _sendNow: aReplicate.

SeamRound >> _replicate: aRoot under: aPermission
  | f gate |
  self seam note: 'replicate'.
  f := super _replicate: aRoot under: aPermission.
  f thenDo: [:v | self seam note: 'answered ' , (v isString ifTrue: [v asString] ifFalse: [v class name])];
    catch: [:e | self seam note: 'answered ' , e class name].
  self seam holdAnswer value ifTrue: [self seam note: 'answer held'. ^ Future new].
  gate := self seam answerGate value.
  gate isNil ifTrue: [^ f].
  ^ self seam after: gate pipe: f.

SeamRound >> applySettle: aSettle
  ((aSettle outcome isKindOf: PBConflictError) and: [aSettle outcome permitHeld]) ifTrue: [
    self seam held swap: [:n | n + 1]].
  ^ super applySettle: aSettle.

SeamRound setUp.

PBObjectSpace subclass: #SeamSpace instanceVariableNames: '' classVariableNames: 'Notes'.

SeamSpace class >> setUp
  Notes := Atom on: #().

SeamSpace class >> note: aString
  Notes swap: [:old | old copyWith: aString].

"Every note so far, in order."
SeamSpace class >> notes
  ^ Notes value.

SeamSpace >> _newClusterRound: aPublisher proxy: aCell
  ^ SeamRound space: self publisher: aPublisher proxy: aCell.

SeamSpace >> _confirm
  SeamSpace note: self coordinator nodeId , ' confirm'.
  ^ super _confirm.

SeamSpace >> _warn: aString
  SeamSpace note: self coordinator nodeId , ' warn ' , aString.
  ^ super _warn: aString.

SeamSpace setUp.

Object subclass: #Worker.

"{ #ok. the value of aDatabase run: aBlock retries: n } or { #error. class name. text }."
Worker >> once: aDatabase block: aBlock retries: n
  ^ [{ #ok. aDatabase run: aBlock retries: n }] on: Error do: [:e | e return: { #error. e class name. e messageText }].

"n increments of the root 'counter' of aDatabase, each writing its own token (aPrefix-i ->
 aPrefix) into the dictionary 'tokens', with run: retries: r: { acknowledged tokens. unknown
 tokens. other errors }."
Worker >> increments: aDatabase count: n prefix: aPrefix retries: r
  | acked unknown other |
  acked := OrderedCollection new.
  unknown := OrderedCollection new.
  other := OrderedCollection new.
  1 to: n do: [:i | | token |
    token := aPrefix , '-' , i printString.
    [aDatabase run: [:t |
        t setRootObject: 'counter' value: (t getRootObject: 'counter') + 1.
        t setRootObject: 'tokens' value: ((t getRootObject: 'tokens') setAt: token value: aPrefix)] retries: r.
     acked add: token]
      on: Error do: [:e |
        (e isKindOf: PBOutcomeUnknownError)
          ifTrue: [unknown add: token]
          ifFalse: [other add: token , ': ' , e class name , ': ' , (e messageText ifNil: [''])].
        e return: nil]].
  ^ { acked asArray. unknown asArray. other asArray }.

"aSpace closed: true, or the error class name."
Worker >> close: aSpace
  ^ [aSpace close. true] on: Error do: [:e | e return: e class name].

Object subclass: #CommitKit instanceVariableNames: 'ids dir network nodes spaces options storages peers restarts'.

"The nodes anArray over the space directory aDirectory, with extra options."
CommitKit class >> ids: anArray dir: aDirectory options: aDictionary
  ^ self basicNew setIds: anArray dir: aDirectory options: aDictionary.

CommitKit >> setIds: anArray dir: aDirectory options: aDictionary
  ids := anArray.
  dir := aDirectory.
  options := aDictionary.
  storages := Dictionary new.
  restarts := Dictionary new.
  self start.

"New coordinators (a new network), started, nothing attached."
CommitKit >> start
  network := PBInProcessNetwork new.
  peers := (1 to: ids size) asArray collect: [:i | PBPeer nodeId: (ids at: i) host: '127.0.0.1' port: 7300 + i].
  nodes := ids collect: [:id | self newNode: id].
  nodes do: [:n | n start].
  spaces := Array new: ids size.

"A new, unstarted coordinator anId on the kit's network; each one draws its own incarnation."
CommitKit >> newNode: anId
  | o n |
  n := restarts at: anId ifAbsent: [0].
  restarts at: anId put: n + 1.
  o := Dictionary new
    at: #leaseDuration put: 600; at: #driftMargin put: 400; at: #requestTimeout put: 100;
    at: #seed put: (ids indexOf: anId) + 11 + (100 * n); yourself.
  options keysAndValuesDo: [:k :v | o at: k put: v].
  o at: #transport put: (self endpointFor: anId).
  ^ PBClusterCoordinator nodeId: anId peers: peers options: o rules: PBCoordinatorCore new acceptorClass: self acceptorClass.

"The transport of the node anId (a seam)."
CommitKit >> endpointFor: anId
  ^ network endpoint.

"The acceptor class of every node (a seam)."
CommitKit >> acceptorClass
  ^ _PBAcceptor.

CommitKit >> network ^ network.

"anId restarted: its space closed, its node stopped, a new coordinator of that id started over
 the same acceptor log, and its space opened again (answered)."
CommitKit >> restart: anId
  | i |
  i := ids indexOf: anId.
  (spaces at: i) isNil ifFalse: [[(spaces at: i) close] on: Error do: [:e | e return: nil]].
  (nodes at: i) stop waitWithin: 60000.
  nodes at: i put: (self newNode: anId).
  (nodes at: i) start.
  ^ self open: anId.

"anId's space closed and its node stopped (its log kept)."
CommitKit >> down: anId
  | i |
  i := ids indexOf: anId.
  (spaces at: i) isNil ifFalse: [[(spaces at: i) close] on: Error do: [:e | e return: nil]].
  spaces at: i put: nil.
  (nodes at: i) stop waitWithin: 60000.

"A new coordinator of anId started (after down:), nothing attached."
CommitKit >> up: anId
  | i |
  i := ids indexOf: anId.
  nodes at: i put: (self newNode: anId).
  (nodes at: i) start.
  ^ nodes at: i.

CommitKit >> dir ^ dir.

CommitKit >> ids ^ ids.
CommitKit >> nodes ^ nodes.
CommitKit >> spaces ^ spaces.

CommitKit >> node: anId
  ^ nodes at: (ids indexOf: anId).

CommitKit >> space: anId
  ^ spaces at: (ids indexOf: anId).

CommitKit >> storage: anId
  ^ storages at: anId.

"Opens the space of anId (a SeamSpace over a new TraceStorage of the directory) and answers it."
CommitKit >> open: anId
  ^ self open: anId segmentMaxBytes: PBFileStorage defaultSegmentMaxBytes.

CommitKit >> open: anId segmentMaxBytes: n
  | st space |
  st := TraceStorage clusterPath: dir pathString segmentMaxBytes: n.
  storages at: anId put: st.
  space := SeamSpace storage: st coordinator: (self node: anId).
  spaces at: (ids indexOf: anId) put: space.
  ^ space.

CommitKit >> openAll
  ids do: [:id | self open: id].
  ^ self waitUntil: [nodes allSatisfy: [:n | (n stats at: 'rejoining') not]].

"Whether aBlock answers true within 60 s, polled every 10 ms."
CommitKit >> waitUntil: aBlock
  | deadline |
  deadline := Time millisecondClockValue + 60000.
  [aBlock value] whileFalse: [
    Time millisecondClockValue > deadline ifTrue: [^ false].
    (Future after: 10) wait].
  ^ true.

"The value of aFuture within 120 s, or #hung."
CommitKit >> settle: aFuture
  ^ [aFuture waitWithin: 120000] on: Error do: [:e | e return: { #hung. e class name }].

"The database aName of anId's space, once its node knows it (nil after 60 s)."
CommitKit >> db: aName on: anId
  | space |
  space := self space: anId.
  (self waitUntil: [[space listDatabases includes: aName] on: Error do: [:e | e return: false]]) ifFalse: [^ nil].
  ^ space openDatabase: aName.

"Every open space closed, every node stopped (waited)."
CommitKit >> shutdown
  spaces do: [:s | s isNil ifFalse: [[s close] on: Error do: [:e | e return: nil]]].
  nodes do: [:n | [n stop waitWithin: 60000] on: Error do: [:e | e return: nil]].

"The PBSpaceRoot of the committed root anId's node knows, nil when none."
CommitKit >> committedSpaceRoot: anId
  | root |
  root := (self node: anId) committedRoot.
  (root isNil or: [root record isNil]) ifTrue: [^ nil].
  ^ (self space: anId) _spaceRootAt: root record.

"The value of the root aName of the database aDb in aSpaceRoot."
CommitKit >> root: aName of: aDb in: aSpaceRoot
  ^ ((aSpaceRoot databases getAt: aDb) objects) getAt: aName.

"The incrementing block of one token: counter + 1 and tokens at: aToken put: aTag."
CommitKit class >> incr: aToken tag: aTag
  ^ [:t |
    t setRootObject: 'counter' value: (t getRootObject: 'counter') + 1.
    t setRootObject: 'tokens' value: ((t getRootObject: 'tokens') setAt: aToken value: aTag)].
