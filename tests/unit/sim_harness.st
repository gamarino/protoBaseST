"EXPECT: ok 13"
"The deterministic simulator (_sim.st) over the core vocabulary (cluster/core.st), with test
 rules: EchoRules sends a want to every other member, sets one timer (1000 us) and hands its
 PBStartNode to its acceptor, which logs a synced promise and an unsynced committed entry.
 (1-2) The same seed and schedule give the same trace byte for byte; another seed gives another
 schedule, not only other incarnations. (3) A partition stops delivery across it and heal
 resumes it. (4-6) A timer fires after its duration of the node's own clock: at 667 us of
 virtual time on a clock at 3/2; at 2000 us when the rate drops to 1/2 after it was set (the
 node's clock then reads 1000, not 500); never while the clock is paused (rate 0), and after
 the rest of its duration once it runs again. (7) A crash keeps the synced entries and chooses
 for the unsynced tail: dropped (power loss, also keepDisk: true), kept (process crash), a
 seeded prefix, or one of the three drawn from the seed; tearLog: cuts the last synced frame; a
 lost disk holds nothing. (8) A crash between the sync and the reply of an acceptor step leaves
 the root accepted and the reply never sent. (9) The acceptor lane is serial: over seeds 1-12,
 a step's reply never runs before the sync of an earlier step, and a simulator that runs the
 lane concurrently is caught by the checker. (10) The checker reports every planted violation
 with the seed and the trace: equal (label, epoch) on two nodes, two owners of one term (S1), a
 reply before its sync, an acknowledged commit missing from a member's chain (S4), an unknown
 commit on one member only, a commit answered none that a member holds (H7), and two committed
 chains that diverge (a fork); a commit every member learns converges. (11) converge: answers
 whether the queue emptied. (12) No file of the simulator or of the core in src/protobase/cluster
 (every file there but the shells: transport.st, whose sender times its reconnection back-off,
 coordinator.st, whose actors read the node's clock and run its timers, round.st, the commit round's
 shell, and persister.st, whose passes and sync: deadlines are timers)
 reads a clock of protoST's (Time, Date, DateTime, the clock primitives, Future after:, Delay);
 each name the exemption lists must be a file that exists. (13) Delays with reorder: true
 deliver every one of 50 messages from n0 to n1, out of send order for seed 11; with reorder:
 false the same seed keeps the send order (proto_db test_in_process_delays_reorder_messages)."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_sim'.

"--- test rules ---"

PBCoordinatorCore subclass: #EchoRules.

"The harness rules test the simulator, not the rejoin (sim_rejoin.st): an acceptor report of an
 empty log starts none."
EchoRules >> rejoinCheck: s now: t effects: fx
  ^ s.

EchoRules >> _others: s
  ^ s config membership ids reject: [:id | id = s config nodeId].

EchoRules >> dispatchStartNode: anEvent in: s now: t
  ^ PBStep state: s effects: ((self _others: s) collect: [:id |
      PBSend to: id message: (PBClusterMessage type: 'want' from: s config nodeId fields: #())])
    , { PBTimer after: 1000 token: 1 event: #tick. PBToAcceptor event: anEvent }.

EchoRules >> acceptStart: anEvent in: s now: t
  ^ PBAcceptorStep state: s
    appends: { PBLogAppend kind: #promise label: 4096 + s config rank root: nil sync: true.
               PBLogAppend kind: #committed label: 0 root: nil sync: false }
    reply: #().

"Re-arms its timer for ever: the queue never empties."
EchoRules subclass: #TickRules.

TickRules >> dispatchTimerFired: anEvent in: s now: t
  ^ PBStep state: s effects: { PBTimer after: 1000 token: 1 event: #tick }.

"Two unsynced committed entries after the synced promise."
EchoRules subclass: #TailRules.

TailRules >> acceptStart: anEvent in: s now: t
  ^ PBAcceptorStep state: s
    appends: { PBLogAppend kind: #promise label: 4096 + s config rank root: nil sync: true.
               PBLogAppend kind: #committed label: 0 root: nil sync: false.
               PBLogAppend kind: #committed label: 0 root: nil sync: false }
    reply: #().

"Starts by its acceptor only, which accepts a root (synced) and replies with a want to every
 other member."
EchoRules subclass: #ReplyLostRules.

ReplyLostRules >> dispatchStartNode: anEvent in: s now: t
  ^ PBStep state: s effects: { PBToAcceptor event: anEvent }.

ReplyLostRules >> acceptStart: anEvent in: s now: t
  ^ PBAcceptorStep state: s
    appends: { PBLogAppend kind: #accepted label: 4096 + s config rank
      root: (PBRootRecord segment: (ByteArray new: 16) offset: 100 + s config rank epoch: 1) sync: true }
    reply: ((self _others: s) collect: [:id |
      PBSend to: id message: (PBClusterMessage type: 'want' from: s config nodeId fields: #())]).

"Two acceptor steps per start: a synced promise, then one that appends nothing and replies."
PBCoordinatorCore subclass: #LaneRules.

"The harness rules test the simulator, not the rejoin (sim_rejoin.st): an acceptor report of an
 empty log starts none."
LaneRules >> rejoinCheck: s now: t effects: fx
  ^ s.

LaneRules >> dispatchStartNode: anEvent in: s now: t
  ^ PBStep state: s effects: { PBToAcceptor event: anEvent.
    PBToAcceptor event: (PBReceived message: (PBClusterMessage type: 'want' from: s config nodeId fields: #())) }.

LaneRules >> acceptStart: anEvent in: s now: t
  ^ PBAcceptorStep state: s appends: { PBLogAppend kind: #promise label: 9 root: nil sync: true } reply: #().

LaneRules >> acceptReceived: anEvent in: s now: t
  ^ PBAcceptorStep state: s appends: #() reply: { PBPublishAcceptor state: s }.

"An acceptor event this test adds without editing core.st."
PBCoreEvent subclass: #NoteEvent.

NoteEvent class >> isAcceptorEvent
  ^ true.

NoteEvent >> acceptWith: aCore in: anAcceptorState now: t
  ^ aCore acceptNote: self in: anAcceptorState now: t.

PBCoordinatorCore subclass: #NoteRules.

"The harness rules test the simulator, not the rejoin (sim_rejoin.st): an acceptor report of an
 empty log starts none."
NoteRules >> rejoinCheck: s now: t effects: fx
  ^ s.

NoteRules >> dispatchStartNode: anEvent in: s now: t
  ^ PBStep state: s effects: { PBToAcceptor event: NoteEvent new }.

NoteRules >> acceptNote: anEvent in: s now: t
  ^ PBAcceptorStep state: s appends: { PBLogAppend kind: #promise label: 5 root: nil sync: true } reply: #().

"Plant of the simulator: the acceptor lane runs its steps concurrently."
PBSim subclass: #ConcurrentLaneSim.

ConcurrentLaneSim >> applyToAcceptor: aToAcceptor
  current lane addLast: aToAcceptor event.
  self _schedule: #accept node: current payload: nil at: now.

ConcurrentLaneSim >> _runLane: aNode
  ^ self.

"Plant: every node accepts a different root labelled 7 at epoch 1."
EchoRules subclass: #TwinRootRules.

TwinRootRules >> acceptStart: anEvent in: s now: t
  ^ PBAcceptorStep state: s
    appends: { PBLogAppend kind: #accepted label: 7
      root: (PBRootRecord segment: (ByteArray new: 16) offset: 100 + s config rank epoch: 1) sync: true }
    reply: #().

"Plant: every node owns term 4096 from its start."
EchoRules subclass: #TwoOwnersRules.

TwoOwnersRules >> dispatchStartNode: anEvent in: s now: t
  ^ PBStep state: (s withOwnership: (PBLease term: 4096 validUntil: t root: nil certain: false)) effects: #().

"Commits: a node permits itself, builds on the empty space, commits and tells every member."
EchoRules subclass: #CommitRules.

CommitRules >> dispatchPermitWanted: anEvent in: s now: t
  ^ PBStep state: s effects: { PBSettle waiter: anEvent waiter outcome: (PBPermission term: 4096 + s config rank
    seq: 1 rid: s nextRid owner: s config nodeId root: nil certain: false sentAt: t valid: 1000) }.

CommitRules >> dispatchBaseWanted: anEvent in: s now: t
  ^ PBStep state: s effects: { PBSettle waiter: anEvent waiter
    outcome: (PBBaseDecision base: (PBLabeledRoot label: 0 record: nil) needsCommit: false outcome: #ok) }.

CommitRules >> outcome
  ^ #committed.

CommitRules >> _done: anEvent in: s
  ^ PBClusterMessage type: 'done' from: s config nodeId fields: {
    'term' -> anEvent permission term. 'seq' -> 1. 'inc' -> s inc. 'outcome' -> 'committed'.
    'root' -> (PBClusterMessage rootValue: anEvent root). 'copies' -> #(). 'ranges' -> nil }.

CommitRules >> dispatchReplicateWanted: anEvent in: s now: t
  ^ PBStep state: s effects: { PBSettle waiter: anEvent waiter outcome: self outcome. PBPublishCommitted root: anEvent root }
    , ((self _others: s) collect: [:id | PBSend to: id message: (self _done: anEvent in: s)]).

"The done travels in dispatchReplicateWanted:in:now:; owner.st's done broadcast would teach the
 members a root the plants below must keep from them."
CommitRules >> dispatchDoneReport: anEvent in: s now: t
  ^ PBStep state: s effects: #().

CommitRules >> dispatchReceived: anEvent in: s now: t
  anEvent message type = 'done' ifFalse: [^ super dispatchReceived: anEvent in: s now: t].
  ^ PBStep state: s effects: { PBPublishCommitted root: (PBClusterMessage rootFrom: (anEvent message at: 'root')) }.

"Plant: an acknowledged commit no member learns."
CommitRules subclass: #LostCommitRules.

LostCommitRules >> dispatchReplicateWanted: anEvent in: s now: t
  ^ PBStep state: s effects: { PBSettle waiter: anEvent waiter outcome: #committed }.

"Plant: an unknown commit only its holder learns."
CommitRules subclass: #SplitUnknownRules.

SplitUnknownRules >> dispatchReplicateWanted: anEvent in: s now: t
  ^ PBStep state: s effects: { PBSettle waiter: anEvent waiter outcome: #unknown. PBPublishCommitted root: anEvent root }.

"Plant: a commit answered none that every member learns (H7)."
CommitRules subclass: #NoneHeldRules.

NoneHeldRules >> outcome
  ^ #none.

"Plant: every holder publishes its own commit on the empty space only to itself (a fork)."
SplitUnknownRules subclass: #ForkRules.

"Plant of the simulator: the reply of an acceptor step performed before its sync."
PBSim subclass: #EarlyReplySim.

EarlyReplySim >> _syncThrough: anIndex step: aStep at: aNode
  self _reply: aStep at: aNode syncedThrough: anIndex.
  aNode disk syncThrough: anIndex.

EchoRules subclass: #ReplyRules.

ReplyRules >> acceptStart: anEvent in: s now: t
  ^ PBAcceptorStep state: s
    appends: { PBLogAppend kind: #promise label: 4096 + s config rank root: nil sync: true }
    reply: { PBPublishAcceptor state: s }.

"n0 sends 50 requests to n1 at start (terms 1-50); every node notes the terms it receives, in
 arrival order. The simulator runs in one thread, so a plain collection is safe here."
EchoRules subclass: #OrderRules instanceVariableNames: 'seen'.

OrderRules class >> new
  ^ self basicNew setSeen.

OrderRules >> setSeen
  seen := OrderedCollection new.

OrderRules >> seen
  ^ seen asArray.

OrderRules >> dispatchStartNode: anEvent in: s now: t
  s config nodeId = 'n0' ifFalse: [^ PBStep state: s effects: #()].
  ^ PBStep state: s effects: ((1 to: 50) asArray collect: [:k |
      PBSend to: 'n1' message: (PBClusterMessage type: 'request' from: 'n0'
        fields: { 'term' -> k. 'rid' -> k. 'inc' -> 0. 'vs' -> 0 })]).

OrderRules >> dispatchReceived: anEvent in: s now: t
  seen add: (anEvent message at: 'term').
  ^ PBStep state: s effects: #().

"--- the checks ---"

| c ids sim run lines times clocks index count failure a b planted errorOf modes |
c := Check new.
ids := #('n0' 'n1' 'n2').
sim := [:seed :rules | PBSim seed: seed ids: ids rules: rules options: Dictionary new].
run := [:seed |
  | s |
  s := sim value: seed value: EchoRules new.
  s faults: (PBSimFaults drop: 1/5 duplicate: 1/5 delay: 5000 reorder: true).
  s runUntil: [false] steps: 200.
  s trace].
"The trace lines of aSim that contain aText."
lines := [:aSim :aText | aSim trace select: [:l | l includesSubstring: aText]].
"The virtual times (the integer after 't=') of the lines of aSim that contain aText."
times := [:aSim :aText | (lines value: aSim value: aText) collect: [:l | ((l copyFrom: 3 to: l size) subStrings: ' ') first asNumber]].
"The node clocks (the integer after '[clock ') of the lines of aSim that contain aText."
clocks := [:aSim :aText | (lines value: aSim value: aText) collect: [:l |
  ((l copyFrom: (l findString: '[clock ') + 7 to: l size) subStrings: ']') first asNumber]].
"The index of the n-th line of aTrace that contains aText, 0 when none."
index := [:aTrace :aText :n |
  | seen |
  seen := 0.
  (1 to: aTrace size) detect: [:i | ((aTrace at: i) includesSubstring: aText) and: [(seen := seen + 1) = n]] ifNone: [0]].
"The error text of aBlock, nil when it signals nothing."
errorOf := [:aBlock | [aBlock value. nil] on: Error do: [:e | e messageText]].

"(1) Determinism: the same seed gives the same trace, byte for byte."
a := run value: 11.
b := run value: 11.
c that: 'two runs of seed 11 give the same trace' is: { a = b. a size > 20 } equals: { true. true }.

"(2) Another seed, another schedule: the traces differ outside the incarnation lines."
b := run value: 12.
c that: 'seeds 11 and 12 give different schedules, not only other incarnations'
  isTrue: (a reject: [:l | l includesSubstring: ' start inc ']) ~= (b reject: [:l | l includesSubstring: ' start inc ']).

"(3) A partition stops delivery across it; heal resumes it (n0 restarted after heal echoes again)."
planted := sim value: 11 value: EchoRules new.
planted partition: #(#('n0') #('n1' 'n2')).
planted runUntil: [false] steps: 100.
count := { (lines value: planted value: 'n1 <- n0 want') size. (lines value: planted value: 'n0 <- n1 want') size.
  (lines value: planted value: 'n2 <- n1 want') size. (lines value: planted value: 'lost n0 -> n1 want') size }.
planted heal.
planted crash: 'n0' keepDisk: true.
planted restart: 'n0'.
planted runUntil: [false] steps: 100.
c that: 'a partition stops delivery and heal resumes it'
  is: { count. (lines value: planted value: 'n1 <- n0 want') size }
  equals: { #(0 0 1 1). 1 }.

"(4) A clock at 3/2 fires a 1000 us timer at 667 us of virtual time."
planted := sim value: 11 value: EchoRules new.
planted clockRate: 'n1' rate: 3/2.
planted runUntil: [false] steps: 100.
c that: 'clockRate: 3/2 fires n1''s timers earlier in virtual time'
  is: { times value: planted value: 'n0 dispatch PBTimerFired'. times value: planted value: 'n1 dispatch PBTimerFired' }
  equals: #(#(1000) #(667)).

"(5) A rate change moves the timers already set: 1/2 after the timer is set at 0."
planted := sim value: 1 value: EchoRules new.
planted runUntil: [(lines value: planted value: 'n1   -> PBTimer') notEmpty] steps: 100.
planted clockRate: 'n1' rate: 1/2.
planted runUntil: [false] steps: 100.
c that: 'a timer set before a rate change fires after its duration of the node''s clock'
  is: { times value: planted value: 'n1 dispatch PBTimerFired'. clocks value: planted value: 'n1 dispatch PBTimerFired'.
    clocks value: planted value: 'n0 dispatch PBTimerFired' }
  equals: #(#(2000) #(1000) #(1000)).

"(6) A paused clock (rate 0) fires nothing; running again, the timer has the rest of its duration."
planted := sim value: 1 value: EchoRules new.
planted runUntil: [(lines value: planted value: 'n1   -> PBTimer') notEmpty] steps: 100.
planted clockRate: 'n1' rate: 0.
count := { planted runUntil: [false] steps: 100. (lines value: planted value: 'n1 dispatch PBTimerFired') size.
  times value: planted value: 'n0 dispatch PBTimerFired' }.
planted clockRate: 'n1' rate: 1.
planted runUntil: [false] steps: 100.
c that: 'a paused clock fires no timer until it runs again'
  is: count , { times value: planted value: 'n1 dispatch PBTimerFired'. clocks value: planted value: 'n1 dispatch PBTimerFired' }
  equals: { false. 0. #(1000). #(2000). #(1000) }.

"(7) Crash modes for the unsynced tail (2 unsynced entries after 1 synced)."
modes := [:mode :seed |
  | s |
  s := sim value: seed value: TailRules new.
  s runUntil: [false] steps: 100.
  s crash: 'n2' unsynced: mode.
  (s diskOf: 'n2') size].
count := { modes value: #drop value: 11. modes value: #keep value: 11.
  (PBSimSoak seeds: (1 to: 12)) collect: [:seed | modes value: #prefix value: seed].
  (PBSimSoak seeds: (1 to: 12)) collect: [:seed | modes value: #any value: seed].
  modes value: #prefix value: 5. modes value: #prefix value: 5 }.
planted := sim value: 11 value: EchoRules new.
planted runUntil: [false] steps: 100.
planted crash: 'n2' keepDisk: true.
count := { count first. (count at: 2).
  ((count at: 3) allSatisfy: [:n | n between: 1 and: 3]) & (((count at: 3) asSet) size > 1).
  (count at: 4) allSatisfy: [:n | n between: 1 and: 3].
  (count at: 5) = (count at: 6).
  (planted diskOf: 'n2') size. (planted diskOf: 'n2') loggedRoots promise }.
planted tearLog: 'n2'.
count := count , { (planted diskOf: 'n2') size }.
planted crash: 'n1' keepDisk: false.
count := count , { (planted diskOf: 'n1') size }.
c that: 'a crash keeps the synced entries and drops, keeps or keeps a seeded prefix of the rest'
  is: count equals: { 1. 3. true. true. true. 1. 4098. 0. 0 }.

"(8) A crash between the sync and the reply: the root is accepted, the reply is lost."
planted := sim value: 11 value: ReplyLostRules new.
planted runUntil: [(lines value: planted value: 'n1 synced through 1') notEmpty] steps: 100.
planted crash: 'n1' unsynced: #drop.
planted runUntil: [false] steps: 100.
c that: 'a crash after the sync and before the reply leaves the root accepted and the reply unsent'
  is: { (planted diskOf: 'n1') loggedRoots accepted label. (lines value: planted value: 'n1   -> PBSend') size.
    (lines value: planted value: 'n0   -> PBSend') size }
  equals: #(4097 0 2).

"(9) The acceptor lane is serial; a concurrent lane is caught."
a := (PBSimSoak seeds: (1 to: 12)) collect: [:seed |
  | s tr |
  s := PBSim seed: seed ids: #('n0') rules: LaneRules new options: Dictionary new.
  s runUntil: [false] steps: 50.
  tr := s trace.
  (index value: tr value: 'n0 synced through 1' value: 1) < (index value: tr value: 'n0 reply' value: 2)].
b := ((1 to: 12) asArray collect: [:seed |
  errorOf value: [(ConcurrentLaneSim seed: seed ids: #('n0') rules: LaneRules new options: Dictionary new) runUntil: [false] steps: 50]])
  select: [:e | e notNil].
planted := PBSim seed: 1 ids: #('n0') rules: NoteRules new options: Dictionary new.
planted runUntil: [false] steps: 50.
c that: 'the acceptor lane runs one step at a time; a concurrent lane is reported; a later module adds an acceptor event'
  is: { a asSet asArray. b notEmpty. b allSatisfy: [:e | e includesSubstring: 'before its append is synced'].
    (planted diskOf: 'n0') loggedRoots promise }
  equals: { #(true). true. true. 5 }.

"(10) The checker: every planted violation is an Error naming the seed, with the trace."
failure := errorOf value: [(sim value: 11 value: TwinRootRules new) runUntil: [false] steps: 100].
a := { failure notNil and: [(failure includesSubstring: 'seed 11') and: [(failure includesSubstring: 'label 7 and epoch 1')
  and: [failure includesSubstring: ' accept PBStartNode']]] }.
failure := errorOf value: [(sim value: 11 value: TwoOwnersRules new) runUntil: [false] steps: 100].
a := a , { failure notNil and: [(failure includesSubstring: 'seed 11') and: [failure includesSubstring: 'S1']] }.
failure := errorOf value: [(EarlyReplySim seed: 11 ids: ids rules: ReplyRules new options: Dictionary new) runUntil: [false] steps: 100].
a := a , { failure notNil and: [failure includesSubstring: 'before its append is synced'] }.
failure := errorOf value: [
  planted := sim value: 11 value: LostCommitRules new.
  planted commit: 'x' at: 'n1'.
  planted runUntil: [(planted outcomeOf: 'x') = #acknowledged] steps: 100.
  planted checker checkConverged].
a := a , { failure notNil and: [(failure includesSubstring: 'seed 11') and: [failure includesSubstring: 'S4']] }.
failure := errorOf value: [
  planted := sim value: 11 value: SplitUnknownRules new.
  planted commit: 'x' at: 'n1'.
  planted converge: 100].
a := a , { failure notNil and: [failure includesSubstring: 'unknown commit ''x'''] }.
failure := errorOf value: [
  planted := sim value: 11 value: NoneHeldRules new.
  planted commit: 'x' at: 'n1'.
  planted converge: 100].
a := a , { failure notNil and: [failure includesSubstring: 'H7'] }.
failure := errorOf value: [
  planted := sim value: 11 value: ForkRules new.
  planted commit: 'x' at: 'n0'.
  planted commit: 'y' at: 'n1'.
  planted converge: 100].
a := a , { failure notNil and: [failure includesSubstring: 'fork'] }.
planted := sim value: 11 value: CommitRules new.
planted commit: 'x' at: 'n1'.
a := a , { errorOf value: [planted converge: 100]. planted outcomeOf: 'x' }.
c that: 'the checker reports each planted violation with the seed and the trace' is: a
  equals: { true. true. true. true. true. true. true. nil. #acknowledged }.

"(11) converge: answers whether the queue emptied."
planted := sim value: 11 value: CommitRules new.
planted commit: 'x' at: 'n1'.
a := { planted converge: 100 }.
planted := sim value: 11 value: TickRules new.
a := a , { planted converge: 100. (lines value: planted value: 'converge: still busy after 100 steps') size }.
c that: 'converge: answers whether the queue emptied' is: a equals: #(true false 1).

"(12) No file of the simulator or of the core in src/protobase/cluster reads a clock (STPATH names
 <repo>/src). The shells (transport.st, coordinator.st, round.st, persister.st) are the files that may; the list of core files is every
 file of the directory less them, so a new core file is checked without being named here."
failure := OSProcess shell: 'src="${STPATH%%:*}"; for f in transport coordinator round persister; do test -f "$src/protobase/cluster/$f.st" || { echo "an exempt shell is missing: $f.st"; exit 2; }; done; core=$(ls "$src"/protobase/cluster/*.st | grep -v -E ''/(transport|coordinator|round|persister)\.st$''); grep -l -E ''millisecondClockValue|microsecondClockValue|utcMicroseconds|nowUTC|__clock|Time now|Date today|DateTime now|millisecondsToRun|timeToRun|Future after|Delay'' "$src/../tests/unit/_sim.st" $core'.
c that: 'no file of the simulator or of the core in src/protobase/cluster reads a clock'
  is: { failure exitCode. failure output } equals: { 1. '' }.

"(13) Delays and reordering deliver every message, in another order (seed 11); without reorder the
 order is kept."
a := { true. false } collect: [:reorder |
  | rules s |
  rules := OrderRules new.
  s := PBSim seed: 11 ids: ids rules: rules options: Dictionary new.
  s faults: (PBSimFaults drop: 0 duplicate: 0 delay: 20000 reorder: reorder).
  "Not converge:, which ends the faults first."
  s runUntil: [rules seen size >= 50] steps: 100000.
  rules seen].
c that: 'delay:reorder: delivers every message out of send order; reorder: false keeps it'
  is: { (a first asSortedCollection: [:x :y | x <= y]) asArray = (1 to: 50) asArray. a first ~= (1 to: 50) asArray.
    a last }
  equals: { true. true. (1 to: 50) asArray }.

c report displayNl.
