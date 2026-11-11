"EXPECT: ok 26"
"Plan Task 14, Review Focus 2: value boxing (ProtoBase D51, avl.py VALUE_BOX_MIN = 256). A
 node value that is a String of 256 code points or more, or a ByteArray of 256 bytes or
 more, is held through a PBValueBox; shorter ones inline. Strings count code points, not
 bytes: 255 code points of U+00E9 (510 bytes in UTF-8) stay inline. Reads unbox (value,
 posAt:, keyAt:); storedValue shows the box. Keys are never boxed. A path copy keeps the
 box (one box object for the value, as ProtoBase), and a set to a new value boxes anew.
 A new node and a new box have no oid yet (knownOid nil: ProtoBase D21, an oid is drawn on
 first need)."
Import from: 'protobase'.
Import from: '_check'.
| c e255 e256 b255 b256 root boxed k key node box found |
c := Check new.
e255 := String new: 255 withAll: (Character value: 233).
e256 := String new: 256 withAll: (Character value: 233).
b255 := ByteArray withAll: (Array new: 255 withAll: 7).
b256 := ByteArray withAll: (Array new: 256 withAll: 7).
c that: '255 code points are 510 bytes' is: e255 utf8Encoded size equals: 510.
boxed := [:v | ((PBAvl posAppend: nil value: v) storedValue isKindOf: PBValueBox)].
c that: 'a String of 255 code points is inline' is: (boxed value: e255) equals: false.
c that: 'a String of 256 code points is boxed' is: (boxed value: e256) equals: true.
c that: 'a ByteArray of 255 bytes is inline' is: (boxed value: b255) equals: false.
c that: 'a ByteArray of 256 bytes is boxed' is: (boxed value: b256) equals: true.
c that: 'a long ASCII String is boxed' is: (boxed value: (String new: 300 withAll: $a)) equals: true.
c that: 'an Integer is inline' is: (boxed value: (10 raisedTo: 700)) equals: false.
c that: 'a tuple holding a long String is inline' is: (boxed value: (PBTuple withAll: { e256 })) equals: false.
root := PBAvl posAppend: nil value: e256.
c that: 'value unboxes' is: root value equals: e256.
c that: 'the box holds the value' is: root storedValue value equals: e256.
c that: 'posAt: unboxes' is: (PBAvl posAt: root index: 0) equals: e256.
c that: 'a new node has no oid yet' is: root knownOid equals: nil.
c that: 'a new box has no oid yet' is: root storedValue knownOid equals: nil.
box := root storedValue.
root := PBAvl posInsert: root at: 0 value: 1.
root := PBAvl posInsert: root at: 0 value: 2.
found := nil.
PBAvl nodesDo: [:n | (n storedValue isKindOf: PBValueBox) ifTrue: [found := n storedValue]] over: root.
c that: 'a path copy keeps the same box' isTrue: found == box.
c that: 'and reads the value' is: (PBAvl posAt: root index: 2) equals: e256.
root := PBAvl posSet: root at: 2 value: e256 copy.
found := nil.
PBAvl nodesDo: [:n | (n storedValue isKindOf: PBValueBox) ifTrue: [found := n storedValue]] over: root.
c that: 'a set boxes the new value in a new box' isTrue: (found ~~ box and: [found value = e256]).
"Keyed trees: the value is boxed, the key never."
key := String new: 300 withAll: $k.
root := (PBAvl keyPut: nil key: key value: b256 nodeClass: PBKeyNode) first.
node := PBAvl keyAt: root key: key.
c that: 'a long key is not boxed' is: (node key isKindOf: PBValueBox) equals: false.
c that: 'the key is the String' is: node key equals: key.
c that: 'a keyed value is boxed' is: (node storedValue isKindOf: PBValueBox) equals: true.
c that: 'and reads unboxed' is: node value equals: b256.
root := (PBAvl keyPut: root key: key value: b255 nodeClass: PBKeyNode) first.
c that: 'a short replacement is inline' is: (PBAvl keyAt: root key: key) storedValue equals: b255.
k := (PBAvl keyPut: nil key: 1 value: (PBTuple withAll: { e256. 3 }) nodeClass: PBCountedKeyNode) first.
c that: 'a weighted pair is never boxed' is: (k storedValue isKindOf: PBValueBox) equals: false.
c that: 'and counts' is: k weight equals: 3.
c that: 'the box type' is: PBValueBox typeName equals: 'proto_db.avl.ValueBox'.
c that: 'the threshold' is: PBAvl valueBoxMin equals: 256.
c that: 'check: accepts boxed values' is: (PBAvl check: root) == root equals: true.
c report displayNl.
