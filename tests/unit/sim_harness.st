"EXPECT: ok 7"
"The deterministic simulator (_sim.st) over the core vocabulary (cluster/core.st), with test
 rules: EchoRules sends a want to every other member, sets one timer (1000 us) and hands its
 PBStartNode to its acceptor, which logs a synced promise and an unsynced committed entry. The
 same seed and schedule give the same trace byte for byte, another seed another trace; a
 partition stops delivery across it and heal resumes it; a clock running at 3/2 fires its
 timer at 667 us of virtual time where a clock at rate 1 fires at 1000 us; a crash that keeps
 the disk loses the unsynced entry and tearLog: cuts the last synced frame. The checker reports
 every planted violation with the seed and the trace: two roots with equal (label, epoch) on
 two nodes, two owners of one term (S1), a reply performed before its append is synced (a
 simulator plant), an acknowledged commit missing from a member's committed chain (S4) and an
 unknown commit present on one member only; a commit every member learns converges. No file
 of the simulator or of src/protobase/cluster reads a wall clock."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_sim'.

"--- test rules ---"

PBCoordinatorCore subclass: #EchoRules.

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
  ^ PBStep state: s effects: { PBSettle waiter: anEvent waiter outcome: (PBLabeledRoot label: 0 record: nil) }.

CommitRules >> outcome
  ^ #committed.

CommitRules >> _done: anEvent in: s
  ^ PBClusterMessage type: 'done' from: s config nodeId fields: {
    'term' -> anEvent permission term. 'seq' -> 1. 'inc' -> s inc. 'outcome' -> 'committed'.
    'root' -> (PBClusterMessage rootValue: anEvent root). 'copies' -> #(). 'ranges' -> nil }.

CommitRules >> dispatchReplicateWanted: anEvent in: s now: t
  ^ PBStep state: s effects: { PBSettle waiter: anEvent waiter outcome: self outcome. PBPublishCommitted root: anEvent root }
    , ((self _others: s) collect: [:id | PBSend to: id message: (self _done: anEvent in: s)]).

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

"--- the checks ---"

| c ids sim run lines times count failure a b planted errorOf |
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
"The error text of aBlock, nil when it signals nothing."
errorOf := [:aBlock | [aBlock value. nil] on: Error do: [:e | e messageText]].

"Determinism: the same seed gives the same trace, byte for byte."
a := run value: 11.
b := run value: 11.
c that: 'two runs of seed 11 give the same trace' is: { a = b. a size > 20 } equals: { true. true }.

"Another seed, another trace."
c that: 'seeds 11 and 12 give different traces' isTrue: (run value: 12) ~= a.

"A partition stops delivery across it; heal resumes it (n0 restarted after heal echoes again)."
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

"A clock at 3/2 fires a 1000 us timer at 667 us of virtual time."
planted := sim value: 11 value: EchoRules new.
planted clockRate: 'n1' rate: 3/2.
planted runUntil: [false] steps: 100.
c that: 'clockRate: 3/2 fires n1''s timers earlier in virtual time'
  is: { times value: planted value: 'n0 dispatch PBTimerFired'. times value: planted value: 'n1 dispatch PBTimerFired' }
  equals: #(#(1000) #(667)).

"A crash that keeps the disk drops the unsynced committed entry; tearLog: cuts the last synced frame."
planted := sim value: 11 value: EchoRules new.
planted runUntil: [false] steps: 100.
count := { (planted diskOf: 'n2') size. (planted diskOf: 'n2') syncedSize }.
planted crash: 'n2' keepDisk: true.
count := count , { (planted diskOf: 'n2') size. (planted diskOf: 'n2') loggedRoots promise }.
planted tearLog: 'n2'.
count := count , { (planted diskOf: 'n2') size }.
planted crash: 'n1' keepDisk: false.
count := count , { (planted diskOf: 'n1') size }.
c that: 'a crash drops the unsynced append, tearLog: the last synced frame, a lost disk everything'
  is: count equals: { 2. 1. 1. 4098. 0. 0 }.

"The checker: every planted violation is an Error naming the seed, with the trace."
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
planted := sim value: 11 value: CommitRules new.
planted commit: 'x' at: 'n1'.
a := a , { errorOf value: [planted converge: 100]. planted outcomeOf: 'x' }.
c that: 'the checker reports each planted violation with the seed and the trace' is: a
  equals: { true. true. true. true. true. nil. #acknowledged }.

"No step reads a wall clock."
failure := OSProcess shell: 'grep -l -e millisecondClockValue -e microsecondClockValue -e utcMicroseconds -e nowUTC _sim.st ../../src/protobase/cluster/*.st'.
c that: 'no file of the simulator or of src/protobase/cluster reads a wall clock'
  is: { failure exitCode. failure output } equals: { 1. '' }.

c report displayNl.
