"_sim.st: the deterministic simulator of the cluster core (a helper: the runner never runs
 files whose name starts with _). Test support, not product (CC12).

  sim := PBSim seed: 11 ids: #('n0' 'n1' 'n2') rules: PBCoordinatorCore new options: Dictionary new.
  sim faults: (PBSimFaults drop: 1/10 duplicate: 1/20 delay: 2000 reorder: true).
  sim commit: 'a' at: 'n1'.
  sim runUntil: [(sim outcomeOf: 'a') ~= #pending] steps: 10000.
  sim converge: 10000.

Time. N nodes run the rules object (a PBCoordinatorCore, or a test subclass that plants a
defect: CC13) in one thread, in virtual time: an Integer of microseconds that only the
scheduler advances. Every node starts at time 0. Its clock (PBSimClock) runs at a rate from
the virtual time, and its rules see that clock as now; clockRate:rate: changes the rate from
the current virtual time on, continuously. Rate 0 pauses the clock: the node still takes
messages and acceptor steps, its now standing still. A timer (PBTimer after:) is kept with its
deadline on the node's clock, and every rate change re-derives the virtual time at which that
clock reaches it, so a timer always fires after its duration of the node's own clock; a timer
of a paused clock is not due until the clock runs again.

Scheduling. The scheduler holds the pending events (a dispatch, a timer, an acceptor step, its
sync, its reply, a delivery) and takes the earliest; it draws every choice (which of several
events due at once, a message's fate, a node's incarnation, a crash's unsynced tail) from one
Random seed: n, so one seed and one script give one trace, byte for byte. Nothing reads a wall
clock or sleeps.

The shell. The simulator is the shell of every node: it performs each effect (PBEffect
applyTo:).
  PBSend         is framed (PBClusterFrame, with the node's authKey) and delivered as a
                 PBReceived of the decoded message, unless the faults (PBSimFaults) drop it:
                 each copy is drawn on send (dropped with probability drop, sent twice with
                 probability duplicate, delayed by 0 to delay us; without reorder each link
                 keeps its order), or a partition separates the two nodes when it arrives. A
                 message is addressed to a node, not to an incarnation: one still in flight when
                 its receiver crashes is delivered to the receiver's next incarnation if it
                 arrives after the restart (more adversarial than a TCP connection, which the
                 crash would close): the rules must check incarnations (L12).
  PBToAcceptor   queues the event on the node's acceptor lane. The lane is serial, as
                 proto_db's (coordinator.py:1791, 'each step decides, makes its write durable,
                 publishes, then replies, in arrival order'): one step at a time, in arrival
                 order, each in three events: decide (the rules' step; its appends written to
                 the node's PBSimDisk), sync (through the last append that asks for one), reply
                 (the reply effects, then PBAcceptorDecided to the dispatcher); the next step of
                 the lane is decided only after that reply.
  PBTimer        comes due when the node's clock has advanced by its after (above).
  PBSettle       advances the synthetic transaction of its waiter: commit: aToken at: id asks
                 the node for a permission (PBPermitWanted), then for the base under it
                 (PBBaseWanted), builds a new root on that base (label the permission's term,
                 epoch the base's + 1, a fresh offset; its pred link is the base) and
                 replicates it (PBReplicateWanted). The replication's outcome is the commit's
                 (#committed: #acknowledged, #unknown, #none; anything else: #failed) and the
                 node gets it as a PBDoneReport.
  PBPublishCommitted sets the root the node's readers see; PBPublishAcceptor and PBFence are
                 recorded by their trace lines.

Crashes. crash: id unsynced: aMode stops a node at once: its pending events and its acceptor
lane are dropped (messages already sent stay in flight). The synced entries of its disk
survive; the unsynced tail is, by aMode: #drop, all lost (power loss); #keep, all kept (a
process crash: the page cache reaches the disk); #prefix, a prefix of a length drawn from the
seed kept (a power loss during write-back); #any, one of the three drawn from the seed. What
survives counts as synced afterwards. A crash between an acceptor step's sync and its reply
leaves the entry durable and the reply never sent. crash: id keepDisk: true is the #drop crash
(the brief's); keepDisk: false loses the whole disk. tearLog: id cuts the last synced frame of a
crashed node's log (a torn tail). restart: id starts it again, with a new incarnation, over
what its disk holds.

The checker. PBSimChecker runs after every step: at most one owner of a term (S1: an ownership
seen in any node's state, by node and incarnation); two different roots with equal (label,
epoch) appended, published or sent anywhere; an acceptor reply performed before every entry the
node's acceptor asked to sync so far is synced. checkConverged (converge:): the committed
chains of the live nodes (from each one's published committed root through the pred links of
the roots the simulator built) do not fork (of two heads, one is in the other's chain); every
acknowledged commit is in every live node's chain (S4); every unknown commit in every live
node's chain or in none; a commit answered #none in no chain (H7). A violation is an Error
whose text holds the seed and the last 200 trace lines."

Import from: 'protobase'.

"=== PBSimFaults ============================================================="

Object subclass: #PBSimFaults instanceVariableNames: 'drop duplicate delay reorder'.

"Each message copy is dropped with probability p (a Number in [0, 1]), sent twice with
 probability q, delayed by 0 to maxMicros us; reorder: false keeps each link in order."
PBSimFaults class >> drop: p duplicate: q delay: maxMicros reorder: aBoolean
  ((p between: 0 and: 1) and: [(q between: 0 and: 1) and: [maxMicros isInteger and: [maxMicros >= 0]]]) ifFalse: [
    ^ Error signal: 'PBSimFaults: probabilities in [0, 1] and a delay >= 0 of microseconds'].
  ^ self basicNew setDrop: p duplicate: q delay: maxMicros reorder: aBoolean.

PBSimFaults class >> none
  ^ self drop: 0 duplicate: 0 delay: 0 reorder: false.

PBSimFaults >> setDrop: p duplicate: q delay: maxMicros reorder: aBoolean
  drop := p.
  duplicate := q.
  delay := maxMicros.
  reorder := aBoolean.

PBSimFaults >> drop
  ^ drop.

PBSimFaults >> duplicate
  ^ duplicate.

PBSimFaults >> delay
  ^ delay.

PBSimFaults >> reorder
  ^ reorder.

"=== PBSimClock =============================================================="

"A node's clock: from the virtual time originGlobal, when it read originLocal, it runs at rate
 (0: paused)."
Object subclass: #PBSimClock instanceVariableNames: 'rate originGlobal originLocal'.

PBSimClock class >> rate: aNumber global: g local: l
  ((aNumber isKindOf: Number) and: [aNumber >= 0]) ifFalse: [^ Error signal: 'PBSimClock: a rate is a Number >= 0'].
  ^ self basicNew setRate: aNumber global: g local: l.

PBSimClock >> setRate: aNumber global: g local: l
  rate := aNumber.
  originGlobal := g.
  originLocal := l.

"The node's clock (microseconds) at the virtual time g (>= originGlobal)."
PBSimClock >> localAt: g
  ^ originLocal + ((g - originGlobal) * rate) floor.

"The earliest virtual time, not before originGlobal, at which the clock reads aLocal or more;
 nil when a paused clock never will."
PBSimClock >> globalAt: aLocal
  aLocal <= originLocal ifTrue: [^ originGlobal].
  rate = 0 ifTrue: [^ nil].
  ^ originGlobal + (aLocal - originLocal / rate) ceiling.

"This clock running at aNumber from the virtual time g on, continuous at g."
PBSimClock >> rate: aNumber at: g
  ^ self class rate: aNumber global: g local: (self localAt: g).

"=== PBSimDisk ==============================================================="

"The acceptor log of one node: its entries (41-byte payloads, PBAcceptorLog encode:label:root:)
 in order, of which the first syncedSize are synced."
Object subclass: #PBSimDisk instanceVariableNames: 'name entries synced'.

PBSimDisk class >> named: aName
  ^ self basicNew setName: aName.

PBSimDisk >> setName: aName
  name := aName.
  entries := OrderedCollection new.
  synced := 0.

"Writes aPayload, not synced; answers its index (from 1)."
PBSimDisk >> append: aPayload
  entries add: aPayload.
  ^ entries size.

"Syncs every entry up to anIndex (an fsync makes everything written before it durable)."
PBSimDisk >> syncThrough: anIndex
  synced := synced max: anIndex.

PBSimDisk >> size
  ^ entries size.

PBSimDisk >> syncedSize
  ^ synced.

PBSimDisk >> unsyncedSize
  ^ entries size - synced.

"A crash: the first n unsynced entries survive (and count as synced), the rest are gone."
PBSimDisk >> keepUnsynced: n
  [entries size > (synced + n)] whileTrue: [entries removeLast].
  synced := entries size.

"A torn tail: the last synced frame is cut."
PBSimDisk >> tear
  self keepUnsynced: 0.
  synced = 0 ifTrue: [^ Error signal: 'PBSimDisk ' , name , ': no synced frame to tear'].
  entries removeLast.
  synced := synced - 1.

"A lost disk."
PBSimDisk >> wipe
  entries := OrderedCollection new.
  synced := 0.

"What a load of the log reads now (PBAcceptorLog decode:path:)."
PBSimDisk >> loggedRoots
  ^ PBAcceptorLog decode: entries asArray path: 'sim:' , name.

"=== PBSimNode ==============================================================="

"One simulated node: its configuration, clock and disk survive a crash; the rest is its
 incarnation's. lane: the acceptor events not yet decided; laneBusy: a step is between its
 decision and its reply; owed: the last disk entry the acceptor asked to sync."
Object subclass: #PBSimNode instanceVariableNames: 'config clock disk up gen state acceptor committed lane laneBusy owed'.

PBSimNode class >> config: aConfig
  ^ self basicNew setConfig: aConfig.

PBSimNode >> setConfig: aConfig
  config := aConfig.
  clock := PBSimClock rate: 1 global: 0 local: 0.
  disk := PBSimDisk named: aConfig nodeId.
  up := false.
  gen := 0.
  lane := OrderedCollection new.
  laneBusy := false.
  owed := 0.

PBSimNode >> id
  ^ config nodeId.

PBSimNode >> config
  ^ config.

PBSimNode >> clock
  ^ clock.

PBSimNode >> clock: aClock
  clock := aClock.

PBSimNode >> disk
  ^ disk.

PBSimNode >> isUp
  ^ up.

PBSimNode >> gen
  ^ gen.

PBSimNode >> state
  ^ state.

PBSimNode >> state: aNodeState
  state := aNodeState.

PBSimNode >> acceptor
  ^ acceptor.

PBSimNode >> acceptor: anAcceptorState
  acceptor := anAcceptorState.

PBSimNode >> committed
  ^ committed.

PBSimNode >> committed: aRoot
  committed := aRoot.

PBSimNode >> lane
  ^ lane.

PBSimNode >> isLaneBusy
  ^ laneBusy.

PBSimNode >> laneBusy: aBoolean
  laneBusy := aBoolean.

PBSimNode >> owed
  ^ owed.

PBSimNode >> owe: anIndex
  owed := owed max: anIndex.

"A new incarnation: up, with these states, an empty lane."
PBSimNode >> startState: aNodeState acceptor: anAcceptorState
  gen := gen + 1.
  up := true.
  state := aNodeState.
  acceptor := anAcceptorState.
  lane := OrderedCollection new.
  laneBusy := false.
  owed := 0.

PBSimNode >> crash
  up := false.
  state := nil.
  acceptor := nil.
  committed := nil.
  lane := OrderedCollection new.
  laneBusy := false.

"The 16 segment bytes of the roots this node builds."
PBSimNode >> segment
  ^ ByteArray withAll: ((1 to: 16) asArray collect: [:i | i = 16 ifTrue: [config rank + 1] ifFalse: [0]]).

"=== PBSimChecker ============================================================"

Object subclass: #PBSimChecker instanceVariableNames: 'sim owners roots rootFields'.

PBSimChecker class >> sim: aSim
  ^ self basicNew setSim: aSim.

PBSimChecker >> setSim: aSim
  sim := aSim.
  owners := Dictionary new.
  roots := Dictionary new.
  rootFields := Dictionary new.
  PBClusterMessage schema keysAndValuesDo: [:type :fields |
    rootFields at: type put: ((fields select: [:f | f value = #root]) collect: [:f | f key])].

"An Error whose text holds the seed, aText and the last 200 trace lines."
PBSimChecker >> fail: aText
  ^ sim fail: aText.

"After every step: at most one owner of each term (S1)."
PBSimChecker >> check
  sim ids do: [:id |
    | node term who prior |
    node := sim nodeAt: id.
    (node isUp and: [node state ownership notNil]) ifTrue: [
      term := node state ownership term.
      who := id , ' inc ' , node state inc printString.
      prior := owners at: term ifAbsent: [nil].
      prior isNil
        ifTrue: [owners at: term put: who]
        ifFalse: [prior = who ifFalse: [
          self fail: 'S1: term ' , term printString , ' is owned by ' , prior , ' and by ' , who]]]].

"aRoot (a PBLabeledRoot or nil) was appended, published or sent: no other root may carry its
 label and epoch."
PBSimChecker >> noteRoot: aRoot
  | labelEpoch key prior |
  aRoot isNil ifTrue: [^ self].
  labelEpoch := aRoot label printString , '/' , aRoot epoch printString.
  key := sim keyText: aRoot.
  prior := roots at: labelEpoch ifAbsent: [nil].
  prior isNil ifTrue: [^ roots at: labelEpoch put: key].
  prior = key ifFalse: [
    self fail: 'two different roots carry label ' , aRoot label printString , ' and epoch ' , aRoot epoch printString
      , ': ' , prior , ' and ' , key].

PBSimChecker >> noteAppend: aLogAppend
  (aLogAppend kind = #accepted or: [aLogAppend kind = #committed]) ifTrue: [
    self noteRoot: (PBLabeledRoot label: aLogAppend label record: aLogAppend root)].

PBSimChecker >> noteMessage: aMessage
  (rootFields at: aMessage type) do: [:field | self noteRoot: (PBClusterMessage rootFrom: (aMessage at: field))].

"aNode performs an acceptor reply: every entry its acceptor asked to sync so far must be synced."
PBSimChecker >> replyAt: aNode
  aNode disk syncedSize < aNode owed ifTrue: [
    self fail: aNode id , ' performed an acceptor reply before its append is synced (entry ' , aNode owed printString
      , ', synced through ' , aNode disk syncedSize printString , ')'].

"At convergence: no fork, S4, the unknown commits and H7."
PBSimChecker >> checkConverged
  | live chains |
  live := sim ids select: [:id | (sim nodeAt: id) isUp].
  chains := live collect: [:id | sim committedChainOf: id].
  1 to: live size do: [:i |
    i + 1 to: live size do: [:j |
      | hi hj |
      hi := (sim nodeAt: (live at: i)) committed.
      hj := (sim nodeAt: (live at: j)) committed.
      (hi notNil and: [hj notNil and: [((chains at: j) includes: (sim keyText: hi)) not
          and: [((chains at: i) includes: (sim keyText: hj)) not]]]) ifTrue: [
        self fail: 'fork: the committed chains of ' , (live at: i) , ' (' , (sim keyText: hi) , ') and '
          , (live at: j) , ' (' , (sim keyText: hj) , ') diverge']]].
  sim commitOrder do: [:token |
    | status root key holders |
    status := sim outcomeOf: token.
    root := sim rootOf: token.
    key := root isNil ifTrue: [nil] ifFalse: [sim keyText: root].
    holders := (1 to: live size) asArray select: [:i | key notNil and: [(chains at: i) includes: key]].
    status = #acknowledged ifTrue: [
      (1 to: live size) do: [:i | (holders includes: i) ifFalse: [
        self fail: 'S4: the acknowledged commit ' , token printString , ' (' , key , ') is not in the committed chain of '
          , (live at: i)]]].
    (status = #unknown and: [holders notEmpty and: [holders size < live size]]) ifTrue: [
      self fail: 'the unknown commit ' , token printString , ' is in the committed chain of '
        , (holders collect: [:i | live at: i]) printString , ' only'].
    (status = #none and: [holders notEmpty]) ifTrue: [
      self fail: 'H7: the commit ' , token printString , ' answered none is in the committed chain of '
        , (holders collect: [:i | live at: i]) printString]].

"=== PBSim ==================================================================="

Object subclass: #PBSim instanceVariableNames: 'seed random rules ids nodes queue now faults groups links lines checker commits commitOrder commitRoots preds offsets current'.

"N nodes (anArray of ids) running aRules, each configured with aDictionary (PBClusterConfig
 options), all started at virtual time 0, every choice drawn from Random seed: n."
PBSim class >> seed: n ids: anArray rules: aRules options: aDictionary
  ^ self basicNew setSeed: n ids: anArray rules: aRules options: aDictionary.

PBSim >> setSeed: n ids: anArray rules: aRules options: aDictionary
  | peers |
  seed := n.
  "Park-Miller's first draws of nearby small seeds are small and alike: the seed is spread
   over the generator's range and the first draws are discarded."
  random := Random seed: n * 48271 + 1013904223.
  16 timesRepeat: [random next].
  rules := aRules.
  ids := anArray asArray.
  peers := (1 to: ids size) asArray collect: [:i | PBPeer nodeId: (ids at: i) host: '127.0.0.1' port: 7000 + i].
  nodes := Dictionary new.
  ids do: [:id | nodes at: id put: (PBSimNode config: (PBClusterConfig nodeId: id peers: peers options: aDictionary))].
  queue := OrderedCollection new.
  now := 0.
  faults := PBSimFaults none.
  links := Dictionary new.
  lines := OrderedCollection new.
  checker := PBSimChecker sim: self.
  commits := Dictionary new.
  commitOrder := OrderedCollection new.
  commitRoots := Dictionary new.
  preds := Dictionary new.
  offsets := 0.
  ids do: [:id | self _start: (nodes at: id)].

"--- accessors ---"

PBSim >> ids
  ^ ids.

PBSim >> nodeAt: anId
  ^ nodes at: anId ifAbsent: [Error signal: 'PBSim: no node ' , anId printString].

PBSim >> diskOf: anId
  ^ (self nodeAt: anId) disk.

PBSim >> checker
  ^ checker.

"The trace lines, a fresh Array."
PBSim >> trace
  ^ lines asArray.

"#pending, #acknowledged, #unknown, #none or #failed; nil for a token never committed."
PBSim >> outcomeOf: aToken
  ^ commits at: aToken ifAbsent: [nil].

"The root built for aToken, nil while none is."
PBSim >> rootOf: aToken
  ^ commitRoots at: aToken ifAbsent: [nil].

PBSim >> commitOrder
  ^ commitOrder asArray.

"The text of the ordering key of aRoot (PBLabeledRoot key)."
PBSim >> keyText: aRoot
  | k |
  k := aRoot key.
  ^ (k at: 1) printString , '/' , (k at: 2) printString , '/' , (k at: 3) hex asLowercase , '/' , (k at: 4) printString.

"The keys of the roots of anId's committed chain: its published committed root and every root
 before it through the pred links of the roots the simulator built."
PBSim >> committedChainOf: anId
  | chain key |
  chain := Set new.
  (self nodeAt: anId) committed isNil ifTrue: [^ chain].
  key := self keyText: (self nodeAt: anId) committed.
  [key notNil and: [(chain includes: key) not]] whileTrue: [
    chain add: key.
    key := preds at: key ifAbsent: [nil]].
  ^ chain.

PBSim >> fail: aText
  | text |
  self _trace: 'VIOLATION ' , aText.
  text := WriteStream on: String new.
  text nextPutAll: 'PBSim seed '; print: seed; nextPutAll: ': '; nextPutAll: aText; nextPut: Character lf;
    nextPutAll: 'last trace lines:'.
  ((lines size - 199) max: 1) to: lines size do: [:i | text nextPut: Character lf; nextPutAll: (lines at: i)].
  ^ Error signal: text contents.

"--- the script ---"

PBSim >> faults: aFaults
  faults := aFaults.

"anArray of groups of ids (every id in exactly one): a message between two groups is lost when
 it arrives."
PBSim >> partition: anArray
  | all |
  all := OrderedCollection new.
  anArray do: [:group | all addAll: group].
  (all size = ids size and: [ids allSatisfy: [:id | all includes: id]]) ifFalse: [
    ^ Error signal: 'PBSim partition: every node in exactly one group'].
  groups := anArray collect: [:group | group asArray].
  self _trace: 'partition ' , groups printString.

PBSim >> heal
  groups := nil.
  self _trace: 'heal'.

"anId's clock runs at aNumber (>= 0; 0 pauses it) from now on; its pending timers move to the
 virtual time at which the clock reaches their deadlines."
PBSim >> clockRate: anId rate: aNumber
  | node |
  node := self nodeAt: anId.
  node clock: (node clock rate: aNumber at: now).
  queue do: [:e |
    ((e at: 2) = #timer and: [(e at: 3) = anId]) ifTrue: [
      e at: 1 put: (node clock globalAt: ((e at: 5) at: 1))]].
  self _trace: anId , ' clock rate ' , aNumber printString.

"A crash of anId: aMode (#drop, #keep, #prefix or #any) decides the unsynced tail of its disk."
PBSim >> crash: anId unsynced: aMode
  | node mode tail kept |
  node := self nodeAt: anId.
  node isUp ifFalse: [^ Error signal: 'PBSim: ' , anId , ' is not running'].
  (#(#drop #keep #prefix #any) includes: aMode) ifFalse: [
    ^ Error signal: 'PBSim crash:unsynced: #drop, #keep, #prefix or #any, not ' , aMode printString].
  mode := aMode = #any ifTrue: [#(#drop #keep #prefix) at: (random nextInt: 3)] ifFalse: [aMode].
  tail := node disk unsyncedSize.
  kept := mode = #drop
    ifTrue: [0]
    ifFalse: [mode = #keep ifTrue: [tail] ifFalse: [(random nextInt: tail + 1) - 1]].
  node crash.
  node disk keepUnsynced: kept.
  self _trace: anId , ' crash (' , mode , '), ' , kept printString , ' of ' , tail printString , ' unsynced entries kept'.

"keepDisk: true is the #drop crash (power loss); false loses the whole disk."
PBSim >> crash: anId keepDisk: aBoolean
  aBoolean ifTrue: [^ self crash: anId unsynced: #drop].
  self crash: anId unsynced: #drop.
  (self nodeAt: anId) disk wipe.
  self _trace: anId , ' disk lost'.

PBSim >> restart: anId
  | node |
  node := self nodeAt: anId.
  node isUp ifTrue: [^ Error signal: 'PBSim: ' , anId , ' is running'].
  self _start: node.

PBSim >> tearLog: anId
  | node |
  node := self nodeAt: anId.
  node isUp ifTrue: [^ Error signal: 'PBSim: tearLog: a crashed node, not the running ' , anId].
  node disk tear.
  self _trace: anId , ' log torn'.

"A synthetic transaction aToken (a new token) at the running node anId."
PBSim >> commit: aToken at: anId
  | node |
  node := self nodeAt: anId.
  node isUp ifFalse: [^ Error signal: 'PBSim: ' , anId , ' is not running'].
  (commits includesKey: aToken) ifTrue: [^ Error signal: 'PBSim: the token ' , aToken printString , ' is taken'].
  commits at: aToken put: #pending.
  commitOrder add: aToken.
  self _trace: anId , ' commit ' , aToken printString.
  self _schedule: #dispatch node: node payload: (PBPermitWanted waiter: { 'permit'. aToken }) at: now.

"Runs the earliest due event (one of those due at once, drawn), then the checker; false when
 nothing is due (the queue is empty, or holds only timers of paused clocks)."
PBSim >> step
  | best due event |
  best := nil.
  queue do: [:e | ((e at: 1) notNil and: [best isNil or: [(e at: 1) < best]]) ifTrue: [best := e at: 1]].
  best isNil ifTrue: [^ false].
  due := queue select: [:e | (e at: 1) = best].
  event := due size = 1 ifTrue: [due first] ifFalse: [due at: (random nextInt: due size)].
  queue := queue reject: [:e | e == event].
  now := best.
  self _run: event.
  checker check.
  ^ true.

"Steps until aBlock answers true (checked before each step) or n steps ran; answers aBlock's
 last value."
PBSim >> runUntil: aBlock steps: n
  n timesRepeat: [
    aBlock value ifTrue: [^ true].
    self step ifFalse: [^ aBlock value]].
  ^ aBlock value.

"Heals the network, ends the faults, runs until the queue is empty or n steps ran, then checks
 the committed chains (checkConverged). Answers whether the queue emptied: false means the
 checks ran on a cluster still busy."
PBSim >> converge: n
  | quiet |
  self heal.
  faults := PBSimFaults none.
  quiet := self runUntil: [queue isEmpty] steps: n.
  self _trace: (quiet ifTrue: ['converge: quiet'] ifFalse: ['converge: still busy after ' , n printString , ' steps']).
  checker checkConverged.
  ^ quiet.

"--- the scheduler ---"

PBSim >> _trace: aText
  lines add: 't=' , now printString , ' ' , aText.

"A queue entry { at (nil: not due). kind. node id. incarnation gen. payload }: an Array the
 rate changes of #timer entries update in place."
PBSim >> _schedule: aKind node: aNode payload: aPayload at: aTime
  queue add: (Array with: aTime with: aKind with: aNode id with: aNode gen with: aPayload).

PBSim >> _start: aNode
  | inc |
  inc := random nextInt: 1073741823.
  aNode startState: (PBNodeState config: aNode config inc: inc)
    acceptor: (PBAcceptorState config: aNode config logged: aNode disk loggedRoots now: (aNode clock localAt: now)).
  self _trace: aNode id , ' start inc ' , inc printString.
  self _schedule: #dispatch node: aNode payload: PBStartNode new at: now.

PBSim >> _run: anEvent
  | kind node payload |
  kind := anEvent at: 2.
  node := self nodeAt: (anEvent at: 3).
  payload := anEvent at: 5.
  kind = #deliver ifTrue: [^ self _deliver: payload to: node].
  (node isUp and: [node gen = (anEvent at: 4)]) ifFalse: [
    ^ self _trace: node id , ' gone, dropped ' , kind , ' ' , payload printString].
  kind = #dispatch ifTrue: [^ self _dispatch: payload at: node].
  kind = #timer ifTrue: [^ self _dispatch: (payload at: 2) at: node].
  kind = #accept ifTrue: [^ self _accept: node lane removeFirst at: node].
  kind = #sync ifTrue: [^ self _syncThrough: (payload at: 1) step: (payload at: 2) at: node].
  kind = #reply ifTrue: [^ self _reply: (payload at: 2) at: node syncedThrough: (payload at: 1)].
  ^ Error signal: 'PBSim: unknown event kind ' , kind printString.

PBSim >> _dispatch: anEvent at: aNode
  | step local |
  local := aNode clock localAt: now.
  self _trace: aNode id , ' dispatch ' , anEvent printString , ' [clock ' , local printString , ']'.
  step := rules dispatch: anEvent in: aNode state now: local.
  aNode state: step state.
  self _apply: step effects at: aNode.

"Decides the next step of aNode's lane only when no step is between its decision and its reply."
PBSim >> _runLane: aNode
  (aNode isLaneBusy or: [aNode lane isEmpty]) ifTrue: [^ self].
  aNode laneBusy: true.
  self _schedule: #accept node: aNode payload: nil at: now.

PBSim >> _accept: anEvent at: aNode
  | step last |
  self _trace: aNode id , ' accept ' , anEvent printString.
  step := rules accept: anEvent in: aNode acceptor now: (aNode clock localAt: now).
  aNode acceptor: step state.
  last := 0.
  step appends do: [:append |
    | index |
    index := aNode disk append: append payload.
    self _trace: aNode id , '   append ' , append printString.
    checker noteAppend: append.
    append sync ifTrue: [last := index]].
  aNode owe: last.
  self _schedule: #sync node: aNode payload: { last. step } at: now.

"The sync of an acceptor step: the disk through anIndex; the reply is the next event."
PBSim >> _syncThrough: anIndex step: aStep at: aNode
  aNode disk syncThrough: anIndex.
  self _trace: aNode id , ' synced through ' , anIndex printString.
  self _schedule: #reply node: aNode payload: { anIndex. aStep } at: now.

PBSim >> _reply: aStep at: aNode syncedThrough: anIndex
  self _trace: aNode id , ' reply'.
  checker replyAt: aNode.
  self _apply: aStep reply at: aNode.
  self _schedule: #dispatch node: aNode payload: (PBAcceptorDecided step: aStep) at: now.
  aNode laneBusy: false.
  self _runLane: aNode.

PBSim >> _apply: anArray at: aNode
  current := aNode.
  anArray do: [:effect |
    self _trace: aNode id , '   -> ' , effect printString.
    effect applyTo: self].

PBSim >> _partitioned: a from: b
  groups isNil ifTrue: [^ false].
  ^ (groups anySatisfy: [:group | (group includes: a) and: [group includes: b]]) not.

PBSim >> _deliver: aPayload to: aNode
  | from text |
  from := aPayload at: 1.
  text := from , ' -> ' , aNode id , ' ' , (aPayload at: 3).
  (self _partitioned: from from: aNode id) ifTrue: [^ self _trace: 'lost ' , text , ' (partition)'].
  aNode isUp ifFalse: [^ self _trace: 'lost ' , text , ' (' , aNode id , ' down)'].
  self _trace: aNode id , ' <- ' , from , ' ' , (aPayload at: 3).
  self _dispatch: (PBReceived message: (PBClusterFrame decode: (aPayload at: 2) to: aNode id key: aNode config authKey)) at: aNode.

"--- the shell: one apply message per effect kind ---"

PBSim >> applySend: aSend
  | to bytes link copies |
  to := self nodeAt: aSend to.
  to == current ifTrue: [^ Error signal: 'PBSim: ' , current id , ' sends to itself (CC1: its own acceptor takes a PBToAcceptor)'].
  checker noteMessage: aSend message.
  bytes := PBClusterFrame encode: aSend message to: to id key: current config authKey.
  link := current id , '>' , to id.
  (faults drop > 0 and: [random next < faults drop]) ifTrue: [
    ^ self _trace: 'lost ' , current id , ' -> ' , to id , ' ' , aSend message type , ' (dropped)'].
  copies := (faults duplicate > 0 and: [random next < faults duplicate]) ifTrue: [2] ifFalse: [1].
  copies timesRepeat: [
    | at |
    at := now + (faults delay > 0 ifTrue: [random between: 0 and: faults delay] ifFalse: [0]).
    faults reorder ifFalse: [
      at := at max: (links at: link ifAbsent: [-1]) + 1.
      links at: link put: at].
    self _schedule: #deliver node: to payload: { current id. bytes. aSend message type } at: at].

PBSim >> applyToAcceptor: aToAcceptor
  current lane addLast: aToAcceptor event.
  self _runLane: current.

"A timer keeps its deadline on the node's clock (clockRate:rate: moves it in virtual time)."
PBSim >> applyTimer: aTimer
  | deadline |
  deadline := (current clock localAt: now) + aTimer after.
  self _schedule: #timer node: current payload: { deadline. aTimer fired } at: (current clock globalAt: deadline).

PBSim >> applySettle: aSettle
  self _settle: aSettle waiter outcome: aSettle outcome at: current.

PBSim >> applyPublishCommitted: aPublish
  checker noteRoot: aPublish root.
  current committed: aPublish root.

"The acceptor snapshot and the fence are what a shell publishes for readers and refuses
 commits by: their trace line (_apply:at:) is the simulator's record of them."
PBSim >> applyPublishAcceptor: aPublish
  ^ self.

PBSim >> applyFence: aFence
  ^ self.

"--- the synthetic transactions ---"

PBSim >> _settle: aWaiter outcome: anOutcome at: aNode
  | stage token permission |
  (aWaiter isArray and: [aWaiter size >= 2 and: [commits includesKey: (aWaiter at: 2)]]) ifFalse: [
    ^ Error signal: 'PBSim: settled an unknown waiter ' , aWaiter printString].
  stage := aWaiter at: 1.
  token := aWaiter at: 2.
  stage = 'permit' ifTrue: [
    (anOutcome isKindOf: PBPermission) ifFalse: [^ self _end: token as: #failed].
    ^ self _schedule: #dispatch node: aNode
      payload: (PBBaseWanted permission: anOutcome waiter: { 'base'. token. anOutcome }) at: now].
  permission := aWaiter at: 3.
  stage = 'base' ifTrue: [
    | root |
    (anOutcome isKindOf: PBLabeledRoot) ifFalse: [^ self _end: token as: #failed].
    offsets := offsets + 1.
    root := PBLabeledRoot label: permission term
      record: (PBRootRecord segment: aNode segment offset: offsets epoch: anOutcome epoch + 1).
    preds at: (self keyText: root) put: (self keyText: anOutcome).
    commitRoots at: token put: root.
    self _trace: aNode id , ' built ' , (PBCoreValue textOf: root) , ' on ' , (PBCoreValue textOf: anOutcome)
      , ' for ' , token printString.
    ^ self _schedule: #dispatch node: aNode
      payload: (PBReplicateWanted permission: permission root: root waiter: { 'replicate'. token. permission }) at: now].
  stage = 'replicate' ifTrue: [
    self _end: token as: ((PBDoneReport outcomes includes: anOutcome)
      ifTrue: [anOutcome = #committed ifTrue: [#acknowledged] ifFalse: [anOutcome]]
      ifFalse: [#failed]).
    ^ self _schedule: #dispatch node: aNode
      payload: (PBDoneReport permission: permission
        outcome: ((PBDoneReport outcomes includes: anOutcome) ifTrue: [anOutcome] ifFalse: [#none])) at: now].
  ^ Error signal: 'PBSim: settled an unknown waiter ' , aWaiter printString.

PBSim >> _end: aToken as: aStatus
  commits at: aToken put: aStatus.
  self _trace: 'commit ' , aToken printString , ' ' , aStatus.
