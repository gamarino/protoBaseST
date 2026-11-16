"-- round.st: PBRoundRunner and PBCommitEntry, the space's commit queue --

The round runner of a space (cluster design spec 5.6, CC10, CC22; proto_db
transactions.py at v2.0.0rc3: _commit_root, _Entry, _Group and, for a
standalone storage, _standalone_round, decision D52). Every commit and every
new database of a PBObjectSpace is a PBCommitEntry queued on the space's
runner; the caller waits only on the entry's Future.

  PBCommitEntry transaction: aTx willRetry: aBoolean deadline: us
                              the commit of aTx (in the state #committing);
                              willRetry: whether the caller retries a
                              conflict (Database.run), read by the cluster
                              round (Task 23), unused by a standalone round;
                              us the monotonic microsecond
                              (Time microsecondClockValue) after which a
                              commit still waiting for the root lock ends in
                              PBTimeoutError
  PBCommitEntry transaction: aTx willRetry: aBoolean caller: anObject deadline: us
                              as above, from the caller anObject (one per
                              Database.run: its held retries, cluster/round.st);
                              without it the entry is its own caller
  PBCommitEntry createDatabase: aName deadline: us
                              version 0 of the database aName
  PBCommitEntry confirmationDeadline: us
                              a confirmation (cluster mode only, Task 24,
                              proto_db _confirm_build): a commit that
                              writes nothing; its round obtains a write
                              permission and commits its base first when
                              it needs a commit
  anEntry future              the Future the runner settles: true when
                              published, rejected with the commit's error
  PBRoundRunner space: aSpace the runner of aSpace, an actor of the medium
                              band (asActor); answers its proxy
  aRunner enqueue: anEntry    adds anEntry to the queue and answers its
                              Future; nothing else (see below)
  aRunner closeStorage        a round of what is queued, then the storage is
                              closed; a Future of nil
  aRunner closeRound          a space with a coordinator: its cluster round is
                              closed (PBClusterRound >> close); a Future of nil
  aRunner dropKept: aCaller   a space with a coordinator: PBDropKept (a held
                              retry that is not coming); nothing otherwise
  aRunner persist: aRoot      a space with a coordinator: the persister's write
                              of aRoot, the tier's persist: on this actor
                              (cluster/persister.st); a Future of true, false
                              or #busy

With a coordinator (PBObjectSpace storage:coordinator:) the runner hands every
entry, every dropKept: and every answer of the coordinator to its
PBClusterRound (cluster/round.st), on this actor (carry-over (j): the runner is
its own actor), and none of the standalone protocol below runs: no root lock,
no space.root.

A standalone round takes the whole queue, in the order it was queued, and
hands it to PBPublisher >> publishGroup: (publisher.st): one root lock, one
root read, each entry built on the root the previous build saved, one flush
and one publish; a lone entry is exactly the single-commit protocol. The
answer has one result per entry: true, an Exception (that entry's error, or
the round's, which reaches every built entry), or #locked (nothing was
decided: the root lock is held by another process or storage). Only true is
reported as a success: any other result (which publishGroup: never answers)
is PBOutcomeUnknownError, never a guess. Every entry a round takes is
settled (proto_db _standalone_round's except BaseException): an error while
settling one entry settles that one with an error naming the cause, and any
other error of the round settles every entry it took and not settled yet,
and takes them out of the queue. The error is PBUnexpectedError when the
entry's result was #locked (nothing of it was published) and
PBOutcomeUnknownError otherwise (the round may have published it). Rounds run
one at a time: a round is a message of this actor, and the entries queued
while it runs form the next one.

The runner owns the lock retry (CC10, which supersedes the caller's backoff
of ruling R19; proto_db holds the lock with a timeout instead). After a
#locked round, each entry whose deadline has passed is rejected with
PBTimeoutError, with the text lockTimeout always had ('Could not acquire the
root lock within <lockTimeout> ms (held by another process or storage)');
the others go back to the head of the queue, and the next round is scheduled
with Future after: d, d from firstLockDelay (1 ms) doubling up to
longestLockDelay (50 ms), never past the nearest deadline (ProtoBase
FileStorage._acquire_process_lock's 0.001 s doubling up to 0.05 s). A round
that takes the lock resets d. Each entry keeps the deadline it was queued
with.

The runner never waits (ruling R19's other half, carry-over (j) of cluster
plan Task 20): no method of this module sends wait, so a round is never
driven synchronously from a caller's thread (its block or its wait), and the
actor never blocks its worker. enqueue: only adds the entry; a round runs as
a message the runner sends to itself (through its proxy) or as the callback
of a Future after: timer. tests/unit/round_lock_retry.st scans this file's
code for it.

This module reads the monotonic clock (Time microsecondClockValue) and uses
Future after: for the retry. Every value is immutable but the runner's
cells: Atoms created by its initialiser and changed only on the actor."

Import from: 'protobase/errors'.
Import from: 'protobase/publisher'.
Import from: 'protobase/cluster/round'.

"=== PBCommitEntry ============================================================"

Object subclass: #PBCommitEntry instanceVariableNames: 'transaction databaseName willRetry caller deadline future'.

PBCommitEntry class >> transaction: aTransaction willRetry: aBoolean deadline: microseconds
  ^ self transaction: aTransaction willRetry: aBoolean caller: nil deadline: microseconds.

PBCommitEntry class >> transaction: aTransaction willRetry: aBoolean caller: anObject deadline: microseconds
  aTransaction isNil ifTrue: [^ PBValidationError signal: 'PBCommitEntry transaction: a transaction was expected, not nil'].
  ^ self basicNew _setTransaction: aTransaction name: nil willRetry: aBoolean caller: anObject deadline: microseconds.

PBCommitEntry class >> createDatabase: aName deadline: microseconds
  aName isNil ifTrue: [^ PBValidationError signal: 'PBCommitEntry createDatabase: a database name was expected, not nil'].
  ^ self basicNew _setTransaction: nil name: aName willRetry: false caller: nil deadline: microseconds.

"A confirmation of the committed root (space.st _confirm; proto_db _read_storage_root's empty
 commit under the lease): no transaction, no database; the cluster round builds nothing for it."
PBCommitEntry class >> confirmationDeadline: microseconds
  ^ self basicNew _setTransaction: nil name: nil willRetry: false caller: nil deadline: microseconds.

PBCommitEntry >> _setTransaction: aTransaction name: aName willRetry: aBoolean caller: anObject deadline: microseconds
  "Runs once, on a fresh instance."
  future isNil ifFalse: [^ PBUserError signal: 'PBCommitEntry is immutable'].
  (aBoolean == true or: [aBoolean == false]) ifFalse: [
    ^ PBValidationError signal: 'PBCommitEntry: willRetry is a Boolean, not ' , aBoolean printString].
  (microseconds isKindOf: SmallInteger) ifFalse: [
    ^ PBValidationError signal: 'PBCommitEntry: deadline is a SmallInteger of monotonic microseconds, not '
      , microseconds printString].
  transaction := aTransaction.
  databaseName := aName.
  willRetry := aBoolean.
  caller := anObject.
  deadline := microseconds.
  future := Future new.
  ^ self.

"The transaction committed, nil for a new database or a confirmation."
PBCommitEntry >> transaction
  ^ transaction.

"The name of the database created, nil for a commit or a confirmation."
PBCommitEntry >> databaseName
  ^ databaseName.

PBCommitEntry >> isCreateDatabase
  ^ transaction isNil and: [databaseName notNil].

"Whether the entry is a confirmation (confirmationDeadline:)."
PBCommitEntry >> isConfirmation
  ^ transaction isNil and: [databaseName isNil].

PBCommitEntry >> willRetry
  ^ willRetry.

"Who commits: the object Database.run made for its attempts (the held retries of one caller,
 cluster/round.st), else the entry itself."
PBCommitEntry >> caller
  ^ caller ifNil: [self].

"The monotonic microsecond after which a commit still waiting for the root
 lock ends in PBTimeoutError."
PBCommitEntry >> deadline
  ^ deadline.

PBCommitEntry >> future
  ^ future.

"The atoms written as roots or cells, saved at step 0 of every attempt (none
 for a new database)."
PBCommitEntry >> writtenAtoms
  ^ transaction isNil ifTrue: [#()] ifFalse: [transaction _writtenAtoms].

PBCommitEntry >> printOn: aStream
  aStream nextPutAll: 'PBCommitEntry('.
  self isConfirmation ifTrue: [aStream nextPutAll: 'confirmation'].
  self isCreateDatabase ifTrue: [aStream nextPutAll: 'createDatabase '; print: databaseName].
  transaction isNil ifFalse: [aStream print: transaction].
  aStream nextPut: $).

"=== PBRoundRunner ============================================================"

Object subclass: #PBRoundRunner instanceVariableNames: 'space publisher queue scheduled delay proxy cluster'.

"The first retry delay after a #locked round, and the longest, in
 milliseconds (ProtoBase FileStorage._acquire_process_lock: 0.001 s doubling
 up to 0.05 s)."
PBRoundRunner class >> firstLockDelay
  ^ 1.

PBRoundRunner class >> longestLockDelay
  ^ 50.

"The runner of aSpace (a PBObjectSpace) with its publisher: answers the actor
 proxy (medium band). The proxy is published to the runner's own cell before
 any message reaches it, so a round can schedule the next one."
PBRoundRunner class >> space: aSpace
  ^ self space: aSpace publisher: (PBPublisher space: aSpace).

"The runner of aSpace over aPublisher (a PBPublisher of aSpace): the seam a test
 uses to supply its own publisher (PBObjectSpace >> _newRunner). Answers the
 actor proxy."
PBRoundRunner class >> space: aSpace publisher: aPublisher
  | runner actor cell |
  cell := Atom on: nil.
  runner := self basicNew _setSpace: aSpace publisher: aPublisher queue: (Atom on: #())
    scheduled: (Atom on: false) delay: (Atom on: self firstLockDelay) proxy: cell
    cluster: (aSpace coordinator isNil ifTrue: [nil] ifFalse: [aSpace _newClusterRound: aPublisher proxy: cell]).
  actor := runner asActor.
  runner _publishProxy: actor.
  ^ actor.

PBRoundRunner >> _setSpace: aSpace publisher: aPublisher queue: aQueue scheduled: aScheduled delay: aDelay proxy: aProxy cluster: aRound
  "Runs once, on a fresh instance."
  space isNil ifFalse: [^ PBUserError signal: 'PBRoundRunner is initialised once'].
  space := aSpace.
  publisher := aPublisher.
  queue := aQueue.
  scheduled := aScheduled.
  delay := aDelay.
  proxy := aProxy.
  cluster := aRound.
  ^ self.

"Sets the proxy cell once (from nil), before the proxy is answered."
PBRoundRunner >> _publishProxy: anActor
  (proxy value: anActor ifCurrent: nil) ifFalse: [^ PBUserError signal: 'PBRoundRunner: the proxy is set once'].

"=== the messages (on the actor) =============================================="

"Makes sure a round is coming, then adds anEntry (a PBCommitEntry) to the
 queue, and answers the entry's Future. It runs no round itself. The round
 posted runs after this method (one message at a time), so it finds the
 entry queued. A failed post signals before the entry is queued: the entry is
 never decided, and the caller is rejected with that error
 (PBObjectSpace >> _commitEntry:), review n2."
PBRoundRunner >> enqueue: anEntry
  (anEntry isKindOf: PBCommitEntry) ifFalse: [
    ^ PBValidationError signal: 'PBRoundRunner enqueue: a PBCommitEntry was expected, not ' , anEntry printString].
  cluster isNil ifFalse: [^ cluster enqueue: anEntry].
  self _schedule.
  queue swap: [:entries | entries copyWith: anEntry].
  ^ anEntry future.

"Runs a round of what is queued (the entries queued before the close commit
 or fail as they would have), then closes the storage, between two rounds,
 never during one. Entries left waiting for the lock meet the closed storage
 in their next round (PBClosedError). The round is run directly
 (_runRound), so a round already coming stays the one that is coming: no
 second retry chain is started (review m4). Answers nil."
PBRoundRunner >> closeStorage
  cluster isNil ifFalse: [
    cluster close.
    publisher closeStorage.
    ^ nil].
  queue value isEmpty ifFalse: [self _runRound].
  publisher closeStorage.
  ^ nil.

"--- the cluster round (a space with a coordinator) ---"

"Closes the cluster round: every commit it holds is settled (PBClusterRound >> close). Answers
 nil; nothing without a coordinator."
PBRoundRunner >> closeRound
  cluster isNil ifFalse: [cluster close].
  ^ nil.

"The persister's write of aLabeledRoot (cluster/persister.st): the tier's persist: (true, false or
 #busy), made on this actor, the one that makes every other write of the node's storage (the
 round's pushAtom: and flushSegment), so the root lock persist: takes and releases never overlaps
 them (Task 21 review I1). PBValidationError without a coordinator."
PBRoundRunner >> persist: aLabeledRoot
  cluster isNil ifTrue: [^ PBValidationError signal: 'PBRoundRunner persist: needs a space with a coordinator'].
  ^ space _tier persist: aLabeledRoot.

"aCaller's held retry is not coming (Database.run): PBDropKept. Nothing without a coordinator."
PBRoundRunner >> dropKept: aCaller
  cluster isNil ifFalse: [cluster dropKept: aCaller].
  ^ nil.

"An answer of the coordinator to an effect of the cluster round's generation anInteger."
PBRoundRunner >> _clusterEvent: anEvent generation: anInteger
  cluster event: anEvent generation: anInteger.
  ^ nil.

"aBlock, posted by the cluster round to run later on this actor (PBClusterRound >> _later:)."
PBRoundRunner >> _clusterDo: aBlock generation: anInteger
  cluster do: aBlock generation: anInteger.
  ^ nil.

"The message of a round (posted by _schedule, or sent by a retry timer): the
 round that was coming is now running, so a later one may be scheduled."
PBRoundRunner >> _round
  scheduled swap: [:old | false].
  self _runRound.

"One round: takes the whole queue, publishes it as one group and settles each
 entry, or, when the root lock is held, settles the entries past their
 deadline and schedules the retry of the others. Every entry taken is
 settled (proto_db _standalone_round's except BaseException, review m1): an
 error while settling one entry settles that entry alone (_failure:of:);
 any other error of the round after the batch was taken settles every entry
 of the batch not settled yet and takes them out of the queue
 (_abandon:settled:results:cause:). So no caller waits for ever on its Future."
PBRoundRunner >> _runRound
  | batch settled results kept now |
  batch := queue value.
  queue swap: [:entries | #()].
  batch isEmpty ifTrue: [^ self].
  settled := Array new: batch size withAll: false.
  [results := [publisher publishGroup: batch] on: Error do: [:e |
     "publishGroup: answers every error as a result; an error here is the
      round's own and reaches every entry."
     e return: (Array new: batch size withAll: e)].
   kept := OrderedCollection new.
   now := Time microsecondClockValue.
   1 to: batch size do: [:i | | entry result |
     entry := batch at: i.
     result := results at: i.
     [(result == #locked and: [now < entry deadline])
        ifTrue: [kept addLast: entry]
        ifFalse: [
          settled at: i put: true.
          self _settle: entry with: result]]
       on: Error do: [:e |
         "settled only once the rejection has returned (review n1): if even
          the fallback fails, the last resort still covers this entry."
         self _reject: entry with: [self _failure: e of: result while: 'settling the commit'].
         settled at: i put: true.
         e return: nil]].
   kept isEmpty ifTrue: [
     (results includes: #locked) ifFalse: [delay swap: [:d | PBRoundRunner firstLockDelay]].
     queue value isEmpty ifFalse: [self _schedule].
     ^ self].
   queue swap: [:entries | kept asArray , entries].
   self _retryAfterLockFor: kept now: now]
    on: Error do: [:e |
      self _abandon: batch settled: settled results: results cause: e.
      e return: nil].

"Settles anEntry with the round's result for it: true is a success; #locked
 (past the deadline) is PBTimeoutError; an Exception is the entry's error;
 anything else is undecided: PBOutcomeUnknownError, never a success."
PBRoundRunner >> _settle: anEntry with: aResult
  aResult == true ifTrue: [^ anEntry future resolve: true].
  aResult == #locked ifTrue: [^ anEntry future rejectWith: self _timeoutError].
  (aResult isKindOf: Exception) ifTrue: [^ anEntry future rejectWith: aResult].
  ^ anEntry future rejectWith: (self _undecidedError: aResult).

"The last resort of a round that failed after it took batch: every entry not
 settled yet is rejected with the cause, and taken out of the queue (a kept
 entry was put back before its retry could be scheduled). One rejection that
 fails never skips the others."
PBRoundRunner >> _abandon: batch settled: settled results: results cause: anError
  [queue swap: [:entries | entries reject: [:each | batch anySatisfy: [:taken | taken == each]]]]
    on: Error do: [:e | e return: nil].
  1 to: batch size do: [:i |
    (settled at: i) ifFalse: [
      [self _reject: (batch at: i) with: [self _failure: anError
          of: (results isNil ifTrue: [nil] ifFalse: [results at: i]) while: 'deciding the round']]
        on: Error do: [:e | e return: nil]]].

"Rejects anEntry with the error anErrorBlock builds; when building it or the
 rejection fails, with the fixed fallback (_fallbackError), which needs
 nothing of the cause. A failure of that fallback rejection signals."
PBRoundRunner >> _reject: anEntry with: anErrorBlock
  [anEntry future rejectWith: anErrorBlock value]
    on: Error do: [:e |
      anEntry future rejectWith: self _fallbackError.
      e return: nil].

PBRoundRunner >> _fallbackError
  ^ PBOutcomeUnknownError new messageText: 'The commit round failed unexpectedly; the outcome of the commit is unknown'; yourself.

"The error of an entry whose round failed with anError while aString: the
 cause is named. PBUnexpectedError when the entry's result was #locked
 (nothing of it was published: the root lock was held); PBOutcomeUnknownError
 otherwise, since the round may have published it."
PBRoundRunner >> _failure: anError of: aResult while: aString
  | cause |
  cause := anError class name , ': ' , (anError messageText ifNil: ['(no message)']).
  aResult == #locked ifTrue: [
    ^ PBUnexpectedError new messageText: 'The commit round failed while ' , aString , ' (' , cause
      , '); nothing of the commit was published (the root lock was held)'; yourself].
  ^ PBOutcomeUnknownError new messageText: 'The commit round failed while ' , aString , ' (' , cause
    , '); the outcome of the commit is unknown'; yourself.

"Schedules the next round after a #locked round: after the current delay,
 never past the nearest deadline of aCollection's entries, and doubles the
 delay up to longestLockDelay. Nothing when a round is already coming (a
 posted message or a pending timer, after closeStorage's direct round): that
 round takes the entries put back (review m4)."
PBRoundRunner >> _retryAfterLockFor: aCollection now: microseconds
  | nearest ms actor |
  scheduled value ifTrue: [^ self].
  nearest := aCollection inject: aCollection first deadline into: [:soonest :entry | soonest min: entry deadline].
  ms := delay value min: (nearest - microseconds + 999 // 1000 max: 0).
  delay swap: [:d | d * 2 min: PBRoundRunner longestLockDelay].
  scheduled swap: [:old | true].
  actor := proxy value.
  (Future after: ms) thenDo: [:x | actor _round].

"Sends _round to the runner's own proxy unless a round is already coming (a
 message posted or a retry timer pending). scheduled is set only once the post
 has returned: a post that fails leaves it false, so the next enqueue: posts
 again (review n2)."
PBRoundRunner >> _schedule
  scheduled value ifTrue: [^ self].
  self _postRound.
  scheduled swap: [:old | true].

"Posts a round to the runner's own proxy (a seam: a test makes it fail)."
PBRoundRunner >> _postRound
  proxy value _round.

PBRoundRunner >> _timeoutError
  ^ PBTimeoutError new messageText: 'Could not acquire the root lock within ' , space lockTimeout printString
    , ' ms (held by another process or storage)'; yourself.

"A result that is neither true, an Exception nor #locked: the round left the
 entry undecided, which publishGroup: never does. Never reported as a
 success: the outcome is not known."
PBRoundRunner >> _undecidedError: aResult
  ^ PBOutcomeUnknownError new messageText: 'The commit round left the commit undecided (' , aResult printString
    , '); its outcome is unknown'; yourself.

PBRoundRunner >> printOn: aStream
  aStream nextPutAll: 'PBRoundRunner('; print: space; nextPut: $).
