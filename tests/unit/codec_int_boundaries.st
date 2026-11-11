"EXPECT: ok 24"
"Review Focus 4: the integer boundaries are written native or @int exactly as
 FS 'Canonical values' requires (-2^63 <= n <= 2^64 - 1 is native), and read
 back to the same Integer and the same bytes."
Import from: 'protobase'.
Import from: '_check'.
| c p63 p64 |
c := Check new.
p63 := 2 raisedTo: 63.
p64 := 2 raisedTo: 64.
{
  { '2^63-1'. p63 - 1. 'cf7fffffffffffffff' }.
  { '2^63'. p63. 'cf8000000000000000' }.
  { '2^64-1'. p64 - 1. 'cfffffffffffffffff' }.
  "{'@int': '10000000000000000'}"
  { '2^64'. p64. '81a440696e74b13130303030303030303030303030303030' }.
  { '-2^63'. p63 negated. 'd38000000000000000' }.
  "{'@int': '-8000000000000001'}"
  { '-2^63-1'. p63 negated - 1. '81a440696e74b12d38303030303030303030303030303031' }.
  { '2^200'. 2 raisedTo: 200. '81a440696e74d933313030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030' }.
  { '-2^200'. (2 raisedTo: 200) negated. '81a440696e74d9342d313030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030' }
} do: [:each |
  | decoded |
  c that: (each at: 1) , ' bytes' is: (PBCodec encode: (each at: 2)) hex equals: (each at: 3).
  decoded := PBCodec decode: (Check bytes: (each at: 3)).
  c that: (each at: 1) , ' value' is: decoded equals: (each at: 2).
  c that: (each at: 1) , ' re-encoded' is: (PBCodec encode: decoded) hex equals: (each at: 3)].
c report displayNl.
