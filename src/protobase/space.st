"-- space.st: PBObjectSpace, PBDatabase, PBSnapshot and PBHistoryEntry, read side --

ProtoBase's ObjectSpace, Database, Snapshot and HistoryEntry
(proto_db/transactions.py at v2.0.0rc1; design spec 5.2 and 6), reading:

  PBObjectSpace registerAtomClass: aClass   PBTypeRegistry register: aClass
  PBObjectSpace storage: aStorage           a space over aStorage (it owns it:
                                            close closes it); lockTimeout 30000 ms
  PBObjectSpace storage: s lockTimeout: ms  ms, a positive SmallInteger (the root
                                            lock wait of a commit)
  aSpace listDatabases                      the database names, sorted
  aSpace newDatabase: aName                 creates the database (version 0)
                                            through the space's publisher and
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
space whose SpaceRoot carries cluster_term was committed by a cluster node and
is PBNotSupportedError, like a directory holding cluster/ (PBFileStorage),
since clusters are outside the prototype (design spec 10.5). snapshotAt:
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
Import from: 'protobase/publisher'.

Object subclass: #_PBNameCheck.

"aName, a non-empty String; PBValidationError otherwise (ProtoBase _check_name)."
_PBNameCheck class >> check: aName what: aWhat
  ((aName isString and: [aName isSymbol not]) and: [aName notEmpty]) ifTrue: [^ aName].
  ^ PBValidationError signal: 'A ' , aWhat , ' name must be a non-empty String, not ' , aName printString.

"=== PBObjectSpace ============================================================"

Object subclass: #PBObjectSpace instanceVariableNames: 'storage lockTimeout closed publisher'.

PBObjectSpace class >> registerAtomClass: aClass
  ^ PBTypeRegistry register: aClass.

PBObjectSpace class >> defaultLockTimeout
  ^ 30000.

PBObjectSpace class >> storage: aStorage
  ^ self storage: aStorage lockTimeout: self defaultLockTimeout.

PBObjectSpace class >> storage: aStorage lockTimeout: milliseconds
  (aStorage isNil or: [aStorage isClassObject]) ifTrue: [
    ^ PBValidationError signal: 'PBObjectSpace storage: a storage was expected, not ' , aStorage printString].
  ((milliseconds isKindOf: SmallInteger) and: [milliseconds > 0]) ifFalse: [
    ^ PBValidationError signal: 'PBObjectSpace: lockTimeout is a positive SmallInteger of milliseconds, not '
      , milliseconds printString].
  ^ self basicNew _setStorage: aStorage lockTimeout: milliseconds.

PBObjectSpace >> _setStorage: aStorage lockTimeout: milliseconds
  "Runs once, on a fresh instance."
  storage isNil ifFalse: [^ PBUserError signal: 'PBObjectSpace is initialised once'].
  storage := aStorage.
  lockTimeout := milliseconds.
  closed := Atom on: false.
  publisher := (PBPublisher space: self) asActor.
  ^ self.

PBObjectSpace >> storage
  ^ storage.

"Milliseconds a commit waits for the root lock."
PBObjectSpace >> lockTimeout
  ^ lockTimeout.

PBObjectSpace >> isClosed
  ^ closed value.

"The first wait between two attempts to take the root lock, and the longest,
 in milliseconds (ProtoBase FileStorage._acquire_process_lock: 0.001 s
 doubling up to 0.05 s)."
PBObjectSpace class >> firstLockDelay
  ^ 1.

PBObjectSpace class >> longestLockDelay
  ^ 50.

"Sends one publish attempt to the publisher (aBlock: the publisher proxy -> a
 Future of true when published, false when the root lock is held) until one
 publishes. Between attempts the caller waits, never the publisher (ruling
 R19; publisher.st): (Future after: d) wait, d from firstLockDelay doubling up
 to longestLockDelay, until lockTimeout milliseconds have passed on the
 monotonic clock, then PBTimeoutError (ProtoBase's message, in milliseconds).
 An error of an attempt ends the loop. Inside an actor these waits are nested
 in blocks, so they block the caller's worker, which helps other actors
 meanwhile; the publisher is never buried under them, because it never
 waits."
PBObjectSpace >> _untilPublished: aBlock
  | deadline delay remaining |
  deadline := Time millisecondClockValue + lockTimeout.
  delay := PBObjectSpace firstLockDelay.
  [(aBlock value: publisher) wait] whileFalse: [
    remaining := deadline - Time millisecondClockValue.
    remaining <= 0 ifTrue: [
      ^ PBTimeoutError signal: 'Could not acquire the root lock within ' , lockTimeout printString
        , ' ms (held by another process or storage)'].
    (Future after: (delay min: remaining)) wait.
    delay := delay * 2 min: PBObjectSpace longestLockDelay].

PBObjectSpace >> _checkOpen
  closed value ifTrue: [^ PBClosedError signal: 'PBObjectSpace is closed'].

"The PBSpaceRoot the storage's root record points to now, or nil (an empty
 space)."
PBObjectSpace >> _currentSpaceRoot
  ^ self _spaceRootAt: self _snapshotRecord.

"The storage's current root record (a PBRootRecord), or nil for an empty
 space: what a new transaction starts from (ProtoBase _snapshot_record)."
PBObjectSpace >> _snapshotRecord
  self _checkOpen.
  ^ storage readRoot.

"The PBSpaceRoot aRootRecord points to, nil for nil. A space root committed by
 a cluster node is PBNotSupportedError."
PBObjectSpace >> _spaceRootAt: aRootRecord
  | record root |
  record := aRootRecord.
  record isNil ifTrue: [^ nil].
  root := PBTypeRegistry unloadedAtomFor: (PBTypeRegistry aliasOf: PBSpaceRoot typeName)
    at: record pointer storage: storage.
  root clusterTerm isNil ifFalse: [
    ^ PBNotSupportedError signal: 'PBObjectSpace: the space root at ' , record pointer printString
      , ' was committed by a cluster node (cluster_term ' , root clusterTerm printString
      , '): clusters are not supported by protoBaseST'].
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
 publisher commits its version 0 (PBPublisher >> createDatabase:). An existing
 name is PBValidationError."
PBObjectSpace >> newDatabase: aName
  _PBNameCheck check: aName what: 'database'.
  self _checkOpen.
  self _untilPublished: [:p | p createDatabase: aName].
  ^ PBDatabase basicNew _setSpace: self name: aName.

PBObjectSpace >> openDatabase: aName
  _PBNameCheck check: aName what: 'database'.
  (self _databaseRootNamed: aName) isNil ifTrue: [
    ^ PBValidationError signal: 'Database ' , (PBCodec repr: aName) , ' does not exist'].
  ^ PBDatabase basicNew _setSpace: self name: aName.

"Closes the space and its storage. Idempotent. The storage is closed by the
 publisher, after the commits sent to it before (store.st: a close never
 interrupts a publish)."
PBObjectSpace >> close
  (closed value: true ifCurrent: false) ifTrue: [publisher closeStorage wait].

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
