# Coming from Soil

This chapter is for readers who know Soil, the object database for Pharo by Norbert Hartl and
Marcus Denker [S4], "the driving database behind ApptiveGrid" [S1]. It maps Soil's
concepts to protoBaseST's: what corresponds, what differs, and what protoBaseST does not do.

Soil and protoBaseST share several engine choices: append-only files, snapshots for readers,
optimistic conflict detection at commit, one writer publishing at a time. The engines also differ
(Soil has an object index, a journal with checkpoints and per-object version chains; protoBaseST
has none of them), and the larger differences are in the model above the engine, which is what
this chapter is about. Soil is in
production and has years of releases (v5 is the latest [S1]); protoBaseST is a proposal prototype
for the FAST workshop (2026-12-03), several weeks old and slow ([not-done.md](../not-done.md)). It
is not offered as a better Soil.

Every statement about Soil is taken from its repository and documentation or from Norbert Hartl's
blog series on Soil's internals (2026), and carries a source mark such as [S5]; the sources are
listed at the end. Statements marked **(not verified)** could not be confirmed there.

## The short version

Soil persists a **mutable Pharo object graph** hung from a database root, detects which objects
changed, and keeps older versions of each object in a chain for snapshot isolation [S2, S7, S9].
protoBaseST persists **immutable values** and **named mutable cells**, writes changes as new
versions explicitly, keeps **every committed version** readable by design, and writes **the same
files** as the Python database `proto_db`, so a directory is shared by protoST and Python
programs.

Soil is closer to GemStone's goal, transparent persistence of a mutable Smalltalk graph, than
protoBaseST is.

## Concept by concept

| Soil | protoBaseST | Comment |
|---|---|---|
| `Soil createOnPath:`, `openOnPath:`, `close`; the database is a directory controlled by Soil [S12] | `PBObjectSpace storage: (PBFileStorage path: ...)`, `newDatabase:`, `openDatabase:`, `close` | Both are libraries in the application's process, over a directory. A protoBaseST space holds several named databases. |
| One database root, `txn root:`; everything reachable from it is stored [S2, S6] | Any number of named roots per database (`setRootObject:value:`) | Same principle (reachability); protoBaseST's roots are also the unit of conflict detection (chapter 5). |
| `txn makeRoot:` partitions the graph: the object gets its own address and is loaded through a proxy [S2] | Every record and tree node is its own record on disk, referenced by pointer and loaded on first use | Lazy loading by reference in both. protoBaseST has no partitioning call: every record and every node of a collection's tree is already a record of its own, loaded on first use. |
| Objects are mutable. Automatic change tracking arrived in v5 [S4]: Soil detects changes by "hashing an object's content", and `SoilTransaction>>initialize` calls `beAutomaticWriteTracking` by default; manual tracking (`beManualWriteTracking`, then `markDirty:` after each change) is opt-in and "only as reliable as remembering to call it" [S9]. The older `docs/model-management.md` still describes `markDirty:` as required [S2] | Records and collections are immutable; a change answers a new version, written back to a root or a cell (chapter 2) | No change detection is needed: nothing changes in place. The cost is the explicit write-back, and the trap of a discarded result (chapter 2). |
| `newTransaction`, `commit`, `abort`; "Aborting a transaction does not roll back the changes made to objects in memory" [S2] | `newTransaction`, `newTransactionDo:`, `commit`, `abort`, `run:` | In protoBaseST there is nothing to roll back in memory: the new versions were never shared. |
| `commitAndContinue` keeps a transaction usable after a commit [S2] | Not provided: a transaction ends at `commit` | |
| A global version counter; a transaction's read version is fixed at creation; per-object version chains, newest first; readers "never wait" [S7] | A transaction reads the version current when it started; readers take no lock | Equivalent snapshot isolation for readers. |
| `newTransactionForVersion:` and `allVersionsOf:` read the past; old versions are kept until a garbage collector removes them [S7]; v5 added an offline `garbageCollect` that "compacts object segments offline" [S4] (the MVCC post [S7] speaks instead of "the online garbage collector that Soil v5 introduced as a preview"; the two sources differ) | Every committed version stays readable for ever (`history`, `snapshotAt:`, chapter 7); there is no collector and no compaction | In Soil, history is a by-product of MVCC that a collector may reclaim; in protoBaseST it is a design property. protoBaseST pays for it with a directory that only grows. |
| Conflict detection at commit: "This is a write-write check on individual objects, nothing more", signalling `SoilObjectHasConcurrentChange`; newly created objects skip it; "it gives you snapshot isolation, not full serializability", and the post names write skew as the gap [S8] | The **read set** is checked: every root and cell the transaction read must be unchanged (chapter 5) | protoBaseST also refuses a write computed from a value that was only read and has changed, which closes that write-skew case for what it read. **Soil is finer-grained**: per object, where protoBaseST conflicts per root or cell. |
| What to do after a conflict: not described in the post [S8] | `run:` aborts and retries with a fresh transaction | Whether Soil provides a retry helper is **(not verified)**. |
| Two writers to one object conflict [S8] | Blind writes of collections built from new merge at commit; counted-set increments compose (chapter 6) | No equivalent was found in the Soil sources read. |
| A single global commit lock: "only one transaction across the whole database can be in here at a time"; serialisation happens before the lock [S6, S7] | One commit is published at a time, through an `flock` on `space.lock` held only while publishing; records are written before the lock is taken | Same shape. |
| Append-only object heap ("There is no update-in-place, ever"), and an object index mapping 8-byte ids to heap positions [S5] | Append-only segment files; a version is reached from `space.root`, replaced by an atomic rename | Same principle, different publication: Soil has an index file and a journal; protoBaseST publishes by renaming one root file. |
| A journal of 16 MB fragments, a write-ahead log with checkpoints; recovery replays from the last checkpoint and discards a truncated entry at the end of the last fragment [S10, S11] | No journal, no replay: a crash leaves bytes nobody reads, and reopening is opening (chapter 10) | Soil's recovery story is documented in depth [S11]; protoBaseST's is simpler and tested only in the crash states of chapter 10. |
| `fsync` is "a separate, explicitly optional step, gated behind a setting" (`isFsyncEnabled`) [S10] | Always `fsync`, no other mode | Soil's default setting is **(not verified)**. |
| A `SoilBehaviorDescription`: the class name and all instance variable names, by name, never by offset; removed variables are skipped, added ones start empty; renaming a variable loses its value; renaming a class with `renameClassNamed:to:` or Pharo's deprecated aliases [S3] | A record stores a type name and attributes by name; `typeAliases` keeps the records of a renamed type readable; an added attribute is absent in old records | Very close. Both store state by name and no code. Neither migrates old data in place. |
| Code is not stored; Soil stores a "flat view" of classes [S3] | Code is not stored; behaviour comes from each program's registered class | Same choice, and in protoBaseST it is what lets a Python class read the same record. |
| SkipList and B+tree indexes; indexed dictionaries usable as non-root objects since v5 [S1, S4] | Maintained equality and range indexes, read and written with `proto_db`, a query front end, a cost-based planner and pagers by rank in one process (0.3.0, [chapters 17-19](17-indexes.md)); no vector search | Comparable for equality and range lookups; Soil's indexed dictionaries are not tied to one collection version, protoBaseST's indexes are part of it. |
| Pharo 11 to 14, 64 bit [S1] | protoST 0.10.0 or newer, and Python's `proto_db` at `v2.0.0rc2` on the same files | Soil's files are written by Pharo; protoBaseST's are shared across two languages. |
| Several images writing one database concurrently | Several processes, protoST or Python, may commit to one directory; the OS lock orders the publications | The Soil repository contains OS file-lock classes (for example `SoilUnixFileLock`), but whether several images may write one database is **(not verified)**. |
| Distribution: the ESUG 2025 talk "Rhizome - Distribution in Soil" [S1] | Cluster mode over one shared directory (0.2.0, [chapters 13-16](13-cluster-concepts.md)), `proto_db`'s protocol | What Rhizome does was **(not verified)**. |
| Backups: the repository has a backup visitor and backup tests | No backup tool | The details of Soil's backups were **(not verified)**. |

## What a Soil user will miss

- Transparent persistence of a Pharo object graph, with automatic change detection.
- Per-object conflict detection.
- Indexes usable outside one collection version (Soil's indexed dictionaries); protoBaseST's
  equality and range indexes belong to a collection version (chapter 17).
- A documented journal, checkpoints and recovery; a garbage collector; backups.
- Pharo's tools, and a database in production.

## What protoBaseST tries instead

- **Values and cells.** Readers and threads share stored values without copies or locks.
- **Read-set conflicts.** A write computed from something that changed meanwhile is refused, not
  only a write to something that changed.
- **Merges of blind writes**, so that many writers can add to one collection without retries.
- **Perennial history** by design, with as-of reads (chapter 7).
- **A shared format**: the same directory is opened by protoST and by Python's `proto_db`
  (chapter 11).
- **Multi-core in one process**: protoST actors on native threads (chapter 9).

## Sources

All consulted 2026-11-13.

- [S1] Soil repository README: <https://github.com/ApptiveGrid/soil>
- [S2] "Store and retrieve a model with transactions", `docs/model-management.md`:
  <https://github.com/ApptiveGrid/Soil/blob/main/docs/model-management.md>
- [S3] "Support for code changes / refactoring", `docs/internals.md`:
  <https://github.com/ApptiveGrid/Soil/blob/main/docs/internals.md>
- [S4] "[ANN] Soil v5", `docs/versions/ann-v5.md`:
  <https://github.com/ApptiveGrid/Soil/blob/main/docs/versions/ann-v5.md>
- [S5] N. Hartl, "Soil: identity and the heap" (2026-07-27):
  <https://norbert.hartl.name/blog/2026-07-27_soil-identity-and-the-heap.html>
- [S6] N. Hartl, "Soil: transactions and how a commit happens" (2026-07-30):
  <https://norbert.hartl.name/blog/2026-07-30_soil-transactions-and-commit.html>
- [S7] N. Hartl, "Soil: MVCC and snapshot isolation" (2026-08-11):
  <https://norbert.hartl.name/blog/2026-08-11_soil-mvcc-and-snapshot-isolation.html>
- [S8] N. Hartl, "Soil: catching write conflicts, optimistically" (2026-08-31):
  <https://norbert.hartl.name/blog/2026-08-31_soil-catching-write-conflicts-optimistically.html>
- [S9] N. Hartl, "Soil: knowing what changed" (2026-09-07):
  <https://norbert.hartl.name/blog/2026-09-07_soil-knowing-what-changed.html>
- [S10] N. Hartl, "Soil: the journal, and what makes it a WAL" (2026-09-11):
  <https://norbert.hartl.name/blog/2026-09-11_soil-the-journal-and-what-makes-it-a-wal.html>
- [S11] N. Hartl, "Soil: checkpoints and recovering from a crash" (2026-09-14):
  <https://norbert.hartl.name/blog/2026-09-14_soil-checkpoints-and-recovering-from-a-crash.html>
- [S12] "Controlling the lifecycle of a database instance", `docs/database-lifecycle-management.md`:
  <https://github.com/ApptiveGrid/Soil/blob/main/docs/database-lifecycle-management.md>
- [S13] N. Hartl, "Soil: serializing a graph" (2026-07-23):
  <https://norbert.hartl.name/blog/2026-07-23_soil-serializing-a-graph.html>
- The series index: <https://norbert.hartl.name/blog/series/soil.html>
- The repository's file tree (file-lock and backup classes):
  <https://github.com/ApptiveGrid/soil/tree/main/src>

## Not verified

- Whether several Pharo images may write one Soil database at the same time.
- What Rhizome (distribution) provides, and its status.
- How Soil's backups work.
- Whether `fsync` is on by default.
- Whether Soil offers a retry helper after `SoilObjectHasConcurrentChange`.
- Soil's serialisation format beyond what [S5] and [S13] describe (Soil's own serializer, walking
  class layouts; Fuel is not mentioned).
- Any Soil performance figure: none is quoted here.

Corrections from Soil's authors and users are welcome.
