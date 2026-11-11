"EXPECT: ok 28"
"Floats keep their 64 bits through a round trip: NaNs with payloads (quiet and
 signaling), -0.0, both infinities, the smallest and the largest subnormal,
 and the largest finite float."
Import from: 'protobase'.
Import from: '_check'.
| c |
c := Check new.
#( 'cb7ff8000000000001' 'cb7ff0000000000001' 'cbfff8000000000000' 'cb7ff8000000000000'
   'cb8000000000000000' 'cb7ff0000000000000' 'cbfff0000000000000' 'cb0000000000000001'
   'cb000fffffffffffff' 'cb800fffffffffffff' 'cb7fefffffffffffff' 'cb0000000000000000' ) do: [:hex |
  | f |
  f := PBCodec decode: (Check bytes: hex).
  c that: hex , ' is a Float' isTrue: f isFloat.
  c that: hex , ' round trip' is: (PBCodec encode: f) hex equals: hex].
"Through the wire tree as well (toWire:atomRef: and fromWire:resolver:)."
#( 'cb7ff8000000000001' 'cb8000000000000000' ) do: [:hex |
  | f tree |
  f := PBCodec decode: (Check bytes: hex).
  tree := PBCodec toWire: f atomRef: PBCodec pointerRef.
  c that: hex , ' wire tree' is: (MessagePack encode: tree) hex equals: hex.
  c that: hex , ' from the tree' is: (PBCodec encode: (PBCodec fromWire: tree resolver: nil)) hex equals: hex].
c report displayNl.
