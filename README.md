# protoBaseST

A perennial object database for protoST, in the tradition GemStone opened.

protoBaseST is a Smalltalk implementation, on protoST, of the Python object database `proto_db`
(developed in the [protoBase repository](https://github.com/gamarino/ProtoDB)). It reads and
writes the **same on-disk format** (format 4, frozen at `v2.0.0rc1`, with the value nesting limit
of `v2.0.0rc2`), so one database directory can be shared
by Python and Smalltalk programs. It has `proto_db`'s API translated to Smalltalk, and `proto_db`'s
transaction semantics: snapshot isolation, read sets checked at commit, merges of blind writes,
mutable cells, retries.

## Status

**A proposal prototype, for discussion at the FAST Smalltalk workshop (2026-12-03). Not a product.**
It is shown to start a conversation and to collect criticism. It is small and meant to be correct;
it is not fast and not complete. Read [docs/not-done.md](docs/not-done.md) first: it states what
is missing and what has not been proven.

What was checked, against `proto_db` at `v2.0.0rc2`: the conformance vectors, a round trip in both
directions (a space written by `proto_db` is dumped identically by protoBaseST, and a space
written by protoBaseST passes the `proto_db` verifier with an identical dump), the shapes of AVL trees node by node, 27 concurrent-commit scenarios with both
languages as first and second committer, and a small ERP demo. What was not: anything outside
those scenarios, speed, long runs, and review by anyone but the people who wrote it.

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
| protoCore | v3.6.0 | https://github.com/numaes/protoCore |
| protoIO | v0.7.0 | https://github.com/gamarino/protoIO |
| protoST | v0.12.0 | https://github.com/gamarino/protoST |

Build protoST 0.12.0 against protoCore 3.6.0 and protoIO 0.7.0 (see its own README); it provides
`lib/decimal.st`, `lib/calendar.st`, `lib/uuid.st`, the fixes for protoST issues S37 to S40 and
`BinaryFile >> linkCount` and `FileReference >> realPath` (the hard-link refusal and the lock
naming of the cluster logs), which this code relies on. The Python interop tests and the ERP demo also need a checkout of the
[protoBase repository](https://github.com/gamarino/ProtoDB), at the tag `v2.0.0rc2`, and Python
3.11 or newer (tested with 3.14):

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

A fuller walk-through, with the reasoning behind each design choice, is
[docs/tutorial.md](docs/tutorial.md).

## The API, mapped from `proto_db`

Names are `proto_db`'s public names at `v2.0.0rc2`, prefixed `PB` in place of a namespace, in
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
| `EqualityIndex`, `RangeIndex`, `VectorIndex` | `PBEqualityIndex`, `PBRangeIndex`, `PBVectorIndex` (read only) |
| `FrozenList`, `FrozenDict`, `MISSING`, a Python tuple | `PBFrozenList`, `PBFrozenDict`, `PBMissing`, `PBTuple` |
| `OpaqueAtom` | `PBOpaqueAtom` |
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
| iteration (`for x in coll`) | `do:`; `keysAndValuesDo:` on the dictionaries |

The complete list of what exists is [docs/reference.md](docs/reference.md). There is no `asOf:`
because `proto_db` has none; the tutorial shows the three-line helper.

## What it refuses

If a value, type, version or operation cannot be stored or done exactly, protoBaseST signals an
error naming it. It does not store something else in its place. A `Symbol` longer than six bytes,
a protoST `Dictionary` (its order is unspecified), a `Fraction`, a write to an indexed collection,
a wall clock in an IANA zone: each is refused, and each refusal protects a specific property of
the file. [docs/deviations.md](docs/deviations.md) lists all of them and the cost of each.

## Documentation

| | |
|---|---|
| [docs/tutorial.md](docs/tutorial.md) | A guided build of a small ERP, with the reasoning at each step. Every snippet is run by the tests. |
| [docs/reference.md](docs/reference.md) | Every public class and message. |
| [docs/deviations.md](docs/deviations.md) | Every refusal and every difference from `proto_db`. |
| [docs/not-done.md](docs/not-done.md) | What is not done, and what is not proven. |
| [docs/decisions.md](docs/decisions.md) | The choices, with what each costs if it is wrong. |
| [examples/erp/](examples/erp/README.md) | A demo in which Python and protoST work on one directory. |
| [docs/superpowers/specs/2026-11-10-protobasest-prototype-design.md](docs/superpowers/specs/2026-11-10-protobasest-prototype-design.md) | The design. |
| [CHANGELOG.md](CHANGELOG.md) | What changed, task by task. |

## Running the tests

The tests need protoST 0.12.0 or newer (see Requirements). Point `PROTOST` at the binary:

```sh
export PROTOST=../protoST/build_release/protost      # default: protost from PATH
tests/conformance/fetch_vectors.sh                    # only to re-vendor the format-4 vectors (they are already in the repository)
PYTHON=python3.14 tests/interop/setup_venv.sh         # Python side of the interop tests (needs the checkout above)
tests/run_tests.sh                                    # everything under tests/ and examples/, less tests/audit
tests/run_tests.sh tests/unit tests/docs              # or chosen paths
tests/run_tests.sh tests/audit                        # the cluster's timer audit alone (some three hours)
tests/run_tests.sh --audit                            # the default set and the timer audit
```

`tests/audit/` holds the cluster's timer audit: every timer of the coordination at 1/10, 10 times
and skewed per member, 3240 simulator runs, a run of its own. Only a path that names it, or
`--audit`, runs it; its index `tests/unit/sim_timer_audit.st` stays in the default run (the audit's
configuration and one run per mode) and fails when an audit file is missing.

The runner prints `PASS`, `FAIL` or `SKIP` per test and ends with `passed N, failed N, skipped N`.
A `.st` test starts with an `"EXPECT: <last line>"` or `"EXPECT-ERROR: <text>"` directive; a
`.sh` test passes with exit 0 and is skipped with exit 77. `PROTOBASE_REPO` (default `../ProtoBase`)
names the protoBase checkout used by the two setup scripts. `tests/docs/` checks the snippets of
the README and the tutorial against the code.

## License

MIT. Copyright (c) 2026 Gustavo Marino.

Third-party material: `tests/conformance/` (the vectors, `manifest.json`, `vectors.sha256`) is
vendored from `proto_db` at `v2.0.0rc2`, MIT, Copyright (c) 2023 ProtoBase Team. Its notice is in
[tests/conformance/LICENSE](tests/conformance/LICENSE).
