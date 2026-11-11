"EXPECT: ok 92"
"Each tagged form of FS 'Canonical values' (the bytes come from ProtoBase's
 encoder at v2.0.0rc1): the value encodes to the bytes, the bytes decode to an
 equal value of the right class, and re-encode to the same bytes. @uuid is in
 codec_tagged_uuid.st (it needs protoST's lib/uuid.st)."
Import from: 'protobase'.
Import from: '_check'.
Object subclass: #TestResolver.
TestResolver >> refTo: aByteArray offset: anInteger tag: aTag
  ^ { aByteArray hex. anInteger. aTag }.
| c roundTrip seg ref legacy legacy0 ny |
c := Check new.
"value, hex, expected class: encode, decode, re-encode."
roundTrip := [:label :value :hex :class |
  | decoded |
  c that: label , ' bytes' is: (PBCodec encode: value) hex equals: hex.
  decoded := PBCodec decode: (Check bytes: hex).
  c that: label , ' class' is: decoded class equals: class.
  c that: label , ' re-encoded' is: (PBCodec encode: decoded) hex equals: hex.
  decoded].

"@dec: the to-scientific-string, trailing zeros, sign and payload kept."
c that: '1.20 =' is: (roundTrip value: '@dec 1.20' value: (Decimal fromString: '1.20') value: '81a440646563a4312e3230' value: Decimal)
  printString equals: '1.20'.
roundTrip value: '@dec -1.5E+30' value: (Decimal fromString: '-1.5E+30') value: '81a440646563a82d312e35452b3330' value: Decimal.
roundTrip value: '@dec -NaN123' value: (Decimal fromString: '-NaN123') value: '81a440646563a72d4e614e313233' value: Decimal.

"@date."
c that: '@date =' is: (roundTrip value: '@date' value: (CalendarDate year: 2026 month: 11 day: 10)
  value: '81a5406461746593cd07ea0b0a' value: CalendarDate) equals: (CalendarDate year: 2026 month: 11 day: 10).

"@time with a fixed zone: unnamed (Python names it UTC-03:00) and named."
c that: '@time fixed =' is: (roundTrip value: '@time fixed'
    value: (TimeOfDay hour: 12 minute: 34 second: 56 microsecond: 789 fold: 0 zone: (ZoneOffset microseconds: -10800000000))
    value: '81a54074696d65960c2238cd03150093a56669786564d3fffffffd7c451400a95554432d30333a3030' value: TimeOfDay) zone name
  equals: 'UTC-03:00'.
c that: '@time named zone' is: (roundTrip value: '@time named'
    value: (TimeOfDay hour: 12 minute: 34 second: 56 microsecond: 789 fold: 0 zone: (ZoneOffset microseconds: -10800000000 name: 'ART'))
    value: '81a54074696d65960c2238cd03150093a56669786564d3fffffffd7c451400a3415254' value: TimeOfDay) zone name
  equals: 'ART'.
"@time in an IANA zone: the wall clock and ['zone', key]."
c that: '@time zone key' is: (roundTrip value: '@time zone'
    value: (TimeOfDay hour: 1 minute: 2 second: 3 microsecond: 0 fold: 0 zone: (ZoneName key: 'Europe/Paris'))
    value: '81a54074696d6596010203000092a47a6f6e65ac4575726f70652f5061726973' value: TimeOfDay) zone key
  equals: 'Europe/Paris'.

"@dt: the instant form (12:00 in Buenos Aires is 15:00 UTC), the FS example
 (01:30 New York, fold 1, is 06:30 UTC), naive, and UTC."
c that: '@dt instant =' is: (roundTrip value: '@dt instant'
    value: (DateTime utcFields: #(2026 11 10 15 0 0 0) zoneName: (ZoneName key: 'America/Argentina/Buenos_Aires'))
    value: '81a340647499cd07ea0b0a0f0000000092a7696e7374616e74be416d65726963612f417267656e74696e612f4275656e6f735f4169726573'
    value: DateTime)
  equals: (DateTime year: 2026 month: 11 day: 10 hour: 12 minute: 0 second: 0 microsecond: 0 fold: 0
    zone: (ZoneOffset microseconds: -10800000000)).
ny := roundTrip value: '@dt FS example'
  value: (DateTime utcFields: #(2026 11 1 6 30 0 0) zoneName: (ZoneName key: 'America/New_York'))
  value: '81a340647499cd07ea0b01061e00000092a7696e7374616e74b0416d65726963612f4e65775f596f726b' value: DateTime.
c that: '@dt FS example is the instant form' isTrue: ny isInstantForm.
roundTrip value: '@dt naive' value: (DateTime year: 2026 month: 11 day: 10 hour: 12 minute: 0 second: 0 microsecond: 5 fold: 0 zone: nil)
  value: '81a340647499cd07ea0b0a0c00000500c0' value: DateTime.
roundTrip value: '@dt UTC' value: (DateTime year: 2026 month: 11 day: 10 hour: 12 minute: 0 second: 0 microsecond: 5 fold: 0 zone: ZoneOffset utc)
  value: '81a340647499cd07ea0b0a0c0000050093a5666978656400a3555443' value: DateTime.

"@td, normalized as Python's timedelta."
c that: '@td -1 s' is: (roundTrip value: '@td -1 s' value: (TimeSpan days: 0 seconds: -1 microseconds: 0)
  value: '81a340746493ffce0001517f00' value: TimeSpan) seconds equals: 86399.
roundTrip value: '@td -3 days 7 us' value: (TimeSpan days: -3 seconds: 0 microseconds: 7)
  value: '81a340746493fd0007' value: TimeSpan.

"@tup: (1, 'x', (true,))."
c that: '@tup =' is: (roundTrip value: '@tup'
    value: (PBTuple withAll: { 1. 'x'. PBTuple withAll: { true } })
    value: '81a4407475709301a17881a44074757091c3' value: PBTuple)
  equals: (PBTuple withAll: { 1. 'x'. PBTuple withAll: { true } }).

"@map: insertion order kept, keys of any kind."
c that: '@map keys in order' is: (roundTrip value: '@map'
    value: (PBFrozenDict withAssociations: { 'b' -> 1. 'a' -> 2. 3 -> 'c' })
    value: '81a4406d61709392a1620192a161029203a163' value: PBFrozenDict) keys
  equals: #('b' 'a' 3).

"@missing: the singleton."
c that: '@missing is the singleton' isTrue: (roundTrip value: '@missing' value: PBMissing default
  value: '81a8406d697373696e6700' value: PBMissing) == PBMissing default.

"@mut: the cell name."
c that: '@mut name' is: (roundTrip value: '@mut' value: (PBMutableObject name: 'counter')
  value: '81a4406d7574a7636f756e746572' value: PBMutableObject) name equals: 'counter'.

"@ref: built-in alias 6 at offset 26; with no resolver, a PBUnresolvedRef that encodes back."
seg := Check bytes: '5eed0000000040008000000000002002'.
ref := roundTrip value: '@ref built-in'
  value: (PBUnresolvedRef pointer: (PBAtomPointer segment: seg offset: 26) tag: 6)
  value: '81a44072656693c4105eed00000000400080000000000020021a06' value: PBUnresolvedRef.
c that: '@ref pointer' is: ref pointer equals: (PBAtomPointer segment: seg offset: 26).
c that: '@ref tag' is: ref tag equals: 6.
c that: '@ref pointer printString' is: ref pointer printString equals: 'PBAtomPointer(5eed0000000040008000000000002002, 26)'.
c that: '@ref application tag' is: (roundTrip value: '@ref application'
    value: (PBUnresolvedRef pointer: (PBAtomPointer segment: seg offset: 100) tag: 'conformance.Invoice')
    value: '81a44072656693c4105eed000000004000800000000000200264b3636f6e666f726d616e63652e496e766f696365'
    value: PBUnresolvedRef) tag
  equals: 'conformance.Invoice'.
"With a resolver, the resolver answers the reference."
c that: '@ref resolver' is: (PBCodec fromWire: (MessagePack decodeOrdered: (Check bytes: '81a44072656693c4105eed00000000400080000000000020021a06'))
    resolver: TestResolver new)
  equals: { '5eed0000000040008000000000002002'. 26. 6 }.
"Format 2: the segment as 32 hexadecimal digits and the type name; read only."
c that: '@ref format 2' is: (PBCodec decode: (Check bytes: '81a44072656693d92035454544303030303030303034303030383030303030303030303030323030321abf70726f746f5f64622e636f6c6c656374696f6e732e44696374696f6e617279')) pointer
  equals: (PBAtomPointer segment: seg offset: 26).
"Token mode: every reference is {'@ref': nil}."
c that: '@ref token' is: (MessagePack encode: (PBCodec toWire: { ref } atomRef: PBCodec tokenRef)) hex
  equals: '9181a440726566c0'.

"A format-3 ['zone', key] datetime is read flagged isLegacyZone, never given an
 offset, never written, and every order or hash use signals PBNotSupportedError."
legacy := PBCodec decode: (Check bytes: '81a340647499cd07ea0b01011e00000192a47a6f6e65b0416d65726963612f4e65775f596f726b').
legacy0 := PBCodec decode: (Check bytes: '81a340647499cd07ea0b01011e00000092a47a6f6e65b0416d65726963612f4e65775f596f726b').
c that: 'legacy isLegacyZone' isTrue: legacy isLegacyZone.
c that: 'legacy is a DateTime' isTrue: (legacy isKindOf: DateTime).
c that: 'a DateTime is not legacy' is: ny isLegacyZone equals: false.
c that: 'legacy printString' is: legacy printString equals: '2026-11-01 01:30:00[America/New_York]'.
c that: 'legacy fold kept' is: legacy fold equals: 1.
c that: 'legacy wall-clock date' is: legacy date equals: (CalendarDate year: 2026 month: 11 day: 1).
c that: 'legacy same zone and wall clock' isTrue: legacy = legacy0.
c that: 'legacy is not a naive value' is: legacy = (DateTime year: 2026 month: 11 day: 1 hour: 1 minute: 30 second: 0 microsecond: 0 fold: 0 zone: nil) equals: false.
c that: 'legacy write' signals: PBValidationError containing: 'America/New_York' during: [PBCodec encode: legacy].
c that: 'legacy inside a list' signals: PBValidationError containing: 'America/New_York' during: [PBCodec encode: { 1. legacy }].
c that: 'legacy hash' signals: PBNotSupportedError containing: 'America/New_York' during: [legacy hash].
c that: 'legacy order' signals: PBNotSupportedError containing: 'America/New_York' during: [legacy < legacy0].
c that: 'order against legacy' signals: PBNotSupportedError containing: 'America/New_York' during: [ny < legacy].
c that: 'legacy instant' signals: PBNotSupportedError containing: 'America/New_York' during: [legacy utcOrdinalMicroseconds].
c that: 'legacy equality with an instant' signals: PBNotSupportedError containing: 'America/New_York' during: [legacy = ny].
c that: 'legacy is made by the decoder only' signals: PBUserError during: [
  PBLegacyZoneDateTime utcFields: #(2026 1 1 0 0 0 0) zoneName: (ZoneName key: 'UTC')].
c report displayNl.
