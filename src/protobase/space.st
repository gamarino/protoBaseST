"-- space.st: PBObjectSpace, PBDatabase, PBSnapshot and PBHistoryEntry, read side --

ProtoBase's ObjectSpace, Database, Snapshot and HistoryEntry
(proto_db/transactions.py at v2.0.0rc1; design spec 5.2 and 6), reading:

  PBObjectSpace registerAtomClass: aClass   PBTypeRegistry register: aClass
  PBObjectSpace storage: aStorage           a space over aStorage (it owns it:
                                            close closes it); lockTimeout 30000 ms
  PBObjectSpace storage: s lockTimeout: ms  ms, a positive SmallInteger (the root
                                            lock wait of a commit)
  PBObjectSpace storage: s coordinator: c   a space of the cluster node c over s, a
                                            storage in cluster mode (PBFileStorage
                                            clusterPath:, CC20); the node's tier
                                            (PBSharedTier) attached to c; its
                                            commits wait for a write permission
                                            up to c's acquireTimeout; also
                                            storage:coordinator:lockTimeout: ms,
                                            whose commits wait up to ms
  aSpace coordinator                        c, or nil without a cluster
  aSpace committedEpoch, persistedEpoch     the epoch of the newest root the node
                                            knows committed, and persisted in
                                            space.root (its persister,
                                            cluster/persister.st); without a
                                            cluster both the storage's
  aSpace sync: ms                           (also aDatabase sync: ms) nil once
                                            persistedEpoch reaches committedEpoch,
                                            PBTimeoutError after ms (nil: no
                                            deadline); a durability barrier, not
                                            a visibility barrier
  aSpace listDatabases                      the database names, sorted
  aSpace newDatabase: aName                 creates the database (version 0)
                                            through the space's round runner and
                                            answers it; an existing name is
                                            PBValidationError
  aSpace openDatabase: aName                the PBDatabase; an absent name is
                                            PBValidationError
  aSpace close                              idempotent; later calls: PBClosedError
  aDatabase name, history                   history: PBHistoryEntry objects, newest
                                            first, through previous
  aDatabase snapshotAt: anEntryOrSnapshot   the PBSnapshot of that version
  aDatabase newTransaction                  a PBTransaction (transactions.st)
  aSnapshot version, committedAt, rootNames, getRootObject:, mutableNames,
            getMutable:                     names sorted; an absent name reads nil
  anEntry   version, committedAt, rootNames, mutableNames, getMutable: (no
            getRootObject:, as in ProtoBase: open the version with snapshotAt:)

Every read goes to the storage's current root: there is no cache of roots. A
space without a coordinator whose SpaceRoot carries cluster_term was committed
by a cluster node and is PBNotSupportedError, like a directory holding
cluster/ (PBFileStorage path:). storage: refuses a storage in cluster mode and
storage:coordinator: one that is not (PBValidationError); close detaches the
node's tier from the coordinator and closes its acceptor log, and leaves the
coordinator running (proto_db: the caller owns it). snapshotAt:
checks that the version is one of this database: the name its entry or
snapshot records, and its origin (DatabaseRoot origin), must be this
database's, else PBReferenceError (ProtoBase Database._check_owned); any
other argument is PBReferenceError (the prototype has no snapshot references
as bytes). PBDatabase >> newTransaction is in transactions.st."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/registry'.
Import from: 'protobase/codec'.
Import from: 'protobase/avl'.
Import from: 'protobase/collections'.
Import from: 'protobase/records'.
Import from: 'protobase/roots'.
Import from: 'protobase/round'.
Import from: 'protobase/cluster/tier'.
Import from: 'protobase/cluster/persister'.

Object subclass: #_PBNameCheck.

"aName, a non-empty String; PBValidationError otherwise (ProtoBase _check_name)."
_PBNameCheck class >> check: aName what: aWhat
  ((aName isString and: [aName isSymbol not]) and: [aName notEmpty]) ifTrue: [^ aName].
  ^ PBValidationError signal: 'A ' , aWhat , ' name must be a non-empty String, not ' , aName printString.

"=== PBObjectSpace ============================================================"

Object subclass: #PBObjectSpace instanceVariableNames: 'storage lockTimeout closed runner coordinator tier permitTimeout persister'.

PBObjectSpace class >> registerAtomClass: aClass
  ^ PBTypeRegistry register: aClass.

PBObjectSpace class >> defaultLockTimeout
  ^ 30000.

PBObjectSpace class >> storage: aStorage
  ^ self storage: aStorage lockTimeout: self defaultLockTimeout.

PBObjectSpace class >> storage: aStorage lockTimeout: milliseconds
  self _checkStorage: aStorage lockTimeout: milliseconds.
  ((aStorage respondsTo: #isClusterMode) and: [aStorage isClusterMode]) ifTrue: [
    ^ PBValidationError signal: 'PBObjectSpace storage: ' , aStorage printString
      , ' was opened in cluster mode (PBFileStorage clusterPath:): it is written only through a coordinator, PBObjectSpace storage:coordinator:'].
  ^ self basicNew _setStorage: aStorage lockTimeout: milliseconds coordinator: nil tier: nil permitTimeout: nil.

"A space of the cluster node aCoordinator (a started PBClusterCoordinator) over aClusterStorage,
 a storage opened in cluster mode (PBFileStorage clusterPath:, CC20), with the default lock
 timeout. The node's tier (PBSharedTier storage:nodeId:) is attached to the coordinator before
 the space is answered (proto_db ObjectSpace(coordinator=)); a refused attach closes the tier
 and is signalled. The caller owns the coordinator: close detaches it, never stops it. Its
 commits, the confirmation among them, wait for a write permission up to the coordinator's
 acquireTimeout (proto_db ObjectSpace(lock_timeout=None))."
PBObjectSpace class >> storage: aClusterStorage coordinator: aCoordinator
  ^ self _storage: aClusterStorage coordinator: aCoordinator lockTimeout: self defaultLockTimeout permitTimeout: nil.

"As storage:coordinator:, its commits, the confirmation among them, waiting for a write permission
 up to milliseconds instead (proto_db ObjectSpace(lock_timeout=), the bound of _run_round's
 permit and of its timeout's text)."
PBObjectSpace class >> storage: aClusterStorage coordinator: aCoordinator lockTimeout: milliseconds
  ^ self _storage: aClusterStorage coordinator: aCoordinator lockTimeout: milliseconds permitTimeout: milliseconds.

PBObjectSpace class >> _storage: aClusterStorage coordinator: aCoordinator lockTimeout: milliseconds permitTimeout: aBound
  | aTier ok |
  self _checkStorage: aClusterStorage lockTimeout: milliseconds.
  "A storage not in cluster mode is refused by PBSharedTier storage:nodeId: (PBValidationError)."
  (aCoordinator isKindOf: PBClusterCoordinator) ifFalse: [
    ^ PBValidationError signal: 'PBObjectSpace storage:coordinator: a PBClusterCoordinator was expected, not ' , aCoordinator printString].
  aTier := PBSharedTier storage: aClusterStorage nodeId: aCoordinator nodeId.
  ok := false.
  [(aCoordinator _attach: aTier) wait. ok := true] ensure: [ok ifFalse: [aTier close]].
  ^ (self basicNew _setStorage: aClusterStorage lockTimeout: milliseconds coordinator: aCoordinator tier: aTier
    permitTimeout: aBound) _startPersister.

PBObjectSpace class >> _checkStorage: aStorage lockTimeout: milliseconds
  (aStorage isNil or: [aStorage isClassObject]) ifTrue: [
    ^ PBValidationError signal: 'PBObjectSpace storage: a storage was expected, not ' , aStorage printString].
  ((milliseconds isKindOf: SmallInteger) and: [milliseconds > 0]) ifFalse: [
    ^ PBValidationError signal: 'PBObjectSpace: lockTimeout is a positive SmallInteger of milliseconds, not '
      , milliseconds printString].

PBObjectSpace >> _setStorage: aStorage lockTimeout: milliseconds coordinator: aCoordinator tier: aTier permitTimeout: aBound
  "Runs once, on a fresh instance."
  storage isNil ifFalse: [^ PBUserError signal: 'PBObjectSpace is initialised once'].
  storage := aStorage.
  lockTimeout := milliseconds.
  permitTimeout := aBound.
  coordinator := aCoordinator.
  tier := aTier.
  closed := Atom on: false.
  runner := self _newRunner.
  persister := aCoordinator isNil ifTrue: [nil] ifFalse: [self _newPersister].
  ^ self.

"The persister of a space with a coordinator (cluster/persister.st), made once by the
 initialiser: its writer is the space's round runner, the actor that makes every write of the
 storage. A seam: a test subclass answers a subclass of PBPersister."
PBObjectSpace >> _newPersister
  ^ PBPersister tier: tier coordinator: coordinator writer: runner.

"Starts the persister (proto_db attach starts it); answers self."
PBObjectSpace >> _startPersister
  persister start.

"The persister, nil without a coordinator."
PBObjectSpace >> _persister
  ^ persister.

"The space's round runner (an actor proxy), made once by the initialiser. A
 seam: a test subclass answers a runner over its own publisher
 (PBRoundRunner space:publisher:)."
PBObjectSpace >> _newRunner
  ^ PBRoundRunner space: self.

"The cluster round of the runner (a space with a coordinator), over aPublisher, posting its
 answers to the runner's proxy in aCell. A seam: a test subclass answers a subclass of
 PBClusterRound."
PBObjectSpace >> _newClusterRound: aPublisher proxy: aCell
  ^ PBClusterRound space: self publisher: aPublisher proxy: aCell.

"The node's tier (a PBSharedTier), nil without a coordinator."
PBObjectSpace >> _tier
  ^ tier.

"Database.run's held retry for aCaller is not coming (cluster/round.st PBDropKept); nothing
 without a coordinator. Posted, never waited."
PBObjectSpace >> _dropKept: aCaller
  coordinator isNil ifTrue: [^ self].
  closed value ifTrue: [^ self].
  runner dropKept: aCaller.

"The cluster coordinator of the space, nil for a space opened without one (proto_db coordinator)."
PBObjectSpace >> coordinator
  ^ coordinator.

PBObjectSpace >> storage
  ^ storage.

"Milliseconds a commit waits for the root lock."
PBObjectSpace >> lockTimeout
  ^ lockTimeout.

"Milliseconds a cluster commit waits for a write permission (the lockTimeout given to
 storage:coordinator:lockTimeout:), nil for the coordinator's acquireTimeout (storage:coordinator:,
 proto_db lock_timeout None); nil without a coordinator."
PBObjectSpace >> _permitTimeout
  ^ permitTimeout.

PBObjectSpace >> isClosed
  ^ closed value.

"The first wait between two attempts to take the root lock, and the longest,
 in milliseconds: the round runner's (PBRoundRunner firstLockDelay and
 longestLockDelay; ProtoBase FileStorage._acquire_process_lock: 0.001 s
 doubling up to 0.05 s)."
PBObjectSpace class >> firstLockDelay
  ^ PBRoundRunner firstLockDelay.

PBObjectSpace class >> longestLockDelay
  ^ PBRoundRunner longestLockDelay.

"The deadline of a commit queued now: lockTimeout milliseconds later on the
 monotonic clock, in microseconds (CC10: each queued commit keeps its own
 deadline from the moment it was queued)."
PBObjectSpace >> _deadline
  ^ Time microsecondClockValue + (lockTimeout * 1000).

"Queues anEntry (a PBCommitEntry) on the space's round runner and waits for
 its outcome: true when published; the entry's error otherwise
 (PBTimeoutError when the root lock was not taken by its deadline). The
 runner owns the lock retry and never waits (round.st, CC10); this wait is
 the caller's only one. Inside an actor it is nested in blocks
 (PBTransaction >> commit), so it blocks the caller's worker, which helps
 other actors meanwhile. A failure of the enqueue itself rejects the entry's
 Future, so this wait always ends."
PBObjectSpace >> _commitEntry: anEntry
  (runner enqueue: anEntry) catch: [:e | anEntry future rejectWith: e].
  ^ anEntry future wait.

PBObjectSpace >> _checkOpen
  closed value ifTrue: [^ PBClosedError signal: 'PBObjectSpace is closed'].

"The PBSpaceRoot the storage's root record points to now, or nil (an empty
 space)."
PBObjectSpace >> _currentSpaceRoot
  ^ self _spaceRootAt: self _snapshotRecord.

"The root record a new transaction starts from (a PBRootRecord), or nil for an
 empty space (ProtoBase _snapshot_record, proto_db _read_storage_root). Without
 a coordinator, the storage's current root. With one, the newest committed
 root this node knows (the coordinator's committedRoot; when it knows none,
 the peers' recovered root, else the persisted root: _committedRecord), after a
 confirmation when the node needs one: on the first snapshot after the attach,
 and on any snapshot after forceRejoin on a survivor asked for one again, since
 needsConfirmation is read on every snapshot (L18; Task 16, review I2)."
PBObjectSpace >> _snapshotRecord
  self _checkOpen.
  coordinator isNil ifTrue: [^ storage readRoot].
  coordinator needsConfirmation ifTrue: [self _confirm].
  ^ self _committedRecord.

"The confirmation (proto_db _read_storage_root): the coordinator records that it started
 (_confirmed, one attempt per attach, as proto_db's confirmed() before the commit), then a commit
 that writes nothing goes through the round runner (PBCommitEntry confirmationDeadline:): it
 obtains a write permission and, when the base the lease names is not the committed root this
 node knows, commits it first (proto_db _commit_base), so the node learns the newest root a
 majority committed, also those made while it was down. A PBTimeoutError, PBConflictError or
 PBOutcomeUnknownError of it is written to stderr (_warn:) and the read goes on from the committed
 root this node knows: its logged one keeps reads from going backwards across a crash, and an
 older committed root is still a committed state, never a wrong one. Any other error (the space
 or the node closed, the node fenced) is signalled."
PBObjectSpace >> _confirm
  coordinator _confirmed wait.
  [self _commitEntry: (PBCommitEntry confirmationDeadline: self _deadline)]
    on: PBTimeoutError, PBConflictError, PBOutcomeUnknownError
    do: [:e | self _warn: 'Confirming the committed root under the cluster lease failed: ' , e class name , ': '
      , (e messageText ifNil: ['(no message)']). e return: nil].

"The record of the newest committed root this node knows (proto_db current_root), nil for the
 empty space. When the node knows none (a node that never learnt one, or one that forgot it: a
 log whose committed entry was lost, forceRejoin on a survivor, its confirmation in progress or
 failed), it recovers it from the peers first (PBClusterCoordinator >> _recover: the highest
 committed root a majority of witnesses reports, published to the readers before the recovery
 answers); a PBConflictError of the recovery is written to stderr (_inform:) and only then, if
 the node still knows none, the persisted root is read and taken as committed
 (_observePersisted:from:: the empty space too, so the next snapshot neither recovers nor reads
 the storage again). A fenced node's recovery is refused at once (PBUnexpectedError); it reads
 the persisted root too, as proto_db's fenced node, whose recovery query goes unanswered and ends
 in ProtoConflictError. A persisted root read but not learnt (the tier detached meanwhile, or a
 fence that landed before the acceptor learnt it: a fenced acceptor learns nothing) is answered
 as it was read, never as the empty space (review M5)."
PBObjectSpace >> _committedRecord
  | root persisted |
  root := coordinator committedRoot.
  root isNil ifTrue: [
    [coordinator _recover wait]
      on: PBConflictError, PBUnexpectedError
      do: [:e |
        ((e isKindOf: PBUnexpectedError) and: [coordinator isFenced not]) ifTrue: [e pass].
        self _inform: 'Node ' , coordinator nodeId , ': recovery from the peers failed ('
          , (e messageText ifNil: ['(no message)']) , '); reading the persisted root'.
        e return: nil].
    root := coordinator committedRoot].
  root isNil ifTrue: [
    persisted := tier readPersisted.
    (coordinator _observePersisted: persisted from: tier) wait.
    root := coordinator committedRoot.
    "Read but not learnt (the tier detached meanwhile, or the node fenced before its acceptor
     learnt it): the persisted root is still a committed root, never the empty space (review M5)."
    (root isNil and: [persisted notNil]) ifTrue: [^ persisted record]].
  root isNil ifTrue: [^ nil].
  ^ root record.

"aString on stderr, prefixed with the space; never signals (proto_db logger.warning)."
PBObjectSpace >> _warn: aString
  [Stdio stderr nextPutAll: self printString , ': ' , aString; lf; flush] on: Error do: [:e | nil].

"aString on stderr, prefixed with the space; never signals (proto_db logger.info)."
PBObjectSpace >> _inform: aString
  [Stdio stderr nextPutAll: self printString , ': ' , aString; lf; flush] on: Error do: [:e | nil].

"The epoch of the newest root this node knows persisted in space.root (proto_db persisted_epoch:
 the persister's), 0 when none; without a coordinator, committedEpoch (every commit is persisted
 when it returns)."
PBObjectSpace >> persistedEpoch
  self _checkOpen.
  coordinator isNil ifTrue: [^ self committedEpoch].
  ^ persister persistedEpoch.

"Waits until every commit this node knows is persisted in space.root (proto_db sync): nil once
 the persisted root orders at or above the newest committed root this node knows, so that
 persistedEpoch >= committedEpoch; PBTimeoutError after milliseconds (a SmallInteger >= 0, or nil
 for no deadline); PBUnexpectedError at once when the persister failed. Nil at once when the node
 knows no committed root, and without a coordinator (commits are persisted when they return).
 A durability barrier, not a visibility barrier: it says nothing about commits this node has not
 learnt yet. A commit another member acknowledged reaches this node asynchronously, so a
 transaction started right after sync: can still miss it. To read every commit acknowledged
 anywhere before the read starts, commit on this node first something that writes (a run: that
 sets a root, such as '_read_barrier') and start the read after it returns normally: a commit
 that writes nothing, or one that ends in an error, is no barrier."
PBObjectSpace >> sync: milliseconds
  | root |
  (milliseconds isNil or: [(milliseconds isKindOf: SmallInteger) and: [milliseconds >= 0]]) ifFalse: [
    ^ PBValidationError signal: 'sync: takes milliseconds, a SmallInteger >= 0, or nil, not ' , milliseconds printString].
  self _checkOpen.
  coordinator isNil ifTrue: [^ nil].
  root := coordinator committedRoot.
  root isNil ifTrue: [^ nil].
  (persister waitFor: root within: milliseconds) wait.
  ^ nil.

"The epoch of the newest committed root this node knows (proto_db committed_epoch), 0 when none;
 without a coordinator, the storage's root epoch (0 for an empty space). It never goes backwards,
 forceRejoin on a survivor aside (PBClusterCoordinator >> committedRoot)."
PBObjectSpace >> committedEpoch
  | record |
  self _checkOpen.
  coordinator isNil ifFalse: [^ coordinator committedEpoch].
  record := storage readRoot.
  ^ record isNil ifTrue: [0] ifFalse: [record epoch].

"The PBSpaceRoot aRootRecord points to, nil for nil. A space root committed by
 a cluster node is PBNotSupportedError, unless the space has a coordinator."
PBObjectSpace >> _spaceRootAt: aRootRecord
  | record root |
  record := aRootRecord.
  record isNil ifTrue: [^ nil].
  root := PBTypeRegistry unloadedAtomFor: (PBTypeRegistry aliasOf: PBSpaceRoot typeName)
    at: record pointer storage: storage.
  (coordinator isNil and: [root clusterTerm notNil]) ifTrue: [
    ^ PBNotSupportedError signal: 'PBObjectSpace: the space root at ' , record pointer printString
      , ' was committed by a cluster node (cluster_term ' , root clusterTerm printString
      , '): it is read only by a cluster node, PBObjectSpace storage:coordinator:'].
  ^ root.

"The current PBDatabaseRoot of the database aName, or nil."
PBObjectSpace >> _databaseRootNamed: aName
  ^ self _databaseRootNamed: aName in: self _currentSpaceRoot.

"The PBDatabaseRoot of the database aName in aSpaceRoot (nil: an empty
 space), or nil."
PBObjectSpace >> _databaseRootNamed: aName in: aSpaceRoot
  | found |
  aSpaceRoot isNil ifTrue: [^ nil].
  found := aSpaceRoot databases getAt: aName.
  ^ _PBTree node: found kind: PBDatabaseRoot in: aSpaceRoot databases.

PBObjectSpace >> listDatabases
  | root |
  root := self _currentSpaceRoot.
  root isNil ifTrue: [^ #()].
  ^ _PBNames sorted: root databases keys.

"Creates the database aName and answers it (ProtoBase new_database): the
 round runner commits its version 0 (a PBCommitEntry createDatabase:,
 PBPublisher >> _newDatabase:on:). An existing name is PBValidationError."
PBObjectSpace >> newDatabase: aName
  _PBNameCheck check: aName what: 'database'.
  self _checkOpen.
  self _commitEntry: (PBCommitEntry createDatabase: aName deadline: self _deadline).
  ^ PBDatabase basicNew _setSpace: self name: aName.

PBObjectSpace >> openDatabase: aName
  _PBNameCheck check: aName what: 'database'.
  (self _databaseRootNamed: aName) isNil ifTrue: [
    ^ PBValidationError signal: 'Database ' , (PBCodec repr: aName) , ' does not exist'].
  ^ PBDatabase basicNew _setSpace: self name: aName.

"Closes the space and its storage. Idempotent. With a coordinator, its cluster
 round is closed first (every commit in it settled: PBClosedError when nothing
 of it left the node, PBOutcomeUnknownError once its root's replicate left),
 then its persister is stopped (a sync: waiting fails with PBTimeoutError; a
 write in flight finishes first, proto_db detach stops the persister), then its tier is detached and the node's acceptor log closed (proto_db close); the
 coordinator keeps running. The storage is closed by the round runner, after a
 round of the commits queued before (store.st: a close never interrupts a
 publish)."
PBObjectSpace >> close
  (closed value: true ifCurrent: false) ifFalse: [^ self].
  [[[coordinator isNil ifFalse: [runner closeRound wait]]
      ensure: [persister isNil ifFalse: [persister stop wait]]]
     ensure: [tier isNil ifFalse: [[(coordinator _detach: tier) wait] ensure: [tier close]]]]
    ensure: [runner closeStorage wait].

PBObjectSpace >> printOn: aStream
  aStream nextPutAll: 'PBObjectSpace('; print: storage; nextPut: $).

"=== PBDatabase ==============================================================="

"A handle on a named database of a space: cheap and stateless, as ProtoBase's."
Object subclass: #PBDatabase instanceVariableNames: 'space dbName'.

PBDatabase >> _setSpace: aSpace name: aName
  "Runs once, on a fresh instance."
  space isNil ifFalse: [^ PBUserError signal: 'PBDatabase is initialised once'].
  space := aSpace.
  dbName := aName.
  ^ self.

PBDatabase >> space
  ^ space.

"The database name."
PBDatabase >> name
  ^ dbName.

"The current PBDatabaseRoot; PBValidationError when the database is gone."
PBDatabase >> _currentRoot
  | root |
  root := space _databaseRootNamed: dbName.
  root isNil ifTrue: [^ PBValidationError signal: 'Database ' , (PBCodec repr: dbName) , ' does not exist'].
  ^ root.

"The committed versions, newest first, as PBHistoryEntry objects."
PBDatabase >> history
  | root entries |
  root := self _currentRoot.
  entries := OrderedCollection new.
  [root notNil] whileTrue: [
    entries add: (PBHistoryEntry basicNew _setRoot: root database: dbName).
    root := root previous].
  ^ entries asArray.

"The read-only PBSnapshot of the version a PBHistoryEntry or a PBSnapshot
 names, after the identity checks (module comment)."
PBDatabase >> snapshotAt: aReference
  | recordedName root |
  space _checkOpen.
  (aReference isClassObject not and: [(aReference isKindOf: PBSnapshot) or: [aReference isKindOf: PBHistoryEntry]])
    ifFalse: [
      ^ PBReferenceError signal: 'snapshotAt: a PBHistoryEntry or a PBSnapshot was expected, not '
        , aReference printString].
  recordedName := aReference databaseName.
  root := aReference _root.
  recordedName = dbName ifFalse: [
    ^ PBReferenceError signal: 'The reference names the database ' , recordedName printString , ', not '
      , (PBCodec repr: dbName)].
  root origin = self _currentRoot origin ifFalse: [
    ^ PBReferenceError signal: 'The reference names a version of another database, not of ' , (PBCodec repr: dbName)
      , ' (another incarnation of the name, or another space)'].
  ^ PBSnapshot basicNew _setRoot: root database: self.

"The space's sync: (proto_db Database.sync): a durability barrier, not a visibility one."
PBDatabase >> sync: milliseconds
  ^ space sync: milliseconds.

PBDatabase >> printOn: aStream
  aStream nextPutAll: 'PBDatabase('; print: dbName; nextPut: $).

"=== the versions ============================================================="

"The read messages of one version (a PBDatabaseRoot): PBHistoryEntry and
 PBSnapshot."
Object subclass: #_PBVersionView instanceVariableNames: 'root'.

_PBVersionView >> _root
  ^ root.

_PBVersionView >> version
  ^ root version.

"When the version was committed: an aware UTC DateTime."
_PBVersionView >> committedAt
  ^ root committedAt.

"The names of the roots of this version, sorted."
_PBVersionView >> rootNames
  ^ _PBNames sorted: root objects keys.

"The names of the mutable cells of this version, sorted."
_PBVersionView >> mutableNames
  ^ _PBNames sorted: root mutables keys.

"The value of the mutable cell aName in this version, nil when absent."
_PBVersionView >> getMutable: aName
  ^ root mutables getAt: (_PBNameCheck check: aName what: 'mutable').

_PBVersionView subclass: #PBHistoryEntry instanceVariableNames: 'databaseName'.

PBHistoryEntry >> _setRoot: aDatabaseRoot database: aName
  "Runs once, on a fresh instance."
  root isNil ifFalse: [^ PBUserError signal: 'PBHistoryEntry is initialised once'].
  root := aDatabaseRoot.
  databaseName := aName.
  ^ self.

"The name of the database this version belongs to."
PBHistoryEntry >> databaseName
  ^ databaseName.

PBHistoryEntry >> printOn: aStream
  aStream nextPutAll: 'PBHistoryEntry(version '; print: root version; nextPut: $).

_PBVersionView subclass: #PBSnapshot instanceVariableNames: 'database'.

PBSnapshot >> _setRoot: aDatabaseRoot database: aDatabase
  "Runs once, on a fresh instance."
  root isNil ifFalse: [^ PBUserError signal: 'PBSnapshot is initialised once'].
  root := aDatabaseRoot.
  database := aDatabase.
  ^ self.

"The PBDatabase this version belongs to."
PBSnapshot >> database
  ^ database.

PBSnapshot >> databaseName
  ^ database name.

"The value of the root aName in this version, nil when absent."
PBSnapshot >> getRootObject: aName
  ^ root objects getAt: (_PBNameCheck check: aName what: 'root').

PBSnapshot >> printOn: aStream
  aStream nextPutAll: 'PBSnapshot('; print: database name; nextPutAll: ', version '; print: root version; nextPut: $).
