# protoBaseST indexed queries and the query planner: analysis and design proposal

- **Date:** 2026-11-18
- **Status:** APPROVED by the maintainer on 2026-11-18. The rulings on the open questions IQ1 to
  IQ8 are recorded in section 9.2. No code is written. Implementation starts after the cluster
  release (0.2.0) ships; the plan is `docs/superpowers/plans/2026-11-18-indexed-queries.md`.
- **Scope in one line:** port `proto_db`'s index maintenance (equality and range indexes), its
  term and expression language, its planner and its plan operators, an idiomatic Smalltalk query
  front end, and in-process paging by rank. **Vector indexes and vector search are excluded.**
- **Maintainer's requirement (2026-11-18, binding):** the implementation ships with complete
  documentation (reference and a conceptual guide, including how to read `explain`), tutorial
  chapters linked from the README that teach the reasoning, runnable examples that run as tests,
  and self-verifying performance tests with a cross-implementation comparison. Section 4 states
  each as a deliverable with acceptance criteria; section 11 schedules docs and tutorials early,
  in parallel with the code.
- **Reference read:** `ProtoBase` at `b99285b` (HEAD, two commits after `v2.0.0rc4`), read only
  through `git show` / `git ls-tree`. `git diff --stat v2.0.0rc4 HEAD` over `proto_db/indexing`,
  `proto_db/query`, `proto_db/collections` and the two framework pages is **empty**, so every
  citation below holds for the normative tag `v2.0.0rc4`. Citations are `file:line` at that
  content.
- **protoBaseST** at `02d9826` (branch `feat/queries`, from `feat/cluster`). **protoST** at
  `b7e206a` (0.12.0). protoCore and protoST need **no change** (ruling IQ4, section 9.2: no
  `log2` primitive is requested).
- **Not verified while writing:** nothing was built or run (the machine is reserved for the
  cluster's timer audit). Every statement about protoBaseST is from reading its source; every
  statement about `proto_db` is from reading its source and docs. The effort figures in 11 are
  estimates with a wide error bar.

Contents:
[1. Intent and why](#1-intent-and-why) |
[2. Reference inventory](#2-reference-inventory) |
[3. Scope](#3-scope) |
[4. Required deliverables and acceptance criteria](#4-required-deliverables-and-acceptance-criteria) |
[5. Design in protoST terms](#5-design-in-protost-terms) |
[6. Compatibility and conformance](#6-compatibility-and-conformance) |
[7. Testing strategy and benchmarks](#7-testing-strategy-and-benchmarks) |
[8. Documentation and tutorial plan](#8-documentation-and-tutorial-plan) |
[9. Decisions taken in this spec](#9-decisions-taken-in-this-spec) |
[10. Risks, gaps and open questions](#10-risks-gaps-and-open-questions) |
[11. Proposed task breakdown](#11-proposed-task-breakdown)

---

## 1. Intent and why

### 1.1 Where protoBaseST stands

protoBaseST reads every index `proto_db` writes and keeps it (`src/protobase/indexes.st`), but it
neither queries nor maintains one. A collection with an index refuses every change
(`PBIndexedCollection >> _checkWritable:`, `src/protobase/collections.st:509-519`), and so does a
merge onto one (`rebaseOnto:`, `collections.st:414-427`; `PBTransaction >> _merged:onto:`,
`transactions.st:671-675`). Chapter 4 of the tutorial tells the reader to answer questions by a
walk or by a hand-kept lookup collection. This is the first item of "what would come next" in
`docs/not-done.md`: without it, a directory shared with Python is limited to databases whose
Python side uses no indexes, because protoST cannot change those collections.

### 1.2 What this feature is for

1. **Close the shared-directory gap.** A collection that `proto_db` indexed can be changed from
   protoST, with its indexes kept in step, and merged onto by a blind write, exactly as
   `proto_db` does. Indexes written by either side are read and maintained by the other.
2. **Answer questions without reading everything.** A declarative query (a predicate, an order,
   a window) is planned against the collection's indexes and answers the same multiset a scan
   would, at a cost that depends on what it returns, not on what is stored.
3. **Teach.** Course material is a goal. The chapters and the guide show the reasoning: the
   obvious solution, why it fails, and the measured alternative. Section 1.3 lists the ones this
   feature can show with real numbers from both implementations.

### 1.3 The obvious solutions, why they fail, and the alternatives (course material)

Each row becomes a section of a tutorial chapter or of the guide (section 8), with its own
measurement from `bench/` (section 7). The figures do not exist yet; the chapters quote them only
after they are measured.

| Question | The obvious solution | Why it fails | The alternative, and what is measured |
|---|---|---|---|
| How do I find the people in Oslo? | Walk the collection and test each element. | Cost is the size of the collection, whatever the answer. | An equality index. Measured: lookup time against collection size, indexed and scanned (bench Q1). |
| Who keeps the index? | The program keeps a second root (`byCity`) and updates it in the same transaction, as chapter 4 does today. | Every writer must remember it, in both languages; a blind write that merges the data root does not merge the program's idea of the index; nothing checks that the two agree. | The index is part of the collection version: every mutator returns content and indexes computed in one step (`proto_db` `collections/base.py:1-13`). There is no code path that returns a stale index. Measured: a contract test that compares every index with a scan after random mutator sequences. |
| When is the index updated? | At commit time, in the publisher, for the roots that changed. | An uncommitted version (what the transaction reads back) would disagree with its own index; a snapshot could see an index ahead of or behind its data. | Path copying: the index is an immutable tree beside the data, each version shares unchanged subtrees with the last. Measured: the extra cost per write with 0, 1 and 3 indexes (bench M1), so the reader sees what "index what you query" costs. |
| Can a blind write still merge? | Replace the indexed root, as the prototype would have done had it not refused. | Last writer wins: a concurrent commit's change is lost silently. | Replay the transaction's intent through the public mutators onto the current version, which maintain the current indexes (`proto_db` `collections/base.py:594-631`). Measured: merge replay cost onto an indexed current (bench M3). |
| Should the planner use an index whenever one exists? | Yes, an index is faster. | Not always: an index pays a descent per value looked up and a visit per key group, so for an unselective predicate (a wide range, an `in` of most keys) reading every element once can cost less. | A cost model: one unit per row produced, per key group visited and per tree level descended (`keyed.py:596-622`). Even `!=`, which reads almost everything, is charged n + G + 1 by the index complement against 2n for a scan plus a filter, so the complement wins whenever the index has fewer than n − 1 key groups (`test_ne_term_alone_prefers_the_index_complement_over_scan_plus_filter`: 211 against 400). Measured: whether real timings cross where the model says they do (bench P2). The model's own crossover for a tiny collection is only one or two elements, so P2 is not a search for a "small collection" threshold. |
| Is `not (x = 5)` the same as `x ~= 5`? | Rewrite it to use the index. | An element without `x` satisfies the first and not the second (absence is not a value, D28). | Negations stay residual filters; only `not isNone` becomes `notNone`, the one exact rewrite (`planner.py:98-126`). Shown by an example, not a benchmark. |
| Two indexed conjuncts: intersect the two index results? | Yes, use both indexes. | Under the cost model an intersection always costs at least a filter over the better input (`planner.py:52-55`). | One access path plus residual filters. Measured: both plans built by hand on the same data (bench P3), to show whether the model's claim holds at protoST's speed too. |
| Page 50 of an ordered report? | Run the query, skip 49 pages. | Cost grows with the page number; a concurrent commit shifts rows between pages. | Rank access on weighted trees, O(log n + page size), on one snapshot (`keyed.py:35-41`, `pager.py:1-11`). Measured: time of page k for k = 0 .. last, by rank and by skipping (bench Q5). |

---

## 2. Reference inventory

Status is protoBaseST's at `02d9826`: **exists** (ported and tested), **read only** (decoded,
never written or used to answer), **partial**, or **missing**. Python citations are `proto_db/`
paths at `b99285b` (= `v2.0.0rc4` for these files).

### 2.1 Index framework and kinds

| `proto_db` feature | Python | protoBaseST status |
|---|---|---|
| `Index` base: immutable atom, `name`, `key_spec`, `_definition`, `_with` | `indexing/base.py:56-215` | **Read only.** `PBIndex` (`indexes.st`) decodes `name`, `key_spec`, `member_tokens`. No `_with`, no new versions. |
| Abstract hooks `with_added`, `with_removed`, `supports`, `estimate`, `plan` | `base.py:240-261` | **Missing.** |
| Defaults `supports_order`, `ordered_plan`, `supports_filtered`, `filtered_plan`, `with_replaced`, `empty`, `build`, `explain`, `validate` | `base.py:265-338` | **Missing.** (`filtered_*` serve vectors only: out of scope.) |
| `has_current_tokens` (format-3 member tokens, D58) | `base.py:287-291`, `keyed.py:397-400` | **Exists** as `hasMemberTokens` (`indexes.st`), with `proto_db`'s comparison of `member_tokens == 1`. |
| `_plan_cacheable` / `_plans_deterministic` (D56) | `base.py:141`, `219-225` | **Missing** (only the query cache uses it; deferred with the cache). |
| `element_identity` | `base.py:22-53` | **Missing.** Needed by `validate`, `Union`, `Intersect`, `Distinct`. |
| `KeySpec`: `path`, `element`, `extractor`; `extract`, `term_path`, `describe`, `to_data` / `from_data` | `indexing/keyspec.py:165-267` | **Partial.** The persisted `(kind, arg)` tuple is kept raw (`PBIndex >> keySpec`); no `PBKeySpec` class, no validation, no extraction. |
| Path step semantics: own attributes of records, mapping keys, `MISSING` when absent, private and reserved names never read | `keyspec.py:149-162` | **Missing.** `PBObject >> at:` answers `nil` for an absent attribute, so the step needs a probe that tells absence from `nil` (`hasDefinedAttr:` exists). |
| Extractor registry: `register_extractor(name, fn, version=)`, `unregister_extractor`, generations, versions | `keyspec.py:42-146` | **Missing.** |
| `KeyGroupIndex` structure: `groups` (weighted keyed AVL of key groups), `side` (unorderable keys), `total_count`, `member_tokens` | `indexing/keyed.py:1-41`, `375-395` | **Read only.** `PBKeyGroupIndex` decodes the fields. |
| Member keys `((0, element) | (1, surrogate), exact_token)`; `surrogate`; equal-member bounds | `keyed.py:81-158` | **Partial.** `PBKeys exactToken:` and `orderKey:` exist (`keys.st:245`, `511`); `surrogate` and the member-key functions are missing. |
| Member-key depth check (`MAX_VALUE_DEPTH`, wrapping constants) | `keyed.py:161-215` | **Partial.** `PBCodec valueDepth:` and `maxValueDepth` exist (`codec.st:54-86`); the index-specific limits are missing. |
| Group operations `group_add`, `group_remove`, `group_iter` | `keyed.py:220-258` | **Missing.** |
| `with_added`, `with_removed`, bulk `build` (group, sort, balanced trees) | `keyed.py:404-457` | **Missing.** |
| Plan parts per operator (`IndexLookup`, `IndexRange`, `IndexComplement`) | `keyed.py:461-533` | **Missing.** |
| Rank access: segments, `window`, `exact_rows`, `sorted_rank` | `keyed.py:266-336`, `535-592` | **Missing.** |
| Cost model (D30) `estimate` | `keyed.py:596-622` | **Missing.** |
| `_ordered_plan` (`IndexOrderedScan`) | `keyed.py:626-647` | **Missing.** |
| `explain`, structural `validate`, misfiled detection | `keyed.py:651-737` | **Missing.** |
| `EqualityIndex` (`==`, `in`, `!=`, `?N`, `?!N`) | `indexing/equality.py:23-35` | **Read only.** |
| `RangeIndex` (also `<` `<=` `>` `>=`, four `between`; ordered iteration) | `indexing/range.py:33-58` | **Read only.** |
| `VectorIndex`, backends, `near[]` | `indexing/vector.py`, `vector_backends.py` | **Read only. Excluded** (section 3.3). |

### 2.2 Persistent trees the indexes need

| `proto_db` feature | Python (`collections/avl.py`) | protoBaseST status |
|---|---|---|
| `CountedKeyNode` (value `(payload, count)`, `weight`) | `:251-272` | **Exists** (`avl.st:241-260`, `491-498`): read, built by `keyPut:` with the weight. |
| `key_get` / `key_put` / `key_remove` | `:513-580` | **Exists** (`PBAvl keyAt:key:`, `keyPut:key:value:nodeClass:`, `keyRemove:key:`). |
| `key_iter` | `:582` | **Exists** (`keysAndValuesDo:over:`). |
| `key_iter_okey_range`, `key_iter_reversed`, `key_count_below` | `:604-671` | **Missing.** |
| `key_from_sorted`, `key_from_sorted_okeys` (balanced bulk build) | `:673-706` | **Missing** for keyed trees (`posFromArray:` exists for positional ones). The shape must be `proto_db`'s `_build_balanced` (`:492-504`) so a bulk build writes the same nodes. |
| `key_weight`, `key_weight_below`, `key_iter_from_weight` | `:713-786` | **Missing.** |
| `pos_iter_from`, `key_iter_from` (scan windows of `List` and `Dictionary`) | `:788-806` | **Missing.** |

### 2.3 Collections and indexes

| `proto_db` feature | Python (`collections/base.py`) | protoBaseST status |
|---|---|---|
| `IndexSet` (`get`, `names`, `with_index`, `without`, `on_add`, `on_remove`, `on_replace`, `rebuilt_stale`, `rebuilt_all`) | `:146-238` | **Partial.** `PBIndexSet` reads (`names`, `get:`, `size`, `isEmpty`; `collections.st:166-200`); no writes. |
| `add_index`, `remove_index`, `get_index`, `index_names` | `:341-368` | **Partial.** `getIndex:`, `indexNames` exist; `addIndex:`, `removeIndex:` missing. |
| Every mutator computes content and `IndexSet` in one step (`_after_add`, `_after_remove`, `_after_removes`, `_after_replace`, `_current_indexes`) | `:450-473`; the mutators in `lists.py`, `dictionaries.py`, `hash_dictionaries.py`, `sets.py` | **Missing.** Every mutator refuses instead (`_checkWritable:`). |
| Stale (format-3) indexes rebuilt before the first change (D58) | `:207-219`, `450-454` | **Missing** (`not-done.md`: "No rebuilding of format-3 indexes"). |
| `elements()` (what indexes see) | `:291-293` | **Exists** (`elements`, `do:`; a dictionary's values, a set's members). |
| `as_query_plan`, `_scan_window` | `:370-378`; `lists.py:61`, `dictionaries.py:108` | **Missing.** |
| `validate()`, `rebuilt()` (misfiled format-3 repair) | `:408-448` | **Missing.** |
| Op log records index-definition changes (`@index_add`, `@index_remove`) | `:42-44`, `572-573` | **Missing.** `_PBOpLog` logs element ops only. |
| `rebase_onto` replays element ops through index-maintaining mutators, then index-definition ops, `ProtoConflictError` for an index created concurrently | `:594-631` | **Partial.** Element replay exists; onto an indexed current it is refused; index-definition replay missing. |
| Transaction merge rule `_merged` | `transactions.py:3217-3223` | **Exists** (`transactions.st:671-675`), but refused onto an indexed current through `rebaseOnto:`. |
| Merges resolve extractors on the committing transaction's behalf, registries pre-built outside the lock | `transactions.py:2865-2873`, `3136-3145` | **Not applicable as such** (no runtime registry in protoBaseST, format 5 refused); application code in the publisher is allowed for extractors by ruling IQ1 (9.2). |

### 2.4 Term and expression language

| `proto_db` feature | Python | protoBaseST status |
|---|---|---|
| Operators `==` `!=` `<` `<=` `>` `>=` `in`, four `between`, `?N` `?!N`, `contains`, `?T` `?!T`, `near[]` | `query/terms.py:59-89` | **Missing** (`near[]` excluded). |
| `Term(path, op, value)`: validation, canonical operands, `in` over a set sorted by order key, equality by `values_equal` | `terms.py:152-213` | **Missing.** |
| `Term.matches` (the scan oracle, D28 semantics) | `terms.py:215-253` | **Missing.** |
| `contains` semantics | `terms.py:282-301` | **Missing.** |
| `describe`, `display_value` (explain rendering) | `terms.py:255-333` | **Missing.** |
| `to_list` / 0.1 prefix list syntax | `terms.py:259-279`; `expressions.py:28-39`, `293-357` | **Missing.** |
| `And`, `Or` (flattened, n-ary), `Not` (`Not(Not(e)) = e`) | `query/expressions.py:98-210` | **Missing.** |
| `PythonPredicate` (opaque leaf) | `expressions.py:213-264` | **Missing**; its protoST counterpart is a block predicate (5.5). |
| `evaluate`, `iter_terms` | `expressions.py:267-290` | **Missing.** |

### 2.5 Planner and plan operators

| `proto_db` feature | Python | protoBaseST status |
|---|---|---|
| `normalize` (De Morgan, flatten, only `Not(?N)` <-> `?!N` rewritten) | `query/planner.py:98-126` | **Missing.** |
| Candidates: full scan with every conjunct residual; per conjunct, the cheapest supporting index with the rest residual | `planner.py:195-218`, `236-248` | **Missing.** |
| Ranking: cost, then scans last, then sorted tuple of index names | `planner.py:148-175` | **Missing.** |
| Disjunction: `Union` only if every branch has an index-only plan | `planner.py:250-261` | **Missing.** |
| Order: one key may use an ordered index scan with the whole predicate as residual, competing with `Sort` | `planner.py:263-275` | **Missing.** |
| `plan_query(source, where, order_by, limit, offset)` and argument checks | `planner.py:278-343` | **Missing.** |
| `near[]` rules, `filtered_knn` | `planner.py:15-26`, `199-234` | **Excluded.** |
| `Estimate`, `QueryPlan` (`execute`, `explain`, `estimate`, `window`, `exact_rows`) | `query/plans.py:75-177` | **Missing.** |
| `CollectionScan`, `ValuesScan` | `plans.py:222-281` | **Missing.** |
| `IndexPlan`, `ordered_index_scan` | `plans.py:284-386` | **Missing.** |
| `Filter` (selectivity 0.5 per term, D36) with rank access over an ordered scan; `PythonFilter` | `plans.py:67-68`, `439-534` | **Missing.** |
| `Union` (max multiplicity), `Intersect` (min multiplicity) by `element_key` | `plans.py:96-99`, `537-608` | **Missing.** |
| `Project`, `Sort` (stable, total order, unorderable last), `Limit` (by rank when possible), `Count` (by rank), `Distinct` | `plans.py:611-880` | **Missing.** |
| `GroupBy`, `Join`, `Unnest` | `plans.py:883-1101` | **Missing.** Deferred (3.2). |
| `VectorSearch` | `plans.py:389-436` | **Excluded.** |

### 2.6 Front end, paging, cache

| `proto_db` feature | Python | protoBaseST status |
|---|---|---|
| LINQ `from_collection`, `Queryable` (immutable, lazy): `where`, `select`, `order_by`, `then_by`, `skip`, `take`, `distinct`, `group_by`, `join`, `select_many`, `plan`, `explain`, `to_list`, `count`, `first`, `first_or_none`, `pager` | `query/linq.py:906-1189` | **Missing.** |
| `F` field builder, `Predicate` (pure or holding Python parts), splitting impure conjuncts into `PythonFilter`s | `linq.py:169-358`, `600-734` | **Missing.** |
| Computed values (`lower`, `upper`, `length`, `abs`, arithmetic), `startswith`, `endswith`, field-to-field comparisons | `linq.py:484-597`, `678-711` | **Missing.** Deferred (3.2). |
| `Agg` aggregations | `linq.py:757-839` | **Missing.** Deferred with `GroupBy`. |
| `Pager` (one plan, one snapshot, by rank or materialised) | `query/pager.py:136-227` | **Missing.** |
| Portable pager tokens (`Transaction.pager`, `Snapshot.pager`, `Database.resume_pager`, `ProtoStalePagerError`) | `pager.py:13-25`, `230-294`; `transactions.py:506-516`, `2370-2387`, `2583-2595` | **Missing** (and `snapshot_ref` is missing too, `not-done.md`). Deferred (3.2, 10.1 R5). |
| Query result cache (keys by pointers, `QUERY_SEMANTICS_VERSION`, `query_cache_stats`) | `query/cache.py:1-533`; `transactions.py:2015`, `2043-2050` | **Missing.** Deferred (3.2). |

### 2.7 Persistence, commit and cluster

| Aspect | `proto_db` | protoBaseST status |
|---|---|---|
| Indexes persist as ordinary atoms under their type names, reachable from the collection's `indexes` field; no separate index file, no commit-time step | `base.py:56-66`; `collections/base.py:146-160`; `indexing-framework.rst` "The model" | **Read side exists** (the conformance `database` vector holds `by_city` and `by_age`, records 20-29). |
| Index maintenance happens in the mutators, inside the transaction; only a merge replays mutators during the commit's build | `collections/base.py:1-13`; `transactions.py:3217-3223` | **Missing** (refused). |
| Cluster mode: no index-specific message, no index-specific rule. The wire messages named `query` and `commit_query` are **not database queries**: `query` asks a peer for its acceptor state (`rid`, `inc`, `ballot`, `vs`), `commit_query` asks where the records of a commit are (Phase D) | `cluster/protocol.py:113-118`, `231`, `236` | `query` is ported (lease and rejoin); `commit_query` is decoded and ignored at DEPTH = 0 (`deviations.md`, "Cluster wire messages"). Nothing to add for this feature (5.8). |

---

## 3. Scope

### 3.1 Ported in this feature

1. **Key specs and extractors:** `PBKeySpec` (path, element, extractor), its validation, its
   extraction with `proto_db`'s step semantics, and a process-wide extractor registry with names
   and declared versions.
2. **Index maintenance** for `PBEqualityIndex` and `PBRangeIndex` (the key-group indexes): the
   element hooks, the bulk build, structural `validate:`, explain, and the weighted trees with rank
   access.
3. **Collections with indexes:** `addIndex:`, `removeIndex:`, index maintenance in every mutator
   of `PBList`, `PBDictionary`, `PBHashDictionary`, `PBSet` and `PBCountedSet`; stale (format-3)
   key-group indexes rebuilt before the first change; index-definition ops in the operation log;
   merges (`rebaseOnto:`) onto indexed currents; collection `validate`.
4. **The term and expression language:** every operator except `near[]`, `matches:` with D28
   semantics, `And` / `Or` / `Not`, the 0.1 prefix list syntax (both directions), `describe`.
5. **The planner** (`normalize`, access paths, the cost model, ties, unions, order) and the plan
   operators `CollectionScan`, `IndexPlan` (lookup, range, complement, ordered scan), `Filter`,
   `BlockFilter` (the counterpart of `PythonFilter`), `Union`, `Intersect`, `Project`, `Sort`,
   `Limit`, `Count`, `Distinct`, with `explain` in `proto_db`'s shape.
6. **The query front end** (`PBQuery`, the field builder `PBField`), section 5.5.
7. **In-process paging** (`PBPager`): by rank when the plan offers it, otherwise materialised once.

### 3.2 Deferred, and why

| Item | Why deferred | What it would take |
|---|---|---|
| Portable pager tokens, `resumePager:`, `snapshot_ref` | The token's plan digest is BLAKE2b-128 of the Python `repr()` of a nested tuple (`cache.py:264-303`). Reproducing Python's `repr` of floats, strings, `Decimal` and nested tuples byte for byte in protoST is fragile and is not a format anyone specified. Without it a token from one language is refused by the other. | A proposal to `proto_db` (IQ7, kept as a proposal, not sent): a digest over a canonical msgpack encoding of the plan key. Then a separate, small plan. |
| Query result cache | It is an optimisation whose soundness rests on the key covering everything a result depends on (`cache.py:1-49`: pointers, extractor generations, the decimal context). Its value at protoST's speed is unmeasured, and a wrong key returns a wrong answer silently. | Port after the planner is measured, with `proto_db`'s soundness property tests (`tests/property/test_query_cache_soundness.py`). |
| `GroupBy` / `Agg`, `Join`, `Unnest` (`select_many`), `ValuesScan` | Execution operators, not optimisation: no index is involved and the planner never chooses them. They are straightforward ports with their own semantics to test (aggregate typing, `MISSING` groups). | A follow-up task list over the same plan classes. |
| Computed values, `startswith` / `endswith`, field-to-field comparison | In `proto_db` they are not terms: they always become a `PythonFilter` (`linq.py:37-46`). A protoST block predicate does the same job today (5.5). | Port if the workshop asks for them. |
| `RepeatedKeysDictionary` writes | A non-goal of the prototype (`deviations.md`), unchanged. An indexed one is still refused. | Its own task. |
| Collection `rebuilt` (misfiled format-3 repair) | A repair tool for damage format 3 left; `validate` reports it (`PBMisfiledError` is new, 5.3). | Port with `validate`'s misfiled checks if a real format-3 database needs it. |

### 3.3 Excluded: vector indexes and vector search

The `near[]` operator, `PBVectorIndex` writes and training, `VectorSearch`, `filtered_plan` and
the planner's kNN rules (`planner.py:15-26`, `199-234`) are **out of scope**. Consequences, all
explicit:

- A collection holding a `PBVectorIndex` keeps refusing every change with `PBNotSupportedError`
  naming the vector index, and so does a merge onto one. Maintaining its other indexes and not
  the vector one would write a stale index.
- A collection holding an index of a type protoBaseST does not know (an opaque atom: a custom
  `proto_db` index kind) refuses changes the same way.
- A term with the operator `near[]` is `PBNotSupportedError` when built, naming the exclusion.
- A `PBVectorIndex` never answers `supports:` with true, so the planner never offers it.

---

## 4. Required deliverables and acceptance criteria

These are the maintainer's requirement of 2026-11-18 and are **binding**: the feature is not done
until each criterion holds. Each is owned by the tasks named in section 11.

**Documentation first (maintainer's priority, 2026-11-18).** For the conceptual description the
documentation matters more than the code, so the conceptual guide (D2) and the tutorial chapters
(D3) are drafted **before any implementation task**, against the API this spec approves. Their
code samples are marked pending until the API lands; each later implementation task turns its
chapter's samples into runnable examples and tests (D4) and replaces the "not measured yet"
markers with its measured figures (D5). The drafts keep the course-material form of 1.3 (the
obvious solution, why it fails, the measured alternative); a figure that has not been measured is
marked as such and never invented.

| # | Deliverable | Acceptance criteria |
|---|---|---|
| D1 | **Reference documentation** in `docs/reference.md` | Every new public class and every public message (sections 5.2 and 5.5) is listed with its arguments, its answer and the errors it signals. `tests/docs/reference_selectors.sh` passes with no allowance for the new selectors; every selector the new chapters and the guide cite exists in `src/protobase`. |
| D2 | **Conceptual guide** `docs/queries.md` | Explains the index model (an index is part of the version), key specs and `MISSING`, exactness (the index-equals-scan invariant), the expression language and D28 semantics, the planner (normalisation, candidates, cost model, ties, unions, order), paging by rank, and **how to read `explain`**: every node kind, every field, and three worked plans with their estimates. Every code block in it runs (a program under `examples/queries/` it quotes, checked by the sync test). Reviewed against `proto_db`'s `indexing-framework.rst` and `query-planner.rst` for semantic agreement, with each deliberate difference linked to `deviations.md`. |
| D3 | **Tutorial chapters** in `docs/tutorial/`, linked from `README.md` and `docs/tutorial/README.md` | The chapters of section 8.2. Each follows the house form (one program, quoted code checked against it) and includes at least one "obvious solution, why it fails, measured alternative" section from 1.3 with figures quoted from `docs/deviations.md#performance`. Chapter 4 and chapter 12 are updated so no chapter still says indexes are refused for writes. |
| D4 | **Runnable examples** in `examples/queries/` (and the chapter programs in `examples/tutorial/`) | Each example checks its own results (the house `lesson check:` style) and is run by `tests/run_tests.sh`. At least: indexes and lookups, ranges and ordered reads, compound predicates (AND / OR / NOT) with `explain`, paging, a merge onto an indexed root, and Python interop (a Python-written indexed collection changed from protoST and validated by Python). |
| D5 | **Performance tests** under `bench/` | The workloads of section 7.3: indexed against full scan per query shape (equality, `in`, range, AND, OR, ordering with paging), index maintenance on commit, planner overhead, and protoBaseST against `proto_db` on the same workloads. Every run prints the work it did (rows, queries, the plan chosen, a checksum of the results) and the runner refuses a run whose counts or checksums differ from the model or between implementations. The methodology is documented in the runner's header and in `docs/deviations.md#performance`, where the dated results are recorded with machine, load, commits and binaries. |
| D6 | **Conformance and interop tests** (section 6) | Format vectors and query vectors pass in both directions; the expected-differences table is empty for this feature or lists each difference with its reason. |
| D7 | **Decision records** | Every call of section 9.1 and every ruling of section 9.2 is entered in `docs/decisions.md`; every deviation in `docs/deviations.md`; `docs/not-done.md` updated (indexes and queries leave the "not done" list; the deferred items of 3.2 enter it). |

---

## 5. Design in protoST terms

### 5.1 Principles applied

- **`proto_db` is the reference** (decisions.md, the rule above all). Semantics, plan choices,
  `explain` keys and node names follow it; a difference is a deviation with its reason.
- **Refuse, never diverge.** Anything the port cannot do exactly (a vector index, an unknown index
  kind, an unregistered extractor) is an explicit error naming it.
- **Immutability.** Every index hook answers a new index; plans are immutable once built; a
  query object answers a new query on every message.
- **No locks in the Smalltalk layer.** Plans hold only immutable values, so they run on any
  thread or actor. The extractor registry is one `Atom` holding an immutable map, changed by
  compare-and-swap.
- **No change to protoCore or protoST** (memory rule; confirmed by ruling IQ4).

### 5.2 Classes and their responsibilities

New module files, all under `src/protobase/`: `keyspec.st`, `keygroups.st` (the key-group
machinery), `terms.st`, `plans.st`, `planner.st`, `query.st`, `pager.st`; `avl.st`,
`indexes.st`, `collections.st` and `transactions.st` change.

| Class | `proto_db` counterpart | Responsibility |
|---|---|---|
| `PBKeySpec` | `KeySpec` | A frozen `(kind, arg)`: `path:`, `element`, `extractor:`, `forTermPath:`; `extract:` (answers the key or `PBMissing default`), `termPath`, `describe`, `asData` / `fromData:` (the persisted tuple). Compares by value. |
| `PBKeySpec class` registry | `register_extractor` and friends | `registerExtractor: aName block: aBlock version: aStringOrNil`, `unregisterExtractor:`, `extractorVersion:`. Process-wide, one `Atom` of an immutable dictionary. Rebinding a name to another block or version is `PBValidationError`. |
| `PBIndex` | `Index` | `keySpec` keeps answering the persisted tuple (the 0.1.0 API); the new `keySpecObject` answers it as a `PBKeySpec` (maintainer, 2026-11-18). Gains `withAdded:`, `withRemoved:`, `withReplaced:with:`, `supports:`, `estimate:`, `plan:`, `supportsOrder:`, `orderedPlan:`, `empty`, `build:`, `explain`, `validate:`; `_with:` builds a new unsaved version (as `PBIndexedCollection >> _withChanges:log:complete:` does). Abstract hooks signal `PBUserError` ("subclass responsibility"). |
| `PBKeyGroupIndex` | `KeyGroupIndex` | Groups, side group, member keys, rank segments, cost model. `name:keySpec:` (the primitive; it takes a `PBKeySpec`) makes an empty index with `member_tokens` 1; `name:path:` is a convenience for `name: n keySpec: (PBKeySpec path: p)`. |
| `PBEqualityIndex`, `PBRangeIndex` | `EqualityIndex`, `RangeIndex` | Supported operators; `PBRangeIndex` adds ordered iteration. |
| `PBVectorIndex` | `VectorIndex` | Unchanged, read only; `supports:` answers false; it makes its collection refuse writes. |
| `PBIndexSet` | `IndexSet` | Gains `withIndex:`, `without:`, `onAdd:`, `onRemove:`, `onReplace:with:`, `rebuiltStale:`. |
| `PBIndexedCollection` | `IndexedCollection` | Gains `addIndex:`, `removeIndex:`, `validate`, `asQueryPlan`, `_scanWindowFrom:to:`; `_checkWritable:` narrows to vector and unknown index kinds. |
| `PBTerm` | `Term` | `path:op:value:` and `path:op:`; operators as `proto_db`'s strings (`'=='`, `'between[]'`, `'?N'`...), so the list syntax and explain read the same in both languages; `matches:`, `describe`, `asList`. |
| `PBAnd`, `PBOr`, `PBNot` | `And`, `Or`, `Not` | n-ary, flattened, immutable; `evaluate:` (via `matches:`), `describe`, `asList`. |
| `PBBlockPredicate` | `PythonPredicate` | An opaque predicate: a block and a description. |
| `PBExpression class >> compile:` | `Expression.compile` | The 0.1 prefix list syntax, from an `Array`. |
| `PBEstimate` | `Estimate` | `rows`, `cost`: finite non-negative Floats. |
| `PBQueryPlan` and subclasses `PBCollectionScan`, `PBIndexPlan`, `PBFilter`, `PBBlockFilter`, `PBUnion`, `PBIntersect`, `PBProject`, `PBSort`, `PBLimit`, `PBCount`, `PBDistinct` | `plans.py` | `execute` (a new stream each time; `do:` evaluates a block per row), `explain` (a `PBFrozenDict` with `proto_db`'s keys), `estimate`, `windowFrom:to:`, `exactRows`. |
| `PBPlanner` | `planner.py` | `PBPlanner plan: aCollectionOrPlan where: anExpression orderBy: keys limit: n offset: m`; `normalize:`. Pure function of its arguments. |
| `PBQuery`, `PBField` | `Queryable`, `F` / `Field` | The front end (5.5). |
| `PBPager` | `Pager` | `on: aPlanOrQuery pageSize: n`; `rows`, `pages`, `page: k` (zero-based, as `proto_db`), `byRank`, `explain` (`pager` → `page_size`, `by_rank`; `plan` → the plan's explain; no `portable`, since tokens are deferred). No `token` (deferred). |
| `PBMisfiledError` | `ProtoMisfiledError` | New error, a `PBCorruptionError` subclass, as in `proto_db`. |

`MISSING` already exists as `PBMissing default` (format kind `@missing`, design spec 4.1); it
becomes visible API as the answer of `extract:` and of a projected absent field.

### 5.3 Index maintenance under immutability and the transaction model

**Where it happens.** Exactly where `proto_db` does it: inside each mutator, in the transaction's
own thread, before commit. `PBDictionary >> setAt:value:` computes the new tree, then the new
`PBIndexSet` with `onReplace: old with: new` (or `onAdd:`), and answers one new version holding
both (`collections/base.py:456-473`). There is no commit-time index step, so a version a
transaction reads back always agrees with its own indexes, and a snapshot's indexes are the
snapshot's.

**Per collection** (the element an index sees is what `elements` answers today):

| Collection | Index work per mutator (as in `proto_db`'s mutators) |
|---|---|
| `PBList` | `appendLast:` / `insertAt:value:` add; `setAt:value:` replaces; `removeAt:` removes; `extend:` adds each; `sliceFrom:to:`, `head:`, `tail:` answer a new collection whose indexes are the same definitions rebuilt (`empty build:`) over the slice (`lists.py:133-147`); a list without indexes keeps its index set. |
| `PBDictionary`, `PBHashDictionary` | `setAt:value:` adds the value for a new key, replaces it for an existing key; `removeAt:` removes the value of a present key. |
| `PBSet` | `add:` of an absent element adds; `remove:` of a present one removes; set algebra folds those. |
| `PBCountedSet` | an add event when an element appears (count 0 to n > 0); a remove event of the stored element when it disappears (to 0); nothing while the count stays positive (`sets.py:352-373`). |

*Corrected at Task 4a:* the original table did not match `proto_db` rc4 (it had slices remove
what they drop and a `PBCountedSet` fire one event per occurrence); node identity
(`tests/interop/index_ops_identical.sh`) confirms the Python reading.

The port takes the exact hook order from each Python mutator (`lists.py`, `dictionaries.py`,
`hash_dictionaries.py`, `sets.py`), because the order of `with_added` / `with_removed` calls
decides the shape of the persisted trees, and the conformance of 6.2 compares nodes.

**Blind writes.** A mutator call that changes nothing (adding a present set member) answers a
new version with the extended log and the receiver's indexes, with no index work
(`collections/base.py:513-519`).

**Stale indexes.** Before the first change, an index with `hasMemberTokens` false is rebuilt from
the elements (`_current_indexes`, `:450-454`, D58). This closes the not-done item "No rebuilding
of format-3 indexes" for key-group indexes; a stale vector index still refuses (3.3).

**Index-definition changes in the log.** `addIndex:` logs `('@index_add' name index)` and
`removeIndex:` logs `('@index_remove' name)` on the `ConcurrentOptimized` classes, never on
`PBList` (`:572-573`). `_PBOpLog`'s net-effect reduction keeps element ops and index ops apart, as
`rebase_onto` does (`:610-612`).

**Merges.** `rebaseOnto:` replays the net element ops through the public mutators of `current`,
which maintain `current`'s indexes, then the index-definition ops per name, with
`PBConflictError` for an index this log created that `current` also has (`:594-631`). The refusal
in `rebaseOnto:` moves from "any index" to "a vector or unknown index". The publisher's merge
(`transactions.st:671-675`) needs no other change. **This runs during the commit's build**, in
the publisher (standalone) or the round's build (cluster), so a path key spec reads atoms there
and an extractor key spec runs its block there. Ruling IQ1 (9.2): this is allowed, as in
`proto_db`; the exception the extractor raises passes through unchanged and fails only that
commit, and purity is a documented contract. The publisher's module comment ("runs no
application code") is amended to name this one exception.

**Unsaved atoms.** A new index version is an unsaved atom like a new collection version
(`PBAtom >> oid` drawn on need, D21). Its trees hold elements (atoms by reference) in member keys.
The writer already saves dependents first (`tests/unit/write_dependents_first.st`); the index
trees are new dependents of the collection, saved by the same walk.

**Threads.** Indexes and plans are immutable values, so a query runs on any actor. Extractor
blocks must be pure and thread-safe (they may run on the publisher's worker); the registry
documents it as `proto_db`'s does (`keyspec.py:60-83`).

### 5.4 On-disk format compatibility

There is no new format and no new record type: the indexes are format-4 atoms that protoBaseST
already decodes. Writing them means producing exactly what `proto_db` writes:

| Field (persisted order) | Content |
|---|---|
| `name` | a String |
| `key_spec` | the `(kind, arg)` tuple: `('path' 'a.b')`, `('element' nil)`, `('extractor' name)` |
| `groups` | nil or a `PBCountedKeyNode` tree keyed by the extracted key (by order key; `PBMissing` and `nil` are ordinary keys at the bottom of the order); each value a group `(members, total)` |
| `side` | the group of every element whose key is unorderable |
| `total_count` | an Integer |
| `member_tokens` | 1 |

A group's `members` is a `PBCountedKeyNode` tree from member key `((0, element) | (1,
surrogate), exactToken bytes)` to `(element, count)`. The attribute order of a new index is the
order `proto_db`'s constructor and `_with` set them; `PBIndex >> persistedFields` already lists
it. The rules that make the bytes equal:

1. **Same keys.** `PBKeys orderKey:` and `exactToken:` are already conformance-tested against
   `proto_db`'s `order`, `exact_tokens` and `atom_tokens` vectors; `surrogate` and the member key
   are new and get their own vectors (6.1).
2. **Same tree shapes.** Incremental changes use `keyPut:` / `keyRemove:`, which are
   node-identical to `proto_db` (`tests/interop/avl_ops_identical.sh`). The bulk build
   (`addIndex:`, `build:`, stale rebuild) must reproduce `key_from_sorted_okeys` and
   `_build_balanced`; a test compares the nodes.
3. **Same hook order** in every mutator (5.3).

**Rule for what cannot be maintained:** a collection holding a vector index or an unknown index
kind is read and refused for writes (3.3); a key-group index with format-3 tokens is rebuilt on
first change. An index built by `proto_db` with an extractor that this process has not registered
is read, and a query whose plan never extracts a key (an index access path with no residual
filter on the extractor's path) runs, because a lookup reads only the trees; a query whose plan
does extract (a scan, or a residual filter on `@name`) signals, and so does any change that
evaluates the extractor (an add, remove or replace event on that index, a rebuild) or a
`validate:` (corrected at Task 4a: `proto_db` checks the registry only inside `KeySpec.extract`,
`keyspec.py:232`, so a blind write, `removeIndex:` or an `addIndex:` of another index pass):
`proto_db`'s error, `PBValidationError`
naming the extractor and telling the program to register it (`keyspec.py:139-146`). It is never
rebuilt or dropped silently.

### 5.5 The public query API

**Defining indexes:**

```smalltalk
people := people addIndex: (PBEqualityIndex name: 'by_city' path: 'city').   "convenience: one path"
people := people addIndex: (PBRangeIndex name: 'by_age' keySpec: (PBKeySpec path: 'age')).
PBKeySpec registerExtractor: 'name_length' block: [:p | (p at: 'name') size] version: '1'.
people := people addIndex: (PBRangeIndex name: 'by_name_length' keySpec: (PBKeySpec extractor: 'name_length')).
```

**Predicates.** The builder (ruling IQ2) uses keyword selectors for equality and keeps the
binary comparisons, because overriding `=` on a builder breaks every collection that compares it:

```smalltalk
city := PBField path: 'city'.                    "PBField element, PBField extractor: 'name_length'"
(city eq: 'Oslo')                                "==        ne: is !="
((PBField path: 'age') between: 30 and: 35)      "between[]; betweenOpen:and: is between(), betweenLeftOpen:and: between(], betweenRightOpen:and: between[)"
((PBField path: 'age') > 70)                     "< <= > >= answer predicates (the receiver is the field)"
(city in: #('Lima' 'Rome'))                      "in"
((PBField path: 'address.zip') isNone)           "?N; notNone, isTrue, notTrue, contains:"
((city eq: 'Oslo') & ((PBField path: 'age') > 70))   "& | and not combine expressions only; and: / or: are not used"
```

A plain block enters a query only through `where:` (`q where: [:p | (p at: 'age') \\ 7 = 0]`);
`&`, `|` and `not` take expressions only. Chained `where:` calls combine with AND. A block is
opaque, becomes a `BlockFilter` in `explain` (the counterpart of `PythonFilter`, named after the language
that runs it, a deviation), and never uses an index. The house mixing rule is `proto_db`'s: in a
top-level AND, pure conjuncts go to the planner and each block becomes its own filter on top; an
OR or NOT holding a block is one block filter for the whole predicate (`linq.py:48-61`).

**Queries.** `PBQuery` is immutable, like every value of the library: each message answers a new
query.

```smalltalk
q := PBQuery from: people.
q := (q where: (city eq: 'Oslo')) orderBy: 'age'.
(q take: 5) asArray.          "runs it; also do:, count, first, firstOrNil, explain"
q explain.                    "the plan that runs, as proto_db's explain"
(q pagerSize: 200) page: 2.
```

**A cascade does not chain.** `q where: p; take: 5` sends both messages to `q` and keeps neither
answer. It is the same trap as `tags add: 'urgent'` with the result discarded (README), and the
chapter shows it first.

| `proto_db` | protoBaseST | Note |
|---|---|---|
| `from_collection(c)` | `PBQuery from: c` | A collection or a plan; an `Array` or `OrderedCollection` is deferred with `ValuesScan`. |
| `where(p)` | `where: p` | |
| `select(...)` | `project: #('name' 'age')`, `collect: aBlock` | Smalltalk's `select:` filters, so `proto_db`'s name would read backwards. `select:` is **not** defined on `PBQuery` (ruling IQ2). |
| `order_by(k, descending=)`, `then_by` | `orderBy:`, `orderBy:descending:`, `thenBy:`, `thenBy:descending:` | A path String, a `PBField`, or a block (a block key always sorts with `Sort`). |
| `skip(n)`, `take(n)` | `skip:`, `take:` | |
| `distinct()` | `distinct` | |
| `count()`, `first()`, `first_or_none()`, `to_list()` | `count`, `first`, `firstOrNil`, `asArray` | `first` of an empty result is `PBUserError`, as `proto_db`'s `ProtoUserError` (`linq.py:1078-1083`). |
| `explain()`, `plan()` | `explain`, `plan` | |
| `pager(n)` | `pagerSize: n` | In-process only. |
| `plan_query(source, where, order_by, limit, offset)` | `PBPlanner plan:where:orderBy:limit:offset:` | `where:` also takes the 0.1 list syntax as an `Array`. |

**Not in the first release (ruling IQ2): selection blocks.** A block such as
`[:each | (each at: 'city') = 'Oslo']` could be translated by evaluating it once against a
recording proxy (protoST honours a user `doesNotUnderstand:` since 0.10.0, and a non-Boolean
receiver of an inlined `and:` gets the real send, STATUS D53). It reads like GemStone's selection
blocks, but it fails silently in ways a course should not teach first: `30 < (each at: 'age')`
sends `<` to an Integer, `ifTrue:` and `==` are inlined, and a block that calls a method of the
element records nothing. It would need its own refusal rules.

### 5.6 Planner behaviour

The planner is a line-for-line port of `planner.py`. The same data and the same query give the
same plan in both implementations, with these specifics:

- **Same inputs.** Indexes are taken in sorted name order (`planner.py:289`); conjuncts keep their
  order with duplicates removed (`:138-141`); candidates are ranked by `(cost, scans,
  indexNames)` (`:161-163`), so ties are broken the same way.
- **Same arithmetic, in the same order.** Costs are Floats built by the formulas of
  `keyed.py:596-622` and `plans.py:439-814`, with sums and products evaluated in Python's order.
  The descent term is `log2(groups + 2)`; protoST has no `log2` and its `log:` is `ln x / ln b`
  (`math_prims.cpp`, `prim_LogBase`), which can differ from C's `log2` in the last bit. Two
  candidates whose costs differ by one ulp could then rank differently (risk R2). Ruling IQ4:
  this is a documented deviation; protoST is not changed. The query vectors compare plans and
  report near-tie differences; results must always match.
- **Same `explain`.** The keys (`plan`, `estimate`, `children`, `index`, `term`, `predicate`,
  `keys`, `limit`, `offset`, `by_rank`) and node names are `proto_db`'s, except `BlockFilter` with
  `description`. An index's `explain` gives `kind` as `proto_db`'s class name (`'EqualityIndex'`,
  `'RangeIndex'`), not the protoST class name. `explain` answers a `PBFrozenDict` of Strings, Numbers, `nil`, Booleans and
  Arrays, so `PBNotation describe:` prints it and the conformance runner compares it.
- **No fallback.** Nothing in the query path catches an error to answer something else; a
  malformed query is `PBValidationError`, an unsupported one `PBNotSupportedError`
  (`query-planner.rst`, last section).

### 5.7 Paging

`PBPager` serves page k of one plan built on one transaction's snapshot. When the plan offers rank
access (an index lookup, range or ordered scan; a `PBList` or `PBDictionary` scan; a `Limit` or a
single-term `Filter` over an ordered scan of the index that answers it; a single-key `Sort` over
an index plan of that key) page k costs O(log n + page size); otherwise the result is materialised
once and sliced. A pager never shows a row twice and never skips one, whatever commits meanwhile,
because the snapshot's versions do not change.

### 5.8 Cluster mode

- **Nothing on the wire changes.** Indexes are ordinary records shipped and persisted with the
  commit like any other; no message names an index. The `query` and `commit_query` messages are
  about acceptor state and record location (2.7), not database queries.
- **Reads.** A query reads the transaction's snapshot, so in a cluster it has exactly the
  consistency `getRootObject:` has there (the existing cluster read rules). It never contacts a
  peer.
- **Writes and merges.** Index maintenance happens in the writer's mutators before the round. A
  merge onto an indexed current happens in the round's build (`PBClusterRound >> _build:`,
  `cluster/round.st:308-314`), on the member that holds the permission, which is the member whose
  transaction it is (or its group-commit leader in the same process). An extractor index therefore
  needs the extractor registered in that process, as in standalone mode. The cost of a merge onto
  an indexed root lengthens the build, which runs under the cluster-wide permission: measured by
  bench M3 in cluster mode (section 7.3).
- **No new safety argument.** The build is deterministic given the transaction and the current
  root; replaying it after a lost round gives the same root, as today.

---

## 6. Compatibility and conformance

The existing pattern is followed: vendored `proto_db` vectors under `tests/conformance/` (with
`vectors.sha256` and the expected-differences table), and generated interop cases under
`tests/interop/` that run `proto_db` in its venv against the same directory.

### 6.1 Format vectors

`proto_db`'s vendored vectors contain indexed records (the `database` vector: an `EqualityIndex`
and a `RangeIndex`) but **no index-maintenance and no query vectors**. Proposed:

1. **Key vectors** (`tests/conformance/_indexkeys.st`, data generated by a new
   `tests/interop/py_index_keys.py`): for a seeded set of values covering every rank, unorderable
   values, `MISSING`, `nil`, atoms, nested lists and maps at the depth limits: the member key's
   wire bytes, the surrogate, `isOrderable`, the rank bounds, and the member-key depth refusals
   with `proto_db`'s limits (`keyed.py:179-215`).
2. **Shape identity** (`tests/interop/index_ops_identical.sh`, modelled on
   `avl_ops_identical.sh`): the same seeded operation sequence (add index, mutators of every
   collection kind, remove index, stale rebuild) is run by both implementations from an empty
   space; the dumps are compared node by node with `compare_dumps.py --exact`; `proto_db`'s
   verifier and `collection.validate()` accept protoBaseST's space.
3. **Both directions with the other side changing**: `proto_db` writes indexed collections,
   protoBaseST changes them (every mutator, a merge), `proto_db` validates and queries the result;
   and the reverse. The `concurrency.sh` row 13 (a blind write onto an indexed root) changes from
   "protoBaseST refuses" to "both merge", with `proto_db`'s recorded outcome.

### 6.2 Query vectors

A generator `tests/interop/py_query_vectors.py` builds a seeded database with `proto_db` (several
collection kinds and index configurations, including none, duplicates in a `List`, `MISSING`,
`nil`, mixed numeric types and unorderable values) and records, for a fixed list of queries written
in the 0.1 prefix list syntax (language neutral) with an order and a window:

- the plan as the tree of node names, index names and `term` descriptions, with every node's
  `estimate` rows and cost;
- the result as the ordered list of element identities (atoms by oid, values by exact token) for
  ordered queries, and as a multiset otherwise;
- `exact_rows` and `by_rank` where offered.

The database directory and a JSON file are vendored under `tests/conformance/vectors-queries/`
with a SHA-256 manifest and the generator's commit, regenerated only by an explicit script (as
`fetch_vectors.sh` is). `tests/conformance/queries.st` opens the directory, runs every query, and
requires: results equal in every case, always; and the same plan tree and index choice, with
every node's rows equal and costs equal within a relative 1e-12 (the log2 issue, R2). When the
plans differ, the case is a near tie, reported by name and not failed (ruling IQ4), only if the
root cost protoBaseST computes for its own plan and the root cost `proto_db` recorded for its
plan are within that tolerance of each other: both are optimal under their own arithmetic, so
equal costs mean the two candidates tied. Any other plan difference fails. (`explain` shows the
chosen plan only, so the rule compares the two chosen plans, never a rejected candidate.) The same generator also checks, on the Python
side, that each recorded result equals a scan (the invariant), so a vector can never encode a
`proto_db` bug as truth without the generator failing.

Upstream: these vectors are protoBaseST's, not `proto_db`'s. Proposing them for `proto_db`'s own
conformance set is IQ6, kept as a proposal and not sent (ruling, 9.2).

### 6.3 What stays different

- `BlockFilter` in place of `PythonFilter` (5.5); the query vectors contain no opaque predicate.
- No pager tokens, no query cache (3.2): their `proto_db` tests are listed as not ported, with the
  reason, in a checklist (`tests/unit/queries_checklist.tsv`, as the cluster's
  `cluster_checklist.tsv`).

---

## 7. Testing strategy and benchmarks

### 7.1 Unit tests (ported from `proto_db`)

Every `proto_db` test of the in-scope parts is ported or justified in
`tests/unit/queries_checklist.tsv` (tag `v2.0.0rc4`; these files are unchanged at `b99285b`):
`tests/unit/test_equality_index.py` (13 tests), `test_range_index.py` (11), `test_index_base.py`
(28), `test_index_key_neutrality.py` (3), `test_index_contract.py` (3), `test_keyspec.py` (19),
`test_terms.py` (19), `test_expressions.py` (25), `test_planner.py` (38), `test_query_plans.py`
(4), `test_linq.py` (56), `test_pager.py` (19); `tests/property/test_index_equals_scan.py` (2),
`test_index_rank.py` (5); `tests/concurrency/test_index_weights_concurrency.py` (1),
`test_indexed_roots.py` (2), `test_pager_stability.py` (1); and, as excluded or deferred rows,
`test_vector_index.py` (30), `test_query_cache.py` (19) and
`tests/property/test_query_cache_soundness.py` (3): 301 rows. The counts are of `def test_`
lines; parametrised cases are more. (The first version of this list omitted the key-spec, term,
expression, property and concurrency files; corrected while writing the plan.)

### 7.2 Property and contract tests

- **The invariant.** For seeded random collections, index configurations and predicates
  (`tests/property/test_index_equals_scan.py`), the planned result equals a full scan as a
  multiset. Seeds by `PBST_SIM_SEEDS`, a default small set in the suite and a large one in the
  final verification, as the cluster's soak.
- **The index contract** (`tests/contracts/index_contract.py`): plan equals scan for every
  supported term; random add / remove / replace keep `validate:` passing; save and lazy load;
  concurrent readers on several actors get identical results; unsupported terms signal; the index
  stays consistent under every mutator of every collection; no hook changes its receiver; `empty`
  keeps the definition; ordered iteration equals a sort by order key; `withReplaced:with:` equals
  remove plus add and `build:` equals the fold of `withAdded:`.
- **Rank** (`tests/property/test_index_rank.py`): `windowFrom:to:` equals slicing `execute`.
- **Merges**: the concurrency table of `tests/interop/concurrency.sh` gains rows for blind writes
  onto indexed roots and concurrent `addIndex:` (the `PBConflictError` case), run with both
  languages as first and second committer.

### 7.3 Benchmarks (deliverable D5)

Files: `bench/query_workload.st`, `bench/py_query_workload.py`, `bench/run_query.sh`, following
`run_tx.sh`: interleaved runs (`RUNS`, default 5) of every implementation, data on a real disk
(`/var/tmp` default, never tmpfs), the minimum and the median reported, nothing asserted about
time.

**Self-reporting and verification.** Each workload builds its data from a seed, computes a model
answer from the plain record list (as `proto_db`'s `benchmarks/workloads/queries.py` does: the sum
of matching ids, counts per range, the exact ordered id list for top-k), and prints a line with the
work done (rows, queries, plan root, checksum). The runner refuses a run whose checksum differs
from the model, or whose figures differ between implementations, or whose plan choice differs
(the plan is part of the work: an indexed time measured on a scan plan is not an indexed time).

| Id | Workload | Shapes |
|---|---|---|
| Q1 | Point equality | indexed lookup against a forced scan (the same collection without indexes), sizes 10^2 to 10^5 |
| Q2 | `in` and ranges | `in` of 1, 10, 100 values; ranges of 0.1%, 1%, 10%, 50% selectivity |
| Q3 | Compound | AND (index + residual), OR of two indexed branches (Union) and of an indexed and an unindexed one (scan), NOT |
| Q4 | Ordering | `orderBy:` + `take:` by an ordered index scan against `Sort` over a lookup, selective and unselective |
| Q5 | Paging | page k for every k, by rank against materialised; `count` by rank |
| M1 | Maintenance on commit | N single-element transactions on a collection with 0, 1 and 3 indexes: commits per second and the extra cost per index |
| M2 | Build | `addIndex:` on n elements (bulk) against the fold of `withAdded:` |
| M3 | Merge | blind writes merged onto an indexed current, standalone and in a three-member cluster (`bench/run_cluster.sh` profile) |
| P1 | Planner overhead | `plan` and `explain` only, no execution, for predicates of 1 to 32 conjuncts and 0 to 8 indexes |
| P2 | Model against timings | for a range term swept from very selective to unselective, and for `!=` on indexes with few and with nearly n key groups: the point where the cost model switches between the index plan and scan plus filter, and whether the measured times of the two plans (both forced) cross at that point. The model's crossover in collection size alone is one or two elements, so size is not the variable swept. |
| P3 | Intersect | the two-index intersection built by hand against the planner's filter plan |

**The comparison.** Every Q, M and P workload runs on both sides with the same seed, the same data
and the same queries (the 0.1 list syntax, so the predicate is literally the same), and the runner
checks equal checksums and equal plans before printing the ratio. Figures are recorded in a new
"Queries and indexes" subsection of `docs/deviations.md#performance` with the date, the machine,
the load, both commits and both binaries, and are indicative only, as every figure there.

---

## 8. Documentation and tutorial plan

### 8.1 Documentation (D1, D2, D7)

- `docs/reference.md`: new sections "Indexes", "Key specs and extractors", "Terms and expressions",
  "Queries", "Plans and explain", "Pagers"; the README's API mapping tables gain the rows of 5.5.
- `docs/queries.md`: the conceptual guide of D2, including "Reading a plan": the shape of
  `explain`, each node, each field, what `estimate` means and how to tell why the planner chose
  what it chose.
- `docs/deviations.md`: the indexed-collections entry is rewritten (vector and unknown kinds
  only); new entries for `BlockFilter`, the absent `select:`, the deferred items, and R2 if it
  stays.
- `docs/not-done.md`: index maintenance and index queries leave the slide; the deferred items of
  3.2 enter it.

### 8.2 Tutorial chapters (D3)

Written **early, in parallel with the code**, as drafts the maintainer can share before release
(feedback memory: tutorials early). Their programs start in `examples/queries/pending/` as
`*.st.pending` (the cluster's `pending/` convention), and move out when the API they use exists.
The selector check (`tests/docs/reference_selectors.sh`) gets a declared list of pending selectors
that must be empty at release; extending the check is part of task T0.

| # | Chapter | Teaches (from 1.3) | Program |
|---|---|---|---|
| 17 | **Indexes** | Why a walk costs n; why the hand-kept index of chapter 4 fails; an index as part of the version; what each write costs with 0, 1, 3 indexes; key specs, `MISSING` and `nil`; extractors and purity. | `examples/tutorial/17_indexes.st` |
| 18 | **Queries and the planner** | The builder and the cascade trap; `explain` read node by node; why the planner sometimes scans (where the model switches, and whether the measured times agree); why `not (x = 5)` is not `x ~= 5`; why no intersection; block predicates and why they never use an index. | `examples/tutorial/18_queries_and_plans.st` |
| 19 | **Ordered reads and pages** | Skip-k against rank access, measured; one snapshot means stable pages under concurrent commits. | `examples/tutorial/19_ordered_reads_and_pages.st` |
| 11 (update) | One directory, two languages | An index added by Python, changed and merged by protoST, validated by Python. | `11_python_interop.sh` (extended) |

Chapter 4's "Queries" section and "`proto_db`'s indexes" section become a short pointer to 17; chapter
12 loses the indexed-write refusal except for vector and unknown kinds; `gemstone.md` (which
maps GemStone's indexes) and `soil.md` are re-checked. All are linked from `README.md` (the
"Tutorials" table gains a "Queries, chapters 17-19" row) and from `docs/tutorial/README.md`.

---

## 9. Decisions taken in this spec

Two kinds, both for `docs/decisions.md`: the spec's own calls (9.1) and the maintainer's rulings
on the open questions (9.2).

### 9.1 The spec's calls, IC1 to IC10

Numbered IC1 to IC10 (indexed-queries calls); each can be overruled in `docs/decisions.md`.

| # | Call | Why | Cost if wrong |
|---|---|---|---|
| IC1 | Port `proto_db`'s structure (mutator-time maintenance, the same trees, the same cost model) rather than design a protoST-native index. | The format is shared; any other structure would be refused by `proto_db` or diverge. | None foreseen. |
| IC2 | Vector and unknown index kinds keep their collection read only. | Vectors are excluded; maintaining only some indexes writes stale ones. | A collection with a vector index stays unchangeable from protoST. |
| IC3 | Operators are `proto_db`'s strings inside `PBTerm`; the builder gives Smalltalk selectors on top. | One list syntax and one `explain` for both languages and for the vectors. | None. |
| IC4 | No `=` override on `PBField`; `eq:` / `ne:` instead. | `=` must stay an equality for collections and tests. | A little less like Python's `F.city == "Oslo"`. |
| IC5 | `PBQuery` immutable, like every value of the library. | `proto_db`'s `Queryable` is; the house rule is the same. | The cascade trap (taught first). |
| IC6 | `BlockFilter` as the node name for an opaque predicate. | The node runs a protoST block; naming it `PythonFilter` would mislead. | A one-name difference in `explain`, listed in the vectors' expected differences only if a vector ever holds one (none does). |
| IC7 | Stale format-3 key-group indexes are rebuilt on first change, as `proto_db` does. | Refusing would keep such collections read only for no format reason. | A first change to a large stale collection pays a full build. |
| IC8 | Query vectors are generated by a protoBaseST script from `proto_db`, vendored with a manifest, and self-checked against a scan. | `proto_db` ships none. | They must be regenerated when the reference moves. |
| IC9 | Pager tokens, the query cache, `GroupBy`/`Join`/`Unnest`, computed values: deferred (3.2). | Each is either not portable today (tokens) or not optimisation (the rest). | Programs that need them wait. |
| IC10 | A version bump to 0.3.0 for the release that carries this feature, after 0.2.0 (cluster). | It changes what protoBaseST writes (indexed collections) and adds API. | Naming only. |

### 9.2 The maintainer's rulings (2026-11-18)

The spec was approved on 2026-11-18 with these answers to the open questions it raised.

| # | Question | Ruling (2026-11-18) | Consequence for the design |
|---|---|---|---|
| IQ1 | Application code in the commit build: a merge onto a collection with an extractor index runs the extractor in the publisher (and in the cluster round), which `publisher.st:71-73` says runs no application code. | **Exactly as `proto_db`.** The extractor runs in the commit. The original exception it raises passes through unchanged (`KeySpec.extract` in `keyspec.py` does not wrap it) and fails only that commit. Purity is a documented contract. No new error class, no deviation. *(Corrected 2026-11-18: the question as first put to the maintainer said `proto_db` names the extractor in the error; it does not.)* | 5.3 and 5.8 as written; the publisher's module comment names the exception; the extractor registry's comment, the reference and chapter 17 state the purity contract; a test plants a failing extractor and checks that only its commit fails, with the block's own exception. |
| IQ2 | The shape of the query API. | **The proposal as written:** `eq:` / `ne:` with the binary comparisons, `&` / `|` / `not`, `project:` / `collect:` for projection, no `select:` on `PBQuery`, no selection blocks in the first release. | 5.5 as written. |
| IQ3 | Scope cut: pager tokens, the query cache, `GroupBy` / `Join` / `Unnest`, computed values, `ValuesScan`. | **Deferred, as proposed.** | 3.2 as written; `not-done.md` lists them. |
| IQ4 | A `log2` primitive in protoST for exact plan parity. | **No protoST change; a documented deviation.** The query vectors compare plans and report near-tie differences; results must always match. | R2 is a `deviations.md` entry; the query-vector runner reports a plan difference on a near-tie (costs within a relative 1e-12 of each other) as an expected difference and fails on any other plan difference and on every result difference. |
| IQ5 | Vector and unknown index kinds keep their collection read only. | **Approved.** | IC2 as written. |
| IQ6 | Propose query and index-shape vectors to `proto_db`. | **Stays a proposal; nothing is sent upstream.** | Recorded under "Proposals to `proto_db`" in `decisions.md`. |
| IQ7 | Propose a portable plan digest to `proto_db`. | **Stays a proposal; nothing is sent upstream.** | The same. Pager tokens stay deferred. |
| IQ8 | Release vehicle. | **0.3.0, after 0.2.0**, as proposed (IC10). | `CHANGELOG.md` gets a 0.3.0 section. |

*Correction at Task 4b (IQ1):* rc4's cluster round fails the whole round on a non-ProtoDBError
build error (`_permit_round`, `transactions.py:1660-1717`, catches only `ProtoConflictError` and
`ProtoDBError` per entry); protoBaseST follows rc4. So an extractor's exception fails only its own
commit standalone and in a group commit, and the whole round in a cluster. The inconsistency is a
maintainer question and an unsent proposal (`decisions.md`, "Proposals to `proto_db`").

**Controller rulings 2026-11-18** (on gaps the documentation drafts found):

| # | Ruling |
|---|---|
| CR1 | The `!=` claim of 1.3 was wrong. Under D30 the index complement costs n + G + 1 against 2n for scan plus filter, so it wins whenever the index has fewer than n − 1 key groups (`proto_db` `test_ne_term_alone_prefers_the_index_complement_over_scan_plus_filter`). 1.3 corrected. |
| CR2 | P2 measures whether real timings cross where the cost model says; the model's crossover for a tiny collection is only one or two elements. 1.3, 7.3 and the chapter 18 row corrected. |
| CR3 | `name:keySpec:` is the primitive index constructor; `name:path:` is a convenience for a single-path key spec. Both listed (5.2, 5.5). |
| CR4 | An index's `explain` `kind` uses `proto_db`'s names (`'EqualityIndex'`, `'RangeIndex'`), as plan nodes keep `proto_db`'s names (5.6). |
| CR5 | Chained `where:` calls combine with AND. `&`, `|` and `not` take expressions only; a block enters only through `where:` and becomes a `BlockFilter` (5.5). |
| CR6 | `where:` with an argument that is neither a `PBExpression` nor a one-argument block signals `PBValidationError` with the text `where: expects a PBExpression or a one-argument block, got a <class name>` (for example `got a Boolean`). |
| CR7 | The half-open selectors are `betweenLeftOpen:and:` (`between(]`) and `betweenRightOpen:and:` (`between[)`); pages are zero-based; the pager's `explain` is `pager` → `page_size`, `by_rank` and `plan` → the plan's explain, with no `portable`; `PBExpression class >> compile:` belongs to the term task (T5). |
| CR8 | Group commit with a failing extractor: when a group-commit leader builds several transactions and one extractor fails, only that transaction's commit fails and the others commit. Tested in the plan's Task 4b. |
| CR9 | The final task (T10) rewrites every "planned for 0.3.0" note in `docs/not-done.md` and `docs/deviations.md` into a present-tense statement of what is. |
| CR10 | The guide's worked-plan estimates (for example a cost of 152.585) are model output, labelled "model estimate", never presented as measurements. They must equal `proto_db`'s own planner output for the same data, generated from `proto_db` by a script, never computed by hand; Task 0 checks the label and Task 7 checks the numbers. |

---

## 10. Risks, gaps and open questions

### 10.1 Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Speed.** protoBaseST's AVL operations are 12 to 31 times slower than `proto_db`'s (`deviations.md`, "AVL operations"). Each indexed write adds two levels of tree work per index (group tree and members tree). Indexed writes may be slow enough to dominate commits. | Measure first (M1, M3) and say so in chapter 17. No speed claim is made. |
| R2 | **Planner ties.** `log2` computed as `ln x / ln 2` can differ from C's `log2` by one ulp, so two candidates of almost equal cost may rank differently in the two implementations: same answer, different plan. | Query vectors compare plans and report near-tie differences; results must always match (ruling IQ4: documented deviation, no protoST change). |
| R3 | **Application code in the commit build.** An extractor block runs during a merge in the publisher or the cluster round; a slow or failing block delays or fails that commit, and an impure one corrupts the index silently. | Ruling IQ1: exactly as in `proto_db`. The block's own exception passes through unchanged and fails that commit only; purity is a documented contract. |
| R4 | **Shape drift in bulk builds.** A bulk build that balances differently from `_build_balanced` writes valid but different trees, breaking node-level conformance. | The shape-identity test (6.1.2) on every bulk path. |
| R5 | **Plan digest is Python-specific.** Portable tokens cannot be ported as specified. | Deferred; IQ7 stays a proposal to `proto_db`, not sent. |
| R6 | **Hook-order mismatches** in the mutators produce valid indexes with different shapes. | Port each mutator against its Python source and the shape-identity test. |
| R7 | **Effort.** `proto_db` reached this design through rulings D28-D58 and review rounds; porting the end state skips the iterations, not the reviews. | Reviews per task, as for the cluster. |

### 10.2 What protoST or protoCore lacks

- **`log2`** (protoST): `Float >> log:` divides two natural logarithms. Needed only for exact plan
  parity (R2). Ruling IQ4: not requested; R2 is a documented deviation.
- **Nothing in protoCore.** Immutable maps and lists, atoms with compare-and-swap and actors are
  what the design needs, and they exist.
- **Speed of the interpreter** (R1): not a gap to fix in this feature.

### 10.3 Open questions

None. The questions IQ1 to IQ8 raised by this spec were answered by the maintainer on 2026-11-18;
the rulings are in section 9.2.

---

## 11. Proposed task breakdown

A rough order only; the detailed plan is `docs/superpowers/plans/2026-11-18-indexed-queries.md`.
**Order (maintainer, 2026-11-18): documentation first.** The conceptual guide, the drafts of
chapters 17-19, the chapter 11 update, the new reference sections and the pending examples are
written first, before T1, by a separate documentation job on branch `feat/queries-docs` (off
`3eb28c6`); the plan's opening task reviews and integrates them. Figures not yet measured are
marked `[measured in T<n>: …]`, naming the task below that measures them. The table below lists the
implementation work; each of its tasks then makes its chapter's samples runnable and replaces its
markers with measured figures. Benchmarks run **alongside** the code: each task delivers its own tests, its part of
the reference, and the benchmark of the code it adds; a final task runs the full comparison and
the audits once.

| Task | Content | Its docs and benchmarks |
|---|---|---|
| T0 | Pending-chapter machinery (pending selectors list in the doc checks), `examples/queries/pending/`, `queries_checklist.tsv` with every in-scope `proto_db` test listed. | Draft outlines of chapters 17-19 and of `docs/queries.md` from section 1.3, shared early. |
| T1 | AVL functions of 2.2 (okey ranges, reversed walk, counts and weights below, rank walks, balanced keyed bulk build), with shape identity against `proto_db`. | Reference for the new `PBAvl` messages. |
| T2 | `PBKeySpec` and the extractor registry; `surrogate`, member keys, depth limits; key vectors (6.1.1). | Guide: "Keys, `MISSING` and `nil`". |
| T3 | `PBKeyGroupIndex`, `PBEqualityIndex`, `PBRangeIndex`: hooks, build, validate, explain, estimate, plans, rank segments; index contract. | Bench M2; reference "Indexes". |
| T4 | Collections: `addIndex:`, `removeIndex:`, maintenance in every mutator, stale rebuild, op-log index ops, merges onto indexed currents, narrowed refusal; shape identity (6.1.2) and both-direction interop (6.1.3); `concurrency.sh` rows. | Bench M1, M3; chapter 17 program moves out of `pending/`; chapter 11 update. |
| T5 | Terms and expressions: `PBTerm`, `PBAnd` / `PBOr` / `PBNot`, `matches:`, list syntax, `describe`. | Guide: "The expression language". |
| T6 | Plan operators and `explain`; rank access through `Limit`, `Count`, `Filter`, `Sort`. | Guide: "Reading a plan". |
| T7 | `PBPlanner`; the index-equals-scan property test; query vectors (6.2). | Bench P1, P2, P3. |
| T8 | `PBQuery`, `PBField`, block predicates and the mixing rule. | Chapter 18 program out of `pending/`; bench Q1-Q4. |
| T9 | `PBPager`. | Chapter 19; bench Q5. |
| T10 | Final: the full suite, the large-seed property runs, the full `run_query.sh` comparison recorded in `deviations.md`, reference and guide completed against D1-D2, decisions and not-done updated (D7), README links. | All figures quoted in chapters 17-19 filled from the recorded run. |

**Effort, honestly:** about 30 to 40 engineering days for T0-T10 (T1 3, T2 3, T3 5, T4 6, T5 2,
T6 4, T7 4, T8 3, T9 2, T10 3, plus reviews), with docs and tutorials running alongside rather
than added at the end. This is an estimate from the size of the Python sources (about 4,500 lines
in scope, docstrings included) and the cluster port's experience, not a measurement, and has a wide error bar.
