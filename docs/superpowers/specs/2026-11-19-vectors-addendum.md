# Addendum V: vector indexes and vector search (revision 2)

- **Date:** 2026-11-19 (revision 2, after independent review 1, `vectors-addendum-review-1.md`).
- **Status:** RULED; ready to fold into the spec. It extends the approved spec
  `docs/superpowers/specs/2026-11-18-indexed-queries-design.md` after the maintainer's decision of
  2026-11-19: "Vectors: implement them. Scope extension: spec addendum + plan tasks after Task 10,
  following proto_db rc4 VectorIndex/near[]/VectorSearch" (`progress.md`, maintainer decisions,
  item 4). Rulings (section 8): **VQ1** hnsw search refused (`PBNotSupportedError` at the first
  execution of a `VectorHnsw` plan); maintenance, `validate:`, `explain` and planning work.
  **VQ2** the fsum primitive (VP) is specified now and built in protoST only if V8 shows the
  interpreted kernel dominates search time. **VQ3** vectors ship in protoBaseST **0.4.0**, after
  0.3.0 (queries) is released. **Stack:** the phase first moves protoBaseST to protoST 0.14.1 on
  protoCore 3.6.1 (task V-pin). **Execution:** the tasks run to the end without approval stops:
  spec, implementation, tests, documentation, tutorial chapter 20, examples, merge, publication.
- **Reference:** `proto_db` at `v2.0.0rc4` (`8e6127f`), read only through
  `git -C /home/gamarino/Documentos/proyectos/ProtoBase show v2.0.0rc4:<path>`. Every `proto_db`
  citation below is `file:line` at that tag. Paths without a directory are under `proto_db/`:
  `vector.py` is `proto_db/indexing/vector.py`, `vector_backends.py` is
  `proto_db/indexing/vector_backends.py`, `terms.py`, `expressions.py`, `planner.py`, `plans.py`,
  `linq.py` and `cache.py` are under `proto_db/query/`, `base.py` is `proto_db/indexing/base.py`,
  `keyed.py` is `proto_db/indexing/keyed.py`. Documentation and tests are given with their full
  repository path.
- **protoBaseST:** branch `feat/queries` at `2c5cb34` (HEAD moves while Task 10 commits; every
  `src/`, `docs/` and `tests/` line cited here is at `2c5cb34`, and V0 re-greps them before editing).
  **protoST:** citations are at the **v0.14.1** tag (`15157d7`, the pinned stack's protoST); they were
  first read from branch `feat/fraction-bytes-prims` at `af640f1` ("protoST 0.14.0", the `v0.14.0` tag
  `8dd0535` has the identical tree), before the tags existed. V-pin re-checked them: no file or line
  cited in this addendum differs between `af640f1` and `v0.14.1` (v0.14.1 only adds the capped-wait fix
  S43 and the empty-conversions test S44, in `STRuntime`, `future_prims.cpp` and their tests).
  **protoCore:** 3.6.1, no change.
- **Verified while revising (2026-11-19, DEV12, CPython 3.14.0, glibc 2.43):** CPython's
  `x ** 2` against `x * x` and against glibc `pow` (C1); protoST 0.14.0's (a build of the same branch at
  `e90bcc1`, the parent of `af640f1`, whose `--version` still printed 0.13.0) `Float raisedTo: 2`,
  `**`, `squared` and `*` against CPython on a half-way case, and its `String >> asNumber` on
  subnormal and out-of-range texts (C2); `float()` of a signalling-NaN Decimal and of huge
  Integers, and `math.isfinite` on them (C4); a pure-Python port of the MT19937 seeding,
  `getrandbits`, `_randbelow` and both `sample` branches against `random.Random` for seeds 0, 1,
  7, 2^32-1, 2^32, 2^40, 2^64+3 and populations up to 2^33 (I6, 0 mismatches). Scripts and
  outputs are in the session scratchpad, not in the repository. Nothing of protoBaseST was built
  or run; statements about its code come from reading `src/protobase/*.st`. Task sizes (section 7) are
  relative, not a schedule.

Contents: [0. Summary](#0-summary) | [1. Scope](#1-scope) |
[2. Design](#2-design-for-protobasest) | [3. Removing the read-only rule](#3-removing-the-read-only-rule) |
[4. Deviations](#4-deviations-expected) | [5. Tests and conformance](#5-tests-and-conformance) |
[6. Documentation](#6-documentation) | [7. Plan tasks](#7-plan-tasks-v-pin-and-v0-v10) |
[8. Rulings](#8-rulings) | [9. Risks](#9-risks) | [10. Review response](#10-review-response)

---

## 0. Summary

- **In scope:** every part of `proto_db`'s vector feature that does not need a native library:
  the `VectorIndex` atom and its maintenance in every mutator, merge and stale rebuild; the
  `exact` and `ivf_flat` backends, search included; the three metrics; `NearQuery` and `near[]`
  terms (k, threshold, both, metric); `filtered_plan` (k nearest among the elements satisfying a
  predicate); the `VectorSearch` node, its estimates and `explain`; the planner's `near[]` rules;
  the query front end's `near` and its mixing rule; validation; the contract.
- **In scope, without search:** the `hnsw` backend is **maintained** (its persisted state is a
  plain store, list 0) and validated, so a collection holding one becomes writable; a search on it
  is refused exactly as `proto_db` refuses it when `hnswlib` is missing (ruling VQ1).
- **Out of scope:** the `hnswlib` graph (native C++, not persisted, not deterministic in
  `proto_db` itself), numpy screening (an optimisation with the same answer), the process-wide
  derived-structure cache, and the query result cache rows (already deferred by IQ3).
- **On disk:** no new record type, no new field. Node identity with `proto_db` is provable for
  every operation. For IVF training it is provable against `proto_db` running **without numpy**
  (the only training path `proto_db` specifies operation by operation) **on the same host libm**:
  the pure-Python k-means squares with `(a - b) ** 2`, which is libm `pow`, and glibc's `pow` is
  not correctly rounded (section 2.5, step 3). "Byte-identical centroids" means: same history,
  numpy blocked, same libm.
- **protoST:** correctness needs no new primitive. CPython's `math.fsum` is portable with IEEE `+`,
  `-`, `*`, `/` and `sqrt`; Python's `float()` of an Integer or a Decimal maps onto protoST's
  correctly rounded `asFloat` and `String >> asNumber`; the k-means square is protoST's
  `raisedTo:`, which calls the same libm `pow` (2.2). Speed probably needs a primitive; one is
  specified in 2.2.4 and gated on a measurement (ruling VQ2).
- **Stack:** protoST 0.14.1 on protoCore 3.6.1 (task V-pin, gated on the `v0.14.1` tag).
- **Tasks:** V-pin, then V0 to V10, after Task 10 and the 0.3.0 release, plus one conditional
  protoST task (VP). V10 releases protoBaseST 0.4.0.

---

## 1. Scope

Each item states what `proto_db` rc4 does, with its source, and whether this addendum ports it.
The rule (maintainer, 2026-11-19): port everything, except what needs a native library protoST
cannot have; each such exclusion is justified.

### 1.1 Index kind, backends and metrics

| # | `proto_db` rc4 | Source | Status |
|---|---|---|---|
| S1 | `VectorIndex(name, key_spec, dim, metric="cosine", backend="exact", **params)`: an empty index; `key_spec` a `KeySpec` or a path string; `dim` an int >= 1 (bool refused); `metric` validated; backend and params validated | `vector.py:125-158`, `70-79` | **In scope.** |
| S2 | Persisted type name `proto_db.indexing.VectorIndex`; definition fields `name`, `key_spec`, `dim`, `metric`, `backend`, `params` | `vector.py:135-139` | **In scope** (the type is already registered, `indexes.st:854-933`). |
| S3 | Metrics `cosine`, `l2`, `ip` | `vector_backends.py:73`; `terms.py:88-89` | **In scope.** |
| S4 | Backends `exact`, `ivf_flat`, `hnsw`; an unknown name is `ProtoValidationError` | `vector_backends.py:75`, `824-832` | **In scope**, hnsw without search (S9). |
| S5 | Params: the complete validated parameters, a tuple of `(name, value)` pairs sorted by name; unknown names refused | `vector_backends.py:325-333` | **In scope.** |
| S6 | `exact` backend: params `numpy` (bool, default True); brute force; numpy screens in bulk, then every candidate that could matter is re-scored exactly, "so the answer equals brute force bit for bit" | `vector_backends.py:22-27`, `480-524`, `430-471` | **In scope** without numpy: the persisted `numpy` param is kept as written and has no effect, since the screened answer is by construction the exact one (`vector_backends.py:433-439`). |
| S7 | `ivf_flat` backend: params `nlist` (16), `nprobe` (min(4, nlist), <= nlist), `train_iters` (10), `seed` (0), `retrain_growth` (4.0, > 1, stored as float); centroids persisted; store keyed by `(list number, member key)`. `_growth` calls `math.isfinite` on an int, so `retrain_growth=10**400` raises `OverflowError` (`vector_backends.py:319-322`) | `vector_backends.py:566-586`, `28-43` | **In scope**, training included (2.5); the `OverflowError` case is a `PBValidationError` refusal (DV7). |
| S8 | IVF training: deterministic k-means from `seed`, on vectors sorted by their IEEE big-endian bytes (R128), normalised for cosine; numpy path or pure-Python path | `vector_backends.py:527-563`, `644-661` | **In scope: the pure-Python path only** (2.5, deviation DV3). |
| S9 | `hnsw` backend: params `M` (>= 2, 16), `ef_construction` (200), `ef_search` (64), `seed` (0); an hnswlib graph built lazily per process from the store, cached by index oid, never persisted; `deterministic = False`; `ProtoNotSupportedError` when hnswlib is missing, at the first search | `vector_backends.py:44-49`, `751-821`, `290-302`, `342-344`; `docs/source/format-spec.rst:1421-1423` | **Maintenance and validation in scope; search refused** (ruling VQ1). Justification: the graph is hnswlib's (native C++, loaded with numpy, `vector_backends.py:772-788`); it is not part of the format, and `proto_db` itself does not promise the same graph twice (`deterministic = False`, `vector_backends.py:755`). |
| S10 | Valid vector: a tuple or list of exactly `dim` numbers (int, float, Decimal; not bool), each converted with `float()`, finite, with a finite correctly rounded squared norm (`fsum` of `x * x`); anything else (MISSING and None included) goes to `invalid`. An int beyond the float range is invalid (the `OverflowError` is caught, `113-116`); a Decimal beyond it converts to `inf` and is invalid. **A signalling-NaN Decimal is not invalid:** `float(Decimal('sNaN'))` raises `ValueError`, which nothing catches, so `with_added`, `with_removed`, `build`, `near_oracle` and `validate` raise (`vector.py:179`, `185`, `207`, `235`, `112`, `369`, `395`, `419`) | `vector_backends.py:100-122`; `docs/source/format-spec.rst:1425-1430` | **In scope.** The sNaN case is a refusal, `PBValidationError` at the same calls (2.2.2, DV7). protoBaseST can hold such a Decimal (`codec.st:431-432`). |
| S11 | Scores: `ip` = fsum of products; `l2` = minus sqrt of the fsum of squared differences (+inf on overflow); `cosine` = `(fsum(q*v)/|q|)/|v|`, 0.0 when either norm is 0.0 | `vector_backends.py:125-137`, `92-97`; `docs/source/format-spec.rst:1432-1437` | **In scope**, bit for bit (2.2). |

### 1.2 Persistence and maintenance

| # | `proto_db` rc4 | Source | Status |
|---|---|---|---|
| S12 | State: `store` (KeyNode tree, `(list, member key)` -> `(element, count, vector)`), `invalid` (a group as in a key-group index), `total_count`, `centroids` (tuple of vectors), `trained_size`, `member_tokens` | `vector.py:8-22`, `147-158`; `docs/source/format-spec.rst:1411-1423` | **In scope.** The read side exists (`indexes.st:864-893`). |
| S13 | List numbers: 0 for `exact` and `hnsw`; -1 for an untrained IVF index; else the best-scoring centroid (cosine score for cosine, l2 score for l2 and ip), lowest index on ties | `vector_backends.py:76-77`, `353-355`, `588-590`, `606-634`; `docs/source/format-spec.rst:1439-1446` | **In scope.** |
| S14 | Hooks: `with_added` (invalid key to `invalid`, else one more occurrence in the store; a new member may trigger a retrain), `with_removed` (only the member under its own store key; absent element `ProtoValidationError`), `build` (bulk: group, train once, balanced trees), `empty` | `vector.py:165-268` | **In scope.** |
| S15 | Depth: an element with a valid vector is checked with 2 more containers (`STORE_KEY_WRAPPING`) | `vector.py:64-67`, `188-190`, `237`; `keyed.py:190-215`; `docs/source/format-spec.rst:916-925` | **In scope** (`PBMemberKeys checkDepth:` gains the outer count, `keygroups.st:217-244`). |
| S16 | Retraining: when the index first holds `nlist` members, and when members reach `retrain_growth * trained_size` (an int compared with a float, exactly); a retrain rebuilds the whole store in bulk | `vector_backends.py:636-642`; `vector.py:196-199`, `252-268` | **In scope** (2.4 for the comparison). |
| S17 | Node classes: the `invalid` members tree is a KeyNode tree when bulk-built and a CountedKeyNode tree when grown from empty | `vector.py:189`, `244-248`; `keyed.py:220-229`; `docs/source/format-spec.rst:1245-1250` | **In scope** (an identity hazard, 2.11). |
| S18 | Format-3 vector indexes (no `member_tokens`) are rebuilt at the collection's first change, training included | `vector.py:160-163`; `proto_db/collections/base.py:207-219`, `450-454`; `docs/source/format-spec.rst:1381-1391` | **In scope.** |
| S19 | `validate`: AVL invariants, training state, every member under its own key and list with its own vector, positive counts, invalid kept aside, totals, and the stored multiset equal to the elements' | `vector.py:334-425` | **In scope.** |
| S20 | `explain`: base entries plus `dim`, `metric`, `backend`, `params`, `entries`, `vectors`, `members`, `invalid`, and for IVF `lists`, `trained_size` | `vector.py:323-332`; `vector_backends.py:732-734` | **In scope.** |
| S21 | Merges replay the mutators onto the current version (indexes maintained there); cluster: nothing index-specific on the wire | `proto_db/collections/base.py:594-631`; spec 2.7 | **In scope**, through the Task 4b machinery; a retrain can run inside a merge (9, risk RV3). |
| S22 | Derived structures (flat snapshots, IVF lists, hnsw graphs) in a process-wide thread-safe LRU keyed by index oid, released when a space closes | `vector_backends.py:200-272`, `496-503`, `671-683` | **Excluded** (deviation DV4): not needed for correctness; protoBaseST keeps no mutable process-wide cache. |

### 1.3 Terms, plans, planner, front end

| # | `proto_db` rc4 | Source | Status |
|---|---|---|---|
| S23 | `NearQuery(vector, k=None, threshold=None, metric=None)`: non-empty vector of finite numbers stored as floats; k an int >= 1; threshold finite; at least one of k and threshold; metric in `NEAR_METRICS` or None; hashable; a mapping of its fields is accepted. `_finite_number` calls `math.isfinite` before `float()` (`terms.py:92-95`), so a component or threshold that is an int beyond the float range raises `OverflowError` and a signalling-NaN Decimal raises `ValueError`, not `ProtoValidationError`; a Decimal beyond the float range is `ProtoValidationError` (not finite) | `terms.py:92-137` | **In scope**; the two raw errors are refusals with `PBValidationError` (DV7). |
| S24 | `Term(path, "near[]", NearQuery)`; equality and hash by the `NearQuery` value; `matches` raises `ProtoNotSupportedError` | `terms.py:72`, `197-198`, `203-213`, `218-219` | **In scope.** |
| S25 | Threshold semantics: cosine keeps similarity >= t, l2 distance <= t, ip score >= t; k counts members (all occurrences of a member come back); both = the k nearest among those within t; nearest first; ties by member key order | `vector.py:24-30`; `vector_backends.py:5-18`, `140-163` | **In scope.** |
| S26 | 0.1 list syntax: `path "near[]" vector threshold` (cosine threshold query) or `path "near[]" NearQuery-or-mapping`; `to_list` writes the first form for a cosine threshold-only query | `expressions.py:34-35`, `352-356`; `terms.py:259-279` | **In scope.** |
| S27 | `describe`: a `NearQuery` renders as `{"vector", "k", "threshold", "metric"}` | `terms.py:304-325` | **In scope.** |
| S28 | `supports(term)`: `near[]` on the index's key, query metric None or equal to the index's, query vector valid for `dim`; `supports_filtered` = `supports` | `vector.py:272-282` | **In scope.** |
| S29 | `plan(term)` / `filtered_plan(term, where)`: an `IndexPlan` of kind `VectorExact`, `VectorIvfFlat` or `VectorHnsw`, details `backend`, `metric`, and `where`; a residual holding `near[]` is `ProtoValidationError` | `vector.py:289-319`; `vector_backends.py:484`, `570`, `756` | **In scope** (VectorHnsw: plan built, execution refused, ruling VQ1). |
| S30 | Estimates (D30 units). Rows: `members * 0.5` without k, `min(k, members)` with k, halved again with k and threshold. Cost: exact `members * (2 if filtered else 1) + rows + 1`; IVF `len(centroids) + members * fraction * (2 if filtered else 1) + rows + 1`, fraction `nprobe / nlist` when trained else 1; hnsw `min(members, ef * log2(members + 2)) * (2 if filtered else 1) + rows + 1`, `ef = max(ef_search, k or 0)` | `vector_backends.py:377-383`, `520-524`, `723-730`, `815-821`; `plans.py:89` | **In scope**, with Python's arithmetic (2.4): `nprobe / nlist` is one correctly rounded true division, `Estimate` stores both values as floats; the hnsw `log2` goes through `PBCost class >> log2:` (IP7, R2). |
| S31 | IVF search: probe list -1 (when present) plus the `nprobe` best non-empty lists; widen by doubling while fewer than k matching members were found; then rank exactly | `vector_backends.py:663-721` | **In scope.** |
| S32 | `VectorSearch(index, term, where=None)`: validation, `explain` `{"plan": "VectorSearch", "index", "term", ["where"], "estimate", "children": [index plan]}`, estimate of the inner plan | `plans.py:389-436` | **In scope.** |
| S33 | `Filter` refuses a `near[]` term (`ProtoValidationError`) | `plans.py:452-462` | **In scope.** |
| S34 | Planner: a negated `near[]` raises; a `near[]` conjunct without a supporting index raises; one bare `near(k)` with other conjuncts is a filtered kNN (`where` = the rest), refused when no index can restrict its search; several `near[]` conjuncts intersect; a threshold-only `near[]` keeps a post-filter; a `near[]` in a disjunction forces the `Union` (branches without an index path are filtered scans); an order with a `near[]` predicate always sorts | `planner.py:15-26`, `98-135`, `194-261`, `263-275`, `328` | **In scope.** |
| S35 | Front end: `F.v.near(vector, k=, threshold=, metric=)`; with exactly one bare `near(k)` conjunct, Python predicates join the vector plan's residual (R27); a `near[]` inside an OR/NOT holding Python parts raises; `near` on a computed value raises | `linq.py:48-61`, `344-353`, `644-647`, `707-709`, `1003-1008`, `1099-1105` | **In scope** (the OR/NOT case cannot arise in protoBaseST, 2.9). |
| S36 | `near_oracle(elements, key_spec, near_query, metric, predicate)`: the brute-force definition used by the contract | `vector.py:92-122` | **In scope** (tests and the contract). |
| S37 | Query result cache: `NearQuery` keys and `VectorSearch` keys; hnsw not cacheable | `cache.py:36-40`, `121-122`, `210-213`; `vector.py:173-176` | **Deferred with the cache** (IQ3, spec 3.2). |

### 1.4 Documentation, examples, benchmarks in `proto_db`

| # | `proto_db` rc4 | Source | Status |
|---|---|---|---|
| S38 | Tutorial "Vector search" (documents with embeddings, nearest neighbours, `near` with conditions, IVF-Flat recall, limits and choices) | `docs/source/tutorials/vector-search.rst:1-180` | **Ported as chapter 20** (section 6). |
| S39 | Example: exact and IVF collections, `explain`, every answer checked against brute force | `examples/vector_search.py:1-85` | **Ported** as `examples/queries/vector_search.st`. |
| S40 | Benchmark `vector_knn` (exact, ivf_flat) and `vector_knn_hnsw` (isolated), checked against a numpy brute force | `benchmarks/workloads/vector.py:1-132` | **Ported** as workloads VB1-VB5 (5.5); hnsw search refused (DV1). |
| S41 | Framework and planner pages on vectors | `docs/source/indexing-framework.rst:91-92`, `131-137`; `docs/source/query-planner.rst:55-59` | Covered by the guide section (6.3). |

---

## 2. Design for protoBaseST

### 2.1 Modules and classes

One new module, `src/protobase/vectors.st`, imported after `indexes` and before `terms` in
`src/protobase.st` (the module order rule of the plan's Global Constraints); `indexes.st`,
`terms.st`, `plans.st`, `planner.st`, `query.st`, `collections.st` and `keygroups.st` change.
`PBVectorIndex` stays in `indexes.st` (where it is registered with its siblings); its backends and
the numeric kernel live in `vectors.st`, which `indexes.st` imports (so `vectors.st` must not import
`indexes.st`; the backends receive the index as an argument, as `proto_db`'s strategy objects do,
`vector_backends.py:338-383`).

| Class | `proto_db` counterpart | Responsibility |
|---|---|---|
| `PBVectorMath` (class side only) | `vector_backends.py` module functions | `floatOf:`, `canonicalVector:dim:`, `fsum:`, `sumNonNegative:`, `score:query:vector:`, `scoreFloor:threshold:`, `rank:query:metric:k:threshold:`, `normalized:`, `trainingOrderOf:`, `kmeans:nlist:iterations:seed:` (2.2, 2.5). |
| `PBPythonRandom` (class side only) | CPython `random.Random` (used by `_kmeans`) | `sampleRange: n count: k seed: s`: Python's `random.Random(s).sample(range(n), k)`; `bits: k count: m seed: s`: the first `m` values of `random.Random(s).getrandbits(k)` (a test entry point). MT19937 state local to each call (2.5). |
| `PBVectorBackend` and subclasses `PBVectorExact`, `PBVectorIvfFlat`, `PBVectorHnsw` (class side only) | `_Backend`, `ExactBackend`, `IvfFlatBackend`, `HnswBackend` | `backendName`, `kindName` (`'VectorExact'`...), `defaults`, `check:`, `listFor:vector:`, `needsTraining:`, `train:vectors:`, `search:query:k:threshold:eligible:`, `estimate:k:threshold:filtered:`, `explainOf:`. Stateless: every method takes the index. `PBVectorBackend named: aString` is `backend_for`. |
| `PBNearQuery` | `NearQuery` | A frozen value: `vector` (a `PBTuple` of Floats), `k`, `threshold`, `metric`; `=` and `hash` by value with Python's float equality (`0.0 = -0.0`, and both hash alike), because the planner deduplicates conjuncts by equality (`planner.py:141`, `196`); `describe`. |
| `PBVectorIndex` (`indexes.st`, rewritten) | `VectorIndex` | Constructors, readers, hooks, `build:`, `validate:`, `explain`, `supports:`, `supportsFiltered:`, `estimate:`, `plan:`, `filteredPlan:where:`, `class >> nearOracle:keySpec:query:metric:predicate:`. |
| `PBVectorSearch` (`plans.st`) | `VectorSearch` | `index: anIndex term: aTerm where: anExpressionOrNil`; `do:`, `execute`, `explain`, `estimate`. |

`PBIndex` gains the two defaults of `base.py:274-281`: `supportsFiltered:` (false) and
`filteredPlan:where:` (`PBNotSupportedError` with `proto_db`'s text).

### 2.2 Floats and vector math in protoST

#### 2.2.1 What must be bit-identical

Answers and persisted bytes depend on scores (rank order, thresholds, IVF list numbers, k-means).
`proto_db` defines every score with `math.fsum` (correctly rounded, so independent of the order of
the terms) and IEEE `sqrt`, and states it normatively (`docs/source/format-spec.rst:1432-1437`). A
port that sums naively would disagree with `proto_db` in the last bit and, on near ties, return
another neighbour or file a member under another IVF list (which `validate` then reports as
corrupt, `vector.py:372-374`).

#### 2.2.2 The kernel, in pure Smalltalk (the reference implementation)

- **`PBVectorMath class >> floatOf: aNumber`**: Python's `float(x)` for an Integer, a Float or a
  Decimal (the caller has refused Booleans and other classes). One rounding, as in Python:
  - **Float:** itself.
  - **Integer:** `asFloat`. protoST's `asFloat` is correctly rounded for every Integer: a value
    within 64 bits is cast to `double` (an IEEE round to nearest, ties to even), a larger one goes
    through `strtod` on its exact decimal digits (`protoST src/primitives/math_prims.cpp:68-77`,
    `223-228`). Beyond the Float range the result is ±infinity, which is exactly where Python's
    `float(int)` raises `OverflowError` (both round first: `2^1024 - 2^970` overflows in both,
    `2^1024 - 2^971` is `Float fmax` in both). `floatOf:` answers nil there, the caller's
    "overflow" case (`canonical_vector` turns it into "not a vector", `vector_backends.py:113-116`;
    `NearQuery` and `retrain_growth` refuse, S23, S7).
  - **Decimal:** Python's `float(Decimal)` is `float(str(d))`: one correctly rounded conversion of
    the exact decimal value, subnormal results included. The port is the same one rounding:
    a finite Decimal with a zero coefficient answers `0.0` or `-0.0` by its sign (exact, and it
    avoids the parser's out-of-range branch for a zero with a huge exponent); any other finite
    Decimal answers `String >> asNumber` of the text `[-]<coefficient>e<exponent>` (the same value
    as `str(d)`, always in the Float syntax so that a zero exponent does not take the Integer
    branch). That primitive is correctly rounded and subnormal-aware (`std::from_chars`, or
    `strtod_l` in the C locale where `from_chars` is missing), answers ±infinity beyond the Float
    range and ±0.0 below half the smallest subnormal, as Python's `float(str)` does
    (`protoST src/primitives/string_prims.cpp:138-185`, `src/runtime/DecimalDouble.h:37-100`;
    checked on this machine: `'1e-310'`, `'2.5e-324'`, `'1e-320'` and `'1e400'` read as CPython
    reads them). A Decimal beyond the range is ±infinity, not nil: Python gives `inf` there, not
    `OverflowError`. A quiet NaN answers `Float nan`, an infinity `Float infinity` with its sign.
    A **signalling NaN** signals `PBValidationError` with CPython's text, "cannot convert
    signaling NaN to float" (Python's `ValueError`, uncaught by `proto_db`, S10, S23; DV7).
  - **Why not the obvious exact algorithm.** The first draft of this addendum scaled the exact
    rational to a 53-bit significand, rounded, then scaled by powers of two. That rounds twice for
    results below `2^-1022` (`Decimal('1e-310')`): first to 53 bits, then to the subnormal's
    fewer bits. Rounding once, at the precision of the target exponent, is what the parser
    already does.
  - **Checked by an exact oracle.** `vec_math.st` checks, for seeded and adversarial Decimals,
    that the answer `f` is the nearest Float: with the exact value `d asExactFraction` and the
    neighbours of `f`, `|d - f| <= |d - neighbour|`, ties to the even significand, compared
    exactly with protoST 0.14.1's exact Fraction comparison (`fraction_prims.cpp`), besides the
    CPython vectors (5.2): subnormal half-way Decimals, `2^-1074` halves, the largest finite
    Float's half-way neighbour, zero with extreme exponents, `-0`.
  - protoST's `Fraction >> asFloat` is never used: it divides two rounded Floats
    (`protoST lib/kernel/fraction.st:32-33`).
- **`fsum: anArray`**: a line-for-line port of CPython's `math_fsum` (Shewchuk's algorithm with
  the final half-way correction; `Modules/mathmodule.c`), on protoST Floats, whose `+`, `-`, `*`, `/`
  are single IEEE double operations in C++. Its special-value path is ported too: an infinite term
  makes the sum that infinity, `+inf` and `-inf` together, or a NaN term, signal. It signals the
  two errors CPython raises (intermediate overflow; `-inf + inf`) as `PBVectorMath` errors;
  `sumNonNegative:` maps overflow to `Float infinity` as `_sum_nonnegative` does
  (`vector_backends.py:92-97`). `ip` and the cosine dot product are **not** guarded in `proto_db`
  (`vector_backends.py:128`, `136`): an exact sum that overflows propagates Python's
  `OverflowError` out of the query. The port signals there too (a test pins the case; the error
  class differs, DV7).
- **`score:query:vector:`**, **`scoreFloor:threshold:`**, **`rank:query:metric:k:threshold:`**:
  `vector_backends.py:125-163`, operation for operation: the l2 term is `(a - b) * (a - b)` with
  the IEEE difference rounded first (`130`); the squared norms are `fsum` of `x * x` (`120`,
  `132-133`); cosine is divided `(dot / nq) / nv` in that order. The rank order is **nearest
  first; ties by the member key's order key**: the sort key is `(-score, order_key(mk))`
  (`159-160`, `166-167`).
- **Three squares, three spellings.** The scores and the norms multiply (`x * x`); the k-means
  distance squares with Python's `** 2` (2.5, step 3), which is libm `pow`. They are not the same
  function (2.5); each place keeps its own. `squared` is never used: in protoST it is `x * x`
  (`math_prims.cpp:167-171`), a trap for the k-means port.
- **`trainingOrderOf: aVector`**: the big-endian IEEE bytes of the components
  (`vector_backends.py:555-558`), written with `WriteStream >> nextPutFloat64:bigEndian:`
  (`protoST lib/kernel/stream.st:131`) and read back as one unsigned Integer with protoST 0.14.1's
  `ByteArray >> unsignedIntegerFrom:to:bigEndian:` (`lib/kernel/bytes.st:179`). Every vector of one
  index has `dim` components, so the byte strings have equal length and Integer order is exactly
  Python's `bytes` order; one primitive and one Integer comparison replace a byte loop per
  comparison.
- **`normalized:`**: `vector_backends.py:561-563`.

#### 2.2.3 Is a protoST primitive needed?

**For correctness: no.** The kernel above uses only operations protoST already exposes: IEEE
`+ - * /` (protoCore's Float arithmetic is one `double` operation per send,
`protoCore core/Integer.cpp:322-323` for `+`, `472-474` for `/`), `sqrt` (`std::sqrt`,
`protoST src/primitives/math_prims.cpp:109`), `raisedTo:` on a Float (libm `pow`, `281-316`),
`asFloat` and `String >> asNumber` (2.2.2). Neither protoST's nor protoCore's CMake sets
`-ffast-math`, `-Ofast` or `-march` flags, so no contraction or reassociation can enter
between sends. **A self-test pins this**, so that a later build flag cannot break it silently:
`vec_math.st` runs Shewchuk's error-free transformations on cases whose low part is non-zero
(`TwoSum` of `1e16` and `1.0`), `-0.0` sums and products, subnormal sums, products that are exact
half-way cases, `sqrt` of perfect squares and of `2`, and the half-way `raisedTo: 2` case of 2.5,
each compared by its bytes with CPython's result.

**For speed: probably, but unmeasured.** An exact search touches every member: `dim` products and
an fsum per member per query, each a loop of interpreted sends with a few partials. protoBaseST's
key-group trees already run 12 to 31 times slower than `proto_db`'s (`docs/deviations.md`, "AVL
operations") and `proto_db` itself scores in bulk with numpy. No figure exists; V1 measures the
kernel alone (bench VB0) and V8 the searches. Ruling VQ2 decides with that measurement.

#### 2.2.4 The primitive, specified (a protoST change; protoCore unchanged)

Built only under ruling VQ2 (V8's measurement), as task VP in the protoST repository:

| Selector (class side of `Float`) | Semantics | Errors |
|---|---|---|
| `Float fsum: aSequence` | CPython's `math.fsum` of the Floats of `aSequence` (an Array or a `PBTuple`-like sequence of Floats; an Integer element is refused so that every conversion stays explicit in Smalltalk) | `Error` 'fsum: intermediate overflow' and 'fsum: -inf + inf', as CPython's `OverflowError` and `ValueError` |
| `Float fsumOfProducts: a with: b` | `fsum(a_i * b_i)`, each product the IEEE double product | as above; sizes differ: `Error` |
| `Float fsumOfSquaredDifferences: a with: b` | `fsum((a_i - b_i) * (a_i - b_i))`, difference and product each rounded | as above |

Constraints: the translation unit is compiled with `-ffp-contract=off` (a fused multiply-add would
break the error-free transformations Shewchuk's algorithm relies on, and would change the rounded
products); results are checked against the same CPython vectors as the Smalltalk kernel, which stays
in protoBaseST as the test oracle and the fallback when the primitive is absent (a feature probe at
module load, not a version check, so the protoST floor stays 0.14.1). Expected gain: unknown until
VB0 and V8 report.

**What the primitive cannot serve.** `fsumOfSquaredDifferences` multiplies, so it serves the l2
score and nothing else: the k-means distance squares with `** 2` (libm `pow`), and replacing it by
this primitive would change centroids on half-way cases (2.5, step 3). k-means keeps the Smalltalk
loop of `raisedTo: 2` terms and `sumNonNegative:`; a fourth selector for it is not specified,
because training is not on the query path.

### 2.3 `PBVectorIndex`

**Constructors** (CR3 style: one primitive form, conveniences named):

```smalltalk
PBVectorIndex name: 'by_vec' keySpec: (PBKeySpec path: 'vec') dim: 8
    metric: 'cosine' backend: 'exact' params: nil.                 "the primitive form"
PBVectorIndex name: 'by_vec' keySpec: (PBKeySpec path: 'vec') dim: 8.    "cosine, exact"
PBVectorIndex name: 'by_vec' keySpec: spec dim: 8 metric: 'l2'.
PBVectorIndex name: 'by_vec' path: 'vec' dim: 8 metric: 'l2'.            "path convenience"
PBVectorIndex name: 'ivf' keySpec: spec dim: 8 metric: 'cosine' backend: 'ivf_flat'
    params: (Dictionary new at: 'nlist' put: 16; at: 'nprobe' put: 4; yourself).
```

`params` is nil (the defaults) or a `Dictionary` / `PBFrozenDict` of String -> value; it is
validated and completed as `normalize_params` does (`vector_backends.py:325-333`) and stored as
`proto_db` stores it: a `PBTuple` of `(name, value)` `PBTuple`s sorted by code point (`'M'` before
`'ef_construction'`), `retrain_growth` as a Float (`vector_backends.py:319-322`). The inherited
`name:keySpec:` signals `PBValidationError` (a vector index needs `dim`). Field order on write is
`persistedFields` (`indexes.st:864-866`), which matches `vector.py:146-158`.

**Validation order.** The checks run in `proto_db`'s order, so that the first error a bad
definition raises is the same: the name and key spec (the inherited `PBIndex` checks,
`vector.py:145`), `dim` (`148`, `_check_dim`, `70-73`), `metric` (`149`), `backend` (`150`), unknown
parameter names (`normalize_params`, `vector_backends.py:328-331`), then the backend's own checks in
the order its dictionary literal evaluates them: `exact` `numpy` (`490`); `ivf_flat` `nlist`,
`nprobe`, `nprobe > nlist`, `seed`, `train_iters`, `retrain_growth` (`577-586`); `hnsw` `M`,
`M >= 2`, `seed`, `ef_construction`, `ef_search` (`763-770`). A test builds definitions with two
faults each and checks which one is reported.

**Readers:** the existing `dim`, `metric`, `backend`, `params`, `centroids`, `trainedSize`,
`storeEntries` (`indexes.st:868-893`), plus `paramAt:`, `memberCount` (the store root's `count`,
`vector.py:327`), `invalidCount`.

**Hooks**, each a port of its Python function, answering a new unsaved version through `_with:`:
`withAdded:` (`vector.py:183-199`), `withRemoved:` (`201-225`), `empty` (`165-168`), `build:`
(`227-263`, with `_withMembers:` and `_retrained`, `252-268`). `withReplaced:with:` stays the
inherited remove-then-add (`base.py:283-285`). `hasMemberTokens` exists.

**Validation:** `validate:` ports `vector.py:334-425` (`_check_centroids`, `_check_store`,
`_check_invalid`, the multiset), with `PBCorruptionError` and `proto_db`'s texts.

**Explain:** a `PBFrozenDict` with `index`, `kind` (`'VectorIndex'`, CR4), `key`, then `dim`,
`metric`, `backend`, `params` (a `PBFrozenDict` of the pairs), `entries`, `vectors`, `members`,
`invalid`, and the backend's entries (`vector.py:323-332`).

### 2.4 Backends

Each backend class is a port of its Python class, with these specifics:

- **`PBVectorExact`** (`vector_backends.py:480-524`): `search:...` ranks every entry of the store,
  restricted to the eligible ones, with `PBVectorMath rank:...` (the numpy-free path,
  `vector_backends.py:516-517`). No snapshot cache (DV4): entries are read from the store tree on
  each search, in key order, which is the order `iter_entries` gives (`189-197`).
- **`PBVectorIvfFlat`** (`566-734`): `listFor:vector:` scores every centroid exactly (the numpy
  screen of `618-628` only skips centroids that cannot win, so the result is the same);
  `needsTraining:`, `train:vectors:` (2.5), `probeOrder:query:`, and `search:...` port `663-721`.
  Without the per-version `_lists` grouping (`671-683`), each probed list is read by an order-key
  range over the store (`list_bounds`, `183-186`, with `PBAvl keyDo:over:fromOrderKey:...`), and
  "is list j non-empty" (the `j in lists` filter of `688`, which decides how many lists `nprobe`
  counts) is one bounded probe of the same range. Same lists, same order, same answer.
- **`PBVectorHnsw`** (`751-821`): `check:`, `estimate:...` and `listFor:` (0) are ported; `train:`
  answers an empty tuple. `search:...` signals `PBNotSupportedError` naming the index and saying
  that the hnsw graph needs `hnswlib`, which protoST cannot load, and to use `exact` or `ivf_flat`
  (ruling VQ1; the counterpart of `load_hnswlib`'s error, `vector_backends.py:290-302`, raised at
  the same moment: the first execution of the plan, never at planning; `plans.py:419`,
  `vector.py:309-312`, `tests/unit/test_vector_index.py:520-531`).
- **Estimates and the retrain test, in Python's arithmetic** (S30, S16). Python mixes ints and
  floats; the port evaluates each expression in Python's order with the same conversions, so the
  Floats are equal:
  - `nprobe / nlist` (`vector_backends.py:727`) is Python's true division of two ints, one correctly
    rounded result. In protoST `Integer / Integer` answers a `Fraction`, and `Fraction >> asFloat`
    rounds twice for large terms; the port writes `nprobe asFloat / nlist asFloat`, which is the
    same single rounding because both are exact Floats (they are far below 2^53), then
    `1.0 min: that`.
  - `members * FILTER_SELECTIVITY`, `members * fraction * 2`, `len(centroids) + touched + rows + 1`
    and `ef * log2(members + 2)` are evaluated left to right, an Integer meeting a Float converted
    exactly (every count is below 2^53), each operation one IEEE rounding (`378-383`, `520-524`,
    `723-730`, `815-821`). `Estimate` stores rows and cost as floats (`plans.py:89`): the port's
    `PBEstimate` answers Floats for vector plans too, even where every term was an Integer.
  - `members >= retrain_growth * trained_size` (`vector_backends.py:642`): the product is a Float
    (`retrain_growth` is stored as a Float, `319-322`); Python compares an int with a float exactly.
    The port writes `members asFloat >= (growth * trainedSize asFloat)`: a member count below
    2^53 converts exactly, so the comparison is Python's exact one without depending on how
    protoST compares mixed operands; the bound is stated in a comment.

### 2.5 Determinism

| Backend | `proto_db` | protoBaseST |
|---|---|---|
| `exact` | Deterministic: answers are exact scores with ties by member key (`vector_backends.py:5-10`, `147-163`). | The same function; the same answer for the same stored elements, in both implementations, on the same database (member keys of atoms are their oids). |
| `ivf_flat` | Deterministic given the training vectors and `seed` (R128: training sorts the vectors by value, `vector_backends.py:650-655`); `_kmeans` takes numpy when it is importable and pure Python otherwise (`527-552`), and the two "may give slightly different centroids" (`docs/source/format-spec.rst:1455-1456`). The pure path squares with libm `pow` (step 3), so its centroids also depend on the host's libm. | Ports the **pure-Python path** exactly, with the same libm `pow`, so centroids equal `proto_db`'s without numpy, bit for bit, on the same host libm (DV3). |
| `hnsw` | Not deterministic (`deterministic = False`, `vector_backends.py:755`; graph built per process by hnswlib with `random_seed`, `780-786`); nothing random is persisted. | Nothing to reproduce: no graph, no random levels; the store is deterministic (list 0). |

The IVF training path, reproduced step by step:

1. Training data: the members' vectors sorted by `trainingOrderOf:` (`vector_backends.py:655`),
   normalised for cosine (`656-657`).
2. Initial centroids: `random.Random(seed).sample(range(len(vectors)), nlist)`, sorted
   (`vector_backends.py:529-530`). `PBPythonRandom class >> sampleRange:count:seed:` ports
   CPython's `Modules/_randommodule.c` and `Lib/random.py` (3.14), each point pinned by vectors:
   - **Seeding** (`random_seed`, `init_by_array`): the key is the 32-bit words of `abs(seed)`,
     least significant word first (`_PyLong_AsByteArray` little-endian); **seed 0 is a key of one
     zero word** (`keyused = 1`), not an empty key; `init_genrand(19650218)` first, then the two
     mixing loops of `init_by_array` over `max(624, keyused)` and 623 steps, `mt[0] = 0x80000000`.
   - **`genrand_uint32`**: the twist of all 624 words when the index reaches 624, then the
     tempering shifts and masks.
   - **`getrandbits(k)`**: 0 for k = 0; for k <= 32, `genrand_uint32() >> (32 - k)`; for k > 32,
     `ceil(k / 32)` words drawn least significant first, the last one shifted right by
     `32 - (k mod 32)` when k is not a multiple of 32. The multi-word path is ported, not refused:
     a population of 2^32 or more members draws through it (checked against CPython at 2^33).
   - **`_randbelow_with_getrandbits(n)`**: `k = n.bit_length()` (`Integer >> highBit` in protoST),
     redraw `getrandbits(k)` while the result is >= n.
   - **`sample`**: both branches, the pool (`n <= setsize`) and the selection set, chosen by
     `setsize = 21`, plus `4 ** ceil(log(3k, 4))` for k > 5. Python's `math.log(x, base)` is
     `log(x) / log(base)` with libm `log`, as protoST's `log:` is
     (`protoST src/primitives/math_prims.cpp:121-131`); `3k` is never a power of 4, so `ceil` sees no
     exact integer.
   - **Integer range.** The seeding products (`1812433253 * x`, `1664525 * x`, `1566083941 * x`) reach
     2^63, beyond protoCore's SmallInteger range, so they run as LargeIntegers and every step is
     reduced with `bitAnd: 16rFFFFFFFF`, as the C code's `uint32_t` arithmetic is. This is correct and
     slow; it runs once per training, never per query.
   protoST's own `Random` is a 32-bit LCG (`protoST lib/random.st:1-10`, `lib/README.md:58`) and
   cannot be used.
   **Immutability:** the generator state (624 words and an index) is an `Array` local to the one
   method that draws the sample, never stored in an instance variable, so the rule of
   `tests/unit/values_immutable.st` holds (the builders of `PBKeyGroupIndex >> build:` use the same
   local-state pattern).
3. Lloyd iterations, `train_iters` times (`vector_backends.py:544-551`): each vector to the
   centroid of least `sumNonNegative:` of the terms `(a - b) raisedTo: 2`, ties to the lowest
   index; sums accumulated in data order with plain IEEE `+` (not fsum: the Python code adds
   sequentially, `550`), each centroid `sum / count` (a Float divided by an Integer below 2^53:
   one rounding, as Python's), an empty cluster keeping its centroid.
   - **Why `raisedTo: 2` and not `*`.** The Python term is `(a - b) ** 2` (`548`). For a float,
     CPython's `**` calls libm `pow` (`Objects/floatobject.c`, `float_pow`), and glibc's `pow` is
     not correctly rounded. Measured on DEV12 (CPython 3.14.0, glibc 2.43): of 200,000 odd integers
     `x` drawn from [2^26, 2^27), the 117,197 above 2^26.5 have 54-bit squares, each an exact
     half-way case between two Floats; `x ** 2` differed from `x * x` on 55,729 of them, and
     `x * x` was the correctly rounded square every time; for 1,000,000 uniform doubles
     in [-1e3, 1e3] they differed 845 times; `x ** 2` and `ctypes` `libm.pow(x, 2.0)` differed 0
     times in 300,000. A port that multiplies would pick another nearest centroid on near ties,
     and the centroids and list numbers would not be byte-identical.
   - **protoST.** `Float >> raisedTo:` with an Integer exponent takes libm `pow` (`std::pow` of the
     two values as doubles; the exact repeated-multiplication path is only for an Integer receiver,
     `protoST src/primitives/math_prims.cpp:281-316`); `**` is `raisedTo:`
     (`lib/kernel/number.st:89-90`). Checked: `130492547 asFloat raisedTo: 2` and `** 2` answer
     `1.702830482254721e16`, as CPython's `**`; `*` and `squared` answer `1.7028304822547208e16`,
     as CPython's `*`.
   - **Pinned.** `vector_math.st` carries half-way cases (odd 27-bit integers, negative
     differences, which CPython squares as `pow(|x|, 2)` in `float_pow` and protoST passes to
     `pow` with their sign, values near the overflow and underflow thresholds) computed by
     CPython's `**`,
     compared by their bytes, so that a future integer-exponent fast path in protoST (`x * x` for
     an exponent of 2) fails loudly instead of changing centroids.
   - **Overflow.** CPython's `**` raises `OverflowError` when the square overflows; the term is
     inside the generator `_sum_nonnegative` consumes, so the error is caught there and the
     distance is `inf` (`92-97`). libm `pow` answers `inf`, and the ported `fsum` answers `inf` for
     non-negative terms holding an infinity (the special-value path, 2.2.2). Same distance, so the
     same tie rule applies (lowest index among infinite distances).
   - **Underflow.** CPython's `float_pow` checks `errno` after `pow` (`_Py_ADJUST_ERANGE1`), which
     clears `ERANGE` only when the result is exactly `0.0`; a non-zero subnormal square returned
     with `ERANGE` set would raise `OverflowError` (then caught by `_sum_nonnegative`, giving a
     distance of `inf`, not the small one). Underflow is harmless here only because glibc's `pow`
     does not set `ERANGE` for such squares: 300,000 squares of values in [1e-170, 1.5e-154]
     raised nothing (coordinator's re-review run, CPython 3.14.0, glibc 2.43). protoST's
     `raisedTo:` ignores `errno` and answers the subnormal. So the two agree on this host, and a
     libm that sets `ERANGE` on a subnormal `pow` result would make `proto_db` and the port
     disagree: part of RV7, pinned by subnormal squares in `vector_math.st`.
   - **Host dependence.** `proto_db`'s pure-path centroids are a function of the host's libm `pow`:
     another libm (musl, Apple's, Microsoft's) may round differently, for `proto_db` against itself
     as for the port. Identity is claimed and tested on one host, both sides using its libm (RV7).
4. Cosine: centroids normalised again (`659-660`); stored as a tuple of tuples of Floats (`661`).

Which vectors a retrain sees (the members at the threshold) and when it happens depend on the
operation history (`vector_backends.py:30-37`); the interop tests replay the same history.

### 2.6 Terms and expressions

- `PBNearQuery class >> vector: aSequence k: anIntegerOrNil threshold: aNumberOrNil metric: aStringOrNil`
  and the conveniences `vector:k:`, `vector:threshold:`, `vector:k:threshold:`. Validation and texts
  port `terms.py:92-137` (a component is converted with `PBVectorMath floatOf:` after the finite and
  type checks of `_finite_number`, `92-95`; a Boolean is refused). Python's raw errors there are
  refusals, `PBValidationError` with CPython's text (DV7): a component or threshold that is an
  Integer beyond the Float range ("int too large to convert to float", Python's `OverflowError`
  from `math.isfinite`), and a signalling-NaN Decimal ("cannot convert signaling NaN to float",
  `ValueError`). A Decimal beyond the Float range is not finite: `proto_db`'s own
  `ProtoValidationError` text.
- `PBTerm path: 'vec' op: 'near[]' value: aPBNearQueryOrMapping`: the refusal at
  `terms.st:231-232` goes; `'near[]'` joins `PBTerm class >> operators` (and so the "Unknown
  operator" list, `terms.py:86`); the value is a `PBNearQuery` (a `Dictionary` or `PBFrozenDict`
  with only `vector`, `k`, `threshold`, `metric` is converted, `terms.py:128-137`); equality and
  hash by the `PBNearQuery` (`terms.py:203-213`).
- `matches:` of a `near[]` term signals `PBNotSupportedError` with `terms.py:219`'s text; so does
  `evaluate:` of any expression holding one (`expressions.py:20-21`).
- `PBExpression compile:` reads both list forms (`expressions.py:352-356`); `asList` writes
  `terms.py:273-276`'s forms; `describe` renders the query as `terms.py:323-325` does.

### 2.7 Plans

- **`PBIndexPlan`** of kind `'VectorExact'`, `'VectorIvfFlat'` or `'VectorHnsw'`, built through a
  `PBIndexPart` with details `backend`, `metric` and, when filtered, `where` (`vector.py:302-319`);
  no rank access (`proto_db` offers none for vector plans; `window` answers nil), estimate from the
  backend (S30).
- **`PBVectorSearch index:term:where:`**: the checks and texts of `plans.py:402-421`;
  `do:` and `execute` delegate to the inner plan; `explain` and `estimate` as `plans.py:427-436`.
- **`PBFilter`** refuses a `near[]` term with `plans.py:459-462`'s text.

### 2.8 Planner

`planner.st` gains the rules its header says it left out (`planner.st:3-5`), each ported line by
line: the negated-`near[]` refusal in `normalize:` (`planner.py:114-116`); `_hasNear:` and
`_isKnn:` (`129-135`); the forced conjuncts, `filteredKnn:rest:` and the Intersect of several
searches in `conjunction:requireIndex:` (`194-234`); the `near[]` branch of `access:` (`239-241`);
the forced `Union` (`250-261`); no ordered index scan under a `near[]` predicate (`268`). Texts of
every `ProtoNotSupportedError` are `proto_db`'s. `PBPlanner class >> _consults:` (`planner.st:156-159`)
stops excluding `PBVectorIndex` (opaque indexes stay excluded). Tie-breaking, cost order and index
order are already `proto_db`'s.

### 2.9 Front end

- `PBField >> near: aVector k: anInteger`, `near:threshold:`, `near:k:threshold:`,
  `near:k:threshold:metric:` (nil allowed for k, threshold, metric), and `near: aPBNearQuery`
  (`linq.py:644-647`).
- The mixing rule of R27 (`linq.py:53-58`, `996-1008`, `1099-1105`). It applies only to the
  conditions of the **leading run** of `where:` and `orderBy:` steps, before the first window step
  (`offset:`, `limit:`) or any other step: `plan` collects predicates only while the steps are
  `where` or `order` (`996-1001`). When the pure part of those conditions has exactly one conjunct
  holding `near[]` and it is a bare `near[]` term with k, each block among those leading `where:`
  steps becomes a `PBBlockPredicate` conjunct of the condition handed to the planner (so it joins
  `PBVectorSearch`'s `where`), instead of a `BlockFilter` on top. A `where:` after a window step
  filters the window's result, as it does today.
- `linq.py:344-353` (`near[]` inside an OR/NOT holding a Python part) has no protoBaseST case:
  `&`, `|` and `not` take expressions only and a block enters only through `where:` (CR5), so such
  a condition cannot be built. Recorded in the checklist row, not as a deviation.

### 2.10 Collections, merges, stale indexes, cluster

- `PBIndexedCollection >> _checkWritable:` (`collections.st:700-723`) refuses only index atoms
  that are not `PBIndex` (opaque kinds); the `PBVectorIndex` clause goes. This lands in V5, once
  every backend is maintained (exact and hnsw in V3, ivf_flat in V4); until then the collection
  refusals stand, which is why V3 and V4 prove identity at the index level (5.2).
- `PBIndexSet >> rebuiltStale:` rebuilds a format-3 vector index by `empty build:` like any other
  (S18); for IVF that includes a training run.
- `rebaseOnto:` and the publisher's merge (Task 4b) need nothing vector-specific: the replayed
  mutators maintain the current version's vector indexes. A replayed add can trigger a retrain; in
  a cluster that k-means runs in the round's build under the cluster-wide permission (RV3).
- Cluster wire: nothing changes (spec 5.8).
- `PBMemberKeys class >> checkDepth:memberKey:index:` (`keygroups.st:217-244`) gains an `outer:`
  count (`keyed.py:190-215`); its comment that protoBaseST "never writes a vector index" goes.

### 2.11 On-disk format and node identity

No new record type and no new field (`docs/source/format-spec.rst:1408-1456`). The bytes are equal
when four things are equal, each covered by an interop test (5.2):

1. **Keys.** Store keys are `PBTuple`s `(list number, member key)`, ordered by
   `store_key_okey` (`vector_backends.py:178-180`), i.e. by `PBKeys orderKey:` of that tuple; the
   member key and its order key are the existing `PBMemberKeys` ones.
2. **Values.** `(element, count, vector)` with the vector a `PBTuple` of Floats (written as
   float64), centroids a `PBTuple` of such tuples, `params` as in 2.3.
3. **Tree shapes and node classes.** The rule is `proto_db`'s `key_put`: a new node has **the
   class of the existing root**; the `node_class` argument is used **only when the tree is
   empty** (`proto_db/collections/avl.py:528-540`; protoBaseST's `keyPut:` already does this,
   `avl.st:900-906`). So:
   - the store: incremental changes use `keyPut:`/`keyRemove:` with `PBKeyNode`
     (`vector.py:194-196`, the `key_put` default); `build:` and retrains use
     `PBAvl keyFromSortedOrderKeys:nodeClass: PBKeyNode` (`vector.py:252-263`);
   - the `invalid` members tree: `build:` makes a `PBKeyNode` tree (`key_from_sorted_okeys`,
     `vector.py:244-248`); `group_add` passes `CountedKeyNode` (`keyed.py:220-229`), which takes
     effect only on an empty tree. An index built with invalid elements and then given another
     invalid one **stays a KeyNode tree**; an index built without invalid elements grows a
     CountedKeyNode tree from its first invalid one. Both histories are identity cases
     (`vector_index_identical.sh`, 5.2). The existing `PBKeyGroups` builders must not be reused for
     the bulk case without that class (`docs/source/format-spec.rst:1245-1250`).
4. **Hook order** in the mutators: already `proto_db`'s (Task 4a).

IVF centroids are part of the bytes. They are equal to `proto_db`'s only when `proto_db` trains
without numpy, on the same host libm (2.5); the format leaves training to the writer
(`docs/source/format-spec.rst:65`, `1448-1456`), so an index trained by either side is valid for
the other.

---

## 3. Removing the read-only rule

### 3.1 Rulings and calls that change

| Item | Today | After this addendum |
|---|---|---|
| IQ5 (spec 9.2) | "Vector and unknown index kinds keep their collection read only." Approved. | **Narrowed:** unknown (opaque) index kinds keep their collection read only; vector indexes are maintained. Recorded as ruling `IQ5a` (2026-11-19) superseding IQ5 for vectors; IQ5's row stays with a pointer. Effective in V5. |
| IC2 (spec 9.1) | Vector and unknown kinds read only. | Unknown kinds only. |
| Spec 3.3 | "Excluded: vector indexes and vector search." | Replaced by a pointer to this addendum (vectors in scope; only the hnsw graph excluded, its search refused, VQ1). |
| `_checkWritable:` (`collections.st:700-723`) | Refuses `PBVectorIndex` and opaque atoms. | Refuses opaque atoms only (V5). |
| `PBVectorIndex` (`indexes.st:854-933`) | Every hook `PBNotSupportedError`; `supports:` false; `explain` refused. | Implemented (2.3). |
| `PBTerm` (`terms.st:231-232`) | `'near[]'` refused at build. | Accepted (2.6). |
| `PBPlanner class >> _consults:` (`planner.st:156-159`) | Skips `PBVectorIndex`. | Consults it. |
| Plan Global Constraints, "Refuse, never diverge" (plan lines 43-44) | Names "a vector index" and "`near[]`" as refusals. | Names an unknown index kind, an unregistered extractor, an hnsw search, and a value `proto_db` itself fails on with a raw Python error (DV7). |

### 3.2 Spec sections to update (`2026-11-18-indexed-queries-design.md`)

Lines at `2c5cb34`: header "Scope in one line" (lines 7-9); 2.1 rows "Defaults ... `filtered_*`
serve vectors only" (100) and `VectorIndex` (119); 2.4 operator row (153); 2.5 rows `near[]` rules
(173) and `VectorSearch` (181); 3.1 item 4 (219); 3.3 (239-253, rewritten); 5.1 "Refuse, never
diverge" (287-288); 5.2 rows `PBVectorIndex` (309) and `PBIndexedCollection` (311); 5.3 "Stale
indexes" (356-358) and "Merges" (367-368); 5.4 "Rule for what cannot be maintained" (413-414);
**5.6 near ties (503-507: the IP8 near-tie rule now also covers the hnsw estimate's `log2`, DV6)**;
**6.2 the generator's self-check (594-596: "each recorded result equals a scan" cannot hold for a
`near[]` case, which a scan refuses; for those the check is `near_oracle`, and for a partial IVF
probe it is the rule of 5.3 here)**; 6.3; 7.1 (622-623, `test_vector_index.py` no longer an
excluded row); **7.3 (644-679: workloads VB0-VB5 of 5.5)**; 8.1 deviations bullet (689-690); 8.2
chapter 12 note (710-711) and a new chapter 20 row; 9.1 IC2 (729); 9.2 IQ5 (749) and the new
rulings IQ5a and VQ1-VQ3; 10.1 R1 (vector maintenance cost) and R2 (the hnsw estimate also uses
`log2`); **10.2 (793-799: what protoST lacks: nothing for correctness, but the port depends on
CPython's MT19937 seeding and sampling, ported in Smalltalk, and on the host's libm `pow`, shared
with CPython; the fsum primitive VP is conditional)**; **11 (808 onward: the V-pin and V0-V10
rows)**.

### 3.3 Plan sections to update (`2026-11-18-indexed-queries.md`)

Lines at `2c5cb34`: Goal (line 8, "Vector indexes and vector search are excluded"); Spec line (30,
"less ... the vector parts"); Global Constraints (43-44); Task 0b statuses (`n/a excluded: vector`
rows become `deferred V<n>`, 5.4); the Task 4b, 5, 6 and 7 texts that state the refusal (555, 614,
633, 738) get a one-line "superseded by Addendum V" note (the tasks are done; their text records
history); a new "Phase 5: vectors (Addendum V)" with tasks V-pin and V0-V10 (section 7). V0
re-greps `vector` and `near[]` in the plan before editing, since Task 10 may move these lines.

### 3.4 Code comments, documentation and tests to update

Lines at `2c5cb34`; V0 re-greps `vector`, `near[]`, `hnsw` and `IQ5` in each file first.

- **Code comments:** `indexes.st` header (lines 3-21, 65, 82-84) and the `PBVectorIndex` section
  (854-933); `collections.st` (103-110, 160, 296-298, 572, 700-709, 774); `terms.st` (4, 18, 204,
  218-232); `plans.st` (3-5); `planner.st` (3-5, 38-43, 156-159, 251, 275); `keygroups.st`
  (217-222).
- **Documentation:** `docs/queries.md` (128-132, 362, 801, and a new section, 6.3);
  `docs/reference.md` (42, 240, 289, 1159-1160, 1183, 1187, 1240, and new sections);
  `docs/deviations.md` (112, 219, the rows at 957-958, the "Unknown operator" note at 1008, new
  entries, a "Vectors" performance subsection); `docs/not-done.md` (19-20, 125); `README.md` (172,
  226, the tutorials table; the Requirements table in V-pin); `docs/tutorial/04-collections-and-queries.md`
  (98-115) and `examples/tutorial/04_collections_and_queries.st` (13); `docs/tutorial/12-refusals.md`
  (72-74); `docs/tutorial/17-indexes.md` (197-199); `docs/tutorial/README.md` (the chapter table);
  `examples/queries/pending/README.md` (the pending table); `docs/decisions.md` (section 5: VQ1-VQ3
  in V0, IQ5a in V5); `CHANGELOG.md` (a 0.4.0 section; the released history stays as written).
- **Tests whose expectations flip:** `tests/unit/indexed_refusal.st` (uses the `hnsw` root as its
  read-only fixture, lines 3, 7, 12, 27, 40-47: it needs an opaque-index fixture instead);
  `tests/unit/idx_merge.st` case (8) (lines 17, 137-144); `tests/unit/idx_keygroups.st`,
  `qry_terms.st`, `qry_expressions.st`, `qry_planner.st`, `qry_index_plans.st` (their
  vector-refusal cases); `tests/interop/py_term_cases.py` (its `near[]` refusal case);
  `tests/unit/queries_checklist.tsv` (41 `excluded: vector` rows, 5.4).

---

## 4. Deviations expected

| # | Deviation | Reason | Cost |
|---|---|---|---|
| DV1 | **hnsw search is refused** (`PBNotSupportedError` at the first execution of a `VectorHnsw` plan); maintenance, `validate:`, `explain` and planning work. `proto_db` answers it when `hnswlib` is installed and refuses it the same way when it is not (`vector_backends.py:290-302`; `tests/unit/test_vector_index.py:520-531`). | The graph is hnswlib's (native C++); it is not part of the format and `proto_db` does not reproduce it either (`vector_backends.py:755`). | A program querying an hnsw index from protoST gets an error; the index can be changed and merged. (Ruling VQ1.) |
| DV2 | The `exact` backend's `numpy` parameter is kept and written but has no effect. | Numpy screening is an optimisation whose result is, by construction, the exact answer (`vector_backends.py:22-27`, `433-439`). | None on answers; only speed. |
| DV3 | IVF training is the pure-Python k-means path; `proto_db` with numpy installed trains with numpy (`vector_backends.py:531-543`). | Only the pure path is specified operation by operation; numpy's results depend on its BLAS. The format leaves centroids to the writer (`docs/source/format-spec.rst:65`, `1448-1456`). | **On one stored database both sides answer identically**: list numbers, probes and rankings are computed exactly from the stored centroids, whoever trained them (5.3). What differs is **the centroids after a retrain of the same history**: protoBaseST's equal those of `proto_db` without numpy on the same host libm (2.5), and may differ in the last bits from those of `proto_db` with numpy. Both are valid for the other side, so `validate` passes either way. |
| DV4 | No derived-structure cache (`DERIVED`, `vector_backends.py:200-272`): each search reads the store; IVF reads only the probed lists by key range. | No process-wide mutable state in the Smalltalk layer (spec 5.1); the tree already gives per-list access. | No first-query build cost and nothing to release when a space closes; every exact search re-reads the tree (measured, V8). `tests/unit/test_vector_index.py:646-...` is n/a. |
| DV5 | `VectorSearch`'s `where`, when it holds a block, describes it as `{'block' -> description}` (`proto_db`: `{'python': ...}`, via `PythonPredicate`). | The existing Task 5 deviation (block predicates), extended. | A one-key difference in `explain`; no query vector holds a block. |
| DV6 | The hnsw estimate's `log2(members + 2)` is `PBCost class >> log2:` (`ln x / ln 2`). | The existing R2 deviation (ruling IQ4), extended. | Plan near-ties as R2. |
| DV7 | **Python's raw errors become `PBValidationError`.** Where `proto_db` fails with an exception Python raises itself, not a `ProtoError`, protoBaseST refuses at the same call with `PBValidationError` carrying CPython's message: (a) an `ip` or cosine score whose exact sum overflows (`OverflowError`, `vector_backends.py:128`, `136`); (b) a signalling-NaN Decimal as a vector component of a stored element, in `withAdded:`, `withRemoved:`, `build:`, `validate:` and `nearOracle:...` (`ValueError`, S10); (c) a signalling-NaN Decimal as a `PBNearQuery` component or threshold (`ValueError`, `terms.py:93`); (d) an Integer beyond the Float range as a `PBNearQuery` component or threshold (`OverflowError` from `math.isfinite`, `terms.py:93`); (e) `retrain_growth` an Integer beyond the Float range (`OverflowError`, `vector_backends.py:320`). | The host's exception classes; "refuse, never diverge": filing an sNaN element under `invalid` would write a space that `proto_db`'s `validate` crashes on. | Only the class differs; both fail the operation at the same point, and nothing is written. |
| DV8 | Error texts that name Python (`pip install hnswlib`, `vector_backends.py:298-301`) are rewritten for protoST; every other text is `proto_db`'s. | The advice would be wrong in protoST. | Text only. |
| DV9 | Performance (recorded, not a semantic difference): unknown until V8. | Interpreted vector math. | Section 5.5. |

Not deviations (recorded so nobody adds one): numbers converted to vector components equal Python's
`float()` (pinned by vectors); the k-means square uses the host's libm `pow` exactly as CPython does
(2.5; a host dependence `proto_db` has too, RV7); `params` as written
(`docs/source/format-spec.rst:1421-1423`); ties by member key; the R27 mixing rule.

---

## 5. Tests and conformance

Test layout follows IP4: unit tests in `tests/unit/` (`vec_*.st` for vector-specific files),
generators and replays in `tests/interop/`, vendored vectors in `tests/conformance/`. The task that
creates or extends each file is named in brackets.

### 5.1 Unit tests

| File | Covers | Ports |
|---|---|---|
| `tests/unit/vec_math.st` [V1] | `floatOf:` (Integers near 2^53 and 2^64, `2^1024 - 2^970` (nil) and `2^1024 - 2^971` (`Float fmax`), negative; Decimals with large and tiny exponents, subnormal half-way Decimals, zero with extreme exponents, `-0`, NaN, infinities; the sNaN refusal; the exact nearest-Float oracle of 2.2.2), `canonicalVector:dim:` (every invalid form of `tests/unit/test_vector_index.py:178-193`), `fsum:` (CPython's msum cases, special values, overflow, `-inf + inf`), scores (`:195-199`), `rank:` ties (nearest first, then member key), the three squares (`x * x` in scores and norms, `raisedTo: 2` in k-means, on half-way cases), `trainingOrderOf:` against byte order, and the IEEE self-test of 2.2.3 | 1 row + vectors of 5.2 |
| `tests/unit/vec_random.st` [V1] | `PBPythonRandom` against CPython: seed 0 as one zero word, seeds 1, 7, 2^32 - 1, 2^32, 2^40, 2^64 + 3 (little-endian words); `getrandbits` for k = 1, 31, 32, 33, 64, 100; `_randbelow`; `sample` in both branches; a population of 2^33 | vectors of 5.2 |
| `tests/unit/vec_terms.st` [V2] | `PBNearQuery` validation (`tests/unit/test_terms.py:139-164`) and its raw-error refusals (DV7 c, d), equality and hash (`0.0` and `-0.0`), `near[]` terms, list syntax both ways, `describe`, `matches:` refusal (`:133-136`), `evaluate:` refusal (`tests/unit/test_expressions.py:245-247`), `PBFilter` refuses `near[]` (`tests/unit/test_plans.py:180-...`) | 5 rows + 1 row of `test_plans.py` |
| `tests/unit/vec_index.st` [V3] | Definition and validation of all three backends, in `proto_db`'s order (`test_vector_index.py:86-100`; 2.3; `PBVectorIvfFlat check:` lands in V3 for it), the `retrain_growth` refusals (DV7 e), absent removal (`:202-207`), validate catches tampering on the exact index (the exact half of `:309-330`; the ivf half and the row are V4's), invalid elements kept aside at the index level (explain counts, validate), the sNaN refusals of DV7 (b), exact removal of equal values (`tests/unit/test_format_neutral.py:113-...`), format-3 validate (`:451-...`), the node classes of the `invalid` tree (2.11 item 3) | 2 rows + 2 rows of `test_format_neutral.py` |
| `tests/unit/vec_ivf.st` [V4 training, V6 search] | V4: training on growth, training depends on data and seed only, retrain thresholds, `validate` catches a removed centroid (the ivf half of `test_vector_index.py:309-330`, whose row turns here), all without search. V6: full probe equals exact (`:212-224`), the search halves of `:227-242` and `:262-279`, partial probe recall and widening (`:245-259`), round trip through a file space (`:282-304`) | 1 row (V4) + 5 rows (V6) |
| `tests/unit/vec_exact.st` [V6] | Exact equals the oracle for three metrics, k, threshold, both (`:121-134`), extreme magnitudes (`:137-151`), ties (`:154-161`), duplicates (`:164-175`), invalid never returned (`:178-193`), `supports:` (`:103-116`) | 6 rows |
| `tests/unit/vec_plans.st` [V6] | `PBVectorSearch` (`tests/unit/test_plans.py:152-164`), filtered kNN (`test_vector_index.py:333-353`), threshold post-filter (`:356-369`), Intersect and Union (`:372-385`), oracle with block and expression (`:388-394`), the hnsw refusal at execution (`:520-531`), eight readers on actors (`:484-515`) | 6 rows + 1 row of `test_plans.py` |
| `tests/unit/vec_contract.st` (or new registrations in `idx_contract.st`) [V6] | The vector contract registrations of `tests/contracts/index_contract.py:703-842` (exact and ivf_flat for three metrics, exact on plain values), with `nearOracle:...` as the oracle; planted defects for `OnceVectorIndex`, `MetricBlindVectorIndex`, `LastTieVectorIndex` (`test_vector_index.py:576-643`) in `_qplants.st` | 1 row |
| `tests/unit/vec_collections.st` [V5] | Every mutator of every collection kind maintains vector indexes (node-for-node with `build:` where `proto_db`'s shapes agree, `validate:` always), stale rebuild, merges onto a vector-indexed current, standalone and in a group commit, depth with the store wrapping on an append and a commit (`tests/unit/test_structure_depth.py:254-...`) | 1 row of `test_structure_depth.py` + new |
| `tests/unit/vec_planner.st` [V7] | `test_planner.py:477-527` (four `near[]` behaviours) | 4 rows |
| `tests/unit/vec_query.st` [V7] | `PBField near:...`, the R27 mixing rule and its scope (leading `where:` steps only; `test_vector_index.py:439-459`), the predicate node (`:462-483`), no index (`tests/unit/test_linq.py:362-369`, `744-750`), commit and reopen (`test_vector_index.py:399-436`) | 5 rows |

### 5.2 Interop identity with `proto_db`

**Two Python environments.** The reference venv, `tests/interop/.venv` (`setup_venv.sh`), installs
only msgpack and has no numpy today; but it is made with `--system-site-packages`, so a numpy or
hnswlib installed on the system would appear in it. A generator that must reproduce IVF training
therefore sets `sys.modules["numpy"] = None` (and `sys.modules["hnswlib"] = None`) before
importing `proto_db`, so `numpy_module()` answers None (`vector_backends.py:278-287`), the mechanism
`proto_db`'s own test uses for `hnswlib` (`tests/unit/test_vector_index.py:523`); that block is the
guarantee, not the venv's contents. A second venv, `tests/interop/.venv-numpy`
(`tests/interop/setup_venv_numpy.sh`, git-ignored like `.venv`), adds a pinned numpy (a release with
CPython 3.14 wheels, its version a constant of the script as `MSGPACK_VERSION` is) for the scripts
that need `proto_db`'s default mode. Every generator and runner prints its mode
(`numpy: blocked` or `numpy: <version>`) and the CPython and libm versions
(`platform.libc_ver()`) in its output and in the files it writes.

| Script | Task | What it proves |
|---|---|---|
| `tests/interop/py_vector_math_cases.py` -> `tests/conformance/vectors-vector-math/` (`cases.msgpack`, `manifest.sha256`), read by `tests/conformance/vector_math.st` | V1 | Float conversion (Integers, Decimals, subnormals, sNaN refusal), `canonical_vector`, fsum, the three scores, `rank_entries`, the `** 2` half-way squares, training-order bytes, `getrandbits`, `random.Random(seed).sample`, `_kmeans` (pure path) outputs, IVF `list_for`, all on seeded and adversarial inputs. Numpy blocked. |
| `tests/interop/vector_index_identical.sh` (`py_vector_index.py`, `_st_vector_index.st`) | V3, V4 | **Index level**, as `index_build_identical.sh` did for key-group indexes (plan Task 3): on one space `proto_db` writes (so both sides index the same atoms with the same oids), `build:` and seeded `withAdded:` / `withRemoved:` / `withReplaced:with:` sequences are dumped atom by atom on both sides and must be equal line for line. V3: exact and hnsw, with the two `invalid`-tree histories of 2.11 item 3 (built with invalid elements then given another; built without, then given one). V4: ivf_flat histories crossing `nlist` and `retrain_growth` thresholds, numpy blocked. No collection is written: `_checkWritable:` still refuses until V5. |
| `tests/interop/vector_ops_identical.sh` (`_st_vector_ops.st`, `py_vector_replay.py`) | V5 | **Collection level**, as `index_ops_identical.sh` (Task 4a): the same seeded history (`addIndex:` of each backend, every mutator of every collection kind, retrain thresholds crossed, removals, slices, `removeIndex:`, a blind write rebased onto a vector-indexed current) from an empty space in both implementations; dumps equal with `compare_dumps.py --exact`; `proto_db`'s verifier and `collection.validate()` accept protoBaseST's space. Numpy blocked. |
| `tests/interop/vector_both_directions.sh` | V5 | `proto_db` in `.venv-numpy` (its default mode) writes vector-indexed collections; protoBaseST changes them with every mutator and a merge; `proto_db` validates and queries the result; and the reverse. Validation must pass in both directions (DV3). Skips (77) without `.venv-numpy`; V9 runs it with the venv present. |
| `tests/conformance/legacy_database.st` (extended) | V5 | The `legacy` vector's format-3 vector index (`tests/conformance/generate.py:838-841`, an exact l2 index, so no training) is rebuilt by protoBaseST's first change, node-identical to `proto_db`'s rebuild. |
| `tests/conformance/database_contents.st` (extended) | V3, V4 | The `vectors`, `ivf` and `hnsw` roots of the `database` vector (`tests/conformance/generate.py:633-643`) pass `validate:` and their `explain` equals `proto_db`'s. The manifest does not record whether numpy was importable when the vendored vectors were generated, and it does not need to: the `ivf` root trains once, at its second member (`nlist=2`), on two vectors, so `sample(range(2), 2)` takes both, each is its own nearest centroid, and both training paths answer the two vectors in training order. The vendored centroids are `((0.0, 1.0), (1.0, 0.0))` with `trained_size` 2 (`manifest.json`), and `database_contents.st` asserts them exactly. |
| `tests/interop/concurrency.sh` | V5 | New rows: a blind write onto a vector-indexed root, both languages first and second. |

### 5.3 Query vectors with `VectorSearch` plans

`tests/interop/py_query_vectors.py` (Task 7) gains, in V7, vector-indexed collections (exact for three
metrics, ivf_flat with `nprobe < nlist` and `== nlist`, hnsw) and cases in the 0.1 list syntax
(the mapping form of `near[]` is MessagePack-neutral): k, threshold, both; a metric mismatch (no
supporting index: refusal); `near(k)` AND a pure condition (`VectorSearch` with `where`); a
threshold-only `near[]` AND a condition (`Filter` over `VectorSearch`); two `near[]` conjuncts
(`Intersect`); `near[]` in an OR (forced `Union`); a negated `near[]` (refusal); `near[]` with an
order (`Sort`); `near[]` on the hnsw index (planned as `VectorHnsw`, execution refused: the case
records the plan and the expected error class). It runs in the reference venv with numpy and
hnswlib blocked (5.2): the hnsw case needs a `proto_db` without hnswlib to record the refusal at all.

**The generator's self-check** (spec 6.2 checks "each recorded result equals a scan"; a scan
refuses `near[]`, so vector cases need their own rule):
- **exact backends, and IVF with `nprobe == nlist`:** the recorded result must equal
  `near_oracle` (S36) with the case's predicate; the generator refuses to write otherwise;
- **IVF with `nprobe < nlist`:** approximate by design (`vector_backends.py:40-41`, `685-721`;
  `proto_db`'s own test asserts only recall >= 0.6, `tests/unit/test_vector_index.py:245-259`), so
  no oracle can check it. The generator records `proto_db`'s answer and its recall against
  `near_oracle` (for the record, not as a gate), and protoBaseST must return exactly that answer:
  both sides read the same stored centroids, so list numbers, probe order and widening are the
  same computation (DV3).

**How results compare.** A result is compared as an ordered list only where `proto_db` defines an
order: a `VectorSearch` (nearest first, ties by member key) and a `Filter` directly over one. Results
of `Intersect`, `Union`, and a `Sort` whose keys tie, are compared as the existing runner compares
results (as multisets, with the order checked only where the plan defines it).
`tests/conformance/queries.st` needs no new rule; the IP8 near-tie rule applies to the hnsw
estimate (DV6).

### 5.4 Checklist rows from `proto_db`'s vector tests

`tests/unit/queries_checklist.tsv` today holds 41 `n/a excluded: vector` rows: `test_terms.py` 4,
`test_expressions.py` 1, `test_planner.py` 4, `test_linq.py` 2, `test_vector_index.py` 30. A row
turns `ported` in the task where the whole `proto_db` test it stands for passes, which for most
vector tests is the search task, since they end with a search. Statuses set in V0:

| Rows | New status |
|---|---|
| `test_vector_index.py::test_zero_vectors_have_cosine_similarity_zero` (scores only) | `deferred V1` |
| `test_terms.py` (4), `test_expressions.py::test_evaluate_near_is_not_a_scan_predicate` | `deferred V2` |
| `test_vector_index.py`: definition and validation (needs `PBVectorIvfFlat check:`, which V3 builds), absent removal (2) | `deferred V3` |
| `test_vector_index.py::test_validate_detects_structural_corruption` (builds an ivf_flat index and removes a centroid) | `deferred V4` |
| `test_vector_index.py`: supports, exact equals brute force (2), ties, duplicates, invalid never returned, ivf (5), residual predicates, threshold and post-filter, several near terms, oracle agreement, contract teeth, missing hnswlib, eight threads (18) | `deferred V6` |
| `test_planner.py` (4), `test_linq.py` (2), `test_vector_index.py`: commit and reopen, LINQ near and lambda, `PythonPredicate` node (3) | `deferred V7` |
| `test_vector_index.py`: `importing ... does not import hnswlib`, `hnsw_recall`, `hnsw_index_contract`, `hnsw_cache_under_eight_concurrent_readers`, `closing_a_space_releases_its_derived_vector_structures` (5) | `n/a` with reasons: Python import mechanics; hnsw search refused (DV1) three times; no derived cache (DV4) |

The 30 `test_vector_index.py` rows split 1 (V1) + 2 (V3) + 1 (V4) + 18 (V6) + 3 (V7) + 5 (n/a). The checklist's file list
(`tests/unit/queries_checklist.sh:26-35`) gains the files with vector tests it does not list yet:
`tests/unit/test_plans.py` (its two vector tests, 152 and 180: `deferred V6` and `deferred V2`),
`tests/unit/test_format_neutral.py` (113, 451: `deferred V3`), `tests/unit/test_structure_depth.py`
(254: `deferred V5`, since it appends to an indexed collection and commits), `tests/unit/hnsw_checks.py` (four checks, `n/a`). V0 counts the new total;
rows already `ported` whose `near[]` sub-cases were skipped (`tests/unit/test_expressions.py:84-89`,
`117-119`, `154`, `167`, `296`; `tests/unit/test_linq.py:195-197`, `716`) are reopened in V2 and V7
and noted in the row text.

### 5.5 Benchmarks

Runner: `bench/run_query.sh` gains workloads **VB0-VB5** (named apart from the tasks V0-V10; one
runner, the IP10 `WORK` line, interleaved `RUNS`, data on `/var/tmp` or `bench/out`, never tmpfs).
Rules, as for M1-M3 and P1-P3: one process per unit; every protost process under
`PROTOCORE_HEAP_LIMIT_CELLS` (default `QUERY_HEAP_LIMIT_CELLS`); peak RSS of each implementation per
unit by `/usr/bin/time`; each run prints its work and a checksum; the runner refuses a run whose
work differs from `proto_db`'s first run of the unit; minimum and median reported, **nothing
asserted about time**; results recorded in a new "Vectors" subsection of
`docs/deviations.md#performance` with date, machine, load, both commits, both binaries and the
Python mode line of 5.2. Data: a seeded clustered data set as `benchmarks/workloads/vector.py:18-26`
builds it, written once per unit by `bench/py_vector_data.py` to a MessagePack file both sides read
(protoST cannot reproduce Python's `gauss` cheaply, and the data must be the same). `proto_db` runs
in two modes: **reference** (the reference venv, numpy blocked: centroids identical, so IVF
checksums must be equal) and **default** (`.venv-numpy`: its usual speed; exact checksums must be
equal, IVF reported by recall only). The default mode is skipped, and the skip printed, when
`.venv-numpy` is absent; V8 runs with it present.

| Id | Workload | Units | Task |
|---|---|---|---|
| VB0 | Kernel: fsum against a naive sum, scores per metric | dim 8, 32, 128; 10^4 vectors (input to VQ2) | V1 |
| VB1 | Exact kNN latency and the first query | n 10^3, 10^4; dim 8, 32; k 10; cosine, l2 | V6 |
| VB2 | IVF: bulk build (`addIndex:`), query by `nprobe` (1, 4, nlist), recall@k against exact | n 10^4, dim 32, nlist = sqrt(n) (`benchmarks/workloads/vector.py:118-119`) | V6 |
| VB3 | Maintenance: commits per second appending to a collection with no index, an exact index, an IVF index (crossing retrain thresholds) | 600 and 5000 elements | V5 |
| VB4 | Filtered kNN (`near(k)` AND a condition of selectivity 1%, 10%, 50%) against the obvious post-filter (which may return fewer than k, reported) | n 10^4 | V7 |
| VB5 | A blind write merged onto a vector-indexed current, standalone and in a three-member cluster | 600 elements | V5 |

---

## 6. Documentation

Documentation first (maintainer, 2026-11-18): the chapter, the guide section and the reference
are drafted in V0, against this addendum's API, with every unmeasured figure as
`[measured in V<n>: ...]` (IP6's marker check extended to V-pin and V0-V10).

### 6.1 Tutorial chapter 20, "Vector search"

`docs/tutorial/20-vector-search.md`, program `examples/tutorial/20_vector_search.st`, modelled on
`docs/source/tutorials/vector-search.rst:1-180` and in the house course form (obvious solution, why
it fails, measured alternative). No numpy is needed (unlike `vector-search.rst:7`).

| Section | Teaches | Source |
|---|---|---|
| Documents with embeddings | `PBVectorIndex` on a path; dim, metric, backend; invalid vectors kept but never returned | `vector-search.rst:9-53` |
| Nearest neighbours | The obvious way: score everything and sort. The index answers the same, nearest first, ties by member key; `explain` read (`VectorSearch <- VectorExact`) | `:55-87` |
| Combining `near` with conditions | The obvious way: the k nearest, then filter; why it fails (fewer than k); the alternative: the condition inside the search (R27); a block from `where:` joins it too | `:89-116`; `linq.py:53-58` |
| Thresholds, and both | Similarity, distance, score per metric | `:116`; `vector.py:24-30` |
| Why two implementations agree to the last bit | The obvious way: add the products in a loop; why it fails (float addition is not associative; on near ties another neighbour wins, or an IVF member lands in another list); the alternative: a correctly rounded sum, and its measured cost (VB0) | `vector_backends.py:12-13`; `format-spec.rst:1432-1437` |
| Why `x ** 2` is not `x * x` | The obvious way: port Python's `(a - b) ** 2` as a multiplication, since "both are correctly rounded" (the first draft of this addendum said so); why it fails: Python's `**` is libm `pow`, which is not correctly rounded, and the measured half-way cases (2.5) move a vector to another centroid; the alternative: the same operation (`raisedTo: 2`), pinned by half-way vectors, and the host libm named as part of what "identical" means | `vector_backends.py:548`; 2.5 step 3 |
| IVF-Flat | Recall against `nprobe`, measured; `nprobe == nlist` is exact; training is reproducible from the data and the seed (R128), and why sampling by stored order failed (atom oids differ every run) | `:118-160`; `vector_backends.py:650-655` |
| Limits and choices | Exact first; IVF when the scan is too slow; hnsw is maintained but not searched here (DV1); a dedicated vector database for vector-only workloads; vectors live in the same versions and transactions as their records | `:166-180` |

`proto_db`'s tutorial says partial-probe recall "varies between runs on identical data ... under
investigation (R128)" (`vector-search.rst:156-159`), while `vector_backends.py:650-655` records
R128's fix. The chapter must not repeat either claim untested: V6 runs the chapter's recall
block several times in both implementations and the chapter states what was observed.

### 6.2 Examples

- `examples/queries/vector_search.st`: a port of `examples/vector_search.py:1-85` (exact and IVF
  collections, `explain`, every answer checked against a brute force), in the house `lesson
  check:` style, run by `tests/run_tests.sh`.
- `examples/tutorial/11_*` (chapter 11, "One directory, two languages"): a vector index added by
  Python, changed and merged by protoST, validated and queried by Python.
- The programs quoted by the guide section (`examples/queries/vectors.st`).

### 6.3 Guide, reference and other pages

- `docs/queries.md`, new section "Vector search": the index model for vectors (store, lists,
  invalid group), scores and why fsum, the backends, training and its determinism, `near[]`
  semantics, the planner rules (S34) with one worked plan whose figures are generated from
  `proto_db` (CR10), and the cost model of S30 labelled "model estimate".
- `docs/reference.md`: sections "Vector indexes", "Near queries", and `PBVectorSearch` under "Plans
  and explain"; `PBField` `near:` selectors; `PBVectorMath` and `PBPythonRandom` as internal (not
  public API: they exist to match CPython, and nothing outside the vector port should depend on
  them).
- `README.md` mapping table: `VectorIndex` -> `PBVectorIndex` (hnsw search refused);
  `NearQuery` -> `PBNearQuery`; `VectorSearch` -> `PBVectorSearch`; `F.v.near(...)` ->
  `(PBField path: 'v') near: ... k: ...`.
- `docs/deviations.md` (section 4), `docs/decisions.md` (3.1, section 8), `docs/not-done.md`
  (hnsw search; derived cache), chapters 4, 12 and 17 (3.4).

---

## 7. Plan tasks V-pin and V0-V10

Placement: a new "Phase 5: vectors (Addendum V)" after Task 10, as the maintainer decided, on a
branch `feat/vectors` cut from `main` once 0.3.0 (the queries work) is merged and tagged
`v0.3.0` (ruling VQ3). Every Global Constraint of the plan applies (TDD with fail-first evidence in
the commit body, test scope per task, benchmarks serial, commit trailer, documentation in the same
task, `PROTOST` and `PROTOBASE_REPO` set explicitly). **No approval stops** (section 8): each task
ends with its own tests and a commit; reviews requested by the plan's process are fixed in the
owning task; V10 merges and publishes.

**Gates.** V-pin starts only when protoST's `v0.14.1` tag exists (`git -C <protoST> rev-parse
--verify v0.14.1`); V10 starts only when protoBaseST's `v0.3.0` GitHub release exists.

**Order.** V-pin first; then V0; V1 and V2 in either order; V3 after V1; V4 after V3; V5 after V4
(collections become writable only once every backend is maintained); V6 after V2 and V5; V7 after
V6; V8 after V7; VP (only if ruling VQ2's condition holds) after V8; V9 after V8 and VP; V10 last.

**Relative size, not a schedule.** Each task's size in human working days, the unit the plan's
earlier tasks were sized in, with a wide error bar: V-pin 1.5, V0 1.5, V1 3.5, V2 1.5, V3 3, V4
3.5, V5 3, V6 3.5, V7 2.5, V8 1.5, V9 2, V10 0.5 (VP about 3 in protoST, if it runs). The figures
only compare the tasks with each other; they are not a calendar and say nothing about how long an
agent-driven run takes. Nothing in the phase is dated or gated by them.

### Task V-pin: Move the stack to protoST 0.14.1 on protoCore 3.6.1

**Files:**
- Modify: `README.md` (Requirements table: protoCore v3.6.1, protoIO v0.7.0, protoST v0.14.1; the
  build line and the "tests need protoST" line, 93-104 and 250 at `2c5cb34`), `docs/tutorial/erp.md`
  (34), `docs/not-done.md` (the floor notes, 108-109), `docs/decisions.md` (a ruling row: protoST
  0.14.1 is the floor, and why), `CHANGELOG.md` (a `## 0.4.0 (unreleased)` section opening with the
  requirements), `src/protobase/keys.st` (`_unsignedBigEndian:`, 324-333),
  `docs/deviations.md` (new dated runs of the headline benchmarks), this addendum's protoST
  citations (re-based to the tag).
- Test: `tests/unit/keys_unsigned.st` (new).
- Commits: three, in order: the pin move (Step 3), the primitive adoption in `keys.st` (Step 4),
  the re-measured benchmarks (Step 5).
- There is no CI configuration in the repository (no `.github/`); the pins live in the README, the
  documents above and the protoST binary the tests and benches are given (`PROTOST`).

**Interfaces:**
- Consumes: protoST `v0.14.1` (`ByteArray >> unsignedIntegerFrom:to:bigEndian:`,
  `lib/kernel/bytes.st:179`; the exact `Fraction` comparison primitives, `fraction_prims.cpp`),
  protoCore `v3.6.1`.
- Produces: the stack every later V task runs on; the `pinned-361` release build (protoST 0.14.1 on
  protoCore 3.6.1) for benchmarks, as `pinned-360` was for 0.12.0 on 3.6.0.

- [ ] **Step 1:** build protoST `v0.14.1` against protoCore `v3.6.1` and protoIO 0.7.0 as the
  `pinned-361` release build; `ldd` shows it links that protoCore, never `/usr`'s.
- [ ] **Step 2: baseline.** Run the full default suite with the venv present on `pinned-361`, before
  any code change. Expected: PASS, the same skips as on `pinned-360`. A failure that protoST or
  protoCore causes is reduced to a minimal reproduction and reported to that project; it is never
  worked around in protoBaseST (no technical debt), and V-pin does not proceed past it.
- [ ] **Step 3: commit the pin move alone.** The documents of **Files** except `keys.st` and its
  test (README Requirements, `erp.md`, `not-done.md`, `decisions.md`, the CHANGELOG 0.4.0
  requirements); re-base every protoST citation of this addendum (and of the spec section it
  becomes) from `af640f1` to the tag (`git diff af640f1 v0.14.1` on the cited files). No code
  changes in this commit; the baseline of Step 2 is its evidence. Commit `Vectors V-pin: protoST
  0.14.1 on protoCore 3.6.1 (pins, documents, full-suite baseline)`.
- [ ] **Step 4: the primitive adoption, its own commit, fail-first.** Write `keys_unsigned.st`:
  `PBKeys _unsignedBigEndian:` on 0, 8, 16 and 33 bytes (all-zero,
  all-`16rFF`, a 16-byte oid, a mixed pattern) against the Integer the bytes spell, and a fifth
  case that calls `unsignedIntegerFrom:to:bigEndian:` directly on the same arrays, so the test
  fails without the 0.14.1 primitive (`"EXPECT: ok 5"`; no `respondsTo:` fallback, the floor is
  0.14.1). Run it with the 0.12.0 binary first:
  Expected FAIL (`doesNotUnderstand: #unsignedIntegerFrom:to:bigEndian:`), recorded in the commit
  body. Then rewrite `_unsignedBigEndian:` (`keys.st:324-333`) as one
  `unsignedIntegerFrom: 1 to: aByteArray size bigEndian: true` for every size (the 16-byte
  two-word special case and the byte loop both go) and run it with `pinned-361`: PASS, and so do
  `tests/conformance/order.st`, `index_keys.st` and `tests/interop/avl_ops_identical.sh`. Commit
  `Keys: an unsigned big-endian Integer from bytes in one protoST 0.14.1 primitive`. The exact
  Fraction comparison needs no code change: order keys of floats compare `Fraction` payloads
  (`keys.st:285`, `336-361`), which now take the primitive.
- [ ] **Step 5: headline benchmarks, serially, on a quiet machine, after both commits:**
  `bench/run_avl.sh`, `bench/run_tx.sh` and `RUNS=5 bench/run_query.sh` (M1-M3, P1-P3) on
  `pinned-361`. Expected: every line `verified`. Record them in `docs/deviations.md#performance` as
  new dated runs beside the 0.12.0 ones (date, machine, load, both commits, both binaries); nothing
  is asserted about time, and no earlier figure is rewritten. Commit `Vectors V-pin: headline
  benchmarks re-measured on protoST 0.14.1`.

### Task V0: Documentation drafts, rulings and the checklist for vectors

**Files:**
- Create: `docs/tutorial/20-vector-search.md` (draft), `examples/queries/pending/20_vector_search.st.pending`,
  `examples/queries/pending/vector_search.st.pending`.
- Modify: `docs/queries.md` (section "Vector search", draft), `docs/reference.md` (new sections, draft),
  `docs/tutorial/README.md` and `README.md` (chapter 20 row, draft), `examples/queries/pending/README.md`
  (the pending table), `docs/decisions.md` (rulings VQ1-VQ3 and the no-approval-stop rule, section
  8), `tests/docs/pending_selectors.tsv` (the new selectors, each with its V task),
  `tests/docs/measured_markers.sh` (tasks V-pin and V0-V10 accepted), `tests/unit/queries_checklist.sh`
  (file list of 5.4), `tests/unit/queries_checklist.tsv` (statuses of 5.4), the spec (3.2) and the
  plan (3.3).

**Interfaces:**
- Consumes: this addendum, folded into the spec.
- Produces: the pending selectors and markers V1-V10 remove; the checklist rows V1-V7 turn to
  `ported`.

- [ ] **Step 1:** extend `measured_markers.sh` and `queries_checklist.sh`; run
  `tests/run_tests.sh tests/docs tests/unit/queries_checklist.sh`. Expected: FAIL (the new markers
  are malformed to the old check; the new files have no rows).
- [ ] **Step 2:** write the drafts (6.1, 6.3) with markers, the pending programs, the rows, the
  rulings.
- [ ] **Step 3:** run the same. Expected: PASS; the checklist prints its new total and the count
  per status.
- [ ] **Step 4:** commit `Vectors V0: documentation drafts, rulings, pending selectors, checklist`.

### Task V1: The vector math kernel and Python's random sample

**Files:**
- Create: `src/protobase/vectors.st` (`PBVectorMath`, `PBPythonRandom`), `tests/interop/py_vector_math_cases.py`,
  `tests/conformance/fetch_vector_math_vectors.sh`, `tests/conformance/vectors-vector-math/`,
  `tests/conformance/vector_math.st`, `tests/unit/vec_math.st`, `tests/unit/vec_random.st`.
- Modify: `src/protobase.st` (import order), `bench/run_query.sh` and its workload files (VB0).

**Interfaces:**
- Produces: `PBVectorMath class >> floatOf:`, `canonicalVector:dim:`, `fsum:`, `sumNonNegative:`,
  `score:query:vector:`, `scoreFloor:threshold:`, `rank:query:metric:k:threshold:` (entries
  `{memberKey. element. count. vector}`, answer `{element. count}` pairs), `normalized:`,
  `trainingOrderOf:`, `kmeans:nlist:iterations:seed:`; `PBPythonRandom class >>
  sampleRange:count:seed:` and `bits:count:seed:`.

- [ ] **Step 1: write the failing tests.** `vec_math.st` (`"EXPECT: ok 12"`): the cases of 5.1,
  the self-test of 2.2.3 included; `vec_random.st` (`"EXPECT: ok 6"`); `vector_math.st`: every case
  of `cases.msgpack` equal bit for bit (Floats compared by their bytes, the `** 2` half-way squares
  included), last line `vector math vectors ok`.
- [ ] **Step 2:** write `py_vector_math_cases.py` (numpy and hnswlib blocked; seeded and adversarial
  inputs: near-cancelling sums, subnormals, 1e±300, huge Integers, Decimals with subnormal half-way
  values and extreme exponents, sNaN, odd 27-bit half-way squares, ties; CPython's own results;
  `_kmeans` on the pure path; the CPython, glibc and mode lines of 5.2) and the fetch script;
  vendor once. Run `tests/run_tests.sh tests/unit/vec_math.st tests/unit/vec_random.st
  tests/conformance/vector_math.st`. Expected: FAIL (`PBVectorMath` unknown).
- [ ] **Step 3:** implement (2.2.2, 2.5 steps 2 and 3), each method citing its source.
- [ ] **Step 4:** run the three. Expected: PASS.
- [ ] **Step 5: bench VB0.** `RUNS=5 bench/run_query.sh VB0`. Expected: `verified` (the sums'
  checksums equal `proto_db`'s). Record the figures; they are an input to VQ2.
- [ ] **Step 6:** reference (internal note), pending lines, checklist row (zero vectors),
  CHANGELOG; commit `Vectors V1: vector math kernel and Python's sample; VB0 measured`.

### Task V2: Near queries, `near[]` terms, the list syntax, refusals in scans and filters

**Files:**
- Modify: `src/protobase/vectors.st` (`PBNearQuery`), `src/protobase/terms.st`, `src/protobase/plans.st`
  (`PBFilter` refusal), `src/protobase/planner.st` (`normalize:` refusal only),
  `tests/interop/py_term_cases.py`.
- Create: `tests/unit/vec_terms.st`.
- Modify: `tests/unit/qry_terms.st`, `tests/unit/qry_expressions.st` (refusal cases flipped; reopened
  `near[]` sub-cases).

**Interfaces:**
- Consumes: V1 (`floatOf:`).
- Produces: `PBNearQuery class >> vector:k:threshold:metric:` and conveniences; `vector`, `k`,
  `threshold`, `metric`, `=`, `hash`, `describe`; `PBTerm path:op:value:` accepting `'near[]'`;
  `matches:` and `evaluate:` refusals; `PBExpression compile:` and `asList` for both forms;
  `PBFilter` refusal; `PBPlanner normalize:` refusal of a negated `near[]`.

- [ ] **Step 1: write the failing tests** (`vec_terms.st` `"EXPECT: ok 10"`: the five rows of 5.4, the
  `test_plans.py:180` Filter refusal, the degenerate cases `py_term_cases.py` records from
  `proto_db`, the raw-error refusals DV7 (c) and (d), equality with `-0.0`; the flipped cases).
- [ ] **Step 2:** run `tests/run_tests.sh tests/unit/vec_terms.st tests/unit/qry_terms.st
  tests/unit/qry_expressions.st`. Expected: FAIL (`'near[]'` refused at build).
- [ ] **Step 3:** implement (2.6, the `PBFilter` and `normalize:` parts of 2.7 and 2.8).
- [ ] **Step 4:** run the three. Expected: PASS.
- [ ] **Step 5:** deviations rows at `docs/deviations.md:958` and `1008` rewritten; DV7 entry
  started; pending lines; checklist rows; commit `Vectors V2: near queries and near[] terms`.

### Task V3: `PBVectorIndex` with the exact and hnsw backends (maintenance, build, validate, explain)

**Files:**
- Modify: `src/protobase/indexes.st` (`PBVectorIndex` rewritten), `src/protobase/vectors.st`
  (`PBVectorBackend`, `PBVectorExact`, `PBVectorHnsw` without search), `src/protobase/keygroups.st`
  (`checkDepth:...outer:`).
- Create: `tests/unit/vec_index.st`, `tests/interop/vector_index_identical.sh`,
  `tests/interop/py_vector_index.py`, `tests/interop/_st_vector_index.st`.
- Modify: `tests/unit/idx_keygroups.st` (vector refusal cases flipped),
  `tests/conformance/database_contents.st` (validate and explain of `vectors` and `hnsw`).

**Interfaces:**
- Consumes: V1.
- Produces: the constructors, readers and validation order of 2.3; `withAdded:`, `withRemoved:`,
  `withReplaced:with:`, `empty`, `build:`, `validate:`, `explain`; `PBVectorBackend named:`;
  `PBVectorExact`/`PBVectorHnsw` `check:`, `listFor:vector:`, `needsTraining:`, `train:vectors:`,
  `explainOf:`; `PBVectorIvfFlat check:` (defaults, order and texts of `vector_backends.py:574-586`,
  with `_growth`'s refusals), so that every backend's definition validates from V3. Collections
  holding vector indexes still refuse writes (V5).

- [ ] **Step 1: write the failing tests.** `vec_index.st` (`"EXPECT: ok 11"`: definition and validation
  order; `PBVectorIvfFlat check:` defaults and order; `retrain_growth` refusals; absent removal;
  tampering on an exact index; invalid elements kept aside; sNaN refusals; removal of equal values;
  format-3 validate; the `invalid` tree after a build and when grown); the index-level
  identity script for exact and hnsw (5.2: `build:` and seeded hook sequences, the two `invalid`-tree
  histories); `database_contents.st` for `vectors` and `hnsw`.
- [ ] **Step 2:** run `tests/run_tests.sh tests/unit/vec_index.st tests/unit/idx_keygroups.st
  tests/interop/vector_index_identical.sh tests/conformance/database_contents.st`. Expected: FAIL
  (`PBVectorIndex name:keySpec:dim:...` not understood).
- [ ] **Step 3:** implement, porting `vector.py:125-268`, `323-425` and the backend parts of
  `vector_backends.py`; the node-class rule of 2.11 item 3; the sNaN refusals of DV7 (b).
- [ ] **Step 4:** run the four. Expected: PASS (dumps equal line for line).
- [ ] **Step 5:** reference "Vector indexes" (hooks, readers), DV7 (b), pending lines, checklist
  rows (2 of `test_vector_index.py`, 2 of `test_format_neutral.py`);
  commit `Vectors V3: vector indexes maintained, exact and hnsw node-identical at the index level`.

### Task V4: IVF-Flat: lists, training, retraining

**Files:**
- Modify: `src/protobase/vectors.st` (`PBVectorIvfFlat`, search excepted).
- Create: `tests/unit/vec_ivf.st` (training half).
- Modify: `tests/interop/py_vector_index.py` and `_st_vector_index.st` (IVF histories crossing
  `nlist` and `retrain_growth` thresholds, numpy blocked on the Python side),
  `tests/conformance/database_contents.st` (`ivf` root, its centroids asserted, 5.2).

**Interfaces:**
- Consumes: V1 (`fsum:`, `sumNonNegative:`, `kmeans:...`, `sampleRange:count:seed:`), V3.
- Produces: `PBVectorIvfFlat` `listFor:vector:` (its `check:` is V3's), `needsTraining:` (2.4's comparison), `train:vectors:`, `probeOrder:query:`;
  the IVF parts of `explain` (`lists`, `trained_size`). Search lands in V6.

- [ ] **Step 1: write the failing tests:** the training rows of `vec_ivf.st` (`"EXPECT: ok 6"`:
  training on growth, training depends on data and seed only (centroids only), retrain thresholds,
  `validate` catches a removed centroid, a subnormal-square distance, a half-way distance tie
  between two centroids resolved as `proto_db` resolves it); IVF identity histories; the `ivf` root.
- [ ] **Step 2:** run `tests/run_tests.sh tests/unit/vec_ivf.st tests/interop/vector_index_identical.sh
  tests/conformance/database_contents.st`. Expected: FAIL.
- [ ] **Step 3:** implement (2.5), porting `vector_backends.py:527-563`, `566-670`, `732-734`.
- [ ] **Step 4:** run the three. Expected: PASS; centroids byte-identical to `proto_db` without
  numpy on this host.
- [ ] **Step 5:** deviation DV3 entry (with the libm note); reference; commit
  `Vectors V4: IVF-Flat lists and training node-identical at the index level`.

### Task V5: Collections become writable: refusal narrowed, collection identity, stale rebuild, merges, both directions

**Files:**
- Modify: `src/protobase/collections.st` (`_checkWritable:`, comments), `tests/unit/indexed_refusal.st`
  (opaque-index fixture), `tests/unit/idx_merge.st` case (8), `tests/interop/concurrency.sh` and
  `concurrency_cases.json`, `tests/conformance/legacy_database.st`, `.gitignore` (`.venv-numpy`),
  `bench/run_query.sh` and its workload files (VB3, VB5).
- Create: `tests/unit/vec_collections.st`, `tests/interop/vector_ops_identical.sh`,
  `tests/interop/_st_vector_ops.st`, `tests/interop/py_vector_replay.py`,
  `tests/interop/vector_both_directions.sh`, `tests/interop/setup_venv_numpy.sh`.

**Interfaces:**
- Consumes: V3, V4.
- Produces: collections holding vector indexes writable and mergeable; format-3 vector indexes
  rebuilt on first change; opaque kinds still refused; the `.venv-numpy` environment.

- [ ] **Step 1: write the failing tests** (`vec_collections.st` `"EXPECT: ok 8"`: depth on an append and a commit
  (`test_structure_depth.py:254`); every mutator of
  every collection kind with an exact and an IVF index, node-for-node against `build:` where shapes
  agree and `validate:` always; stale rebuild; merges standalone and in a group commit;
  `indexed_refusal.st` with an opaque index; `idx_merge.st` (8) now merging; the collection identity
  script; legacy rebuild identity; both directions; the concurrency rows).
- [ ] **Step 2:** run `tests/run_tests.sh tests/unit/vec_collections.st tests/unit/indexed_refusal.st
  tests/unit/idx_merge.st tests/interop/vector_ops_identical.sh tests/conformance/legacy_database.st
  tests/interop/vector_both_directions.sh tests/interop/concurrency.sh`. Expected: FAIL
  (`PBNotSupportedError` naming the vector index).
- [ ] **Step 3:** implement (2.10); write `setup_venv_numpy.sh`.
- [ ] **Step 4:** run the seven. Expected: PASS (with `.venv-numpy` present, no skip).
- [ ] **Step 5: bench VB3, VB5.** `RUNS=5 bench/run_query.sh VB3 VB5`. Expected: `verified`. Record.
- [ ] **Step 6:** the documents and comments of 3.4 that concern writes, `docs/decisions.md`
  (IQ5a); commit `Vectors V5: collections with vector indexes are written and merged; VB3 and VB5
  measured`.

### Task V6: Vector search: supports, estimates, plans, `PBVectorSearch`, the contract

**Files:**
- Modify: `src/protobase/indexes.st` (`supports:`, `supportsFiltered:`, `estimate:`, `plan:`,
  `filteredPlan:where:`, `nearOracle:...`; `PBIndex` defaults), `src/protobase/vectors.st` (the three
  `search:...` and `estimate:...`), `src/protobase/plans.st` (`PBVectorSearch`),
  `bench/run_query.sh` and its workload files (VB1, VB2).
- Create: `tests/unit/vec_exact.st`, `tests/unit/vec_plans.st`, `tests/unit/vec_contract.st`.
- Modify: `tests/unit/vec_ivf.st` (search rows), `tests/unit/_qplants.st` (the three broken
  variants), `tests/unit/qry_index_plans.st` (vector cases flipped).

**Interfaces:**
- Consumes: V2, V3, V4, V5.
- Produces: `PBVectorIndex >> supports:`, `supportsFiltered:`, `estimate:`, `plan:`,
  `filteredPlan:where:`; `PBVectorIndex class >> nearOracle:keySpec:query:metric:predicate:`;
  `PBVectorSearch class >> index:term:where:` with `do:`, `execute`, `explain`, `estimate`;
  `PBIndex >> supportsFiltered:` (false), `filteredPlan:where:` (refusal); the hnsw search refusal.

- [ ] **Step 1: write the failing tests** (5.1 rows for `vec_exact.st` `"EXPECT: ok 6"`, `vec_ivf.st`
  search rows (`"EXPECT: ok 11"` in all), `vec_plans.st` `"EXPECT: ok 7"`, `vec_contract.st` with
  seeds from `PBST_PROP_SEEDS`; S30's arithmetic checked against `proto_db`'s estimates).
- [ ] **Step 2:** run `tests/run_tests.sh tests/unit/vec_exact.st tests/unit/vec_ivf.st
  tests/unit/vec_plans.st tests/unit/vec_contract.st tests/unit/qry_index_plans.st`. Expected: FAIL.
- [ ] **Step 3:** implement (2.4, 2.7), porting `vector.py:92-122`, `272-319`,
  `vector_backends.py:480-524`, `663-730`, `790-821`, `plans.py:389-436`, `base.py:274-281`.
- [ ] **Step 4:** run the five. Expected: PASS; the contract's planted defects are each caught; the
  recall block of chapter 20 run several times in both implementations, its observation recorded
  for the chapter (6.1).
- [ ] **Step 5: bench VB1, VB2.** `RUNS=5 bench/run_query.sh VB1 VB2`. Expected: `verified` (exact
  checksums equal in both `proto_db` modes; IVF checksums equal in reference mode). Record.
- [ ] **Step 6:** reference ("Near queries", `PBVectorSearch`), DV1, DV2, DV4, DV7 (a), DV8
  entries, checklist rows (18 of `test_vector_index.py`, `test_plans.py:152`); commit
  `Vectors V6: vector search plans; VB1 and VB2 measured`.

### Task V7: The planner's `near[]` rules, `PBField near:`, the R27 mixing rule, query vectors

**Files:**
- Modify: `src/protobase/planner.st`, `src/protobase/query.st`, `tests/interop/py_query_vectors.py`,
  `tests/conformance/vectors-queries/` (regenerated by `fetch_query_vectors.sh`),
  `tests/conformance/queries.st` (the comparison rule of 5.3), `bench/run_query.sh` and its
  workload files (VB4).
- Create: `tests/unit/vec_planner.st`, `tests/unit/vec_query.st`.
- Modify: `tests/unit/qry_planner.st` (the vector-not-consulted case flipped).
- Move: `examples/queries/pending/vector_search.st.pending` -> `examples/queries/vector_search.st`.

**Interfaces:**
- Consumes: V6.
- Produces: the planner rules of 2.8; `PBPlanner class >> _consults:` narrowed; `PBField >> near:...`
  selectors; the R27 rule in `PBQuery`, with its scope (2.9).

- [ ] **Step 1: write the failing tests** (`vec_planner.st` `"EXPECT: ok 4"`, `vec_query.st`
  `"EXPECT: ok 5"`, the new query-vector cases of 5.3 with the generator's self-check rule, the
  example through `tutorial_chapters_sync.sh`).
- [ ] **Step 2:** regenerate the query vectors; run `tests/run_tests.sh tests/unit/vec_planner.st
  tests/unit/vec_query.st tests/unit/qry_planner.st tests/conformance/queries.st
  examples/queries/vector_search.st`. Expected: FAIL (near conjuncts not planned).
- [ ] **Step 3:** implement, porting `planner.py:98-135`, `194-275` and `linq.py:996-1008`,
  `1099-1105`.
- [ ] **Step 4:** run the five. Expected: PASS; `queries.st` prints `near ties: N` (IP8) and `query vectors ok`.
- [ ] **Step 5: bench VB4.** `RUNS=5 bench/run_query.sh VB4`. Expected: `verified`. Record.
- [ ] **Step 6:** guide (planner rules), DV5, DV6 entries, reference (`PBField`), checklist rows;
  commit `Vectors V7: near[] in the planner and the query front end; query vectors; VB4 measured`.

### Task V8: The full vector comparison and the primitive decision

**Files:**
- Modify: `docs/deviations.md` ("Vectors" performance subsection), `docs/decisions.md` (the VQ2
  outcome), `bench/run_query.sh` (only if a unit needs a fix).

- [ ] **Step 1:** on a quiet machine, `RUNS=5 bench/run_query.sh VB0 VB1 VB2 VB3 VB4 VB5`, serially,
  nothing else running, `.venv-numpy` present. Expected: `verified`.
- [ ] **Step 2:** record the figures with date, machine, load, commits, binaries, both `proto_db`
  modes and peak RSS.
- [ ] **Step 3: apply ruling VQ2.** From VB0 (kernel cost per scored vector, per dim and metric) and
  VB1 (exact query time at the same dim, metric and n), compute the kernel's share of an exact
  query: kernel cost per vector times the vectors scored, over the measured query time. If that
  share is above one half for any unit of VB1, the interpreted kernel dominates and VP runs;
  otherwise it does not. Record the computation, the figures it used and the outcome in
  `docs/deviations.md` and `docs/decisions.md` (VQ2).
- [ ] **Step 4:** commit `Vectors V8: the vector comparison recorded; VQ2 applied`.

### Task VP (conditional on ruling VQ2): protoST `Float` fsum primitives

Runs only when V8's Step 3 says so. In the protoST repository, on its own branch from `main`.
**Files:** `src/primitives/math_prims.cpp` (three class-side primitives on `Float`, 2.2.4), its CMake
flags (`-ffp-contract=off` for that unit), protoST tests with CPython-generated cases, `CHANGELOG.md`,
`KNOWN_ISSUES.md` if needed. protoST's own process applies (its tests, review, a minor release).
protoBaseST then gains the feature probe in `PBVectorMath` (scores only: k-means keeps the
Smalltalk `raisedTo: 2` loop, 2.2.4), re-runs `tests/conformance/vector_math.st` with and without
the primitive, and re-measures VB0-VB2 on the release that carries it. The protoST floor stays
0.14.1 (the probe falls back). protoCore is not touched.

### Task V9: Final: chapter 20 runnable, documentation complete, audits

**Files:**
- Move: `examples/queries/pending/20_vector_search.st.pending` -> `examples/tutorial/20_vector_search.st`.
- Modify: `docs/tutorial/20-vector-search.md` (markers filled, draft banner removed),
  `docs/queries.md`, `docs/reference.md`, `docs/not-done.md`, `docs/deviations.md`, `README.md`,
  `CHANGELOG.md`, chapter 11 and its program, `examples/queries/pending/README.md`.

- [ ] **Step 1:** run `PENDING_FINAL=1 MARKERS_FINAL=1 CHECKLIST_FINAL=1 tests/run_tests.sh tests/docs
  tests/unit/queries_checklist.sh`. Expected: FAIL until every vector selector, marker and row is done.
- [ ] **Step 2:** finish the chapter (the recall observation of V6 and the `** 2` lesson included),
  the example of chapter 11, the reference, the guide's worked vector plan (generated from
  `proto_db`, CR10).
- [ ] **Step 3:** run the full default suite with both venvs present, the vector property seeds at
  the large setting, and the doc checks once. Expected: PASS, no skip in the vector tests.
- [ ] **Step 4:** request the whole-phase review (superpowers:requesting-code-review); fix every
  finding in its owning module, fail-first; record any declined finding with its evidence.
- [ ] **Step 5:** commit `Vectors V9: chapter 20, documentation complete, final verification`.

### Task V10: Release protoBaseST 0.4.0

Gate: protoBaseST's `v0.3.0` GitHub release exists.

**Files:**
- Modify: `CHANGELOG.md` (`## 0.4.0 — <date>`: requirements protoST 0.14.1 and protoCore 3.6.1,
  vector indexes and search, the deviations DV1-DV9 by name, the measured comparison by link);
  `README.md` (a "Vector search (0.4.0)" line beside "Cluster mode (0.2.0)", the chapter 20 and
  guide rows marked **(0.4.0)** as 0.3.0's are; Requirements were moved by V-pin); `docs/not-done.md`
  and `docs/deviations.md` (CR9 rule: no future tense about 0.4.0). The source carries no version
  string (none for 0.2.0 or 0.3.0 either): the version is the tag and the CHANGELOG heading.

- [ ] **Step 1:** `grep -n "0.4.0" docs/not-done.md docs/deviations.md` shows no future-tense line;
  the CHANGELOG heading, the README lines and the tag to be made agree.
- [ ] **Step 2:** run the full default suite once more on the merge result of `feat/vectors` into
  `main` (both venvs present). Expected: PASS.
- [ ] **Step 3:** open a pull request from `feat/vectors` to `main` and merge it with a merge
  commit, as 0.2.0 was (PR #1); tag the merge `v0.4.0`; push the tag.
- [ ] **Step 4:** create the GitHub release `protoBaseST 0.4.0 — vector search` with the CHANGELOG
  section as its notes, the stack pins (protoCore v3.6.1, protoIO v0.7.0, protoST v0.14.1, and the
  protoST release of VP if it ran) and the `proto_db` reference (`v2.0.0rc4`, `8e6127f`).
- [ ] **Step 5:** record the release in `progress.md` and report.

---

## 8. Rulings

Settled on 2026-11-19. V0 records them in `docs/decisions.md`, section 5.

| # | Question | Ruling | Consequence |
|---|---|---|---|
| VQ1 | **hnsw search.** Refuse it, answer it with an exact search under the `VectorHnsw` node, or write an HNSW graph in Smalltalk? | **Refuse.** `PBNotSupportedError` at the first execution of a `VectorHnsw` plan, as `proto_db` refuses it without `hnswlib` (`tests/unit/test_vector_index.py:520-531`); maintenance, `validate:`, `explain` and planning work. | "Refuse, never diverge" holds, and hnsw-indexed collections are writable from protoST. An exact answer under an hnsw node would show `proto_db`'s hnsw estimate for a full scan; a Smalltalk graph would be new, unreproducible against hnswlib, and slow to build per process. DV1. |
| VQ2 | **A protoST primitive for fsum** (2.2.4). | **Specified now; built in protoST only if V8 shows the interpreted kernel dominates search time** (the rule of V8, Step 3). | Correctness never depends on it; the Smalltalk kernel stays as the oracle and the fallback. It cannot serve k-means, whose square is `** 2` (libm `pow`), not a product (2.2.4). |
| VQ3 | **Release vehicle.** | **0.4.0, after 0.3.0 (queries) is released.** | 0.3.0 ships after Task 10 with IQ5 as approved, on protoST 0.12.0. The vectors phase moves the stack to protoST 0.14.1 (V-pin) and ends with the 0.4.0 release (V10). |
| (execution) | Approval stops. | **None.** The phase runs to the end: spec, implementation, tests, documentation, tutorial chapter 20, examples, merge, publication. | Decisions the tasks take (the VQ2 outcome, declined review findings) are recorded with their evidence in `docs/decisions.md` instead of waiting for approval. |

---

## 9. Risks

| # | Risk | Mitigation |
|---|---|---|
| RV1 | **Interpreted vector math is slow** enough that exact search on 10^4 vectors is impractical. | Measure first (VB0, VB1); VQ2's rule in V8; the chapter says what was measured, no claim beyond it. |
| RV2 | **Float conversion or fsum differ from CPython in a corner** (huge Integers, subnormal Decimals, half-way sums), giving a different neighbour or list number. | `vec_math.st` with the exact nearest-Float oracle, and `vector_math.st` on adversarial CPython vectors; `validate:` in every interop test catches a wrong list number. |
| RV3 | **A retrain inside a merge** runs k-means in the publisher or, in a cluster, in the round's build under the cluster-wide permission; at protoST's speed it can exceed the lease send window (M3 already saw rounds refused at 189 ms). | Bench VB5 measures it; documented in chapter 20 and the guide; behaviour is `proto_db`'s (S21). |
| RV4 | **Node-class drift** in the `invalid` group (the root's class rule) or in the store. | The index-level identity script covers both `invalid`-tree histories, and the collection-level one every mutator (2.11). |
| RV5 | **IVF interop with numpy-trained `proto_db` indexes** (DV3): protoBaseST reads and maintains them, but a protoBaseST retrain replaces numpy centroids with pure-path ones. | Valid by the format; stated in DV3 and chapter 20; `vector_both_directions.sh` validates both ways. |
| RV6 | **Python's `random.sample` or MT19937 seeding changes between CPython versions.** | The vectors record the CPython version that generated them; `vec_random.st` fails loudly on a change. |
| RV7 | **Host libm.** The k-means square is libm `pow`, which is not correctly rounded (2.5); another libm can round half-way squares differently, for `proto_db` and the port alike, or set `ERANGE` on a subnormal square, which CPython turns into `OverflowError` (a distance of `inf`) while protoST keeps the subnormal. | Identity is claimed and tested on one host; every generator records `platform.libc_ver()`; the half-way vectors of `vector_math.st` fail on a host whose `pow` differs, which names the cause instead of reporting a wrong centroid. |
| RV8 | **protoST 0.14.1 is not tagged when the phase is due**, or regresses protoBaseST. | V-pin is gated on the tag and runs the full suite before any change; a protoST regression is reported upstream, never worked around. |

---

## 10. Review response

Review 1 (`vectors-addendum-review-1.md`) was checked finding by finding against the sources; every
Critical, Important and Minor finding is folded in above. Where a finding was rejected in part,
amended, or taken in another form, the evidence is recorded here.

- **C4, "`supports` raises" on a signalling-NaN Decimal: not reproduced; not adopted.**
  `VectorIndex.supports` calls `canonical_vector(query.vector, self.dim)` (`vector.py:278`), but
  `query.vector` is never the caller's raw sequence: `NearQuery.__post_init__` replaces it with a
  tuple of floats from `_finite_number` (`terms.py:113-116`), which already raised `ValueError` for an
  sNaN component (checked: `float(Decimal('sNaN'))` and `math.isfinite(Decimal('sNaN'))` both raise
  `ValueError` on CPython 3.14.0). A `near[]` term's value is always a `NearQuery`
  (`_near_query`, `terms.py:128-137`), so `supports` cannot meet an sNaN. The refusal sits at
  `PBNearQuery` construction (DV7 c), and `supports:` needs none. The other calls the finding
  names (`with_added`, `build`, `validate`) are confirmed and handled (DV7 b), together with
  `with_removed` and `near_oracle`, which raise the same way.
- **C1, the measured counts.** The phenomenon is reproduced and the conclusion adopted; the figures
  in 2.5 are this revision's own run (seeded differently from the reviewer's): 55,729 differences
  among 200,000 odd integers from [2^26, 2^27) (117,197 of which have half-way squares; the
  reviewer's wording, "odd 27-bit integers (exact half-way squares)", counts all 200,000 as
  half-way, which holds only above 2^26.5), 845 of 1,000,000 uniform doubles, and `**` against
  `libm.pow` 0 of 300,000. The reviewer reported 94,468, 840 and 0. Both runs agree that `x * x` is the correctly
  rounded square every time and that `**` is libm `pow`.
- **I3, "the `sys.modules` block becomes belt and braces": amended.** The reference venv is made
  with `--system-site-packages` (`tests/interop/setup_venv.sh`; `.venv/pyvenv.cfg` says
  `include-system-site-packages = true`). Neither it nor the system Python has numpy today
  (checked), but a system-wide numpy would appear in it, so the block is the guarantee and the
  venv's contents are not (5.2).
- **I1, "CI": nothing to change.** The repository has no CI configuration (no `.github/`, no other
  workflow file in `git ls-files`); V-pin moves the pins where they live: the README, the
  documents that name a floor, and the protoST build the tests and benchmarks are given.
- **C5: the first option is taken in a different form.** Narrowing `_checkWritable:` in V3 would
  make IVF-indexed collections writable before IVF maintenance exists (V4). Instead V3 and V4 prove
  identity at the index level, as plan Task 3 did for key-group indexes
  (`index_build_identical.sh`), and the narrowing, with the collection histories, moves to V5,
  right after the last backend is maintained and before search; the tasks are renumbered so that
  each one's tests can pass when it runs.
