"EXPECT: ok 26"
"The read set of a transaction (plan Task 13, design spec 7.1, ProtoBase get_root_object
 and _token), on a copy of the database vector: the first read of a root records its
 token (an atom's storage pointer, a plain value's exact token, #absent for an absent
 name); reading again changes nothing; rootNames and mutableNames record nothing;
 getMutable: records in the mutable read set. A transaction reads the version that was
 current when it started. Tokens tell apart values that are equal keys: 1 and 1.0,
 Decimal 1 and Decimal 1.00; a value holding atoms is its exact token and the atoms'
 pointers."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_spaces'.

| c base space db tx people invoice reads list token b first second later |
c := Check new.
base := FileSystem temp / ('pbst-tx-read-set-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
'../conformance/vectors/database' asFileReference files do: [:f | f copyTo: base / f basename].
space := PBObjectSpace storage: (PBFileStorage path: base).
db := space openDatabase: 'db'.
tx := db newTransaction.
c that: 'nothing read yet' is: tx readSet size equals: 0.
c that: 'rootNames' is: tx rootNames asArray
  equals: #('bag' 'hash' 'hnsw' 'invoice' 'ivf' 'multi' 'people' 'set' 'tags' 'vectors').
c that: 'rootNames records nothing' is: tx readSet size equals: 0.
people := tx getRootObject: 'people'.
invoice := tx getRootObject: 'invoice'.
c that: 'an absent root reads nil' is: (tx getRootObject: 'nope') equals: nil.
reads := tx readSet.
c that: 'three entries' is: reads size equals: 3.
c that: 'the read set is a PBFrozenDict' is: reads class equals: PBFrozenDict.
c that: 'an atom''s token is its pointer' is: (reads at: 'people') equals: people pointer.
c that: 'the record''s too' is: (reads at: 'invoice') equals: invoice pointer.
c that: 'an absent name''s token' is: (reads at: 'nope') == #absent equals: true.
tx getRootObject: 'people'. tx getRootObject: 'nope'. tx getRootObject: 'invoice'.
c that: 'reading again changes nothing' is: tx readSet equals: reads.
c that: 'the same tokens' is: (tx readSet at: 'people') equals: people pointer.
c that: 'the snapshot value again' is: (tx getRootObject: 'people') pointer equals: people pointer.
"Mutable cells."
c that: 'mutableNames' is: tx mutableNames asArray equals: #('counter').
c that: 'mutableNames records nothing' is: tx mutableReadSet size equals: 0.
c that: 'getMutable:' is: ((PBMutableObject name: 'counter') get: tx) equals: 5.
c that: 'a plain value''s token is its exact token' is: (tx mutableReadSet at: 'counter') equals: (PBKeys exactToken: 5).
c that: 'an absent cell' is: (tx getMutable: 'nope') equals: nil.
c that: 'two mutable entries' is: tx mutableReadSet keys asArray equals: #('counter' 'nope').
c that: 'the root read set is apart' is: tx readSet size equals: 3.
"Tokens."
c that: '1 and 1.0' isTrue: (tx _tokenOf: 1) ~= (tx _tokenOf: 1.0).
c that: 'Decimal 1 and 1.00' isTrue: (tx _tokenOf: (Decimal fromString: '1')) ~= (tx _tokenOf: (Decimal fromString: '1.00')).
list := PBCodec canonical: { 1. people. PBTuple withAll: { invoice } }.
token := tx _tokenOf: list.
c that: 'a value holding atoms' is: token
  equals: (PBTuple withAll: { PBKeys exactToken: list. PBTuple withAll: { people pointer. invoice pointer } }).
tx abort.
space close.
"Snapshot reads: a transaction keeps the version current when it started, even after
 space.root moves on (here rewritten to another SpaceRoot of the same segment)."
b := SpaceBuilder segment: (ByteArray fromHex: '2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b').
first := b spaceWithDatabase: 'db' roots: { 'x' -> 1 } mutables: #() oids: 10.
second := b spaceWithDatabase: 'db' roots: { 'x' -> 2. 'y' -> 3 } mutables: #() oids: 60.
space := PBObjectSpace storage: (PBFileStorage path: (b writeTo: base / 'moving' root: first)).
tx := (space openDatabase: 'db') newTransaction.
b writeTo: base / 'moving' root: second.
later := (space openDatabase: 'db') newTransaction.
c that: 'the started transaction reads its version' is: (tx getRootObject: 'x') equals: 1.
c that: 'and its names' is: tx rootNames asArray equals: #('x').
c that: 'a later transaction reads the new one' is: (later getRootObject: 'x') equals: 2.
c that: 'a plain root''s token' is: (tx readSet at: 'x') equals: (PBKeys exactToken: 1).
tx abort. later abort.
space close.
base deleteAll.
c report displayNl.
