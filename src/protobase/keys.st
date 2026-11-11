"-- keys.st: order keys, hash keys, exact tokens and the map-key rule --

The functions of the value model that keyed structures place their keys by
(ProtoBase format spec v2.0.0rc1, 'Order, equality and hashing' and 'Map
keys'; ProtoBase proto_db/values.py):

  PBKeys orderKey: aValue          a PBOrderKey (rank, payload); a NaN, a list,
                                   a map, or a tuple holding one: PBValidationError
  PBKeys compare: a with: b        -1, 0 or 1, by order key
  PBKeys isOrderable: aValue       whether orderKey: accepts aValue
  PBKeys hashKey: aValue           the signed 64-bit BLAKE2b-8 of feed(rank, payload)
  PBKeys exactToken: aValue        the canonical msgpack bytes, every atom {'@ref': nil}
  PBKeys checkMapKeys: aDict       the writer's map-key rule (PBValidationError)
  PBKeys checkMapKeys: keys reading: aBoolean
                                   the writer's or the reader's rule over an Array of keys

aValue is a canonical value, as PBCodec canonical: or decode: answers it: a
host object outside the format (a Fraction, a Symbol, an Array) is refused.

Ranks: 0 missing, 1 nil, 2 bool, 3 number, 4 str, 5 bytes, 6 date, 7 naive
time and time in an IANA zone, 8 fixed-offset time, 9 naive datetime, 10
aware datetime, 11 timedelta, 12 uuid, 13 tuple, 14 atom, 15 mutable handle.

The payload of rank 3 is an Integer or a Fraction (a float's exact value), a
finite Decimal, or PBOrderKey negInf / posInf. A decimal stays a Decimal: its exact
value may be a power of ten too large to build (an untrusted 1E+999999999), so
it is compared by Decimal's own exact comparison, which never expands a large
exponent, and hashed through its residue modulo 2^61 - 1, derived from
protoST's numeric hash (CPython's, R3), which takes the power of ten modulo
2^61 - 1 (residue:). A naive and an aware datetime are ranks 9 and 10, never compared
with < between them; aware instants come from utcOrdinalMicroseconds.

Map keys. Each key has a map-key id: its order key with every bool read as the
number 0 or 1 (true, 1, 1.0 and Decimal 1.00 are one key). Two keys of one map
conflict when their ids are equal: keys are bucketed in a Dictionary by id, in
linear time, never compared pairwise. A NaN key is identified by its exact
token when written (two NaNs of one encoding conflict) and by its identity when
read (format 3 kept such keys as two; a tuple holding a NaN is identified by
its items, the NaN by identity, as Python's tuple equality). A format-3 zone
datetime (PBLegacyZoneDateTime) can be read as a key: it is identified by its
zone and wall clock, and keys whose conflict would need the zone's offsets
signal PBNotSupportedError (checkDecidableKeys:, design 4.3). PBMapKeyIndex is
the index of a PBFrozenDict: its construction is the reader's rule, its
lookups the same ids.

Atoms. An atom is identified by its oid, as ProtoBase's map_key_ids and
Atom.__eq__ do: a stub loads its record to read it, so a map holding
references to two records of one oid is refused, and an atom's key does not
change when it is saved. An atom that is not stored draws its oid in memory
on first need (ProtoBase D21), so it is a key like any other. A PBUnresolvedRef
(decoded without a resolver) has no known oid: as a map key it is identified
by its pointer, a weaker rule than the format's (two references to two records
of one oid are two keys there), and it has no order key.

This module needs no other protoBaseST module when it loads: the value classes
(values.st, which imports it) and PBCodec are looked up when a method runs."

Import from: 'protobase/errors'.
Import from: 'decimal'.
Import from: 'calendar'.
Import from: 'uuid'.

"=== PBOrderKey ==============================================================="

"An order key: a rank (0 to 15) and a payload of that rank. Keys compare by
 rank, then by payload; = and hash agree, and hash never hashes a Decimal."
Object subclass: #PBOrderKey instanceVariableNames: 'rank payload' classVariableNames: 'PosInf NegInf'.

"The rank-3 payloads of the two infinities, made once when the module loads:
 private objects compared with ==, never Symbols (a short Symbol is the equal
 String in protoST, STATUS D35, so a Symbol mark was neither a Symbol nor a
 number to the code that tested it, and an infinite key could not be hashed)."
PBOrderKey class >> _initializeInfinities
  PosInf isNil ifTrue: [PosInf := Object new].
  NegInf isNil ifTrue: [NegInf := Object new].

PBOrderKey class >> posInf
  ^ PosInf.

PBOrderKey class >> negInf
  ^ NegInf.

PBOrderKey class >> rank: anInteger payload: anObject
  ((anInteger isInteger) and: [anInteger between: 0 and: 15]) ifFalse: [
    ^ PBValidationError signal: 'PBOrderKey: a rank from 0 to 15 was expected, not ' , anInteger printString].
  ^ self basicNew _setRank: anInteger payload: anObject.

PBOrderKey >> _setRank: anInteger payload: anObject
  "Runs once, on a fresh instance."
  rank isNil ifFalse: [^ PBUserError signal: 'PBOrderKey is immutable'].
  rank := anInteger.
  payload := anObject.
  ^ self.

PBOrderKey >> rank
  ^ rank.

"The payload (a tuple's is a fresh Array of the items' order keys)."
PBOrderKey >> payload
  ^ rank = 13 ifTrue: [payload copy] ifFalse: [payload].

PBOrderKey >> _payload
  ^ payload.

"-1, 0 or 1."
PBOrderKey >> compareWith: other
  rank = other rank ifFalse: [^ rank < other rank ifTrue: [-1] ifFalse: [1]].
  ^ PBKeys _comparePayload: payload with: other _payload rank: rank.

PBOrderKey >> < other
  ^ (self compareWith: other) < 0.

PBOrderKey >> <= other
  ^ (self compareWith: other) <= 0.

PBOrderKey >> > other
  ^ (self compareWith: other) > 0.

PBOrderKey >> >= other
  ^ (self compareWith: other) >= 0.

PBOrderKey >> = anObject
  (anObject isClassObject not and: [anObject class == PBOrderKey]) ifFalse: [^ false].
  ^ (self compareWith: anObject) = 0.

"Equal keys have equal hashes: a number hashes by its residue modulo 2^61 - 1,
 so 1, 1.0 and Decimal 1.00 agree, and a huge decimal costs a modular power."
PBOrderKey >> hash
  | h |
  rank = 3 ifTrue: [
    h := payload == PosInf ifTrue: [314159] ifFalse: [
      payload == NegInf ifTrue: [314158] ifFalse: [PBKeys residue: payload]].
    ^ (h bitXor: rank) \\ 1073741824].
  rank = 13 ifTrue: [
    h := payload size.
    payload do: [:each | h := (h * 31 + each hash) \\ 1073741824].
    ^ (h bitXor: rank) \\ 1073741824].
  ^ (payload hash bitXor: rank) \\ 1073741824.

PBOrderKey >> printOn: aStream
  aStream nextPutAll: 'PBOrderKey('; print: rank; nextPutAll: ', '; print: payload; nextPut: $).

"=== PBKeys ==================================================================="

PBOrderKey _initializeInfinities.

Object subclass: #PBKeys.

"The modulus of the numeric hash, the Mersenne prime 2^61 - 1."
PBKeys class >> modulus
  ^ 2305843009213693951.

"=== order keys ==============================================================="

"The order key of aValue (FS 'Order keys'). A NaN, a list, a map, a tuple
 holding one, or an object outside the format signals PBValidationError; a
 format-3 zone datetime, or a reference decoded without a resolver (its oid
 is unknown), signals PBNotSupportedError."
PBKeys class >> orderKey: aValue
  ^ self _orderKey: aValue.

PBKeys class >> compare: a with: b
  ^ (self orderKey: a) compareWith: (self orderKey: b).

"True when orderKey: accepts aValue, false when it signals PBValidationError
 (PBNotSupportedError passes: whether a format-3 zone datetime orders is not
 known without its zone's rules)."
PBKeys class >> isOrderable: aValue
  ^ [self orderKey: aValue. true] on: PBValidationError do: [:e | e return: false].

PBKeys class >> _key: aRank payload: aPayload
  ^ PBOrderKey rank: aRank payload: aPayload.

PBKeys class >> _refuse: aValue because: aString
  ^ PBValidationError signal: 'PBKeys: ' , aString , ': ' , (self _preview: aValue).

PBKeys class >> _preview: anObject
  | text |
  text := [anObject printString] on: Error do: [:e | e return: 'a ' , anObject class name].
  ^ text size <= 80 ifTrue: [text] ifFalse: [(text copyFrom: 1 to: 77) , '...'].

PBKeys class >> _orderKey: v
  v isNil ifTrue: [^ self _key: 1 payload: 0].
  v == false ifTrue: [^ self _key: 2 payload: 0].
  v == true ifTrue: [^ self _key: 2 payload: 1].
  v isClassObject ifTrue: [^ self _refuse: v because: 'a class is not a value'].
  v isInteger ifTrue: [^ self _key: 3 payload: v].
  v isFloat ifTrue: [
    v isNaN ifTrue: [^ self _refuse: v because: 'a NaN cannot be used as a key'].
    v isInfinite ifTrue: [^ self _key: 3 payload: (v > 0 ifTrue: [PBOrderKey posInf] ifFalse: [PBOrderKey negInf])].
    ^ self _key: 3 payload: v asExactFraction].
  (v isKindOf: Decimal) ifTrue: [
    v isNaN ifTrue: [^ self _refuse: v because: 'a NaN cannot be used as a key'].
    v isInfinite ifTrue: [^ self _key: 3 payload: (v sign = 0 ifTrue: [PBOrderKey posInf] ifFalse: [PBOrderKey negInf])].
    ^ self _key: 3 payload: v].
  v isSymbol ifTrue: [^ self _refuse: v because: 'a Symbol is not a value of format 4 (the @sym kind is reserved)'].
  v isString ifTrue: [^ self _key: 4 payload: v].
  (v isKindOf: ByteArray) ifTrue: [^ self _key: 5 payload: v].
  (v isKindOf: DateTime) ifTrue: [
    v isLegacyZone ifTrue: [^ v _unsupported: 'order key'].
    v isNaive ifTrue: [^ self _key: 9 payload: v localOrdinalMicroseconds].
    ^ self _key: 10 payload: v utcOrdinalMicroseconds].
  (v isKindOf: CalendarDate) ifTrue: [^ self _key: 6 payload: v ordinal].
  (v isKindOf: TimeOfDay) ifTrue: [
    v _offset isNil ifTrue: [^ self _key: 7 payload: v microsecondsSinceMidnight].
    ^ self _key: 8 payload: v microsecondsSinceMidnight - v _offset].
  (v isKindOf: TimeSpan) ifTrue: [^ self _key: 11 payload: v totalMicroseconds].
  v == PBMissing default ifTrue: [^ self _key: 0 payload: 0].
  (v isKindOf: UUID) ifTrue: [^ self _key: 12 payload: (self _unsignedBigEndian: (PBCodec _uuidBytes: v))].
  (v isKindOf: PBTuple) ifTrue: [^ self _key: 13 payload: (v asArray collect: [:each | self _orderKey: each])].
  (v isKindOf: PBMutableObject) ifTrue: [^ self _key: 15 payload: v name].
  (v isKindOf: PBAtom) ifTrue: [^ self _key: 14 payload: (self _unsignedBigEndian: (self _oidBytes: (self _oidOf: v)))].
  (v isKindOf: PBUnresolvedRef) ifTrue: [
    ^ PBNotSupportedError signal: 'PBKeys: ' , v printString
      , ' was decoded without a resolver: its oid, which is its order key, is not known'].
  ((v isKindOf: PBFrozenList) or: [(v isKindOf: Array) or: [v isKindOf: OrderedCollection]]) ifTrue: [
    ^ self _refuse: v because: 'a list is not an orderable key'].
  ((v isKindOf: PBFrozenDict) or: [v isKindOf: Dictionary]) ifTrue: [
    ^ self _refuse: v because: 'a map is not an orderable key'].
  ^ self _refuse: v because: 'a ' , v class name , ' is not a value of format 4'.

"The oid of anAtom: its record's (a stub loads it), or, for an atom that is
 not stored, the one it draws on first need (PBAtom >> oid, ProtoBase D21)."
PBKeys class >> _oidOf: anAtom
  ^ anAtom oid.

PBKeys class >> _oidBytes: anOid
  (anOid isKindOf: ByteArray) ifTrue: [^ anOid].
  ^ anOid bytes.

PBKeys class >> _unsignedBigEndian: aByteArray
  | n |
  n := 0.
  aByteArray do: [:b | n := n * 256 + b].
  ^ n.

"Payloads of one rank."
PBKeys class >> _comparePayload: a with: b rank: aRank
  aRank = 3 ifTrue: [^ self _compareNumber: a with: b].
  (aRank = 4 or: [aRank = 15]) ifTrue: [^ self _compareString: a with: b].
  aRank = 5 ifTrue: [^ self _compareBytes: a with: b].
  aRank = 13 ifTrue: [^ self _compareTuple: a with: b].
  a = b ifTrue: [^ 0].
  ^ a < b ifTrue: [-1] ifFalse: [1].

"Exact: an Integer, a Fraction, a finite Decimal; the infinities at the ends.
 A Decimal is compared from its own side (Decimal _orderWith:), which never
 expands a large exponent."
PBKeys class >> _compareNumber: a with: b
  a == b ifTrue: [^ 0].
  a == PBOrderKey negInf ifTrue: [^ -1].
  b == PBOrderKey negInf ifTrue: [^ 1].
  a == PBOrderKey posInf ifTrue: [^ 1].
  b == PBOrderKey posInf ifTrue: [^ -1].
  (a isKindOf: Decimal) ifTrue: [^ a _orderWith: b].
  (b isKindOf: Decimal) ifTrue: [^ (b _orderWith: a) negated].
  a = b ifTrue: [^ 0].
  ^ a < b ifTrue: [-1] ifFalse: [1].

"Code point order."
PBKeys class >> _compareString: a with: b
  | n |
  n := a size min: b size.
  1 to: n do: [:i |
    | x y |
    x := (a at: i) asInteger.
    y := (b at: i) asInteger.
    x = y ifFalse: [^ x < y ifTrue: [-1] ifFalse: [1]]].
  ^ (a size - b size) sign.

"Unsigned lexicographic order."
PBKeys class >> _compareBytes: a with: b
  | n |
  n := a size min: b size.
  1 to: n do: [:i |
    | x y |
    x := a at: i.
    y := b at: i.
    x = y ifFalse: [^ x < y ifTrue: [-1] ifFalse: [1]]].
  ^ (a size - b size) sign.

"Lexicographic over the items' order keys; a shorter prefix orders first."
PBKeys class >> _compareTuple: a with: b
  | n |
  n := a size min: b size.
  1 to: n do: [:i |
    | c |
    c := (a at: i) compareWith: (b at: i).
    c = 0 ifFalse: [^ c]].
  ^ (a size - b size) sign.

"=== hash keys ================================================================"

"The hash key of aValue (FS 'Hash keys'): BLAKE2b with an 8-byte digest over
 feed(rank, payload), read as a signed little-endian 64-bit Integer. Equal
 keys have equal hashes; an unorderable value signals as orderKey: does."
PBKeys class >> hashKey: aValue
  | digest u |
  digest := (self feed: (self orderKey: aValue)) blake2b: 8.
  u := 0.
  8 to: 1 by: -1 do: [:i | u := u * 256 + (digest at: i)].
  u >= (1 bitShift: 63) ifTrue: [u := u - (1 bitShift: 64)].
  ^ u.

"The bytes the hash of anOrderKey is computed over."
PBKeys class >> feed: anOrderKey
  | w |
  w := WriteStream on: ByteArray new.
  self _feed: anOrderKey on: w.
  ^ w bytesContents.

PBKeys class >> _feed: aKey on: w
  | rank payload |
  rank := aKey rank.
  payload := aKey _payload.
  w putByte: rank.
  rank = 3 ifTrue: [
    payload == PBOrderKey posInf ifTrue: [^ w putBytes: '+inf' utf8Encoded].
    payload == PBOrderKey negInf ifTrue: [^ w putBytes: '-inf' utf8Encoded].
    ^ w nextPutUnsigned: (self residue: payload) width: 8 bigEndian: false].
  rank = 13 ifTrue: [
    w nextPutUnsigned: payload size width: 8 bigEndian: false.
    payload do: [:each | self _feed: each on: w].
    ^ self].
  (rank = 4 or: [rank = 15]) ifTrue: [^ self _feedData: payload utf8Encoded on: w].
  rank = 5 ifTrue: [^ self _feedData: payload on: w].
  ^ self _feedData: (self signedBytes: payload) on: w.

PBKeys class >> _feedData: aByteArray on: w
  w nextPutUnsigned: aByteArray size width: 8 bigEndian: false.
  aByteArray isEmpty ifFalse: [
    w putBytes: (aByteArray class == ByteArray ifTrue: [aByteArray] ifFalse: [ByteArray withAll: aByteArray asArray])].

"The number of bits of |anInteger| without its leading zeros (Python's
 int.bit_length): 0 for 0, 1 for -1, 8 for -128. Never highBit of a negative."
PBKeys class >> bitLength: anInteger
  ^ anInteger abs highBit.

"anInteger in two's complement, little-endian, in bitLength // 8 + 1 bytes:
 0 is 00, 255 is ff 00, -1 is ff, -128 is 80 ff."
PBKeys class >> signedBytes: anInteger
  | n u |
  n := (self bitLength: anInteger) // 8 + 1.
  u := anInteger < 0 ifTrue: [anInteger + (1 bitShift: 8 * n)] ifFalse: [anInteger].
  ^ ByteArray withAll: ((0 to: n - 1) asArray collect: [:i | (u bitShift: -8 * i) bitAnd: 255]).

"The residue modulo P = 2^61 - 1 of an exact number, in 0 .. P - 1 (FS 'Hash
 keys'). An Integer is n mod P. A Fraction or a finite Decimal goes through
 protoST's native numeric hash, which is CPython's (R3): sign * (|x| mod P),
 the power of ten taken modulo P, so no power of ten is ever built, -1
 becoming -2. Modulo P that is x mod P, the residue ProtoBase computes
 (proto_db/values.py _number_residue), except where -1 became -2: a hash of
 -2 is that of a negative number, told apart by the hash of its magnitude
 (1 when x = -1 mod P, 2 when x = -2 mod P). A Fraction whose denominator
 is a multiple of P has no inverse modulo P (CPython hashes it as infinity,
 314159) and is PBValidationError: ProtoBase has no such value (a float's
 denominator is a power of two, and format 4 has no fractions), so it
 defines no residue for it."
PBKeys class >> residue: aNumber
  | p h |
  p := self modulus.
  aNumber isInteger ifTrue: [^ aNumber \\ p].
  ((aNumber isKindOf: Fraction) and: [aNumber denominator \\ p = 0]) ifTrue: [
    ^ PBValidationError signal: 'PBKeys residue: the denominator of ' , (self _preview: aNumber)
      , ' is a multiple of 2^61 - 1, so the number has no residue modulo it'].
  ((aNumber isKindOf: Fraction) or: [(aNumber isKindOf: Decimal) and: [aNumber isFinite]]) ifTrue: [
    h := aNumber hash.
    h = -2 ifTrue: [
      | magnitude |
      magnitude := (aNumber isKindOf: Fraction)
        ifTrue: [aNumber abs]
        ifFalse: [Decimal sign: 0 coefficient: aNumber coefficient exponent: aNumber exponent].
      ^ magnitude hash = 1 ifTrue: [p - 1] ifFalse: [p - 2]].
    ^ h \\ p].
  ^ PBValidationError signal: 'PBKeys residue: an Integer, a Fraction or a finite Decimal was expected, not '
    , (self _preview: aNumber).

"=== exact tokens ============================================================="

"The exact token of aValue (FS 'Exact tokens'): the msgpack bytes of its
 canonical encoding, with every atom, at any depth, written {'@ref': nil}.
 An atom's token is the 7 bytes 81 a4 40 72 65 66 c0."
PBKeys class >> exactToken: aValue
  ^ MessagePack encode: (PBCodec toWire: aValue atomRef: PBCodec tokenRef).

"=== map keys ================================================================="

"The writer's rule over the keys of aPBFrozenDict (PBValidationError)."
PBKeys class >> checkMapKeys: aPBFrozenDict
  ^ self checkMapKeys: aPBFrozenDict keys reading: false.

"The map-key rule over anArray of keys (FS 'Map keys'). A writer (aBoolean
 false) refuses a key that can never be a map key (a list, a map, a
 signaling NaN, a datetime in an IANA zone, a tuple holding one) and two keys
 that conflict, NaNs of one encoding included. A reader (true) is the rule a
 PBFrozenDict is built under (PBMapKeyIndex): NaN keys are distinct and
 format-3 zone datetimes are accepted. Both signal PBValidationError; a
 conflict that needs a zone's offsets signals PBNotSupportedError."
PBKeys class >> checkMapKeys: anArray reading: aBoolean
  | ids |
  aBoolean ifTrue: [PBMapKeyIndex on: anArray asArray. ^ self].
  ids := Dictionary new.
  anArray do: [:k |
    | id |
    id := self _keyId: k mode: #write.
    (ids includesKey: id) ifTrue: [
      ^ PBValidationError signal: 'PBCodec: the map keys ' , (self _preview: (ids at: id)) , ' and '
        , (self _preview: k) , ' conflict (format spec, ''Map keys'')'].
    ids at: id put: k].

"The map-key id of k. aMode is:
   #write  the writer's rule: a key that can never be a map key signals
           PBValidationError; a NaN is identified by its exact token
   #read   the reader's rule, and lookups: a NaN is its identity
           (PBIdentityKey); a format-3 zone datetime is its zone and wall
           clock; an object outside the format (a Symbol, a Fraction) is kept
           apart by its own =
   #coarse as #read, but every aware or format-3 datetime is one id: keys
           equal everywhere except at datetime positions share an id
           (checkDecidableKeys:)."
PBKeys class >> _keyId: k mode: aMode
  | reason |
  k isClassObject ifTrue: [^ { 'other'. k }].
  aMode == #write ifTrue: [
    reason := self _unkeyableReason: k legacyAllowed: false.
    reason isNil ifFalse: [^ PBValidationError signal: 'PBCodec: ' , reason]].
  k == true ifTrue: [^ self _key: 3 payload: 1].
  k == false ifTrue: [^ self _key: 3 payload: 0].
  ((k isFloat or: [k isKindOf: Decimal]) and: [k isNaN]) ifTrue: [
    ^ aMode == #write ifTrue: [{ 'nan'. self exactToken: k }] ifFalse: [PBIdentityKey on: k]].
  (k isKindOf: DateTime) ifTrue: [
    (aMode == #coarse and: [k isNaive not]) ifTrue: [^ #('zoned')].
    k isLegacyZone ifTrue: [^ { 'format-3'. k zone key. k localOrdinalMicroseconds }]].
  (k isKindOf: PBTuple) ifTrue: [
    | ids |
    ids := k asArray collect: [:each | self _keyId: each mode: aMode].
    ^ { 'tuple' } , ids].
  "An atom is its oid (its order key, through the next lines); a reference
   decoded without a resolver, whose oid is unknown, its pointer."
  (k isKindOf: PBUnresolvedRef) ifTrue: [^ { 'pointer'. k pointer }].
  aMode == #write ifTrue: [^ self _orderKey: k].
  ^ [self _orderKey: k] on: PBValidationError do: [:e | e return: { 'other'. k }].

"Why k can never be a map key (FS 'Map keys'), or nil. With aBoolean true (a
 reader), a format-3 zone datetime is accepted: format 3 wrote such keys. An
 Array or OrderedCollection is a list (PBCodec canonical: makes it one), a
 Dictionary a map."
PBKeys class >> _unkeyableReason: k legacyAllowed: aBoolean
  k isClassObject ifTrue: [^ nil].
  ((k isKindOf: PBFrozenList) or: [(k isKindOf: Array) or: [k isKindOf: OrderedCollection]]) ifTrue: [
    ^ 'a list cannot be a map key'].
  ((k isKindOf: PBFrozenDict) or: [k isKindOf: Dictionary]) ifTrue: [^ 'a map cannot be a map key'].
  ((k isKindOf: Decimal) and: [k isSignaling]) ifTrue: [^ 'a signaling decimal NaN cannot be a map key'].
  ((k isKindOf: DateTime) and: [k isLegacyZone]) ifTrue: [
    ^ aBoolean ifTrue: [nil] ifFalse: ['a datetime in an IANA time zone cannot be a map key']].
  ((k isKindOf: DateTime) and: [k isInstantForm]) ifTrue: [
    ^ 'a datetime in an IANA time zone cannot be a map key: use its UTC or fixed-offset form'].
  (k isKindOf: PBTuple) ifTrue: [
    k do: [:each |
      | r |
      r := self _unkeyableReason: each legacyAllowed: aBoolean.
      r isNil ifFalse: [^ r , ' (inside a tuple)']]].
  ^ nil.

"=== format-3 zone keys (design 4.3) ========================================="

"The most a fixed offset or a zone's offset moves a wall clock from its
 instant (|offset| < 24 h, format spec 'Canonical values')."
PBKeys class >> offsetWindow
  ^ 86399999999.

"Signals PBNotSupportedError when two keys of aKeyArray could conflict and
 only the zone's offsets can tell (format spec, 'Map keys' and 'Known gaps').
 That is exactly when the two keys are equal under the map-key rule at every
 position (the key itself, or each item of a tuple key) except positions
 holding datetimes, and at one such position one key holds a format-3 zone
 datetime and the other either an aware datetime whose instant lies within
 24 h of its wall clock, or a format-3 datetime of another zone whose wall
 clock lies within 48 h. Format-3 datetimes of one zone conflict exactly when
 their wall clocks are equal (fold ignored), which needs no offset and is the
 id's business. Linear apart from a sort per datetime position: keys are
 bucketed by their coarse map-key id, in which every aware or format-3
 datetime is one token."
PBKeys class >> checkDecidableKeys: aKeyArray
  | buckets |
  (aKeyArray anySatisfy: [:k | self _holdsLegacy: k]) ifFalse: [^ self].
  buckets := Dictionary new.
  aKeyArray do: [:k |
    (buckets at: (self _keyId: k mode: #coarse) ifAbsentPut: [OrderedCollection new]) add: k].
  buckets keysAndValuesDo: [:id :bucket |
    bucket size > 1 ifTrue: [
      (self _zonedPathsOf: bucket first prefix: #()) do: [:path |
        self _checkDateTimes: (bucket collect: [:k | self _at: path in: k])]]].

"True when k is, or a tuple k holds, a format-3 zone datetime."
PBKeys class >> _holdsLegacy: k
  k isClassObject ifTrue: [^ false].
  (k isKindOf: PBTuple) ifTrue: [^ k asArray anySatisfy: [:each | self _holdsLegacy: each]].
  ^ (k isKindOf: DateTime) and: [k isLegacyZone].

"True when k is, or a tuple k holds, an aware or format-3 datetime (no
 allocation: most keys hold none)."
PBKeys class >> _holdsZoned: k
  (self _isZoned: k) ifTrue: [^ true].
  (k isClassObject not and: [k isKindOf: PBTuple]) ifTrue: [
    k do: [:each | (self _holdsZoned: each) ifTrue: [^ true]]].
  ^ false.

PBKeys class >> _isZoned: k
  ^ k isClassObject not and: [(k isKindOf: DateTime) and: [k isNaive not]].

"The index paths, within k, of its aware and format-3 datetimes."
PBKeys class >> _zonedPathsOf: k prefix: anArray
  | out |
  (self _isZoned: k) ifTrue: [^ OrderedCollection with: anArray].
  out := OrderedCollection new.
  (k isClassObject not and: [k isKindOf: PBTuple]) ifTrue: [
    k keysAndValuesDo: [:i :each | out addAll: (self _zonedPathsOf: each prefix: anArray , { i })]].
  ^ out.

PBKeys class >> _at: aPath in: k
  | v |
  v := k.
  aPath do: [:i | v := v at: i].
  ^ v.

"Datetimes at one position of keys that match everywhere else."
PBKeys class >> _checkDateTimes: aCollection
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
PBKeys class >> _firstIndexIn: aSortedArray atLeast: x
  | lo hi |
  lo := 1. hi := aSortedArray size + 1.
  [lo < hi] whileTrue: [
    | mid |
    mid := (lo + hi) // 2.
    (aSortedArray at: mid) < x ifTrue: [lo := mid + 1] ifFalse: [hi := mid]].
  ^ lo.

PBKeys class >> _undecidable: aLegacy and: other
  ^ PBNotSupportedError signal: 'A map whose keys hold the format-3 zone datetime ' , aLegacy printString
    , ' and ' , other printString , ' at the same position: whether they conflict needs the offsets of '
    , aLegacy zone key , ', and protoBaseST has no time-zone database (design 4.3)'.

"=== PBIdentityKey ============================================================"

"The id of a key identified by identity (a NaN, when read): = is ==, hash is
 the identity hash."
Object subclass: #PBIdentityKey instanceVariableNames: 'object'.

PBIdentityKey class >> on: anObject
  ^ self basicNew _setObject: anObject.

PBIdentityKey >> _setObject: anObject
  "Runs once, on a fresh instance."
  object isNil ifFalse: [^ PBUserError signal: 'PBIdentityKey is immutable'].
  object := anObject.
  ^ self.

PBIdentityKey >> _object
  ^ object.

PBIdentityKey >> = anObject
  ^ (anObject isClassObject not and: [anObject class == PBIdentityKey]) and: [object == anObject _object].

PBIdentityKey >> hash
  ^ object identityHash.

"=== PBMapKeyIndex ============================================================"

"The key index of a PBFrozenDict, built once with it: map-key id -> position
 (the reader's rule, PBKeys _keyId:mode: #read). Building it refuses a key
 that can never be a map key (a list, a map, a signaling NaN, an instant-form
 datetime), and two keys of one id (one object twice included), with
 PBValidationError ('appears twice': a map is never collapsed); it runs
 checkDecidableKeys: when a key holds a format-3 zone datetime.

 When a key holds an aware or format-3 datetime, the index also keeps, per
 coarse id (PBKeys _keyId:mode: #coarse) and per datetime position, the aware
 datetimes sorted by instant and the format-3 ones sorted by wall clock, with
 for each the next one of another zone. A lookup then checks only its probe:
 a probe holding no such datetime needs no check (the keys were proved
 pairwise decidable when the map was built), and a probe holding one is placed
 by binary search. Never exposed, never changed after it is built."
Object subclass: #PBMapKeyIndex instanceVariableNames: 'ids zoned'.

PBMapKeyIndex class >> on: aKeyArray
  | ids |
  aKeyArray do: [:k |
    | reason |
    reason := PBKeys _unkeyableReason: k legacyAllowed: true.
    reason isNil ifFalse: [^ PBValidationError signal: 'PBFrozenDict: ' , reason]].
  PBKeys checkDecidableKeys: aKeyArray.
  ids := Dictionary new.
  1 to: aKeyArray size do: [:i |
    | k id |
    k := aKeyArray at: i.
    id := PBKeys _keyId: k mode: #read.
    (ids includesKey: id) ifTrue: [^ self _twice: k as: (aKeyArray at: (ids at: id))].
    ids at: id put: i].
  ^ self basicNew _setIds: ids zoned: (self _zonedColumnsOf: aKeyArray).

PBMapKeyIndex class >> _twice: aKey as: anEarlierKey
  | text earlier |
  text := PBKeys _preview: aKey.
  earlier := PBKeys _preview: anEarlierKey.
  ^ PBValidationError signal: 'PBFrozenDict: the key ' , text , ' appears twice'
    , (earlier = text ifTrue: [''] ifFalse: [' (it conflicts with the key ' , earlier , ', format spec ''Map keys'')']).

"nil when no key holds an aware or format-3 datetime; else coarse id ->
 (index path -> column). A column is { aware sorted by instant. their
 instants. format-3 sorted by wall clock. their wall clocks. next }, next at i
 the first later position whose zone differs from the one at i (or nil)."
PBMapKeyIndex class >> _zonedColumnsOf: aKeyArray
  | groups out |
  (aKeyArray anySatisfy: [:k | PBKeys _holdsZoned: k]) ifFalse: [^ nil].
  groups := Dictionary new.
  aKeyArray do: [:k |
    | paths |
    paths := PBKeys _zonedPathsOf: k prefix: #().
    paths isEmpty ifFalse: [
      | byPath |
      byPath := groups at: (PBKeys _keyId: k mode: #coarse) ifAbsentPut: [Dictionary new].
      paths do: [:path | (byPath at: path ifAbsentPut: [OrderedCollection new]) add: (PBKeys _at: path in: k)]]].
  groups isEmpty ifTrue: [^ nil].
  out := Dictionary new.
  groups keysAndValuesDo: [:id :byPath |
    | columns |
    columns := Dictionary new.
    byPath keysAndValuesDo: [:path :datetimes | columns at: path put: (self _columnOf: datetimes)].
    out at: id put: columns].
  ^ out.

PBMapKeyIndex class >> _columnOf: aCollection
  | aware legacy n next |
  aware := (aCollection reject: [:each | each isLegacyZone]) asArray
    sort: [:a :b | a utcOrdinalMicroseconds <= b utcOrdinalMicroseconds].
  legacy := (aCollection select: [:each | each isLegacyZone]) asArray
    sort: [:a :b | a localOrdinalMicroseconds <= b localOrdinalMicroseconds].
  n := legacy size.
  next := Array new: n.
  n - 1 to: 1 by: -1 do: [:i |
    next at: i put: (((legacy at: i + 1) zone = (legacy at: i) zone)
      ifTrue: [next at: i + 1] ifFalse: [i + 1])].
  ^ { aware. aware collect: [:each | each utcOrdinalMicroseconds].
      legacy. legacy collect: [:each | each localOrdinalMicroseconds]. next }.

PBMapKeyIndex >> _setIds: aDictionary zoned: aZonedOrNil
  "Runs once, on a fresh instance."
  ids isNil ifFalse: [^ PBUserError signal: 'PBMapKeyIndex is immutable'].
  ids := aDictionary.
  zoned := aZonedOrNil.
  ^ self.

"The position of aKey (1-based), or 0. A lookup that needs a zone's offsets
 to answer signals PBNotSupportedError."
PBMapKeyIndex >> indexOf: aKey
  zoned isNil ifFalse: [self _checkProbe: aKey].
  ^ ids at: (PBKeys _keyId: aKey mode: #read) ifAbsent: [0].

"Signals PBNotSupportedError when aKey and a key of the map could conflict
 and only a zone's offsets can tell (the rule of checkDecidableKeys:)."
PBMapKeyIndex >> _checkProbe: aKey
  | paths columns |
  (PBKeys _holdsZoned: aKey) ifFalse: [^ self].
  paths := PBKeys _zonedPathsOf: aKey prefix: #().
  paths isEmpty ifTrue: [^ self].
  columns := zoned at: (PBKeys _keyId: aKey mode: #coarse) ifAbsent: [^ self].
  paths do: [:path |
    | column |
    column := columns at: path ifAbsent: [nil].
    column isNil ifFalse: [self _check: (PBKeys _at: path in: aKey) against: column]].

PBMapKeyIndex >> _check: aDateTime against: aColumn
  | w aware utcs legacy locals next i |
  w := PBKeys offsetWindow.
  aware := aColumn at: 1. utcs := aColumn at: 2.
  legacy := aColumn at: 3. locals := aColumn at: 4. next := aColumn at: 5.
  aDateTime isLegacyZone
    ifTrue: [
      | l j |
      l := aDateTime localOrdinalMicroseconds.
      i := PBKeys _firstIndexIn: utcs atLeast: l - w.
      (i <= utcs size and: [(utcs at: i) <= (l + w)]) ifTrue: [
        ^ PBKeys _undecidable: aDateTime and: (aware at: i)].
      i := PBKeys _firstIndexIn: locals atLeast: l - (2 * w).
      i <= locals size ifTrue: [
        j := (legacy at: i) zone = aDateTime zone ifTrue: [next at: i] ifFalse: [i].
        (j notNil and: [(locals at: j) <= (l + (2 * w))]) ifTrue: [
          ^ PBKeys _undecidable: aDateTime and: (legacy at: j)]]]
    ifFalse: [
      | u |
      u := aDateTime utcOrdinalMicroseconds.
      i := PBKeys _firstIndexIn: locals atLeast: u - w.
      (i <= locals size and: [(locals at: i) <= (u + w)]) ifTrue: [
        ^ PBKeys _undecidable: (legacy at: i) and: aDateTime]].
