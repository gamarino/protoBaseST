"EXPECT: ok 40"
"Spec 10.5: values outside format 4 are refused when written, with
 PBValidationError naming the class, never stored in another form."
Import from: 'protobase'.
Import from: '_check'.
Array subclass: #TaggedArray.
Decimal subclass: #Price instanceVariableNames: 'currency'.
Price >> printOn: aStream
  aStream nextPutAll: 'USD 99'.
Price >> exponent
  ^ 1000.
CalendarDate subclass: #Holiday.
Holiday >> year
  ^ 1.
| c price |
c := Check new.
{
  { 'a Symbol'. #foobarbaz. 'Symbol' }.
  { 'a Fraction'. 1 / 3. 'Fraction' }.
  { 'a Dictionary'. Dictionary new. 'Dictionary' }.
  { 'a Character'. $a. 'Character' }.
  { 'a Set'. Set new. 'Set' }.
  { 'a Bag'. Bag new. 'Bag' }.
  { 'an Interval'. 1 to: 3. 'Interval' }.
  { 'a block'. [:x | x]. 'BlockClosure' }.
  { 'an Object'. Object new. 'Object' }.
  { 'a class'. String. 'class' }.
  { 'a zone alone'. ZoneOffset utc. 'ZoneOffset' }.
  { 'a Symbol inside a list'. { 1. #foobarbaz }. 'Symbol' }.
  { 'a Fraction inside a map'. PBFrozenDict withAssociations: { 'k' -> (1 / 2) }. 'Fraction' }
} do: [:each |
  c that: (each at: 1) signals: PBValidationError containing: (each at: 3) during: [PBCodec encode: (each at: 2)].
  c that: (each at: 1) , ' (canonical:)' signals: PBValidationError containing: (each at: 3) during: [PBCodec canonical: (each at: 2)]].
"A short Symbol literal is the String itself in protoST (STATUS D35): it is stored as a string."
c that: 'a short symbol literal' is: (PBCodec encode: #paid) hex equals: 'a470616964'.
"Map keys that can never be keys (FS 'Map keys')."
c that: 'a list key' signals: PBValidationError containing: 'list' during: [
  PBCodec encode: (PBFrozenDict withAssociations: { #(1) -> 1 })].
c that: 'a zone datetime key' signals: PBValidationError containing: 'IANA' during: [
  PBCodec encode: (PBFrozenDict withAssociations: {
    (DateTime utcFields: #(2026 1 1 0 0 0 0) zoneName: (ZoneName key: 'Europe/Paris')) -> 1 })].
c that: 'a signaling NaN key' signals: PBValidationError containing: 'signaling' during: [
  PBCodec encode: (PBFrozenDict withAssociations: { (Decimal fromString: 'sNaN') -> 1 })].
c that: 'a key twice' signals: PBValidationError containing: 'twice' during: [
  PBFrozenDict withAssociations: { 'a' -> 1. 'a' -> 2 }].
"Time zones and decimals the reference implementation cannot hold."
c that: 'an unknown zone key' signals: PBValidationError containing: 'Mars/Olympus' during: [
  PBCodec encode: (TimeOfDay hour: 1 minute: 0 second: 0 microsecond: 0 fold: 0 zone: (ZoneName key: 'Mars/Olympus'))].
c that: 'a key outside the zone directory' signals: PBValidationError containing: 'unknown time zone' during: [
  PBCodec encode: (TimeOfDay hour: 1 minute: 0 second: 0 microsecond: 0 fold: 0 zone: (ZoneName key: '../zoneinfo/UTC'))].
c that: 'an exponent CPython cannot represent' signals: PBValidationError containing: 'exponent' during: [
  PBCodec encode: (Decimal fromString: '12E+999999999999999999')].
c that: 'an instant at the end of year 9999' signals: PBNotSupportedError containing: 'Asia/Tokyo' during: [
  PBCodec encode: (DateTime utcFields: #(9999 12 31 20 0 0 0) zoneName: (ZoneName key: 'Asia/Tokyo'))].
"Spec 10.5: a zoned datetime built from a wall clock (protoST's calendar, plan call C7)."
c that: 'a zoned datetime from a wall clock' signals: TimeZoneUnavailable during: [
  DateTime year: 2026 month: 1 day: 1 hour: 0 minute: 0 second: 0 microsecond: 0 fold: 0 zone: (ZoneName key: 'Europe/Paris')].
"A host subclass of a mapped class is stored as its base value, read from the
 base instance variables, never through the subclass's methods."
price := Price sign: 0 coefficient: 1999 exponent: -2.
c that: 'a Decimal subclass' is: (PBCodec encode: price) hex equals: (PBCodec encode: (Decimal fromString: '19.99')) hex.
c that: 'a Decimal subclass reads back a Decimal' is: (PBCodec decode: (PBCodec encode: price)) class equals: Decimal.
c that: 'a CalendarDate subclass' is: (PBCodec encode: (Holiday year: 2026 month: 12 day: 25)) hex
  equals: (PBCodec encode: (CalendarDate year: 2026 month: 12 day: 25)) hex.
c that: 'an Array subclass is a list' is: (PBCodec canonical: (TaggedArray new: 1)) class equals: PBFrozenList.
c report displayNl.
