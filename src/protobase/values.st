"-- values.st: the value classes of protoBaseST --

The containers and handles of ProtoBase's canonical values (format spec,
'Canonical values'), with PB in place of Proto:

  PBFrozenList     ProtoBase FrozenList: the list kind (a msgpack array)
  PBTuple          a Python tuple: the tuple kind (@tup)
  PBFrozenDict     ProtoBase FrozenDict: the map kind (@map), insertion order kept
  PBMissing        ProtoBase MISSING (@missing), a singleton: PBMissing default
  PBMutableObject  ProtoBase MutableObject (@mut), the handle part: name: and name
  PBAtomPointer    ProtoBase AtomPointer: 16 segment bytes and an offset
  PBUnresolvedRef  a @ref decoded without a resolver; it encodes back to the @ref,
                   with the type in its canonical spelling

Every value is immutable (Spec decision 3): a class-side constructor copies its
arguments and calls a private initialiser once; no other method assigns an
instance variable, and no accessor answers internal state that a caller could
change (associations and asArray answer fresh copies). The constructors are
shallow: PBCodec canonical: is what freezes a whole tree.

Keys. A PBFrozenDict's keys follow the map-key rule of the format (keys.st,
PBMapKeyIndex): true, 1, 1.0 and Decimal 1.00 are one key, so a map holding
two of them is refused, and a lookup by any of them finds the one it holds.
Items of a list or tuple, and the values of a map, still compare with
protoST's = within one class (_PBItems same:as:). hash is deliberately cheap
and safe (it never hashes an item, so a Decimal of untrusted input is never
hashed): the size and the class.

This module also gives every DateTime isLegacyZone (false), and defines
PBLegacyZoneDateTime, the format-3 ['zone', key] datetime (Spec 4.3)."

Import from: 'protobase/errors'.
Import from: 'protobase/keys'.
Import from: 'calendar'.

"=== item equality ========================================================="

"Item equality of the containers' items and of a map's values: identity, else
 the same class and =. A NaN is never = to itself, but one NaN object is the
 same item as itself. A format-3 zone datetime against another DateTime is
 decided by its own =, which signals PBNotSupportedError whenever the answer
 needs the zone's offsets (never an assumed 'not equal'). Map keys follow the
 map-key rule instead (keys.st)."
Object subclass: #_PBItems.

_PBItems class >> same: a as: b
  a == b ifTrue: [^ true].
  (a isClassObject or: [b isClassObject]) ifTrue: [^ false].
  ((a isKindOf: DateTime) and: [b isKindOf: DateTime]) ifTrue: [
    a isLegacyZone ifTrue: [^ a = b].
    b isLegacyZone ifTrue: [^ b = a]].
  a class == b class ifFalse: [^ false].
  ^ a = b.

"The most a fixed offset or a zone's offset moves a wall clock from its
 instant (|offset| < 24 h, format spec 'Canonical values')."
_PBItems class >> offsetWindow
  ^ PBKeys offsetWindow.

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
  (anObject isClassObject not and: [anObject class == self class]) ifFalse: [^ false].
  anObject size = items size ifFalse: [^ false].
  1 to: items size do: [:i | (_PBItems same: (items at: i) as: (anObject at: i)) ifFalse: [^ false]].
  ^ true.

_PBSequence >> hash
  ^ (self class name hash bitXor: items size) \\ 1073741824.

_PBSequence >> printOn: aStream
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

"A tuple holding anArray itself, not a copy (withAll: copies): the private
 constructor for a caller that made anArray fresh, a brace for instance, and
 never touches it again."
PBTuple class >> _trustedOn: anArray
  ^ self basicNew _setItems: anArray.

"=== PBFrozenDict ============================================================"

"ProtoBase FrozenDict: the map kind (@map). Insertion order is kept and is
 part of the value's bytes; = ignores it, as Python's dict equality does."
Object subclass: #PBFrozenDict instanceVariableNames: 'keys values index'.

"anArray holds Associations, in insertion order. Two keys that conflict under
 the map-key rule (keys.st, PBMapKeyIndex: true, 1, 1.0 and Decimal 1.00 are
 one key; one object twice) signal PBValidationError (a map is never
 collapsed); keys whose conflicts need a time-zone database signal
 PBNotSupportedError. Two NaN objects are two keys (a reader keeps format-3
 NaN keys); PBCodec refuses them when it writes the map."
PBFrozenDict class >> withAssociations: anArray
  | ks vs |
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
  ^ self basicNew _setKeys: ks values: vs index: (PBMapKeyIndex on: ks).

"A map of the keys aKeyArray, filed by aPBMapKeyIndex (PBMapKeyIndex on:
 aKeyArray, which the caller built once and shares between maps of the same
 keys: both are never changed), and the values aValueArray, in order."
PBFrozenDict class >> _keys: aKeyArray index: aPBMapKeyIndex values: aValueArray
  aKeyArray size = aValueArray size ifFalse: [
    ^ PBValidationError signal: 'PBFrozenDict: ' , aKeyArray size printString , ' keys and '
      , aValueArray size printString , ' values'].
  ^ self basicNew _setKeys: aKeyArray values: aValueArray index: aPBMapKeyIndex.

PBFrozenDict >> _setKeys: aKeyArray values: aValueArray index: aPBMapKeyIndex
  "Runs once, on a fresh instance."
  keys isNil ifFalse: [^ PBUserError signal: 'PBFrozenDict is immutable'].
  keys := aKeyArray.
  values := aValueArray.
  index := aPBMapKeyIndex.
  ^ self.

"A map of the receiver's keys (and their index) with the values anArray, in
 order."
PBFrozenDict >> _withValues: anArray
  ^ self class _keys: keys index: index values: anArray.

PBFrozenDict >> size
  ^ keys size.

PBFrozenDict >> isEmpty
  ^ keys isEmpty.

PBFrozenDict >> notEmpty
  ^ keys notEmpty.

"The position of aKey under the map-key rule (1.0 finds the key 1), or 0."
PBFrozenDict >> _indexOfKey: aKey
  ^ index indexOf: aKey.

"The value at aKey; an absent key signals KeyNotFound."
PBFrozenDict >> at: aKey
  ^ self at: aKey ifAbsent: [
    KeyNotFound signal: 'PBFrozenDict>>at: key not found: ' , aKey printString].

PBFrozenDict >> at: aKey ifAbsent: aBlock
  | i |
  i := self _indexOfKey: aKey.
  i = 0 ifTrue: [^ aBlock value].
  ^ values at: i.

"The value at position anIndex (1-based, from _indexOfKey:)."
PBFrozenDict >> _valueAt: anIndex
  ^ values at: anIndex.

"The values Array itself when the keys are anArray's elements, in order (the
 identical Array or an equal one), else nil. For the record shapes
 (_PBRecordShape), which keep it as a record's slots: never to be changed."
PBFrozenDict >> _valuesIfKeys: anArray
  keys == anArray ifTrue: [^ values].
  keys = anArray ifTrue: [^ values].
  ^ nil.

"Whether the keys are anArray itself (a state built on a shared key Array)."
PBFrozenDict >> _hasKeys: anArray
  ^ keys == anArray.

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
  (anObject isClassObject not and: [anObject class == PBFrozenDict]) ifFalse: [^ false].
  anObject size = keys size ifFalse: [^ false].
  1 to: keys size do: [:i |
    | other |
    other := anObject at: (keys at: i) ifAbsent: [^ false].
    (_PBItems same: (values at: i) as: other) ifFalse: [^ false]].
  ^ true.

PBFrozenDict >> hash
  ^ ('PBFrozenDict' hash bitXor: keys size) \\ 1073741824.

PBFrozenDict >> printOn: aStream
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
  aStream nextPutAll: 'PBMissing default'.

PBMissing _initializeDefault.

"=== PBMutableObject ========================================================="

"ProtoBase MutableObject, the value part: a handle naming a cell of the
 database's mutable table (@mut). get: and set:value: are in transactions.st."
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

"The cell name."
PBMutableObject >> name
  ^ cellName.

PBMutableObject >> = anObject
  ^ (anObject isClassObject not and: [anObject class == PBMutableObject])
    and: [cellName = anObject name].

PBMutableObject >> hash
  ^ cellName hash.

PBMutableObject >> printOn: aStream
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
  ^ (anObject isClassObject not and: [anObject class == PBAtomPointer])
    and: [offset = anObject offset and: [segmentBytes = anObject segmentBytes]].

PBAtomPointer >> hash
  ^ (segmentBytes hash bitXor: offset hash) \\ 1073741824.

"The pointer as ProtoBase prints it (the repr of its AtomPointer dataclass),
 for the messages that quote it word for word:
 AtomPointer(segment=UUID('00010203-0405-0607-0809-0a0b0c0d0e0f'), offset=26)."
PBAtomPointer >> pythonText
  | h |
  h := self segmentHex.
  ^ 'AtomPointer(segment=UUID(''' , (h copyFrom: 1 to: 8) , '-' , (h copyFrom: 9 to: 12) , '-'
    , (h copyFrom: 13 to: 16) , '-' , (h copyFrom: 17 to: 20) , '-' , (h copyFrom: 21 to: 32)
    , '''), offset=' , offset printString , ')'.

PBAtomPointer >> printOn: aStream
  aStream nextPutAll: 'PBAtomPointer('; nextPutAll: self segmentHex;
    nextPutAll: ', '; print: offset; nextPut: $).

"=== PBUnresolvedRef ========================================================="

"A @ref decoded with no resolver: the pointer and the type tag as read (an
 alias Integer or a type name). It encodes back to the same @ref, with the type
 in its canonical spelling (PBCodec, PBTypeRegistry writerTag:)."
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

"PBUnresolvedRef >> = is defined in registry.st: two references are equal by
 pointer and by the type their tags name, which needs the alias table."

PBUnresolvedRef >> hash
  ^ pointer hash.

PBUnresolvedRef >> printOn: aStream
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
  ^ self _unsupported: 'hash'.

PBLegacyZoneDateTime >> _orderWith: anObject
  ^ self _unsupported: 'order'.

"Python's rule without a database: a value in the same zone compares by its
 wall clock (fold ignored); a naive DateTime or another object is never
 equal; an aware value whose instant is more than 24 h from this wall clock
 (48 h for a format-3 value of another zone) is never equal; any other aware
 value needs the zone's offsets and signals."
PBLegacyZoneDateTime >> = anObject
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
  aStream nextPutAll: (DateTime _fieldsText: { self year. self month. self day. self hour. self minute. self second. self microsecond });
    nextPut: $[; nextPutAll: self zone key; nextPut: $].
