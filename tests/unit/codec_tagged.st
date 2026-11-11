"EXPECT: ok 126"
"Each tagged form of FS 'Canonical values' (the bytes come from ProtoBase's
 encoder at v2.0.0rc1): the value encodes to the bytes, the bytes decode to an
 equal value of the right class, and re-encode to the same bytes. @uuid is in
 codec_tagged_uuid.st (it needs protoST's lib/uuid.st)."
Import from: 'protobase'.
Import from: '_check'.
Object subclass: #TestResolver.
TestResolver >> refTo: aByteArray offset: anInteger tag: aTag
  ^ { aByteArray hex. anInteger. aTag }.
| c roundTrip seg ref legacy legacy0 ny gap fmt3 utc nyT utcT |
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
"Format-3 zone keys of a map (FS 'Map keys', format-3 key forms). Within one
 zone two keys conflict exactly when their wall clocks are equal, fold ignored:
 the spring-forward 02:30 and 03:30 are two keys, as in ProtoBase, and 01:30
 fold 0 and fold 1 conflict. Against an aware key or a key of another zone the
 answer needs the offsets, so the map is refused, never assumed distinct."
gap := PBCodec decode: (Check bytes: '81a4406d6170929281a340647499cd07ea0308021e00000092a47a6f6e65b0416d65726963612f4e65775f596f726b019281a340647499cd07ea0308031e00000092a47a6f6e65b0416d65726963612f4e65775f596f726b02').
c that: 'format-3 gap keys are two keys' is: gap size equals: 2.
c that: 'format-3 gap map re-reads its key' is: (gap at: gap keys first) equals: 1.
c that: 'format-3 fold keys conflict' signals: PBCorruptionError containing: 'twice' during: [
  PBCodec decode: (Check bytes: '81a4406d6170929281a340647499cd07ea0b01011e00000092a47a6f6e65b0416d65726963612f4e65775f596f726b019281a340647499cd07ea0b01011e00000192a47a6f6e65b0416d65726963612f4e65775f596f726b02')].
c that: 'format-3 key next to a fixed-offset key' signals: PBNotSupportedError containing: 'America/New_York' during: [
  PBCodec decode: (Check bytes: '81a4406d6170929281a340647499cd07ea03080c0000000092a47a6f6e65b0416d65726963612f4e65775f596f726b019281a340647499cd07ea0308100000000093a5666978656400a355544302')].
c that: 'format-3 key in a tuple next to a fixed-offset one' signals: PBNotSupportedError containing: 'America/New_York' during: [
  PBCodec decode: (Check bytes: '81a4406d6170929281a4407475709281a340647499cd07ea03080c0000000092a47a6f6e65b0416d65726963612f4e65775f596f726b01a1619281a4407475709281a340647499cd07ea0308100000000093a5666978656400a355544301a162')].
c that: 'format-3 keys of two zones' signals: PBNotSupportedError containing: 'America/New_York' during: [
  PBCodec decode: (Check bytes: '81a4406d6170929281a340647499cd07ea03080c0000000092a47a6f6e65b0416d65726963612f4e65775f596f726b019281a340647499cd07ea03080c0000000092a47a6f6e65ac4575726f70652f506172697302')].
c that: 'a lookup by an aware key in a map of format-3 keys' signals: PBNotSupportedError containing: 'America/New_York' during: [
  gap at: (DateTime year: 2026 month: 3 day: 8 hour: 7 minute: 30 second: 0 microsecond: 0 fold: 0 zone: ZoneOffset utc)].
c that: 'a tuple holding a format-3 datetime against an aware one' signals: PBNotSupportedError during: [
  (PBTuple withAll: { legacy }) = (PBTuple withAll: { ny })].

"Duplicate keys are found through map-key ids (PBKeys), for every kind of key: equal values of one class."
{ { Decimal fromString: '1.20'. Decimal fromString: '1.2' }.
  { Decimal fromString: '0'. Decimal fromString: '-0E+5' }.
  { 0.0. -0.0 }.
  { 2 raisedTo: 80. 2 raisedTo: 80 }.
  { ny. DateTime year: 2026 month: 11 day: 1 hour: 1 minute: 30 second: 0 microsecond: 0 fold: 0 zone: (ZoneOffset microseconds: -18000000000) }.
  { TimeOfDay hour: 1 minute: 2 second: 3 microsecond: 0 fold: 0 zone: (ZoneName key: 'Europe/Paris'). TimeOfDay hour: 1 minute: 2 second: 3 }.
  { PBTuple withAll: { 'a'. Decimal fromString: '1.0' }. PBTuple withAll: { 'a'. Decimal fromString: '1.00' } }.
  { 'abcdefghij'. 'abcdefghij' copy }.
  { #[1 2 3]. #[1 2 3] copy }
} doWithIndex: [:pair :i |
  c that: 'duplicate keys ' , i printString signals: PBValidationError containing: 'twice' during: [
    PBFrozenDict withAssociations: { (pair at: 1) -> 1. (pair at: 2) -> 2 }]].
"Keys of different classes conflict under the map-key rule (FS 'Map keys': 1 and 1.0
 are one key; keys_map_key_rule.st); two NaN objects are two keys when read."
c that: '1 and 1.0' signals: PBValidationError containing: 'twice' during: [
  PBFrozenDict withAssociations: { 1 -> 'a'. 1.0 -> 'b' }].
c that: 'two NaN objects' is: (PBFrozenDict withAssociations: {
  (PBCodec decode: (Check bytes: 'cb7ff8000000000000')) -> 1. (PBCodec decode: (Check bytes: 'cb7ff8000000000000')) -> 2 }) size equals: 2.
"A large map is checked through the map-key ids (it would be 12.5 million comparisons pairwise)."
c that: 'a map of 5000 decimal keys' is: (PBFrozenDict withAssociations:
  ((1 to: 5000) asArray collect: [:i | (Decimal sign: 0 coefficient: i exponent: -2) -> i])) size equals: 5000.

"The refusal is exactly where a conflict is possible (N5): keys that match at
 every other position, with the datetimes within the offset window."
fmt3 := [:y :mo :d :h :zone | PBCodec fromWire: (MessagePackMap withAll: { '@dt' -> { y. mo. d. h. 0. 0. 0. 0. { 'zone'. zone } } }) resolver: nil].
utc := [:y :mo :d :h | DateTime year: y month: mo day: d hour: h minute: 0 second: 0 microsecond: 0 fold: 0 zone: ZoneOffset utc].
c that: 'one tuple key holding a format-3 and an aware datetime' is: (PBFrozenDict withAssociations: {
  (PBTuple withAll: { fmt3 value: 2026 value: 3 value: 8 value: 12 value: 'America/New_York'. utc value: 2026 value: 3 value: 8 value: 16 }) -> 1 }) size equals: 1.
c that: 'a format-3 key and an aware key years apart' is: (PBFrozenDict withAssociations: {
  (fmt3 value: 2026 value: 3 value: 8 value: 12 value: 'America/New_York') -> 1. (utc value: 2020 value: 1 value: 1 value: 0) -> 2 }) size equals: 2.
c that: 'a format-3 key and an aware key 25 h apart' is: (PBFrozenDict withAssociations: {
  (fmt3 value: 2026 value: 3 value: 8 value: 12 value: 'America/New_York') -> 1. (utc value: 2026 value: 3 value: 9 value: 13) -> 2 }) size equals: 2.
c that: 'a format-3 key and an aware key 23 h apart' signals: PBNotSupportedError containing: 'America/New_York' during: [
  PBFrozenDict withAssociations: {
    (fmt3 value: 2026 value: 3 value: 8 value: 12 value: 'America/New_York') -> 1. (utc value: 2026 value: 3 value: 9 value: 11) -> 2 }].
c that: 'datetimes at different tuple positions' is: (PBFrozenDict withAssociations: {
  (PBTuple withAll: { fmt3 value: 2026 value: 3 value: 8 value: 12 value: 'America/New_York'. 1 }) -> 1.
  (PBTuple withAll: { 1. utc value: 2026 value: 3 value: 8 value: 16 }) -> 2 }) size equals: 2.
c that: 'tuples that differ at another position' is: (PBFrozenDict withAssociations: {
  (PBTuple withAll: { fmt3 value: 2026 value: 3 value: 8 value: 12 value: 'America/New_York'. 'a' }) -> 1.
  (PBTuple withAll: { utc value: 2026 value: 3 value: 8 value: 16. 'b' }) -> 2 }) size equals: 2.
c that: 'format-3 keys of two zones 3 days apart' is: (PBFrozenDict withAssociations: {
  (fmt3 value: 2026 value: 3 value: 8 value: 12 value: 'America/New_York') -> 1.
  (fmt3 value: 2026 value: 3 value: 11 value: 12 value: 'Europe/Paris') -> 2 }) size equals: 2.
c that: 'format-3 keys of two zones 47 h apart' signals: PBNotSupportedError containing: 'Europe/Paris' during: [
  PBFrozenDict withAssociations: {
    (fmt3 value: 2026 value: 3 value: 8 value: 12 value: 'America/New_York') -> 1.
    (fmt3 value: 2026 value: 3 value: 10 value: 11 value: 'Europe/Paris') -> 2 }].
"Other positions compare as map keys do (order-key rule: true, 1, 1.0 and
 Decimal 1.00 are one key), so these tuples could conflict (N6)."
nyT := [:x | PBTuple withAll: { fmt3 value: 2026 value: 3 value: 8 value: 12 value: 'America/New_York'. x }].
utcT := [:x | PBTuple withAll: { utc value: 2026 value: 3 value: 8 value: 16. x }].
c that: '(format-3, 1) and (aware, 1.0)' signals: PBNotSupportedError containing: 'America/New_York' during: [
  PBFrozenDict withAssociations: { (nyT value: 1) -> 1. (utcT value: 1.0) -> 2 }].
c that: '(format-3, true) and (aware, 1)' signals: PBNotSupportedError containing: 'America/New_York' during: [
  PBFrozenDict withAssociations: { (nyT value: true) -> 1. (utcT value: 1) -> 2 }].
c that: '(format-3, 1) and (aware, Decimal 1.00)' signals: PBNotSupportedError containing: 'America/New_York' during: [
  PBFrozenDict withAssociations: { (nyT value: 1) -> 1. (utcT value: (Decimal fromString: '1.00')) -> 2 }].
c that: '(format-3, 1) and (aware, 2.0)' is: (PBFrozenDict withAssociations: { (nyT value: 1) -> 1. (utcT value: 2.0) -> 2 }) size equals: 2.
c that: '(format-3, 0.1) and (aware, Decimal 0.1)' is: (PBFrozenDict withAssociations: {
  (nyT value: 0.1) -> 1. (utcT value: (Decimal fromString: '0.1')) -> 2 }) size equals: 2.
c that: 'a lookup by an aware key years away' is: (gap at: (utc value: 2020 value: 1 value: 1 value: 0) ifAbsent: ['absent']) equals: 'absent'.

c report displayNl.
