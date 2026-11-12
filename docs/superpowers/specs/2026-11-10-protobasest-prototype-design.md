# protoBaseST prototype: a perennial object database for protoST

Status: **draft, revision 2, for maintainer review** (2026-11-10). Author: Gustavo Marino,
with Claude. No code is written until this document is approved.

Revision 2 applies the maintainer's answers to the six questions of revision 1, and one rule:
**when in doubt, ProtoBase v2.0.0rc1 is the reference**, for semantics, API shape and names.

Normative source: ProtoBase `docs/source/format-spec.rst` at tag `v2.0.0rc1` (commit
`c48f73e`). The conformance vectors are pinned by the SHA-256 of
`tests/conformance/vectors.sha256`:
`5f86eb09ed1683aa9f048051c64cca68d23b9fb753e87416cb1ecf11ed406df0`. The transaction semantics
follow `docs/source/concurrency-model.rst` and `proto_db/transactions.py` at the same tag.
"Spec §X" means a section of `format-spec.rst`; "CM §X" a section of
`concurrency-model.rst`. Background: `tasks/protobasest-readiness-2026-11-10.md`.

**Decisions recorded in this revision**

| # | Question | Decision (maintainer, 2026-11-10) |
|---|---|---|
| 1 | Where the code lives | A new repository, `protoBaseST`. `Decimal`, the calendar values and `UUID` go to protoST's `lib/` (§8) |
| 2 | Symbols | For the prototype, a `Symbol` is refused and strings are strings. When `@sym` lands, protoST gets an explicit wrapper; STATUS D35 stays (§4.4) |
| 3 | Immutability of stored values | By convention: built once, never assigned afterwards. No frozen instances (§4.1) |
| 4 | Names | ProtoBase's names with the `PB` prefix, the camelCase translation of the real API at the tag (§5) |
| 5 | Conflict granularity | **The same as ProtoBase**: per-root and per-cell read sets, the replace and merge rules, and the mutable-cell rules of D35 (§7) |
| 6 | Early primitives | Approved: protoIO 0.5.0 and protoST 0.10.0 (ruling R10) with `randomBytes:` and a microsecond clock, in weeks 0-1, once the protoPython release frees DEV12 (§9) |

## 1. Intent

protoBaseST is a perennial object database for protoST, in the tradition GemStone opened.
It is a Smalltalk implementation of ProtoBase (the Python package `proto_db`). It reads and
writes the **same files**: one directory, opened by a Python process and by a protoST process,
holds one database. It has the same API, translated to Smalltalk, and the same transaction
semantics.

This prototype is a **proposal**, not a product. It is shown at the FAST Smalltalk workshop on
2026-12-03 to start a discussion and to collect criticism. It must be honest, small and
correct; it need not be fast or complete. About three weeks of work.

**Acceptance: a cross-implementation round trip, in both directions.**
- A space written by ProtoBase is read by protoBaseST, and the contents agree.
- A space written by protoBaseST passes `python -m proto_db.tools.verify <dir>` (exit 0), and
  the contents it prints agree.
- Both directions run on the conformance vectors and on a small ERP example.
- Concurrent commits from both languages to one directory get ProtoBase's outcomes: the same
  conflicts, the same merges.

What the prototype shows the audience:
- objects persist as objects, as in GemStone;
- **values and mutable objects**: records and collections are immutable values, and every
  change answers a new version. A `PBMutableObject` names a cell whose value moves from
  version to version, by commit;
- **perennial history**: every committed version stays readable (`history`, `snapshotAt:`);
- **a polyglot disk format**: one directory, two languages, the same answers;
- in-process objects with real multithreading, synchronised by actors and atoms only.

## 2. Goals, non-goals, anti-goals

**Goals**
- A Reader and a Writer at the conformance levels of spec §"Status, versions and
  conformance", for file storage. It reads formats 2, 3 and 4 and writes format 4.
- ProtoBase's transaction model: snapshot isolation, read sets checked at commit, the merge
  of blind writes to the collections that support it, the mutable-cell rules, `run:` with
  retries, and outcome-unknown reporting.
- Core collections read and written: `List`, `Dictionary`, `HashDictionary`, `Set`,
  `CountedSet` (a stretch goal, §10), `DBObject` records, application record types, mutable
  cells.
- `RepeatedKeysDictionary` and every index type are read; they are not changed.
- A Smalltalk API that mirrors ProtoBase's, so that one document explains both languages.

**Non-goals for 2026-12-03** (stated openly in the talk)
- The cluster: framed logs, the wire protocol, leases. Mixed Python/protoST clusters stay
  outside acceptance until a protocol freeze (B11).
- Cloud and tiered storage.
- Writes to indexed collections, and merges onto indexed collections (refused, §7.4). Index
  queries: indexes are decoded and kept, not queried (moved out in this revision, §10).
  Vector-index writes, IVF training, hnsw and extractor indexes.
- `RepeatedKeysDictionary` writes and merges.
- IANA time zones: no wall-clock conversion (§4.3).
- The per-database class registry (`__currentModules` and so on) and `@sym`. Both are
  additive format-5 features (spec §"Format stability").
- Group commit (D52, implementation-specific), the query planner and LINQ, pagers,
  `snapshot_ref` byte references, residency, durability modes other than `fsync`, Windows.
- Rebuilding format-3 indexes, and `validate()`/`rebuilt()` of misfiled format-3 collections.

**Anti-goals**
- A value that changes in place. Every collection operation answers a new version.
- A lock, mutex or semaphore in the protoST layer. The `flock` on `space.lock` is the
  format's inter-process protocol; only the publisher actor takes it (§7.3).
- A value stored under a kind it does not have (a symbol as a string, a `Fraction` as a
  float, a `Dictionary` of unspecified order as a map). Refuse instead.
- A semantic divergence from ProtoBase hidden behind the same name. In particular, never
  replace a value where ProtoBase would merge it (§7.4).
- Silent failure. A value, type, version or operation the prototype cannot handle raises an
  explicit error naming it.
- Business rules in the database core: no constraints, schema checks or `ondelete` rules.
  Application classes keep them (the Odoo lesson).

## 3. Constraints

- protoST 0.9.0 gives the ground: `ByteArray`, `BinaryFile` (`#create #exclusive`,
  `readAt:size:`, `append:`, `sync`, `tryLock`), `FileSystem replace:with:` and
  `syncDirectory:`, `crc32`, `blake2b:`, `sha256`, `MessagePack` with `decodeOrdered:`,
  `Future after:` and `waitWithin:`, `Atom`, actors.
- OS and encoding primitives go into **protoIO**, for every runtime. protoST only binds them
  (`src/primitives/`) and adds classes in `lib/`.
- Synchronisation only through actors, Futures and `Atom`.
- Tests never depend on timing.
- The ProtoBase repository is read and never modified. The Python side of the tests installs
  ProtoBase from `git archive v2.0.0rc1` into a private venv.

## 4. The model in protoST

### 4.1 Values, atoms and mutable objects

ProtoBase's model, kept as is:
- **values**: scalars, frozen lists, tuples and frozen maps;
- **atoms**: records, collections and tree nodes. An atom is immutable. A change answers a new
  atom with a new `oid`, which shares every unchanged subtree by pointer;
- **mutable objects**: a `PBMutableObject` is an immutable handle naming a cell of the
  database's mutable table (`@mut`). The cell's value changes only by commit;
- **the transaction** is a unit of work, not a value. As in ProtoBase, it is an explicit
  object whose state moves from active to committed or aborted; it records reads and writes.
  The values it reads and writes stay immutable.

Collection operations keep ProtoBase's names (`setAt:value:`, `appendLast:`, `add:`), and
each one **answers a new version**; the receiver is unchanged. §5.3 notes the three names
that clash with Pharo's meaning.

**Immutability by convention** (decision 3). A persisted value is built once by a class-side
constructor or a transaction factory, and none of its methods assigns an instance variable
afterwards. protoST does not enforce this at run time (LANGUAGE.md §4.5). Two runtime-only
fields are exceptions, and neither is persisted: the memo of a lazy load (§6.3) and the
consumed mark of a collection's operation log (§7.2). Both are `Atom` cells, and both mirror
what ProtoBase does with `object.__setattr__`.

### 4.2 Value kinds and protoST classes

The canonical values of spec §"Canonical values", and what each becomes:

| Format kind | Wire form | protoST class when read | Accepted when written | Notes |
|---|---|---|---|---|
| nil | `nil` | `nil` | `nil` | |
| bool | `true`/`false` | `true`/`false` | `true`/`false` | a kind of its own: `true` is not `1` as a key |
| int | msgpack int, or `{"@int": hex}` outside -2^63..2^64-1 | `SmallInteger`, `LargeInteger` | any `Integer` | `@int` is signed lowercase hex, one spelling |
| float | `float 64` | `Float` | `Float` | NaN, ±inf and `-0.0` kept bit for bit |
| decimal | `{"@dec": text}` | `Decimal` (new, §9) | `Decimal` | to-scientific-string; sign, exponent, trailing zeros, NaN payloads and sNaN kept |
| str | msgpack str | `String` | `String` | NUL kept (0.9.0); lengths in code points |
| bytes | `bin` | `ByteArray` | `ByteArray` | |
| date | `{"@date": [y, m, d]}` | `CalendarDate` (new) | `CalendarDate` | proleptic Gregorian, years 1-9999 |
| time | `{"@time": [h, mi, s, us, fold, tz]}` | `TimeOfDay` (new) | `TimeOfDay` | naive, fixed offset, or `["zone", key]` |
| datetime | `{"@dt": [..., fold, tz]}` | `DateTime` (new) | `DateTime` | naive, fixed offset, or `["instant", key]` (§4.3) |
| timedelta | `{"@td": [d, s, us]}` | `TimeSpan` (new) | `TimeSpan` | normalized, in microseconds (the kernel `Duration` counts milliseconds) |
| uuid | `{"@uuid": 16 bytes}` | `UUID` (new) | `UUID` | Pharo's name and meaning |
| list | msgpack array | `PBFrozenList` | `PBFrozenList`, `Array`, `OrderedCollection` (copied at once) | ProtoBase's `FrozenList`; not orderable |
| tuple | `{"@tup": [...]}` | `PBTuple` | `PBTuple` | orderable when its items are |
| map | `{"@map": [[k, v], ...]}` | `PBFrozenDict` | `PBFrozenDict` only | ProtoBase's `FrozenDict`; insertion order kept. A protoST `Dictionary` is **refused**: its order is unspecified, and the order is part of the exact token |
| missing | `{"@missing": 0}` | `PBMissing` (ProtoBase's `MISSING`) | — | only in index keys |
| mutable | `{"@mut": name}` | `PBMutableObject` | `PBMutableObject` | |
| ref | `{"@ref": [seg, off, tag]}` | the atom, loaded on access (§6.3) | any atom | |
| opaque atom | a record of a type with no class | `PBOpaqueAtom` | as a reference only | never re-written (D59) |
| — | — | — | `Symbol` (class `Symbol`) | **refused** (§4.4) |
| — | — | — | `Fraction`, `Character`, `Set`, `Bag`, `Dictionary`, `Interval`, a block, any other object | **refused** with `PBValidationError`, naming the class |

- A host subclass of a mapped class is stored as its base value (spec §"Canonical values").
- Equality between stored values, and dictionary keys, follow the format's order keys (§6.1),
  never protoST's `=`. `1`, `1.0` and `Decimal 1.00` are one key; `true` and `1` are two; and
  `10**16 + 1` is not `1.0e16`. protoST's `=` would coerce through doubles.

### 4.3 Time zones without a tz database

protoST has no IANA database (readiness §3). The rules, all explicit:
- A fixed offset is fully supported, its name included (`"UTC"`, `"UTC-03:00"`).
- **Zone keys: a pinned list** (decided at the Task 7 review).
  - A key is valid when it is in `PBZoneKeys` (`src/protobase/zonekeys.st`): the Zone and
    Link names of one IANA tzdata release, `Factory` excluded. Host-relative names such as
    `localtime` and `posixrules` are never keys.
  - The list is generated by `tools/gen_zone_keys.py <tzdata.zi> <release>` and committed.
    The release is recorded in the file (`PBZoneKeys release`).
  - A key outside the list is `PBCorruptionError` when read and `PBValidationError` when
    written, identically on every machine. The format spec makes key validity relative to
    the reader's database, and this list is protoBaseST's database of keys.
  - A key newer than the pinned release is refused explicitly until the list is regenerated,
    which is a deliberate commit.
  - **Cost: a pinned key may be refused by a ProtoBase host** (decided at the Task 7
    re-review). ProtoBase checks a key against the host's own tz database, so a host without
    some of the pinned names refuses them when it reads. On the reference host (no
    `tzdata-legacy` and no `tzdata` Python package), ProtoBase refuses 113 of the 597 pinned
    keys, the backward links such as `US/Eastern` and `America/Buenos_Aires`, with
    `ProtoCorruptionError "Malformed @time value"`. ProtoBase on a host that has those links
    writes the same keys. The format makes key validity relative to the reader's database
    (Known gaps), so protoBaseST neither refuses nor rewrites such keys: refusing them on
    write would make protoBaseST unable to re-save an atom that ProtoBase wrote legitimately,
    and the reader must accept them in any case. Cross-implementation tests (§10.2, §10.3)
    use canonical Zone names only.
- A format-4 `["instant", key]` datetime is read as its UTC instant **plus the zone key**. It
  orders, hashes, tokenizes and re-encodes exactly, because none of that needs the zone's
  rules (D58). Asking for its wall clock signals `TimeZoneUnavailable` (protoST's calendar,
  call C7).
  - **Reading.** It is read and presented in UTC even when its wall clock in the zone might
    fall outside years 1 to 9999, which a reader cannot check without the zone's rules. The
    format spec (Known gaps) explicitly lets a reader without a database "present the instant
    in UTC". Refusing would call valid data corrupt (9999-12-31 12:00Z in `America/New_York`
    is valid). The conformance vector `invalid/value-instant-wall-out-of-range` is therefore
    accepted: a permanent expected difference (plan Task 8).
  - **Writing.** An instant within one day of year 1 or year 9999 is refused with
    `PBNotSupportedError`, because ProtoBase refuses to read such a value back when its wall
    clock leaves the range. The cost: a `datetime.max`-style sentinel in an IANA zone cannot
    be written from protoST, and an atom that holds such an in-band instant written by
    ProtoBase can be read but not modified (re-written) by protoBaseST.
- Building a zoned datetime from a wall clock is refused (`TimeZoneUnavailable`, call C7). The
  application stores a UTC or fixed-offset datetime, or a naive datetime plus the zone name.
- **A format-3 `["zone", key]` datetime** (legacy data) is read *lazily*. This supersedes the
  earlier "refused when read" (decided at the Task 7 review). It decodes to a
  `PBLegacyZoneDateTime`, a `DateTime` that answers `isLegacyZone` true and holds the wall
  clock and fold as written. It is never given an offset. Every use that needs the offset
  signals `PBNotSupportedError` naming the zone:
  - its hash, its order and its UTC instant;
  - equality with an aware value of another zone or kind;
  - a map with two keys that could conflict. That is exactly when the two keys are equal
    under the order-key rule at every position (the key itself, or each item of a tuple key,
    nested tuples included) except positions that hold aware or format-3 datetimes, and at
    one such position one key holds a format-3 datetime and the other either an aware datetime whose
    UTC instant is within 24 h of the format-3 wall clock, or a format-3 datetime of another
    zone whose wall clock is within 48 h. Every offset is under 24 h, so keys farther apart
    can never be one instant, and keys that differ at another position never conflict. The
    check is linear apart from one sort per datetime position: keys are grouped by a coarse
    probe in which every aware or format-3 datetime is one token, and only a group of two or
    more keys is examined. A map with one key is never refused. Equality (`=`) applies the
    same 24 h and 48 h windows and answers false outside them.
    At the other positions numbers fold as the order-key rule says: `true`, `1`, `1.0` and
    `Decimal("1.00")` are one item (corrected at the Task 7 re-review, N6). Other items
    compare by class and `=`, which for them is the same equality.

  Writing it is refused with `PBValidationError`. Two things need no offset and work:
  - its wall-clock date;
  - equality with a format-3 value of the same zone, by wall clock with fold ignored. This is
    Python's same-tzinfo rule. For map keys of one zone it is exactly the format's format-3
    conflict rule: a wall clock that occurs once is identified by its instant, and an
    ambiguous or skipped one by its wall clock, so two keys of one zone conflict only when
    their wall clocks are equal. The spring-forward 02:30 and 03:30 are two keys.

  Why lazily: old atoms whose other attributes are fine stay readable, and atoms that are
  never changed are kept byte for byte, as the spec requires. ProtoBase re-encodes such a
  value as its instant, which needs a database, so the vector
  `values_decode_only/datetime-zone-format3` is a permanent expected difference (plan Task 8).
- `["zone", key]` inside a `@time` is a wall clock without a date. It orders as the naive
  time, so it is fully supported.

### 4.4 Symbols (decision 2)

- **For the prototype:** a value of class `Symbol` is refused with `PBValidationError`.
  Strings are strings.
- In protoST a literal of 6 bytes or fewer, such as `#paid`, *is* the `String` `'paid'`
  (STATUS D35, which stays). It is therefore stored as a string; the format sees only what the
  program holds.
- **Future direction, when `@sym` lands (format 5):** protoST gets an explicit wrapper class
  for persisted symbols, to be named then. It is written as `@sym` and read back as the
  wrapper. Code that wants a stored symbol says so explicitly, and nothing depends on telling
  a short `Symbol` from a `String`. This answers B2 from protoST's side.
- Attribute names, root names and mutable-cell names are names, not values. A symbol is
  accepted for them, since on disk they are always strings.

### 4.5 Application record types

As in ProtoBase, an application type subclasses `PBObject` (ProtoBase's `DBObject`). It
declares its language-neutral name (`__type_name__` in Python) and its former names
(`__type_aliases__`), and is registered with `registerAtomClass:`. The same name and aliases
must be declared in every implementation (D57).

Accessors only answer the stored value (A4: an accessor is not behaviour). Behaviour methods
must not share a name with a persisted attribute, in any implementation of the type. There
are no generated setters: a change goes through `with:value:`, which is ProtoBase's `with_()`.

```smalltalk
PBObject subclass: #Invoice.

Invoice class >> typeName      ^ 'demo.erp.Invoice'.
Invoice class >> typeAliases   ^ #().

"Accessors: they only answer the stored value."
Invoice >> number     ^ self at: 'number'.
Invoice >> total      ^ self at: 'total'.
Invoice >> paidOn     ^ self at: 'paidOn'.

"Behaviour: reserves the name isPaid, which no implementation may persist."
Invoice >> isPaid     ^ self paidOn notNil.

PBObjectSpace registerAtomClass: Invoice.
```

The registry is process-wide, as ProtoBase's is (`register_atom_class`). It is held in an
`Atom` over an immutable map. A record whose type has no registered class reads as a
`PBOpaqueAtom` (D59). The per-database, module-composed registry is excluded (§2).

## 5. Names: ProtoBase's API, translated

**Decided** (decision 4): ProtoBase's public names at `v2.0.0rc1`, with the prefix `PB` in
place of a namespace (protoST has none) and Smalltalk camelCase. Python keyword arguments
become keyword parts named after the parameter. Every name below was checked against the
tag (`proto_db/__init__.py`, `transactions.py`, `collections/*.py`, `core/dbobject.py`,
`values.py`).

### 5.1 Classes

| ProtoBase (`proto_db`) | protoBaseST |
|---|---|
| `ObjectSpace` | `PBObjectSpace` |
| `FileStorage` | `PBFileStorage` |
| `Database` | `PBDatabase` |
| `Transaction` | `PBTransaction` |
| `Snapshot` | `PBSnapshot` |
| `HistoryEntry` | `PBHistoryEntry` |
| `DBObject` | `PBObject` |
| `MutableObject` | `PBMutableObject` |
| `List`, `Dictionary`, `HashDictionary` | `PBList`, `PBDictionary`, `PBHashDictionary` |
| `Set`, `CountedSet`, `RepeatedKeysDictionary` | `PBSet`, `PBCountedSet`, `PBRepeatedKeysDictionary` |
| `EqualityIndex`, `RangeIndex`, `VectorIndex` | `PBEqualityIndex`, `PBRangeIndex`, `PBVectorIndex` (read only) |
| `FrozenList`, `FrozenDict`, `MISSING` | `PBFrozenList`, `PBFrozenDict`, `PBMissing` |
| `OpaqueAtom` (`proto_db.core.atom`) | `PBOpaqueAtom` |
| `ProtoValidationError`, `ProtoCorruptionError`, `ProtoNotSupportedError`, `ProtoConflictError`, `ProtoTimeoutError`, `ProtoOutcomeUnknownError`, `ProtoUserError`, `ProtoClosedError` | `PBValidationError`, `PBCorruptionError`, `PBNotSupportedError`, `PBConflictError`, `PBTimeoutError`, `PBOutcomeUnknownError`, `PBUserError`, `PBClosedError` |
| (a tuple, a Python built-in) | `PBTuple` |

### 5.2 Messages

| ProtoBase | protoBaseST |
|---|---|
| `FileStorage(path, durability="fsync")` | `PBFileStorage path: '/srv/erp'` (durability is always `fsync`) |
| `ObjectSpace(storage, lock_timeout=s)` | `PBObjectSpace storage: aStorage`, `storage:lockTimeout:` (milliseconds) |
| `register_atom_class(cls)` | `PBObjectSpace registerAtomClass: aClass` |
| `space.new_database(name)`, `open_database(name)`, `list_databases()`, `close()` | `newDatabase:`, `openDatabase:`, `listDatabases`, `close` |
| `db.name`, `db.new_transaction()`, `db.history()`, `db.snapshot_at(ref)` | `name`, `newTransaction`, `history`, `snapshotAt:` (a `PBHistoryEntry` or `PBSnapshot`) |
| `db.run(fn, retries=10, backoff=(0.001, 0.2))` | `run: aBlock`, `run:retries:`, `run:retries:backoff:` |
| `with db.new_transaction() as tr:` | `newTransactionDo: aBlock` (commits when the block ends, aborts on an exception) |
| `tr.get_root_object(n)`, `set_root_object(n, v, replace=)`, `remove_root_object(n)`, `root_names()` | `getRootObject:`, `setRootObject:value:`, `setRootObject:value:replace:`, `removeRootObject:`, `rootNames` |
| `tr.new_mutable(n, v)`, `get_mutable(n)`, `set_mutable(n, v)`, `remove_mutable(n)`, `mutable_names()` | `newMutable:value:`, `getMutable:`, `setMutable:value:`, `removeMutable:`, `mutableNames` |
| `tr.new_list()`, `new_dictionary()`, `new_hash_dictionary()`, `new_set()`, `new_counted_set()` | `newList`, `newDictionary`, `newHashDictionary`, `newSet`, `newCountedSet` |
| `tr.new_object(**attrs)` | `newObject: { 'name' -> 'Ada'. 'born' -> 1815 }` |
| `tr.commit()`, `abort()`, `is_active` | `commit`, `abort`, `isActive` |
| `Snapshot.version`, `committed_at`, `root_names`, `get_root_object(n)`, `mutable_names`, `get_mutable(n)` | `version`, `committedAt`, `rootNames`, `getRootObject:`, `mutableNames`, `getMutable:` |
| `HistoryEntry.version`, `committed_at`, `root_names`, `mutable_names`, `get_mutable(n)` | `version`, `committedAt`, `rootNames`, `mutableNames`, `getMutable:` (no `getRootObject:`, as in ProtoBase: open the version with `snapshotAt:`) |
| `MutableObject(name)`, `.name`, `.get(tr)`, `.set(tr, v)` | `PBMutableObject name: 'customer:acme'`, `name`, `get: tr`, `set: tr value: v` |
| `DBObject.with_(**changes)`, `has_defined_attr(n)`, attribute read | `with: 'field' value: v`, `withAll: { 'a' -> 1. 'b' -> 2 }`, `hasDefinedAttr:`, `at:` (absent: `nil`) |
| `Application(**attrs)` (construction) | `Invoice withAll: { 'number' -> 1043. ... }` |
| `List.get_at(i)`, `set_at(i, v)`, `insert_at(i, v)`, `remove_at(i)` | `getAt:`, `setAt:value:`, `insertAt:value:`, `removeAt:` |
| `List.append_first(v)`, `append_last(v)`, `extend(items)`, `slice(a, b)`, `head(n)`, `tail(n)` | `appendFirst:`, `appendLast:`, `extend:`, `sliceFrom:to:`, `head:`, `tail:` |
| `Dictionary`/`HashDictionary` `.get_at(k, default)`, `has(k)`, `set_at(k, v)`, `remove_at(k)`, `keys()`, `values()`, `items()` | `getAt:`, `getAt:default:`, `has:`, `setAt:value:`, `removeAt:`, `keys`, `values`, `items` |
| `Set.add(e)`, `remove(e)`, `has(e)`, `union`, `intersection`, `difference` | `add:`, `remove:`, `has:`, `union:`, `intersection:`, `difference:` |
| `CountedSet.add(e)`, `remove(e)`, `count_of(e)` | `add:`, `remove:`, `countOf:` |
| `RepeatedKeysDictionary.get_at(k)`, `has(k)`, `keys()`, `items()` | `getAt:`, `has:`, `keys`, `items` |
| `IndexedCollection.index_names()`, `get_index(n)` | `indexNames`, `getIndex:` |
| `count` (a persisted field) | `count`; `size` as the Smalltalk synonym |
| iteration (`for x in coll`) | `do:`; `keysAndValuesDo:` on the dictionaries |

- **Zero-based indexes.** `List` positions are 0-based in ProtoBase, and in protoBaseST they
  are too, because the name is ProtoBase's and the persisted `PosNode` counts are the same.
  Smalltalk collections are 1-based. This is noted in the class comment and in the talk.
- **Units.** Timeouts and backoffs are SmallInteger milliseconds, the protoST convention of
  STATUS D48, not Python's float seconds.
- **No `asOf:`.** ProtoBase has none. As-of is the three-line helper of the ERP tutorial,
  which is shown in §6.5.

### 5.3 Note for the maintainer: three names that clash with Pharo's meaning

These are kept as decided. They are listed so that the decision is made knowingly.

| Name | Pharo meaning | ProtoBase/protoBaseST meaning | The risk | Alternative, if ever wanted |
|---|---|---|---|---|
| `Set >> add:`, `CountedSet >> add:` | adds in place and answers the **element** | answers a **new set** | `s add: 3.` with the result discarded changes nothing, and nothing fails | `copyWith:` (Pharo's own non-mutating name, same meaning for `Set`) |
| `Set >> remove:`, `CountedSet >> remove:` | removes in place and answers the element; signals when absent | answers a new set; an absent element is a no-op | the same discarded result | `copyWithout:` for `Set`; no Pharo name for one occurrence of a `CountedSet` |
| `List >> removeAt:` (and `Dictionary >> removeAt:`) | `OrderedCollection >> removeAt:` removes in place and answers the element | answers a new list | the same | `copyWithoutIndex:` (Pharo) for `List` |

Mitigation inside the decided names: the class comments and the talk state the rule
"every collection message answers a new version". A later protoST lint could warn on a
discarded result of these messages. That is a protoST tool question, not part of this
prototype.

## 6. Using it: examples

The module is `protobase`. Every example is a protoST script.

### 6.1 Opening a space and its databases

```smalltalk
Import from: 'protobase'.
PBObjectSpace registerAtomClass: Invoice.
PBObjectSpace registerAtomClass: Customer.

space := PBObjectSpace storage: (PBFileStorage path: '/srv/erp').
space listDatabases.                          "=> #('erp')"
db := space openDatabase: 'erp'.
"or, the first time: db := space newDatabase: 'erp'."
space close.
```

`PBFileStorage path:` creates the directory if needed; the first commit writes `space.root`.
It refuses a directory with a `cluster/` subdirectory, or whose `SpaceRoot` carries a
`cluster_term` (spec §"A minimal external writer", step 6).

### 6.2 Reading and writing in a transaction

```smalltalk
db newTransactionDo: [:tr |
    | invoices inv |
    invoices := tr getRootObject: 'invoices'.          "recorded in the read set"
    inv := Invoice withAll: {
        'number'   -> 1043.
        'customer' -> (PBMutableObject name: 'customer:acme').
        'total'    -> (Decimal fromString: '1250.00') }.
    tr setRootObject: 'invoices' value: (invoices setAt: 1043 value: inv)].
```

As in Python's `with db.new_transaction() as tr:`, the block form commits when the block
ends and aborts if it raises; the exception then propagates. There is **no retry**. A
concurrent change to `invoices` makes `commit` signal `PBConflictError`, because the root was
read.

The explicit form is ProtoBase's:

```smalltalk
tr := db newTransaction.
(tr getRootObject: 'invoices') size printNl.
tr abort.
```

### 6.3 Retries, as `Database.run`

```smalltalk
db run: [:tr |
    | hits |
    hits := tr getRootObject: 'hits'.
    tr setRootObject: 'hits' value: hits + 1].
```

`run:` mirrors `Database.run`:
- it runs the block in a fresh transaction and commits it;
- on `PBConflictError` it aborts and retries with a fresh transaction, up to `retries`
  (default 10), with ProtoBase's bounded exponential backoff with jitter (`Future after:`,
  never a blocked worker);
- any other exception aborts and propagates. `PBOutcomeUnknownError` is never retried,
  because the commit may have been applied;
- the block may therefore run more than once, so it must be free of outside side effects.

### 6.4 Blind writes merge, as in ProtoBase

```smalltalk
"Two processes add different keys to 'tags' without reading it: both survive."
db newTransactionDo: [:tr |
    tr setRootObject: 'tags' value: ((tr newDictionary) setAt: 'urgent' value: true)].
```

The dictionary is built from empty in this transaction, and the root was not read. So the
commit replays its operations onto the dictionary current at commit time (§7.2). A concurrent
writer of another key does not conflict. `setRootObject:value:replace: true` substitutes the
value instead (last writer wins).

### 6.5 Mutable objects, history and as-of reads

```smalltalk
acme := PBMutableObject name: 'customer:acme'.

db newTransactionDo: [:tr |
    tr newMutable: acme name
       value: (Customer withAll: { 'name' -> 'ACME S.A.'. 'taxId' -> '30-12345678-9' })].

db newTransactionDo: [:tr |
    acme set: tr value: ((acme get: tr) with: 'name' value: 'ACME Argentina S.A.')].

db history.                                   "PBHistoryEntry objects, newest first"

"As of a moment: the ERP tutorial's helper, in Smalltalk."
asOf := [:moment |
    (db history detect: [:entry | entry committedAt <= moment]
        ifNone: [PBUserError signal: 'the database did not exist yet'])
        ifNotNil: [:entry | db snapshotAt: entry]].

((asOf value: beforeWeek) getMutable: 'customer:acme') name.   "the name as it was then"
```

Nothing is ever deleted, so every version stays readable.

## 7. Transactions and concurrency: the same as ProtoBase

This section specifies decision 5. Source: CM §"Snapshot isolation" to §"Free-threading",
and `Transaction._build_root`, `_merged`, `_check_mutables` and `Database.run` at the tag.

### 7.1 The transaction

A `PBTransaction` holds:
- its database;
- its snapshot: the root record (epoch and pointer), the `SpaceRoot` and the
  `DatabaseRoot`, read once when it starts;
- its bookkeeping, the same maps as ProtoBase's:
  - `reads`: root name to token;
  - `writes`: root name to a value or *removed*;
  - `replaced`: root names written with `replace: true`, or removed;
  - `mreads`: cell name to token;
  - `mwrites`: cell name to a value or *removed*;
  - `mexpected`: cells set blindly, which must still exist at commit;
- its state: active, committing, committed or aborted. After commit or abort, every message
  signals `PBUserError`.

The bookkeeping is one immutable record held in an **`Atom`**, updated with `swap:`. That
replaces ProtoBase's `RLock`: a transaction is meant for one thread at a time, and if it is
misused from two actors, each call still happens entirely before or after the others. The
protoST layer has no lock.

The rules are ProtoBase's, one for one:
- **Snapshot reads.** `getRootObject:` answers the transaction's own write if there is one.
  Otherwise it reads the snapshot and records `(name, token)` on the first read. Absence is a
  token too. `rootNames` records nothing.
- **Tokens.** An atom's token is its storage pointer; a plain value's token is its exact token
  (§6.1). So `1` becoming `1.0` is a change, and `Decimal 1` becoming `Decimal 1.00` is one
  too.
- **Writes.** `setRootObject:value:` canonicalises the value at once. With `replace: true`,
  or after `removeRootObject:` of the same name, the name is marked replaced for the rest of
  the transaction. A root name starting with `__` is refused (`PBValidationError`).
- **Mutable cells** (D35):
  - reads record tokens in their own namespace;
  - `newMutable:value:` requires the cell to be absent in the transaction's view, and records
    that absence;
  - `setMutable:value:` requires the cell to exist; a blind set adds the name to `mexpected`;
  - `removeMutable:` requires the cell to exist; a blind removal of a cell that was removed
    meanwhile is a no-op;
  - cells are never merged.

### 7.2 Operation logs (what makes a merge possible)

`PBDictionary`, `PBHashDictionary`, `PBSet` and `PBCountedSet` are ProtoBase's
`ConcurrentOptimized` collections. Each version carries two runtime-only fields, never
persisted:
- the **operation log**: an immutable `PBFrozenList` of intents, such as `('set' key value)`,
  `('remove' key)`, `('add' element)`, and for a counted set `('transform' element removes
  adds)`. Every mutator logs its intent, including one that changes nothing (a blind write),
  and answers a new version carrying the longer log;
- **log is complete**: true for a collection built empty in this process (`tr newDictionary`,
  `PBDictionary new`) and for versions derived from it only through logged mutators. False
  for loaded, bulk-built and rebased versions, and for everything derived from them.

**D33, a log is replayed once.** ProtoBase marks a committed value's log incomplete after the
commit (`object.__setattr__`), so that reusing the value in a later transaction replaces
instead of replaying the same operations twice. protoBaseST gives each version a *consumed*
cell, an `Atom` holding `false`. The publisher sets it to `true` on every value it committed.
A version derived later reads its parent's cell at derivation time, as Python copies
`_log_complete` in `_with`. The outcome is the same: a version derived from a committed value
has an incomplete log, and an earlier sibling keeps its own.

`rebaseOnto: current` is ProtoBase's `rebase_onto`. It reduces the log to its **net effect**:
- the last intent per key, compared by order key, in order of last occurrence;
- for `PBCountedSet`, the composed counter transform per element (D26):
  `c -> max(c - removes, 0) + adds`.

It then replays the net effect onto `current` through the public mutators. Index-definition
operations never occur, because the prototype does not add indexes.

### 7.3 The publisher actor and the commit

The space has **one actor per process**, the publisher. It owns the segment and the publish
protocol, and it never runs application code. `tr commit` sends the transaction to the
publisher and waits on the Future; inside an actor the wait suspends that actor (D37). The
publisher handles one commit at a time. That is ProtoBase's protocol with a group of one,
since group commit (D52) is implementation-specific and excluded.

For each commit, the publisher:

1. **Takes the root lock.** `tryLock` on `space.lock`, retried with `Future after:` until
   `lockTimeout`; when the lock cannot be taken in time it signals `PBTimeoutError`. (Python
   takes the lock before building the root, under `_commit_root`, and the publisher does the
   same.)
2. **Reads `space.root`** and checks its CRC, fields and version. A version it does not know
   is an error, never a reason to overwrite.
3. **Validates.** If the root's pointer is the transaction's snapshot pointer, nothing
   changed. Otherwise it loads the current `SpaceRoot` and this database's `DatabaseRoot`
   (`PBConflictError` if the database no longer exists). It then compares every `reads`
   token with the current `objects` value, and every `mreads` token with the current
   `mutables` value. Every name in `mexpected` must still exist. Any difference is
   `PBConflictError`, and nothing is published. The check is **per root and per cell**: what
   happens inside a collection is covered by the root that holds it.
4. **Merges and builds** (`_build_root`), starting from the *current* `objects`:
   - a *removed* write removes the name if it is present;
   - a written name that was neither read nor replaced is merged by `_merged`: when the
     written value is a `ConcurrentOptimized` collection with a complete log, and the current
     value exists and has the same class, it stores `written rebaseOnto: current`. In every
     other case the written value replaces the current one (last writer wins). That covers
     integers, strings, records, lists, and any collection with an incomplete log;
   - a written name that was read or replaced is stored as written: it was validated in
     step 3;
   - `mwrites` are applied to the current `mutables`, a *removed* cell removed if present;
   - a new `DatabaseRoot`: `version` + 1, `previous` the current one, `origin` carried,
     `committed_at = max(now, previous committed_at)` in UTC, so that history times never go
     back;
   - a new `databases` dictionary and a new `SpaceRoot`.
   A conflict raised by a replay is a conflict like any other.
5. **Saves** the new atoms children first into its segment, then flushes and `sync`s it. A
   new segment is created `#create #exclusive` under a fresh UUID4 name, and the directory is
   `syncDirectory:`'d once after creating it.
6. **Publishes.** It checks that the space belongs to no cluster, then writes
   `space.root.tmp` with `epoch` + 1, `sync`s it, `replace:with:` over `space.root`, and
   `syncDirectory:`. It then releases the lock, best effort: a failure there is logged, never
   raised.
7. **After success** it sets the *consumed* cell of every written collection (§7.2).
   ProtoBase keeps a last-known root only in a cluster: there, the coordinator's committed
   root may be ahead of the persisted one, and `committed_epoch` reads it. Outside a cluster,
   `committed_epoch` reads the storage's root. This prototype runs one process per space
   without a cluster, so it keeps no last-known root: nothing would read it (ruling N2, Task 18
   review).
8. **When publishing fails**, the outcome may be unknown. Because the root lock excludes every
   writer, the publisher re-reads `space.root`. If the root is its own, the commit succeeded.
   If it can prove the root is not its own, the commit failed and nothing was published.
   Otherwise it signals `PBOutcomeUnknownError`, an honest "I do not know", never a guess
   (P5).

Python processes sharing the directory run the same protocol under the same lock. A commit
by either language is validated against the newest root at the moment it is built. That is
what makes the round trip transactional and not only a file exchange.

### 7.4 What is in scope for 2026-12-03

| Rule | Scope |
|---|---|
| Snapshot isolation; per-root and per-cell read sets with exact tokens and absence tokens | **In** |
| Replace rules (`replace: true`, removal then set, read roots), last writer wins for non-mergeable values | **In** |
| Net-effect replay for `PBDictionary`, `PBHashDictionary`, `PBSet` | **In** |
| D33 consumed marks | **In** |
| Mutable-cell rules (new, blind set, blind remove) | **In** |
| `run:` with retries and backoff; `PBOutcomeUnknownError` resolution by re-reading the root | **In** |
| `PBCountedSet` writes and the counter-transform merge (D26) | **Stretch**, cut first (§10) |
| `RepeatedKeysDictionary` writes and merges; index-definition merges | **Out** |
| A merge onto a current value that has indexes | **Out, and refused.** ProtoBase replays through mutators that maintain the current value's indexes. protoBaseST cannot maintain indexes, so it signals `PBNotSupportedError`. Replacing instead would silently diverge from ProtoBase |
| Group commit (D52), cluster leases | **Out** (implementation-specific, or outside acceptance) |

The rule behind the table: protoBaseST either does what ProtoBase does, or refuses with an
explicit error. It never does something else under the same name.

## 8. Layering and where the code lives

### 8.1 Layers

From the bottom up. Each layer depends only on the layers below it.

| # | Layer | Contents | Lives in |
|---|---|---|---|
| 0 | primitives | `ByteArray`, `BinaryFile`, digests, `MessagePack`, timers; **new**: OS random bytes, a microsecond UTC clock | protoIO + protoST |
| 1 | general values | `Decimal`, `CalendarDate`, `TimeOfDay`, `DateTime`, `TimeSpan`, `ZoneOffset`, `UUID` | protoST `lib/` |
| 2 | codec | canonical encode and decode with every refusal; `PBFrozenList`, `PBTuple`, `PBFrozenDict`, `PBMissing`; order keys, hash keys, exact tokens | protoBaseST |
| 3 | framing | segment header, record header, root record, atom envelope, type tags (built-in aliases, application names and aliases, opaque atoms), the class registry | protoBaseST |
| 4 | object store | `PBFileStorage`: segment reader, owned segment writer, root reading, publish | protoBaseST |
| 5 | structures | AVL `KeyNode`, `PosNode`, `CountedKeyNode`, `ValueBox`; the collections with their operation logs; `IndexSet`; records; opaque atoms; indexes decoded | protoBaseST |
| 6 | transactions | `PBObjectSpace` and its publisher actor, `PBDatabase`, `PBTransaction`, `PBSnapshot`, `PBHistoryEntry`, `PBMutableObject`; `SpaceRoot` and `DatabaseRoot` | protoBaseST |

**Codec (layer 2).**
- Decoding goes through `MessagePack decodeOrdered:`, which keeps wire order. The codec then
  checks what the format adds to msgpack:
  - every envelope and state-map key is a `str`; a `bin` key is `PBCorruptionError`;
  - an ext value is refused;
  - every tagged map has exactly one key;
  - `@int`, `@dec`, `@td` and the date and time fields have their one spelling.
- Encoding writes the smallest msgpack forms, and maps always as `MessagePackMap`.
- **Order keys** are `(rank, payload)` values. Numbers compare through exact fractions:
  `Float >> asExactFraction`, and a decimal as coefficient × 10^exponent.
- **Hash keys** are `blake2b: 8` over `feed(rank, payload)`, read as a signed little-endian
  int64. Residues modulo 2^61 - 1 use square-and-multiply in Smalltalk, and the bit length is
  `abs highBit`, as the spec's `highBit` warning requires.
- **Exact tokens** are the canonical encoding with every atom written as `{"@ref": nil}`.
- A wrong hash shows up as a missing key, not as a crash. The hash and token vectors gate
  every change to this layer.

**Structures (layer 5).**
- A reference decodes to an unloaded atom (a pointer plus its storage) that loads its record
  when a message needs its state. The loaded state is memoised in an `Atom`. Two concurrent
  loads give equal values, so the race is harmless. This is ProtoBase's lazy loading, which
  the spec calls implementation-specific.
- New versions are built in memory by path copying. AVL insert and remove keep the invariants
  of spec §"AVL nodes": height, count, balance, key order and `weight`.
- Oids:
  - a record draws its oid when it is constructed, because its equality and hash follow the
    oid (D10);
  - a tree node draws its oid when the publisher saves it.
- Node values that are strings of 256 or more code points, or byte strings of 256 or more
  bytes, are boxed in a `ValueBox`.
- New collections get an empty `IndexSet`. Collections with indexes refuse every change.
- `PBOpaqueAtom` answers `typeName`, `at:` and `attributeNames`. Any other message, any
  change, and any use as a collection signal `PBNotSupportedError` naming the type. The
  writer never writes a record for an opaque atom; it may reference one.
- In state maps, built-in types write their attributes in the vectors' order.

### 8.2 Where the code lives (decision 1)

A new repository, `protoBaseST`, a sibling of protoST and protoIO:

```
protoBaseST/
  src/protobase.st          the module an application imports
  src/protobase/*.st        codec, framing, store, structures, transactions
  tests/conformance/        the vector runner (pinned by digest)
  tests/interop/            Python scripts for the round trips (pinned ProtoBase venv)
  tests/unit/               protoST tests, one behaviour each
  examples/erp/             the demo, both languages
  docs/                     README, the API mapping of §5, deviations
```

The general-purpose values of layer 1 go into protoST's `lib/`, with LANGUAGE.md sections and
STATUS deviations.

## 9. Missing primitives and where each goes

| Need | Why | Where | When |
|---|---|---|---|
| OS random bytes, `ByteArray randomBytes: n` | oids, segment UUID4 names, `origin`. `Random` is a 32-bit Park-Miller generator, unfit for identities | protoIO `random::bytes(n)` (`getrandom`; `BCryptGenRandom` on Windows), bound by protoST | **Approved** for protoIO 0.5.0 / protoST 0.10.0 (ruling R10), weeks 0-1, once the protoPython release frees DEV12 |
| A UTC clock in microseconds | `committed_at` | protoIO `clock::utcMicroseconds()` plus a protoST binding | **Approved**, same release |
| `Decimal` | `@dec`; rank-3 order and hash | protoST `lib/decimal.st`, Smalltalk over `LargeInteger`: parse, to-scientific-string, exact comparison, special values; no arithmetic context yet | Week 1, Smalltalk only |
| Calendar values and fixed offsets | `@date`, `@time`, `@dt`, `@td` | protoST `lib/calendar.st`, Smalltalk | Week 1 |
| `UUID` | `@uuid`, oids, names | protoST `lib/` | Week 1 |
| Modular exponentiation, bit length | hash residues | Smalltalk; a protoCore integer primitive only if a measurement demands it | — |
| IANA tz database | wall clocks, format-3 zone datetimes | protoIO (a TZif reader), later | Excluded |
| Correctly rounded sum | vector scores | later | Excluded |

The str-only map keys and the ext refusal need no primitive; they are codec checks in
Smalltalk. Week 0 verifies three claims against a **running** protoST 0.9.0 (the installed
0.9.0 packages; no build):
- `MessagePack encode:` writes `uint 64` for 2^63..2^64-1 and always writes floats as
  `float 64`;
- `lib/json.st` loads `manifest.json`;
- `tryLock` excludes a Python `OwnerLock`.

No stopgap random source is adopted: reading `/dev/urandom` through `BinaryFile` is
unverified, and it would be debt.

## 10. Test strategy

All tests are deterministic. No test sleeps or races a clock. Interleavings are driven step
by step by the test script.

**10.1 Conformance vectors (pinned).** The runner first checks the SHA-256 of
`vectors.sha256` (`5f86eb09…406df0`) and refuses to run on any other value.

| Manifest section | Gate |
|---|---|
| `values` | decode to the described value; re-encode to the same bytes |
| `values_decode_only`, `values_read_not_rewritten` | legacy forms decode; they re-encode canonically, or are refused |
| `invalid` | refused at their layer with the listed error class (value, atom, record, segment, root); the log and message layers are skipped visibly |
| `order`, `hashes`, `exact_tokens`, `atom_hashes`, `atom_tokens` | exact equality |
| `framing` | decode to the fields; re-encode to the same bytes |
| `database` | every record at its offset; the contents in the manifest notation |
| `legacy_database` | read; the format-3 zone datetimes are read as `PBLegacyZoneDateTime` (§4.3), and whatever needs their offsets is refused as *expected entries* listed in the runner; index rebuild and misfiled detection are skipped visibly |
| `polyglot_database` | the opaque record is readable, and is kept byte for byte after the record that references it is changed and committed |
| `cluster` | skipped visibly (`SKIP:`) |

**10.2 Python to protoST.** A pinned-venv Python script writes a space through ProtoBase's
API:
- every non-indexed collection, `DBObject`, `demo.erp.Invoice`, a mutable cell;
- three versions;
- an indexed collection;
- a type only Python knows (`demo.erp.AuditNote`).

`verify --out` dumps the space; protoBaseST dumps it in the same notation. The two must be
equal.

**10.3 protoST to Python.** A protoST script writes the same shapes through protoBaseST. Then
`python -m proto_db.tools.verify <dir> --out` must exit 0, and its JSON must equal
protoBaseST's own dump.

**10.4 Concurrency: the same outcomes as ProtoBase.** Each case runs twice:
1. both transactions in Python, to record ProtoBase's outcome;
2. one transaction in protoST and one in Python, interleaved at the same points (start A,
   start B, commit B, commit A).

The two outcomes must be identical: which commit conflicts, and the final contents.

| Case | Expected (ProtoBase) |
|---|---|
| Both read and write one root | the second commit: `PBConflictError` |
| Each writes a different root | both commit |
| Blind writes of different keys to one `Dictionary` root, each built empty | both commit; both keys present (merge) |
| Blind writes of the same key | both commit; the later commit's value wins |
| Blind write with `replace: true` | the later value replaces; the other key is lost |
| A blind write of a `List` | last writer wins |
| A blind `Set` add and a concurrent remove of the same element | the net intent, in commit order |
| A read of an absent root while the other creates it | conflict |
| Two `newMutable:` of one name | conflict |
| A blind `setMutable:` of a cell the other removed | conflict |
| A blind `removeMutable:` of a cell already removed | both commit (no-op) |
| A collection committed, then reused in a later blind write (D33) | replaces; it does not replay twice |
| A blind write onto a root whose current value has indexes | ProtoBase merges; protoBaseST signals `PBNotSupportedError` (the documented refusal) |

Within one process, the same table runs with two protoST actors.

**10.5 Refusals.** One test each:
- a `Symbol` value, a `Fraction`, a `Dictionary` used as a value, a NaN key;
- a change to an indexed collection, a change to an opaque atom;
- a zoned datetime built from a wall clock;
- a `cluster/` directory, a `__` root name.

**10.6 Structures.** Seeded random operation sequences (fixed and recorded seeds) on every
writable collection. After each commit a local invariant check runs, and at the end
`verify` runs over the whole space.

**10.7 The lock.** A Python helper takes `space.lock` and holds it until its stdin closes.
The protoST commit must end in `PBTimeoutError`; that outcome does not depend on durations.

**10.8 The ERP demo** (`examples/erp/`), also run as a test:
1. Python creates customers and invoices.
2. protoST records payments as new versions with `with:value:`, and renames a customer
   through its mutable object.
3. Both languages tag invoices concurrently, as blind dictionary writes, and both tags
   survive.
4. Both print the same as-of report for three moments.

The demo uses tens of records. No benchmark is shown, since neither side has been measured at
the scale this audience knows.

## 11. Plan (revised)

The work starts once the ProtoBase agent finishes; the format is frozen at `v2.0.0rc1`. The
primitives release waits for the protoPython release to free DEV12. Decision 5 adds about
four days: the transaction bookkeeping, operation logs and replay, validation, outcome
resolution, and the concurrency tests. Three weeks do not hold everything, so the plan moves
work out explicitly.

| Week | Dates | Work | Gate |
|---|---|---|---|
| 0 | 11-11 to 11-14 | `protoBaseST` skeleton; pinned Python venv; the three checks of §9 on the installed 0.9.0; protoIO `random::bytes` and the µs clock written, released as protoIO 0.5.0 / protoST 0.10.0 (ruling R10) when DEV12 is free | the checks pass; the release is scheduled |
| 1 | 11-12 to 11-18 | `Decimal`, calendar values and `UUID` in protoST `lib/`; codec with every refusal; framing for formats 2-4; vector runner and notation printer | `values`, `values_*`, `invalid` (storage layers), `framing` |
| 2 | 11-19 to 11-25 | order keys, hash keys, exact tokens; lazy loading; read path for every collection, records, opaque atoms; `history`, `snapshotAt:`, `getMutable:`; `PBTransaction` read side (snapshot, tokens, read sets) | `order`, `hashes`, `exact_tokens`, `atom_*`, `database`, `legacy_database` (with listed refusals), `polyglot_database` read; test 10.2 |
| 3 | 11-26 to 12-01 | AVL writes; `PBList`, `PBDictionary`, `PBHashDictionary`, `PBSet`, records and mutable cells with their operation logs; the publisher (lock, validation, merge, save, publish, outcome); `run:` | tests 10.3, 10.4, 10.5, 10.7; the polyglot byte-for-byte check |
| — | 12-02 | ERP demo; README with the API mapping; the "what is not done" slide | 10.8 runs from a clean checkout |

**Moved out of the 12-03 scope in this revision:**
- index queries (the `lookup:` and range path of revision 1). Indexes are still decoded,
  kept and verified;
- `PBCountedSet` writes and its counter-transform merge, now a stretch goal.

**Cut order, if week 3 slips:**
1. `PBCountedSet` (already a stretch goal).
2. `PBHashDictionary` and `PBSet` **writes**. Their blind merges go out with them; they stay
   readable.
3. Nothing further. The minimum shown is `PBList`, `PBDictionary` with its merge, records,
   mutable cells, and the full validation.

A blind write is never shipped without its merge: that would replace where ProtoBase merges.

## 12. Risks

1. **Week 3 is overloaded.** The writer and the transaction semantics are about eight days of
   work in six. *Mitigation*: the cut order above, decided now, so that the demo is never
   built on a half-implemented rule. *Residual risk*: if `PBDictionary`'s merge is not
   correct by 11-30, the demo shows the read side and the validation only, and says so.
2. **DEV12 availability.** If the protoPython release does not free DEV12 by about 11-24, the
   writer has no fit source for oids. *Mitigation*: the reader (weeks 1-2) does not depend
   on it. *Residual risk*: a late release cuts week 3.
3. **Numeric exactness.** Cross-kind equality, hash residues and tokens: wrong values look
   like missing keys, and with merges they look like lost updates. *Mitigation*: the vectors
   gate every change, and the concurrency tests compare against ProtoBase run by itself.
4. **Speed.** The interpreter is 2-12x slower than CPython; `LargeInteger` modular arithmetic
   runs for every hashed key; large collections cost n log n cells. *Mitigation*: demo scale
   only, no numbers on slides.
5. **protoST defects found on the way.** This is the first large library written in protoST.
   *Mitigation*: each defect goes to protoST's `KNOWN_ISSUES.md` and is fixed there, never
   worked around in protoBaseST.
6. **Immutability by convention** (decision 3). An application subclass could assign an
   instance variable of a record. *Mitigation*: documented; a test checks that the library's
   own classes never assign after construction.
7. **Name clashes with Pharo** (§5.3). `add:`, `remove:` and `removeAt:` with a discarded
   result do nothing, silently. *Mitigation*: documented in the class comments and the talk.
8. **Format movement after rc1.** *Mitigation*: everything is pinned to the tag and the
   digest; a re-sync is a deliberate step.

## 13. Remaining points for the maintainer

The six questions of revision 1 are decided. What is left to confirm:

1. **The cut order of §11 and the residual risk 12.1.** Is the fallback acceptable: no
   merges beyond `PBDictionary`'s if week 3 slips, or in the worst case a demo of the read
   side plus validation?
2. **The three Pharo clashes of §5.3.** They are kept as decided; the note is there so that
   the choice is made knowingly.
3. **Zero-based `PBList` indexes** (§5.2), kept because the name and the persisted counts
   are ProtoBase's. Confirm, since every Smalltalk collection is 1-based.
