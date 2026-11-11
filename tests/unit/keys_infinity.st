"EXPECT: ok 10"
"Infinite map keys (review I1 of plan Task 13). The order key of an infinity is rank 3
 with a private mark as payload (PBOrderKey posInf / negInf), never a Symbol: a short
 Symbol is the equal String in protoST (STATUS D35), so a Symbol mark could not be hashed
 and a map keyed by Float infinity could be neither built nor read. As in ProtoBase
 (map_key_ids gives (3, inf)), Float infinity and Decimal Infinity are one key, and the
 infinities order below and above every number. A ProtoBase-written map keyed by
 infinities is read by tests/interop/py_to_st.sh."
Import from: 'protobase'.
Import from: '_check'.

| c inf ninf map dinf |
c := Check new.
inf := Float infinity.
ninf := Float infinity negated.
dinf := Decimal fromString: 'Infinity'.
c that: 'the order key of infinity hashes' is: (PBKeys orderKey: inf) hash equals: (PBKeys orderKey: inf) hash.
c that: 'Float and Decimal infinity: one order key' is: (PBKeys orderKey: inf) equals: (PBKeys orderKey: dinf).
c that: 'and one hash' is: (PBKeys orderKey: inf) hash equals: (PBKeys orderKey: dinf) hash.
c that: '-inf below a huge negative' is: (PBKeys compare: ninf with: (10 raisedTo: 400) negated) equals: -1.
c that: 'inf above a huge number' is: (PBKeys compare: inf with: (10 raisedTo: 400)) equals: 1.
map := PBFrozenDict withAssociations: { inf -> 'up'. ninf -> 'down'. 2 -> 'two' }.
c that: 'a map keyed by infinities' is: (map at: inf) equals: 'up'.
c that: 'found by Decimal Infinity' is: (map at: dinf) equals: 'up'.
c that: 'the negative one' is: (map at: ninf) equals: 'down'.
c that: 'round trip through the codec' is: ((PBCodec decode: (PBCodec encode: map)) at: inf) equals: 'up'.
c that: 'Float and Decimal infinity conflict as keys' signals: PBValidationError during: [
  PBFrozenDict withAssociations: { inf -> 1. dinf -> 2 }].
c report displayNl.
