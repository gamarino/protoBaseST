# Deviations and refusals

Where protoBaseST differs from ProtoBase (`proto_db` at `v2.0.0rc2`), and everything it refuses.
The rule behind the whole list is the design spec's: **refuse, never diverge**. A value, type,
version or operation the prototype cannot handle exactly signals an explicit error naming it. It
never stores something else in its place, and it never replaces where ProtoBase would merge.

Each entry says what differs, why, and what it costs. "Refusal" means an error; "divergence"
means a visible difference in behaviour that is not an error.

Contents:
[Names that mean something else](#names-that-mean-something-else) |
[Values refused when written](#values-refused-when-written) |
[Time and time zones](#time-and-time-zones) |
[Collections and records](#collections-and-records) |
[Transactions and storage](#transactions-and-storage) |
[Shapes protoBaseST cannot write](#shapes-protobasest-cannot-write) |
[Reading](#reading) |
[Conformance vectors](#conformance-vectors) |
[Errors and messages](#errors-and-messages) |
[Performance](#performance) |
[Known protoST limits](#known-protost-limits)

## Names that mean something else

| What | Divergence | Why | Cost |
|---|---|---|---|
| `Set >> add:`, `Set >> remove:`, `List >> removeAt:` (and `Dictionary >> removeAt:`) | They answer a **new version**; Pharo's change the receiver in place and answer the element. | ProtoBase's names are the documented API of the Python implementation, and one document should explain both languages (design spec 5.3). | `s add: 3.` with the result discarded changes nothing and nothing fails. Alternatives, if ever wanted: `copyWith:`, `copyWithout:`, `copyWithoutIndex:`. A protoST lint could warn on a discarded result; that is outside this prototype. |
| `PBList` positions | **Zero-based**, a negative one counts from the end. | The name is ProtoBase's and the persisted `PosNode` counts are the same in both languages. | Smalltalk programmers expect 1. Every other collection a program builds (`Array`, `PBTuple`, `PBFrozenList`) stays 1-based. |
| `Dictionary` iteration | A `PBDictionary` iterates in key order, a `PBHashDictionary` in hash order. | The format's order. | Insertion order is not kept; `PBFrozenDict` keeps it. |
| Timeouts and backoffs | SmallInteger **milliseconds**, where Python uses float seconds (`lockTimeout`, `run:retries:backoff:`). | The protoST convention (STATUS D48). | A rounded delay: the jitter is rounded to whole milliseconds and never above the bound. |
| Class names in some error texts | `PBList element`, `PBSet element` where ProtoBase says `List element`, `Set element`. | They are protoST's class names. | None; the tests pin both sides. |
| No `asOf:` | None. | ProtoBase has none. As-of is a three-line helper (tutorial, section 12). | The helper is a block in a script. |

## Values refused when written

All are `PBValidationError`, raised by the call that receives the value, naming the class.

| Value | Why it is refused | What to do |
|---|---|---|
| A `Symbol` longer than six bytes (decision 2; format 4 has no symbol kind) | A symbol stored as a string would come back as a string; the value would change kind. | Store a `String`. When `@sym` lands (format 5), protoST gets an explicit wrapper. |
| A short `Symbol`, such as `#paid` | **Not refused**, because in protoST it *is* the `String` `'paid'` (STATUS D35). It is stored as a string. | Nothing depends on telling them apart. |
| A protoST `Dictionary` | Its order is unspecified and the order of a map is part of its bytes. | `PBFrozenDict`, or a `PBDictionary`. |
| `Fraction`, `Character`, `Set`, `Bag`, `Interval`, a block, any other object | They have no kind in the format. Storing them under another kind would be a lie. | Convert explicitly. |
| A string with a lone surrogate | It has no UTF-8 encoding. | |
| A list, a map, a NaN as a key or set element | Not orderable (as in Python). | `PBTuple`. |
| A value nested deeper than 1022 msgpack containers (`PBCodec maxValueDepth`) | The normative limit of `v2.0.0rc2`. Reading deeper data is `PBCorruptionError`. | |
| A root name starting with `__` | Reserved for the format. | |
| An attribute name starting with `_`, or `oid`, `atom_pointer`, `context`, `with_`, `has_defined_attr`, or a name the class reserves | The format's rule for records. | |
| A `PBSet` element nested past 1020, a `PBHashDictionary` key or value past 1018 | The bucket tuple around it adds containers; refused when the mutator is called. | |
| A slice bound that is not an Integer or `nil` (including `true`) | Python's `slice.indices` takes `True` as 1; in Smalltalk a Boolean is not a number, and ProtoBase's own positions refuse `bool`. `tests/unit/list_positions.st` records ProtoBase's answers next to this one's. | |
| `PBList extend:` of a `String` | Python's `extend("abc")` appends three one-character strings; in Smalltalk a String's elements are Characters, which no format stores. | `appendLast:` for one string value. |

Host subclasses of a mapped class are stored as their base value, as the format spec says.

## Time and time zones

protoST has no IANA time-zone database. Everything below follows from that, and each case is
explicit.

- **Wall clock of a zoned instant (call C7).** The calendar classes signal protoST's own
  `TimeZoneUnavailable` (an `Error`, in protoST's `lib/calendar.st`) when asked for the wall clock
  of an instant-zone `DateTime`, and when asked to build a named-zone `DateTime` from a wall
  clock. They live in protoST `lib/`, which cannot depend on protoBaseST, so this is not
  `PBNotSupportedError`. protoBaseST's own refusals of the same family are `PBNotSupportedError`.
  *Cost:* store a UTC or fixed-offset datetime, or a naive datetime plus the zone's name.
- **A format-4 `["instant", key]` datetime** is read as its UTC instant plus the zone key. It
  orders, hashes, tokenizes and re-encodes exactly. Its wall clock is not available.
- **Instants near the ends of the calendar.** Reading presents the instant in UTC even if its
  wall clock in the zone might fall outside years 1 to 9999. Writing an instant within one day of
  year 1 or year 9999 is `PBNotSupportedError`, because ProtoBase refuses to read such a value
  back. *Cost:* a `datetime.max`-style sentinel in an IANA zone cannot be written from protoST; an
  atom that holds one, written by ProtoBase, can be read but not re-written by protoBaseST.
- **A format-3 `["zone", key]` datetime** (legacy data) is read lazily as a `PBLegacyZoneDateTime`
  (`isLegacyZone` true). Its wall clock and fold are kept. It is never given an offset; every use
  that needs one (hash, order, UTC instant, comparison with an aware value more than the window
  apart, a map with two keys that could conflict) is `PBNotSupportedError` naming the zone.
  Writing it is `PBValidationError`. *Why lazy:* old atoms whose other attributes are fine stay
  readable, and atoms that are never changed are kept byte for byte. ProtoBase would re-encode
  such a value as its instant, which needs a database, so this differs from it on purpose
  (see the conformance vectors, below).
- **Zone keys: a pinned list.** A key is valid when it is in `PBZoneKeys`, the Zone and Link
  names of IANA tzdata 2026e (`tools/gen_zone_keys.py`, committed). The same on every machine.
  A key outside the list is `PBCorruptionError` when read and `PBValidationError` when written;
  a key newer than the release is refused until the list is regenerated. *Cost:* ProtoBase checks
  against its host's tz database. On a host that lacks the backward-link names
  (a host without `tzdata-legacy`; `US/Eastern` is one), ProtoBase refuses those pinned keys. protoBaseST neither refuses nor
  rewrites such keys, because refusing them on write would make it unable to re-save an atom that
  ProtoBase wrote legitimately. Cross-implementation tests use canonical Zone names only.
- **`["zone", key]` inside a `@time`** is a wall clock without a date, fully supported.
- **`TimeSpan`** counts microseconds (protoST's kernel `Duration` counts milliseconds).

## Collections and records

- **Indexed collections are not written or merged.** A collection that has an index (a
  `PBEqualityIndex`, `PBRangeIndex` or `PBVectorIndex`) refuses every change with
  `PBNotSupportedError` naming its indexes, and so does a merge onto one (design spec 7.4).
  ProtoBase updates the indexes in the same step and merges blind writes onto them; protoBaseST
  cannot do either, so it does not do a lesser version. Index *queries* are not provided either:
  indexes are decoded and kept. `extend:` of nothing still answers the receiver, as ProtoBase's.
  *Cost:* a database that uses indexes can be read and its non-indexed parts changed; the indexed
  collections cannot be changed from protoST.
- **`PBRepeatedKeysDictionary` is read only.** Its writes and merges are a non-goal. A new empty
  one is mergeable and its rebase answers `current` unchanged, as ProtoBase's.
- **Immutability is by convention** (decision 3). No instance is frozen at run time: a method
  that assigns an instance variable after construction would compile. A test
  (`tests/unit/values_immutable.st`) scans for it. Two runtime-only fields are exceptions, both
  `Atom` cells and neither persisted: the memo of a lazy load and the consumed mark of an
  operation log.
- **Application records.** Accessors only answer the stored value (decision A4). A behaviour name
  that is also a stored attribute, in any implementation, is a defect: a record holding a
  reserved name is refused when loaded (`PBCorruptionError`). There are no generated setters.
- **Positional trees are not subclassable**, as in ProtoBase: a `PBPosNode` subclass is refused
  when registered, built or given to a positional operation. A keyed node class may be extended
  with fields, which every write carries into the copies.
- **Self-referencing records.** A record whose decoding needs the record itself (a map key that
  refers back to it) is `PBCorruptionError` naming its pointer. ProtoBase recurses until Python's
  `RecursionError`. ProtoBase saves every dependent before the record that refers to it, so such a
  record is damaged data or the work of a writer that breaks that invariant.
- **A mergeable log is a property of the version's history** (ProtoBase D33): a rebased version
  keeps the completeness of the version it was rebased onto, as ProtoBase's code does (the brief
  and ProtoBase's docstring said "not mergeable"; the code is the reference).
- **Counted-set logs** use ProtoBase's op names: `('add' e)`, `('remove' e)` for calls and
  `('transform' e removes adds)` only for a rebase's adjustments.

## Transactions and storage

- **No cluster mode.** A directory with `cluster/`, or whose SpaceRoot carries a `cluster_term`,
  is refused (`PBNotSupportedError`). ProtoBase's "held retries" (an immediate retry without
  backoff, `permit_held`) are therefore not ported. Mixed Python/protoST clusters are outside
  acceptance until a protocol freeze.
- **Framed log files** (the `log` and `roots_log` layers) are not read. ProtoBase reads them only
  in its cluster and tiered storage. The conformance vectors of those layers are visible skips
  (ruling R14). A reader was written and then removed, because an uncalled reader is debt.
- **The caller owns the lock backoff, and it blocks the caller's worker.** The publisher never
  waits (ruling R19): an attempt that finds the root lock held answers at once, and the
  committing caller waits 1 ms, doubling to 50 ms, until `lockTimeout`. That wait sits in a
  `whileFalse:` block, so it blocks the caller's worker thread instead of suspending the actor
  (protoST question K23, open, see below). It is bounded and only happens while
  another *process* holds the lock; while it waits, the worker still serves other actors.
- **Group commit** (ProtoBase D52) is not implemented: every publish is a group of one.
- **One storage failure ends writing through that storage** (`isFailed`), as ProtoBase's; reopen
  the space. Reads keep working.
- **Step 8 of a failed publish.** A root at a different epoch is `PBConflictError`, as
  ProtoBase's `_publish`. A root that reappears at the same epoch, written by a writer that
  ignored the lock, cannot be told from "nothing published"; ProtoBase has the same limit.
- **`newTransactionDo:` commits on a non-local return** (`^`) and aborts exactly when an
  exception unwinds the block (ruling R20b), as Python's `with`. A resumable exception that an
  enclosing handler resumes does not end the block, and the block's writes are committed. This
  needed `Exception >> outer` in protoST.
- **Durability** is always `fsync`; there are no other modes. Windows is untested.
- **A non-aware previous `committedAt`** is `PBCorruptionError` (Python's `max` would raise
  `TypeError`).
- **Origin bytes** of a new database are a version-4 UUID's, as ProtoBase's `uuid4().bytes`.

## Shapes protoBaseST cannot write

The round-trip tests (design spec 10.2) write a space from protoST and have ProtoBase's verifier
accept it. The space cannot contain what protoBaseST cannot write:

- an indexed collection (index maintenance is out of scope, design spec 7.4);
- `PBRepeatedKeysDictionary` writes (a non-goal);
- Python-only types such as `demo.erp.AuditNote`, which protoST reads as opaque atoms and never
  re-writes.

Hence the interop round trip compares dumps with `compare_dumps.py --exact` (no normalisation of
the opaque type), and `tests/interop/concurrency.sh` row 13 (a blind write onto an indexed root)
uses a copy of the conformance database in all four runs and asserts protoBaseST's
`PBNotSupportedError` in place of ProtoBase's merge. Likewise `st_random_ops` covers the four
collections with writes, and `PBCountedSet` since Task 22.

## Reading

- **Opaque atoms.** A record whose type has no registered class is a `PBOpaqueAtom` (D59). It
  answers `typeName`, `tag`, `at:` and `attributeNames`; every other message is
  `PBNotSupportedError` naming the type. A reference to it is written back byte for byte at the
  original pointer; no record of its type is written.
- **Indexes** are decoded and kept (`name`, `keySpec`, `hasMemberTokens`...). Not queried.
- **Format-3 collections** are read; their indexes are not rebuilt, and `validate()` and
  `rebuilt()` of misfiled format-3 collections are not provided.
- **`snapshot_ref` byte references, pagers and residency** are not provided.
- **Symbols and the per-database class registry** (`__currentModules`, `@sym`) are format-5
  features and are outside this prototype. The registry of record classes is process-wide, as
  ProtoBase's.
- **The root record refusal** is ProtoBase's `decode_root` sentence ("Undecodable root record"),
  without protoST's MessagePack detail. ProtoBase keeps that detail only as `__cause__`, and
  protoST has no exception chaining. *Cost:* a corrupt root is harder to diagnose.

## Conformance vectors

The vectors are those of ProtoBase `v2.0.0rc2` (digest recorded in
`tests/conformance/vectors.sha256`). Where protoBaseST differs from the manifest on purpose, the
difference is a tracked table (`tests/conformance/_expected_differences.st`) and the runner fails
if a listed difference goes away or an unlisted one appears. Three remain, all `permanent,
design 4.3` (no time-zone database):

| Section | Id | Difference |
|---|---|---|
| `values_decode_only` | `datetime-zone-format3` | Decodes to a `PBLegacyZoneDateTime` (the wall clock), not the instant; re-encoding it is `PBValidationError`. |
| `values_read_not_rewritten` | `map-zone-key-format3` | Re-encoding is refused, as listed; the decoded keys are format-3 wall clocks, not instants. |
| `invalid` | `value-instant-wall-out-of-range` | **Accepted** and presented in UTC. The wall-clock range needs the zone's rules; the format spec ("Known gaps") lets a reader without a database present the instant in UTC. Refusing would call valid data corrupt. |

The cluster section and the invalid vectors of the `log`, `roots_log` and `message` layers are
visible skips, printed under the `PASS` line of `tests/conformance/cluster.st`.

## Errors and messages

- The error classes mirror `proto_db/errors.py` with `PB` for `Proto`. ProtoBase's extra classes
  that a prototype of this size never raises (`StalePager`, `Misfiled`, `NotAuthorized`,
  `BacklogFull`, `WriteRefused`) are omitted. `PBDBError` has no `code` API yet. `PBReferenceError`
  exists.
- Error texts quote names as Python's `repr` does (`PBCodec repr:`). One known imperfection:
  `repr:` leaves non-printable code points at or above U+0100 unescaped, where Python escapes
  them. It affects error text only.
- `PBTimeoutError` is not protoST's `TimeoutError`.

## Performance

The prototype need not be fast, and it is not. This is the only place in the documentation that
states figures; the other documents link here.

Measured 2026-11-12 on a pre-release build of protoST 0.10.0 (commit `58f1834`) and
protoBaseST commit `1564bce` (the source is unchanged since `5d09adf`), with
`bench/run_avl.sh` (`RUNS=3`), against ProtoBase `v2.0.0rc2`, at a load average of about 3.5, so
the figures are indicative only:

| Operation | Ratio to ProtoBase |
|---|---|
| `posAppend` | 19x |
| `keyPut`, new key / replacing a key | 14x / 17x |
| `posAt` / `keyAt` | 17x / 16x |
| `check:` of a positional / of a keyed tree | 52x / 54x |

So the AVL structures are roughly 14 to 54 times slower; `check:` is the slowest. protoST
interpreter work is ongoing and its branches are not merged yet, so these numbers will move.
Re-run the script on your binary before quoting any of them. No claim of speed is made, nothing
was measured under heavy concurrent load, and the remaining cost is mostly protoST's interpreter
and node building, not the format.

## Known protoST limits

Defects found in protoST while building this were fixed in protoST, with a test, and are recorded
in its issue ledger (K14 class and instance methods sharing a slot, K15 deep nesting, K16
subnormal float literals, K17 JSON `\u` escapes, K20 and others). Four more observations were
filed in protoST as S37 to S40 and are fixed in protoST 0.10.0, the version this repository
requires; one question is still open and one observation was not a bug:

- **protoST S37, fixed in protoST 0.10.0:** the instance variables a class inherits from an
  imported superclass were not declared when a method of a program's main file was compiled, so
  such a method could not reference them. `PBObject` subclasses defined in a script still use
  `at:` accessors, because that is the design, not because of this defect.
- **protoST S38, fixed in protoST 0.10.0:** `Atom on:` ignored the receiver class, and `swap:`
  bypassed an `Atom` subclass's `#value` override, so a test seam could not intercept an `Atom`
  read.
- **protoST S39, fixed in protoST 0.10.0:** `Atom new swap:` spun forever.
- **protoST S40, fixed in protoST 0.10.0:** a silent hang past the helping cap of 16 nested
  `Future` waits. protoST now grows its worker pool and raises `deadlock: too many nested waits`
  only on provable pool-wide quiescence. protoBaseST's design (ruling R19: no waits inside
  actors) never exercised it.
- **K23 (open question for protoST, not yet filed):** an actor that blocks its worker in a
  `Future` wait can raise `deadlock:` while another actor on that worker waits for it. Whether
  the detection is a false positive is not settled. The pattern that raised it here was a
  publisher backing off inside its actor (now removed, ruling R19). What remains is the caller's
  lock backoff, which is bounded and only runs while another process holds the lock; while it
  waits, its worker still serves other actors.
- **Module resolution is documented protoST behaviour, not a bug.** The working directory is
  searched before the library, as in Python, so a stray `calendar.st` in the current directory
  shadows the library's calendar module. **Security note:** an untrusted working directory's
  `.st` files replace library modules of the same name. Run protoBaseST programs and tests from a
  trusted directory.
