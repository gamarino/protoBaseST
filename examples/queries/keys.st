"EXPECT: keys ok (17 checks)"
"Key specs, MISSING and nil. Quoted by docs/queries.md, 'Key specs, MISSING and nil'.

 A key spec names the key of an element: a dotted path, the element itself, or a registered
 extractor (proto_db, indexing/keyspec.py). A path step through an absent attribute yields MISSING
 (PBMissing default), an explicit nil stays nil, and the operators tell them apart as proto_db's
 terms do (decision D28): eq: nil finds the explicit nil only, ne: matches a present key only,
 isNone finds both, notNone neither, and a range compares keys of its own type rank only. An index
 persists its key spec as proto_db's (kind, arg) tuple (keySpec) and answers it as a PBKeySpec
 (keySpecObject); a String is not a key spec (ruling CR3).

 Run it: STPATH=<repository>/src protost keys.st"
Import from: 'protobase'.
Import from: '../tutorial/_lesson'.

| lesson contacts spec zip count byZip element |
lesson := Lesson named: 'keys'.

"Four contacts: Ada's zip is '1010', Bob's an explicit nil, Cy has an address without a zip, Di has
 no address at all."
contacts := (((PBList new
    appendLast: (PBObject withAll: { 'name' -> 'Ada'. 'address' -> (PBFrozenDict withAssociations: { 'zip' -> '1010' }) }))
    appendLast: (PBObject withAll: { 'name' -> 'Bob'. 'address' -> (PBFrozenDict withAssociations: { 'zip' -> nil }) }))
    appendLast: (PBObject withAll: { 'name' -> 'Cy'. 'address' -> (PBFrozenDict withAssociations: {}) }))
    appendLast: (PBObject withAll: { 'name' -> 'Di' }).

spec := PBKeySpec path: 'address.zip'.
lesson check: 'a present zip is its value' is: (spec extract: (contacts getAt: 0)) equals: '1010'.
lesson check: 'an explicit nil stays nil' is: (spec extract: (contacts getAt: 1)) equals: nil.
lesson check: 'an absent zip is MISSING' is: (spec extract: (contacts getAt: 2)) equals: PBMissing default.
lesson check: 'no address at all is MISSING too' is: (spec extract: (contacts getAt: 3)) equals: PBMissing default.
lesson check: 'at: cannot tell absence from nil' is: ((contacts getAt: 3) at: 'address') equals: nil.

zip := PBField path: 'address.zip'.
count := [:condition | ((PBQuery from: contacts) where: condition) count].
lesson check: 'eq: nil finds the explicit nil only' is: (count value: (zip eq: nil)) equals: 1.
lesson check: 'ne: matches a present key only' is: (count value: (zip ne: '1010')) equals: 1.
lesson check: 'isNone finds nil and MISSING' is: (count value: zip isNone) equals: 3.
lesson check: 'notNone finds the rest' is: (count value: zip notNone) equals: 1.
lesson check: 'a range compares keys of its own rank only' is: (count value: zip > 5) equals: 0.

"The element itself as the key: a collection of plain values."
element := PBKeySpec element.
lesson check: 'the element key spec describes itself' is: element describe equals: '<element>'.
lesson check: 'and PBField element queries the values themselves'
    is: ((PBQuery from: (PBList new extend: #(3 1 4 1 5))) where: PBField element > 2) asArray equals: #(3 4 5).

byZip := (contacts addIndex: (PBEqualityIndex name: 'by_zip' keySpec: spec)) getIndex: 'by_zip'.
lesson check: 'keySpec answers the persisted tuple' is: byZip keySpec asArray equals: #('path' 'address.zip').
lesson check: 'keySpecObject answers the key spec' is: byZip keySpecObject equals: spec.
lesson check: 'a String is not a key spec'
    signals: PBValidationError containing: 'must be a PBKeySpec'
    during: [PBEqualityIndex name: 'by_zip' keySpec: 'address.zip'].

"The index answers what the scan answers, MISSING and nil included."
lesson check: 'by the index, isNone is a lookup of two groups'
    is: (((PBQuery from: (contacts addIndex: (PBEqualityIndex name: 'by_zip' keySpec: spec))) where: zip isNone) asArray
        collect: [:p | p at: 'name']) asSortedCollection asArray
    equals: #('Bob' 'Cy' 'Di').
lesson check: 'and its key groups count them apart: one value, nil, MISSING'
    is: (byZip explain at: 'keys') equals: 3.

lesson finish.
