"EXPECT: ok 35"
"PBHashDictionary writes and the PBSet algebra (plan Task 16; ProtoBase
 hash_dictionaries.py and sets.py at v2.0.0rc1). A hash dictionary is a keyed tree from the
 hash key of a key (PBKeys hashKey:) to a bucket, a tuple of (key, value) tuples (format
 spec, 'Collections'); setAt:value: and removeAt: answer a new version, keys go by order
 key (1, 1.0 and Decimal 1.00 are one key, the stored key object is kept, the last value
 wins), and a bucket emptied by removeAt: leaves the tree. union:, intersection: and
 difference: are folds of add: and remove: (ProtoBase's): union: adds each element of the
 operand in its order, intersection: removes the receiver's members absent from the operand
 in the receiver's order, difference: removes each element of the operand in its order;
 each answers a new version, and the log records each element's intent. The logs expected
 are ProtoBase's for the same calls."
Import from: 'protobase'.
Import from: '_check'.

| c empty h1 h2 h3 gone same node bucket s u i d kinds big |
c := Check new.
kinds := [:aColl | (aColl opLog asArray collect: [:op | (op at: 1) , ' ' , (op at: 2) printString]) asArray].
empty := PBHashDictionary new.
c that: 'a new hash dictionary is empty' is: empty count equals: 0.
c that: 'its fields in ProtoBase''s order' is: empty state keys equals: #('indexes' 'count' 'root').
h1 := empty setAt: 1 value: 'one'.
c that: 'setAt:value: answers the new version' is: (h1 getAt: 1) equals: 'one'.
c that: 'the receiver is unchanged' is: empty count equals: 0.
c that: 'a new oid' isTrue: h1 oid ~= empty oid.
node := h1 stateAt: 'root'.
c that: 'the node key is the hash key of the key' is: node key equals: (PBKeys hashKey: 1).
bucket := node value.
c that: 'the bucket is a tuple' is: bucket class equals: PBTuple.
c that: 'of (key, value) tuples' is: bucket equals: (PBTuple withAll: { PBTuple withAll: #(1 'one') }).
h2 := h1 setAt: 1.0 value: 'uno'.
c that: '1.0 is the key 1' is: h2 count equals: 1.
c that: 'the last value wins' is: (h2 getAt: (Decimal fromString: '1.00')) equals: 'uno'.
c that: 'the stored key object is kept' is: h2 keys first class equals: SmallInteger.
c that: 'h1 is unchanged' is: (h1 getAt: 1) equals: 'one'.
h3 := (h2 setAt: true value: 't') setAt: 'b' value: #(1 2).
c that: 'true is another key' is: h3 count equals: 3.
c that: 'a value is made canonical' is: (h3 getAt: 'b') class equals: PBFrozenList.
gone := h3 removeAt: 1.0.
c that: 'removeAt: answers the new version' is: gone count equals: 2.
c that: 'without the key' is: (gone has: 1) equals: false.
c that: 'an emptied bucket leaves the tree' is: (PBAvl keyAt: (gone stateAt: 'root') key: (PBKeys hashKey: 1)) equals: nil.
c that: 'h3 is unchanged' is: h3 count equals: 3.
same := h3 removeAt: 'absent'.
c that: 'removeAt: an absent key: a new version' isTrue: same ~~ h3.
c that: 'with the same tree' isTrue: (same stateAt: 'root') == (h3 stateAt: 'root').
c that: 'a NaN key' signals: PBValidationError during: [empty setAt: Float nan value: 1].
c that: 'a list key' signals: PBValidationError during: [empty setAt: #(1 2) value: 1].
c that: 'a removeAt: of a NaN key' signals: PBValidationError during: [h3 removeAt: Float nan].
big := String new: PBAvl valueBoxMin withAll: $v.
c that: 'a bucket holds a large value itself (no value box)'
  is: (((empty setAt: 'k' value: big) stateAt: 'root') value at: 1) equals: (PBTuple withAll: { 'k'. big }).

"The set algebra; ProtoBase answers the logs below for the same calls."
s := (PBSet new add: 1) add: 2.
u := (PBSet new add: 1) union: #(2 3).
c that: 'union: adds each element' is: u count equals: 3.
c that: 'union: logs an add per element' is: (kinds value: u) equals: #('add 1' 'add 2' 'add 3').
c that: 'union: of a set' is: ((PBSet new add: 9) union: s) count equals: 3.
i := s intersection: #(2).
c that: 'intersection: keeps the common members' is: i elements equals: #(2).
c that: 'intersection: logs the removes' is: (kinds value: i) equals: #('add 1' 'add 2' 'remove 1').
c that: 'intersection: with a set operand' is: (s intersection: (PBSet new add: 1.0)) elements equals: #(1).
d := s difference: #(2 5).
c that: 'difference: removes the operand''s elements' is: d elements equals: #(1).
c that: 'difference: logs a remove per element' is: (kinds value: d) equals: #('add 1' 'add 2' 'remove 2' 'remove 5').
c that: 'an empty operand: a new version' isTrue: ((s union: #()) ~~ s and: [(s union: #()) opLog size = 2]).
c that: 'an unorderable operand element' signals: PBValidationError during: [s intersection: { Float nan }].
c that: 'a String operand' signals: PBValidationError during: [s union: 'abc'].
c report displayNl.
