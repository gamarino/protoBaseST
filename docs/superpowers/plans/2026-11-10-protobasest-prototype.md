# protoBaseST Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a Smalltalk implementation of ProtoBase on protoST, reading and writing format 4 at
ProtoBase `v2.0.0rc1`, with ProtoBase's transaction semantics, proven by a two-way round trip
with Python and an ERP demo for the FAST workshop on 2026-12-03.

**Architecture:** three repositories, bottom up.
- protoIO 0.5.0 adds OS random bytes and a UTC microsecond clock (rulings R1, R10).
- protoST 0.10.0 binds them and adds `Decimal`, the calendar values and `UUID` to `lib/`.
- The new `protoBaseST` repository holds the codec, framing, file store, AVL structures,
  collections with operation logs, and the transactions with one publisher actor per process.

Every protoBaseST layer is a module under `src/protobase/`, and `src/protobase.st` imports
them in order.

**Tech Stack:**
- C++20, protoIO (GoogleTest), protoST 0.9.x (conformance `.st` programs with `EXPECT:`
  directives);
- protoST Smalltalk;
- CPython ≥ 3.11 with `msgpack` 1.1.2, and ProtoBase extracted from `git archive v2.0.0rc1`,
  for the interop tests only.

**Spec:** `docs/superpowers/specs/2026-11-10-protobasest-prototype-design.md` (protoBaseST
commit `e5f6db9`). The normative format is ProtoBase `v2.0.0rc1` (commit `c48f73e`):
- `docs/source/format-spec.rst`;
- `docs/source/concurrency-model.rst`;
- `proto_db/transactions.py`;
- `tests/conformance/`.

Read every ProtoBase file with `git -C ../ProtoBase show v2.0.0rc1:<path>`, and never modify
that repository. Citations: "FS §X" is a section of `format-spec.rst`, "Spec §N" a section of
the design spec. **When in doubt, ProtoBase at the tag is the reference** (maintainer rule).
Read ProtoBase's code before guessing a behaviour.

## Global Constraints

- **Repositories and branches**, all siblings under `/home/gamarino/Documentos/proyectos/`:
  - `protoIO` on branch `feat/random-clock`;
  - `protoST` on branch `feat/protobase-support`;
  - `protoBaseST` on branch `feat/prototype`;
  - `ProtoBase` is read only.
- **Do not push, merge, tag or publish anything before Task 26.** The maintainer's rule is
  "mergear y publicar al final". Commits stay local on the branches above.
- **Build gate (DEV12).** Every step marked **[BUILD-GATED]** compiles C++. Before it, run
  `pgrep -fa 'protoPython' | grep -E 'cmake|make|ninja|cc1plus|c\+\+|ld'`. If that prints
  anything, wait with a Monitor until-loop until it prints nothing. Never start a build while
  protoPython builds run.
  - Builds use `-j4`. Never run two protoST builds at once.
  - After a protoST build, run `ldd build_release/protost | grep -i protocore` and record the
    library it links.
- **No locks in the protoST layer.** Synchronisation uses only actors, `Future` and `Atom`.
  The `flock` on `space.lock` is the format's inter-process protocol, and only the publisher
  actor takes it.
- **Tests never depend on timing.** No test sleeps, races a clock, or asserts a duration.
  Interleavings are driven step by step by the test. A timeout is tested by an outcome that
  holds for any duration, such as a lock that is never released.
- **Visible skips only.** A test that cannot run (no Python, no venv, a missing protoST 0.10.0
  primitive) prints `SKIP: <reason>` as its last line and exits 77. The final gate (Task 25)
  tolerates no SKIP.
- **Refuse, never diverge.** Any value, type, version or operation the prototype cannot handle
  signals an explicit error naming it (Spec §2, anti-goals). protoBaseST never replaces where
  ProtoBase would merge.
- **Immutability by convention** (decision 3). A persisted value is built once. No method of a
  protoBaseST class assigns an instance variable after construction. The two exceptions are the
  lazy-load memo and the operation-log *consumed* cell (Spec §4.1), and both are `Atom` cells.
- **Names.** Classes and messages come from Spec §5 exactly. Errors mirror
  `proto_db/errors.py`, with `PB` in place of `Proto`.
- **Units.** Timeouts and backoffs are SmallInteger milliseconds: `lockTimeout` defaults to
  30000, and `run:` backoff to `(1, 200)`.
- **Pinned vectors.** The SHA-256 of `tests/conformance/vectors.sha256` is
  `5f86eb09ed1683aa9f048051c64cca68d23b9fb753e87416cb1ecf11ed406df0`. Runners refuse any
  other value.
- **Defects found in protoST** go to protoST `KNOWN_ISSUES.md`, are fixed in protoST on the
  protoST branch, and are never worked around in protoBaseST (Spec §12.5).
- **Documentation.** Every task that adds API also updates its documentation in the same task:
  the tutorial, the reference and the CHANGELOG. Text is professional English.
- **Commits** end with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  `LICENSE`, copyright and attribution use "Gustavo Marino".

## Calls made by the planner (unattended; review at Task 26)

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
| C9 | The Python side is a venv at `tests/interop/.venv` (git-ignored), made with `--system-site-packages`. `msgpack==1.1.2` is installed only when the import is missing or another version. ProtoBase is extracted with `git archive v2.0.0rc1` into `tests/interop/.venv/protobase/` and used through `PYTHONPATH` | Pure Python, so no install step is needed. Network use is kept to a missing `msgpack` |
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

## Review Focus

1. **Cross-kind keys.** A Python-written `Dictionary` keyed by int `1` must be found from
   protoST with `1.0` and with `Decimal fromString: '1.00'`, and must not be found with `true`.
   The case `10**16 + 1` versus `1.0e16` gives two keys. Test in Task 12.
2. **ValueBox threshold by code points.** A string of 255 code points with multi-byte
   characters (more than 256 UTF-8 bytes) is not boxed. One of 256 code points is boxed.
   Python reads both. Test in Task 14, cross-checked in Task 20.
3. **A transaction after its end.** Every message after `commit` or `abort` signals
   `PBUserError`. That includes `commit` twice and a failed commit followed by `commit`. An
   empty commit is a no-op (C16). Test in Task 18.
4. **Integer boundaries.** 2^63-1, 2^63, 2^64-1, 2^64, -2^63 and -2^63-1 are written native or
   `@int` as FS requires, order correctly against `1.8446744073709552e19`, and survive a
   Python round trip as values and as `PBDictionary` keys. Test in Task 7 (codec) and Task 20
   (round trip).
5. **`PBList` positions.** `getAt: -1` answers the last element. `getAt: count` and
   `insertAt: count + 1` signal `PBValidationError`. `insertAt: count value:` appends. Every
   case does what ProtoBase's `List` does, as recorded by a Python run. Test in Task 15.

---

## Phase A: ground releases (week 0, from 11-11)

### Task 1: protoIO 0.5.0, OS random bytes and a UTC microsecond clock

**Files:**
- Create: `protoIO/include/protoio/random.h`, `protoIO/src/random.cpp`,
  `protoIO/include/protoio/clock.h`, `protoIO/src/clock.cpp`.
- Create: `protoIO/tests/test_random.cpp`, `protoIO/tests/test_clock.cpp`.
- Modify: `protoIO/CMakeLists.txt`. Add the sources to `add_library(protoio ...)`, set
  `project(protoIO VERSION 0.5.0 ...)`, and add `bcrypt` to the Windows
  `target_link_libraries`.
- Modify: `protoIO/tests/CMakeLists.txt` with `protoio_test(test_random random)` and
  `protoio_test(test_clock clock)`.
- Modify: `protoIO/README.md`. Add rows to the "API overview" table, add `random|clock` to the
  TSan `-L` list, and change the version in the deb name and in `find_package`.
- Modify: `protoIO/CHANGELOG.md`, adding a section `## 0.5.0 - (unreleased)` under
  `## Unreleased`.

**Interfaces:**
- Produces:
  - `std::string protoio::random::bytes(std::size_t n)`: n bytes from the OS CSPRNG.
    - Linux uses `getrandom(buf, len, 0)`, looping on short reads and `EINTR`.
    - macOS and the BSDs use `getentropy` in chunks of at most 256 bytes.
    - Windows uses `BCryptGenRandom(nullptr, buf, len, BCRYPT_USE_SYSTEM_PREFERRED_RNG)`.
    - Failure throws `protoio::Error(Error::Kind::Internal, msg, errno)`. `n == 0` answers
      `""`.
  - `std::int64_t protoio::clock::utcMicroseconds()`: microseconds since
    1970-01-01T00:00:00Z from `std::chrono::system_clock`.

- [ ] **Step 1: write the failing tests.**
  - `test_random.cpp`:
    - `RandomBytes.ZeroIsEmpty` (`bytes(0).empty()`);
    - `RandomBytes.Length` (sizes 1, 16, 257 and 1 << 20);
    - `RandomBytes.TwoDrawsDiffer` (two 32-byte draws differ: a 2^-256 event, not a timing
      dependency);
    - `RandomBytes.NotAllZero` (a 4096-byte draw has a non-zero byte).
  - `test_clock.cpp`:
    - `UtcMicroseconds.AfterYear2026` (`> 1767225600000000`);
    - `UtcMicroseconds.BracketedBySystemTime`: `t0 = std::time(nullptr)` before,
      `t1 = std::time(nullptr)` after, and `t0 <= us / 1000000 <= t1`.
- [ ] **Step 2 [BUILD-GATED]:** run
  `cmake -S . -B build_release -DCMAKE_BUILD_TYPE=Release && cmake --build build_release -j4 && ctest --test-dir build_release -L 'random|clock' --output-on-failure`.
  Expected: compile FAIL (missing headers).
- [ ] **Step 3:** implement both modules, each header starting with the project's 2-line
  copyright comment and `#pragma once`.
- [ ] **Step 4 [BUILD-GATED]:** build, then run the whole suite with
  `ctest --test-dir build_release --output-on-failure`. Expected: all PASS.
- [ ] **Step 5 [BUILD-GATED]:** TSan run for the new labels, as in the README:
  `-DPROTOIO_TSAN=ON` in `build_tsan`, then `-L 'random|clock'`. Expected: PASS, no reports.
- [ ] **Step 6:** update the README and the CHANGELOG. The CHANGELOG paragraph reads "A patch
  release adding two OS services for protoBaseST: `random::bytes` and
  `clock::utcMicroseconds`."
- [ ] **Step 7:** commit `protoIO 0.5.0: OS random bytes and a UTC microsecond clock`.

### Task 2: protoST 0.10.0 bindings, `ByteArray randomBytes:` and `Time utcMicroseconds`

**Files:**
- Modify: `protoST/CMakeLists.txt`. Set `VERSION 0.10.0` and `set(PROTOIO_MIN_VERSION "0.5.0")`.
- Modify: `protoST/src/primitives/bytes_prims.cpp`. Add `__randomBytes:` on the ByteArray
  class side, registered in `installBytesPrimitives`, with the `unmanaged()` wrapper. Build
  the result through `makeBytes`, and map errors through `ProtoioErrors.h`.
- Modify: `protoST/src/primitives/time_prims.cpp`. Add `__utcMicros`, bound on `objectProto`
  in `installTimePrimitives`.
- Modify: `protoST/lib/kernel/bytes.st` with `ByteArray class >> randomBytes: n`, and
  `protoST/lib/kernel/time.st` with `Time class >> utcMicroseconds`.
- Test: `protoST/tests/conformance/15-binary/random_bytes.st`,
  `random_bytes_bounds.st`, and `protoST/tests/conformance/12-builtins/time_utc_microseconds.st`.
- Modify: `protoST/tests/conformance/14-io/http_request_shape.st` (`protoST/0.10.0`).
- Docs:
  - `docs/LANGUAGE.md`: §12.12.1 for `randomBytes:`, and the time section for
    `utcMicroseconds`, with a sentence that `microsecondClockValue` is monotonic;
  - `docs/tutorial/` (the bytes and time chapters);
  - the version text in `README.md`, `docs/INSTALLATION.md`, `docs/STATUS.md`,
    `docs/ROADMAP.md` and `docs/INTEROP.md`;
  - `CHANGELOG.md`, adding `## 0.10.0 — protoBaseST groundwork (unreleased)` with
    "**Requires protoIO 0.5.0**".

**Interfaces:**
- Consumes: Task 1's `protoio::random::bytes` and `protoio::clock::utcMicroseconds`.
- Produces:
  - `ByteArray randomBytes: n`, a frozen ByteArray of n OS-random bytes (C4 bounds;
    `InvalidArgument` outside them, or for a non-SmallInteger);
  - `Time utcMicroseconds`, a SmallInteger.

- [ ] **Step 1: write the failing tests.**
  - `random_bytes.st`, `"EXPECT: 16 0 true true"`, prints:
    - `(ByteArray randomBytes: 16) size`;
    - `(ByteArray randomBytes: 0) size`;
    - that two 32-byte draws differ;
    - that `[(ByteArray randomBytes: 4) at: 1 put: 0] on: ModificationForbidden do: [:e | true]`
      answers true.
  - `random_bytes_bounds.st`: `-1`, `1048577` and `'x'` each signal `InvalidArgument`. Print
    `3 refused`.
  - `time_utc_microseconds.st`: `t0 := nil __currentMillis. u := Time utcMicroseconds.
    t1 := nil __currentMillis.` Print `(u > 1767225600000000) & (u // 1000 between: t0 and: t1)`.
    Expected `true`.
- [ ] **Step 2 [BUILD-GATED]:** build protoST against the sibling `../protoIO` on its branch
  (`cmake --build build_release -j4`), then run the three files with
  `tests/conformance/run_conformance.sh build_release/protost <file>`. Expected: FAIL
  (doesNotUnderstand).
- [ ] **Step 3:** implement the primitives and the kernel methods.
- [ ] **Step 4 [BUILD-GATED]:** build, check with `ldd`, and run the full suite
  `ctest --test-dir build_release -j1 --output-on-failure`. Expected: all PASS, with SKIP
  lines listed. Then build `build_tsan` and run `ctest -L tsan`. Expected: PASS.
- [ ] **Step 5:** write the docs and the CHANGELOG entry.
- [ ] **Step 6:** commit `protoST 0.10.0: ByteArray randomBytes: and Time utcMicroseconds (protoIO 0.5.0)`.

### Task 3: protoST `lib/decimal.st`, an exact `Decimal` value

**Files:**
- Create: `protoST/lib/decimal.st` (class `Decimal`).
- Test: `protoST/tests/conformance/13-stdlib/`:
  - `decimal-parse-print.st`;
  - `decimal-specials.st`;
  - `decimal-compare.st`;
  - `decimal-exact-fraction.st`;
  - `decimal-invalid.st`.
- Docs:
  - `lib/README.md` (a module table row);
  - `docs/LANGUAGE.md` (a new standard-library subsection, "Exact decimals");
  - `docs/STATUS.md`: deviation **D49**, "`Decimal` is a value without arithmetic: parse,
    print, compare, `asExactFraction`; no context, no rounding";
  - `docs/tutorial/` (the standard-library chapter);
  - `CHANGELOG.md` (the 0.10.0 entry).

**Interfaces:**
- Produces (import with `Import from: 'decimal'`; the class is bound as a global):
  - `Decimal fromString: aString`. It parses Python's `Decimal(str)` syntax: an optional sign,
    digits with an optional point, an optional exponent, `Infinity`/`Inf`, `NaN[digits]` and
    `sNaN[digits]`, case-insensitive. A bad string signals `Error` naming it.
  - `Decimal sign: 0or1 coefficient: aNonNegativeInteger exponent: anInteger`,
    `Decimal infinity: sign`, `Decimal nan: payload signaling: aBoolean sign: s`.
  - Accessors: `sign` (0 or 1), `coefficient`, `exponent`, `payload`, `isFinite`,
    `isInfinite`, `isNaN`, `isSignaling`, `isZero`.
  - `printString` is Python's `str(Decimal)` to-scientific-string, exactly FS "Decimal text".
  - `asExactFraction`: an Integer or a Fraction, for finite values only. Otherwise it signals
    `Error`.
  - Comparison with any `Number` through exact fractions: `=`, `<`, `<=`, `>`, `>=`. A NaN is
    never `=`, and `<` with a NaN signals `Error`. Infinities order at the ends. `hash` is
    consistent with `=`.
  - `sameRepresentationAs: aDecimal`, which compares sign, coefficient, exponent and kind
    exactly, so `1.0` and `1.00` differ.

- [ ] **Step 1: write the failing tests.** Each test prints one line and asserts it with
  `EXPECT:`.
  - `decimal-parse-print.st`: these strings round-trip unchanged through
    `(Decimal fromString: s) printString`: `1.20`, `-0`, `1E-7`, `-1.5E+30`, `0.000001`,
    `1E+2`, `123`, `0E-10`, `-0.00`. These normalise as Python does: `1e5` → `1E+5`,
    `.5` → `0.5`, `+7` → `7`, `1.0E-7` → `1.0E-7`. Copy the expected strings from
    `python3 -c "from decimal import Decimal; print(str(Decimal('<s>')))"` and paste them
    into the test as literals.
  - `decimal-specials.st`: `NaN123`, `sNaN`, `-Infinity`, `-NaN` and `Inf` → `Infinity`, with
    their predicates.
  - `decimal-compare.st`:
    - `(Decimal fromString: '1.00') = 1`;
    - `= 1.0`;
    - `(Decimal fromString: '0.1') = 0.1` is false;
    - `(Decimal fromString: '1.0') sameRepresentationAs: (Decimal fromString: '1.00')` is
      false;
    - `-Infinity < -1E+999999`;
    - `NaN = NaN` is false;
    - `[nan < 1] on: Error do: [:e | 'refused']`.
  - `decimal-exact-fraction.st`: `'1.25'` → `5/4`, `'-0'` → `0`, `'1E+3'` → `1000`.
  - `decimal-invalid.st`: `'1..2'`, `''`, `'1e'` and `'NaNx'` each signal `Error`.
    Print `4 refused`.
- [ ] **Step 2:** run each file with
  `tests/conformance/run_conformance.sh ../protoST/build_release/protost <file>` (0.9.0, no
  build; the binary reads the branch's `lib/`). First confirm `Import from: 'decimal'`
  resolves to the branch file. Expected: FAIL.
- [ ] **Step 3:** implement `lib/decimal.st` in Smalltalk over `LargeInteger`. Use FS
  "Decimal text" and Python's `Decimal.__str__` (adjusted exponent, the `-6` threshold) for
  printing.
- [ ] **Step 4:** run the five tests and the whole `13-stdlib` folder with the same binary.
  Expected: PASS.
- [ ] **Step 5:** docs, then commit `lib/decimal.st: an exact Decimal value (no arithmetic, D49)`.

### Task 4: protoST `lib/calendar.st`, calendar values with fixed offsets

**Files:**
- Create: `protoST/lib/calendar.st`, with classes `CalendarDate`, `TimeOfDay`, `DateTime`,
  `TimeSpan`, `ZoneOffset`, `ZoneName` and the error `TimeZoneUnavailable` (C7).
- Test: `protoST/tests/conformance/13-stdlib/`:
  - `calendar-date.st`;
  - `calendar-time.st`;
  - `calendar-datetime.st`;
  - `calendar-timespan.st`;
  - `calendar-zones.st`;
  - `calendar-now-utc.st` (needs Task 2's binary);
  - `calendar-invalid.st`.
- Docs: `lib/README.md`, `docs/LANGUAGE.md` ("Calendar values"), and `docs/STATUS.md`
  deviation **D50**. D50 reads: "Calendar values are protoST's own classes. They count
  microseconds; `Date`, `Time` and `Duration` keep their kernel meaning. There is no IANA
  database: a named zone keeps its key, and a wall clock in it is refused with
  `TimeZoneUnavailable`." Also `docs/tutorial/` and `CHANGELOG.md`.

**Interfaces:**
- Produces (import with `Import from: 'calendar'`):
  - `ZoneOffset microseconds: us name: aString`, where |us| < 86400·10^6, and
    `ZoneOffset utc` (0, `'UTC'`). It answers `microseconds` and `name`.
  - `ZoneName key: aString` (an IANA key, kept as text, no rules). It answers `key`.
  - `CalendarDate year: y month: m day: d`, with the proleptic Gregorian calendar and years
    1-9999. It answers:
    - `year`, `month`, `day`;
    - `ordinal` (0001-01-01 is 1), and `CalendarDate fromOrdinal: n`;
    - `=`, `hash`, `<`;
    - `printString` (`2026-11-10`).
  - `TimeOfDay hour: h minute: mi second: s microsecond: us fold: f zone: z`, where `z` is
    `nil`, a `ZoneOffset` or a `ZoneName`; plus `hour:minute:second:`. It answers the fields
    and `microsecondsSinceMidnight`.
  - `DateTime year:month:day:hour:minute:second:microsecond:fold:zone:`:
    - with `nil` it is naive;
    - with a `ZoneOffset` it is a fixed offset;
    - with a `ZoneName` it signals `TimeZoneUnavailable` (no wall-clock conversion).
  - `DateTime utcFields: anArray7 zoneName: aZoneName`: the instant form, whose fields are
    the UTC instant and whose fold is 0.
  - `DateTime nowUTC`, from `Time utcMicroseconds`, with zone `ZoneOffset utc`.
  - `DateTime` accessors:
    - `localMicroseconds`: the fields' microseconds since 0001-01-01T00:00;
    - `utcMicroseconds`: for a fixed offset, local minus the offset; for the instant form,
      local; for a naive value it signals `Error`;
    - `isNaive`, `zone`, `fold`;
    - `wallClock`: a `ZoneName` value signals `TimeZoneUnavailable`; any other value answers
      self.
  - `DateTime utcMicroseconds: n zone: aZoneOffset`, which builds from an instant.
  - `TimeSpan days: d seconds: s microseconds: us`, normalised exactly as Python's
    `timedelta`: 0 ≤ seconds < 86400, 0 ≤ us < 10^6, and |days| ≤ 999999999 or it signals
    `Error`. Also `TimeSpan microseconds: n`, `totalMicroseconds`, `days`, `seconds`,
    `microseconds`, `=`, `<`, `hash`.

- [ ] **Step 1: write the failing tests.** Use the expected values printed by CPython
  (`date.toordinal()`, `timedelta(...)` normalisation), pasted as literals.
  - Ordinals: 0001-01-01 → 1, 2000-02-29, 9999-12-31 → 3652059.
  - Normalisation: `TimeSpan days: 0 seconds: -1 microseconds: 0` → `-1 86399 0`.
  - Fixed offset: `utcMicroseconds` of 2026-11-10 12:00 at `UTC-03:00` equals that of
    15:00 UTC.
  - `wallClock` of an instant-zone value is refused.
  - `calendar-invalid.st`: month 13, day 30 of February, year 0 and year 10000, and offset
    86400·10^6, each signal `Error`. Print `5 refused`.
  - `calendar-now-utc.st`: `DateTime nowUTC` lies between 2026 and 2100. Without
    `Time respondsTo: #utcMicroseconds`, print `SKIP: needs protoST 0.10.0`.
- [ ] **Step 2:** run them with `../protoST/build_release/protost`. Expected: FAIL.
- [ ] **Step 3:** implement in Smalltalk.
- [ ] **Step 4:** run them. Expected: PASS, with `calendar-now-utc.st` SKIPPING until
  Task 2's build is done. Re-run it after that build. Expected: PASS.
- [ ] **Step 5:** docs, then commit `lib/calendar.st: dates, times, datetimes, time spans and fixed offsets (D50)`.

### Task 5: protoST `lib/uuid.st`, a `UUID` value

**Files:**
- Create: `protoST/lib/uuid.st`.
- Test: `protoST/tests/conformance/13-stdlib/uuid-parse-print.st`, `uuid-compare.st`,
  `uuid-v4.st` (needs Task 2's binary).
- Docs: `lib/README.md`, `docs/LANGUAGE.md` ("UUID", with Pharo's meaning and no deviation),
  `docs/tutorial/`, `CHANGELOG.md`.

**Interfaces:**
- Produces (import with `Import from: 'uuid'`):
  - `UUID fromBytes: aByteArray16`, and `UUID fromString:`, which accepts 32 hex digits or the
    36-character form, in either case;
  - `UUID new`: version 4, from `ByteArray randomBytes: 16`, with the version and variant
    bits set as RFC 4122;
  - `bytes`, `hex` (32 lowercase digits), `printString` (the 36-character lowercase form);
  - `asInteger`, the unsigned big-endian value;
  - `=`, `hash`, `<` (by `asInteger`).

- [ ] **Step 1: failing tests.**
  - Round trip of `'12345678-1234-5678-1234-567812345678'`, and of its 32-hex form.
  - `asInteger` of `ff…ff` is `2 raisedTo: 128` minus 1.
  - A bad length signals `Error`.
  - `uuid-v4.st`: `(UUID new bytes at: 7) bitShift: -4` is 4, and the variant bits are `2r10`.
    Two `UUID new` differ. Without `ByteArray respondsTo: #randomBytes:`, print a SKIP line.
- [ ] **Step 2:** run them with the 0.9.0 binary. Expected: FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run them. Expected: PASS, with `uuid-v4.st` passing after Task 2's build.
- [ ] **Step 5:** docs, then commit `lib/uuid.st: UUID values (RFC 4122, version 4 from OS random bytes)`.
- [x] **Step 6 (protoBaseST, added by the Task 7 review):** done in protoBaseST 1ee0e98 (protoST `lib/uuid.st`: 25fa7e2).
  - `src/protobase/codec.st` gets `Import from: 'uuid'`, unconditionally, so a program no
    longer needs to import it itself. Until this task, PBCodec looks the global `UUID` up at
    run time and refuses `@uuid` without it.
  - `PBCodec` reduces a `UUID` subclass to its base value from the base instance variables.
    Today it signals `PBNotSupportedError`, because the layout is unknown before this task.
  - Run `tests/unit/codec_tagged_uuid.st`, which must pass, not SKIP.
  - Remove `values/uuid` from Task 8's expected-differences list, and the uuid rows of the
    key runners (Task 10: `order`, `hashes`, `exact_tokens`); their EXPECT lines become
    `order ascending 43/43 equal 4/4 unorderable 5/5`, `hashes 36/36 atom_hashes 3/3` and
    `exact_tokens 34/34 atom_tokens 3/3`.
  - Remove `database/13966` (added by Task 11: the database record holding a `@uuid`) from
    `tests/conformance/_expected_differences.st`; the EXPECT line of
    `tests/conformance/database_records.st` becomes `database records 127/127` (Task 11's brief
    says `N/N`; it reads `126/127 expected 1` until this step).
  - Remove the two `database_contents` entries (`database` and `root invoice`, added by Task 12:
    the root `invoice` holds the `@uuid` value) from `tests/conformance/_expected_differences.st`;
    the EXPECT line of `tests/conformance/database_contents.st` becomes
    `database contents ok (database contents 17/17)` (it reads `15/17 expected 2` until this step).

---

## Phase B: protoBaseST reader (weeks 0-2)

Every protoBaseST test is a `.st` program whose first line is a directive, as in protoST's
conformance suite: `"EXPECT: <last line>"` or `"EXPECT-ERROR: <text>"`. A last line
`SKIP: ...` exits 77. Files starting with `_` are helpers. The runner sets `cwd` to the test's
directory and `STPATH=$REPO/src`, so a test imports `Import from: 'protobase'`. Inside
`src/`, modules import each other as `Import from: 'protobase/<name>'`.

### Task 6: Repository skeleton, test runner, venv, vendored vectors and the week-0 checks

**Files:**
- Create:
  - `LICENSE` (C18), `CHANGELOG.md` (`## 0.1.0 (unreleased)`), and `.gitignore`
    (`tests/interop/.venv/`, `*.tmp`, `tests/**/out/`);
  - `src/protobase.st`, the module that imports every submodule in layer order; it starts
    empty and grows task by task;
  - `src/protobase/errors.st`, with the hierarchy of C14, each class carrying a class comment
    naming its ProtoBase counterpart;
  - `tests/run_tests.sh [path...]`, which runs `*.st` (directive semantics) and `*.sh` (exit
    0 pass, 77 skip, anything else fail) under the given paths, or under `tests/` and
    `examples/` by default, and prints a summary `passed N, failed N, skipped N`;
  - `tests/conformance/fetch_vectors.sh` (C8), which extracts `tests/conformance/` of
    `$PROTOBASE_REPO` (default `../ProtoBase`) at `v2.0.0rc1` into `tests/conformance/`.
    It refuses unless `sha256sum vectors.sha256` equals the pinned digest and every listed
    file matches;
  - the vendored `tests/conformance/manifest.json`, `vectors.sha256`, `vectors/**` and
    `README.md`, copied verbatim; the Python files (`generate.py`, `test_conformance.py`)
    are not vendored;
  - `tests/interop/setup_venv.sh` (C9). It checks that `v2.0.0rc1` resolves to `c48f73e`
    and that Python is 3.11 or newer, and is idempotent;
  - `tests/interop/env.sh`, sourced by interop tests, which sets `PY`, `PYTHONPATH` and
    `PROTOST`, or prints `SKIP: venv missing (run tests/interop/setup_venv.sh)` and exits 77;
  - `tests/week0/msgpack_uint64_float64.st`, `tests/week0/json_manifest.st`,
    `tests/week0/lock_excludes_protobase.sh` with `tests/week0/_lock_peer.py`;
  - `tests/unit/errors_hierarchy.st`.
- Modify: `README.md`, adding a "Running the tests" section and setting `PROTOST`.

**Interfaces:**
- Produces:
  - the runner contract above;
  - the environment variables `PROTOST` (default `protost`) and `PROTOBASE_REPO`;
  - the error classes of C14.

- [ ] **Step 1: write the week-0 checks** (Spec §9) and `errors_hierarchy.st`.
  - `msgpack_uint64_float64.st` checks four encodings:
    - `(MessagePack encode: (2 raisedTo: 63)) hex` is `'cf8000000000000000'`;
    - `(MessagePack encode: (2 raisedTo: 64) - 1) hex` is `'cfffffffffffffffff'`;
    - `(MessagePack encode: 1.5) hex` is `'cb3ff8000000000000'`;
    - `(MessagePack encode: 0.0) hex` is `'cb0000000000000000'`.

    It prints `ok 4`.
  - `json_manifest.st` parses the vendored `manifest.json` with `lib/json.st` and prints
    `(m at: 'values') size` and `(m at: 'invalid') size`. Expected: `73 59`.
  - `lock_excludes_protobase.sh` (C6):
    1. Python opens `space.lock` as ProtoBase's FileStorage does and takes
       `fcntl.flock(fd, LOCK_EX | LOCK_NB)`, holding it until its stdin closes.
    2. A protoST script asserts `(BinaryFile open: lock options: #(#read #write #create)) tryLock`
       answers false.
    3. After the peer exits, the script asserts it answers true.

    The shell feeds the peer's stdin from a FIFO it keeps open, and reads the peer's stdout
    from a second FIFO. It waits for the `locked` line before running the script, and closes
    the stdin FIFO to release the lock. The order comes from that line, never from a sleep.
  - `errors_hierarchy.st` prints `(PBConflictError inheritsFrom: PBLockingError)`,
    `(PBClosedError inheritsFrom: PBValidationError)`,
    `(PBOutcomeUnknownError inheritsFrom: PBUnexpectedError)` and
    `(PBTimeoutError inheritsFrom: TimeoutError) not`. Expected: `true true true true`.
- [ ] **Step 2:** run `PROTOST=../protoST/build_release/protost tests/run_tests.sh tests/week0 tests/unit`.
  Expected: the three checks PASS (they test protoST 0.9.0 itself) and `errors_hierarchy.st`
  FAILS. **If a week-0 check fails, stop.** Record the defect in protoST `KNOWN_ISSUES.md`
  and fix it on the protoST branch (a C++ fix is BUILD-GATED) before Task 7.
- [ ] **Step 3:** implement `errors.st` and `src/protobase.st`.
- [ ] **Step 4:** run `fetch_vectors.sh` (expected: "digest ok"), then `setup_venv.sh`, then
  the runner on everything. Expected: all PASS.
- [ ] **Step 5:** commit `Skeleton: errors, test runner, vendored conformance vectors, venv, week-0 checks`.

### Task 7: Value classes and the canonical codec

**Files:**
- Create:
  - `src/protobase/values.st`: `PBFrozenList`, `PBTuple`, `PBFrozenDict`, `PBMissing` (a
    singleton), `PBMutableObject` (the value part only: `name:` and `name`;
    `get:`/`set:value:` come in Task 13 and Task 18), `PBAtomPointer` and `PBUnresolvedRef`;
  - `src/protobase/codec.st`: `PBCodec`.
- Test: `tests/unit/`:
  - `codec_roundtrip_scalars.st`;
  - `codec_int_boundaries.st` (Review Focus 4);
  - `codec_floats_bitexact.st`;
  - `codec_tagged.st`;
  - `codec_refusals.st` (Spec §10.5: a `Symbol`, a `Fraction`, a protoST `Dictionary`, a
    `Character`, a `Set`, an `Interval`, a block);
  - `codec_wire_checks.st`: a `bin` key, an ext value, a two-key tagged map, an `@int` in
    native range, `@missing` other than 0, and an unknown tag (`@sym`) are refused with
    `PBCorruptionError`;
  - `values_immutable.st`.

**Interfaces:**
- Consumes: `Decimal`, `CalendarDate`, `TimeOfDay`, `DateTime`, `TimeSpan`, `ZoneOffset`,
  `ZoneName` and `UUID` (Tasks 3-5); `MessagePack encode:`, `decodeOrdered:` and
  `MessagePackMap withAll:`.
- Produces:
  - `PBFrozenList withAll: aSequence`, `PBTuple withAll: aSequence`,
    `PBFrozenDict withAssociations: anArrayOfAssociations` (insertion order kept; keys
    compared by order key once Task 10 exists). They answer `size`, `at:` (1-based on these
    value classes, as Smalltalk's), `do:`, `keysAndValuesDo:`, `associations`, `=`, `hash`;
  - `PBMissing default`;
  - `PBCodec class >> canonical: aValue` → the canonical value. An `Array` or
    `OrderedCollection` is copied to a `PBFrozenList`; a host subclass of a mapped class is
    reduced to its base value; a refused value signals `PBValidationError` naming the class;
  - `PBCodec class >> toWire: aValue atomRef: aBlock` → a MessagePack-encodable tree.
    `aBlock value: anAtom` answers the wire form of a reference: `{"@ref": [...]}` for a
    pointer, or `{"@ref": nil}` in token mode;
  - `PBCodec class >> fromWire: aTree resolver: aResolverOrNil` → a value.
    `aResolver refTo: segmentBytes offset: anInteger tag: aTag` answers an unloaded atom
    (Task 9). With a nil resolver, a ref decodes to `PBUnresolvedRef pointer: aPBAtomPointer tag: aTag`,
    which encodes back to the same `@ref`;
  - `PBAtomPointer segment: aUUID offset: anInteger`, with `=`, `hash` and `printString`;
  - `PBCodec class >> encode: aValue` → a ByteArray, and `PBCodec class >> decode: aByteArray`
    → a value, for one value as it sits in a state map.

  A zone datetime in the format-3 `["zone", key]` form decodes to a `DateTime` flagged
  `isLegacyZone`. Encoding it is refused with `PBValidationError`, and every order or hash use
  of it signals `PBNotSupportedError` naming the zone (Spec §4.3). It is never given an
  offset.

- [ ] **Step 1: write the failing tests**, with exact bytes from FS "Canonical values".
  - `codec_int_boundaries.st`: the encodings of 2^63-1, 2^63, 2^64-1, 2^64 (`{"@int": "10000000000000000"}`),
    -2^63 and -2^63-1 (`{"@int": "-8000000000000001"}`), each as hex.
  - `codec_floats_bitexact.st`: NaN with a payload, `-0.0`, `±inf` and a subnormal keep their
    bits through a round trip.
  - `codec_tagged.st` covers each tagged form: `@dec` `'1.20'`, `@date`, `@time` with a fixed
    zone, `@dt` with `["instant", "America/Argentina/Buenos_Aires"]`, `@td` normalised,
    `@uuid`, `@tup`, `@map` (insertion order), `@missing`, `@mut`.
  - `values_immutable.st` greps the protoBaseST sources through `OSProcess`. Every
    `instanceVariableNames:` class of `src/protobase/*.st` has its ivar assignments only in
    class-side constructors and `set...:` initialisers called from them. The check is
    `grep -n ':= ' src/protobase/*.st` against an allowlist file `tests/unit/_ivar_allowlist.txt`
    of `Class>>selector` initialisers. It prints `ok`. This is the Spec §12.6 check, and it
    grows with each task.
- [ ] **Step 2:** run `tests/run_tests.sh tests/unit` with `PROTOST=../protoST/build_release/protost`.
  Expected: FAIL.
- [ ] **Step 3:** implement. Check the decode side's rules on the tree that `decodeOrdered:`
  answers:
  - keys are str only;
  - no `MessagePackExt`;
  - one key per tagged map;
  - one spelling for `@int`, `@dec` (decode then `printString` must equal the text), `@td`
    and the date fields.

  Encode with `MessagePackMap` for every map.
- [ ] **Step 4:** run the tests. Expected: PASS.
- [ ] **Step 5:** commit `Codec: canonical values, wire checks and refusals`.

### Task 8: Manifest notation and the value-layer vector runner

**Files:**
- Create: `src/protobase/notation.st` (`PBNotation`).
- Create: `tests/conformance/_vectors.st`. It loads `manifest.json`, checks the pinned digest
  and every file's SHA-256 against `vectors.sha256` (use `ByteArray sha256`), and answers the
  manifest.
- Test: `tests/conformance/values.st` (`EXPECT: values 73/73 decode-only 6/6 read-not-rewritten 3/3`),
  and `tests/conformance/invalid_value.st` (`EXPECT: invalid value-layer N/N`, where N is the
  manifest's count of `layer = "value"` entries, computed and printed by the runner).
- Test: `tests/unit/notation_float_hex.st`.

**Interfaces:**
- Consumes: `PBCodec` (Task 7).
- Produces:
  - `PBNotation class >> describe: aValue` → a JSON-ready structure (protoST `Dictionary` with
    one key, `Array`s), following the README notation and `proto_db/tools/notation.py`
    exactly;
  - `PBNotation class >> build: aDescription` → a value;
  - `PBNotation class >> describeRaw: aWireTree`, adding `array`/`mpmap`;
  - `PBNotation class >> floatHex: aFloat`, Python's `float.hex` (`0x1.8000000000000p+0`,
    `0x0.0p+0`, `-0x0.0000000000001p-1022`; `nan`, `inf`, `-inf` as `repr`), and
    `PBNotation class >> floatFromHex: aString` (bit exact, built through `float64At:`).
  - `describeObject:` and `describeDatabase:` come in Task 12.

- [ ] **Step 1: write the failing tests.**
  - `notation_float_hex.st`: `1.5`, `0.1` → `0x1.999999999999ap-4`, `-0.0`, `5e-324` and
    `1.7976931348623157e308` match CPython's `float.hex` (paste the literals), and round-trip
    through `floatFromHex:`.
  - `values.st` checks every `values` entry: `PBCodec decode:` of the file, then `describe:`,
    equals the entry's `value`; and `PBCodec encode:` of `build:` of the value equals the
    file's bytes.
    - `values_decode_only`: the decode matches, and the re-encode equals the `canonical`
      file.
    - `values_read_not_rewritten`: the decode matches, and the re-encode signals
      `PBValidationError`.
    - Each mismatch prints `FAIL <id>: <why>` and the runner continues.
  - `invalid_value.st`: each `layer = "value"` file is refused with the listed class
    (`corruption` → `PBCorruptionError`, `not_supported` → `PBNotSupportedError`). A refusal
    with the wrong class is a FAIL.
- [ ] **Step 2:** run `tests/run_tests.sh tests/conformance tests/unit`. Expected: FAIL.
- [ ] **Step 3:** implement `notation.st` and `_vectors.st`.
- **Expected differences** (added by the Task 7 review; tracked here, never only in the SDD
  workspace). The runners keep this list as data in `tests/conformance/_expected_differences.st`.
  - Each listed id prints `EXPECTED <id>: <reason>` and is counted apart from passes.
  - A listed id that now matches the manifest (it "unexpectedly passes") is a FAIL, so the
    list cannot go stale.
  - So is a listed id that is missing from the manifest.

  The EXPECT lines then name the counts, for example
  `values 72/73 expected 1 decode-only ...`.

  | Vector (section/id) | What protoBaseST does | Why | Removed by |
  |---|---|---|---|
  | `values/uuid` | decode: `PBNotSupportedError` | `lib/uuid.st` is not in protoST 0.9.0 | Task 5, Step 6: removed in 1ee0e98 |
  | `values_decode_only/datetime-zone-format3` | decodes to a `PBLegacyZoneDateTime` (wall clock), not the instant; re-encoding it is `PBValidationError` | the instant needs a tz database (design §4.3) | permanent, design §4.3 |
  | `values_read_not_rewritten/map-zone-key-format3` | re-encoding is refused, as listed; the decoded keys are the format-3 wall clocks, not instants | the same | permanent, design §4.3 |
  | `invalid/value-instant-wall-out-of-range` | accepted and presented in UTC | the wall-clock range needs the zone's rules; the format spec (Known gaps) lets a reader without a database present the instant in UTC | permanent, design §4.3 |
  | `order/uuid 00000000000000000000000000000001`, `order/uuid ff000000000000000000000000000000` | stage `order`: `PBNotSupportedError` | the value cannot be built: `lib/uuid.st` is not in protoST 0.9.0 | Task 5, Step 6: removed in 1ee0e98 |
  | `hashes/uuid ffffffffffffffffffffffffffffffff`, `hashes/uuid 12345678123456781234567812345678` | stage `hash`: `PBNotSupportedError` | the same | Task 5, Step 6: removed in 1ee0e98 |
  | `exact_tokens/uuid 12345678123456781234567812345678` | stage `token`: `PBNotSupportedError` | the same | Task 5, Step 6: removed in 1ee0e98 |

  Removed by Task 9: `values_decode_only/ref-format2`, `ref-name-of-builtin` and `ref-alias`
  (the reader maps a built-in name to its alias and an application alias to its declared name
  through `PBTypeRegistry`; the runner now matches them).

  Removed by Task 10: `values_read_not_rewritten/map-nan-keys-format3` and
  `map-decimal-nan-keys-format3` (the writer's map-key rule, `PBKeys checkMapKeys:reading:`,
  refuses two NaN keys of one exact token), `invalid/map-key-bool-and-int` and
  `map-key-equal-numbers` (`PBFrozenDict` keys follow the order-key rule). Added by Task 10:
  the uuid rows of the key runners (`order`, `hashes`, `exact_tokens`; their manifest
  sections have no ids, so a runner names a value `kind body`).
- [ ] **Step 4:** run. Expected: PASS, with exactly the expected differences above. A
  failing vector that is not listed is a codec bug (fix it in Task 7's files); never edit a
  vector, and never add an entry without a reason and a removing task (or "permanent" with
  a design reference).
- [ ] **Step 5:** commit `Notation and value-layer vector runner (values, decode-only, read-not-rewritten, invalid values)`.

### Task 9: Framing: segment header, records, root record, atom envelope and the type registry

**Files:**
- Create: `src/protobase/framing.st`, with:
  - `PBSegmentHeader`, `PBRecordHeader`, `PBRootRecord`, `PBAtomEnvelope`;
  - `PBTypeRegistry`, with the alias table of FS "Built-in type aliases";
  - `PBAtom`, the base class with its lazy-load memo.
- Test:
  - `tests/conformance/framing.st` (`EXPECT: framing 10/10`);
  - `tests/conformance/invalid_framing.st` (the `record`, `segment` and `root` layers;
    `EXPECT: invalid framing-layers N/N`);
  - `tests/unit/registry_names.st`.

**Interfaces:**
- Consumes: Task 7, Task 8.
- Produces:
  - `PBSegmentHeader class >> decode: bytes26` → `version` and `segment` (4, 3 and 2 are
    accepted; a bad magic is `PBCorruptionError`; another version is
    `PBNotSupportedError`); `PBSegmentHeader class >> encodeSegment: aUUID` → 26 bytes,
    version 4;
  - `PBRecordHeader class >> decode: bytes15` → `kind`, `length`, `payloadCrc` (magic and
    header CRC checked), and `PBRecordHeader class >> encodeKind: k payload: aByteArray` →
    the 15 bytes plus the payload;
  - `PBRootRecord class >> decode: aByteArray` → `version`, `segment`, `offset`, `epoch`, with
    the CRC and field types checked. Extra keys are ignored, a version outside 2-4 is
    `PBNotSupportedError`. `encode` writes version 4 with keys in the order
    `version, segment, offset, epoch`;
  - `PBAtomEnvelope class >> decode: payload expecting: aTypeTag` → `tag`, `oid` (16 bytes),
    `state` (a `PBFrozenDict` in wire order), with the FS "Atom records" checks: exactly
    `t`, `oid`, `s`; attribute names non-empty, no leading `_`, not `oid`, `atom_pointer` or
    `context`; `t` matching the reference. `encode` writes the keys `t`, `oid`, `s`;
  - `PBTypeRegistry`. It is process-wide, held in an `Atom` over a `PBFrozenDict`.
    - `PBTypeRegistry register: aClass` reads `aClass typeName` and `aClass typeAliases`.
      A conflicting name is `PBValidationError`; a name must match FS "Type names", with two
      or more dotted ASCII identifiers.
    - `classForTag: anIntegerOrString` → a class. An unknown `proto_db.` name is
      `PBCorruptionError`, any other unknown name is `PBOpaqueAtom`, and pre-D57 Python names
      are accepted as FS lists them.
    - `tagFor: aClass` → the alias Integer for a built-in, or the type name for an
      application type.
  - `PBAtom`, the abstract base. It holds `oid`, `pointer`, `storage` and `memo` (an `Atom`
    holding nil or the loaded `PBFrozenDict` state).
    - `PBAtom class >> typeName`, `typeAliases`, `requiredFields` (Array), `persistedFields`
      (the writer's attribute order, taken from the database vector's records).
    - `PBAtom class >> unloadedAt: aPointer storage: aStorage`.
    - `PBAtom >> state`, which loads through `storage loadAt: pointer expecting: tag`
      (Task 11) and memoises with `memo value:ifCurrent:`.
    - `PBAtom >> stateAt: aName`, `isLoaded`, `oid`.

- [ ] **Step 1: failing tests.**
  - `framing.st` checks each `framing` entry: decode it to the listed fields (through
    `describeRaw:` for msgpack bodies), then re-encode it to the same bytes. The v2/v3
    headers and roots, the cloud root and the tiered root are decoded. The cloud and tiered
    roots are only checked to decode their file-storage fields, and the runner prints
    `NOTE: cloud/tiered extra keys ignored`.
  - `registry_names.st`: alias 6 → `PBDictionary`'s registered class (a placeholder class
    stands in until Task 12); `'proto_db.collections.Dictionary'` → the same;
    `'proto_db.nonexistent.X'` → `PBCorruptionError`; `'polyglot.st.Order'` → `PBOpaqueAtom`;
    `'bad'` → `PBValidationError`.
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 3b (added by the Task 7 review):**
  - Map built-in type names to their aliases, and application aliases to their declared
    names, wherever `PBCodec` reads a `@ref`. Do it in `PBUnresolvedRef` creation and in the
    resolver path.
  - `PBCodec` then uses the registry instead of `_builtinAliasCount`.
  - An object's atom class answers `isPBReference` true, as `PBUnresolvedRef` does.
  - Remove `ref-format2`, `ref-name-of-builtin` and `ref-alias` from Task 8's
    expected-differences list; Task 8's runner must then match them.
  - `PBNotation` (Task 8) holds a literal copy of the 22 built-in aliases
    (`builtinAliasNames`, used by `_typeName:` and `_buildRef:`). Replace it with
    `PBTypeRegistry`, delete `builtinAliasNames`, and make `tests/conformance/_vectors.st`
    compare the registry's built-in table with the manifest's `builtin_type_aliases`.
- [ ] **Step 4:** run `tests/run_tests.sh tests/conformance tests/unit`. Expected: PASS.
  **Gate of week 1** (Spec §11): `values`, `values_*`, `invalid` at the value, record,
  segment and root layers, and `framing`.
- [ ] **Step 5:** commit `Framing: segment, record, root and atom envelope; the type registry`.
- **As implemented** (calls of the Task 9 implementer, see its report):
  - `PBTypeRegistry`, `PBAtom` and `PBOpaqueAtom` are in `src/protobase/registry.st`, not in
    `framing.st`: `PBCodec` (below `framing.st`, which needs the codec) reads `@ref` tags through
    the registry, so the registry is a module of its own between `values.st` and `codec.st`.
  - `PBAtom`'s memo holds the loaded envelope (tag, oid, state), not only the state: an unloaded
    stub learns its oid from the record. `state` answers the envelope's state.
  - A built-in type whose class is not registered yet is `PBNotSupportedError`, never corruption.
  - Registration (fix round 1): a declared name follows the grammar and a `proto_db.` declared
    name must be in the table; an alias is any non-empty string that is not a built-in name, as
    ProtoBase's `__type_aliases__` (pre-D57 names such as `pkg.mod.f.<locals>.Person`). Writers
    use `PBTypeRegistry writerTag:`, which writes the canonical spelling and refuses a name
    every reader refuses. The table is a private hashed `Dictionary` snapshot behind the
    `Atom` (constant-time lookup), copied on each registration and never changed once
    installed, not a `PBFrozenDict` (whose lookup is linear).
  - Task 11's resolver answers `PBTypeRegistry unloadedAtomFor: tag at: pointer storage: self`,
    which builds a `PBOpaqueAtom` that keeps the name it was referenced by for an unknown
    application name (`PBOpaqueAtom unloadedAt:storage:` alone is refused: it needs the name).
  - Task 12 extends `PBOpaqueAtom` (in `registry.st`) instead of defining it in `records.st`, and
    replaces the test-side `ConformanceInvoice` of `_vectors.st` (a `PBAtom` subclass) by a
    `PBObject` subclass.

### Task 10: Order keys, hash keys and exact tokens

**Files:**
- Create: `src/protobase/keys.st` (`PBOrderKey`, `PBKeys`).
- Test:
  - `tests/conformance/order.st`
    (`EXPECT: order ascending 41/43 expected 2 equal 4/4 unorderable 5/5`);
  - `tests/conformance/hashes.st` (`EXPECT: hashes 34/36 expected 2 atom_hashes 3/3`);
  - `tests/conformance/tokens.st` (`EXPECT: exact_tokens 33/34 expected 1 atom_tokens 3/3`);
  - the uuid vectors are expected differences until Task 5 (`lib/uuid.st`); Task 5 Step 6
    removes them and the counts become `43/43`, `36/36` and `34/34`;
  - `tests/unit/keys_bit_length.st`;
  - `tests/unit/keys_map_key_rule.st`.

**Interfaces:**
- Consumes: Tasks 7-9.
- Produces:
  - `PBKeys class >> orderKey: aValue` → a `PBOrderKey` (`rank`, `payload`). The payload for
    rank 3 is an exact Integer or Fraction (a float's exact value), a finite `Decimal` (kept as
    is: its exact value may be a power of ten too large to build; compared by `Decimal`'s exact
    comparison and hashed by its residue), or `#negInf`/`#posInf`. A NaN, or a list, map or
    tuple holding one, signals `PBValidationError`.
  - `PBOrderKey >> < other`, `= other`, `hash`.
  - `PBKeys class >> compare: a with: b` → -1, 0 or 1.
  - `PBKeys class >> isOrderable: aValue`.
  - `PBKeys class >> hashKey: aValue` → a signed int64 Integer. It is BLAKE2b-8 (`blake2b: 8`)
    over `feed(rank, payload)`, read as signed little-endian (FS "Hash keys").
  - `PBKeys class >> bitLength: anInteger` (the bits of the absolute value; never `highBit`
    of a negative).
  - `PBKeys class >> residue: anExactNumber`: modulo 2^61-1. An Integer is `n \\ P`; a
    Fraction or a Decimal goes through protoST's native numeric hash (CPython's, protoST R3,
    which takes powers modulo P with `raisedTo:modulo:`), the -1 → -2 case told apart by the
    hash of the magnitude. (Until Task 12's fix round it used a `modPow:exp:mod:` of its own.)
  - `PBKeys class >> exactToken: aValue` → a ByteArray: `PBCodec toWire:atomRef:` in token
    mode, then encoded.
  - `PBKeys class >> checkMapKeys: aPBFrozenDict`, the FS "Map keys" conflict rule, which
    signals `PBValidationError`. `PBCodec` calls it on encode, and on decode for format 4.
  - `PBFrozenDict` keys and lookups compare by map-key id (FS "Map keys"): the order key with
    every bool read as 0 or 1, as ProtoBase's decoded map (a Python dict) does, so `at: true`
    finds the key `1` (C-T10-3); a NaN by identity (a tuple holding one by its items'
    identity, as Python's tuple equality); a format-3 zone datetime by zone and wall clock.
  - Atom keys (fix round 1, review I1): every `PBAtom` key is its rank-14 order key, its oid,
    as ProtoBase's `map_key_ids` and `Atom.__eq__`. A stub's record is loaded to read it, so a
    decoded map holding references to two records of one oid is `PBCorruptionError`, and an
    atom's key never changes when it is saved. A `PBUnresolvedRef` (decoded without a resolver,
    its oid unknown) is a map key by its pointer only, a weaker rule than the format's. An
    atom whose oid is not assigned yet has no key: `orderKey:`, `hashKey:`, `isOrderable:` and
    map construction signal `PBNotSupportedError` until Task 15 assigns oids.
  - Added by the Task 7 review:
    - `checkMapKeys:` replaces the interim rule of `_PBItems` (same class and `=`) and keeps
      its linear-time duplicate check: keys are bucketed by order key or hash key, never
      compared pairwise on untrusted input.
    - It keeps Task 7's refusal of format-3 zone keys whose conflicts need offsets, with
      exactly Task 7's rule (design §4.3): `PBNotSupportedError` only for two keys equal under
      the order-key rule at every position except datetime positions, with a format-3
      datetime against an aware one within 24 h or a format-3 one of another zone within 48 h.
      Its order-key bucketing must refuse every such pair and only those, and replaces Task 7's
      coarse probe (numbers already fold there; every other item still compares by class and
      `=`); `codec_tagged.st` holds the cases.
    - It decodes format-3 NaN keys as distinct, and refuses them on write.
    - Once this task lands, remove `map-nan-keys-format3`, `map-decimal-nan-keys-format3`,
      `map-key-bool-and-int` and `map-key-equal-numbers` from Task 8's expected-differences
      list.

- [ ] **Step 1: failing tests.**
  - `keys_bit_length.st`: `0`→0, `-1`→1, `255`→8, `-128`→8, and `2^61-1`→61.
  - The feed lengths of FS: `0` is `00`, `255` is `ff 00`, `-1` is `ff`, `-128` is `80 ff`.
  - `keys_map_key_rule.st`: `{true→1, 1→2}` is refused (FS "Map keys": `1`, `1.0`,
    `Decimal("1.00")` and `true` conflict pairwise; vector `invalid/map-key-bool-and-int`);
    `{true→1, 2→2}` and `{false→1, true→2}` are accepted; `{1→a, 1.0→b}` is refused; NaN
    twice is refused.
  - The three conformance files compare against the manifest.
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run. Expected: PASS. These vectors gate every later change to `codec.st` and
  `keys.st`.
- [ ] **Step 5:** commit `Order keys, hash keys and exact tokens (vectors: order, hashes, tokens)`.

### Task 11: File storage, read side; database record walk

**Files:**
- Create: `src/protobase/store.st` (`PBFileStorage`, `PBSegmentReader`).
- Test:
  - `tests/conformance/database_records.st` (`EXPECT: database records N/N`);
  - `tests/conformance/invalid_atom.st` (the `atom` layer; it needs Task 12's required
    fields, so it is written here and expected to pass at the end of Task 12);
  - `tests/unit/store_open_refusals.st`.

**Interfaces:**
- Consumes: Task 9.
- Produces:
  - `PBFileStorage path: aString` creates the directory if needed. It refuses a directory
    holding `cluster/` with `PBNotSupportedError`.
  - `PBFileStorage storage:lockTimeout:` is not here; the lock timeout belongs to the space
    (Task 18).
  - `readRoot` → a `PBRootRecord`, or nil when there is no `space.root`.
  - `loadAt: aPointer expecting: aTag` → the decoded envelope. The segment header is checked
    once per segment (`PBSegmentHeader decode:`), and its `segment` must equal the UUID of the
    file name `<uuid-hex>.seg` (FS "Segment header": it MUST equal the UUID in the file name;
    a mismatch is `PBCorruptionError`). The reader is cached per segment UUID in an `Atom` over
    a `PBFrozenDict`.
  - `refTo:offset:tag:`, the resolver of Task 7, which answers
    `PBTypeRegistry unloadedAtomFor: tag at: pointer storage: self` (Task 9: a class's
    `unloadedAt:storage:`, or, for an unknown application name, a `PBOpaqueAtom` that keeps
    the name it was referenced by; `PBOpaqueAtom unloadedAt:storage:` alone is refused).
  - `recordsOfSegment: aUUID` → the `(offset, header, payload)` walk from offset 26, used by
    the runner.
  - `close`, after which every load signals `PBClosedError`.

- [ ] **Step 1: failing tests.**
  - `store_open_refusals.st` also holds a segment whose header UUID differs from its file
    name: loading from it is `PBCorruptionError`.
  - `database_records.st`: for every `database.records` entry, the record at `offset` has the
    listed `kind`, `size`, `tag`, `type`, `oid` and `state` (through `describeRaw:` or
    `describe:`). When `canonical` is true, re-encoding gives the same bytes.
  - `store_open_refusals.st`: a temp directory with `cluster/` is refused, and a `space.root`
    with a bad CRC is `PBCorruptionError`.
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run. Expected: PASS for `database_records.st` and the unit test.
- [ ] **Step 5:** commit `File storage read side: root, segments, lazy references`.

### Task 12: Read structures, roots, the read-only space API and the database dumps

**Files:**
- Create:
  - `src/protobase/avl.st`: `PBPosNode`, `PBKeyNode`, `PBCountedKeyNode`, `PBValueBox`; read
    and walk only (writes come in Task 14);
  - `src/protobase/collections.st`: `PBIndexSet`, `PBList`, `PBDictionary`,
    `PBHashDictionary`, `PBSet`, `PBCountedSet`, `PBRepeatedKeysDictionary`; read API only;
  - `src/protobase/records.st`: `PBObject`. `PBOpaqueAtom` already exists in
    `src/protobase/registry.st` (Task 9): extend it there (or with methods of `PBOpaqueAtom`
    in `records.st`), never define a second class;
  - `src/protobase/indexes.st`: `PBEqualityIndex`, `PBRangeIndex`, `PBVectorIndex`, decoded
    and kept, with `name`, `keySpec` and `hasMemberTokens`;
  - `src/protobase/roots.st`: `PBSpaceRoot`, `PBDatabaseRoot`;
  - `src/protobase/space.st`: `PBObjectSpace`, `PBDatabase`, `PBSnapshot` and
    `PBHistoryEntry`, read side only.
- Modify: `src/protobase/notation.st`, adding `describeObject:` and `describeDatabase:`.
- Test:
  - `tests/conformance/database_contents.st` (`EXPECT: database contents ok`);
  - `tests/conformance/legacy_database.st`;
  - `tests/conformance/polyglot_read.st`;
  - `tests/conformance/cluster.st`, which prints `SKIP:`-prefixed lines for each cluster
    item, then `cluster skipped visibly`, and exits 0;
    This runner also owns the invalid-vector layers `roots_log` and `message` (an acceptor
    log and cluster wire messages): the cluster is out of the prototype's scope (Spec §10.5:
    a space with `cluster/` is refused), so it prints one `SKIP: invalid <layer> <id>` line per
    manifest entry of those two layers, naming the id, and the Task 25 accounting check
    accepts exactly those lines as justified skips;
  - `tests/unit/read_cross_kind_keys.st` (Review Focus 1, on a Python-written space made by
    `tests/interop/py_make_keys_space.py`, run through the helper
    `tests/interop/_make_keys_space.sh`: the leading `_` makes the runner treat it as a helper,
    not a test, so there is no test file named `py_make_keys_space.sh`; without the venv the
    helper exits 77 and the test prints `SKIP:`);
  - `tests/unit/read_opaque_refusals.st`;
  - `tests/unit/read_history.st`.

**Interfaces:**
- Consumes: Tasks 9-11.
- Produces:
  - Every class registers with `PBTypeRegistry` under its alias, and declares `requiredFields`
    and `persistedFields`.
  - The read API of Spec §5.2 for each collection: `getAt:`, `getAt:default:`, `has:`,
    `keys`, `values`, `items`, `do:`, `keysAndValuesDo:`, `count`, `size`, `countOf:`,
    `indexNames`, `getIndex:`. `PBList >> getAt:` follows C15.
  - Node values that are refs to a `PBValueBox` are unboxed when read.
  - `PBObject`:
    - `at: aName` (absent: nil), `hasDefinedAttr:`, `attributeNames`;
    - `PBObject class >> typeName` is `'proto_db.core.dbobject.DBObject'`, and application
      subclasses override `typeName` and `typeAliases`;
    - loading a `PBObject` refuses (`PBCorruptionError`) a persisted attribute named like a
      behaviour name of DBObject, `with_` or `has_defined_attr` (FS "Attribute names"; vector
      `invalid/atom-reserved-name`, run by `invalid_atom.st`). The Task 9 envelope checks only
      the names every type refuses;
    - `PBObjectSpace registerAtomClass: aClass` → `PBTypeRegistry register:`.
  - `PBOpaqueAtom`: `typeName` (the name it was referenced by, also its `tag` of Task 9),
    `at:`, `attributeNames`. Any other message, including
    `doesNotUnderstand:`, and any collection use signal `PBNotSupportedError` naming the
    type.
  - `PBObjectSpace storage: aStorage` and `storage:lockTimeout:` (the default lockTimeout is
    30000).
  - `PBObjectSpace >> listDatabases` (sorted), `openDatabase:` (an absent name is
    `PBValidationError`), `close`.
  - `PBDatabase >> name`, `history` (`PBHistoryEntry`s, newest first, through `previous`) and
    `snapshotAt: aHistoryEntryOrSnapshot`.
  - `PBSnapshot`: `version`, `committedAt`, `rootNames`, `getRootObject:`, `mutableNames`,
    `getMutable:`. `PBHistoryEntry` has the same messages without `getRootObject:`.
  - A `DatabaseRoot` without `mutables` is `PBCorruptionError`.
  - `PBNotation class >> describeDatabase: aSnapshotOrTransaction` → the shape of
    `notation.describe_database` (`roots` sorted by name, `mutables`, `indexes`, `origin`).
  - `PBNotation class >> dumpSpace: aSpace to: aPath` writes JSON shaped like verify's
    `--out`, with `databases` and `opaque_types` filled.

- [ ] **Step 1: failing tests.**
  - `database_contents.st`: open `vectors/database` read-only (a copy in a temp directory,
    never the vendored files), with the conformance type registered: `ConformanceInvoice`
    (`typeName` `'conformance.Invoice'`, `typeAliases` `#('conformance.LegacyInvoice')`),
    which `_vectors.st` defines and registers since Task 9. Its single home moves to
    `tests/conformance/_model.st`, imported by `_vectors.st`, where it becomes a `PBObject`
    subclass; no runner registers a second class under those names. Compare `describeDatabase:` with `contents` (roots,
    mutables, indexes, origin).
  - `legacy_database.st` does the same on `vectors/legacy`. The format-3 `["zone", key]`
    datetimes are refused, as *expected entries listed in the runner* by root name. Index
    rebuild and misfiled detection print `SKIP-ITEM: ...` lines. The test ends
    `legacy contents ok, N expected refusals`.
  - `polyglot_read.st`: the `polyglot.st.Order` record reads as a `PBOpaqueAtom` with its
    fields; the old name `polyglot.st.SalesOrder` resolves through the declared alias; the
    ProtoBase record it references is readable.
  - `read_opaque_refusals.st`: `opaque setAt: 1 value: 2`, `opaque with: 'a' value: 1` and
    `opaque do: [...]` each signal `PBNotSupportedError` whose text names the type.
  - `read_cross_kind_keys.st`: `getAt: 1.0` and `getAt: (Decimal fromString: '1.00')` hit
    the key `1`; `getAt: true` misses; `10**16+1` and `1.0e16` are two keys. It SKIPs
    without the venv.
  - `read_history.st`: on the database vector, `history` sizes, versions descend, and
    `snapshotAt:` of the oldest entry answers that version's roots.
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement, reading FS "Atom types and their persisted fields" for each
  class. For each class, read its Python counterpart at the tag before choosing the iteration
  order: Set and HashDictionary iterate in tree order, then bucket order.
- [ ] **Step 4:** run `tests/run_tests.sh tests/conformance tests/unit`. Expected: all PASS,
  including `invalid_atom.st` from Task 11.
  Task 11 lists the 9 `invalid` entries `atom-*` (stage `refusal`, `PBNotSupportedError`,
  removedBy `Task 12`) in `tests/conformance/_expected_differences.st`, because the built-in
  types had no class: remove all 9, and set the EXPECT line of
  `tests/conformance/invalid_atom.st` to `invalid atom-layer 9/9`. VectorRun fails any listed
  entry that now matches, so they cannot stay.
- [ ] **Step 5:** commit `Read path: AVL nodes, collections, records, opaque atoms, indexes, roots, history`.

### Task 13: Transaction read side, and the Python → protoST round trip (Spec §10.2)

**Files:**
- Create: `src/protobase/transactions.st`, with `PBTransaction` (read side) and the
  `get:` side of `PBMutableObject`.
- Create: `examples/erp/erp_model.py` (`demo.erp.Invoice`, `demo.erp.Customer`,
  `demo.erp.AuditNote`; the last is Python-only) and `examples/erp/erp_model.st` (`Invoice`,
  `Customer`, with Spec §4.5 accessors and `isPaid`).
- Create: `tests/interop/py_write_space.py <dir>` (Spec §10.2's shapes: every non-indexed
  collection, a `DBObject`, `demo.erp.Invoice`, a mutable cell, three versions, an indexed
  collection, an AuditNote), `tests/interop/py_verify.py` (C10) and
  `tests/interop/compare_dumps.py` (C11).
- Test:
  - `tests/interop/py_to_st.sh` with `tests/interop/_st_dump.st`;
  - `tests/unit/tx_read_set.st`;
  - `tests/unit/tx_states.st` (read side: `abort`, then any message is `PBUserError`);
  - `tests/unit/tx_atom_depth.st`, `tests/unit/tx_atom_map_keys.st`, and
    `tests/interop/st_deep_to_py.sh` with `tests/interop/_st_deep_space.st` and
    `tests/interop/py_read_deep.py` (the depth bullet below).

**Interfaces:**
- Consumes: Task 12.
- Produces:
  - `PBDatabase >> newTransaction`. The transaction snapshots the root record, the
    `SpaceRoot` and the `DatabaseRoot` once.
  - `PBTransaction >> getRootObject:`. It answers its own write first. Otherwise it records
    `(name → token)` on the first read, where the token is the atom's pointer, the exact token
    bytes of a plain value, or `#absent`. Also `rootNames` (records nothing), `getMutable:`
    (records in `mreads`), `mutableNames`, `abort`, `isActive`.
  - The bookkeeping is one immutable `PBTxState` record in an `Atom`, updated with `swap:`
    (Spec §7.1). It holds `reads`, `writes`, `replaced`, `mreads`, `mwrites`, `mexpected`
    and `state` (`#active`, `#committing`, `#committed`, `#aborted`).
  - `PBTransaction >> readSet` and `mutableReadSet` are test-visible accessors that answer
    `PBFrozenDict` copies.
  - `PBMutableObject >> get: aTransaction` → `aTransaction getMutable: name`.

- [ ] **Step 1: failing tests.**
  - `py_to_st.sh`:
    1. `py_write_space.py $TMP` writes the space.
    2. `py_verify.py $TMP --out py.json` exits 0.
    3. `_st_dump.st $TMP st.json` (which imports `erp_model.st`) writes protoST's dump.
    4. `compare_dumps.py py.json st.json` exits 0.

    It SKIPs without the venv.
  - `tx_states.st`: after `abort`, `getRootObject:`, `rootNames` and `abort` each signal
    `PBUserError`.
  - Atom depth (added by the Task 7 re-review): ProtoBase packs an attribute value inside the
    atom payload `{"t", "oid", "s": {name: value}}` at depth 2, so the effective limit for a
    stored attribute value is 509 msgpack containers. The atom writer passes the enclosing
    depth 2 to the codec (`PBCodec canonical:enclosingDepth:` or
    `toWire:atomRef:enclosingDepth:`). `tx_atom_depth.st` writes an attribute of 509 nested
    lists (accepted, and read back by ProtoBase in the interop run) and one of 510 (refused
    with `PBValidationError` before any byte is written, never protoST's raw msgpack
    `Error`). Found in Task 13: ProtoBase's reader decodes nested lists recursively (two
    Python frames per level), so under Python's default recursion limit it raises
    `RecursionError` from about 333 nested lists, and its writer from about 497.
    `st_deep_to_py.sh` therefore reads the 509-deep record with a raised recursion limit
    (`py_read_deep.py`), and prints the outcome at the default limit; the limit is
    ProtoBase's, reported to the maintainer, and protoBaseST keeps the format's 509.
  - `tx_read_set.st`, on a copy of the database vector: reading two roots and an absent name
    records three entries; reading again does not change them; `rootNames` records nothing.
  - Atom map keys through the real resolver (from Task 10 fix round 1, which must be kept):
    a map whose keys are references is decoded with the storage's resolver, and its stub keys
    are identified by their oids (`PBKeys _keyId:mode:` loads them); a state holding a map with
    references to two records of one oid is `PBCorruptionError`. `tx_atom_map_keys.st` checks
    it on a space with two versions of one atom.
  - Lookups by an unsaved atom (review note N1 of Task 10): a lookup (`at:ifAbsent:`,
    `includesKey:`, `getAt:`, `has:`, `countOf:`) whose probe is, or holds in a tuple, an atom
    with no oid and no pointer answers absent, as ProtoBase does (it assigns a fresh oid and
    misses), never `PBNotSupportedError`; the tuple's other items must still be keys.
    `orderKey:` and `hashKey:` of such an atom keep signalling `PBNotSupportedError` until
    Task 15 assigns oids. `tx_atom_map_keys.st` checks a `PBFrozenDict` and every collection.
  - A record that needs itself to be decoded (review note N3 of Task 10): a map key that
    refers back to the record being loaded, directly or through another record keyed by it.
    ProtoBase recurses until Python's `RecursionError`; protoBaseST signals
    `PBCorruptionError` naming the pointer (the loads in progress on the call stack answer a
    resumable `_PBLoadInProgress` signal for their own pointer), and the transaction stays
    usable. `tx_atom_map_keys.st` checks a self-keyed record and two records keyed by each
    other.
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run everything. Expected: PASS. **Gate of week 2** (Spec §11): `order`,
  `hashes`, `exact_tokens`, `atom_*`, `database`, `legacy_database`, `polyglot_database`
  read, and §10.2.
- [ ] **Step 5:** commit `Transaction read side; Python-written space read and dumped identically (10.2)`.

---

## Phase C: protoBaseST writer and transactions (week 3)

Phase C needs Task 2's build: oids and segment names come from `ByteArray randomBytes:`, and
`committedAt` from `DateTime nowUTC`. From here on, `PROTOST` is the protoST branch build
(0.10.0). Tests that need it SKIP visibly on 0.9.0.

### Task 14: Persistent AVL writes and value boxing

**Files:**
- Modify: `src/protobase/avl.st`.
- Test:
  - `tests/unit/avl_pos_random.st`;
  - `tests/unit/avl_key_random.st`;
  - `tests/unit/avl_counted_weight.st`;
  - `tests/unit/avl_valuebox_threshold.st` (Review Focus 2).

**Interfaces:**
- Consumes: Task 12's node classes, Task 10's `PBKeys compare:with:`.
- Produces (class-side functions over a root node, or nil for the empty tree; every function
  answers a new root and never changes a node):
  - `PBAvl posAt: root index: i`, `posInsert: root at: i value: v`, `posSet: root at: i value: v`,
    `posRemove: root at: i`, `posAppend: root value: v`;
  - `PBAvl keyAt: root key: k` (a node or nil), `keyPut: root key: k value: v nodeClass: aClass`,
    `keyRemove: root key: k`;
  - `PBAvl do: aBlock over: root` (in order);
  - `PBAvl check: root` (the FS invariants: height, count, balance, key order, `weight`, and
    one node class per tree), signalling `PBCorruptionError` on a violation;
  - a new node gets no oid until saved (Spec §8.1); `PBAtom >> oid` of an unsaved node is
    nil until the publisher assigns it.
  - Boxing: a node value that is a `String` of 256 code points or more, or a `ByteArray` of
    256 bytes or more, is stored as a `PBValueBox`, and reads unbox it. Keys and bucket
    values are never boxed.
  - A node added to a non-empty tree takes the root's node class (FS "Node classes").

- [ ] **Step 1: failing tests.** Seeded sequences use a fixed seed through `Random seed: 20261110`.
  The test prints the seed on failure.
  - `avl_pos_random.st` runs 2000 random inserts, sets and removes against an `OrderedCollection`
    model, calling `check:` after each, and prints `ok 2000`.
  - `avl_key_random.st` does the same against a model kept sorted with `PBKeys compare:with:`.
  - `avl_counted_weight.st` checks `weight` after inserts and removes.
  - `avl_valuebox_threshold.st`: 255 code points of `'é'` (510 bytes) are not boxed; 256 are.
    The same for ByteArrays of 255 and 256.
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement path-copying insert and remove with the four rotations, and
  successor removal.
- [ ] **Step 4:** run. Expected: PASS.
- [ ] **Step 5:** commit `AVL: persistent positional and keyed trees, counted weights, value boxes`.

### Task 15: `PBList`, `PBDictionary` and record writes; oids; registering application classes

**Files:**
- Modify: `src/protobase/collections.st` (`PBList` and `PBDictionary` mutators),
  `src/protobase/records.st` (`PBObject` construction and `with:value:`) and
  `src/protobase/framing.st` (`PBAtom class >> newOid`).
- Test:
  - `tests/unit/list_ops.st`;
  - `tests/unit/list_positions.st` (Review Focus 5, with expected results recorded from a
    Python run by `tests/interop/py_list_positions.py` and pasted as literals);
  - `tests/unit/dict_ops.st`;
  - `tests/unit/object_with.st`;
  - `tests/unit/indexed_refusal.st`;
  - `tests/unit/discarded_result.st`.

**Interfaces:**
- Consumes: Task 14.
- Produces:
  - `PBAtom class >> newOid` → a 16-byte UUID4 ByteArray (`UUID new bytes`), as ProtoBase's
    `uuid.uuid4()`. A record draws its oid at construction. A node or collection draws it
    when saved.
  - Atom keys (from Task 10 fix round 1, which must be kept): an atom's map-key and order-key
    identity is its oid and never changes when it is saved. ProtoBase assigns a new atom's oid
    on first need (`==`, `hash`, a key, or `_save`; D21), so a node or collection used as a key
    before it is saved draws its oid then, once, through the atom's memo cell; the
    `PBNotSupportedError` that Task 10 signals for an atom without an oid is removed.
    `atom_keys_oid.st`: an unsaved atom used as a map key keeps its key after the save; the
    writer refuses `{atomV1 -> a, atomV2 -> b}` and `{saved A -> a, twin of A -> b}` (one oid,
    `PBValidationError`), as ProtoBase's reader would refuse those bytes.
  - `PBList new`, plus the mutators of Spec §5.2. Each answers a new `PBList` and leaves the
    receiver unchanged: `setAt:value:`, `insertAt:value:`, `removeAt:`, `appendFirst:`,
    `appendLast:`, `extend:`, `sliceFrom:to:`, `head:`, `tail:`. Positions are zero-based
    and follow C15.
  - Values pass through `PBCodec canonical:` at once.
  - `PBDictionary new`, `setAt:value:`, `removeAt:` (an absent key is a no-op, as
    ProtoBase), each answering a new version. The operation log comes in Task 16.
  - `PBObject withAll: anArrayOfAssociations`; `Invoice withAll:` for subclasses;
    `with: aName value: v`; `withAll:` on an instance. Each answers a new record with a new
    oid. Attribute names are checked as in FS "Atom records".
  - Any mutator of a collection whose `PBIndexSet` is non-empty signals
    `PBNotSupportedError` naming the index (Spec §7.4).
  - Class comments of `PBList`, `PBDictionary`, `PBSet` and `PBCountedSet` state, in their
    first sentence, "Every message answers a new version; the receiver never changes."
    The `PBList` comment states "Positions are zero-based, as in ProtoBase." Rulings 2 and 3.

- [ ] **Step 1: failing tests.**
  - `list_positions.st` checks `getAt: -1`, `getAt: count` (`PBValidationError`),
    `insertAt: count value:` (appends), `insertAt: count + 1 value:` (refused) and
    `getAt: 'a'` (refused).
  - `discarded_result.st` documents the Pharo clash: after `l appendLast: 3.` and
    `s add: 3.` with the results discarded, `l size` and `s size` are unchanged. It prints
    `unchanged unchanged`.
  - `indexed_refusal.st`, on a copy of the database vector: `setAt:value:` on the indexed
    root signals `PBNotSupportedError` whose text names the index.
  - `dict_ops.st` also checks that `setAt: Float nan value: 1` signals `PBValidationError`
    (a NaN key, Spec §10.5).
  - `object_with.st` checks that a new oid differs from the old, that the old record is
    unchanged, and that `with: '_x' value: 1` is refused.
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run. Expected: PASS.
- [ ] **Step 5:** commit `Writes: List, Dictionary and records as new versions; oids from OS random bytes`.

### Task 16: Operation logs, net-effect rebase and consumed marks; `PBHashDictionary` and `PBSet` writes

**Files:**
- Modify: `src/protobase/collections.st`.
- Test:
  - `tests/unit/oplog_complete.st`;
  - `tests/unit/rebase_dictionary.st`;
  - `tests/unit/rebase_set.st`;
  - `tests/unit/rebase_hashdict.st`;
  - `tests/unit/consumed_d33.st`;
  - `tests/unit/hashdict_set_ops.st`.
  - `tests/conformance/invalid_log.st`: every invalid vector of the `log` layer
    (`log-version-3`, `log-kind-mismatch`, `log-mid-corruption`) is refused by the operation-log
    reader with the listed class (`EXPECT: invalid log-layer N/N`, N computed from the
    manifest).

**Interfaces:**
- Consumes: Task 15.
- Produces:
  - `PBHashDictionary` (`setAt:value:`, `removeAt:`) and `PBSet` (`add:`, `remove:`,
    `union:`, `intersection:`, `difference:`), with buckets as FS "Collections" describes.
  - Every `PBDictionary`, `PBHashDictionary` and `PBSet` version carries:
    - `opLog`: a `PBFrozenList` of `PBTuple`s `('set' k v)`, `('remove' k)` and
      `('add' e)`, the names ProtoBase uses (read `collections/*.py` for the exact op names
      and arities);
    - `logComplete`: true for a version built by `new` and derived only by logged mutators;
      false when loaded, bulk-built or rebased;
    - `consumed`: an `Atom` holding false.

    A derived version's `logComplete` is the parent's `logComplete and: [parent consumed value not]`,
    read at derivation time (D33, Spec §7.2).
  - `rebaseOnto: current` → the net effect of the log replayed onto `current` through the
    public mutators. The net effect is the last intent per key, by order key, in order of
    last occurrence. A `current` with indexes signals `PBNotSupportedError`.
  - `isMergeable`, which answers `logComplete`.
  - `markConsumed`, which sets `consumed` to true; the publisher calls it.

- [ ] **Step 1: failing tests.**
  - `rebase_dictionary.st`: A is built empty with `setAt: 'a' value: 1`; current holds
    `'b' → 2`; the rebase holds both.
  - Set then remove of one key nets to remove.
  - `rebase_set.st`: add then remove of one element nets to remove, and replays as a no-op on
    a current without it.
  - `consumed_d33.st`: after `v markConsumed`, `(v setAt: 'c' value: 3) isMergeable` is
    false, while a sibling derived before the mark keeps true.
  - `rebase_hashdict.st` mirrors the dictionary cases.
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement, after reading `ConcurrentOptimized` and `rebase_onto` in
  `proto_db/collections/base.py`, `dictionaries.py`, `hash_dictionaries.py` and `sets.py` at
  the tag.
- [ ] **Step 4:** run. Expected: PASS.
- [ ] **Step 5:** commit `Operation logs, net-effect rebase and D33 consumed marks; HashDictionary and Set writes`.

*Cut-order item 2 (Spec §11):* if week 3 slips, drop the `PBHashDictionary` and `PBSet`
**writes** of this task together with their merge, and keep the `PBDictionary` log. Record the
cut in `docs/not-done.md`. A blind write never ships without its merge.

### Task 17: File storage, write side: owned segment, saving atoms, publishing the root

**Files:**
- Modify: `src/protobase/store.st`, adding `PBSegmentWriter` and the publish operations of
  `PBFileStorage`.
- Test:
  - `tests/unit/store_write_read.st`;
  - `tests/unit/store_publish_epoch.st`;
  - `tests/unit/store_cluster_refusal.st` (Spec §10.5);
  - `tests/unit/store_segment_exclusive.st`.

**Interfaces:**
- Consumes: Tasks 9, 11, 14, 15.
- Produces (used only by the publisher of Task 18):
  - `PBFileStorage >> save: anAtom` → a `PBAtomPointer`. It saves unsaved children first, in
    depth-first order, assigns node and collection oids, writes the envelope with
    `persistedFields` order, and records the pointer in the atom.
    - The first save creates `<uuid hex>.seg` with `#create #exclusive` and a UUID4 name,
      writes the header, `sync`s it, and `FileSystem syncDirectory:` once.
    - Later saves `append:`.
  - `PBFileStorage >> flushSegment`, which `sync`s.
  - `PBFileStorage >> tryLockRoot` → a Boolean, from `tryLock` on `space.lock` opened
    `#(#read #write #create)`; and `unlockRoot`, best effort, which logs to stderr and never
    raises.
  - `PBFileStorage >> replaceRoot: aPBRootRecord`. It refuses when `cluster/` exists or the
    current SpaceRoot has a non-nil `cluster_term`. It then writes `space.root.tmp`, `sync`s
    it, runs `FileSystem replace:with:` and `syncDirectory:`.
  - `PBFileStorage >> isCluster`.
  - `PBFileStorage >> newSegmentId` → a `UUID` (`UUID new`). It is overridable only so that a
    test subclass can inject a name.

- [ ] **Step 1: failing tests.**
  - `store_write_read.st`: save a `PBList` of 300 elements and a `PBObject`, publish a root
    pointing at a hand-built SpaceRoot, reopen with a fresh storage, and read it back equal.
    `PBAvl check:` passes on the reloaded tree.
  - `store_publish_epoch.st`: two publishes give epochs 1 and 2.
  - `store_cluster_refusal.st`: `cluster/` created after open makes `replaceRoot:` signal
    `PBNotSupportedError`.
  - `store_segment_exclusive.st`: a pre-existing file with the drawn name makes creation fail
    loudly. Inject the name through a test subclass that overrides `newSegmentId`.
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run. Expected: PASS.
- [ ] **Step 5:** commit `File storage write side: owned segment, atom saving, root publication`.

### Task 18: The publisher actor and the write side of transactions

**Files:**
- Create: `src/protobase/publisher.st` (`PBPublisher`, used through `asActor`).
- Modify:
  - `src/protobase/transactions.st` (the write side, commit, `newTransactionDo:`);
  - `src/protobase/space.st` (`newDatabase:` through the publisher, the last-known root
    `Atom`);
  - `PBMutableObject >> set:value:`.
- Test:
  - `tests/unit/tx_commit_basic.st`;
  - `tests/unit/tx_conflict_read.st`;
  - `tests/unit/tx_blind_merge.st`;
  - `tests/unit/tx_replace.st`;
  - `tests/unit/tx_mutables.st`;
  - `tests/unit/tx_after_end.st` (Review Focus 3);
  - `tests/unit/tx_refusals.st` (`__` root name; a `Symbol` value);
  - `tests/unit/tx_outcome.st` (C17);
  - `tests/unit/tx_new_database.st`.

**Interfaces:**
- Consumes: Tasks 13, 16, 17; `DateTime nowUTC`.
- Produces (Spec §5.2 and §7):
  - `PBObjectSpace >> newDatabase: aName`. It commits version 0 with empty `objects` and
    `mutables`, `origin := ByteArray randomBytes: 16`, and `committedAt` now. An existing
    name is `PBValidationError`.
  - `PBTransaction` write side:
    - `setRootObject:value:` and `setRootObject:value:replace:`; a name starting with `__` is
      `PBValidationError`;
    - `removeRootObject:`;
    - `newMutable:value:`, `setMutable:value:`, `removeMutable:`, with the D35 rules of
      Spec §7.1;
    - `newList`, `newDictionary`, `newHashDictionary`, `newSet`, `newCountedSet`,
      `newObject:`;
    - `commit` (C16 for an empty commit), `abort`.

    After the end, every message signals `PBUserError`. A failed commit leaves the
    transaction aborted.
  - `PBDatabase >> newTransactionDo: aBlock`. It commits when the block ends, aborts if the
    block raises, re-signals the exception, and does not retry.
  - `PBMutableObject >> set: aTransaction value: v`.
  - `PBPublisher >> commit: aTransaction`, one actor per `PBObjectSpace`, which answers a
    Future. It runs the steps of Spec §7.3 in order:
    1. lock, retried with `(Future after: d) wait` from 1 ms, doubling, capped at 50 ms,
       until `lockTimeout`, then `PBTimeoutError`;
    2. read the root;
    3. validate (`PBConflictError`);
    4. build with merges (`_merged`, Task 16's `rebaseOnto:`, last writer wins otherwise);
    5. save and `flushSegment`;
    6. `replaceRoot:`;
    7. `markConsumed` on every written collection, and update the last-known root;
    8. on a publish failure, re-read the root. If it is our own, the commit succeeded. If it
       is provably not our own, re-signal the original error. Otherwise signal
       `PBOutcomeUnknownError`.

    `committedAt` is `max(now, previous committedAt)` in UTC (`ZoneOffset utc`).

- [ ] **Step 1: failing tests**, each in one process and step by step.
  - `tx_conflict_read.st`: A reads `'x'` and B reads `'x'`; B writes and commits; A writes
    and commits, which signals `PBConflictError`; the final value is B's. A second case: B
    replaces the integer `1` with the float `1.0` (equal keys, different tokens), and A's
    commit still conflicts (Spec §7.1, tokens).
  - `tx_blind_merge.st`: A and B each `setRootObject: 'tags'` a `newDictionary` with
    different keys, unread; both commit, and both keys are present.
  - `tx_replace.st`: the same with `replace: true` on the later commit, so only its key
    remains.
  - `tx_mutables.st` checks each mutable-cell row of Spec §10.4.
  - `tx_outcome.st`, with two test subclasses of `PBFileStorage`:
    - one fails after the rename, and the commit is reported successful;
    - one fails before the rename, and the original error is re-signalled with no new
      version.

    A third subclass also fails the re-read, and gives `PBOutcomeUnknownError`.
  - `tx_after_end.st`: `commit` twice, `getRootObject:` after `abort`, `commit` after a
    failed commit, each `PBUserError`; an empty commit leaves `history size` unchanged.
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement, after reading `Transaction._commit`, `_build_root`, `_merged`,
  `_check_mutables` and `_commit_root` at the tag.
- [ ] **Step 4:** run. Expected: PASS.
- [ ] **Step 5:** commit `Transactions write side and the publisher actor: validation, merge, publish, outcome`.

### Task 19: `run:` with retries and backoff

**Files:**
- Modify: `src/protobase/space.st` (`PBDatabase >> run:`, `run:retries:`,
  `run:retries:backoff:`, `PBDatabase class >> backoffFor:low:high:random:`).
- Test: `tests/unit/run_retries.st`, `tests/unit/run_backoff_bounds.st`,
  `tests/unit/run_no_retry.st`.

**Interfaces:**
- Consumes: Task 18.
- Produces:
  - `run: aBlock` is `run: aBlock retries: 10 backoff: #(1 200)`, and answers the block's
    value.
  - On `PBConflictError` it aborts and waits `(Future after: d) wait`, with
    `d = (min(high, low * 2^attempt) * (0.5 + random / 2))` rounded to a SmallInteger
    millisecond count. It then retries with a fresh transaction.
  - Any other error aborts and propagates. `PBOutcomeUnknownError` is never retried.
  - After the last retry the conflict is re-signalled.

- [ ] **Step 1: failing tests.**
  - `run_retries.st`: the block itself makes a nested competing commit on the attempts listed
    in a script-held `Atom` (attempts 1 and 2), so attempt 3 succeeds. Assert 3 attempts and
    the final value. With `retries: 1`, it ends in `PBConflictError` after 2 attempts.
  - `run_backoff_bounds.st`: `backoffFor:` with `Random seed: 7` for attempts 0-10 lies
    within `[d/2, d]`, and never above 200.
  - `run_no_retry.st`: an `Error` raised in the block propagates after exactly 1 attempt.
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run. Expected: PASS.
- [ ] **Step 5:** commit `Database run: with ProtoBase's bounded exponential backoff`.

### Task 20: protoST → Python round trip, polyglot byte-for-byte check, and the lock test

**Files:**
- Create:
  - `tests/interop/st_to_py.sh` with `tests/interop/_st_write_space.st`, which writes the
    shapes of §10.2 through protoBaseST, plus Review Focus 2 and 4 values;
  - `tests/interop/st_random_ops.sh` with `_st_random_ops.st` (Spec §10.6: seeded random
    operations on every writable collection over 20 commits, `PBAvl check:` after each, and
    `verify` at the end);
  - `tests/conformance/polyglot_rewrite.st`;
  - `tests/interop/lock_timeout.sh` with `tests/interop/hold_lock.py` and `_st_commit_once.st`
    (C13).

**Interfaces:**
- Consumes: Tasks 12-19.

- [ ] **Step 1: write the tests.**
  - `st_to_py.sh`:
    1. `_st_write_space.st` writes `$TMP` and dumps `st.json`.
    2. `py_verify.py $TMP --out py.json` exits **0**.
    3. `compare_dumps.py` exits 0.
    4. A Python reader asserts the integer-boundary keys and the boxed strings.
  - `polyglot_rewrite.st`, on a copy of `vectors/polyglot`: change the record that references
    the opaque atom and commit. The opaque record's bytes at its original pointer are
    unchanged, the new version references the same pointer, and no new record of type
    `polyglot.st.Order` exists in the new segment. Then run `py_verify.py` on the copy. It
    SKIPs without the venv.
  - `lock_timeout.sh`: `hold_lock.py` takes the lock, prints `locked`, runs
    `protost _st_commit_once.st $TMP 50`, and expects its output to end with
    `PBTimeoutError`. It then releases, runs the script again with 30000, and expects
    `committed`.
- [ ] **Step 2:** run `tests/run_tests.sh tests/interop tests/conformance`. Expected: PASS.
  A failure is a bug in Tasks 12-19: fix it there, and never weaken the test.
- [ ] **Step 3:** commit `Round trip protoST → Python (10.3), random structures (10.6), polyglot rewrite, lock timeout (10.7)`.

### Task 21: Concurrency table, the same outcomes as ProtoBase (Spec §10.4)

**Files:**
- Create:
  - `tests/interop/concurrency_cases.json`, one entry per row of Spec §10.4 with
    `{id, setup, a, b, expected}`. The A and B operations are written in a small neutral
    vocabulary: `read root`, `set root k v`, `blind dict set root k v`, `replace`,
    `list set`, `set add` and `set remove`, `new mutable`, `set mutable`, `remove mutable`,
    `reuse committed`;
  - `tests/interop/py_case.py`, which runs one side of a case in Python, or both sides alone
    for the reference outcome;
  - `tests/interop/_st_case.st`, which runs one side in protoST;
  - `tests/interop/concurrency.sh`;
  - `tests/unit/concurrency_actors.st`, the same table with two protoST actors driven step
    by step.

**Interfaces:**
- Consumes: everything above. Ordering follows C12.

- [ ] **Step 1: write the tests.** For each case:
  1. **Reference.** `py_case.py both` runs A and B in Python (start A, start B, commit B,
     commit A) and prints the outcome: `A=<committed|PBConflictError|...> B=...` plus the
     final dump of the touched roots.
  2. **protoST as A.** `_st_case.st` starts A, runs `py_case.py b` as a subprocess (start B,
     commit B), then commits A.
  3. **Python as A.** `py_case.py a` starts A, runs `protost _st_case.st b`, then commits A.
  4. The three outcome lines are identical.

  Exception: the indexed-root case. Its expected protoST result is the documented
  `PBNotSupportedError` while ProtoBase merges. The script asserts exactly that difference
  and prints it. `concurrency_actors.st` asserts the reference outcomes recorded in the JSON.
- [ ] **Step 2:** run. Expected: PASS for all 13 rows.
- [ ] **Step 3:** commit `Concurrency: ProtoBase's outcomes across languages and actors (10.4)`.

### Task 22 (stretch, cut first): `PBCountedSet` writes and the D26 merge

**Files:**
- Modify: `src/protobase/collections.st`.
- Test: `tests/unit/counted_set_ops.st`, `tests/unit/rebase_counted_set.st`, and a new row
  `counted set blind adds` in `tests/interop/concurrency_cases.json`.

**Interfaces:**
- Produces:
  - `PBCountedSet` `add:`, `remove:` (one occurrence; an absent element is a no-op) and
    `countOf:`, with `total_count` kept;
  - log entries `('transform' e removes adds)`;
  - net effect per element `c → max(c - removes, 0) + adds`.

- [ ] **Step 1:** failing tests: the composed transform of add, add, remove onto a current
  count of 5 gives 6; removes below zero clamp at 0 before the adds.
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement, after reading `CountedSet` in `sets.py` at the tag.
- [ ] **Step 4:** run, with the concurrency row. Expected: PASS.
- [ ] **Step 5:** commit `CountedSet writes with the D26 counter-transform merge`.

If this task is cut, `docs/not-done.md` says so, and any `PBCountedSet` mutator signals
`PBNotSupportedError` naming the class, so it is never a silent replace.

### Task 23: ERP demo, both languages, run as a test (Spec §10.8)

**Files:**
- Create in `examples/erp/`:
  - `1_create.py` (customers and invoices);
  - `2_payments.st`: payments as new versions with `with:value:`, and a customer renamed
    through its `PBMutableObject`;
  - `3_tag.st`, which starts a transaction, runs `3_tag_peer.py` (C12), and commits; both
    are blind dictionary writes, and both tags survive;
  - `4_report.st` and `4_report.py`, the as-of report for three moments (C19), using the
    `asOf` helper of Spec §6.5;
  - `run_demo.sh`, which runs the steps in order on a fresh temp directory and diffs the two
    reports;
  - `expected_report.txt`;
  - `README.md`.
- Test: `examples/erp/run_demo.sh` is picked up by `tests/run_tests.sh`.

**Interfaces:**
- Consumes: `erp_model.st` and `erp_model.py` (Task 13), and everything else.

- [ ] **Step 1:** write `expected_report.txt` from the scenario: tens of records and three
  moments. Write the scripts.
- [ ] **Step 2:** run `examples/erp/run_demo.sh`. Expected: both reports equal
  `expected_report.txt`, and the script prints `demo ok`.
- [ ] **Step 3:** from a clean clone (`git clone` of the local repo into a temp directory,
  then `setup_venv.sh` and the runner), run the demo again. Expected: `demo ok`.
- [ ] **Step 4:** commit `ERP demo: Python and protoST on one directory (10.8)`.

### Task 24: protoBaseST documentation

**Files:**
- Modify: `README.md`, with:
  - what it is (Spec §1 wording, "in the tradition GemStone opened");
  - status (a proposal);
  - a quick start;
  - the API mapping table of Spec §5;
  - **prominent boxes** for "Every collection message answers a new version" (with the three
    Pharo clashes of Spec §5.3, ruling 2) and "`PBList` positions are zero-based" (ruling 3);
  - how to run the tests.
- Create:
  - `docs/tutorial.md`, following Spec §6 with runnable snippets checked by
    `tests/docs/tutorial_snippets.st`;
  - `docs/reference.md`, every public class and message, grouped by Spec §5.1;
  - `docs/deviations.md`, every refusal and divergence (C7, the indexed-merge refusal, the
    opaque rules, Symbols, IANA zones, cut items);
  - `docs/not-done.md`, the "what is not done" slide text from Spec §2's non-goals plus any
    cut;
  - `docs/decisions.md`, the planner's calls C1-C19 and every call made during execution.
- Modify: `CHANGELOG.md` (`0.1.0`).
- Test: `tests/docs/tutorial_snippets.st`.

- [ ] **Step 1:** write `tutorial_snippets.st` from the tutorial's code blocks. Run it.
  Expected: FAIL until the tutorial and the code agree.
- [ ] **Step 2:** write the docs, then run the snippets. Expected: PASS.
- [ ] **Step 3:** commit `Docs: README with the API mapping, tutorial, reference, deviations, not-done`.

### Task 25: Final verification

- [ ] **Step 1 [BUILD-GATED]:** in protoIO, run a clean build, `ctest`, and the TSan labels.
  Expected: PASS.
- [ ] **Step 2 [BUILD-GATED]:** in protoST, run a clean build, `ldd`, `ctest -j1` twice and
  `ctest -L tsan`. Expected: PASS. List every SKIP; none may come from the new tests.
- [ ] **Step 3:** in protoBaseST, from a clean clone with the venv, run `tests/run_tests.sh`
  twice. Expected: `failed 0, skipped 0` both times.
- [ ] **Step 3b (all-vectors accounting, added by the Task 8 review):**
  `tests/conformance/accounting.st` walks every id of every manifest section (`values`,
  `values_*`, `invalid`, `order`, `hashes`, `exact_tokens`, `atom_*`, `framing`, `database`,
  `legacy_database`, `polyglot_database`, `cluster`) and fails unless each one is run by some
  runner, listed as an expected difference, or listed as a justified `SKIP:` line of
  `cluster.st` (`roots_log` and `message` layers, the cluster section). The runners record the
  ids they ran; an id that no runner names is a FAIL, so a vector can never be silently
  unrun.
- [ ] **Step 4:** run a whole-branch review per repository with superpowers:requesting-code-review,
  and fix every finding, cheap "can stay" items included (maintainer rule). Then re-run Steps
  1-3.
- [ ] **Step 5:** write `tasks/protobasest-prototype-report-<date>.md` in the workspace. It
  records the gates passed, the cuts, the protoST defects found (with their K-numbers), and
  what remains unproven.

### Task 26: Merge and publish (at the very end only)

Run this task only after Task 25 passes. The maintainer's rule is "mergear y publicar al
final".

- [ ] **Step 1: protoIO (first: protoST's CI needs its tag).**
  - Date the CHANGELOG section `0.5.0 - <date>` (rulings R1, R10).
  - Merge `feat/random-clock` into `main`, tag `v0.5.0`, push, and create the GitHub
    release.
  - Put the main protoIO checkout on that commit. Only then re-configure the main protoST
    `build_release`: from 0.10.0 protoST refuses a 0.4.x sibling at configure time.
- [ ] **Step 2: protoST.** Do not push the protoST branch before protoIO's `v0.5.0` tag
  exists: both CI workflows build protoIO at a pinned tag, and the 0.5.0 floor refuses the
  current pin `v0.4.0`, so every job would fail at configure time.
  - Move **both** protoIO pins to `v0.5.0`, with the comments above them:
    `PROTOIO_REF` in `.github/workflows/ci.yml` (line 88, comment lines 82-87) and in
    `.github/workflows/cross-platform.yml` (line 29, comment lines 27-28). Date the
    CHANGELOG section `0.10.0 - <date>`.
  - Push `feat/protobase-support` (which holds `feat/random-clock`, merged locally) and open a
    PR from it into protoST `main`. Wait for CI to pass on Linux, macOS and Windows.
  - Merge it into `main`, tag `v0.10.0`, and build the deb with the recipe in
    `project_protoio030_protost090_binary_storage` (docker `pc-deb-build:24.04 --dns 8.8.8.8`,
    protoIO at the tag as a sibling, `-DPROTOCORE_REQUIRE_PACKAGE=ON`, `cpack -G DEB`).
  - Create the GitHub release with the deb.
- [ ] **Step 3: protoBaseST.**
  - Date the CHANGELOG `0.1.0` and merge `feat/prototype` into `main`.
  - Create the GitHub repository **only if the maintainer has said where**; otherwise stop
    and report that it is ready to push.
  - Tag `v0.1.0`.
- [ ] **Step 4:** update the workspace memory and the report with the released versions.
