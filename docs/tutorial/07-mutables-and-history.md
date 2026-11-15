# 7. Mutable objects and history

<!-- example: examples/tutorial/07_mutables_and_history.st -->
Program: [examples/tutorial/07_mutables_and_history.st](../../examples/tutorial/07_mutables_and_history.st).
Previous: [6. Blind writes merge](06-blind-writes.md). Next: [8. Bytes and the cost of a version](08-bytes.md).

## Identity that outlives a value

Values never change, but some things keep their identity while their state changes: an author who
is renamed is still the same author, and every book should see the new name. A `PBMutableObject`
is a **name for a cell** of the database. The cell holds a value; a commit replaces the value;
records refer to the cell, not to the value.

```smalltalk
author := PBMutableObject name: 'author:kay'.
db newTransactionDo: [:t |
    t newMutable: author name value: 'Alan Kay'.
    t setRootObject: 'book' value: (t newObject: {
        'title' -> 'The Early History of Smalltalk'.
        'author' -> author })].
```

```smalltalk
db newTransactionDo: [:t | author set: t value: 'Alan C. Kay'].
```

```smalltalk
lesson check: 'the book holds the handle' is: (book at: 'author') name equals: 'author:kay'.
lesson check: 'the handle reads the latest value' is: ((book at: 'author') get: tr) equals: 'Alan C. Kay'.
```

The handle is itself an immutable value (it holds only the name); `get:` and `set:value:` take
the transaction, so a read of a cell is recorded and checked at commit like a read of a root:

```smalltalk
tr := db newTransaction.
tr setMutable: 'author:kay' value: (tr getMutable: 'author:kay') , ' (Xerox PARC)'.
db newTransactionDo: [:t | t setMutable: 'author:kay' value: 'Alan Curtis Kay'].
lesson check: 'a stale cell write conflicts'
    signals: PBConflictError containing: 'author:kay' during: [tr commit].
```

Cells are the finest unit of conflict this design has: one cell per entity (one per customer, one
per author) means two transactions conflict only when they touch the same entity.

## Every version stays readable

```smalltalk
lesson check: 'three versions' is: db history size equals: 3.
lesson check: 'version 0 is the empty database' is: (db snapshotAt: db history last) rootNames equals: #().
lesson check: 'version 1 had the first name'
    is: ((db snapshotAt: (db history at: 2)) getMutable: 'author:kay') equals: 'Alan Kay'.
```

`db history` answers one `PBHistoryEntry` per committed version, newest first, each with its
`version` and `committedAt`. `snapshotAt:` opens one for reading. Nothing is ever deleted or
overwritten, so the history is not a by-product waiting for collection: it is part of the
design ("perennial"). The cost is that the directory only grows: protoBaseST has no compaction and
no collection of old versions.

## As of a moment

`proto_db` has no "as of" message, and neither has protoBaseST: it is three lines over the history.

```smalltalk
asOf := [:moment |
    | entry |
    entry := db history detect: [:each | each committedAt <= moment]
        ifNone: [PBUserError signal: 'the database did not exist yet'].
    db snapshotAt: entry].
lesson check: 'as of moment 1' is: ((asOf value: moment1) getMutable: 'author:kay') equals: 'Alan Kay'.
lesson check: 'as of moment 2' is: ((asOf value: moment2) getMutable: 'author:kay') equals: 'Alan C. Kay'.
```

The moments are taken from the history (`committedAt`), never from a wall clock: commit times
never decrease but may repeat, so the helper takes the newest version at or before the moment.
Records keep their old versions too, so an as-of read answers the record as it was:

```smalltalk
old := (asOf value: moment2) getRootObject: 'book'.
lesson check: 'the old version of the record has no year' isTrue: (old at: 'year') isNil.
```

A snapshot only reads; it understands no message that writes.

## What to take away

- A `PBMutableObject` is a named cell: the one thing that means "the latest version".
- A cell is checked at commit like a root, and is the finest unit of conflict.
- Every version is kept and readable; as-of is a helper over `history` and `snapshotAt:`.
