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
                 the node's PBSimDisk), sync (through the last append that asks for one; it
                 takes syncCost: microseconds of virtual time when the step asks for a sync,
                 none by default), reply (the reply effects, then PBAcceptorDecided to the
                 dispatcher); the next step of the lane is decided only after that reply.
  PBTimer        comes due when the node's clock has advanced by its after (above).
  PBSettle       advances the synthetic transaction of its waiter: commit: aToken at: id asks
                 the node for a permission (PBPermitWanted), then for the base under it
                 (PBBaseWanted, settled with a PBBaseDecision or an error), builds a new root on
                 that base (label the permission's term, epoch the base's + 1, or + epochStep:at:,
                 a fresh offset; its pred link is the base) and replicates it
                 (PBReplicateWanted). The replication's outcome is the commit's (#committed:
                 #acknowledged, #unknown, #none; anything else: #failed) and the node gets it as
                 a PBDoneReport (with the built root when #committed). A decision that needs a
                 commit first replicates an unchanged root on the base (label the term, epoch the
                 base's + 1, proto_db _commit_base) and, once it is #committed, builds the
                 commit's root on it; any other outcome of it is the commit's. A #stale decision
                 reports #unknown and asks for a permission again (the round requeues, D50); an
                 #unreachable one reports #unknown and ends the commit #none (a retryable
                 conflict, nothing sent, R133); an error reports #none and ends the commit #none
                 (a PBConflictError) or #failed.
  PBReadPersisted is answered at once with PBStorageRead token: root: (the persisted root of the
                 shared storage, persist:, nil until one is set) failure: nil.
  PBProbeRoot    is answered at once with PBRootProbed token: readable: (false for a root the
                 node's PBSimDisk was told it cannot read, unreadable:).
  PBPublishCommitted sets the root the node's readers see; PBPublishAcceptor and PBFence are
                 recorded by their trace lines; PBCount adds one to the node's counter
                 (countOf:at:).

Script. inject: aMessage to: anId at: aTime delivers a message as if its sender had sent it
(framed with the sender's key; the faults apply), to drive the acceptors without a proposer.
delay: fromId to: toId by: someMicros adds a fixed delay to every message of that link sent
from then on.
seed:ids:rules:options:logs: starts each node over a synced log (id -> an Array of
PBLogAppend), as a member of a cluster formed before. failAppends: anId makes every later
append of that node's acceptor fail: the step is discarded (the acceptor keeps its state before
it; nothing written, synced or replied), the acceptor takes PBAppendFailed before the next
event of its lane, and the dispatcher takes PBAcceptorDiscarded with the step.

Crashes. crash: id unsynced: aMode stops a node at once: its pending events and its acceptor
lane are dropped (messages already sent stay in flight). The synced entries of its disk
survive; the unsynced tail is, by aMode: #drop, all lost (power loss); #keep, all kept (a
process crash: the page cache reaches the disk); #prefix, a prefix of a length drawn from the
seed kept (a power loss during write-back); #any, one of the three drawn from the seed. What
survives counts as synced afterwards. A crash between an acceptor step's sync and its reply
leaves the entry durable and the reply never sent. crash: id keepDisk: true is the #drop crash
(the brief's); keepDisk: false loses the whole disk. tearLog: id cuts the last synced frame of a
crashed node's log (a torn tail). restart: id starts it again, with a new incarnation, over
what its disk holds. reconfigure: id options: aDictionary gives a crashed node other options
(its peers kept: another voter set, another startup grace) for its next restart.

Pauses. pause: id freezes a node's process (a VM or process stop): its clock stands still and
none of its events runs (deliveries, timers, acceptor steps wait; messages to it queue). resume:
id restarts its clock at the rate it had and runs what waited, in order, from now on. A crash
resumes a paused node first; clockRate: refuses a paused node. (A clock at rate 0 stays the
clock-skew model: the node still runs, its time does not advance.)

The checker. PBSimChecker runs after every step: at most one owner of a term (S1: an ownership
seen in any node's state, by node and incarnation); two different roots with equal (label,
epoch) appended, published or sent anywhere; an acceptor reply performed before every entry the
node's acceptor asked to sync so far is synced. With watchLeases (off by default: a paused clock
or a startup grace of 0 after a restart lets a lease outlive its grants by design, fenced by
the term), at most one node holds an ownership whose lease is valid on its own clock (L5: the
belief never outlives the granters' promise). checkConverged (converge:): the committed
chains of the live nodes (from each one's published committed root through the pred links of
the roots the simulator built) do not fork (of two heads, one is in the other's chain), then
checkHistory: over the history the simulator derives (history, a PBSimHistory: the tokens of
the commits each live node's chain holds: a commit is in a chain that holds its own built root;
the unchanged root of a re-commit holds none of its effect and credits no commit), the rules of proto_db's assert_outcomes_resolved:
every acknowledged commit is in every live node's chain (S4); every unknown commit (#unknown,
or #pending: nobody answered it) in every live node's chain or in none; a commit answered #none
or with an error in no chain (H7); no chain holds a root the simulator did not build, no log
held and no script persisted (a stray write); every commit in the chain of a root any node
published as committed is still in every chain (a fork of history); and, for a history that
carries counters, each member's counter equals its tokens. checkSafe is the form that does not
need the nodes to have caught up (the timer audit, when its members have not caught up):
no fork of heads; an acknowledged root, or a published one, is in every live chain whose head
does not precede it; H7; no stray write. A violation is an Error whose text holds the seed and
the last 200 trace lines.

Configurations. seed:ids:rules:configs:logs: builds each node's configuration with a block of
its id and the peers (the timer audit gives each member its own timer values, tests/audit/_audit.st)."

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

PBSimClock >> rate
  ^ rate.

"This clock running at aNumber from the virtual time g on, continuous at g."
PBSimClock >> rate: aNumber at: g
  ^ self class rate: aNumber global: g local: (self localAt: g).

"=== PBSimDisk ==============================================================="

"The acceptor log of one node: its entries (41-byte payloads, PBAcceptorLog encode:label:root:)
 in order, of which the first syncedSize are synced."
Object subclass: #PBSimDisk instanceVariableNames: 'name entries synced unreadable'.

PBSimDisk class >> named: aName
  ^ self basicNew setName: aName.

PBSimDisk >> setName: aName
  name := aName.
  entries := OrderedCollection new.
  synced := 0.
  unreadable := OrderedCollection new.

"A fault of the shared storage seen from this node: the SpaceRoot of aRoot (a PBLabeledRoot)
 cannot be read from now on (it survives crashes and a lost disk: it is not the log's)."
PBSimDisk >> unreadable: aRoot
  unreadable add: aRoot key.

"Whether this node can read the SpaceRoot of aRoot."
PBSimDisk >> canRead: aRoot
  ^ (unreadable includes: aRoot key) not.

"Writes aPayload, not synced; answers its index (from 1)."
PBSimDisk >> append: aPayload
  entries add: aPayload.
  ^ entries size.

"Syncs every entry up to anIndex (an fsync makes everything written before it durable)."
PBSimDisk >> syncThrough: anIndex
  synced := synced max: anIndex.

PBSimDisk >> size
  ^ entries size.

"The payloads written, synced or not, a fresh Array."
PBSimDisk >> payloads
  ^ entries asArray.

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
Object subclass: #PBSimNode instanceVariableNames: 'config clock disk up gen state acceptor committed lane laneBusy owed paused'.

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
  paused := nil.

"A crashed node configured with aConfig from its next start on (its disk and clock kept)."
PBSimNode >> reconfigure: aConfig
  up ifTrue: [^ Error signal: 'PBSimNode: reconfigure a crashed node'].
  config := aConfig.

"The rate its clock ran at when it was paused, nil while it runs."
PBSimNode >> paused
  ^ paused.

PBSimNode >> paused: aRateOrNil
  paused := aRateOrNil.

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

"=== PBSimHistory ============================================================"

"What a test's readers saw of its commits (proto_db tests/support/outcomes.py, CommitTokens and
 assert_outcomes_resolved): the members read; the tokens of the commits each one's committed
 state holds (present: id -> Set); the counter each one read in the same snapshot (values: id ->
 Integer, absent when the workload counts nothing: the simulator's commits have no effect apart
 from their root, so a derived history has none); the tokens acknowledged, unknown (the caller
 got no answer either way) and answered none or with an error (nothing applied); every token a
 member was seen to show during the run (observed); a text naming a token's root (keys, for
 the messages); and how many roots of a member's chain wrote a token, when more than one
 (applied: proto_db's commits applied more than once). PBSim history derives one at convergence; sim_checker_plants.st feeds synthetic
 ones (proto_db's workload plants) to the same checks. A builder of test support: the setters
 answer the receiver."
Object subclass: #PBSimHistory instanceVariableNames: 'members present values acked unknown none observed keys applied'.

PBSimHistory class >> members: someIds present: aDictionary
  ^ self basicNew setMembers: someIds present: aDictionary.

PBSimHistory >> setMembers: someIds present: aDictionary
  members := someIds asArray.
  present := Dictionary new.
  members do: [:m | present at: m put: (aDictionary at: m ifAbsent: [#()]) asSet].
  values := Dictionary new.
  acked := Set new.
  unknown := Set new.
  none := Set new.
  observed := Set new.
  keys := Dictionary new.
  applied := Dictionary new.

PBSimHistory >> acked: someTokens
  acked addAll: someTokens.

PBSimHistory >> unknown: someTokens
  unknown addAll: someTokens.

PBSimHistory >> none: someTokens
  none addAll: someTokens.

PBSimHistory >> observed: someTokens
  observed addAll: someTokens.

PBSimHistory >> value: anInteger at: anId
  values at: anId put: anInteger.

"aToken is written by anInteger distinct roots of anId's committed chain (absent: by one, when
 present)."
PBSimHistory >> applied: anInteger of: aToken at: anId
  (applied at: anId ifAbsentPut: [Dictionary new]) at: aToken put: anInteger.

"The times anId's committed chain applies aToken: the roots that wrote it (1 when present and not
 counted, 0 when absent)."
PBSimHistory >> timesOf: aToken at: anId
  ((present at: anId) includes: aToken) ifFalse: [^ 0].
  ^ (applied at: anId ifAbsent: [Dictionary new]) at: aToken ifAbsent: [1].

PBSimHistory >> key: aText of: aToken
  keys at: aToken put: aText.

PBSimHistory >> members
  ^ members.

PBSimHistory >> presentAt: anId
  ^ present at: anId.

PBSimHistory >> valueAt: anId
  ^ values at: anId ifAbsent: [nil].

"Tokens in a fixed order (the messages name the first violation the same way on every run)."
PBSimHistory >> sorted: aSet
  ^ aSet asArray sorted: [:a :b | a <= b].

PBSimHistory >> acked
  ^ self sorted: acked.

PBSimHistory >> unknown
  ^ self sorted: unknown.

PBSimHistory >> none
  ^ self sorted: none.

PBSimHistory >> observed
  ^ self sorted: observed.

PBSimHistory >> isWritten: aToken
  ^ (acked includes: aToken) or: [(unknown includes: aToken) or: [none includes: aToken]].

"aToken printString, with the text of its root when known."
PBSimHistory >> name: aToken
  | k |
  k := keys at: aToken ifAbsent: [nil].
  ^ k isNil ifTrue: [aToken printString] ifFalse: [aToken printString , ' (' , k , ')'].

"=== PBSimChecker ============================================================"

Object subclass: #PBSimChecker instanceVariableNames: 'sim owners roots rootFields leases'.

PBSimChecker class >> sim: aSim
  ^ self basicNew setSim: aSim.

PBSimChecker >> setSim: aSim
  sim := aSim.
  owners := Dictionary new.
  leases := false.
  roots := Dictionary new.
  rootFields := Dictionary new.
  PBClusterMessage schema keysAndValuesDo: [:type :fields |
    rootFields at: type put: ((fields select: [:f | f value = #root]) collect: [:f | f key])].

"An Error whose text holds the seed, aText and the last 200 trace lines."
PBSimChecker >> fail: aText
  ^ sim fail: aText.

"Checks from now on that at most one node holds a valid lease at once."
PBSimChecker >> watchLeases
  leases := true.

"After every step: at most one owner of each term (S1); with watchLeases, at most one valid
 lease."
PBSimChecker >> check
  leases ifTrue: [self checkLeases].
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

"At most one node holds an ownership whose lease is valid on its own clock now."
PBSimChecker >> checkLeases
  | valid |
  valid := sim ids select: [:id |
    | node |
    node := sim nodeAt: id.
    node isUp and: [node state ownership notNil and: [node state ownership lease isValidAt: (sim localNowOf: id)]]].
  valid size > 1 ifTrue: [
    self fail: 'L5: valid leases at once: ' , (valid collect: [:id |
      id , ' term ' , (sim nodeAt: id) state ownership term printString , ' until '
        , (sim nodeAt: id) state ownership lease validUntil printString , ' at ' , (sim localNowOf: id) printString]) printString].

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

"At convergence: the committed heads of the live nodes do not fork, then the outcome rules over
 the history the simulator derives (checkHistory:)."
PBSimChecker >> checkConverged
  self checkHeads.
  self checkHistory: sim history.

"The committed chains of the live nodes do not fork: of two heads, one is in the other's chain."
PBSimChecker >> checkHeads
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

"The rules of proto_db's assert_outcomes_resolved, and the counter its tests compare, over
 aHistory (a PBSimHistory), in this order: every acknowledged token present on every member
 (S4); every unknown token present on every member or on none; no token answered none (or with
 an error) present anywhere (H7); no token applied more than once (written by two roots of one
 member's chain: a conflicted or failed attempt's root that took effect beside its retry, proto_db
 read_blind_tokens); no token present that no commit wrote (a stray write); every
 token a member was seen to show still present on every member (history never loses what a member
 showed, proto_db P1: a fork); a member's counter equal to the tokens it holds."
PBSimChecker >> checkHistory: aHistory
  | members holdersOf |
  members := aHistory members.
  holdersOf := [:token | (members select: [:m | (aHistory presentAt: m) includes: token]) asArray].
  aHistory acked do: [:token |
    members do: [:m | ((aHistory presentAt: m) includes: token) ifFalse: [
      self fail: 'S4: the acknowledged commit ' , (aHistory name: token) , ' is not in the committed chain of ' , m]]].
  aHistory unknown do: [:token | | holders |
    holders := holdersOf value: token.
    (holders notEmpty and: [holders size < members size]) ifTrue: [
      self fail: 'the unknown commit ' , token printString , ' is in the committed chain of ' , holders printString , ' only']].
  aHistory none do: [:token | | holders |
    holders := holdersOf value: token.
    holders notEmpty ifTrue: [
      self fail: 'H7: the commit ' , token printString , ' answered none (or an error) is in the committed chain of '
        , holders printString]].
  self checkApplied: aHistory.
  members do: [:m |
    (aHistory sorted: (aHistory presentAt: m)) do: [:token |
      (aHistory isWritten: token) ifFalse: [
        self fail: 'stray: the committed chain of ' , m , ' holds ' , token printString
          , ', which no acknowledged or unknown commit wrote']]].
  aHistory observed do: [:token |
    members do: [:m | ((aHistory presentAt: m) includes: token) ifFalse: [
      self fail: 'fork: the commit ' , (aHistory name: token) , ' that a member showed is not in the committed chain of ' , m
        , ': history lost it']]].
  members do: [:m | | v |
    v := aHistory valueAt: m.
    (v notNil and: [v ~= (aHistory presentAt: m) size]) ifTrue: [
      self fail: 'counter: ' , m , ' counts ' , v printString , ' commits, its committed chain holds '
        , (aHistory presentAt: m) size printString]].

"No member's committed chain applies a token more than once (proto_db read_blind_tokens:
 'commits applied more than once'): two of its roots wrote it."
PBSimChecker >> checkApplied: aHistory
  aHistory members do: [:m |
    (aHistory sorted: (aHistory presentAt: m)) do: [:token | | times |
      times := aHistory timesOf: token at: m.
      times > 1 ifTrue: [
        self fail: 'applied more than once: the commit ' , (aHistory name: token) , ' is applied '
          , times printString , ' times in the committed chain of ' , m]]].

"The safety rules that hold whether or not the nodes caught up (the timer audit: liveness may
 suffer, safety may not): the heads do not fork (checkHeads); for every live node, the root of
 an acknowledged commit, and every root a node published as committed, is in its chain unless
 its head is still before that root (it has not learnt it yet: counted, not a violation); a
 commit answered none (or with an error) is in no chain (H7); no chain holds a root no commit
 wrote. Answers how many (root, node) pairs were not learnt yet."
PBSimChecker >> checkSafe
  | live history behind targets chains |
  self checkHeads.
  live := sim ids select: [:id | (sim nodeAt: id) isUp].
  history := sim history.
  behind := 0.
  targets := Dictionary new.
  sim publishedKeys do: [:k | targets at: k put: 'committed root ' , k , ' a node published'].
  history acked do: [:token | targets at: (sim keyText: (sim rootOf: token)) put: 'acknowledged commit ' , (history name: token)].
  chains := Dictionary new.
  live do: [:m | chains at: m put: (sim committedChainOf: m)].
  (targets keys asArray sorted: [:a :b | a <= b]) do: [:key | | chain |
    chain := sim chainFrom: key.
    live do: [:m | | head |
      head := (sim nodeAt: m) committed.
      ((chains at: m) includes: key) ifFalse: [
        (head isNil or: [chain includes: (sim keyText: head)])
          ifTrue: [behind := behind + 1]
          ifFalse: [
            self fail: 'S4: the ' , (targets at: key) , ' is not in the committed chain of ' , m , ', whose head '
              , (sim keyText: head) , ' does not precede it']]]].
  history none do: [:token |
    live do: [:m | ((history presentAt: m) includes: token) ifTrue: [
      self fail: 'H7: the commit ' , token printString , ' answered none (or an error) is in the committed chain of ' , m]]].
  self checkApplied: history.
  live do: [:m |
    (history sorted: (history presentAt: m)) do: [:token |
      (history isWritten: token) ifFalse: [
        self fail: 'stray: the committed chain of ' , m , ' holds ' , token printString
          , ', which no acknowledged or unknown commit wrote']]].
  ^ behind.

"=== PBSim ==================================================================="

Object subclass: #PBSim instanceVariableNames: 'seed random rules ids nodes queue now faults groups links lines checker commits commitOrder commitRoots preds offsets current counts failing syncCost fixedLags peers persisted epochSteps writers published initialKeys recommitRoots foreignLinks failures'.

"N nodes (anArray of ids) running aRules, each configured with aDictionary (PBClusterConfig
 options), all started at virtual time 0, every choice drawn from Random seed: n."
PBSim class >> seed: n ids: anArray rules: aRules options: aDictionary
  ^ self seed: n ids: anArray rules: aRules options: aDictionary logs: Dictionary new.

"As seed:ids:rules:options:, each node id of aLogs starting over a synced log holding its
 Array of PBLogAppend."
PBSim class >> seed: n ids: anArray rules: aRules options: aDictionary logs: aLogs
  ^ self seed: n ids: anArray rules: aRules
    configs: [:id :somePeers | PBClusterConfig nodeId: id peers: somePeers options: aDictionary] logs: aLogs.

"As seed:ids:rules:options:logs:, each node configured with what aBlock answers for its id and
 the peers (Array of PBPeer) of the cluster: a PBClusterConfig, or a test subclass of it (the
 timer audit gives each node its own timer values)."
PBSim class >> seed: n ids: anArray rules: aRules configs: aBlock logs: aLogs
  ^ self basicNew setSeed: n ids: anArray rules: aRules configs: aBlock logs: aLogs.

PBSim >> setSeed: n ids: anArray rules: aRules configs: aBlock logs: aLogs
  seed := n.
  "Park-Miller's first draws of nearby small seeds are small and alike: the seed is spread
   over the generator's range and the first draws are discarded."
  random := Random seed: n * 48271 + 1013904223.
  16 timesRepeat: [random next].
  rules := aRules.
  ids := anArray asArray.
  peers := (1 to: ids size) asArray collect: [:i | PBPeer nodeId: (ids at: i) host: '127.0.0.1' port: 7000 + i].
  nodes := Dictionary new.
  ids do: [:id | nodes at: id put: (PBSimNode config: (aBlock value: id value: peers))].
  queue := OrderedCollection new.
  now := 0.
  faults := PBSimFaults none.
  links := Dictionary new.
  lines := OrderedCollection new.
  checker := PBSimChecker sim: self.
  commits := Dictionary new.
  commitOrder := OrderedCollection new.
  commitRoots := Dictionary new.
  recommitRoots := Dictionary new.
  failures := Dictionary new.
  foreignLinks := Dictionary new.
  preds := Dictionary new.
  offsets := 0.
  counts := Dictionary new.
  failing := Set new.
  syncCost := 0.
  fixedLags := Dictionary new.
  persisted := nil.
  epochSteps := Dictionary new.
  writers := Dictionary new.
  published := Set new.
  initialKeys := Set new.
  aLogs keysAndValuesDo: [:id :appends |
    | disk |
    disk := (self nodeAt: id) disk.
    appends do: [:a |
      a root notNil ifTrue: [initialKeys add: (self keyText: (PBLabeledRoot label: a label record: a root))].
      disk append: a payload].
    disk syncThrough: disk size].
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

"The error a commit's permit request ended with (a PBTimeoutError, ...), nil when its permit
 request did not fail."
PBSim >> failureOf: aToken
  ^ failures at: aToken ifAbsent: [nil].

"#pending, #acknowledged, #unknown, #none or #failed; nil for a token never committed."
PBSim >> outcomeOf: aToken
  ^ commits at: aToken ifAbsent: [nil].

"The root built for aToken, nil while none is."
PBSim >> rootOf: aToken
  ^ commitRoots at: aToken ifAbsent: [nil].

PBSim >> commitOrder
  ^ commitOrder asArray.

"The virtual time now."
PBSim >> now
  ^ now.

"anId's clock now."
PBSim >> localNowOf: anId
  ^ (self nodeAt: anId) clock localAt: now.

"How many PBCount stat: aName anId performed."
PBSim >> countOf: aName at: anId
  ^ counts at: anId , ' ' , aName ifAbsent: [0].

"The text of the ordering key of aRoot (PBLabeledRoot key)."
PBSim >> keyText: aRoot
  | k |
  k := aRoot key.
  ^ (k at: 1) printString , '/' , (k at: 2) printString , '/' , (k at: 3) hex asLowercase , '/' , (k at: 4) printString.

"The keys of the roots of anId's committed chain: its published committed root and every root
 before it through the pred links of the roots the simulator built."
PBSim >> committedChainOf: anId
  (self nodeAt: anId) committed isNil ifTrue: [^ Set new].
  ^ self chainFrom: (self keyText: (self nodeAt: anId) committed).

"The keys of the chain ending at the root of key aKeyText: it and every root before it through
 the pred links of the roots the simulator built."
PBSim >> chainFrom: aKeyText
  | chain key |
  chain := Set new.
  key := aKeyText.
  [key notNil and: [(chain includes: key) not]] whileTrue: [
    chain add: key.
    key := preds at: key ifAbsent: [foreignLinks at: key ifAbsent: [nil]]].
  ^ chain.

"The token of the commit whose attempt built the root of key aKeyText (its own root; the unchanged
 root of a re-commit has no writer: it holds none of the commit's effect), nil for a root the
 simulator did not build."
PBSim >> writerOf: aKeyText
  ^ writers at: aKeyText ifAbsent: [nil].

"Whether the root of key aKeyText was built by the simulator (every root it builds records its
 pred link; a re-commit's included, known through its pred link though it has no writer) or needs
 no builder: the empty space (exactly its key, PBLabeledRoot label: 0 record: nil), a root of the
 logs the nodes started over, or a root the script persisted (persist:)."
PBSim >> isKnownRoot: aKeyText
  ^ (preds includesKey: aKeyText) or: [(initialKeys includes: aKeyText)
      or: [aKeyText = (self keyText: (PBLabeledRoot label: 0 record: nil))]].

"--- the checker's plants (sim_checker_plants.st): roots no commit wrote ---"

"A root of aBase's label at aBase's epoch + 1 with a fresh offset, its pred link aBase recorded
 as the simulator records the roots it builds: a known root no commit wrote (a plant moves a
 member's head to it)."
PBSim >> declare: aBase
  | root |
  root := self _plantRoot: aBase.
  preds at: (self keyText: root) put: (self keyText: aBase).
  ^ root.

"As declare:, but the pred link is the chain's only (foreignLinks): the simulator never built the root
 and does not know it (isKnownRoot: false), as a root a defect fabricated."
PBSim >> fabricate: aBase
  | root |
  root := self _plantRoot: aBase.
  foreignLinks at: (self keyText: root) put: (self keyText: aBase).
  ^ root.

PBSim >> _plantRoot: aBase
  offsets := offsets + 1.
  ^ PBLabeledRoot label: aBase label
    record: (PBRootRecord segment: (self nodeAt: ids first) segment offset: offsets epoch: aBase epoch + 1).

"anId publishes aRoot as its committed root, as its shell performs a PBPublishCommitted effect
 (applyPublishCommitted:: the checker notes the root, the published keys record it)."
PBSim >> publish: aRoot at: anId
  | was |
  was := current.
  current := self nodeAt: anId.
  self applyPublishCommitted: (PBPublishCommitted root: aRoot).
  current := was.

"The unchanged root aToken's re-commit replicated (proto_db _commit_base), nil when it had none."
PBSim >> recommitRootOf: aToken
  ^ recommitRoots at: aToken ifAbsent: [nil].

"The keys of every root any node published as committed, in no order (a fresh Set)."
PBSim >> publishedKeys
  ^ published copy.

"The history of the commits as the live nodes' committed chains show it (a PBSimHistory): a
 node's tokens are those whose commit wrote a root of its chain (its own root; never the unchanged
 root of its re-commit, which holds none of its effect), and a root of its chain that the simulator did not build, no log held and
 no script persisted (isKnownRoot:) is the stray token 'root <key>'; acknowledged as the simulator
 recorded; unknown: #unknown, and #pending (a commit no one answered: its node's incarnation
 is gone, or it is still running); none: #none and #failed (an error other than an unknown
 outcome: nothing applied, H7); observed: the writers of every root in the chain of a root any
 node published as committed during the run."
PBSim >> history
  | live present history seen tokensOf times |
  live := ids select: [:id | (self nodeAt: id) isUp].
  "The tokens whose commit wrote each root: its own built roots (writerOf:, rootOf:)."
  tokensOf := Dictionary new.
  writers keysAndValuesDo: [:k :token | (tokensOf at: k ifAbsentPut: [Set new]) add: token].
  commitRoots keysAndValuesDo: [:token :root | (tokensOf at: (self keyText: root) ifAbsentPut: [Set new]) add: token].
  present := Dictionary new.
  times := Dictionary new.
  live do: [:id | | tokens counts |
    tokens := Set new.
    counts := Dictionary new.
    (self committedChainOf: id) do: [:k |
      (tokensOf at: k ifAbsent: [#()]) do: [:token |
        tokens add: token.
        counts at: token put: (counts at: token ifAbsent: [0]) + 1].
      (self isKnownRoot: k) ifFalse: [tokens add: 'root ' , k]].
    present at: id put: tokens.
    times at: id put: counts].
  history := PBSimHistory members: live present: present.
  times keysAndValuesDo: [:id :counts |
    counts keysAndValuesDo: [:token :n | n > 1 ifTrue: [history applied: n of: token at: id]]].
  history acked: (commitOrder select: [:k | (commits at: k) = #acknowledged]).
  history unknown: (commitOrder select: [:k | #(#unknown #pending) includes: (commits at: k)]).
  history none: (commitOrder select: [:k | #(#none #failed) includes: (commits at: k)]).
  commitOrder do: [:k | (commitRoots includesKey: k) ifTrue: [history key: (self keyText: (commitRoots at: k)) of: k]].
  seen := Set new.
  published do: [:k | (seen includes: k) ifFalse: [seen addAll: (self chainFrom: k)]].
  seen do: [:k | history observed: (tokensOf at: k ifAbsent: [#()])].
  ^ history.

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
  node paused notNil ifTrue: [^ Error signal: 'PBSim: ' , anId , ' is paused (resume: it first)'].
  node clock: (node clock rate: aNumber at: now).
  queue do: [:e |
    ((e at: 2) = #timer and: [(e at: 3) = anId]) ifTrue: [
      e at: 1 put: (node clock globalAt: ((e at: 5) at: 1))]].
  self _trace: anId , ' clock rate ' , aNumber printString.

"A process pause of anId (a VM freeze, SIGSTOP, a long GC): from now on until resume: its clock
 stands still and the node runs nothing, neither a delivery, nor a dispatch, nor a timer, nor an
 acceptor step; what is due for it waits, in order. Messages it sent before stay in flight."
PBSim >> pause: anId
  | node rate |
  node := self nodeAt: anId.
  (node isUp and: [node paused isNil]) ifFalse: [^ Error signal: 'PBSim: pause a running node that is not paused'].
  self _trace: anId , ' paused'.
  rate := node clock rate.
  self clockRate: anId rate: 0.
  node paused: rate.
  ^ self.

"anId resumes after pause: its clock runs again at the rate it had, from where it stood; what
 waited for it is due now, in the order it was due."
PBSim >> resume: anId
  | node rate waiting tick |
  node := self nodeAt: anId.
  node paused isNil ifTrue: [^ Error signal: 'PBSim: ' , anId , ' is not paused'].
  rate := node paused.
  node paused: nil.
  self clockRate: anId rate: rate.
  waiting := (queue select: [:e | (e at: 3) = anId and: [(e at: 1) notNil and: [(e at: 1) < now]]]) asArray.
  waiting := waiting asSortedCollection: [:a :b | (a at: 1) <= (b at: 1)].
  tick := 0.
  waiting do: [:e | e at: 1 put: now + tick. tick := tick + 1].
  self _trace: anId , ' resumed'.
  ^ self.

"A crashed node anId starts, at its next restart, configured with aDictionary (PBClusterConfig
 options) instead of the options it had: a member misconfigured by its operator."
PBSim >> reconfigure: anId options: aDictionary
  (self nodeAt: anId) reconfigure: (PBClusterConfig nodeId: anId peers: peers options: aDictionary).
  self _trace: anId , ' reconfigured'.

"A crash of anId: aMode (#drop, #keep, #prefix or #any) decides the unsynced tail of its disk."
PBSim >> crash: anId unsynced: aMode
  | node mode tail kept |
  node := self nodeAt: anId.
  node isUp ifFalse: [^ Error signal: 'PBSim: ' , anId , ' is not running'].
  (#(#drop #keep #prefix #any) includes: aMode) ifFalse: [
    ^ Error signal: 'PBSim crash:unsynced: #drop, #keep, #prefix or #any, not ' , aMode printString].
  node paused notNil ifTrue: [self resume: anId].
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

"Every acceptor step that asks for a sync takes someMicros of virtual time to sync (an fsync)."
PBSim >> syncCost: someMicros
  (someMicros isInteger and: [someMicros >= 0]) ifFalse: [^ Error signal: 'PBSim syncCost: an Integer >= 0'].
  syncCost := someMicros.

"Every message sent from fromId to toId from now on arrives someMicros later (on top of the
 faults' delay)."
PBSim >> delay: fromId to: toId by: someMicros
  (someMicros isInteger and: [someMicros >= 0]) ifFalse: [^ Error signal: 'PBSim delay:to:by: an Integer >= 0'].
  fixedLags at: fromId , '>' , toId put: someMicros.
  self _trace: fromId , ' -> ' , toId , ' delayed by ' , someMicros printString.

"The shared storage's persisted root is aRoot (a PBLabeledRoot) from now on (the persister of
 a later task writes it; a script sets it here)."
PBSim >> persist: aRoot
  persisted := aRoot.
  aRoot notNil ifTrue: [initialKeys add: (self keyText: aRoot)].
  self _trace: 'persisted ' , (PBCoreValue textOf: aRoot).

PBSim >> persisted
  ^ persisted.

"The commits of anId build their root at the base's epoch + n (an Integer >= 1) from now on: a
 node whose transactions write several epochs (a test of root order between siblings)."
PBSim >> epochStep: n at: anId
  (n isInteger and: [n >= 1]) ifFalse: [^ Error signal: 'PBSim epochStep:at: an Integer >= 1'].
  epochSteps at: anId put: n.

PBSim >> failAppends: anId
  failing add: anId.
  self _trace: anId , ' appends fail'.

"Delivers aMessage (a PBClusterMessage from a member) to anId at aTime (not before now), as if
 its sender had sent it then."
PBSim >> inject: aMessage to: anId at: aTime
  | from |
  aTime < now ifTrue: [^ Error signal: 'PBSim inject: a time not before now'].
  from := self nodeAt: aMessage from.
  current := from.
  self _trace: 'inject ' , aMessage type , ' from ' , from id , ' to ' , anId , ' at ' , aTime printString.
  self _send: (PBSend to: anId message: aMessage) at: aTime.

PBSim >> tearLog: anId
  | node |
  node := self nodeAt: anId.
  node isUp ifTrue: [^ Error signal: 'PBSim: tearLog: a crashed node, not the running ' , anId].
  node disk tear.
  self _trace: anId , ' log torn'.

"A synthetic transaction aToken (a new token) at the running node anId."
PBSim >> commit: aToken at: anId
  ^ self commit: aToken at: anId time: now.

"A synthetic transaction aToken at the running node anId, asked at aTime (not before now): a
 commit of an incarnation that is gone by then is dropped and stays pending."
PBSim >> commit: aToken at: anId time: aTime
  | node |
  node := self nodeAt: anId.
  node isUp ifFalse: [^ Error signal: 'PBSim: ' , anId , ' is not running'].
  aTime < now ifTrue: [^ Error signal: 'PBSim commit: a time not before now'].
  (commits includesKey: aToken) ifTrue: [^ Error signal: 'PBSim: the token ' , aToken printString , ' is taken'].
  commits at: aToken put: #pending.
  commitOrder add: aToken.
  self _trace: anId , ' commit ' , aToken printString , (aTime = now ifTrue: [''] ifFalse: [' at ' , aTime printString]).
  self _schedule: #dispatch node: node payload: (PBPermitWanted waiter: { 'permit'. aToken }) at: aTime.

"Runs the earliest due event (one of those due at once, drawn), then the checker; false when
 nothing is due (the queue is empty, or holds only timers of paused clocks and events of paused
 nodes)."
PBSim >> step
  | best due event |
  best := nil.
  queue do: [:e | ((e at: 1) notNil and: [(self _isPaused: (e at: 3)) not and: [best isNil or: [(e at: 1) < best]]]) ifTrue: [best := e at: 1]].
  best isNil ifTrue: [^ false].
  due := queue select: [:e | (e at: 1) = best and: [(self _isPaused: (e at: 3)) not]].
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

PBSim >> _isPaused: anId
  ^ (nodes at: anId) paused notNil.

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
  ((failing includes: aNode id) and: [step appends notEmpty]) ifTrue: [
    "The failed step is discarded: the acceptor keeps the state it had before it."
    self _trace: aNode id , '   append failed, the step is discarded and not replied'.
    aNode lane addFirst: (PBAppendFailed reason: 'simulated append failure').
    aNode laneBusy: false.
    self _schedule: #dispatch node: aNode payload: (PBAcceptorDiscarded step: step reason: 'simulated append failure') at: now.
    ^ self _runLane: aNode].
  aNode acceptor: step state.
  last := 0.
  step appends do: [:append |
    | index |
    index := aNode disk append: append payload.
    self _trace: aNode id , '   append ' , append printString.
    checker noteAppend: append.
    append sync ifTrue: [last := index]].
  aNode owe: last.
  self _schedule: #sync node: aNode payload: { last. step } at: now + (last > 0 ifTrue: [syncCost] ifFalse: [0]).

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
  ^ self _send: aSend at: now.

PBSim >> _send: aSend at: aTime
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
    at := aTime + (fixedLags at: link ifAbsent: [0]) + (faults delay > 0 ifTrue: [random between: 0 and: faults delay] ifFalse: [0]).
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
  aPublish root notNil ifTrue: [published add: (self keyText: aPublish root)].
  current committed: aPublish root.

"The acceptor snapshot and the fence are what a shell publishes for readers and refuses
 commits by: their trace line (_apply:at:) is the simulator's record of them."
PBSim >> applyPublishAcceptor: aPublish
  ^ self.

PBSim >> applyFence: aFence
  ^ self.

PBSim >> applyReadPersisted: aRead
  self _schedule: #dispatch node: current
    payload: (PBStorageRead token: aRead token root: persisted failure: nil) at: now.

PBSim >> applyProbeRoot: aProbe
  self _schedule: #dispatch node: current
    payload: (PBRootProbed token: aProbe token readable: (current disk canRead: aProbe root)) at: now.

PBSim >> applyCount: aCount
  | key |
  key := current id , ' ' , aCount stat.
  counts at: key put: (counts at: key ifAbsent: [0]) + 1.

"--- the synthetic transactions ---"

PBSim >> _settle: aWaiter outcome: anOutcome at: aNode
  | stage token permission |
  (aWaiter isArray and: [aWaiter size >= 2 and: [commits includesKey: (aWaiter at: 2)]]) ifFalse: [
    ^ Error signal: 'PBSim: settled an unknown waiter ' , aWaiter printString].
  stage := aWaiter at: 1.
  token := aWaiter at: 2.
  stage = 'permit' ifTrue: [
    (anOutcome isKindOf: PBPermission) ifFalse: [
      failures at: token put: anOutcome.
      ^ self _end: token as: #failed].
    ^ self _schedule: #dispatch node: aNode
      payload: (PBBaseWanted permission: anOutcome waiter: { 'base'. token. anOutcome }) at: now].
  permission := aWaiter at: 3.
  stage = 'base' ifTrue: [^ self _based: token decision: anOutcome permission: permission at: aNode].
  stage = 'recommit' ifTrue: [
    anOutcome = #committed ifTrue: [^ self _build: token on: (recommitRoots at: token) permission: permission step: nil at: aNode].
    ^ self _replicated: token outcome: anOutcome permission: permission at: aNode].
  stage = 'replicate' ifTrue: [^ self _replicated: token outcome: anOutcome permission: permission at: aNode].
  ^ Error signal: 'PBSim: settled an unknown waiter ' , aWaiter printString.

"The base decision (or error) of aToken's permission."
PBSim >> _based: aToken decision: anOutcome permission: aPermission at: aNode
  | base root |
  (anOutcome isKindOf: PBBaseDecision) ifFalse: [
    self _end: aToken as: ((anOutcome isKindOf: PBConflictError) ifTrue: [#none] ifFalse: [#failed]).
    ^ self _report: aPermission outcome: #none root: nil at: aNode].
  anOutcome outcome = #stale ifTrue: [
    self _trace: aNode id , ' requeues ' , aToken printString , ' (stale base)'.
    self _report: aPermission outcome: #unknown root: nil at: aNode.
    ^ self _schedule: #dispatch node: aNode payload: (PBPermitWanted waiter: { 'permit'. aToken }) at: now].
  anOutcome outcome = #unreachable ifTrue: [
    self _end: aToken as: #none.
    ^ self _report: aPermission outcome: #unknown root: nil at: aNode].
  base := anOutcome base.
  anOutcome needsCommit ifFalse: [^ self _build: aToken on: base permission: aPermission step: nil at: aNode].
  "proto_db _commit_base: an unchanged root on the base, labelled with the term, epoch + 1."
  root := self _newRoot: aPermission on: base step: 1 at: aNode.
  "No writer: the unchanged root holds none of aToken's effect; aToken's own root is built on it."
  recommitRoots at: aToken put: root.
  self _trace: aNode id , ' re-commits ' , (PBCoreValue textOf: base) , ' as ' , (PBCoreValue textOf: root)
    , ' for ' , aToken printString.
  ^ self _schedule: #dispatch node: aNode
    payload: (PBReplicateWanted permission: aPermission root: root pred: base waiter: { 'recommit'. aToken. aPermission }) at: now.

"A new root of aPermission's term on aBase at epoch + n, its pred link recorded."
PBSim >> _newRoot: aPermission on: aBase step: n at: aNode
  | root |
  offsets := offsets + 1.
  root := PBLabeledRoot label: aPermission term
    record: (PBRootRecord segment: aNode segment offset: offsets epoch: aBase epoch + n).
  preds at: (self keyText: root) put: (self keyText: aBase).
  ^ root.

PBSim >> _build: aToken on: aBase permission: aPermission step: aStep at: aNode
  | root |
  root := self _newRoot: aPermission on: aBase step: (epochSteps at: aNode id ifAbsent: [1]) at: aNode.
  commitRoots at: aToken put: root.
  writers at: (self keyText: root) put: aToken.
  self _trace: aNode id , ' built ' , (PBCoreValue textOf: root) , ' on ' , (PBCoreValue textOf: aBase)
    , ' for ' , aToken printString.
  ^ self _schedule: #dispatch node: aNode
    payload: (PBReplicateWanted permission: aPermission root: root pred: aBase waiter: { 'replicate'. aToken. aPermission }) at: now.

PBSim >> _replicated: aToken outcome: aSettled permission: aPermission at: aNode
  | anOutcome |
  "An unknown replication is settled with its PBOutcomeUnknownError (holder.st)."
  anOutcome := (aSettled isKindOf: PBOutcomeUnknownError) ifTrue: [#unknown] ifFalse: [aSettled].
  self _end: aToken as: ((PBDoneReport outcomes includes: anOutcome)
    ifTrue: [anOutcome = #committed ifTrue: [#acknowledged] ifFalse: [anOutcome]]
    ifFalse: [#failed]).
  ^ self _report: aPermission
    outcome: ((PBDoneReport outcomes includes: anOutcome) ifTrue: [anOutcome] ifFalse: [#none])
    root: (anOutcome = #committed ifTrue: [commitRoots at: aToken] ifFalse: [nil]) at: aNode.

"aNode ends aPermission with anOutcome (its PBDoneReport)."
PBSim >> _report: aPermission outcome: anOutcome root: aRoot at: aNode
  ^ self _schedule: #dispatch node: aNode payload: (PBDoneReport permission: aPermission outcome: anOutcome root: aRoot) at: now.

PBSim >> _end: aToken as: aStatus
  commits at: aToken put: aStatus.
  self _trace: 'commit ' , aToken printString , ' ' , aStatus.
