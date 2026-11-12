# Decisions

Every call that shaped protoBaseST, with what was decided, why, and what it costs if it is wrong.
Three kinds, in this order:

1. [The maintainer's decisions](#1-the-maintainers-decisions) of the design review (2026-11-10).
2. [The planner's calls, C1 to C19](#2-the-planners-calls-c1-to-c19), made unattended when the plan
   was written and reviewed at the end.
3. [Execution rulings](#3-execution-rulings), made while the tasks ran, numbered R1 to R22 where
   they were numbered.

The first two kinds are quoted as decided; where a later ruling superseded one, it says so in the
entry. The rule that governs them all is the maintainer's: **when in doubt, ProtoBase
`v2.0.0rc1` (later `v2.0.0rc2`) is the reference.** This file is the place to overrule any of
them; the cost column says what that would take.

## 1. The maintainer's decisions

| # | Question | Decision | Why | Cost if wrong |
|---|---|---|---|---|
| 1 | Where the code lives | A new repository, `protoBaseST`. `Decimal`, the calendar values and `UUID` go to protoST's `lib/`. | The values are general; a database repository should not own a decimal. | Moving the three libraries is mechanical. |
| 2 | Symbols | A `Symbol` is refused; strings are strings. When `@sym` lands, protoST gets an explicit wrapper. | A symbol stored as a string would come back as a string. In protoST a literal of six bytes or fewer is a `String` (STATUS D35), so a short symbol cannot be told apart anyway. | Code that wants stored symbols waits for format 5. |
| 3 | Immutability of stored values | By convention: built once, never assigned afterwards. No frozen instances. | protoST does not enforce immutability at run time. | A method that mutates would compile; a test scans for it. |
| 4 | Names | ProtoBase's names with the `PB` prefix, camelCase. | One document explains both languages. | Three names clash with Pharo's meaning (`add:`, `remove:`, `removeAt:`); see [deviations.md](deviations.md). Alternatives: `copyWith:`, `copyWithout:`, `copyWithoutIndex:`. |
| 5 | Conflict granularity | The same as ProtoBase: per-root and per-cell read sets, the replace and merge rules, the mutable-cell rules. | A different granularity would be a semantic divergence hidden behind the same name. | None; it is the reference. |
| 6 | Early primitives | Approved: protoIO 0.5.0 and protoST 0.10.0, with `randomBytes:` and a microsecond clock. | The identities and timestamps of the format need OS random bytes and a UTC clock; they belong in protoIO for every runtime. | A release of two other repositories before this one. |

## 2. The planner's calls, C1 to C19

| # | Call | Why |
|---|---|---|
| C1 | *Superseded by ruling R1: protoIO is **0.5.0**, protoST's floor `PROTOIO_MIN_VERSION 0.5.0`.* Original call: protoIO keeps the approved number **0.4.1**, although protoIO bumped the minor for new API in 0.4.0 | The maintainer approved 0.4.1 by number. protoST sets `PROTOIO_MIN_VERSION 0.4.1`. If the maintainer prefers 0.5.0, it is a one-line change in Task 26 |
| C2 | *Renumbered by ruling R10: the release is **0.10.0** (the branch carries breaking changes: D52, K20, numeric hash values, the protoIO floor).* protoST's `lib/` additions (Tasks 3-5) ship in the same release as the bindings | Publication happens once, at the end. The additions are additive and break nothing |
| C3 | The protoST API names are `ByteArray randomBytes: n` and `Time utcMicroseconds` (microseconds since 1970-01-01T00:00Z, wall clock). `Time microsecondClockValue` stays monotonic | Clarity over familiar names: Pharo's `microsecondClockValue` is a wall clock, protoST's is monotonic, and reusing the name would mislead |
| C4 | `randomBytes:` accepts 0 ≤ n ≤ 1,048,576 and signals `InvalidArgument` outside that range | A bound keeps one call from allocating without limit. Identities need 16 bytes |
| C5 | Week-0 checks and every reader task run on the existing `../protoST/build_release/protost` (0.9.0), with protoST's branch `lib/`. The installed `/usr/bin/protost` is 0.8.1 and is not used | The spec assumed an installed 0.9.0. The local release build is 0.9.0 and runs, so no build is needed until Task 2 |
| C6 | The §9 lock check targets ProtoBase's **FileStorage root lock** (`fcntl.flock(LOCK_EX\|LOCK_NB)` on `space.lock`), not `OwnerLock` | At the tag, `OwnerLock` guards logs and tiered storage, not `space.lock` |
| C7 | The calendar classes signal protoST's own `TimeZoneUnavailable` (an `Error` subclass in `lib/calendar.st`) for a wall clock of an instant-zone `DateTime` and for building a named-zone `DateTime` from a wall clock. protoBaseST's own refusals (format-3 `["zone", key]` datetimes) signal `PBNotSupportedError` | The values live in protoST `lib/` (decision 1), which cannot depend on protoBaseST. Spec §4.3 named `PBNotSupportedError`; the refusal stays explicit and is documented |
| C8 | Conformance vectors are **vendored** into `protoBaseST/tests/conformance/vectors/` by a script that extracts them from the tag and checks every file against `vectors.sha256` | A clean checkout must run the tests (Spec §10.8) |
| C9 | The Python side is a venv at `tests/interop/.venv` (git-ignored), made with `--system-site-packages`. `msgpack==1.2.4` is installed only when the import is missing or another version (*amended by Task 17b, ruling R18*: ProtoBase `v2.0.0rc2` needs msgpack ≥ 1.2.0 and its C extension; until then `msgpack==1.1.2` and `v2.0.0rc1`). ProtoBase is extracted with `git archive v2.0.0rc2` into `tests/interop/.venv/protobase/` and used through `PYTHONPATH`; `env.sh` fails a run whose venv holds another commit than `setup_venv.sh` pins | Pure Python, so no install step is needed. Network use is kept to a missing `msgpack` |
| C10 | Spec §10.2 and §10.3 run the verifier through `tests/interop/py_verify.py`. It imports `examples/erp/erp_model.py`, which registers `demo.erp.*`, then calls `proto_db.tools.verify.main([dir, "--out", file])` | A bare `python -m proto_db.tools.verify` would read `demo.erp.Invoice` as opaque. It is still ProtoBase's verifier, with the application's classes registered |
| C11 | The dumps are compared on the `databases` and `opaque_types` keys by `tests/interop/compare_dumps.py`. A `{"opaque": T}` on the protoST side equals `{"object": T}` on the Python side only for the Python-only type `demo.erp.AuditNote` | Atom counts depend on the walk. AuditNote is deliberately unknown to protoST |
| C12 | protoST cannot drive an interactive pipe (`OSProcess run:arguments:input:` is one batch). Interleavings use nested runs. For "start A, start B, commit B, commit A", the side owning A starts A, runs the other language's one-shot script (start B, commit B) as a subprocess, and then commits A. Both assignments run: protoST as A and Python as B, and Python as A and protoST as B | Deterministic with no pipes. Each language validates against the other's commit |
| C13 | Spec §10.7 is driven from Python. `tests/interop/hold_lock.py` takes the `flock`, runs a protoST script whose commit uses `lockTimeout: 50`, asserts it ends in `PBTimeoutError`, then releases | The outcome holds for any duration, because the lock is never released while protoST waits |
| C14 | `PBDBError` is the root of the errors, which mirror `errors.py`: `PBValidationError` (with `PBClosedError` under it), `PBUserError`, `PBCorruptionError`, `PBNotSupportedError`, `PBUnexpectedError` (with `PBOutcomeUnknownError` under it), and `PBLockingError` (with `PBConflictError` and `PBTimeoutError` under it). `PBTimeoutError` is **not** protoST's `TimeoutError` | ProtoBase's hierarchy, so `on: PBLockingError do:` means the same thing in both languages |
| C15 | `PBList` positions follow ProtoBase's `_position`: negative counts from the end; out of range or not an Integer is `PBValidationError` | `lists.py` at the tag |
| C16 | A commit with no writes is a no-op, with no new version, as `Transaction._commit` at the tag | ProtoBase's behaviour |
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
| C10 | The verifier runs with the demo's classes registered, so it is "ProtoBase's verifier, with the application's classes", not the bare command. |
| C11 | The one normalisation (`opaque` equals `object` for `AuditNote`) could hide a real difference; `--exact` runs without it. |
| C12 | Interleavings are scripted with nested runs, not live pipes; a bug that needs true concurrency between processes would not show. |
| C13 | The timeout test is driven from Python, so it needs Python. |
| C14 | None while the hierarchy mirrors `errors.py`. |
| C15 | `PBList` could not match ProtoBase's `List` on a bad position. |
| C16 | An empty commit would publish a version. |
| C17 | A test-only subclass instead of a product hook: outcome resolution is only as tested as the subclass is faithful. |
| C18 | A renumber. |
| C19 | A report that depended on the wall clock. |

## 3. Execution rulings

Rulings R1 to R22 were taken while the tasks ran, by the controller of the build, recorded in
the build ledger, which is not part of this repository; the text of each is here, with its what,
why and cost. Unnumbered rulings follow them.
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
| R12 | Keep 509 nesting (the format's msgpack limit), and ask ProtoBase for a non-recursive codec or a documented depth limit (ask B12). **Superseded by R18.** | ProtoBase's recursive codec failed at about 333 decoding. | A later lowering of the limit. |
| R13 | Implement ProtoBase D21 now: an atom's oid is assigned lazily in memory (a version-4 UUID), with a lock-free publish; remove "unsaved atoms are not keys". | The first reading of D21 was a misreading, corrected on challenge. Atoms are keys before they are saved. | None. |
| R14 | Remove `PBFramedLog`. The `log`-layer vectors become justified, visible skips. | The spec lists framed logs as a non-goal and nothing reads them; keeping an uncalled reader is debt, and its worst case was quadratic. | If cluster or tiered storage enters scope, re-port the reader with ProtoBase's linear prefix-checksum search. |
| R15 | Insert a task for record field access: each record carries a slots Array, with literal-index accessors. | Every later task reads records through this path; the AVL was 35-211 times slower than ProtoBase, and a field read cost about 15 sends. | One task of rework. |
| R16 | Fold the reviewer's extra waste items (polymorphic kind check in the walk, skipping the integer check on writer-built nodes, one handler per tree in `check:`) into the same fix round. | Same code and benchmark. | A larger diff to review. |
| R17 | Positional trees are not subclassable: they refuse subclasses, and writes build plain `PBPosNode` (as ProtoBase's `_pos_set`). | In ProtoBase positional trees are not subclassable; mixing classes gave false corruption. | A later change in positional writes that preserves a subclass. |
| R18 | Adopt ProtoBase **v2.0.0rc2** (B12 resolved: `MAX_VALUE_DEPTH` 1022 containers, readers accept 1024). Supersedes R12. | It touches the codec, the venv pin and the conformance vectors, which Task 18 builds on. rc2 is the new reference. | None. |
| R19 | The publisher never waits. An attempt that finds the root lock held answers "locked" at once; the caller owns the backoff (1 ms doubling to 50 ms until `lockTimeout`). A different epoch at step 8 is `PBConflictError` as ProtoBase's `_publish`. The epoch is taken from the root read under the lock. | An actor must never block its worker: protoST runs many actors per worker, and a waiting publisher deadlocked 40 concurrent commits (reproduced). | Retry logic in the callers instead of one place; and the caller's wait blocks the caller's worker (K23). |
| R20 | Implement ANSI/Pharo `Exception>>outer` in protoST (D7), and have `newTransactionDo:` mark an exception in flight around `e outer`. | A non-Error exception unwound by an outer handler committed the block's writes. The completed-flag variant was rejected: it silently aborts a `^` taken after a resumed notification. | A protoST language-core change before the task could close. |
| R20b | The rule carried from ProtoBase: abort iff an exception unwinds the block. A resumable `Error` (such as `ZeroDivide`) goes through `outer` like any resumable exception. | A resumed `Error` must not silently discard writes; Python's `with` aborts only on unwinding. | A resumed `Error` commits the writes made before it. |
| R21 | `run:` lives in `transactions.st`, beside `newTransactionDo:`, not in `space.st`. | Cohesion. | A file move. |
| R22 | The stretch task (`CountedSet` writes and the D26 counter-transform merge) is done, not cut. | Time allowed, and cutting it would have left `PBCountedSet` mutators refusing. | None. |

Unnumbered rulings, in task order:

| Task | What was decided | Why | Cost if wrong |
|---|---|---|---|
| 7 | Time-zone keys come from a **pinned list** (`PBZoneKeys`, tzdata 2026e), not from the host's zoneinfo. | A key valid on one machine and invalid on another makes a database unreadable by location. | A ProtoBase host without the backward-link names refuses those pinned keys. |
| 7 | A format-4 `["instant", key]` datetime is read as its UTC instant plus the key (D58); the vector `value-instant-wall-out-of-range` is accepted. Writing within one day of years 1 or 9999 is refused. | The format spec lets a reader without a database present the instant in UTC; refusing would call valid data corrupt. | A `datetime.max`-style sentinel in an IANA zone cannot be written. |
| 7 | A format-3 `["zone", key]` datetime is read lazily as `PBLegacyZoneDateTime`, never given an offset, never written. | Old atoms whose other attributes are fine stay readable, and untouched atoms are kept byte for byte. | The vector `datetime-zone-format3` differs from ProtoBase on purpose. |
| 8 | The expected differences from the manifest are a tracked table, not a workspace note. | A difference that is not tracked can go stale. | None. |
| 13 | ProtoBase's save-dependents-first invariant is honoured; the reader keeps a defensive `PBCorruptionError` for a record that needs itself (ask B13 withdrawn). | The invariant is by construction in ProtoBase. | A foreign writer that breaks it gets an error instead of a recursion. |
| 15 | `PBList sliceFrom:to:` refuses a bound that is not an Integer or `nil` (a Boolean included); `extend:` of a String is refused. | Python's `slice.indices` takes `True` as 1, and ProtoBase's own positions refuse `bool`; a String's elements are Characters, which no format stores. | A caller used to Python's slice rules gets an error. Recorded next to ProtoBase's answers in `list_positions.st`. |
| 16 | A rebased version keeps the completeness of the version it was rebased onto. | The brief and ProtoBase's docstring say rebased versions are not mergeable, but ProtoBase's code gives the target's completeness; Python is the tie-breaker. | A rebased version in a commit is always incomplete anyway (the target is loaded). |
| 16 | The test runner prints every `SKIP:` line a passing test emits under its `PASS` line. | A skip must stay visible where the run is read. | Longer output. |
| 17 | `replaceRoot:` is stricter than ProtoBase's: the lock must be held, the pointer must be a SpaceRoot record, the epoch must be current + 1. | An unchecked publish could overwrite a newer commit. | A raw caller that ProtoBase would accept gets an error. |
| 17 | The storage's failure policy is wider than ProtoBase's: any file-system failure while writing ends writing through that storage (`isFailed`). | After a failed write the on-disk state of the segment is unknown. | The space must be reopened. |
| 17b | The root-record refusal drops protoST's MessagePack detail and keeps ProtoBase's sentence word for word. | ProtoBase keeps the detail only as `__cause__`; protoST has no exception chaining. Exact text parity wins. | A corrupt root is harder to diagnose (a cause slot could be added to `PBDBError`). |
| 18 | Atoms are serialised and saved before the root lock, once, and kept across lock retries (never re-saved). | Shorter lock hold; ProtoBase parity. | A crash between save and publish leaves unreachable atoms, which ProtoBase accepts too. |
| 18 | Design spec 7.3 step 7 is amended: the last-known root is read only in a cluster; the single-process prototype keeps none. | It had no reader outside a cluster. | None. |
| 22 | The counted set's log keeps ProtoBase's op kinds (`add`, `remove`, and `transform` only on a rebase). | ProtoBase at the tag is the reference. | The brief listed `transform` for every call; the spec was amended. |
| 22 | `_withChanges:log:complete:` refuses a field the class does not persist. | A misspelled field was silently dropped. | None. |
| 23 | The ERP demo's moments are `committedAt` values of chosen history entries, and the reports refuse to run on equal or out-of-order moments. | Determinism (C19), and a report that blurs two versions is wrong. | None. |
| 24 | The tutorial is checked by `tests/docs/tutorial_snippets.st`, and `tests/docs/tutorial_sync.sh` fails when a tutorial block is not in that test, in order. | A tutorial edited without its test goes stale silently. | A tutorial block cannot be freely reformatted without updating the test. |

## What is still open

- Whether the three Pharo name clashes should stay (design spec 5.3). This is the first question
  for the workshop.
- Whether zero-based `PBList` positions are the right call for a Smalltalk audience, or whether a
  one-based view should be added over the same tree.
- Whether refusing a `Dictionary` (rather than storing it as a map of unspecified order) costs
  more convenience than it protects.
- The four protoST candidates (K21 to K24, not yet filed) in [deviations.md](deviations.md#known-protost-limits).
