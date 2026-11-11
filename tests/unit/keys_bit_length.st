"EXPECT: ok 21"
"FS 'Hash keys': bit_length is the bits of |v| (Python's int.bit_length, never
 Smalltalk's highBit of a negative), and an integer payload is fed as its
 two's-complement little-endian bytes of length bit_length // 8 + 1, preceded
 by that length as 8 bytes little-endian. modPow: and residue: are the modular
 arithmetic of the numeric rank (P = 2^61 - 1)."
Import from: 'protobase'.
Import from: '_check'.
| c p |
c := Check new.
p := (2 raisedTo: 61) - 1.
{ 0 -> 0. -1 -> 1. 255 -> 8. -128 -> 8. p -> 61. 256 -> 9. (2 raisedTo: 64) negated -> 65 } do: [:each |
  c that: 'bitLength: ' , each key printString is: (PBKeys bitLength: each key) equals: each value].
{ 0 -> '00'. 255 -> 'ff00'. -1 -> 'ff'. -127 -> '81'. -128 -> '80ff'. 127 -> '7f'. 128 -> '8000' } do: [:each |
  c that: 'signedBytes: ' , each key printString is: (PBKeys signedBytes: each key) hex asLowercase equals: each value].
c that: 'the feed of the integer 255 (rank 9)' is: (PBKeys feed: (PBOrderKey rank: 9 payload: 255)) hex asLowercase
  equals: '090200000000000000ff00'.
c that: 'modPow: 3^200 mod 1000' is: (PBKeys modPow: 3 exp: 200 mod: 1000) equals: ((3 raisedTo: 200) \\ 1000).
c that: 'modPow: x^0' is: (PBKeys modPow: 12345 exp: 0 mod: p) equals: 1.
c that: 'modPow: a huge exponent' is: ((PBKeys modPow: 10 exp: (10 raisedTo: 18) mod: p) between: 0 and: p - 1) equals: true.
c that: 'residue: of -1' is: (PBKeys residue: -1) equals: p - 1.
c that: 'residue: of 1/2 times 2' is: (PBKeys residue: 1 / 2) * 2 \\ p equals: 1.
c that: 'residue: of Decimal 0.5 is that of 1/2' is: (PBKeys residue: (Decimal fromString: '0.5')) equals: (PBKeys residue: 1 / 2).
c report displayNl.
