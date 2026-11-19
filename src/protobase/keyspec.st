"-- keyspec.st: PBKeySpec, the persistable description of an indexed key, and the extractor registry --

A port of proto_db's proto_db/indexing/keyspec.py at v2.0.0rc4 (spec section 8.3 there, decision
D29). A key spec is a frozen value of one of three kinds:

  PBKeySpec path: 'a.b'       a dotted path. Each step reads a persisted attribute of a record
                              (its own attributes only) or of another atom, or a key of a map
                              (PBFrozenDict, or a Dictionary); an absent attribute or key at any
                              level, or a step through any other value (nil, a number, ...),
                              answers PBMissing default. Names starting with _ and the reserved
                              names (oid, atom_pointer, context) are never read from an atom. An
                              explicit nil stays nil: absence and nil are different keys.
  PBKeySpec element           the element itself.
  PBKeySpec extractor: aName  a block registered in this process under aName
                              (registerExtractor:block:version:). Only the name is persisted,
                              never the block; the name is resolved when a key is extracted, and
                              an unregistered name signals PBValidationError naming it. Results
                              pass through PBCodec canonical:.

Key specs persist as plain data (asData, the PBTuple (kind, arg)) and compare by value. Terms name
a key by its termPath: the dotted path, nil for the element, '@name' for an extractor.

The extractor registry is process-wide: one Atom holding a PBFrozenDict from name to the PBTuple
(block, version), replaced by compare-and-swap. There is no other mutable state, no lock, and
nothing is held across an allocation. An extractor block must be pure and thread-safe: the same
element always gives the same key, whatever the time, the actor or any state outside the
element, because indexes store the keys it computed. With its name, the optional version
declared when it is registered is its identity across processes (proto_db R101): changing what
it answers for some element needs a new name or a new version. During a merge it runs in the
commit's build (the publisher, or the cluster round), and an exception it raises passes through
extract: unchanged and fails only that commit (ruling IQ1, plan call IP2: exactly as proto_db's
KeySpec.extract, which does not wrap it).

Messages follow proto_db's, with protoST's names (String for str, nil for None, a block for a
function); a value is quoted as Python's repr does for a String (PBCodec repr:)."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/codec'.

Object subclass: #PBKeySpec instanceVariableNames: 'kind arg segments' classVariableNames: 'Extractors'.

"=== the registry ============================================================"

"The registry, made once when the module loads: an Atom of an empty PBFrozenDict."
PBKeySpec class >> _initializeRegistry
  Extractors isNil ifTrue: [Extractors := Atom on: (PBFrozenDict withAssociations: #())].

"The three kinds, in proto_db's order (keyspec.py _KINDS)."
PBKeySpec class >> kinds
  ^ PBTuple withAll: #('path' 'element' 'extractor').

"Python's repr of aValue in a message: a String quoted as Python quotes a str, nil as None."
PBKeySpec class >> _repr: aValue
  aValue isNil ifTrue: [^ 'None'].
  (aValue isString and: [aValue isSymbol not]) ifTrue: [^ PBCodec repr: aValue].
  ^ PBKeys _preview: aValue.

"Whether aCharacter is whitespace as Python's str.isspace() defines it (the Unicode White_Space
 characters and the separators U+001C to U+001F)."
PBKeySpec class >> _isSpace: aCharacter
  | cp |
  cp := aCharacter asInteger.
  (cp between: 9 and: 13) ifTrue: [^ true].
  (cp between: 28 and: 32) ifTrue: [^ true].
  (cp between: 8192 and: 8202) ifTrue: [^ true].
  ^ #(133 160 5760 8232 8233 8239 8287 12288) includes: cp.

PBKeySpec class >> _hasSpace: aString
  ^ aString anySatisfy: [:ch | self _isSpace: ch].

"keyspec.py _check_extractor_name: a non-empty String without whitespace or a leading '@'."
PBKeySpec class >> _checkExtractorName: aName
  ((aName isString and: [aName isSymbol not]) and: [
      aName notEmpty and: [aName first ~= $@ and: [(self _hasSpace: aName) not]]]) ifFalse: [
    ^ PBValidationError signal: 'An extractor name must be a non-empty String without whitespace or a leading ''@'', not '
      , (self _repr: aName)].
  ^ aName.

"Registers aBlock, [:element | key], under aName for PBKeySpec extractor: aName, with the version
 aStringOrNil (keyspec.py register_extractor). Registration is process-wide and must happen
 before any index or term naming the extractor is used. Registering the same block and version
 again does nothing; binding a registered name to another block or another version is
 PBValidationError, because stored indexes rely on the name keeping its meaning. The block must
 be pure and thread-safe (the module comment)."
PBKeySpec class >> registerExtractor: aName block: aBlock version: aStringOrNil
  self _checkExtractorName: aName.
  (aBlock isClassObject not and: [aBlock isKindOf: BlockClosure]) ifFalse: [
    ^ PBValidationError signal: 'Extractor ' , (self _repr: aName) , ' must be a block, not a ' , aBlock class name].
  (aStringOrNil isNil or: [(aStringOrNil isString and: [aStringOrNil isSymbol not]) and: [aStringOrNil notEmpty]]) ifFalse: [
    ^ PBValidationError signal: 'Extractor ' , (self _repr: aName) , ' version must be a non-empty String or nil, not '
      , (self _repr: aStringOrNil)].
  [ | current entry |
    current := Extractors value.
    entry := current at: aName ifAbsent: [nil].
    entry isNil ifFalse: [
      ((entry at: 1) == aBlock and: [(entry at: 2) = aStringOrNil]) ifTrue: [^ self].
      ^ PBValidationError signal: 'Extractor ' , (self _repr: aName) , ' is already registered with another block or version'].
    Extractors
      value: (PBFrozenDict withAssociations: (current associations copyWith: aName -> (PBTuple withAll: { aBlock. aStringOrNil })))
      ifCurrent: current ] whileFalse.

"Removes the registration of aName (keyspec.py unregister_extractor); PBValidationError when it is
 not registered. Until it is registered again, indexes and terms naming it signal on use. Stored
 indexes built with the old block are not rebuilt."
PBKeySpec class >> unregisterExtractor: aName
  self _checkExtractorName: aName.
  [ | current |
    current := Extractors value.
    (current includesKey: aName) ifFalse: [
      ^ PBValidationError signal: 'No key extractor is registered under ' , (self _repr: aName)].
    Extractors
      value: (PBFrozenDict withAssociations: (current associations reject: [:each | each key = aName]))
      ifCurrent: current ] whileFalse.

"The version declared when aName was registered, or nil (keyspec.py extractor_version);
 PBValidationError when aName is not registered."
PBKeySpec class >> extractorVersion: aName
  ^ (self _entry: aName) at: 2.

"Whether an extractor is registered under aName in this process."
PBKeySpec class >> isExtractorRegistered: aName
  (aName isString and: [aName isSymbol not]) ifFalse: [^ false].
  ^ Extractors value includesKey: aName.

"The (block, version) PBTuple registered under aName; PBValidationError naming it and telling
 the program to register it when there is none (keyspec.py _registered)."
PBKeySpec class >> _entry: aName
  | entry |
  entry := (aName isString and: [aName isSymbol not])
    ifTrue: [Extractors value at: aName ifAbsent: [nil]]
    ifFalse: [nil].
  entry isNil ifTrue: [
    ^ PBValidationError signal: 'No key extractor is registered under ' , (self _repr: aName)
      , '; call PBKeySpec registerExtractor: ' , (self _repr: aName)
      , ' block: aBlock version: aStringOrNil in this process before using an index or term that names it'].
  ^ entry.

"=== construction ============================================================"

"Key = the value at the dotted attribute or map path aString (PBMissing default when absent)."
PBKeySpec class >> path: aString
  ^ self _kind: 'path' arg: aString.

"Key = the element itself."
PBKeySpec class >> element
  ^ self _kind: 'element' arg: nil.

"Key = the answer of the block registered under aName, resolved when a key is extracted."
PBKeySpec class >> extractor: aName
  ^ self _kind: 'extractor' arg: aName.

"The key spec a term path names: nil is the element, '@name' an extractor, any other String a
 path (keyspec.py for_term_path)."
PBKeySpec class >> forTermPath: aStringOrNil
  aStringOrNil isNil ifTrue: [^ self element].
  (aStringOrNil isString and: [aStringOrNil isSymbol not]) ifFalse: [
    ^ PBValidationError signal: 'A term path must be a String or nil, not a ' , aStringOrNil class name].
  (aStringOrNil notEmpty and: [aStringOrNil first = $@]) ifTrue: [
    ^ self extractor: (aStringOrNil copyFrom: 2 to: aStringOrNil size)].
  ^ self path: aStringOrNil.

"The key spec of the persisted (kind, arg) data aTuple, a PBTuple, a PBFrozenList or an Array
 (keyspec.py from_data); malformed data is PBCorruptionError."
PBKeySpec class >> fromData: aTuple
  ((aTuple isClassObject not and: [(aTuple isKindOf: _PBSequence) or: [aTuple isKindOf: Array]])
      and: [aTuple size = 2]) ifFalse: [
    ^ PBCorruptionError signal: 'Malformed persisted key spec ' , (self _dataRepr: aTuple)].
  ^ [self _kind: (aTuple at: 1) arg: (aTuple at: 2)] on: PBValidationError do: [:e |
    PBCorruptionError signal: 'Malformed persisted key spec ' , (self _dataRepr: aTuple) , ': ' , e messageText].

"aData as Python's repr shows it: a tuple ('path', 'a') for a PBTuple, a list ['path', 'a'] for
 a PBFrozenList or an Array (msgpack hands a list back), else the value's repr."
PBKeySpec class >> _dataRepr: aData
  | items |
  ((aData isClassObject not and: [(aData isKindOf: _PBSequence) or: [aData isKindOf: Array]])) ifFalse: [
    ^ self _repr: aData].
  items := ', ' join: (aData asArray collect: [:each | self _repr: each]).
  (aData isKindOf: PBTuple) ifFalse: [^ '[' , items , ']'].
  ^ '(' , items , (aData size = 1 ifTrue: [',)'] ifFalse: [')']).

"A key spec of aKind and anArg, validated as proto_db's KeySpec.__post_init__."
PBKeySpec class >> _kind: aKind arg: anArg
  (self kinds asArray includes: aKind) ifFalse: [
    ^ PBValidationError signal: 'Unknown key spec kind ' , (self _repr: aKind)
      , '; expected one of (''path'', ''element'', ''extractor'')'].
  aKind = 'element' ifTrue: [
    anArg isNil ifFalse: [^ PBValidationError signal: 'PBKeySpec element takes no argument'].
    ^ self basicNew _setKind: aKind arg: nil segments: #()].
  aKind = 'extractor' ifTrue: [
    self _checkExtractorName: anArg.
    PBCodec _checkUTF8: anArg.
    ^ self basicNew _setKind: aKind arg: anArg segments: #()].
  ((anArg isString and: [anArg isSymbol not]) and: [anArg notEmpty and: [anArg first ~= $@]]) ifFalse: [
    ^ PBValidationError signal: 'A key path must be a non-empty String not starting with ''@'', not '
      , (self _repr: anArg)].
  PBCodec _checkUTF8: anArg.
  ^ self basicNew _setKind: aKind arg: anArg copy segments: (self _segmentsOf: anArg).

"The segments of the dotted path aString (empty ones kept, as Python's str.split('.'));
 PBValidationError for an empty segment or one holding whitespace."
PBKeySpec class >> _segmentsOf: aString
  | segments start |
  segments := OrderedCollection new.
  start := 1.
  1 to: aString size + 1 do: [:i |
    (i > aString size or: [(aString at: i) = $.]) ifTrue: [
      segments add: (aString copyFrom: start to: i - 1).
      start := i + 1]].
  (segments anySatisfy: [:s | s isEmpty or: [self _hasSpace: s]]) ifTrue: [
    ^ PBValidationError signal: 'Invalid key path ' , (self _repr: aString) , ': empty or blank segment'].
  ^ segments asArray.

PBKeySpec >> _setKind: aKind arg: anArg segments: anArray
  "Runs once, on a fresh instance."
  kind isNil ifFalse: [^ PBUserError signal: 'PBKeySpec is immutable'].
  kind := aKind.
  arg := anArg.
  segments := anArray.
  ^ self.

"=== use ====================================================================="

"'path', 'element' or 'extractor'."
PBKeySpec >> kind
  ^ kind.

"The path, the extractor name, or nil for the element."
PBKeySpec >> arg
  ^ arg.

"The key of anElement, or PBMissing default when it has none (keyspec.py KeySpec.extract). An
 extractor block's exception passes through unchanged."
PBKeySpec >> extract: anElement
  | value |
  kind = 'element' ifTrue: [^ anElement].
  kind = 'extractor' ifTrue: [^ PBCodec canonical: (((self class _entry: arg) at: 1) value: anElement)].
  value := anElement.
  segments do: [:name |
    value := self _step: value name: name.
    value == PBMissing default ifTrue: [^ value]].
  ^ value.

"One path step (keyspec.py _step): the attribute aName of an atom (a record's own ones) or the
 key aName of a map, else PBMissing default."
PBKeySpec >> _step: aValue name: aName
  aValue isClassObject ifTrue: [^ PBMissing default].
  ((aValue isKindOf: PBFrozenDict) or: [aValue isKindOf: Dictionary]) ifTrue: [
    ^ aValue at: aName ifAbsent: [PBMissing default]].
  (aValue isKindOf: PBAtom) ifTrue: [
    (PBAtomEnvelope _nameProblem: aName) isNil ifFalse: [^ PBMissing default].
    (aValue isKindOf: PBObject) ifTrue: [
      ^ (aValue hasDefinedAttr: aName) ifTrue: [aValue at: aName] ifFalse: [PBMissing default]].
    ^ aValue state at: aName ifAbsent: [PBMissing default]].
  ^ PBMissing default.

"How a term names this key: the path, nil (the element) or '@name' (an extractor)."
PBKeySpec >> termPath
  kind = 'element' ifTrue: [^ nil].
  kind = 'extractor' ifTrue: [^ '@' , arg].
  ^ arg.

"The form explain shows: the path, '<element>' or '@name'."
PBKeySpec >> describe
  kind = 'element' ifTrue: [^ '<element>'].
  ^ self termPath.

"=== persistence and value ==================================================="

"The persisted form, the PBTuple (kind, arg)."
PBKeySpec >> asData
  ^ PBTuple withAll: { kind. arg }.

PBKeySpec >> = anObject
  (anObject isClassObject not and: [anObject class == PBKeySpec]) ifFalse: [^ false].
  ^ kind = anObject kind and: [arg = anObject arg].

PBKeySpec >> hash
  ^ (kind hash bitXor: arg hash) \\ 1073741824.

PBKeySpec >> printOn: aStream
  aStream nextPutAll: 'PBKeySpec('; nextPutAll: kind; nextPutAll: ', '; nextPutAll: (self class _repr: arg); nextPut: $).

PBKeySpec _initializeRegistry.
