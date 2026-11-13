# 5. Transactions and conflicts

<!-- example: examples/tutorial/05_transactions_and_conflicts.st -->
Program: [examples/tutorial/05_transactions_and_conflicts.st](../../examples/tutorial/05_transactions_and_conflicts.st).
Previous: [4. Collections and queries](04-collections-and-queries.md). Next: [6. Blind writes merge](06-blind-writes.md).

## A transaction reads one snapshot

```smalltalk
early := db newTransaction.
db newTransactionDo: [:t | t setRootObject: 'balance' value: 150].
lesson check: 'an older transaction sees its snapshot' is: (early getRootObject: 'balance') equals: 100.
lesson check: 'a new transaction sees the commit' is: (db newTransaction getRootObject: 'balance') equals: 150.
```

A transaction takes the current version when it starts and reads only that version. Readers take
no lock and never wait; a reader never blocks a writer.

## The read set, and what a conflict is

Every root (and every mutable cell, chapter 7) that a transaction reads is recorded, with what it
held: the *read set*. At commit, the database checks the read set against the version that is
current then. If any of those roots changed in between, the commit fails with `PBConflictError`
and the transaction is aborted:

```smalltalk
tr := db newTransaction.
v := tr getRootObject: 'balance'.
db newTransactionDo: [:t | t setRootObject: 'balance' value: 175].
tr setRootObject: 'balance' value: v + 10.
outcome := lesson check: 'the stale write conflicts'
    signals: PBConflictError containing: 'balance' during: [tr commit].
```

The message names the root: `Root 'balance' of database 'bank' was changed by a concurrent
commit`. The failed transaction published nothing; the concurrent commit stands.

The check covers **what was read, not only what is written**. Here `'interest'` is computed from
`'rate'`, which the transaction only reads, and `'rate'` changes:

```smalltalk
tr := db newTransaction.
v := (tr getRootObject: 'balance') * (tr getRootObject: 'rate') // 100.
db newTransactionDo: [:t | t setRootObject: 'rate' value: 7].
tr setRootObject: 'interest' value: v.
lesson check: 'a root that was only read conflicts too'
    signals: PBConflictError containing: 'rate' during: [tr commit].
```

A check on written objects alone (a write-write check) would have committed an interest computed
from a rate that no longer holds. This is stricter than both GemStone's default optimistic
detection and Soil's, as their documentation describes them (see the orientation chapters).

The other side of the coin is **granularity**. The read set records roots and cells, not each
object inside them. Two transactions that both read the root `'books'` and write back different
books conflict, even though they touched different records. The design answers this in three
ways: split data that is written concurrently into separate roots or cells; let writers that do
not need to read write blindly, which merges (chapter 6); and retry, which `run:` does.

## Abort and exceptions

```smalltalk
lesson check: 'the exception goes on'
    signals: ZeroDivide containing: '' during: [
        db newTransactionDo: [:t | t setRootObject: 'balance' value: 0. 1 / 0]].
lesson check: 'and the write was discarded' is: (db newTransaction getRootObject: 'balance') equals: 175.
```

`abort` discards a transaction's writes; an exception that leaves a `newTransactionDo:` block
aborts it and goes on. After `commit` or `abort`, every message to the transaction is a
`PBUserError`: a transaction is never reused by mistake. Since the values the transaction built
are immutable, nothing in memory needs rolling back either: they are simply not stored.

## `run:` retries

```smalltalk
attempts := 0.
db run: [:t |
    attempts := attempts + 1.
    v := t getRootObject: 'balance'.
    attempts = 1 ifTrue: [db newTransactionDo: [:rival | rival setRootObject: 'balance' value: 200]].
    t setRootObject: 'balance' value: v + 1].
lesson check: 'the block ran twice' is: attempts equals: 2.
lesson check: 'the second run built on the rival' is: (db newTransaction getRootObject: 'balance') equals: 201.
```

`run:` is the shape for every read-modify-write: on `PBConflictError` it starts a fresh
transaction and runs the block again, after a short randomised wait that grows with each attempt,
up to ten retries (`run:retries:` and `run:retries:backoff:` change both). Because the block may
run more than once, it must have no effect outside the transaction; counting attempts, as here,
is the one harmless exception. `PBOutcomeUnknownError` (the commit may or may not have happened)
is never retried, and any other error aborts and goes on.

## What to take away

- Snapshots for readers, no locks.
- The commit checks everything the transaction read, root by root and cell by cell.
- Conflicts are per root: design roots around what is written concurrently.
- Wrap read-modify-write in `run:`, and keep the block free of outside effects.
