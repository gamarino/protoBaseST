"EXPECT: ok 7"
"Fresh oids come from _PBOidPool: the 16 bytes of version-4 UUIDs (the version nibble 4,
 the variant bits 2r10), drawn from the operating system's generator a batch at a time.
 Every draw is distinct, on one thread and on several actors drawing at once (the pool is
 an Atom replaced by compare-and-swap), across many batches, and an atom's oid is one."
Import from: 'protobase'.
Import from: '_check'.

Object subclass: #Drawer.
Drawer >> draw: n
  ^ (1 to: n) asArray collect: [:i | _PBOidPool next].

| c draws v4 actors seen all |
c := Check new.
v4 := [:b | b size = 16 and: [((b at: 7) bitShift: -4) = 4 and: [((b at: 9) bitShift: -6) = 2]]].
draws := (1 to: 1000) asArray collect: [:i | _PBOidPool next].
c that: '1000 draws are version-4 UUIDs' isTrue: (draws allSatisfy: [:b | v4 value: b]).
c that: 'and distinct' is: (draws collect: [:b | b hex]) asSet size equals: 1000.
c that: 'they span batches' isTrue: 1000 > _PBOidPool batchSize.
actors := (1 to: 4) collect: [:i | Drawer new asActor].
all := ((actors collect: [:a | a draw: 500]) collect: [:f | f wait]) inject: #() into: [:acc :each | acc , each].
c that: '4 actors drawing at once get 2000 oids' is: all size equals: 2000.
seen := (all , draws) collect: [:b | b hex].
c that: 'all distinct, from the earlier ones too' is: seen asSet size equals: 3000.
c that: 'and version-4' isTrue: (all allSatisfy: [:b | v4 value: b]).
c that: 'an atom''s oid is one' isTrue: (v4 value: (PBObject withAll: { 'a' -> 1 }) oid).
c report displayNl.
