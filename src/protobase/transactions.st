"-- transactions.st: PBTransaction --

ProtoBase's Transaction (proto_db/transactions.py at v2.0.0rc2; design spec
7.1 and 7.3). Reading:

  aDatabase newTransaction        a PBTransaction on the database's current
                                  version: the root record, the SpaceRoot and
                                  the DatabaseRoot are read once, here (a
                                  missing database is PBValidationError)
  aTransaction getRootObject: n   the root n (nil when absent): the
                                  transaction's own write first, else the
                                  snapshot's value, whose token the first read
                                  records
  aTransaction rootNames          the names as the transaction sees them,
                                  sorted; records nothing
  aTransaction getMutable: n      the mutable cell n (nil when absent), recorded
                                  in mreads on the first read
  aTransaction mutableNames       the cell names, sorted; records nothing
  aTransaction isActive           true until commit or abort
  aTransaction database           the PBDatabase
  aTransaction readSet            root name -> token, a PBFrozenDict
  aTransaction mutableReadSet     cell name -> token, a PBFrozenDict
  aMutableObject get: aTransaction
                                  aTransaction getMutable: its name

Writing (ProtoBase set_root_object, remove_root_object, new_mutable,
set_mutable, remove_mutable and the factories):

  aTransaction setRootObject: n value: v
  aTransaction setRootObject: n value: v replace: aBoolean
                                  the root n is v at commit; a name starting
                                  with '__' is PBValidationError (reserved for
                                  the format); replace: true, or a set after a
                                  removal of n, stores v as written (no merge)
  aTransaction removeRootObject: n
                                  n is removed at commit (absent then: no-op)
  aTransaction newMutable: n value: v
                                  creates the cell n (absent in the view, which
                                  is recorded; present: PBValidationError) and
                                  answers its PBMutableObject
  aTransaction setMutable: n value: v
                                  the existing cell n is v at commit (absent:
                                  PBValidationError); without an earlier write
                                  of n it is blind: n must exist at commit
  aTransaction removeMutable: n   the existing cell n is removed at commit
  aMutableObject set: aTransaction value: v
                                  aTransaction setMutable: its name value: v
  newList, newDictionary, newHashDictionary, newSet, newCountedSet,
  newObject: { name -> value. ... }
                                  new values built in this process (a new
                                  collection's log is complete, so a blind
                                  write of it merges)

A written value passes PBCodec canonical:for: at once, with the holder
Root 'name' or Mutable 'name' (ProtoBase canonical_for), so a refusal (a
Symbol, a Dictionary, a value deeper than MAX_VALUE_DEPTH) names where the
value was going and the transaction stays active. The checks run in
ProtoBase's order: the name, then the value, then the state.

Ending:

  aTransaction commit             publishes the writes through the space's
                                  publisher (publisher.st) and waits for it;
                                  with no writes, publishes nothing (plan call
                                  C16); the transaction ends either way:
                                  committed, or aborted after a failure
  aTransaction abort              ends the transaction; nothing is published
  aDatabase newTransactionDo: aBlock
                                  aBlock with a new transaction, committed when
                                  the block ends, normally or by ^ (if still
                                  active), aborted when an exception ends it
                                  (the exception goes on; one resumed by an
                                  enclosing handler does not end it); no
                                  retry; answers the block's value

After the end, every message but isActive, database, readSet and
mutableReadSet signals PBUserError (ProtoBase's properties is_active and
database answer in any state; the two read sets are test-visible
diagnostics). A name is checked before the state, as in ProtoBase: an
invalid name is PBValidationError in any state.

The commit (design spec 7.3; ProtoBase _build_root, _merged and
_check_mutables), built by the publisher under the root lock with
_buildOn:. When the root read under the lock is the transaction's snapshot,
nothing changed. Otherwise every read token must equal the token of the same
name in the current version, every blindly set cell must still exist, and
the database must still exist: PBConflictError otherwise. The new version
starts from the current objects and mutables: a removed root or cell is
removed if present; a root written but neither read nor replaced is merged
(_merged:onto:: a collection with a complete log, onto a current value of the
same class, is rebased, rebaseOnto:; anything else replaces); a root read or
replaced is stored as written; a cell is stored as written, never merged.
version + 1, previous the current version, origin carried, committedAt
max(now, previous committedAt) in UTC. After the publish, every collection the
transaction wrote is marked consumed (D33).

Tokens (design spec 7.1, ProtoBase _token): what a read remembers of a value.
An atom's token is its storage pointer (a PBAtomPointer); a plain value's is
its exact token (PBKeys exactToken:, the bytes of its canonical encoding), so
1 and 1.0, or Decimal 1 and Decimal 1.00, have different tokens; a plain
value that holds atoms is PBTuple { its exact token. PBTuple of the atoms'
pointers in encoding order }; an absent name is #absent (unambiguous: every
other token is a ByteArray, a PBAtomPointer or a PBTuple, never a String).

The bookkeeping is one immutable PBTxState in an Atom, replaced with swap:
(design spec 7.1): reads, writes, replaced, mreads, mwrites, mexpected and
state (#active, #committing, #committed, #aborted). Every map is persistent
(_PBNameMap: a first read or a write costs O(log n), not a rebuild): reads and
mreads are _PBReadMaps; writes, mwrites, and the sets replaced and mexpected
(name -> true) are _PBWriteMaps. A read call reads the snapshot outside the
swap (a read has no side effect) and records its token inside it; a write
call checks and records inside one swap; so two actors misusing one
transaction still see each call happen entirely before or after the other."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/keys'.
Import from: 'protobase/codec'.
Import from: 'protobase/registry'.
Import from: 'protobase/collections'.
Import from: 'protobase/roots'.
Import from: 'protobase/space'.

"=== _PBNameMap, _PBReadMap, _PBWriteMap ======================================="

"A map from name to value, in first-insertion order, persistent. Adding a name
 answers a new map in O(log n) and leaves the receiver unchanged: the entries
 live in a protoST Dictionary, which is a wrapper over an immutable protoCore
 map, so copy shares the structure and at:put: on the copy path-copies one
 branch (LANGUAGE 9.10). The Dictionary is filled before the new map is made
 and never changed afterwards, nor ever answered (immutability by convention,
 as every value of this module). Each entry is { position. value }, so the
 order is rebuilt in O(n) when the map is walked or answered as a PBFrozenDict
 (review M5 of plan Task 13: a PBFrozenDict rebuilt on every insertion made n
 insertions cost O(n^2)). Two kinds: _PBReadMap (the read sets: a name is
 recorded once) and _PBWriteMap (the writes, the replaced names, the cell
 writes and the expected cells: a later write of a name replaces its value and
 keeps its place, as a Python dict does)."
Object subclass: #_PBNameMap instanceVariableNames: 'entries'.

_PBNameMap class >> empty
  ^ self basicNew _setEntries: Dictionary new.

_PBNameMap >> _setEntries: aDictionary
  "Runs once, on a fresh instance."
  entries isNil ifFalse: [^ PBUserError signal: self class name , ' is immutable'].
  entries := aDictionary.
  ^ self.

_PBNameMap >> size
  ^ entries size.

_PBNameMap >> isEmpty
  ^ entries isEmpty.

_PBNameMap >> includesKey: aName
  ^ entries includesKey: aName.

"The value of aName; an absent name signals KeyNotFound."
_PBNameMap >> at: aName
  ^ (entries at: aName) at: 2.

"A map of the receiver's class that also maps aName to aValue: a new name
 goes last, a known one keeps its place."
_PBNameMap >> _with: aName value: aValue
  | copy |
  copy := entries copy.
  copy at: aName put: { (entries at: aName ifAbsent: [{ entries size + 1 }]) at: 1. aValue }.
  ^ self class basicNew _setEntries: copy.

"name -> value Associations, in first-insertion order."
_PBNameMap >> associations
  | ordered |
  ordered := Array new: entries size.
  entries keysAndValuesDo: [:name :entry | ordered at: (entry at: 1) put: name -> (entry at: 2)].
  ^ ordered.

"Evaluates aBlock with each name and its value, in first-insertion order."
_PBNameMap >> keysAndValuesDo: aBlock
  self associations do: [:each | aBlock value: each key value: each value].

"The map as a PBFrozenDict, in first-insertion order."
_PBNameMap >> asFrozenDict
  ^ PBFrozenDict withAssociations: self associations.

"A read set: name -> token, each name recorded once."
_PBNameMap subclass: #_PBReadMap.

"A map that also maps aName (absent here) to aToken, last in order."
_PBReadMap >> with: aName token: aToken
  (entries includesKey: aName) ifTrue: [
    ^ PBUserError signal: '_PBReadMap: ' , (PBCodec repr: aName) , ' is recorded already'].
  ^ self _with: aName value: aToken.

"The writes of a transaction: name -> the value written (or PBTxState removed),
 and the sets of names (name -> true)."
_PBNameMap subclass: #_PBWriteMap.

"A map that maps aName to aValue: last in order when aName is new, in its
 place otherwise."
_PBWriteMap >> with: aName value: aValue
  ^ self _with: aName value: aValue.

"=== PBTxState ================================================================"

"The bookkeeping of a transaction at one moment: immutable; every change
 answers a new PBTxState."
Object subclass: #PBTxState instanceVariableNames: 'reads writes replaced mreads mwrites mexpected state'
  classVariableNames: 'Missing Removed'.

"The two marks, made once when the module loads. They are private objects,
 never Symbols: a Symbol is the equal String in protoST (STATUS D35), so
 #removed could not be told from a root holding the string 'removed'."
PBTxState class >> _initializeMarks
  Missing isNil ifTrue: [Missing := Object new].
  Removed isNil ifTrue: [Removed := Object new].

"What a lookup in the snapshot answers for an absent name (never a value)."
PBTxState class >> missing
  ^ Missing.

"The value of writes or mwrites for a removed name."
PBTxState class >> removed
  ^ Removed.

"The state of a new transaction: every map empty, #active."
PBTxState class >> initial
  | empty |
  empty := _PBWriteMap empty.
  ^ self basicNew _setReads: _PBReadMap empty writes: empty replaced: empty mreads: _PBReadMap empty mwrites: empty
    mexpected: empty state: #active.

PBTxState class >> states
  ^ #(#active #committing #committed #aborted).

PBTxState >> _setReads: r writes: w replaced: rp mreads: mr mwrites: mw mexpected: me state: aSymbol
  "Runs once, on a fresh instance."
  state isNil ifFalse: [^ PBUserError signal: 'PBTxState is immutable'].
  (PBTxState states includes: aSymbol) ifFalse: [
    ^ PBValidationError signal: 'PBTxState: the state is one of ' , PBTxState states printString , ', not '
      , aSymbol printString].
  reads := r. writes := w. replaced := rp.
  mreads := mr. mwrites := mw. mexpected := me.
  state := aSymbol.
  ^ self.

"Root name -> token of the first read of each root (a _PBReadMap)."
PBTxState >> reads
  ^ reads.

"Root name -> the value written, or PBTxState removed (a _PBWriteMap)."
PBTxState >> writes
  ^ writes.

"The root names written with replace: true or removed (name -> true, a
 _PBWriteMap)."
PBTxState >> replaced
  ^ replaced.

"Cell name -> token of the first read of each mutable cell (a _PBReadMap)."
PBTxState >> mreads
  ^ mreads.

"Cell name -> the value written, or PBTxState removed (a _PBWriteMap)."
PBTxState >> mwrites
  ^ mwrites.

"The cells set blindly, which must still exist at commit (name -> true, a
 _PBWriteMap)."
PBTxState >> mexpected
  ^ mexpected.

PBTxState >> state
  ^ state.

PBTxState >> isActive
  ^ state == #active.

"The receiver; PBUserError unless it is active (ProtoBase _check_active)."
PBTxState >> checkActive
  state == #active ifFalse: [
    ^ PBUserError signal: 'The transaction is ' , state asString , '; start a new one'].
  ^ self.

"A copy whose reads also map aName to aToken."
PBTxState >> withRead: aName token: aToken
  ^ PBTxState basicNew _setReads: (reads with: aName token: aToken) writes: writes
    replaced: replaced mreads: mreads mwrites: mwrites mexpected: mexpected state: state.

"A copy whose mreads also map aName to aToken."
PBTxState >> withMutableRead: aName token: aToken
  ^ PBTxState basicNew _setReads: reads writes: writes replaced: replaced
    mreads: (mreads with: aName token: aToken) mwrites: mwrites mexpected: mexpected state: state.

"A copy whose writes map aName to aValue (a value, or PBTxState removed). The
 name is marked replaced when aBoolean is true, or when its previous write in
 this transaction was a removal (ProtoBase set_root_object), or when aValue is
 a removal (remove_root_object); a mark is never cleared."
PBTxState >> withWrite: aName value: aValue replace: aBoolean
  | marked |
  marked := (aBoolean or: [aValue == Removed])
    or: [(writes includesKey: aName) and: [(writes at: aName) == Removed]].
  ^ PBTxState basicNew _setReads: reads writes: (writes with: aName value: aValue)
    replaced: (marked ifTrue: [replaced with: aName value: true] ifFalse: [replaced])
    mreads: mreads mwrites: mwrites mexpected: mexpected state: state.

"A copy whose mwrites map aName to aValue (a value, or PBTxState removed); a
 blind set (aBoolean true) also enters mexpected."
PBTxState >> withMutableWrite: aName value: aValue expected: aBoolean
  ^ PBTxState basicNew _setReads: reads writes: writes replaced: replaced mreads: mreads
    mwrites: (mwrites with: aName value: aValue)
    mexpected: (aBoolean ifTrue: [mexpected with: aName value: true] ifFalse: [mexpected]) state: state.

"Whether the transaction has nothing to publish: no root and no cell written
 (ProtoBase _commit returns at once then, plan call C16)."
PBTxState >> hasNoWrites
  ^ writes isEmpty and: [mwrites isEmpty].

"A copy in the state aSymbol."
PBTxState >> withState: aSymbol
  ^ PBTxState basicNew _setReads: reads writes: writes replaced: replaced mreads: mreads mwrites: mwrites
    mexpected: mexpected state: aSymbol.

PBTxState >> printOn: aStream
  aStream nextPutAll: 'PBTxState('; print: state; nextPutAll: ', '; print: reads size; nextPutAll: ' reads)'.

PBTxState _initializeMarks.

"=== PBTransaction ============================================================="

Object subclass: #PBTransaction
  instanceVariableNames: 'database snapshotPointer spaceRoot dbRoot objects mutables bookkeeping'.

"A transaction on aDatabase's current version (PBDatabase >> newTransaction)."
PBTransaction class >> _on: aDatabase
  | space record spaceRoot dbRoot |
  (aDatabase isKindOf: PBDatabase) ifFalse: [
    ^ PBValidationError signal: 'PBTransaction: a PBDatabase was expected, not ' , aDatabase printString].
  space := aDatabase space.
  record := space _snapshotRecord.
  spaceRoot := space _spaceRootAt: record.
  dbRoot := space _databaseRootNamed: aDatabase name in: spaceRoot.
  dbRoot isNil ifTrue: [
    ^ PBValidationError signal: 'Database ' , (PBCodec repr: aDatabase name) , ' does not exist'].
  ^ self basicNew _setDatabase: aDatabase record: record spaceRoot: spaceRoot root: dbRoot.

PBTransaction >> _setDatabase: aDatabase record: aRootRecord spaceRoot: aSpaceRoot root: aDatabaseRoot
  "Runs once, on a fresh instance. objects and mutables are read here, as
   ProtoBase's constructor reads them."
  bookkeeping isNil ifFalse: [^ PBUserError signal: 'PBTransaction is initialised once'].
  database := aDatabase.
  snapshotPointer := aRootRecord isNil ifTrue: [nil] ifFalse: [aRootRecord pointer].
  spaceRoot := aSpaceRoot.
  dbRoot := aDatabaseRoot.
  objects := aDatabaseRoot objects.
  mutables := aDatabaseRoot mutables.
  bookkeeping := Atom on: PBTxState initial.
  ^ self.

"The PBDatabase this transaction works on."
PBTransaction >> database
  ^ database.

"The pointer of the SpaceRoot the transaction started from."
PBTransaction >> _snapshotPointer
  ^ snapshotPointer.

"The PBSpaceRoot the transaction started from."
PBTransaction >> _spaceRoot
  ^ spaceRoot.

"The PBDatabaseRoot of the version the transaction reads."
PBTransaction >> _root
  ^ dbRoot.

"True until the transaction is committed or aborted."
PBTransaction >> isActive
  ^ bookkeeping value isActive.

"The current PBTxState, after checking it is active (PBUserError otherwise)."
PBTransaction >> _activeState
  ^ bookkeeping value checkActive.

"Root name -> token of every root read so far (module comment), a PBFrozenDict."
PBTransaction >> readSet
  ^ bookkeeping value reads asFrozenDict.

"Cell name -> token of every mutable cell read so far, a PBFrozenDict."
PBTransaction >> mutableReadSet
  ^ bookkeeping value mreads asFrozenDict.

"=== roots ===================================================================="

"The value of the root aName (nil when absent). The transaction's own write
 comes first; otherwise the snapshot's value, and the first read of aName
 records its token (absence included)."
PBTransaction >> getRootObject: aName
  | st value |
  _PBNameCheck check: aName what: 'root'.
  st := self _activeState.
  (st writes includesKey: aName) ifTrue: [^ self _written: (st writes at: aName)].
  value := objects getAt: aName default: PBTxState missing.
  (st reads includesKey: aName) ifFalse: [self _recordRead: aName token: (self _tokenOf: value) in: #reads].
  ^ value == PBTxState missing ifTrue: [nil] ifFalse: [value].

"The names of the roots as this transaction sees them, sorted. Nothing is
 recorded: to create a root only when it is absent, test getRootObject:,
 whose read is recorded (ProtoBase root_names)."
PBTransaction >> rootNames
  ^ self _namesOf: objects written: self _activeState writes.

"=== mutable cells ============================================================"

"The value of the mutable cell aName (nil when absent); the first read records
 its token in mreads (ProtoBase get_mutable)."
PBTransaction >> getMutable: aName
  | st value |
  _PBNameCheck check: aName what: 'mutable'.
  st := self _activeState.
  (st mwrites includesKey: aName) ifTrue: [^ self _written: (st mwrites at: aName)].
  value := mutables getAt: aName default: PBTxState missing.
  (st mreads includesKey: aName) ifFalse: [self _recordRead: aName token: (self _tokenOf: value) in: #mreads].
  ^ value == PBTxState missing ifTrue: [nil] ifFalse: [value].

"The names of the mutable cells as this transaction sees them, sorted; not
 recorded."
PBTransaction >> mutableNames
  ^ self _namesOf: mutables written: self _activeState mwrites.

"=== writes ==================================================================="

"Sets the root aName to aValue at commit (ProtoBase set_root_object): merged
 into the current value when the root was neither read nor replaced and the
 value is a collection with a complete log (design spec 7.3 step 4)."
PBTransaction >> setRootObject: aName value: aValue
  ^ self setRootObject: aName value: aValue replace: false.

"As setRootObject:value:; with aBoolean true the value is stored as written
 (last writer wins, no merge), and the name stays marked replaced for the rest
 of the transaction. The checks come in ProtoBase's order: the name, the '__'
 prefix the format reserves, replace:, the value (PBCodec canonical:for: with
 the holder Root 'name'), and only then the state."
PBTransaction >> setRootObject: aName value: aValue replace: aBoolean
  | value |
  _PBNameCheck check: aName what: 'root'.
  (aName beginsWith: '__') ifTrue: [
    ^ PBValidationError signal: 'Root names starting with ''__'' are reserved for the format, not ' , (PBCodec repr: aName)].
  (aBoolean == true or: [aBoolean == false]) ifFalse: [
    ^ PBValidationError signal: 'replace must be a Boolean, not ' , aBoolean printString].
  value := PBCodec canonical: aValue for: 'Root ' , (PBCodec repr: aName).
  bookkeeping swap: [:st | st checkActive withWrite: aName value: value replace: aBoolean].

"Removes the root aName at commit (a no-op if it is absent then); a later set
 of the name in this transaction replaces (ProtoBase remove_root_object)."
PBTransaction >> removeRootObject: aName
  _PBNameCheck check: aName what: 'root'.
  bookkeeping swap: [:st | st checkActive withWrite: aName value: PBTxState removed replace: true].

"Creates the mutable cell aName holding aValue at commit and answers its
 PBMutableObject (ProtoBase new_mutable). The cell's absence in this
 transaction's view is recorded in mreads, so a concurrent creator makes one of
 the two commits conflict; an existing cell is PBValidationError, after its
 read is recorded, as in ProtoBase."
PBTransaction >> newMutable: aName value: aValue
  | value exists |
  _PBNameCheck check: aName what: 'mutable'.
  value := PBCodec canonical: aValue for: 'Mutable ' , (PBCodec repr: aName).
  bookkeeping swap: [:st |
    | current view |
    current := st checkActive.
    view := self _mutableView: aName in: current.
    ((current mwrites includesKey: aName) or: [current mreads includesKey: aName]) ifFalse: [
      current := current withMutableRead: aName token: (self _tokenOf: view)].
    exists := view ~~ PBTxState missing.
    exists ifTrue: [current] ifFalse: [current withMutableWrite: aName value: value expected: false]].
  exists ifTrue: [^ PBValidationError signal: 'Mutable ' , (PBCodec repr: aName) , ' already exists'].
  ^ PBMutableObject name: aName.

"Sets the existing mutable cell aName to aValue at commit (ProtoBase
 set_mutable): stored as written, never merged. An absent cell is
 PBValidationError. A set with no earlier write of the cell in this
 transaction is blind: the cell must still exist at commit (mexpected), but a
 concurrent set is not a conflict."
PBTransaction >> setMutable: aName value: aValue
  | value absent |
  _PBNameCheck check: aName what: 'mutable'.
  value := PBCodec canonical: aValue for: 'Mutable ' , (PBCodec repr: aName).
  bookkeeping swap: [:st |
    | current |
    current := st checkActive.
    absent := (self _mutableView: aName in: current) == PBTxState missing.
    absent
      ifTrue: [current]
      ifFalse: [current withMutableWrite: aName value: value expected: (current mwrites includesKey: aName) not]].
  absent ifTrue: [
    ^ PBValidationError signal: 'Mutable ' , (PBCodec repr: aName) , ' does not exist; create it with newMutable:value:'].

"Removes the existing mutable cell aName at commit (ProtoBase remove_mutable);
 an absent cell is PBValidationError. A cell removed meanwhile by a concurrent
 commit makes the removal a no-op, not a conflict."
PBTransaction >> removeMutable: aName
  | absent |
  _PBNameCheck check: aName what: 'mutable'.
  bookkeeping swap: [:st |
    | current |
    current := st checkActive.
    absent := (self _mutableView: aName in: current) == PBTxState missing.
    absent ifTrue: [current] ifFalse: [current withMutableWrite: aName value: PBTxState removed expected: false]].
  absent ifTrue: [^ PBValidationError signal: 'Mutable ' , (PBCodec repr: aName) , ' does not exist'].

"=== factories ================================================================"

"A new empty collection of aClass, while the transaction is active. It is
 built empty in this process, so its log is complete: a blind write of it
 merges (design spec 7.2)."
PBTransaction >> _new: aClass
  self _activeState.
  ^ aClass new.

PBTransaction >> newList
  ^ self _new: PBList.

PBTransaction >> newDictionary
  ^ self _new: PBDictionary.

PBTransaction >> newHashDictionary
  ^ self _new: PBHashDictionary.

PBTransaction >> newSet
  ^ self _new: PBSet.

PBTransaction >> newCountedSet
  ^ self _new: PBCountedSet.

"A new PBObject with the attributes anArray (name -> value Associations), as
 ProtoBase's new_object(**attributes)."
PBTransaction >> newObject: anArray
  self _activeState.
  ^ PBObject withAll: anArray.

"=== the end =================================================================="

"Discards the transaction: nothing is published. PBUserError when it already
 ended."
PBTransaction >> abort
  bookkeeping swap: [:st | st checkActive withState: #aborted].

"Commits the writes (design spec 7.3): the space's publisher validates the
 reads against the newest root, merges, saves and publishes. This call sends
 it attempts and waits for each (PBObjectSpace >> _untilPublished:): while the
 root lock is held by another holder, it waits and tries again, the publisher
 never does (ruling R19). Inside an actor these waits are nested in ensure:,
 so they block the actor's worker, which helps other actors meanwhile; they do
 not suspend the actor. A transaction with no writes publishes nothing (plan
 call C16). PBConflictError when a root or cell it read changed, or a merge
 conflicts; PBTimeoutError when the root lock is not taken within the space's
 lockTimeout; PBOutcomeUnknownError when the publish failed and its outcome
 could not be decided. The transaction ends either way: committed, or aborted
 after a failure (ProtoBase commit)."
PBTransaction >> commit
  | st committed |
  bookkeeping swap: [:current | st := current checkActive. current withState: #committing].
  committed := false.
  [st hasNoWrites ifFalse: [database space _untilPublished: [:publisher | publisher commit: self]].
   committed := true]
    ensure: [bookkeeping swap: [:current | current withState: (committed ifTrue: [#committed] ifFalse: [#aborted])]].

"=== the build (on the publisher, under the root lock) ========================"

"The new PBSpaceRoot of this transaction's commit on the root record
 aRootRecord, read under the root lock (nil: an empty space), unsaved, built
 after the validation of the reads (ProtoBase _build_root, design spec 7.3
 steps 3 and 4). PBConflictError when a root or cell read changed, a blindly
 set cell was removed, or the database no longer exists."
PBTransaction >> _buildOn: aRootRecord
  | st space current root newObjects currentObjects cells newRoot |
  st := bookkeeping value.
  st state == #committing ifFalse: [
    ^ PBUserError signal: 'PBTransaction: only a committing transaction is built, not a ' , st state asString , ' one'].
  space := database space.
  (aRootRecord isNil ifTrue: [nil] ifFalse: [aRootRecord pointer]) = snapshotPointer
    ifTrue: [
      "The very root the transaction started from: nothing changed since."
      current := spaceRoot.
      root := dbRoot]
    ifFalse: [
      current := space _spaceRootAt: aRootRecord.
      root := space _databaseRootNamed: database name in: current.
      root isNil ifTrue: [^ PBConflictError signal: 'Database ' , (PBCodec repr: database name) , ' no longer exists'].
      self _checkReads: st reads in: root objects what: 'Root'.
      (st mreads isEmpty and: [st mexpected isEmpty]) ifFalse: [self _checkMutables: root mutables in: st]].
  currentObjects := root objects.
  newObjects := currentObjects.
  st writes keysAndValuesDo: [:name :value |
    value == PBTxState removed
      ifTrue: [(newObjects has: name) ifTrue: [newObjects := newObjects removeAt: name]]
      ifFalse: [
        newObjects := newObjects setAt: name value: (((st reads includesKey: name) or: [st replaced includesKey: name])
          ifTrue: [value]
          ifFalse: [self _merged: value onto: (currentObjects getAt: name default: PBTxState missing)])]].
  cells := root mutables.
  st mwrites keysAndValuesDo: [:name :value |
    value == PBTxState removed
      ifTrue: [(cells has: name) ifTrue: [cells := cells removeAt: name]]
      ifFalse: [cells := cells setAt: name value: value]].
  newRoot := PBDatabaseRoot objects: newObjects mutables: cells version: root version + 1
    committedAt: (PBDatabaseRoot committedAfter: root committedAt) origin: root origin previous: root.
  ^ PBSpaceRoot databases: (current databases setAt: database name value: newRoot).

"PBConflictError unless every token of aReadMap is the token of the same name
 in aDictionary now (ProtoBase _same_token)."
PBTransaction >> _checkReads: aReadMap in: aDictionary what: aKind
  aReadMap keysAndValuesDo: [:name :token |
    (self _sameToken: token as: (self _tokenOf: (aDictionary getAt: name default: PBTxState missing))) ifFalse: [
      ^ PBConflictError signal: aKind , ' ' , (PBCodec repr: name) , ' of database ' , (PBCodec repr: database name)
        , ' was changed by a concurrent commit']].

"ProtoBase _check_mutables: a read cell that changed, or a blindly set cell
 that is gone, is PBConflictError."
PBTransaction >> _checkMutables: aDictionary in: aState
  self _checkReads: aState mreads in: aDictionary what: 'Mutable'.
  aState mexpected keysAndValuesDo: [:name :ignored |
    (aDictionary has: name) ifFalse: [
      ^ PBConflictError signal: 'Mutable ' , (PBCodec repr: name) , ' of database ' , (PBCodec repr: database name)
        , ' was removed by a concurrent commit']].

PBTransaction >> _sameToken: aToken as: anotherToken
  (aToken == #absent or: [anotherToken == #absent]) ifTrue: [^ aToken == anotherToken].
  ^ aToken = anotherToken.

"The value to store for a root written but neither read nor replaced
 (ProtoBase _merged): aValue rebased onto aCurrent when aValue is a collection
 with a complete log and aCurrent exists and is of the same class; aValue
 otherwise (last writer wins). A rebase onto an indexed current is
 PBNotSupportedError (design spec 7.4)."
PBTransaction >> _merged: aValue onto: aCurrent
  aCurrent == PBTxState missing ifTrue: [^ aValue].
  ((aValue isKindOf: PBIndexedCollection) and: [aValue isMergeable and: [aCurrent class == aValue class]])
    ifFalse: [^ aValue].
  ^ aValue rebaseOnto: aCurrent.

"The atoms written as roots or cells, which the publisher saves before it
 takes the root lock (ProtoBase _commit saves each written Atom before
 _commit_root); atoms nested in a plain value are saved with the new root."
PBTransaction >> _writtenAtoms
  | st out |
  st := bookkeeping value.
  out := OrderedCollection new.
  { st writes. st mwrites } do: [:map |
    map keysAndValuesDo: [:name :value | (value isKindOf: PBAtom) ifTrue: [out addLast: value]]].
  ^ out asArray.

"After a successful publish: every collection this transaction wrote has had
 its log replayed, so it and the versions derived from it are no longer
 mergeable (D33; ProtoBase clears _log_complete on each written value)."
PBTransaction >> _markConsumed
  | st |
  st := bookkeeping value.
  { st writes. st mwrites } do: [:map |
    map keysAndValuesDo: [:name :value |
      (value isKindOf: PBIndexedCollection) ifTrue: [value markConsumed]]].

"=== helpers =================================================================="

PBTransaction >> _written: aValue
  ^ aValue == PBTxState removed ifTrue: [nil] ifFalse: [aValue].

"The cell aName as aState's transaction sees it: its own write, else the
 snapshot's value; PBTxState missing when absent (ProtoBase _mutable_view,
 without recording)."
PBTransaction >> _mutableView: aName in: aState
  | value |
  (aState mwrites includesKey: aName) ifTrue: [
    value := aState mwrites at: aName.
    ^ value == PBTxState removed ifTrue: [PBTxState missing] ifFalse: [value]].
  ^ mutables getAt: aName default: PBTxState missing.

"Records aToken for aName in the map aSelector (#reads or #mreads), unless a
 read recorded it meanwhile, and only while the transaction is active."
PBTransaction >> _recordRead: aName token: aToken in: aSelector
  bookkeeping swap: [:st |
    | current |
    current := st checkActive.
    ((current perform: aSelector) includesKey: aName)
      ifTrue: [current]
      ifFalse: [aSelector == #reads
        ifTrue: [current withRead: aName token: aToken]
        ifFalse: [current withMutableRead: aName token: aToken]]].

"The sorted names of aDictionary (a PBDictionary) as changed by aWrites."
PBTransaction >> _namesOf: aDictionary written: aWrites
  | names |
  names := Set withAll: aDictionary keys.
  aWrites keysAndValuesDo: [:name :value |
    value == PBTxState removed ifTrue: [names remove: name ifAbsent: []] ifFalse: [names add: name]].
  ^ _PBNames sorted: names.

"The token of aValue (module comment)."
PBTransaction >> _tokenOf: aValue
  | atoms bytes |
  aValue == PBTxState missing ifTrue: [^ #absent].
  (aValue isKindOf: PBAtom) ifTrue: [^ aValue pointer].
  atoms := OrderedCollection new.
  bytes := MessagePack encode: (PBCodec toWire: aValue atomRef: [:anAtom |
    atoms add: anAtom.
    PBCodec tokenRef value: anAtom]).
  atoms isEmpty ifTrue: [^ bytes].
  ^ PBTuple withAll: { bytes. PBTuple withAll: (atoms collect: [:each | each pointer]) }.

PBTransaction >> printOn: aStream
  aStream nextPutAll: 'PBTransaction('; print: database name; nextPutAll: ', version '; print: dbRoot version;
    nextPutAll: ', '; print: bookkeeping value state; nextPut: $).

"=== entry points on other classes ============================================"

"A new PBTransaction on the database's current version."
PBDatabase >> newTransaction
  space _checkOpen.
  ^ PBTransaction _on: self.

"The value of this cell in aTransaction (ProtoBase MutableObject.get):
 aTransaction getMutable: name."
PBMutableObject >> get: aTransaction
  ^ aTransaction getMutable: self name.

"Runs aBlock with a new transaction and answers its value (ProtoBase's
 'with db.new_transaction() as tr:'). The transaction is committed when the
 block ends, normally or by a non-local return (^, Python's return inside the
 with block), if it is still active; a failure of that commit is signalled.
 It is aborted when an exception ends the block (ProtoBase's __exit__ aborts
 on any exception), and the exception goes on unchanged. There is no retry
 (run: retries).
 An exception that is not resumable can only end the block: it aborts at once
 and is passed. A resumable one, an Error such as ZeroDivide included (ruling
 R20b), is handed to the enclosing handlers with outer while inFlight is true:
 if they resume it, the block goes on from the signal with their value and
 nothing ends (an unhandled Warning or Notification resumes with nil); if they
 end it (return:, retry, falling off, ^) or it is unhandled and its default
 action ends the activation, the unwind passes through here with inFlight
 still true and the ensure: block aborts. So the transaction is aborted
 exactly when an exception unwinds the block, and committed otherwise,
 including a ^ taken after a resumed exception."
PBDatabase >> newTransactionDo: aBlock
  | tr inFlight |
  tr := self newTransaction.
  inFlight := false.
  ^ [[aBlock value: tr] on: Exception do: [:e | | answer |
       e isResumable ifFalse: [
         tr isActive ifTrue: [tr abort].
         e pass].
       inFlight := true.
       answer := e outer.
       inFlight := false.
       e resume: answer]]
    ensure: [tr isActive ifTrue: [inFlight ifTrue: [tr abort] ifFalse: [tr commit]]].

"The milliseconds to wait after the failed attempt number anAttempt (from 0) of run:retries:backoff:
 (ProtoBase Database.run: uniform(d/2, d) seconds with d = min(high, low * 2^attempt)): d * (0.5 + r / 2)
 for r in [0, 1) drawn from aRandom, rounded to a whole number of milliseconds (a SmallInteger). The
 random source is a parameter so that the bounds are tested with a seeded Random, never by timing."
PBDatabase class >> backoffFor: anAttempt low: aLow high: aHigh random: aRandom
  | d |
  d := aHigh min: aLow * (2 raisedTo: anAttempt).
  ^ (d * (0.5 + (aRandom next / 2))) rounded.

"Runs aBlock with a new transaction and answers its value: run: aBlock retries: 10 backoff: #(1 200)."
PBDatabase >> run: aBlock
  ^ self run: aBlock retries: 10 backoff: #(1 200).

"run: aBlock retries: n backoff: #(1 200)."
PBDatabase >> run: aBlock retries: aCount
  ^ self run: aBlock retries: aCount backoff: #(1 200).

"Runs aBlock with a new transaction, as newTransactionDo: does, and answers its value (ProtoBase
 Database.run). A PBConflictError, signalled by the commit, by a merge or by aBlock itself, aborts the
 attempt (newTransactionDo: aborts whenever an exception unwinds the block) and the block runs again with a
 fresh transaction, at most aCount more times, after waiting backoffFor:low:high:random: milliseconds
 ((Future after: d) wait; aBackoff is #(low high) in milliseconds, ProtoBase's seconds pair scaled). After
 the last retry the conflict is signalled again. Any other exception aborts the attempt and goes on
 unretried; notably PBOutcomeUnknownError, because the commit may have been applied. A block that ends its
 transaction itself is not committed again (newTransactionDo: commits only an active one). The checks of
 ProtoBase run first: aCount a non-negative Integer, aBackoff a pair of numbers 0 <= low <= high
 (PBValidationError)."
PBDatabase >> run: aBlock retries: aCount backoff: aBackoff
  | low high random |
  (aCount isInteger and: [aCount >= 0]) ifFalse: [
    ^ PBValidationError signal: 'run: retries must be a non-negative Integer, not ' , aCount printString].
  ((aBackoff isKindOf: Array) and: [aBackoff size = 2]) ifFalse: [
    ^ PBValidationError signal: 'run: backoff must be a (low, high) pair of milliseconds, not '
      , aBackoff printString].
  low := aBackoff first.
  high := aBackoff last.
  ((low isNumber and: [high isNumber]) and: [low >= 0 and: [high >= low]]) ifFalse: [
    ^ PBValidationError signal: 'run: backoff must satisfy 0 <= low <= high, not ' , aBackoff printString].
  random := Random new.
  0 to: aCount do: [:attempt | | failed value |
    failed := false.
    value := [self newTransactionDo: aBlock] on: PBConflictError do: [:conflict |
      attempt = aCount ifTrue: [conflict pass].
      failed := true.
      nil].
    failed ifFalse: [^ value].
    (Future after: (PBDatabase backoffFor: attempt low: low high: high random: random)) wait].
  ^ PBUnexpectedError signal: 'run: the retry loop always answers or signals'.

"Sets this cell to aValue in aTransaction (ProtoBase MutableObject.set):
 aTransaction setMutable: name value: aValue."
PBMutableObject >> set: aTransaction value: aValue
  ^ aTransaction setMutable: self name value: aValue.
