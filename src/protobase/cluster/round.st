"-- cluster/round.st: PBClusterRound, the shell of a cluster node's commit round --

The commit round of a space opened with a coordinator (PBObjectSpace storage:coordinator:;
proto_db transactions.py at v2.0.0rc4: _run_round, _permit_round, _commit_base, _keep,
_take_kept, _end_kept, _drop_kept and Database.run's held retries; cluster plan Task 23). The
round's decisions are the pure core's (holder.st round:in:now: over a PBRoundState); this shell
performs its effects and hands it their answers as events. It runs on the space's round runner
(round.st), an actor: the runner hands it every commit, every PBDropKept and every answer, one
message at a time, so the state needs no lock; the state is in Atoms all the same (the module
keeps values immutable, spec 12.6).

  PBClusterRound space: aSpace publisher: aPublisher proxy: aCell
                     the round of aSpace (its coordinator, storage and tier); aCell holds the
                     runner's actor proxy, to which the answers are posted
  aRound enqueue: anEntry
                     saves the atoms anEntry's transaction wrote (before any permission, as
                     proto_db _commit saves them before it joins the group: a failure is that
                     commit's alone), then hands the core PBRoundEnqueued with a PBRoundEntry
                     whose token is anEntry itself and whose caller is anEntry's (Database.run's
                     one caller per run:, carry-over (i)); answers anEntry's Future
  aRound dropKept: aCaller
                     PBDropKept: aCaller's held retry is not coming (Database.run's finally)
  aRound close       PBRoundClosed: every commit settled (PBClosedError when nothing of it
                     left the node, PBOutcomeUnknownError once its root's replicate left it);
                     every later answer is dropped (a permission that arrives later is ended
                     #none: nothing was sent under it)

The effects, in the order of the core's step (an answer that comes at once is queued and handed
to the core after the step's other effects, never inside them):
  PBAskPermit   the coordinator's _permitWithin:; its answer (a PBPermission, or the error) comes back
                as PBPermitted.
  PBAskBase     _baseFor:; PBBaseDecided.
  PBBuild       synchronous, on the runner: the entry's build on the base's record with the
                stamp { term. epoch } (PBTransaction >> _buildOn:stamp:, PBPublisher >>
                _newDatabase:on:stamp:), nothing for a confirmation (PBCommitEntry
                confirmationDeadline:, Task 24: its PBBuilt has no root, and it settles once its
                round's base is committed), or, for a base that needs a commit first (no entry),
                the base's databases unchanged (proto_db _commit_base); the root saved in the
                storage (PBSpaceRoot databases:term:epoch:previous:), labelled with the term
                (PBLabeledRoot). The build's microseconds (Time microsecondClockValue) go into
                PBBuilt: the core's group bound (CC11) uses them, and the critical stats. A
                PBConflictError is PBBuildConflict; any other error PBBuildFailed, whose
                tierFailed is the storage's isFailed read when the failure is observed (R231).
  PBReplicate   the tier's flushLocal first (L11: the records are durable in the shared
                storage before anything that may be accepted leaves the node), then the
                coordinator's _replicateRound:under:, whose answer is PBReplicated
                (#committed, #none, or the PBOutcomeUnknownError itself); a failed flush or a
                rejected replicate is PBReplicateFailed (the core decides what was sent). The
                round notes that the replicate left (for PBRoundClosed) just before the call.
  PBReportDone  the coordinator's _done:outcome:root:, posted at once. A PBAskPermit that
                follows it in the same step is posted after it, from this actor, so both reach
                the dispatcher's mailbox in that order: the done frees the node's permission
                before the next permit asks (R148, carry-over (h)); a commit that starts while a
                kept permission ends waits, its wait counted against the permit's bound (the space's
                permit timeout, PBObjectSpace >> _permitTimeout).
  PBSettle      the PBCommitEntry's Future: true resolves it (the transaction's collections
                marked consumed, D33, and its critical section recorded: critical_commits and
                the build and replication seconds of stats), false (nothing to publish) too; an
                error rejects it with a copy of the error (one per caller); anything else is
                PBOutcomeUnknownError, never a success.
  PBTimer       Future after: the milliseconds rounded up, then the event, on the runner.
  PBCount       the coordinator's counter.
Every answer carries the round's generation: close (and the last resort) starts a new one, and
an answer of an older generation is dropped. The last resort (an error of the core or of an
effect, proto_db _run_round's except BaseException): every commit of the round is settled,
PBUnexpectedError when nothing of it was built, PBOutcomeUnknownError otherwise, and a
permission held is ended #unknown.

Every PBCommitEntry's transaction is built with its own validation and merge: the round runs no
application code. A cluster commit never writes space.root: the persisted root is the
persister's (Task 25).

This module is a shell: it reads the monotonic clock (Time microsecondClockValue for the build
and replication durations; the node's clock, the coordinator's _now, for the core) and uses
Future after: for the core's timers."

Import from: 'protobase/errors'.
Import from: 'protobase/roots'.
Import from: 'protobase/publisher'.
Import from: 'protobase/cluster/rootlog'.
Import from: 'protobase/cluster/lease'.
Import from: 'protobase/cluster/core'.
Import from: 'protobase/cluster/holder'.
Import from: 'protobase/cluster/coordinator'.

Object subclass: #PBClusterRound
  instanceVariableNames: 'space coordinator publisher proxy state inbox draining generation closed left builds sentAt'.

"The commit round of aSpace (a PBObjectSpace with a coordinator) over aPublisher; aCell (an Atom)
 holds the actor proxy of the round runner that owns the round."
PBClusterRound class >> space: aSpace publisher: aPublisher proxy: aCell
  (aSpace coordinator isKindOf: PBClusterCoordinator) ifFalse: [
    ^ PBValidationError signal: 'PBClusterRound: a space with a coordinator was expected, not ' , aSpace printString].
  ^ self basicNew _setSpace: aSpace publisher: aPublisher proxy: aCell.

PBClusterRound >> _setSpace: aSpace publisher: aPublisher proxy: aCell
  "Runs once, on a fresh instance."
  space isNil ifFalse: [^ PBUserError signal: 'PBClusterRound is initialised once'].
  space := aSpace.
  coordinator := aSpace coordinator.
  publisher := aPublisher.
  proxy := aCell.
  state := Atom on: (PBRoundState config: coordinator config).
  inbox := Atom on: #().
  draining := Atom on: false.
  generation := Atom on: 0.
  closed := Atom on: false.
  left := Atom on: false.
  builds := Atom on: Dictionary new.
  sentAt := Atom on: nil.
  ^ self.

PBClusterRound >> coordinator
  ^ coordinator.

PBClusterRound >> storage
  ^ space storage.

"The PBRoundState (for tests and diagnostics)."
PBClusterRound >> roundState
  ^ state value.

"=== the messages (from the runner, on its actor) ============================="

"Saves the atoms anEntry wrote, then queues it in the core; answers its Future."
PBClusterRound >> enqueue: anEntry
  | failure |
  closed value ifTrue: [
    anEntry future rejectWith: (PBClosedError new messageText: 'PBObjectSpace is closed'; yourself).
    ^ anEntry future].
  failure := nil.
  [anEntry writtenAtoms do: [:each | self storage save: each]] on: Error do: [:e | failure := e. e return: nil].
  failure isNil ifFalse: [
    anEntry future rejectWith: failure.
    ^ anEntry future].
  self _handle: (PBRoundEnqueued entry: (PBRoundEntry token: anEntry caller: anEntry caller
    willRetry: anEntry willRetry deadline: nil)).
  ^ anEntry future.

PBClusterRound >> dropKept: aCaller
  closed value ifTrue: [^ self].
  self _handle: (PBDropKept caller: aCaller).

"An answer posted by an effect of generation anInteger: handed to the core unless the round
 closed or moved to another generation since (_stale:)."
PBClusterRound >> event: anEvent generation: anInteger
  (closed value or: [anInteger ~= generation value]) ifTrue: [^ self _stale: anEvent].
  self _handle: anEvent.

"aBlock, posted by _later: in generation anInteger, runs unless the round closed or moved on."
PBClusterRound >> do: aBlock generation: anInteger
  (closed value or: [anInteger ~= generation value]) ifTrue: [^ self].
  [aBlock value] on: Error do: [:e | self _abandon: e. e return: nil].

"Closes the round (Review Focus 1): PBRoundClosed with whether the last replicate left the node;
 a new generation drops every answer still coming. Idempotent; answers nil."
PBClusterRound >> close
  (closed value: true ifCurrent: false) ifFalse: [^ nil].
  generation swap: [:g | g + 1].
  inbox swap: [:q | #()].
  self _step: (PBRoundClosed left: left value).
  ^ nil.

"An answer nobody waits for any more. A permission it carries ends #none (nothing was sent under
 it): the node frees it at once instead of at its expiry."
PBClusterRound >> _stale: anEvent
  ((anEvent isKindOf: PBPermitted) and: [anEvent permission isKindOf: PBPermission]) ifTrue: [
    [self _sendDone: anEvent permission outcome: #none root: nil] on: Error do: [:e | e return: nil]].

"=== the core ================================================================"

"Hands anEvent to the core after the events queued before it: an effect that answers at once
 queues its event here, so the core never runs inside a step's effects."
PBClusterRound >> _handle: anEvent
  inbox swap: [:q | q copyWith: anEvent].
  draining value ifTrue: [^ self].
  draining swap: [:old | true].
  [[inbox value isEmpty] whileFalse: [| next |
     next := inbox value first.
     inbox swap: [:q | q copyFrom: 2 to: q size].
     self _step: next]]
    ensure: [draining swap: [:old | false]].

"One step of the core at the node's clock, then its effects in order. An answer to the
 replicate clears the note that it left; a #committed one publishes its root to the node's
 readers (PBClusterCoordinator >> _publishCommitted:, what a snapshot starts from, space.st
 _snapshotRecord) before any commit of the round is settled: a commit reads its own write, even
 before the node's acceptor has learnt it (Task 24)."
PBClusterRound >> _step: anEvent
  | step |
  ((anEvent isKindOf: PBReplicated) or: [anEvent isKindOf: PBReplicateFailed]) ifTrue: [left swap: [:old | false]].
  ((anEvent isKindOf: PBReplicated) and: [anEvent outcome = #committed]) ifTrue: [
    state value current isNil ifFalse: [coordinator _publishCommitted: state value current]].
  step := [coordinator _rules round: anEvent in: (state value withRejoinBallot: self _rejoinBallot) now: coordinator _now]
    on: Error do: [:e | self _abandon: e. e return: nil].
  step isNil ifTrue: [^ self].
  state swap: [:old | step state].
  step effects do: [:fx | | failed |
    failed := false.
    [fx applyTo: self] on: Error do: [:e | self _abandon: e. failed := true. e return: nil].
    failed ifTrue: [^ self]].

"The rejoin ballot of the node's acceptor (L14), 0 before it has one."
PBClusterRound >> _rejoinBallot
  | a |
  a := coordinator acceptorState.
  ^ a isNil ifTrue: [0] ifFalse: [a rejoinBallot].

"The last resort (proto_db _run_round's except BaseException): every commit the round holds is
 settled, PBUnexpectedError when nothing of it was built (queued, asking for a permission or not
 built yet), PBOutcomeUnknownError when it was built or building (its root may have left); a
 permission held ends #unknown; the round starts again, idle, in a new generation."
PBClusterRound >> _abandon: anError
  | s cause unbuilt unknown |
  s := state value.
  generation swap: [:g | g + 1].
  inbox swap: [:q | #()].
  left swap: [:old | false].
  state swap: [:old | (PBRoundState config: coordinator config) with: { #nextToken -> s nextToken }].
  cause := anError class name , ': ' , (anError messageText ifNil: ['(no message)']).
  unbuilt := PBUnexpectedError new messageText: 'The cluster commit round failed (' , cause
    , '); nothing of the commit was sent'; yourself.
  unknown := PBOutcomeUnknownError new messageText: 'The cluster commit round failed (' , cause
    , '); the outcome of the commit is unknown'; yourself.
  s queue , s batch , s live do: [:e | self _reject: e token with: unbuilt].
  (s built collect: [:b | b first]) , (s conflicted collect: [:c | c first])
    , (s building isNil ifTrue: [#()] ifFalse: [{ s building }]) do: [:e | self _reject: e token with: unknown].
  s permission isNil ifFalse: [
    [self _sendDone: s permission outcome: #unknown root: nil] on: Error do: [:e | e return: nil]].

PBClusterRound >> _reject: anEntry with: anError
  [anEntry future rejectWith: anError copy] on: Error do: [:e | e return: nil].

"=== the effects (PBEffect >> applyTo:) ======================================"

PBClusterRound >> applyAskPermit: anEffect
  self _answer: self _askPermit with: [:v | PBPermitted permission: v].

PBClusterRound >> applyAskBase: anEffect
  self _answer: (self _askBase: anEffect permission) with: [:v | PBBaseDecided decision: v].

"Synchronous: the build and its save; the answer is queued (_handle:)."
PBClusterRound >> applyBuild: aBuild
  | t0 event |
  t0 := Time microsecondClockValue.
  event := [| root micros |
      root := self _build: aBuild.
      micros := Time microsecondClockValue - t0.
      aBuild entry isNil ifFalse: [
        builds swap: [:d | | copy | copy := d copy. copy at: aBuild entry token put: micros. copy]].
      PBBuilt entry: aBuild entry root: root micros: micros]
    on: Error do: [:e |
      e return: ((e isKindOf: PBConflictError)
        ifTrue: [PBBuildConflict entry: aBuild entry error: e]
        ifFalse: [PBBuildFailed entry: aBuild entry error: e tierFailed: self _tierFailed])].
  self _handle: event.

PBClusterRound >> applyReplicate: aReplicate
  self _send: aReplicate.

"Posted at once; a failure to post is left to the permission's expiry (the node ends it)."
PBClusterRound >> applyReportDone: anEffect
  [(self _sendDone: anEffect permission outcome: anEffect outcome root: anEffect root) catch: [:e | nil]]
    on: Error do: [:e | e return: nil].

PBClusterRound >> applySettle: aSettle
  | entry outcome micros |
  entry := aSettle waiter.
  outcome := aSettle outcome.
  micros := builds value at: entry ifAbsent: [0].
  builds swap: [:d | | copy | copy := d copy. copy removeKey: entry ifAbsent: [nil]. copy].
  (outcome isKindOf: Exception) ifTrue: [^ self _reject: entry with: outcome].
  outcome == true ifTrue: [
    entry transaction ifNotNil: [:t | [t _markConsumed] on: Error do: [:e | e return: nil]].
    coordinator _recordCritical: micros replication: (sentAt value isNil ifTrue: [0] ifFalse: [Time microsecondClockValue - sentAt value]).
    ^ entry future resolve: true].
  outcome == false ifTrue: [^ entry future resolve: true].
  ^ self _reject: entry with: (PBOutcomeUnknownError new messageText: 'The cluster commit round left the commit undecided ('
    , outcome printString , '); its outcome is unknown'; yourself).

PBClusterRound >> applyTimer: aTimer
  | event |
  event := aTimer event.
  self _later: [self _handle: event] after: (aTimer after + 999 // 1000 max: 0).

PBClusterRound >> applyCount: aCount
  coordinator _count: aCount stat.

"=== the shell's steps (seams: a test subclass overrides one) ================="

"The permit (a Future), its wait bounded by the space's permit timeout (proto_db _run_round's
 permit(lock_timeout): the space's lockTimeout when one was given, else acquireTimeout)."
PBClusterRound >> _askPermit
  ^ coordinator _permitWithin: space _permitTimeout.

"The base under aPermission (a Future)."
PBClusterRound >> _askBase: aPermission
  ^ coordinator _baseFor: aPermission.

"The root of aBuild, saved and labelled: a PBLabeledRoot; nil for a confirmation (proto_db
 _confirm_build: nothing to publish)."
PBClusterRound >> _build: aBuild
  | stamp root pointer |
  (aBuild entry notNil and: [aBuild entry token isConfirmation]) ifTrue: [^ nil].
  stamp := aBuild stamp.
  root := aBuild entry isNil
    ifTrue: [self _recommitRootOn: aBuild base record stamp: stamp]
    ifFalse: [publisher _build: aBuild entry token on: aBuild base record stamp: stamp].
  pointer := self storage save: root.
  ^ PBLabeledRoot label: stamp first
    record: (PBRootRecord segment: pointer segmentBytes offset: pointer offset epoch: stamp last).

"proto_db _commit_base: the databases of the root aRecord, unchanged, stamped aStamp, built on it."
PBClusterRound >> _recommitRootOn: aRecord stamp: aStamp
  | current |
  current := space _spaceRootAt: aRecord.
  current isNil ifTrue: [^ PBValidationError signal: 'PBClusterRound: the empty space is never re-committed'].
  ^ PBSpaceRoot databases: current databases stamp: aStamp previous: current.

"Whether the storage has failed, read when a build's failure is observed (R231)."
PBClusterRound >> _tierFailed
  ^ self storage isFailed.

"Sends aReplicate now (_sendNow:)."
PBClusterRound >> _send: aReplicate
  ^ self _sendNow: aReplicate.

"L11: the tier flushed, then the replicate, noted as left just before it is asked."
PBClusterRound >> _sendNow: aReplicate
  | failure now |
  failure := nil.
  [space _tier flushLocal] on: Error do: [:e | failure := e. e return: nil].
  failure isNil ifFalse: [^ self _handle: (PBReplicateFailed error: failure)].
  left swap: [:old | true].
  now := Time microsecondClockValue.
  sentAt swap: [:old | now].
  self _answer: (self _replicate: aReplicate root under: aReplicate permission) with: [:v |
    ((v isKindOf: Exception) and: [(v isKindOf: PBOutcomeUnknownError) not])
      ifTrue: [PBReplicateFailed error: v]
      ifFalse: [PBReplicated outcome: v]].

"The coordinator's replicate of the round (a Future)."
PBClusterRound >> _replicate: aRoot under: aPermission
  ^ coordinator _replicateRound: aRoot under: aPermission.

"The done of aPermission (a Future)."
PBClusterRound >> _sendDone: aPermission outcome: anOutcome root: aRootOrNil
  ^ coordinator _done: aPermission outcome: anOutcome root: aRootOrNil.

"aFuture's value or error, as the event aBlock makes of it, posted to the runner with the
 current generation (the callback runs on a worker)."
PBClusterRound >> _answer: aFuture with: aBlock
  | g p |
  g := generation value.
  p := proxy value.
  aFuture
    thenDo: [:v | p _clusterEvent: (aBlock value: v) generation: g];
    catch: [:e | p _clusterEvent: (aBlock value: e) generation: g].

"aBlock, run on the runner as a later message of the current generation."
PBClusterRound >> _later: aBlock
  proxy value _clusterDo: aBlock generation: generation value.

"aBlock, run on the runner after ms milliseconds, in the current generation."
PBClusterRound >> _later: aBlock after: ms
  | g p |
  g := generation value.
  p := proxy value.
  (Future after: ms) thenDo: [:x | p _clusterDo: aBlock generation: g].

PBClusterRound >> printOn: aStream
  aStream nextPutAll: 'PBClusterRound('; nextPutAll: coordinator nodeId; nextPut: $).
