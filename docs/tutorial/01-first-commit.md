# 1. A space, a database and a first commit

<!-- example: examples/tutorial/01_first_commit.st -->
Program: [examples/tutorial/01_first_commit.st](../../examples/tutorial/01_first_commit.st).
Next: [2. Values and versions](02-values-and-versions.md).

A note on the quoted code: the programs prove what they show. `lesson check: 'what' is: actual
equals: expected` prints `ok - what` when the two agree and `FAIL - ...` when they do not, and
`lesson check: ... signals: AnError containing: 'text' during: [...]` checks that a block is
refused. They come from the small helper `examples/tutorial/_lesson.st`; read `lesson check:` as
"assert", and everything else is protoBaseST.

## A space is a directory

```smalltalk
dir := FileSystem temp / ('pbst-tutorial-01-' , Smalltalk pid printString).
dir deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
lesson check: 'a new space has no database' is: space listDatabases equals: #().
```

A *space* is a directory of files: segment files (`<uuid>.seg`), which are only ever appended to,
`space.root`, which names the current version, and `space.lock`, which writers lock while they
publish. There is no server process. The program that opens the directory is the database engine,
in the same process as the application, as with Soil, and unlike GemStone's Stone and Gems
(see [Coming from GemStone/S](gemstone.md)).

A space holds any number of named *databases*. `newDatabase:` creates one and commits its version
0, the empty database; `openDatabase:` opens one that exists:

```smalltalk
db := space newDatabase: 'library'.
lesson check: 'the database is listed' is: space listDatabases equals: #('library').
lesson check: 'version 0 is committed' is: db history size equals: 1.
```

## Roots

What a database stores is reachable from its *roots*: named entry points, set inside a
transaction.

```smalltalk
db newTransactionDo: [:tr |
    tr setRootObject: 'title' value: 'My library'.
    tr setRootObject: 'books' value: ((tr newDictionary
        setAt: 'isbn:0201113716' value: 'Smalltalk-80: The Language')
        setAt: 'isbn:0201136880' value: 'Smalltalk-80: Bits of History, Words of Advice')].
lesson check: 'the commit made version 1' is: db history first version equals: 1.
```

`newTransactionDo:` runs the block with a new transaction and commits when the block ends; if
the block raises, it aborts and the exception goes on. It never retries (chapter 5 shows `run:`,
which does). Each commit adds one version to the database, numbered from 0; `db history` lists
them newest first.

There are as many roots as the application wants, each with its own name. That matters for
concurrency: the commit checks what a transaction read **root by root** (chapter 5), so two
transactions that work on different roots never conflict.

## Reading

```smalltalk
reader := db newTransaction.
lesson check: 'the root names' is: reader rootNames equals: #('books' 'title').
lesson check: 'a root read back' is: (reader getRootObject: 'title') equals: 'My library'.
```

A transaction reads the version that was current when it started (a snapshot), and keeps reading
it for its whole life. A read-only transaction ends with `abort`; nothing is written either way.

## It is on disk

```smalltalk
again := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := again openDatabase: 'library'.
lesson check: 'reopened: two books' is: (db newTransaction getRootObject: 'books') count equals: 2.
```

The commit returned after the segment and `space.root` were synced (`fsync`); the durability is
always `fsync`, there is no faster mode. A second space opened on the same directory, in this
process or another one, written in protoST or in Python, reads the same versions.

## What to take away

- A space is a directory; a database is a named history of versions; a root is a named entry point.
- The engine runs inside the application's process.
- A transaction reads one snapshot; a commit adds one version.
