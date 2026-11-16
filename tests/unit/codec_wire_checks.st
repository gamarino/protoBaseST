"EXPECT: ok 53"
"The decoder checks the tree MessagePack decodeOrdered: answers (FS 'Canonical
 values'): string keys only, no ext value, exactly one key per tagged map, one
 spelling for @int, @dec, @td and the date fields. Each malformed input is
 refused with PBCorruptionError."
Import from: 'protobase'.
Import from: '_check'.
| c |
c := Check new.
{
  "The six of the plan."
  { 'a bin key'. '81c40440696e74a131' }.
  { 'an ext value'. 'd40102' }.
  { 'a two-key tagged map'. '82a440646563a131a440696e74a131' }.
  { 'an @int in the native range'. '81a440696e74a131' }.
  { '@missing other than 0'. '81a8406d697373696e6701' }.
  { 'an unknown tag (@sym)'. '81a44073796da3666f6f' }.
  "More of the same rules."
  { 'an integer key'. '8101a178' }.
  { 'the timestamp extension'. 'd6ff00000000' }.
  { 'an ext inside a list'. '9101d40102' }.
  { 'a zero-key map'. '80' }.
  { '@missing false'. '81a8406d697373696e67c2' }.
  { '@int uppercase'. '81a440696e74b13130303030303030303030303030303041' }.
  { '@int leading zero'. '81a440696e74b2303130303030303030303030303030303030' }.
  { '@int 0x prefix'. '81a440696e74b330783130303030303030303030303030303030' }.
  { '@int plus sign'. '81a440696e74b22b3130303030303030303030303030303030' }.
  { '@dec 1e3'. '81a440646563a3316533' }.
  { '@dec nan'. '81a440646563a36e616e' }.
  { '@dec 1.0E+1'. '81a440646563a6312e30452b31' }.
  { '@dec exponent beyond CPython'. '81a440646563b631452b31303030303030303030303030303030303030' }.
  { '@td seconds 86400'. '81a34074649300ce0001518000' }.
  { '@td microseconds 10^6'. '81a3407464930000ce000f4240' }.
  { '@date 2026-02-30'. '81a5406461746593cd07ea021e' }.
  { '@date with a bool field'. '81a5406461746593cd07eac301' }.
  { '@time unknown zone'. '81a54074696d6596010000000092a47a6f6e65ac4d6172732f4f6c796d707573' }.
  { '@time instant form'. '81a54074696d6596010000000092a7696e7374616e74a3555443' }.
  { '@time fixed offset of 24 h'. '81a54074696d6596010000000093a56669786564cf000000141dd76000a158' }.
  { '@dt instant with fold 1'. '81a340647499cd07ea0101000000000192a7696e7374616e74a3555443' }.
  { '@ref segment of 15 bytes'. '81a44072656693c40f3131313131313131313131313131310006' }.
  { '@ref alias outside the table (24: the rc4 table holds 0-23)'. '81a44072656693c410313131313131313131313131313131310018' }.
  { '@ref negative offset'. '81a44072656693c41031313131313131313131313131313131ff06' }.
  { '@mut empty name'. '81a4406d7574a0' }.
  { '@map key twice'. '81a4406d61709292a1610192a16102' }.
  { '@map list key'. '81a4406d61709192910101' }.
  { '@tup not an array'. '81a44074757005' }.
  { 'truncated bytes'. '92' }.
  { 'trailing bytes'. '0101' }
} do: [:each |
  c that: (each at: 1) signals: PBCorruptionError during: [PBCodec decode: (Check bytes: (each at: 2))]].
"Zone keys come from the pinned IANA list (PBZoneKeys), the same on every machine:
 host-relative names and Factory are not keys; backward links are."
c that: 'the pinned release' is: PBZoneKeys release equals: '2026e'.
#('localtime' 'posixrules' 'Factory' 'No/Such_Zone' '../zoneinfo/UTC' 'Europe/Paris/') do: [:key |
  c that: 'zone key ' , key signals: PBCorruptionError containing: 'unknown time zone key' during: [
    PBCodec fromWire: (MessagePackMap withAll: { '@time' -> { 1. 0. 0. 0. 0. { 'zone'. key } } }) resolver: nil]].
#('US/Eastern' 'America/Buenos_Aires' 'UTC' 'Etc/GMT+3' 'America/Argentina/Buenos_Aires') do: [:key |
  c that: 'zone key ' , key is: (PBCodec fromWire: (MessagePackMap withAll: { '@time' -> { 1. 0. 0. 0. 0. { 'zone'. key } } })
    resolver: nil) zone key equals: key].
"An instant whose wall clock may leave years 1-9999 is read and presented in UTC,
 as the format spec lets a reader without a database do; it re-encodes to its bytes."
c that: 'an instant within a day of year 9999' is: (PBCodec decode: (Check bytes: '81a340647499cd270f0c1f140000000092a7696e7374616e74aa417369612f546f6b796f')) printString
  equals: '9999-12-31 20:00:00Z[Asia/Tokyo]'.
"fromWire: refuses a protoST Dictionary or any other object in the tree."
c that: 'a Dictionary in a tree' signals: PBCorruptionError during: [PBCodec fromWire: Dictionary new resolver: nil].
c that: 'a Symbol in a tree' signals: PBCorruptionError during: [PBCodec fromWire: #foobarbaz resolver: nil].
c that: 'a Fraction in a tree' signals: PBCorruptionError during: [PBCodec fromWire: 1 / 2 resolver: nil].
c that: 'decode: of a String' signals: PBValidationError during: [PBCodec decode: 'c0'].
c report displayNl.
