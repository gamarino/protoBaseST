# protoBaseST Indexed Queries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** writes to collections with equality and range indexes, maintained in every mutator and
merged by blind writes exactly as `proto_db` does, plus `proto_db`'s term language, planner, plan
operators and `explain`, an immutable Smalltalk query front end and in-process paging by rank,
documented first and measured against `proto_db` on the same work. Vector indexes and vector
search are excluded.

**Architecture:** a line-for-line port of `proto_db`'s structure (spec call IC1). An index is an
immutable atom of the collection version: every mutator answers new content and new indexes in
one step, so no version can disagree with its indexes, and only a merge replays mutators during
the commit's build. The planner is a pure function from a source, an expression, an order and a
window to an immutable plan; plans hold only immutable values and run on any actor. The
documentation (guide, chapters 17-19, reference) is written before the code and each
implementation task makes its part runnable and measured.

**Tech Stack:**
- protoST 0.12.0 (`b7e206a`): `Atom`, actors, `MessagePack`, `crc32`, `Random seed:`,
  non-local return from blocks; no protoST or protoCore change (ruling IQ4);
- protoBaseST on branch `feat/queries` (from `feat/cluster` at `02d9826`; spec commits `34abe97`,
  `3eb28c6`, `6680e50`), starting after 0.2.0 ships;
- CPython ≥ 3.12 with `proto_db` at `v2.0.0rc4` (`8e6127f`) from the interop venv, for the
  interop tests, the vector generators and the Python side of the benchmarks.

**Spec:** `docs/superpowers/specs/2026-11-18-indexed-queries-design.md` (read all of it, including
section 9.2, the maintainer's rulings IQ1-IQ8 and the controller rulings CR1-CR10 of 2026-11-18, and section 4, the binding
deliverables D1-D7). The normative behaviour is `proto_db` at `v2.0.0rc4`: `proto_db/indexing/*`,
`proto_db/query/*` (less `cache.py` and the vector parts), `proto_db/collections/{avl,base,lists,
dictionaries,hash_dictionaries,sets}.py`, `docs/source/indexing-framework.rst` and
`docs/source/query-planner.rst`. Read every `proto_db` file with
`git -C "$PROTOBASE_REPO" show v2.0.0rc4:<path>`; never modify that repository. **When a rule is
unclear, `proto_db`'s code at the tag is the reference**; read it before guessing. Every ported
rule carries a comment citing its source (`file.py` function, or a D/R number).

## Global Constraints

From the maintainer's briefs and the approved spec:

- `proto_db` is the reference: semantics, plan choices, `explain` keys and node names follow it;
  every difference is a `docs/deviations.md` entry with its reason.
- Refuse, never diverge: what the port cannot do exactly (a vector index, an unknown index kind,
  an unregistered extractor, `near[]`) is an explicit error naming it.
- On-disk format shared with `proto_db`, same bytes: format 4, no new record type; index trees
  node-identical to `proto_db`'s for the same operations.
- Everything immutable; mutable state only through `Atom` (the extractor registry is one `Atom`
  of an immutable dictionary). No mutexes; no lock held across allocation.
- No change to protoCore or protoST (ruling IQ4: `log2` is not requested; plan near-ties are a
  documented deviation, results always equal).
- Documentation first (maintainer, 2026-11-18): the guide, chapters 17-19, the chapter 11 update
  and the reference sections are drafted before any implementation task, on `feat/queries-docs`,
  and integrated by Task 0. Course-material form: the obvious solution, why it fails, the
  measured alternative. A figure not measured yet is marked `[measured in T<n>: …]` and never
  invented.
- Benchmarks self-report and verify: every run prints the work done and a checksum; the runner
  refuses mismatched counts, checksums or plans; nothing is asserted about time; results are
  recorded with date, machine, load, commits and binaries in `docs/deviations.md#performance`.
- Naming: the Python product is `proto_db`, never "ProtoDB" or "ProtoBase"; protoBaseST is never
  called a GemStone "successor".
- Docs, comments and messages in professional English.
- TDD with fail-first evidence.
- Commits end `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push, merge, tag
  or publish.
- Correctness over speed; no technical debt (no uncalled code; cheap reviewer items get fixed).

Project rules that apply to every task:

- **Environment.** `export PROTOST=<absolute path of protoST 0.12.0 build_release/protost>` and
  `export PROTOBASE_REPO=<absolute path of the ProtoBase checkout>`, always set explicitly in a
  worktree. Verify the binary's protoCore with `ldd "$PROTOST"` once per session.
- **Test scope** (maintainer ruling, 2026-11-15, as for the cluster): each task runs only its own
  tests (the ones it adds or changes and the ones exercising the code it touches, named in its
  steps). The whole default suite, the property soaks and the audits run once, in Task 10.
- **Fail-first evidence.** Every "run, expect FAIL" step records the failing line in the task's
  commit body (`fail-first: <line>`).
- **Commit trailer.** Every commit step means
  `git commit -m "<subject>" -m "<body>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`.
- **State.** No method assigns an instance variable after construction
  (`tests/unit/values_immutable.st`); that test covers new modules through its glob over
  `src/protobase/*.st` and `cluster/*.st` (line 80), so a task that adds a module checks that
  the module is in the glob's reach and adds nothing to a list (pre-flight F19).
- **Module order.** `src/protobase.st` keeps its existing import order (`avl`, `collections`,
  `records`, `indexes`, `roots`, ...) and gains `keyspec` after `codec`, `keygroups` after `avl`,
  and `terms`, `plans`, `planner`, `query`, `pager` after `indexes` and before `roots`
  (pre-flight F14). `tests/docs/reference_selectors.sh` scans every new module.
- **Documentation in the same task.** A task that adds public API moves its selectors off the
  pending list (call IP5), makes the reference text it touches true, makes its chapter samples
  runnable when the program needs only the API built so far (a program that sends `PBQuery`,
  `PBField` or `PBPlanner` runs in Task 8, IP1), replaces its `[measured in T<n>: …]` markers, and adds to `CHANGELOG.md`
  (`## 0.3.0 (unreleased)`, ruling IQ8).
- **Benchmarks run serially**, on a quiet machine, never alongside a build, a soak or another
  bench (profiling is serial; builds may be parallel).
- **protoST defects** found while working go to protoST `KNOWN_ISSUES.md` and become a task
  flagged for the maintainer; they are never worked around here.
- **Visible skips only.** A test that cannot run prints `SKIP: <reason>` as its last line (exit
  77 for `.sh`); Task 10 accepts no skip in the query tests.

## Calls made by the planner (review at Task 10)

Rulings on points the spec leaves open. Entries marked **(maintainer)** change something the
spec states or a released API; Task 10 copies the table into `docs/decisions.md`.

| # | Call | Why |
|---|---|---|
| IP1 | Task numbers are the spec's T0-T10, so a marker `[measured in T<n>: …]` names the task that fills it. T4 is split into Tasks 4a and 4b; a `T4` marker is filled by whichever of the two measures it (M1 in 4a, M3 in 4b). Task 0b is the checklist. The chapter and example programs of `examples/queries/pending/` all send `PBQuery`, `PBField` or `PBPlanner`, so they leave `pending/` and run in Task 8 (Task 9 for chapter 19 and `paging.st`); Tasks 4a, 4b and 6 keep their benches, markers and reference work (pre-flight F3). | One numbering for the docs job and the plan. |
| IP2 | **Ruled by the maintainer, 2026-11-18: exactly as `proto_db`.** An exception raised by an extractor block passes through `extract:` unchanged (`KeySpec.extract` does not wrap it) and fails only the commit whose merge ran it. No new error class, no deviation. | Ruling IQ1 as corrected in spec 9.2. |
| IP3 | **Ruled by the maintainer, 2026-11-18: keep the released API.** `PBIndex >> keySpec` keeps answering the persisted `(kind, arg)` tuple, as in 0.1.0. The new `PBIndex >> keySpecObject` answers it as a `PBKeySpec` (`PBKeySpec fromData: self keySpec`); a malformed tuple is `PBValidationError` naming the index, when asked, never at read. Every later task uses `keySpecObject` for the object. | Compatibility of a 0.1.0 selector. |
| IP4 | Test layout: unit, property and contract tests live flat in `tests/unit/` (`idx_*.st` indexes, `qry_*.st` terms, plans, planner, query, pager), helpers `_queries.st` (seeded data sets, the scan oracle) and `_qplants.st` (planted defects); generators and replays in `tests/interop/`. The spec's `tests/property/...`, `tests/contracts/...` names are `proto_db`'s files. | CC12 precedent: the runner sets the working directory to the test's and `_check.st` lives in `tests/unit`. |
| IP5 | `tests/docs/pending_selectors.tsv` (columns: selector, task) lists the selectors the drafts cite before they exist. `reference_selectors.sh` accepts them; a listed selector that is now defined is an error (a stale line), so each task removes its own lines; with `PENDING_FINAL=1` (Task 10) a non-empty list is an error. | Drafts first (maintainer) with the guard kept honest. |
| IP6 | `tests/docs/measured_markers.sh` lists every `[measured in T<n>: …]` in `docs/` and `README.md`, fails on a malformed marker or a task outside T0-T10, and with `MARKERS_FINAL=1` (Task 10) fails on any marker left. | Numbers never invented, never forgotten. |
| IP7 | The descent term `log2(groups + 2)` is computed in one method, `PBCost class >> log2: aNumber` (`aNumber asFloat log: 2`); no other code computes a logarithm. | R2 lives in one place; the deviation entry cites it. |
| IP8 | Near tie (ruling IQ4, spec 6.2): two chosen plans differ acceptably only when `|a - b| <= 1e-12 * (a abs max: b abs)` for the root cost `a` protoBaseST computes for its plan and the root cost `b` `proto_db` recorded for its plan. Results are compared in every case. | The spec's rule, made exact. |
| IP9 | Plans: `do: aBlock` is the lazy protocol (early exit by non-local return in the caller); `execute` answers a new `Array` of rows each time. No stream class. | Laziness for `Limit` without a stream type; the spec's "a new stream each time" is met by `do:`. |
| IP10 | Bench line: `WORK id=<id> impl=<st|py> size=<n> rows=<n> queries=<n> plan=<root>[/<index>] checksum=<n>`; checksum = (Σ over rows of (position + 1) × id) mod (2^61 - 1) for ordered answers, (Σ id) mod (2^61 - 1) for unordered ones, counts added as rows. Same formula in both languages. | A checksum both languages compute trivially and exactly. |
| IP11 | Query vectors are vendored as `tests/conformance/vectors-queries/space/` (the database directory), `queries.msgpack` (cases) and `manifest.sha256`, written only by `tests/conformance/fetch_query_vectors.sh` (needs the venv). MessagePack, not JSON: protoST reads it natively. | Spec 6.2 said "a JSON file"; the format is not normative. |
| IP12 | Task 0 merges `feat/queries-docs` into `feat/queries` with `git merge --no-ff` after review; review findings are fixed on `feat/queries` in the same task. | The drafts are another job's commits; history keeps them. |
| IP13 | The keyed bulk build ports `_build_balanced` (`avl.py:492-504`) exactly, including which middle it picks for an even count; `posFromArray:`'s builder is not reused. | R4: shape drift breaks node conformance. |
| IP14 | Sort keys are `PBSortKey key: aPathOrFieldOrBlock descending: aBoolean` (plans.st). `PBQuery >> orderBy:` builds them. | One value type for `PBPlanner`, `PBSort` and `PBQuery`. |
| IP15 | Term-facing index methods (`supports:`, `estimate:`, `plan:`, `supportsOrder:`, `orderedPlan:descending:`) and rank segments are built in Task 6, with the plan classes they answer, not in Task 3. | They take `PBTerm` (Task 5) and answer `PBIndexPlan` (Task 6). |
| IP16 | The seed count of the property and contract tests is read from `PBST_PROP_SEEDS` (`qry_prop_equals_scan.st` default 20, `idx_contract.st` default 5). Spec 7.2 names `PBST_SIM_SEEDS`; the simulator owns that name, so the plan keeps its own. | A knob Task 10 can turn without clashing with the simulator (pre-flight F17). |
| IP17 | Between Tasks 4a and 4b the merge stays refused: 4a keeps an explicit interim refusal in `rebaseOnto:` and in `PBCountedSet`'s `_transform` for any indexed receiver or current, and `addIndex:` and `removeIndex:` answer an incomplete log (`_withChanges:log:complete:` with `complete` false), so such a version is never mergeable. Task 4b removes both. | `@index_add` and `@index_remove` are logged only in 4b; a replay onto the current version would otherwise drop the index definition (pre-flight F1). |

## Review Focus

1. **An extractor that raises, or is slow, during a merge in a group commit or a cluster round.**
   Only the commit whose merge ran the extractor fails, with the block's own exception, unchanged; the other commits of the same round commit; the publisher and the round runner keep
   running. Test: Task 4b, `tests/unit/idx_merge_extractor.st` (standalone, group of three, and
   the simulator's cluster round).
2. **Mixed numeric types and unorderable keys in one index** (1, 1.0, `Decimal` 1, `nil`,
   `PBMissing`, a map, a list holding a map). `eq: 1` finds every value `proto_db`'s
   `values_equal` makes equal; unorderable keys live in the side group, are found by equality and
   never by a range; ordering puts them last. Tests: Task 3 (`idx_keygroups.st`, case
   `mixed numeric and unorderable keys`), Task 7 (query vectors include them).
3. **A query or pager over a version, then more writes in the same transaction.** The query and
   pager keep reading the version they were built from; a new query sees the new version. Test:
   Task 8 (`qry_query.st`, case `query keeps its version`), Task 9 (`qry_pager.st`, case
   `writes after the pager do not move its pages`).
4. **Degenerate terms:** an empty `in:`, `between: 5 and: 3`, `in:` with duplicates and mixed
   types, a 1000-value `in:`, a path with an empty segment, a path starting with `@`. Each answers
   what `proto_db`'s `Term` decides (`terms.py:152-213`): the same result or the same error class.
   Test: Task 5 (`qry_terms.st`, case `degenerate terms as proto_db`), with the expected outcomes
   taken from `proto_db` by `tests/interop/py_term_cases.py`.
5. **A Python-written database whose extractor this process has not registered.** Reading and
   index-only queries work; a scan, a residual filter on `@name`, any change that evaluates the
   extractor and `validate` signal `PBValidationError` naming the extractor (corrected at Task 4a:
   as in `proto_db`, a blind write, `removeIndex:` or an `addIndex:` of another index pass); nothing is rebuilt or dropped. Tests: Task 4a
   (`idx_unregistered_extractor.st`, writes and validate), Task 7 (`qry_planner.st`, case
   `unregistered extractor: lookup runs, scan signals`).

---

## Phase 0: documentation first (maintainer, 2026-11-18)

### Task 0: Review and integrate the documentation drafts from `feat/queries-docs`

Starts when the documentation job reports its drafts done. It writes nothing new of its own: it
reviews, fixes and integrates.

**Files:**
- Merge: branch `feat/queries-docs` (worktree `../protoBaseST-queries-docs`, off `3eb28c6`):
  `docs/queries.md`, `docs/tutorial/17-*.md`, `18-*.md`, `19-*.md`, the chapter 11 update, the new
  sections of `docs/reference.md`, the pending programs (all in `examples/queries/pending/`:
  `17_indexes`, `18_queries_and_plans`, `19_ordered_reads_and_pages`, `reading_plans`,
  `_indexed_change`, `11_indexed_interop.sh`, `11_indexed_python_side.py`), whatever README rows
  it added.
- Create: `tests/docs/pending_selectors.tsv` (IP5), `tests/docs/measured_markers.sh` (IP6),
  `examples/queries/README.md` (the drafts have `examples/queries/pending/README.md`).
- Modify: `tests/docs/reference_selectors.sh` (pending list; scan `docs/queries.md`);
  `tests/docs/tutorial_chapters_sync.sh` (programs may live in `examples/queries/pending/` as
  `X.st.pending`, `X.sh.pending` or `X.py.pending`; `docs/queries.md` quotes `examples/queries/`
  programs under the same rule); `README.md` and `docs/tutorial/README.md` (chapters 17-19 row,
  marked draft until Task 10); `docs/tutorial/04-collections-and-queries.md` and
  `12-refusals.md` only if the drafts did not touch them (a "see chapter 17, in progress" pointer).

**Interfaces:**
- Consumes: the approved spec (5.2, 5.5 are the API the drafts may cite).
- Produces: the pending-selector list every later task shrinks; the marker convention every later
  task fills; the pending programs Tasks 8 and 9 move out of `pending/` (Task 8 moves `17`, `18`,
  `reading_plans`, `_indexed_change` and the chapter 11 files, Task 9 moves `19`).

- [ ] **Step 1: review the drafts against the spec**, file by file, with this checklist; record
  each finding as a line in the commit body.
  - Every selector cited is in spec 5.2/5.5 (or the Interfaces blocks of this plan); none is
    invented (`select:` on `PBQuery` never appears except to say it does not exist).
  - The 1.3 rows appear in course form: obvious solution, why it fails, the alternative, the
    measurement, with every figure as a `[measured in T<n>: …]` marker naming the right task
    (Q1-Q4 T8, Q5 T9, M1 T4, M2 T3, M3 T4, P1-P3 T7). No number that has not been measured.
  - The guide covers what D2 lists, and "Reading a plan" covers every node kind of 5.2, every
    `explain` key of 5.6, and three worked plans (estimates as markers).
  - Semantics agree with `proto_db` (`indexing-framework.rst`, `query-planner.rst`): D28 absence,
    `!=` not the complement of `==`, the one `Not(?N)` rewrite, no intersection plan, Filter
    selectivity 0.5, unions only of index-only branches.
  - Cluster interaction (spec 5.8) and IQ1's purity contract are stated, with a failing
    extractor's own exception passing through unchanged.
  - **Rulings of 2026-11-18 (IP2, IP3):** no draft mentions `PBExtractorError` or any wrapping of
    an extractor's error, and no draft says `keySpec` answers an object: `keySpec` answers the
    persisted tuple, `keySpecObject` the `PBKeySpec`. Grep the drafts for `PBExtractorError`,
    `keySpecData` and `keySpec` and fix every hit that contradicts this. `keySpecObject` is
    final: remove "provisional" (`docs/reference.md`, `docs/queries.md`).
  - **CR3 (pre-flight F5):** `name:keySpec:` takes a `PBKeySpec` only; anything else, a String
    included, is `PBValidationError`. Fix `docs/reference.md`'s `name: aString keySpec:
    aKeySpecOrString` and its "a String key spec is a path" sentence; `name:path:` is the
    convenience for a path.
  - Naming: `proto_db`, never "ProtoDB"/"ProtoBase"; no "successor" of GemStone.
  - Controller rulings CR1-CR10 (spec 9.2) hold in the drafts: the `!=` text of CR1, P2 as CR2
    states it, both constructors (CR3), `kind` names (CR4), `where:` and `&` / `|` / `not` (CR5,
    CR6 with its exact text), `betweenLeftOpen:and:` / `betweenRightOpen:and:`, zero-based
    pages, the pager's `explain` without `portable` (CR7); every worked-plan figure is labelled
    "model estimate" (CR10), never presented as a measurement.
- [ ] **Step 2: write the doc-guard changes and run them to see them fail on the merged drafts.**
  Merge `feat/queries-docs` (`git merge --no-ff feat/queries-docs`), then run
  `tests/run_tests.sh tests/docs`. Expected before the guard changes: FAIL in
  `reference_selectors.sh` (selectors not defined) and in `tutorial_chapters_sync.sh` (chapters
  name programs under `pending/`).
- [ ] **Step 3: implement IP5 and IP6 and extend the sync test.** Fill
  `pending_selectors.tsv` from the failure list, each selector with the task (1-9) whose
  Interfaces block produces it; a selector no task produces is a draft defect: fix the draft.
  `measured_markers.sh` prints the marker count per task.
- [ ] **Step 4: fix the review findings of Step 1** in the drafts.
- [ ] **Step 5:** run `tests/run_tests.sh tests/docs`. Expected: PASS;
  `measured_markers.sh` prints counts for T3, T4, T7, T8, T9 at least.
- [ ] **Step 6:** commit `Queries T0: integrate the documentation drafts; pending selectors and measured markers`.

### Task 0b: The `proto_db` test checklist

**Files:**
- Create: `tests/lib/checklist_rows.sh` (the table parser and row rules both checklists use),
  `tests/unit/queries_checklist.sh`, `tests/unit/queries_checklist.tsv`.
- Modify: `tests/unit/cluster_checklist.sh` (calls the shared helper; its rules and output do not
  change).

**Interfaces:**
- Consumes: `tests/unit/cluster_checklist.sh` (its parsing and row rules move into
  `tests/lib/checklist_rows.sh`, which both checklists call; no copy, pre-flight F13).
- Produces: one row per `proto_db` test function of the files of spec 7.1 (301 rows at
  `v2.0.0rc4`); statuses `ported <file> <check label>`, `deferred <task 1..10, or 4a/4b> <reason>`,
  `n/a <excluded: vector | deferred: cache | deferred: tokens | Python-only API> <reason>`. Every
  later task turns its deferred rows into `ported` rows.

- [ ] **Step 1: extract the shared helper, then write the check.** Move the cluster checklist's
  parsing and row rules into `tests/lib/checklist_rows.sh`, make `cluster_checklist.sh` call it,
  and run `tests/unit/cluster_checklist.sh` (expected: PASS, output unchanged). Then write the
  check on the same helper with the cluster checklist's rules (missing row, unknown row,
  duplicate, malformed, missing file, label not a whole check label, reasons of at least six
  words), the file list fixed in the script, the tag `v2.0.0rc4`, and `CHECKLIST_FINAL=1` making
  every deferred row an error.
- [ ] **Step 2:** run it with an empty table. Expected: FAIL, `no row for test_equality_index.py::...`
  (301 such lines).
- [ ] **Step 3:** write the table: every row `deferred` to its task (from the spec's 2.x tables:
  `test_keyspec` 2; index base and the structure rows of equality and range 3; the plan halves
  of `test_equality_index.py` and `test_range_index.py` 6; `test_index_rank.py` 6; the contract
  tests 3 or 7 per row (structure 3, plan 7); collection rows 4a; `test_indexed_roots.py` and
  `test_index_weights_concurrency.py` (the three `tests/concurrency/` files) 4b; terms and
  expressions 5; planner and `test_index_equals_scan.py` 7; linq 8; pager 9 and
  `test_pager_stability.py` 9) or `n/a`
  (all 30 of `test_vector_index.py`, the 19 of `test_query_cache.py`, the 3 of
  `test_query_cache_soundness.py`, and the token tests of `test_pager.py` as `deferred: tokens`).
- [ ] **Step 4:** run it and `tests/unit/cluster_checklist.sh`. Expected: PASS, `301 rows`,
  counts per status printed.
- [ ] **Step 5:** commit `Queries T0b: checklist of proto_db's index and query tests`.

---

## Phase 1: indexes that can be written (spec T1-T4)

Tests use `tests/unit/_check.st` (`Check new`, `that:is:equals:`, `that:isTrue:`,
`that:signals:containing:during:`, `report`) and declare `"EXPECT: ok N"`.

### Task 1: AVL functions for indexes and rank access

**Files:**
- Modify: `src/protobase/avl.st` (after `keysAndValuesDo:over:`).
- Test: `tests/unit/idx_avl.st` (no venv); extend `tests/interop/_st_avl_ops.st` and
  `tests/interop/py_avl_replay.py` with a `bulk` sequence.

**Interfaces:**
- Consumes: `PBAvl class >> keyPut:key:value:nodeClass:`, `keyRemove:key:`, `PBKeys orderKey:`.
- Produces (all on `PBAvl class`; `okey` is a `PBKeys orderKey:` value; a nil bound is open):
  - `keyDo: aBlock over: aRoot fromOrderKey: lo inclusive: aBoolean toOrderKey: hi inclusive: aBoolean`
    (block `[:key :value]`, ascending), port of `key_iter_okey_range`.
  - `keyReverseDo: aBlock over: aRoot`, port of `key_iter_reversed`.
  - `keyCountBelow: aRoot orderKey: okey inclusive: aBoolean` → Integer, O(log n).
  - `keyFromSorted: anArrayOfPairs nodeClass: aClass` (`{key. value}`, ascending) and
    `keyFromSortedOrderKeys: anArrayOfTriples nodeClass: aClass` (`{okey. key. value}`) → root,
    shape of `_build_balanced` (IP13).
  - `keyWeight: aRoot` → Integer; `keyWeightBelow: aRoot orderKey: okey inclusive: aBoolean` →
    Integer; both refuse a non-weighted tree (`PBValidationError`, as `_check_counted`).
  - `keyDo: aBlock over: aRoot fromWeight: rank descending: aBoolean` (block
    `[:key :value :skip]`), port of `key_iter_from_weight`, its `rank` check included.
  - `posDo: aBlock over: aRoot from: start` and `keyDo: aBlock over: aRoot from: start`, ports of
    `pos_iter_from` and `key_iter_from`.

- [ ] **Step 1: write the failing tests.** `idx_avl.st` (`"EXPECT: ok 12"`), on trees built by
  `keyPut:` from `Random seed: 20261118` (500 keys, weights 1-5):
  - `okey range`: for 20 random bound pairs and the four inclusivity combinations, the keys
    visited equal the filter of `keysAndValuesDo:` by order key.
  - `reverse`: `keyReverseDo:` equals the reversed `keysAndValuesDo:` list.
  - `count below`: equals the count of keys `<` (or `<=`) for 50 probes, present and absent.
  - `bulk shape`: `keyFromSorted:` of the sorted pairs passes `PBAvl check:`; for sizes 0..16 its
    node shape (heights and keys in preorder) equals shapes written inline in the test, and the
    even-count middle follows IP13. Node identity with `proto_db` is checked only by
    `avl_ops_identical.sh` (Step 4); the unit test needs no Python.
  - `weight`: `keyWeight:` = sum of weights; `keyWeightBelow:` = partial sums for 50 probes.
  - `from weight`: for every rank 0..W, ascending and descending, the first triple's key and
    `skip` equal the ones computed from the flat occurrence list; rank W yields nothing; rank
    W + 1 and -1 signal `PBValidationError`.
  - `from position`: `posDo:from:` and `keyDo:over:from:` equal slicing the full walk.
  - `early exit`: a `^` from the block of `keyDo:over:fromWeight:descending:` inside a method
    stops the walk after 3 calls (a counter in an `Atom` reads 3): pins IP9's laziness.
- [ ] **Step 2:** run `tests/run_tests.sh tests/unit/idx_avl.st`. Expected: FAIL
  (`keyDo:over:fromOrderKey:...` not understood).
- [ ] **Step 3:** implement each function by porting `avl.py:604-806` and `:492-504`.
- [ ] **Step 4:** add the `bulk` sequence to `_st_avl_ops.st` / `py_avl_replay.py` (sizes 0..64
  and 2000, every node line identical). Run `tests/run_tests.sh tests/unit/idx_avl.st
  tests/interop/avl_ops_identical.sh`. Expected: PASS.
- [ ] **Step 5:** reference ("Lower layers": the new `PBAvl` messages), remove their
  `pending_selectors.tsv` lines, CHANGELOG; turn the AVL rows of the checklist (if any) to
  `ported`; commit `Queries T1: AVL ranges, weights, rank walks and the balanced keyed build`.

### Task 2: Key specs, the extractor registry and member keys

**Files:**
- Create: `src/protobase/keyspec.st`, `src/protobase/keygroups.st` (member-key part only).
- Modify: `src/protobase/errors.st` (`PBMisfiledError`), `src/protobase.st`.
- Test: `tests/unit/idx_keyspec.st`, `tests/conformance/index_keys.st`; create
  `tests/interop/py_index_keys.py` and the vendored output
  `tests/conformance/vectors-index-keys/keys.msgpack` + `manifest.sha256`.

**Interfaces:**
- Consumes: `PBKeys orderKey:`, `exactToken:`, `isOrderable:`; `PBCodec canonical:`,
  `valueDepth:`, `maxValueDepth`; `PBObject >> hasDefinedAttr:`; `PBMissing default`.
- Produces:
  - `PBKeySpec class >> path: aString`, `element`, `extractor: aName`,
    `forTermPath: aStringOrNil` (nil → element, `'@name'` → extractor), `fromData: aTuple`;
    validation as `KeySpec.__post_init__` (`PBValidationError`).
  - `PBKeySpec >> kind` (`'path' 'element' 'extractor'`), `arg`, `extract: anElement` (the key,
    or `PBMissing default`; step semantics of `_step`: own attributes of a `PBObject`, keys of a
    map, `_`-prefixed and reserved names never read; extractor results through
    `PBCodec canonical:`), `termPath`, `describe`, `asData` (a `PBTuple`), `=`, `hash`.
  - `PBKeySpec class >> registerExtractor: aName block: aBlock version: aStringOrNil`,
    `unregisterExtractor: aName`, `extractorVersion: aName`, `isExtractorRegistered: aName`
    (one `Atom` of a `PBFrozenDict`; rebinding a name to another block or version is
    `PBValidationError`; an unregistered name used is `PBValidationError` with `proto_db`'s text).
  - `extract:` lets any exception of an extractor block pass through unchanged (IP2);
    `PBMisfiledError` (`PBCorruptionError` subclass) for Task 3.
  - `PBMemberKeys class >> surrogate: aValue`, `memberKeyOf: anElement` (`PBTuple`
    `{{0 or 1. element or surrogate}. exactToken bytes}`), `checkDepth: anElement` (`proto_db`'s
    index depth limits, `keyed.py:161-215`), `lowestOf: aValue` / `highestOf: aValue` (the
    equal-member bounds of `keyed.py:81-158`).

- [ ] **Step 1: write the failing tests.**
  - `idx_keyspec.st` (`"EXPECT: ok 15"`): the 19 `test_keyspec.py` behaviours that apply
    (constructors, validation messages, `forTermPath:`, `extract:` on records, maps, nested
    paths, absent → `PBMissing default`, `nil` kept as `nil`, private names → missing, data round
    trip, equality and hash); registry: register, rebind same block and version (accepted),
    rebind other (`PBValidationError`), unregister, `isExtractorRegistered:` (false before
    registering, true after, false after unregistering), use unregistered (`PBValidationError`
    containing `'register'`); `extractor error passes through`: a block `[:e | 1 / 0]` registered
    as `'boom'` makes `extract:` signal `ZeroDivide` itself, not a `PBDBError`; registration from 8 actors at once leaves 8 names (CAS).
  - `index_keys.st` (`"EXPECT: index keys ok"`): for every case of `keys.msgpack`, the member
    key's wire bytes, the surrogate, `isOrderable:`, the bounds and the depth refusals equal
    `proto_db`'s (seeded values of every rank, unorderables, `PBMissing`, `nil`, atoms, nested
    lists and maps at the depth limits).
- [ ] **Step 2:** write `py_index_keys.py` (seed 20261118, reads `proto_db` at the tag through
  the venv) and generate the vendored file once with its manifest. Run
  `tests/run_tests.sh tests/unit/idx_keyspec.st tests/conformance/index_keys.st`. Expected: FAIL
  (`PBKeySpec` not understood).
- [ ] **Step 3:** implement, porting `keyspec.py` and `keyed.py:81-215`.
- [ ] **Step 4:** run both tests. Expected: PASS.
- [ ] **Step 5:** reference ("Key specs and extractors"), remove pending lines, checklist rows of
  `test_keyspec.py` to `ported`; the guide section "Keys, `MISSING` and `nil`" quotes
  `examples/queries/keys.st`, which Task 8 writes (F4), so its samples run there; commit `Queries T2: key specs, extractor registry, member keys`.

### Task 3: Key-group indexes: hooks, bulk build, validate, explain

**Files:**
- Modify: `src/protobase/keygroups.st` (groups, side group, group operations),
  `src/protobase/indexes.st` (`PBIndex` hooks, `PBKeyGroupIndex`, `PBEqualityIndex`,
  `PBRangeIndex`, `PBVectorIndex` refusals, IP3; the module comment, which says the module "never queries or
  maintains" indexes, is rewritten: pre-flight F15), `src/protobase/collections.st` (`PBIndexSet`
  writes only).
- Create: `bench/query_workload.st`, `bench/py_query_workload.py`, `bench/run_query.sh` (with
  workload M2 only).
- Test: `tests/unit/idx_keygroups.st`, `tests/unit/idx_contract.st`,
  `tests/unit/read_records_indexes.st` (IP3), `tests/unit/_queries.st`.

**Interfaces:**
- Consumes: Task 1 (`keyFromSortedOrderKeys:nodeClass:`, weights), Task 2 (`PBKeySpec`,
  `PBMemberKeys`, `PBMisfiledError`).
- Produces:
  - `PBKeyGroupIndex class >> name: aString keySpec: aPBKeySpec` (the primitive, CR3; anything
    but a `PBKeySpec` is `PBValidationError`) and `name: aString path: aString` (the convenience,
    `name: n keySpec: (PBKeySpec path: p)`): an empty unsaved index, `member_tokens` 1, fields in
    `persistedFields` order.
  - `PBIndex >> withAdded: anElement`, `withRemoved: anElement`,
    `withReplaced: old with: new`, `empty`, `build: aCollection` → new unsaved index;
    `explain` → `PBFrozenDict` (keys of `keyed.py:651-675`); `validate: aCollection` (structural
    checks of `keyed.py:677-737`, `PBCorruptionError` or `PBMisfiledError`); `keySpec`,
    `keySpecObject` (IP3; `keySpec` unchanged); `_with: aFieldDictionary`.
  - `PBMemberKeys class >> checkDepth: anElement index: anIndex` (Task 2 review): `proto_db`'s
    `check_member_key` refusal word for word, "Index 'n' (EqualityIndex on a.b) cannot store this
    element: ...", used by the hooks; its landing drops the `docs/deviations.md` row "Member-key
    depth refusal (until Task 3)".
  - `PBKeyGroupIndex >> groupCount`, `count`, `countOfKey: aKey`,
    `membersDo: aBlock` (block `[:element :count]`, groups in key order, side group last).
  - `PBVectorIndex` and an unknown index kind: every hook signals `PBNotSupportedError` naming
    the index and spec 3.3.
  - `PBIndexSet >> withIndex: anIndex`, `without: aName`, `onAdd: e`, `onRemove: e`,
    `onReplace: old with: new`, `rebuiltStale: aCollection`.
  - `_queries.st`: `QData class >> people: n seed: s` (records with `name`, `city`, `age`,
    some absent, some `nil`, mixed numeric ages), `QData class >> values: n seed: s` (every value
    rank), `QData class >> scan: aCollection where: aBlock` (the oracle, as a counted bag).
  - Bench: `bench/run_query.sh [ids...]` with IP10 lines; workload `M2` (`build:` on
    n = 10^2..10^5 against the fold of `withAdded:`, both implementations: what `addIndex:`
    will call in 4a and what `Index.build` is in `proto_db`; pre-flight F6).

- [ ] **Step 1: write the failing tests.**
  - `idx_keygroups.st` (`"EXPECT: ok 16"`): the structure-level tests of `test_index_base.py`,
    `test_equality_index.py`, `test_range_index.py` and `test_index_key_neutrality.py` (hooks
    answer new versions and leave the receiver unchanged; counts; duplicates in a multiset;
    `withRemoved:` of an absent element as `proto_db` decides; side group for unorderables;
    `empty` keeps the definition; `build:` equals the fold of `withAdded:` node for node);
    `mixed numeric and unorderable keys` (Review Focus 2); `explain` keys and values, with `kind` `'EqualityIndex'` / `'RangeIndex'` (`proto_db`'s names,
    CR4), `index`, `key`, `entries`, `keys`, `unorderable`; `name:path:` equals
    `name:keySpec: (PBKeySpec path:)`; `validate:`
    passes on built indexes and fails with `PBMisfiledError` on a hand-misfiled member; a
    `PBVectorIndex withAdded:` signals `PBNotSupportedError` containing `'vector'`; IP3:
    `keySpec` still answers the tuple, `keySpecObject` an equal `PBKeySpec`; the depth refusal
    of `checkDepth:index:` is `proto_db`'s exact sentence for an index too deep to hold an element
    (asserted in one of the sixteen checks).
  - `idx_contract.st` (`"EXPECT: ok 6"`): the structure half of `index_contract.py` over
    `QData values: 300 seed: s` for the seeds of `PBST_PROP_SEEDS` (default 5, IP16): random add / remove / replace keep `validate:`
    passing; `withReplaced:with:` equals remove then add; save and lazy load give equal
    `explain`; no hook changes its receiver.
  - Extend `read_records_indexes.st` for IP3 (`keySpecObject` of each decoded index; the
    existing `keySpec` checks unchanged).
- [ ] **Step 2:** run `tests/run_tests.sh tests/unit/idx_keygroups.st tests/unit/idx_contract.st
  tests/unit/read_records_indexes.st`. Expected: FAIL (`withAdded:` not understood).
- [ ] **Step 3:** implement, porting `base.py:56-338` and `keyed.py:220-457`, `651-737`.
- [ ] **Step 4:** run the three tests. Expected: PASS.
- [ ] **Step 5: bench M2** (`build:` against the fold of `withAdded:`). Write the bench files and run `RUNS=3 bench/run_query.sh M2`.
  Expected: every pair of lines has equal `rows` and `checksum` (the runner prints `verified`);
  record the figures in `docs/deviations.md#performance` ("Queries and indexes", dated, machine,
  load, both commits and binaries) and replace the `[measured in T3: …]` markers with them.
- [ ] **Step 6:** reference ("Indexes"), pending lines, checklist rows, CHANGELOG; commit
  `Queries T3: equality and range indexes can be written; bulk build; M2 measured`.

### Task 4a: Collections maintain their indexes in every mutator

**Files:**
- Modify: `src/protobase/collections.st` (`addIndex:`, `removeIndex:`, `_currentIndexes`, every
  mutator of `PBList`, `PBDictionary`, `PBHashDictionary`, `PBSet`, `PBCountedSet`, `validate`,
  `_checkWritable:` narrowed to vector and unknown kinds; `rebaseOnto:` and `PBCountedSet`'s
  `_transform` keep an explicit interim refusal for an indexed receiver or current, IP17);
  `bench/*` (workload M1).
- No program moves in this task: `17_indexes.st.pending` sends `PBQuery` and `PBField` and moves
  in Task 8 (IP1).
- Test: `tests/unit/idx_collections.st`, `tests/unit/idx_unregistered_extractor.st`,
  `tests/unit/indexed_refusal.st` (narrowed), `tests/interop/index_ops_identical.sh`,
  `tests/interop/_st_index_ops.st`, `tests/interop/py_index_replay.py`.

**Interfaces:**
- Consumes: Task 3 (`PBIndexSet` writes, hooks, `build:`).
- Produces:
  - `PBIndexedCollection >> addIndex: anIndex` (built from `elements`; an existing name is
    `PBValidationError`), `removeIndex: aName` (absent name: `PBValidationError`), `validate`
    (every index's `validate:` against `elements`); both answer an incomplete log (IP17), so the
    version cannot be merged until Task 4b logs the index ops.
  - Every mutator answers one new version holding new content and new indexes, with the hook
    order of its Python mutator (`lists.py`, `dictionaries.py`, `hash_dictionaries.py`,
    `sets.py`); a blind no-op answers the receiver's indexes untouched
    (`collections/base.py:513-519`); stale indexes (`hasMemberTokens` false) are rebuilt by
    `rebuiltStale:` before the first change.
  - `_checkWritable:` refuses only a `PBVectorIndex` or an unknown index kind
    (`PBNotSupportedError` naming it). `rebaseOnto:` and `PBCountedSet`'s `_transform` keep their
    `_checkWritable:` call narrowed so far, plus an explicit interim refusal
    (`PBNotSupportedError`, "merge onto an indexed current: Task 4b") for any indexed receiver or
    current (IP17); Task 4b removes it.

- [ ] **Step 1: write the failing tests.**
  - `idx_collections.st` (`"EXPECT: ok 15"`): the collection rows of `test_index_base.py`; for
    each collection kind and each mutator (the table of spec 5.3), after a seeded sequence of 200
    mutations with 0, 1 and 3 indexes, every index equals `build:` of `elements` node for node
    and `validate` passes; `addIndex:` with an existing name and `removeIndex:` of an absent one
    signal; a set `add:` of a present element keeps the index atom identical (`==`); a
    format-3 stale index (built with `member_tokens` absent, as `read_records_indexes.st` does)
    is rebuilt on the first change and not before; a version read back in the same transaction
    agrees with its own indexes.
  - `idx_unregistered_extractor.st` (`"EXPECT: ok 6"`, Review Focus 5, corrected at Task 4a's
    review): a collection with an index on extractor `'gone'` (written by registering, saving,
    then unregistering): reading and `indexNames` work; `setAt:value:` of a new key and
    `validate` signal `PBValidationError` containing `'gone'`; `removeAt:` of an absent key,
    `removeIndex: 'by_gone'` and `addIndex:` of a path index succeed; the stored index is
    unchanged.
  - `indexed_refusal.st`: now expects writes to succeed on key-group indexes and the refusal only
    with a `PBVectorIndex` or an opaque index atom; and a merge (`rebaseOnto:`, and a
    `PBCountedSet` transform) onto an indexed current still signals `PBNotSupportedError`
    (the interim refusal, IP17), including after `addIndex:` / `removeIndex:`.
  - `index_ops_identical.sh` (spec 6.1.2): a seeded sequence (add index, every mutator of every
    collection kind, remove index, stale rebuild) run by `_st_index_ops.st` and by
    `py_index_replay.py`, dumps compared with `compare_dumps.py --exact`; `proto_db`'s verifier
    and `collection.validate()` accept protoBaseST's space.
- [ ] **Step 2:** run `tests/run_tests.sh tests/unit/idx_collections.st
  tests/unit/idx_unregistered_extractor.st tests/unit/indexed_refusal.st
  tests/interop/index_ops_identical.sh`. Expected: FAIL (`addIndex:` not understood).
- [ ] **Step 3:** implement, porting `collections/base.py:146-238`, `341-473` and each mutator
  against its Python source (R6).
- [ ] **Step 4:** run the four tests. Expected: PASS.
- [ ] **Step 5: chapter 17.** Its program stays in `pending/` until Task 8 (IP1); run
  `tests/run_tests.sh tests/docs`. Expected: PASS (the pending guard still accounts for it).
- [ ] **Step 6: bench M1.** Add workload M1 (N single-element transactions with 0, 1, 3 indexes;
  commits per second and the extra cost per index) and run `RUNS=5 bench/run_query.sh M1`.
  Expected: `verified`. Record and replace the M1 markers.
- [ ] **Step 7:** reference ("Collections": `addIndex:`, `removeIndex:`, `validate`; the
  read-only note narrowed), `docs/deviations.md` indexed-collections entry rewritten,
  `docs/not-done.md` ("No rebuilding of format-3 indexes" and "indexed writes" leave), pending
  lines, checklist rows; commit `Queries T4a: indexed collections can be written; M1 measured`.

### Task 4b: Index-definition ops, merges onto indexed currents, extractors in the commit

**Files:**
- Modify: `src/protobase/collections.st` (`_PBOpLog` index ops, `rebaseOnto:`, `_replay:onto:`
  for index ops), `src/protobase/publisher.st` (module comment: the extractor exception, IQ1),
  `src/protobase/round.st` and `src/protobase/cluster/round.st` only if Step 2 shows a failing
  build fails more than its own commit; `src/protobase/transactions.st` (the comment of
  `_merged:onto:`, near line 671, which says a rebase onto an indexed current is
  `PBNotSupportedError`, is rewritten; pre-flight F15); `bench/*` (workload M3);
  `tests/interop/concurrency.sh` (row 13, the new rows, and the hard-coded `count -eq 27` check
  and its comment, updated to the new row count; pre-flight F20).
- No program moves in this task: the chapter 11 additions are the new files
  `11_indexed_interop.sh.pending`, `11_indexed_python_side.py.pending` and
  `_indexed_change.st.pending`, which send `PBQuery` and `PBField` and move in Task 8 (IP1).
- Test: `tests/unit/idx_merge.st`, `tests/unit/idx_merge_extractor.st`,
  `tests/interop/index_both_directions.sh`, `tests/interop/concurrency.sh`.

**Interfaces:**
- Consumes: Task 4a; `_PBOpLog class >> after:op:`, `opsOf:`, `orderKeysOf:`,
  `lastOccurrencesOf:do:`; `PBPublisher` merge (`transactions.st:671-675`); `PBClusterRound >>
  _build:`; the simulator of `tests/unit/_sim.st`.
- Produces: `addIndex:` logs `('@index_add' name index)` and `removeIndex:` logs
  `('@index_remove' name)` on the classes `proto_db` logs them for (never `PBList`,
  `base.py:572-573`); the net-effect reduction keeps element ops and index ops apart;
  `rebaseOnto:` replays element ops through the public mutators of the current version, then
  index ops per name, `PBConflictError` naming the index when both created it
  (`base.py:594-631`); the refusal in `rebaseOnto:` only for vector and unknown kinds. Task 4b
  removes the interim refusal of `rebaseOnto:` and `PBCountedSet`'s `_transform` and the
  incomplete-log marking of `addIndex:` / `removeIndex:` that Task 4a left (IP17).

- [ ] **Step 1: write the failing tests.**
  - `idx_merge.st` (`"EXPECT: ok 9"`): blind writes from two transactions onto an indexed
    dictionary, set, counted set and hash dictionary both commit and the result's indexes equal a
    rebuild; a concurrent `addIndex:` of the same name in both is `PBConflictError` containing the
    name; different names both survive; `removeIndex:` against a concurrent write keeps the write
    and drops the index; a merge onto a current that holds a vector index is
    `PBNotSupportedError`.
  - `idx_merge_extractor.st` (`"EXPECT: ok 4"`, ruling IQ1, Review Focus 1): extractor
    `'flaky'` raises for one marked element. (a) Standalone: the commit whose merge extracts it
    fails with the block's own exception (`ZeroDivide`), unchanged; the next commit succeeds. (b) `group commit: one extractor fails` (CR8): a
    group-commit leader (D52) builds three queued blind-write transactions in one round, the
    middle one's merge hitting the element: the first and third commits' Futures resolve
    committed and their writes are in the new root; only the middle one's Future fails, with that
    same `ZeroDivide`. (c) The simulator's cluster round
    (`PBClusterRound >> _build:` with the same three): the same outcome, the round runner still
    serving the next round. No case asserts the text of a comment (pre-flight F18); the
    `publisher.st` and `_merged:onto:` comments are corrected in review.
  - `index_both_directions.sh` (spec 6.1.3): `proto_db` writes indexed collections, protoBaseST
    changes them with every mutator and a merge, `proto_db` validates and queries the result
    (index lookups equal its scans); then the reverse.
  - `concurrency.sh`: row 13 expects "both merge" with `proto_db`'s recorded outcome; new rows for
    concurrent `addIndex:` (both orders of the two languages as first and second committer);
    the expected row count in the script is updated with them.
- [ ] **Step 2:** run `tests/run_tests.sh tests/unit/idx_merge.st tests/unit/idx_merge_extractor.st
  tests/interop/index_both_directions.sh tests/interop/concurrency.sh`. Expected: FAIL
  (the interim refusal of Task 4a: `rebaseOnto:` signals `PBNotSupportedError` for the indexed
  current).
- [ ] **Step 3:** implement. If case (b) or (c) shows one failing build failing the whole group,
  the fix goes in the round runner's per-commit build (each queued commit's build error resolves
  only its own Future), with that case as its fail-first evidence.
- [ ] **Step 4:** run the four tests. Expected: PASS.
- [ ] **Step 5: chapter 11.** Its additions stay in `pending/` until Task 8 (IP1); run
  `tests/run_tests.sh tests/docs`. Expected: PASS.
- [ ] **Step 6: bench M3.** Add workload M3 (blind writes merged onto an indexed current,
  standalone and in a three-member cluster with `bench/run_cluster.sh`'s profile). Run
  `RUNS=5 bench/run_query.sh M3`. Expected: `verified`. Record and replace the M3 markers.
- [ ] **Step 7:** reference, checklist rows
  (`test_indexed_roots.py`, `test_index_weights_concurrency.py`, merge rows), CHANGELOG; commit
  `Queries T4b: merges onto indexed currents; extractors in the commit (IQ1); M3 measured`.

---

## Phase 2: the expression language, plans and the planner (spec T5-T7)

### Task 5: Terms and expressions

Runs after Task 3: its tests use `QData values:` from `tests/unit/_queries.st` (pre-flight F7).

**Files:**
- Create: `src/protobase/terms.st`.
- Modify: `src/protobase.st`; `tests/conformance/vectors-index-keys/manifest.sha256` (Task 2
  creates it; one manifest per vector directory, regenerated by each task that adds a file to
  that directory, F8).
- Test: `tests/unit/qry_terms.st`, `tests/unit/qry_expressions.st`,
  `tests/interop/py_term_cases.py` with its vendored output
  `tests/conformance/vectors-index-keys/terms.msgpack`.

**Interfaces:**
- Consumes: Task 2 (`PBKeySpec forTermPath:`, `extract:`), `PBKeys orderKey:`,
  `PBCodec canonical:`.
- Produces:
  - `PBTerm class >> path: aStringOrNil op: anOperatorString value: aValue` and
    `path:op:` (the unary operators `'?N' '?!N' '?T' '?!T'`); operators exactly
    `'==' '!=' '<' '<=' '>' '>=' 'in' 'between[]' 'between()' 'between[)' 'between(]' '?N' '?!N'
    'contains' '?T' '?!T'`; `'near[]'` signals `PBNotSupportedError` containing `'vector'`;
    validation and canonical operands as `terms.py:152-213` (`in` over a set sorted by order key).
  - `PBTerm >> path`, `op`, `value`, `keySpecObject` (the `PBKeySpec` of its path; every selector
    answering a `PBKeySpec` is named `keySpecObject`, ruling 2026-11-19; `PBTerm` has no
    `keySpec`), `matches: anElement` (D28: `PBMissing` matches
    only `?N`; `!=` is not the complement of `==`), `describe`, `asList`, `=`, `hash`.
  - `PBExpression` (abstract): `evaluate: anElement`, `describe`, `asList`, `termsDo: aBlock`,
    `&`, `|`, `not`. `PBAnd class >> withAll: anArray`, `PBOr class >> withAll:` (flattened,
    n-ary), `PBNot class >> of: anExpression` (`not not` answers the original), `PBTerm`
    and `PBBlockPredicate` are expressions.
  - `PBBlockPredicate class >> block: aBlock description: aString`.
  - `PBExpression class >> compile: anArray` (the 0.1 prefix list syntax, both directions with
    `asList`).

- [ ] **Step 1: write the failing tests.** `qry_terms.st` (`"EXPECT: ok 12"`) and
  `qry_expressions.st` (`"EXPECT: ok 10"`): the 19 `test_terms.py` and 25 `test_expressions.py`
  behaviours that apply; `matches:` on `QData values:` equals `proto_db`'s answers recorded in
  `terms.msgpack` for every operator; `degenerate terms as proto_db` (Review Focus 4);
  `compile:` of every recorded list gives a term whose `asList` is the same list and whose
  `describe` is `proto_db`'s text; `near[]` refused; `& | not take expressions only` (CR5): a
  block argument to `&` or `|` signals `PBValidationError`.
- [ ] **Step 2:** write `py_term_cases.py`, vendor its output and regenerate the directory's
  `manifest.sha256`, run
  `tests/run_tests.sh tests/unit/qry_terms.st tests/unit/qry_expressions.st`. Expected: FAIL.
- [ ] **Step 3:** implement, porting `terms.py` and `expressions.py`.
- [ ] **Step 4:** run both. Expected: PASS.
- [ ] **Step 5:** reference ("Terms and expressions"), pending lines, checklist rows, CHANGELOG;
  the guide section "The expression language" quotes `examples/queries/expressions.st`, which
  Task 8 writes (F4), so its samples run there; commit
  `Queries T5: terms, And/Or/Not, the list syntax`.

### Task 6: Plan operators, `explain`, index access paths and rank

**Files:**
- Create: `src/protobase/plans.st`.
- Modify: `src/protobase/keygroups.st` and `src/protobase/indexes.st` (term-facing methods and
  rank segments, IP15), `src/protobase/collections.st` (`asQueryPlan`, `_scanWindowFrom:to:`),
  `src/protobase.st`; `tests/interop/py_term_cases.py`, its vendored
  `tests/conformance/vectors-index-keys/terms.msgpack` and that directory's `manifest.sha256`
  (extended with the index costs; the manifest regenerated, F8).
- Test: `tests/unit/qry_plans.st`, `tests/unit/qry_index_plans.st`, `tests/unit/qry_rank.st`.

**Interfaces:**
- Consumes: Tasks 1, 3, 4a, 5.
- Produces:
  - `PBCost class >> log2: aNumber` (IP7). `PBEstimate class >> rows: r cost: c` (finite,
    non-negative Floats; else `PBValidationError`), `rows`, `cost`.
  - `PBQueryPlan` protocol: `do: aBlock` (lazy, IP9), `execute` (new `Array`), `explain`
    (`PBFrozenDict`: `plan`, `estimate`, `children`, `index`, `term`, `predicate`, `keys`,
    `limit`, `offset`, `by_rank`; `BlockFilter` has `description`), `estimate`,
    `windowFrom: start to: stop` (answers an `Array`; by rank where offered),
    `exactRows` (Integer or nil), `byRank` (Boolean).
  - Classes and constructors: `PBCollectionScan class >> on: aCollection` (its explain's
    `'collection'` is `proto_db`'s class name, `type(c).__name__`: the last segment of the
    collection class's `typeName`, `'Dictionary'`, `'List'`, `'HashDictionary'`, `'Set'`,
    `'CountedSet'`, `'RepeatedKeysDictionary'`, never the protoST class name; ruling 2026-11-19, so
    explain output compares equal across the two languages);
    `PBIndexPlan class >> index: anIndex term: aTerm part: aPart` (parts: lookup, range,
    complement, ordered scan, as `IndexLookup`/`IndexRange`/`IndexComplement`/`IndexOrderedScan`);
    `PBFilter class >> source: aPlan terms: anArray`; `PBBlockFilter class >> source: aPlan
    predicate: aBlockPredicate`; `PBUnion class >> withAll:`; `PBIntersect class >> withAll:`;
    `PBProject class >> source: aPlan fields: anArrayOrBlock`; `PBSort class >> source: aPlan
    keys: anArrayOfSortKeys`; `PBLimit class >> source: aPlan limit: n offset: m`;
    `PBCount class >> source: aPlan`; `PBDistinct class >> source: aPlan`;
    `PBSortKey class >> key: aPathOrFieldOrBlock descending: aBoolean` (IP14).
    Row identity for `Union` / `Intersect` / `Distinct` is `element_identity` (`base.py:22-53`).
  - On indexes: `supports: aTerm`, `estimate: aTerm` → `PBEstimate` (D30, `keyed.py:596-622`),
    `plan: aTerm` → `PBIndexPlan`, `supportsOrder: aKeySpec`, `orderedPlan: aKeySpec descending:
    aBoolean`; `PBVectorIndex >> supports:` answers false.
  - On collections: `asQueryPlan` → `PBCollectionScan`; `_scanWindowFrom:to:` for `PBList`
    and `PBDictionary` (rank by position).

- [ ] **Step 1: write the failing tests.**
  - `qry_plans.st` (`"EXPECT: ok 14"`): `test_query_plans.py`'s 4 and every node's `execute`,
    `estimate` and `explain` over `QData people: 200`: `Filter` selectivity 0.5 per term;
    `Union` max multiplicity and `Intersect` min multiplicity by element identity; `Sort` stable,
    total order, unorderable last, descending; `Limit` by rank over an ordered scan;
    `Count` by rank; `Distinct`; `Project` of a field and of a block, absent field projected as
    `PBMissing default`; `explain` printable by `PBNotation describe:`; `execute` twice answers
    equal, distinct `Array`s.
  - `qry_index_plans.st` (`"EXPECT: ok 10"`): the plan halves of `test_equality_index.py` and
    `test_range_index.py`: `supports:` per operator per kind; `plan:` results equal
    `QData scan:` for every operator; `estimate:` equals the costs `proto_db` gives for the same
    data (recorded by `py_term_cases.py`, extended), within IP8's tolerance.
  - `qry_rank.st` (`"EXPECT: ok 5"`, `test_index_rank.py`): `windowFrom:to:` equals slicing
    `execute` for every window of 30 random ones on lookups, ranges, ordered scans, list and
    dictionary scans, `Limit` and `Filter` over an ordered scan; `exactRows` where offered.
- [ ] **Step 2:** run `tests/run_tests.sh tests/unit/qry_plans.st tests/unit/qry_index_plans.st
  tests/unit/qry_rank.st`. Expected: FAIL.
- [ ] **Step 3:** implement, porting `plans.py:75-880` (less `ValuesScan`, `VectorSearch`,
  `GroupBy`, `Join`, `Unnest`) and `keyed.py:266-336`, `461-647`.
- [ ] **Step 4:** run the three. Expected: PASS.
- [ ] **Step 5:** guide section "Reading a plan": its worked plans come from
  `examples/queries/reading_plans.st`, which sends `PBPlanner` and `PBQuery` and so runs in Task 8
  (IP1); Task 7 Step 5b checks their figures against `proto_db`. Their estimates are model
  output, labelled "model estimate" (CR10). Reference ("Plans and explain"), pending lines,
  checklist rows (including the plan halves of `test_equality_index.py` and
  `test_range_index.py` and `test_index_rank.py`, F10), CHANGELOG;
  commit `Queries T6: plan operators, explain, index access paths, rank access`.

### Task 7: The planner, the index-equals-scan property, query vectors

**Files:**
- Create: `src/protobase/planner.st`; `tests/interop/py_query_vectors.py`;
  `tests/conformance/fetch_query_vectors.sh`; `tests/conformance/vectors-queries/` (IP11);
  `tests/conformance/queries.st`.
- Create (Step 5b): `tests/interop/py_guide_plans.py`, `tests/docs/guide_plans.sh`.
  `guide_plans.sh` needs the venv: without it it prints `SKIP: no interop venv` and exits 77;
  Task 10 accepts no skip in it. Tasks 8 and 9 run `tests/docs` and so see that skip.
- Modify: `bench/*` (workloads P1, P2, P3), `docs/deviations.md` (R2 entry).
- Test: `tests/unit/qry_planner.st`, `tests/unit/qry_prop_equals_scan.st`,
  `tests/conformance/queries.st`.

**Interfaces:**
- Consumes: Tasks 5 and 6.
- Produces: `PBPlanner class >> plan: aCollectionOrPlan where: anExpressionOrArrayOrNil
  orderBy: anArrayOfSortKeys limit: anIntegerOrNil offset: anInteger` → `PBQueryPlan`;
  `PBPlanner class >> normalize: anExpression`. A pure function of its arguments: indexes in
  sorted name order, conjuncts deduplicated in order, candidates ranked by
  `{cost. scans. sorted index names}`, `Union` only when every branch is index-only, ordered
  index scan against `Sort`; argument errors as `planner.py:278-343`; no `near[]` rules.

- [ ] **Step 1: write the failing tests.**
  - `qry_planner.st` (`"EXPECT: ok 16"`): the 38 `test_planner.py` behaviours that apply
    (normalisation and the single `Not(?N)` rewrite; choice per operator; ties broken by name;
    unions; order; window; argument errors) and `unregistered extractor: lookup runs, scan
    signals` (Review Focus 5).
  - `qry_prop_equals_scan.st` (`"EXPECT: ok"`; seeds from `PBST_PROP_SEEDS`, default 20, each
    seed printed on failure): random collections of every kind, random index sets (0-3, equality
    and range, path, element and extractor key specs), random expressions of depth ≤ 3 with
    every operator: the planned result equals `QData scan:` as a multiset; with an order, the
    ordered result equals the scan sorted by the same keys; `concurrent readers` (spec 7.2): several
    actors run the same plan over the same version at once and every answer is identical.
  - `queries.st`: for every case of `queries.msgpack`, results equal always; plan tree, index
    choice, every node's rows equal and costs equal within IP8's tolerance; a different plan is a
    named near-tie report only under IP8, else FAIL. It prints `near ties: N` and its last line
    `query vectors ok`.
- [ ] **Step 2:** write `py_query_vectors.py` (seeded `proto_db` database: several collection
  kinds and index configurations, duplicates in a list, `MISSING`, `nil`, mixed numerics,
  unorderables; a fixed list of queries in the 0.1 syntax with orders and windows; it checks each
  recorded result against a scan and refuses to write otherwise) and `fetch_query_vectors.sh`;
  vendor the output once. Run `tests/run_tests.sh tests/unit/qry_planner.st
  tests/unit/qry_prop_equals_scan.st tests/conformance/queries.st`. Expected: FAIL.
- [ ] **Step 3:** implement, porting `planner.py` line by line (less `:15-26`, `199-234`).
- [ ] **Step 4:** run the three. Expected: PASS. Record the near-tie count in the commit body.
- [ ] **Step 5: bench P1-P3.** Add the workloads (P1: `plan` and `explain` only, 1-32
  conjuncts, 0-8 indexes; P2 (CR2): whether the measured times of the index plan and of scan plus filter, both forced,
  cross where the cost model switches, for a range swept from very selective to unselective and
  for `!=` on indexes with few and with nearly n key groups (the model's crossover in collection
  size is one or two elements, so size is not swept); P3: the hand-built
  intersection against the planner's filter plan). Run `RUNS=5 bench/run_query.sh P1 P2 P3`.
  Expected: `verified` (plans equal between implementations, or IP8 near ties named). Record and
  replace the T7 markers.
- [ ] **Step 5b: worked plans equal `proto_db`'s (CR10).** Write
  `tests/interop/py_guide_plans.py`, which builds the guide's worked-plan data with `proto_db`
  and prints `proto_db`'s own `explain` for each worked plan, and `tests/docs/guide_plans.sh`,
  which requires every "model estimate" number quoted in `docs/queries.md` and chapter 18 to
  equal that output (within IP8's tolerance) and the protoBaseST program's printed plan to equal
  it too once `examples/queries/reading_plans.st` exists (Task 8 moves it out of `pending/`
  and runs it; until then the script checks the quoted figures only). Expected: FAIL first on any
  hand-computed figure in the drafts; fix the text from the generated output, never by hand;
  then PASS.
- [ ] **Step 6:** guide (planner section), R2 deviation entry citing `PBCost class >> log2:`,
  reference ("Queries": `PBPlanner`), pending lines, checklist rows, CHANGELOG; commit
  `Queries T7: the planner; index equals scan; query vectors; P1-P3 measured`.

---

## Phase 3: the front end and paging (spec T8-T9)

### Task 8: `PBQuery`, `PBField`, block predicates

**Files:**
- Create: `src/protobase/query.st`.
- Move out of `examples/queries/pending/` (every one sends `PBQuery`, `PBField` or `PBPlanner`;
  pre-flight F2, F3): `17_indexes.st.pending`, `18_queries_and_plans.st.pending` and the chapter
  11 files `11_indexed_interop.sh.pending`, `11_indexed_python_side.py.pending`,
  `_indexed_change.st.pending` → `examples/tutorial/` under the same names without `.pending`
  (the pending README); `reading_plans.st.pending` → `examples/queries/reading_plans.st`.
- Create (F4, D4): `examples/queries/lookups.st`, `ranges.st`, `compound.st` (compound
  predicates with `explain`), `merge_indexed.st` (a merge onto an indexed root), and the programs
  the guide's sections "Keys, `MISSING` and `nil`" and "The expression language" quote:
  `keys.st` and `expressions.st`. Each is fail-first through `tutorial_chapters_sync.sh`: the
  guide quotes it before it exists.
- Modify: `bench/*` (Q1-Q4), `README.md` (API mapping rows of spec 5.5).
- Test: `tests/unit/qry_query.st`, `tests/unit/qry_field.st`.

**Interfaces:**
- Consumes: Tasks 5-7.
- Produces:
  - `PBField class >> path: aString`, `element`, `extractor: aName`; on a field:
    `eq:`, `ne:`, `<`, `<=`, `>`, `>=`, `in:`, `between:and:`, `betweenOpen:and:`,
    `betweenLeftOpen:and:`, `betweenRightOpen:and:`, `isNone`, `notNone`, `isTrue`, `notTrue`,
    `contains:` → `PBTerm`. No `=` override (IC4).
  - `PBQuery class >> from: aCollectionOrPlan`; `where: anExpressionOrBlock`,
    `project: anArrayOfPaths`, `collect: aBlock`, `orderBy: aKey`, `orderBy: aKey descending:
    aBoolean`, `thenBy:`, `thenBy:descending:`, `skip:`, `take:`, `distinct` → a new `PBQuery`;
    `asArray`, `do:`, `count`, `first` (`PBUserError` when empty), `firstOrNil`, `explain`,
    `plan`, `pagerSize: n` (Task 9; Task 8's tests do not cover it). No `select:` (ruling IQ2).
  - `where:` takes a `PBExpression` or a one-argument block; chained `where:` calls combine with
    AND (CR5); anything else signals `PBValidationError` with exactly
    `'where: expects a PBExpression or a one-argument block, got a ' , anArgument class name`
    (CR6; for `true`: `where: expects a PBExpression or a one-argument block, got a Boolean`,
    using the class name protoST answers for `true`, recorded in the test). A block enters a
    query only through `where:`.
  - The mixing rule (`linq.py:48-61`): in a top-level AND, pure conjuncts go to the planner and
    each block becomes its own `PBBlockFilter` on top; an OR or NOT holding a block is one block
    filter for the whole predicate.

- [ ] **Step 1: write the failing tests.** `qry_field.st` (`"EXPECT: ok 6"`) and
  `qry_query.st` (`"EXPECT: ok 14"`): the 56 `test_linq.py` behaviours in scope (less
  `group_by`, `join`, `select_many`, computed values, `startswith`/`endswith`: `n/a` or deferred
  rows); immutability (every message answers a new query; the receiver's `explain` unchanged);
  `the cascade does not chain` (`q where: p; take: 5` leaves `q`'s plan unchanged);
  `query keeps its version` (Review Focus 3); `first` of an empty query signals `PBUserError`;
  `PBQuery` does not understand `select:`; `chained where: is AND` (`(q where: a) where: b`
  plans and answers as `q where: a & b`); `where: a Boolean` signals `PBValidationError` whose
  `messageText` is the CR6 text exactly, and so does a two-argument block; mixing rule plans equal `proto_db`'s shape on the same
  predicate (node names, `BlockFilter` for `PythonFilter`).
- [ ] **Step 2:** run `tests/run_tests.sh tests/unit/qry_field.st tests/unit/qry_query.st`.
  Expected: FAIL.
- [ ] **Step 3:** implement, porting `linq.py:169-358`, `600-734`, `906-1189` in scope.
- [ ] **Step 4:** run both, then write the `examples/queries/` programs above, move the programs
  listed under Move out of `pending/`, and run `tests/run_tests.sh
  examples/tutorial/17_indexes.st examples/tutorial/18_queries_and_plans.st
  examples/tutorial/11_indexed_interop.sh examples/queries tests/docs`. Expected: PASS;
  `guide_plans.sh` now compares the printed plan of `reading_plans.st` too, and the chapter 11
  additions run against the venv.
- [ ] **Step 5: bench Q1-Q4.** Run `RUNS=5 bench/run_query.sh Q1 Q2 Q3 Q4`. Expected: `verified`
  (forced-scan rows use the same collection without indexes). Record and replace the T8 markers
  in chapters 17-18 and the guide.
- [ ] **Step 6:** reference ("Queries"), README rows, deviations (`BlockFilter`, no `select:`),
  pending lines, checklist rows, CHANGELOG; commit
  `Queries T8: PBQuery and PBField; chapters 11, 17, 18 and the examples run; Q1-Q4 measured`.

### Task 9: `PBPager`

**Files:**
- Create: `src/protobase/pager.st`.
- Move: `examples/queries/pending/19_ordered_reads_and_pages.st.pending` →
  `examples/tutorial/19_ordered_reads_and_pages.st`.
- Create (F4, D4): `examples/queries/paging.st`, fail-first through `tutorial_chapters_sync.sh`.
- Modify: `bench/*` (Q5).
- Test: `tests/unit/qry_pager.st`, `tests/unit/qry_pager_stability.st`.

**Interfaces:**
- Consumes: Tasks 6-8.
- Produces: `PBPager class >> on: aPlanOrQuery pageSize: n` (`n` ≥ 1, else
  `PBValidationError`); `rows` (Integer), `pages` (Integer), `page: k` (zero-based, as
  `proto_db`, CR7; a negative or non-Integer `k` is `PBValidationError`; past the last page as
  `pager.py` decides) → `Array`, `byRank` (Boolean), `explain` → `PBFrozenDict` with exactly
  `pager` → {`page_size`. `by_rank`} and `plan` → the plan's `explain`; no `portable` (CR7).
  `PBQuery >> pagerSize: n` answers `PBPager on: self pageSize: n`. No `token` (deferred, 3.2).

- [ ] **Step 1: write the failing tests.** `qry_pager.st` (`"EXPECT: ok 8"`): the
  `test_pager.py` behaviours in scope (tokens `n/a deferred: tokens`); for every page k of
  ordered and unordered queries, by rank and materialised, the concatenation of the pages equals
  `asArray`; `byRank` true exactly for the plans of spec 5.7; `writes after the pager do not move
  its pages` (Review Focus 3). `qry_pager_stability.st` (`"EXPECT: ok"`,
  `test_pager_stability.py`): an actor commits inserts and deletes while another reads every
  page of a pager built before; no row shown twice, none skipped.
- [ ] **Step 2:** run `tests/run_tests.sh tests/unit/qry_pager.st tests/unit/qry_pager_stability.st`.
  Expected: FAIL.
- [ ] **Step 3:** implement, porting `pager.py:136-227`.
- [ ] **Step 4:** run both, then move chapter 19's program out of `pending/` and write
  `examples/queries/paging.st`; run `tests/run_tests.sh examples/tutorial/19_ordered_reads_and_pages.st
  examples/queries tests/docs`. Expected: PASS.
- [ ] **Step 5: bench Q5.** Run `RUNS=5 bench/run_query.sh Q5`. Expected: `verified`. Record and
  replace the T9 markers.
- [ ] **Step 6:** reference ("Pagers"), pending lines, checklist rows, CHANGELOG; commit
  `Queries T9: in-process pagers by rank; chapter 19 runs; Q5 measured`.

---

## Phase 4: final verification (spec T10)

### Task 10: Full suite, soaks, the full comparison, documentation complete

A failure found here is fixed in the owning module, fail-first.

- [ ] **Step 1:** run the whole suite with the venv present: `tests/run_tests.sh`. Expected: all
  PASS, no `SKIP` in `idx_*`, `qry_*`, `index_*`, `queries.st` and `tests/docs/guide_plans.sh`. Then the final modes:
  `PENDING_FINAL=1 tests/docs/reference_selectors.sh` (empty pending list),
  `MARKERS_FINAL=1 tests/docs/measured_markers.sh` (no marker left),
  `CHECKLIST_FINAL=1 tests/unit/queries_checklist.sh` (no deferred row).
- [ ] **Step 2: soaks, in parallel** with each other and with Step 4's review, never with Step 3:
  `PBST_PROP_SEEDS=5000 RUN_TIMEOUT=7200 tests/run_tests.sh tests/unit/qry_prop_equals_scan.st`
  and `PBST_PROP_SEEDS=200 tests/run_tests.sh tests/unit/idx_contract.st` (IP16). Expected: PASS; a failure is a seed to reproduce and fix
  fail-first.
- [ ] **Step 3: the full comparison, serially, on a quiet machine:**
  `RUNS=5 bench/run_query.sh` (every workload). Expected: every line `verified`. Record the
  dated run in `docs/deviations.md#performance` ("Queries and indexes": date, machine, load,
  both commits, both binaries, `ldd` of the protoST binary), re-quote every figure in chapters
  17-19 and the guide from this run, and state in chapter 17 R1's outcome as measured.
- [ ] **Step 4:** request the whole-branch review (superpowers:requesting-code-review); fix every
  cheap finding, record the others with a reason.
- [ ] **Step 5: documentation complete (D1, D2, D3, D7).** Re-read the reference against spec
  5.2/5.5 (every public message with arguments, answer, errors); the guide against D2's list and
  against `indexing-framework.rst` and `query-planner.rst`; README and `docs/tutorial/README.md`
  rows (drop "draft"); `gemstone.md` and `soil.md` re-checked; `docs/decisions.md` gets IC1-IC10,
  IQ1-IQ8 and IP1-IP17 (updated where execution changed one), and "Proposals to `proto_db`"
  (IQ6, IQ7: not sent), and CR1-CR10; `docs/not-done.md` gets the deferred items of spec 3.2.
  **CR9:** every "planned for 0.3.0" (or "in 0.3.0", "will") note in `docs/not-done.md` and
  `docs/deviations.md` is rewritten as a present-tense fact of what is shipped or still not
  done; `grep -n "0.3.0" docs/not-done.md docs/deviations.md` shows no future-tense line.
- [ ] **Step 6:** commit `Queries: final verification`; report to the maintainer. Do not merge, tag or push.

---

## Self-review

1. **Spec coverage.** 3.1 items 1-7: Tasks 2, 3, 4a/4b, 5, 6-7, 8, 9. 3.2 deferrals: checklist
   rows (0b), `not-done.md` (10). 3.3 exclusion: Tasks 3, 4a, 5, 6. D1-D7: reference per task and
   Task 10 (D1); Task 0 drafts and Tasks 2, 5, 6, 7 sections (D2); Task 0 and Tasks 8, 9
   (D3, with the chapter programs running in 8 and 9); pending programs moved out in 8 and 9, and
   `examples/queries/{lookups,ranges,compound,merge_indexed,keys,expressions}.st` written in 8
   and `paging.st` in 9 (D4: indexes and lookups, ranges and ordered reads, compound with
   `explain`, paging, a merge onto an indexed root, Python interop in chapter 11; the chapter
   programs alone do not satisfy D4); benches M2 (3), M1 (4a), M3 (4b), P1-P3 (7), Q1-Q4 (8), Q5 (9), full comparison
   (10) (D5); vectors 2, 5, 7 and interop 4a, 4b (D6); Task 10 (D7). 5.3 hook order and blind
   no-ops: 4a; merges 4b; IQ1 4b; 5.4 bytes: 1, 2, 4a; 5.6 ties and IQ4: 7 with IP7/IP8; 5.7: 9;
   5.8 cluster: 4b (simulator round) and M3. 6.1.1: 2; 6.1.2: 4a; 6.1.3: 4b; 6.2: 7; 6.3: 0b.
   7.2 contract: 3 (structure) and 7 (plan equals scan; the `concurrent readers` case of
   `qry_prop_equals_scan.st`, several actors running one plan with identical answers); rank: 6; merges: 4b.
2. **Step scan.** Every test step names its file, its expected count and its cases with the
   spec's values; every code step names its selectors and the `proto_db` lines it ports. The
   bodies are left to the port of the cited lines; IP13 pins the one shape choice.
3. **Type consistency.** `PBKeySpec` (2) is what `name:keySpec:` (3), `supportsOrder:` (6) and
   `PBTerm >> keySpecObject` (5) use; `PBSortKey` (6) is what `PBPlanner` (7) and `PBQuery` (8) build;
   `PBEstimate` (6) is `estimate:`'s answer; `windowFrom:to:` answers an `Array` everywhere;
   `keySpecObject` (3, and 5 on `PBTerm`) is the only selector name answering a `PBKeySpec`; 4b expects
   the extractor's own exception (2).
4. **Review Focus.** Each of the five lines has a named test case in its owning task.
5. **Proportion.** The plan is about the spec's length and holds no method body; the code is the
   port of the cited `proto_db` lines.

Defects of the spec found while planning (fixed in the spec, commit `6680e50`): the checklist
list of 7.1 omitted five test files (301 rows, not about 200); `proto_db` does not name a failing
extractor (the question behind IQ1 misdescribed it; the maintainer then ruled IP2: pass the
exception through, as `proto_db`); the near-tie rule now compares the
two chosen plans' root costs (6.2); an unregistered extractor index answers queries that never
extract (5.4). IP3 was ruled: `keySpec` unchanged, `keySpecObject` new. Left as calls rather than spec edits: IP9 (`execute`
answers an `Array`), IP11 (MessagePack, not JSON), IP15 (term-facing index methods in Task 6).
The pre-flight scan of 2026-11-19 (`.superpowers/sdd/2026-11-18-indexed-queries/preflight.md`,
findings F1-F21, rulings in `progress.md`) is applied above; it adds IP16 (`PBST_PROP_SEEDS`,
F17) and IP17 (the interim merge refusal between 4a and 4b, F1).
