# Coming from GemStone/S

This chapter is for readers who know GemStone/S 64 Bit. It maps GemStone's concepts to
protoBaseST's: what corresponds, what differs, and what protoBaseST does not do. It is written
with respect for a system that opened the field: protoBaseST stands **in the tradition GemStone
opened**, the idea that objects persist as objects, reachable from roots, and is not offered as
its successor or as a better GemStone. Where GemStone is stronger, this chapter says so.

Every statement about GemStone is taken from GemTalk Systems' *GemStone/S 64 Bit Programmer's
Guide*, version 3.7, and carries a source mark such as [G2]; the sources are listed at the end.
Statements marked **(not verified)** are ones this chapter could not confirm in those sources;
treat them as questions, not facts.

## The short version

GemStone is a multi-user object server: Smalltalk code and objects live in one repository, and
each session runs GemStone Smalltalk in a Gem process against a consistent view of it [G1]. Its
first version shipped in 1986 [G7], and its guide speaks of thousands of concurrent users and
repositories of billions of objects [G1]. Its maturity, production record, tooling and scale are
of another order than anything protoBaseST can show.

protoBaseST is a library: a protoST program opens a directory and is the database engine, in its
own process, with no server. Its objects are **immutable values** and **named mutable cells**; it
keeps **every committed version** readable; and its files are **the same files** as those of the
Python database `proto_db`, so one directory is shared by Smalltalk and Python programs. It is a
proposal prototype for the FAST workshop (2026-12-03), several weeks old, slow, and unproven
outside its test scenarios ([not-done.md](../not-done.md)).

The question it brings to a GemStone audience is not "is this a better GemStone?" (it is not)
but: what changes when the persistent objects are values and history is never erased, and when
Smalltalk code can share its database with another language?

## Concept by concept

| GemStone/S | protoBaseST | Comment |
|---|---|---|
| Repository, managed by one Stone process; one Gem per session [G1] | A *space*: a directory of append-only segment files and a `space.root`; no server process | protoBaseST runs in the application's process. Processes coordinate through the files and an OS lock only. |
| Persistence by attachment: "Persistence is established by attaching new objects to other persistent objects", ultimately from `AllUsers` [G1]; per-user `UserGlobals` and the shared `Published` dictionary in the symbol list [G6] | Persistence by reachability from the named **roots** of a database (`setRootObject:value:`) | Similar idea. The difference is how a change reaches the database: in GemStone you modify a persistent object and commit; in protoBaseST you build a new version and write it back to a root or a cell (chapter 2). |
| Objects are mutable; the session keeps separate sets of the objects it wrote and the objects it only read, and "the read set is always a superset of the write set" [G2] | Records and collections are immutable; a change answers a new version; the transaction keeps a read set of roots and cells | No write set of modified objects is needed: a change that is not written back is a value nobody kept. |
| An object whose identity outlives its state is simply an object | A `PBMutableObject`: a named cell whose value a commit replaces (chapter 7) | The one place where protoBaseST has "the current state of an entity". |
| Snapshot view at transaction start, refreshed on commit, abort or `continueTransaction` [G2] | A transaction reads the version current when it started, for its whole life | Equivalent idea. protoBaseST has no automatic or transactionless mode; every read is in a transaction or a read-only snapshot. |
| `commitTransaction` answers false on failure; `commit` signals [G2] | `commit` signals `PBConflictError`; `run:` retries | |
| `abortTransaction` discards modified objects in your view [G2] | `abort` discards the writes | In protoBaseST nothing in memory needs restoring: the values built were never shared. |
| After a failed commit you must abort and redo the work; repeating the commit does not succeed [G2] | A failed commit ends the transaction; `run:` starts a fresh one and runs the block again | Same discipline, packaged as `run:`. |
| The commit steps the guide lists compare the write set with other sessions' write sets ("write-write") and dependency lists ("write-dependency"), and check read locks other sessions set on objects you read; the conflict report (`transactionConflicts`, Table 9.1) also has a `#'Read-Write'` entry, "StrongReadSet and WriteSetUnion conflicts, with the RcReadSet subtracted" [G2] | The read set is checked: every root and cell the transaction **read** must be unchanged (chapter 5) | Both systems track reads. When and how GemStone checks its strong read set, and what puts an object in it, the chapter does not say; it is **(not verified)** here, so no claim is made that either system is stricter. |
| Conflict granularity: objects; with indexes, conflicts can also arise on internal index structures "despite the fact that neither transaction has explicitly accessed an object written by the other transaction" [G2] | Roots and mutable cells | **GemStone is finer.** Two sessions changing different objects inside one collection do not conflict in GemStone (index structures aside); in protoBaseST two transactions that read the same root and write it back do. protoBaseST's answers are blind-write merges, cells per entity, and retries. |
| Reduced-conflict classes: `RcCounter`, `RcIdentityBag`, `RcQueue`, `RcKeyValueDictionary`, with the caveat that "'reduced conflict' does not mean 'no conflict'" [G2] | Blind writes of collections built from new merge at commit; `PBCountedSet` increments compose (chapter 6) | The closest correspondence in this table. The merge is defined by the file format, so it also merges with Python writers. |
| Read and write locks, never waited for automatically [G2] | No object locks. One OS lock (`flock` on `space.lock`) is held only while a version is published | No pessimistic mode. |
| Code (classes and methods) is stored in the repository and executed by the Gem [G1] | **No code is stored.** The file holds a type name and attributes; behaviour comes from the class each program registers | A deliberate difference: the same record is read by a protoST class and by a Python class. It also means there is no server-side execution and no shared code base in the database. |
| Class versions and class history; instances migrate explicitly (`migrateTo:`, `migrateInstancesTo:`, `migrateFrom:instVarMap:`); unmigrated instances keep the old class's methods [G4] | No class versions and no migration. Records are maps of attribute names; an attribute added later is absent in old records; `typeAliases` keeps records of a renamed type readable | GemStone's model is far richer. protoBaseST's answer is that old versions are immutable history and should stay as written; a "migration" is a new version written by a program. |
| Equality and identity indexes on `UnorderedCollection` subclasses, `GsQuery`, selection blocks, automatic index maintenance [G3] | Maintained equality and range indexes, a query front end (`PBQuery`, `PBField`) and a cost-based planner, and pagers by rank in one process (0.3.0, [chapters 17-19](17-indexes.md)) | **GemStone is still ahead here.** protoBaseST's conditions are built with `PBField`, not selection blocks (a block is opaque and never uses an index; ruling IQ2), and there are no identity indexes. |
| Clustering: `cluster`, `clusterDepthFirst`, cluster buckets packing objects into disk pages [G5] | No clustering control. Records are appended to segments in commit order | Not addressed. |
| Shared page cache holding the object table and pages, shared by the Stone and the Gems on a host [G5] | A per-storage atom cache of decoded records, in the process (bounded in entries and bytes) | No shared cache across processes. |
| Transaction log with point-in-time roll-forward recovery [G1] | No log. A version is published by an atomic rename of `space.root`; a crash leaves only unreachable debris (chapter 10) | Different technique. protoBaseST has no backup or roll-forward tool. |
| Garbage collection (`markForCollection`, epoch GC) [G5] | No collection: every version is kept for ever, by design | protoBaseST trades disk for perennial history and has no compaction yet. |
| Reading the repository as of a past commit | `db history`, `snapshotAt:`, and a three-line as-of helper (chapter 7) | That GemStone has no built-in as-of read of past commits is **(not verified)**; the guide's transaction chapter describes snapshot views of the current state [G2]. |
| Many concurrent sessions, each a Gem process; "thousands of concurrent users" [G1] | Many protoST actors in one process, on native threads with no global lock, plus other processes on the same directory; one commit published at a time | Different shapes; protoBaseST has never been run at any scale. |
| GemBuilder for Smalltalk, Java and C: client interfaces to the GemStone server [G1] | The file format itself is shared: Python's `proto_db` opens the same directory, with its own classes | GemBuilder lets other languages talk to GemStone objects; protoBaseST lets another implementation read and write the same files without a server. |
| Repositories of "hundreds of gigabytes", "billions of objects", "hundreds of transactions per second" [G1] | Measured 2026-11-13 on one machine at a load average of about 9 to 14, so indicative only: 0.06x to 0.22x of `proto_db`'s commits per second (single small commits about 0.2x, about 22 to 33 per second; 100-key batch commits 0.06x, about 3 per second; four writers merging into one root 0.09x), and AVL operations 12 to 31 times slower than `proto_db`'s. No re-measurement on an idle machine has been made ([deviations.md](../deviations.md#performance)) | **No comparison of scale is possible.** protoBaseST has never been run near a large size. |

## What a GemStone programmer will miss

- Transparent persistence of a mutable graph: modify, commit, done.
- Object-level conflict detection.
- Identity indexes, and selection blocks that use an index (`GsQuery`); protoBaseST has
  equality and range indexes and `PBQuery` (chapters 17-19), where a block never uses an index.
- Code in the database, executed next to the data; class history and migration tools.
- A server, a shared page cache, administration tools, backups, and a product history that
  goes back to 1986 [G7].

## What protoBaseST tries instead

- **Values.** A stored record or collection never changes. A reader holds a whole, consistent
  value without a lock, and a value can be handed to any number of threads without a copy
  (chapter 9).
- **Perennial history.** Every committed version stays readable, by design, not as a by-product.
- **Merges of blind writes**, defined by the file format, so that they also merge with another
  language's writers (chapters 6 and 11).
- **A shared format.** One directory, opened by protoST and by Python, with the same answers in
  every scenario tested.
- **Multi-core in one process**: protoST actors on native threads (chapter 9).

## Sources

All consulted 2026-11-13.

- [G1] GemStone/S 64 Bit Programmer's Guide 3.7, chapter 1, "Introduction to GemStone":
  <https://docs.gemtalksystems.com/GemStone64/3.7.x/GS64-ProgGuide-3.7/1-IntroToGemStone.htm>
- [G2] Chapter 9, "Transactions and Concurrency Control":
  <https://docs.gemtalksystems.com/GemStone64/3.7.x/GS64-ProgGuide-3.7/9-Transactions.htm>
- [G3] Chapter 8, "Indexes and Querying":
  <https://docs.gemtalksystems.com/GemStone64/3.7.x/GS64-ProgGuide-3.7/8-IndexingAndQuerying.htm>
- [G4] Chapter 11, "Class Versions and Instance Migration":
  <https://docs.gemtalksystems.com/GemStone64/3.7.x/GS64-ProgGuide-3.7/11-ClassHistory.htm>
- [G5] Chapter 16, "Performance" (clustering, shared page cache, garbage collection):
  <https://docs.gemtalksystems.com/GemStone64/3.7.x/GS64-ProgGuide-3.7/16-Performance.htm>
- [G6] Chapter 3, "Resolving Names and Sharing Objects":
  <https://docs.gemtalksystems.com/GemStone64/3.7.x/GS64-ProgGuide-3.7/3-Symbols.htm>
- [G7] Wikipedia, "GemStone/S" (company history, first release in 1986):
  <https://en.wikipedia.org/wiki/GemStone/S>
- The guide's table of contents: <https://docs.gemtalksystems.com/GemStone64/3.7.x/GS64-ProgGuide-3.7/MAIN.htm>

## Not verified

- Whether GemStone offers a built-in read of the repository as of a past commit.
- How GemStone uses its read set at commit: what puts an object in the "StrongReadSet" of the
  `#'Read-Write'` conflict entry, and whether read-write conflicts are detected optimistically,
  without read locks, in the default configuration. Chapter 9 lists the entry but does not
  explain it.
- How GemStone's garbage collection works in detail; chapter 16 only names `markForCollection`
  and epoch collection.
- Any GemStone performance figure beyond the guide's own general statements quoted above.

Corrections from people who run GemStone are welcome; that is what the workshop is for.
