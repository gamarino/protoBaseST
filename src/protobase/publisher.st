"-- publisher.st: PBPublisher, the actor that publishes a space's commits --

The commit protocol of design spec 7.3 (ProtoBase Transaction._commit,
_commit_root, _standalone_round and _publish at v2.0.0rc2, with a group of
one: group commit is implementation-specific and left out). Each PBObjectSpace
makes one publisher and talks to it through its actor proxy (asActor), so its
publishes are made one at a time; it is the one writer of the space's storage
(store.st, 'One writer at a time').

The publisher never waits (ruling R19). An attempt that finds the root lock
held answers false at once, and the caller owns the backoff
(PBObjectSpace >> _untilPublished:, used by PBTransaction >> commit and
PBObjectSpace >> newDatabase:). protoST runs many actors per worker, and a
worker blocked in a wait helps other actors on top of the waiting one; a
publisher that waited there would be buried under the commits it helped, and
their waits on it would be reported as a deadlock (review C1 of Task 18).

  aPublisher commit: aTransaction   a Future of true when the transaction's
                                    commit is published, false when the root
                                    lock is held by another holder (nothing
                                    published; try again)
  aPublisher createDatabase: aName  the same for version 0 of the database
                                    aName
  aPublisher closeStorage           a Future of nil: closes the storage between
                                    two publishes

A commit attempt runs these steps in order:
  0. it saves the atoms the transaction wrote (dependents first), before the
     root lock, as ProtoBase's _commit saves them before _commit_root; a save
     is idempotent, so a later attempt writes them no more;
  1. it tries the root lock once (PBFileStorage tryLockRoot): false when it is
     held;
  2. it reads space.root (readRoot: its CRC, fields and version are checked);
  3. and 4. the builder validates against that root and builds the new
     SpaceRoot on it (PBTransaction >> _buildOn:, ProtoBase _build_root);
  5. it saves the new atoms (the path copies, merged values and roots) and
     syncs the segments (flushSegment);
  6. it publishes the root record with the epoch of the root read in step 2
     plus one (1 for an empty space): replaceRoot: checks that epoch against
     the current root again;
  7. after success it marks every collection the transaction wrote as consumed
     (D33). The spec also names a last-known root updated here; it has no
     reader (ProtoBase reads one only in a cluster), so none is kept;
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
Import from: 'protobase/codec'.
Import from: 'calendar'.
Import from: 'uuid'.
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

"=== the messages ============================================================="

"One attempt to commit aTransaction (in the state #committing): steps 0 to 8
 of the module comment, the build being aTransaction >> _buildOn:. Answers
 true when published, false when the root lock is held by another holder."
PBPublisher >> commit: aTransaction
  aTransaction _writtenAtoms do: [:each | storage save: each].
  (self _publish: [:record | aTransaction _buildOn: record]) ifFalse: [^ false].
  aTransaction _markConsumed.
  ^ true.

"One attempt to create the database aName (ProtoBase ObjectSpace.new_database):
 version 0, with empty objects and mutables, no previous version, committedAt
 now in UTC and a new origin, the database's identity: the 16 bytes of a
 version-4 UUID, as ProtoBase's uuid.uuid4().bytes. An existing name is
 PBValidationError, and nothing is published. Answers true when published,
 false when the root lock is held by another holder."
PBPublisher >> createDatabase: aName
  ^ self _publish: [:record |
    | current databases root |
    current := space _spaceRootAt: record.
    databases := current isNil ifTrue: [PBDictionary new] ifFalse: [current databases].
    (databases has: aName) ifTrue: [^ PBValidationError signal: 'Database ' , (PBCodec repr: aName) , ' already exists'].
    root := PBDatabaseRoot objects: PBDictionary new mutables: PBDictionary new version: 0
      committedAt: DateTime nowUTC origin: UUID new bytes previous: nil.
    PBSpaceRoot databases: (databases setAt: aName value: root)].

"Closes the storage. Sent through the actor, it runs between two publishes,
 never during one."
PBPublisher >> closeStorage
  storage close.
  ^ nil.

"=== the protocol ============================================================="

"Steps 1 to 8 with aBuilder (a block: the root record read in step 2 -> the
 new, unsaved PBSpaceRoot): true when published, false when the root lock is
 held by another holder (one attempt, no wait)."
PBPublisher >> _publish: aBuilder
  storage tryLockRoot ifFalse: [^ false].
  [self _publishLocked: aBuilder] ensure: [storage unlockRoot].
  ^ true.

"Steps 2 to 6 and 8, under the root lock; answers the published PBRootRecord."
PBPublisher >> _publishLocked: aBuilder
  | current newRoot pointer record |
  current := storage readRoot.
  newRoot := aBuilder value: current.
  pointer := storage save: newRoot.
  storage flushSegment.
  record := PBRootRecord segment: pointer segmentBytes offset: pointer offset
    epoch: (current isNil ifTrue: [1] ifFalse: [current epoch + 1]).
  ^ self _replaceRoot: record builtOn: current.

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
