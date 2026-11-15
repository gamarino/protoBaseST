"EXPECT: 06 blind writes ok (10 checks)"
"Lesson 06: blind writes merge instead of conflicting.
 Tutorial chapter: docs/tutorial/06-blind-writes.md

 What it teaches:
 - a transaction that writes a root without reading it has no stale input to protect. When
   the value is a collection built from new (tr newDictionary, newSet, newCountedSet...),
   the commit replays the operations that built it onto the version that is current: two
   such writers to one root both keep their work, and neither retries;
 - a PBCountedSet merge composes: concurrent increments are all kept;
 - setRootObject:value:replace: true asks for last-writer-wins explicitly;
 - reading the root first turns the same pair of writes into a conflict (lesson 05);
 - a PBList has no operation log: a blind write of a list replaces.

 Run it: STPATH=<repository>/src protost 06_blind_writes.st"
Import from: 'protobase'.
Import from: '_lesson'.

| lesson dir space db mine theirs tags loans |
lesson := Lesson named: '06 blind writes'.
dir := FileSystem temp / ('pbst-tutorial-06-' , Smalltalk pid printString).
dir deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'library'.
db newTransactionDo: [:t |
    t setRootObject: 'tags' value: (t newDictionary setAt: 'classic' value: 1).
    t setRootObject: 'loans' value: t newCountedSet.
    t setRootObject: 'queue' value: (t newList appendLast: 'first')].

"Two transactions open at once; neither reads 'tags'; each writes one key."
mine := db newTransaction.
theirs := db newTransaction.
mine setRootObject: 'tags' value: (mine newDictionary setAt: 'smalltalk' value: 2).
theirs setRootObject: 'tags' value: (theirs newDictionary setAt: 'databases' value: 3).
mine commit.
theirs commit.
tags := db newTransaction getRootObject: 'tags'.
lesson check: 'both keys survive, and the old one too' is: tags keys equals: #('classic' 'databases' 'smalltalk').
lesson say: 'tags after two blind commits: ' , tags keys printString.

"What made it possible: the version remembers the operations that built it."
lesson check: 'a new collection has a complete log' isTrue: (PBDictionary new setAt: 'k' value: 1) isMergeable.
lesson check: 'the log is the intents, proto_db''s names'
    is: (PBDictionary new setAt: 'k' value: 1) opLog printString
    equals: 'PBFrozenList(PBTuple(''set'', ''k'', 1))'.
lesson check: 'a loaded version is not mergeable: it was not built from new' isTrue: tags isMergeable not.

"Counted sets compose: three borrowers, three concurrent blind increments."
mine := db newTransaction.
theirs := db newTransaction.
mine setRootObject: 'loans' value: (mine newCountedSet add: 'Blue Book').
theirs setRootObject: 'loans' value: ((theirs newCountedSet add: 'Blue Book') add: 'Blue Book').
mine commit.
theirs commit.
loans := db newTransaction getRootObject: 'loans'.
lesson check: 'every increment is kept' is: (loans countOf: 'Blue Book') equals: 3.

"replace: true says last writer wins."
mine := db newTransaction.
theirs := db newTransaction.
mine setRootObject: 'tags' value: (mine newDictionary setAt: 'a' value: 1) replace: true.
theirs setRootObject: 'tags' value: (theirs newDictionary setAt: 'b' value: 2) replace: true.
mine commit.
theirs commit.
lesson check: 'replace: the last commit wins' is: (db newTransaction getRootObject: 'tags') keys equals: #('b').

"Reading the root first makes the second writer stale: a conflict, not a merge."
mine := db newTransaction.
theirs := db newTransaction.
mine setRootObject: 'tags' value: ((mine getRootObject: 'tags') setAt: 'c' value: 3).
theirs setRootObject: 'tags' value: ((theirs getRootObject: 'tags') setAt: 'd' value: 4).
mine commit.
lesson check: 'a read root is protected, not merged'
    signals: PBConflictError containing: 'tags' during: [theirs commit].
lesson check: 'the first writer''s version stands' is: (db newTransaction getRootObject: 'tags') keys equals: #('b' 'c').

"A PBList keeps no log: a blind write of a list replaces the root."
lesson check: 'a list is never mergeable' isTrue: (PBList new appendLast: 1) isMergeable not.
mine := db newTransaction.
theirs := db newTransaction.
mine setRootObject: 'queue' value: (mine newList appendLast: 'mine').
theirs setRootObject: 'queue' value: (theirs newList appendLast: 'theirs').
mine commit.
theirs commit.
lesson check: 'the last list written is the root' is: (db newTransaction getRootObject: 'queue') elements
    equals: #('theirs').
space close.
dir deleteAll.
lesson finish.
