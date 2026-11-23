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
  PBTypeRegistry builtinNames         the normative table of the 24 built-in aliases

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
      'proto_db.avl.CountedKeyNode'
      'proto_db.registry.ModuleList' 'proto_db.registry.Catalog').

"22 and 23 are the runtime registry's types (format 5, feature registry, proto_db 2.0.0rc4):
 named here, as the table is append-only, with no class, so a record of either is
 PBNotSupportedError (docs/deviations.md, 'Reading')."
PBTypeRegistry class >> builtinCount
  ^ 24.

"The aliases of the runtime registry's types (proto_db REGISTRY_TYPES): a record of either is
 format 5, never written here."
PBTypeRegistry class >> registryAliases
  ^ #(22 23).

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
 must be in the built-in table and not one of the runtime registry's types (22, 23:
 format 5, which protoBaseST does not write); an alias is any non-empty String that is not a
 built-in name (see the module comment). A name or an
 alias already registered by another class is PBValidationError. Registering
 the same class again is a no-op. The class's record shape is built here: a
 class whose declarations cannot hold (_PBRecordShape build:) is PBUserError.
 Answers aClass."
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
  "The record shape is built and published now: a class whose declarations its
   literal accessors cannot hold (_PBRecordShape build:) is refused here."
  aClass _recordShape.
  [ | old new additions |
    old := self _table.
    additions := OrderedCollection new.
    ({ name } , aliases) do: [:key |
      | entry |
      entry := old at: key ifAbsent: [nil].
      entry isNil
        ifTrue: [additions add: key -> (PBTuple _trustedOn: { aClass. name })]
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
  (self registryAliases includes: (self aliasOf: aName)) ifTrue: [
    ^ PBValidationError signal: 'PBTypeRegistry: ' , aName , ' is a format-5 type of the runtime registry; protoBaseST writes format 4'].

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

"The record shape (_PBRecordShape) of the class registered for the type aTag
 names, or nil when no class is registered for it (an opaque type). For a
 decoder: aTag is valid (PBAtomEnvelope _checkTag:expecting: ran)."
PBTypeRegistry class >> recordShapeForTag: aTag
  | entry |
  entry := self _entryFor: (self nameOfTag: aTag).
  entry isNil ifTrue: [^ nil].
  ^ (entry at: 1) _recordShape.

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

"The abstract base of every persistent object. An atom holds oid (nil, or its
 16-byte oid), its pointer and storage (a stub's, set when it is made; nil for
 an atom made in memory), saved (nil, or the _PBPlace the save of an atom made
 in memory recorded), slots (nil, or the values of its record in the slot
 order of its class's record shape, which its accessors read at literal
 positions) and memo (nil until its state is known, then what the state is
 read through). These are the runtime-only fields a constructor, a load, a
 first need or the save fills (spec 4.1, decision 3 as amended 2026-11-19), as
 ProtoBase sets oid and atom_pointer with object.__setattr__; never persisted,
 compared or hashed.

 The memo is one of two things (plan Task 12, atom weight stage 2):
  - the class's record shape (_PBRecordShape), shared by every atom of the
    class, when the state holds exactly the shape's persisted fields in that
    order and the shape's slots are its state (_PBRecordShape keepsState:):
    the atom keeps its slots and its oid, and nothing else. Its state is a
    PBFrozenDict on the shape's keys over the slots, derived on demand
    (state), equal to the state it was built or decoded from;
  - otherwise the envelope (PBAtomEnvelope: tag, oid, the state PBFrozenDict
    and the slots), as a load or a constructor made it: a record of a class
    with no persisted fields (PBObject), a record whose names differ from its
    class's shape, a write that leaves a field of its class absent, an opaque
    atom.
 A constructor writes the fields it knows on the fresh instance, in one write
 group, and never writes nil (an unset instance variable reads as nil). Every
 later fill writes a field once, by a compare-and-swap from nil on the
 instance variable itself (_publishOid:, _publishSaved:, _publishMemo:, and
 _slots), so two threads that race install one value and both answer it. A
 load publishes the memo last for a shaped record (its oid and slots first)
 and first for an envelope (its slots then, from the installed envelope), so
 a reader that sees the memo sees the fields it is read with, and every
 reader sees nil or one immutable slots Array.

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
Object subclass: #PBAtom instanceVariableNames: 'oid pointer storage saved memo slots'.

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

"Answers self when this class may have records; signals PBUserError (a class
 declaration error) otherwise. Checked when its record shape is built, so when
 it is registered (PBPosNode refuses its subclasses)."
PBAtom class >> _checkRecordClass
  ^ self.

"The persisted fields whose value must be an Integer (not a Boolean), checked
 once per record when it is loaded or built from a caller's state:
 PBCorruptionError otherwise. A field that is not required may be absent (nil:
 an older record)."
PBAtom class >> integerFields
  ^ #().

"The slot order the class's literal accessors read (see _PBRecordShape), or
 nil when it declares none. A class that declares one names its own class, not
 self, so its subclasses inherit the layout their inherited accessors read
 whatever their persistedFields; a subclass that declares its own must start
 with it."
PBAtom class >> slotFields
  ^ nil.

"The shape of this class's records (_PBRecordShape)."
PBAtom class >> _recordShape
  ^ _PBRecordShape for: self.

"The memo an atom of this class keeps for aState, whose slots (aShape
 slotsOf:) are aSlotArray: aShape, the class's record shape, when the atom
 keeps its state as its slots (_PBRecordShape keepsState:), else the in-memory
 envelope of aState (tag aTag, no oid) with the slots."
PBAtom class >> _memoOfState: aPBFrozenDict slots: aSlotArray tag: aTag shape: aShape
  (aShape keepsState: aPBFrozenDict) ifTrue: [^ aShape].
  ^ PBAtomEnvelope basicNew _setTag: aTag oid: nil state: aPBFrozenDict slots: aSlotArray.

"The memo a new atom of this class keeps when a writer gives anArray, the
 values of the first anArray size fields of aShape, the class's record shape
 (_unsavedWithSlots:), whose slots are aPaddedArray (aShape slotsPadded:
 anArray): aShape when anArray holds every field (_PBRecordShape keepsSlots:),
 else the in-memory envelope of the state they make (_PBRecordShape
 stateOfSlots:)."
PBAtom class >> _memoOfSlots: anArray padded: aPaddedArray shape: aShape
  (aShape keepsSlots: anArray) ifTrue: [^ aShape].
  ^ PBAtomEnvelope basicNew _setTag: nil oid: nil state: (aShape stateOfSlots: anArray) slots: aPaddedArray.

"Checks anEnvelope, the record at aPointer as a storage decoded it (or as the
 atom cache rebuilt it), against this class (its required fields, the reserved
 names, its integer fields) and fills anAtom, a stub of that record or its
 decoded twin, with what it keeps (see the class comment); answers anAtom's
 memo, the one installed. The required fields are not searched for when the
 shape proves them present (_PBRecordShape holdsRequiredFields:)."
PBAtom class >> _load: anEnvelope at: aPointer into: anAtom
  | shape state missing recordSlots |
  shape := self _recordShape.
  state := anEnvelope state.
  (shape holdsRequiredFields: state) ifFalse: [
    missing := self requiredFields reject: [:field | state includesKey: field].
    missing isEmpty ifFalse: [
      ^ PBCorruptionError signal: 'the atom at ' , aPointer printString , ' (' , (PBTypeRegistry nameOfTag: anAtom tag)
        , ') lacks the required fields ' , missing printString]].
  self _checkPersistedNames: state at: aPointer.
  recordSlots := shape check: (shape slotsOf: state) of: anAtom.
  (shape keepsState: state) ifTrue: [^ anAtom _publishOid: anEnvelope oid slots: recordSlots memo: shape].
  ^ anAtom _publishEnvelope: (PBAtomEnvelope basicNew _setTag: anEnvelope tag oid: anEnvelope oid state: state
    slots: recordSlots).

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
 kept in the in-memory envelope only, when the atom keeps one; the save writes
 PBAtom >> tag, read from the class."
PBAtom class >> _unsavedWithState: aPBFrozenDict tag: aTag
  ^ self _unsaved: self basicNew withState: aPBFrozenDict tag: aTag.

"aBlank (a fresh basicNew instance of this class, which a subclass may have
 given its own runtime-only fields first) made an unsaved atom holding
 aPBFrozenDict, its integer fields checked. The attribute names must be valid
 (PBAtomEnvelope _nameProblem:): the save does not check them again
 (PBAtomEnvelope _ofAtomTag:oid:state:); the public constructors guarantee
 it. The values may come from a decoded record (PBObject >> withAll: copies
 the fields it does not change, a tree rebuild copies stored values), so they
 are not trusted to be writable: the save checks each as a writer must
 (PBAtomEnvelope >> encode)."
PBAtom class >> _unsaved: aBlank withState: aPBFrozenDict tag: aTag
  | atom shape recordSlots |
  atom := aBlank _setOid: nil pointer: nil storage: nil.
  shape := self _recordShape.
  recordSlots := shape check: (shape slotsOf: aPBFrozenDict) of: atom.
  ^ atom _installSlots: recordSlots
    memo: (self _memoOfState: aPBFrozenDict slots: recordSlots tag: aTag shape: shape).

PBAtom >> _installSlots: anArray memo: aMemo
  "Runs once, on a fresh instance that is not shared yet: an unsaved atom. Its
   slots and its memo (the record shape, or an envelope) are written in one
   write group."
  memo isNil ifFalse: [^ PBUserError signal: 'PBAtom: the state is installed once'].
  memo := aMemo.
  slots := anArray.
  ^ self.

"A new, unsaved atom of this class whose slots are anArray, the values of the
 first anArray size fields of its shape (_PBRecordShape stateOfSlots:): the
 constructor of the AVL writes, whose values are their own computations
 (heights, counts, weights), so the integer fields are not checked again.
 anArray is kept as the slots: never to be changed."
PBAtom class >> _unsavedWithSlots: anArray
  | shape padded |
  shape := self _recordShape.
  padded := shape slotsPadded: anArray.
  ^ (self basicNew _setOid: nil pointer: nil storage: nil)
    _installSlots: padded memo: (self _memoOfSlots: anArray padded: padded shape: shape).

"An unloaded atom (a stub) of this class: its record is at aPointer in
 aStorage and is loaded on first use."
PBAtom class >> unloadedAt: aPointer storage: aStorage
  (aPointer isKindOf: PBAtomPointer) ifFalse: [
    ^ PBValidationError signal: self name , ' unloadedAt: a PBAtomPointer was expected, not ' , aPointer printString].
  aStorage isNil ifTrue: [
    ^ PBValidationError signal: self name , ' unloadedAt:storage: needs a storage'].
  ^ self basicNew _setOid: nil pointer: aPointer storage: aStorage.

PBAtom >> _setOid: anOid pointer: aPointer storage: aStorage
  "Runs once, on a fresh instance: every constructor of an atom calls it. A stub
   (aPointer and aStorage given, and anOid when the caller knows it: a decoded
   twin) gets them in one write group; an atom made in memory gets anOid when
   one is given, and nothing else. No field is written nil: an unset instance
   variable reads as nil. A second call is refused once any of these fields or the
   state is set, so an oid drawn or given is never replaced."
  (memo isNil and: [pointer isNil and: [oid isNil]]) ifFalse: [^ PBUserError signal: 'PBAtom is initialised once'].
  aPointer isNil ifTrue: [
    anOid isNil ifFalse: [oid := anOid].
    ^ self].
  anOid isNil ifTrue: [
    pointer := aPointer.
    storage := aStorage.
    ^ self].
  oid := anOid.
  pointer := aPointer.
  storage := aStorage.
  ^ self.

"The write-once publishers of the runtime-only fields (spec 4.1, decision 3):
 each installs its argument unless the field holds a value already, by a
 compare-and-swap from nil on the instance variable, and answers the value the
 field then holds: the argument, or the value an earlier or a racing
 publication installed (the loser of a race answers the winner's)."
PBAtom >> _publishOid: anOid
  self setInstVar: #oid from: nil to: anOid.
  ^ oid.

PBAtom >> _publishSaved: aPBPlace
  self setInstVar: #saved from: nil to: aPBPlace.
  ^ saved.

PBAtom >> _publishMemo: aMemo
  self setInstVar: #memo from: nil to: aMemo.
  ^ memo.

"The load of a record the atom keeps as its slots (PBAtom class >>
 _load:at:into:): its oid, then its slots, then aShape, the memo, each by a
 compare-and-swap from nil, so a reader that sees the memo sees the oid and
 the slots. Racing loads of one record publish equal oids and slots: each
 field keeps the first, and every racer answers the installed memo."
PBAtom >> _publishOid: anOid slots: anArray memo: aShape
  self _publishOid: anOid.
  self setInstVar: #slots from: nil to: anArray.
  ^ self _publishMemo: aShape.

"The load of a record the atom keeps as an envelope (PBAtom class >>
 _load:at:into:): anEnvelope, then the slots of the envelope installed (the
 first racer's), each by a compare-and-swap from nil; answers the installed
 envelope."
PBAtom >> _publishEnvelope: anEnvelope
  | installed |
  installed := self _publishMemo: anEnvelope.
  self setInstVar: #slots from: nil to: installed slots.
  ^ installed.

"A reference to an atom, for PBCodec."
PBAtom >> isPBReference
  ^ true.

"The atom's PBAtomPointer: a stub's, or the one its save recorded; nil while
 it is not saved."
PBAtom >> pointer
  pointer isNil ifFalse: [^ pointer].
  saved isNil ifTrue: [^ nil].
  ^ saved pointer.

"The storage the atom is stored in (nil while it is not saved)."
PBAtom >> _storage
  storage isNil ifFalse: [^ storage].
  saved isNil ifTrue: [^ nil].
  ^ saved storage.

"Whether the atom has a record (a stub, or an atom whose save is done)."
PBAtom >> isSaved
  ^ self pointer notNil.

"The oid when this atom holds it already (nil otherwise), without loading or
 drawing one: a stub learns its oid from its record, an atom that is not stored
 draws it on first need (oid)."
PBAtom >> knownOid
  ^ oid.

"The tag a writer puts for this atom's type (PBTypeRegistry tagFor:)."
PBAtom >> tag
  ^ PBTypeRegistry tagFor: self class.

PBAtom >> isLoaded
  ^ memo notNil.

"A new, unloaded stub of this stored atom: what a holder answers when it must
 not keep the record loaded (DatabaseRoot previous, D53). An atom with no
 stored record answers itself."
PBAtom >> unloadedCopy
  | ptr |
  ptr := self pointer.
  ptr isNil ifTrue: [^ self].
  ^ self class unloadedAt: ptr storage: self _storage.

"The memo (the record shape, or the envelope), loading the record once through
 the storage."
PBAtom >> _loaded
  memo isNil ifFalse: [^ memo].
  ^ self _loadedWithin: #().

"The memo, the record loaded within aChain: an Array of the pointers whose
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
PBAtom >> _loadedWithin: aChain
  memo isNil ifFalse: [^ memo].
  (storage isNil or: [pointer isNil]) ifTrue: [
    ^ PBUserError signal: self class name , ': an atom with no stored record has no state to load'].
  (aChain includes: pointer) ifTrue: [
    ^ PBCorruptionError signal: 'the record at ' , pointer printString , ' (' , (PBTypeRegistry nameOfTag: self tag)
      , ') cannot be loaded: decoding its state needs the record itself (a map key refers back to it: damaged data, or a writer that broke the save-dependents-first invariant)'].
  ^ storage _pbLoad: pointer into: self within: (aChain copyWith: pointer).

"The slots Array (_PBRecordShape), loading the record on first use. A load
 publishes it; while the memo is an envelope whose slots are not published yet
 (a racing load is between its two compare-and-swaps), they are published
 here from the installed envelope, so a reader of the field sees nil or this
 one Array. The literal accessors read the field and come here only while it
 is nil."
PBAtom >> _slots
  | m |
  m := self _loaded.
  slots == nil ifTrue: [self setInstVar: #slots from: nil to: m slots].
  ^ slots.

"The slot anIndex (_PBRecordShape): what a literal accessor reads. The
 built-in node classes read the slots field directly. An application
 subclass reads through here: protoST resolves an instance variable when it
 compiles a method, from the classes compiled before it, and a program's main
 file is compiled before the modules it imports are loaded, so its methods do
 not see PBAtom's fields."
PBAtom >> _slotAt: anIndex
  slots == nil ifTrue: [^ self _slots at: anIndex].
  ^ slots at: anIndex.

"The persisted state, a PBFrozenDict of attribute name to value, in the
 record's order (loaded on first use): the envelope's, or, for an atom that
 keeps its slots, a PBFrozenDict on its shape's keys over them, made on
 demand (= to the state the atom was built or decoded from; never ==)."
PBAtom >> state
  | m |
  m := memo.
  m isNil ifTrue: [m := self _loaded].
  ^ m _pbStateOver: slots.

"The value of the persisted attribute aName; an attribute the record does not
 hold reads as nil (an application type's later field, format spec 'Required
 fields')."
PBAtom >> stateAt: aName
  "Every field read of every atom runs here: the memo is read from its field
   directly (the slots are set once it is), the lookup creates no block and,
   for an atom that keeps its slots, no state."
  | m i |
  m := memo.
  m isNil ifTrue: [m := self _loaded].
  i := m _pbIndexOfField: aName.
  i = 0 ifTrue: [^ self _absentField: aName].
  ^ m _pbFieldAt: i over: slots.

PBAtom >> _absentField: aName
  ^ nil.

"As state at: aName ifAbsent: aBlock, without making the state of an atom
 that keeps its slots (plan Task 12): the per-row field read of a key path
 (PBKeySpec >> _step:name:recordName:)."
PBAtom >> _stateAt: aName ifAbsent: aBlock
  | m i |
  m := memo.
  m isNil ifTrue: [m := self _loaded].
  i := m _pbIndexOfField: aName.
  i = 0 ifTrue: [^ aBlock value].
  ^ m _pbFieldAt: i over: slots.

"The atom's oid (16 bytes): the record's for a stored atom (a stub loads it);
 for an atom that is not stored, the one drawn on first need (ProtoBase D21)."
PBAtom >> oid
  | m |
  oid isNil ifFalse: [^ oid].
  pointer isNil ifTrue: [^ self _publishOid: self _newOid].
  m := self _loaded.
  "A record the atom keeps as its slots published its oid before the memo."
  oid isNil ifFalse: [^ oid].
  ^ m oid.

"A fresh oid: the 16 bytes of a version-4 UUID (ProtoBase uuid.uuid4()), from
 _PBOidPool. The seam a test overrides to drive two first readers in a chosen
 order."
PBAtom >> _newOid
  ^ _PBOidPool next.

"=== _PBOidPool ================================================================

The source of fresh oids: the 16 bytes of version-4 UUIDs, as UUID new makes
them (RFC 4122 section 4.4: ByteArray randomBytes:, the operating system's
secure generator, with the version nibble set to 4 and the variant bits to
2r10), drawn batchSize at a time, so a commit that writes a dozen atoms makes
one call to the generator instead of a dozen. Every oid is 16 bytes of the
generator's output, of which the same 6 bits are fixed as in UUID new, so the
distribution is UUID new's.

The pool is an Atom holding the unused rest of the current batch: a ByteArray
of whole oids (a multiple of 16 bytes, already marked). A draw takes the first
16 bytes by compare-and-swap of the rest after them; the compare is by
identity and every rest is a new object, so each slice is handed out once,
whatever the threads. A batch that is used up (an empty rest) is replaced by a
fresh one, by compare-and-swap too (a batch drawn by a loser of that race is
dropped, never handed out). No lock, and nothing depends on timing.

A draw allocates the two slices and the publication (plan Task 12). A batch is
marked by concatenating slices of the generator's bytes with the marked bytes
from a table of the 256 one-byte ByteArrays (ByteArrays are immutable, and
setting the two bytes of each oid through an Array of the batch's bytes cost
about 276 cells per oid drawn)."
Object subclass: #_PBOidPool classVariableNames: 'Pool Bytes'.

_PBOidPool class >> batchSize
  ^ 64.

"The 16 bytes of a fresh version-4 UUID."
_PBOidPool class >> next
  [| current |
   current := Pool value.
   current size < 16
     ifTrue: [Pool value: self _batch ifCurrent: current]
     ifFalse: [
       (Pool value: (current copyFrom: 17 to: current size) ifCurrent: current) ifTrue: [
         ^ current copyFrom: 1 to: 16]]]
    repeat.

"batchSize oids: random bytes, marked (_mark:)."
_PBOidPool class >> _batch
  ^ self _mark: (ByteArray randomBytes: self batchSize * 16).

"aByteArray, oids of 16 bytes back to back, with the version and variant bits
 of each set as UUID new sets them: byte 7's high nibble is 4 (version 4) and
 byte 9's two high bits are 2r10 (the variant); every other bit is kept."
_PBOidPool class >> _mark: aByteArray
  | out |
  out := ByteArray new.
  0 to: aByteArray size // 16 - 1 do: [:k |
    | at |
    at := k * 16.
    out := out , (aByteArray copyFrom: at + 1 to: at + 6)
      , (Bytes at: (((aByteArray at: at + 7) bitAnd: 16r0F) bitOr: 16r40) + 1)
      , (aByteArray copyFrom: at + 8 to: at + 8)
      , (Bytes at: (((aByteArray at: at + 9) bitAnd: 16r3F) bitOr: 16r80) + 1)
      , (aByteArray copyFrom: at + 10 to: at + 16)].
  ^ out.

_PBOidPool class >> _initializePool
  Bytes := (0 to: 255) asArray collect: [:b | ByteArray withAll: { b }].
  Pool := Atom on: ByteArray new.

_PBOidPool _initializePool.

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
 storage.push_atom). PBFileStorage answers it by appending to the segment it
 owns (store.st); saves run on the space's round runner (round.st), through
 its publisher (publisher.st), one round at a time."

"A saved atom's place: its pointer and the storage it was written to (an
 immutable pair, what the saved field of an atom holds)."
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
  "Frames { atom. nil } before the atom is visited, { atom. its state. its
   unsaved references } once it is: the state is built once per atom saved and
   serves the walk, the record and the atom cache (plan Task 10)."
  stack := OrderedCollection new.
  stack addLast: self; addLast: nil.
  [stack notEmpty] whileTrue: [
    | refs atom st |
    refs := stack removeLast.
    refs isNil
      ifTrue: [
        atom := stack last.
        (atom _pointerIn: aStorage) isNil
          ifTrue: [
            "The class is checked before any dependent is written or bound to
             aStorage, as ProtoBase's _save checks the declared type name before
             it encodes the state."
            atom tag.
            st := atom state.
            refs := OrderedCollection new.
            st _pbAddUnsavedAtomsTo: refs in: aStorage.
            stack addLast: st; addLast: refs.
            refs size to: 1 by: -1 do: [:i | stack addLast: (refs at: i); addLast: nil]]
          ifFalse: [stack removeLast]]
      ifFalse: [
        st := stack removeLast.
        atom := stack removeLast.
        "A dependent met twice is saved once: the second visit finds it saved."
        (atom _pointerIn: aStorage) isNil ifTrue: [atom _push: st into: aStorage]]].
  ^ self pointer.

"The pointer of this atom in aStorage, or nil while it is not saved; an atom
 stored in another storage is PBValidationError."
PBAtom >> _pointerIn: aStorage
  | place |
  pointer isNil ifFalse: [
    storage == aStorage ifTrue: [^ pointer].
    ^ self _storedElsewhere: aStorage].
  place := saved.
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
PBAtom >> _push: aState into: aStorage
  | ptr place |
  ptr := aStorage pushAtom: (PBAtomEnvelope _ofAtomTag: self tag oid: self oid state: aState).
  place := _PBPlace pointer: ptr storage: aStorage.
  (self _publishSaved: place) == place ifTrue: [
    aStorage _pbSaved: self state: aState at: ptr.
    ^ ptr].
  ^ self _pointerIn: aStorage.

"=== loading through a storage, and the stored form of a saved state =========="

"Loads the record at aPointer into anAtom, a stub of this storage (PBAtom >>
 _loadedWithin:): the record decoded, expecting anAtom's tag, within aChain,
 then checked against anAtom's class, which fills anAtom (PBAtom class >>
 _load:at:into:); answers anAtom's memo. A storage may rebuild the record from
 what it holds already (PBFileStorage's atom cache)."
Object >> _pbLoad: aPointer into: anAtom within: aChain
  ^ anAtom class _load: (self loadAt: aPointer expecting: anAtom tag within: aChain) at: aPointer into: anAtom.

"Told by a save that anAtom's record, of the state aState, is now at aPointer
 in this storage (a storage may keep what a decode of it would give)."
Object >> _pbSaved: anAtom state: aState at: aPointer
  ^ self.

"aState, this atom's state as its save just wrote it, in the form a decode of
 that record would hold before its references are resolved: the same values
 (an atom stays itself; the storage that caches it makes the one new stub of
 each, PBFileStorage >> _pbOwnValues:), and, as a decode does, on the class's
 shared keys and index when it is in the persisted order of its class. nil when
 a container value holds a reference, or a value is a reference read without a
 resolver: those are left to a decode."
PBAtom >> _pbCacheableState: aState
  | shape values |
  aState _pbHoldsNestedReference ifTrue: [^ nil].
  shape := self class _recordShape.
  values := aState _valuesIfKeys: shape persisted.
  values isNil ifTrue: [^ aState].
  ^ PBFrozenDict _keys: shape persisted index: shape persistedIndex values: values.

"0: the value holds no reference; 1: it is an atom; 2: it is a reference read
 without a resolver, or a container holding a reference."
Object >> _pbReferenceKind
  ^ 0.

PBAtom >> _pbReferenceKind
  ^ 1.

PBUnresolvedRef >> _pbReferenceKind
  ^ 2.

_PBSequence >> _pbReferenceKind
  1 to: self size do: [:i | (self at: i) _pbReferenceKind = 0 ifFalse: [^ 2]].
  ^ 0.

"Whether a value of this state is a container holding a reference, or a
 reference read without a resolver (_pbReferenceKind 2)."
PBFrozenDict >> _pbHoldsNestedReference
  1 to: self size do: [:i | (self _valueAt: i) _pbReferenceKind = 2 ifTrue: [^ true]].
  ^ false.

PBFrozenDict >> _pbReferenceKind
  | ks |
  ks := self keys.
  1 to: ks size do: [:i |
    ((ks at: i) _pbReferenceKind = 0 and: [(self _valueAt: i) _pbReferenceKind = 0]) ifFalse: [^ 2]].
  ^ 0.

"A new stub of this saved atom in aStorage: what a decode of a reference to it
 answers (PBTypeRegistry unloadedAtomFor:at:storage:, of the class its tag
 names, which is this atom's class)."
PBAtom >> _pbStubIn: aStorage
  ^ self class unloadedAt: (self _pointerIn: aStorage) storage: aStorage.

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
  | ptr st envelope twin |
  ptr := self pointer.
  ptr isNil ifTrue: [^ PBUserError signal: self printString , ' is not saved: only a saved atom has a decoded twin'].
  st := self _storage.
  envelope := PBAtomEnvelope
    decode: (PBAtomEnvelope tag: self tag oid: self oid state: self state) encode
    expecting: self tag
    resolver: (_PBLoadResolver storage: st chain: { ptr }).
  twin := self class basicNew _setOid: envelope oid pointer: ptr storage: st.
  self class _load: envelope at: ptr into: twin.
  ^ twin.

"=== record shapes (plan Task 16b) ==========================================="

"The shape of the records of a class (every atom class has one, built from its
 declarations the first time it is needed and published once):

  persisted       its persistedFields (one Array, the keys of every state built
                  from slots and of every loaded record in that order, which
                  share it with persistedIndex: no index per record)
  fields          the slot order: the class's slotFields (the order its literal
                  accessors read, inherited by its subclasses), then its other
                  persisted fields in their order; persisted itself when the
                  two orders agree (the built-in node classes)
  integerSlots    the slots of its integerFields that are required (nil is
                  corruption) and optionalIntegerSlots, those that are not (nil
                  is an older record, valid)
  slotsAreState   whether persisted is not empty and fields is persisted itself:
                  then a record holding exactly the persisted fields, in order,
                  is its slots under persisted (keepsState:), and an atom keeps
                  no state of its own (PBAtom, plan Task 12)
  namesValid      whether every persisted name may be a record's attribute name
                  (nameProblem:), so a decoder that finds a record's names equal
                  to persisted need not check each (PBAtomEnvelope decode:...)

 A record carries a slots Array, the values of fields in that order (nil for a
 field the state does not hold), which the accessors read at literal slot
 numbers (tests/unit/record_slots.st holds each literal to slotFields, for
 every registered class that declares one). The slots are derived from the
 immutable state once per record and are never persisted, compared or hashed:
 the state stays the record, in its own order. A shape is immutable."
Object subclass: #_PBRecordShape instanceVariableNames: 'persisted persistedIndex fields persistedSlots integerSlots optionalIntegerSlots requiredPersisted required slotsAreState namesValid'
  classVariableNames: 'Table'.

"Table: an Atom cell holding a Dictionary class -> shape, never changed once
 installed (a new shape installs a copy, by compare-and-swap)."
_PBRecordShape class >> _initializeTable
  Table := Atom on: Dictionary new.

"The shape of aClass: the published one, or one built now and published (two
 threads that race build equal shapes; both answer the installed one). A class
 whose declarations cannot hold is PBUserError (see build:)."
_PBRecordShape class >> for: aClass
  | shape |
  shape := Table value at: aClass ifAbsent: nil.
  shape isNil ifFalse: [^ shape].
  shape := self build: aClass.
  [ | old new |
    old := Table value.
    (old includesKey: aClass) ifTrue: [^ old at: aClass].
    new := old copy.
    new at: aClass put: shape.
    Table value: new ifCurrent: old ] whileFalse.
  ^ shape.

"A new shape of aClass. PBUserError (a class declaration error) when its
 persistedFields name a field twice (the decoder shares the shape's keys
 without checking a record's names again, review R2-M1), its
 integerFields are not slot fields, or its
 slotFields do not start with its superclass's (the literal accessors it
 inherits would read the wrong slots)."
_PBRecordShape class >> build: aClass
  | persisted slotFields inherited fields required ints optional |
  aClass _checkRecordClass.
  persisted := Array withAll: aClass persistedFields.
  persisted asSet size = persisted size ifFalse: [
    ^ PBUserError signal: aClass name , ': its persistedFields ' , persisted printString
      , ' name a field twice (a record holds each field once)'].
  slotFields := aClass slotFields.
  inherited := (aClass superclass respondsTo: #slotFields) ifTrue: [aClass superclass slotFields] ifFalse: [nil].
  (inherited notNil and: [slotFields isNil or: [slotFields size < inherited size
      or: [(slotFields copyFrom: 1 to: inherited size) ~= inherited]]]) ifTrue: [
    ^ PBUserError signal: aClass name , ': its slotFields ' , slotFields printString
      , ' must start with its superclass''s ' , inherited printString , ', which its inherited accessors read'].
  fields := (slotFields isNil or: [slotFields = persisted])
    ifTrue: [persisted]
    ifFalse: [(Array withAll: slotFields) , (persisted reject: [:f | slotFields includes: f])].
  required := aClass requiredFields.
  ints := OrderedCollection new.
  optional := OrderedCollection new.
  aClass integerFields do: [:f |
    (fields includes: f) ifFalse: [
      ^ PBUserError signal: aClass name , ': the integer field ' , f printString , ' is not a persisted field'].
    ((required includes: f) ifTrue: [ints] ifFalse: [optional]) addLast: (fields indexOf: f)].
  ^ self basicNew _setPersisted: persisted index: (PBMapKeyIndex on: persisted) fields: fields
    persistedSlots: (persisted collect: [:f | fields indexOf: f])
    integerSlots: ints asArray optional: optional asArray
    required: (Array withAll: required).

_PBRecordShape >> _setPersisted: anArray index: aPBMapKeyIndex fields: aFieldArray persistedSlots: aSlotArray integerSlots: anIntegerArray optional: anOptionalArray required: aRequiredArray
  "Runs once, on a fresh instance."
  persisted isNil ifFalse: [^ PBUserError signal: '_PBRecordShape is immutable'].
  persisted := anArray.
  persistedIndex := aPBMapKeyIndex.
  fields := aFieldArray.
  persistedSlots := aSlotArray.
  integerSlots := anIntegerArray.
  optionalIntegerSlots := anOptionalArray.
  required := aRequiredArray.
  requiredPersisted := aRequiredArray allSatisfy: [:f | anArray includes: f].
  slotsAreState := anArray notEmpty and: [aFieldArray == anArray].
  namesValid := anArray allSatisfy: [:f | (_PBRecordShape nameProblem: f) isNil].
  ^ self.

"Why aName cannot be a persisted attribute name, or nil (format spec 'Atom
 records'): a non-empty String, not starting with _, not oid, atom_pointer or
 context. The rule of every reader and writer (PBAtomEnvelope _nameProblem:),
 run once per key path step: the reserved names are compared one by one (a
 literal Array's includes: cost more than the rest of the rule together; plan
 Task 10)."
_PBRecordShape class >> nameProblem: aName
  ((aName isString and: [aName isSymbol not]) and: [aName notEmpty]) ifFalse: [
    ^ 'an attribute name is a non-empty string, not ' , aName printString].
  aName first = $_ ifTrue: [^ 'the attribute name ' , aName printString , ' starts with _'].
  (aName = 'oid' or: [aName = 'atom_pointer' or: [aName = 'context']]) ifTrue: [
    ^ 'the attribute name ' , aName printString , ' is reserved'].
  ^ nil.

"The persistedFields, shared by the states built on them (never to be changed)."
_PBRecordShape >> persisted
  ^ persisted.

"The PBMapKeyIndex over persisted (never to be changed)."
_PBRecordShape >> persistedIndex
  ^ persistedIndex.

"The slot order (never to be changed)."
_PBRecordShape >> fields
  ^ fields.

"Whether every persisted name may be an attribute name (see namesValid)."
_PBRecordShape >> persistedNamesValid
  ^ namesValid.

"Whether an atom whose state is aState keeps it as its slots (PBAtom, plan
 Task 12): the shape's slots are its state (slotsAreState) and aState holds
 exactly the persisted fields, in order, so its values are its slots (slotsOf:
 answers them) and a PBFrozenDict on persisted over the slots equals it."
_PBRecordShape >> keepsState: aState
  slotsAreState ifFalse: [^ false].
  ^ (aState _valuesIfKeys: persisted) notNil.

"Whether a new atom whose writer gives anArray, the values of the first
 anArray size fields (PBAtom class >> _unsavedWithSlots:), keeps them as its
 slots: the shape's slots are its state and anArray gives every field
 (stateOfSlots: would answer a PBFrozenDict on persisted over anArray)."
_PBRecordShape >> keepsSlots: anArray
  slotsAreState ifFalse: [^ false].
  ^ anArray size = fields size.

"The memo protocol of PBAtom (shared with PBAtomEnvelope): an atom whose memo
 is its shape keeps its state as aSlotArray, its slots. Its state, made on
 demand: the shared keys and index over the slots."
_PBRecordShape >> _pbStateOver: aSlotArray
  ^ PBFrozenDict _keys: persisted index: persistedIndex values: aSlotArray.

"The position of the field aName in such a state (the map-key rule, as
 PBFrozenDict >> _indexOfKey:), or 0."
_PBRecordShape >> _pbIndexOfField: aName
  ^ persistedIndex indexOf: aName.

"The value at the position anIndex (from _pbIndexOfField:) of such a state."
_PBRecordShape >> _pbFieldAt: anIndex over: aSlotArray
  ^ aSlotArray at: anIndex.

"Whether aState holds every required field because its keys are persisted, in
 order (the shared Array or an equal one), and the class's requiredFields are
 persisted fields (the built-in classes; a class may require a field it does
 not list)."
_PBRecordShape >> holdsRequiredFields: aState
  requiredPersisted ifFalse: [^ false].
  ^ (aState _valuesIfKeys: persisted) notNil.

"The slots of aState: its values Array itself when its keys are the fields in
 order, else its values in field order (nil for a field it does not hold)."
_PBRecordShape >> slotsOf: aState
  | slots |
  slots := aState _valuesIfKeys: fields.
  slots isNil ifFalse: [^ slots].
  ^ fields collect: [:f |
    | i |
    i := aState _indexOfKey: f.
    i = 0 ifTrue: [nil] ifFalse: [aState _valueAt: i]].

"The state of a new record whose slots are anArray, the values of the first
 anArray size fields (an AVL write fills the fields of its node class; a later
 field of a subclass is then absent, as in a record written before it existed;
 a required one is PBValidationError). The keys are persisted, in order: the
 shared Array when every field is given in persisted order (zero copies)."
_PBRecordShape >> stateOfSlots: anArray
  | keys values |
  fields == persisted ifTrue: [
    anArray size = fields size ifTrue: [^ PBFrozenDict _keys: persisted index: persistedIndex values: anArray]].
  anArray size > fields size ifTrue: [
    ^ PBValidationError signal: 'a record of ' , fields size printString , ' fields was given '
      , anArray size printString , ' values'].
  anArray size = fields size ifTrue: [
    ^ PBFrozenDict _keys: persisted index: persistedIndex
      values: (persistedSlots collect: [:i | anArray at: i])].
  required do: [:f |
    (fields indexOf: f) > anArray size ifTrue: [
      ^ PBValidationError signal: 'the required field ' , f printString , ' of this record is not given (a write of '
        , anArray size printString , ' of its ' , fields size printString , ' fields)']].
  keys := OrderedCollection new.
  values := OrderedCollection new.
  1 to: persisted size do: [:p |
    | i |
    i := persistedSlots at: p.
    i <= anArray size ifTrue: [keys addLast: (persisted at: p). values addLast: (anArray at: i)]].
  ^ PBFrozenDict withAssociations: ((1 to: keys size) asArray collect: [:k | (keys at: k) -> (values at: k)]).

"The state of a copy of the record aState whose first anArray size fields are
 given by anArray (an AVL write): every later field is carried from aState,
 present with its value when aState holds it, absent otherwise. The keys are
 persisted, in order: the shared Array when every field is present."
_PBRecordShape >> stateOfSlots: anArray carrying: aState
  | keys values |
  keys := OrderedCollection new.
  values := OrderedCollection new.
  1 to: persisted size do: [:p |
    | i f |
    i := persistedSlots at: p.
    f := persisted at: p.
    i <= anArray size
      ifTrue: [keys addLast: f. values addLast: (anArray at: i)]
      ifFalse: [(aState includesKey: f) ifTrue: [keys addLast: f. values addLast: (aState at: f)]]].
  keys size = persisted size ifTrue: [
    ^ PBFrozenDict _keys: persisted index: persistedIndex values: values asArray].
  ^ PBFrozenDict withAssociations: ((1 to: keys size) asArray collect: [:k | (keys at: k) -> (values at: k)]).

"The slots of a record of this shape, given by a writer that has fewer values
 than fields: padded with nil (the fields it does not know are absent)."
_PBRecordShape >> slotsPadded: anArray
  anArray size = fields size ifTrue: [^ anArray].
  ^ (1 to: fields size) asArray collect: [:i | i <= anArray size ifTrue: [anArray at: i] ifFalse: [nil]].

"Checks the integer fields of aSlotArray, a record of anAtom: a required one
 must be an Integer (not a Boolean), an optional one nil or an Integer;
 PBCorruptionError naming the field and anAtom otherwise. Answers aSlotArray."
_PBRecordShape >> check: aSlotArray of: anAtom
  1 to: integerSlots size do: [:k |
    | i |
    i := integerSlots at: k.
    _PBRecordShape integer: (aSlotArray at: i) field: (fields at: i) of: anAtom].
  1 to: optionalIntegerSlots size do: [:k |
    | i |
    i := optionalIntegerSlots at: k.
    (aSlotArray at: i) isNil ifFalse: [
      _PBRecordShape integer: (aSlotArray at: i) field: (fields at: i) of: anAtom]].
  ^ aSlotArray.

"anObject's value as an Integer field (not a Boolean); PBCorruptionError otherwise."
_PBRecordShape class >> integer: anObject field: aName of: anAtom
  "Nested ifTrue: (inlined by the compiler), not and: (a block)."
  anObject isInteger ifTrue: [
    anObject == true ifFalse: [anObject == false ifFalse: [^ anObject]]].
  ^ PBCorruptionError signal: 'the ' , aName , ' of ' , anAtom printString , ' is not an integer: '
    , (PBKeys _preview: anObject).

_PBRecordShape _initializeTable.

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
PBOpaqueAtom >> _pbStubIn: aStorage
  ^ PBOpaqueAtom named: referencedName unloadedAt: (self _pointerIn: aStorage) storage: aStorage.

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
