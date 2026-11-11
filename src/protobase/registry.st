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

"The abstract base of every persistent object. An atom holds its oid (nil
 until known), its pointer (nil until saved), its storage, and memo: an Atom
 cell holding nil or the loaded envelope (what storage loadAt:expecting:
 answers: tag, oid and the state PBFrozenDict). The memo is the one cell a
 load fills (plan, immutability by convention): two loads that race install
 the first envelope and both answer it."
Object subclass: #PBAtom instanceVariableNames: 'oid pointer storage memo'.

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

"An atom of this class that is not stored: no pointer, no storage, no oid,
 holding aPBFrozenDict as its state (a read-side value, such as the empty
 CountedSet a RepeatedKeysDictionary answers for an absent key). The public
 constructors of new atoms come with the writer (plan Task 15)."
PBAtom class >> _unsavedWithState: aPBFrozenDict
  (aPBFrozenDict isKindOf: PBFrozenDict) ifFalse: [
    ^ PBValidationError signal: self name , ': the state of an atom is a PBFrozenDict, not ' , aPBFrozenDict printString].
  ^ (self basicNew _setOid: nil pointer: nil storage: nil)
    _installState: (PBAtomEnvelope basicNew _setTag: (PBTypeRegistry tagFor: self) oid: nil state: aPBFrozenDict).

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
  "Runs once, on a fresh instance."
  memo isNil ifFalse: [^ PBUserError signal: 'PBAtom is initialised once'].
  oid := anOid.
  pointer := aPointer.
  storage := aStorage.
  memo := Atom on: nil.
  ^ self.

"A reference to an atom, for PBCodec."
PBAtom >> isPBReference
  ^ true.

PBAtom >> pointer
  ^ pointer.

"The oid when this atom holds it already (nil otherwise), without loading:
 a stub learns its oid from its record (oid loads it)."
PBAtom >> knownOid
  ^ oid.

"The tag a writer puts for this atom's type (PBTypeRegistry tagFor:)."
PBAtom >> tag
  ^ PBTypeRegistry tagFor: self class.

PBAtom >> isLoaded
  ^ memo value notNil.

"A new, unloaded stub of this stored atom: what a holder answers when it must
 not keep the record loaded (DatabaseRoot previous, D53). An atom with no
 stored record answers itself."
PBAtom >> unloadedCopy
  pointer isNil ifTrue: [^ self].
  ^ self class unloadedAt: pointer storage: storage.

"The loaded envelope, loading it once through the storage."
PBAtom >> _envelope
  | envelope missing |
  envelope := memo value.
  envelope isNil ifFalse: [^ envelope].
  (storage isNil or: [pointer isNil]) ifTrue: [
    ^ PBUserError signal: self class name , ': an atom with no stored record has no state to load'].
  envelope := storage loadAt: pointer expecting: self tag.
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
  ^ self state at: aName ifAbsent: [self _absentField: aName].

PBAtom >> _absentField: aName
  ^ nil.

"The atom's oid (16 bytes); an unloaded atom loads its record to answer it."
PBAtom >> oid
  oid isNil ifFalse: [^ oid].
  ^ self _envelope oid.

PBAtom >> printOn: aStream
  aStream nextPutAll: self class name; nextPutAll: '('; print: pointer; nextPut: $).

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
