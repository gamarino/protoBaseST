"EXPECT: merge indexed ok (9 checks)"
"A blind write merged onto an indexed root. Quoted by docs/queries.md, 'Merges of blind writes'.

 Two transactions write the root 'people' blind (a dictionary built from new, chapter 6) while it
 holds 600 people indexed by city. Each commit merges by replaying its intents through the current
 version's mutators, which maintain the current version's indexes (proto_db,
 collections/base.py:594-631), so the merged version keeps its index and the index equals a scan.
 Index definitions are logged too: two blind writes that each create the same index are a
 concurrent creation, and the second commit is PBConflictError.

 Run it: STPATH=<repository>/src protost merge_indexed.st"
Import from: 'protobase'.
Import from: '../tutorial/_lesson'.

| lesson dir space db cities inOslo mine theirs people one two |
lesson := Lesson named: 'merge indexed'.
dir := FileSystem temp / ('pbst-queries-merge-' , Smalltalk pid printString).
dir deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'people'.
cities := #('Lima' 'Oslo' 'Paris' 'Rome').
db newTransactionDo: [:t |
    | ps |
    ps := t newDictionary.
    0 to: 599 do: [:i |
        ps := ps setAt: i value: (t newObject: { 'name' -> ('person' , i printString). 'city' -> (cities at: i \\ 4 + 1) })].
    t setRootObject: 'people' value: (ps addIndex: (PBEqualityIndex name: 'by_city' path: 'city'))].
inOslo := [:ps | ((PBQuery from: ps) where: ((PBField path: 'city') eq: 'Oslo')) count].
lesson check: 'the indexed root holds 150 people in Oslo' is: (inOslo value: (db newTransaction getRootObject: 'people')) equals: 150.

mine := db newTransaction.
theirs := db newTransaction.
mine setRootObject: 'people' value: (mine newDictionary
    setAt: 700 value: (mine newObject: { 'name' -> 'person700'. 'city' -> 'Oslo' })).
theirs setRootObject: 'people' value: (theirs newDictionary
    setAt: 701 value: (theirs newObject: { 'name' -> 'person701'. 'city' -> 'Oslo' })).
mine commit.
theirs commit.
people := db newTransaction getRootObject: 'people'.
lesson check: 'both blind writes merged, and the index counts them' is: (inOslo value: people) equals: 152.
lesson check: 'the merged version keeps its index' is: people indexNames equals: #('by_city').
lesson check: 'and the index equals a scan'
    is: ([people validate. 'clean'] on: PBCorruptionError do: [:e | e messageText]) equals: 'clean'.
lesson check: 'every element is there' is: people count equals: 602.
lesson check: 'the lookup is answered by the index'
    is: (((PBQuery from: people) where: ((PBField path: 'city') eq: 'Oslo')) explain at: 'plan') equals: 'IndexLookup'.

one := db newTransaction.
two := db newTransaction.
one setRootObject: 'tags' value: (one newDictionary addIndex: (PBEqualityIndex name: 'by_tag' path: 'tag')).
two setRootObject: 'tags' value: (two newDictionary addIndex: (PBEqualityIndex name: 'by_tag' path: 'tag')).
one commit.
lesson check: 'the second creation of the same index is a conflict'
    signals: PBConflictError containing: 'by_tag' during: [two commit].
lesson check: 'the first one stands' is: (db newTransaction getRootObject: 'tags') indexNames equals: #('by_tag').
lesson check: 'and the people were not touched' is: (db newTransaction getRootObject: 'people') count equals: 602.

space close.
dir deleteAll.
lesson finish.
