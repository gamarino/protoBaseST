"EXPECT: ok 34"
"Atom weight, stage 1 (plan Task 11; spec 4.1, decision 3 as amended 2026-11-19). An atom's
 runtime-only fields (oid, saved, memo, and a keyed node's order key; an index's key spec
 object) are instance variables written once, by a compare-and-swap from nil on the variable
 itself, not Atom cells: a node holds no Atom in any instance variable, before or after its
 oid is drawn, its order key read and its record saved. Each publisher installs one value
 and answers the installed one: raced by two actors, both callers answer the same value, one
 of the two offered, whatever the interleaving (nothing here depends on timing); published
 again with another value, it keeps and answers the first. And PBTuple _trustedOn:, the
 constructor that keeps a fresh Array instead of copying it, makes the tuple withAll: makes."
Import from: 'protobase'.
Import from: '_check'.

"Publishes aValue into anAtom by aSelector (one of the write-once publishers), on an actor."
Object subclass: #Publisher.
Publisher >> publish: aSelector on: anAtom value: aValue
  ^ anAtom perform: aSelector with: aValue.

| c ok v node holdsAtom base storage race twice envelope place stub blank won |
c := Check new.
"Whether an instance variable of anObject holds an Atom."
holdsAtom := [:anObject |
  anObject class allInstVarNames anySatisfy: [:name | (anObject instVarNamed: name) isKindOf: Atom]].

"A node holds no Atom: built, then with its oid drawn and its order key read, then saved."
ok := PBKeys orderKey: 5.
v := PBTuple withAll: { 'payload'. 1 }.
node := PBCountedKeyNode key: 5 orderKey: ok value: v left: nil right: nil.
c that: 'a built node holds no Atom' is: (holdsAtom value: node) equals: false.
c that: 'it holds the order key it was built with' isTrue: node knownOrderKey == ok.
c that: 'it has no oid before the first need' is: node knownOid equals: nil.
node oid.
node orderKey.
c that: 'nor once its oid is drawn' is: (holdsAtom value: node) equals: false.
c that: 'the drawn oid is kept' isTrue: node knownOid == node oid.
base := FileSystem temp / ('pbst-atom-weight-' , Smalltalk pid printString).
base deleteAll.
[
  storage := PBFileStorage path: (base / 'space') pathString.
  node _saveInto: storage.
  c that: 'nor once it is saved' is: (holdsAtom value: node) equals: false.
  c that: 'the saved node has a pointer' isTrue: node pointer notNil.
  stub := PBCountedKeyNode unloadedAt: node pointer storage: storage.
  c that: 'a stub holds no Atom' is: (holdsAtom value: stub) equals: false.
  c that: 'a stub loads its oid' is: stub oid equals: node oid.
  c that: 'a stub fills its order key on first use' is: stub orderKey equals: ok.
  c that: 'nor once loaded' is: (holdsAtom value: stub) equals: false.
  c that: 'an index holds no Atom' is: (holdsAtom value: (PBEqualityIndex name: 'i' path: 'a')) equals: false.
  c that: 'a record holds no Atom' is: (holdsAtom value: (PBObject withAll: { 'a' -> 1 })) equals: false.

  "PBTuple _trustedOn: makes the tuple withAll: makes."
  c that: '_trustedOn: equals withAll:' is: (PBTuple _trustedOn: { 1. 'two'. nil }) equals: (PBTuple withAll: { 1. 'two'. nil }).
  c that: '_trustedOn: makes a PBTuple' isTrue: (PBTuple _trustedOn: { 1 }) class == PBTuple.

  "race value: aSelector value: aBlank value: a value: b: two actors publish a and b into the fresh
   aBlank at once (aSelector is one of the write-once publishers); answers the value both
   answered when they answered the same one, a or b, and nil otherwise."
  race := [:aSelector :aBlank :a :b |
    | f1 f2 r1 r2 |
    f1 := Publisher new asActor publish: aSelector on: aBlank value: a.
    f2 := Publisher new asActor publish: aSelector on: aBlank value: b.
    r1 := f1 wait.
    r2 := f2 wait.
    (r1 == r2 and: [r1 == a or: [r1 == b]]) ifTrue: [r1] ifFalse: [nil]].
  "twice value: aSelector value: aBlank value: a value: b: publishes a, then b; answers whether
   both publications answered a."
  twice := [:aSelector :aBlank :a :b |
    (aBlank perform: aSelector with: a) == a and: [(aBlank perform: aSelector with: b) == a]].
  envelope := [PBAtomEnvelope basicNew _setTag: nil oid: nil state: (PBFrozenDict withAssociations: #()) slots: #()].
  place := [:offset | _PBPlace pointer: (PBAtomPointer segment: (ByteArray new: 16) offset: offset) storage: storage].

  "oid"
  blank := PBObject basicNew.
  won := race value: #_publishOid: value: blank value: (ByteArray new: 16) value: (ByteArray new: 16).
  c that: 'raced oids: both answer the installed one' isTrue: (won notNil and: [won == blank knownOid]).
  c that: 'oid answers it' isTrue: blank oid == won.
  c that: 'an oid is installed once' isTrue:
    (twice value: #_publishOid: value: PBObject basicNew value: (ByteArray new: 16) value: (ByteArray new: 16)).

  "saved"
  blank := PBObject basicNew.
  won := race value: #_publishSaved: value: blank value: (place value: 64) value: (place value: 128).
  c that: 'raced places: both answer the installed one' isTrue: (won notNil and: [won pointer == blank pointer]).
  c that: 'the storage is the place''s' isTrue: blank _storage == storage.
  c that: 'a place is installed once' isTrue:
    (twice value: #_publishSaved: value: PBObject basicNew value: (place value: 64) value: (place value: 128)).

  "memo"
  blank := PBObject basicNew.
  won := race value: #_publishMemo: value: blank value: envelope value value: envelope value.
  c that: 'raced envelopes: both answer the installed one' isTrue: (won notNil and: [won == blank _envelope]).
  c that: 'the atom is loaded' isTrue: blank isLoaded.
  c that: 'an envelope is installed once' isTrue:
    (twice value: #_publishMemo: value: PBObject basicNew value: envelope value value: envelope value).

  "order key"
  blank := PBCountedKeyNode basicNew.
  won := race value: #_publishOrderKey: value: blank value: (PBKeys orderKey: 1) value: (PBKeys orderKey: 1).
  c that: 'raced order keys: both answer the installed one' isTrue: (won notNil and: [won == blank knownOrderKey]).
  c that: 'an order key is installed once' isTrue:
    (twice value: #_publishOrderKey: value: PBCountedKeyNode basicNew value: (PBKeys orderKey: 1) value: (PBKeys orderKey: 2)).

  "key spec object"
  blank := PBEqualityIndex basicNew.
  won := race value: #_publishKeySpec: value: blank value: (PBKeySpec path: 'a') value: (PBKeySpec path: 'b').
  c that: 'raced key specs: both answer the installed one' isTrue: (won notNil and: [won == blank keySpecObject]).
  c that: 'a key spec is installed once' isTrue:
    (twice value: #_publishKeySpec: value: PBEqualityIndex basicNew value: (PBKeySpec path: 'a') value: (PBKeySpec path: 'b')).

  "_setOid:pointer:storage: runs once: not on an atom whose oid was drawn or given."
  blank := PBObject basicNew.
  blank oid.
  c that: 'a second _setOid: after an oid was drawn' signals: PBUserError during: [blank _setOid: (ByteArray new: 16) pointer: nil storage: nil].
  blank := PBObject basicNew _setOid: (ByteArray new: 16) pointer: nil storage: nil.
  c that: 'a second _setOid: after an oid was given' signals: PBUserError during: [blank _setOid: nil pointer: nil storage: nil].

  "A blank atom reads nil in every write-once field."
  c that: 'a blank atom has no oid' is: PBObject basicNew knownOid equals: nil.
  c that: 'nor a pointer' is: PBObject basicNew pointer equals: nil.
  c that: 'nor a state' is: PBObject basicNew isLoaded equals: false.
  c that: 'a blank node has no order key' is: PBCountedKeyNode basicNew knownOrderKey equals: nil.
] ensure: [
  storage isNil ifFalse: [storage close].
  base deleteAll].
c report displayNl.
