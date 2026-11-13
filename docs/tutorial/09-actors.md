# 9. Actors

<!-- example: examples/tutorial/09_actors.st -->
Program: [examples/tutorial/09_actors.st](../../examples/tutorial/09_actors.st).
Previous: [8. Bytes and the cost of a version](08-bytes.md). Next: [10. Crashes and reopening](10-crash-recovery.md).

protoST runs Smalltalk on several cores at once: an object sent `asActor` gets a mailbox and runs
its messages, one at a time, on a pool of native worker threads shared by all actors, on protoCore,
whose threads have no global interpreter lock (protoST's
[README](https://github.com/gamarino/protoST) and
[LANGUAGE.md](https://github.com/gamarino/protoST/blob/main/docs/LANGUAGE.md), section 10). This
chapter puts four writers and an auditor on one database.

## Writers

```smalltalk
Writer >> commit: n as: aName on: aDatabase
  runs := 0.
  1 to: n do: [:i |
    aDatabase run: [:tr |
        runs := runs + 1.
        tr setRootObject: 'counter' value: (tr getRootObject: 'counter') + 1.
        tr setRootObject: 'log' value: (tr newDictionary setAt: aName , '-' , i printString value: i)]
      retries: 100].
  ^ runs.
```

Each transaction does two things: a read-modify-write of `'counter'`, which conflicts when another
writer got there first and is retried by `run:`, and a blind write of one entry to `'log'`, which
merges (chapter 6). Both happen in one commit or neither does.

```smalltalk
writers := names collect: [:each | Writer new asActor].
"Each send answers a Future at once: the four writers and the auditor run together."
futures := (1 to: names size) collect: [:i | (writers at: i) commit: 10 as: (names at: i) on: db].
audit := Auditor new asActor sample: 30 on: db.
runs := futures inject: 0 into: [:sum :f | sum + f wait].
lesson check: 'no snapshot was ever inconsistent' is: audit wait equals: 0.
```

The database object is shared by all of them; there is no lock in the program. Commits of one
space are serialised by its publisher, an actor, and readers do not involve it at all. On the
machine where this was written, the 40 commits ran their blocks about 96 times: the counter is a
hot spot, and every conflict is a retry. The log, written blindly, never caused one.

## The auditor

```smalltalk
Auditor >> sample: count on: aDatabase
  | broken tr |
  broken := 0.
  count timesRepeat: [
    tr := aDatabase newTransaction.
    (tr getRootObject: 'counter') = (tr getRootObject: 'log') count ifFalse: [broken := broken + 1].
    tr abort.
    (Future after: 10) wait].
  ^ broken.
```

While the writers commit, the auditor opens snapshots and checks that `'counter'` equals the size of
`'log'`. It never finds one where they differ: a snapshot is a committed version, and a version is a
whole commit.

## Sharing a value

```smalltalk
totals := ((1 to: 3) collect: [:i | Auditor new asActor total: log]) collect: [:f | f wait].
lesson check: 'three actors read the same value' is: totals asArray equals: #(220 220 220).
```

The same stored dictionary is handed to three actors at once. It is immutable, so no copy is made
and nothing is locked. This is the property the whole design rests on: in a multi-core runtime,
values are the things that can be shared for free.

## Across processes

Several processes may open one directory, in protoST or in Python. They exclude each other only
while one publishes a version, with the operating system's `flock` on `space.lock` (the format's
own protocol); a process that finds the lock held waits, from 1 ms doubling to 50 ms, up to the
space's `lockTimeout`. That wait blocks the waiting caller's worker thread
([deviations.md](../deviations.md), "Transactions and storage").

## What to take away

- One database object can be shared by any number of actors; no lock in the program.
- Hot read-modify-write data costs retries; blind writes do not.
- Snapshots are always whole commits; stored values are shared without copies.
- Throughput is modest: see the measured figures in [deviations.md](../deviations.md#performance).
