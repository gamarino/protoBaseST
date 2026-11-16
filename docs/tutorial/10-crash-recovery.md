# 10. Crashes and reopening

<!-- example: examples/tutorial/10_crash_recovery.st -->
<!-- example: examples/tutorial/_crash_writer.st -->
Program: [examples/tutorial/10_crash_recovery.st](../../examples/tutorial/10_crash_recovery.st)
and the process it kills, [_crash_writer.st](../../examples/tutorial/_crash_writer.st).
Previous: [9. Actors](09-actors.md). Next: [11. One directory, two languages](11-python-interop.md).

## How a version is published

A commit writes its new records to the end of a segment file the writer owns, syncs it, writes
the new root to `space.root.tmp`, syncs that, renames it over `space.root`, and syncs the
directory. The rename is the moment the version exists. Before it, the version does not exist for
any reader; after it, it is durable. Files are only appended to, never rewritten in place.

So a crash can leave exactly two kinds of debris: bytes after the last published record of a
segment (a torn tail), and a partial `space.root.tmp`. Neither is reachable from `space.root`, so
neither is ever read. There is no journal to replay and no recovery step: reopening is opening.

## A torn tail, on purpose

```smalltalk
segment := (dir children select: [:f | f basename endsWith: '.seg']) first.
file := BinaryFile open: segment pathString options: #(#append).
file append: #[1 200 0 0 0 0 0 0 0 7 7].
file close.
"What a crash before the rename leaves: a partial next root."
(dir / 'space.root.tmp') binaryContents: #[80 66 0 0 3].
```

```smalltalk
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space openDatabase: 'crash'.
lesson check: 'reopens at the last published version' is: db history first version equals: 1.
lesson check: 'its data is intact' is: (db newTransaction getRootObject: 'counter') equals: 0.
db newTransactionDo: [:t | t setRootObject: 'counter' value: 1].
lesson check: 'a commit after the crash works' is: db history first version equals: 2.
```

The next commit writes to a new segment of its own; the torn bytes stay where they were, never
truncated, because a writer only ever appends to segments it created. (The unit test
`tests/unit/store_crash_states.st` covers the other states a writer can leave, such as a torn
segment header, and `tests/interop/crash_states_to_py.sh` hands them to `proto_db`, which reads
them the same way.)

## A real kill

The second half starts a writer process that commits until it is killed:

```smalltalk
[i < 1000 and: [sentinel exists and: [Time millisecondClockValue < deadline]]] whileTrue: [
  i := i + 1.
  db run: [:tr |
    tr setRootObject: 'counter' value: (tr getRootObject: 'counter') + 1.
    tr setRootObject: 'log' value: ((tr getRootObject: 'log') setAt: i value: Smalltalk pid)]].
```

It is built so that it can never outlive the lesson by long: it stops by itself when a sentinel
file the lesson created is gone, after 1000 commits, or after 60 seconds. The lesson waits until
it has committed a few versions and then kills it with `SIGKILL`. The kill is in an `ensure:`
block, so an error while waiting still ends the writer, and the only process it signals is the
one it started:

```smalltalk
pid := OSProcess spawn: protost arguments: { writer. dir pathString. sentinel pathString }.
```

```smalltalk
  ensure: [
    sentinel ensureDelete.
    OSProcess kill: pid signal: 9.
    status := OSProcess waitFor: pid].
```

Where it dies varies from run to run: between commits, in the middle of writing records, during a
sync. The checks hold wherever it dies:

```smalltalk
lesson check: 'every version is a whole commit: counter = log size'
    is: (snap getRootObject: 'counter') equals: (snap getRootObject: 'log') count.
lesson check: 'one version per commit, none half-made'
    is: db history first version equals: 3 + (snap getRootObject: 'counter').
```

The commit in flight is lost or published whole; nothing in between. The lock the killed process
may have held is an `flock`, which the operating system releases with the process, so the next
commit goes through at once.

## What is not claimed

These are the crash states a writer can leave on a working file system. What was not tested:
damaged media, a file system that reorders or loses synced writes, a directory edited by hand. A
segment that is corrupt *inside* the published data is reported (`PBCorruptionError`), not
repaired; there is no repair tool, and there is no backup tool.

## What to take away

- A version exists from the rename of `space.root`; everything else is debris nobody reads.
- No recovery step, no journal replay; a killed writer loses at most its commit in flight.
