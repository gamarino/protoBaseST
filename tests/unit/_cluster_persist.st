"_cluster_persist.st: helpers of the persister tests (cluster_persister.st,
 cluster_persister_recovery.st; a helper: the runner never runs files whose name starts with _).
 Test support, not product, over _cluster_commit.st: each seam is a subclass overriding one method.

  PersistSeams   the seams of the persisters and storages, by node id, every field an Atom the test
                 sets: holdWritesOf:until: (the next write of that node's persister waits for a
                 Future first, 20 s at most: used once), dropWrites: (the writes of that node's
                 persister are dropped, noted, never sent: an outage of the storage root for that
                 node), breakPasses: (every pass of that node's persister signals a plain Error, an
                 unexpected failure), and notes ('<id> write held', '<id> write sent', '<id> write
                 dropped', '<id> push gated', '<id> push released', '<id> gate expired').
  SeamPersister  a PBPersister applying them.
  PersistSpace   a SeamSpace whose persister is a SeamPersister.
  GateStorage    a TraceStorage whose next pushAtom: waits, once armed (gatePushes:), inside its
                 write operation, until a Future resolves (20 s at most): a commit's write held in
                 progress on the round runner, while the test makes the persister write (Task 21
                 review I1).
  MuteEndpoint   a transport that, once armed, drops what would tell n2 of others' commits.
  PersistKit     a CommitKit opening GateStorage and PersistSpace, over MuteEndpoints.
  Persist        reads of the persisted root (its counter, through a fresh storage of the
                 directory), the wiped logs, the progress lines on stderr (never asserted), and
                 within:do: (a step run on its own actor, bounded by a deadline: a step that
                 would hang answers #hung, so a check fails on it instead of the file).
  Bounded        the actor within:do: runs its step on."
Import from: 'protobase'.
Import from: '_cluster_commit'.

Object subclass: #PersistSeams classVariableNames: 'Holds Drops Breaks Notes'.

PersistSeams class >> setUp
  Holds := Atom on: Dictionary new.
  Drops := Atom on: #().
  Breaks := Atom on: #().
  Notes := Atom on: #().

PersistSeams class >> note: aString
  Notes swap: [:old | old copyWith: aString].

PersistSeams class >> notes
  ^ Notes value.

"Whether aString was noted."
PersistSeams class >> noted: aString
  ^ Notes value includes: aString.

"How many times aString was noted."
PersistSeams class >> count: aString
  ^ Notes value count: [:x | x = aString].

"Whether aString was noted after the first n notes."
PersistSeams class >> noted: aString after: n
  | all |
  all := Notes value.
  ^ (all copyFrom: n + 1 to: all size) includes: aString.

PersistSeams class >> holdWritesOf: anId until: aFuture
  Holds swap: [:d | | copy | copy := d copy. copy at: anId put: aFuture. copy].

"The hold of anId, taken (used once), or nil."
PersistSeams class >> takeHoldOf: anId
  | gate |
  gate := Holds value at: anId ifAbsent: [nil].
  gate isNil ifFalse: [Holds swap: [:d | | copy | copy := d copy. copy removeKey: anId ifAbsent: [nil]. copy]].
  ^ gate.

PersistSeams class >> dropWrites: anArray
  Drops swap: [:old | anArray].

PersistSeams class >> drops: anId
  ^ Drops value includes: anId.

PersistSeams class >> breakPasses: anArray
  Breaks swap: [:old | anArray].

PersistSeams class >> breaks: anId
  ^ Breaks value includes: anId.

PersistSeams setUp.

PBPersister subclass: #SeamPersister.

SeamPersister >> _write: aRoot
  | id gate |
  id := coordinator nodeId.
  (PersistSeams drops: id) ifTrue: [
    (PersistSeams noted: id , ' write dropped') ifFalse: [PersistSeams note: id , ' write dropped'].
    ^ self].
  gate := PersistSeams takeHoldOf: id.
  gate isNil ifFalse: [
    PersistSeams note: id , ' write held'.
    ([gate waitWithin: 20000. true] on: Error do: [:e | e return: false]) ifFalse: [
      PersistSeams note: id , ' gate expired']].
  super _write: aRoot.
  PersistSeams note: id , ' write sent'.

SeamPersister >> _cycle
  (PersistSeams breaks: coordinator nodeId) ifTrue: [^ Error new signal: 'upload queue corrupted'].
  ^ super _cycle.

SeamSpace subclass: #PersistSpace.

PersistSpace >> _newPersister
  ^ SeamPersister tier: self _tier coordinator: self coordinator writer: runner.

TraceStorage subclass: #GateStorage instanceVariableNames: 'pushGate nodeId'.

GateStorage >> nodeId: anId
  nodeId := anId.
  pushGate := Atom on: nil.

"The next pushAtom: waits for aFuture first."
GateStorage >> gatePushes: aFuture
  pushGate swap: [:old | aFuture].

"Inside the write operation of a pushAtom: (the storage's state is { #writing. token }): the
 gate holds the write in progress."
GateStorage >> _segmentFor: aSize
  | gate |
  gate := pushGate isNil ifTrue: [nil] ifFalse: [pushGate value].
  (gate notNil and: [pushGate value: nil ifCurrent: gate]) ifTrue: [
    PersistSeams note: nodeId , ' push gated'.
    ([gate waitWithin: 20000. true] on: Error do: [:e | e return: false]) ifFalse: [
      PersistSeams note: nodeId , ' gate expired'].
    PersistSeams note: nodeId , ' push released'].
  ^ super _segmentFor: aSize.

"Once armed, drops every message sent to n2 that would tell it of another member's commit
 unprompted (proto_db's _UNPROMPTED: done, release, replicate, store, propose, warm, records),
 noting each type dropped (Muted)."
PBInProcessTransport subclass: #MuteEndpoint instanceVariableNames: '' classVariableNames: 'Armed Muted'.

MuteEndpoint class >> setUp
  Armed := Atom on: false.
  Muted := Atom on: #().

MuteEndpoint class >> arm: aBoolean
  Armed swap: [:x | aBoolean].

MuteEndpoint class >> muted
  ^ Muted value.

MuteEndpoint >> send: aMessage to: aNodeId
  (Armed value and: [aNodeId = 'n2' and: [#('done' 'release' 'replicate' 'store' 'propose' 'warm' 'records') includes: aMessage type]])
    ifTrue: [
      Muted swap: [:d | (d includes: aMessage type) ifTrue: [d] ifFalse: [d copyWith: aMessage type]].
      ^ self].
  ^ super send: aMessage to: aNodeId.

MuteEndpoint setUp.

CommitKit subclass: #PersistKit.

PersistKit >> endpointFor: anId
  ^ MuteEndpoint network: self network.

PersistKit >> open: anId lockTimeout: milliseconds
  | st space |
  st := (GateStorage clusterPath: dir pathString segmentMaxBytes: PBFileStorage defaultSegmentMaxBytes) nodeId: anId; yourself.
  storages at: anId put: st.
  space := PersistSpace storage: st coordinator: (self node: anId) lockTimeout: milliseconds.
  spaces at: (ids indexOf: anId) put: space.
  ^ space.

PersistKit >> open: anId segmentMaxBytes: n
  | st space |
  st := (GateStorage clusterPath: dir pathString segmentMaxBytes: n) nodeId: anId; yourself.
  storages at: anId put: st.
  space := PersistSpace storage: st coordinator: (self node: anId).
  spaces at: (ids indexOf: anId) put: space.
  ^ space.

"anId's space closed, its node stopped, and its acceptor log moved aside (a wiped disk: the file
 renamed to <id>.roots.lost<n>, never removed)."
PersistKit >> wipe: anId
  | log n |
  self down: anId.
  log := dir / 'cluster' / (anId , '.roots').
  n := 1.
  [(dir / 'cluster' / (anId , '.roots.lost' , n printString)) exists] whileTrue: [n := n + 1].
  log exists ifTrue: [log renameTo: anId , '.roots.lost' , n printString].

"anId started again (a new coordinator) and its space opened: answered."
PersistKit >> revive: anId
  self up: anId.
  ^ self open: anId.

Object subclass: #Bounded.

Bounded >> run: aBlock
  ^ [{ #ok. aBlock value }] on: Error do: [:e | e return: { #error. e class name }].

Object subclass: #Persist.

"aBlock run on a new actor: its value, the class name of its error, or #hung when it has not ended
 within milliseconds (the actor is left behind)."
Persist class >> within: milliseconds do: aBlock
  | r |
  r := [(Bounded new asActor run: aBlock) waitWithin: milliseconds] on: Error do: [:e | e return: #(#hung)].
  ^ r first = #ok ifTrue: [r last] ifFalse: [r first = #error ifTrue: [r last] ifFalse: [#hung]].

"aString on stderr with the monotonic milliseconds: where a run is, never asserted."
Persist class >> step: aString
  [Stdio stderr nextPutAll: 'cluster_persister ' , Time millisecondClockValue printString , ' ' , aString; lf; flush]
    on: Error do: [:e | nil].

Persist class >> incr
  ^ [:t | t setRootObject: 'counter' value: (t getRootObject: 'counter') + 1].

"aDatabase run: incr, retried on PBConflictError and PBTimeoutError up to n times: #ok or the
 last error's class name."
Persist class >> run: aDatabase retries: n
  | last |
  1 to: n do: [:i |
    last := [aDatabase run: self incr retries: 20. nil] on: Error do: [:e | e return: e].
    last isNil ifTrue: [^ #ok].
    ((last isKindOf: PBConflictError) or: [last isKindOf: PBTimeoutError]) ifFalse: [^ last class name]].
  ^ last class name.

"anArray of node ids, each committing one increment of 'db' in turn, count commits in all: the
 results, in order."
Persist class >> commits: count over: anArray kit: aKit
  ^ (1 to: count) collect: [:i | self run: (aKit db: 'db' on: (anArray at: i - 1 \\ anArray size + 1)) retries: 3].

"The counter of 'db' a new transaction of aSpace reads, or the error's class name."
Persist class >> counterIn: aSpace
  ^ [| tr v | tr := (aSpace openDatabase: 'db') newTransaction. v := tr getRootObject: 'counter'. tr abort. v]
    on: Error do: [:e | e return: e class name].

"The database 'db' made on anId's space, its root 'counter' set to anInteger: #ok, or the class
 name of the error (a check fails on it, never the run)."
Persist class >> create: aKit on: anId counter: anInteger
  ^ [((aKit space: anId) newDatabase: 'db') run: [:t | t setRootObject: 'counter' value: anInteger]. #ok]
    on: Error do: [:e | e return: e class name].

"aSpace sync: milliseconds: nil, or the class name of its error (a check fails on it, never the run)."
Persist class >> sync: aSpace within: milliseconds
  ^ [aSpace sync: milliseconds] on: Error do: [:e | e return: e class name].

"The PBLabeledRoot space.root holds in aDirectory (through a fresh storage), nil when none."
Persist class >> persistedIn: aDirectory
  | st tier |
  st := PBFileStorage clusterPath: aDirectory pathString.
  ^ [st readRoot isNil ifTrue: [nil] ifFalse: [
      tier := PBSharedTier basicNew _setStorage: st nodeId: 'reader' log: nil.
      tier readPersisted]] ensure: [st close].

"The counter of 'db' in the root space.root holds in aDirectory (through a fresh storage, the
 SpaceRoot read as a cluster node reads it), nil when none."
Persist class >> persistedCounterIn: aDirectory
  | st root sr db |
  st := PBFileStorage clusterPath: aDirectory pathString.
  ^ [root := st readRoot.
     root isNil ifTrue: [nil] ifFalse: [
       sr := PBTypeRegistry unloadedAtomFor: (PBTypeRegistry aliasOf: PBSpaceRoot typeName) at: root pointer storage: st.
       db := sr databases getAt: 'db'.
       db isNil ifTrue: [nil] ifFalse: [db objects getAt: 'counter']]] ensure: [st close].

"The options of the persister tests' kits: acquireTimeout 8000 ms and persistLag milliseconds."
Persist class >> options: lagMilliseconds
  ^ Dictionary new at: #leaseDuration put: 1500; at: #driftMargin put: 1000; at: #requestTimeout put: 300;
    at: #acquireTimeout put: 8000; at: #persistLag put: lagMilliseconds; yourself.

"A PersistKit of n0, n1 and n2 over aDirectory, its waits ending at 20 s each."
Persist class >> kitDir: aDirectory lag: lagMilliseconds
  | kit |
  kit := PersistKit ids: #('n0' 'n1' 'n2') dir: aDirectory options: (self options: lagMilliseconds).
  kit limit: 20000.
  ^ kit.
