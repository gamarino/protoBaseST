"_cluster_reads.st: helpers of the cluster read tests (cluster_reads.st, cluster_reads_restarts.st,
 cluster_reads_majority.st; a helper: the runner never runs files whose name starts with _).
 Test support, not product, over _cluster_commit.st.

  GateAcceptor  an acceptor that, while its node has a gate (a Future), defers its learning of
                its own commit (the PBLearnCommitted of the commit point: accepted and logged, of
                a root its node's round built, RoundSeam hasBuilt:) until the gate opens, 20 s
                at most: the event is handed back to the acceptor then, and the acceptor goes on
                with the events behind it meanwhile, so a held learning never blocks another
                commit's acceptance; a gate that expires is counted (timedOut), so a test that
                never opens it fails instead of hanging. closeHearsay: defers, the same way, its
                learning of committed roots it neither accepts nor logs (a recovery's answers).
  DropEndpoint  a transport that, once armed, drops the first two 'answer' messages sent to n0.
  GateKit, DropKit  CommitKits whose nodes have a GateAcceptor, or a DropEndpoint.
  ReadWorker    an actor client: commits and reads off the test's thread, so a commit that does not
                return shows up as { #hung. ... } from the kit's settle:, never as a hang.
  Reads         the reads and commits of the tests, the power loss of an acceptor log, and the
                progress lines on stderr (never asserted)."
Import from: 'protobase'.
Import from: '_cluster_commit'.

"=== seams ===================================================================="

"Held counts the events held, Learnt the events it went on with, TimedOut the gates that expired."
_PBAcceptor subclass: #GateAcceptor instanceVariableNames: '' classVariableNames: 'Gates Held Learnt TimedOut Hearsay Released'.

GateAcceptor class >> setUp
  Gates := Atom on: Dictionary new.
  Held := Atom on: Dictionary new.
  Learnt := Atom on: Dictionary new.
  TimedOut := Atom on: 0.
  Hearsay := Atom on: Dictionary new.
  Released := Atom on: #().

"The milliseconds a held learning waits for its gate at most."
GateAcceptor class >> gateLimit
  ^ 20000.

GateAcceptor class >> _bump: anAtom at: anId
  anAtom swap: [:d | | copy | copy := d copy. copy at: anId put: (d at: anId ifAbsent: [0]) + 1. copy].

GateAcceptor class >> held: anId
  ^ Held value at: anId ifAbsent: [0].

GateAcceptor class >> learnt: anId
  ^ Learnt value at: anId ifAbsent: [0].

"How many held learnings went on because their gate expired."
GateAcceptor class >> timedOut
  ^ TimedOut value.

"Holds anId's next own-commit learning (and every one after it) until the gate opens."
GateAcceptor class >> close: anId
  Gates swap: [:d | | copy | copy := d copy. copy at: anId put: Future new. copy].

"Holds anId's learning of committed roots it neither accepts nor logs (what a recovery's answers
 teach) until openHearsay:, 20 s at most."
GateAcceptor class >> closeHearsay: anId
  Hearsay swap: [:d | | copy | copy := d copy. copy at: anId put: Future new. copy].

GateAcceptor class >> openHearsay: anId
  | old |
  old := Hearsay value at: anId ifAbsent: [nil].
  Hearsay swap: [:d | | copy | copy := d copy. copy removeKey: anId ifAbsent: [nil]. copy].
  old isNil ifFalse: [old resolve: true].

"Opens anId's gate for good."
GateAcceptor class >> open: anId
  | old |
  old := Gates value at: anId ifAbsent: [nil].
  Gates swap: [:d | | copy | copy := d copy. copy removeKey: anId ifAbsent: [nil]. copy].
  old isNil ifFalse: [old resolve: true].

"anEvent handed back to this acceptor (its actor) once aGate resolves, or after gateLimit (counted
 in TimedOut), whichever comes first: the acceptor goes on with the events behind it meanwhile, so
 a held learning never blocks another commit's acceptance. Held counts it under aKey."
GateAcceptor >> _defer: anEvent until: aGate as: aKey
  | done release |
  GateAcceptor _bump: Held at: aKey.
  done := Atom on: false.
  release := [:late | (done value: true ifCurrent: false) ifTrue: [
    late ifTrue: [TimedOut swap: [:n | n + 1]].
    Released swap: [:old | old copyWith: (self _keyOf: anEvent)].
    cells acceptor value handle: anEvent]].
  aGate thenDo: [:x | release value: false].
  (Future after: GateAcceptor gateLimit) thenDo: [:x | release value: true].
  ^ true.

"What names a learning released once (the actor may hand back a copy of the event)."
GateAcceptor >> _keyOf: aLearn
  ^ { cells config nodeId. aLearn isAccepted. aLearn root key }.

GateAcceptor >> handle: anEvent
  | gate result |
  ((anEvent isKindOf: PBLearnCommitted) and: [Released value includes: (self _keyOf: anEvent)]) ifTrue: [
    result := super handle: anEvent.
    anEvent isAccepted ifTrue: [GateAcceptor _bump: Learnt at: cells config nodeId].
    ^ result].
  ((anEvent isKindOf: PBLearnCommitted) and: [anEvent isAccepted not and: [anEvent isLogged not]]) ifTrue: [
    gate := Hearsay value at: cells config nodeId ifAbsent: [nil].
    gate isNil ifFalse: [^ self _defer: anEvent until: gate as: cells config nodeId , ' hearsay'].
    ^ super handle: anEvent].
  ((anEvent isKindOf: PBLearnCommitted) and: [anEvent isAccepted and: [anEvent isLogged
    and: [(SeamRound seamOf: cells config nodeId) hasBuilt: anEvent root]]]) ifFalse: [^ super handle: anEvent].
  gate := Gates value at: cells config nodeId ifAbsent: [nil].
  gate isNil ifFalse: [^ self _defer: anEvent until: gate as: cells config nodeId].
  result := super handle: anEvent.
  GateAcceptor _bump: Learnt at: cells config nodeId.
  ^ result.

GateAcceptor setUp.

"Once armed, drops the first two 'answer' messages sent to n0, noting who sent them (Dropped)."
PBInProcessTransport subclass: #DropEndpoint instanceVariableNames: '' classVariableNames: 'Armed Dropped'.

DropEndpoint class >> setUp
  Armed := Atom on: false.
  Dropped := Atom on: #().

DropEndpoint class >> arm
  Armed swap: [:x | true].

DropEndpoint class >> dropped
  ^ Dropped value.

DropEndpoint >> send: aMessage to: aNodeId
  | drop |
  drop := false.
  (Armed value and: [aNodeId = 'n0' and: [aMessage type = 'answer']]) ifTrue: [
    Dropped swap: [:d | drop := d size < 2. drop ifTrue: [d copyWith: aMessage from] ifFalse: [d]]].
  drop ifTrue: [^ self].
  ^ super send: aMessage to: aNodeId.

DropEndpoint setUp.

CommitKit subclass: #GateKit.

GateKit >> acceptorClass
  ^ GateAcceptor.

CommitKit subclass: #DropKit.

DropKit >> endpointFor: anId
  ^ DropEndpoint network: self network.

"=== the worker ================================================================"

Object subclass: #ReadWorker.

"aDatabase run: aBlock retries: 20: #ok, or the error's class name."
ReadWorker >> run: aBlock on: aDatabase
  ^ [aDatabase run: aBlock retries: 20. #ok] on: Error do: [:e | e return: e class name].

"aSpace newDatabase: aName: #ok, or the error's class name."
ReadWorker >> newDatabase: aName in: aSpace
  ^ [aSpace newDatabase: aName. #ok] on: Error do: [:e | e return: e class name].

"The record of a snapshot of aSpace (its _snapshotRecord): { #ok. record } or { #error. class name }."
ReadWorker >> snapshotOf: aSpace
  ^ [{ #ok. aSpace _snapshotRecord }] on: Error do: [:e | e return: { #error. e class name }].

"The counter of the database 'db' of aSpace, read by its first snapshot (Reads counterIn:)."
ReadWorker >> counterIn: aSpace
  ^ Reads counterIn: aSpace.

"=== helpers ==================================================================="

Object subclass: #Reads.

"The counter of aDatabase as a new transaction of it reads it."
Reads class >> counter: aDatabase
  | tr v |
  tr := aDatabase newTransaction.
  v := tr getRootObject: 'counter'.
  tr abort.
  ^ v.

"The counter of the database 'db' of aSpace, or the error's class name."
Reads class >> counterIn: aSpace
  ^ [self counter: (aSpace openDatabase: 'db')] on: Error do: [:e | e return: e class name].

"aString on stderr with the monotonic milliseconds: where a run is, never asserted."
Reads class >> step: aString
  [Stdio stderr nextPutAll: 'cluster_reads ' , Time millisecondClockValue printString , ' ' , aString; lf; flush] on: Error do: [:e | nil].

Reads class >> incr
  ^ [:t | t setRootObject: 'counter' value: (t getRootObject: 'counter') + 1].

"aDatabase run: incr, retried on PBConflictError and PBTimeoutError up to n times: #ok or the
 last error's class name."
Reads class >> run: aDatabase retries: n
  | last |
  1 to: n do: [:i |
    last := [aDatabase run: self incr retries: 20. nil] on: Error do: [:e | e return: e].
    last isNil ifTrue: [^ #ok].
    ((last isKindOf: PBConflictError) or: [last isKindOf: PBTimeoutError]) ifFalse: [^ last class name]].
  ^ last class name.

"The notes of SeamSpace after the first n that start with aPrefix."
Reads class >> notesAfter: n prefix: aPrefix
  | all |
  all := SeamSpace notes.
  ^ (all copyFrom: n + 1 to: all size) select: [:x | x beginsWith: aPrefix].

"The options of the read tests' kits, with acquireTimeout milliseconds."
Reads class >> options: acquire
  ^ Dictionary new at: #leaseDuration put: 1500; at: #driftMargin put: 1000; at: #requestTimeout put: 300;
    at: #acquireTimeout put: acquire; yourself.

"A kit of aClass (CommitKit or a subclass) of n0, n1 and n2 over aDirectory, whose waits end at
 20 s each."
Reads class >> kit: aClass dir: aDirectory acquire: milliseconds
  | kit |
  kit := aClass ids: #('n0' 'n1' 'n2') dir: aDirectory options: (self options: milliseconds).
  kit limit: 20000.
  ^ kit.

"The entry codes of the acceptor log at aRef (1 #accepted, 2 #committed, 3 #promise, 4 #rejoined)."
Reads class >> codesOf: aRef
  ^ (PBFramedLog read: aRef kind: PBAcceptorLog logKind) payloads collect: [:p | p at: 1].

"The acceptor log at aRef after a power loss: the #committed entries after its last synced entry
 are gone (an #accepted, #promise or #rejoined entry is synced before it answers, a #committed one
 is durable only with the next synced entry, R67). The file is renamed to aRef's name with
 aSuffix; a new log holds what survives. Answers the number of entries lost."
Reads class >> losePower: aRef suffix: aSuffix
  | payloads keep log |
  payloads := (PBFramedLog read: aRef kind: PBAcceptorLog logKind) payloads.
  keep := payloads size.
  [keep > 0 and: [((payloads at: keep) at: 1) = 2]] whileTrue: [keep := keep - 1].
  aRef renameTo: aRef basename , aSuffix.
  log := PBFramedLog openAppend: aRef kind: PBAcceptorLog logKind.
  [1 to: keep do: [:i | log append: (payloads at: i) sync: false]. log sync] ensure: [log close].
  ^ payloads size - keep.
