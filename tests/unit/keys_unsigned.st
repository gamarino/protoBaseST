"EXPECT: ok 5"
"PBKeys _unsignedBigEndian: reads the bytes of an oid or of any order-key payload as one
 unsigned big-endian Integer (the high bit is never a sign). Four sizes (0, 8, 16, 33 bytes), each
 with an all-zero, an all-16rFF, an oid-like and a mixed pattern, are checked against the Integer
 the bytes spell, computed here by the plain digit loop (the independent reference). The fifth check
 calls ByteArray >> unsignedIntegerFrom:to:bigEndian: (protoST 0.14.0, below the 0.17.0 floor: no fallback)
 directly on the same arrays, so the test fails on a protoST without the primitive, as _unsignedBigEndian:
 does after it adopts it."
Import from: 'protobase'.
Import from: '_check'.
| c spelled patterns bad direct |
c := Check new.
spelled := [:bytes | | n | n := 0. bytes do: [:b | n := n * 256 + b]. n].
patterns := [:size | | make |
  make := [:block | ByteArray withAll: ((1 to: size) collect: block)].
  { make value: [:i | 0].
    make value: [:i | 16rFF].
    make value: [:i | (i * 37 + 11) \\ 256].
    make value: [:i | i odd ifTrue: [16r80 + (i \\ 7)] ifFalse: [i \\ 3]] }].
bad := OrderedCollection new.
direct := OrderedCollection new.
#(0 8 16 33) do: [:size |
  bad := OrderedCollection new.
  (patterns value: size) do: [:bytes |
    (PBKeys _unsignedBigEndian: bytes) = (spelled value: bytes) ifFalse: [bad add: bytes hex]].
  c that: size printString , ' bytes through _unsignedBigEndian:' is: bad asArray equals: #().
  direct addAll: (patterns value: size)].
bad := OrderedCollection new.
direct do: [:bytes |
  (bytes unsignedIntegerFrom: 1 to: bytes size bigEndian: true) = (spelled value: bytes) ifFalse: [bad add: bytes hex]].
c that: 'unsignedIntegerFrom:to:bigEndian: on the same arrays' is: bad asArray equals: #().
c report displayNl.
