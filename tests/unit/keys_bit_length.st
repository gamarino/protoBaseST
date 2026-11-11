"EXPECT: ok 23"
"FS 'Hash keys': bit_length is the bits of |v| (Python's int.bit_length, never
 Smalltalk's highBit of a negative), and an integer payload is fed as its
 two's-complement little-endian bytes of length bit_length // 8 + 1, preceded
 by that length as 8 bytes little-endian. residue: is the modular arithmetic of
 the numeric rank (P = 2^61 - 1), checked against n * d^(P-2) mod P built with
 raisedTo:modulo:, including the two numbers whose native hash is -2."
Import from: 'protobase'.
Import from: '_check'.
| c p ref |
c := Check new.
p := (2 raisedTo: 61) - 1.
{ 0 -> 0. -1 -> 1. 255 -> 8. -128 -> 8. p -> 61. 256 -> 9. (2 raisedTo: 64) negated -> 65 } do: [:each |
  c that: 'bitLength: ' , each key printString is: (PBKeys bitLength: each key) equals: each value].
{ 0 -> '00'. 255 -> 'ff00'. -1 -> 'ff'. -127 -> '81'. -128 -> '80ff'. 127 -> '7f'. 128 -> '8000' } do: [:each |
  c that: 'signedBytes: ' , each key printString is: (PBKeys signedBytes: each key) hex asLowercase equals: each value].
c that: 'the feed of the integer 255 (rank 9)' is: (PBKeys feed: (PBOrderKey rank: 9 payload: 255)) hex asLowercase
  equals: '090200000000000000ff00'.
ref := [:n :d | n * (d raisedTo: p - 2 modulo: p) \\ p].
c that: 'residue: of -3/7' is: (PBKeys residue: -3 / 7) equals: (ref value: -3 value: 7).
c that: 'residue: of Decimal -1.0 (native hash -2)' is: (PBKeys residue: (Decimal fromString: '-1.0')) equals: p - 1.
c that: 'residue: of Decimal -2 (native hash -2)' is: (PBKeys residue: (Decimal fromString: '-2')) equals: p - 2.
c that: 'residue: of -1/3' is: (PBKeys residue: -1 / 3) equals: (ref value: -1 value: 3).
c that: 'residue: of Decimal 1E+999999999999' is: (PBKeys residue: (Decimal fromString: '1E+999999999999'))
  equals: (10 raisedTo: 999999999999 modulo: p).
c that: 'residue: of -1' is: (PBKeys residue: -1) equals: p - 1.
c that: 'residue: of 1/2 times 2' is: (PBKeys residue: 1 / 2) * 2 \\ p equals: 1.
c that: 'residue: of Decimal 0.5 is that of 1/2' is: (PBKeys residue: (Decimal fromString: '0.5')) equals: (PBKeys residue: 1 / 2).
c report displayNl.
