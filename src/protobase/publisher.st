"-- publisher.st: PBPublisher, the actor that publishes a space's commits --

The commit protocol of design spec 7.3 (ProtoBase _commit_root,
_standalone_round and _publish at v2.0.0rc2, with a group of one: group commit
is implementation-specific and left out). Each PBObjectSpace makes one
publisher and talks to it through its actor proxy (asActor), so its commits
are made one at a time; it is the one writer of the space's storage (store.st,
'One writer at a time'):

  aPublisher commit: aTransaction   a Future of true: the transaction's commit,
                                    published (PBTransaction >> commit waits
                                    for it)
  aPublisher createDatabase: aName  a Future of true: version 0 of the
                                    database aName, published
                                    (PBObjectSpace >> newDatabase:)
  aPublisher closeStorage           a Future of nil: closes the storage between
                                    two commits (PBObjectSpace >> close)

Each publish runs these steps in order:
  1. it takes the root lock (PBFileStorage tryLockRoot), retried after
     (Future after: d) wait, d from 1 ms, doubling, capped at 50 ms, until the
     space's lockTimeout (milliseconds, on the monotonic clock) has passed:
     then PBTimeoutError (ProtoBase FileStorage._acquire_process_lock);
  2. it reads space.root (readRoot: its CRC, fields and version are checked);
  3. and 4. the builder validates against that root and builds the new
     SpaceRoot on it (PBTransaction >> _buildOn:, ProtoBase _build_root);
  5. it saves the new atoms, dependents first, and syncs them (flushSegment);
  6. it publishes the root record with the epoch of the root read in step 2
     plus one (1 for an empty space): replaceRoot: checks that epoch against
     the current root again;
  7. after success it marks every collection the transaction wrote as consumed
     (D33) and records the root as the space's last-known root;
  8. when the publish fails, it reads space.root again, still under the lock:
     the commit's own root means the commit succeeded; the root it was built
     on (same epoch) proves that nothing was published, and the original error
     is signalled again; another root (another epoch, which only a writer
     ignoring the lock can publish) is PBConflictError, as ProtoBase's
     _publish; a root that cannot be read leaves the outcome unknown:
     PBOutcomeUnknownError, never a guess.
The root lock is released after every publish, failed or not, best effort
(unlockRoot never signals). The epoch is the one of the root read under the
lock in step 2, which is the root the validation of step 3 compared the reads
with, as in ProtoBase's _standalone_round: a root that moved since the
transaction started is validated, not overwritten.

The publisher runs no application code: the builder is the library's
validation and merge (rebaseOnto: replays a log through the collections' own
mutators)."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/framing'.
Import from: 'protobase/collections'.
Import from: 'protobase/roots'.

Object subclass: #PBPublisher instanceVariableNames: 'space storage'.

"The publisher of aSpace (a PBObjectSpace), not yet an actor: the space sends
 it asActor once."
PBPublisher class >> space: aSpace
  ^ self basicNew _setSpace: aSpace.

PBPublisher >> _setSpace: aSpace
  "Runs once, on a fresh instance."
  space isNil ifFalse: [^ PBUserError signal: 'PBPublisher is initialised once'].
  space := aSpace.
  storage := aSpace storage.
  ^ self.

"The first wait between two attempts to take the root lock, and the longest,
 in milliseconds (ProtoBase: 0.001 s doubling up to 0.05 s)."
PBPublisher class >> firstLockDelay
  ^ 1.

PBPublisher class >> longestLockDelay
  ^ 50.

"=== the messages ============================================================="

"Commits aTransaction (in the state #committing): steps 1 to 8 of the module
 comment, the build being aTransaction >> _buildOn:. Answers true."
PBPublisher >> commit: aTransaction
  self _publish: [:record | aTransaction _buildOn: record].
  aTransaction _markConsumed.
  ^ true.

"Creates the database aName (ProtoBase ObjectSpace.new_database): version 0,
 with empty objects and mutables, no previous version, committedAt now in UTC
 and a new origin of 16 random bytes, the database's identity. An existing
 name is PBValidationError, and nothing is published. Answers true."
PBPublisher >> createDatabase: aName
  self _publish: [:record |
    | current databases root |
    current := space _spaceRootAt: record.
    databases := current isNil ifTrue: [PBDictionary new] ifFalse: [current databases].
    (databases has: aName) ifTrue: [^ PBValidationError signal: 'Database ' , aName printString , ' already exists'].
    root := PBDatabaseRoot objects: PBDictionary new mutables: PBDictionary new version: 0
      committedAt: DateTime nowUTC origin: (ByteArray randomBytes: 16) previous: nil.
    PBSpaceRoot databases: (databases setAt: aName value: root)].
  ^ true.

"Closes the storage. Sent through the actor, it runs between two publishes,
 never during one."
PBPublisher >> closeStorage
  storage close.
  ^ nil.

"=== the protocol ============================================================="

"Steps 1 to 8 with aBuilder (a block: the root record read in step 2 -> the
 new, unsaved PBSpaceRoot); answers the published PBRootRecord."
PBPublisher >> _publish: aBuilder
  self _lockRoot.
  ^ [self _publishLocked: aBuilder] ensure: [storage unlockRoot].

"Step 1: takes the root lock, waiting between attempts (module comment);
 PBTimeoutError once the space's lockTimeout has passed. A wait here blocks
 the publisher's worker for at most longestLockDelay milliseconds."
PBPublisher >> _lockRoot
  | timeout deadline delay remaining |
  timeout := space lockTimeout.
  deadline := Time millisecondClockValue + timeout.
  delay := PBPublisher firstLockDelay.
  [storage tryLockRoot] whileFalse: [
    remaining := deadline - Time millisecondClockValue.
    remaining <= 0 ifTrue: [
      ^ PBTimeoutError signal: 'Could not acquire the root lock within ' , timeout printString
        , ' ms (held by another process or storage)'].
    (Future after: (delay min: remaining)) wait.
    delay := delay * 2 min: PBPublisher longestLockDelay].

"Steps 2 to 7, under the root lock."
PBPublisher >> _publishLocked: aBuilder
  | current newRoot pointer record |
  current := storage readRoot.
  newRoot := aBuilder value: current.
  pointer := storage save: newRoot.
  storage flushSegment.
  record := PBRootRecord segment: pointer segmentBytes offset: pointer offset
    epoch: (current isNil ifTrue: [1] ifFalse: [current epoch + 1]).
  self _replaceRoot: record builtOn: current.
  space _noteRoot: record.
  ^ record.

"Steps 6 and 8: publishes aRecord, built on the root record aCurrent (nil: an
 empty space); when the publish fails, decides its outcome by reading
 space.root again (module comment). Answers aRecord when it is published."
PBPublisher >> _replaceRoot: aRecord builtOn: aCurrent
  | expected |
  expected := aCurrent isNil ifTrue: [0] ifFalse: [aCurrent epoch].
  ^ [storage replaceRoot: aRecord] on: PBDBError do: [:error |
    | now |
    now := [storage readRoot] on: PBDBError do: [:e |
      ^ PBOutcomeUnknownError signal: 'Publishing the root failed (' , error messageText
        , ') and reading it back failed (' , e messageText , '); the outcome of the commit is unknown'].
    (now notNil and: [now pointer = aRecord pointer]) ifTrue: [
      storage _log: 'replaceRoot: reported ' , error class name , ' (' , error messageText
        , ') but the new root is visible; the commit succeeded'.
      ^ aRecord].
    (now isNil ifTrue: [0] ifFalse: [now epoch]) = expected ifFalse: [
      ^ PBConflictError signal: 'Another root was published concurrently; nothing was committed ('
        , error messageText , ')'].
    error pass].

PBPublisher >> printOn: aStream
  aStream nextPutAll: 'PBPublisher('; print: storage; nextPut: $).
