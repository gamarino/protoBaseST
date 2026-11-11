"EXPECT: ok 67"
"Scalars and lists: the exact bytes of FS 'Canonical values' (msgpack-python 1.x
 smallest forms), the decoded value and its class, and the re-encoded bytes."
Import from: 'protobase'.
Import from: '_check'.
| c cases nul |
c := Check new.
nul := 'a' , (String with: (Character value: 0)) , 'b'.
cases := {
  { 'nil'. nil. 'c0' }.
  { 'true'. true. 'c3' }.
  { 'false'. false. 'c2' }.
  { '0'. 0. '00' }.
  { '-1'. -1. 'ff' }.
  { '127'. 127. '7f' }.
  { '128'. 128. 'cc80' }.
  { '-33'. -33. 'd0df' }.
  { '65535'. 65535. 'cdffff' }.
  { '2^32'. 4294967296. 'cf0000000100000000' }.
  { '-2^31-1'. -2147483649. 'd3ffffffff7fffffff' }.
  { '1.5'. 1.5. 'cb3ff8000000000000' }.
  { '0.1'. 0.1. 'cb3fb999999999999a' }.
  { 'empty string'. ''. 'a0' }.
  { 'utf-8 string'. 'héllo'. 'a668c3a96c6c6f' }.
  { 'string with NUL'. nul. 'a3610062' }.
  { 'bytes'. #[0 255]. 'c40200ff' }.
  { 'empty bytes'. ByteArray new. 'c400' }.
  { 'list'. { 1. { 2.5. nil }. #[0 255]. 'hé'. true. false }. '960192cb4004000000000000c0c40200ffa368c3a9c3c2' }.
  { 'empty list'. #(). '90' } }.
cases do: [:each |
  | label value hex bytes decoded |
  label := each at: 1. value := each at: 2. hex := each at: 3.
  bytes := PBCodec encode: value.
  c that: label , ' bytes' is: bytes hex equals: hex.
  decoded := PBCodec decode: (Check bytes: hex).
  c that: label , ' value' is: decoded equals: (PBCodec canonical: value).
  c that: label , ' re-encoded' is: (PBCodec encode: decoded) hex equals: hex].
"An Array and an OrderedCollection are written as a list and read back as a PBFrozenList."
c that: 'array reads as PBFrozenList' is: (PBCodec decode: (PBCodec encode: #(1 2))) class equals: PBFrozenList.
c that: 'nested list is frozen' is: ((PBCodec decode: (PBCodec encode: { #(1) })) at: 1) class equals: PBFrozenList.
c that: 'OrderedCollection bytes' is: (PBCodec encode: (OrderedCollection new add: 1; add: 2; yourself)) hex equals: '920102'.
c that: 'canonical of an Array' is: (PBCodec canonical: #(1 2)) equals: (PBFrozenList withAll: #(1 2)).
"msgpack's own non-canonical forms are read: a wider integer and a float 32."
c that: 'int 64 holding 1' is: (PBCodec decode: (Check bytes: 'd30000000000000001')) equals: 1.
c that: 'float 32 holding 1.5' is: (PBCodec decode: (Check bytes: 'ca3fc00000')) equals: 1.5.
c that: 'float 32 re-encodes as float 64' is: (PBCodec encode: (PBCodec decode: (Check bytes: 'ca3fc00000'))) hex equals: 'cb3ff8000000000000'.
c report displayNl.
