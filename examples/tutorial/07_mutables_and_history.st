"EXPECT: 07 mutables and history ok (14 checks)"
"Lesson 07: mutable objects, perennial history and as-of reads.
 Tutorial chapter: docs/tutorial/07-mutables-and-history.md

 What it teaches:
 - values never change, but some things keep their identity while their state changes (an
   author who is renamed). A PBMutableObject is a NAME for a cell of the database; the
   cell's value is replaced by commit, and records refer to the cell, not to a value;
 - every committed version stays readable: db history lists them, newest first, and
   snapshotAt: opens one for reading;
 - 'as of a moment' is a three-line helper over the history (proto_db has no asOf: either);
 - a snapshot is read-only.

 Run it: STPATH=<repository>/src protost 07_mutables_and_history.st"
Import from: 'protobase'.
Import from: '_lesson'.

| lesson dir space db author asOf moment1 moment2 tr book old |
lesson := Lesson named: '07 mutables and history'.
dir := FileSystem temp / ('pbst-tutorial-07-' , Smalltalk pid printString).
dir deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'library'.

"A cell named 'author:kay', and a book whose author is the cell (a handle, not a value)."
author := PBMutableObject name: 'author:kay'.
db newTransactionDo: [:t |
    t newMutable: author name value: 'Alan Kay'.
    t setRootObject: 'book' value: (t newObject: {
        'title' -> 'The Early History of Smalltalk'.
        'author' -> author })].
moment1 := db history first committedAt.

"Renaming the author is one commit to the cell. The book is not rewritten."
db newTransactionDo: [:t | author set: t value: 'Alan C. Kay'].
moment2 := db history first committedAt.
tr := db newTransaction.
book := tr getRootObject: 'book'.
lesson check: 'the book holds the handle' is: (book at: 'author') name equals: 'author:kay'.
lesson check: 'the handle reads the latest value' is: ((book at: 'author') get: tr) equals: 'Alan C. Kay'.
lesson check: 'the book itself was not rewritten: one record in both versions'
    isTrue: book = ((db snapshotAt: (db history at: 2)) getRootObject: 'book').
lesson check: 'newMutable: refuses a cell that exists'
    signals: PBValidationError containing: 'author:kay' during: [tr newMutable: 'author:kay' value: 'x'].
tr abort.

"Every version stays readable."
lesson check: 'three versions' is: db history size equals: 3.
lesson check: 'version 0 is the empty database' is: (db snapshotAt: db history last) rootNames equals: #().
lesson check: 'version 1 had the first name'
    is: ((db snapshotAt: (db history at: 2)) getMutable: 'author:kay') equals: 'Alan Kay'.

"As of a moment: the newest version committed at or before it. A moment is taken from the
 history (committedAt), never from a wall clock, so the answer is exact."
asOf := [:moment |
    | entry |
    entry := db history detect: [:each | each committedAt <= moment]
        ifNone: [PBUserError signal: 'the database did not exist yet'].
    db snapshotAt: entry].
lesson check: 'as of moment 1' is: ((asOf value: moment1) getMutable: 'author:kay') equals: 'Alan Kay'.
lesson check: 'as of moment 2' is: ((asOf value: moment2) getMutable: 'author:kay') equals: 'Alan C. Kay'.
lesson check: 'commit times never decrease' isTrue: moment1 <= moment2.

"Old values of records are kept too: replace the book, then read the old one back."
db newTransactionDo: [:t |
    t setRootObject: 'book' value: ((t getRootObject: 'book') with: 'year' value: 1993)].
old := (asOf value: moment2) getRootObject: 'book'.
lesson check: 'the old version of the record has no year' isTrue: (old at: 'year') isNil.
lesson check: 'the current one has' is: ((db newTransaction getRootObject: 'book') at: 'year') equals: 1993.

"A snapshot reads; it has no message that writes."
lesson check: 'a snapshot cannot write' isTrue: ((asOf value: moment2) respondsTo: #setRootObject:value:) not.

"Cells are protected like roots: a cell read, then changed by another commit, conflicts."
tr := db newTransaction.
tr setMutable: 'author:kay' value: (tr getMutable: 'author:kay') , ' (Xerox PARC)'.
db newTransactionDo: [:t | t setMutable: 'author:kay' value: 'Alan Curtis Kay'].
lesson check: 'a stale cell write conflicts'
    signals: PBConflictError containing: 'author:kay' during: [tr commit].
lesson say: 'history: ' , (db history collect: [:e | e version printString , '@' , e committedAt printString]) asArray printString.
space close.
dir deleteAll.
lesson finish.
