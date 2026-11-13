"EXPECT: ok 90"
"The fast paths of the record codec give the bytes and values of the general walk:
 PBCodec wireOfCanonical:atomRef: (what PBAtomEnvelope >> encode writes for each attribute)
 against _wire:ref:, and PBCodec fromWireValue:resolver: (what PBAtomEnvelope decode reads
 for each attribute) against fromWire:resolver:, over the scalars at their boundaries (the
 msgpack integer range and past it, floats with payload NaNs, -0.0 and infinities, strings,
 Booleans, nil), a reference, and containers (which take the general walk)."
Import from: 'protobase'.
Import from: 'decimal'.
Import from: '_check'.

| c base st atom ref values floats |
c := Check new.
base := FileSystem temp / ('pbst-codec-fast-' , Smalltalk pid printString).
base deleteAll.
st := PBFileStorage path: base pathString.
atom := PBObject withAll: { 'x' -> 1 }.
st save: atom.
ref := PBCodec pointerRef.
floats := #( 'cb7ff8000000000001' 'cb8000000000000000' 'cb7ff0000000000000' 'cbfff0000000000000' 'cb0000000000000001' )
  collect: [:hex | PBCodec decode: (Check bytes: hex)].
values := { nil. true. false. 0. 1. -1. 127. 128. -32. -33. 255. 256. 65535. 65536.
  4294967295. 4294967296. -2147483648. -2147483649.
  PBCodec _intMin. PBCodec _intMax. PBCodec _intMin - 1. PBCodec _intMax + 1. (2 raisedTo: 200). (2 raisedTo: 200) negated.
  0.0. 1.5. -2.25. 1.0e300. ''. 'a'. 'ñandú'. (String new: 40 withAll: $x). 'äö€😀'.
  (ByteArray withAll: #(1 2 3)). (Decimal fromString: '1.25'). (PBFrozenList withAll: #()). (PBFrozenList withAll: { 1. 'a' }).
  (PBTuple withAll: { 1. 2 }). (PBFrozenDict withAssociations: { 'k' -> 1 }). atom } , floats.
values do: [:v |
  | fast general |
  fast := MessagePack encode: (PBCodec wireOf: v atomRef: ref for: 'v').
  general := MessagePack encode: (PBCodec _wire: v ref: ref).
  c that: 'encode ' , v printString is: fast hex equals: general hex].
values do: [:v |
  | tree fast general |
  tree := PBCodec _wire: v ref: ref.
  fast := PBCodec fromWireValue: tree resolver: st.
  general := PBCodec fromWire: tree resolver: st.
  c that: 'decode ' , v printString is: (MessagePack encode: (PBCodec _wire: fast ref: ref)) hex
    equals: (MessagePack encode: (PBCodec _wire: general ref: ref)) hex].
st close.
base deleteAll.
c report displayNl.
