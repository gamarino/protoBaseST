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
[Indexed queries (in progress)](#indexed-queries-in-progress) |
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

- **Indexed collections are written, merged, queried and paged** (0.3.0 in progress, plan Tasks
  4a to 9). Every mutator maintains the collection's `PBEqualityIndex` and
  `PBRangeIndex` indexes in the same step, with the hook order of `proto_db`'s mutator, so one
  sequence of operations gives the same index nodes in both implementations
  (`tests/interop/index_ops_identical.sh`); a format-3 index is rebuilt before the first change;
  `addIndex:`, `removeIndex:` and `validate` are provided, and the index definitions are logged
  (`('@index_add' name index)`, `('@index_remove' name)`, never on `PBList`), so a blind write
  onto an indexed current merges as in `proto_db` (`tests/unit/idx_merge.st`,
  `tests/interop/index_both_directions.sh`, row 13 of `tests/interop/concurrency.sh`). What stays
  refused: a collection holding a `PBVectorIndex` or an index of a kind protoBaseST does not know
  is read only, a merge onto one included (`PBNotSupportedError` naming it; see the table below).
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

- a collection holding a vector index or an index of an unknown kind (read only, ruling IQ5);
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

## Indexed queries (in progress)

> **0.3.0, in progress.** These are the differences the approved
> [indexed-queries spec](superpowers/specs/2026-11-18-indexed-queries-design.md) plans on purpose,
> written early so the draft chapters ([17](tutorial/17-indexes.md),
> [18](tutorial/18-queries-and-plans.md), [19](tutorial/19-ordered-reads-and-pages.md)) and the
> guide ([queries.md](queries.md)) can link here. The entry "Indexed collections are written, merged,
> queried and paged" above says what holds today. Each entry became a deviation when its task was
> merged; every row is in force (the tasks 4a to 9 have landed).

| What | Difference from `proto_db` | Why | Cost |
|---|---|---|---|
| Opaque predicates in `explain` | A block condition is the node `BlockFilter` with `description`, where `proto_db` has `PythonFilter` (call IC6). | The node runs a protoST block; naming it after Python would mislead. | A one-name difference in `explain`; the query vectors hold no opaque predicate. |
| Equality on the field builder | `eq:` and `ne:` build `==` and `!=`; `=` is not overridden on `PBField` (IC4, ruling IQ2). | `=` must stay an equality for collections and tests. | Less like Python's `F.city == "Oslo"`; `aField = v` answers a Boolean, which `where:` refuses. |
| Index constructors | `name:keySpec:` takes a `PBKeySpec` only (a String is `PBValidationError`); one path is `name:path:` (controller ruling CR3). `proto_db`'s `KeyGroupIndex(name, key_spec)` accepts a `KeySpec` or a str path. | One argument, one type: a keyword selector names the convenience instead of overloading the argument. | A path is written `name: 'by_city' path: 'city'`, not `name: 'by_city' keySpec: 'city'`. |
| Extractor blocks | `registerExtractor:block:version:` takes a `BlockClosure` only (anything else is `PBValidationError`); `proto_db`'s `register_extractor` takes any callable. | An extractor is `[:element \| key]`; one type keeps the identity test (`==`, `proto_db`'s `is`) and the purity contract simple. | An object that answers `value:` must be wrapped in a block. |
| `isExtractorRegistered:` | A protoBaseST addition: `proto_db` has no such function (its programs call `extractor_version` and catch the error). | Asking needs no exception handler. | None: one more message. |
| Projection | `project:` and `collect:`; `PBQuery` has **no** `select:` (ruling IQ2). | Smalltalk's `select:` filters; `proto_db`'s `select` projects, and would read backwards. | A name to learn. |
| Selection blocks | Not in the first release (ruling IQ2): a block condition is opaque and never uses an index. | Translating a block by running it on a recording object fails silently (`30 < (p at: 'age')`, inlined `ifTrue:` and `==`, methods of the element). | Index-using conditions are written with `PBField`. |
| Plan choice on near ties (R2) | The descent term `log2 (G + 2)` and a sort's `n log2 n` are computed by `PBCost class >> log2:` (`src/protobase/plans.st`, the one place a logarithm is computed, plan call IP7) as `ln x / ln 2` (protoST has no `log2`; ruling IQ4: protoST is not changed), which can differ from C's `log2` in the last bit. Two candidates whose costs are within a relative 1e-12 may be ranked differently: the same answer by another plan. | No protoST change for plan parity (IQ4). | The query vectors (`tests/conformance/queries.st`) report such a plan difference by name and do not fail on it; it counts as a near tie only when the choice differs (the node and index names) and the root costs agree within plan call IP8; any other plan difference, and every result difference, fails. Measured at Task 7: 0 near ties in the 314 recorded queries, every plan node for node and cost for cost `proto_db`'s. |
| Vector and unknown index kinds (Task 4a) | A collection holding a `PBVectorIndex`, or an index of a kind protoBaseST does not know, stays read only: every change and every merge onto it is `PBNotSupportedError` naming it (IC2, ruling IQ5). | Vector search is out of scope; maintaining the other indexes but not that one would write a stale index. | Such a collection is changed from Python only. |
| `near[]` terms (Task 5) | `PBTerm path:op:value:` with `'near[]'`, and the list syntax naming it, signal `PBNotSupportedError` when the term is made; `proto_db` builds the term (a `NearQuery`) and refuses it only when it is evaluated by a scan, answering it with a vector plan otherwise. | Vector search is out of scope (spec 3.3); a term no plan of this port can answer is refused where it is written, never later. | A query naming `near[]` fails at once, as every vector feature does. |
| Atoms and instant-form IANA datetimes in `describe` (Task 5) | `describe` (so `explain`) renders an atom as `<type name oid=...>` and an instant-form datetime in an IANA zone by its `printString`; `proto_db`'s `display_value` prints Python's `repr`: a record's fields (`DBObject(r=1)`), a collection's count, a stub's storage pointer (`<type stub at ...>`), a zone datetime's wall clock. Every other value is rendered as Python renders it, checked by `tests/unit/qry_terms.st`: against `proto_db` for the values of its vector (numbers, `Decimal('1.50')`, `inf`, strings, `b'\x00'`, dates, naive and fixed-offset datetimes, times, timedeltas, UUIDs, tuples), and against CPython's text for the rest (`Decimal('Infinity')`, `Decimal('NaN')` and the other specials, named offsets, `fold=1`, a time or a format-3 datetime in an IANA zone, `zoneinfo.ZoneInfo(key='Europe/Rome')`, `MutableObject('cell')`, maps as `{'@dict': ...}`). | Python's `repr` of a record walks its fields with Python's rules; an instant-form datetime holds only its UTC instant, and its wall clock in the zone needs a time-zone database (design 4.3). A time and a format-3 datetime keep their wall clock, so they are rendered. | The `explain` of a term whose operand is an atom, or of a key that is an instant-form zone datetime, differs in that one value; results do not. |
| `in` over a `Set` (Task 5) | A protoST `Set` keeps `true` and `1` as two operands; a Python `set` holds one of them, since `True == 1` there. Both sort their operands by order key. | The difference is the host's set, not the term: `PBTerm` keeps what it is given, as `proto_db`'s `Term` does. | `in: (Set withAll: { true. 1 })` also matches 1, where `{True, 1}` in Python matches only `True`; a sequence (an `Array`) is the same in both. |
| Block predicates (Task 5) | `PBBlockPredicate` (`proto_db`'s `PythonPredicate`) describes itself as `{ 'block' -> description }`, where `proto_db` writes `{'python': description}`; it takes a block of one argument (`proto_db`: any callable). | Named after the language that runs it, as `BlockFilter` (call IC6). | A one-key difference in the description of a condition holding a block; the query vectors hold none. |
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
| Benchmark sizes (Task 8) | Bench Q1 measures 10^2 to 10^4 records by default, not the spec's 10^2 to 10^5 (spec 7.3). | A 10^5 process with only the one index Q1 uses took 336 s and peaked at 5.4 GB in protoST (the budget is about 5 GB), and a run needs ten per size ([Q1-Q4](#q1-q4-queries-indexed-against-a-forced-scan)). | The largest size is 10^4; `QUERY_Q1_SIZES` adds 10^5 for a run that can afford it. |
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
  "Unknown operator" leaves out `'near[]'`, which is refused (above).

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

0.3.0, in progress (spec section 7.3, `bench/run_query.sh`). M1, M2, M3, P1-P3 and Q1-Q4 are measured so far (below);
the drafts cite these markers for the rest, each filled by the task named:

- Q1-Q4, point equality, `in` and ranges, compound conditions, ordering, indexed against a forced
  scan, in both implementations: measured at Task 8,
  [below](#q1-q4-queries-indexed-against-a-forced-scan).
- [measured in T9: Q5, page k by rank against materialised, and `count` by rank]
- [measured in T10: the full comparison with `proto_db`, with date, machine, load, both commits and
  both binaries]

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
- Ruling CR2, as written: the model's crossover in collection size is only one or two elements,
  so size is not the variable swept.

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
