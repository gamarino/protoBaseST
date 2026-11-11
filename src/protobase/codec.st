"-- codec.st: PBCodec, the canonical values of format 4 --

The wire form of a value is the msgpack data of the ProtoBase format spec
(v2.0.0rc1, 'Canonical values'). PBCodec turns a protoST value into that data
and back, with every refusal of the spec:

  PBCodec canonical: aValue              the canonical value, or PBValidationError
  PBCodec toWire: aValue atomRef: aBlock a tree MessagePack encode: takes
  PBCodec fromWire: aTree resolver: r    a value, or PBCorruptionError
  PBCodec encode: aValue                 the msgpack bytes of one value
  PBCodec decode: aByteArray             one value from its bytes

Kinds (format kind: protoST class):
  nil, bool: nil, true, false        int: Integer (@int outside -2^63..2^64-1)
  float: Float                       str: String         bytes: ByteArray
  decimal: Decimal (@dec)            date: CalendarDate (@date)
  time: TimeOfDay (@time)            datetime: DateTime (@dt)
  timedelta: TimeSpan (@td)          uuid: UUID (@uuid, when lib/uuid.st exists)
  list: PBFrozenList (an Array or an OrderedCollection is copied)
  tuple: PBTuple (@tup)              map: PBFrozenDict (@map)
  missing: PBMissing default         mutable: PBMutableObject (@mut)
  ref: an atom (anything answering isPBReference), through the atomRef: block

Refused when written (PBValidationError naming the class): a Symbol (the @sym
kind is reserved and not in format 4, Spec 4.4), a Fraction, a Character, a
Dictionary (its order is unspecified, and the order is part of the bytes: use
PBFrozenDict), a Set, a Bag, an Interval, a block, a class, and any other
object. A host subclass of a mapped class is stored as its base value, read
from the base class's instance variables, never through the subclass's
methods.

Time zones (Spec 4.3). There is no time-zone database. A zone key is known
when the system's zoneinfo directory (Python's default TZPATH) holds a TZif
file of that name, which is what Python's ZoneInfo reads; an unknown key is
PBValidationError when written and PBCorruptionError when read. An instant
whose wall clock in its zone could fall outside years 1 to 9999 (within one
day of either end) cannot be checked without the zone's rules, and is refused
with PBNotSupportedError in both directions. A format-3 ['zone', key]
datetime is read as a PBLegacyZoneDateTime and is never written.

Decoding checks the tree that MessagePack decodeOrdered: answers: map keys are
strings, no ext value, exactly one key per tagged map, one spelling for @int,
@dec, @td and the date and time fields. Every map is written as a
MessagePackMap, so the bytes keep their order."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'decimal'.
Import from: 'calendar'.
[Import from: 'uuid'] on: Error do: [:e |
  e messageText = 'module not found: uuid' ifFalse: [e pass]].

Object subclass: #PBCodec.

"=== constants ================================================================"

PBCodec class >> _intMin
  ^ -9223372036854775808.

PBCodec class >> _intMax
  ^ 18446744073709551615.

"CPython's decimal limits on a string it converts (MIN_ETINY and MAX_EMAX):
 the exponent of a finite decimal, and its adjusted exponent."
PBCodec class >> _decimalMinExponent
  ^ -1999999999999999997.

PBCodec class >> _decimalMaxAdjusted
  ^ 999999999999999999.

"The number of built-in type aliases (format spec 'Built-in type aliases');
 the table itself is PBTypeRegistry's (plan Task 9)."
PBCodec class >> _builtinAliasCount
  ^ 22.

"Python's default TZPATH."
PBCodec class >> _zoneDirectories
  ^ #('/usr/share/zoneinfo' '/usr/lib/zoneinfo' '/usr/share/lib/zoneinfo' '/etc/zoneinfo').

"The ordinal microseconds within which every wall clock of an instant lies in
 years 1 to 9999, whatever its zone's offset (|offset| < 24 h)."
PBCodec class >> _instantLow
  ^ 86399999999.

PBCodec class >> _instantHigh
  ^ 315537897599999999 - 86399999999.

PBCodec class >> _uuidClass
  ^ Smalltalk at: #UUID ifAbsent: [nil].

"=== canonical values ========================================================="

"aValue in canonical form: containers frozen (an Array or OrderedCollection
 becomes a PBFrozenList), host subclasses reduced to their base values. An
 already canonical value is answered as is. A value that cannot be stored
 signals PBValidationError naming its class."
PBCodec class >> canonical: aValue
  ^ self _canonical: aValue depth: 0.

PBCodec class >> _canonical: v depth: d
  | uuid |
  d > 512 ifTrue: [^ PBValidationError signal: 'PBCodec: a value nested deeper than 512 levels cannot be stored'].
  v isNil ifTrue: [^ v].
  (v == true or: [v == false]) ifTrue: [^ v].
  v isClassObject ifTrue: [^ self _refuse: v because: 'a class is not a value'].
  v isInteger ifTrue: [^ v].
  v isFloat ifTrue: [^ v].
  v isSymbol ifTrue: [
    ^ self _refuse: v because: 'the @sym kind is reserved and not part of format 4 (Spec 4.4); store a String'].
  v isString ifTrue: [^ v].
  (v isKindOf: ByteArray) ifTrue: [
    ^ v class == ByteArray ifTrue: [v] ifFalse: [self _plainBytes: v]].
  (v isKindOf: Decimal) ifTrue: [^ self _canonicalDecimal: v].
  (v isKindOf: PBLegacyZoneDateTime) ifTrue: [
    ^ PBValidationError signal: 'PBCodec: the format-3 zone datetime ' , v printString
      , ' cannot be written: its UTC instant needs the time-zone database of ' , v zone key
      , ' (Spec 4.3); store its UTC or fixed-offset form'].
  (v isKindOf: DateTime) ifTrue: [^ self _canonicalDateTime: v].
  (v isKindOf: CalendarDate) ifTrue: [
    v class == CalendarDate ifTrue: [^ v].
    ^ CalendarDate year: (self _field: 'year' of: v base: CalendarDate)
        month: (self _field: 'month' of: v base: CalendarDate)
        day: (self _field: 'day' of: v base: CalendarDate)].
  (v isKindOf: TimeOfDay) ifTrue: [^ self _canonicalTime: v].
  (v isKindOf: TimeSpan) ifTrue: [
    v class == TimeSpan ifTrue: [^ v].
    ^ TimeSpan microseconds: (self _field: 'total' of: v base: TimeSpan)].
  uuid := self _uuidClass.
  (uuid notNil and: [v isKindOf: uuid]) ifTrue: [
    v class == uuid ifTrue: [^ v].
    ^ PBNotSupportedError signal: 'PBCodec: a subclass of UUID (' , v class name
      , ') cannot be reduced to its base value yet'].
  v == PBMissing default ifTrue: [^ v].
  (v isKindOf: PBMutableObject) ifTrue: [
    v class == PBMutableObject ifTrue: [^ v].
    ^ PBMutableObject name: (self _field: 'cellName' of: v base: PBMutableObject)].
  (v isKindOf: PBTuple) ifTrue: [^ self _canonicalItems: v class: PBTuple depth: d].
  (v isKindOf: PBFrozenList) ifTrue: [^ self _canonicalItems: v class: PBFrozenList depth: d].
  ((v isKindOf: Array) or: [v isKindOf: OrderedCollection]) ifTrue: [
    ^ PBFrozenList withAll: (v asArray collect: [:each | self _canonical: each depth: d + 1])].
  (v isKindOf: PBFrozenDict) ifTrue: [^ self _canonicalMap: v depth: d].
  (v isKindOf: Dictionary) ifTrue: [
    ^ self _refuse: v because: 'its order is unspecified, and the order is part of the bytes; use PBFrozenDict'].
  (self _isReference: v) ifTrue: [^ v].
  ^ self _refuse: v because: 'it is not a canonical value of format 4'.

PBCodec class >> _refuse: v because: aString
  ^ PBValidationError signal: 'PBCodec: a ' , v class name , ' cannot be stored ('
    , (self _preview: v) , '): ' , aString.

PBCodec class >> _isReference: v
  ^ v isClassObject not and: [(v respondsTo: #isPBReference) and: [v isPBReference == true]].

"The instance variable aName of v as aBaseClass declares it: a subclass's
 accessors are never used to read the base value."
PBCodec class >> _field: aName of: v base: aBaseClass
  ^ v instVarAt: (aBaseClass allInstVarNames indexOf: aName).

PBCodec class >> _plainBytes: aByteArray
  ^ ByteArray withAll: ((1 to: aByteArray size) asArray collect: [:i | aByteArray at: i]).

PBCodec class >> _canonicalDecimal: v
  | d kind |
  d := v.
  v class == Decimal ifFalse: [
    kind := self _field: 'kind' of: v base: Decimal.
    d := kind == #finite
      ifTrue: [Decimal sign: (self _field: 'sign' of: v base: Decimal)
        coefficient: (self _field: 'coefficient' of: v base: Decimal)
        exponent: (self _field: 'exponent' of: v base: Decimal)]
      ifFalse: [kind == #infinite
        ifTrue: [Decimal infinity: (self _field: 'sign' of: v base: Decimal)]
        ifFalse: [Decimal nan: (self _field: 'coefficient' of: v base: Decimal)
          signaling: kind == #snan sign: (self _field: 'sign' of: v base: Decimal)]]].
  (self _isDecimalInRange: d) ifFalse: [
    ^ PBValidationError signal: 'PBCodec: the decimal ' , (self _preview: d)
      , ' has an exponent outside what CPython''s decimal module can represent'].
  ^ d.

"False for a finite decimal whose exponent is below MIN_ETINY or whose
 adjusted exponent is above MAX_EMAX: CPython refuses its text."
PBCodec class >> _isDecimalInRange: aDecimal
  | digits |
  aDecimal isFinite ifFalse: [^ true].
  aDecimal exponent < self _decimalMinExponent ifTrue: [^ false].
  digits := aDecimal coefficient printString size.
  ^ aDecimal exponent + digits - 1 <= self _decimalMaxAdjusted.

PBCodec class >> _canonicalZone: z
  z isNil ifTrue: [^ nil].
  (z isKindOf: ZoneOffset) ifTrue: [
    z class == ZoneOffset ifTrue: [^ z].
    ^ ZoneOffset microseconds: (self _field: 'microseconds' of: z base: ZoneOffset)
        name: (self _field: 'name' of: z base: ZoneOffset)].
  (z isKindOf: ZoneName) ifTrue: [
    | key |
    key := self _field: 'key' of: z base: ZoneName.
    (self _isKnownZoneKey: key) ifFalse: [
      ^ PBValidationError signal: 'PBCodec: unknown time zone key ' , key printString].
    z class == ZoneName ifTrue: [^ z].
    ^ ZoneName key: key].
  ^ self _refuse: z because: 'it is not a time zone of format 4'.

PBCodec class >> _canonicalTime: v
  | zone |
  zone := self _canonicalZone: (self _field: 'zone' of: v base: TimeOfDay).
  (v class == TimeOfDay and: [zone == v zone]) ifTrue: [^ v].
  ^ TimeOfDay hour: (self _field: 'hour' of: v base: TimeOfDay)
      minute: (self _field: 'minute' of: v base: TimeOfDay)
      second: (self _field: 'second' of: v base: TimeOfDay)
      microsecond: (self _field: 'microsecond' of: v base: TimeOfDay)
      fold: (self _field: 'fold' of: v base: TimeOfDay)
      zone: zone.

PBCodec class >> _canonicalDateTime: v
  | zone f result |
  zone := self _canonicalZone: (self _field: 'zone' of: v base: DateTime).
  f := [:name | self _field: name of: v base: DateTime].
  result := (v class == DateTime and: [zone == v zone])
    ifTrue: [v]
    ifFalse: [(zone isKindOf: ZoneName)
      ifTrue: [DateTime
        utcFields: { f value: 'year'. f value: 'month'. f value: 'day'. f value: 'hour'.
          f value: 'minute'. f value: 'second'. f value: 'microsecond' }
        zoneName: zone]
      ifFalse: [DateTime year: (f value: 'year') month: (f value: 'month') day: (f value: 'day')
        hour: (f value: 'hour') minute: (f value: 'minute') second: (f value: 'second')
        microsecond: (f value: 'microsecond') fold: (f value: 'fold') zone: zone]].
  result isInstantForm ifTrue: [self _checkInstantBand: result].
  ^ result.

"Signals PBNotSupportedError when the wall clock of an instant-form DateTime
 could fall outside years 1 to 9999 in its zone: deciding needs the zone's
 rules (format spec, ['instant', key])."
PBCodec class >> _checkInstantBand: aDateTime
  | utc |
  utc := aDateTime utcOrdinalMicroseconds.
  (utc < self _instantLow or: [utc > self _instantHigh]) ifTrue: [
    ^ PBNotSupportedError signal: 'PBCodec: the instant ' , aDateTime printString
      , ' lies within one day of year 1 or year 9999, so its wall clock in '
      , aDateTime zone key , ' may fall outside years 1 to 9999; protoBaseST has no time-zone database to decide (Spec 4.3)'].
  ^ aDateTime.

PBCodec class >> _canonicalItems: v class: aClass depth: d
  | items same |
  items := (self _field: 'items' of: v base: _PBSequence) collect: [:each | self _canonical: each depth: d + 1].
  same := v class == aClass.
  same ifTrue: [
    | old |
    old := self _field: 'items' of: v base: _PBSequence.
    1 to: items size do: [:i | (items at: i) == (old at: i) ifFalse: [same := false]]].
  same ifTrue: [^ v].
  ^ aClass withAll: items.

PBCodec class >> _canonicalMap: v depth: d
  | ks vs pairs same |
  ks := self _field: 'keys' of: v base: PBFrozenDict.
  vs := self _field: 'values' of: v base: PBFrozenDict.
  same := v class == PBFrozenDict.
  pairs := (1 to: ks size) asArray collect: [:i |
    | k val |
    k := self _canonical: (ks at: i) depth: d + 1.
    val := self _canonical: (vs at: i) depth: d + 1.
    (k == (ks at: i) and: [val == (vs at: i)]) ifFalse: [same := false].
    self _checkMapKey: k.
    k -> val].
  same ifTrue: [^ v].
  ^ PBFrozenDict withAssociations: pairs.

"Signals PBValidationError for a value that can never be a map key (format
 spec 'Map keys'): a list, a map, a signaling decimal NaN, a datetime in an
 IANA zone, or a tuple holding one. The conflict rule between keys (1 and
 1.0, two aware datetimes of one instant) comes with the order keys (plan
 Task 10); until then a map refuses only keys that are the same item."
PBCodec class >> _checkMapKey: k
  | reason |
  reason := self _unkeyableReason: k legacyAllowed: false.
  reason isNil ifFalse: [^ PBValidationError signal: 'PBCodec: ' , reason].
  ^ k.

PBCodec class >> _unkeyableReason: k legacyAllowed: aBoolean
  (k isKindOf: PBFrozenList) ifTrue: [^ 'a list cannot be a map key'].
  (k isKindOf: PBFrozenDict) ifTrue: [^ 'a map cannot be a map key'].
  ((k isKindOf: Decimal) and: [k isSignaling]) ifTrue: [^ 'a signaling decimal NaN cannot be a map key'].
  (k isKindOf: PBLegacyZoneDateTime) ifTrue: [
    ^ aBoolean ifTrue: [nil] ifFalse: ['a datetime in an IANA time zone cannot be a map key']].
  ((k isKindOf: DateTime) and: [k isInstantForm]) ifTrue: [
    ^ 'a datetime in an IANA time zone cannot be a map key: use its UTC or fixed-offset form'].
  (k isKindOf: PBTuple) ifTrue: [
    k do: [:each |
      | r |
      r := self _unkeyableReason: each legacyAllowed: aBoolean.
      r isNil ifFalse: [^ r , ' (inside a tuple)']]].
  ^ nil.

"=== time zone keys ==========================================================="

"True when aKey names a TZif file of a TZPATH directory, as Python's ZoneInfo
 requires; a key that is not a normalized relative path is never known."
PBCodec class >> _isKnownZoneKey: aKey
  (aKey isString and: [aKey isSymbol not and: [aKey notEmpty]]) ifFalse: [^ false].
  (self _isNormalizedKey: aKey) ifFalse: [^ false].
  self _zoneDirectories do: [:dir |
    | file |
    file := FileReference path: dir , '/' , aKey.
    file isFile ifTrue: [
      | head |
      head := [file binaryContents] on: Error do: [:e | nil].
      ^ (head isKindOf: ByteArray) and: [head size >= 4
        and: [(head copyFrom: 1 to: 4) = #[84 90 105 102]]]]].
  ^ false.

"No leading /, no empty, . or .. component, no NUL or backslash."
PBCodec class >> _isNormalizedKey: aKey
  | start |
  (aKey first = $/ or: [aKey last = $/]) ifTrue: [^ false].
  1 to: aKey size do: [:i |
    | c |
    c := (aKey at: i) asInteger.
    (c = 0 or: [c = 92]) ifTrue: [^ false]].
  start := 1.
  1 to: aKey size + 1 do: [:i |
    (i > aKey size or: [(aKey at: i) = $/]) ifTrue: [
      | part |
      part := aKey copyFrom: start to: i - 1.
      (part isEmpty or: [part = '.' or: [part = '..']]) ifTrue: [^ false].
      start := i + 1]].
  ^ true.

"=== encoding ================================================================="

"The wire form of aValue (canonicalized first): msgpack-ready data where
 every map is a MessagePackMap. aBlock value: anAtom answers the wire form of
 a reference to it; PBCodec pointerRef and PBCodec tokenRef are the two
 standard blocks."
PBCodec class >> toWire: aValue atomRef: aBlock
  ^ self _wire: (self canonical: aValue) ref: aBlock.

"The block that writes a reference as its pointer: {'@ref': [segment, offset,
 tag]}, from the reference's pointer and tag."
PBCodec class >> pointerRef
  ^ [:anAtom | self _pointerRefOf: anAtom].

"The block of exact tokens: every reference writes {'@ref': nil}."
PBCodec class >> tokenRef
  ^ [:anAtom | self _tagged: '@ref' body: nil].

PBCodec class >> _pointerRefOf: anAtom
  | ptr |
  ptr := anAtom pointer.
  ptr isNil ifTrue: [
    ^ PBValidationError signal: 'PBCodec: ' , anAtom printString , ' is not saved: it has no pointer to refer to'].
  ^ self _tagged: '@ref' body: { ptr segmentBytes. ptr offset. anAtom tag }.

PBCodec class >> _tagged: aTag body: aBody
  ^ MessagePackMap withAll: { aTag -> aBody }.

PBCodec class >> _wire: v ref: aBlock
  | uuid |
  v isNil ifTrue: [^ v].
  (v == true or: [v == false]) ifTrue: [^ v].
  v isInteger ifTrue: [
    (v between: self _intMin and: self _intMax) ifTrue: [^ v].
    ^ self _tagged: '@int' body: (v printString: 16) asLowercase].
  v isFloat ifTrue: [^ v].
  v isString ifTrue: [^ v].
  (v isKindOf: ByteArray) ifTrue: [^ v].
  (v isKindOf: Decimal) ifTrue: [^ self _tagged: '@dec' body: v printString].
  (v isKindOf: DateTime) ifTrue: [
    ^ self _tagged: '@dt' body: {
      v year. v month. v day. v hour. v minute. v second. v microsecond. v fold.
      v isInstantForm ifTrue: [{ 'instant'. v zone key }] ifFalse: [self _wireZone: v zone] }].
  (v isKindOf: CalendarDate) ifTrue: [^ self _tagged: '@date' body: { v year. v month. v day }].
  (v isKindOf: TimeOfDay) ifTrue: [
    ^ self _tagged: '@time' body: {
      v hour. v minute. v second. v microsecond. v fold. self _wireZone: v zone }].
  (v isKindOf: TimeSpan) ifTrue: [
    ^ self _tagged: '@td' body: { v days. v seconds. v microseconds }].
  uuid := self _uuidClass.
  (uuid notNil and: [v isKindOf: uuid]) ifTrue: [^ self _tagged: '@uuid' body: v bytes].
  v == PBMissing default ifTrue: [^ self _tagged: '@missing' body: 0].
  (v isKindOf: PBMutableObject) ifTrue: [^ self _tagged: '@mut' body: v name].
  (v isKindOf: PBTuple) ifTrue: [
    ^ self _tagged: '@tup' body: (v asArray collect: [:each | self _wire: each ref: aBlock])].
  (v isKindOf: PBFrozenList) ifTrue: [^ v asArray collect: [:each | self _wire: each ref: aBlock]].
  (v isKindOf: PBFrozenDict) ifTrue: [
    ^ self _tagged: '@map' body: (v associations collect: [:each |
      { self _wire: each key ref: aBlock. self _wire: each value ref: aBlock }])].
  (self _isReference: v) ifTrue: [^ aBlock value: v].
  ^ PBUnexpectedError signal: 'PBCodec: no wire form for a canonical ' , v class name.

PBCodec class >> _wireZone: z
  z isNil ifTrue: [^ nil].
  (z isKindOf: ZoneOffset) ifTrue: [^ { 'fixed'. z microseconds. z name }].
  ^ { 'zone'. z key }.

"The msgpack bytes of aValue; references are written as their pointers."
PBCodec class >> encode: aValue
  ^ MessagePack encode: (self toWire: aValue atomRef: self pointerRef).

"=== decoding ================================================================="

"The value aByteArray holds (one value, as it sits in a state map);
 references decode to PBUnresolvedRef. Malformed bytes signal
 PBCorruptionError."
PBCodec class >> decode: aByteArray
  | tree |
  (aByteArray isKindOf: ByteArray) ifFalse: [
    ^ PBValidationError signal: 'PBCodec decode: a ByteArray was expected, not a ' , aByteArray class name].
  tree := [MessagePack decodeOrdered: aByteArray strictKeys: false]
    on: Error do: [:e |
      (e isKindOf: MessageNotUnderstood) ifTrue: [e pass].
      PBCorruptionError signal: 'PBCodec: malformed msgpack: ' , e messageText].
  ^ self fromWire: tree resolver: nil.

"The value of aTree, as MessagePack decodeOrdered:strictKeys: answers it. A
 reference is aResolver refTo: segmentBytes offset: anInteger tag: aTag, or a
 PBUnresolvedRef when aResolver is nil."
PBCodec class >> fromWire: aTree resolver: aResolver
  aTree isNil ifTrue: [^ aTree].
  (aTree == true or: [aTree == false]) ifTrue: [^ aTree].
  aTree isInteger ifTrue: [^ aTree].
  aTree isFloat ifTrue: [^ aTree].
  (aTree isString and: [aTree isSymbol not]) ifTrue: [^ aTree].
  (aTree isKindOf: ByteArray) ifTrue: [^ aTree].
  (aTree isKindOf: Array) ifTrue: [
    ^ PBFrozenList withAll: (aTree collect: [:each | self fromWire: each resolver: aResolver])].
  (aTree isKindOf: MessagePackMap) ifTrue: [^ self _fromTagged: aTree resolver: aResolver].
  (aTree isKindOf: MessagePackExt) ifTrue: [
    ^ PBCorruptionError signal: 'PBCodec: a msgpack ext value (type ' , aTree type printString
      , ') is never a canonical value'].
  ^ PBCorruptionError signal: 'PBCodec: malformed encoded value: ' , (self _preview: aTree).

PBCodec class >> _fromTagged: aMap resolver: aResolver
  | assoc tag body |
  aMap size = 1 ifFalse: [
    ^ PBCorruptionError signal: 'PBCodec: a tagged value is a map with exactly one key, not '
      , aMap size printString , ': ' , (self _preview: aMap)].
  assoc := aMap associations first.
  tag := assoc key.
  body := assoc value.
  (tag isString and: [tag isSymbol not]) ifFalse: [
    ^ PBCorruptionError signal: 'PBCodec: a map key must be a string, not ' , (self _preview: tag)].
  tag = '@int' ifTrue: [^ self _decodeInt: body].
  tag = '@dec' ifTrue: [^ self _decodeDecimal: body].
  tag = '@date' ifTrue: [^ self _decodeDate: body].
  tag = '@time' ifTrue: [^ self _decodeTime: body].
  tag = '@dt' ifTrue: [^ self _decodeDateTime: body].
  tag = '@td' ifTrue: [^ self _decodeTimeSpan: body].
  tag = '@uuid' ifTrue: [^ self _decodeUUID: body].
  tag = '@tup' ifTrue: [
    (body isKindOf: Array) ifFalse: [^ self _corrupt: tag body: body because: 'an array was expected'].
    ^ PBTuple withAll: (body collect: [:each | self fromWire: each resolver: aResolver])].
  tag = '@map' ifTrue: [^ self _decodeMap: body resolver: aResolver].
  tag = '@missing' ifTrue: [
    (body isInteger and: [body = 0]) ifFalse: [^ self _corrupt: tag body: body because: 'the body must be the integer 0'].
    ^ PBMissing default].
  tag = '@ref' ifTrue: [^ self _decodeRef: body resolver: aResolver].
  tag = '@mut' ifTrue: [
    (body isString and: [body notEmpty]) ifFalse: [
      ^ self _corrupt: tag body: body because: 'a non-empty name was expected'].
    ^ PBMutableObject name: body].
  ^ PBCorruptionError signal: 'PBCodec: unknown codec tag ' , (self _preview: tag).

PBCodec class >> _corrupt: aTag body: aBody because: aString
  ^ PBCorruptionError signal: 'PBCodec: malformed ' , aTag , ' value ' , (self _preview: aBody)
    , ': ' , aString.

"aBlock's value; an Error of a value constructor (not a PBDBError, not a
 MessageNotUnderstood) is a malformed body."
PBCodec class >> _build: aBlock tag: aTag body: aBody
  ^ aBlock on: Error do: [:e |
    ((e isKindOf: PBDBError) or: [e isKindOf: MessageNotUnderstood]) ifTrue: [e pass].
    self _corrupt: aTag body: aBody because: e messageText].

PBCodec class >> _preview: anObject
  | text |
  text := [anObject printString] on: Error do: [:e | 'a ' , anObject class name].
  ^ text size <= 80 ifTrue: [text] ifFalse: [(text copyFrom: 1 to: 77) , '...'].

"aBody when it is an Array of n items whose first aCount items are Integers;
 otherwise a corruption."
PBCodec class >> _fields: aBody count: n integers: aCount tag: aTag
  ((aBody isKindOf: Array) and: [aBody size = n]) ifFalse: [
    ^ self _corrupt: aTag body: aBody because: 'an array of ' , n printString , ' items was expected'].
  1 to: aCount do: [:i |
    (aBody at: i) isInteger ifFalse: [
      ^ self _corrupt: aTag body: aBody because: 'item ' , i printString , ' must be an integer']].
  ^ aBody.

PBCodec class >> _decodeInt: aBody
  | value |
  value := self _parseHex: aBody.
  value isNil ifTrue: [^ self _corrupt: '@int' body: aBody because: 'not signed lowercase hexadecimal without leading zeros'].
  (value between: self _intMin and: self _intMax) ifTrue: [
    ^ self _corrupt: '@int' body: aBody because: 'an integer in the native range is never @int'].
  ^ value.

"The Integer of a canonical @int text ('-' then lowercase hexadecimal digits,
 the first not 0), or nil."
PBCodec class >> _parseHex: aText
  | start value |
  (aText isString and: [aText isSymbol not and: [aText notEmpty]]) ifFalse: [^ nil].
  start := aText first = $- ifTrue: [2] ifFalse: [1].
  start > aText size ifTrue: [^ nil].
  (aText at: start) = $0 ifTrue: [^ nil].
  value := 0.
  start to: aText size do: [:i |
    | c |
    c := (aText at: i) asInteger.
    (c between: 48 and: 57)
      ifTrue: [value := value * 16 + (c - 48)]
      ifFalse: [(c between: 97 and: 102)
        ifTrue: [value := value * 16 + (c - 87)]
        ifFalse: [^ nil]]].
  ^ start = 2 ifTrue: [value negated] ifFalse: [value].

PBCodec class >> _decodeDecimal: aBody
  | d |
  (aBody isString and: [aBody isSymbol not]) ifFalse: [
    ^ self _corrupt: '@dec' body: aBody because: 'a string was expected'].
  d := self _build: [Decimal fromString: aBody] tag: '@dec' body: aBody.
  d printString = aBody ifFalse: [
    ^ self _corrupt: '@dec' body: aBody because: 'not the canonical text (the to-scientific-string form)'].
  (self _isDecimalInRange: d) ifFalse: [
    ^ self _corrupt: '@dec' body: aBody because: 'an exponent CPython''s decimal module cannot represent'].
  ^ d.

PBCodec class >> _decodeDate: aBody
  | f |
  f := self _fields: aBody count: 3 integers: 3 tag: '@date'.
  ^ self _build: [CalendarDate year: (f at: 1) month: (f at: 2) day: (f at: 3)] tag: '@date' body: aBody.

"The zone of a tz field: nil, ['fixed', offset, name] or ['zone', key]. The
 instant form is read by _decodeDateTime: itself; in a @time it is malformed."
PBCodec class >> _decodeZone: tz tag: aTag body: aBody
  | kind |
  tz isNil ifTrue: [^ nil].
  ((tz isKindOf: Array) and: [tz notEmpty and: [(tz at: 1) isString]]) ifFalse: [
    ^ self _corrupt: aTag body: aBody because: 'malformed tzinfo'].
  kind := tz at: 1.
  (kind = 'fixed' and: [tz size = 3 and: [(tz at: 2) isInteger and: [(tz at: 3) isString]]]) ifTrue: [
    ^ self _build: [ZoneOffset microseconds: (tz at: 2) name: (tz at: 3)] tag: aTag body: aBody].
  (kind = 'zone' and: [tz size = 2 and: [(tz at: 2) isString]]) ifTrue: [
    ^ self _zoneName: (tz at: 2) tag: aTag body: aBody].
  ^ self _corrupt: aTag body: aBody because: 'malformed tzinfo'.

PBCodec class >> _zoneName: aKey tag: aTag body: aBody
  (self _isKnownZoneKey: aKey) ifFalse: [
    ^ self _corrupt: aTag body: aBody because: 'unknown time zone key ' , aKey printString].
  ^ ZoneName key: aKey.

PBCodec class >> _decodeTime: aBody
  | f zone |
  f := self _fields: aBody count: 6 integers: 5 tag: '@time'.
  zone := self _decodeZone: (f at: 6) tag: '@time' body: aBody.
  ^ self _build: [TimeOfDay hour: (f at: 1) minute: (f at: 2) second: (f at: 3)
      microsecond: (f at: 4) fold: (f at: 5) zone: zone] tag: '@time' body: aBody.

PBCodec class >> _decodeDateTime: aBody
  | f tz fields zone |
  f := self _fields: aBody count: 9 integers: 8 tag: '@dt'.
  tz := f at: 9.
  fields := f copyFrom: 1 to: 7.
  ((tz isKindOf: Array) and: [tz size = 2 and: [(tz at: 1) = 'instant' and: [(tz at: 2) isString]]])
    ifTrue: [
      (f at: 8) = 0 ifFalse: [^ self _corrupt: '@dt' body: aBody because: 'an instant has fold 0'].
      zone := self _zoneName: (tz at: 2) tag: '@dt' body: aBody.
      ^ self _checkInstantBand: (self _build: [DateTime utcFields: fields zoneName: zone]
          tag: '@dt' body: aBody)].
  ((tz isKindOf: Array) and: [tz size = 2 and: [(tz at: 1) = 'zone' and: [(tz at: 2) isString]]])
    ifTrue: [
      zone := self _zoneName: (tz at: 2) tag: '@dt' body: aBody.
      ^ self _build: [PBLegacyZoneDateTime wallClockFields: fields fold: (f at: 8) zoneName: zone]
          tag: '@dt' body: aBody].
  zone := self _decodeZone: tz tag: '@dt' body: aBody.
  ^ self _build: [DateTime year: (f at: 1) month: (f at: 2) day: (f at: 3) hour: (f at: 4)
      minute: (f at: 5) second: (f at: 6) microsecond: (f at: 7) fold: (f at: 8) zone: zone]
    tag: '@dt' body: aBody.

PBCodec class >> _decodeTimeSpan: aBody
  | f |
  f := self _fields: aBody count: 3 integers: 3 tag: '@td'.
  (((f at: 2) between: 0 and: 86399) and: [(f at: 3) between: 0 and: 999999]) ifFalse: [
    ^ self _corrupt: '@td' body: aBody
      because: 'not normalized: 0 <= seconds < 86400 and 0 <= microseconds < 10^6'].
  ^ self _build: [TimeSpan days: (f at: 1) seconds: (f at: 2) microseconds: (f at: 3)]
    tag: '@td' body: aBody.

PBCodec class >> _decodeUUID: aBody
  | uuid |
  ((aBody isKindOf: ByteArray) and: [aBody size = 16]) ifFalse: [
    ^ self _corrupt: '@uuid' body: aBody because: '16 bytes were expected'].
  uuid := self _uuidClass.
  uuid isNil ifTrue: [
    ^ PBNotSupportedError signal: 'PBCodec: the @uuid value ' , (self _preview: aBody)
      , ' needs protoST''s UUID (lib/uuid.st, protoST 0.9.1), which this protoST does not have'].
  ^ uuid fromBytes: aBody.

PBCodec class >> _decodeMap: aBody resolver: aResolver
  | pairs |
  (aBody isKindOf: Array) ifFalse: [^ self _corrupt: '@map' body: aBody because: 'an array was expected'].
  pairs := aBody collect: [:pair |
    | k reason |
    ((pair isKindOf: Array) and: [pair size = 2]) ifFalse: [
      ^ self _corrupt: '@map' body: aBody because: 'each entry is a [key, value] array'].
    k := self fromWire: (pair at: 1) resolver: aResolver.
    reason := self _unkeyableReason: k legacyAllowed: true.
    reason isNil ifFalse: [^ self _corrupt: '@map' body: aBody because: reason].
    k -> (self fromWire: (pair at: 2) resolver: aResolver)].
  ^ [PBFrozenDict withAssociations: pairs] on: PBValidationError do: [:e |
    self _corrupt: '@map' body: aBody because: e messageText].

PBCodec class >> _decodeRef: aBody resolver: aResolver
  | f segment offset tag bytes |
  f := self _fields: aBody count: 3 integers: 0 tag: '@ref'.
  segment := f at: 1.
  offset := f at: 2.
  tag := f at: 3.
  bytes := ((segment isKindOf: ByteArray) and: [segment size = 16])
    ifTrue: [segment]
    ifFalse: [self _segmentFromHex: segment].
  bytes isNil ifTrue: [
    ^ self _corrupt: '@ref' body: aBody because: 'the segment is 16 bytes (or, in format 2, 32 hexadecimal digits)'].
  (offset isInteger and: [offset >= 0]) ifFalse: [
    ^ self _corrupt: '@ref' body: aBody because: 'the offset is an integer >= 0'].
  ((tag isInteger and: [tag between: 0 and: self _builtinAliasCount - 1])
      or: [tag isString and: [tag notEmpty]]) ifFalse: [
    ^ self _corrupt: '@ref' body: aBody because: 'the type tag is an alias of the table or a type name'].
  aResolver isNil ifTrue: [
    ^ PBUnresolvedRef pointer: (PBAtomPointer segment: bytes offset: offset) tag: tag].
  ^ aResolver refTo: bytes offset: offset tag: tag.

"The 16 bytes of a format-2 segment written as 32 hexadecimal digits, or nil."
PBCodec class >> _segmentFromHex: aText
  | bytes |
  ((aText isString and: [aText isSymbol not]) and: [aText size = 32]) ifFalse: [^ nil].
  bytes := (1 to: 16) asArray collect: [:i |
    | hi lo |
    hi := self _hexDigit: (aText at: 2 * i - 1).
    lo := self _hexDigit: (aText at: 2 * i).
    (hi isNil or: [lo isNil]) ifTrue: [^ nil].
    hi * 16 + lo].
  ^ ByteArray withAll: bytes.

PBCodec class >> _hexDigit: aCharacter
  | c |
  c := aCharacter asInteger.
  (c between: 48 and: 57) ifTrue: [^ c - 48].
  (c between: 97 and: 102) ifTrue: [^ c - 87].
  (c between: 65 and: 70) ifTrue: [^ c - 55].
  ^ nil.
