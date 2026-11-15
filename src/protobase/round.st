"-- round.st: PBRoundRunner and PBCommitEntry, the space's commit queue --

The round runner of a space (cluster design spec 5.6, CC10, CC22; proto_db
transactions.py at v2.0.0rc3: _commit_root, _Entry, _Group and, for a
standalone storage, _standalone_round, decision D52). Every commit and every
new database of a PBObjectSpace is a PBCommitEntry queued on the space's
runner; the caller waits only on the entry's Future.

  PBCommitEntry transaction: aTx willRetry: aBoolean deadline: us
                              the commit of aTx (in the state #committing);
                              willRetry: whether the caller retries a
                              conflict (Database.run), kept for the cluster
                              round (Task 23), unused by a standalone round;
                              us the monotonic microsecond
                              (Time microsecondClockValue) after which a
                              commit still waiting for the root lock ends in
                              PBTimeoutError
  PBCommitEntry createDatabase: aName deadline: us
                              version 0 of the database aName
  anEntry future              the Future the runner settles: true when
                              published, rejected with the commit's error
  PBRoundRunner space: aSpace the runner of aSpace, an actor of the medium
                              band (asActor); answers its proxy
  aRunner enqueue: anEntry    adds anEntry to the queue and answers its
                              Future; nothing else (see below)
  aRunner closeStorage        a round of what is queued, then the storage is
                              closed; a Future of nil

A standalone round takes the whole queue, in the order it was queued, and
hands it to PBPublisher >> publishGroup: (publisher.st): one root lock, one
root read, each entry built on the root the previous build saved, one flush
and one publish; a lone entry is exactly the single-commit protocol. The
answer has one result per entry: true, an Exception (that entry's error, or
the round's, which reaches every built entry), or #locked (nothing was
decided: the root lock is held by another process or storage). Only true is
reported as a success: any other result (which publishGroup: never answers)
is PBOutcomeUnknownError, never a guess. Rounds run
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

"=== PBCommitEntry ============================================================"

Object subclass: #PBCommitEntry instanceVariableNames: 'transaction databaseName willRetry deadline future'.

PBCommitEntry class >> transaction: aTransaction willRetry: aBoolean deadline: microseconds
  aTransaction isNil ifTrue: [^ PBValidationError signal: 'PBCommitEntry transaction: a transaction was expected, not nil'].
  ^ self basicNew _setTransaction: aTransaction name: nil willRetry: aBoolean deadline: microseconds.

PBCommitEntry class >> createDatabase: aName deadline: microseconds
  aName isNil ifTrue: [^ PBValidationError signal: 'PBCommitEntry createDatabase: a database name was expected, not nil'].
  ^ self basicNew _setTransaction: nil name: aName willRetry: false deadline: microseconds.

PBCommitEntry >> _setTransaction: aTransaction name: aName willRetry: aBoolean deadline: microseconds
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
  deadline := microseconds.
  future := Future new.
  ^ self.

"The transaction committed, nil for a new database."
PBCommitEntry >> transaction
  ^ transaction.

"The name of the database created, nil for a commit."
PBCommitEntry >> databaseName
  ^ databaseName.

PBCommitEntry >> isCreateDatabase
  ^ transaction isNil.

PBCommitEntry >> willRetry
  ^ willRetry.

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
  transaction isNil
    ifTrue: [aStream nextPutAll: 'createDatabase '; print: databaseName]
    ifFalse: [aStream print: transaction].
  aStream nextPut: $).

"=== PBRoundRunner ============================================================"

Object subclass: #PBRoundRunner instanceVariableNames: 'space publisher queue scheduled delay proxy'.

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
  | runner actor |
  runner := self basicNew _setSpace: aSpace publisher: (PBPublisher space: aSpace) queue: (Atom on: #())
    scheduled: (Atom on: false) delay: (Atom on: self firstLockDelay) proxy: (Atom on: nil).
  actor := runner asActor.
  runner _publishProxy: actor.
  ^ actor.

PBRoundRunner >> _setSpace: aSpace publisher: aPublisher queue: aQueue scheduled: aScheduled delay: aDelay proxy: aProxy
  "Runs once, on a fresh instance."
  space isNil ifFalse: [^ PBUserError signal: 'PBRoundRunner is initialised once'].
  space := aSpace.
  publisher := aPublisher.
  queue := aQueue.
  scheduled := aScheduled.
  delay := aDelay.
  proxy := aProxy.
  ^ self.

"Sets the proxy cell once (from nil), before the proxy is answered."
PBRoundRunner >> _publishProxy: anActor
  (proxy value: anActor ifCurrent: nil) ifFalse: [^ PBUserError signal: 'PBRoundRunner: the proxy is set once'].

"=== the messages (on the actor) =============================================="

"Adds anEntry (a PBCommitEntry) to the queue, makes sure a round is coming,
 and answers the entry's Future. It runs no round itself."
PBRoundRunner >> enqueue: anEntry
  (anEntry isKindOf: PBCommitEntry) ifFalse: [
    ^ PBValidationError signal: 'PBRoundRunner enqueue: a PBCommitEntry was expected, not ' , anEntry printString].
  queue swap: [:entries | entries copyWith: anEntry].
  self _schedule.
  ^ anEntry future.

"Runs a round of what is queued (the entries queued before the close commit
 or fail as they would have), then closes the storage, between two rounds,
 never during one. Entries left waiting for the lock meet the closed storage
 in their next round (PBClosedError). Answers nil."
PBRoundRunner >> closeStorage
  queue value isEmpty ifFalse: [self _round].
  publisher closeStorage.
  ^ nil.

"One round: takes the whole queue, publishes it as one group and settles each
 entry, or, when the root lock is held, settles the entries past their
 deadline and schedules the retry of the others."
PBRoundRunner >> _round
  | batch results kept now |
  scheduled swap: [:old | false].
  batch := queue value.
  queue swap: [:entries | #()].
  batch isEmpty ifTrue: [^ self].
  results := [publisher publishGroup: batch] on: Error do: [:e |
    "publishGroup: answers every error as a result; an error here is the
     round's own and reaches every entry."
    e return: (Array new: batch size withAll: e)].
  kept := OrderedCollection new.
  now := Time microsecondClockValue.
  1 to: batch size do: [:i | | entry result |
    entry := batch at: i.
    result := results at: i.
    result == #locked
      ifTrue: [now >= entry deadline
        ifTrue: [entry future rejectWith: self _timeoutError]
        ifFalse: [kept addLast: entry]]
      ifFalse: [result == true
        ifTrue: [entry future resolve: true]
        ifFalse: [entry future rejectWith: ((result isKindOf: Exception)
          ifTrue: [result]
          ifFalse: [self _undecidedError: result])]]].
  kept isEmpty ifTrue: [
    (results includes: #locked) ifFalse: [delay swap: [:d | PBRoundRunner firstLockDelay]].
    queue value isEmpty ifFalse: [self _schedule].
    ^ self].
  queue swap: [:entries | kept asArray , entries].
  self _retryAfterLockFor: kept now: now.

"Schedules the next round after a #locked round: after the current delay,
 never past the nearest deadline of aCollection's entries, and doubles the
 delay up to longestLockDelay."
PBRoundRunner >> _retryAfterLockFor: aCollection now: microseconds
  | nearest ms actor |
  nearest := aCollection inject: aCollection first deadline into: [:soonest :entry | soonest min: entry deadline].
  ms := delay value min: (nearest - microseconds + 999 // 1000 max: 0).
  delay swap: [:d | d * 2 min: PBRoundRunner longestLockDelay].
  scheduled swap: [:old | true].
  actor := proxy value.
  (Future after: ms) thenDo: [:x | actor _round].

"Sends _round to the runner's own proxy unless a round is already coming (a
 message posted or a retry timer pending)."
PBRoundRunner >> _schedule
  scheduled value ifTrue: [^ self].
  scheduled swap: [:old | true].
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
