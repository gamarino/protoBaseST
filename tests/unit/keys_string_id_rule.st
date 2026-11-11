"EXPECT: ok 17"
"Fix round 1 of plan Task 14 (review M4): PBMapKeyIndex files a plain String (not a Symbol)
 under the String itself instead of PBKeys _keyId: s mode: #read, to skip the type tests
 on every attribute read. That is only right while the #read id of a plain String is its
 order key (rank 4, the String itself), and no other key's id is a String. This test pins
 both, for ASCII, non-ASCII and empty Strings, and checks a map that mixes Strings with
 Integers, Floats and tuples, looked up by every kind: if String order keys ever change
 (a normalization, say), it fails rather than letting the two paths split."
Import from: 'protobase'.
Import from: '_check'.
| c strings map tuple |
c := Check new.
strings := { 'abc'. String new: 3 withAll: (Character value: 233). ''. 'a b' }.
strings do: [:s |
  c that: 'the #read id of ' , s printString , ' is its order key' is: (PBKeys _keyId: s mode: #read) equals: (PBOrderKey rank: 4 payload: s).
  c that: 'whose payload is the String' is: (PBKeys _keyId: s mode: #read) _payload equals: s].
c that: 'no id of another key is a String' isTrue: ({ 1. 2.5. true. nil. PBTuple withAll: #('a'). #at:put:. ByteArray new: 1 }
  allSatisfy: [:k | (PBMapKeyIndex _idOf: k) isString not]).
tuple := PBTuple withAll: #('a' 1).
map := PBFrozenDict withAssociations: { 'a' -> 1. 2 -> 2. 2.5 -> 3. tuple -> 4. '' -> 5. (strings at: 2) -> 6 }.
c that: 'a String key' is: (map at: 'a') equals: 1.
c that: 'an Integer key by a Float' is: (map at: 2.0) equals: 2.
c that: 'a Float key' is: (map at: 2.5) equals: 3.
c that: 'a tuple key by an equal tuple' is: (map at: (PBTuple withAll: { 'a'. 1.0 })) equals: 4.
c that: 'the empty String' is: (map at: '') equals: 5.
c that: 'a non-ASCII String' is: (map at: (String new: 3 withAll: (Character value: 233))) equals: 6.
c that: 'a Symbol (#at:put:) is a Symbol here' is: #at:put: isSymbol equals: true.
c that: 'a Symbol is not the String' is: ((PBFrozenDict withAssociations: { 'at:put:' -> 1 }) at: #at:put: ifAbsent: ['absent']) equals: 'absent'.
c report displayNl.
