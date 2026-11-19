# Decisions

Every call that shaped protoBaseST, with what was decided, why, and what it costs if it is wrong.
Three kinds, in this order, for the single-process prototype and then for cluster mode:

1. [The maintainer's decisions](#1-the-maintainers-decisions) of the design review (2026-11-10).
2. [The planner's calls, C1 to C19](#2-the-planners-calls-c1-to-c19), made unattended when the plan
   was written and reviewed at the end.
3. [Execution rulings](#3-execution-rulings), made while the tasks ran, numbered R1 to R29 where
   they were numbered.
4. [Cluster mode](#4-cluster-mode): the maintainer's answers Q1 to Q8, the planner's calls CC1 to
   CC25, and the rulings taken while the cluster tasks ran; then
   [the proposals to `proto_db`](#proposals-to-proto_db).

The first two kinds are quoted as decided; where a later ruling superseded one, it says so in the
entry. The rule that governs them all is the maintainer's: **when in doubt, `proto_db` is the
reference**: `v2.0.0rc1`, then `v2.0.0rc2` for the single process, and `v2.0.0rc4` (at format 4)
since the cluster branch adopted it. This file is the place to overrule any of
them; the cost column says what that would take.

## 1. The maintainer's decisions

| # | Question | Decision | Why | Cost if wrong |
|---|---|---|---|---|
| 1 | Where the code lives | A new repository, `protoBaseST`. `Decimal`, the calendar values and `UUID` go to protoST's `lib/`. | The values are general; a database repository should not own a decimal. | Moving the three libraries is mechanical. |
| 2 | Symbols | A `Symbol` is refused; strings are strings. When `@sym` lands, protoST gets an explicit wrapper. | A symbol stored as a string would come back as a string. In protoST a literal of six bytes or fewer is a `String` (STATUS D35), so a short symbol cannot be told apart anyway. | Code that wants stored symbols waits for format 5. |
| 3 | Immutability of stored values | By convention: built once, never assigned afterwards. No frozen instances. | protoST does not enforce immutability at run time. | A method that mutates would compile; a test scans for it. |
| 4 | Names | `proto_db`'s names with the `PB` prefix, camelCase. | One document explains both languages. | Three names clash with Pharo's meaning (`add:`, `remove:`, `removeAt:`); see [deviations.md](deviations.md). Alternatives: `copyWith:`, `copyWithout:`, `copyWithoutIndex:`. |
| 5 | Conflict granularity | The same as `proto_db`: per-root and per-cell read sets, the replace and merge rules, the mutable-cell rules. | A different granularity would be a semantic divergence hidden behind the same name. | None; it is the reference. |
| 6 | Early primitives | Approved: protoIO 0.5.0 and protoST 0.10.0, with `randomBytes:` and a microsecond clock. | The identities and timestamps of the format need OS random bytes and a UTC clock; they belong in protoIO for every runtime. | A release of two other repositories before this one. |

## 2. The planner's calls, C1 to C19

| # | Call | Why |
|---|---|---|
| C1 | *Superseded by ruling R1: protoIO is **0.5.0**, protoST's floor `PROTOIO_MIN_VERSION 0.5.0`.* Original call: protoIO keeps the approved number **0.4.1**, although protoIO bumped the minor for new API in 0.4.0 | The maintainer approved 0.4.1 by number. protoST sets `PROTOIO_MIN_VERSION 0.4.1`. If the maintainer prefers 0.5.0, it is a one-line change in Task 26 |
| C2 | *Renumbered by ruling R10: the release is **0.10.0** (the branch carries breaking changes: D52, K20, numeric hash values, the protoIO floor).* protoST's `lib/` additions (Tasks 3-5) ship in the same release as the bindings | Publication happens once, at the end. The additions are additive and break nothing |
| C3 | The protoST API names are `ByteArray randomBytes: n` and `Time utcMicroseconds` (microseconds since 1970-01-01T00:00Z, wall clock). `Time microsecondClockValue` stays monotonic | Clarity over familiar names: Pharo's `microsecondClockValue` is a wall clock, protoST's is monotonic, and reusing the name would mislead |
| C4 | `randomBytes:` accepts 0 ≤ n ≤ 1,048,576 and signals `InvalidArgument` outside that range | A bound keeps one call from allocating without limit. Identities need 16 bytes |
| C5 | Week-0 checks and every reader task run on the existing `../protoST/build_release/protost` (0.9.0), with protoST's branch `lib/`. The installed `/usr/bin/protost` is 0.8.1 and is not used | The spec assumed an installed 0.9.0. The local release build is 0.9.0 and runs, so no build is needed until Task 2 |
| C6 | The §9 lock check targets `proto_db`'s **FileStorage root lock** (`fcntl.flock(LOCK_EX\|LOCK_NB)` on `space.lock`), not `OwnerLock` | At the tag, `OwnerLock` guards logs and tiered storage, not `space.lock` |
| C7 | The calendar classes signal protoST's own `TimeZoneUnavailable` (an `Error` subclass in `lib/calendar.st`) for a wall clock of an instant-zone `DateTime` and for building a named-zone `DateTime` from a wall clock. protoBaseST's own refusals (format-3 `["zone", key]` datetimes) signal `PBNotSupportedError` | The values live in protoST `lib/` (decision 1), which cannot depend on protoBaseST. Spec §4.3 named `PBNotSupportedError`; the refusal stays explicit and is documented |
| C8 | Conformance vectors are **vendored** into `protoBaseST/tests/conformance/vectors/` by a script that extracts them from the tag and checks every file against `vectors.sha256` | A clean checkout must run the tests (Spec §10.8) |
| C9 | The Python side is a venv at `tests/interop/.venv` (git-ignored), made with `--system-site-packages`. `msgpack==1.2.4` is installed only when the import is missing or another version (*amended by Task 17b, ruling R18*: `proto_db` at `v2.0.0rc2` needs msgpack ≥ 1.2.0 and its C extension; until then `msgpack==1.1.2` and `v2.0.0rc1`). `proto_db` is extracted with `git archive v2.0.0rc2` into `tests/interop/.venv/protobase/` and used through `PYTHONPATH`; `env.sh` fails a run whose venv holds another commit than `setup_venv.sh` pins | Pure Python, so no install step is needed. Network use is kept to a missing `msgpack` |
| C10 | Spec §10.2 and §10.3 run the verifier through `tests/interop/py_verify.py`. It imports `examples/erp/erp_model.py`, which registers `demo.erp.*`, then calls `proto_db.tools.verify.main([dir, "--out", file])` | A bare `python -m proto_db.tools.verify` would read `demo.erp.Invoice` as opaque. It is still `proto_db`'s verifier, with the application's classes registered |
| C11 | The dumps are compared on the `databases` and `opaque_types` keys by `tests/interop/compare_dumps.py`. A `{"opaque": T}` on the protoST side equals `{"object": T}` on the Python side only for the Python-only type `demo.erp.AuditNote` | Atom counts depend on the walk. AuditNote is deliberately unknown to protoST |
| C12 | protoST cannot drive an interactive pipe (`OSProcess run:arguments:input:` is one batch). Interleavings use nested runs. For "start A, start B, commit B, commit A", the side owning A starts A, runs the other language's one-shot script (start B, commit B) as a subprocess, and then commits A. Both assignments run: protoST as A and Python as B, and Python as A and protoST as B | Deterministic with no pipes. Each language validates against the other's commit |
| C13 | Spec §10.7 is driven from Python. `tests/interop/hold_lock.py` takes the `flock`, runs a protoST script whose commit uses `lockTimeout: 50`, asserts it ends in `PBTimeoutError`, then releases | The outcome holds for any duration, because the lock is never released while protoST waits |
| C14 | `PBDBError` is the root of the errors, which mirror `errors.py`: `PBValidationError` (with `PBClosedError` under it), `PBUserError`, `PBCorruptionError`, `PBNotSupportedError`, `PBUnexpectedError` (with `PBOutcomeUnknownError` under it), and `PBLockingError` (with `PBConflictError` and `PBTimeoutError` under it). `PBTimeoutError` is **not** protoST's `TimeoutError` | `proto_db`'s hierarchy, so `on: PBLockingError do:` means the same thing in both languages |
| C15 | `PBList` positions follow `proto_db`'s `_position`: negative counts from the end; out of range or not an Integer is `PBValidationError` | `lists.py` at the tag |
| C16 | A commit with no writes is a no-op, with no new version, as `Transaction._commit` at the tag | `proto_db`'s behaviour |
| C17 | Outcome resolution (Spec §7.3 step 8) is tested through a test-only subclass of `PBFileStorage`, defined in the test file, that fails `replaceRoot:` before or after the rename | No flag or hook in product code |
| C18 | protoBaseST's version is `0.1.0`, with a CHANGELOG from the start and the MIT license, "Copyright (c) 2026 Gustavo Marino" | Same license as protoST |
| C19 | The as-of moments of the ERP demo are the `committedAt` values of chosen history entries, never wall-clock readings | Deterministic report |

Cost if wrong, in brief (C1 and C2 were renumbered by rulings R1 and R10, below):

| # | Cost if the call is wrong |
|---|---|
| C3 | Two protoST selectors renamed. |
| C4 | The bound changes in one primitive. |
| C5 | None once Task 2 landed; the installed 0.8.1 binary stayed unused. |
| C6 | The lock test would target the wrong lock; it was checked against the tag. |
| C7 | A second error class for time-zone refusals (`TimeZoneUnavailable` in protoST, `PBNotSupportedError` here). A caller that catches one must catch both. |
| C8 | Vendoring adds 185 binary files to the repository; the alternative is a network fetch before every test run. |
| C9 | The venv needs `git archive` of the tag and, at most, one `msgpack` install. |
| C10 | The verifier runs with the demo's classes registered, so it is "`proto_db`'s verifier, with the application's classes", not the bare command. |
| C11 | The one normalisation (`opaque` equals `object` for `AuditNote`) could hide a real difference; `--exact` runs without it. |
| C12 | Interleavings are scripted with nested runs, not live pipes; a bug that needs true concurrency between processes would not show. |
| C13 | The timeout test is driven from Python, so it needs Python. |
| C14 | None while the hierarchy mirrors `errors.py`. |
| C15 | `PBList` could not match `proto_db`'s `List` on a bad position. |
| C16 | An empty commit would publish a version. |
| C17 | A test-only subclass instead of a product hook: outcome resolution is only as tested as the subclass is faithful. |
| C18 | A renumber. |
| C19 | A report that depended on the wall clock. |

## 3. Execution rulings

Rulings R1 to R22 were taken while the tasks ran, and R23 to R29 during the commit
performance work of 2026-11-13; their record is here, with the what, why and cost of each.
Unnumbered rulings follow them.
A "task" is a task of the implementation plan (`docs/superpowers/plans/`).

| # | What was decided | Why | Cost if wrong |
|---|---|---|---|
| R1 | Version numbers follow each repository's own semver habit. protoIO is **0.5.0**. | The maintainer approved "an early release"; the number is mechanical. | A renumber before publishing. |
| R2 | Execution starts with the pure-library tasks (3 and 4) on the existing protoST 0.9.0 binary; the build-gated tasks wait. | The machine was busy with another build. | None. |
| R3 | The numeric hash (mod 2^61-1) across `Integer`, `LargeInteger`, `Fraction`, `Float` and `Decimal`, and a `raisedTo:modulo:` primitive, go into the C++ task. | The format's hash keys need one hash across all numeric kinds, and modular exponentiation was a listed gap of protoST. | The C++ task grew by about a day. |
| R4 | The class/instance method-slot bug (K14) is fixed in protoST's C++ in the build-gated batch, before Task 5. | A class-side method hid the instance method of the same selector; working around it in protoBaseST would be debt. | Task 5 waited for the build. |
| R5 | The branch `feat/prototype` carries the protoBaseST work. Tasks 6 and 7 had landed on `main` by a dispatch error and were moved. Nothing was published. | The plan names the branch. | None. |
| R6 | The deep-nesting crash (400-509 nested lists segfault) is a protoST/protoCore bug (K15), not worked around: investigated and fixed in the build-gated batch. | Silent crashes are worse than a limit. | Task 13 waited. |
| R7 | protoST 0.9.0 could not parse the float literal `5e-324` (K16); fixed in protoST. | A subnormal minimum is a boundary value of the format. | None beyond the batch. |
| R8 | `JSON parse:` crashed on any `\uXXXX` escape (K17); fixed in protoST with a test. | The manifest uses them. | Small. |
| R9 | K15 is the top item of the build-gated batch, started before Tasks 1-2. | It may be a protoCore GC bug affecting every runtime. | Tasks 1-2 slipped a few hours. |
| R10 | protoST's next version is **0.10.0**, not 0.9.1. | The branch carries breaking changes (D52, K20, numeric hash values, the protoIO floor). | A rename. |
| R11 | The announced refusal of `Array`-of-Integers in binary I/O ships in protoST 0.10.0. | A released deprecation promise is kept. | One more deprecation cycle. |
| R12 | Keep 509 nesting (the format's msgpack limit), and ask `proto_db` for a non-recursive codec or a documented depth limit (ask B12). **Superseded by R18.** | `proto_db`'s recursive codec failed at about 333 decoding. | A later lowering of the limit. |
| R13 | Implement `proto_db` D21 now: an atom's oid is assigned lazily in memory (a version-4 UUID), with a lock-free publish; remove "unsaved atoms are not keys". | The first reading of D21 was a misreading, corrected on challenge. Atoms are keys before they are saved. | None. |
| R14 | Remove `PBFramedLog`. The `log`-layer vectors become justified, visible skips. | The spec lists framed logs as a non-goal and nothing reads them; keeping an uncalled reader is debt, and its worst case was quadratic. | If cluster or tiered storage enters scope, re-port the reader with `proto_db`'s linear prefix-checksum search. |
| R15 | Insert a task for record field access: each record carries a slots Array, with literal-index accessors. | Every later task reads records through this path; the AVL was 35-211 times slower than `proto_db`, and a field read cost about 15 sends. | One task of rework. |
| R16 | Fold the reviewer's extra waste items (polymorphic kind check in the walk, skipping the integer check on writer-built nodes, one handler per tree in `check:`) into the same fix round. | Same code and benchmark. | A larger diff to review. |
| R17 | Positional trees are not subclassable: they refuse subclasses, and writes build plain `PBPosNode` (as `proto_db`'s `_pos_set`). | In `proto_db` positional trees are not subclassable; mixing classes gave false corruption. | A later change in positional writes that preserves a subclass. |
| R18 | Adopt `proto_db` **v2.0.0rc2** (B12 resolved: `MAX_VALUE_DEPTH` 1022 containers, readers accept 1024). Supersedes R12. | It touches the codec, the venv pin and the conformance vectors, which Task 18 builds on. rc2 is the new reference. | None. |
| R19 | The publisher never waits. An attempt that finds the root lock held answers "locked" at once; the caller owns the backoff (1 ms doubling to 50 ms until `lockTimeout`). A different epoch at step 8 is `PBConflictError` as `proto_db`'s `_publish`. The epoch is taken from the root read under the lock. | An actor must never block its worker: protoST runs many actors per worker, and a waiting publisher deadlocked 40 concurrent commits (reproduced). | Retry logic in the callers instead of one place; and the caller's wait blocks the caller's worker (K23). |
| R20 | Implement ANSI/Pharo `Exception>>outer` in protoST (D7), and have `newTransactionDo:` mark an exception in flight around `e outer`. | A non-Error exception unwound by an outer handler committed the block's writes. The completed-flag variant was rejected: it silently aborts a `^` taken after a resumed notification. | A protoST language-core change before the task could close. |
| R20b | The rule carried from `proto_db`: abort iff an exception unwinds the block. A resumable `Error` (such as `ZeroDivide`) goes through `outer` like any resumable exception. | A resumed `Error` must not silently discard writes; Python's `with` aborts only on unwinding. | A resumed `Error` commits the writes made before it. |
| R21 | `run:` lives in `transactions.st`, beside `newTransactionDo:`, not in `space.st`. | Cohesion. | A file move. |
| R22 | The stretch task (`CountedSet` writes and the D26 counter-transform merge) is done, not cut. | Time allowed, and cutting it would have left `PBCountedSet` mutators refusing. | None. |
| R23 | The commit performance work changes how records are saved, encoded, verified and cached, never what is written: `tests/unit/bytes_pinned.st` pins the SHA-256 of the segment and of `space.root` after a fixed workload (oids, segment name, clock and UUIDs fixed through seams). | A format drift must fail a test, not be found by a `proto_db` reader. | A deliberate format change must update the digests. |
| R24 | Each value is made canonical once on the way in, and checked as a writer must on the way out. `PBObject` (per field, when built) and the collections (per element, when inserted) make values canonical, with the holder texts (`'Field ...'`, `'Root ...'`) built only on refusal (`PBCodec canonical:for:` takes a block). The save no longer canonicalises the whole state twice more: `PBAtomEnvelope >> encode` checks each attribute name, then writes nil, Booleans, msgpack-range integers, floats and atoms of registered classes directly, and sends every other value through `toWire:atomRef:for:`, which refuses what a writer may not write with the old text, before anything is written. **Corrected in fix round 1 (review C1):** the first version assumed a state is canonical by construction, which is false: `PBObject >> withAll:` keeps the fields it does not change, and a tree write rebuilds nodes around stored values, so decoded values reach a new record unchecked, and a reader accepts values a writer must refuse (a format-3 zone datetime, an instant within one day of year 1 or 9999, a container deeper than the writer's limit, map keys only the legacy rule admits, a string with a lone surrogate). That version wrote them; one record was refused by `proto_db` as corrupt. Tests: `save_refuses_decoded.st`, `tests/interop/st_every_record_to_py.sh`. | The save refused, and must refuse, what a writer may not write, whatever the value's origin. | A value kind added to the fast path must be one every writer may write as it is. |
| R25 | `replaceRoot:` checks the SpaceRoot this storage pushed last by reading it back (framing and CRC, as `proto_db`'s `publish_root` fetches it) and comparing its payload with the bytes written; any other pointer is decoded in full as before. The bytes compared passed every check a decode makes when they were encoded (attribute names, each value as a writer writes it, canonical tag, 16-byte oid, the map shape: R24), so a decode could only refuse what the disk changed, which the CRC and the comparison catch. The cluster check (`isCluster`, and the publish) reads the SpaceRoot's state from the atom cache when it holds the record, else decodes it with `loadAt:expecting:` as before, with no added class check, so a malformed SpaceRoot is reported as before (review M2). | Two full decodes per commit bought nothing over a byte comparison. | None found. |
| R26 | `PBFileStorage` keeps an atom cache bounded in records (default 20,000) and in record payload bytes (default 64 MiB, `proto_db`'s storage cache default; `path:atomCacheEntries:atomCacheBytes:`, either `0` disables it). An entry is a record as a decode gives it (tag, oid, state; no slots), its references stubs that are never handed out: from a verified decode, or from the state of an atom this storage just saved with each atom replaced by a new stub (never the atom itself). A load copies it with new stubs for its references and checks the copy against the loading atom's class (`_loadedEnvelope:at:for:`, for that atom, on every load, as a decode is checked), so a load answers what a decode answers, every reader's stubs are its own, and nothing a reader loaded or built stays reachable from the cache. Records holding references inside containers are not cached. Two generations keyed by offset (the segment compared), an Atom over immutable Dictionaries replaced by compare-and-swap; emptied on close and on a write failure, and an insertion that races either empties it again. **Corrected in fix round 1 (review I1, M1, M8):** the first version kept the saved atom itself until the record was read, which kept the transaction's whole loaded graph reachable (3,038 atoms after a scan of 3,000 keys), was bounded in records only, and skipped the class hook on hits. `proto_db` caches raw record bytes, not decoded state; this cache keeps decoded state because the decode is protoST's cost. | Each commit re-decoded about 20 records the previous commit wrote, against `proto_db`'s 1. | Memory: at most 64 MiB of record payload, held as decoded state (several times larger in memory than on disk); a record with references in a list is decoded every time. |
| R27 | Fresh oids come from `_PBOidPool`: `ByteArray randomBytes:` for 64 oids at a time, version and variant bits set per slice as `UUID new` does, each slice taken once by compare-and-swap. `PBAtom >> _newOid` stays the seam. | One call to the generator per 64 atoms instead of one per atom. The saving is in system calls and does not show in user-space instruction counts. | None found; the distribution is `UUID new`'s. |
| R28 | Codec fast paths for the attribute values of a record (`PBCodec wireOfCanonical:atomRef:`, `fromWireValue:resolver:`): nil, strings, msgpack-range integers, floats, Booleans and references are answered before the general walk, with the same tests in the same order. | Most attribute values are scalars or references; the general walk built frames and ran a chain of `isKindOf:` tests for each. `tests/unit/codec_fast_paths.st` holds both paths equal. | None found. |
| R29 | **Not applied, held for the maintainer:** buffering the record appends into one write per flush (strategy 4 of the commit profile). Measured: a tiny commit makes 14 `pwrite64` calls, about 14 µs each under `strace` (an upper bound), so at most about 0.2 ms of a tiny commit of about 25 ms of CPU (22 ms of wall time); the fsync count and order are unchanged either way. Buffering would move an append failure from `pushAtom:` to the flush and need a second read path for records not yet written (or a write on read, a race between actors). | Correctness over speed: a change to the failure model of the durability path for under 1 % is debt, not a win. | **Accepted by the maintainer (fix round 1).** `proto_db`'s `FileStorage` does buffer appends (`_buffered`, `spill`), so matching it later is possible, with a read path for records not yet written. If it is wanted, it is a contained change in `PBSegmentWriter` with the seam tests adapted (`store_write_failures.st`, `store_crash_states.st`, `store_close_race.st`, `_st_write_space.st`). |

Unnumbered rulings, in task order:

| Task | What was decided | Why | Cost if wrong |
|---|---|---|---|
| 7 | Time-zone keys come from a **pinned list** (`PBZoneKeys`, tzdata 2026e), not from the host's zoneinfo. | A key valid on one machine and invalid on another makes a database unreadable by location. | A `proto_db` host without the backward-link names refuses those pinned keys. |
| 7 | A format-4 `["instant", key]` datetime is read as its UTC instant plus the key (D58); the vector `value-instant-wall-out-of-range` is accepted. Writing within one day of years 1 or 9999 is refused. | The format spec lets a reader without a database present the instant in UTC; refusing would call valid data corrupt. | A `datetime.max`-style sentinel in an IANA zone cannot be written. |
| 7 | A format-3 `["zone", key]` datetime is read lazily as `PBLegacyZoneDateTime`, never given an offset, never written. | Old atoms whose other attributes are fine stay readable, and untouched atoms are kept byte for byte. | The vector `datetime-zone-format3` differs from `proto_db` on purpose. |
| 8 | The expected differences from the manifest are a tracked table, not a workspace note. | A difference that is not tracked can go stale. | None. |
| 13 | `proto_db`'s save-dependents-first invariant is honoured; the reader keeps a defensive `PBCorruptionError` for a record that needs itself (ask B13 withdrawn). | The invariant is by construction in `proto_db`. | A foreign writer that breaks it gets an error instead of a recursion. |
| 15 | `PBList sliceFrom:to:` refuses a bound that is not an Integer or `nil` (a Boolean included); `extend:` of a String is refused. | Python's `slice.indices` takes `True` as 1, and `proto_db`'s own positions refuse `bool`; a String's elements are Characters, which no format stores. | A caller used to Python's slice rules gets an error. Recorded next to `proto_db`'s answers in `list_positions.st`. |
| 16 | A rebased version keeps the completeness of the version it was rebased onto. | The brief and `proto_db`'s docstring say rebased versions are not mergeable, but `proto_db`'s code gives the target's completeness; Python is the tie-breaker. | A rebased version in a commit is always incomplete anyway (the target is loaded). |
| 16 | The test runner prints every `SKIP:` line a passing test emits under its `PASS` line. | A skip must stay visible where the run is read. | Longer output. |
| 17 | `replaceRoot:` is stricter than `proto_db`'s: the lock must be held, the pointer must be a SpaceRoot record, the epoch must be current + 1. | An unchecked publish could overwrite a newer commit. | A raw caller that `proto_db` would accept gets an error. |
| 17 | The storage's failure policy is wider than `proto_db`'s: any file-system failure while writing ends writing through that storage (`isFailed`). | After a failed write the on-disk state of the segment is unknown. | The space must be reopened. |
| 17b | The root-record refusal drops protoST's MessagePack detail and keeps `proto_db`'s sentence word for word. | `proto_db` keeps the detail only as `__cause__`; protoST has no exception chaining. Exact text parity wins. | A corrupt root is harder to diagnose (a cause slot could be added to `PBDBError`). |
| 18 | Atoms are serialised and saved before the root lock, once, and kept across lock retries (never re-saved). | Shorter lock hold; `proto_db` parity. | A crash between save and publish leaves unreachable atoms, which `proto_db` accepts too. |
| 18 | Design spec 7.3 step 7 is amended: the last-known root is read only in a cluster; the single-process prototype keeps none. | It had no reader outside a cluster. | None. |
| 22 | The counted set's log keeps `proto_db`'s op kinds (`add`, `remove`, and `transform` only on a rebase). | `proto_db` at the tag is the reference. | The brief listed `transform` for every call; the spec was amended. |
| 22 | `_withChanges:log:complete:` refuses a field the class does not persist. | A misspelled field was silently dropped. | None. |
| 23 | The ERP demo's moments are `committedAt` values of chosen history entries, and the reports refuse to run on equal or out-of-order moments. | Determinism (C19), and a report that blurs two versions is wrong. | None. |
| 24 | The tutorial is checked by `tests/docs/tutorial_snippets.st`, and `tests/docs/tutorial_sync.sh` fails when a tutorial block is not in that test, in order. | A tutorial edited without its test goes stale silently. | A tutorial block cannot be freely reformatted without updating the test. |

## 4. Cluster mode

The design is `docs/superpowers/specs/2026-11-13-cluster-design.md`, the plan
`docs/superpowers/plans/2026-11-13-cluster-mode.md`, and the move from `proto_db` rc3 to rc4
`docs/superpowers/specs/2026-11-15-rc4-delta.md`. What the port does differently is in
[deviations.md](deviations.md#cluster-mode).

### The maintainer's answers (2026-11-13)

The maintainer accepted the design's recommendation on every question (design spec 8.3 and 8.4):

| # | Question | Answer | Cost if wrong |
|---|---|---|---|
| Q1 | Scope | Phases A-C over a shared `PBFileStorage` first; Phase D (tiered storage) decided after C is measured. | Multi-host deployments need a shared file system with reliable `flock`, or wait for Phase D. |
| Q2 | Wire protocol | Keep `proto_db`'s bytes, so its message vectors are the tests; protoBaseST does not promise to track later protocol versions. (It did track rc4's protocol 14, ruling below.) | A protocol change upstream is work here, or a fork of the wire. |
| Q3 | Pipelined permits | Ship `DEPTH = 0`; add pipelining only after measurement. | Lower throughput under load (measured in [deviations.md](deviations.md#cluster-mode-commits-per-second)). |
| Q4 | Group-size bound | Accepted, a liveness-only departure (CC11). | A round commits fewer entries per permission than its batch. |
| Q5 | Security | Optional HMAC frame authentication with a shared key from the start (CC4); the trusted-network assumption stated in either case. | A keyed cluster cannot mix with `proto_db` nodes; no encryption. |
| Q6 | Timer defaults | `proto_db`'s (a 2000 ms lease), all configurable. | Builds that do not fit the belief; the reserve refusal says so (CC18). |
| Q7 | Upstream proposals | Yes, both go to `proto_db` (the maintainer owns that repository). | See [the proposals](#proposals-to-proto_db). |
| Q8 | Standalone group commit (D52) | Built together with the round runner (CC10, CC22). | None found. |

### The planner's calls, CC1 to CC25

Made unattended when the plan was written; entries marked **(maintainer)** were confirmed by the
maintainer. Quoted from the plan as decided; the notes after the table say where the build
differs.

| # | Call | Why |
|---|---|---|
| CC1 | The node's own vote and own acceptance are local events to its own acceptor (`PBToAcceptor`), decided by the same rule methods as a peer's request, never through the transport | One decision path; spec 5.4 leaves the dispatcher/acceptor mapping as a Phase B review point |
| CC2 | `PBGrantState` lives inside `PBAcceptorState`: promises are durable acceptor state. The dispatcher reads the acceptor's published snapshot (an `Atom`) for hints only and never decides a grant or an acceptance from it | Atomic acceptor steps (R55, R81, R81b) |
| CC3 | The core counts integer microseconds; options are milliseconds. Defaults: `driftMargin` = ⌈2D/3⌉, belief = D − margin, `sendReserve` = min(`requestTimeout`, belief // 4), `startupGrace` = D + margin, idle end D // 4 | No rounding of `proto_db`'s float seconds can make the margin fall below 2/3 D (R78b) |
| CC4 | **(maintainer)** HMAC frame authentication layout: the frame body is the msgpack map followed by a 32-byte tag, HMAC-SHA-256(key, UTF-8(receiver id) ‖ 0x00 ‖ msgpack bytes); the 4-byte length covers both; `MAX_FRAME_BYTES` unchanged; a key is a `ByteArray` of at least 32 bytes; a missing or wrong tag drops the connection like an invalid message; the tag is compared over all 32 bytes without an early exit. Replay needs no counter: duplication and reordering are inside the failure model (P5), and the receiver id in the tag stops delivery to another member. Disabled, the bytes are protocol 14 (13 before Task 22a) | Q5 asks for optional HMAC "from the start" but fixes no layout |
| CC5 | The reader delivers each valid frame as it is read. `proto_db`'s "messages decoded from the same 64 KiB read as a bad frame are lost with it" is a property of its reads, not reproduced | Delivery and loss are both inside the failure model; the connection is still dropped at the first invalid frame |
| CC6 | **(maintainer)** The node-id binding of the acceptor log proposed in lesson L27 is **not** added in Phases A-C: it needs a new entry kind, which would change the shared format. In shared storage the file name `cluster/<name>.roots` binds the id. Kept as a proposal to `proto_db` for Phase D | "Same bytes" outranks a cheap addition |
| CC7 | Message types never sent at `DEPTH = 0` over shared storage (`records warm store propose fetch fetched commit_query commit_info`) are decoded and validated (an invalid one drops the connection), then ignored and counted in `stats` (`ignored_messages`) | All 22 types must be validated (spec 3.3 item 4); answering them would be code for Phase D |
| CC8 | `#fetchTimeout` and every tier option are refused (`PBNotSupportedError` naming Phase D), not accepted silently | No uncalled code; refuse, never diverge |
| CC9 | The barrier commit is a documented pattern (a `run:` that writes a root), not an API, as in `proto_db` (CP 1.12; the read-only barrier is not implemented there either) | No invented API |
| CC10 | **(maintainer)** Standalone group commit (D52, Q8): the round runner retries a busy root lock with `Future after:` timers and never waits; each queued commit keeps its own `lockTimeout` deadline from the moment it was queued; the caller waits only on its commit's Future. This supersedes the "caller owns the backoff" half of R19 (the "never waits" half stays) and removes the deviation "the lock backoff blocks the caller's worker" | The runner owns the queue, so it owns the retry; one place instead of every caller |
| CC11 | Group-size bound (Q4): the first queued commit of a round is always built; before building commit k+1, the runner continues only if the permission's time left is at least `sendReserve` + the longest build measured in this round. The rest go back to the head of the queue, not counted as attempts | Spec 5.6 states the bound, not the formula |
| CC12 | Test layout: cluster unit and simulator tests live flat in `tests/unit/` (`cluster_*.st`, `sim_*.st`, helpers `_sim.st`, `_plants.st`), because the runner sets the working directory to the test's directory and `_check.st` lives there; real-process tests live in `tests/cluster/` | Spec 5.2 named `tests/cluster/sim/`; the runner's import rule decides |
| CC13 | The simulator takes the rules object as a parameter (`rules:`); plants override one method of `PBCoordinatorCore` | C17 precedent: no product flags |
| CC14 | Each scenario family runs a fixed list of seeds in the default suite (sized to fit `RUN_TIMEOUT`); `PBST_SIM_SEEDS=n` raises it for the soak run of Task 30. A failure prints the seed and the event trace | "Seeded runs at volume" without a slow default suite |
| CC15 | Acceptor-log kinds 5 and 6 are decoded on load (the format says a reader takes them) and never written; `PBSharedTier` refuses a log holding one (`PBNotSupportedError`: a tiered node's log) | A shared-storage node never writes them |
| CC16 | `ranges.log` and `segments.log` are verified at the framed-log layer (header, frame count, payload bytes); their entry decoders are Phase D | No uncalled decoders |
| CC17 | Wire roots: `[0, nil, nil, label]` is the known empty space; the 3-item form is decoded with label 0 and never written | FS-wire field types |
| CC18 | A reserve refusal is `PBConflictError` whose text names the longest build of the round, the time the permission had left, `sendReserve` and `leaseDuration` | Review Focus 2 |
| CC19 | The persister writes `space.root` with `tryLockRoot`, `readRoot`, root-order check, then `replaceRoot:` (epoch + 1 is the CAS); a busy lock reschedules it after `persistInterval` | Port of `PlainTier.persist`; the persister never waits |
| CC20 | `PBFileStorage class >> clusterPath:` opens a storage that may write a cluster space; `PBObjectSpace storage:coordinator:` requires one, `PBObjectSpace storage:` refuses one. `PBFileStorage path:` keeps refusing cluster spaces | Spec 5.2 "a coordinator-owned handle"; no mode flag on an open storage |
| CC21 | A node id that is not `[A-Za-z0-9._-]{1,64}` is not refused: its log is `cluster/<hex of the UTF-8 bytes>.roots`, `proto_db`'s `_node_log` rule | Same file name as `proto_db` would pick |
| CC22 | `PBRoundRunner` is shared by both modes and lives in `src/protobase/round.st`; the cluster round's shell is `PBClusterRound` in `src/protobase/cluster/round.st`. `PBPublisher` stays as the standalone strategy (one group per call) | Q8: one mechanism for both modes |
| CC23 | Membership values (`PBPeer`, `PBMembership`: ranks, ballots, voters, fingerprint) get their own module `cluster/members.st` | One responsibility per file; spec 5.2 spread them over `protocol.st` and `lease.st` |
| CC24 | `coordinator stats` answers a `Dictionary` keyed by `proto_db`'s stat names (snake_case Strings) for the counters protoBaseST has | One vocabulary in both projects' docs |
| CC25 | Release number: 0.2.0, `## 0.2.0 (unreleased)` in the CHANGELOG | Spec header: "the release after the first public protoBaseST (0.1.0)" |

As built:

- **CC7**: built as the call says. The eight types are decoded and validated, then ignored and
  counted in `stats` (`ignored_messages`) by `PBCoordinatorCore >> dispatchReceived:in:now:`
  after the voter-set check (`PBCoordinatorCore class >> ignoredTypes`, an explicit list, so a
  Phase D handler cannot silently change what is counted). The counter was missing until Task 29's
  fix round 1, which added it with its tests (`cluster_ignored_types.st`).
- **CC10** supersedes the "caller owns the backoff" half of R19; the "never waits" half stands.
- **CC4** and **CC2**: protocol 14 since Task 22a (13 before), with the same layout.
- **CC14**: the seed lists were built, the knob was not: nothing read `PBST_SIM_SEEDS` until
  Task 30, which found it missing when it came to run the soak. Task 30 added it as
  `PBSimSoak` (`tests/unit/_sim.st`): `PBSimSoak seeds: aList` raises a product-rule family's
  list to n seeds, keeping a family split over two files split (1-100 and 101-200 become 1..n and
  n+1..2n); a single-seed schedule whose expected answer does not depend on the seed runs through
  `PBSimSoak same: aBlock over: #(s)`, which answers that one answer or names the seeds that
  differ. Plants keep their own seeds. `tests/unit/sim_soak_seeds.sh` checks the knob and that
  every `sim_*.st` file takes it or is listed exempt with its reason (the plant files, the lessons,
  the timer audit's index).
- **CC19**: as the call says, with Task 21's ruling on top: the persister's writes go through
  the round runner (`PBSharedTier >> persist:` takes `tryLockRoot`, reads the root, checks the
  order, then `replaceRoot:`).

### Rulings taken during execution

| Task | What was decided | Why | Cost if wrong |
|---|---|---|---|
| 2, 4 | `proto_db`'s refusal of a log file with two hard links, and its lock named after the real path, are ported with new protoST primitives (`BinaryFile >> linkCount` in protoST 0.11.0, `FileReference >> realPath` in protoIO 0.7.0 and protoST 0.12.0), never with a stopgap lock. | Review reproduced two live handles on one log through a symbolic link; a workaround would be debt. | protoST 0.12.0 is the floor. |
| 5 | Map keys and the version field follow `proto_db`'s code, not its format spec's wording (bin keys admitted as `strict_map_key` admits them; `v` 13.0 equals 13, now 14.0 equals 14). | A peer is judged by the bytes `proto_db` accepts. | Hostile-input handling differs only on garbage. |
| 7 | An option key that is not a String is refused; a String key is honoured as its Symbol. | protoST finds either spelling in a Dictionary. | None found. |
| 8 | Where a task's brief and `proto_db` disagree on an interface, `proto_db` wins; the plan is updated. | The spec binds behaviour to `proto_db`. | Signature churn in later tasks. |
| 9 | The startup grace and the log restore belong to the acceptor state, once, at node start; a re-attach reuses them. | One owner for the grace. | Grace semantics on re-attach; tested in Task 10. |
| 16 | The rejoin state is reset at detach in the core, as `proto_db`'s `detach` clears `_rejoin_forced`. | Not a plan note: the core must not carry a detached log's rejoin. | None found. |
| 17 | The timer audit's floors are measured per part; the full audit, the default suite and integration run **once**, in the final verification (Task 30), each task running only its own tests (maintainer, 2026-11-15). | Deterministic runs; a full audit takes hours. | A regression between tasks is found only at Task 30. |
| 18 | The checklist has a third status, `deferred` (to a named task), for tests that need Phase C; the final gate refuses any. | Phase B had no shell, transport or storage. | Rows relabelled at Task 30 (none is left after Task 28). |
| 19 | A failed write on a connection follows rc3: reconnect and write once more at once; back off only after a failed connect. | The brief's drop-and-back-off lost frames `proto_db` keeps. | None found. |
| 19b | The renewal back-off and the fenced term (gamarino/ProtoDB#1) are ported from `proto_db` `88ca21d`, adopted upstream as R149/R149a and shipped in rc4. | The issue was filed from this port and fixed upstream. | None: it is `proto_db`'s rule. |
| 20 | Every guard and failure mode of the coordinator shell follows `proto_db` (fence on unexpected errors only, a dropped message on a rule's `PBDBError`, attach of the same storage a no-op); one fix after the review breaker tripped, adjudicated and closed. | Five review rounds narrowed the differences to timing. | None open. |
| 21 | Persister writes go through the round runner, with the commit round's writes (no root lock held forever); `persist:` refuses a label or epoch that is not the SpaceRoot's (protoBaseST addition). | Review found two failure modes of concurrent writes. | A persist waits behind queued commit work. |
| 22a | **rc4 adopted at its minimum** (maintainer, 2026-11-15): protocol 14, acceptor log format 3 refused, rc4's cluster rules (R148, R149, R212/R231/R233, the D46 amendment); keep writing format 4; refuse format 5 with `PBNotSupportedError`. | rc4 was released mid-branch; a format-4 writer stays valid indefinitely. | The runtime registry waits for its own plan (below). |
| 22b | The R133 gap (an unreadable base that must be committed first) follows rc4 exactly: nothing sent, the term kept. | No technical debt; `proto_db` is the reference. | None. |
| docs | The tutorial is chaptered (13-16) with checked programs in `examples/cluster/`, written before release (maintainer: tutorials are how enthusiasts arrive). | Documentation teaches the reasoning. | Chapters to keep in sync (`tests/docs/tutorial_chapters_sync.sh`). |
| 29 | The cluster benchmark runs each member as a process of its own on loopback, beside a standalone run of the same workload; the root-independent split is measured by a benchmark-only subclass of the round (`BenchRound`), not by a new product statistic; no `proto_db` figure is shown, since `proto_db`'s cluster was not run on the same shape. | Compare like with like; a measurement task changes no product code. | A `proto_db` comparison needs its own driver. |
| 29 | The timer table of the reference is generated from `PBClusterConfig timerTable` and guarded (`tests/docs/timer_table_sync.sh`). | A copied table goes stale. | None. |
| 30 | The timer audit's row `persist` stays outside the simulator audit: its only reader is the persister, a shell actor the simulator does not run; the declaration names that source and class, and the index fails on any other reader. `AcceptFamilies powerLoss:` keeps its between-terms schedule and gains `powerLossInTerm:` (crashes inside a term, then one more commit). The audit's floors are re-measured; the drops are named (R149/R149a, and Task 22b's base read by the build). | The persister is `proto_db`'s `PlainTier.persist`, beside the coordinator; `proto_db`'s power-loss tests keep their load running after the revive. | The persister's timers are tested only where it runs (`cluster_persister.st`, `tests/cluster`). |
| Queries 4b | **(maintainer, 2026-11-19)** An entry's build error of any class fails only that commit in a cluster round too (`PBCoordinatorCore >> roundBuildFailed:in:now:`), a documented deviation from rc4's `_permit_round`, which fails the whole round on an error that is not a `ProtoDBError`. | One rule in every mode: standalone and in a group commit rc4 already fails only the commit whose build raised (`_standalone_round`, review M2); an extractor's exception must not fail its round-mates in a cluster only. Failing one entry is safe: nothing of the round's own root is sent before its builds end; a re-commit, if any, has already committed. An unsent proposal asks `proto_db` to adopt the rule. | A program that relied on a round-mate's build error failing its own cluster commit; none found. Reverting is one branch of the core (`roundBuildFailed:in:now:`), case 30 of `tests/unit/cluster_round_rules.st` and the subcase of case 34, case 27 of `tests/unit/sim_round_rules.st`, case (c) of `tests/unit/idx_merge_extractor.st`, and the docs (deviations.md cluster mode, decisions.md, reference.md, queries.md, tutorial 17, CHANGELOG, the spec 9.2 note, the source comments of round.st, publisher.st, keyspec.st, transactions.st). |

### Known, not adopted: `proto_db` D62 (the runtime registry, format 5)

`proto_db` `v2.0.0rc4` added format 5: the features `parents` (an envelope key `p`) and
`registry` (the types `ModuleList` and `Catalog`, aliases 22 and 23), with `__currentModules` and
`__catalog`, C3 resolution and their merge rules (D62). protoBaseST knows it and does not adopt
it: it reads formats 2 to 4, writes 4, and refuses format 5 with `PBNotSupportedError` (segment
headers, root records, acceptor log format 3; [deviations.md](deviations.md#reading)). A space any
rc4 writer opened with a feature is refused at open, never misread. Why: rc4 allows a writer to
stay at format 4 for data without a feature, and the registry is mostly semantics (load order,
C3 with oid identity, catalog replacement), about the size of the cluster plan itself. Per the
maintainer, the full registry gets its own plan after the cluster branch merges
(`2026-11-15-rc4-delta.md`, section 3b). *Cost:* protoBaseST cannot open a space whose `proto_db`
writers use the registry.

## Proposals to `proto_db`

Text for the maintainer to file in the protoBase repository. Done first:

- **Done: the renewal back-off (gamarino/ProtoDB#1).** An owner whose renewal a majority refused
  renewed again once per round trip until its lease ended. Filed 2026-11-14 from this port;
  adopted upstream as rulings R149 and R149a (merge `88ca21d`), released in `v2.0.0rc4`. The port
  follows it ([deviations.md](deviations.md#cluster-mode)).

Still open (checked against `v2.0.0rc4`):

- **Q7(a): refuse a cluster space without a coordinator.** *Proposal:* `FileStorage` (and every
  storage that can hold a cluster space) should refuse to publish a root into a space whose
  SpaceRoot carries `cluster_term`, or whose directory holds `cluster/`, unless the write comes
  through a coordinator, as `proto_db`'s format spec already requires of a minimal external
  writer ("A minimal external writer (file storage)", step 6: no `cluster/` directory and no
  `cluster_term`); `proto_db`'s own `FileStorage` does not apply that check at rc4.
  *Why:* today a plain `proto_db` process that opens a member's directory publishes a root outside
  the cluster's order; the next persisted cluster root replaces it, and the write is lost without
  an error. *Precedent:* protoBaseST refuses it (`PBFileStorage path:` refuses `cluster/`;
  `replaceRoot:` of a plain storage refuses a cluster SpaceRoot).
- **Q7(b): state the trusted-network assumption.** *Proposal:* the coordinator protocol and the
  cluster guide should say that the transport is plaintext and unauthenticated: anyone who can
  reach a member's port can send it any message, so a cluster must run on a trusted network.
  *Why:* the assumption is real and unstated; operators read the guide, not the code.
  *Precedent:* protoBaseST states it, and offers optional HMAC authentication (CC4).
- **IQ1 (Task 4b): one rule for an unexpected build error in both commit paths.** *Not sent.*
  *Proposal:* rc4's cluster round should adopt the per-commit rule: `_permit_round`
  (`transactions.py:1660-1717` at rc4) should fail only the entry whose build raised an error that
  is not a `ProtoDBError`, as `_standalone_round` does (`transactions.py:1149-1157`), instead of
  failing every unfinished entry with a copy and re-raising. *Why:* the build runs application
  code, an extractor in a merge onto an indexed current; under rc4 one failing extractor fails
  only its own commit standalone and in a group commit, but every commit of the round in a
  cluster, so the same program behaves differently in the two modes. Failing one entry alone is
  safe: nothing of the round's own root is sent before its builds end; a re-commit, if any, has already committed. *Precedent:* protoBaseST does it, by the
  maintainer's decision of 2026-11-19 (`PBCoordinatorCore >> roundBuildFailed:in:now:`;
  `tests/unit/idx_merge_extractor.st` case (c), `tests/unit/cluster_round_rules.st` case 30;
  [deviations.md](deviations.md#cluster-mode)).
- **CC6: bind the node id in the acceptor log (lesson L27), for Phase D.** *Proposal:* record the
  node id in the acceptor log (a new entry kind, or a header field at the next log format), and
  refuse to open a log whose id is not the node's. *Why:* over shared storage the file name
  `cluster/<name>.roots` binds the id, but with per-node disks a log copied onto another member is
  indistinguishable from its own, and two members voting from one history break the majority
  argument. It changes the shared format, so protoBaseST does not add it alone.

A note, not a proposal: `proto_db`'s format spec says a non-string map key drops the connection,
while `protocol.py` admits bin keys (`strict_map_key=True`); the two should say the same thing
([deviations.md](deviations.md#cluster-wire-messages)).

## What is still open

- Whether the three Pharo name clashes should stay (design spec 5.3). This is the first question
  for the workshop.
- Whether zero-based `PBList` positions are the right call for a Smalltalk audience, or whether a
  one-based view should be added over the same tree.
- Whether refusing a `Dictionary` (rather than storing it as a map of unspecified order) costs
  more convenience than it protects.
- **`nextBytes:` on a socket, as observed (cluster plan Task 1, 2026-11-13, protoST 0.10.0;
  `tests/week0/socket_short_reads.st`).** Mid-stream it did not answer short: a reader in
  `nextBytes: 10` that got 4 bytes, then 6 more 200 ms later, answered all 10. At the end of the
  stream it answers what is left (4 bytes of the 10 asked for, the peer having closed), and the
  next `nextBytes:` answers `nil`. LANGUAGE.md §12.11.1 does not promise the mid-stream
  behaviour, so the cluster's `_readExactly:from:` (Task 19) still loops until it has `n` bytes
  and treats `nil` (or an empty answer) as the end of the stream. The runner does not show the
  `NOTE:` lines of a `.st` test, so if the protoST binary changes, Task 19 re-runs
  `tests/week0/socket_short_reads.st` directly and updates this note.
- The open protoST question K23 (not yet filed), the fixed issues S37 to S40 and the documented working-directory module resolution, in [deviations.md](deviations.md#known-protost-limits).
