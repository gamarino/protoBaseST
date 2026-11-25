# protoBaseST

A perennial object database for protoST, in the tradition GemStone opened.

protoBaseST is a Smalltalk implementation, on protoST, of the Python object database `proto_db`
(developed in the [protoBase repository](https://github.com/gamarino/ProtoDB)). It reads and
writes the **same on-disk format** (format 4, frozen at `v2.0.0rc1`, with the value nesting limit
of `v2.0.0rc2`; the reference is now `proto_db` `v2.0.0rc4` at format 4, whose format 5 is
refused), so one database directory can be shared
by Python and Smalltalk programs. It has `proto_db`'s API translated to Smalltalk, and `proto_db`'s
transaction semantics: snapshot isolation, read sets checked at commit, merges of blind writes,
mutable cells, retries.

## Status

**A proposal prototype, for discussion at the FAST Smalltalk workshop (2026-12-03). Not a product.**
It is shown to start a conversation and to collect criticism. It is small and meant to be correct;
it is not fast and not complete. Read [docs/not-done.md](docs/not-done.md) first: it states what
is missing and what has not been proven.

What was checked, against `proto_db` at `v2.0.0rc2` and, since the cluster branch, `v2.0.0rc4` (its vectors and its interop venv): the conformance vectors, a round trip in both
directions (a space written by `proto_db` is dumped identically by protoBaseST, and a space
written by protoBaseST passes the `proto_db` verifier with an identical dump), the shapes of AVL trees node by node, 27 concurrent-commit scenarios with both
languages as first and second committer, and a small ERP demo. What was not: anything outside
those scenarios, speed, long runs, and review by anyone but the people who wrote it.

**Cluster mode (0.2.0).** Several protoBaseST processes can share one database
directory as a cluster: `proto_db`'s protocol, rule by rule (a majority lease with numbered
terms, write permissions, a commit point of a majority of synced acceptances), at `v2.0.0rc4`,
protocol 14. It runs over one shared directory only, one permission at a time, on a trusted
network. It is tested in a seeded simulator with planted defects, in one process, and with real
processes killed with `kill -9`; `proto_db`'s 298 cluster tests are each ported or justified
(`tests/unit/cluster_checklist.tsv`). The final verification passed: the long soak (every
simulator family at 100 to 5000 seeds, commit 02d9826) and the whole timer audit (81 parts, 0
violations, commit 7cbac4a); the counts are under Tests below and in
[docs/not-done.md](docs/not-done.md). That is evidence from one simulator and one machine, not a
proof. Measured on one machine, indicatively: three
members commit about half as many small transactions per second as one standalone process on
disjoint roots, and a third as many on one hot key ([docs/deviations.md](docs/deviations.md#cluster-mode-commits-per-second)). Start with
[chapter 13](docs/tutorial/13-cluster-concepts.md); what it does not do is in
[docs/not-done.md](docs/not-done.md).

**Indexed queries (0.3.0).** Equality and range indexes that are part of a collection
version, maintained by every mutator and by merges; the query front end (`PBQuery`, `PBField`),
`proto_db`'s cost-based planner with the same plans and model costs, ordered reads, pages and
counts by rank, all from `proto_db` `v2.0.0rc4`, on the same disk format. Vector indexes came
in 0.4.0 (below). Checked: `proto_db`'s query and plan vectors, its index contract over 200 seeds, a
planned-equals-scan property over 5000 seeds and every collection kind, and its tests, each ported
or justified (`tests/unit/queries_checklist.tsv`). The atom weight work that came with it (plan
Tasks 11 and 12) cut the cells a stored index node keeps by about a third (stage 2 alone). Measured on one
quiet machine against `proto_db`: 3.5 to 35 times slower on every unit, and an indexed commit
spends most of its time on index work (65 % with one index, 85 % with three)
([docs/deviations.md](docs/deviations.md#the-final-comparison-plan-task-10)). Start with
[chapter 17](docs/tutorial/17-indexes.md) and [docs/queries.md](docs/queries.md).

**Vector search (0.4.0).** Vector indexes (`'exact'` and `'ivf_flat'` searched; `'hnsw'` maintained,
its search refused) that are part of a collection version like the others, `near[]` queries alone
and combined with conditions, and the planner's `near[]` rules, all from `proto_db` `v2.0.0rc4`,
on the same disk format. Every score is a correctly rounded sum, ported from CPython's `math.fsum`,
and IVF training is `proto_db`'s pure-Python k-means operation for operation, so both
implementations answer the same neighbours and write the same index bytes (on the same C library,
for training). Checked against `proto_db`: index trees node by node and refusal texts byte for byte
(101 indexes, every training of five growth histories), 4021 vector-math cases, 101 vector cases
among the query vectors, its index contract for vector indexes, and its vector tests, each ported
or justified. Measured on one machine against `proto_db`'s pure-Python mode, protoST 0.16.0: an
exact query over 10^4 vectors takes 3.4 to 5.1 times as long, an IVF build 2.4 times, a commit to
a vector-indexed collection 8.5 to 12.3 times
([docs/deviations.md](docs/deviations.md#vectors)). An IVF index retrained in a cluster needs a
lease longer than four times its retrain. Start with
[chapter 20](docs/tutorial/20-vector-search.md).

## What it shows

- **Objects persist as objects reachable from named roots**, the part of GemStone's model this
  takes: records, collections and tree nodes. Record classes are registered by type name.
- **Values and mutable objects.** Records and collections are immutable values; every change
  answers a new version that shares the unchanged parts. A `PBMutableObject` names a cell whose
  value moves from version to version, by commit.
- **Perennial history.** Every committed version stays readable (`history`, `snapshotAt:`).
- **A polyglot disk format.** One directory, two languages, the same answers.
- **No locks in the Smalltalk layer.** In-process synchronisation is by actors, Futures and
  atoms only; the one lock is the operating system's `flock` on `space.lock`, the format's
  inter-process protocol.

> ### Every collection message answers a new version
>
> `add:`, `remove:`, `setAt:value:`, `removeAt:`, `appendLast:` and the rest **answer a new
> collection and leave the receiver unchanged**. A statement that discards the answer changes
> nothing, and nothing fails:
>
> ```smalltalk
> tags := PBSet new.
> tags add: 'urgent'.            "builds a set and throws it away: tags is still empty"
> tags := tags add: 'urgent'.    "keep the answer"
> ```
>
> Three names clash with Pharo's meaning (design spec 5.3, ruling 2). They are `proto_db`'s names,
> kept on purpose so that one document explains both languages:
>
> | Message | Pharo | protoBaseST |
> |---|---|---|
> | `Set >> add:` | adds in place, answers the **element** | answers a **new set** |
> | `Set >> remove:` | removes in place, answers the element; signals when absent | answers a **new set**; an absent element is a no-op |
> | `List >> removeAt:` | removes in place, answers the element | answers a **new list** |
>
> `CountedSet >> add:` and `remove:` and `Dictionary >> removeAt:` follow the same rule.
> The alternatives (`copyWith:`, `copyWithout:`, `copyWithoutIndex:`) are in
> [docs/decisions.md](docs/decisions.md). This is the first thing to argue about.

> ### `PBList` positions are zero-based
>
> `getAt: 0` is the first element and `getAt: -1` the last. `proto_db`'s `List` is zero-based and
> the persisted tree counts are the same in both languages (design spec ruling 3). Smalltalk
> collections are one-based, so this is a trap for Smalltalk programmers; it is the price of
> sharing the format. A position out of range is `PBValidationError`, never `nil`. Every other
> collection a program builds (`Array`, `PBTuple`, `PBFrozenList`) is one-based as usual.

## Requirements

| Component | Version | Source |
|---|---|---|
| protoCore | v3.6.1 | https://github.com/numaes/protoCore |
| protoIO | v0.7.1 | https://github.com/gamarino/protoIO |
| protoST | v0.17.0 | https://github.com/gamarino/protoST |

These are the minimum versions: protoST 0.17.0 is the floor, and it is checked when the package
loads: on an older protoST, `Import from: 'protobase'` signals `PBNotSupportedError` ("protoBaseST
0.4.1 requires protoST 0.17.0 or later (protoIO 0.7.1)", with the missing capabilities;
`src/protobase/floor.st`). A TCP cluster needs it: its helping
waits run one message at a time (protoST S48), and protoIO 0.7.1 bounds a whole socket write by its
timeout and reports how many bytes it wrote (S49), which together let `PBTcpTransport` end every
turn, so an actor that waits while a connection is open is never buried under it (CHANGELOG,
0.4.0, "Fixed"). The vector kernel calls protoST's `Float` fsum primitives (0.15.0) and its k-means
distance primitive (0.16.0) directly; the Smalltalk kernel they replace is kept as the tests'
oracle. The final 0.4.0 suite ran on protoST 0.16.1, protoCore 3.6.1 and protoIO 0.7.1 (the 0.3.0
release was tested on protoCore 3.6.0 with protoST 0.12.0); the 0.4.1 suite ran on protoST 0.17.0, protoCore
3.6.1 and protoIO 0.7.1 (315 passed, 0 failed, 3 skipped, with the interop venv). The vector benchmarks of 0.4.0 ran on
0.16.0, whose vector primitives 0.16.1 keeps unchanged.

**Recommended: protoST 0.17.2** (built against protoCore 3.6.2). It fixes S51: on arm64, notably
macOS on Apple silicon, a message sent to an actor could be left in its mailbox unscheduled, so a
program waiting on the reply hung (measured on loaded macOS runners: about 1 run in 7,500 before
the fix, none in 183,271 runs after it). Every protoBaseST write goes through the space's round
runner, an actor (and the cluster roles and transports are actors too), so it is exposed to that
hang. The floor stays protoST 0.17.0, since 0.17.2 changes no API;
the 0.4.1 suite has not been re-run on 0.17.2.

Build protoST 0.17.0 against protoCore 3.6.1 and protoIO 0.7.1 (see its own README); it provides
`lib/decimal.st`, `lib/calendar.st`, `lib/uuid.st`, the fixes for protoST issues S37 to S49,
`BinaryFile >> linkCount` and `FileReference >> realPath` (the hard-link refusal and the lock
naming of the cluster logs), the exact `Fraction` comparison and the ByteArray primitive that
reads an unsigned Integer of any width from bytes (both from protoST 0.14.0), the `Float` fsum and
k-means distance primitives (0.15.0 and 0.16.0), and the bounded helping wait and write timeout
(0.16.1), and compareAndSet:from:to: (0.17.0, which replaces the deprecated
setInstVar:from:to: in the write-once publishers), which this code
relies on. The Python interop tests and the ERP demo also need a checkout of the
[protoBase repository](https://github.com/gamarino/ProtoDB), at the tag `v2.0.0rc4` (`v2.0.0rc2`
before the cluster branch), and Python 3.12 or newer (3.11 before it; tested with 3.14):

```sh
git clone https://github.com/gamarino/ProtoDB ../ProtoBase    # default location; or set PROTOBASE_REPO
```

## Quick start

You also need this repository's `src/` on the module path. Run from a trusted directory: protoST
searches the working directory before its library, so an untrusted directory's `.st` files can
replace library modules (see [docs/deviations.md](docs/deviations.md#known-protost-limits)).

```sh
export PROTOST=../protoST/build_release/protost
STPATH=$PWD/src $PROTOST hello.st
```

```smalltalk
Import from: 'protobase'.

| dir space db hits |
dir := FileSystem temp / ('protobase-hello-' , Smalltalk pid printString).
dir deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'hello'.
db newTransactionDo: [:tr |
    tr setRootObject: 'hits' value: 0.
    tr setRootObject: 'tags' value: (tr newDictionary setAt: 'first' value: true)].
db run: [:tr | tr setRootObject: 'hits' value: (tr getRootObject: 'hits') + 1].
hits := db newTransaction getRootObject: 'hits'.
hits.                                          "=> 1"
db history size.                               "=> 3"
space close.
```


## Tutorials

Start here. Every chapter is short, explains why the design is what it is, and quotes a small
program that checks its own results and is run by the tests.

| Read | What you learn |
|---|---|
| [The tutorial, chapters 1-12](docs/tutorial/README.md) | A single process: first commit, values and versions, records, collections and queries, transactions and conflicts, blind writes, mutables and history, bytes, actors, crash recovery, Python interop, refusals. |
| [Cluster mode, chapters 13-16](docs/tutorial/13-cluster-concepts.md) | Several processes sharing one database: [the ideas](docs/tutorial/13-cluster-concepts.md), [a three-node cluster](docs/tutorial/14-a-three-node-cluster.md), [failures and recovery](docs/tutorial/15-failures-and-recovery.md), [operating a cluster](docs/tutorial/16-operating-a-cluster.md). |
| [Queries, chapters 17-19](docs/tutorial/17-indexes.md) **(0.3.0)** | [Indexes](docs/tutorial/17-indexes.md) and [queries and the planner](docs/tutorial/18-queries-and-plans.md) and [ordered reads and pages](docs/tutorial/19-ordered-reads-and-pages.md) run. |
| [Vector search, chapter 20](docs/tutorial/20-vector-search.md) **(0.4.0)** | Nearest-neighbour search with vector indexes, combined with conditions; why the scores are correctly rounded sums; why `x ** 2` is not `x * x`; IVF-Flat and its recall. |
| [A small ERP](docs/tutorial/erp.md) | A guided build of a real application, with the reasoning at each step. |
| [Coming from GemStone/S](docs/tutorial/gemstone.md), [Coming from Soil](docs/tutorial/soil.md) | Orientation for readers who know those systems. |

The programs are in [examples/tutorial/](examples/tutorial/README.md) and
[examples/cluster/](examples/cluster/README.md).

## The API, mapped from `proto_db`

Names are `proto_db`'s public names at `v2.0.0rc4`, prefixed `PB` in place of a namespace, in
Smalltalk camelCase. Python keyword arguments become keyword parts. Timeouts and backoffs are
SmallInteger milliseconds, not float seconds.

### Classes

| `proto_db` (Python) | protoBaseST |
|---|---|
| `ObjectSpace`, `FileStorage`, `Database` | `PBObjectSpace`, `PBFileStorage`, `PBDatabase` |
| `Transaction`, `Snapshot`, `HistoryEntry` | `PBTransaction`, `PBSnapshot`, `PBHistoryEntry` |
| `DBObject`, `MutableObject` | `PBObject`, `PBMutableObject` |
| `List`, `Dictionary`, `HashDictionary` | `PBList`, `PBDictionary`, `PBHashDictionary` |
| `Set`, `CountedSet`, `RepeatedKeysDictionary` | `PBSet`, `PBCountedSet`, `PBRepeatedKeysDictionary` |
| `EqualityIndex`, `RangeIndex`, `VectorIndex` | `PBEqualityIndex`, `PBRangeIndex`, `PBVectorIndex` (0.4.0: maintained, its collections written and merged, searched; hnsw search refused) |
| `FrozenList`, `FrozenDict`, `MISSING`, a Python tuple | `PBFrozenList`, `PBFrozenDict`, `PBMissing`, `PBTuple` |
| `OpaqueAtom` | `PBOpaqueAtom` |
| `KeySpec`, `Term`, `And`, `Or`, `Not`, `PythonPredicate` | `PBKeySpec`, `PBTerm`, `PBAnd`, `PBOr`, `PBNot`, `PBBlockPredicate` |
| `F`, `Field`; `Queryable` | `PBField`; `PBQuery` |
| `PythonFilter` (an `explain` node) | `BlockFilter` (`PBBlockFilter`) |
| `NearQuery`, `VectorSearch` **(0.4.0)** | `PBNearQuery`, `PBVectorSearch` (chosen by the planner; [Addendum V](docs/superpowers/specs/2026-11-19-vectors-addendum.md)) |
| `F.vec.near(v, k=5)` **(0.4.0)** | `(PBField path: 'vec') near: v k: 5` |
| `ProtoValidationError`, `ProtoCorruptionError`, `ProtoNotSupportedError`, `ProtoConflictError`, `ProtoTimeoutError`, `ProtoOutcomeUnknownError`, `ProtoUserError`, `ProtoClosedError` | `PBValidationError`, `PBCorruptionError`, `PBNotSupportedError`, `PBConflictError`, `PBTimeoutError`, `PBOutcomeUnknownError`, `PBUserError`, `PBClosedError` |

### Messages

| `proto_db` (Python) | protoBaseST |
|---|---|
| `FileStorage(path)` | `PBFileStorage path: '/srv/erp'` (durability is always `fsync`) |
| `ObjectSpace(storage, lock_timeout=s)` | `PBObjectSpace storage: aStorage`, `storage:lockTimeout:` (milliseconds) |
| `register_atom_class(cls)` | `PBObjectSpace registerAtomClass: aClass` |
| `space.new_database(n)`, `open_database(n)`, `list_databases()`, `close()` | `newDatabase:`, `openDatabase:`, `listDatabases`, `close` |
| `db.name`, `db.new_transaction()`, `db.history()`, `db.snapshot_at(ref)` | `name`, `newTransaction`, `history`, `snapshotAt:` |
| `db.run(fn, retries=10, backoff=(0.001, 0.2))` | `run:`, `run:retries:`, `run:retries:backoff:` |
| `with db.new_transaction() as tr:` | `newTransactionDo: aBlock` (commits at the end, aborts on an exception) |
| `tr.get_root_object(n)`, `set_root_object(n, v, replace=)`, `remove_root_object(n)`, `root_names()` | `getRootObject:`, `setRootObject:value:`, `setRootObject:value:replace:`, `removeRootObject:`, `rootNames` |
| `tr.new_mutable(n, v)`, `get_mutable(n)`, `set_mutable(n, v)`, `remove_mutable(n)`, `mutable_names()` | `newMutable:value:`, `getMutable:`, `setMutable:value:`, `removeMutable:`, `mutableNames` |
| `tr.new_list()`, `new_dictionary()`, `new_hash_dictionary()`, `new_set()`, `new_counted_set()` | `newList`, `newDictionary`, `newHashDictionary`, `newSet`, `newCountedSet` |
| `tr.new_object(**attrs)` | `newObject: { 'name' -> 'Ada'. 'born' -> 1815 }` |
| `tr.commit()`, `abort()`, `is_active` | `commit`, `abort`, `isActive` |
| `Snapshot.version`, `committed_at`, `root_names`, `get_root_object(n)`, `mutable_names`, `get_mutable(n)` | `version`, `committedAt`, `rootNames`, `getRootObject:`, `mutableNames`, `getMutable:` |
| `MutableObject(name)`, `.name`, `.get(tr)`, `.set(tr, v)` | `PBMutableObject name: 'customer:acme'`, `name`, `get: tr`, `set: tr value: v` |
| `DBObject.with_(**changes)`, `has_defined_attr(n)`, attribute read | `with: 'field' value: v`, `withAll: { 'a' -> 1 }`, `hasDefinedAttr:`, `at:` (absent: `nil`) |
| `Application(**attrs)` | `Invoice withAll: { 'number' -> 1043. ... }` |
| `List.get_at(i)`, `set_at`, `insert_at`, `remove_at` | `getAt:`, `setAt:value:`, `insertAt:value:`, `removeAt:` |
| `List.append_first`, `append_last`, `extend`, `slice(a, b)`, `head(n)`, `tail(n)` | `appendFirst:`, `appendLast:`, `extend:`, `sliceFrom:to:`, `head:`, `tail:` |
| `Dictionary` / `HashDictionary` `.get_at(k, default)`, `has(k)`, `set_at`, `remove_at`, `keys()`, `values()`, `items()` | `getAt:`, `getAt:default:`, `has:`, `setAt:value:`, `removeAt:`, `keys`, `values`, `items` |
| `Set.add`, `remove`, `has`, `union`, `intersection`, `difference` | `add:`, `remove:`, `has:`, `union:`, `intersection:`, `difference:` |
| `CountedSet.add`, `remove`, `count_of(e)` | `add:`, `remove:`, `countOf:` |
| `IndexedCollection.index_names()`, `get_index(n)` | `indexNames`, `getIndex:` |
| `add_index(EqualityIndex("by_city", "city"))`, `remove_index(n)`, `validate()` | `addIndex: (PBEqualityIndex name: 'by_city' path: 'city')`, `removeIndex:`, `validate` |
| `F.city == v`, `!=`, `<`, `<=`, `>`, `>=` | `(PBField path: 'city') eq: v`, `ne:`, `<`, `<=`, `>`, `>=` (`=` is not overridden: it answers a Boolean) |
| `F.a.in_(vs)`, `F.a.between(a, b)`, `F.a.between_open(a, b)`, `F.a.between_left_open(a, b)`, `F.a.between_right_open(a, b)` | `in:`, `between:and:`, `betweenOpen:and:`, `betweenLeftOpen:and:`, `betweenRightOpen:and:` |
| `F.a.is_none()`, `not_none()`, `is_true()`, `not_true()`, `contains(v)`; `F()`, `F["@name"]` | `isNone`, `notNone`, `isTrue`, `notTrue`, `contains:`; `PBField element`, `PBField extractor: 'name'` |
| `p & q`, `p \| q`, `~p` | `p & q`, `p \| q`, `p not` (expressions only; a block enters a query only through `where:`) |
| `from_collection(c)`, `.where(p)`, `.where(fn)` | `PBQuery from: c`, `where: aCondition`, `where: [:e \| ...]` (chained `where:` is AND) |
| `.select([paths])`, `.select(fn)` | `project: #('name' 'age')`, `collect: aBlock` (no `select:`: Smalltalk's `select:` filters) |
| `.order_by(k, descending=)`, `.then_by(k, descending=)`, `.skip(n)`, `.take(n)`, `.distinct()` | `orderBy:`, `orderBy:descending:`, `thenBy:`, `thenBy:descending:`, `skip:`, `take:`, `distinct` |
| `.to_list()`, `.count()`, `.first()`, `.first_or_none()`, `.explain()`, `.plan()` | `asArray`, `count`, `first`, `firstOrNil`, `explain`, `plan` |
| `.count(p)`, `.first(p)`, `.first_or_none(p)`, `.explain_count()`; `F.a.between(a, b, inclusive=(lo, hi))`, `F.a.between_closed(a, b)`, `F.a.range(a, b, bounds)` | `count:`, `first:`, `firstOrNil:`, `explainCount`; `between:and:inclusive:`, `betweenClosed:and:`, `range:to:bounds:` |
| `plan_query(source, where, order_by, limit, offset)` | `PBPlanner plan:where:orderBy:limit:offset:` |
| iteration (`for x in coll`) | `do:`; `keysAndValuesDo:` on the dictionaries |

The complete list of what exists is [docs/reference.md](docs/reference.md). There is no `asOf:`
because `proto_db` has none; the tutorial shows the three-line helper.

## What it refuses

If a value, type, version or operation cannot be stored or done exactly, protoBaseST signals an
error naming it. It does not store something else in its place. A `Symbol` longer than six bytes,
a protoST `Dictionary` (its order is unspecified), a `Fraction`, a write to a collection holding an unknown index kind,
a wall clock in an IANA zone: each is refused, and each refusal protects a specific property of
the file. [docs/deviations.md](docs/deviations.md) lists all of them and the cost of each.

## Documentation

| | |
|---|---|
| [docs/tutorial/erp.md](docs/tutorial/erp.md) | A guided build of a small ERP, with the reasoning at each step. Every snippet is run by the tests. |
| [docs/tutorial/](docs/tutorial/README.md) | The chaptered tutorial: chapters 1-12 on a single process, chapters 13-16 on cluster mode, chapters 17-19 on indexed queries, chapter 20 on vector search (0.4.0), each quoting a program of `examples/tutorial/` or `examples/cluster/`; and two orientation chapters, coming from GemStone/S and coming from Soil, with their sources. |
| [examples/cluster/](examples/cluster/README.md) | The cluster chapters' programs, run by the tests; `pending/` is for those that need API still being built (none today). |
| [examples/tutorial/](examples/tutorial/README.md) | Small programs, one concept each, each checking its own results; run by the tests. |
| [docs/reference.md](docs/reference.md) | Every public class and message, the indexed-query API and pagers included. |
| [docs/queries.md](docs/queries.md) | **0.3.0:** indexed queries and the query planner, the conceptual guide, including how to read `explain`; **0.4.0:** vector search, with a worked vector plan. |
| [examples/queries/](examples/queries/README.md) | **0.3.0:** the programs of the guide, run as tests; **0.4.0:** `vector_search.st` and `vector_plans.st`; `pending/` is empty. |
| [docs/deviations.md](docs/deviations.md) | Every refusal and every difference from `proto_db`. |
| [docs/not-done.md](docs/not-done.md) | What is not done, and what is not proven. |
| [docs/decisions.md](docs/decisions.md) | The choices, with what each costs if it is wrong. |
| [examples/erp/](examples/erp/README.md) | A demo in which Python and protoST work on one directory. |
| [docs/superpowers/specs/2026-11-10-protobasest-prototype-design.md](docs/superpowers/specs/2026-11-10-protobasest-prototype-design.md) | The design. |
| [CHANGELOG.md](CHANGELOG.md) | What changed, release by release; the detailed log of 0.2.0 is [docs/changelog-0.2.0-development.md](docs/changelog-0.2.0-development.md). |

## Running the tests

The tests need protoST 0.17.0 or newer (see Requirements). Point `PROTOST` at the binary:

```sh
export PROTOST=../protoST/build_release/protost      # default: protost from PATH
tests/conformance/fetch_vectors.sh                    # only to re-vendor the format-4 vectors (they are already in the repository)
PYTHON=python3.14 tests/interop/setup_venv.sh         # Python side of the interop tests (needs the checkout above)
PYTHON=python3.14 tests/interop/setup_venv_numpy.sh   # proto_db in its default mode, with numpy (the vector tests that hand spaces both ways)
tests/run_tests.sh                                    # everything under tests/ and examples/, less tests/audit
tests/run_tests.sh tests/unit tests/docs              # or chosen paths
tests/run_tests.sh tests/audit                        # the cluster's timer audit alone (measured: 2 h 22 min)
tests/run_tests.sh --audit                            # the default set and the timer audit
```

`tests/cluster/` runs cluster members as separate protost processes over TCP on 127.0.0.1
(`_node.st`, driven by `_cluster.sh`): three members committing concurrently, and `kill -9` of the
owner, of a voter, and of two owners in turn in a five-voter cluster, while they commit;
`kill -9` of a permission holder mid-round (its root built, its replicate sent, its done sent),
each restarted on its disk, then the whole cluster killed before its commits were persisted and
restarted on its disks; a voter killed, its acceptor log lost, rejoining by ballot. Each run
starts four to six processes; every one is killed and reaped when the test ends, on every exit
path. `verify_rules.sh` checks the verifier's rules on synthetic files, with no process.

`tests/audit/` holds the cluster's timer audit: every timer of the coordination at 1/10, 10 times
and skewed per member, 3420 simulator runs, a run of its own. Only a path that names it, or
`--audit`, runs it; its index `tests/unit/sim_timer_audit.st` stays in the default run (the audit's
configuration and one run per mode) and fails when an audit file is missing, extra or stale. Each
audit file fails on a violation, and also when its runs fall below their declared floors of strict
runs and acknowledged commits, or when a timer's probe (acquireTimeout, gatherAttempts,
retryHold) leaves its bounds; the safety-only row-modes and the rows not exercised yet (persist,
until Task 20) are declared and listed by the index. In the final verification the full timer audit
(81 parts, 3420 simulator runs) ran twice at the final code: the first run had no violation but
missed 36 floors by 1 to 7 commits, because 02d9826 changes every schedule (bisected), so the floors
were re-measured from it (7cbac4a); the second run passed whole at 7cbac4a in 2 h 22 min, serially.

The runner prints `PASS`, `FAIL` or `SKIP` per test and ends with `passed N, failed N, skipped N`.
A `.st` test starts with an `"EXPECT: <last line>"` or `"EXPECT-ERROR: <text>"` directive; a
`.sh` test passes with exit 0 and is skipped with exit 77. `PROTOBASE_REPO` (default `../ProtoBase`)
names the protoBase checkout used by the two setup scripts. `tests/docs/` checks the snippets of
the README and the tutorial against the code, the code quoted by the chapters of `docs/tutorial/`
against the programs of `examples/tutorial/` and `examples/cluster/`, the selectors the documents
cite against `src/protobase`, and the reference's timer table against `PBClusterConfig timerTable`.

## Benchmarks

`bench/` holds the measurements; none runs in the test suite. `run_avl.sh` and `run_tx.sh` compare
the single process with `proto_db`; `run_cluster.sh` measures standalone mode and clusters of one
and three member processes on one machine. Each run reports the work it did and a verifier's
count, and the runner refuses a run whose counts differ. The dated figures, with the machine and
the commit, are in [docs/deviations.md](docs/deviations.md#performance): indicative only.

## License

MIT. Copyright (c) 2026 Gustavo Marino.

Third-party material: `tests/conformance/` (the vectors, `manifest.json`, `vectors.sha256`) is
vendored from `proto_db` at `v2.0.0rc4` (`v2.0.0rc2` before the cluster branch), MIT, Copyright (c) 2023 ProtoBase Team. Its notice is in
[tests/conformance/LICENSE](tests/conformance/LICENSE).
