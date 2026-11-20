"-- publisher.st: PBPublisher, the publish protocol of a space's commits --

The commit protocol of design spec 7.3 (ProtoBase Transaction._commit,
_commit_root, _standalone_round and _publish at v2.0.0rc3), for a group of
commits: group commit on a standalone storage (proto_db D52, ruling R71;
cluster plan Task 22). Each PBObjectSpace has one round runner
(PBRoundRunner, round.st), an actor, which owns the space's one publisher and
calls it on its own thread, one round at a time; so the publisher is the one
writer of the space's storage (store.st, 'One writer at a time'). It is not
an actor itself.

The publisher never waits (ruling R19). An attempt that finds the root lock
held answers #locked at once for every entry it did not decide, and the
runner owns the retry (CC10): Future after: timers, never a wait. protoST
runs many actors per worker, and a worker blocked in a wait helps other
actors on top of the waiting one; a writer that waited there would be buried
under the commits it helped, and their waits on it would be reported as a
deadlock (review C1 of Task 18).

  aPublisher publishGroup: entries
                              one attempt to publish the PBCommitEntry
                              objects entries as one group: one result per
                              entry, true, an Exception or #locked
  aPublisher closeStorage     closes the storage (the runner sends it between
                              two rounds)

A round runs these steps in order:
  0. for each entry, it saves the atoms the transaction wrote (dependents
     first), before the root lock, as proto_db's _commit saves them before
     _commit_root; a failure is that entry's alone; a save is idempotent, so a
     later attempt writes them no more;
  1. it tries the root lock once (PBFileStorage tryLockRoot): #locked for
     every remaining entry when it is held;
  2. it reads space.root once (readRoot: its CRC, fields and version are
     checked);
  3. and 4. for each entry in queue order, the builder validates against the
     root the previous build produced (the root of step 2 for the first) and
     builds the new SpaceRoot on it (PBTransaction >> _buildOn:, proto_db
     _build_root), and saves it; the record of that saved root, with the
     epoch of step 2 plus one, is the next build's root. A build error (a
     conflict, a failed merge, even an unexpected error) is that entry's
     alone: nothing of it is published and the others go on;
  5. when some entry was built, it saves nothing more and syncs the segments
     once (flushSegment): the path copies, merged values and roots of every
     build;
  6. it publishes the last build's root record once, with the epoch of the
     root read in step 2 plus one (1 for an empty space): replaceRoot: checks
     that epoch against the current root again. The storage epoch advances
     once per round; every commit keeps its own DatabaseRoot in the version
     chain;
  7. after success it marks every collection each built transaction wrote as
     consumed (D33). The spec also names a last-known root updated here; it
     has no reader (proto_db reads one only in a cluster), so none is kept;
  8. when the publish fails, it reads space.root again, still under the lock:
     the round's own root means the round succeeded; the root it was built on
     (same epoch) proves that nothing was published, and the original error
     is the outcome; another root (another epoch, which only a writer ignoring
     the lock can publish) is PBConflictError, as proto_db's _publish; a root
     that cannot be read leaves the outcome unknown: PBOutcomeUnknownError,
     never a guess. That outcome is every built entry's.
A failure of the lock, of the root read, of the flush or of the publish
reaches every entry still undecided, and nothing of the round is visible
before the publish. A lone entry runs exactly the single-commit protocol, so
it writes the same bytes as before group commit (tests/unit/bytes_pinned.st).
The root lock is released after every round, failed or not, best effort
(unlockRoot never signals). The epoch is the one of the root read under the
lock in step 2, which is the root the validation of step 3 compared the first
entry's reads with, as in proto_db's _standalone_round: a root that moved
since the transaction started is validated, not overwritten.

The builder is the library's validation and merge (rebaseOnto: replays a log
through the collections' own mutators). The one application code it runs is an
extractor (PBKeySpec registerExtractor:block:version:), when a merge onto an
indexed current evaluates it (ruling IQ1, as proto_db, whose KeySpec.extract
runs it in the commit): its exception, of whatever class, passes through
unchanged (never wrapped) and is that entry's build error alone (steps 3 and 4),
so only the commit whose merge ran it fails and the others of the round go on, as
in a cluster round (cluster/round.st).
An extractor must be pure and quick: a slow one delays the round, under the root
lock."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/codec'.
Import from: 'calendar'.
Import from: 'uuid'.
Import from: 'protobase/framing'.
Import from: 'protobase/collections'.
Import from: 'protobase/roots'.

Object subclass: #PBPublisher instanceVariableNames: 'space storage'.

"The publisher of aSpace (a PBObjectSpace), owned by the space's round runner."
PBPublisher class >> space: aSpace
  ^ self basicNew _setSpace: aSpace.

PBPublisher >> _setSpace: aSpace
  "Runs once, on a fresh instance."
  space isNil ifFalse: [^ PBUserError signal: 'PBPublisher is initialised once'].
  space := aSpace.
  storage := aSpace storage.
  ^ self.

"=== the messages ============================================================="

"One attempt to publish entries (an Array of PBCommitEntry, in queue order)
 as one group: steps 0 to 8 of the module comment. Answers an Array with one
 result per entry: true when it is published; an Exception, its error (its
 own: a failed save of its atoms or a failed build; or the round's: a failed
 lock, root read, flush or publish, which reaches every entry still
 undecided); or #locked when the root lock is held by another holder
 (nothing decided, nothing published: try again). One attempt, no wait."
PBPublisher >> publishGroup: entries
  | results live took |
  results := Array new: entries size.
  "Step 0, each entry alone (proto_db: each thread saves its written atoms in
   _commit, before it joins the group)."
  live := OrderedCollection new.
  1 to: entries size do: [:i |
    [(entries at: i) writtenAtoms do: [:each | storage save: each].
     live addLast: i]
      on: Error do: [:e | results at: i put: e. e return: nil]].
  live isEmpty ifTrue: [^ results].
  "Step 1."
  took := [storage tryLockRoot] on: Error do: [:e |
    live do: [:i | results at: i put: e].
    e return: nil].
  took isNil ifTrue: [^ results].
  took ifFalse: [
    live do: [:i | results at: i put: #locked].
    ^ results].
  [self _roundOf: entries at: live into: results] ensure: [storage unlockRoot].
  ^ results.

"Closes the storage. Sent by the round runner between two rounds, never
 during one."
PBPublisher >> closeStorage
  storage close.
  ^ nil.

"=== the protocol ============================================================="

"Steps 2 to 8 under the root lock, for the entries of entries at the indices
 aCollection (those whose step 0 succeeded); writes each one's result into
 results. Built in order, each on the record the previous build saved
 (proto_db _standalone_round): its validation reads that root, so conflicts
 inside a group are those of sequential commits."
PBPublisher >> _roundOf: entries at: aCollection into: results
  | current record built failure |
  current := [storage readRoot] on: Error do: [:e |
    aCollection do: [:i | results at: i put: e].
    ^ self].
  record := current.
  built := OrderedCollection new.
  aCollection do: [:i |
    [| pointer |
     pointer := storage save: (self _build: (entries at: i) on: record).
     record := PBRootRecord segment: pointer segmentBytes offset: pointer offset
       epoch: (current isNil ifTrue: [1] ifFalse: [current epoch + 1]).
     built addLast: i]
      on: Error do: [:e |
        "That entry's error alone, even an unexpected one (proto_db review
         M2); nothing of it is published, the others go on."
        results at: i put: e.
        e return: nil]].
  built isEmpty ifTrue: [^ self].
  failure := nil.
  [storage flushSegment.
   self _replaceRoot: record builtOn: current]
    on: Error do: [:e | failure := e. e return: nil].
  failure isNil ifFalse: [
    built do: [:i | results at: i put: failure].
    ^ self].
  built do: [:i |
    [(entries at: i) transaction ifNotNil: [:t | t _markConsumed].
     results at: i put: true]
      on: Error do: [:e | results at: i put: e. e return: nil]].

"The new, unsaved PBSpaceRoot of anEntry built on the root record aRecord
 (nil: an empty space): the transaction's _buildOn:, or version 0 of a new
 database."
PBPublisher >> _build: anEntry on: aRecord
  ^ self _build: anEntry on: aRecord stamp: nil.

"As _build:on:, with aStampOrNil: nil for a standalone commit (the same root, byte for byte),
 { term. epoch } for a cluster commit (PBSpaceRoot databases:stamp:previous:; the commit round,
 cluster/round.st)."
PBPublisher >> _build: anEntry on: aRecord stamp: aStampOrNil
  anEntry isCreateDatabase ifTrue: [^ self _newDatabase: anEntry databaseName on: aRecord stamp: aStampOrNil].
  ^ anEntry transaction _buildOn: aRecord stamp: aStampOrNil.

"The SpaceRoot of aRecord with the database aName added at version 0
 (proto_db ObjectSpace.new_database): empty objects and mutables, no
 previous version, committedAt now in UTC and a new origin, the database's
 identity: the 16 bytes of a version-4 UUID, as proto_db's
 uuid.uuid4().bytes. An existing name is PBValidationError."
PBPublisher >> _newDatabase: aName on: aRecord
  ^ self _newDatabase: aName on: aRecord stamp: nil.

PBPublisher >> _newDatabase: aName on: aRecord stamp: aStampOrNil
  | current databases root |
  current := space _spaceRootAt: aRecord.
  databases := current isNil ifTrue: [PBDictionary new] ifFalse: [current databases].
  (databases has: aName) ifTrue: [^ PBValidationError signal: 'Database ' , (PBCodec repr: aName) , ' already exists'].
  root := PBDatabaseRoot objects: PBDictionary new mutables: PBDictionary new version: 0
    committedAt: DateTime nowUTC origin: UUID new bytes previous: nil.
  ^ PBSpaceRoot databases: (databases setAt: aName value: root) stamp: aStampOrNil previous: current.

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
