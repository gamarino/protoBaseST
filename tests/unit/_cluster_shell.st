"_cluster_shell.st: helpers of the coordinator shell's tests (a helper: the runner never runs
 files whose name starts with _).

  MemoryTier       a tier test double over an in-memory acceptor log (the payloads of
                   PBAcceptorLog encode:label:root:): loadRoots decodes them; every write is
                   recorded in a shared trace ('<id> append <kind> <label>'); a failing tier
                   signals PBUnexpectedError (a PBDBError, as a failed PBAcceptorLog write) on
                   every write (failing: true) or on the writes of the kinds it names (failing:
                   an Array of kinds). readPersisted answers nil, canRead: true.
  TracingEndpoint  a PBInProcessTransport that records each send in the trace ('<id> send
                   <type> to <peer>') before handing it on.
  ShellKit         a cluster of coordinators over one PBInProcessNetwork: ids, options, waits.
                   waitUntil:label: polls a condition (every 10 ms) with a deadline of 60 s and
                   answers whether it held: no test asserts a duration."
Import from: 'protobase'.

Object subclass: #MemoryTier instanceVariableNames: 'name payloads trace failing cache'.

MemoryTier class >> name: anId trace: aTraceAtom
  ^ self basicNew setName: anId payloads: (Atom on: #()) trace: aTraceAtom failing: false.

MemoryTier class >> name: anId trace: aTraceAtom failing: aBoolean
  ^ self basicNew setName: anId payloads: (Atom on: #()) trace: aTraceAtom failing: aBoolean.

"A tier over a log holding the rejoined marker (a member that served the cluster before)."
MemoryTier class >> served: anId trace: aTraceAtom
  ^ (self name: anId trace: aTraceAtom) addPayload: (PBAcceptorLog encode: #rejoined label: 0 root: nil); yourself.

MemoryTier >> setName: anId payloads: anAtom trace: aTraceAtom failing: aBoolean
  name := anId.
  payloads := anAtom.
  trace := aTraceAtom.
  failing := aBoolean.
  cache := Atom on: nil.

MemoryTier >> addPayload: aByteArray
  payloads swap: [:old | old , { aByteArray }].

MemoryTier >> payloads
  ^ payloads value.

MemoryTier >> note: aText
  trace swap: [:old | old , { name , ' ' , aText }].

MemoryTier >> write: aKind label: aLabel root: aRecord
  (failing == true or: [failing isArray and: [failing includes: aKind]]) ifTrue: [
    self note: 'failed ' , aKind.
    ^ PBUnexpectedError signal: 'Writing the root log of ' , name , ' failed: simulated disk failure'].
  self addPayload: (PBAcceptorLog encode: aKind label: aLabel root: aRecord).
  self note: 'append ' , aKind , ' ' , aLabel printString.

"The roots loaded, the same object while the payloads are unchanged (as a tier that caches
 what it loaded: the shell must build a fresh PBLoggedRoots at every attach, review N4)."
MemoryTier >> loadRoots
  | current hit |
  current := payloads value.
  hit := cache value.
  (hit notNil and: [hit first == current]) ifTrue: [^ hit last].
  hit := { current. PBAcceptorLog decode: current path: name }.
  cache value: hit ifCurrent: cache value.
  ^ hit last.

MemoryTier >> logAccepted: aLabeledRoot
  ^ self write: #accepted label: aLabeledRoot label root: aLabeledRoot record.

MemoryTier >> logCommitted: aLabeledRoot
  ^ self write: #committed label: aLabeledRoot label root: aLabeledRoot record.

MemoryTier >> logPromise: aTerm
  ^ self write: #promise label: aTerm root: nil.

MemoryTier >> logRejoined
  ^ self write: #rejoined label: 0 root: nil.

MemoryTier >> readPersisted
  ^ nil.

MemoryTier >> canRead: aLabeledRoot
  ^ true.

PBInProcessTransport subclass: #TracingEndpoint instanceVariableNames: 'trace'.

TracingEndpoint class >> network: aNetwork trace: aTraceAtom
  ^ (self network: aNetwork) setTrace: aTraceAtom.

TracingEndpoint >> setTrace: aTraceAtom
  trace := aTraceAtom.

TracingEndpoint >> send: aMessage to: aNodeId
  trace swap: [:old | old , { aMessage from , ' send ' , aMessage type , ' to ' , aNodeId
    , (aMessage type = 'ack' ifTrue: [' ok=' , (aMessage at: 'ok') printString] ifFalse: [''])
    , (aMessage type = 'answer' ifTrue: [' state=' , (aMessage at: 'state')] ifFalse: [''])
    , (aMessage type = 'reject' ifTrue: [' reason=' , (aMessage at: 'reason')] ifFalse: ['']) }].
  ^ super send: aMessage to: aNodeId.

Object subclass: #ShellKit instanceVariableNames: 'ids network trace peers'.

ShellKit class >> ids: anArray
  ^ self basicNew setIds: anArray.

ShellKit >> setIds: anArray
  ids := anArray.
  network := PBInProcessNetwork new.
  trace := Atom on: #().
  peers := (1 to: ids size) asArray collect: [:i | PBPeer nodeId: (ids at: i) host: '127.0.0.1' port: 7000 + i].

ShellKit >> ids
  ^ ids.

ShellKit >> network
  ^ network.

ShellKit >> trace
  ^ trace.

ShellKit >> peers
  ^ peers.

"Durations small enough for a test, every one explicit (no test depends on them but for liveness):
 leaseDuration 600 ms, driftMargin 400 ms, requestTimeout 100 ms, the default startupGrace
 (leaseDuration + driftMargin)."
ShellKit >> options
  ^ Dictionary new
    at: #leaseDuration put: 600; at: #driftMargin put: 400; at: #requestTimeout put: 100;
    at: #seed put: 7; yourself.

"A coordinator anId on this network (a TracingEndpoint), with extra options."
ShellKit >> node: anId options: aDictionary rules: aRules acceptorClass: aClass
  | o |
  o := self options.
  o at: #transport put: (TracingEndpoint network: network trace: trace).
  o at: #seed put: (ids indexOf: anId) + 7.
  aDictionary keysAndValuesDo: [:k :v | o at: k put: v].
  ^ PBClusterCoordinator nodeId: anId peers: peers options: o rules: aRules acceptorClass: aClass.

ShellKit >> node: anId
  ^ self node: anId options: Dictionary new rules: PBCoordinatorCore new acceptorClass: _PBAcceptor.

"Whether aBlock answers true within 60 s, polled every 10 ms."
ShellKit >> waitUntil: aBlock
  | deadline |
  deadline := Time millisecondClockValue + 60000.
  [aBlock value] whileFalse: [
    Time millisecondClockValue > deadline ifTrue: [^ false].
    (Future after: 10) wait].
  ^ true.

"The outcome of aFuture within 60 s: { #ok. value } or { #error. exception }."
ShellKit >> settle: aFuture
  ^ [{ #ok. aFuture waitWithin: 60000 }] on: Error do: [:e | { #error. e }].

"A root labelled aPermission's term, on aBase, epoch + 1, at offset anInteger."
ShellKit >> rootUnder: aPermission on: aBase offset: anInteger
  ^ PBLabeledRoot label: aPermission term
    record: (PBRootRecord segment: (ByteArray new: 16) offset: anInteger epoch: aBase epoch + 1).

"{ outcome of the commit. permission. root }: a permit, a base, a root replicated and done, on
 aCoordinator. outcome: #committed, #none, #unknown, or the class name of the error."
ShellKit >> commitOn: aCoordinator offset: anInteger
  | p base root r |
  p := self settle: aCoordinator _permit.
  p first = #ok ifFalse: [^ { (p at: 2) class name. nil. nil }].
  p := p at: 2.
  base := self settle: (aCoordinator _baseFor: p).
  base first = #ok ifFalse: [^ { (base at: 2) class name. p. nil }].
  base := base at: 2.
  root := self rootUnder: p on: base base offset: anInteger.
  r := self settle: (aCoordinator _replicate: root under: p).
  r first = #ok ifFalse: [^ { (r at: 2) class name. p. root }].
  (aCoordinator _done: p outcome: (r at: 2) root: ((r at: 2) = #committed ifTrue: [root] ifFalse: [nil])) wait.
  ^ { r at: 2. p. root }.

"Every coordinator of someCoordinators stopped (their Futures waited)."
ShellKit >> stopAll: someCoordinators
  someCoordinators do: [:n | n stop waitWithin: 60000].
