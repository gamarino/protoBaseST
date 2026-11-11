"EXPECT: ok 26"
"PBDictionary writes (plan Task 15; ProtoBase Dictionary set_at and remove_at): PBDictionary
 new, setAt:value: and removeAt: each answer a new dictionary, a new atom with its own oid,
 and leave the receiver as it was. Keys go by their order key: 1, 1.0 and Decimal 1.00 are
 one key (the first key object is kept, the last value wins) and true another. A key that
 is not orderable (a NaN, a list, a map; design spec 10.5) is PBValidationError, and so is
 a value the codec refuses. removeAt: of an absent key answers a new version with the same
 content, as ProtoBase's. An unsaved record is a key like any other (its oid). PBSet add:
 and remove: follow the same rules (plan Task 15 needs them for discarded_result.st; the
 set algebra and the operation logs come with Task 16)."
Import from: 'protobase'.
Import from: '_check'.

| c empty d1 d2 d3 gone same rec keyed s1 s2 |
c := Check new.
empty := PBDictionary new.
c that: 'a new dictionary is empty' is: empty count equals: 0.
c that: 'its fields in ProtoBase''s order' is: empty state keys equals: #('indexes' 'count' 'root').
d1 := empty setAt: 1 value: 'one'.
c that: 'setAt:value: answers the new version' is: (d1 getAt: 1) equals: 'one'.
c that: 'the receiver is unchanged' is: empty count equals: 0.
c that: 'a new oid' isTrue: d1 oid ~= empty oid.
d2 := d1 setAt: 1.0 value: 'uno'.
c that: '1.0 is the key 1' is: d2 count equals: 1.
c that: 'the last value wins' is: (d2 getAt: (Decimal fromString: '1.00')) equals: 'uno'.
c that: 'the stored key object is kept' is: d2 keys first class equals: SmallInteger.
c that: 'd1 is unchanged' is: (d1 getAt: 1) equals: 'one'.
d3 := (d2 setAt: true value: 't') setAt: 'b' value: #(1 2).
c that: 'true is another key' is: d3 count equals: 3.
c that: 'key order: bool, number, string' is: d3 keys equals: { true. 1. 'b' }.
c that: 'a value is made canonical' is: (d3 getAt: 'b') class equals: PBFrozenList.
gone := d3 removeAt: 1.0.
c that: 'removeAt: answers the new version' is: gone keys equals: { true. 'b' }.
c that: 'd3 is unchanged' is: d3 count equals: 3.
same := d3 removeAt: 'absent'.
c that: 'removeAt: an absent key: a new version' isTrue: same ~~ d3.
c that: 'with the same content' is: same items equals: d3 items.
c that: 'and the same tree' isTrue: (same stateAt: 'root') == (d3 stateAt: 'root').
c that: 'a NaN key (spec 10.5)' signals: PBValidationError during: [empty setAt: Float nan value: 1].
c that: 'a list key' signals: PBValidationError during: [empty setAt: #(1 2) value: 1].
c that: 'a removeAt: of a NaN key' signals: PBValidationError during: [d3 removeAt: Float nan].
c that: 'a refused value' signals: PBValidationError during: [empty setAt: 1 value: #sym:bol:].
rec := PBObject withAll: { 'n' -> 1 }.
keyed := empty setAt: rec value: 'record'.
c that: 'an unsaved record is a key' is: (keyed getAt: rec) equals: 'record'.
c that: 'another record is another key' is: (keyed getAt: (rec with: 'n' value: 1)) equals: nil.
"PBSet add: and remove:"
s1 := (PBSet new add: 1) add: 'x'.
s2 := s1 add: 1.0.
c that: 'add: of a present element: a new version' isTrue: (s2 ~~ s1 and: [s2 count = 2]).
c that: 'remove:' is: ((s1 remove: (Decimal fromString: '1')) has: 1) equals: false.
c that: 'remove: of an absent element: the same content' is: (s1 remove: 99) count equals: 2.
c report displayNl.
