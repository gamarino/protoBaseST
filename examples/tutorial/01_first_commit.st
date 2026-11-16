"EXPECT: 01 first commit ok (9 checks)"
"Lesson 01: a space, a database and a first commit.
 Tutorial chapter: docs/tutorial/01-first-commit.md

 What it teaches:
 - a space is a directory; it holds named databases;
 - a database starts at version 0, empty; every commit adds a version;
 - roots are the named entry points of a database: what is stored is reachable from a root;
 - a transaction commits at the end of newTransactionDo:, and what it committed is on disk:
   a second space opened on the same directory reads it back.

 Run it: STPATH=<repository>/src protost 01_first_commit.st"
Import from: 'protobase'.
Import from: '_lesson'.

| lesson dir space db reader again |
lesson := Lesson named: '01 first commit'.

"A space is a directory. Opening it creates it if needed."
dir := FileSystem temp / ('pbst-tutorial-01-' , Smalltalk pid printString).
dir deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
lesson check: 'a new space has no database' is: space listDatabases equals: #().

"newDatabase: commits version 0, the empty database."
db := space newDatabase: 'library'.
lesson check: 'the database is listed' is: space listDatabases equals: #('library').
lesson check: 'version 0 is committed' is: db history size equals: 1.

"A first commit: two roots, a string and a dictionary."
db newTransactionDo: [:tr |
    tr setRootObject: 'title' value: 'My library'.
    tr setRootObject: 'books' value: ((tr newDictionary
        setAt: 'isbn:0201113716' value: 'Smalltalk-80: The Language')
        setAt: 'isbn:0201136880' value: 'Smalltalk-80: Bits of History, Words of Advice')].
lesson check: 'the commit made version 1' is: db history first version equals: 1.
lesson say: 'committed version ' , db history first version printString , ' at ' , db history first committedAt printString.

"A new transaction reads the version that is current when it starts."
reader := db newTransaction.
lesson check: 'the root names' is: reader rootNames equals: #('books' 'title').
lesson check: 'a root read back' is: (reader getRootObject: 'title') equals: 'My library'.
lesson check: 'a key of the dictionary' is: ((reader getRootObject: 'books') getAt: 'isbn:0201113716')
    equals: 'Smalltalk-80: The Language'.
reader abort.
space close.

"Everything committed is in the directory: a new space reads it back."
again := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := again openDatabase: 'library'.
lesson check: 'reopened: two books' is: (db newTransaction getRootObject: 'books') count equals: 2.
lesson check: 'reopened: two versions' is: db history size equals: 2.
again close.
dir deleteAll.
lesson finish.
