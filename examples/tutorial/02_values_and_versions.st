"EXPECT: 02 values and versions ok (16 checks)"
"Lesson 02: collections are values; every change answers a new version.
 Tutorial chapter: docs/tutorial/02-values-and-versions.md

 What it teaches:
 - add:, remove:, setAt:value:, removeAt:, appendLast: answer a NEW collection and leave the
   receiver as it was. A statement that discards the answer changes nothing, and nothing fails;
 - an old version stays valid for whoever holds it (no copy was made: the versions share
   every unchanged part);
 - PBList positions are zero-based, and getAt: -1 is the last element;
 - a stored collection is changed the same way: read it, build the new version, write it back.
 No database is needed for the first part: the collections are plain values.

 Run it: STPATH=<repository>/src protost 02_values_and_versions.st"
Import from: 'protobase'.
Import from: '_lesson'.

| lesson tags before shelf v1 v2 dir space db |
lesson := Lesson named: '02 values and versions'.

"The trap: Pharo's Set>>add: changes the set; this one answers a new set."
tags := PBSet new.
tags add: 'smalltalk'.
lesson check: 'a discarded add: changed nothing' is: tags count equals: 0.
tags := tags add: 'smalltalk'.
lesson check: 'keep the answer' is: tags count equals: 1.

"The old version is still there, unchanged."
before := tags.
tags := (tags add: 'databases') remove: 'smalltalk'.
lesson check: 'the new version' is: tags elements equals: #('databases').
lesson check: 'the old version, untouched' is: before elements equals: #('smalltalk').

"Lists count from zero, as proto_db's List does."
shelf := ((PBList new appendLast: 'Blue Book') appendLast: 'Green Book') appendLast: 'Orange Book'.
lesson check: 'getAt: 0 is the first' is: (shelf getAt: 0) equals: 'Blue Book'.
lesson check: 'getAt: -1 is the last' is: (shelf getAt: -1) equals: 'Orange Book'.
lesson check: 'removeAt: answers a new list' is: (shelf removeAt: 0) elements equals: #('Green Book' 'Orange Book').
lesson check: 'and shelf still has three' is: shelf count equals: 3.
lesson check: 'a position out of range is an error, never nil'
    signals: PBValidationError containing: 'out of range' during: [shelf getAt: 3].

"Dictionaries answer new versions too, and iterate in key order."
v1 := PBDictionary new setAt: 'b' value: 2.
v2 := v1 setAt: 'a' value: 1.
lesson check: 'v1 has one key' is: v1 keys equals: #('b').
lesson check: 'v2 has two, in key order' is: v2 keys equals: #('a' 'b').

"In a database: read the root, build a new version, write it back."
dir := FileSystem temp / ('pbst-tutorial-02-' , Smalltalk pid printString).
dir deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'library'.
db newTransactionDo: [:tr | tr setRootObject: 'shelf' value: shelf].
db newTransactionDo: [:tr |
    | current |
    current := tr getRootObject: 'shelf'.
    current appendLast: 'Purple Book'.
    lesson check: 'inside the transaction, the discarded version is not stored'
        is: (tr getRootObject: 'shelf') count equals: 3.
    tr setRootObject: 'shelf' value: (current appendLast: 'Purple Book')].
lesson check: 'the stored list has four books' is: (db newTransaction getRootObject: 'shelf') count equals: 4.
lesson check: 'version 1 still holds three'
    is: ((db snapshotAt: (db history detect: [:each | each version = 1])) getRootObject: 'shelf') count
    equals: 3.
lesson say: 'versions, newest first: ' , (db history collect: [:each | each version]) printString.

"Values a program builds itself, outside the database, are ordinary Smalltalk: PBFrozenList is
 one-based, like Array."
lesson check: 'a PBFrozenList is one-based' is: ((PBFrozenList withAll: #(10 20)) at: 1) equals: 10.
lesson check: 'and immutable: it has no at:put:' isTrue: ((PBFrozenList withAll: #(10 20)) respondsTo: #at:put:) not.
space close.
dir deleteAll.
lesson finish.
