# Deviations and refusals

Where protoBaseST differs from `proto_db` at `v2.0.0rc2`, and everything it refuses.
The rule behind the whole list is the design spec's: **refuse, never diverge**. A value, type,
version or operation the prototype cannot handle exactly signals an explicit error naming it. It
never stores something else in its place, and it never replaces where `proto_db` would merge.

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
[Cluster wire messages](#cluster-wire-messages) |
[Cluster mode](#cluster-mode) |
[Errors and messages](#errors-and-messages) |
[Performance](#performance) |
[Known protoST limits](#known-protost-limits)

## Names that mean something else

| What | Divergence | Why | Cost |
|---|---|---|---|
| `Set >> add:`, `Set >> remove:`, `List >> removeAt:` (and `Dictionary >> removeAt:`) | They answer a **new version**; Pharo's change the receiver in place and answer the element. | `proto_db`'s names are the documented API of the Python implementation, and one document should explain both languages (design spec 5.3). | `s add: 3.` with the result discarded changes nothing and nothing fails. Alternatives, if ever wanted: `copyWith:`, `copyWithout:`, `copyWithoutIndex:`. A protoST lint could warn on a discarded result; that is outside this prototype. |
| `PBList` positions | **Zero-based**, a negative one counts from the end. | The name is `proto_db`'s and the persisted `PosNode` counts are the same in both languages. | Smalltalk programmers expect 1. Every other collection a program builds (`Array`, `PBTuple`, `PBFrozenList`) stays 1-based. |
| `Dictionary` iteration | A `PBDictionary` iterates in key order, a `PBHashDictionary` in hash order. | The format's order. | Insertion order is not kept; `PBFrozenDict` keeps it. |
| Timeouts and backoffs | SmallInteger **milliseconds**, where Python uses float seconds (`lockTimeout`, `run:retries:backoff:`). | The protoST convention (STATUS D48). | A rounded delay: the jitter is rounded to whole milliseconds and never above the bound. |
| Class names in some error texts | `PBList element`, `PBSet element` where `proto_db` says `List element`, `Set element`. | They are protoST's class names. | None; the tests pin both sides. |
| No `asOf:` | None. | `proto_db` has none. As-of is a three-line helper (tutorial, section 12). | The helper is a block in a script. |

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
| A slice bound that is not an Integer or `nil` (including `true`) | Python's `slice.indices` takes `True` as 1; in Smalltalk a Boolean is not a number, and `proto_db`'s own positions refuse `bool`. `tests/unit/list_positions.st` records `proto_db`'s answers next to this one's. | |
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
  year 1 or year 9999 is `PBNotSupportedError`, because `proto_db` refuses to read such a value
  back. *Cost:* a `datetime.max`-style sentinel in an IANA zone cannot be written from protoST; an
  atom that holds one, written by `proto_db`, can be read but not re-written by protoBaseST.
- **A format-3 `["zone", key]` datetime** (legacy data) is read lazily as a `PBLegacyZoneDateTime`
  (`isLegacyZone` true). Its wall clock and fold are kept. It is never given an offset; every use
  that needs one (hash, order, UTC instant, comparison with an aware value more than the window
  apart, a map with two keys that could conflict) is `PBNotSupportedError` naming the zone.
  Writing it is `PBValidationError`. *Why lazy:* old atoms whose other attributes are fine stay
  readable, and atoms that are never changed are kept byte for byte. `proto_db` would re-encode
  such a value as its instant, which needs a database, so this differs from it on purpose
  (see the conformance vectors, below).
- **Zone keys: a pinned list.** A key is valid when it is in `PBZoneKeys`, the Zone and Link
  names of IANA tzdata 2026e (`tools/gen_zone_keys.py`, committed). The same on every machine.
  A key outside the list is `PBCorruptionError` when read and `PBValidationError` when written;
  a key newer than the release is refused until the list is regenerated. *Cost:* `proto_db` checks
  against its host's tz database. On a host that lacks the backward-link names
  (a host without `tzdata-legacy`; `US/Eastern` is one), `proto_db` refuses those pinned keys. protoBaseST neither refuses nor
  rewrites such keys, because refusing them on write would make it unable to re-save an atom that
  `proto_db` wrote legitimately. Cross-implementation tests use canonical Zone names only.
- **`["zone", key]` inside a `@time`** is a wall clock without a date, fully supported.
- **`TimeSpan`** counts microseconds (protoST's kernel `Duration` counts milliseconds).

## Collections and records

- **Indexed collections are not written or merged.** A collection that has an index (a
  `PBEqualityIndex`, `PBRangeIndex` or `PBVectorIndex`) refuses every change with
  `PBNotSupportedError` naming its indexes, and so does a merge onto one (design spec 7.4).
  `proto_db` updates the indexes in the same step and merges blind writes onto them; protoBaseST
  cannot do either, so it does not do a lesser version. Index *queries* are not provided either:
  indexes are decoded and kept. `extend:` of nothing still answers the receiver, as `proto_db`'s.
  *Cost:* a database that uses indexes can be read and its non-indexed parts changed; the indexed
  collections cannot be changed from protoST.
- **`PBRepeatedKeysDictionary` is read only.** Its writes and merges are a non-goal. A new empty
  one is mergeable and its rebase answers `current` unchanged, as `proto_db`'s.
- **Immutability is by convention** (decision 3). No instance is frozen at run time: a method
  that assigns an instance variable after construction would compile. A test
  (`tests/unit/values_immutable.st`) scans for it. Two runtime-only fields are exceptions, both
  `Atom` cells and neither persisted: the memo of a lazy load and the consumed mark of an
  operation log.
- **Application records.** Accessors only answer the stored value (decision A4). A behaviour name
  that is also a stored attribute, in any implementation, is a defect: a record holding a
  reserved name is refused when loaded (`PBCorruptionError`). There are no generated setters.
- **Positional trees are not subclassable**, as in `proto_db`: a `PBPosNode` subclass is refused
  when registered, built or given to a positional operation. A keyed node class may be extended
  with fields, which every write carries into the copies.
- **Self-referencing records.** A record whose decoding needs the record itself (a map key that
  refers back to it) is `PBCorruptionError` naming its pointer. `proto_db` recurses until Python's
  `RecursionError`. `proto_db` saves every dependent before the record that refers to it, so such a
  record is damaged data or the work of a writer that breaks that invariant.
- **A mergeable log is a property of the version's history** (`proto_db` D33): a rebased version
  keeps the completeness of the version it was rebased onto, as `proto_db`'s code does (the brief
  and `proto_db`'s docstring said "not mergeable"; the code is the reference).
- **Counted-set logs** use `proto_db`'s op names: `('add' e)`, `('remove' e)` for calls and
  `('transform' e removes adds)` only for a rebase's adjustments.

## Transactions and storage

- **No cluster mode.** A directory with `cluster/`, or whose SpaceRoot carries a `cluster_term`,
  is refused (`PBNotSupportedError`). `proto_db`'s "held retries" (an immediate retry without
  backoff, `permit_held`) are therefore not ported. Mixed Python/protoST clusters are outside
  acceptance until a protocol freeze.
- **Framed log files** (the `log` and `roots_log` layers) are read and written by the cluster
  modules (`PBFramedLog`, `PBAcceptorLog`), which no space uses yet. The acceptor log writes
  kinds 1 to 4 and reads 1 to 6 (it never writes kinds 5 and 6, which belong to `proto_db`'s
  tiered storage), and it is never compacted (`proto_db`'s `RootsLog` rewrites a log over 1 MiB).
  The lock file is named after the real path (`FileReference >> realPath`, as `proto_db`'s
  `os.path.realpath`). A symbolic link loop is refused when the path is resolved
  (`PBUnexpectedError`, nothing created): Python's non-strict `realpath` does not raise on a loop,
  so `proto_db` creates `<loop path>.lock` and then fails to open the log (`ELOOP`, also
  `ProtoUnexpectedError`). Same class, earlier refusal, no stray lock file. A lock held
  elsewhere is `PBUserError` naming the lock file (cluster plan, Review Focus 3), where `proto_db`
  raises `ProtoLockingError`; a log with two hard links is `PBLockingError`, as `proto_db`.
- **The caller owns the lock backoff, and it blocks the caller's worker.** The publisher never
  waits (ruling R19): an attempt that finds the root lock held answers at once, and the
  committing caller waits 1 ms, doubling to 50 ms, until `lockTimeout`. That wait sits in a
  `whileFalse:` block, so it blocks the caller's worker thread instead of suspending the actor
  (protoST question K23, open, see below). It is bounded and only happens while
  another *process* holds the lock; while it waits, the worker still serves other actors.
- **Group commit** (`proto_db` D52) is not implemented: every publish is a group of one.
- **One storage failure ends writing through that storage** (`isFailed`), like `proto_db`'s, but triggered by any write error (see decisions, Task 17); reopen
  the space. Reads keep working.
- **Step 8 of a failed publish.** A root at a different epoch is `PBConflictError`, as
  `proto_db`'s `_publish`. A root that reappears at the same epoch, written by a writer that
  ignored the lock, cannot be told from "nothing published"; `proto_db` has the same limit.
- **`newTransactionDo:` commits on a non-local return** (`^`) and aborts exactly when an
  exception unwinds the block (ruling R20b), as Python's `with`. A resumable exception that an
  enclosing handler resumes does not end the block, and the block's writes are committed. This
  needed `Exception >> outer` in protoST.
- **Durability** is always `fsync`; there are no other modes. Windows is untested.
- **A non-aware previous `committedAt`** is `PBCorruptionError` (Python's `max` would raise
  `TypeError`).
- **Origin bytes** of a new database are a version-4 UUID's, as `proto_db`'s `uuid4().bytes`.

## Shapes protoBaseST cannot write

The round-trip tests (design spec 10.2) write a space from protoST and have `proto_db`'s verifier
accept it. The space cannot contain what protoBaseST cannot write:

- an indexed collection (index maintenance is out of scope, design spec 7.4);
- `PBRepeatedKeysDictionary` writes (a non-goal);
- Python-only types such as `demo.erp.AuditNote`, which protoST reads as opaque atoms and never
  re-writes.

Hence the interop round trip compares dumps with `compare_dumps.py --exact` (no normalisation of
the opaque type), and `tests/interop/concurrency.sh` row 13 (a blind write onto an indexed root)
uses a copy of the conformance database in all four runs and asserts protoBaseST's
`PBNotSupportedError` in place of `proto_db`'s merge. Likewise `st_random_ops` covers the four
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
  `proto_db`'s.
- **The root record refusal** is `proto_db`'s `decode_root` sentence ("Undecodable root record"),
  without protoST's MessagePack detail. `proto_db` keeps that detail only as `__cause__`, and
  protoST has no exception chaining. *Cost:* a corrupt root is harder to diagnose.

## Conformance vectors

The vectors are those of `proto_db` at `v2.0.0rc2` (digest recorded in
`tests/conformance/vectors.sha256`). Where protoBaseST differs from the manifest on purpose, the
difference is a tracked table (`tests/conformance/_expected_differences.st`) and the runner fails
if a listed difference goes away or an unlisted one appears. Three remain, all `permanent,
design 4.3` (no time-zone database):

| Section | Id | Difference |
|---|---|---|
| `values_decode_only` | `datetime-zone-format3` | Decodes to a `PBLegacyZoneDateTime` (the wall clock), not the instant; re-encoding it is `PBValidationError`. |
| `values_read_not_rewritten` | `map-zone-key-format3` | Re-encoding is refused, as listed; the decoded keys are format-3 wall clocks, not instants. |
| `invalid` | `value-instant-wall-out-of-range` | **Accepted** and presented in UTC. The wall-clock range needs the zone's rules; the format spec ("Known gaps") lets a reader without a database present the instant in UTC. Refusing would call valid data corrupt. |

The invalid `message-oversized` vector (a frame length, the frame layer's refusal) is verified by
`tests/conformance/cluster.st` with `PBClusterFrame lengthFrom:`; no vector is skipped.

## Cluster wire messages

`PBClusterMessage` (`cluster/protocol.st`) decodes what `proto_db`'s `protocol.py` at
`v2.0.0rc3` decodes and refuses what it refuses. Where `proto_db`'s format spec (and so the
cluster plan's brief and design spec 1.11, which quote it) words a rule differently from its
code, the code is followed (controller ruling, cluster Task 5 review), because a peer is judged
by the bytes `proto_db` accepts. Pinned by `tests/unit/cluster_messages.st`:

- **Map keys.** The format spec says a map key that is not a string drops the connection.
  `proto_db` decodes with msgpack-python's `strict_map_key=True`, which also admits bin keys, so
  protoBaseST decodes with `strictKeys: true`: an int, float or nil key is refused; a bin key
  never equals a field name, so a bin `v`, `type` or `from` is a missing one and an extra bin key
  is ignored. No honest peer writes bin keys (`packb(use_bin_type=True)`); the two readings
  differ only on garbage. The disagreement between `format-spec.rst` and `protocol.py` is a note
  for `proto_db` upstream.
- **Version.** `proto_db` refuses `msg.get('v') != 13`, and Python's `13.0 == 13`: a `v` written
  as the Float 13.0 (float64 or float32) is version 13. `true` is not (Python's `True == 1`).
- **Value lists.** The format spec lists the values of `done.outcome` (`committed`, `none`,
  `unknown`) and `answer.state` (`ok`, `empty`, `unknown`); `proto_db`'s `_check_field` checks
  only that they are strings, and so does protoBaseST. A message using another value is a
  protocol matter for the rules (later tasks), not a decoding refusal.
- **Timestamp exts.** msgpack-python turns every ext of type -1 into a `Timestamp` while
  decoding, and refuses data that is not 4, 8 or 12 bytes or whose nanoseconds reach 10^9, even
  inside an extra field that `proto_db` then ignores. protoST's MessagePack keeps exts as they
  are, so `PBClusterMessage decode:` checks every type -1 ext in the map the same way
  (`PBClusterProtocolError`).

A message protoBaseST builds (`type:from:fields:`) is stricter than `proto_db`'s
`make_message`: an integer of 2^64 or more and the 3-item root form (never written, CC17) are
`PBValidationError` when it is built, not a failure of `encode` or a form only a reader takes.

## Cluster mode

- **Frame authentication (divergence, design spec 8.4 Q5, CC4).** `proto_db`'s cluster has no
  authentication: a frame is a 4-byte length and a msgpack map. protoBaseST offers optional HMAC
  frame authentication with a shared key (`PBClusterFrame`, a `ByteArray` of at least 32
  bytes). **Disabled** (no key), the frames are protocol 13 byte for byte and the message
  vectors are the test. **Enabled**, every frame body is the msgpack bytes followed by a 32-byte
  tag, HMAC-SHA-256(key, UTF-8(receiver id) ‖ 0x00 ‖ msgpack bytes), and the 4-byte length
  covers both: such frames are not protocol 13, and a `proto_db` node (or a protoBaseST node
  without the key) refuses them as undecodable, as protoBaseST with a key refuses an unkeyed
  frame. A missing or wrong tag drops the connection like an invalid message. The receiver id in
  the tag stops a frame from being delivered to another member; there is no replay counter,
  because duplicated and reordered messages are already inside the failure model. protoST has
  no constant-time comparison: the tag is compared by accumulating the XOR of all 32 byte pairs
  and testing the result once, with no early exit. *Cost:* a keyed cluster cannot mix with
  `proto_db` nodes; with the key, a frame costs 32 bytes and one HMAC each way.
- **Node ids (stricter than `proto_db`).** `proto_db`'s `Peer` takes any non-empty `str` as a
  node id, NUL included, and its frame layer names no receiver. protoBaseST refuses
  (`PBValidationError`) an id holding NUL in `PBPeer nodeId:host:port:`, and an empty id or one
  holding NUL as the receiver of `PBClusterFrame`. With no NUL in the id, the tag input
  UTF-8(id) ‖ 0x00 ‖ msgpack bytes names exactly one (id, message) pair, by construction rather
  than by an argument about msgpack's first byte. The cluster is protoBaseST-only, so no
  `proto_db` node is refused by this. *Cost:* none known; an id with NUL is not a useful id.
- **Trusted network (both cases).** The cluster transport is plaintext. Without a key it is
  unauthenticated, exactly as `proto_db`'s: anyone who can reach a member's port can send it any
  message, so the network must be trusted. With a key, frames are authenticated but **not
  encrypted**: a listener on the network reads every message (roots, records, data), so the
  network must still be trusted for confidentiality. Encrypted links would need a TLS server in
  protoST. `proto_db`'s documentation does not state the assumption; proposing that it does is
  Q7(b) of the design spec.

## Errors and messages

- The error classes mirror `proto_db/errors.py` with `PB` for `Proto`. `proto_db`'s extra classes
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

All figures below were measured 2026-11-13 on the same machine, at a load average of about 9 to 14
(other work was running), so they are indicative only; instruction counts hold better than wall
time on a busy machine. The binary is protoST 0.10.0 built at `build_rel0100` (protoST with S37 to
S40 merged), the same binary for every column, against `proto_db` `v2.0.0rc2` on Python 3.14.6.
Re-run the scripts on your binary before quoting any figure. No claim of speed is made.

An earlier table (2026-11-12, `RUNS=3`, a pre-release protoST build, load about 3.5) gave
`check:` at 52x / 54x. It is superseded by the figures below: every re-measurement on later
protoST builds gave about half that ratio; which protoST change caused it was not isolated.

### AVL operations

`bench/run_avl.sh` (`RUNS=5`), ratio of the minimum time to `proto_db`'s minimum; "before" is
protoBaseST at `7ef11d7`, "after" at `36f2579` (the commit work below changed the commit path
only):

| Operation | before | after |
|---|---|---|
| `posAppend` | 21x | 24x |
| `keyPut`, new key / replacing a key | 12x / 18x | 13x / 22x |
| `posAt` / `keyAt` | 19x / 14x | 17x / 14x |
| `check:` of a positional / of a keyed tree | 22x / 31x | 22x / 30x |

So the AVL structures are roughly 12 to 31 times slower. The before/after differences are within
the noise of this load (the medians moved the other way for several rows); the remaining cost is
protoST's interpreter and node building, not the format.

### Commits per second

`bench/run_tx.sh` (`RUNS=5`, interleaved, `TX_SCALE=1`). Segments on ZFS (`sync=standard`),
`fsync` durability on both sides. "Before" is protoBaseST at `7ef11d7`; "after" is `36f2579`,
after the commit performance work (decisions R23 to R29: each value made canonical once, the new
root checked by its bytes, an atom cache bounded in entries and bytes, batched oids, codec fast
paths) and its first review fixes (values the writer must refuse are refused again at save). The
bytes written are the same (`tests/unit/bytes_pinned.st`). Commits per second from the minimum /
median wall time:

| Profile | `proto_db` | before | after | after / `proto_db` |
|---|---|---|---|---|
| tiny (one key) | 152 / 130 | 18.3 / 16.4 | 31.9 / 29.3 | 0.21x |
| small-record (3 fields of a record) | 148 / 122 | 13.6 / 12.8 | 26.2 / 22.0 | 0.18x |
| batch-100 (100 keys per commit) | 55.2 / 49.5 | 2.2 / 2.0 | 3.2 / 2.6 | 0.06x |
| conc-disjoint, 1 / 2 / 4 writers (min) | 141 / 134 / 226 | 14.6 / 15.7 / 15.0 | 25.2 / 27.5 / 31.3 | 0.18x / 0.21x / 0.14x |
| conc-merge, 1 / 2 / 4 writers (min) | 145 / 128 / 207 | 10.8 / 10.4 / 10.3 | 22.3 / 22.4 / 18.7 | 0.15x / 0.18x / 0.09x |
| conc-hot, 1 / 2 / 4 writers (min) | 153 / 151 / 114 | 21.5 / 21.7 / 16.0 | 32.9 / 29.1 / 25.3 | 0.22x / 0.19x / 0.22x |

User-space instructions per committed transaction (`bench/run_tx_instr.sh`): tiny 119 M before,
53 M after, 3.6 M for `proto_db`; small-record 140 M, 61 M and 4.0 M; batch-100 1,335 M, 904 M
and 61 M. The I/O is the same on both sides (about 2.4 KB and three `fsync` per small commit), so
the remaining gap is CPU: protoST's interpreter, node building and record encoding. A batch commit
is dominated by the 100 in-memory tree inserts, which this work did not change.

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
  waits, its worker still serves other actors. **Not reproduced with Futures settled by network
  events** (Task 1 of the cluster plan, 2026-11-13, protoST 0.10.0 on protoCore 3.6.0):
  `tests/week0/k23_network_settled_futures.st` has 64 actors waiting nested (blocking their
  worker) and 64 waiting at the top level of their method on Futures a hub actor hands out and a
  socket reader actor settles; all 128 answer and no `deadlock:` is raised, also with
  `PROTOST_WORKERS=1`. **Limit of that evidence:** the interleaving the check targets (a caller
  already in its second `wait` when the reader settles its Future) is likely but not forced; a
  caller that gets there late waits on a settled Future and cannot show the defect. 40 runs (10 of
  them with one worker) never raised `deadlock:`: an absence of observed failure, not a proof.
  The question stays open, for this pattern too and for the pattern that first raised it.
- **Module resolution is documented protoST behaviour, not a bug.** The working directory is
  searched before the library, as in Python, so a stray `calendar.st` in the current directory
  shadows the library's calendar module. **Security note:** an untrusted working directory's
  `.st` files replace library modules of the same name. Run protoBaseST programs and tests from a
  trusted directory.
