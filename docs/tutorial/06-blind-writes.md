# 6. Blind writes merge

<!-- example: examples/tutorial/06_blind_writes.st -->
Program: [examples/tutorial/06_blind_writes.st](../../examples/tutorial/06_blind_writes.st).
Previous: [5. Transactions and conflicts](05-transactions-and-conflicts.md). Next: [7. Mutable objects and history](07-mutables-and-history.md).

Chapter 5 ended with a cost: conflicts are per root. This chapter is the answer for the most
common case, many writers adding to one collection.

## Writing without reading

```smalltalk
mine := db newTransaction.
theirs := db newTransaction.
mine setRootObject: 'tags' value: (mine newDictionary setAt: 'smalltalk' value: 2).
theirs setRootObject: 'tags' value: (theirs newDictionary setAt: 'databases' value: 3).
mine commit.
theirs commit.
tags := db newTransaction getRootObject: 'tags'.
lesson check: 'both keys survive, and the old one too' is: tags keys equals: #('classic' 'databases' 'smalltalk').
```

Neither transaction read `'tags'`, so neither computed anything from a stale value: their writes are
*blind*. The second commit did not replace the first one's dictionary, and neither side retried.

## How: the operation log

```smalltalk
lesson check: 'a new collection has a complete log' isTrue: (PBDictionary new setAt: 'k' value: 1) isMergeable.
lesson check: 'the log is the intents, proto_db''s names'
    is: (PBDictionary new setAt: 'k' value: 1) opLog printString
    equals: 'PBFrozenList(PBTuple(''set'', ''k'', 1))'.
```

A collection built from new remembers the operations that built it. When a root was written but
not read, the commit replays those operations onto the version that is current at commit
(`rebaseOnto:`). A collection that was loaded from the database has no complete log, so it is not
mergeable; that is why the merge applies to blind writes only.

## Counters compose

```smalltalk
mine setRootObject: 'loans' value: (mine newCountedSet add: 'Blue Book').
theirs setRootObject: 'loans' value: ((theirs newCountedSet add: 'Blue Book') add: 'Blue Book').
mine commit.
theirs commit.
loans := db newTransaction getRootObject: 'loans'.
lesson check: 'every increment is kept' is: (loans countOf: 'Blue Book') equals: 3.
```

A `PBCountedSet` merge composes: concurrent increments are all kept. This is the counter that
does not conflict, which GemStone programmers know as the reason for `RcCounter`.

## When the merge does not apply

- `setRootObject:value:replace: true` asks for last-writer-wins explicitly.
- A transaction that **read** the root is protected instead, and conflicts (chapter 5):

```smalltalk
mine setRootObject: 'tags' value: ((mine getRootObject: 'tags') setAt: 'c' value: 3).
theirs setRootObject: 'tags' value: ((theirs getRootObject: 'tags') setAt: 'd' value: 4).
mine commit.
lesson check: 'a read root is protected, not merged'
    signals: PBConflictError containing: 'tags' during: [theirs commit].
```

- A `PBList` keeps no log, so a blind write of a list replaces the root (the last commit wins).
- Mutable cells are never merged.
- A blind write onto a collection with an equality or range index merges like any other: its
  intents are replayed through the current version's mutators, which maintain its indexes (0.3.0;
  [chapter 17](17-indexes.md)). A collection with a vector index is refused.

So the choice is the programmer's, per write: read and be protected, or write blindly and merge.
`proto_db` makes the same choice in the same places; the 27 concurrent-commit scenarios of
`tests/interop/concurrency.sh` check that both languages reach `proto_db`'s outcomes.

## What to take away

- Blind writes of collections built from new merge at commit; nobody retries.
- Counted sets are the conflict-free counters.
- Reading a root opts into conflict protection; `replace: true` opts into last-writer-wins.
