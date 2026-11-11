"-- registry.st: PBTypeRegistry and PBAtom, the type names of format 4 --

The format spec (v2.0.0rc1) sections 'Type names (D57)', 'Atoms of unknown
types (D59)' and 'Built-in type aliases', with ProtoBase's proto_db/core/atom.py
(register_atom_class, type_tag, type_name_of, opaque_class) as the reference:

  PBTypeRegistry register: aClass     registers aClass typeName and aClass typeAliases
  PBTypeRegistry classForTag: aTag    the class of a persisted tag (an alias Integer
                                      or a name), PBOpaqueAtom for an unknown
                                      application name
  PBTypeRegistry tagFor: aClass       the tag a writer puts in a record or a @ref
  PBTypeRegistry nameOfTag: aTag      the declared type name a tag stands for
  PBTypeRegistry canonicalTag: aTag   the tag a writer puts for the type aTag names
  PBTypeRegistry writerTag: aTag      the same, refusing (PBValidationError) a
                                      name every reader must refuse
  PBTypeRegistry builtinNames         the normative table of the 22 built-in aliases

  PBAtom          the abstract base of every persistent object: oid, pointer,
                  storage and the lazy-load memo
  PBOpaqueAtom    an atom of a type this process has no class for (D59)

The registry is process-wide: one Atom cell over a table that maps each
registered name (declared names and aliases) to a PBTuple { class. declared
name }. The table is a hashed Dictionary snapshot, so a lookup takes constant
time; it is private and never changed once installed: a registration copies
it, adds its names to the copy and installs the copy by compare-and-swap, so
readers never lock and never see a half-made table. The built-in alias table
is built once, when the module loads, the same way.

Declared names follow the grammar of 'Type names' (two or more dotted ASCII
identifiers). Aliases are any non-empty strings (format spec D57: every
implementation of a type declares the same aliases, and ProtoBase accepts any
non-empty str in __type_aliases__): a pre-D57 Python default name such as
'myapp.models.make.<locals>.Person', or one with non-ASCII identifiers, is
outside the grammar but still names stored data. Writers never write an alias.

Lookups of a name never registered:
  - a built-in name (or alias Integer) whose class is not registered yet is
    PBNotSupportedError naming the type (every built-in type is known to every
    reader; a missing class is a gap of this implementation, never corruption);
  - any other name starting with proto_db. is PBCorruptionError;
  - a name outside the grammar is PBCorruptionError;
  - any other name is an opaque atom: PBOpaqueAtom.

Names written before D57 by ProtoBase (Python module.QualifiedName names of
application classes) are read like any other name: an application class lists
them in typeAliases, as ProtoBase's __type_aliases__."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.

Object subclass: #PBTypeRegistry classVariableNames: 'Registry BuiltinNames BuiltinAliases'.

"=== the built-in alias table ================================================"

"Format spec, 'Built-in type aliases': the alias of a built-in type is its
 index here (0-based). Append-only (D51). The conformance runner checks it
 against manifest.json's builtin_type_aliases. Answers a fresh copy."
PBTypeRegistry class >> builtinNames
  ^ BuiltinNames copy.

PBTypeRegistry class >> _builtinTable
  ^ #('proto_db.avl.KeyNode' 'proto_db.avl.PosNode' 'proto_db.avl.ValueBox'
      'proto_db.collections.IndexSet' 'proto_db.collections.IndexedCollection'
      'proto_db.collections.List' 'proto_db.collections.Dictionary'
      'proto_db.collections.RepeatedKeysDictionary' 'proto_db.collections.HashDictionary'
      'proto_db.collections.sets._HashBuckets' 'proto_db.collections.Set'
      'proto_db.collections.CountedSet' 'proto_db.indexing.Index'
      'proto_db.indexing.keyed.KeyGroupIndex' 'proto_db.indexing.EqualityIndex'
      'proto_db.indexing.RangeIndex' 'proto_db.indexing.VectorIndex'
      'proto_db.transactions.SpaceRoot' 'proto_db.transactions.DatabaseRoot'
      'proto_db.core.dbobject.DBObject' 'proto_db.avl._Node'
      'proto_db.avl.CountedKeyNode').

PBTypeRegistry class >> builtinCount
  ^ 22.

"The alias Integer of a built-in type name, or nil (constant time)."
PBTypeRegistry class >> aliasOf: aName
  (aName isString and: [aName isSymbol not]) ifFalse: [^ nil].
  ^ BuiltinAliases at: aName ifAbsent: [nil].

"=== the grammar ============================================================="

"Format spec 'Type names': two or more ASCII identifiers ([A-Za-z_][A-Za-z0-9_]*)
 joined by dots."
PBTypeRegistry class >> isValidName: aName
  | parts |
  (aName isString and: [aName isSymbol not]) ifFalse: [^ false].
  (aName isEmpty or: [aName first = $. or: [aName last = $.]]) ifTrue: [^ false].
  parts := aName subStrings: '.'.
  parts size >= 2 ifFalse: [^ false].
  "subStrings: drops empty parts: a doubled dot would hide among them."
  (aName occurrencesOf: $.) = (parts size - 1) ifFalse: [^ false].
  ^ parts allSatisfy: [:part | self _isIdentifier: part].

PBTypeRegistry class >> _isIdentifier: aString
  | first |
  aString isEmpty ifTrue: [^ false].
  first := aString first asInteger.
  ((first between: 65 and: 90) or: [(first between: 97 and: 122) or: [first = 95]]) ifFalse: [^ false].
  ^ aString allSatisfy: [:ch |
    | c |
    c := ch asInteger.
    (c between: 65 and: 90) or: [(c between: 97 and: 122) or: [(c between: 48 and: 57) or: [c = 95]]]].

"=== the process-wide table =================================================="

PBTypeRegistry class >> _initializeRegistry
  | aliases |
  BuiltinNames := self _builtinTable copy.
  aliases := Dictionary new.
  BuiltinNames doWithIndex: [:name :i | aliases at: name put: i - 1].
  BuiltinAliases := aliases.
  Registry := Atom on: Dictionary new.

"The current table: a Dictionary snapshot, never changed once installed."
PBTypeRegistry class >> _table
  ^ Registry value.

"The PBTuple { class. declaredName } registered under aName, or nil."
PBTypeRegistry class >> _entryFor: aName
  ^ self _table at: aName ifAbsent: [nil].

"Registers aClass under aClass typeName and each of aClass typeAliases. The
 name must follow the grammar, and a name of the reserved proto_db. namespace
 must be in the built-in table; an alias is any non-empty String that is not a
 built-in name (see the module comment). A name or an
 alias already registered by another class is PBValidationError. Registering
 the same class again is a no-op. Answers aClass."
PBTypeRegistry class >> register: aClass
  | name aliases |
  (aClass isClassObject and: [aClass respondsTo: #typeName]) ifFalse: [
    ^ PBValidationError signal: 'PBTypeRegistry register: a class answering typeName was expected, not '
      , aClass printString].
  name := aClass typeName.
  aliases := aClass typeAliases.
  self _checkDeclaredName: name of: aClass.
  ((aliases isKindOf: Array) and: [aliases isString not]) ifFalse: [
    ^ PBValidationError signal: 'PBTypeRegistry: ' , aClass name , ' typeAliases must be an Array of type names, not '
      , aliases printString].
  aliases do: [:alias |
    ((alias isString and: [alias isSymbol not]) and: [alias notEmpty]) ifFalse: [
      ^ PBValidationError signal: 'PBTypeRegistry: the alias ' , alias printString , ' of ' , aClass name
        , ' is not a non-empty String'].
    (self aliasOf: alias) isNil ifFalse: [
      ^ PBValidationError signal: 'PBTypeRegistry: the alias ' , alias printString , ' of ' , aClass name
        , ' is a built-in type name'].
    alias = name ifTrue: [
      ^ PBValidationError signal: 'PBTypeRegistry: ' , aClass name , ' lists its own name among its aliases']].
  (aliases asSet size = aliases size) ifFalse: [
    ^ PBValidationError signal: 'PBTypeRegistry: ' , aClass name , ' typeAliases repeats a name: ' , aliases printString].
  [ | old new additions |
    old := self _table.
    additions := OrderedCollection new.
    ({ name } , aliases) do: [:key |
      | entry |
      entry := old at: key ifAbsent: [nil].
      entry isNil
        ifTrue: [additions add: key -> (PBTuple withAll: { aClass. name })]
        ifFalse: [
          ((entry at: 1) == aClass and: [(entry at: 2) = name]) ifFalse: [
            ^ PBValidationError signal: 'PBTypeRegistry: the type name ' , key printString
              , ' is already registered by ' , (entry at: 1) name]]].
    additions isEmpty ifTrue: [^ aClass].
    new := old copy.
    additions do: [:each | new at: each key put: each value].
    Registry value: new ifCurrent: old ] whileFalse.
  ^ aClass.

PBTypeRegistry class >> _checkDeclaredName: aName of: aClass
  (self isValidName: aName) ifFalse: [
    ^ PBValidationError signal: 'PBTypeRegistry: ' , aClass name , ' typeName must be two or more dotted ASCII identifiers, such as ''acme.sales.Order'', not '
      , aName printString].
  ((aName beginsWith: 'proto_db.') and: [(self aliasOf: aName) isNil]) ifTrue: [
    ^ PBValidationError signal: 'PBTypeRegistry: ' , aName , ' is in the reserved proto_db. namespace but is not a built-in type'].

"Whether a class is registered under aName (a declared name or an alias)."
PBTypeRegistry class >> isRegistered: aName
  ^ (self _entryFor: aName) notNil.

"=== tags ===================================================================="

PBTypeRegistry class >> _badTag: aTag
  ^ PBCorruptionError signal: 'PBTypeRegistry: malformed atom type tag ' , aTag printString.

"The type name a persisted tag stands for: an alias Integer is its built-in
 name, an application alias is the declared name of its class, any other name
 is itself. An Integer outside the table, or a tag that is neither an Integer
 nor a non-empty String, is PBCorruptionError (proto_db type_name_of)."
PBTypeRegistry class >> nameOfTag: aTag
  | entry |
  (aTag isInteger and: [aTag ~~ true and: [aTag ~~ false]]) ifTrue: [
    (aTag between: 0 and: self builtinCount - 1) ifFalse: [^ self _badTag: aTag].
    ^ BuiltinNames at: aTag + 1].
  ((aTag isString and: [aTag isSymbol not]) and: [aTag notEmpty]) ifFalse: [^ self _badTag: aTag].
  entry := self _entryFor: aTag.
  ^ entry isNil ifTrue: [aTag] ifFalse: [entry at: 2].

"The tag a writer puts for the type aTag names (format spec, 'The name a writer
 puts in a reference'): the alias of a built-in type, the declared name of a
 registered application type, and any other name as read."
PBTypeRegistry class >> canonicalTag: aTag
  | name alias |
  name := self nameOfTag: aTag.
  alias := self aliasOf: name.
  ^ alias isNil ifTrue: [name] ifFalse: [alias].

"As canonicalTag:, for a writer: a tag every reader must refuse (malformed, a
 name outside the grammar, an unknown proto_db. name) is PBValidationError.
 An unknown application name is valid (an opaque atom's, written as read)."
PBTypeRegistry class >> writerTag: aTag
  | tag |
  tag := [self canonicalTag: aTag] on: PBCorruptionError do: [:e |
    ^ PBValidationError signal: 'PBTypeRegistry: cannot write the type tag ' , aTag printString , ': ' , e messageText].
  tag isInteger ifTrue: [^ tag].
  ((self isValidName: tag) and: [(tag beginsWith: 'proto_db.') not]) ifFalse: [
    ^ PBValidationError signal: 'PBTypeRegistry: cannot write the type name ' , tag printString
      , ', which every reader refuses (outside the grammar, or an unknown proto_db. name)'].
  ^ tag.

"Whether two tags name one type once aliases are mapped (malformed tags
 compare as written)."
PBTypeRegistry class >> isTag: aTag sameTypeAs: otherTag
  ^ [(self nameOfTag: aTag) = (self nameOfTag: otherTag)] on: PBCorruptionError do: [:e | aTag = otherTag].

"The class a persisted tag names (see the module comment for unknown names)."
PBTypeRegistry class >> classForTag: aTag
  | name entry |
  name := self nameOfTag: aTag.
  entry := self _entryFor: name.
  entry isNil ifFalse: [^ entry at: 1].
  (self aliasOf: name) isNil ifFalse: [
    ^ PBNotSupportedError signal: 'PBTypeRegistry: the built-in type ' , name , ' has no class in protoBaseST yet'].
  self checkOpaqueName: name.
  ^ PBOpaqueAtom.

"aName may be the type of an opaque atom: it follows the grammar and is
 outside the reserved proto_db. namespace; PBCorruptionError otherwise."
PBTypeRegistry class >> checkOpaqueName: aName
  ((self isValidName: aName) and: [(aName beginsWith: 'proto_db.') not]) ifFalse: [
    ^ PBCorruptionError signal: 'PBTypeRegistry: unknown atom type ' , aName printString].
  ^ aName.

"The tag a writer puts for aClass's records and references: the alias Integer
 of a built-in type, else the declared name. aClass must be registered under
 its typeName (PBValidationError otherwise: an opaque atom's tag is the name of
 the reference it was read through, PBOpaqueAtom >> tag)."
PBTypeRegistry class >> tagFor: aClass
  | name entry |
  name := (aClass isClassObject and: [aClass respondsTo: #typeName]) ifTrue: [aClass typeName] ifFalse: [nil].
  entry := (name isString and: [name isSymbol not]) ifTrue: [self _entryFor: name] ifFalse: [nil].
  (entry notNil and: [(entry at: 1) == aClass and: [(entry at: 2) = name]]) ifFalse: [
    ^ PBValidationError signal: 'PBTypeRegistry tagFor: ' , aClass printString , ' is not registered under its typeName'].
  ^ self canonicalTag: name.

"An unloaded atom for a reference: the class of aTag at aPointer of
 aStorage; for an unknown application name, a PBOpaqueAtom that keeps the
 name it was referenced by. The resolver of a storage answers this."
PBTypeRegistry class >> unloadedAtomFor: aTag at: aPointer storage: aStorage
  | cls |
  cls := self classForTag: aTag.
  cls == PBOpaqueAtom ifTrue: [^ PBOpaqueAtom named: (self nameOfTag: aTag) unloadedAt: aPointer storage: aStorage].
  ^ cls unloadedAt: aPointer storage: aStorage.

"=== PBAtom ================================================================="

"The abstract base of every persistent object. An atom holds oid (an Atom
 cell holding nil or its 16-byte oid), its pointer and storage (a stub's, set
 when it is made; nil for an atom made in memory), saved (for an atom made in
 memory, an Atom cell holding nil or the _PBPlace its save recorded; nil for a
 stub), and memo (an Atom cell holding nil or the loaded envelope: what
 storage loadAt:expecting: answers, tag, oid and the state PBFrozenDict). The
 cells are the runtime-only fields a load, a first need or the save fills
 (plan, immutability by convention), as ProtoBase sets oid and atom_pointer
 with object.__setattr__; each is filled once, by compare-and-swap, so two
 threads that race install one value and both answer it.

 Identity (ProtoBase D21, core/atom.py _assign_oid): an atom's oid is not a
 storage id. A stored atom's oid is its record's (a stub loads the record to
 read it). An atom that is not stored draws a random version-4 UUID in memory
 on first need (oid, =, hash, an order key or a hash key), never by saving;
 the save (_saveInto:, a first need too) persists that same oid. Two atoms
 are = when they are the same object or have the same oid, and hash by their
 oid, as ProtoBase's Atom.__eq__ and __hash__.

 The save (ProtoBase Atom._save) writes the dependents first: every atom a
 record refers to (attribute values, map keys, tree nodes, value boxes) is
 saved before the record, so a record only refers to records written before
 it, never to itself or forward (the save-dependents-first invariant; the
 reader's PBCorruptionError for a record that needs itself stays as a defence
 against damaged data). Atoms are immutable and built from atoms that exist
 already, so the references of unsaved atoms form no cycle."
Object subclass: #PBAtom instanceVariableNames: 'oid pointer storage saved memo'.

"The declared type name, two or more dotted ASCII identifiers; nil for an
 abstract class (never registered)."
PBAtom class >> typeName
  ^ nil.

"The names the type was persisted under before (ProtoBase __type_aliases__)."
PBAtom class >> typeAliases
  ^ #().

"The fields every record of this exact type must hold: a record without one
 is PBCorruptionError when it is loaded (D58). Only the classes of built-in
 types list fields (format spec, 'Required fields'): an application class,
 an application subclass of a built-in collection included, answers its
 built-in base's list unchanged, never a longer one, since a field it adds in
 a later release may be absent from its older records (it reads as nil)."
PBAtom class >> requiredFields
  ^ #().

"The attribute order the reference implementation writes for this type (the
 order the database vector's records show), which a writer reproduces."
PBAtom class >> persistedFields
  ^ #().

"The check of a loaded record's attribute names against the behaviour names
 of this class (format spec, 'Attribute names'): PBCorruptionError for a
 reserved name. The names every type refuses are the envelope's check; a
 class with behaviour names to reserve overrides this (PBObject)."
PBAtom class >> _checkPersistedNames: aState at: aPointer
  ^ aState.

"An atom of this class that is not stored: no pointer, no storage, no oid
 until its first need draws one (PBAtom >> oid), holding aPBFrozenDict as its
 state; the protected constructor under the public ones (PBObject withAll:,
 PBList new and the mutators, the AVL writes). The class need not be
 registered yet: as in ProtoBase, a class with no registered type name is
 refused when the atom is saved (PBAtom >> tag)."
PBAtom class >> _unsavedWithState: aPBFrozenDict
  (aPBFrozenDict isKindOf: PBFrozenDict) ifFalse: [
    ^ PBValidationError signal: self name , ': the state of an atom is a PBFrozenDict, not ' , aPBFrozenDict printString].
  ^ self _unsavedWithState: aPBFrozenDict tag: nil.

"As _unsavedWithState:, for a caller that built aPBFrozenDict itself. aTag is
 kept in the in-memory envelope only (the AVL writes pass the tag they computed
 once per class); the save writes PBAtom >> tag, read from the class."
PBAtom class >> _unsavedWithState: aPBFrozenDict tag: aTag
  ^ self _unsaved: self basicNew withState: aPBFrozenDict tag: aTag.

"aBlank (a fresh basicNew instance of this class, which a subclass may have
 given its own runtime-only fields first) made an unsaved atom holding
 aPBFrozenDict."
PBAtom class >> _unsaved: aBlank withState: aPBFrozenDict tag: aTag
  ^ (aBlank _setOid: nil pointer: nil storage: nil)
    _installState: (PBAtomEnvelope basicNew _setTag: aTag oid: nil state: aPBFrozenDict).

PBAtom >> _installState: anEnvelope
  "Runs once, on a fresh unsaved instance."
  (memo value: anEnvelope ifCurrent: nil) ifFalse: [^ PBUserError signal: 'PBAtom: the state is installed once'].
  ^ self.

"An unloaded atom (a stub) of this class: its record is at aPointer in
 aStorage and is loaded on first use."
PBAtom class >> unloadedAt: aPointer storage: aStorage
  (aPointer isKindOf: PBAtomPointer) ifFalse: [
    ^ PBValidationError signal: self name , ' unloadedAt: a PBAtomPointer was expected, not ' , aPointer printString].
  aStorage isNil ifTrue: [
    ^ PBValidationError signal: self name , ' unloadedAt:storage: needs a storage'].
  ^ self basicNew _setOid: nil pointer: aPointer storage: aStorage.

PBAtom >> _setOid: anOid pointer: aPointer storage: aStorage
  "Runs once, on a fresh instance. A stub (aPointer given) is stored from the
   start and has no saved cell; an atom made in memory gets one."
  memo isNil ifFalse: [^ PBUserError signal: 'PBAtom is initialised once'].
  oid := Atom on: anOid.
  pointer := aPointer.
  storage := aStorage.
  saved := aPointer isNil ifTrue: [Atom on: nil] ifFalse: [nil].
  memo := Atom on: nil.
  ^ self.

"A reference to an atom, for PBCodec."
PBAtom >> isPBReference
  ^ true.

"The atom's PBAtomPointer: a stub's, or the one its save recorded; nil while
 it is not saved."
PBAtom >> pointer
  | place |
  pointer isNil ifFalse: [^ pointer].
  saved isNil ifTrue: [^ nil].
  place := saved value.
  ^ place isNil ifTrue: [nil] ifFalse: [place pointer].

"The storage the atom is stored in (nil while it is not saved)."
PBAtom >> _storage
  | place |
  storage isNil ifFalse: [^ storage].
  saved isNil ifTrue: [^ nil].
  place := saved value.
  ^ place isNil ifTrue: [nil] ifFalse: [place storage].

"Whether the atom has a record (a stub, or an atom whose save is done)."
PBAtom >> isSaved
  ^ self pointer notNil.

"The oid when this atom holds it already (nil otherwise), without loading or
 drawing one: a stub learns its oid from its record, an atom that is not stored
 draws it on first need (oid)."
PBAtom >> knownOid
  ^ oid value.

"The tag a writer puts for this atom's type (PBTypeRegistry tagFor:)."
PBAtom >> tag
  ^ PBTypeRegistry tagFor: self class.

PBAtom >> isLoaded
  ^ memo value notNil.

"A new, unloaded stub of this stored atom: what a holder answers when it must
 not keep the record loaded (DatabaseRoot previous, D53). An atom with no
 stored record answers itself."
PBAtom >> unloadedCopy
  | ptr |
  ptr := self pointer.
  ptr isNil ifTrue: [^ self].
  ^ self class unloadedAt: ptr storage: self _storage.

"The loaded envelope, loading it once through the storage."
PBAtom >> _envelope
  ^ self _envelopeWithin: #().

"The loaded envelope, loaded within aChain: an Array of the pointers whose
 decoding is in progress on this call stack and needs this record (a map key
 is identified by its oid, so decoding a map whose keys are references loads
 them: PBCodec asks its resolver, _PBLoadResolver, to load each key within the
 chain extended by the record being decoded).

 A record whose pointer is already in the chain needs itself to be decoded (a
 map key that refers back to the record, directly or through other records
 keyed in turn): PBCorruptionError naming the pointer, never a recursion
 without end. ProtoBase cannot load such a record either (its load recurses
 until Python's RecursionError). ProtoBase saves every dependent before the
 record that refers to it, so a record only points to earlier records: such a
 record can only come from damaged data or from a writer that breaks that
 save-dependents-first invariant (review note N3 of plan Task 10). The chain is passed explicitly, never
 kept in a stub and never shared, so loads on other threads are independent and
 an application's exception handlers see nothing."
PBAtom >> _envelopeWithin: aChain
  | envelope missing |
  envelope := memo value.
  envelope isNil ifFalse: [^ envelope].
  (storage isNil or: [pointer isNil]) ifTrue: [
    ^ PBUserError signal: self class name , ': an atom with no stored record has no state to load'].
  (aChain includes: pointer) ifTrue: [
    ^ PBCorruptionError signal: 'the record at ' , pointer printString , ' (' , (PBTypeRegistry nameOfTag: self tag)
      , ') cannot be loaded: decoding its state needs the record itself (a map key refers back to it: damaged data, or a writer that broke the save-dependents-first invariant)'].
  envelope := storage loadAt: pointer expecting: self tag within: (aChain copyWith: pointer).
  missing := self class requiredFields reject: [:field | envelope state includesKey: field].
  missing isEmpty ifFalse: [
    ^ PBCorruptionError signal: 'the atom at ' , pointer printString , ' (' , (PBTypeRegistry nameOfTag: self tag)
      , ') lacks the required fields ' , missing printString].
  self class _checkPersistedNames: envelope state at: pointer.
  (memo value: envelope ifCurrent: nil) ifTrue: [^ envelope].
  ^ memo value.

"The persisted state, a PBFrozenDict of attribute name to value, in the
 record's order (loaded on first use)."
PBAtom >> state
  ^ self _envelope state.

"The value of the persisted attribute aName; an attribute the record does not
 hold reads as nil (an application type's later field, format spec 'Required
 fields')."
PBAtom >> stateAt: aName
  "Every field read of every atom runs here: the loaded envelope is read from
   its cell directly, and the lookup creates no block."
  | envelope state i |
  envelope := memo value.
  envelope isNil ifTrue: [envelope := self _envelope].
  state := envelope state.
  i := state _indexOfKey: aName.
  i = 0 ifTrue: [^ self _absentField: aName].
  ^ state _valueAt: i.

PBAtom >> _absentField: aName
  ^ nil.

"The atom's oid (16 bytes): the record's for a stored atom (a stub loads it);
 for an atom that is not stored, the one drawn on first need (ProtoBase D21)."
PBAtom >> oid
  | known |
  known := oid value.
  known isNil ifFalse: [^ known].
  pointer isNil ifFalse: [^ self _envelope oid].
  oid value: self _newOid ifCurrent: nil.
  ^ oid value.

"A fresh oid: the 16 bytes of a version-4 UUID (ProtoBase uuid.uuid4()). The
 seam a test overrides to drive two first readers in a chosen order."
PBAtom >> _newOid
  ^ UUID new bytes.

"ProtoBase Atom.__eq__: the same object, or another atom of the same oid."
PBAtom >> = anObject
  self == anObject ifTrue: [^ true].
  (anObject isClassObject not and: [anObject isKindOf: PBAtom]) ifFalse: [^ false].
  ^ self oid = anObject oid.

"ProtoBase Atom.__hash__: the hash of the oid."
PBAtom >> hash
  ^ self oid hash.

PBAtom >> printOn: aStream
  aStream nextPutAll: self class name; nextPutAll: '('; print: self pointer; nextPut: $).

"=== the save (ProtoBase Atom._save) ========================================

 aStorage is what a record is written to: it answers pushAtom: aPBAtomEnvelope
 with the PBAtomPointer of the ATOM record it appended (ProtoBase's
 storage.push_atom). PBFileStorage gains it with its owned segment (plan Task
 17); saves run on the space's publisher (plan Task 18), one at a time."

"A saved atom's place: its pointer and the storage it was written to (an
 immutable pair, what the saved cell of an atom holds)."
Object subclass: #_PBPlace instanceVariableNames: 'pointer storage'.

_PBPlace class >> pointer: aPointer storage: aStorage
  ^ self basicNew _setPointer: aPointer storage: aStorage.

_PBPlace >> _setPointer: aPointer storage: aStorage
  "Runs once, on a fresh instance."
  pointer isNil ifFalse: [^ PBUserError signal: '_PBPlace is immutable'].
  pointer := aPointer.
  storage := aStorage.
  ^ self.

_PBPlace >> pointer
  ^ pointer.

_PBPlace >> storage
  ^ storage.

"Saves this atom into aStorage unless it is saved there already, and answers
 its pointer. Every atom it refers to that is not saved is saved first, depth
 first in the order the encoder meets the references (attribute order; in a
 value, item order; a map entry's key before its value), each once, as
 ProtoBase's _save: so every reference in a written record points to an
 earlier record. Each record carries the atom's oid, drawn now if no need drew
 it before (ProtoBase D21), and the state in the order it was built (the
 order ProtoBase's constructors and _with set the attributes). Each atom
 records its place once saved (pointer answers it). The walk keeps an explicit
 stack, so a long chain of records does not recurse.

 Refused with PBValidationError: a class not registered under its typeName
 (PBTypeRegistry tagFor:, as ProtoBase refuses a class with no declared
 __type_name__), checked when the atom is first visited, so nothing beneath it
 is written; a value the codec refuses; an atom stored in another storage (its
 pointer would mean nothing in aStorage). A pointer pushAtom: answers stays
 valid for the life of the storage: the atom keeps it."
PBAtom >> _saveInto: aStorage
  | stack known |
  known := self _pointerIn: aStorage.
  known isNil ifFalse: [^ known].
  "Pairs { atom. its unsaved references, or nil before they are listed }."
  stack := OrderedCollection new.
  stack addLast: self; addLast: nil.
  [stack notEmpty] whileTrue: [
    | refs atom |
    refs := stack removeLast.
    atom := stack last.
    refs isNil
      ifTrue: [
        (atom _pointerIn: aStorage) isNil
          ifTrue: [
            "The class is checked before any dependent is written or bound to
             aStorage, as ProtoBase's _save checks the declared type name before
             it encodes the state."
            atom tag.
            refs := OrderedCollection new.
            atom state _pbAddUnsavedAtomsTo: refs in: aStorage.
            stack addLast: refs.
            refs size to: 1 by: -1 do: [:i | stack addLast: (refs at: i); addLast: nil]]
          ifFalse: [stack removeLast]]
      ifFalse: [
        stack removeLast.
        "A dependent met twice is saved once: the second visit finds it saved."
        (atom _pointerIn: aStorage) isNil ifTrue: [atom _pushInto: aStorage]]].
  ^ self pointer.

"The pointer of this atom in aStorage, or nil while it is not saved; an atom
 stored in another storage is PBValidationError."
PBAtom >> _pointerIn: aStorage
  | place |
  pointer isNil ifFalse: [
    storage == aStorage ifTrue: [^ pointer].
    ^ self _storedElsewhere: aStorage].
  place := saved value.
  place isNil ifTrue: [^ nil].
  place storage == aStorage ifTrue: [^ place pointer].
  ^ self _storedElsewhere: aStorage.

PBAtom >> _storedElsewhere: aStorage
  ^ PBValidationError signal: self printString , ' is stored in ' , self _storage printString
    , ', not in ' , aStorage printString , ': a record of one storage cannot refer to it'.

"Writes this atom's record, whose references are all saved in aStorage, and
 records its place; answers the atom's pointer in aStorage. When another save
 of this atom installed its place first (a compare-and-swap lost), the winner's
 place decides, whatever the interleaving: in aStorage, its pointer is the
 answer, as ProtoBase's _save answers the pointer the first save published
 (the record just pushed is an orphan nothing refers to, in an append-only
 segment); in another storage, PBValidationError, the error a sequential
 second save meets (_pointerIn:)."
PBAtom >> _pushInto: aStorage
  | ptr |
  ptr := aStorage pushAtom: (PBAtomEnvelope tag: self tag oid: self oid state: self state).
  (saved value: (_PBPlace pointer: ptr storage: aStorage) ifCurrent: nil) ifTrue: [^ ptr].
  ^ self _pointerIn: aStorage.

"Adds to anOrderedCollection the atoms the receiver refers to that are not
 saved in aStorage, in encoder order (a value holds none; the containers and
 the atoms below answer theirs). A reference read without a resolver
 (PBUnresolvedRef) is a pointer already."
Object >> _pbAddUnsavedAtomsTo: anOrderedCollection in: aStorage
  ^ self.

PBAtom >> _pbAddUnsavedAtomsTo: anOrderedCollection in: aStorage
  (self _pointerIn: aStorage) isNil ifTrue: [anOrderedCollection addLast: self].

_PBSequence >> _pbAddUnsavedAtomsTo: anOrderedCollection in: aStorage
  1 to: self size do: [:i | (self at: i) _pbAddUnsavedAtomsTo: anOrderedCollection in: aStorage].

PBFrozenDict >> _pbAddUnsavedAtomsTo: anOrderedCollection in: aStorage
  | ks |
  ks := self keys.
  1 to: ks size do: [:i |
    (ks at: i) _pbAddUnsavedAtomsTo: anOrderedCollection in: aStorage.
    (self _valueAt: i) _pbAddUnsavedAtomsTo: anOrderedCollection in: aStorage].

"The decoded twin of this saved atom (ProtoBase Atom._decoded_twin): the atom a
 load of its record would produce, built from its state without reading the
 storage. A new object of this class, a stub of the same pointer and storage
 holding the same oid, loaded with the state as its record decodes (each
 reference a stub of the storage, each value canonical). It is = to this atom
 (one oid) and leaves it untouched. An atom that is not saved has no twin
 (PBUserError)."
PBAtom >> _decodedTwin
  | ptr st envelope |
  ptr := self pointer.
  ptr isNil ifTrue: [^ PBUserError signal: self printString , ' is not saved: only a saved atom has a decoded twin'].
  st := self _storage.
  envelope := PBAtomEnvelope
    decode: (PBAtomEnvelope tag: self tag oid: self oid state: self state) encode
    expecting: self tag
    resolver: (_PBLoadResolver storage: st chain: { ptr }).
  ^ (self class basicNew _setOid: envelope oid pointer: ptr storage: st) _installState: envelope.

"=== PBOpaqueAtom ==========================================================="

"An atom of a type this process has no class for (D59): a record another
 implementation wrote. It keeps the name it was referenced by (its tag in
 references), its pointer and its decoded fields; anything that needs the
 type's behaviour, a field it does not hold included, is PBNotSupportedError
 naming the type. It is never registered and never written."
PBAtom subclass: #PBOpaqueAtom instanceVariableNames: 'referencedName'.

PBOpaqueAtom class >> unloadedAt: aPointer storage: aStorage
  ^ PBNotSupportedError signal: 'PBOpaqueAtom: an opaque atom needs the type name it is referenced by (named:unloadedAt:storage:)'.

PBOpaqueAtom class >> named: aTypeName unloadedAt: aPointer storage: aStorage
  | name stub |
  name := PBTypeRegistry checkOpaqueName: aTypeName.
  (aPointer isKindOf: PBAtomPointer) ifFalse: [
    ^ PBValidationError signal: 'PBOpaqueAtom: a PBAtomPointer was expected, not ' , aPointer printString].
  aStorage isNil ifTrue: [^ PBValidationError signal: 'PBOpaqueAtom: a storage is needed'].
  stub := self basicNew _setOid: nil pointer: aPointer storage: aStorage.
  ^ stub _setReferencedName: name.

PBOpaqueAtom >> _setReferencedName: aString
  "Runs once, on a fresh instance."
  referencedName isNil ifFalse: [^ PBUserError signal: 'PBOpaqueAtom is initialised once'].
  referencedName := aString.
  ^ self.

"The type name this atom was referenced by: what a writer puts in a @ref to it."
PBOpaqueAtom >> tag
  ^ referencedName.

"The atom's type name (design spec 8.1): the name it was referenced by, the
 only name of its type this process knows."
PBOpaqueAtom >> typeName
  ^ referencedName.

PBOpaqueAtom >> unloadedCopy
  ^ PBOpaqueAtom named: referencedName unloadedAt: pointer storage: storage.

PBOpaqueAtom >> _absentField: aName
  ^ PBNotSupportedError signal: aName printString , ' is not a field of this ' , referencedName
    , ' atom, and that type has no class registered in this process: its behaviour is not available here'.

"The value of the field aName; a field the record does not hold is
 PBNotSupportedError naming the type (D59)."
PBOpaqueAtom >> at: aName
  ^ self stateAt: aName.

"The names of the fields the record holds, sorted."
PBOpaqueAtom >> attributeNames
  ^ _PBNames sorted: self state keys.

"Any message an opaque atom does not implement needs the type's behaviour:
 PBNotSupportedError naming the type and the message (a collection message,
 a change such as with:value: or setAt:value:, a record message such as
 hasDefinedAttr:)."
PBOpaqueAtom >> doesNotUnderstand: aMessage
  ^ PBNotSupportedError signal: 'this ' , referencedName , ' atom does not understand '
    , aMessage selector printString , ': the type has no class registered in this process, so its behaviour is not available here'.

PBOpaqueAtom >> printOn: aStream
  aStream nextPutAll: 'PBOpaqueAtom('; nextPutAll: referencedName; nextPutAll: ', '; print: pointer; nextPut: $).

"An opaque atom is never written (D59): it is always a stub, so a save only
 refers to it. Its decoded twin would need its type's behaviour."
PBOpaqueAtom >> _decodedTwin
  ^ PBNotSupportedError signal: 'this ' , referencedName
    , ' atom has no class registered in this process: protoBaseST never writes it, so it has no decoded twin'.

PBTypeRegistry _initializeRegistry.

"Attribute names sorted by code point (the order key of a str)."
Object subclass: #_PBNames.

_PBNames class >> sorted: aCollection
  ^ (Array withAll: aCollection) sorted: [:a :b | (PBKeys compare: a with: b) <= 0].

"=== PBUnresolvedRef equality ==============================================="

"Two references are equal when they hold the same pointer and name the same
 type once aliases are mapped (PBTypeRegistry isTag:sameTypeAs:): equality does
 not depend on the spelling read. Defined here, not in values.st, because the
 alias table is the registry's; hash is the pointer's (values.st)."
PBUnresolvedRef >> = anObject
  ^ (anObject isClassObject not and: [anObject class == PBUnresolvedRef])
    and: [self pointer = anObject pointer and: [PBTypeRegistry isTag: self tag sameTypeAs: anObject tag]].
