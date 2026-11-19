"EXPECT: ok 6"
"The index writes compute each order key once (diag/index-cost): PBMemberKeys
 memberKeyAndOrderKeyOf: answers memberKeyOf: and the order key of that key, PBKeys exactToken:
 answers an atom's constant token without encoding it, and the order key of an atom read from its
 16 oid bytes as two words equals the byte-by-byte reading. Each check gathers its mismatches over
 many elements and requires none. The tree writes that take an order key (keyAt:orderKey:,
 keyPut:key:orderKey:value:nodeClass:, keyRemove:orderKey:) build the same trees as the plain
 ones; idx_keygroups checks build: against the fold of withAdded: node for node."
Import from: 'protobase'.
Import from: '_check'.

| c atoms values fails root1 root2 keys shape |
c := Check new.
atoms := (1 to: 200) asArray collect: [:i | PBObject withAll: { 'id' -> i }].
atoms := atoms , { PBCountedKeyNode key: 1 value: (PBTuple withAll: { 1. 1 }) left: nil right: nil.
  PBEqualityIndex name: 'i' path: 'a' }.
values := atoms , { nil. true. false. 0. 1. 1.0. -7. (2 raisedTo: 80). 0.5. Decimal fromString: '1.00'.
  'text'. ''. #[1 2 3]. PBMissing default. PBTuple withAll: { 1. 'a' }.
  PBTuple withAll: { PBTuple withAll: { 1. 2 }. 3 }. PBFrozenList withAll: #(1 2). PBTuple withAll: { 1. PBFrozenList withAll: #(2) }.
  PBFrozenDict withAssociations: { 'a' -> 1 }. Float nan. PBMutableObject name: 'm'.
  PBTuple withAll: { atoms first. 2 } }.

fails := OrderedCollection new.
values do: [:v |
  | pair |
  pair := PBMemberKeys memberKeyAndOrderKeyOf: v.
  (pair at: 1) = (PBMemberKeys memberKeyOf: v) ifFalse: [fails add: v printString , ' member key'].
  (pair at: 2) = (PBKeys orderKey: (PBMemberKeys memberKeyOf: v)) ifFalse: [fails add: v printString , ' order key'].
  ((pair at: 2) compareWith: (PBKeys orderKey: (pair at: 1))) = 0 ifFalse: [fails add: v printString , ' compare']].
c that: 'memberKeyAndOrderKeyOf: answers memberKeyOf: and its order key' is: fails asArray equals: #().

fails := OrderedCollection new.
values do: [:v |
  | slow fast |
  slow := [MessagePack encode: (PBCodec toWire: v atomRef: PBCodec tokenRef)] on: Error do: [:e | e return: e class].
  fast := [PBKeys exactToken: v] on: Error do: [:e | e return: e class].
  slow = fast ifFalse: [fails add: v printString]].
c that: 'exactToken: answers the encoded token' is: fails asArray equals: #().
c that: 'an atom''s token is {''@ref'': nil}' is: (PBKeys exactToken: atoms first) equals: (MessagePack encode: (PBCodec toWire: atoms first atomRef: PBCodec tokenRef)).

fails := OrderedCollection new.
(atoms collect: [:a | PBKeys _oidBytes: a oid]) , { ByteArray withAll: ((1 to: 16) asArray collect: [:i | 255]). ByteArray withAll: ((1 to: 16) asArray collect: [:i | 0]). #[1 2 3] } do: [:b |
  | slow |
  slow := 0.
  b do: [:x | slow := slow * 256 + x].
  (PBKeys _unsignedBigEndian: b) = slow ifFalse: [fails add: b printString]].
c that: 'oid bytes read as two words equal the bytes read one by one' is: fails asArray equals: #().

"The writes with a given order key make the trees of the plain writes, node for node."
shape := [:root | | out | out := OrderedCollection new.
  PBAvl nodesDo: [:n | out add: { n key. n value. n height. n count. n weight }] over: root. out asArray].
keys := (1 to: 300) asArray collect: [:i | (i * 7919) \\ 101].
root1 := nil. root2 := nil.
keys doWithIndex: [:k :i |
  root1 := (PBAvl keyPut: root1 key: k value: (PBTuple withAll: { i. 1 }) nodeClass: PBCountedKeyNode) at: 1.
  root2 := (PBAvl keyPut: root2 key: k orderKey: (PBKeys orderKey: k) value: (PBTuple withAll: { i. 1 }) nodeClass: PBCountedKeyNode) at: 1].
(1 to: 60) do: [:k |
  root1 := (PBAvl keyRemove: root1 key: k) at: 1.
  root2 := (PBAvl keyRemove: root2 orderKey: (PBKeys orderKey: k)) at: 1].
c that: 'keyPut:/keyRemove: with an order key make the same tree' is: (shape value: root2) equals: (shape value: root1).
c that: 'keyAt:orderKey: finds what keyAt:key: finds' is: ((70 to: 110) collect: [:k | (PBAvl keyAt: root2 orderKey: (PBKeys orderKey: k)) ifNotNil: [:n | n value]]) asArray
  equals: ((70 to: 110) collect: [:k | (PBAvl keyAt: root1 key: k) ifNotNil: [:n | n value]]) asArray.
c report displayNl.
