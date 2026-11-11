"-- values.st: the value classes of protoBaseST --

The containers and handles of ProtoBase's canonical values (format spec,
'Canonical values'), with PB in place of Proto:

  PBFrozenList     ProtoBase FrozenList: the list kind (a msgpack array)
  PBTuple          a Python tuple: the tuple kind (@tup)
  PBFrozenDict     ProtoBase FrozenDict: the map kind (@map), insertion order kept
  PBMissing        ProtoBase MISSING (@missing), a singleton: PBMissing default
  PBMutableObject  ProtoBase MutableObject (@mut), the handle part: name: and name
  PBAtomPointer    ProtoBase AtomPointer: 16 segment bytes and an offset
  PBUnresolvedRef  a @ref decoded without a resolver; it encodes back to the same @ref

Every value is immutable (Spec decision 3): a class-side constructor copies its
arguments and calls a private initialiser once; no other method assigns an
instance variable, and no accessor answers internal state that a caller could
change (associations and asArray answer fresh copies). The constructors are
shallow: PBCodec canonical: is what freezes a whole tree.

Equality. Until the order keys of the format exist (plan Task 10), keys and
items compare with protoST's = within one class only (1 and 1.0 are different
keys here, as are 1 and true); Task 10 replaces this by order-key comparison.
hash is deliberately cheap and safe (it never hashes an item, so a Decimal of
untrusted input is never hashed): the size and the class.

K14: instance-side methods are reachable from the class object, so =, hash,
printOn: and name answer what a class answers when sent to a class object.
No selector is defined on both sides of one class.

This module also gives every DateTime isLegacyZone (false), and defines
PBLegacyZoneDateTime, the format-3 ['zone', key] datetime (Spec 4.3)."

Import from: 'protobase/errors'.
Import from: 'calendar'.

"=== item equality (until Task 10's order keys) ============================"

"Item and key equality of the containers: identity, else the same class and
 =. A NaN is never = to itself, but one NaN object is the same item as itself.
 A format-3 zone datetime against another DateTime is decided by its own =,
 which signals PBNotSupportedError whenever the answer needs the zone's
 offsets (never an assumed 'not equal')."
Object subclass: #_PBItems.

_PBItems class >> same: a as: b
  a == b ifTrue: [^ true].
  (a isClassObject or: [b isClassObject]) ifTrue: [^ false].
  ((a isKindOf: DateTime) and: [b isKindOf: DateTime]) ifTrue: [
    a isLegacyZone ifTrue: [^ a = b].
    b isLegacyZone ifTrue: [^ b = a]].
  a class == b class ifFalse: [^ false].
  ^ a = b.

"A probe of k: two items that are the same item (same:as:) have = probes, so
 a map checks its keys for duplicates through a Dictionary of probes, in
 linear time. Building one is cheap and safe on untrusted input: no power of
 ten and no Decimal hash. A NaN's probe is its identity; an object of
 another class falls back to its class name (checked pairwise)."
_PBItems class >> probe: k
  ^ self probe: k coarse: false.

"With coarse true, every aware or format-3 datetime has one probe (#('zoned')),
 and numbers compare as the format's map keys do (the order-key rule: true,
 1, 1.0 and Decimal 1.00 are one key): checkDecidableKeys: groups keys that
 may differ only in such datetimes."
_PBItems class >> probe: k coarse: aBoolean
  (aBoolean and: [self _isZoned: k]) ifTrue: [^ #('zoned')].
  (aBoolean and: [self _isNumeric: k]) ifTrue: [^ self _numericProbe: k].
  k isNil ifTrue: [^ #('nil')].
  k == true ifTrue: [^ #('true')].
  k == false ifTrue: [^ #('false')].
  k isClassObject ifTrue: [^ { 'class'. k name }].
  k isInteger ifTrue: [^ { 'int'. k }].
  k isFloat ifTrue: [
    k isNaN ifTrue: [^ { 'nan'. k identityHash }].
    ^ { 'float'. k = 0.0 ifTrue: [0] ifFalse: [k] }].
  k isString ifTrue: [^ { 'str'. k }].
  (k isKindOf: ByteArray) ifTrue: [^ { 'bytes'. k hex }].
  (k isKindOf: Decimal) ifTrue: [^ self _decimalProbe: k].
  (k isKindOf: DateTime) ifTrue: [
    k isLegacyZone ifTrue: [^ { 'dt-format3'. k zone key. k localOrdinalMicroseconds }].
    k isNaive ifTrue: [^ { 'dt-naive'. k localOrdinalMicroseconds }].
    ^ { 'dt-aware'. k utcOrdinalMicroseconds }].
  (k isKindOf: TimeOfDay) ifTrue: [^ { 'time'. k _offset isNil. k _key }].
  (k isKindOf: CalendarDate) ifTrue: [^ { 'date'. k ordinal }].
  (k isKindOf: TimeSpan) ifTrue: [^ { 'td'. k totalMicroseconds }].
  (k isKindOf: _PBSequence) ifTrue: [
    ^ { k class name. k asArray collect: [:each | self probe: each coarse: aBoolean] }].
  (k isKindOf: PBMutableObject) ifTrue: [^ { 'mut'. k name }].
  (k isKindOf: PBUnresolvedRef) ifTrue: [
    ^ { 'ref'. k pointer segmentHex. k pointer offset. k tag }].
  k class name = 'UUID' ifTrue: [^ { 'uuid'. k bytes hex }].
  ^ { 'other'. k class name }.

_PBItems class >> _isNumeric: k
  k isClassObject ifTrue: [^ false].
  ^ k == true or: [k == false or: [k isInteger or: [k isFloat or: [k isKindOf: Decimal]]]].

"Numerically equal bools, integers, floats and decimals have one probe: a
 decimal's (sign, digits without trailing zeros, exponent), or one probe for
 zero, one per infinite sign; a NaN is itself only. A float is converted
 exactly (its binary fraction has a finite decimal expansion, at most 1074
 digits); a decimal is never expanded, so a huge exponent costs nothing."
_PBItems class >> _numericProbe: k
  | f n d k2 |
  k == true ifTrue: [^ self _numericProbe: 1].
  k == false ifTrue: [^ self _numericProbe: 0].
  (k isKindOf: Decimal) ifTrue: [
    | p |
    p := self _decimalProbe: k.
    (p first = 'nan') ifTrue: [^ p].
    ^ { 'num' } , (p copyFrom: 2 to: p size)].
  k isFloat ifTrue: [
    k isNaN ifTrue: [^ { 'nan'. k identityHash }].
    k isInfinite ifTrue: [^ { 'num'. k < 0 ifTrue: [1] ifFalse: [0] }].
    k = 0.0 ifTrue: [^ #('num')].
    f := k asExactFraction.
    f isInteger ifTrue: [^ self _numericProbe: f].
    n := f numerator. d := f denominator. k2 := 0.
    [d > 1] whileTrue: [d := d // 2. k2 := k2 + 1].
    "n / 2^k2 = n * 5^k2 / 10^k2; n is odd, so the digits end in 5, not 0."
    ^ { 'num'. n < 0 ifTrue: [1] ifFalse: [0]. (n abs * (5 raisedTo: k2)) printString. k2 negated }].
  k = 0 ifTrue: [^ #('num')].
  ^ { 'num' } , ((self _decimalProbe: (Decimal sign: (k < 0 ifTrue: [1] ifFalse: [0]) coefficient: k abs exponent: 0)) copyFrom: 2 to: 4).

"Equal decimals have one probe: the sign, the coefficient's digits without
 trailing zeros and the matching exponent (zero has one probe, -0 included)."
_PBItems class >> _decimalProbe: d
  | digits zeros |
  d isNaN ifTrue: [^ { 'nan'. d identityHash }].
  d isInfinite ifTrue: [^ { 'dec-inf'. d sign }].
  d isZero ifTrue: [^ #('dec-zero')].
  digits := d coefficient printString.
  zeros := 0.
  [(digits at: digits size - zeros) = $0] whileTrue: [zeros := zeros + 1].
  ^ { 'dec'. d sign. digits copyFrom: 1 to: digits size - zeros. d exponent + zeros }.

"The most a fixed offset or a zone's offset moves a wall clock from its
 instant (|offset| < 24 h, format spec 'Canonical values')."
_PBItems class >> offsetWindow
  ^ 86399999999.

"Signals PBNotSupportedError when two keys of aKeyArray could conflict and
 only the zone's offsets can tell (format spec, 'Map keys' and 'Known gaps').
 That is exactly when the two keys are equal under the order-key rule at
 every position (the key itself, or each item of a tuple key) except
 positions holding datetimes (numbers fold: true, 1, 1.0 and Decimal 1.00 are
 one key), and at one such position one key holds a format-3 zone datetime
 and the other either an aware datetime whose instant lies within 24 h of its
 wall clock, or a format-3 datetime of another zone whose wall clock lies
 within 48 h. Format-3 datetimes of one zone conflict exactly when their wall
 clocks are equal (fold ignored), which needs no offset. Linear apart from a
 sort per datetime position: keys are grouped by a probe in which every aware
 or format-3 datetime is one token."
_PBItems class >> checkDecidableKeys: aKeyArray
  | buckets |
  (aKeyArray anySatisfy: [:k | self _holdsLegacy: k]) ifFalse: [^ self].
  buckets := Dictionary new.
  aKeyArray do: [:k |
    (buckets at: (self probe: k coarse: true) ifAbsentPut: [OrderedCollection new]) add: k].
  buckets keysAndValuesDo: [:probe :bucket |
    bucket size > 1 ifTrue: [
      (self _zonedPathsOf: bucket first prefix: #()) do: [:path |
        self _checkDateTimes: (bucket collect: [:k | self _at: path in: k])]]].

_PBItems class >> _holdsLegacy: k
  (k isKindOf: _PBSequence) ifTrue: [^ k asArray anySatisfy: [:each | self _holdsLegacy: each]].
  ^ (k isKindOf: DateTime) and: [k isClassObject not and: [k isLegacyZone]].

_PBItems class >> _isZoned: k
  ^ (k isKindOf: DateTime) and: [k isClassObject not and: [k isNaive not]].

"The index paths, within k, of its aware and format-3 datetimes."
_PBItems class >> _zonedPathsOf: k prefix: anArray
  | out |
  (self _isZoned: k) ifTrue: [^ OrderedCollection with: anArray].
  out := OrderedCollection new.
  (k isKindOf: _PBSequence) ifTrue: [
    k keysAndValuesDo: [:i :each | out addAll: (self _zonedPathsOf: each prefix: anArray , { i })]].
  ^ out.

_PBItems class >> _at: aPath in: k
  | v |
  v := k.
  aPath do: [:i | v := v at: i].
  ^ v.

"Datetimes at one position of keys that match everywhere else."
_PBItems class >> _checkDateTimes: aCollection
  | w legacy aware utcs sorted n next |
  w := self offsetWindow.
  legacy := (aCollection select: [:each | each isLegacyZone]) asArray.
  legacy isEmpty ifTrue: [^ self].
  aware := ((aCollection reject: [:each | each isLegacyZone]) asArray)
    sort: [:a :b | a utcOrdinalMicroseconds <= b utcOrdinalMicroseconds].
  utcs := aware collect: [:each | each utcOrdinalMicroseconds].
  legacy do: [:l |
    | i |
    i := self _firstIndexIn: utcs atLeast: l localOrdinalMicroseconds - w.
    (i <= utcs size and: [(utcs at: i) <= (l localOrdinalMicroseconds + w)]) ifTrue: [
      ^ self _undecidable: l and: (aware at: i)]].
  sorted := legacy copy sort: [:a :b | a localOrdinalMicroseconds <= b localOrdinalMicroseconds].
  n := sorted size.
  next := Array new: n.
  n - 1 to: 1 by: -1 do: [:i |
    next at: i put: (((sorted at: i + 1) zone = (sorted at: i) zone)
      ifTrue: [next at: i + 1] ifFalse: [i + 1])].
  1 to: n - 1 do: [:i |
    | j |
    j := next at: i.
    (j notNil and: [(sorted at: j) localOrdinalMicroseconds - (sorted at: i) localOrdinalMicroseconds <= (2 * w)])
      ifTrue: [^ self _undecidable: (sorted at: i) and: (sorted at: j)]].

"The first index of aSortedArray whose element is >= x (size + 1 if none)."
_PBItems class >> _firstIndexIn: aSortedArray atLeast: x
  | lo hi |
  lo := 1. hi := aSortedArray size + 1.
  [lo < hi] whileTrue: [
    | mid |
    mid := (lo + hi) // 2.
    (aSortedArray at: mid) < x ifTrue: [lo := mid + 1] ifFalse: [hi := mid]].
  ^ lo.

_PBItems class >> _undecidable: aLegacy and: other
  ^ PBNotSupportedError signal: 'A map whose keys hold the format-3 zone datetime ' , aLegacy printString
    , ' and ' , other printString , ' at the same position: whether they conflict needs the offsets of '
    , aLegacy zone key , ', and protoBaseST has no time-zone database (design 4.3)'.

"=== the two sequence kinds ================================================="

"The shared protocol of PBFrozenList and PBTuple: an Array that is never
 exposed, 1-based as Smalltalk's collections."
Object subclass: #_PBSequence instanceVariableNames: 'items'.

"A copy of aSequence as an Array: an Array, an OrderedCollection, a
 PBFrozenList or a PBTuple."
_PBSequence class >> withAll: aSequence
  | copy |
  (aSequence isKindOf: _PBSequence)
    ifTrue: [copy := aSequence asArray]
    ifFalse: [
      ((aSequence isKindOf: Array) or: [aSequence isKindOf: OrderedCollection])
        ifFalse: [^ PBValidationError signal: self name , ' withAll: an Array, an OrderedCollection, a PBFrozenList or a PBTuple was expected, not a '
          , aSequence class name].
      copy := Array new: aSequence size.
      1 to: aSequence size do: [:i | copy at: i put: (aSequence at: i)]].
  ^ self basicNew _setItems: copy.

_PBSequence >> _setItems: anArray
  "Runs once, on a fresh instance."
  items isNil ifFalse: [^ PBUserError signal: self class name , ' is immutable'].
  items := anArray.
  ^ self.

_PBSequence >> size
  ^ items size.

_PBSequence >> isEmpty
  ^ items isEmpty.

_PBSequence >> notEmpty
  ^ items notEmpty.

"The item at anInteger, 1-based; out of range signals SubscriptOutOfBounds."
_PBSequence >> at: anInteger
  ^ items at: anInteger.

_PBSequence >> do: aBlock
  items do: aBlock.

"aBlock receives the 1-based index and the item."
_PBSequence >> keysAndValuesDo: aBlock
  1 to: items size do: [:i | aBlock value: i value: (items at: i)].

"index -> item Associations, fresh on each call."
_PBSequence >> associations
  ^ (1 to: items size) asArray collect: [:i | i -> (items at: i)].

"A fresh Array of the items: changing it changes nothing here."
_PBSequence >> asArray
  ^ items copy.

_PBSequence >> = anObject
  self isClassObject ifTrue: [^ self == anObject].
  (anObject isClassObject not and: [anObject class == self class]) ifFalse: [^ false].
  anObject size = items size ifFalse: [^ false].
  1 to: items size do: [:i | (_PBItems same: (items at: i) as: (anObject at: i)) ifFalse: [^ false]].
  ^ true.

_PBSequence >> hash
  self isClassObject ifTrue: [^ self identityHash].
  ^ (self class name hash bitXor: items size) \\ 1073741824.

_PBSequence >> printOn: aStream
  self isClassObject ifTrue: [^ aStream nextPutAll: self name].
  aStream nextPutAll: self class name; nextPut: $(.
  items doWithIndex: [:each :i |
    i > 1 ifTrue: [aStream nextPutAll: ', '].
    aStream print: each].
  aStream nextPut: $).

"ProtoBase FrozenList: the list kind, read back from every msgpack array. It
 is not orderable and cannot be a map key."
_PBSequence subclass: #PBFrozenList.

"A Python tuple: the tuple kind (@tup). Orderable when its items are."
_PBSequence subclass: #PBTuple.

"=== PBFrozenDict ============================================================"

"ProtoBase FrozenDict: the map kind (@map). Insertion order is kept and is
 part of the value's bytes; = ignores it, as Python's dict equality does."
Object subclass: #PBFrozenDict instanceVariableNames: 'keys values'.

"anArray holds Associations, in insertion order. Two keys that are the same
 item signal PBValidationError (a map is never collapsed); keys whose
 conflicts need a time-zone database signal PBNotSupportedError."
PBFrozenDict class >> withAssociations: anArray
  | ks vs buckets |
  ((anArray isKindOf: Array) or: [anArray isKindOf: OrderedCollection]) ifFalse: [
    ^ PBValidationError signal: 'PBFrozenDict withAssociations: an Array of Associations was expected, not a '
      , anArray class name].
  ks := Array new: anArray size.
  vs := Array new: anArray size.
  1 to: anArray size do: [:i |
    | each |
    each := anArray at: i.
    (each isKindOf: Association) ifFalse: [
      ^ PBValidationError signal: 'PBFrozenDict withAssociations: an Association was expected, not a '
        , each class name].
    ks at: i put: each key.
    vs at: i put: each value].
  _PBItems checkDecidableKeys: ks.
  buckets := Dictionary new.
  1 to: ks size do: [:i |
    | bucket |
    bucket := buckets at: (_PBItems probe: (ks at: i)) ifAbsentPut: [OrderedCollection new].
    bucket do: [:j |
      (_PBItems same: (ks at: j) as: (ks at: i)) ifTrue: [
        ^ PBValidationError signal: 'PBFrozenDict: the key ' , (ks at: i) printString , ' appears twice']].
    bucket add: i].
  ^ self basicNew _setKeys: ks values: vs.

PBFrozenDict >> _setKeys: aKeyArray values: aValueArray
  "Runs once, on a fresh instance."
  keys isNil ifFalse: [^ PBUserError signal: 'PBFrozenDict is immutable'].
  keys := aKeyArray.
  values := aValueArray.
  ^ self.

PBFrozenDict >> size
  ^ keys size.

PBFrozenDict >> isEmpty
  ^ keys isEmpty.

PBFrozenDict >> notEmpty
  ^ keys notEmpty.

PBFrozenDict >> _indexOfKey: aKey
  1 to: keys size do: [:i | (_PBItems same: (keys at: i) as: aKey) ifTrue: [^ i]].
  ^ 0.

"The value at aKey; an absent key signals KeyNotFound."
PBFrozenDict >> at: aKey
  ^ self at: aKey ifAbsent: [
    KeyNotFound signal: 'PBFrozenDict>>at: key not found: ' , aKey printString].

PBFrozenDict >> at: aKey ifAbsent: aBlock
  | i |
  i := self _indexOfKey: aKey.
  i = 0 ifTrue: [^ aBlock value].
  ^ values at: i.

PBFrozenDict >> includesKey: aKey
  ^ (self _indexOfKey: aKey) > 0.

"The values, in insertion order."
PBFrozenDict >> do: aBlock
  values do: aBlock.

"aBlock receives each key and its value, in insertion order."
PBFrozenDict >> keysAndValuesDo: aBlock
  1 to: keys size do: [:i | aBlock value: (keys at: i) value: (values at: i)].

"The keys, in insertion order (a fresh Array)."
PBFrozenDict >> keys
  ^ keys copy.

"key -> value Associations in insertion order, fresh on each call."
PBFrozenDict >> associations
  ^ (1 to: keys size) asArray collect: [:i | (keys at: i) -> (values at: i)].

PBFrozenDict >> = anObject
  self isClassObject ifTrue: [^ self == anObject].
  (anObject isClassObject not and: [anObject class == PBFrozenDict]) ifFalse: [^ false].
  anObject size = keys size ifFalse: [^ false].
  1 to: keys size do: [:i |
    | other |
    other := anObject at: (keys at: i) ifAbsent: [^ false].
    (_PBItems same: (values at: i) as: other) ifFalse: [^ false]].
  ^ true.

PBFrozenDict >> hash
  self isClassObject ifTrue: [^ self identityHash].
  ^ ('PBFrozenDict' hash bitXor: keys size) \\ 1073741824.

PBFrozenDict >> printOn: aStream
  self isClassObject ifTrue: [^ aStream nextPutAll: self name].
  aStream nextPutAll: 'PBFrozenDict('.
  1 to: keys size do: [:i |
    i > 1 ifTrue: [aStream nextPutAll: ', '].
    aStream print: (keys at: i); nextPutAll: '->'; print: (values at: i)].
  aStream nextPut: $).

"=== PBMissing ==============================================================="

"ProtoBase MISSING: an absent value, distinct from nil. One instance,
 PBMissing default, made when this module loads."
Object subclass: #PBMissing classVariableNames: 'Default'.

PBMissing class >> _initializeDefault
  Default isNil ifTrue: [Default := self basicNew].
  ^ Default.

PBMissing class >> default
  ^ Default.

"The singleton, as Python's MISSING: there is never a second instance."
PBMissing class >> new
  ^ Default.

PBMissing >> printOn: aStream
  self isClassObject ifTrue: [^ aStream nextPutAll: self name].
  aStream nextPutAll: 'PBMissing default'.

PBMissing _initializeDefault.

"=== PBMutableObject ========================================================="

"ProtoBase MutableObject, the value part: a handle naming a cell of the
 database's mutable table (@mut). get: and set:value: come with the
 transactions (plan Tasks 13 and 18)."
Object subclass: #PBMutableObject instanceVariableNames: 'cellName'.

"aName is a non-empty String; a Symbol is accepted and kept as its String,
 since a name is always a string on disk (Spec 4.4)."
PBMutableObject class >> name: aName
  | text |
  (aName isString and: [aName isEmpty not]) ifFalse: [
    ^ PBValidationError signal: 'A mutable name must be a non-empty String, not '
      , aName printString].
  text := aName isSymbol ifTrue: [aName asString] ifFalse: [aName].
  ^ self basicNew _setCellName: text.

PBMutableObject >> _setCellName: aString
  "Runs once, on a fresh instance."
  cellName isNil ifFalse: [^ PBUserError signal: 'PBMutableObject is immutable'].
  cellName := aString.
  ^ self.

"The cell name (the class name when sent to the class object, K14)."
PBMutableObject >> name
  self isClassObject ifTrue: [^ super name].
  ^ cellName.

PBMutableObject >> = anObject
  self isClassObject ifTrue: [^ self == anObject].
  ^ (anObject isClassObject not and: [anObject class == PBMutableObject])
    and: [cellName = anObject name].

PBMutableObject >> hash
  self isClassObject ifTrue: [^ self identityHash].
  ^ cellName hash.

PBMutableObject >> printOn: aStream
  self isClassObject ifTrue: [^ aStream nextPutAll: self name].
  aStream nextPutAll: 'PBMutableObject('; print: cellName; nextPut: $).

"=== PBAtomPointer ==========================================================="

"ProtoBase AtomPointer: where an atom's record is, as the 16 bytes of its
 segment's UUID (RFC 4122 order) and an offset >= 0."
Object subclass: #PBAtomPointer instanceVariableNames: 'segmentBytes offset'.

"aUUID is a UUID (anything answering bytes) or its 16 bytes as a ByteArray."
PBAtomPointer class >> segment: aUUID offset: anInteger
  | bytes |
  bytes := (aUUID isKindOf: ByteArray)
    ifTrue: [aUUID]
    ifFalse: [(aUUID respondsTo: #bytes) ifTrue: [aUUID bytes] ifFalse: [nil]].
  ((bytes isKindOf: ByteArray) and: [bytes size = 16]) ifFalse: [
    ^ PBValidationError signal: 'PBAtomPointer: a segment of 16 bytes was expected, not '
      , aUUID printString].
  (anInteger isInteger and: [anInteger >= 0]) ifFalse: [
    ^ PBValidationError signal: 'PBAtomPointer: an offset >= 0 was expected, not '
      , anInteger printString].
  ^ self basicNew _setSegmentBytes: bytes offset: anInteger.

PBAtomPointer >> _setSegmentBytes: aByteArray offset: anInteger
  "Runs once, on a fresh instance."
  segmentBytes isNil ifFalse: [^ PBUserError signal: 'PBAtomPointer is immutable'].
  segmentBytes := aByteArray.
  offset := anInteger.
  ^ self.

"The 16 segment bytes (a ByteArray, immutable in protoST)."
PBAtomPointer >> segmentBytes
  ^ segmentBytes.

"The segment as 32 lowercase hexadecimal digits (uuid.hex)."
PBAtomPointer >> segmentHex
  ^ segmentBytes hex asLowercase.

PBAtomPointer >> offset
  ^ offset.

PBAtomPointer >> = anObject
  self isClassObject ifTrue: [^ self == anObject].
  ^ (anObject isClassObject not and: [anObject class == PBAtomPointer])
    and: [offset = anObject offset and: [segmentBytes = anObject segmentBytes]].

PBAtomPointer >> hash
  self isClassObject ifTrue: [^ self identityHash].
  ^ (segmentBytes hash bitXor: offset hash) \\ 1073741824.

PBAtomPointer >> printOn: aStream
  self isClassObject ifTrue: [^ aStream nextPutAll: self name].
  aStream nextPutAll: 'PBAtomPointer('; nextPutAll: self segmentHex;
    nextPutAll: ', '; print: offset; nextPut: $).

"=== PBUnresolvedRef ========================================================="

"A @ref decoded with no resolver: the pointer and the type tag as read (an
 alias Integer or a type name). It encodes back to the same @ref."
Object subclass: #PBUnresolvedRef instanceVariableNames: 'pointer tag'.

PBUnresolvedRef class >> pointer: aPBAtomPointer tag: aTag
  (aPBAtomPointer isKindOf: PBAtomPointer) ifFalse: [
    ^ PBValidationError signal: 'PBUnresolvedRef: a PBAtomPointer was expected, not '
      , aPBAtomPointer printString].
  ((aTag isInteger and: [aTag >= 0]) or: [aTag isString and: [aTag isSymbol not and: [aTag isEmpty not]]])
    ifFalse: [^ PBValidationError signal: 'PBUnresolvedRef: a type alias or name was expected, not '
      , aTag printString].
  ^ self basicNew _setPointer: aPBAtomPointer tag: aTag.

PBUnresolvedRef >> _setPointer: aPBAtomPointer tag: aTag
  "Runs once, on a fresh instance."
  pointer isNil ifFalse: [^ PBUserError signal: 'PBUnresolvedRef is immutable'].
  pointer := aPBAtomPointer.
  tag := aTag.
  ^ self.

PBUnresolvedRef >> pointer
  ^ pointer.

PBUnresolvedRef >> tag
  ^ tag.

"A reference to an atom, for PBCodec."
PBUnresolvedRef >> isPBReference
  ^ true.

PBUnresolvedRef >> = anObject
  self isClassObject ifTrue: [^ self == anObject].
  ^ (anObject isClassObject not and: [anObject class == PBUnresolvedRef])
    and: [pointer = anObject pointer and: [tag = anObject tag]].

PBUnresolvedRef >> hash
  self isClassObject ifTrue: [^ self identityHash].
  ^ pointer hash.

PBUnresolvedRef >> printOn: aStream
  self isClassObject ifTrue: [^ aStream nextPutAll: self name].
  aStream nextPutAll: 'PBUnresolvedRef('; print: pointer; nextPutAll: ', '; print: tag; nextPut: $).

"=== PBLegacyZoneDateTime ===================================================="

"False: a DateTime of protoST's calendar is never the format-3 zone form."
DateTime >> isLegacyZone
  ^ false.

"A format-3 ['zone', key] datetime (its methods read DateTime's fields
 through its accessors: inherited instance variables of another module are
 not in scope) (legacy data): its fields are a wall clock
 and a fold in an IANA zone. Without a time-zone database its UTC instant is
 unknown, so it is never given an offset: every order or hash use, and every
 question about its instant, signals PBNotSupportedError naming the zone, and
 PBCodec refuses to write it (PBValidationError). Only the decoder makes one."
DateTime subclass: #PBLegacyZoneDateTime.

PBLegacyZoneDateTime class >> wallClockFields: anArray fold: aFold zoneName: aZoneName
  ((anArray isKindOf: Array) and: [anArray size = 7]) ifFalse: [
    ^ PBValidationError signal: 'PBLegacyZoneDateTime: an Array of 7 fields was expected, not '
      , anArray printString].
  ((aZoneName isKindOf: ZoneName) and: [aZoneName isClassObject not]) ifFalse: [
    ^ PBValidationError signal: 'PBLegacyZoneDateTime: a ZoneName was expected, not '
      , aZoneName printString].
  "The naive DateTime checks every field's range."
  DateTime year: (anArray at: 1) month: (anArray at: 2) day: (anArray at: 3)
    hour: (anArray at: 4) minute: (anArray at: 5) second: (anArray at: 6)
    microsecond: (anArray at: 7) fold: aFold zone: nil.
  ^ self basicNew
      _setYear: (anArray at: 1) month: (anArray at: 2) day: (anArray at: 3)
      hour: (anArray at: 4) minute: (anArray at: 5) second: (anArray at: 6)
      microsecond: (anArray at: 7) fold: aFold zone: aZoneName.

"DateTime's constructors would make a PBLegacyZoneDateTime of another form."
PBLegacyZoneDateTime class >> year: y month: m day: d hour: h minute: mi second: s microsecond: us fold: f zone: z
  ^ PBUserError signal: 'PBLegacyZoneDateTime is made by PBCodec from format-3 data only'.

PBLegacyZoneDateTime class >> utcFields: anArray zoneName: aZoneName
  ^ PBUserError signal: 'PBLegacyZoneDateTime is made by PBCodec from format-3 data only'.

PBLegacyZoneDateTime class >> utcOrdinalMicroseconds: anInteger zone: aZone
  ^ PBUserError signal: 'PBLegacyZoneDateTime is made by PBCodec from format-3 data only'.

PBLegacyZoneDateTime >> isLegacyZone
  ^ true.

PBLegacyZoneDateTime >> isInstantForm
  ^ false.

PBLegacyZoneDateTime >> _unsupported: aString
  ^ PBNotSupportedError signal: 'The format-3 zone datetime ' , self printString , ' has no '
    , aString , ' without the time-zone database of ' , self zone key
    , ' (Spec 4.3); store its UTC or fixed-offset form'.

PBLegacyZoneDateTime >> utcOrdinalMicroseconds
  ^ self _unsupported: 'known UTC instant'.

PBLegacyZoneDateTime >> hash
  self isClassObject ifTrue: [^ self identityHash].
  ^ self _unsupported: 'hash'.

PBLegacyZoneDateTime >> _orderWith: anObject
  ^ self _unsupported: 'order'.

"Python's rule without a database: a value in the same zone compares by its
 wall clock (fold ignored); a naive DateTime or another object is never
 equal; an aware value whose instant is more than 24 h from this wall clock
 (48 h for a format-3 value of another zone) is never equal; any other aware
 value needs the zone's offsets and signals."
PBLegacyZoneDateTime >> = anObject
  self isClassObject ifTrue: [^ self == anObject].
  self == anObject ifTrue: [^ true].
  ((anObject isKindOf: DateTime) and: [anObject isClassObject not]) ifFalse: [^ false].
  anObject isNaive ifTrue: [^ false].
  (anObject isLegacyZone and: [anObject zone = self zone]) ifTrue: [
    ^ self localOrdinalMicroseconds = anObject localOrdinalMicroseconds].
  "Offsets are under 24 h: far enough apart, the two can never be one instant."
  anObject isLegacyZone
    ifTrue: [(self localOrdinalMicroseconds - anObject localOrdinalMicroseconds) abs > (2 * _PBItems offsetWindow)
      ifTrue: [^ false]]
    ifFalse: [(self localOrdinalMicroseconds - anObject utcOrdinalMicroseconds) abs > _PBItems offsetWindow
      ifTrue: [^ false]].
  ^ self _unsupported: 'equality with ' , anObject printString.

"The wall clock, then the zone key in brackets."
PBLegacyZoneDateTime >> printOn: aStream
  self isClassObject ifTrue: [^ aStream nextPutAll: self name].
  aStream nextPutAll: (DateTime _fieldsText: { self year. self month. self day. self hour. self minute. self second. self microsecond });
    nextPut: $[; nextPutAll: self zone key; nextPut: $].
