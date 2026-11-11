"-- notation.st: PBNotation, the language-neutral notation of the conformance manifest --

Every description is a Dictionary with one key (the JSON object of
tests/conformance/README.md, 'The notation'), read from the manifest by
protoST's JSON library or made by describe:. It follows ProtoBase's
proto_db/tools/notation.py (describe) and tests/conformance/typed.py (build)
at v2.0.0rc2; every walk of a value keeps an explicit stack, as ProtoBase's
(R128), so a value MAX_VALUE_DEPTH deep is described and built on any thread:

  PBNotation describe: aValue         the description of a decoded canonical value
  PBNotation build: aDescription      the value a description names
  PBNotation describeRaw: aWireTree   the description of raw msgpack data: the
                                      scalars, plus array and mpmap
  PBNotation floatHex: aFloat         Python's float.hex (nan, inf, -inf as repr)
  PBNotation floatFromHex: aString    the Float of such a text, bit exact
  PBNotation describeObject: anObject the content description of a stored object
                                      (records, opaque atoms and collections by
                                      their content, recursively)
  PBNotation describeDatabase: aSnapshotOrTransaction
                                      roots, mutables, indexes and origin, as
                                      ProtoBase's notation.describe_database
  PBNotation dumpSpace: aSpace to: aPath
                                      the JSON dump of ProtoBase's verifier --out
  PBNotation jsonText: aValue         the JSON text of a dump or description

Kinds: nil, bool, int (decimal text), float (C99 hexadecimal), str, bytes
(hexadecimal), decimal, date, time, datetime, timedelta, uuid, list, tuple,
map (pairs, in order), missing, mutable, ref ({segment, offset, type}); the
stored objects: object, opaque and collection (tests/conformance/README.md,
'Stored objects'). The stored-object part needs the whole protobase module
(the collection and record classes are looked up when a method runs).

A datetime in an instant zone describes as ['instant', key] with the UTC
fields; a format-3 wall-clock datetime (PBLegacyZoneDateTime) describes as
['zone', key] with its wall-clock fields, the form that Python never decodes
(ProtoBase turns it into an instant with its time-zone database; design 4.3).

A reference's type is its name. The type tag of a reference to a built-in type
is an alias (an Integer): describe: shows its name and build: writes the tag a
writer puts (the alias of a built-in type, the declared name of an application
alias), both through PBTypeRegistry, which owns the built-in alias table."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/registry'.
Import from: 'protobase/codec'.
Import from: 'decimal'.
Import from: 'calendar'.
Import from: 'uuid'.

Object subclass: #PBNotation classVariableNames: 'JSONModule'.

PBNotation class >> _setJSON: aModule
  JSONModule := aModule.

PBNotation _setJSON: (Import from: 'json').

"=== floats ==================================================================="

PBNotation class >> _bitsOf: aFloat
  | w |
  w := WriteStream on: ByteArray new.
  w nextPutFloat64: aFloat bigEndian: true.
  ^ w contents unsignedLong64At: 1 bigEndian: true.

"Python's float.hex: '0x1.8000000000000p+0', '0x0.0p+0', '-0x0.0000000000001p-1022'
 (13 hexadecimal digits, the exponent always signed); nan, inf and -inf are
 Python's repr."
PBNotation class >> floatHex: aFloat
  | bits sign e m digits |
  aFloat isNaN ifTrue: [^ 'nan'].
  aFloat isInfinite ifTrue: [^ aFloat > 0 ifTrue: ['inf'] ifFalse: ['-inf']].
  bits := self _bitsOf: aFloat.
  sign := (bits bitShift: -63) = 1 ifTrue: ['-'] ifFalse: [''].
  e := (bits bitShift: -52) bitAnd: 16r7FF.
  m := bits bitAnd: (1 bitShift: 52) - 1.
  (e = 0 and: [m = 0]) ifTrue: [^ sign , '0x0.0p+0'].
  digits := (m printString: 16) asLowercase.
  digits := (String new: 13 - digits size withAll: $0) , digits.
  e = 0 ifTrue: [^ sign , '0x0.' , digits , 'p-1022'].
  ^ sign , '0x1.' , digits , 'p' , (e >= 1023 ifTrue: ['+'] ifFalse: ['-']) , (e - 1023) abs printString.

PBNotation class >> _badHex: aText
  ^ PBValidationError signal: 'PBNotation: not a hexadecimal float of the notation: ' , aText printString.

"The Float of a text floatHex: writes (or 'nan', 'inf', '-inf'), bit exact: a
 NaN is the quiet NaN with no payload."
PBNotation class >> floatFromHex: aString
  | s negative p mantissa exponent lead frac bits bytes |
  (aString isString and: [aString isSymbol not]) ifFalse: [^ self _badHex: aString].
  aString = 'nan' ifTrue: [^ Float nan].
  aString = 'inf' ifTrue: [^ Float infinity].
  aString = '-inf' ifTrue: [^ Float infinity negated].
  aString = '0x0.0p+0' ifTrue: [^ 0.0].
  aString = '-0x0.0p+0' ifTrue: [^ -0.0].
  s := aString.
  negative := s notEmpty and: [s first = $-].
  negative ifTrue: [s := s copyFrom: 2 to: s size].
  "Canonical: 0x, one lead digit, '.', 13 digits, 'p', a sign, the exponent (at least 20 characters)."
  (s size >= 20 and: [(s copyFrom: 1 to: 2) = '0x' and: [(s at: 4) = $.]]) ifFalse: [^ self _badHex: aString].
  lead := (s at: 3) = $0 ifTrue: [0] ifFalse: [(s at: 3) = $1 ifTrue: [1] ifFalse: [^ self _badHex: aString]].
  p := s indexOf: $p.
  p = 18 ifFalse: [^ self _badHex: aString].
  frac := s copyFrom: 5 to: 17.
  mantissa := PBCodec _parseHex: '1' , frac.
  (mantissa isNil or: [frac size ~= 13]) ifTrue: [^ self _badHex: aString].
  mantissa := mantissa - (1 bitShift: 52).
  ((s at: 19) = $+ or: [(s at: 19) = $-]) ifFalse: [^ self _badHex: aString].
  exponent := (s copyFrom: 20 to: s size) asInteger.
  (exponent isNil or: [exponent printString ~= (s copyFrom: 20 to: s size)]) ifTrue: [^ self _badHex: aString].
  "No 'p-0' (zero is written p+0) and no zero mantissa on a lead 0 other than the zero text above."
  ((s at: 19) = $- and: [exponent = 0]) ifTrue: [^ self _badHex: aString].
  (s at: 19) = $- ifTrue: [exponent := exponent negated].
  lead = 0
    ifTrue: [
      (mantissa ~= 0 and: [exponent = -1022]) ifFalse: [^ self _badHex: aString].
      bits := mantissa]
    ifFalse: [
      (exponent between: -1022 and: 1023) ifFalse: [^ self _badHex: aString].
      bits := ((exponent + 1023) bitShift: 52) + mantissa].
  negative ifTrue: [bits := bits + (1 bitShift: 63)].
  bytes := ByteArray withAll: ((0 to: 7) asArray collect: [:i | (bits bitShift: -8 * (7 - i)) bitAnd: 255]).
  ^ bytes float64At: 1 bigEndian: true.

"=== describing ================================================================"

PBNotation class >> _one: aKey value: aValue
  | d |
  d := Dictionary new.
  d at: aKey put: aValue.
  ^ d.

PBNotation class >> _hex: aByteArray
  ^ aByteArray hex asLowercase.

PBNotation class >> _tz: z
  z isNil ifTrue: [^ nil].
  (z isKindOf: ZoneOffset) ifTrue: [^ { 'fixed'. z microseconds. z name }].
  ^ { 'zone'. z key }.

PBNotation class >> _typeName: aTag
  ^ PBTypeRegistry nameOfTag: aTag.

"The description of a decoded canonical value: its kind decides, never its
 truthiness or equality; anything else signals PBValidationError. A walk with
 an explicit stack (ProtoBase notation.describe, 'any depth'): a value nested
 MAX_VALUE_DEPTH deep, or deeper, is described on any thread."
PBNotation class >> describe: v
  ^ _PBValueFrame fold: v
    children: [:x | self _itemsOf: x]
    leaf: [:x | self _describeScalar: x]
    node: [:x :results | self _node: x results: results].

"The items a tuple, list or map is described or walked from (a map's keys and
 values interleaved, in order), or nil for anything else."
PBNotation class >> _itemsOf: v
  ((v isKindOf: PBTuple) or: [v isKindOf: PBFrozenList]) ifTrue: [^ v asArray].
  (v isKindOf: PBFrozenDict) ifTrue: [^ self _interleaved: v associations].
  ^ nil.

"k1, v1, k2, v2, ... of an Array of associations."
PBNotation class >> _interleaved: anArray
  | out |
  out := Array new: 2 * anArray size.
  1 to: anArray size do: [:i |
    out at: 2 * i - 1 put: (anArray at: i) key.
    out at: 2 * i put: (anArray at: i) value].
  ^ out.

"[[r1, r2], [r3, r4], ...] of the results of interleaved keys and values."
PBNotation class >> _pairs: anArray
  | out |
  out := Array new: anArray size // 2.
  1 to: out size do: [:i | out at: i put: { anArray at: 2 * i - 1. anArray at: 2 * i }].
  ^ out.

"The description of a tuple, list or map v from the descriptions of its items."
PBNotation class >> _node: v results: anArray
  (v isKindOf: PBTuple) ifTrue: [^ self _one: 'tuple' value: anArray].
  (v isKindOf: PBFrozenList) ifTrue: [^ self _one: 'list' value: anArray].
  ^ self _one: 'map' value: (self _pairs: anArray).

"The description of a value that is not a tuple, list or map."
PBNotation class >> _describeScalar: v
  v isNil ifTrue: [^ self _one: 'nil' value: nil].
  (v == true or: [v == false]) ifTrue: [^ self _one: 'bool' value: v].
  v isInteger ifTrue: [^ self _one: 'int' value: v printString].
  v isFloat ifTrue: [^ self _one: 'float' value: (self floatHex: v)].
  (v isString and: [v isSymbol not]) ifTrue: [^ self _one: 'str' value: v].
  (v isKindOf: ByteArray) ifTrue: [^ self _one: 'bytes' value: (self _hex: v)].
  (v isKindOf: Decimal) ifTrue: [^ self _one: 'decimal' value: v printString].
  (v isKindOf: DateTime) ifTrue: [^ self _describeDateTime: v].
  (v isKindOf: CalendarDate) ifTrue: [^ self _one: 'date' value: { v year. v month. v day }].
  (v isKindOf: TimeOfDay) ifTrue: [
    ^ self _one: 'time' value: { v hour. v minute. v second. v microsecond. v fold. self _tz: v zone }].
  (v isKindOf: TimeSpan) ifTrue: [^ self _one: 'timedelta' value: { v days. v seconds. v microseconds }].
  (v isKindOf: UUID) ifTrue: [^ self _one: 'uuid' value: (self _hex: (PBCodec _uuidBytes: v))].
  v == PBMissing default ifTrue: [^ self _one: 'missing' value: true].
  (v isKindOf: PBMutableObject) ifTrue: [^ self _one: 'mutable' value: v name].
  ((v isKindOf: PBUnresolvedRef) or: [v isKindOf: PBAtom]) ifTrue: [
    | ref |
    v pointer isNil ifTrue: [^ PBValidationError signal: 'PBNotation: ' , v printString , ' is not stored: it has no ref'].
    ref := Dictionary new.
    ref at: 'segment' put: v pointer segmentHex; at: 'offset' put: v pointer offset;
      at: 'type' put: (self _typeName: v tag).
    ^ self _one: 'ref' value: ref].
  ^ PBValidationError signal: 'PBNotation: no description for a ' , v class name.

PBNotation class >> _describeDateTime: v
  | tz |
  v isLegacyZone ifTrue: [tz := { 'zone'. v zone key }]
    ifFalse: [tz := v isInstantForm ifTrue: [{ 'instant'. v zone key }] ifFalse: [self _tz: v zone]].
  ^ self _one: 'datetime' value: {
    v year. v month. v day. v hour. v minute. v second. v microsecond. v fold. tz }.

"=== stored objects and databases =============================================="

"The content description of a stored object (ProtoBase notation.describe_object):
 a PBObject as {object: type, attrs} (attributes sorted by name), an opaque atom
 as {opaque: type, attrs}, a PBList or PBSet as {collection: type, elements}, a
 PBCountedSet as {collection: type, items: [[element, {int: count}]]}, the
 dictionaries as {collection: type, items: [[key, value]]}, each in the
 collection's own order, recursively; a tuple, list or map is described item by
 item the same way, and any other value by describe: (an atom of another type is
 its ref). A format-3 zone datetime (PBLegacyZoneDateTime) is refused with
 PBNotSupportedError naming its zone: ProtoBase describes the UTC instant, which
 needs the zone's rules (design spec 4.3). A walk with an explicit stack, as
 ProtoBase's: neither the depth of a value nor the length of a chain of records
 is bounded by the protoST stack."
PBNotation class >> describeObject: o
  ^ _PBValueFrame fold: o
    children: [:x | self _contentItemsOf: x]
    leaf: [:x | self _describeContentLeaf: x]
    node: [:x :results | self _contentNode: x results: results].

"The items the content description of o is made from, in order, or nil for a
 leaf: a record's attribute values (by name), a PBList's or PBSet's elements,
 the keys and values (or elements and counts) of the other collections
 interleaved, and the items of a tuple, list or map."
PBNotation class >> _contentItemsOf: o
  | state |
  ((o isKindOf: PBObject) or: [o isKindOf: PBOpaqueAtom]) ifTrue: [
    state := o state.
    ^ o attributeNames asArray collect: [:name | state at: name]].
  ((o isKindOf: PBList) or: [o isKindOf: PBSet]) ifTrue: [^ o elements asArray].
  (self _isItemCollection: o) ifTrue: [^ self _interleaved: o items asArray].
  ^ self _itemsOf: o.

PBNotation class >> _isItemCollection: o
  ^ (o isKindOf: PBCountedSet) or: [(o isKindOf: PBDictionary) or: [
    (o isKindOf: PBHashDictionary) or: [o isKindOf: PBRepeatedKeysDictionary]]].

"The description of a leaf of describeObject: (a count of a PBCountedSet is an
 Integer, so its description is describe:'s)."
PBNotation class >> _describeContentLeaf: o
  ((o isKindOf: DateTime) and: [o isLegacyZone]) ifTrue: [
    ^ o _unsupported: 'description in ProtoBase''s database notation (its UTC instant)'].
  ^ self _describeScalar: o.

"The content description of o from the descriptions of its items."
PBNotation class >> _contentNode: o results: anArray
  | d |
  (o isKindOf: PBObject) ifTrue: [^ self _content: 'object' of: o attrs: anArray].
  (o isKindOf: PBOpaqueAtom) ifTrue: [^ self _content: 'opaque' of: o attrs: anArray].
  ((o isKindOf: PBList) or: [o isKindOf: PBSet]) ifTrue: [
    d := self _one: 'collection' value: (self _typeName: o tag).
    d at: 'elements' put: anArray.
    ^ d].
  (self _isItemCollection: o) ifTrue: [
    d := self _one: 'collection' value: (self _typeName: o tag).
    d at: 'items' put: (self _pairs: anArray).
    ^ d].
  ^ self _node: o results: anArray.

PBNotation class >> _content: aKind of: anAtom attrs: anArray
  | d names |
  names := anAtom attributeNames asArray.
  d := self _one: aKind value: (self _typeName: anAtom tag).
  d at: 'attrs' put: ((1 to: names size) asArray collect: [:i | { names at: i. anArray at: i }]).
  ^ d.

"The description of the database aSnapshotOrTransaction reads (ProtoBase
 notation.describe_database): a Dictionary of roots (name order),
 mutables (name order), indexes and origin."
PBNotation class >> describeDatabase: aSnapshotOrTransaction
  | d |
  d := Dictionary new.
  d at: 'roots' put: (self describeRoots: aSnapshotOrTransaction);
    at: 'mutables' put: (self describeMutables: aSnapshotOrTransaction);
    at: 'indexes' put: (self describeIndexes: aSnapshotOrTransaction);
    at: 'origin' put: (self describeOrigin: aSnapshotOrTransaction).
  ^ d.

"[[name, description], ...] of the roots, by name."
PBNotation class >> describeRoots: aSnapshotOrTransaction
  ^ aSnapshotOrTransaction rootNames asArray collect: [:name |
    { name. self describeObject: (aSnapshotOrTransaction getRootObject: name) }].

"[[name, description], ...] of the mutable cells, by name."
PBNotation class >> describeMutables: aSnapshotOrTransaction
  ^ aSnapshotOrTransaction mutableNames asArray collect: [:name |
    { name. self describeObject: (aSnapshotOrTransaction getMutable: name) }].

"{root name: {index name: {type, member_tokens}}} of every root collection that
 has indexes."
PBNotation class >> describeIndexes: aSnapshotOrTransaction
  | out |
  out := Dictionary new.
  aSnapshotOrTransaction rootNames do: [:name |
    | root |
    root := aSnapshotOrTransaction getRootObject: name.
    ((root isKindOf: PBIndexedCollection) and: [root indexNames notEmpty]) ifTrue: [
      | indexes |
      indexes := Dictionary new.
      root indexNames do: [:indexName |
        | index entry |
        index := root getIndex: indexName.
        entry := Dictionary new.
        entry at: 'type' put: (self _typeName: index tag); at: 'member_tokens' put: index hasMemberTokens.
        indexes at: indexName put: entry].
      out at: name put: indexes]].
  ^ out.

"The description of the database's origin (nil when it has none)."
PBNotation class >> describeOrigin: aSnapshotOrTransaction
  ^ self describe: aSnapshotOrTransaction _root origin.

"Writes to aPath (a String or a FileReference) the JSON dump ProtoBase's
 verifier writes with --out (proto_db/tools/verify.py): root (the root
 record's fields), atoms (every atom reachable from the space root, each
 counted once by pointer), collections (the collections among them),
 opaque_types (the sorted type names of the opaque atoms among them) and
 databases (each database's describeDatabase: of its current version). The
 verifier's canonical-encoding and validate() checks are not made. Answers
 the dump, a Dictionary."
PBNotation class >> dumpSpace: aSpace to: aPath
  | record report walk databases file |
  record := aSpace storage readRoot.
  report := Dictionary new.
  record isNil ifFalse: [
    | root |
    root := Dictionary new.
    root at: 'version' put: record version; at: 'segment' put: record segmentHex;
      at: 'offset' put: record offset; at: 'epoch' put: record epoch.
    report at: 'root' put: root].
  walk := self _walk: aSpace _currentSpaceRoot.
  report at: 'atoms' put: (walk at: 1); at: 'collections' put: (walk at: 2);
    at: 'opaque_types' put: (_PBNames sorted: (walk at: 3)).
  databases := Dictionary new.
  aSpace listDatabases do: [:name |
    | db |
    db := aSpace openDatabase: name.
    databases at: name put: (self describeDatabase: (db snapshotAt: db history first))].
  report at: 'databases' put: databases.
  file := aPath isString ifTrue: [aPath asFileReference] ifFalse: [aPath].
  file contents: (self jsonText: report) , (String with: Character lf).
  ^ report.

"The JSON text of aValue (Dictionaries, Arrays and OrderedCollections of
 scalars), the text protoST's JSON stringify: writes, but written with an
 explicit stack: stringify: recurses through do: blocks, which protoST bounds
 at about 1,000 levels, and a description nests two JSON levels per
 container level (ProtoBase verify.dump_text, R128, for the same reason).
 Scalars and keys are written by stringify: itself."
PBNotation class >> jsonText: aValue
  | out stack |
  out := WriteStream on: String new.
  stack := OrderedCollection new.
  self _jsonOpen: aValue on: out stack: stack.
  [stack isEmpty] whileFalse: [
    | frame items position |
    frame := stack last.
    items := frame at: 1.
    position := (frame at: 2) + 1.
    position > items size
      ifTrue: [
        stack removeLast.
        out nextPutAll: (frame at: 3)]
      ifFalse: [
        | item |
        frame at: 2 put: position.
        position > 1 ifTrue: [out nextPutAll: ','].
        item := items at: position.
        (frame at: 4)
          ifTrue: [
            out nextPutAll: (JSONModule JSON stringifyString: item key jsonKeyString); nextPutAll: ':'.
            self _jsonOpen: item value on: out stack: stack]
          ifFalse: [self _jsonOpen: item on: out stack: stack]]].
  ^ out contents.

"Writes a scalar, or the opening bracket of a container and pushes its frame:
 { items. items written. closing bracket. whether the items are associations }."
PBNotation class >> _jsonOpen: v on: aStream stack: aStack
  (v isKindOf: Dictionary) ifTrue: [
    | items |
    items := OrderedCollection new.
    v keysAndValuesDo: [:k :x | items add: k -> x].
    aStream nextPutAll: '{'.
    ^ aStack addLast: { items asArray. 0. '}'. true }].
  ((v isKindOf: Array) or: [v isKindOf: OrderedCollection]) ifTrue: [
    aStream nextPutAll: '['.
    ^ aStack addLast: { v asArray. 0. ']'. false }].
  aStream nextPutAll: (JSONModule JSON stringify: v).

"{ atoms. collections. opaque type names (a Set) } of the atoms reachable from
 aRoot (nil: none), depth first, each decoded once by pointer."
PBNotation class >> _walk: aRoot
  | stack seen atoms collections opaque |
  stack := OrderedCollection new.
  aRoot isNil ifFalse: [stack addLast: aRoot].
  seen := Set new.
  atoms := 0. collections := 0.
  opaque := Set new.
  [stack notEmpty] whileTrue: [
    | atom children |
    atom := stack removeLast.
    (atom pointer isNil or: [seen includes: atom pointer]) ifFalse: [
      seen add: atom pointer.
      atoms := atoms + 1.
      (atom isKindOf: PBOpaqueAtom) ifTrue: [opaque add: atom tag].
      (atom isKindOf: PBIndexedCollection) ifTrue: [collections := collections + 1].
      children := OrderedCollection new.
      atom state do: [:value | self _atomsIn: value into: children].
      children reverseDo: [:each | stack addLast: each]]].
  ^ { atoms. collections. opaque }.

"Adds the atoms held by the canonical value v, at any depth, to anOrderedCollection."
PBNotation class >> _atomsIn: v into: anOrderedCollection
  | pending |
  pending := OrderedCollection with: v.
  [pending notEmpty] whileTrue: [
    | x |
    x := pending removeFirst.
    (x isKindOf: PBAtom) ifTrue: [anOrderedCollection add: x].
    ((x isKindOf: PBTuple) or: [x isKindOf: PBFrozenList]) ifTrue: [pending addAll: x asArray].
    (x isKindOf: PBFrozenDict) ifTrue: [
      x associations do: [:each | pending add: each key; add: each value]]].

"The description of the tree MessagePack decodeOrdered: answers (raw msgpack
 data: atom envelopes, root records, cluster messages): the scalars as
 describe:, an Array as array, a MessagePackMap as mpmap (pairs, in order).
 A walk with an explicit stack: a record nests up to 1024 containers."
PBNotation class >> describeRaw: aTree
  ^ _PBValueFrame fold: aTree
    children: [:x |
      (x isKindOf: MessagePackMap)
        ifTrue: [self _interleaved: x associations asArray]
        ifFalse: [(x isKindOf: Array) ifTrue: [x] ifFalse: [nil]]]
    leaf: [:x |
      (x isKindOf: MessagePackExt) ifTrue: [
        PBValidationError signal: 'PBNotation: a msgpack ext value has no description'].
      self _describeScalar: x]
    node: [:x :results |
      (x isKindOf: MessagePackMap)
        ifTrue: [self _one: 'mpmap' value: (self _pairs: results)]
        ifFalse: [self _one: 'array' value: results]].

"=== building =================================================================="

PBNotation class >> _bad: aDescription because: aString
  ^ PBValidationError signal: 'PBNotation: ' , aString , ': ' , aDescription printString.

PBNotation class >> _intFrom: aText of: aDescription
  | n |
  n := (aText isString and: [aText isSymbol not]) ifTrue: [aText asInteger] ifFalse: [nil].
  (n isNil or: [n printString ~= aText]) ifTrue: [^ self _bad: aDescription because: 'an int is decimal text'].
  ^ n.

"The value a description names (the inverse of describe:, with a reference's
 type name turned back into its alias when it names a built-in type). A walk
 with an explicit stack, as describe:."
PBNotation class >> build: aDescription
  ^ _PBValueFrame fold: aDescription
    children: [:d | self _buildItemsOf: d]
    leaf: [:d | self _buildScalar: d]
    node: [:d :results | self _buildNode: d results: results].

"The kind of a description, which has exactly one key."
PBNotation class >> _kindOf: aDescription
  ((aDescription isKindOf: Dictionary) and: [aDescription size = 1]) ifFalse: [
    ^ self _bad: aDescription because: 'a description has exactly one key'].
  ^ aDescription associations first key.

"The item descriptions of a list, tuple or map description (a map's keys and
 values interleaved), or nil for any other description."
PBNotation class >> _buildItemsOf: aDescription
  | kind body |
  kind := self _kindOf: aDescription.
  body := aDescription at: kind.
  (kind = 'list' or: [kind = 'tuple']) ifTrue: [^ body asArray].
  kind = 'map' ifTrue: [
    | out |
    out := Array new: 2 * body size.
    1 to: body size do: [:i |
      out at: 2 * i - 1 put: ((body at: i) at: 1).
      out at: 2 * i put: ((body at: i) at: 2)].
    ^ out].
  ^ nil.

PBNotation class >> _buildNode: aDescription results: anArray
  | kind |
  kind := self _kindOf: aDescription.
  kind = 'list' ifTrue: [^ PBFrozenList withAll: anArray].
  kind = 'tuple' ifTrue: [^ PBTuple withAll: anArray].
  ^ PBFrozenDict withAssociations: ((1 to: anArray size // 2) asArray collect: [:i |
    (anArray at: 2 * i - 1) -> (anArray at: 2 * i)]).

"The value of a description that is not a list, tuple or map."
PBNotation class >> _buildScalar: aDescription
  | kind body |
  kind := self _kindOf: aDescription.
  body := aDescription at: kind.
  kind = 'nil' ifTrue: [^ nil].
  kind = 'bool' ifTrue: [^ body].
  kind = 'int' ifTrue: [^ self _intFrom: body of: aDescription].
  kind = 'float' ifTrue: [^ self floatFromHex: body].
  kind = 'str' ifTrue: [^ body].
  kind = 'bytes' ifTrue: [^ self _bytesFromHex: body].
  kind = 'decimal' ifTrue: [^ Decimal fromString: body].
  kind = 'date' ifTrue: [^ CalendarDate year: (body at: 1) month: (body at: 2) day: (body at: 3)].
  kind = 'time' ifTrue: [
    ^ TimeOfDay hour: (body at: 1) minute: (body at: 2) second: (body at: 3) microsecond: (body at: 4)
      fold: (body at: 5) zone: (self _zoneOf: (body at: 6))].
  kind = 'datetime' ifTrue: [^ self _buildDateTime: body].
  kind = 'timedelta' ifTrue: [^ TimeSpan days: (body at: 1) seconds: (body at: 2) microseconds: (body at: 3)].
  kind = 'uuid' ifTrue: [^ self _buildUUID: body].
  kind = 'missing' ifTrue: [^ PBMissing default].
  kind = 'mutable' ifTrue: [^ PBMutableObject name: body].
  kind = 'ref' ifTrue: [^ self _buildRef: body].
  ^ self _bad: aDescription because: 'unknown kind ' , kind printString.

PBNotation class >> _bytesFromHex: aText
  | n |
  ((aText isString and: [aText isSymbol not]) and: [aText size even]) ifFalse: [
    ^ PBValidationError signal: 'PBNotation: bytes are hexadecimal text of even length'].
  n := aText size // 2.
  ^ ByteArray withAll: ((1 to: n) asArray collect: [:i |
    | hi lo |
    hi := PBCodec _hexDigit: (aText at: 2 * i - 1).
    lo := PBCodec _hexDigit: (aText at: 2 * i).
    (hi isNil or: [lo isNil]) ifTrue: [
      ^ PBValidationError signal: 'PBNotation: not a hexadecimal digit in ' , aText printString].
    hi * 16 + lo]).

PBNotation class >> _zoneOf: tz
  tz isNil ifTrue: [^ nil].
  (tz at: 1) = 'fixed' ifTrue: [^ ZoneOffset microseconds: (tz at: 2) name: (tz at: 3)].
  (tz at: 1) = 'zone' ifTrue: [^ ZoneName key: (tz at: 2)].
  ^ PBValidationError signal: 'PBNotation: a time zone is null, fixed or zone: ' , tz printString.

PBNotation class >> _buildDateTime: body
  | tz fields |
  tz := body at: 9.
  fields := body copyFrom: 1 to: 7.
  (tz notNil and: [(tz at: 1) = 'instant']) ifTrue: [
    ^ DateTime utcFields: fields zoneName: (ZoneName key: (tz at: 2))].
  (tz notNil and: [(tz at: 1) = 'zone']) ifTrue: [
    ^ PBLegacyZoneDateTime wallClockFields: fields fold: (body at: 8) zoneName: (ZoneName key: (tz at: 2))].
  ^ DateTime year: (body at: 1) month: (body at: 2) day: (body at: 3) hour: (body at: 4)
    minute: (body at: 5) second: (body at: 6) microsecond: (body at: 7) fold: (body at: 8)
    zone: (self _zoneOf: tz).

PBNotation class >> _buildUUID: aHexText
  ^ UUID fromBytes: (self _bytesFromHex: aHexText).

PBNotation class >> _buildRef: body
  ^ PBUnresolvedRef
    pointer: (PBAtomPointer segment: (self _bytesFromHex: (body at: 'segment')) offset: (body at: 'offset'))
    tag: ([PBTypeRegistry canonicalTag: (body at: 'type')] on: PBCorruptionError do: [:e |
      PBValidationError signal: 'PBNotation: ' , e messageText]).
