"EXPECT: ok 42"
"The value nesting limit (format spec v2.0.0rc2, 'Value nesting depth'; ProtoBase D60; plan
 Task 17b): a value nests at most MAX_VALUE_DEPTH = 1022 msgpack containers, counted from the
 value: a list 1, a tuple 2, a map 3 (2 when empty), a tagged scalar 1 to 3, an empty
 container like any other, map keys on the paths. Depth 1022 round-trips; 1023 is refused
 when written (PBValidationError, also by canonical: alone) and when read (PBCorruptionError,
 from data a raw packer wrote). The walks use explicit stacks: the same values round-trip
 inside an actor, on a worker thread."
Import from: 'protobase'.
Import from: '_check'.

Object subclass: #DepthWorker.
"The bytes of the value aByteArray holds, decoded and encoded again on this actor's thread."
DepthWorker >> roundTrip: aByteArray
  ^ PBCodec encode: (PBCodec decode: aByteArray).
DepthWorker >> encode: aValue
  ^ [PBCodec encode: aValue] on: PBValidationError do: [:e | e class name].
DepthWorker >> decode: aByteArray
  ^ [PBCodec decode: aByteArray. 'accepted'] on: PBCorruptionError do: [:e | e class name].

| c nest lists roundTrips writeRefused readRefused raw aware naive bigInt worker over |
c := Check new.
nest := [:n :seed :wrap | | v | v := seed. n timesRepeat: [v := wrap value: v]. v].
lists := [:n :seed | nest value: n value: seed value: [:v | Array with: v]].
roundTrips := [:v | | b | b := PBCodec encode: v. (PBCodec encode: (PBCodec decode: b)) = b].
writeRefused := 'MAX_VALUE_DEPTH = 1022'.
readRefused := 'The encoded value nests deeper than MAX_VALUE_DEPTH = 1022 MessagePack containers, the most the storage format allows (format spec, "Value nesting depth")'.
"raw: the bytes of wire data written by protoST's MessagePack, which knows nothing of the limit."
raw := [:wire | MessagePack encode: wire].

c that: 'MAX_VALUE_DEPTH' is: PBCodec maxValueDepth equals: 1022.

"Lists: 1 each."
c that: '1022 lists round-trip' isTrue: (roundTrips value: (lists value: 1022 value: 1)).
c that: 'their bytes: 1022 fixarray headers and the 1' is: (PBCodec encode: (lists value: 1022 value: 1)) size equals: 1023.
c that: '1023 lists: encode refuses' signals: PBValidationError containing: writeRefused during: [
  PBCodec encode: (lists value: 1023 value: 1)].
c that: '1023 lists: canonical: refuses' signals: PBValidationError containing: writeRefused during: [
  PBCodec canonical: (lists value: 1023 value: 1)].
c that: '1023 lists: decode refuses' signals: PBCorruptionError containing: readRefused during: [
  PBCodec decode: (raw value: (lists value: 1023 value: 1))].

"Empty containers count: an empty list 1, an empty tuple and an empty map 2."
c that: 'an empty list in 1021 lists round-trips' isTrue: (roundTrips value: (lists value: 1021 value: #())).
c that: 'an empty list in 1022 lists is refused' signals: PBValidationError containing: writeRefused during: [
  PBCodec encode: (lists value: 1022 value: #())].
c that: 'and read as corruption' signals: PBCorruptionError containing: readRefused during: [
  PBCodec decode: (raw value: (lists value: 1022 value: #()))].
c that: 'an empty tuple in 1020 lists round-trips' isTrue: (roundTrips value: (lists value: 1020 value: (PBTuple withAll: #()))).
c that: 'an empty tuple in 1021 lists is refused' signals: PBValidationError containing: writeRefused during: [
  PBCodec encode: (lists value: 1021 value: (PBTuple withAll: #()))].
c that: 'and read as corruption' signals: PBCorruptionError containing: readRefused during: [
  PBCodec decode: (raw value: (lists value: 1021 value: (MessagePackMap withAll: { '@tup' -> #() })))].
c that: 'an empty map in 1020 lists round-trips' isTrue: (roundTrips value: (lists value: 1020 value: (PBFrozenDict withAssociations: #()))).
c that: 'an empty map in 1021 lists is refused' signals: PBValidationError containing: writeRefused during: [
  PBCodec encode: (lists value: 1021 value: (PBFrozenDict withAssociations: #()))].
c that: 'and read as corruption' signals: PBCorruptionError containing: readRefused during: [
  PBCodec decode: (raw value: (lists value: 1021 value: (MessagePackMap withAll: { '@map' -> #() })))].

"Tuples 2, maps 3."
c that: '511 tuples round-trip' isTrue: (roundTrips value: (nest value: 511 value: 1 value: [:v | PBTuple withAll: { v }])).
c that: '512 tuples are refused' signals: PBValidationError containing: writeRefused during: [
  PBCodec encode: (nest value: 512 value: 1 value: [:v | PBTuple withAll: { v }])].
c that: '2 lists around 340 maps round-trip' isTrue: (roundTrips value:
  (lists value: 2 value: (nest value: 340 value: 1 value: [:v | PBFrozenDict withAssociations: { 'k' -> v }]))).
c that: '3 lists around 340 maps are refused' signals: PBValidationError containing: writeRefused during: [
  PBCodec encode: (lists value: 3 value: (nest value: 340 value: 1 value: [:v | PBFrozenDict withAssociations: { 'k' -> v }]))].
c that: '3 lists around 340 maps: read as corruption' signals: PBCorruptionError containing: readRefused during: [
  PBCodec decode: (raw value: (lists value: 3 value:
    (nest value: 340 value: 1 value: [:v | MessagePackMap withAll: { '@map' -> { { 'k'. v } } }])))].

"Tagged scalars: an aware @time or @dt 3, a naive one 2, an @int 1."
aware := TimeOfDay hour: 1 minute: 0 second: 0 microsecond: 0 fold: 0 zone: ZoneOffset utc.
naive := DateTime year: 2026 month: 11 day: 11 hour: 12 minute: 0 second: 0 microsecond: 0 fold: 0 zone: nil.
bigInt := 1 bitShift: 70.
c that: 'an aware @time in 1019 lists round-trips' isTrue: (roundTrips value: (lists value: 1019 value: aware)).
c that: 'an aware @time in 1020 lists is refused' signals: PBValidationError containing: writeRefused during: [
  PBCodec encode: (lists value: 1020 value: aware)].
c that: 'a naive @dt in 1020 lists round-trips' isTrue: (roundTrips value: (lists value: 1020 value: naive)).
c that: 'a naive @dt in 1021 lists is refused' signals: PBValidationError containing: writeRefused during: [
  PBCodec encode: (lists value: 1021 value: naive)].
c that: 'an @int in 1021 lists round-trips' isTrue: (roundTrips value: (lists value: 1021 value: bigInt)).
c that: 'an @int in 1022 lists is refused' signals: PBValidationError containing: writeRefused during: [
  PBCodec encode: (lists value: 1022 value: bigInt)].
c that: 'an aware @dt whose time-zone array is container 1023: read as corruption' signals: PBCorruptionError
  containing: readRefused during: [
    PBCodec decode: (raw value: (lists value: 1020 value: (MessagePackMap withAll: {
      '@dt' -> { 2026. 11. 10. 12. 30. 45. 0. 0. { 'fixed'. 0. 'UTC' } } })))].

"Map keys are on the paths: a map (3) whose key is 509 tuples (1018) around 1 is 1021."
over := [:n | lists value: n value: (PBFrozenDict withAssociations: {
  (nest value: 509 value: 1 value: [:v | PBTuple withAll: { v }]) -> 'v' })].
c that: 'a key of 509 tuples in a map in 1 list round-trips' isTrue: (roundTrips value: (over value: 1)).
c that: 'the same in 2 lists is refused' signals: PBValidationError containing: writeRefused during: [
  PBCodec encode: (over value: 2)].
c that: 'and read as corruption' signals: PBCorruptionError containing: readRefused during: [
  PBCodec decode: (raw value: (lists value: 2 value: (MessagePackMap withAll: { '@map' -> {
    { nest value: 509 value: 1 value: [:v | MessagePackMap withAll: { '@tup' -> { v } }]. 'v' } } })))].

"A payload deeper than protoST's MessagePack reads (1024): malformed msgpack, PBCorruptionError."
c that: '1025 nested arrays' signals: PBCorruptionError containing: 'malformed msgpack' during: [
  PBCodec decode: (ByteArray withAll: (((1 to: 1025) asArray collect: [:i | 16r91]) , #(1)))].

"valueDepth: counts as the spec does."
c that: 'valueDepth: of 1' is: (PBCodec valueDepth: 1) equals: 0.
c that: 'valueDepth: of an empty list' is: (PBCodec valueDepth: (PBFrozenList withAll: #())) equals: 1.
c that: 'valueDepth: of an empty tuple' is: (PBCodec valueDepth: (PBTuple withAll: #())) equals: 2.
c that: 'valueDepth: of an empty map' is: (PBCodec valueDepth: (PBFrozenDict withAssociations: #())) equals: 2.
c that: 'valueDepth: of 1022 lists' is: (PBCodec valueDepth: (PBCodec canonical: (lists value: 1022 value: 1))) equals: 1022.
c that: 'valueDepth: through a map key' is: (PBCodec valueDepth: (PBCodec canonical: (over value: 1))) equals: 1022.
c that: 'valueDepth: of an aware @time' is: (PBCodec valueDepth: aware) equals: 3.

"On a worker thread: an actor reads and writes the same values at the limit and refuses one more."
worker := DepthWorker new asActor.
c that: 'an actor round-trips 1022 lists' is: (worker roundTrip: (PBCodec encode: (lists value: 1022 value: 1))) wait
  equals: (PBCodec encode: (lists value: 1022 value: 1)).
c that: 'an actor round-trips a key of 509 tuples' is: (worker roundTrip: (PBCodec encode: (over value: 1))) wait
  equals: (PBCodec encode: (over value: 1)).
c that: 'an actor refuses to write 1023 lists' is: (worker encode: (lists value: 1023 value: 1)) wait equals: #PBValidationError.
c that: 'an actor refuses to read 1023 lists' is: (worker decode: (raw value: (lists value: 1023 value: 1))) wait
  equals: #PBCorruptionError.
c report displayNl.
