"-- transactions.st: PBTransaction, read side --

ProtoBase's Transaction (proto_db/transactions.py at v2.0.0rc1; design spec
7.1), reading:

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
  aTransaction abort              ends the transaction; nothing is published
  aTransaction isActive           true until commit or abort
  aTransaction database           the PBDatabase
  aTransaction readSet            root name -> token, a PBFrozenDict
  aTransaction mutableReadSet     cell name -> token, a PBFrozenDict
  aMutableObject get: aTransaction
                                  aTransaction getMutable: its name

After abort, every message but isActive, database, readSet and
mutableReadSet signals PBUserError (ProtoBase's properties is_active and
database answer in any state; the two read sets are test-visible
diagnostics). A name is checked before the state, as in ProtoBase: an
invalid name is PBValidationError in any state.

Tokens (design spec 7.1, ProtoBase _token): what a read remembers of a value.
An atom's token is its storage pointer (a PBAtomPointer); a plain value's is
its exact token (PBKeys exactToken:, the bytes of its canonical encoding), so
1 and 1.0, or Decimal 1 and Decimal 1.00, have different tokens; a plain
value that holds atoms is PBTuple { its exact token. PBTuple of the atoms'
pointers in encoding order }; an absent name is #absent (unambiguous: every
other token is a ByteArray, a PBAtomPointer or a PBTuple, never a String).

The bookkeeping is one immutable PBTxState in an Atom, replaced with swap:
(design spec 7.1): reads, writes, replaced, mreads, mwrites, mexpected and
state (#active, #committing, #committed, #aborted). The maps are PBFrozenDicts
keyed by name; replaced and mexpected are sets, held as PBFrozenDicts from
name to true. A call reads the snapshot outside the swap (a read has no side
effect) and records its token inside it, so two actors misusing one
transaction still see each call happen entirely before or after the other.
The writes, commit and the publisher come with plan Task 18."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/keys'.
Import from: 'protobase/codec'.
Import from: 'protobase/registry'.
Import from: 'protobase/collections'.
Import from: 'protobase/roots'.
Import from: 'protobase/space'.

"=== PBTxState ================================================================="

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

"The value of writes or mwrites for a removed name (plan Task 18)."
PBTxState class >> removed
  ^ Removed.

"The state of a new transaction: every map empty, #active."
PBTxState class >> initial
  | empty |
  empty := PBFrozenDict withAssociations: #().
  ^ self basicNew _setReads: empty writes: empty replaced: empty mreads: empty mwrites: empty
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

"Root name -> token of the first read of each root."
PBTxState >> reads
  ^ reads.

"Root name -> the value written, or PBTxState removed."
PBTxState >> writes
  ^ writes.

"The root names written with replace: true or removed (name -> true)."
PBTxState >> replaced
  ^ replaced.

"Cell name -> token of the first read of each mutable cell."
PBTxState >> mreads
  ^ mreads.

"Cell name -> the value written, or PBTxState removed."
PBTxState >> mwrites
  ^ mwrites.

"The cells set blindly, which must still exist at commit (name -> true)."
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
  ^ PBTxState basicNew _setReads: (PBTxState _map: reads with: aName -> aToken) writes: writes
    replaced: replaced mreads: mreads mwrites: mwrites mexpected: mexpected state: state.

"A copy whose mreads also map aName to aToken."
PBTxState >> withMutableRead: aName token: aToken
  ^ PBTxState basicNew _setReads: reads writes: writes replaced: replaced
    mreads: (PBTxState _map: mreads with: aName -> aToken) mwrites: mwrites mexpected: mexpected state: state.

"A copy in the state aSymbol."
PBTxState >> withState: aSymbol
  ^ PBTxState basicNew _setReads: reads writes: writes replaced: replaced mreads: mreads mwrites: mwrites
    mexpected: mexpected state: aSymbol.

"aPBFrozenDict with anAssociation added (its key must be absent)."
PBTxState class >> _map: aPBFrozenDict with: anAssociation
  ^ PBFrozenDict withAssociations: aPBFrozenDict associations , { anAssociation }.

PBTxState >> printOn: aStream
  aStream nextPutAll: 'PBTxState('; print: state; nextPutAll: ', '; print: reads size; nextPutAll: ' reads)'.

PBTxState _initializeMarks.

"=== PBTransaction ============================================================="

Object subclass: #PBTransaction
  instanceVariableNames: 'database epoch snapshotPointer spaceRoot dbRoot objects mutables bookkeeping'.

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
    ^ PBValidationError signal: 'Database ' , aDatabase name printString , ' does not exist'].
  ^ self basicNew _setDatabase: aDatabase record: record spaceRoot: spaceRoot root: dbRoot.

PBTransaction >> _setDatabase: aDatabase record: aRootRecord spaceRoot: aSpaceRoot root: aDatabaseRoot
  "Runs once, on a fresh instance. objects and mutables are read here, as
   ProtoBase's constructor reads them."
  bookkeeping isNil ifFalse: [^ PBUserError signal: 'PBTransaction is initialised once'].
  database := aDatabase.
  epoch := aRootRecord isNil ifTrue: [0] ifFalse: [aRootRecord epoch].
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

"The epoch of the root record the transaction started from (0: an empty space),
 for the commit (plan Task 18)."
PBTransaction >> _epoch
  ^ epoch.

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
  ^ bookkeeping value reads.

"Cell name -> token of every mutable cell read so far, a PBFrozenDict."
PBTransaction >> mutableReadSet
  ^ bookkeeping value mreads.

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

"=== the end =================================================================="

"Discards the transaction: nothing is published. PBUserError when it already
 ended."
PBTransaction >> abort
  bookkeeping swap: [:st | st checkActive withState: #aborted].

"=== helpers =================================================================="

PBTransaction >> _written: aValue
  ^ aValue == PBTxState removed ifTrue: [nil] ifFalse: [aValue].

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
