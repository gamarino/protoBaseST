# Deviations and refusals

Where protoBaseST differs from `proto_db` at `v2.0.0rc4`, and everything it refuses. protoBaseST
follows rc4 at format 4 and protocol 14; rc4's format 5 (the runtime registry, decision D62) is
known and not adopted: it is refused (see [Reading](#reading)). Entries first written against an
earlier release candidate (`v2.0.0rc2` for the single process, `v2.0.0rc3` for parts of the
cluster) say so where the release matters.
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
[Indexed queries](#indexed-queries) |
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

- **Indexed collections are written, merged, queried and paged** (0.3.0, plan Tasks 4a to
  9). Every mutator maintains the collection's `PBEqualityIndex` and
  `PBRangeIndex` indexes in the same step, with the hook order of `proto_db`'s mutator, so one
  sequence of operations gives the same index nodes in both implementations
  (`tests/interop/index_ops_identical.sh`); a format-3 index is rebuilt before the first change;
  `addIndex:`, `removeIndex:` and `validate` are provided, and the index definitions are logged
  (`('@index_add' name index)`, `('@index_remove' name)`, never on `PBList`), so a blind write
  onto an indexed current merges as in `proto_db` (`tests/unit/idx_merge.st`,
  `tests/interop/index_both_directions.sh`, row 13 of `tests/interop/concurrency.sh`). What stays
  refused: a collection holding an index of a kind protoBaseST does not know is read only, a
  merge onto one included (`PBNotSupportedError` naming it; see the table below). A collection
  holding a `PBVectorIndex` is written and merged since the vectors phase's V5 (ruling IQ5a).
  `extend:` of nothing still answers the receiver, as `proto_db`'s. *Cost:* a merge onto an
  indexed current runs the index work and the extractors in the commit's build, at protoBaseST's
  index speed (bench M3 below). The term and expression language is provided (plan Task 5:
  `PBTerm`, `PBAnd`, `PBOr`, `PBNot`, `PBBlockPredicate`, `PBExpression compile:`): a condition
  is built, described and evaluated on one element. The planner (Task 7) and the query front end
  (Task 8: `PBField`, `PBQuery`) answer conditions with the collection's indexes, and pagers
  (Task 9: `pagerSize:`, `PBPager`) serve pages of one plan, by rank when it offers rank access.
- **`PBRepeatedKeysDictionary` is read only.** Its writes and merges are a non-goal. A new empty
  one is mergeable and its rebase answers `current` unchanged, as `proto_db`'s.
- **Immutability is by convention** (decision 3). No instance is frozen at run time: a method
  that assigns an instance variable after construction would compile. A test
  (`tests/unit/values_immutable.st`) scans for it. The runtime-only fields are the exceptions,
  none persisted: what a lazy load fills (the oid, the slots and the memo), the saved place, a
  keyed node's order key, an index's parsed key spec, each written once by a compare-and-swap
  from nil on its instance variable (plan Tasks 11 and 12), and the consumed mark of an
  operation log, an `Atom`.
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
  shared tier). `proto_db`'s "held retries" (an immediate retry without backoff under a kept
  permission, `permit_held`) are ported with the cluster round (Task 23). Mixed clusters of
  `proto_db` and protoBaseST nodes are a non-goal (see [Cluster mode](#cluster-mode)).
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
  v2.0.0rc3, which rc4 changes only in the root version, nothing at format 4 (cluster plan Task 22): one round takes every queued commit, saves each one's written
  atoms (a failure is that commit's alone, as each `proto_db` thread saves its own before it
  joins the group), holds the root lock once, reads the root once, builds each commit on the root
  the previous build saved (a build error is that commit's alone), and makes the last root
  durable with one flush and one publish; a failure of the lock, the root read, the flush or the
  publish reaches every built commit (each `wait` re-signals its own copy of the error, as
  `proto_db` raises a copy in each thread), and the step-8 outcome of a failed publish is the
  round's. A commit's own error, a build error included (an extractor's exception in a merge),
  also reaches its caller as a copy (`shallowCopy`: the same class, text and fields, not the same
  object, since a Future's `wait` re-signals a copy), where `proto_db` raises the object itself
  (`transactions.py:1121`). *Cost:* a caller that compares the exception it caught with `==`
  against one it kept (an extractor that records what it raised) finds them different; compare
  class and text. A commit alone in the queue runs exactly the single-commit protocol (the bytes of
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

- a collection holding an index of an unknown kind (read only, ruling IQ5a; a collection holding a
  vector index is written since the vectors phase's V5, `tests/interop/vector_ops_identical.sh`);
- `PBRepeatedKeysDictionary` writes (a non-goal);
- Python-only types such as `demo.erp.AuditNote`, which protoST reads as opaque atoms and never
  re-writes.

Hence the interop round trip compares dumps with `compare_dumps.py --exact` (no normalisation of
the opaque type), and `tests/interop/concurrency.sh` row 13 (a blind write onto an indexed root)
uses a copy of the conformance database in all four runs; since plan Task 4b it expects
`proto_db`'s merge from protoBaseST too. Likewise `st_random_ops` covers the four
collections with writes, and `PBCountedSet` since Task 22.

## Reading

- **Opaque atoms.** A record whose type has no registered class is a `PBOpaqueAtom` (D59). It
  answers `typeName`, `tag`, `at:` and `attributeNames`; every other message is
  `PBNotSupportedError` naming the type. A reference to it is written back byte for byte at the
  original pointer; no record of its type is written.
- **Indexes** are decoded and kept (`name`, `keySpec`, `hasMemberTokens`...). Not queried yet.
- **Format-3 collections** are read; a format-3 key-group index is rebuilt with format-4 tokens
  before the collection's first change (a read or a blind write keeps it), and `validate` reports
  a misfiled entry with `PBMisfiledError`, as `proto_db`'s. `rebuilt()` (the repair) is not
  provided. A stale index that must order format-3 zone datetimes (IANA zones, which have no order
  key here) makes the collection unwritable: its first change is `PBNotSupportedError` naming the
  zone.
- **`snapshot_ref` byte references, portable pager tokens and residency** are not provided (in-process
  pagers are, plan Task 9).
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

**In brief.** The entries after this list are the detail, rule by rule. What an operator must know
first:

- **Shared storage only (Phases A-C, design spec 8.4 Q1).** Every member opens the same
  `PBFileStorage` directory with `clusterPath:`, and keeps its acceptor log in
  `cluster/<id>.roots` inside it. `proto_db`'s tiered storage (local logs per node plus an object
  store, peer fetch, `warm`, log kinds 5 and 6) is Phase D, not ported: its options are refused
  (`PBNotSupportedError`, CC8) and so is a log written by a tiered node (CC15). The cluster
  protects commits from the failure of processes, not from the loss of the directory.
- **`flock` on network file systems.** The root lock (`space.lock`) and each acceptor log's lock
  are `flock`s, as `proto_db`'s. Members on several hosts need a shared file system whose `flock`
  is reliable across hosts; on one that silently grants a lock to two hosts, two processes can
  serve one acceptor log, which breaks the protocol's assumptions. Nothing here detects that.
  Members on one host are the tested deployment.
- **DEPTH = 0 (Q3).** One write permission at a time across the cluster. `proto_db`'s pipelined
  permits (DEPTH 1, D55, rules H1-H7) are not ported; a received permit naming a proposal
  (`after`) is held as uncertain (below). Throughput is bounded by one permission round trip plus
  the round's builds, its segment sync and its replication, whatever the number of members ([Performance](#cluster-mode-commits-per-second)).
- **The group bound (Q4, CC11, liveness only).** A round stops adding commits when the
  permission's time left falls below `sendReserve` plus the longest build of the round; the rest
  wait for the next permission. `proto_db` builds the whole batch and refuses it whole when the
  last build crosses the reserve.
- **HMAC frame authentication (Q5, CC4).** Optional (`#authKey`); with it the frames are not
  protocol 14 and cannot mix with `proto_db` nodes. Without it the bytes are protocol 14. Either
  way the transport is plaintext: run on a trusted network (entries below).
- **Each valid frame is delivered as it is read (CC5).** `proto_db` loses, with a bad frame, the
  other messages decoded from the same 64 KiB read; protoBaseST delivers them. The connection is
  dropped at the first invalid frame in both.
- **No node-id binding in the acceptor log (CC6).** Lesson L27 proposed recording the node id in
  the log; it needs a new entry kind, which would change the shared format, so it is not added.
  Over shared storage the file name `cluster/<name>.roots` binds the id. Copying one member's
  directory or log onto another member is forbidden, as in `proto_db`, and is not detected.
  Recorded as a proposal for `proto_db` ([decisions.md](decisions.md#proposals-to-proto_db)).
- **Message types never sent at DEPTH 0 (CC7).** `records`, `warm`, `store`, `propose`, `fetch`,
  `fetched`, `commit_query` and `commit_info` are decoded and validated like every type (an
  invalid one drops the connection), then ignored and counted in `stats` as
  `'ignored_messages'` (a `store` of another voter set counts `'config_mismatches'` only: the
  fingerprint is checked first, as in `proto_db`'s `_route`). `proto_db` handles these types; at
  DEPTH 0 over shared storage no protoBaseST member sends them. Not to be confused with
  `'messages_ignored'`, which counts messages whose sender is not another member.
- **About 16 members in practice.** Membership is static; `PBMembership` accepts at most 4096
  members (the rank's 12 bits). Every connection has its own reader actor and every peer its own
  sender actor, so a member of an N-member cluster runs about 2(N - 1) transport actors. "About
  16" is a planning estimate, **not measured**: the benchmark below runs 1 and 3 members.
- **A plain `proto_db` writer on a cluster space.** protoBaseST refuses to open a cluster
  directory without a coordinator (`PBFileStorage path:` refuses `cluster/`). `proto_db`'s
  `FileStorage` does not refuse it: a `proto_db` process that opens a member's directory without
  a coordinator can publish a root outside the cluster's order, which the next persisted cluster
  root replaces: its write is silently lost. Do not do it. Proposal Q7(a) asks `proto_db` to
  refuse it ([decisions.md](decisions.md#proposals-to-proto_db)).
- **Mixed clusters** of protoBaseST and `proto_db` nodes are a non-goal (design spec section 4).
  The on-disk format and, without a key, the frames are shared; behaviour across implementations
  is not tested. What is tested across implementations is the data: `proto_db` reads a space
  a protoBaseST cluster wrote, and the acceptor logs round-trip both ways (Task 26).

The detail:

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
  not a deviation from `proto_db` at `88ca21d`, and rc4 (`v2.0.0rc4`) ships it unchanged; the
  checklist is pinned to rc4 since Task 22a, its seven renewal back-off rows ported. The rejoin families' workarounds for the storm are gone: the `r78a`
  schedule no longer cuts the holder off before its timer resumes, and `lagged:` (1 ms links)
  is no longer applied (`tests/unit/_rejoin.st`); the acceptance families' guard that skipped a
  wrong rule's continuation is gone too. `AcceptFamilies idle:` (`tests/unit/_accept.st`) is
  kept, for another reason, a liveness property shared with `proto_db` (rc3 and `88ca21d`):
  committed knowledge of an acknowledged commit whose holder crashed before its done is learnt
  only by a later term's phase 1 or a recovery round a commit or a read asks for, never at
  quiescence, so its crashes fall between terms. Its companion `powerLossInTerm:` (Task 30)
  crashes inside a term and then commits once more, so a new term settles what the crash left,
  as `proto_db`'s power-loss tests keep their load running after the revive. A local commit that asks while its own node's
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
- **proto_db's cluster tests, ported or justified (Task 18, re-pinned to rc4 in Task 22a).**
  `tests/unit/cluster_checklist.tsv` gives each of the 298 test functions of `proto_db`
  `v2.0.0rc4`'s `tests/unit/test_cluster_*.py` a row: ported (the protoBaseST file and the
  check that covers it) or not applicable (33 tiered storage, 32 DEPTH = 1, 10 a Python-only API
  such as `FencingToken`, which the port does not have: the fencing token is the term). After
  Task 28, 223 rows are ported, 75 are n/a and none is deferred. `tests/unit/cluster_checklist.sh`
  checks the table against the tag (it needs the protoBase checkout, `PROTOBASE_REPO`); the final
  gate (Task 30) runs it with `CHECKLIST_FINAL=1`, which fails on any deferred row. *Cost:* none
  in the code. A ported row means a protoBaseST check of the same property, not the same test
  code: the port's checks are its own.
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
    `'persisting'` turns `false` when the persister of the node's space stops after an
    unexpected error (`_persistenceFailed:`, Task 25), and `'failure'` then names it, as
    `proto_db`'s; `'rejoining'` does not depend on it (`proto_db`'s does not either); `'dispatch_seconds_max'` is
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
  - **An entry's build error in a cluster round fails only that commit** (indexed queries
    ruling IQ1; the maintainer's decision of 2026-11-19). An error that one entry's build raises,
    of any class, even one that is not a `PBDBError` (an extractor's exception in a merge onto an
    indexed current), fails that commit alone, and the round builds the next entry
    (`PBCoordinatorCore >> roundBuildFailed:in:now:`). `proto_db` rc4's `_permit_round`
    (`transactions.py:1660-1717`) catches only `ProtoConflictError` and `ProtoDBError` per entry
    and fails the whole round on any other error. *Why:* the maintainer's decision, for one rule in
    every mode: rc4's standalone and group-commit round already fails only the commit whose build
    raised (`_standalone_round`, `transactions.py:1149-1157`, review M2), and the same program
    should not fail its neighbours' commits in a cluster only. It is safe: nothing of the round's own root is sent before its builds end; a re-commit, if any, has already committed
    (every entry's build comes before the round's replicate), so failing one entry sends nothing of
    it.
    Unchanged: a base read that failed with `PBUnexpectedError` after the permission expired is
    still a retryable conflict (R212), and the re-commit's error still ends the round. *Cost:* a
    commit whose round-mate's build failed with, say, a `ZeroDivide` commits here where `proto_db`
    rc4 would fail it with that error (`tests/unit/idx_merge_extractor.st` case (c),
    `tests/unit/cluster_round_rules.st` case 30).
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
  - The public reads (final review M2). `proto_db`'s `healthy`, `owner`, `cluster_size`,
    `voters`, `is_voter` and `majority` are `isHealthy`, `owner`, `clusterSize`, `voters`,
    `isVoter` and `majority`, and `persister.stats()` is the space's `persisterStats` (the
    persister belongs to the space here). Left out, each with its reason:
    `wait_committed_change` (protoBaseST's committed root is an Atom the acceptor publishes, with
    no version counter or condition to wait on; a reader polls `committedEpoch`, and `sync:` is
    the durability wait); the `persister` and `tier` objects (owned by the space; `_persister`
    and `_tier` stay private); `transport`, `lease_duration`, `acquire_timeout` and
    `restart_grace` (read from `config`: `leaseDuration`, `acquireTimeout`, and `leaseDuration +
    driftMargin`; the transport is an option, not state to read back); `known_root`,
    `accepted_root` and `committed_root` (`committedRoot` and `acceptorState`); and the commit
    path's members (`permit`, `finish`, `replicate`, `acquire`, `release`, `lease` and the
    others), which the commit round calls through private selectors (`_permit`, `_done:outcome:`,
    and so on) and an application never calls (chapter 14).
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
  - A persisted root read but not learnt (final review M5, `_committedRecord`). A read that
    knows no committed root, and whose recovery failed, reads the persisted root and has the
    acceptor learn it. Two things can stop the learn. The first is a fence that lands between
    the read and the learn: a fenced acceptor learns nothing (`acceptLearnCommitted:`), while
    `proto_db`'s `_observe_committed` does not check the fence and learns it. The second is a tier
    detached meanwhile: `proto_db`'s `current_root` then says nothing and answers `None`, the
    empty space. In both cases protoBaseST answers the persisted root it read, which is a
    committed root, and never the empty space. For the fence, this is what `proto_db` reads. For
    the detach, it differs from rc4: rc4 reads the empty space (`listDatabases` would answer
    `#()`, `openDatabase:` "does not exist"), which is a wrong state, not an older one. *Cost:*
    on a fenced node that learnt no root, every snapshot reads the storage root again.
  - A fenced node's recovery is refused at once (`PBUnexpectedError`). `proto_db`'s fenced node
    sends its query, gets no answer, and ends in `ProtoConflictError`. Either way the read falls
    back to the persisted root: `_committedRecord` treats the fenced refusal as a failed
    recovery. *Cost:* none (the fenced node answers sooner).
  - The confirmation's check (`needsConfirmation`) and its record that it started (`_confirmed`)
    are two steps in both: `proto_db` takes the coordinator's lock for each, protoBaseST reads the
    acceptor's published state and posts `_confirmed` to the dispatcher, which hands it to the
    acceptor. Two snapshots that pass the check before the record both confirm in either; the
    window here is wider by that hop. *Cost:* an extra empty round, never a weaker read.
- **The persister (Task 25, `cluster/persister.st`, `proto_db` `Persister` at v2.0.0rc4).**
  - Every storage write of the persister goes through the space's round runner
    (`PBRoundRunner >> persist:`), the actor that makes the commit round's `pushAtom:` and
    `flushSegment` on the same storage; `proto_db`'s persister thread calls `PlainTier.persist`
    itself, whose storage serialises writes with its own lock. protoBaseST's storage takes no
    lock to serialise its writes and its root lock is per storage object and not re-entrant
    (Task 21 review I1): run side by side, a persist refused inside a commit's write in progress
    would keep the root lock for good. *Cost:* a persist waits behind the commit work queued on
    the runner before it; commits never wait for a persist longer than one `persist:`.
  - The persister belongs to the space: `PBObjectSpace storage:coordinator:` starts it after the
    attach and `close` stops it before the detach (a write in flight finishes first). `proto_db`'s
    coordinator starts it in `attach` and stops it in `detach` and `stop`; here a coordinator
    stopped under an open space stops the persister at its next pass (its waiters then end
    `PBTimeoutError`, 'The persister stopped before the root was persisted', as `proto_db`'s).
  - "This node committed it" (`proto_db`'s `committed_root()` committer `== node_id`) is the
    readers' committed root being the highest root this node's commit round published at its
    commit point (`PBClusterCoordinator >> _committedHere:`); a drop or an attach forgets it, as
    `proto_db`'s `_committed_by` is replaced by the next root observed. *Cost:* none.
  - `#busy` (another holder has the root lock; `persist:` never waits) is counted `'roots_busy'`,
    a protoBaseST counter, and retried at the next pass, one `persistInterval` later; `proto_db`
    waits for the lock inside `publish_root`.
  - DEPTH = 0: nothing is shipped, verified, uploaded or released, and `check_backlog` has no
    counterpart, as `proto_db`'s `PlainTier` answers each of them with a no-op (`_persistable` is
    true for a tier that is not a cluster tier). The persister never calls `flushLocal`, as
    `proto_db`'s does not: the commit round flushes before its replicate (L11).
  - `sync:` takes milliseconds (a SmallInteger >= 0, or `nil` for no deadline), `proto_db`'s
    `sync` seconds; `PBDatabase >> sync:` is the space's. The persister's counters are its own
    (`aSpace persisterStats`: cycles, roots_written, roots_behind, roots_busy, errors,
    refreshes, persisted_epoch, last_error), as `proto_db`'s `persister.stats()`. The lag is
    measured on the node's clock (the `#clock` option's when set), `proto_db`'s on
    `time.monotonic`. An unexpected error is written to stderr and kept, not re-raised: no
    thread dies with it.
  - A refresh hands the root it read to the acceptor (`_learnPersisted:from:`, a message never
    waited) and records it persisted at once, so a waiter may return a moment before the
    readers' committed root shows that root; `proto_db` does both under its lock. *Cost:* none
    for `sync:`, which promises durability, not visibility.
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
    caller. The persister reschedules a busy attempt (Task 25), so it never waits. The
    comparison has rc4's shape (delta C4): the storage's root makes the persist a no-op when it
    orders after the new one, or is the same root at a version at or above the new one's (the
    version is outside the order of roots), and `readPersisted` keeps the version read; at
    format 4 every root is version 4, so this is the old comparison. `proto_db`
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

## Indexed queries

> **0.3.0.** These are the differences from `proto_db` of the
> [indexed-queries spec](superpowers/specs/2026-11-18-indexed-queries-design.md), as shipped; the
> chapters ([17](tutorial/17-indexes.md), [18](tutorial/18-queries-and-plans.md),
> [19](tutorial/19-ordered-reads-and-pages.md)) and the guide ([queries.md](queries.md)) link
> here. The entry "Indexed collections are written, merged, queried and paged" above says what
> the collections do. Every row is in force.

| What | Difference from `proto_db` | Why | Cost |
|---|---|---|---|
| Opaque predicates in `explain` | A block condition is the node `BlockFilter` with `description`, where `proto_db` has `PythonFilter` (call IC6). | The node runs a protoST block; naming it after Python would mislead. | A one-name difference in `explain`; the query vectors hold no opaque predicate. |
| Equality on the field builder | `eq:` and `ne:` build `==` and `!=`; `=` is not overridden on `PBField` (IC4, ruling IQ2). | `=` must stay an equality for collections and tests. | Less like Python's `F.city == "Oslo"`; `aField = v` answers a Boolean, which `where:` refuses. |
| Index constructors | `name:keySpec:` takes a `PBKeySpec` only (a String is `PBValidationError`); one path is `name:path:` (controller ruling CR3). `proto_db`'s `KeyGroupIndex(name, key_spec)` accepts a `KeySpec` or a str path. | One argument, one type: a keyword selector names the convenience instead of overloading the argument. | A path is written `name: 'by_city' path: 'city'`, not `name: 'by_city' keySpec: 'city'`. |
| Extractor blocks | `registerExtractor:block:version:` takes a `BlockClosure` only (anything else is `PBValidationError`); `proto_db`'s `register_extractor` takes any callable. | An extractor is `[:element \| key]`; one type keeps the identity test (`==`, `proto_db`'s `is`) and the purity contract simple. | An object that answers `value:` must be wrapped in a block. |
| `isExtractorRegistered:` | A protoBaseST addition: `proto_db` has no such function (its programs call `extractor_version` and catch the error). | Asking needs no exception handler. | None: one more message. |
| Projection | `project:` and `collect:`; `PBQuery` has **no** `select:` (ruling IQ2). | Smalltalk's `select:` filters; `proto_db`'s `select` projects, and would read backwards. | A name to learn. |
| Selection blocks | Not in the first release (ruling IQ2): a block condition is opaque and never uses an index. | Translating a block by running it on a recording object fails silently (`30 < (p at: 'age')`, inlined `ifTrue:` and `==`, methods of the element). | Index-using conditions are written with `PBField`. |
| Plan choice on near ties (R2) | The descent term `log2 (G + 2)` and a sort's `n log2 n` are computed by `PBCost class >> log2:` (`src/protobase/plans.st`, the one place a logarithm is computed, plan call IP7) as `ln x / ln 2` (protoST has no `log2`; ruling IQ4: protoST is not changed), which can differ from C's `log2` in the last bit. Two candidates whose costs are within a relative 1e-12 may be ranked differently: the same answer by another plan. | No protoST change for plan parity (IQ4). | The query vectors (`tests/conformance/queries.st`) report such a plan difference by name and do not fail on it; it counts as a near tie only when the choice differs (the node and index names) and the root costs agree within plan call IP8; any other plan difference, and every result difference, fails. Measured at Task 7: 0 near ties in the 314 recorded queries, every plan node for node and cost for cost `proto_db`'s. **Vector plans (DV6; vectors V6, V7):** the hnsw estimate's descent `log2 (members + 2)` is `PBCost class >> log2:` too (`vector_backends.py:815-821`), so an hnsw candidate can rank otherwise on a near tie in the same way; the vector query cases (vectors V7, 101 of the 415 recorded queries, 16 over an hnsw index, 13 of them planned and their execution refused, DV1) have 0 near ties, every vector plan node for node and cost for cost within IP8 `proto_db`'s. |
| Unknown index kinds (Task 4a; narrowed by vectors V5) | A collection holding an index of a kind protoBaseST does not know (an opaque atom, such as a custom `proto_db` index kind) stays read only: every change and every merge onto it is `PBNotSupportedError` naming it (IC2, ruling IQ5 as narrowed by IQ5a). A collection holding a `PBVectorIndex` is not refused since V5: its mutators and merges maintain it as `proto_db`'s do (Addendum V, 2.10). | Maintaining the other indexes but not that one would write a stale index, and an unknown kind cannot be maintained. | Such a collection is changed from Python only. |
| Python's own errors (DV7; vectors V1, V2, V3, V6) | Where `proto_db` fails with an exception Python raises itself, not a `ProtoError`, protoBaseST refuses at the same call, and at the same point of its checks, with `PBValidationError` carrying CPython's message. In force: (a) an `ip` or cosine score whose exact sum overflows (`OverflowError`, `vector_backends.py:128`, `136`; `PBVectorMath`, V1), and so, since V6, the execution of a search plan or a `nearOracle:...` that scores such a vector, when it is scored (the IVF probe count and the ranking score each entry they reach; `PBVectorMath` computes every score of a search); (b) a signalling-NaN `Decimal` as a vector component of a stored element, in `withAdded:`, `withRemoved:`, `build:` and `validate:` ("cannot convert signaling NaN to float", the `ValueError` of `float()` in `canonical_vector`; V3; a component that already made the key invalid, a Boolean before it, masks it as in Python; `nearOracle:...` too, since V6, as `near_oracle`'s `canonical_vector`); (c) a signalling-NaN `Decimal` as a `PBNearQuery` component or threshold ("cannot convert signaling NaN to float", `ValueError`, `terms.py:93`; V2); (d) an Integer beyond the Float range as a `PBNearQuery` component or threshold ("int too large to convert to float", the `OverflowError` of `math.isfinite`, `terms.py:93`; V2); (f) a metric Python cannot hash, such as a list (the `TypeError` of `metric not in NEAR_METRICS`, `terms.py:123`; V2), refused with `proto_db`'s metric sentence, since CPython's ("unhashable type: 'list'") names a Python type. (e) an Integer `retrain_growth` beyond the Float range ("int too large to convert to float", the `OverflowError` of `math.isfinite` in `_growth`, `vector_backends.py:320`; V3, checked by `tests/unit/vec_index.st`). Filing an element with a signalling-NaN component under `invalid` would write a space whose `validate` crashes in `proto_db`, so it is refused. The term vector records `proto_db`'s class for (c), (d) and (f) (`tests/interop/py_term_cases.py`, cases named DV7). | The host's exception classes; "refuse, never diverge": the operation fails at the same point in both, and nothing is written. | Only the class differs (and, for (f), the text). |
| hnsw search (DV1; vectors V6, ruling VQ1) | An `'hnsw'` index is maintained, merged, validated, explained, estimated and planned as `proto_db`'s, but the execution of its plan (alone, under a `PBVectorSearch`, or restricted to a condition) is `PBNotSupportedError` naming the index, at the first execution and never at planning: `proto_db` answers it when `hnswlib` is installed and refuses it the same way, at the same moment, when it is not (`vector_backends.py:290-302`; `tests/unit/test_vector_index.py:520-531`). | The graph is hnswlib's (native C++, built per process, `deterministic = False`, `vector_backends.py:755`): it is not part of the format, and `proto_db` does not promise the same graph twice. | A program querying an hnsw index from protoST gets an error; the index can still be changed and merged. Checked by `tests/unit/vec_plans.st`. |
| The text of the hnsw refusal (DV8; vectors V6) | "Index 'v' (VectorIndex on vec): the 'hnsw' vector backend needs hnswlib, which protoST cannot load; use the 'exact' or 'ivf_flat' backend", where `proto_db` says to `pip install hnswlib` and warns about free-threaded CPython (`vector_backends.py:298-301`). Every other text of the vector port is `proto_db`'s. | The advice would be wrong in protoST. | Text only. |
| The exact backend's `numpy` (DV2; vectors V3, V6) | `'numpy'` is validated, kept and written as `proto_db`'s, and has no effect: an exact search scores every member exactly (`PBVectorMath`), where `proto_db` with numpy screens candidates in float64 and re-scores them exactly (`vector_backends.py:22-27`, `433-439`). | The screening is an optimisation whose result is, by construction, the exact answer. | None on answers (both modes of `proto_db` give VB1's checksums); only speed. |
| No derived-structure cache (DV4; vectors V6) | A search reads the version's store tree itself: `proto_db` caches, per index version, a flat snapshot (exact), the grouped lists (ivf_flat) and the hnsw graph in a process-wide `DERIVED` cache (`vector_backends.py:200-272`). protoBaseST has none: an exact search walks the store; an ivf_flat search reads only the lists it reaches in probe order, each by a key range of the store tree bounded on the list number (an Integer compare), and skips an empty one as it reaches it (`proto_db` filters the probe order against its cached lists first: the same lists are probed). | No process-wide mutable state in the Smalltalk layer (spec 5.1); the tree already gives per-list access. | No first-query build cost and nothing to release when a space closes; every exact search re-reads the tree (bench VB1 has the first query and the repeated ones). `test_closing_a_space_releases_its_derived_vector_structures` is n/a. |
| IVF training (DV3; vectors V4) | An `'ivf_flat'` index is trained by `proto_db`'s pure-Python k-means (`vector_backends.py:527-563`, `644-661`), operation for operation: the vectors sorted by their big-endian IEEE bytes, normalised for cosine, the initial centroids at `random.Random(seed).sample(range(n), nlist)` (CPython's Mersenne Twister, ported), Lloyd iterations whose distances sum `(a - b) ** 2` terms, ties to the lowest list, sums added in data order (on protoST 0.16.0 each distance is one call of `Float fsumOfPowSquaredDifferences:with:`, behind its own feature probe, bit for bit the Smalltalk loop of `raisedTo: 2` and `sumNonNegative:`). `proto_db` trains with numpy instead when numpy is importable (`531-543`). CPython's `float ** 2` is the C library's `pow`, which is not correctly rounded (it differs from `(a - b) * (a - b)` on half-way squares, Addendum V 2.5); protoBaseST squares with `raisedTo: 2`, the same `pow`, and sums centroids with plain `+` (on protoST 0.15.0 only the correctly rounded sums, the distances' `_sum_nonnegative` and the cosine normalisation's norm, run in protoST's fsum primitive, bit for bit the Smalltalk kernel's; the squares stay `raisedTo: 2`), so its centroids and lists equal those of `proto_db` without numpy byte for byte, on the same host's libm (CPython 3.14 and glibc 2.43 on the reference host: `tests/interop/vector_index_identical.sh`, every training of four growth histories crossing `nlist` and `retrain_growth`; `tests/unit/vec_ivf.st`, a subnormal-square and a half-way case). **The libm note:** the centroids of `proto_db`'s pure path are a function of the host's `pow`; another libm (musl, Apple's, Microsoft's) may round some squares differently, for `proto_db` against itself as for protoBaseST, and a libm that set `ERANGE` on a subnormal square would make CPython's `**` raise `OverflowError`, which `_sum_nonnegative` turns into an infinite distance, where protoST's `raisedTo:` answers the subnormal: training would not fail on either side, but another centroid could be nearest, so the centroids would differ (glibc does not set it: 300,000 such squares raised nothing). Identity is claimed and tested on one host, both sides on its libm (RV7). **Two differences in how the square is reached, neither changing a byte:** (1) an overflowing square makes CPython's `**` raise `OverflowError` inside `fsum`, which `_sum_nonnegative` answers as an infinite distance; protoST's `raisedTo: 2` and the 0.16.0 primitive answer an infinite term, and the msum of an infinite term among finite ones is infinity, so the distance is infinite in both. That needs no term to be a NaN, and none can be: a canonical vector is finite with a finite squared norm (`canonical_vector`), and a centroid is a mean of such vectors, so every difference is finite or infinite, never a NaN (`tests/unit/vec_math.st` 16 pins an overflowing square and an overflowing sum on both paths); (2) CPython's `float_pow` squares the absolute value of a negative base, while `raisedTo: 2` and the primitive pass the signed difference to `pow(d, 2.0)`; glibc's `pow` with exponent 2 depends only on the magnitude, so the bytes are the same (`tests/unit/vec_math.st` 10 and 16 square a half-way difference of either sign). **Platforms:** protoST's deviation D58 (0.16.0) records that MSVC's `pow(x, 2.0)` rounds some half-way squares differently from glibc's, for CPython there as well; protoBaseST's tests pin k-means and pow-square bytes computed by CPython on glibc, so they hold on that libm only. protoBaseST has no Windows CI; on another libm those pinned bytes are expected to differ in the last bit, not the two paths from each other. | Only the pure path is specified operation by operation; numpy's results depend on its BLAS, and the format leaves the centroids to the writer (`format-spec.rst:65`, `1448-1456`). | On one stored database both answer identically: list numbers, probes and rankings are computed from the stored centroids, whoever trained them, and `validate:` accepts either side's index. What differs is the centroids after a (re)training of the same history: protoBaseST's may differ in the last bits from those of `proto_db` with numpy installed. |
| Symbols in `near[]` (vectors V2) | A Symbol is accepted wherever a `near[]` query takes a String: as its metric (`#l2`) and as a key of the mapping form (`#vector -> ...`). Python has no Symbols, and `proto_db` takes a `str` only. | In protoST a Symbol is a String (`#l2 isSymbol` answers false, its class is `String`), so the two cannot be told apart, and refusing one would refuse the other. | None: `#l2` names the metric `'l2'`, as the String does. |
| Atoms and instant-form IANA datetimes in `describe` (Task 5) and in the vector port's messages (vectors V2, V3) | `describe` (so `explain`) renders an atom as `<type name oid=...>`, and so do the texts of `PBNearQuery`, `PBVectorBackend` and `PBVectorIndex` that quote a value (one helper, `PBCodec _pyRepr:`, renders every value they quote: `withRemoved:` of a record the index does not hold, a tampered element in `validate:`) and an instant-form datetime in an IANA zone by its `printString`; `proto_db`'s `display_value` prints Python's `repr`: a record's fields (`DBObject(r=1)`), a collection's count, a stub's storage pointer (`<type stub at ...>`), a zone datetime's wall clock. Every other value is rendered as Python renders it, checked by `tests/unit/qry_terms.st`: against `proto_db` for the case operands (numbers, `Decimal('1.50')`, `inf`, strings, `b'\x00'`, dates, naive and fixed-offset datetimes, times, timedeltas, UUIDs, tuples), and against CPython's text for the rest (`Decimal('Infinity')`, `Decimal('NaN')` and the other specials, named offsets, `fold=1`, a time or a format-3 datetime in an IANA zone, `zoneinfo.ZoneInfo(key='Europe/Rome')`, `MutableObject('cell')`, maps as `{'@dict': ...}`). | Python's `repr` of a record walks its fields with Python's rules; an instant-form datetime holds only its UTC instant, and its wall clock in the zone needs a time-zone database (design 4.3). A time and a format-3 datetime keep their wall clock, so they are rendered. | The `explain` of a term whose operand is an atom, or of a key that is an instant-form zone datetime, differs in that one value, and so does a vector refusal that quotes a record (`does not hold <proto_db.core.dbobject.DBObject oid=...>` where `proto_db` says `does not hold DBObject(vec=(1.0, 0.0))`); results do not. |
| `in` over a `Set` (Task 5) | A protoST `Set` keeps `true` and `1` as two operands; a Python `set` holds one of them, since `True == 1` there. Both sort their operands by order key. | The difference is the host's set, not the term: `PBTerm` keeps what it is given, as `proto_db`'s `Term` does. | `in: (Set withAll: { true. 1 })` also matches 1, where `{True, 1}` in Python matches only `True`; a sequence (an `Array`) is the same in both. |
| Block predicates (Task 5; DV5, vectors V7) | `PBBlockPredicate` (`proto_db`'s `PythonPredicate`) describes itself as `{ 'block' -> description }`, where `proto_db` writes `{'python': description}`; it takes a block of one argument (`proto_db`: any callable). Since the vectors phase's V7 a `VectorSearch`'s `'where'` can hold one: `near(k)` with a block given to the leading `where:` steps (ruling R27) puts the block into the search's predicate, and its `explain` describes it so (DV5). A block's description is the one it was given (`'block'` for a `where:` block), where `proto_db` describes a lambda by its qualified name, file and line. | Named after the language that runs it, as `BlockFilter` (call IC6). | A one-key difference in the description of a condition holding a block, and so in a `VectorSearch`'s `'where'`; the query vectors hold none. |
| Terms quoted in refusal texts (Task 5; vectors V2, V7) | A refusal that quotes a term or a near query (the planner's `near[]` refusals, a negated `near[]`, `where:`'s `near[]` inside an OR or a NOT holding a block, a `PBFilter` over `near[]`) quotes its `printString`, `PBTerm('vec', 'near[]', PBNearQuery(vector=(1.0, 0.0), k=3, threshold=None, metric=None))`, where `proto_db` quotes its dataclass repr, `Term(path='vec', op='near[]', value=NearQuery(...))`; the values inside are Python's repr in both (`PBCodec _pyRepr:`), and the rest of each text is `proto_db`'s. | The classes are protoBaseST's (`PBTerm`, `PBNearQuery`), and a term prints as it is built. | Only the quoted term's class names and field labels differ; `tests/conformance/queries.st` compares the 21 planning refusals of the query vectors text for text, each term written back as protoBaseST prints it. |
| The 0.1 list syntax (Task 5) | `PBExpression compile:` takes an `Array`, an `OrderedCollection` or a `PBFrozenList` as a list (`proto_db`: a Python `list`); a `PBTuple` is refused, as a Python tuple is. | A list in protoST is any of the three, and a decoded MessagePack list is a `PBFrozenList`. | None. |
| Lists in `explain` (Task 6) | Every list in an `explain` (`'indexes'`, `'children'`, `'keys'`, the operands of a term) is a `PBFrozenList`, where `proto_db` answers Python lists and tuples. | A decoded MessagePack list is a `PBFrozenList`, so an `explain` compares with `proto_db`'s as decoded, and `PBNotation describe:` prints it (it cannot print an `Array`). | `at:` and `do:` work; `first` is spelled `asArray first`. |
| Blocks in `explain` (Task 6) | A `PBSortKey` or `PBProject` block is described by its description, `'block'` by default (`key:descending:description:`, `source:fields:description:`); `proto_db` describes a callable by its `__qualname__`. | A protoST block has no qualified name; the caller names it. | The `'key'` or `'function'` of a block differs; no vector holds one. |
| Atom operands in an index plan's `explain` (Task 6) | The `'term'` of an index plan whose operand is an atom is rendered by `describe` (the Task 5 row above); everything else of that `explain`, and its estimate, equals `proto_db`'s (checked for every single-term case of the conformance vector by `tests/unit/qry_index_plans.st`). | As the Task 5 row. | As the Task 5 row. |
| Ordered index plans (Task 6; key check order, Task 7) | `orderedPlan: aKey descending: aBoolean` takes the key to order by and checks it as `plans.py`'s `ordered_index_scan` does, in its order: the key (a `PBKeySpec`, or a term path through `PBKeySpec forTermPath:`, `PBValidationError` for anything else), then the direction (`PBValidationError` unless a Boolean), then `supportsOrder:` (`PBNotSupportedError` for another key); `proto_db`'s `ordered_plan(descending)` takes the direction only, and `ordered_index_scan` checks the key. | One message carries both checks of `proto_db`'s pair, so no caller can ask an index for an order it does not have. | One argument more; its refusal is `ordered_index_scan`'s sentence ("Index 'n' cannot iterate in the order of k") for every kind, `base.py`'s "does not provide ordered iteration" having no entry point here. |
| `windowFrom:to:` (Task 6) | Always answers an `Array`: by rank when the plan offers rank access, otherwise read through `do:` and stopped after the window. `proto_db`'s `window(start, stop)` answers `None` without rank access; `byRank` answers whether it does here. | A caller asking for rows wants rows; whether they were sought is a separate question. | None for results; a caller that needs the cost bound asks `byRank`. |
| The count node (Task 6) | `Count` is built by `PBCountPlan source:`; the class `PBCount` is the cluster coordinator's counter effect (0.2.0). | protoST classes share one namespace. | A name to learn: `explain` still says `'Count'`. |
| Pagers (Task 9) | In-process only: no portable token, no `resumePager:` (ruling IQ3). The pager's `explain` has no `'portable'` key, which `proto_db`'s `Pager.explain` has (`pager.py:221-224`); a pager here is never portable (ruling CR7). | The token's plan digest is over Python's `repr` of the plan, which protoST cannot reproduce byte for byte (spec 3.2; a portable digest is proposal IQ7, not sent). | A page sequence cannot be resumed by another process or language. |
| A pager's materialised result (Task 9) | A pager whose plan has no rank access runs the plan when a page or `rows` first needs it and keeps the result in an `Atom` set once from nil; two actors asking at the same moment may both run the plan, and every page is then served from the one result installed. `proto_db`'s `Pager._materialized` takes a `threading.Lock`, so it runs the plan once; it also accepts a `cache=` (the query result cache), deferred here (row "Deferred"). | No lock is held across allocation (Global Constraints); the plan reads immutable versions, so both runs answer the same rows. | Under a race on the first page, the plan's work is done twice, once wasted; the pages are the same. |
| `pagerSize:` (Task 9) | `aQuery pagerSize: n` is `proto_db`'s `Queryable.pager(n)`; `PBPager on: aSource pageSize: n` its `Pager(source, n)`, with the same sources (a plan, a query, a collection) and the same refusals (a page size an Integer ≥ 1, a page number an Integer ≥ 0, `PBValidationError` for `ProtoValidationError`). | A keyword selector names its argument. | None. |
| `where:` and the list syntax (Task 8) | `where:` takes a `PBExpression` or a one-argument block only (ruling CR6); the 0.1 list syntax is `PBExpression compile:`'s (and `PBPlanner`'s), so `q where: #('city' '==' 'Oslo')` is `PBValidationError` with the text `where: expects a PBExpression or a one-argument block, got a Array`. `proto_db`'s `Queryable.where` accepts a list too (`test_where_accepts_expressions_and_the_list_syntax`). | An Array is also a Smalltalk collection value: one way in keeps the refusal of a Boolean (`aField = v`) exact, and the list syntax stays one message away. | `where: (PBExpression compile: aList)`. |
| Single-value projection (Task 8) | `project:` always answers maps (a `PBFrozenDict` per row), from an Array of paths or `PBField`s or a map of output names; `proto_db`'s `select("name")` answers the bare values. A single value is `collect: [:e \| e at: 'name']`. | `project:` has one result shape; a block names a computed answer. | One message more for a bare value. |
| Query sources (Task 8) | `PBQuery from:` takes a `PBIndexedCollection`, a `PBQueryPlan` or a `PBQuery` (answered as is); a protoST collection (an `Array`, an `OrderedCollection`) is `PBValidationError`. `proto_db`'s `from_collection` also takes any iterable, through `ValuesScan` (deferred, row below). | `ValuesScan` is deferred (ruling IQ3). | Host collections are filtered with Smalltalk's own `select:`. |
| First of nothing (Task 8) | `first` of an empty query is `PBUserError` ("first of an empty query; use firstOrNil when no row is expected"); `proto_db` raises `ProtoUserError` too, with its own text. | The hierarchy maps one to one; the text names the protoST message. | None. |
| Benchmark sizes (Task 8) | Bench Q1 measures 10^2 to 10^4 records by default, not the spec's 10^2 to 10^5 (spec 7.3); Q5 (Task 9) measures 2000 and 10^4. | At Task 8 a 10^5 process with only the one index Q1 uses took 336 s and peaked at 5.4 GB in protoST (the budget is about 5 GB), and a run needs ten per size ([Q1-Q4](#q1-q4-queries-indexed-against-a-forced-scan)). Since the atom weight work (Tasks 11 and 12) one run at 10^5 is feasible: at Task 10 both implementations' index and scan units together took 6 minutes and verified ([the final comparison](#the-final-comparison-plan-task-10)); five interleaved runs would add about half an hour to Q1. | The default largest size is 10^4; `QUERY_Q1_SIZES` adds 10^5, measured once at Task 10. |
| Deferred | No query result cache, and so no `extractor_generation` (the registration generation that keys it); no `GroupBy`, `Agg`, `Join`, `Unnest` (`select_many`) or `ValuesScan`; no computed values, `startswith` / `endswith` or field-to-field comparisons; no collection `rebuilt` (misfiled format-3 repair) (ruling IQ3, spec 3.2). | Each is either not portable today or not an optimisation; a block condition covers computed values meanwhile. | Programs that need them wait, or use a block. |

Worth knowing: an extractor runs inside the commit when a blind write is merged onto a collection
with an extractor index, and an exception it raises passes through unwrapped and fails only that
commit, standalone, in a group commit and in a cluster round (ruling IQ1; plan call IP2). That is
`proto_db`'s rule standalone and in a group commit; in a cluster round it is a deviation by the
maintainer's decision of 2026-11-19 (see "Cluster mode": rc4 fails the whole round), and the
exception reaches the caller as a copy (see "Group commit" above).
Purity is a documented contract ([queries.md](queries.md#extractors-and-their-purity-contract)).

## Errors and messages

- The error classes mirror `proto_db/errors.py` with `PB` for `Proto`. `proto_db`'s extra classes
  that a prototype of this size never raises (`StalePager`, `NotAuthorized`, `BacklogFull`,
  `WriteRefused`) are omitted; `PBMisfiledError` exists (indexed queries, 0.3.0). `PBDBError` has no `code` API yet. `PBReferenceError`
  exists.
- Error texts quote names as Python's `repr` does (`PBCodec repr:`). One known imperfection:
  `repr:` leaves non-printable code points at or above U+0100 unescaped, where Python escapes
  them. It affects error text only.
- `PBTimeoutError` is not protoST's `TimeoutError`.
- Key specs and the extractor registry (`PBKeySpec`) speak protoST's nouns where `proto_db`'s
  messages speak Python's: "String" for str, "nil" for None, "a block" for a function, "PBKeySpec
  element takes no argument" for "KeySpec.element() takes no argument". The text for an
  unregistered extractor names protoBaseST's remedy, "call PBKeySpec registerExtractor: 'x' block:
  aBlock version: aStringOrNil", where `proto_db` says `register_extractor('x', fn)`. A path or
  extractor name holding a lone surrogate is refused with the codec's own text (`PBCodec`, "a String
  holding the lone surrogate U+... cannot be stored"), not with `check_text`'s sentence.
- Terms and expressions (`PBTerm`, `PBExpression compile:`) keep `proto_db`'s sentences and positions
  (counted from 0) with protoST's names: "PBAnd operands must be PBExpression instances ... use
  PBExpression compile: for the list syntax", an `in` operand "needs a list, tuple or set of values
  (an Array, an OrderedCollection, a PBFrozenList, a PBTuple or a Set)". The list of operators in
  "Unknown operator" is `proto_db`'s, `'near[]'` included. The `near[]` texts (`PBNearQuery`, the
  mapping form, the 0.1 list form, `PBFilter`, `normalize:`) are `proto_db`'s word for word, its
  Python nouns included ("k must be an int >= 1", "or None"), as the reference promises; the value
  they quote is protoST's (`PBKeySpec _repr:`: `true`, `#(1 2)`), except the keys of a refused
  mapping, which are listed as Python's `str` renders them (`'None'`, `'1e+16'`, `"b'\x01'"`,
  `"(1, 't')"`), so that text is `proto_db`'s whole. Where `proto_db` fails with one of Python's
  own errors, the text is CPython's (DV7, row "Python's own errors" above).

## Performance

The prototype need not be fast, and it is not. This is where the figures are recorded,
with how they were measured; the documents that quote one (the tutorial's cluster chapters) link
here.

The single-process figures below ([AVL operations](#avl-operations),
[Commits per second](#commits-per-second)) were measured 2026-11-13 on the same machine, at a load
average of about 9 to 14 (other work was running), so they are indicative only; instruction counts hold better than wall
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

### Cluster mode: commits per second

`bench/run_cluster.sh` (`RUNS=5`, interleaved, `CLUSTER_SCALE=1`: 120 transactions per run, split
evenly over the members). **Indicative only.** Measured 2026-11-16 on an AMD Ryzen 5 5500U (6
cores, 12 threads, Linux 7.0.0), protoST 0.12.0 (`build_rel0100`, used as built), protoBaseST at
`f5ec4b2` (cluster plan Task 29, fix round 1); the run directories on ZFS (`sync=standard`, lz4),
`fsync` durability. The machine ran nothing else heavy; the desktop's own load average was 2.9
before and 5.7 after. Each member is a protost process of its own on 127.0.0.1 with `proto_db`'s
default options (a 2000 ms lease: belief 667 ms, send reserve 167 ms). Every run self-reports:
each process counts the transactions it committed (one per `run:` that returned normally), a
verifier reads the space afterwards (in a cluster: member n0, after a read barrier, through the
cluster) and compares a checksum, and the runner refuses a run whose members' commits do not add up
to the run's total, whose verifier counts another number, or whose coordinators counted another
number of commits (`critical_commits`). All 30 runs passed. Two hand mutants were refused: a member
that left one commit uncounted (the members' sum 119, not 120) and a member that skipped one commit
(the verifier's checksum).

- **tiny**: one writer per process; each member writes its own root, one new key per transaction.
  No two transactions conflict on data, but every one needs a write permission.
- **conc-hot**: four writers (actors) per process, every writer of every member incrementing one
  key of one shared root: read-modify-write, conflicts retried by `run:`.

Commits per second from the minimum / median wall time (the first process's start to the last
one's end). Per commit, the medians of the runs, in milliseconds: *save*, the root-independent work
(the commit's atoms saved before the permission is asked, design spec 7.2), timed inside one
message of the space's round runner; *build*, the root-dependent work under the permission
(validation, merge, path copy, the new root saved); *replication*, from the replicate's send to the
commit settled (the acceptors' synced appends and the acknowledgements). Step 4 of the commit path,
the one sync of the shared segment before the replicate, is in no column:

| Profile | Mode | Commits/s | Retries (min-max) | Save | Build | Replication | Reserve refusals (5 runs) |
|---|---|---|---|---|---|---|---|
| tiny | standalone | 46.3 / 44.8 | 0 | | | | |
| tiny | 1 member | 27.8 / 25.7 | 0 | 7.3 | 7.4 | 9.3 | 0 |
| tiny | 3 members | 25.9 / 23.5 | 0-2 | 6.3 | 18.0 | 11.8 | 2 |
| conc-hot | standalone | 51.3 / 46.4 | 86-106 | | | | |
| conc-hot | 1 member | 29.9 / 26.2 | 128-238 | 5.3 | 8.8 | 9.6 | 1 |
| conc-hot | 3 members | 17.1 / 14.8 | 392-446 | 9.4 | 11.5 | 12.7 | 51 |

Each column is the mean, over the committed transactions, of that stage's duration on the member
that committed it. The replication stage spans actor messages and includes their waits; it charges
every commit of a round the round's whole send-to-settle time. The columns do not add up to a
commit's latency: the wait for a permission, the queueing, and the segment sync of step 4 are in no
column. End-to-end latency was not measured.

What the figures say, and what they do not:

- **A cluster costs throughput; it buys survival of a member's failure.** Three members commit
  0.56 times as many tiny transactions per second as one standalone process, and 0.33 times as
  many hot ones. A one-member cluster already pays most of it (0.60 on tiny). The design's
  expectation, not measured separately, is that the acceptor log's synced appends and the round's
  actor messages come on top of the same segment `fsync`.
- **Adding members does not add throughput.** One permission at a time across the cluster
  (DEPTH 0): three members on disjoint roots reach 0.93 times the commits of one member, and on
  one hot key 0.57 times.
- **The build under the permission is the cluster's critical section** (spec 7.2). At three
  members it is 11 to 18 ms per commit, against 7.4 to 8.8 ms at one. Why the tiny build more
  than doubles is **not established**; the likely cause, unmeasured, is that a member builds on
  roots other members wrote, whose records are not in its atom cache and are decoded from the
  segment.
- **Hot keys hurt more in a cluster.** Retries rise from 86-106 (standalone) to 392-446 per 120
  commits at three members, and 51 rounds in 600 commits were refused by the send reserve
  (retryable conflicts, nothing sent, retried by `run:`; two such refusals also occurred on tiny,
  which is what its 0-2 retries are). A reserve refusal is a round that reached the send with
  less than `sendReserve` plus its longest build left on its permission. Why permissions ran that
  short under contention was not measured.
- The figures vary between runs of the whole benchmark: an earlier run with the benchmark files of `3f5aa19` (the
  same workload, before the members counted their own commits) gave 44.3, 26.3 and 23.8 commits/s on
  tiny and 50.2, 26.0 and 14.9 on conc-hot. Read differences of 10 % as noise.
- **No `proto_db` figure is shown**: `proto_db`'s cluster was not run on this workload shape, so
  no ratio to it is claimed. Memory was not measured.

### Queries and indexes

0.3.0 (spec section 7.3, `bench/run_query.sh`, `bench/run_atom_weight.sh`). The headline is
[the final comparison](#the-final-comparison-plan-task-10) of plan Task 10, every workload on one
quiet machine from one clean commit; the sections after it are the runs of the tasks that built
each part (Q1-Q4 at Task 8, Q5 at Task 9, M1 at Task 4a, M3 at Task 4b, P1-P3 at Task 7, M2 at
Task 3, the atom weight at Tasks 11 and 12), kept as dated history.

#### The final comparison (plan Task 10)

**The headline figures for 0.3.0.** Every workload of spec 7.3, run once more on one quiet
machine from one committed, clean tree, one workload after another. The sections after this one
are the earlier runs of plan Tasks 3 to 12, kept as dated history; where they differ, this run
holds.

- **Date and machine**: 2026-11-20, 05:37 to 07:24 UTC; AMD Ryzen 5 5500U (6 cores, 12 threads),
  62 GB, Linux 7.0.0-43, DEV12. No other benchmark or build ran (the desktop only); the 1-minute
  load average was checked below 3 before each workload.
- **Commits**: protoBaseST `0fbed55`, clean (`git status` of `src` and `bench` empty; every
  provenance line reads `protoBaseST 0fbed55; protoST 0.12.0`, none "modified"); `proto_db`
  v2.0.0rc4 (`8e6127f`) in the interop venv, CPython 3.14.0.
- **Binaries**: the `pinned-360` release builds, protoST 0.12.0 (`b7e206a`) at
  `worktrees/pinned-360/protoST/build_release/protost` on protoCore 3.6.0 (`799d7615`); `ldd`
  resolves `libprotoCore.so.5` to `worktrees/pinned-360/protoCore/build_release/libprotoCore.so.5`.
- **Protocol** (unchanged from the earlier runs): `RUNS=5 bench/run_query.sh <workload>` for each
  of M1 M2 M3 P1 P2 P3 Q1 Q2 Q3 Q4 Q5, then `bench/run_atom_weight.sh`; default sizes; one
  process per unit, five rounds interleaved with `proto_db`; heap budget
  `PROTOCORE_HEAP_LIMIT_CELLS=80000000` (cluster members 32000000). Every workload printed
  `verified`: all ten runs of every unit reported `proto_db`'s first run's work (rows, queries,
  plan, checksum, and for P2 and P3 the model costs). Nothing is asserted about time; differences
  under about 15 % are noise.

| Workload | load before | load after | wall time |
|---|---|---|---|
| M1 | 2.32 | 2.18 | 6 min |
| M2 | 2.18 | 2.73 | 24 min |
| M3 | 2.73 | 2.82 | 13 min |
| P1 | 2.82 | 2.55 | 4 min |
| P2 | 2.55 | 1.61 | 9 min |
| P3 | 1.61 | 1.60 | 1 min |
| Q1 | 1.60 | 1.84 | 3 min |
| Q2 | 1.84 | 1.83 | 6 min |
| Q3 | 1.83 | 3.18 | 4 min |
| Q4 | 2.18 | 2.24 | 2 min |
| Q5 | 2.24 | 2.13 | 17 min |
| atom weight | 2.13 | 2.13 | 17 min |

Times are microseconds for the whole unit, minimum / median of five; the ratio is protoBaseST's
minimum over `proto_db`'s; peak RSS is the largest over a unit's runs. protoBaseST's peak RSS is
the heap budget being used, not the live set: protoCore keeps memory until it needs it. The units
are those of the sections below (M1 and M3: 200 and 120 commits on 600 records; M2: the build and
the fold of n elements; P1: 200 plans; P2: five executions per forced plan; Q1-Q4: 20 queries;
Q5: every page of 50, or 20 counts). M3's `-c3` units are the three-member cluster, which has no
`proto_db` run.

| Workload | size | plan | `proto_db` µs min / median | protoBaseST µs min / median | ratio (min) | peak RSS MB `proto_db` / protoBaseST |
|---|---|---|---|---|---|---|
| M1 | 600 | idx0 | 1361419 / 1389430 | 4760302 / 4795291 | 3.5x | 29 / 1368 |
| M1 | 600 | idx1 | 1752649 / 1758518 | 13782804 / 13906999 | 7.9x | 35 / 5090 |
| M1 | 600 | idx3 | 2534663 / 2542191 | 31722795 / 32289038 | 12.5x | 47 / 5114 |
| M2 | 100 | build | 2479 / 2509 | 39912 / 41045 | 16.1x | 25 / 113 |
| M2 | 100 | fold | 6525 / 6751 | 46614 / 48189 | 7.1x | 25 / 113 |
| M2 | 1000 | build | 23459 / 23747 | 463499 / 475349 | 19.8x | 26 / 328 |
| M2 | 1000 | fold | 83882 / 86473 | 689131 / 697204 | 8.2x | 26 / 312 |
| M2 | 10000 | build | 266201 / 275133 | 5612292 / 5672401 | 21.1x | 40 / 2942 |
| M2 | 10000 | fold | 1052880 / 1075352 | 9908198 / 9989066 | 9.4x | 37 / 2938 |
| M2 | 100000 | build | 3335620 / 3348963 | 63844880 / 64245469 | 19.1x | 173 / 5282 |
| M2 | 100000 | fold | 13772465 / 14023286 | 129458655 / 130095804 | 9.4x | 145 / 5276 |
| M3 | 600 | idx0 | 854501 / 874127 | 3091701 / 3128468 | 3.6x | 28 / 1072 |
| M3 | 600 | idx1 | 1082173 / 1096577 | 8485569 / 8491757 | 7.8x | 33 / 3628 |
| M3 | 600 | idx3 | 1480988 / 1541217 | 20030802 / 20349629 | 13.5x | 41 / 5126 |
| M3 | 600 | idx0-c3 | - | 6166511 / 6219983 | - | - / 1426 (largest member) |
| M3 | 600 | idx1-c3 | - | 14944095 / 15158879 | - | - / 2073 (largest member) |
| M3 | 600 | idx3-c3 | - | 42853972 / 47126251 | - | - / 2083 (largest member) |
| P1 | 1 | idx0 | 7467 / 7615 | 135510 / 138534 | 18.1x | 26 / 489 |
| P1 | 1 | idx2 | 15005 / 15197 | 332864 / 350358 | 22.2x | 27 / 944 |
| P1 | 1 | idx8 | 17628 / 18427 | 438140 / 453995 | 24.9x | 32 / 2182 |
| P1 | 8 | idx0 | 20601 / 21533 | 466262 / 481526 | 22.6x | 26 / 729 |
| P1 | 8 | idx2 | 50478 / 52914 | 895232 / 919840 | 17.7x | 28 / 1249 |
| P1 | 8 | idx8 | 127856 / 130143 | 1897269 / 1942618 | 14.8x | 33 / 2722 |
| P1 | 32 | idx0 | 58070 / 58980 | 1707790 / 1718854 | 29.4x | 29 / 1526 |
| P1 | 32 | idx2 | 248709 / 261183 | 3236054 / 3267989 | 13.0x | 31 / 2398 |
| P1 | 32 | idx8 | 825239 / 843934 | 7683493 / 7766873 | 9.3x | 35 / 4924 |
| P2 | 2000 | r0001-index | 69 / 72 | 1408 / 1423 | 20.4x | 33 / 1764 |
| P2 | 2000 | r0001-scan | 24403 / 26659 | 503909 / 522335 | 20.6x | 33 / 1932 |
| P2 | 2000 | r0010-index | 220 / 232 | 5339 / 7922 | 24.3x | 33 / 1768 |
| P2 | 2000 | r0010-scan | 25558 / 26195 | 506797 / 519046 | 19.8x | 33 / 1932 |
| P2 | 2000 | r0100-index | 1687 / 1712 | 58269 / 59033 | 34.5x | 33 / 1796 |
| P2 | 2000 | r0100-scan | 24599 / 26170 | 483620 / 507511 | 19.7x | 33 / 1933 |
| P2 | 2000 | r0500-index | 8312 / 8675 | 281191 / 286937 | 33.8x | 33 / 1860 |
| P2 | 2000 | r0500-scan | 25144 / 25722 | 492224 / 537609 | 19.6x | 33 / 1929 |
| P2 | 2000 | r0900-index | 14915 / 15364 | 522426 / 529533 | 35.0x | 33 / 1933 |
| P2 | 2000 | r0900-scan | 25569 / 26178 | 524057 / 527785 | 20.5x | 33 / 1945 |
| P2 | 2000 | r0990-index | 16223 / 17025 | 569247 / 577303 | 35.1x | 33 / 1960 |
| P2 | 2000 | r0990-scan | 25660 / 26001 | 517984 / 529938 | 20.2x | 33 / 1936 |
| P2 | 2000 | r1000-index | 16627 / 16978 | 564385 / 577525 | 33.9x | 33 / 1956 |
| P2 | 2000 | r1000-scan | 26201 / 26518 | 523437 / 533829 | 20.0x | 33 / 1936 |
| P2 | 2000 | ne-few-index | 3243 / 3296 | 94251 / 95608 | 29.1x | 33 / 1800 |
| P2 | 2000 | ne-few-scan | 25771 / 26114 | 449805 / 461988 | 17.5x | 33 / 1916 |
| P2 | 2000 | ne-many-index | 19380 / 20278 | 357185 / 364190 | 18.4x | 33 / 1892 |
| P2 | 2000 | ne-many-scan | 24666 / 25443 | 458427 / 466040 | 18.6x | 33 / 1909 |
| P3 | 2000 | intersect | 10302 / 10685 | 59400 / 60666 | 5.8x | 29 / 1584 |
| P3 | 2000 | filter | 2804 / 2882 | 54216 / 55097 | 19.3x | 29 / 1571 |
| Q1 | 100 | index | 1729 / 1774 | 13202 / 14582 | 7.6x | 25 / 133 |
| Q1 | 100 | scan | 5938 / 6077 | 78773 / 81026 | 13.3x | 25 / 136 |
| Q1 | 1000 | index | 1949 / 2018 | 15807 / 17640 | 8.1x | 26 / 488 |
| Q1 | 1000 | scan | 51928 / 52279 | 815972 / 827975 | 15.7x | 25 / 544 |
| Q1 | 10000 | index | 2072 / 2126 | 17009 / 19128 | 8.2x | 39 / 4780 |
| Q1 | 10000 | scan | 513312 / 525933 | 9653716 / 9916435 | 18.8x | 29 / 5063 |
| Q2 | 2000 | in1-index | 2317 / 2345 | 23533 / 25039 | 10.2x | 32 / 1768 |
| Q2 | 2000 | in1-scan | 118240 / 120928 | 1751588 / 1768493 | 14.8x | 26 / 1065 |
| Q2 | 2000 | in10-index | 4566 / 4633 | 77740 / 82060 | 17.0x | 31 / 1788 |
| Q2 | 2000 | in10-scan | 272352 / 275811 | 2398401 / 2442435 | 8.8x | 26 / 1073 |
| Q2 | 2000 | in100-index | 24865 / 25948 | 576064 / 577847 | 23.2x | 31 / 1964 |
| Q2 | 2000 | in100-scan | 1394862 / 1438012 | 6804113 / 6877480 | 4.9x | 26 / 1133 |
| Q2 | 2000 | r0001-index | 2346 / 2369 | 22042 / 24124 | 9.4x | 31 / 1764 |
| Q2 | 2000 | r0001-scan | 122873 / 128973 | 2086058 / 2107700 | 17.0x | 26 / 1157 |
| Q2 | 2000 | r0010-index | 3026 / 3066 | 40250 / 41839 | 13.3x | 31 / 1780 |
| Q2 | 2000 | r0010-scan | 126039 / 128473 | 2080236 / 2093710 | 16.5x | 26 / 1161 |
| Q2 | 2000 | r0100-index | 8832 / 9238 | 187780 / 197136 | 21.3x | 31 / 1820 |
| Q2 | 2000 | r0100-scan | 122676 / 125527 | 2102076 / 2124809 | 17.1x | 26 / 1165 |
| Q2 | 2000 | r0500-index | 36048 / 38196 | 831151 / 855426 | 23.1x | 32 / 2045 |
| Q2 | 2000 | r0500-scan | 123605 / 126814 | 2096585 / 2126679 | 17.0x | 26 / 1197 |
| Q3 | 2000 | and-index | 3879 / 3935 | 39644 / 40170 | 10.2x | 32 / 1772 |
| Q3 | 2000 | and-scan | 128047 / 129326 | 2362938 / 2398895 | 18.5x | 25 / 1117 |
| Q3 | 2000 | or2-index | 51645 / 54558 | 353553 / 364397 | 6.8x | 31 / 1928 |
| Q3 | 2000 | or2-scan | 229365 / 236688 | 3310989 / 3321893 | 14.4x | 26 / 1570 |
| Q3 | 2000 | ormix-index | 233970 / 238591 | 3281410 / 3361715 | 14.0x | 31 / 2817 |
| Q3 | 2000 | ormix-scan | 231262 / 233746 | 3193386 / 3211591 | 13.8x | 26 / 1561 |
| Q3 | 2000 | not-index | 137646 / 138575 | 1838130 / 1881847 | 13.4x | 32 / 2361 |
| Q3 | 2000 | not-scan | 134358 / 136171 | 1747321 / 1803522 | 13.0x | 26 / 1105 |
| Q4 | 2000 | all-index | 2056 / 2090 | 16138 / 17070 | 7.8x | 31 / 1764 |
| Q4 | 2000 | all-scan | 84025 / 90272 | 2602089 / 2652995 | 31.0x | 26 / 1178 |
| Q4 | 2000 | sel-index | 4153 / 4333 | 42767 / 44532 | 10.3x | 31 / 1773 |
| Q4 | 2000 | sel-scan | 103118 / 107250 | 1696583 / 1725388 | 16.5x | 26 / 1045 |
| Q4 | 2000 | unsel-index | 30332 / 32074 | 892045 / 903837 | 29.4x | 32 / 1952 |
| Q4 | 2000 | unsel-scan | 123607 / 125280 | 2217912 / 2252461 | 17.9x | 26 / 1189 |
| Q5 | 2000 | page-rank | 5198 / 5398 | 76170 / 77834 | 14.7x | 31 / 1784 |
| Q5 | 2000 | page-mat | 5176 / 5493 | 144722 / 151420 | 28.0x | 26 / 589 |
| Q5 | 2000 | page-skip | 52839 / 53496 | 1401843 / 1412060 | 26.5x | 32 / 2289 |
| Q5 | 2000 | count-index | 1988 / 2046 | 32662 / 35970 | 16.4x | 31 / 3628 |
| Q5 | 2000 | count-scan | 115372 / 121872 | 2084085 / 2160619 | 18.1x | 26 / 1690 |
| Q5 | 10000 | page-rank | 24399 / 24788 | 321440 / 326633 | 13.2x | 59 / 5099 |
| Q5 | 10000 | page-mat | 30883 / 32100 | 866604 / 883393 | 28.1x | 32 / 2915 |
| Q5 | 10000 | page-skip | 1416701 / 1464857 | 29488169 / 29523500 | 20.8x | 59 / 5099 |
| Q5 | 10000 | count-index | 1988 / 2032 | 44563 / 46973 | 22.4x | 59 / 5113 |
| Q5 | 10000 | count-scan | 571553 / 587083 | 8776353 / 8891148 | 15.4x | 29 / 5087 |

**Atom weight** (`bench/run_atom_weight.sh`, `src` at `0fbed55` clean, n = 10^5 kept, 200
allocated, empty run's interquartile range 1.77 cells per object), cells per object: retained
(median) / allocated. `tuple2` 13.2 / 54.9; `tupletrusted` 9.4 / 30.9; `atomshell` 3.0 / 12.0;
`nodeshell` 13.4 / 51.9; `nodeown` 33.6 / 136.4; `nodeoid` 15.4 / 82.2; `build` 41.7 / 110.5;
`oiddraw` 1.2 / 30.8; `loaded` 48.3 / 1397.5; `loadedcache` 51.6 / 307.1. The retained figures
equal stage 2's "after" ([below](#atom-weight-stage-2-shaped-atoms-keep-only-their-slots)) within
their interquartile ranges; the allocations differ from it by 0.5 to 15 cells per object (up 2.4
for `nodeown` and 14.7 for `loaded`, down 7.2 for `loadedcache`), not analysed.

**Q1 at 10^5, one run** (`QUERY_Q1_SIZES=100000 RUNS=1 bench/run_query.sh Q1`, right after,
07:24 to 07:31 UTC, load 1.66 before and 2.87 after, same commit and binaries, `verified`): the
20 lookups by index took 2.0 ms in `proto_db` and 40.4 ms in protoBaseST (20.2x); the 20 scans
5.48 s and 105.4 s (19.2x); peak RSS 166 / 5220 MB (index) and 71 / 5100 MB (scan). A single run
is not a minimum of five, and it did not run in the five-round interleaving.

What it shows.

- **protoBaseST is 3.5 to 35 times slower than `proto_db`**, minimum against minimum, on every
  unit: commits 3.5x to 13.5x (M1, M3), index builds 7x to 21x (M2), planning 9x to 29x (P1),
  queries 5x to 35x (P2, P3, Q1-Q5). No speed claim is made.
- **R1, whether indexed writes dominate a commit: they do, in protoBaseST.** One element per
  commit on 600 records: 42.0, 14.5 and 6.3 commits/s with 0, 1 and 3 indexes (23.8, 68.9 and
  158.6 ms per commit), against `proto_db`'s 147, 114 and 79 (6.8, 8.8 and 12.7 ms). Each index
  costs about 45 ms per commit here and 2.0 ms in `proto_db`, so index work is 65 % of an
  indexed commit's time with one index and 85 % with three (`proto_db`: 22 % and 46 %). At Task
  4a it was 55 to 58 ms per index (38, 11.9 and 5.2 commits/s); the atom weight work (Tasks 11
  and 12) cut it by about a fifth.
- **A merged blind write still costs what a read-modify-write costs** (M3 standalone: 38.8,
  14.1 and 6.0 commits/s, M1's within noise). In the three-member cluster: 19.5, 8.0 and 2.8
  commits/s, 2.0x, 1.8x and 2.1x slower than standalone; at Task 4b the three-index cluster
  committed 1.1 times per second, 4.4x slower than standalone. Its builds are shorter now, so
  fewer rounds are refused for lack of permission time: 119 to 151 retries per run of 120
  commits (309 to 450 at Task 4b), 30 to 35 with one index, 0 or 1 with none.
- **The bulk build is 1.2x (10^2) to 2.0x (10^5) faster than the fold** in protoBaseST, 2.6x to
  4.1x in `proto_db`. protoBaseST's build is 16x to 21x `proto_db`'s time and its fold 7x to 9x;
  at Task 3 the gap grew with n to 38x, it no longer does (10^4 build 5.6 s, fold 9.9 s, against
  10.0 s and 30.6 s at Task 3).
- **Planning costs grow with conjuncts times indexes** (P1): 0.68 ms to 38 ms per query in
  protoBaseST, 0.04 to 4.1 ms in `proto_db`.
- **The cost model against timings** (P2; both implementations computed the same model costs at
  every point). In `proto_db` the model switches early at both switch points: the forced index
  plan is still 37 % faster at `r < 2000` and 21 % at `many != 0`. In protoBaseST the range plans
  cross between 90 % and 99 % (index against scan 1.00x at 90 %, 1.10x at 99 %, 1.08x at 100 %),
  so the model, which switches between 99 % and 100 %, is late by under 10 %, within noise; on
  `many != 0` the complement is 22 % faster than the scan the model chooses, early as in
  `proto_db`. On `few != 0` the complement is 4.8x faster than the scan (`proto_db` 7.9x).
- **The intersection** (P3): 3.7x the filter plan's time in `proto_db`, so the model's claim
  holds there; 1.10x in protoBaseST (59.4 against 54.2 ms), within noise, so inconclusive at
  protoST's speed. Both planners choose the filter.
- **A point lookup by an index does not grow with the collection** (Q1): 0.66, 0.79 and 0.85 ms
  per query at 10^2, 10^3 and 10^4 records (`proto_db` 0.09 to 0.10 ms), against 3.9, 41 and
  483 ms for the scan (`proto_db` 0.30, 2.6 and 26 ms); at 10^4 the index answers 568 times
  faster than the scan. The single 10^5 run gave 2.0 ms per indexed query and 5.3 s per scan.
- **Q2-Q4, per query** (2000 records, protoBaseST; `proto_db` in parentheses): `in:` 1, 10, 100
  values 1.2, 3.9, 29 ms by index against 88, 120, 340 ms scanned (0.12, 0.23, 1.2 against 5.9,
  14, 70); ranges of 0.1 %, 1 %, 10 %, 50 % 1.1, 2.0, 9.4, 42 ms against about 104 ms (0.12, 0.15,
  0.44, 1.8 against about 6.2); AND 2.0 against 118 ms (0.19 against 6.4); the Union of two
  lookups 18 against 166 ms (2.6 against 11.5); an OR with an unindexed branch and a NOT are
  scans either way (about 160 and 90 ms; 11.6 and 6.8); an ordered index scan with `take: 5`
  0.81 ms against 130 ms for a sort of the scan (0.10 against 4.2); the selective and unselective
  sorts over a lookup 2.1 and 45 ms against 85 and 111 ms (0.21 and 1.5 against 5.2 and 6.2).
- **A page by rank costs the same at every size** (Q5): 1.9 ms per page of 50 at 2000 records and
  1.6 ms at 10^4 (`proto_db` 0.13 and 0.12). Skipping costs 35 and 147 ms per page on average, so
  reading every page by skipping costs 18x and 92x the pager's time (`proto_db` 10x and 58x).
  Materialising once costs 1.9x and 2.7x the pager by rank (`proto_db` 1.0x and 1.3x). A count by
  rank takes 1.6 and 2.2 ms against 104 and 439 ms for counting a filtered scan, 64x and 197x
  (`proto_db` 0.10 ms against 5.8 and 29 ms, 58x and 288x).
- **The Task 12 residual** (stage 2 below: steady Q1 queries about 1.5 times slower after
  `69e6888` in two of three driver pairs, possibly the load). Q1 at 10^4 by index now takes
  17,009 / 19,128 µs (minimum / median) at load 1.6 to 1.8: 8.7 % above the pre-Task-12 minimum
  (15,653 at `f95b09f`, load 3.0) and 6.7 % below the post-Task-12 one (18,236 at `69e6888`), both
  within the 15 % noise, and 0.9 % above Task 8's (16,854 at `90bad75`). So on a quiet machine
  the bench shows no Q1 index regression from Task 12; a per-row regression smaller than the
  noise is not excluded, since this run has no before side. The scan at 10^4 (9.65 s) is faster
  than every earlier run (11.1 s at Task 8; 11.5 s and 13.1 s in stage 2). Settled as noise
  unless a quiet, alternating A/B run shows otherwise.

#### Q1-Q4: queries, indexed against a forced scan

`RUNS=5 bench/run_query.sh Q1 Q2 Q3 Q4 P3`, plan Task 8, re-run after its fix round 1 on a clean,
committed tree. The runner's provenance line, unmodified:
`2026-11-19T15:38Z; protoBaseST 90bad75; protoST 0.12.0`. The run took 23 minutes; load average
2.07 before and 2.77 after, with no other heavy process, on the machine of M1 to M3 (AMD Ryzen 5
5500U, 6 cores, 12 threads, Linux 7.0.0-43, DEV12); the `pinned-360` build (protoST 0.12.0 on
protoCore 3.6.0); `proto_db` v2.0.0rc4 on CPython 3.14.0. One process per unit, five rounds
interleaved, heap budget `PROTOCORE_HEAP_LIMIT_CELLS=80000000`. The data and the units are
`bench/_query_bench.st` (`QueryUnits`) and `bench/py_query_workload.py`: records with `g` (ten
records per value), `r` (unique), `few` (four values) and `x` (ten values, never indexed). Plan
`-index` queries them with an equality index on `g` (Q1: that index only) and, for Q2-Q4, an
equality index on `few` and a range index on `r`, and the planner chooses; plan `-scan` queries the
same records without indexes. Each unit times 20 queries, each built, planned and run to an
`Array` through the query front end (`PBQuery`, `from_collection`). Every run self-reports its rows,
queries, checksum and the plan's node names; all ten runs of every unit agreed with `proto_db`'s
first (the runner printed `verified`), so both planners chose the same plan everywhere, and each
`-index` unit answered the rows of its `-scan`. Times are microseconds for the 20 queries, minimum
/ median of five; peak RSS is the largest over a unit's runs, in MB, `proto_db` / protoBaseST.
Q4's point `all` (no condition) is an addition to spec 7.3: with a condition both implementations
sort over a lookup, so `all` is the only Q4 point where the planner streams an ordered index.

| Unit | Plan chosen (`-index`) | `proto_db` index | protoBaseST index | `proto_db` scan | protoBaseST scan | Peak RSS index; scan |
|---|---|---|---|---|---|---|
| Q1, 10^2 records, `g == v` | `IndexLookup` | 1785 / 1931 | 14329 / 15158 | 6345 / 6504 | 117643 / 120145 | 25 / 148; 24 / 152 |
| Q1, 10^3 | `IndexLookup` | 2065 / 2214 | 16614 / 17862 | 55044 / 56536 | 1253409 / 1297072 | 26 / 744; 25 / 832 |
| Q1, 10^4 | `IndexLookup` | 2147 / 2204 | 16854 / 18694 | 545171 / 550601 | 11073528 / 11757011 | 39 / 5088; 29 / 5088 |
| Q2, `in:` 1 value (2000 records) | `IndexLookup` | 2555 / 2598 | 29200 / 29713 | 132556 / 135944 | 2496193 / 2644884 | 31 / 2626; 25 / 1701 |
| Q2, `in:` 10 values | `IndexLookup` | 4889 / 4983 | 87886 / 91332 | 303499 / 307919 | 3232368 / 3372979 | 31 / 2654; 25 / 1705 |
| Q2, `in:` 100 values | `IndexLookup` | 27768 / 28914 | 642911 / 655602 | 1541370 / 1650731 | 8026655 / 8254401 | 31 / 2822; 25 / 1773 |
| Q2, range 0.1 % | `IndexRange` | 2475 / 2621 | 24743 / 26337 | 132992 / 138976 | 2886970 / 2893763 | 31 / 2626; 25 / 1785 |
| Q2, range 1 % | `IndexRange` | 3177 / 3258 | 45674 / 48758 | 133402 / 144826 | 2896411 / 2908670 | 31 / 2634; 25 / 1785 |
| Q2, range 10 % | `IndexRange` | 9543 / 9600 | 213744 / 218714 | 137104 / 143286 | 2848140 / 2968641 | 31 / 2674; 25 / 1801 |
| Q2, range 50 % | `IndexRange` | 39988 / 43190 | 973328 / 991265 | 136358 / 141660 | 2896923 / 2985878 | 31 / 2910; 25 / 1837 |
| Q3, AND (`g == v & x < 5`) | `Filter <- IndexLookup` | 4103 / 4197 | 47227 / 49104 | 139702 / 147769 | 3222087 / 3323021 | 31 / 2630; 25 / 1757 |
| Q3, OR of two indexed branches | `Union` of two `IndexLookup` | 54714 / 57769 | 382118 / 386269 | 252187 / 253677 | 4693198 / 4795787 | 31 / 2786; 25 / 2406 |
| Q3, OR with an unindexed branch | `Filter <- CollectionScan` | 250269 / 260422 | 4681005 / 4757859 | 247941 / 259061 | 4583162 / 4739753 | 31 / 4091; 25 / 2398 |
| Q3, NOT (`not (few == v)`) | `Filter <- CollectionScan` | 147109 / 147684 | 2599471 / 2730049 | 150480 / 152606 | 2554866 / 2693507 | 31 / 3407; 25 / 1745 |
| Q4, `orderBy: r` `take: 5`, no condition | `Limit <- IndexOrderedScan` | 2300 / 2462 | 19977 / 20685 | 98970 / 99285 | 3442564 / 3571788 | 31 / 2626; 26 / 1806 |
| Q4, selective (`g == v`, ten rows) | `Limit <- Sort <- IndexLookup` | 4568 / 4896 | 51278 / 52218 | 115025 / 117884 | 2499579 / 2635541 | 31 / 2630; 25 / 1693 |
| Q4, unselective (`few == v`, 500 rows) | `Limit <- Sort <- IndexLookup` | 36205 / 38321 | 1136992 / 1158193 | 129762 / 137303 | 3236612 / 3262506 | 31 / 2862; 26 / 1877 |

What it shows.

- **A point lookup by an index does not grow with the collection.** In protoBaseST it takes about
  0.8 ms per query from 10^2 to 10^4 records, and `proto_db` about 0.1 ms. The scan grows with the
  collection: 5.9 ms to 554 ms per query in protoBaseST, 0.3 to 27 ms in `proto_db`. At 10^4 records
  protoBaseST's index answers about 650 times faster than its scan.
- **protoBaseST is 5 to 35 times slower than `proto_db`** on every unit (minimum against minimum),
  by kind:
  - point lookups and ordered streams: 8x to 12x (Q1 index, Q2 `in:` 1 value, Q3 AND, Q4 `all`
    and selective);
  - the Union of two lookups: 7x;
  - index plans that answer many rows: 14x to 24x (Q2 `in:` 10 and 100 values, ranges of 1 % to
    50 %), and 31x for the unselective Q4 (a sort of 500 rows);
  - the 0.1 % range: 10x;
  - scans, forced or chosen: 17x to 25x, and 35x for Q4's sort over the whole scan;
  - the `in:` scans of 10 and 100 values: 11x and 5x, because `proto_db` tests a long `in` slowly
    on a scan.
- **The Union is now cheap.** The first run of Task 8 measured the Union of two lookups at 107x
  `proto_db`'s time, slower than its own scan. The cause was the identity key of `PBUnion`,
  `PBIntersect` and `PBDistinct`: a constant cost of about 430 µs per row, from a member tuple built
  and dropped, a nested tuple order key, and four dictionary operations each recomputing that key's
  uncached hash. Fix round 1 keys an atom by its oid's bytes, builds no member tuple, and looks each
  row up once. The Union is now 7.0x `proto_db`, and 12x faster than its own scan; `proto_db`'s is
  4.6x faster than its scan.
- **The planner's choices are `proto_db`'s.** Both implementations sort the unselective Q4 over a
  lookup rather than filter an ordered scan, as the model says.

**Sizes.** Q1 stops at 10^4 records, not at the spec's 10^5. With every index, a 10^5 probe was
stopped after more than 5 CPU minutes and 5 GB, before its first query. With only the `by_g` index
the index plan uses, one 10^5 process took 336 s and peaked at 5.4 GB (the budget is about 5 GB),
and answered its 20 lookups in 32.5 ms against `proto_db`'s 2.0 ms. Outputs are in
`bench/out/q1-probe/`, which git ignores. Q1 needs ten such processes per size, so 10^5 is not run
by default (`QUERY_Q1_SIZES` sets the sizes); see "Benchmark sizes" in the table of indexed-query
deviations. Peak resident sets of protost (up to 5 GB) are not a figure of the work: protoCore
keeps memory until it needs it.

#### Q5: pages by rank, materialised and by skipping; counts by rank

`RUNS=5 bench/run_query.sh Q5`, plan Task 9, on a clean, committed tree with no other heavy
process. The runner's provenance line, unmodified:
`2026-11-19T16:59Z; protoBaseST f7d3da7; protoST 0.12.0`. The run took 24 minutes; load average
3.08 before and 2.64 after (the desktop only), on the machine of M1 to M3 (AMD Ryzen 5 5500U, 6
cores, 12 threads, Linux 7.0.0-43, DEV12); the `pinned-360` build (protoST 0.12.0 on protoCore
3.6.0); `proto_db` v2.0.0rc4 on CPython 3.14.0. One process per unit, five rounds interleaved,
heap budget `PROTOCORE_HEAP_LIMIT_CELLS=80000000`. The records are Q1-Q4's (`QueryUnits` in
`bench/_query_bench.st`, `bench/py_query_workload.py`), at 2000 and 10^4. Every page of 50 of the
records ordered by `r` is read, from page 0 to the last (40 and 200 pages): `page-rank` by a pager
over the indexed records (an `IndexOrderedScan`, by rank); `page-mat` by a pager over the same
records without indexes (a `Sort` over the scan, run once and sliced); `page-skip` the obvious way,
each page read from the indexed query by producing and dropping the rows before it and stopping
after it. `count-index` and `count-scan` time 20 counts of `r >= n (q + 1) // 21`, by rank over
the indexes and by walking a filtered scan without them. Each unit checks before timing that its
pager or every count is by rank (or is not) and fails otherwise; every run self-reported its rows,
pages, plan and checksum, all ten runs of every unit agreed with `proto_db`'s first, and the three
page units of a size, and the two count units, reported the same rows and checksum (the runner
printed `verified`). Times are microseconds for the whole unit, minimum / median of five; per page
and per count are the minimum divided by the pages or the counts. Peak RSS is the largest over a
unit's runs, in MB, `proto_db` / protoBaseST; protoBaseST's (up to 5 GB, the heap budget) is not a
figure of the work: protoCore keeps memory until it needs it.

| Unit | `proto_db` | protoBaseST | Per page or count, `proto_db`; protoBaseST | Ratio st/py | Peak RSS |
|---|---|---|---|---|---|
| 2000, `page-rank` (40 pages) | 5450 / 5662 | 85097 / 97592 | 0.14; 2.1 ms | 15.6x | 31 / 2646 |
| 2000, `page-mat` | 5596 / 6029 | 188960 / 205331 | 0.14; 4.7 ms | 33.8x | 26 / 1033 |
| 2000, `page-skip` | 56258 / 60756 | 1554057 / 1652503 | 1.4; 38.9 ms | 27.6x | 31 / 3151 |
| 2000, `count-index` (20 counts) | 2067 / 2197 | 34440 / 39398 | 0.10; 1.7 ms | 16.7x | 31 / 5067 |
| 2000, `count-scan` | 123359 / 126130 | 2850606 / 2862384 | 6.2; 143 ms | 23.1x | 26 / 2818 |
| 10^4, `page-rank` (200 pages) | 25956 / 27426 | 385390 / 420313 | 0.13; 1.9 ms | 14.8x | 59 / 5088 |
| 10^4, `page-mat` | 32289 / 34284 | 910807 / 1041215 | 0.16; 4.6 ms | 28.2x | 32 / 5088 |
| 10^4, `page-skip` | 1467964 / 1502836 | 39002927 / 39571531 | 7.3; 195 ms | 26.6x | 59 / 5088 |
| 10^4, `count-index` | 2094 / 2173 | 43907 / 48654 | 0.10; 2.2 ms | 21.0x | 58 / 5126 |
| 10^4, `count-scan` | 618763 / 629753 | 13082681 / 13310845 | 31; 654 ms | 21.1x | 29 / 5088 |

What it shows.

- **A page by rank costs the same at every size.** About 2 ms per page of 50 in protoBaseST at
  2000 and at 10^4 records (0.13 ms in `proto_db`): one descent of the weighted index, then the
  page. Skipping grows with the page number: on average 39 ms per page at 2000 and 195 ms at 10^4,
  so reading every page by skipping costs 18x the pager's time at 2000 and 101x at 10^4
  (`proto_db`: 10x and 57x). The gap grows with n, as O(n² / s) against O(n + (n / s) log n) says.
- **Materialising once is close to rank.** A pager over a plan without rank access runs its sort
  once and slices it: 2.2x to 2.4x the pager by rank in protoBaseST, over every page
  (`proto_db`: 1.0x to 1.2x). Its cost is the plan's, paid once, not per page.
- **A count by rank does not grow with the collection.** 1.7 and 2.2 ms per count at 2000 and
  10^4 (`proto_db` 0.10 ms at both, which includes building and planning each query), against
  143 and 654 ms for counting a filtered scan: 83x and 298x (`proto_db`: 60x and 295x).
- **protoBaseST is 15x to 34x slower than `proto_db`** (minimum against minimum): 15x to 21x for
  the rank units, 21x to 28x for the walks, and 28x to 34x for the materialised pager, whose
  `Sort` dominates (Q4 measured a sort over a scan at 35x).

The first run of Q5 (at `d7e5a25`, also `verified`) counted `r >= n q // 20`. For q = 0 that bound
covers every row, and both planners answer it by a scan, so `count-index` was not all by rank and
grew with n (98 % of `proto_db`'s 10^4 unit was that one walk, by profile). The bounds were changed
and each count unit now checks its plans before timing (`f7d3da7`); the table is the second run.
Sizes: Q5 runs 2000 and 10^4 records, not 10^5, for the reason given for Q1 ("Benchmark sizes" in
the table of indexed-query deviations); `QUERY_Q5_SIZES` sets them.

#### M1: commits per second with 0, 1 and 3 indexes

`RUNS=5 bench/run_query.sh M1`. **Indicative only.** Measured 2026-11-19 (05:05-05:13 local) on
the same machine as M2 below (AMD Ryzen 5 5500U, 6 cores, 12 threads, Linux 7.0.0, DEV12), load
average 3.0 before and 3.1 after (other desktop sessions open, not controlled); protoBaseST at the
Task 4a commit `82572e9` (on `b9ec393`; the
benchmark ran on that working tree), protoST 0.12.0 (`b7e206a`) on protoCore 3.6.0 (`799d7615`),
the `pinned-360` release build; `proto_db` v2.0.0rc4 (`8e6127f`) on CPython 3.14.0. Each unit (a
plan) ran in a process of its own, five rounds interleaved, every protost process with the heap
budget `PROTOCORE_HEAP_LIMIT_CELLS=80000000` (about 5 GB). The workload: a `PBDictionary` of 600
records committed once, then 200 transactions, timed together, each reading the dictionary and
committing it with one record replaced (one replace event per index), on a file space under
`bench/out`. Plans: no index (idx0); a `PBEqualityIndex` on `city` (idx1); that one, a
`PBRangeIndex` on `age` and a `PBRangeIndex` on an extractor (the name's length) (idx3). Every run
self-reports the count read back and an ordered checksum over the values and every index; the
read-back version must pass `validate`; all ten runs of each plan agreed with `proto_db`'s first.

| Indexes | `proto_db` commits/s | protoBaseST commits/s | protoBaseST / `proto_db` time (min) | peak RSS MB `proto_db` / protoBaseST |
|---|---|---|---|---|
| 0 | 150 (6.7 ms per commit) | 38 (26.3 ms) | 3.9x | 27 / 1902 |
| 1 | 115 (8.7 ms) | 11.9 (84.1 ms) | 9.7x | 33 / 5077 |
| 3 | 83 (12.1 ms) | 5.2 (192.3 ms) | 15.9x | 45 / 5078 |

Commits per second from the minimum of five runs of 200 commits (medians within 7 %: protoBaseST
5.28 s, 18.0 s, 39.6 s; `proto_db` 1.34 s, 1.76 s, 2.48 s).

- **The extra cost per index**: about 2.0 ms per commit for the first index and 1.8 ms each on
  average over three in `proto_db`; about 58 ms for the first and 55 ms each over three in
  protoBaseST. A commit without an index is 3.9x slower than `proto_db`'s; each index is about
  30x slower than `proto_db`'s, which is what the per-element costs of the key-group trees
  measured in M2 predict (member key, order key, depth check), not a cost of the maintenance
  order itself.
- **Peak RSS is the heap budget, not the live set**: protoCore keeps memory until it reaches its
  budget, so 5 GB is the budget being used, and 1.9 GB for idx0 is where that run stopped growing.
  `proto_db` stays under 50 MB. Not a measure of what the workload needs.
- Not measured: commits per second under contention (M3 below measures merges onto indexed
  roots), and sizes other than 600.

#### M3: a blind write merged onto an indexed current, standalone and in a cluster

`RUNS=5 bench/run_query.sh M3`. **Indicative only.** Measured 2026-11-19 (09:20-09:49 UTC) on the
machine of M1 and M2 (AMD Ryzen 5 5500U, 6 cores, 12 threads, Linux 7.0.0, DEV12), load average
2.5 before and 4.6 after (other desktop sessions open, not controlled); protoBaseST at `6437d90`
with the Task 4b working tree (committed as the Task 4b commit), the `pinned-360` build of M1
(protoST 0.12.0 on protoCore 3.6.0); `proto_db` v2.0.0rc4 (`8e6127f`) on CPython 3.14.0. The
workload: M1's dictionary of 600 records and plans (0, 1 and 3 indexes, one of them on an
extractor), then 120 transactions, timed together, each committing **a new dictionary holding one
record and never reading the root**, so every commit rebases it onto the current version, whose
mutators maintain its indexes (`rebaseOnto:`, plan Task 4b). The 120 keys are distinct, so the
final content does not depend on the order of the commits. Standalone: one process per unit, five
rounds interleaved with `proto_db`, protost heap budget `PROTOCORE_HEAP_LIMIT_CELLS=80000000`.
Cluster: `bench/run_cluster.sh`'s profile (three protost member processes on 127.0.0.1 over one
shared directory on ZFS, `proto_db`'s default options: a 2000 ms lease), one writer per member,
40 commits each, `run:retries: 1000`; every member with the budget 32000000 cells (about 2 GB).
Every run self-reports the rows read back, the commits and M1's ordered checksum over the values
and every index, and the read-back version must pass `validate`; all five standalone runs of
each implementation and all five cluster runs agreed with `proto_db`'s standalone run of the same
plan (there is no `proto_db` cluster run of this workload: its cluster is not driven here).

| Indexes | `proto_db` commits/s | protoBaseST commits/s | protoBaseST / `proto_db` time (min) | protoBaseST, 3-member cluster, commits/s | peak RSS MB `proto_db` / protoBaseST / largest member |
|---|---|---|---|---|---|
| 0 | 141 (7.1 ms per commit) | 34.2 (29.3 ms) | 4.1x | 17.4 (57.6 ms) | 27 / 1481 / 1743 |
| 1 | 110 (9.1 ms) | 11.9 (84.2 ms) | 9.2x | 6.8 (146 ms) | 31 / 4613 / 2060 |
| 3 | 81 (12.4 ms) | 5.1 (197.6 ms) | 16.0x | 1.1 (879 ms) | 39 / 5077 / 2067 |

Commits per second from the minimum of five runs (medians: standalone within 5 %; cluster 17.0,
6.1 and 0.96 commits/s).

- **A merged blind write costs what a read-modify-write costs**: the standalone figures are M1's
  within a few per cent (34.2 against 38, 11.9 against 11.9, 5.1 against 5.2 commits/s). The
  merge replays one `setAt:value:` through the current version's mutator, which does the same
  index work as the writer's own `setAt:value:` in M1; it moves that work into the commit's
  build, it does not add to it. The same holds in `proto_db` (141, 110, 81 against 150, 115, 83).
- **In the cluster the build runs under the write permission, and with three indexes it no
  longer fits.** The median build per commit was 34, 91 and 189 ms for 0, 1 and 3 indexes
  (replication about 11 ms in every plan). A permission lasts at most 667 ms here (the 2000 ms
  lease less the drift margin) and a send needs 167 ms of it (sendReserve); a group commit builds
  a second entry only while sendReserve plus the longest build is left (CC11), and a round whose
  builds leave less than sendReserve is refused and retried (R121). With 189 ms builds that
  happened 135 to 210 times per run of 120 commits, and the block ran 309 to 450 times more than
  once per commit, so the three-index cluster commits 1.1 times per second, 4.4 times slower
  than standalone; with 0 and 1 index it is 2.0x and 1.7x slower (0 to 5 and 28 to 82 retries
  per run). This is the cost queries.md names: an indexed root lengthens the build, which runs
  under the cluster-wide permission. A longer `leaseDuration` raises the ceiling (not measured).
- **Two limits follow, in cluster mode only.** A single build longer than the permission less
  sendReserve (about 500 ms at the default 2000 ms lease: 667 ms less 167 ms) never commits: every
  attempt is refused before its send (CC18 says so in the conflict's text), so a merge onto a
  large or heavily indexed current can be impossible at the default lease. And retries this heavy
  can exhaust the default `run:` retry budget (10), where M3 passed `run:retries: 1000`. The remedy is a
  longer `leaseDuration` (with its drift margin), not more retries.
- **Peak RSS is the heap budget, not the live set** (as M1): the standalone protost processes
  grow to their 5 GB budget, the cluster members to their 2 GB one. Not a measure of what the
  workload needs.
- Not measured: `proto_db`'s cluster on this workload, a longer lease, more writers per member,
  sizes other than 600.

#### P1, P2, P3: the planner's overhead, the cost model against timings, the intersection

`RUNS=5 bench/run_query.sh P1 P2 P3`. **Indicative only, and noisy**: measured on a committed tree
under a heavy desktop load. The runner's provenance line, unmodified:
`2026-11-19T13:31Z; protoBaseST b68bec7; protoST 0.12.0` (the run ended then; it took about 20
minutes). Machine of M1 to M3 (AMD Ryzen 5 5500U, 6 cores, 12 threads, Linux 7.0.0-43, DEV12); load
average 5.5 before and 8.9 after (other sessions running, not controlled); the `pinned-360` build
(protoST 0.12.0 on protoCore 3.6.0); `proto_db` v2.0.0rc4 (`8e6127f`) on CPython 3.14.0. One process
per unit, five rounds interleaved, protost heap budget `PROTOCORE_HEAP_LIMIT_CELLS=80000000`. The
data and work are `bench/_query_bench.st` (`PlannerBench`) and `bench/py_query_workload.py`. Every
run self-reports its rows, queries, checksum and `model=`, the node names of the plan the planner
chooses, and P2 and P3 runs a MODEL line with the model costs of the plans compared; all ten runs of
every unit agreed with `proto_db`'s first run on both (the runner compares them), so on every unit
the two planners chose the same plan at the same model costs; the two forced plans of a P2 point,
and P3's two plans, answered the same rows and checksum. Times are the minimum of five; the medians
are up to 50 % above it in this run (load), so differences under about 15 % are noise.

**Sizes.** The workloads use 1000 records (P1) and 2000 (P2, P3), not the 10^4 first drafted:
building a 10^4-record `PBList` with three indexes took about 30 s per process in protoST (untimed
setup, paid by every one of the 330 processes of a run). Size is not the variable of P2 (ruling CR2);
P3 is measured at one size and one selectivity only.

**P1, planner overhead**: `plan` and `explain` of 200 conditions, no execution, on a `PBList` of
1000 records with 0, 2 or 8 indexes (alternately range and equality on eight fields).

| Conjuncts | Indexes | `proto_db` ms per query | protoBaseST ms per query | ratio |
|---|---|---|---|---|
| 1 | 0 | 0.04 | 0.71 | 16.8x |
| 1 | 2 | 0.08 | 1.94 | 24.0x |
| 1 | 8 | 0.09 | 2.53 | 27.3x |
| 8 | 0 | 0.11 | 2.70 | 23.8x |
| 8 | 2 | 0.27 | 4.95 | 18.1x |
| 8 | 8 | 0.71 | 11.0 | 15.5x |
| 32 | 0 | 0.33 | 9.11 | 27.4x |
| 32 | 2 | 1.41 | 18.2 | 12.9x |
| 32 | 8 | 4.52 | 47.0 | 10.4x |

The cost grows with conjuncts times indexes, as `planner.py`'s design says (one candidate per
supported conjunct, each estimated): 32 conjuncts over 8 indexes cost protoBaseST 47 ms a query,
`proto_db` 4.5 ms.

**P2, the cost model against timings**: 2000 records; a `PBRangeIndex` on a unique key `r`,
`PBEqualityIndex`es on `few` (4 key groups) and `many` (2000 groups). Each point runs the index's
own plan and a `Filter` over the scan, both forced, five executions timed together. The model costs
are compared by the runner: `proto_db`'s and protoBaseST's are equal (in thousandths).

| Term | rows | model: index / scan cost | planner chooses | `proto_db` ms index / scan | protoBaseST ms index / scan |
|---|---|---|---|---|---|
| `r < 2` | 2 | 15.0 / 4000 | IndexRange | 0.08 / 28.7 | 1.5 / 693 |
| `r < 20` | 20 | 51.0 / 4000 | IndexRange | 0.24 / 28.5 | 6.8 / 767 |
| `r < 200` | 200 | 411 / 4000 | IndexRange | 1.9 / 27.1 | 73 / 782 |
| `r < 1000` | 1000 | 2011 / 4000 | IndexRange | 9.5 / 27.9 | 341 / 817 |
| `r < 1800` | 1800 | 3611 / 4000 | IndexRange | 19.5 / 29.6 | 693 / 761 |
| `r < 1980` | 1980 | 3971 / 4000 | IndexRange | 18.7 / 31.8 | 850 / 728 |
| `r < 2000` | 2000 | 4011 / 4000 | scan + Filter | 21.4 / 30.8 | 883 / 800 |
| `few != 0` (4 groups) | 1500 | 2005 / 4000 | IndexComplement | 4.2 / 30.5 | 111 / 760 |
| `many != 0` (2000 groups) | 1999 | 4001 / 4000 | scan + Filter | 26.2 / 32.3 | 492 / 708 |

- **The model switches** to the scan between 99 % and 100 % selectivity on the unique range
  index, and for `!=` when the index has n groups (CR1: the complement wins below n − 1 groups).
- **In `proto_db` the model switches early**: at both switch points it chooses the scan while the
  forced index plan is still faster, by 31 % (range, `r < 2000`) and 19 % (`!=` on n groups).
- **In protoBaseST the range point converges and is within noise**: near the switch the two plans
  take about the same time (index against scan 0.91x at 90 %, 1.17x at 99 %, 1.10x at 100 % in
  this run; 0.83x, 0.96x and 0.96x in an earlier run on an uncommitted tree under lighter load), so
  no crossing is resolved there. For `!=` on n groups the model switches early in protoBaseST too:
  the complement is 30 % faster than the scan it rejects (and was in the earlier run).
- Below the switch the index wins in proportion to the rows (about 460x at 2 rows in protoBaseST).
  Why a full index pass beats a scan with a filter that the model prices 0.3 % cheaper in
  `proto_db` was not measured; the model charges a scanned element 2 units (read, test) and an
  index row 1 plus its group's share.
- Ruling CR2, verbatim: "P2 measures whether real timings cross where the cost model says; the model's crossover for a tiny collection is only one or two elements." So collection size is
  not the variable swept.

**P3, intersect** (one size, one selectivity): 2000 records, `x == 3` on a `PBEqualityIndex`
(200 rows) and `y == 2` on a `PBRangeIndex` (286 rows); 29 rows answer. The hand-built
`PBIntersect` of both index plans costs 978.8 in the model, the planner's plan
(`Filter <- IndexLookup` of `x`) 403.6.

| Plan | `proto_db` ms (5 runs) | protoBaseST ms (5 runs), Task 7 | protoBaseST ms (5 runs), Task 8 fix round 1 |
|---|---|---|---|
| `Intersect (IndexLookup x, IndexRange y)` | 12.2 (re-run: 11.1 / 12.0) | 1139 | 65.5 / 67.7 |
| `Filter <- IndexLookup` (planner) | 3.1 (re-run: 3.0 / 3.1) | 86 | 71.9 / 74.5 |

At Task 7 the model's claim held at both speeds on this data. The intersection was 3.9x slower
than the filter in `proto_db` and 13.2x in protoBaseST (model: 2.4x).

Task 8's fix round 1 made the intersection's identity keys cheap, and P3 was re-run in the Q1-Q4
run above (provenance `90bad75`, all runs verified; the re-run cells are minimum / median of five,
ms). In `proto_db` the intersection is still 3.7x slower than the filter plan. **In protoBaseST
the two plans are now within noise of each other** (65.5 / 67.7 against 71.9 / 74.5 ms, a 9 %
difference, under the about 15 % this section counts as noise): the run is inconclusive on the
model's claim at protoST's speed. The filter evaluates `y == 2` on each of the 200 rows of the
lookup, and a term evaluation in protoST costs about as much per row as an identity key now does.

The planner still chooses the filter plan, as `proto_db`'s does: plans are ported, not retuned
(spec 5.6). Other sizes and selectivities were not measured.

**Peak RSS** (0.7 to 5 GB for protoBaseST against about 30 MB) is the heap budget being used, not
the live set (see M1).

#### M2: the bulk build against the fold of single additions

`QUERY_M2_SIZES="100 1000 10000" RUNS=3 bench/run_query.sh M2`. **Indicative only.** Measured
2026-11-19 (03:55-03:58 local) on an AMD Ryzen 5 5500U (6 cores, 12 threads, Linux 7.0.0, DEV12),
load average 2.6 before and 2.9 after (other desktop sessions open; their load was not controlled); protoBaseST at
`e52b691` (the Task 3 commit; the fix round changed no code the benchmark runs), protoST 0.12.0
(`b7e206a`, tag v0.12.0) on protoCore 3.6.0 (`799d7615`, tag v3.6.0), the `pinned-360` release
builds (`build_release/protost`, as built; their sources match the tags file for file);
`proto_db` v2.0.0rc4 (`8e6127f`) in the interop venv on CPython 3.14.0. The workload is an `EqualityIndex` on the path `age` over n records (about a quarter as many
distinct ages as records, Integers and Floats, some absent, some nil), built by `build:` and by the
fold of `withAdded:` from `empty`. Every run self-reports its rows and an ordered checksum over the
stored occurrences; the runner refuses any run whose work differs from `proto_db`'s first run, and
all six runs (three each, interleaved) agreed. Times in microseconds, minimum / median of 3:

| n | plan | `proto_db` | protoBaseST | protoBaseST / `proto_db` (min) |
|---|---|---|---|---|
| 100 | build | 3884 / 4189 | 64771 / 73068 | 16.7x |
| 100 | fold | 5695 / 6141 | 105419 / 146660 | 18.5x |
| 1000 | build | 23831 / 24365 | 691942 / 709918 | 29.0x |
| 1000 | fold | 76950 / 78559 | 1807449 / 1838218 | 23.5x |
| 10000 | build | 261664 / 275029 | 10011607 / 10200266 | 38.3x |
| 10000 | fold | 1007979 / 1051734 | 30599201 / 30720372 | 30.4x |

- The bulk build is 3.1x faster than the fold at 10^4 in protoBaseST (1.6x at 10^2) and 3.9x in
  `proto_db`: the build is what `rebuiltStale:` and a first change to a stale collection pay.
- protoBaseST is 17x to 38x slower than `proto_db` here, and the gap grows with n. Not analysed
  in Task 3 beyond a probe on 4000 records: each element costs about 0.17 ms for its member key
  (`memberKeyOf:`), 0.11 ms for the order key of that member key, 0.07 ms per hash of it (not
  cached; a `Dictionary` rehash recomputes it) and 0.24 ms for the depth check (`checkDepth:`), all
  of which `proto_db` does in C-backed MessagePack and tuples. These are the first candidates.
- **n = 10^5, measured in Task 4a** with the runner's new isolation: each plan in a process of
  its own with the heap budget `PROTOCORE_HEAP_LIMIT_CELLS=80000000` (about 5 GB),
  `QUERY_M2_SIZES=100000 RUNS=1 bench/run_query.sh M2`, 2026-11-19 05:13-05:24 local, same
  machine and binaries as M1 above, load average 2.8 before (13 GB of 62 free). One run each,
  verified (same rows and checksum in both implementations and both plans): build 3.53 s
  (`proto_db`) against 95.6 s (protoBaseST), 27.1x; fold 15.4 s against 470.4 s, 30.5x. The build
  is 4.9x faster than the fold in protoBaseST, 4.4x in `proto_db`. Peak RSS: `proto_db` 172 MB
  (build) and 143 MB (fold); protoBaseST 5301 MB and 5307 MB, that is, the budget (protoCore keeps
  memory until it reaches it; the earlier attempt without a budget, in Task 3, was stopped by the
  machine's out-of-memory guard at 14 GB, during the 10^5 step, with every size in one process). The
  ratio does not keep growing past 10^4 (38.3x there, 27.1x here, single runs on a busy machine).

#### Atom weight, stage 1: construction cleanup, write-once fields by compare-and-swap

Plan Task 11 (the maintainer's question of 2026-11-19, "why so many cells?", answered without
breaking immutability; [decisions.md](decisions.md), row Queries 11). An atom's runtime-only
fields (oid, saved place, load memo, a keyed node's order key, an index's parsed key spec) were
one `Atom` each; they are now instance variables written once by a compare-and-swap from nil, and
a constructor writes its fields in one write group without writing nil. A counted node builds its
slots with one brace instead of `copyWith:`, the built-in node classes read their record shape
from a class variable, and `PBTuple _trustedOn:` keeps a fresh brace Array instead of copying it.
Bytes on disk and tree node identity with `proto_db` are unchanged
(`tests/interop/*identical*.sh` pass).

**Cells**, `bench/run_atom_weight.sh` (protoCore's cell allocator counted under gdb; live cells
from `PROTOCORE_HEAP_TRACE` after a churn, 10^5 objects kept, minus an empty run, heap budget
`PROTOCORE_HEAP_LIMIT_CELLS=32000000`), 2026-11-19, same machine and binary as below, load
average 2.8 to 3.6 (the bench's own processes included); before at `138730d`, after at `70a4969`,
both clean. Retained is the object run's median live count minus the empty run's median, per
object; the interquartile range of a run's live counts is 0.5 to 2.3 cells per object (the empty
run's 1.6), re-derived from the recorded raw outputs;
allocated is the cells allocated per object built:

| object | retained before | retained after | allocated before | allocated after |
|---|---|---|---|---|
| a `PBCountedKeyNode`, own key and value tuple (`key:orderKey:value:left:right:`) | 80.1 | 51.6 | 518.6 | 200.7 |
| the same node, key, order key and value shared (the node's own cells) | 58.4 | 31.2 | 406.9 | 111.2 |
| a node of a 10^5-node tree built by `PBAvl keyFromSorted:` (per node) | 88.3 | 59.9 | 481.6 | 173.2 |
| a blank atom after `_setOid: nil pointer: nil storage: nil` | 33.3 | 3.8 | 121.4 | 13.0 |
| a `PBTuple` of 2, `withAll:` (copies) / `_trustedOn:` (new) | 13.2 | 13.5 / 10.0 | 53.4 | 54.0 / 30.0 |

Drawing a node's oid still allocates about 315 cells (the oid pool's slice and the
publication); it retains about 2.

**Wall time and memory**, `QUERY_M2_SIZES="2000 10000" QUERY_Q1_SIZES=10000 RUNS=3
bench/run_query.sh M2 Q1`, before (`138730d`, from a clean worktree of that commit) then after
(`70a4969`), one after the other on the machine of M1 to M3 (AMD Ryzen 5 5500U, Linux 7.0.0-43,
DEV12), the `pinned-360` build (protoST 0.12.0 on protoCore 3.6.0), `proto_db` v2.0.0rc4 on
CPython 3.14.0, heap budget `PROTOCORE_HEAP_LIMIT_CELLS=80000000`. Runner provenance lines,
unmodified: `2026-11-19T17:59Z; protoBaseST 138730d; protoST 0.12.0` and
`2026-11-19T18:03Z; protoBaseST 70a4969; protoST 0.12.0`. Load average 3.6 before and 4.2 after
the first run, 3.2 and 3.6 for the second (desktop sessions open, not controlled). Every run was
verified (same rows, queries, plan and checksum as `proto_db`'s). Microseconds, minimum / median
of 3; peak RSS in MB (the largest over the runs):

| unit | protoBaseST before | protoBaseST after | change (min) | peak RSS before / after | `proto_db` (after run) |
|---|---|---|---|---|---|
| M2, 2000, build | 1292462 / 1399337 | 1074495 / 1171899 | -17% | 765 / 665 | 51765 / 52791 |
| M2, 2000, fold | 3513430 / 3933494 | 1827802 / 2145897 | -48% | 1393 / 749 | 185683 / 201873 |
| M2, 10^4, build | 7343821 / 7446686 | 6043123 / 6266610 | -18% | 3928 / 3368 | 279660 / 282305 |
| M2, 10^4, fold | 19711389 / 20012678 | 12322533 / 12649148 | -37% | 5070 / 4141 | 1083321 / 1083536 |
| Q1, 10^4, index | 17606 / 17693 | 15616 / 16167 | -11% | 5087 / 5086 | 2127 / 2169 |
| Q1, 10^4, scan | 10731204 / 12457996 | 11392206 / 11475968 | +6% | 5088 / 5086 | 542515 / 558608 |

- The fold of single additions gains most (about a third to a half): every addition copies a
  path of nodes, and each node cost four `Atom` creations and several publications before.
  The build gains about a sixth. Differences under about 15% (Q1) are noise on this machine.
- Q1's processes peak at the heap budget either way (protoCore keeps memory until it reaches
  it), so their RSS says nothing about the live set; the M2 peaks below the budget dropped by
  13% to 46%.
- Stage 2 (plan Task 12: no envelope or state dictionary for a shaped atom, a decode fast path,
  a cheaper oid draw) follows.

#### Atom weight, stage 2: shaped atoms keep only their slots

Plan Task 12 ([decisions.md](decisions.md), row Queries 12). An atom whose class has a record
shape whose slots are its persisted fields, in order, and whose record holds exactly those
fields, keeps its slots and its oid; its memo is the class's shape, shared, and `state` builds a
`PBFrozenDict` over the slots on each call (equal, never identical, to the dictionary it was
built or decoded from). Every other atom keeps the envelope as before: `PBObject` (no shape),
a record whose fields are in another order or with a field absent, a subclass that reorders its
slot fields, an opaque atom. The atom cache keeps the oid and values Array of a shaped record,
else the envelope. The decoder reads the payload keys in one pass, reads a record whose names
equal its shape's persisted fields straight into one values Array (`persistedNamesValid` keeps
classes declaring an invalid name on the checked path, with their errors), and decodes a list or
a `@tup` of scalars on the wire Array itself. The oid pool keeps the unused rest of its batch as
one immutable ByteArray and marks a batch by concatenating slices: the old batch built an
Array of 1024 oids by `at:put:`, about 276 of the ~303 cells of a draw. Bytes on disk, tree node
identity with `proto_db` and every error text are unchanged.

**Cells**, `bench/run_atom_weight.sh` as in stage 1, 2026-11-19, load average 2.4 to 3.1; before
at `f95b09f`, after at `69e6888`, both clean (`515cd86`, a key path fix, does not touch these
kinds). The loaded kinds read a stored tree of n nodes written by a process of their own:
retained is per loaded node, allocated is per record load (the decode included; with the cache,
a load the cache serves). Interquartile ranges 0.3 to 2.0 cells per object (empty runs 1.9 and
1.7):

| object | retained before | retained after | allocated before | allocated after |
|---|---|---|---|---|
| a `PBCountedKeyNode`, own key and value tuple | 51.2 | 33.7 | 200.1 | 134.0 |
| the same node, key, order key and value shared | 30.7 | 13.4 | 111.2 | 49.5 |
| the same, its oid drawn | 32.6 | 15.1 | 426.3 | 80.3 |
| a node of a 10^5-node tree built by `PBAvl keyFromSorted:` | 60.2 | 41.6 | 173.3 | 110.0 |
| a node loaded from storage, atom cache off | 69.6 | 48.2 | 2338.6 | 1382.8 |
| a node loaded from storage, atom cache on (entry included) | 75.8 | 51.4 | 384.6 | 314.3 |
| one oid drawn (`_PBOidPool next`) | 1.0 | 1.0 | 296.6 | 31.8 |

A diagnostic split of a record load (200 records of such a tree, after the change): reading the
record 302 cells, msgpack 587, the envelope decode 908 (1,620 before), the class's check and
publication 106.

**Wall time and memory**, as in stage 1 (`QUERY_M2_SIZES="2000 10000" QUERY_Q1_SIZES=10000
RUNS=3 bench/run_query.sh M2 Q1`, heap budget `PROTOCORE_HEAP_LIMIT_CELLS=80000000`), before
(`f95b09f`, a clean worktree of it) then after (`69e6888`). Runner provenance lines, unmodified:
`2026-11-19T19:53Z; protoBaseST f95b09f; protoST 0.12.0` and
`2026-11-19T19:56Z; protoBaseST 69e6888; protoST 0.12.0`. Load average 3.0 before and 2.3
after the first run, 2.3 and 3.9 for the second. Every run verified. Microseconds, minimum /
median of 3; peak RSS in MB:

| unit | protoBaseST before | protoBaseST after | change (min) | peak RSS before / after | `proto_db` (after run) |
|---|---|---|---|---|---|
| M2, 2000, build | 1090222 / 1118948 | 1003718 / 1030832 | -8% | 665 / 611 | 50058 / 52619 |
| M2, 2000, fold | 1909006 / 1963684 | 1526953 / 1599246 | -20% | 749 / 583 | 192044 / 205883 |
| M2, 10^4, build | 6234040 / 6547333 | 5816012 / 5982705 | -7% | 3352 / 3038 | 273432 / 274016 |
| M2, 10^4, fold | 12474643 / 12511415 | 10318996 / 11059922 | -17% | 4141 / 3034 | 1043149 / 1080007 |
| Q1, 10^4, index | 15653 / 15656 | 18236 / 18316 | +17% | 5086 / 4952 | 2123 / 2195 |
| Q1, 10^4, scan | 11535203 / 11586151 | 13090513 / 13539523 | +13% | 5086 / 5082 | 507110 / 530351 |

- M2's fold gains about a fifth and its peak RSS drops by a fifth to a quarter; the build gains
  under 10% (noise level).
- **Q1's index gap: a fresh-page fault mechanism is shown; a smaller per-row regression is not
  excluded** (review fix rounds 1 and 2). Two alternating pairs of Q1 alone (before `f95b09f`,
  after `515cd86`, load 2.4 to 3.8) had given index 17614 and 15935 before against 18568 and 19621
  after (minimums). A driver runs the 20 queries as the bench does and times each, and reads the heap
  trace (`PROTOCORE_HEAP_TRACE=1`) and the process's minor faults (`/proc/self/stat`) around each
  one, at the bench's heap budget, `f95b09f` against `a89cbae`, both clean, one process per run,
  alternating, 2026-11-19T21:06Z to about 21:30Z, load 2.5 to 4.8. Its window totals include the
  `/proc` reads and the marker writes, so only its per-query times compare with the bench; it
  verifies the rows (200), not the bench's checksum.
  - No collection lands in the index window on either side (after: no cycle in the whole
    process; before: one, finished before the window). On the after side one or two of the 20
    queries per run take 2.7 to 4.6 ms, each with 1,025 to 1,029 minor faults (one 4 MB chunk of
    fresh pages); the whole before window has 64 to 73 faults. The after side builds Q1 with
    fewer cells, reaches the timer before its first collection and allocates into memory the
    kernel has not mapped yet; the before side reuses cells its first collection swept. One
    faulting query of an earlier run was not slow (1,190 us with 1,027 faults).
  - The queries that do not fault are level only in the first of the three pairs; in the other
    two the after side's are about 1.5 times slower, unexplained (possibly the load; steady is
    every query but the first, which takes 1.3 to 2.7 ms on both sides):

    | pair | before: window / steady queries | after: window / steady queries | after: faulting queries |
    |---|---|---|---|
    | 1 | 19.5 ms / 0.75 to 0.88 ms | 22.3 ms / 0.76 to 1.04 ms | 1 (2.76 ms) |
    | 2 | 21.4 ms / 0.80 to 1.03 ms | 36.4 ms / 1.31 to 1.56 ms | 1 (3.69 ms) |
    | 3 | 31.1 ms / 1.13 to 1.38 ms | 50.1 ms / 1.72 to 1.96 ms | 2 (4.50, 4.57 ms) |

  - The control: 2 x 10^7 short-lived Arrays made after the build and before the timer (both
    sides then run 20 to 22 collections first) take the after side's window faults to 3 to 5 and
    its faulting queries go; six pairs then give windows of 27 to 48 ms on both sides (minimum
    27.3 ms before, 27.6 ms after; median about 35 and 31 ms), with queries over 2 ms and no
    faults on both sides as the load rose to 4.
  - So the fault mechanism is shown (the fault and collection counts do not depend on the load)
    and accounts for a gap of the bench's size (about 2.6 ms); the control is too noisy to
    exclude a per-row regression smaller than that. The final comparison of plan Task 10 (quiet, five
    interleaved runs) shows no Q1 index regression beyond noise
    ([above](#the-final-comparison-plan-task-10)). Where the heap stands when the timer starts depends on how many
    cells the build allocates (protoCore's heap policy), so Q1's index figures move whenever the
    build's cells change.
  - The scan: the table's +13% comes from a pass that ran every before unit, then every after
    unit (not alternating), so drift is the likely cause; the alternating driver pairs give
    11.60 and 12.10 s before against 11.18 and 10.56 s after (one collection in each window,
    pauses under 0.1 ms), and with the control 16.3 s against 12.9 s (one pair, load 4.8).
  - The driver, its runner and the raw outputs are in the task's working notes (`.superpowers/`,
    not in the repository).

#### Headline benchmarks re-measured on protoST 0.14.1 (V-pin, 2026-11-20)

The stack moved to protoST 0.14.1 on protoCore 3.6.1 (task V-pin of the vectors plan). The three
headline benchmarks were re-run, serially, on a quiet machine, as new runs beside the protoST 0.12.0
ones above; **no earlier figure is rewritten and nothing is asserted about time**. Every query run
ended `verified: 5 runs of each implementation report the same work (rows, queries, plan,
checksum)`, and every AVL and transaction run self-reported and passed its check. Indicative only: one
machine, one session, five rounds each.

- **Provenance.** The runner's line, unmodified: `2026-11-20T11:14Z; protoBaseST 119584a; protoST 0.14.1`.
  Commits: `7fbd139` (the pin move) and `119584a` (the primitive adoption), a clean tree for every
  run. The binaries: protoST 0.14.1 (`v0.14.1`, `15157d7`) on protoCore 3.6.1 (`v3.6.1`,
  `00a90df3`) and protoIO 0.7.0, the `pinned-361` release builds (`ldd` shows the pinned
  `libprotoCore.so.5`, never `/usr`'s); `proto_db` v2.0.0rc4 on CPython 3.14.6. The earlier
  figures above are `pinned-360` (protoST 0.12.0 on protoCore 3.6.0) at older protoBaseST commits.
- **Machine and load.** AMD Ryzen 5 5500U, 12 CPUs, Linux 7.0.0-43 (DEV12). Load average before
  and after: AVL 2.38 before (the runner prints no after figure); query run 2.38 before and 2.08 after (a short build by another
  session had just ended: the one-minute load was 2.5 when the AVL run started, the five-minute
  average 7.4); transactions 1.84 before and 2.10 after. The query run took 54 minutes
  (10:20Z to 11:14Z).
- **Commands.** `RUNS=5 bench/run_avl.sh pinned361=<protost>`, `RUNS=5 bench/run_tx.sh
  pinned361=<protost>`, `RUNS=5 bench/run_query.sh M1 M2 M3 P1 P2 P3`, with `PROTOST` and
  `PROTOBASE_REPO` set.

**AVL operations** (microseconds per operation, minimum / median):

| operation | ops | ProtoBase | pinned361 | ratio pinned361 |
|---|---|---|---|---|
| posAppend | 1000 | 17.0 / 17.2 | 147.2 / 150.5 | 9x |
| keyPut-new | 1000 | 26.1 / 26.4 | 181.5 / 189.0 | 7x |
| posAt | 2000 | 0.8 / 0.8 | 15.3 / 15.4 | 20x |
| keyAt | 2000 | 1.8 / 1.9 | 27.7 / 28.1 | 15x |
| keyPut-replace | 500 | 19.2 / 19.3 | 172.3 / 172.9 | 9x |
| check-pos | 3 | 678.5 / 686.6 | 18167.7 / 18561.3 | 27x |
| check-key | 3 | 1025.0 / 1038.7 | 31033.7 / 31948.3 | 30x |

**Commits per second** (`TX_SCALE=1`, minimum / median wall time; segments on ZFS, `fsync`):

| profile | transactions | ProtoBase commits/s | ProtoBase retries | pinned361 commits/s | pinned361 retries | ratio pinned361 |
|---|---|---|---|---|---|---|
| tiny | 100 | 163.9 / 155.3 | 0-0 | 54.1 / 53.6 | 0-0 | 0.330x |
| small-record | 100 | 159.1 / 156.5 | 0-0 | 51.1 / 50.2 | 0-0 | 0.321x |
| batch-100 | 10 | 75.7 / 74.2 | 0-0 | 8.9 / 8.7 | 0-0 | 0.118x |
| conc-disjoint-1 | 120 | 160.1 / 157.4 | 0-0 | 47.1 / 47.1 | 0-0 | 0.294x |
| conc-disjoint-2 | 120 | 152.9 / 151.3 | 0-0 | 49.6 / 49.0 | 0-0 | 0.325x |
| conc-disjoint-4 | 120 | 256.8 / 246.9 | 0-0 | 52.7 / 51.6 | 0-0 | 0.205x |
| conc-merge-1 | 120 | 155.4 / 152.2 | 0-0 | 38.3 / 37.2 | 0-0 | 0.246x |
| conc-merge-2 | 120 | 144.8 / 143.7 | 0-0 | 45.7 / 41.8 | 0-0 | 0.315x |
| conc-merge-4 | 120 | 238.2 / 232.8 | 0-0 | 46.1 / 45.3 | 0-0 | 0.193x |
| conc-hot-1 | 120 | 168.3 / 163.4 | 0-0 | 56.1 / 55.4 | 0-0 | 0.334x |
| conc-hot-2 | 120 | 156.0 / 152.2 | 9-38 | 53.1 / 50.4 | 14-56 | 0.340x |
| conc-hot-4 | 120 | 135.8 / 133.9 | 57-117 | 44.9 / 43.5 | 41-144 | 0.330x |

**M1, M2, M3 (commits with indexes, bulk build against fold, the cluster) and P1, P2, P3 (the
planner)**, microseconds, minimum / median; protoBaseST peak RSS in MB:

| id | size | plan | proto_db us min / median | protoBaseST us min / median | ratio st/py (min) | peak RSS MB py / st |
|---|---|---|---|---|---|---|
| M1 | 600 | idx0 | 1287521 / 1343151 | 4759445 / 4821141 | 3.7x | 27 / 1085 |
| M1 | 600 | idx1 | 1533237 / 1563797 | 13755653 / 13890551 | 9.0x | 34 / 4128 |
| M1 | 600 | idx3 | 2060544 / 2120526 | 32500847 / 33015599 | 15.8x | 46 / 5140 |
| M2 | 100 | build | 1882 / 1900 | 36571 / 38469 | 19.4x | 23 / 97 |
| M2 | 100 | fold | 5022 / 5065 | 44404 / 45836 | 8.8x | 24 / 97 |
| M2 | 1000 | build | 19122 / 20021 | 434696 / 454779 | 22.7x | 25 / 264 |
| M2 | 1000 | fold | 66717 / 67293 | 628485 / 650177 | 9.4x | 24 / 240 |
| M2 | 10000 | build | 204316 / 212870 | 5024412 / 5198421 | 24.6x | 38 / 2326 |
| M2 | 10000 | fold | 838089 / 858723 | 8746668 / 8985768 | 10.4x | 35 / 2186 |
| M2 | 100000 | build | 2709895 / 2783515 | 53778817 / 54455202 | 19.8x | 172 / 5299 |
| M2 | 100000 | fold | 12838432 / 12946482 | 110909792 / 114651304 | 8.6x | 142 / 5270 |
| M3 | 600 | idx0 | 800313 / 813732 | 3074622 / 3103652 | 3.8x | 27 / 837 |
| M3 | 600 | idx1 | 936415 / 938474 | 8448352 / 8662500 | 9.0x | 31 / 2988 |
| M3 | 600 | idx3 | 1210178 / 1234176 | 20858878 / 21063507 | 17.2x | 40 / 5140 |
| M3 | 600 | idx0-c3 | - | 5903094 / 6014560 | - | - / 1165 (largest member) |
| M3 | 600 | idx1-c3 | - | 14380158 / 14797360 | - | - / 1889 (largest member) |
| M3 | 600 | idx3-c3 | - | 44074416 / 54417679 | - | - / 2088 (largest member) |
| P1 | 1 | idx0 | 5417 / 5482 | 139080 / 141630 | 25.7x | 24 / 401 |
| P1 | 1 | idx2 | 11966 / 12177 | 321127 / 331124 | 26.8x | 26 / 773 |
| P1 | 1 | idx8 | 14110 / 14200 | 405612 / 428468 | 28.7x | 30 / 1821 |
| P1 | 8 | idx0 | 15780 / 15862 | 485019 / 489978 | 30.7x | 25 / 593 |
| P1 | 8 | idx2 | 37029 / 39161 | 855204 / 885951 | 23.1x | 27 / 1025 |
| P1 | 8 | idx8 | 95436 / 98021 | 1766945 / 1822154 | 18.5x | 31 / 2246 |
| P1 | 32 | idx0 | 43683 / 45439 | 1762051 / 1782438 | 40.3x | 27 / 1254 |
| P1 | 32 | idx2 | 188884 / 191905 | 3126482 / 3153748 | 16.6x | 29 / 1954 |
| P1 | 32 | idx8 | 600098 / 615330 | 7322972 / 7444189 | 12.2x | 34 / 3996 |
| P2 | 2000 | r0001-index | 59 / 60 | 741 / 780 | 12.6x | 31 / 1465 |
| P2 | 2000 | r0001-scan | 20738 / 21605 | 495952 / 507682 | 23.9x | 31 / 1580 |
| P2 | 2000 | r0010-index | 186 / 195 | 3530 / 3800 | 19.0x | 31 / 1464 |
| P2 | 2000 | r0010-scan | 21222 / 21514 | 506282 / 509462 | 23.9x | 31 / 1577 |
| P2 | 2000 | r0100-index | 1401 / 1416 | 41026 / 44082 | 29.3x | 31 / 1476 |
| P2 | 2000 | r0100-scan | 20418 / 21779 | 484237 / 495626 | 23.7x | 31 / 1577 |
| P2 | 2000 | r0500-index | 6894 / 7029 | 207523 / 211418 | 30.1x | 31 / 1517 |
| P2 | 2000 | r0500-scan | 20393 / 21371 | 507889 / 530196 | 24.9x | 31 / 1584 |
| P2 | 2000 | r0900-index | 12441 / 12631 | 364170 / 370748 | 29.3x | 31 / 1561 |
| P2 | 2000 | r0900-scan | 20652 / 21105 | 515007 / 531713 | 24.9x | 31 / 1589 |
| P2 | 2000 | r0990-index | 13967 / 14663 | 405322 / 420817 | 29.0x | 31 / 1569 |
| P2 | 2000 | r0990-scan | 20682 / 21308 | 530426 / 534371 | 25.6x | 31 / 1589 |
| P2 | 2000 | r1000-index | 13753 / 13814 | 406428 / 422988 | 29.6x | 31 / 1569 |
| P2 | 2000 | r1000-scan | 21132 / 21582 | 527112 / 540162 | 24.9x | 31 / 1589 |
| P2 | 2000 | ne-few-index | 2950 / 3047 | 91996 / 95407 | 31.2x | 31 / 1493 |
| P2 | 2000 | ne-few-scan | 20315 / 20780 | 450156 / 460804 | 22.2x | 31 / 1565 |
| P2 | 2000 | ne-many-index | 15475 / 16171 | 357701 / 358948 | 23.1x | 31 / 1569 |
| P2 | 2000 | ne-many-scan | 20897 / 21042 | 449763 / 458561 | 21.5x | 31 / 1569 |
| P3 | 2000 | intersect | 7815 / 7839 | 56360 / 57203 | 7.2x | 27 / 1324 |
| P3 | 2000 | filter | 2234 / 2309 | 52184 / 55121 | 23.4x | 27 / 1316 |

M3 cluster retries per run (block runs beyond one per commit): idx0-c3 27, 1, 0, 0, 0; idx1-c3 31,
26, 29, 28, 25; idx3-c3 172, 153, 174, 115, 171.

### Vectors

**VB0, the vector math kernel** (vectors phase task V1; an input to ruling VQ2). `RUNS=5
bench/run_query.sh VB0`, measured 2026-11-20 12:29-12:41 UTC on an AMD Ryzen 5 5500U (12 CPUs, Linux
7.0.0-43-generic), load average 1.35 before and 2.39 after; protoBaseST `a36dc7f`, protoST 0.14.1
(`worktrees/pinned-361/protoST/build_release/protost`, protoCore 3.6.1), `proto_db` `v2.0.0rc4` on
CPython 3.14.6 and glibc 2.43 in its reference mode (numpy and hnswlib blocked, every score its
pure-Python `exact_score`; the default mode, with numpy, was skipped: `tests/interop/.venv-numpy` does
not exist yet). Data: `proto_db`'s clustered benchmark set (`benchmarks/workloads/vector.py:18-26`,
seed 51, 16 centres), 10^4 vectors and one query, read by both sides from one MessagePack file
(`bench/py_vector_data.py`). Each unit times one operation over the 10^4 vectors (`bench/vector_workload.st`
states them): `products` the dim products of each vector, `naive` a plain left-to-right sum of
precomputed products, `fsum` CPython's `math.fsum` of the same products, and the three scores. The
runner printed `verified`: every run of both sides reported the same CRC-32 of the results' bytes,
so every product, sum and score is `proto_db`'s to the bit. Times in microseconds, minimum and median
of 5 interleaved runs; nothing is asserted about time.

| dim | op | proto_db us min / median | protoBaseST us min / median | ratio st/py (min) | peak RSS MB py / st |
|---|---|---|---|---|---|
| 8 | products | 8298 / 8788 | 169151 / 173085 | 20.4x | 31 / 413 |
| 8 | naive | 2006 / 2028 | 90532 / 94478 | 45.1x | 27 / 334 |
| 8 | fsum | 2139 / 2259 | 443275 / 468377 | 207.2x | 27 / 474 |
| 8 | ip | 8434 / 8826 | 653086 / 664258 | 77.4x | 27 / 554 |
| 8 | l2 | 10306 / 10893 | 716641 / 731393 | 69.5x | 27 / 578 |
| 8 | cosine | 20571 / 20644 | 1716774 / 1786196 | 83.5x | 27 / 1063 |
| 32 | products | 32169 / 32620 | 444381 / 467272 | 13.8x | 64 / 1135 |
| 32 | naive | 5862 / 5977 | 278608 / 287513 | 47.5x | 47 / 868 |
| 32 | fsum | 7539 / 7910 | 2445678 / 2505955 | 324.4x | 47 / 1856 |
| 32 | ip | 23599 / 24997 | 2916613 / 3032046 | 123.6x | 47 / 2036 |
| 32 | l2 | 27712 / 29318 | 3132586 / 3248288 | 113.0x | 47 / 2144 |
| 32 | cosine | 55337 / 58146 | 8916927 / 9178626 | 161.1x | 47 / 4943 |
| 128 | products | 107690 / 108909 | 1584645 / 1618040 | 14.7x | 197 / 4155 |
| 128 | naive | 21180 / 22011 | 1010019 / 1033946 | 47.7x | 128 / 3092 |
| 128 | fsum | 28192 / 29459 | 10128024 / 10540129 | 359.3x | 128 / 4964 |
| 128 | ip | 83195 / 87900 | 11630306 / 12140643 | 139.8x | 128 / 4966 |
| 128 | l2 | 103367 / 106770 | 13340647 / 13612491 | 129.1x | 128 / 4966 |
| 128 | cosine | 210111 / 214950 | 33496258 / 34064568 | 159.4x | 128 / 4964 |

What the table says, and what it does not:

- **The sum dominates a score.** An `ip` score is the products plus one fsum; the fsum alone takes
  68% (dim 8), 84% (32) and 87% (128) of the `ip` time in protoBaseST, against 25%, 32% and 34% in
  `proto_db`, whose `math.fsum` is C. The correctly rounded sum costs 4.9, 8.8 and 10.0 times a naive
  interpreted sum: the ratio grows with the dimension (more partials per sum).
- **A score per vector** (the minimum divided by 10^4) costs 65, 292 and 1163 us for `ip` at dim 8,
  32 and 128, 72, 313 and 1334 us for `l2`, and 2.63, 3.06 and 2.88 times the `ip` time for cosine (two
  norms and a dot product, three fsums); the scores are 69.5 (`l2`, dim 8) to 161.1 (cosine, dim 32)
  times `proto_db`'s pure-Python scores. An exact search over 10^4 vectors of dim 32 would spend about 3 s in
  the kernel alone; V8 measures searches, and ruling VQ2 decides on those figures whether the protoST
  fsum primitive (Addendum V, 2.2.4) is built.
- **Peak resident set** is not determinant: protoCore keeps memory until it needs it, up to the heap
  budget (`PROTOCORE_HEAP_LIMIT_CELLS`, 80,000,000 cells here), which the dim-128 units reach; it is
  reported, not compared.

**VB0 on protoST 0.15.0, with the fsum primitives** (task VP-adopt; the run above is kept as the
0.14.1 baseline). `RUNS=5 bench/run_query.sh VB0`, measured 2026-11-20 14:42-14:47 UTC on the same
machine, load average 2.95 / 3.34 / 3.36 (1, 5 and 15 minutes) before and 2.64 / 3.17 / 3.30 after;
protoBaseST `2f6ab44` (committed tree), protoST 0.15.0
(`worktrees/pinned-0150/protoST/build_release/protost`, protoCore 3.6.1 per `ldd`, protoIO 0.7.0),
`PBVectorMath usesFsumPrimitive` true; `proto_db` and the data as above. The runner printed
`verified`: every result is `proto_db`'s to the bit, as with the Smalltalk kernel.

| dim | op | proto_db us min / median | protoBaseST us min / median | ratio st/py (min) | 0.14.1 / 0.15.0 (min) | peak RSS MB py / st |
|---|---|---|---|---|---|---|
| 8 | products | 8740 / 9304 | 188261 / 191055 | 21.5x | 0.9x | 31 / 414 |
| 8 | naive | 2168 / 2252 | 97419 / 98238 | 44.9x | 0.9x | 27 / 335 |
| 8 | fsum | 2369 / 2388 | 49839 / 50811 | 21.0x | 8.9x | 27 / 291 |
| 8 | ip | 9359 / 9930 | 171323 / 176481 | 18.3x | 3.8x | 27 / 335 |
| 8 | l2 | 11546 / 11712 | 163151 / 167690 | 14.1x | 4.4x | 27 / 331 |
| 8 | cosine | 21178 / 23966 | 354295 / 387420 | 16.7x | 4.8x | 27 / 431 |
| 32 | products | 33268 / 34371 | 483211 / 509456 | 14.5x | 0.9x | 64 / 1136 |
| 32 | naive | 6451 / 6593 | 288522 / 306205 | 44.7x | 1.0x | 47 / 869 |
| 32 | fsum | 8553 / 8958 | 66501 / 69425 | 7.8x | 36.8x | 47 / 673 |
| 32 | ip | 27924 / 28833 | 205215 / 212894 | 7.3x | 14.2x | 47 / 717 |
| 32 | l2 | 34016 / 34498 | 192865 / 203766 | 5.7x | 16.2x | 47 / 713 |
| 32 | cosine | 63935 / 69025 | 396953 / 410627 | 6.2x | 22.5x | 47 / 813 |
| 128 | products | 113340 / 116277 | 1717960 / 1768144 | 15.2x | 0.9x | 197 / 4156 |
| 128 | naive | 23999 / 24983 | 1090660 / 1136748 | 45.4x | 0.9x | 128 / 3093 |
| 128 | fsum | 31106 / 33546 | 134054 / 137761 | 4.3x | 75.6x | 128 / 2297 |
| 128 | ip | 100361 / 102443 | 298788 / 310040 | 3.0x | 38.9x | 128 / 2345 |
| 128 | l2 | 113650 / 118571 | 297544 / 301457 | 2.6x | 44.8x | 128 / 2337 |
| 128 | cosine | 235901 / 236327 | 597312 / 601554 | 2.5x | 56.1x | 128 / 2441 |

What changed, and what did not:

- **The sum no longer dominates a score.** The primitive fsum of precomputed products costs 0.51,
  0.23 and 0.12 times the naive interpreted sum at dim 8, 32 and 128 (it was 4.9, 8.8 and 10.0
  times). An `ip` score is now one `fsumOfProducts:with:` call, products and sum in C; the `fsum`
  unit (the same sum over Arrays of products) is 29%, 32% and 45% of the `ip` time, and the rest of
  a score is interpreted overhead: the call, the dispatch on the metric and the copy of each
  `PBTuple` vector to an Array (below). A score per vector costs 17.1, 20.5 and 29.9 us for `ip`,
  16.3, 19.3 and 29.8 us for `l2`, and 35.4, 39.7 and 59.7 us for cosine; the scores are 2.5 (cosine,
  dim 128) to 18.3 (`ip`, dim 8) times `proto_db`'s pure-Python scores (69.5 to 161.1 times on 0.14.1).
- **products and naive** run no primitive; their 0.9x to 1.0x against the 0.14.1 run is the noise
  between the two runs, not a regression.
- **PBTuple against Array.** The primitives read Arrays and OrderedCollections directly, any other
  sequence through `size` and `at:`; the indexes hold vectors as `PBTuple`s. Measured on the same
  data, one process per dim, minimum of 5 (`score:query:vector:` over the 10^4 vectors, us): `ip`
  with the `PBTuple`s handed to the primitive 175566, 355939 and 1117629 at dim 8, 32 and 128;
  with each operand copied to an Array first 151814, 176236 and 296936; with Arrays held beforehand
  (no copy, a bound) 107284, 134877 and 234988. Cosine: 529291, 1080980 and 3083632; copied 377236,
  438701 and 578321; bound 323380, 377313 and 498554. `fsumOfProducts:with:` alone, `PBTuple`s
  against Arrays: 77939 against 15954, 264050 against 40180, 1004944 against 168326. The copy is one
  Array per operand per score, and it is a net win at every dim and metric (1.2 to 5.3 times), so
  `score:query:vector:` copies a `PBTuple` or `PBFrozenList` operand to an Array when the primitives
  are in use (`2f6ab44`); the table above is measured with it. A first run without the copy
  (`cd89a2e`, same day) measured `ip` at 160858, 348247 and 1054215 us.
- The figures are one machine's, under a load average near 3; nothing is asserted about time.

**VB3 and VB5, vector index maintenance** (vectors phase task V5). `RUNS=5 bench/run_query.sh VB3
VB5`, measured 2026-11-20 17:11-18:06 UTC on the same machine, load average 2.58 before and 2.37
after (the runner starts only below 3); protoBaseST `880127e` (clean tree), protoST 0.15.0
(`worktrees/pinned-0150/protoST/build_release/protost`, the benchmark binary; the tests of the
same commit pass on the floor, protoST 0.14.1 at `worktrees/pinned-361/protoST/build_release/protost`),
`proto_db` `v2.0.0rc4` on CPython 3.14.6 and glibc 2.43 in its reference mode (numpy and hnswlib
blocked; `tests/interop/.venv-numpy` exists, but `proto_db`'s numpy centroids cannot be verified
against protoBaseST's, DV3, so that mode is not measured). Data: `proto_db`'s clustered set at dim
8 (`bench/py_vector_data.py`); indexes on the element, l2: exact, or `ivf_flat` with nlist 16,
train_iters 10, seed 51 and retrain_growth 1.03 (`bench/_vector_bench.st`). Every run of both
implementations reported the same work, `verified`: rows, commits and a CRC-32 over the elements,
the index counts and, for VB3, every IVF centroid; each run with an IVF index is refused unless the
index retrained past its start. Commits per second are the commits divided by the minimum time over
5 runs (the median is within 3 % of it everywhere):

| unit | proto_db | protoBaseST | peak RSS MB py / st |
|---|---|---|---|
| VB3, 600 + 200 appends, no index | 157.3 | 36.7 | 26 / 1106 |
| VB3, 600 + 200 appends, exact | 132.6 | 16.6 | 36 / 5102 |
| VB3, 600 + 200 appends, IVF (nine retrains, at 618 to 787) | 51.1 | 3.3 | 45 / 5082 |
| VB3, 5000 + 200 appends, no index | 151.9 | 32.2 | 34 / 2480 |
| VB3, 5000 + 200 appends, exact | 126.4 | 15.1 | 64 / 5137 |
| VB3, 5000 + 200 appends, IVF (one retrain, at 5150) | 56.9 | 3.3 | 83 / 5161 |
| VB5, 120 blind writes merged onto 600, exact | 129.7 | 16.2 | 32 / 3929 |
| VB5, the same, IVF (six retrains, at 618 to 719) | 48.7 | 3.2 | 39 / 5082 |
| VB5, the same in a three-member cluster, exact | - | 8.4 | - / 2074 (largest member) |
| VB5, the same in a three-member cluster, IVF (90 s lease) | - | 2.7 | - / 2090 (largest member) |

- **A retrain is the cost.** Each VB3 commit reads the list and appends one vector; with an exact
  index protoBaseST commits 2.2 times slower than with none, `proto_db` 1.2 times. An IVF retrain
  is k-means over every member on the pure-Python path, which protoBaseST runs operation for
  operation: each distance's sum is `sumNonNegative:`, which is the fsum primitive on protoST
  0.15.0 and the Smalltalk msum on 0.14.1 (where it is about 78 % of a distance); the `pow` squares
  (`raisedTo: 2`, a primitive call each) and the boxed Floats they allocate stay in Smalltalk on
  both. That is why VB3's IVF rate is the same at 600 (nine retrains, over 618 to 787 vectors) and
  at 5000 (one retrain over 5150 vectors). One training, `build:` of the VB data at dim 8, nlist 16,
  10 iterations, each size in a fresh process (indicative: single runs, load about 1.6, after the
  fix-round-1 k-means below):

  | | 631 vectors | 696 vectors |
  |---|---|---|
  | protoBaseST, protoST 0.14.1 (the floor) | 7752 ms | 8421 ms |
  | protoBaseST, protoST 0.15.0 (the bench binary) | 2799 ms | 3058 ms |
  | `proto_db`, pure path, `build:` | 193 ms | 214 ms |
  | `proto_db`, pure path, `_kmeans` alone (the reviewer's figures) | 153 ms | 173 ms |
  | `proto_db`, numpy 2.3.5 (its default mode), `_kmeans` alone (the reviewer's figures) | 4.4 ms | 4.3 ms |

  The VB3/VB5 figures above were measured before that fix (V5 fix round 1:
  `kmeans:nlist:iterations:seed:` copies each vector to an Array once, reuses one squares buffer
  and adds the sums in place, the same operations in the same order, so the centroids are the same
  bytes); the review measured that k-means at 3835 ms (631) on 0.15.0 and 9547 ms on 0.14.1. A
  first figure of this section, 10.6 s over 631 and 15.2 s over 696, was 0.14.1, both sizes in one
  process: a retrain gets slower as the process ages (the review timed four in one 0.15.0 process at
  2.3, 2.7, 3.5 and 3.4 s, whatever the size), which made 696 look much dearer than 631.
- **In a cluster a retrain needs a long lease.** The merge of a blind write, and its retrain, runs
  in the round's build, under the write permission, which a member believes for a third of the
  lease (the drift margin is two thirds): 667 ms with `proto_db`'s default 2000 ms. A retrain that
  takes longer outlasts its permission at every attempt (a truthful retryable conflict, R121), so it
  never commits. Measured with retrain_growth 1.05 and the default lease (protoST 0.14.1): no member
  of the IVF cluster unit finished its 40 commits within 1700 s, while the exact unit finishes in
  15 s. VB5's IVF cluster unit therefore runs with `leaseDuration` 90000 ms (a 30 s permission;
  `bench/run_query.sh`, `QUERY_VB5_IVF_LEASE_MS`) and an acquire timeout of three leases (the new
  members' startup grace grows to 150 s, untimed): it then commits with no retry in 5 of 5 runs.
  The exact cluster unit, on the default lease, retried 33, 31, 28, 27 and 28 times per 120
  commits. `proto_db`'s own k-means fits the default permission at this size; at a few thousand
  members it would not either. Safety is not affected: a refused attempt writes nothing. A longer
  lease has a price: when the holder of the write permission dies, no member can write until its
  lease and drift margin have passed (with 90 s, two and a half minutes), and a starting member
  grants nothing for the same span. The advice stands until the k-means distance gets a protoST
  primitive (planned for protoST 0.16.0), when the retrain will be measured again against the
  default 667 ms permission. (Measured on 0.16.0 in the run below: the retrain still does not fit,
  so the advice stays, with a sizing rule.)
- The peak resident set of a protoBaseST unit is mostly the heap budget it is allowed
  (`QUERY_HEAP_LIMIT_CELLS`, about 5 GB), which protoCore keeps until it needs it; it is not a
  measure of the working set.

**VB3 and VB5 on protoST 0.16.0, with `proto_db`'s default mode** (task V5, fix round 2).
`RUNS=5 bench/run_query.sh VB3 VB5`, measured 2026-11-21, ending 17:01 UTC, on the same machine,
load average 1.62 before and 3.10 after (the machine was also building other projects at times);
protoBaseST `97e25e4` (clean tree), protoST 0.16.0
(`worktrees/pinned-0160/protoST/build_release/protost`, protoCore 3.6.1 per `ldd`, now the
benchmark binary: its `Float fsumOfPowSquaredDifferences:with:` computes every k-means distance,
DV3), the same data, indexes and verification as the run above. `proto_db` `v2.0.0rc4` ran in
both of its modes: the reference mode (numpy and hnswlib blocked, CPython 3.14.6), whose work every
protoBaseST run equals (`verified`), and its default mode (numpy 2.3.5 in
`tests/interop/.venv-numpy`, CPython 3.14.0), whose counts (contents, members, invalid
occurrences, trained sizes, centroid counts) and, except for VB3's IVF checksum, which covers the
centroids, whole work equal the reference mode's. Its centroids are numpy's and are not compared
(DV3): that column is a timing of the same commits, not of the same training. Commits per second,
the commits over the minimum time of 5 runs (every median within 6 % of it):

| unit | proto_db, reference | proto_db, numpy | protoBaseST | peak RSS MB py / st |
|---|---|---|---|---|
| VB3, 600 + 200 appends, no index | 156.2 | 142.3 | 35.9 | 27 / 1105 |
| VB3, 600 + 200 appends, exact | 133.0 | 119.3 | 16.2 | 36 / 5118 |
| VB3, 600 + 200 appends, IVF | 51.6 | 69.8 | 5.0 | 45 / 5093 |
| VB3, 5000 + 200 appends, no index | 147.3 | 136.6 | 32.1 | 34 / 2484 |
| VB3, 5000 + 200 appends, exact | 129.2 | 108.7 | 15.1 | 64 / 5136 |
| VB3, 5000 + 200 appends, IVF | 57.4 | 75.4 | 5.1 | 83 / 5131 |
| VB5, 120 blind writes merged onto 600, exact | 132.3 | 114.1 | 16.1 | 32 / 3929 |
| VB5, the same, IVF | 50.8 | 73.1 | 4.7 | 39 / 5093 |
| VB5, the same in a three-member cluster, exact | - | - | 8.1 | - / 2074 (largest member) |
| VB5, the same in a three-member cluster, IVF (90 s lease) | - | - | 3.7 | - / 2075 (largest member) |

- **The primitive's gain.** An IVF commit rate rose from 3.3 to 5.0 (VB3 at 600), 3.3 to 5.1 (VB3
  at 5000) and 3.2 to 4.7 (VB5) commits per second against 0.15.0, 2.7 to 3.7 in the cluster
  (these two runs also differ in fix round 1's k-means buffers, which only 0.16.0's run has). The
  units without an IVF index are unchanged (35.9 against 36.7, 16.2 against 16.6: noise of the
  load). `proto_db` commits 10 to 11 times faster than protoBaseST with an IVF index in its reference
  mode, 14 to 16 times with numpy; its default mode is slower than its reference mode where nothing trains (other CPython
  patch release in that venv; not investigated), faster where an IVF index retrains.
- **The retrain against the default permission.** One training, each size in a fresh process
  (`build:` of the VB data, then `_retrained` of the result, which is what a merge crossing the
  threshold runs; dim 8, nlist 16, 10 iterations), measured before the run above under the bench
  marker at load 2.3 rising to 4.0 (indicative: single runs, three at the two VB sizes):

  | members | `build:` | retrain (`_retrained`) |
  |---|---|---|
  | 631 | 2047 to 2151 ms | 1555 to 1636 ms |
  | 696 | 2200 to 2353 ms | 1747 to 1935 ms |
  | 1000 | 3874 ms | 3404 ms |
  | 2000 | 9182 ms | 6941 ms |
  | 5150 | 26535 ms | 19080 ms |

  Per member, the retrain costs 2.5 to 2.6 ms at 631, 2.5 to 2.8 ms at 696, 3.4 ms at 1000, 3.5 ms
  at 2000 and 3.7 ms at 5150: it grows with the size. k-means is about half of a retrain; the rest is rebuilding the members: the store walk (each
  member's order key recomputed, then a sort) about 20 %, the store rebuild about 15 %, and the
  assignment of every member to its list (`listFor:`) about 10 %, the smallest part (the V5 review's
  split at 631 members, each part timed alone, load about 3.5, indicative). A later speed pass
  should start from the store walk. A retrain is still 2.3 to 2.9 times the 667 ms a member believes a permission under
  the default 2000 ms lease, so the long-lease requirement of a cluster that retrains an IVF index
  stays, and VB5's IVF cluster unit keeps its 90 s lease (it retried 0 times in 5 runs; the exact
  unit, on the default lease, 34, 31, 28, 30 and 30). **Sizing rule:** a build must fit in the
  believed permission less the send reserve, a third of the lease less a twelfth, so the lease
  must exceed four times the measured retrain for the index's size. On protoST 0.16.0 at
  dim 8 (nlist 16, 10 iterations) a retrain costs a growing amount per member, 2.5 ms at 631 members
  rising to 3.7 ms at 5150, so up to about 4 ms per member over the measured range: a lease above
  16 ms per member, about 11 s for 700 members and 80 s for 5000, with headroom for load. The lease bounds the write outage after a holder dies,
  which is the price.

**VB1 and VB2, vector search** (vectors phase task V6). `RUNS=5 bench/run_query.sh VB1 VB2`,
measured 2026-11-21, ending 19:58 UTC, on an AMD Ryzen 5 5500U (12 CPUs, Linux 7.0.0-43-generic),
load average 1.78 before and 2.08 after; protoBaseST `09e9d4f` (the clean committed tree), protoST
0.16.0 (`worktrees/pinned-0160/protoST/build_release/protost`), `proto_db` `v2.0.0rc4` in its
reference mode (CPython 3.14.6, glibc 2.43, numpy and hnswlib blocked) and its default mode (column
numpy: numpy 2.3.5, CPython 3.14.0, `tests/interop/.venv-numpy`). Data: `proto_db`'s clustered
benchmark set (seed 51, 16 centres) with 10 query points (`bench/py_vector_data.py`); k = 10; the
records `{ 'i'. 'vec' }` searched through a `PBVectorSearch` (`proto_db`: `VectorSearch`) over the
index's plan, built by the program: the plan both planners build for near(k) on an indexed collection. `-first` is the first query after the
index is built, `-knn` the 10 queries (the first among them again); VB2's `-build` is the
`ivf_flat` build (nlist 100, k-means on 10^4 vectors of dim 32), `-nprobe<p>` the 10 queries on the
same trained index with that nprobe. The runner printed `verified`: every run of every
implementation reported `proto_db`'s first run's work, so VB1's answers are `proto_db`'s in both of
its modes (exact answers do not depend on numpy), and VB2's centroids and answers are those of its
reference mode; its numpy mode trains its own centroids (DV3) and is verified by its counts only.
Recall at 10 against the exact answer, over the 10 queries, was the same in all three: 46 of 100 at
nprobe 1, 85 at nprobe 4, 100 at nprobe 100. Times in microseconds, minimum and median of 5
interleaved runs; nothing is asserted about time.

| id | size | plan | proto_db us min / median | protoBaseST us min / median | ratio st/py (min) | peak RSS MB py / st | proto_db numpy us min / median |
|---|---|---|---|---|---|---|---|
| VB1 | 1000 | d8-cosine-first | 7218 / 7355 | 57825 / 61184 | 8.0x | 25 / 690 | 2359 / 2597 |
| VB1 | 1000 | d8-cosine-knn | 62024 / 67962 | 586644 / 630240 | 9.5x | 25 / 690 | 3148 / 3496 |
| VB1 | 1000 | d8-l2-first | 5699 / 6348 | 41481 / 44389 | 7.3x | 25 / 566 | 1758 / 2411 |
| VB1 | 1000 | d8-l2-knn | 52120 / 55621 | 416098 / 435433 | 8.0x | 25 / 566 | 2291 / 3163 |
| VB1 | 1000 | d32-cosine-first | 10443 / 11806 | 62752 / 64007 | 6.0x | 26 / 775 | 3007 / 3092 |
| VB1 | 1000 | d32-cosine-knn | 100088 / 112890 | 638561 / 661812 | 6.4x | 26 / 775 | 3862 / 3983 |
| VB1 | 1000 | d32-l2-first | 7624 / 8688 | 42381 / 45254 | 5.6x | 26 / 650 | 2945 / 3238 |
| VB1 | 1000 | d32-l2-knn | 72244 / 78409 | 451270 / 452496 | 6.2x | 26 / 650 | 3289 / 3469 |
| VB1 | 10000 | d8-cosine-first | 132369 / 133825 | 597254 / 616935 | 4.5x | 48 / 5092 | 15630 / 16188 |
| VB1 | 10000 | d8-cosine-knn | 900436 / 915571 | 6320614 / 6346510 | 7.0x | 48 / 5092 | 3604 / 3779 |
| VB1 | 10000 | d8-l2-first | 123199 / 124910 | 436108 / 459867 | 3.5x | 48 / 5092 | 15219 / 15500 |
| VB1 | 10000 | d8-l2-knn | 787593 / 801469 | 4461892 / 4727204 | 5.7x | 48 / 5092 | 4482 / 4629 |
| VB1 | 10000 | d32-cosine-first | 173640 / 176979 | 666384 / 675408 | 3.8x | 61 / 5089 | 26370 / 27713 |
| VB1 | 10000 | d32-cosine-knn | 1289632 / 1298917 | 6954950 / 7155001 | 5.4x | 61 / 5089 | 6200 / 6816 |
| VB1 | 10000 | d32-l2-first | 154145 / 164234 | 479321 / 484646 | 3.1x | 61 / 5089 | 27739 / 28208 |
| VB1 | 10000 | d32-l2-knn | 1016612 / 1034286 | 4944847 / 4997425 | 4.9x | 61 / 5089 | 9880 / 10261 |
| VB2 | 10000 | d32-ivf-build | 56686826 / 56950388 | 163933587 / 167256841 | 2.9x | 79 / 5089 | 1245128 / 1312498 |
| VB2 | 10000 | d32-ivf-nprobe1 | 21920 / 22080 | 617364 / 768519 | 28.2x | 79 / 5089 | 11798 / 11945 |
| VB2 | 10000 | d32-ivf-nprobe4 | 144924 / 149445 | 1095917 / 1159150 | 7.6x | 79 / 5089 | 11414 / 11716 |
| VB2 | 10000 | d32-ivf-nprobe100 | 1362887 / 1393694 | 14563864 / 14671563 | 10.7x | 79 / 5089 | 21535 / 22158 |

Observed: protoBaseST's first query costs what every later one costs (no derived cache, DV4),
where `proto_db`'s first query builds its flat snapshot (in the reference mode 1.0 to 1.2 times
a later query at 10^3 and 1.3 to 1.6 times at 10^4; with numpy, its matrix too: 7.5 to 9 times at
10^3, 28 to 43 times at 10^4). An exact
query over 10^4 vectors takes about 0.45 to 0.7 s on protoST 0.16.0: 4.9 to 7.0 times
`proto_db`'s pure-Python search (6.2 to 9.5 times at 10^3) and 500 to 1800 times its numpy
search. The `ivf_flat` build is 2.9 times the pure-Python one, and its probes of 1 and 4
lists take 0.06 and 0.11 s per query. A full probe (nprobe 100) takes about twice an exact search
of the same index size (1.46 s against 0.70 s per query), where `proto_db`'s costs about the same
as its exact search. (Review I1 of task V6 measured the cause: every node a bounded range walk
reached was compared with tuple order keys, and before the first list was read every list was
probed for emptiness; the run below follows the fix.) The peak resident
set of protoBaseST (about 5 GB at 10^4) is protoCore's heap budget being used, not a working set
(memory figures are not a headline).

**VB1 and VB2 after fix round 1 of task V6** (2026-11-22). The same command, data and
implementations as the run above, measured 2026-11-21 23:40 to 2026-11-22 00:17 UTC on the same
machine, load average 2.91 before and 4.20 after (the machine grew busier during the run: the
exact rows are up to 18 per cent slower than in the run above, on both sides, a few unchanged); protoBaseST `605d991`
(the clean committed tree), protoST 0.16.0. The change: a list of the store is read by a walk
bounded on the key's Integer list number instead of tuple order-key compares (the same nodes in
the same order), and the probe order is walked lazily, an empty list skipped as it is reached
instead of every list probed for emptiness before the first is read. The runner printed
`verified`; recall was again 46, 85 and 100 of 100 in all three implementations.

| id | size | plan | proto_db us min / median | protoBaseST us min / median | ratio st/py (min) | peak RSS MB py / st | proto_db numpy us min / median |
| VB1 | 1000 | d8-cosine-first | 7206 / 7830 | 65412 / 72164 | 9.1x | 23 / 677 | 2125 / 2426 |
| VB1 | 1000 | d8-cosine-knn | 64601 / 71960 | 649090 / 687743 | 10.0x | 23 / 677 | 2964 / 3283 |
| VB1 | 1000 | d8-l2-first | 5920 / 6751 | 41772 / 50358 | 7.1x | 23 / 552 | 2478 / 2539 |
| VB1 | 1000 | d8-l2-knn | 56116 / 57051 | 445971 / 497645 | 7.9x | 23 / 552 | 2909 / 3233 |
| VB1 | 1000 | d32-cosine-first | 11409 / 12758 | 71043 / 80317 | 6.2x | 24 / 761 | 3403 / 3528 |
| VB1 | 1000 | d32-cosine-knn | 117568 / 120242 | 737200 / 762394 | 6.3x | 24 / 761 | 4179 / 4439 |
| VB1 | 1000 | d32-l2-first | 8848 / 9236 | 41987 / 44891 | 4.7x | 24 / 637 | 3075 / 3858 |
| VB1 | 1000 | d32-l2-knn | 80905 / 88394 | 447870 / 506858 | 5.5x | 24 / 637 | 3536 / 3946 |
| VB1 | 10000 | d8-cosine-first | 145916 / 159315 | 637732 / 678338 | 4.4x | 46 / 5090 | 17523 / 18679 |
| VB1 | 10000 | d8-cosine-knn | 991296 / 1064982 | 7178765 / 7598329 | 7.2x | 46 / 5090 | 4202 / 4415 |
| VB1 | 10000 | d8-l2-first | 133622 / 156345 | 477171 / 499942 | 3.6x | 46 / 5090 | 17264 / 20089 |
| VB1 | 10000 | d8-l2-knn | 913492 / 929489 | 5012334 / 5256932 | 5.5x | 46 / 5090 | 5145 / 6494 |
| VB1 | 10000 | d32-cosine-first | 191877 / 198957 | 715685 / 738710 | 3.7x | 59 / 5087 | 28399 / 28975 |
| VB1 | 10000 | d32-cosine-knn | 1442574 / 1467884 | 7692983 / 7865632 | 5.3x | 59 / 5087 | 7258 / 7565 |
| VB1 | 10000 | d32-l2-first | 161067 / 168489 | 526005 / 549272 | 3.3x | 59 / 5087 | 30944 / 32275 |
| VB1 | 10000 | d32-l2-knn | 1116438 / 1154995 | 5361926 / 5497977 | 4.8x | 59 / 5087 | 11874 / 12719 |
| VB2 | 10000 | d32-ivf-build | 62846341 / 64271246 | 191839295 / 196962247 | 3.1x | 76 / 5087 | 1627480 / 1730075 |
| VB2 | 10000 | d32-ivf-nprobe1 | 23766 / 25579 | 194128 / 240887 | 8.2x | 76 / 5087 | 12183 / 13260 |
| VB2 | 10000 | d32-ivf-nprobe4 | 151692 / 167521 | 535111 / 681444 | 3.5x | 76 / 5087 | 11797 / 12852 |
| VB2 | 10000 | d32-ivf-nprobe100 | 1499394 / 1588079 | 10769764 / 10789113 | 7.2x | 76 / 5087 | 25151 / 25316 |

Observed: the IVF queries are cheaper; the exact ones do not use the bounded walk. The table's
microseconds cover the 10 queries of each unit; per query, nprobe 1 takes 19 ms instead of 62 ms
(8.2 times `proto_db`'s pure-Python search instead of 28.2 times), nprobe 4 54 ms instead of
110 ms (3.5 times instead of 7.6), and the full probe (nprobe 100) 1.08 s instead of 1.46 s. The
full probe now costs 1.40 times an exact search of the same index size (10769764 against 7692983
microseconds for the 10 queries; it was 2.09 times), where `proto_db`'s costs 1.04 times its own.
The remaining gap is not measured. Candidates only: the per-list collections (one
OrderedCollection per probed list, its `asArray`, and `probed addAll:`; the per-member entry
Arrays are not one, since the exact search builds them too) and the 101 bounded descents (review 1
measured the walks bounded on the list number at about 6 per cent of an exact search, too little
alone for 40 per cent). Nor is what remains at nprobe 1 and 4 against `proto_db` (8.2 and 3.5
times) measured; the interpreted kernel and the store walk, where `proto_db` reads its cached
lists, are candidates only.

**VB4, filtered kNN** (vectors phase task V7). `RUNS=5 bench/run_query.sh VB4`, measured
2026-11-22 08:23 to 08:32 UTC on an AMD Ryzen 5 5500U (12 CPUs, Linux 7.0.0-43-generic), load
average 2.57 before and 3.41 after (4.02 a moment later: the machine grew busier during the run);
protoBaseST `1fd30d8` (the clean committed tree), protoST 0.16.0
(`worktrees/pinned-0160/protoST/build_release/protost`), `proto_db` `v2.0.0rc4` in its reference
mode (CPython 3.14.6, glibc 2.43, numpy and hnswlib blocked; an exact answer does not depend on
numpy, so its default mode is not run). Data: `proto_db`'s clustered benchmark set (seed 51, 16
centres), 10^4 vectors of dim 8 and its 10 query points (`bench/py_vector_data.py`), as the
records `{ 'i'. 's' -> i mod 100. 'vec' }` under an exact l2 index; the condition `s < p` keeps p
per cent of them. `-filtered` is near(k = 10) AND `s < p` planned by each planner (checked first,
untimed, to be one `VectorSearch` whose `'where'` is the condition, ruling R27) and executed;
`-post` is near(k = 10) planned and executed alone, then the condition applied to its 10 rows.
Planning is timed with the execution. The runner printed `verified`: every run of both sides
reported the same rows and the same CRC-32 of the answers' positions, so both answers are
`proto_db`'s. The rows of the 10 queries: 100 for `-filtered` at every selectivity, and 1, 17 and
60 for `-post` at 1, 10 and 50 per cent. Times in microseconds for the 10 queries, minimum and
median of 5 interleaved runs; nothing is asserted about time.

| id | size | plan | proto_db us min / median | protoBaseST us min / median | ratio st/py (min) | peak RSS MB py / st | proto_db numpy us min / median |
|---|---|---|---|---|---|---|---|
| VB4 | 10000 | d8-s01-filtered | 209863 / 214527 | 6401987 / 6539876 | 30.5x | 48 / 5093 | - |
| VB4 | 10000 | d8-s01-post | 894956 / 925393 | 4793909 / 4975721 | 5.4x | 48 / 5093 | - |
| VB4 | 10000 | d8-s10-filtered | 328825 / 343666 | 6632641 / 6883538 | 20.2x | 48 / 5093 | - |
| VB4 | 10000 | d8-s10-post | 864738 / 872740 | 4896461 / 4936969 | 5.7x | 48 / 5093 | - |
| VB4 | 10000 | d8-s50-filtered | 677686 / 698571 | 7943173 / 8400157 | 11.7x | 47 / 5093 | - |
| VB4 | 10000 | d8-s50-post | 865546 / 882906 | 4795003 / 5098400 | 5.5x | 47 / 5093 | - |

Observed, per query (the table's figures divided by 10): the filtered search answers 10 rows at
every selectivity, the post-filter 0.1, 1.7 and 6 on average, so the two do not answer the same
question, and only the filtered one answers near(k) AND P. In `proto_db` the filtered search is
also the cheaper: 21, 33 and 68 ms against 86 to 89 ms for the post-filter, since it scores only
the members the condition accepts. In protoBaseST it is the dearer: 640, 663 and 794 ms against
479 to 490 ms, 1.3 to 1.7 times the post-filter, and 11.7 to 30.5 times `proto_db`'s filtered
search (the post-filter is 5.4 to 5.7 times). Its cost hardly falls with the selectivity, so the
work that dominates is done for every member, not for the scored ones. Not measured as a bench;
one unrepeated probe on protoST 0.16.0 (a scratch program, not committed) took 670 ms to evaluate
`s < 1` (`PBExpression evaluate:`) over the 10^4 records alone, about 67 microseconds per element,
and 214 ms to walk the index's 10^4 store entries: the condition's evaluation, not the scoring, is
the candidate. Faster term evaluation is not part of this phase.

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
- **protoST 0.12.0, not yet filed:** `asSortedCollection:` of an empty collection signals "sort:
  needs an Array or an OrderedCollection (use sorted)" (`SortedCollection >> addAll:` sorts the
  receiver, which `sort:` refuses), and `Array new collect:` recurses. protoBaseST sorts with
  `sorted:` and builds with `Array new: n`; the property soak of plan Task 10 found the first, in
  an `in` with no operand ordered by an index key.
- **Module resolution is documented protoST behaviour, not a bug.** The working directory is
  searched before the library, as in Python, so a stray `calendar.st` in the current directory
  shadows the library's calendar module. **Security note:** an untrusted working directory's
  `.st` files replace library modules of the same name. Run protoBaseST programs and tests from a
  trusted directory.
