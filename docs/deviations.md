# Deviations and refusals

Where protoBaseST differs from `proto_db` at `v2.0.0rc2`, and everything it refuses. The cluster
branch follows `proto_db` at `v2.0.0rc4` at format 4 (protocol 14, format 5 refused; see
[Reading](#reading)).
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
| No `asOf:` | None. | `proto_db` has none. As-of is a three-line helper ([tutorial/erp.md](tutorial/erp.md), section 12). | The helper is a block in a script. |

## Values refused when written

All are `PBValidationError`, raised by the call that receives the value, naming the class.

| Value | Why it is refused | What to do |
|---|---|---|
| A `Symbol` longer than six bytes (decision 2; format 4 has no symbol kind) | A symbol stored as a string would come back as a string; the value would change kind. | Store a `String`. When `@sym` lands (in a later format; `proto_db` deferred symbol references past format 5), protoST gets an explicit wrapper. |
| A short `Symbol`, such as `#paid` | **Not refused**, because in protoST it *is* the `String` `'paid'` (STATUS D35). It is stored as a string. | Nothing depends on telling them apart. |
| A protoST `Dictionary` | Its order is unspecified and the order of a map is part of its bytes. | `PBFrozenDict`, or a `PBDictionary`. |
| `Fraction`, `Character`, `Set`, `Bag`, `Interval`, a block, any other object | They have no kind in the format. Storing them under another kind would be a lie. | Convert explicitly. |
| A string with a lone surrogate | It has no UTF-8 encoding. | |
| A list, a map, a NaN as a key or set element | Not orderable (as in Python). | `PBTuple`. |
| A value nested deeper than 1022 msgpack containers (`PBCodec maxValueDepth`) | The normative limit of `v2.0.0rc2`. Reading deeper data is `PBCorruptionError`. | |
| A root name starting with `__`, written or removed (`removeRootObject:` too, since `proto_db` 2.0.0rc4) | Reserved for the format (the runtime registry's roots). | |
| An attribute name starting with `_`, or `oid`, `atom_pointer`, `context`, `with_`, `has_defined_attr`, or a name the class reserves | The format's rule for records. | |
| A change (`withAll:`, `with:value:`) naming `parents` or `with_parents` | Reserved for new fields by `proto_db` 2.0.0rc4 (format spec "Reserved names", R157, R158: DBObject's parents API). A stored field of either name, written before, still loads, reads and is carried unchanged by a new version. | Another name. |
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

- **Cluster mode only through a coordinator.** A plain storage (`PBFileStorage path:`) refuses a
  directory with `cluster/`, and a space without a coordinator a SpaceRoot that carries a
  `cluster_term` (`PBNotSupportedError`); a cluster node opens its directory with
  `PBFileStorage clusterPath:` and `PBObjectSpace storage:coordinator:` (see Cluster mode, the
  shared tier). `proto_db`'s "held retries" (an immediate retry without
  backoff, `permit_held`) are not ported. Mixed Python/protoST clusters are outside
  acceptance until a protocol freeze.
- **Framed log files** (the `log` and `roots_log` layers) are read and written by the cluster
  modules (`PBFramedLog`, `PBAcceptorLog`); a space uses the acceptor log only through a
  coordinator (`PBSharedTier`). The acceptor log writes
  kinds 1 to 4 and reads 1 to 6 (it never writes kinds 5 and 6, which belong to `proto_db`'s
  tiered storage), and it is never compacted (`proto_db`'s `RootsLog` rewrites a log over 1 MiB).
  The lock file is named after the real path (`FileReference >> realPath`, as `proto_db`'s
  `os.path.realpath`). A symbolic link loop is refused when the path is resolved
  (`PBUnexpectedError`, nothing created): Python's non-strict `realpath` does not raise on a loop,
  so `proto_db` creates `<loop path>.lock` and then fails to open the log (`ELOOP`, also
  `ProtoUnexpectedError`). Same class, earlier refusal, no stray lock file. A lock held
  elsewhere is `PBUserError` naming the lock file (cluster plan, Review Focus 3), where `proto_db`
  raises `ProtoLockingError`; a log with two hard links is `PBLockingError`, as `proto_db`.
- **The round runner owns the lock retry (CC10).** `proto_db`'s round holds the root lock with
  `root_lock(lock_timeout)`, which blocks the runner's thread. Here neither the round runner nor
  the publisher ever waits (ruling R19): a round that finds the root lock held answers `#locked`
  at once, and the runner schedules the next round with `Future after:` (1 ms, doubling to
  50 ms, `proto_db`'s `_acquire_process_lock` steps). Each queued commit keeps its own
  `lockTimeout` deadline from the moment it was queued, and ends in `PBTimeoutError` with
  `proto_db`'s message once it has passed; `proto_db` measures one `lock_timeout` per round, from
  the start of the round's wait. The committing caller waits only on its commit's `Future`. The
  lock backoff no longer blocks the caller's worker (the deviation that it did is removed, and so
  is that part of K23): the caller's single `wait` is nested in `ensure:` and so still blocks its
  worker, as any `Future` wait inside a block does in protoST, while the worker serves other
  actors. *Cost:* a commit queued while a retry timer is pending starts at that timer (at most
  50 ms later), where `proto_db` would join the round after the one waiting for the lock.
- **Group commit** (`proto_db` D52, ruling R71) is implemented, as `_standalone_round` at
  v2.0.0rc3 (cluster plan Task 22): one round takes every queued commit, saves each one's written
  atoms (a failure is that commit's alone, as each `proto_db` thread saves its own before it
  joins the group), holds the root lock once, reads the root once, builds each commit on the root
  the previous build saved (a build error is that commit's alone), and makes the last root
  durable with one flush and one publish; a failure of the lock, the root read, the flush or the
  publish reaches every built commit (each `wait` re-signals its own copy of the error, as
  `proto_db` raises a copy in each thread), and the step-8 outcome of a failed publish is the
  round's. A commit alone in the queue runs exactly the single-commit protocol (the bytes of
  `tests/unit/bytes_pinned.st` are unchanged). The round is a message of the runner actor, so a
  group is what was queued while the previous round ran; `proto_db`'s group is what was queued
  while the previous runner held the group. The R148 change to `transactions.py` (`88ca21d`,
  the `_Ending` marker of a kept permission being ended) touches only the cluster round's kept
  permissions (`_take_kept`, `_keep`, `_drop_kept`, `_run_round`), not `_standalone_round`: it
  has no counterpart here (Task 23 owns the cluster half).
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
- **Format 5 is refused** (`proto_db` 2.0.0rc4, the runtime registry D62: the features `parents`,
  envelope key `p`, and `registry`, the types `ModuleList` and `Catalog`, aliases 22 and 23).
  protoBaseST reads formats 2 to 4 and writes 4, as `proto_db` writes for data without a
  feature. A segment header or root record of version 5 (or above) is `PBNotSupportedError`
  (format spec "Format stability": a reader that predates a version refuses it and never
  misreads it), so any space an rc4 writer opened with a feature is refused at open. The header
  is checked before any record of the segment is decoded, so a four-key envelope is never
  reported as corruption (`tests/conformance/format5_refused.st`). An acceptor log of log format
  3 is refused at its header; protoBaseST writes log format 2 and never a kind-7 entry. The
  aliases 22 and 23 are in the built-in table with no class, and an application class
  declaring either name is refused when registered (`PBValidationError`). So a record of
  either is `PBNotSupportedError` when read, and `PBAtomEnvelope encode` refuses one as a
  backstop, so none is ever written. The runtime registry (modules, catalog, C3
  resolution, `__currentModules`, `__catalog`) is not supported; it gets its own plan after the
  cluster branch. The registry of record classes is process-wide, as `proto_db`'s.
- **The root record refusal** is `proto_db`'s `decode_root` sentence ("Undecodable root record"),
  without protoST's MessagePack detail. `proto_db` keeps that detail only as `__cause__`, and
  protoST has no exception chaining. *Cost:* a corrupt root is harder to diagnose.

## Conformance vectors

The vectors are those of `proto_db` at `v2.0.0rc4` (digest `37b286fd…`, recorded in
`tests/conformance/vectors.sha256`; `v2.0.0rc2` before cluster Task 22a). Where protoBaseST differs
from the manifest on purpose, the difference is a tracked table
(`tests/conformance/_expected_differences.st`) and the runner fails if a listed difference goes
away or an unlisted one appears. Six remain: three `permanent, design 4.3` (no time-zone
database) and three format-5 vectors refused until the runtime-registry plan (D62):

| Section | Id | Difference |
|---|---|---|
| `values_decode_only` | `datetime-zone-format3` | Decodes to a `PBLegacyZoneDateTime` (the wall clock), not the instant; re-encoding it is `PBValidationError`. |
| `values_read_not_rewritten` | `map-zone-key-format3` | Re-encoding is refused, as listed; the decoded keys are format-3 wall clocks, not instants. |
| `invalid` | `value-instant-wall-out-of-range` | **Accepted** and presented in UTC. The wall-clock range needs the zone's rules; the format spec ("Known gaps") lets a reader without a database present the instant in UTC. Refusing would call valid data corrupt. |
| `format5` | `parents_database` | A format-5 space (feature `parents`): its version-5 root is `PBNotSupportedError` at open. |
| `format5` | `registry_database` | A format-5 space (feature `registry`): the same refusal. |
| `format5` | `roots_log_v5` (`cluster/roots-v5.log`) | An acceptor log of log format 3: `PBNotSupportedError` at its header. |

The invalid `message-oversized` vector (a frame length, the frame layer's refusal) is verified by
`tests/conformance/cluster.st` with `PBClusterFrame lengthFrom:`; no vector is skipped.

## Cluster wire messages

`PBClusterMessage` (`cluster/protocol.st`) decodes what `proto_db`'s `protocol.py` at
`v2.0.0rc4` (protocol 14) decodes and refuses what it refuses. Protocol 13 and 14 nodes never
exchange messages: every message carries `v`, and another version drops the connection. Where `proto_db`'s format spec (and so the
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
- **Version.** `proto_db` refuses `msg.get('v') != 14`, and Python's `14.0 == 14`: a `v` written
  as the Float 14.0 (float64 or float32) is version 14. `true` is not (Python's `True == 1`).
- **Optional `unknown` (R240L).** `fetched` and `commit_info` may carry `unknown`, a Boolean:
  absent reads `false`, present and not a Boolean is refused, present is carried and re-encoded
  (`at:`, `includesField:`). On any other type it is an extra field, ignored. At DEPTH = 0 the
  port never sends `fetch` or `commit_query` and ignores the replies; answering `unknown` and the
  read capping of the fetch service (R212) are Phase D.
- **Five-item roots.** A protocol-14 root may carry its format version as a fifth item (above 4).
  protoBaseST never writes one, and refuses every one it receives with `proto_db`'s two reasons:
  a fifth item that is not an Integer above 4 is malformed; any other is a format version this
  node does not read (2 to 4).
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
  bytes). **Disabled** (no key), the frames are protocol 14 byte for byte and the message
  vectors are the test. **Enabled**, every frame body is the msgpack bytes followed by a 32-byte
  tag, HMAC-SHA-256(key, UTF-8(receiver id) ‖ 0x00 ‖ msgpack bytes), and the 4-byte length
  covers both: such frames are not protocol 14, and a `proto_db` node (or a protoBaseST node
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
- **Plain queries on the acceptor lane (timing only, CC2).** `proto_db`'s dispatcher answers a
  plain query (`ballot` 0) at once from its in-memory state (`_route`); only a ballot query goes
  to the acceptor lane. protoBaseST's dispatcher holds no acceptor state (CC2), so the acceptor
  answers every query from its own state, after the steps queued before it. The fields are the
  same (`promised` is max(terms seen, accepted label)); the answer can come later, and it reports
  only what is durable, where `proto_db`'s may count a promise not yet synced. *Cost:* a recovery
  round or a rejoin may wait behind a node's queued syncs.
- **A release's fairness bookkeeping at dispatch (timing only).** `proto_db` notes a release's
  wake-ups, progress and the turn it names (`_note_release`) when its acceptor lane takes the
  release; protoBaseST's dispatcher notes them when it receives the release, before it hands the
  release to its acceptor (`receivedRelease:in:now:`, `cluster/proposer.st`). The acceptor still
  takes the release before any request of the same step, and no grant rule reads the hints.
  *Cost:* a back-off or a deferral may end one acceptor-lane latency earlier.
- **Permission waiters (timing only, `cluster/owner.st`).** `proto_db` runs one thread per
  commit, each asking an owner, backing off and timing out on its own. protoBaseST's waiters
  share the node's acquisition: a waiter refused or met with silence rejoins it, and the next
  round asks a known owner at once (`proto_db` backs off once first); a waiter that is not the
  head of the acquisition times out at the end of the first round after its deadline (`proto_db`'s
  thread, blocked on the node's local lock, at its deadline); a waiter queued at the node's own
  ownership while a renewal runs times out when the renewal closes. A waiter queued at its own
  node's ownership otherwise leaves the queue at its deadline with `PBTimeoutError`, as in
  `proto_db`. No safety rule reads these times. *Cost:* such a timeout may be reported up to
  one round late.
- **The done carries the committed root (representation only).** `proto_db`'s `finish` reads the
  committed root from the permission object, which the commit path set; protoBaseST's
  `PBDoneReport` carries it (`permission:outcome:root:`), since a `PBPermission` is immutable. The
  `done` message is the same. *Cost:* none.
- **Permits naming a proposal (`after`).** Mixed clusters with `proto_db` nodes are not a goal
  (design spec section 4), and a protoBaseST cluster never sends `after` (DEPTH 0). A received
  permit whose `after` is not nil is held as uncertain (H2, tested); its proposal and the gate
  H5 are not tracked, and that case is untested. *Cost:* none in a protoBaseST cluster.
- **The base issued twice (R79/L28), tested in its strict form.** `proto_db` keeps an owner
  issuing one base twice as a strict expected failure at convergence (S4). protoBaseST plants the
  same defect (`PlantBaseTwice`, O1's pipeline check dropped) over the real base choice and
  replication: the second holder's root commits, the first holder's higher-epoch sibling is ranked
  above it by phase 1, and the run must fail S4 at convergence (`sim_base_choice.st` (5)); the
  product passes the same schedule. Not a deviation; recorded because the stand-in form of
  Task 12 (caught earlier, by the sibling-roots rule) was one.
- **The dispatcher's suspicion clears one acceptor step later (timing only, CC2).** `proto_db`'s
  `_learn_label` clears the node's `suspect_term` in the one shared state the moment a committed
  label at or above it is observed. protoBaseST's suspicion has two halves: the acceptor's
  (cleared in the step that learns the label) and the dispatcher's, cleared when that step
  reaches it (`PBAcceptorStep learnt`, `_learnt:in:`, `cluster/holder.st`); a replication that
  commits clears it at once. Two effects follow. (1) A lease or release decided between the
  observation and its step's return is reported uncertain: freshness only. (2) When the
  acceptor observes label T and the dispatcher then abandons T (its suspicion T, the
  `PBSuspect` queued behind that step), the step's return clears the dispatcher's half,
  although in `proto_db`'s single variable that real-time order (learn, then abandon) leaves
  the node suspect; until the `PBSuspect` step returns, a release decided in that window is
  certain. That is still an execution `proto_db` admits: it clears the suspicion the same way
  when the observation is delivered after the abandon (`_learn_label` has no ordering guard),
  and a message delayed past the abandon is inside the failure model. It is transient: once the
  `PBSuspect` step lands, the acceptor's half holds the suspicion again, more conservatively
  than `proto_db`. *Cost:* uncertainty reported a little longer in (1); in (2) a certainty
  `proto_db` also reports under a delayed observation, never one it could not.
- **The replicate's pred is named by the commit path and checked by the core (representation
  only).** `proto_db`'s `replicate` takes the pred from the lease (`lease.sent`, else the lease
  root, which `bind_root` sets to the base, then to the re-committed root and to each root a
  round commits); protoBaseST's commit path names it in
  `PBReplicateWanted permission:root:pred:waiter:`, since a `PBPermission` is immutable. The
  `replicate` message is the same. Acceptors trust the pred (V2' cannot detect one that lies
  about the build base), so the core keeps `proto_db`'s rule itself: `PBHolder permits` records,
  per permission held, the base bound (the base choice's, then each root committed under the
  permission, as `bind_root`), the root last sent and the root last committed, and
  `dispatchReplicateWanted:` refuses (`PBValidationError`) a pred other than `predFor:in:` (the
  root last sent, even when its outcome was `#unknown`; else the base bound; else the
  permission's root; a round that sent nothing does not move it). A record is forgotten when
  the permission's done report is made; at most `permitsSeenLimit` (64) are kept, the oldest
  dropped first. After an eviction `predFor:in:` falls back to the permission's root, so a root
  built on it would be accepted even if another root had been sent under that permission: the
  check would no longer hold for it. At DEPTH 0 or 1 at most two permissions are live at once
  and every update re-appends a record at the end, so an eviction cannot reach a live
  permission. *Cost:* none on the wire; a commit path holding more than 64 permissions at once
  would lose the check for the oldest.
- **The base choice runs as values on the dispatcher (representation and timing, CC2).**
  `proto_db`'s `_lease_base` and `recover_root` block a commit thread on the recovery round and
  on the storage read. protoBaseST's `leaseBase:waiter:in:now:` (`cluster/holder.st`) records a
  `PBBaseChoice` in the holder and goes on at each answer (`receivedAnswer:in:now:`), at the
  recovery timer (`requestTimeout`), at the persisted-root read (`PBReadPersisted`, answered by
  `PBStorageRead`); the
  waiter is settled with a `PBBaseDecision` (`#ok`, `#stale`) or with an error
  value: the `PBConflictError` of a recovery that no majority of witnesses answered (retryable:
  the permission ends `none`, as `proto_db`'s raising), the hard guard's `PBCorruptionError`, or
  the failure of a refound read. This node's own accepted and committed roots and its witness
  state are the acceptor's last report (`acceptorView`), not the one shared state `proto_db`
  reads: they can lag one acceptor step. A lagging accepted root can only lower the recovery
  result (the phase-1 floor and the hard guard still apply); a lagging committed root (other than
  one committed under the same permission, which the holder records itself) can give
  an extra re-commit (`needsCommit` where `proto_db` would not) or miss a `#stale` supersession,
  whose replicate the acceptors then refuse by the chain rule like any stale one. The suspicion
  held when the query was sent is cleared on both halves: the dispatcher's at once, the
  acceptor's by `PBRecovered`, which keeps a higher one raised meanwhile (`proto_db`'s single
  variable has the same rule: cleared only when at most the one held at the send). *Cost:* the
  lag only; no safety rule reads a value the acceptor has not made durable.
- **`proto_db`'s I1 rule (`_BaseUnreachable`, R133) is Phase D.** It arises only on a
  local-records tier (`commit_records` answering that the base's records are on no reachable
  peer). Over shared storage the port follows rc4: a base that must be committed first is read
  by the round's re-commit build (`_commit_base`'s `_load_space`), and a failed read there sent
  nothing (R233): the permission ends `none`, the owner keeps its term, and the commits get the
  read error, or R212's retryable conflict once the permission expired.
- **A base read failing after the permission expired (rc4 C3: R212, R231, R233; representation
  only).** `proto_db`'s `_check_expired_read` reads the tier's `failure` and raises
  `ProtoConflictError(...) from error`. The core reads no tier: `PBBuildFailed
  entry:error:tierFailed:` carries whether the commit's tier had failed, which the shell passes
  (`PBFileStorage isFailed`, Task 23; there is no constructor without it, so a shell cannot
  leave it out), and the conflict carries its cause as `PBConflictError cause`
  (`text:cause:`), protoST errors having no `__cause__`. `proto_db` marks the re-commit sent
  with a `sending()` callback just before its replicate; here the split is structural: the
  re-commit's build answers `PBBuildFailed` (nothing sent) and its replication answers
  `PBReplicated`, whose unknown outcome carries only a `PBOutcomeUnknownError`, so a re-commit
  whose root left the node can never be converted (R238L), whatever the error. A commit whose
  read is converted joins the round's conflicts, as `proto_db`'s `conflicted`; the permission
  is no longer valid, so it is never held. The tiered half (`TieredStorage.failure` reporting a
  poisoned tier, R237L, plant `lease_read_failure_hidden`) is Phase D; its counterpart here is
  the event's flag (`HiddenTierFailure`, `tests/unit/_round.st`). *Cost:* none.
- **The renewal back-off and the fenced term: adopted from `proto_db` `88ca21d` (post-rc3,
  R149/R149a).** gamarino/ProtoDB#1 (an owner whose renewal a majority refused renewed again
  once per round trip until its lease ended) was fixed upstream after `v2.0.0rc3` (merge
  `88ca21d`, CHANGELOG 2.0.0rc4, the D50 amendment); the core follows it
  (`PBAttempt isTermFenced`, `cluster/lease.st`; `_ownLoop:now:effects:` and
  `_closeRenewal:now:effects:`, `cluster/proposer.st`; `receivedPermitReq:in:now:`,
  `cluster/owner.st`; `PBClusterConfig renewBackoffFloor`, the timer row `renewBackoff`). It is
  not a deviation from `proto_db` at `88ca21d`; it is ahead of the Task 18 checklist, which stays
  pinned to `v2.0.0rc3`. The rejoin families' workarounds for the storm are gone: the `r78a`
  schedule no longer cuts the holder off before its timer resumes, and `lagged:` (1 ms links)
  is no longer applied (`tests/unit/_rejoin.st`); the acceptance families' guard that skipped a
  wrong rule's continuation is gone too. `AcceptFamilies idle:` (`tests/unit/_accept.st`) is
  kept, for another reason, a liveness property shared with `proto_db` (rc3 and `88ca21d`):
  committed knowledge of an acknowledged commit whose holder crashed before its done is learnt
  only by a later term's phase 1 or a recovery round a commit or a read asks for, never at
  quiescence, so its crashes fall between terms. A local commit that asks while its own node's
  term is fenced waits for that term to end, then acquires, and times out at its
  `acquireTimeout` deadline meanwhile, as `proto_db`'s `_become_owner` blocks on `_local`
  until `release()` with that timeout (the ownership loop arms the waiter's deadline). One
  representation difference, read by no safety rule: `proto_db`'s ownership thread is woken by
  a notify when a fenced term's permission ends; here `_permitOutcome:` re-evaluates the
  ownership in the same step, and the fenced term's timer is the lease's end (or a waiter's
  deadline). *Cost:* none beyond `proto_db`'s.
- **The rejoin-ballot refusal is made twice (L14).** `proto_db`'s `replicate` refuses
  (`ProtoConflictError`) a term below the node's rejoin ballot, read under its lock at the send.
  protoBaseST refuses first in the commit round (`mayReplicate:now:`, `cluster/holder.st`), from
  the ballot the shell hands the `PBRoundState` (`withRejoinBallot:`, never lowered): nothing is
  sent and the commits get a retryable conflict naming the ballot, as `proto_db`'s. Because the
  shell performs the `PBReplicate` later, `dispatchReplicateWanted:` checks again against its
  acceptor's ballot at the send, and then sends nothing (`#none`: the same retryable conflict,
  with the generic text). The ballot is set when the node's rejoin completes (the acceptor's
  adoption, `acceptRejoinLearnt:in:now:`, `cluster/rejoin.st`, never lowered); a node that never
  rejoined by ballot has ballot 0. *Cost:* none: the second check refuses only what the first
  would have refused had the ballot been known when the round asked.
- **The rejoin is a state machine (representation and timing, CC2, L13).** `proto_db`'s `_rejoin`
  is a thread that blocks on its gathers and sleeps `request_timeout` between rounds. protoBaseST's
  rejoin (`cluster/rejoin.st`) is a `PBRejoin` value in the node state: each gather attempt is a
  `PBTimer` of `requestTimeout`, each retry another; the rules, the decision, the ballot round,
  the order of the three appends and what is adopted are `proto_db`'s. No wait makes anything
  safe: a timer only retries a query (L13). *Cost:* none.
- **A rejoin probes the root it adopts (protoBaseST addition).** `proto_db`'s `_secure_chain`
  fetches the chain of the adopted root from a peer for a local tier and is a no-op on a shared
  storage. protoBaseST has only shared storage (L11), so it fetches nothing, and it probes the
  adopted root's SpaceRoot (`PBProbeRoot`) before it logs it: an unreadable one leaves the node
  rejoining, with the reason in `rejoinBlockedIn:` (`proto_db`'s `rejoin_blocked`), and the round
  is retried. Under the failure model it does not arise (records are synced before a round
  replicates). *Cost:* one storage probe per rejoin that adopts a root; a damaged storage object
  keeps a wiped node rejoining instead of serving with an unreadable accepted root.
- **The witness raises its hint on the dispatcher (timing).** `proto_db`'s `_on_ballot_query`
  raises the fairness hint to the ballot on the acceptor lane. Here the hint is dispatcher state
  (CC2): the dispatcher raises it when it hands a ballot query to an acceptor it last saw 'ok'
  and not fenced (`_queryHint:in:`), before the acceptor promises. *Cost:* none: the hint only
  steers which term this node asks for next.
- **forceRejoin before the first attach report (representation).** `proto_db`'s `force_rejoin`
  on a node not attached yet sets `_rejoin_forced` for the next attach, and `detach` drops it
  with the rest of the rejoin (coordinator.py 1644). protoBaseST's `PBRejoinWanted` marks the
  rejoin forced whenever the acceptor's last report (or none yet) is not rejoined, and the
  forced flag is dropped at detach, as in `proto_db`: `PBLogDetached` drops the rejoin
  (`rejoinDetached:`, leaving a marker of the detached log, so a late report of it starts
  nothing), a report over another log than the one a rejoin ran on starts a fresh, unforced
  rejoin (`rejoinCheck:now:effects:`), and an adoption in flight for the detached log is
  refused by an acceptor over another log (`PBRejoinLearnt log`, `proto_db`'s `self._tier is
  not tier` in `_complete_rejoin`); the shell's attach and detach are Task 20's
  (carry-over (k)). On a survivor the acceptor forgets a committed root above its accepted
  root (memory only: such a root was learnt, never logged) and asks for a confirmation again;
  the readers' root is dropped with it (`PBPublishCommitted root: nil`), and the space checks
  `needsConfirmation` on every snapshot, as `proto_db`'s `_read_storage_root` (Task 24, review
  I2), so the next snapshot confirms first and never starts from the lost root.
- **The commit round is a state machine (representation and timing, CC2, CC10).** `proto_db`'s
  `_run_round` is a thread that blocks on the permit, the base, each build and the replication,
  and waits on a condition for held retries. protoBaseST's `round:in:now:` is pure: each answer
  is an event and each wait a `PBTimer` (`PBHoldExpired`). Two refinements, timing only: the
  group bound (CC11, `groupBoundAllows:now:`) is protoBaseST's addition (`proto_db` builds the
  whole batch, so a round whose last build crosses `sendReserve` is refused whole); and the
  reserve refusal's text also names the round's longest build, the belief and `leaseDuration`
  (CC18), so a transaction whose build alone exceeds a permission says why it never commits.
  `proto_db`'s held-retry test that the outcome is not unknown is not written: here an unknown
  outcome ends the permission before a round can hold anything. Held retries are awaited by
  caller, as `_await_retries` (`held <= queued`); `proto_db` leaves out the runner's own thread,
  which cannot wait for the retry it must run itself and keeps the permission for "that retry,
  or any commit queued meanwhile" (`_keep`). The state machine has no runner thread, so it
  waits for every held caller, the runner's included: a commit of another caller never takes
  the round a held retry was promised. The reserve refusal of a permission that already expired
  keeps the CC18 text (`proto_db` raises "lease expired") and, as `proto_db`, is not counted.
  *Cost:* none on the wire; a round under the group bound commits fewer entries per permission
  than its batch.
- **proto_db's cluster tests, ported or justified (Task 18).** `tests/unit/cluster_checklist.tsv`
  gives each of the 261 test functions of `proto_db` v2.0.0rc3's `tests/unit/test_cluster_*.py`
  a row: ported (the protoBaseST file and the family that checks it), deferred to the Phase C
  task that builds what it needs (the threaded shell, the transport, the file-backed log,
  transactions, persistence, the end-to-end and soak tests), or not applicable (tiered storage,
  DEPTH = 1, or a Python-only API such as `FencingToken`, which the port does not have: the
  fencing token is the term). `tests/unit/cluster_checklist.sh` checks the table against the
  tag. Until those tasks land, a deferred row is a `proto_db` test without a protoBaseST
  counterpart: each of Tasks 19-28 turns its rows into ported ones (or re-justifies one as n/a
  in its review), and the final gate runs the checker with `CHECKLIST_FINAL=1`, which fails on
  any deferred row. *Cost:* none in the code; the deferred rows are open work, tracked.
- **The transports are actors (representation and timing, `cluster/transport.st`, Task 19).**
  `proto_db`'s `TcpTransport` has one listener thread multiplexing every accepted connection with
  a selector and one sender thread per peer; protoST has no `select`, so `PBTcpTransport` has
  one listener actor, one reader actor per accepted connection and one sender actor per peer,
  all in the high band. Consequences: (1) the handler is called on the reader of each
  connection, so concurrently when several peers send, where `proto_db` calls it on its one
  listener thread; it must be safe to call from several threads (the coordinator forwards each
  message to its dispatcher actor). (2) Each valid frame is delivered as it is read (CC5);
  `proto_db` loses, with a bad frame, the other messages decoded from the same 64 KiB read.
  (3) `stop` answers a `Future` that settles once nothing more is delivered and every actor has
  finished, where `proto_db`'s `stop` joins its threads: an actor must not wait (R19), so the
  caller chooses whether to wait. *Cost:* none known; delivery and loss are both inside the
  failure model.
- **The sender's queue and back-off (`cluster/transport.st`).** `proto_db` bounds a peer's control
  lane at 10 000 frames (`max_queue`, a send beyond it is dropped) and has a second, best-effort
  lane for `warm` frames bounded by bytes. protoBaseST has the control lane only (`warm` is
  tiered-only, never sent at depth 0 over shared storage) and bounds it by bytes, at
  `PBClusterFrame maxFrameBytes`: a frame that does not fit makes room by dropping the oldest
  queued frames, counted in `frames_dropped`, and is always queued itself. Failures follow
  `proto_db`'s `_send_loop`: a failed write closes the connection and the same frame is written
  once more on a fresh one, at once (`tests/unit/cluster_transport_tcp.st` check 11: a peer
  restart loses only the frames written into the dead connection); only a failed connect starts
  a back-off, during which the frames to that peer are dropped. The back-off is drawn from 100
  to 200 ms where `proto_db`'s is a fixed 0.1 s (the jitter is protoBaseST's). The connect and
  write timeouts are one value, `requestTimeout` (default 1000 ms, `proto_db`'s
  `connect_timeout` and `send_timeout` with which its coordinator builds the transport; a
  coordinator may pass another). The sender reads the monotonic clock for the back-off:
  `transport.st` is a shell, outside the no-clock check of the core (`tests/unit/sim_harness.st`,
  check 12). *Cost:* an old frame may be lost to a burst where `proto_db` would drop the new
  one; both are losses the protocol tolerates.
- **The transport's stats (`cluster/transport.st`).** `frames_dropped` is `proto_db`'s
  `TcpTransport.dropped`; `frames_sent`, `frames_rejected` and `connections_dropped` are
  protoBaseST's own (the plan's names), as `proto_db`'s TCP transport counts nothing else. The
  in-process network's own `stats` (`sent`, `dropped`, `duplicated`, `delivered`) are not
  ported: each endpoint counts its frames.
- **Accept errors (`proto_db` behaviour, kept).** An `accept` that fails while the transport runs
  is written to stderr and the listener tries again at once, as `proto_db`'s selector loop does:
  a persistent error (no file descriptor left) keeps the high-band listener busy and stderr
  full until it clears. An actor cannot wait to back off (R19).
- **The in-process network's faults (`cluster/transport.st`).** `PBInProcessNetwork` drops and
  duplicates frames with probabilities drawn from a seeded generator, partitions the members into
  groups and treats a stopped endpoint as a crashed node, as `proto_db`'s `InProcessNetwork`;
  it has no delays (`set_faults(delay=...)`, `set_link_delay`): delays and reordering are the
  simulator's (`PBSimFaults delay:reorder:`, in virtual time), so no test depends on wall-clock
  timing. The checklist row `test_in_process_delays_reorder_messages` is ported there
  (`tests/unit/sim_harness.st` check 13: with seed 11 all 50 messages arrive, out of send
  order, and with `reorder: false` in order). The network has no `stats` of its own and no `close` (nothing is in flight outside the
  endpoints); the endpoints count their frames (`stats`).
- **The coordinator shell (`cluster/coordinator.st`, Task 20).** Actors stand for `proto_db`'s
  threads and locks: the dispatcher and the acceptor are one high-band actor each, and attach,
  detach and every acceptor step are messages of the acceptor actor, so they never interleave
  (`proto_db` serialises them with `_log_lock`; the checklist rows that test those interleavings
  are `n/a`, Python-only API). Differences, timing or reporting only unless stated:
  - A message whose sender is not another member, or is the node itself, is dropped as
    `proto_db` `_route` does and also **counted** in `stats` `'messages_ignored'` (`proto_db`
    only logs it). The transport cannot check the sender (one-way connections, an HMAC that
    binds the receiver, CC4), so the count is the operator's only sign of it.
  - A tier write fails the tier (R57) when it signals a `PBDBError` or a `FileSystemError`
    (`proto_db`'s `ProtoDBError` or `OSError`). A `PBDBError` a rule's decision signals while handling
    a message (a protocol violation in a peer's message, a malformed value), before anything
    changed, is written to stderr and the message dropped, the node kept, as `proto_db`'s `_work`
    and `_route` do; a local request it interrupts (`_replicate:under:` of a root not labelled
    with its term, for one) is rejected with it, as `proto_db` raises it to its caller, and the
    acceptor hands the dispatcher the error of its decision on this node's own message
    (`PBOwnStepFailed`), matched to the current attempt, renewal, replication or last lost
    attempt (a late one is ignored). For a request, `proto_db` raises from `_open_attempt` into the one
    `permit()` caller driving the acquisition and sends nothing; as there, one waiter, the
    oldest, is rejected with the error, nothing is counted lost and the next waiter asks at once
    (no back-off), but the attempt's request is already out (CC1), so its cancel is broadcast (a
    failure of that cancel rejects nobody). A replication ends unknown, or in the violation. A
    renewal fails as `proto_db`'s ownership thread does (`_own_loop`): the ownership abandoned,
    its queue refused `'ending'`, no release, the node fenced. A failed held release is logged,
    as `proto_db` (3545). A failed cancel of the last lost attempt rejects the oldest waiter, as
    `proto_db`'s `_close_attempt` raises it to the driving caller; the cancel is broadcast
    already here, where `proto_db` raises before broadcasting it, and when it rejects the last
    waiter while the next attempt is open, that attempt is cancelled too (no requested term is
    left without its cancel). **A cancel failure that arrives after the acquisition ended is
    only logged.** In `proto_db` the driving caller raises inside `_close_attempt`, before it
    could open another attempt, so it never receives a permit for that acquisition. Here the
    own acceptor decides the cancel after it was sent, and the failure can come back after the
    next attempt has already won (or after every waiter left): the acquisition it belongs to
    is gone, and the waiter it would have been reported to now holds a permit of a valid term,
    so there is no caller left to raise it to. Cost: that waiter commits where `proto_db`'s
    caller would have seen the error; the error is still written to stderr, and nothing is
    unsafe (the cancel was broadcast, the won term is a regular one). An error while the effects
    of a decided step are performed (its state already published) fences the node whatever its
    class, where `proto_db` would leave the step half done: here a lost timer would strand a
    waiter; a replication whose root was sent then settles `#unknown`. Any other error fences the node, as
    `proto_db`'s lanes do; the acceptor reads the fence before each step (`proto_db`'s
    `_refusal` reads `_failure` at decision time), so a message queued before a dispatcher fence
    is never granted nor acknowledged ok. A peer's replication whose accepted append failed is decided again over the
    failed tier and refused with `ack(ok = false)` (`proto_db`'s behaviour); a grant whose promise
    append failed is never answered, as `proto_db`.
  - A fence settles a replication in flight `#unknown` (its root may have left the node) and
    rejects every other waiter with `PBUnexpectedError` (`'Node n is fenced after an internal
    failure: ...'`). A replication whose majority acknowledged a root that clashes (same label
    and epoch, another record) with the root the holder's acceptor reported accepted, or
    committed (`proto_db` `_observe_committed` compares with both, 1708 and 1725), is rejected `PBCorruptionError` (`'Protocol violation: ...'`), counted
    `replication_failures`, nothing learnt committed (`proto_db` `replicate`'s
    `except ProtoCorruptionError`, `test_x4_...`). `proto_db` raises it from its own acceptance
    or from `_observe_committed`; here the own acceptor refuses the sibling (D50, S3) and the
    holder compares when the majority is reached, so the replicator gets the violation, never an
    unknown outcome.
  - The attach of a tier follows `proto_db` `_attach_locked`: the tier attached already, or a
    tier whose `storage` is the same object as the attached tier's (`proto_db`
    `self._tier.storage is tier.storage`), is a no-op answering `true`; another is refused
    `PBValidationError` (`'This coordinator already serves another storage'`) before its roots
    are loaded. Two `PBFileStorage` objects over one directory are two storages, as two
    `FileStorage` objects are in `proto_db`. A second `PBSharedTier` of the same node over the
    same directory never reaches the attach: opening its acceptor log is `PBUserError` naming
    `cluster/<name>.roots.lock` (Review Focus 3). `_detach: aTier` (what `PBObjectSpace close`
    calls) follows `proto_db` `detach(tier)`: it detaches only that tier or one over its
    storage; the test-only `_detach` detaches whatever is attached.
  - An own acceptance queued in the acceptor's mailbox behind a detach and an attach is decided
    and logged on the new log, where `proto_db` refuses it (the tier changed under the
    replicate, ruling R55) and the replication ends unknown; the outcome reported is the
    majority's either way (`n1_a_holder_moved_to_another_disk_mid_commit...`, `n/a`).
  - `stop` finishes the acceptor step in progress; the steps queued behind it are dropped, as
    `proto_db`'s lanes return once the node is not running.
  - `stats` `'rejoining'` is derived from the published acceptor state (attached, no rejoined
    marker, healthy) rather than from a thread flag, so it turns `false`, and
    `'rejoin_blocked'` `nil`, once the tier failed or the node is fenced, where `proto_db` keeps
    `_rejoining` true (its rejoin thread stops; nothing completes the rejoin either way);
    `'persisting'` is `true` until the persister exists (Task 25); `'dispatch_seconds_max'` is
    the longest single dispatcher step and `'dispatch_slow'` counts the steps over 10 ms
    (`proto_db` `DISPATCH_SLOW`), both measured with `Time microsecondClockValue`.
  - The L17 refusal of a short `#startupGrace` states the durations in milliseconds, the unit of
    the options, where `proto_db` states seconds.
  - Before a tier is attached the acceptor is `PBAcceptorState config:detachedAt:`: requests are
    refused `no_storage` after `learner` (`proto_db` `_refusal`'s order, `fenced` aside: a
    fenced node sends nothing), counted `grants_refused_no_storage` for a peer; a plain query
    is answered `'unknown'`.
- **Commits through the coordinator (Task 23, `cluster/round.st`, `proto_db` `_run_round`,
  `_permit_round`, `Database.run`).**
  - The round runs on the space's round runner, an actor, as messages; `proto_db` runs it on the
    thread of the commit that leads the group (the runner thread waits on its own retry, so it
    leaves the kept permission in `group.kept`). Here the runner never waits: a held caller's
    retry is a later message, and `Database.run`'s caller is an object made for each `run:`
    (`proto_db` uses the thread id).
  - `stats` `'critical'` has two stages, `'build'` (validation, merge and path copy together)
    and `'replication'`; `proto_db` has four (`validation`, `replay`, `path_copy`,
    `replication`). `critical_commits` is the same count.
  - A replicate that fails with an error (`PBReplicateFailed`) is decided by the error's class,
    as `proto_db`'s `nothing_sent`: a conflict, validation (`PBClosedError` included) or user
    error sent nothing; any other error, a failed flush included, leaves the outcome unknown.
  - A permission that arrives after the round closed is ended `#none` at once; `proto_db`'s
    closing thread never asked for one.
  - rc4's R148 texts ('its kept permission is still being ended', '... s of it spent waiting
    for its kept permission to be ended') and its misuse error ('already holds a write
    permission') have no counterpart: the done of a permission and the next permit request are
    posted in that order into the one dispatcher mailbox, so a commit never meets a permission
    still being ended. Its wait counts inside the permit's own bound (the space's `lockTimeout`
    when one was given, else `acquireTimeout`, as rc4's), and the `PBTimeoutError` names that
    bound in milliseconds ('within 8000 ms'), never what is left of it (rc4 C1).
  - `'replication'` in `stats` `'critical'` runs from the send of the replicate to the settle of
    the commit on the runner (it includes the time the answer waits in the runner's mailbox);
    rc4 times the `replicate` call.
  - Whether an attempt of `run:` will retry is the attempt transaction's own (its commit entry);
    a commit made by another transaction inside the block does not inherit it, as every commit
    inside `fn` inherits rc4's thread-local `retry_left`.
  - A space closed while its replicate is in flight posts the permission's done `#unknown` at
    once, while the coordinator's replication may still be running; rc4's closing thread never
    ends a permission a runner is still replicating under. The owner forgets the permit on the
    done and abandons the term (safe); the replication then ends as any other.
  - Reads (Task 24, `space.st`). `proto_db`'s readers read the coordinator's `_committed`
    under its lock, which the commit thread sets before `commit()` returns. protoBaseST's
    committed knowledge is the acceptor's (an actor), so the readers' root is an Atom the
    acceptor publishes to, and the commit round publishes its root there too, before the commit
    settles (`_publishCommitted:`): the Atom keeps the higher root (`PBRootOrder`), so the
    acceptor's later publish of an older root never lowers it; only the acceptor's drop
    (`forceRejoin` on a survivor) and an attach (which resets it to the new log's committed root,
    as `proto_db`'s attach resets `_committed`) clear it. A recovery round publishes the committed
    roots it learnt there before it answers, as `proto_db`'s `recover_root` observes them under
    its lock before it returns. *Cost:* none; the readers see what `proto_db`'s do.
  - The confirmation's check (`needsConfirmation`) and its record that it started (`_confirmed`)
    are two steps in both: `proto_db` takes the coordinator's lock for each, protoBaseST reads the
    acceptor's published state and posts `_confirmed` to the dispatcher, which hands it to the
    acceptor. Two snapshots that pass the check before the record both confirm in either; the
    window here is wider by that hop. *Cost:* an extra empty round, never a weaker read.
- **The shared tier and cluster storage mode (Task 21, `cluster/tier.st`, `proto_db`
  `PlainTier`).**
  - Cluster mode is chosen when the storage opens (`PBFileStorage clusterPath:`, CC20), not
    inferred: `proto_db`'s `FileStorage` has no mode, and its `ObjectSpace` takes any storage
    with a coordinator. protoBaseST refuses `PBObjectSpace storage:` of a cluster-mode storage,
    `PBObjectSpace storage:coordinator:` of a plain one and `PBSharedTier storage:nodeId:` of a
    plain one (`PBValidationError`), and `PBFileStorage path:` keeps refusing a directory holding
    `cluster/` (`PBNotSupportedError`). In cluster mode `replaceRoot:` publishes only a SpaceRoot
    that carries a `cluster_term` (`PBValidationError`, nothing written), a check `proto_db`
    does not make: a plain commit through a cluster node's storage would publish a root the
    cluster's order cannot place. *Cost:* none for a cluster; a plain process must not open a
    node's directory, as before.
  - `persist:` (CC19) takes the root lock without waiting (`tryLockRoot`) and answers `#busy`
    when another holder has it; the root is read and compared under the lock, then published
    with `replaceRoot:` (storage epoch + 1). `proto_db` reads outside the lock and retries a
    lost compare-and-swap up to 100 times inside a waiting `publish_root`. Under the lock no
    lock-respecting writer can move the root between the read and the publish, so there is no
    retry loop: a `PBConflictError` (a writer that ignores the lock) is signalled to the
    caller. The persister reschedules a busy attempt (Task 25), so it never waits. `proto_db`
    also retries a `ProtoOutcomeUnknownError` (reading the root again decides) and raises
    `ProtoUnexpectedError` after 100 lost races; here neither exists: a file-system failure
    inside `replaceRoot:` is `PBUnexpectedError`, leaves the storage failed (every later write
    refused) and is signalled to the persister, and no re-read decides it.
  - `persist:` refuses (`PBValidationError`, nothing written, the lock released) a
    `PBLabeledRoot` whose label or epoch differs from the `cluster_term` or `cluster_epoch` of
    the SpaceRoot it points to (a protoBaseST addition; `proto_db` trusts the caller). Without
    it the persisted root would be ordered by one key and reported by `readPersisted` with
    another, which can look like the persisted root went backwards. *Cost:* one SpaceRoot read
    per persist.
  - `PBObjectSpace close` on a node whose coordinator is stopping closes the tier's log only
    once the stop has settled (`_detach:` chains on `stop`'s `Future`), so the acceptor step in
    progress has finished; `proto_db`'s `detach` takes the log lock instead.
  - A log holding entries of kind 5 or 6 (written by a node of a tiered storage) is refused
    `PBNotSupportedError` when the tier opens (CC15); `proto_db` `PlainTier` reads it.
  - The log name follows `proto_db` `_node_log` (CC21): an id outside `[A-Za-z0-9._-]{1,64}`
    is not refused, its file is `cluster/<lowercase hex of its UTF-8 bytes>.roots`. A storage
    without a directory (`proto_db`'s in-memory logs over `MemoryStorage`) does not exist here.
  - `canRead:` (the rejoin's probe of its adopted root) answers whether the storage can load the SpaceRoot
    record (a closed storage is `PBClosedError`, not false); `proto_db`'s `PlainTier` has no such method (the probe is a protoBaseST addition,
    see the rejoin entry above).
  - The ported power-loss check (`test_a_new_acceptor_log_and_its_directories_survive_a_power_loss`,
    kind `plain`) observes the directory syncs through the `PBAcceptorLog _syncDirectory:` seam
    and reloads the log; protoST cannot simulate a power loss. The `tiered` kind is not ported
    (DEPTH = 0).

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
  publisher backing off inside its actor (now removed, ruling R19). The caller's lock backoff
  that followed is gone too (cluster plan Task 22, CC10: the round runner retries with timers);
  what remains is the committing caller's single wait on its commit's `Future`, nested in
  `ensure:`, which blocks its worker while the worker still serves other actors. **Not reproduced with Futures settled by network
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
