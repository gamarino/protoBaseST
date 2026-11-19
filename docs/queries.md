# Indexed queries and the query planner

<!-- example: examples/queries/reading_plans.st -->

> **In progress for protoBaseST 0.3.0.** This guide explains the design of the approved
> [indexed-queries spec](superpowers/specs/2026-11-18-indexed-queries-design.md). Indexes, their
> maintenance in every write and merge, the expression language, the planner and the query front
> end (`PBQuery`, `PBField`) are implemented; pagers (plan Task 9) are not yet. Everything below
> about `proto_db` is read from its code and documentation at `v2.0.0rc4` and cited by file. Every
> code block comes from a program of [examples/queries/](../examples/queries/README.md) that runs
> as a test and checks what it shows; the section that quotes one names it. Figures marked
> `[measured in T<n>: ...]` do not exist yet: each names the task of spec section 11 whose
> benchmark (spec 7.3) will measure it.

This is the conceptual guide. The tutorial teaches the same ground by example, in
[chapter 17](tutorial/17-indexes.md) (indexes), [chapter 18](tutorial/18-queries-and-plans.md)
(queries and the planner) and [chapter 19](tutorial/19-ordered-reads-and-pages.md) (ordered reads
and pages). The reference lists every class and message:
[reference.md, Indexed queries](reference.md#indexed-queries-in-progress-030).

The normative texts are `proto_db`'s own: `docs/source/indexing-framework.rst` and
`docs/source/query-planner.rst` in the protoBase repository. Where protoBaseST differs on purpose,
the difference is listed in [deviations.md](deviations.md#indexed-queries-planned).

Contents:
[Why a full scan fails at scale](#why-a-full-scan-fails-at-scale) |
[The index model](#the-index-model) |
[Equality and range indexes](#equality-and-range-indexes) |
[Key specs, MISSING and nil](#key-specs-missing-and-nil) |
[Extractors and their purity contract](#extractors-and-their-purity-contract) |
[The expression language](#the-expression-language) |
[How the planner chooses](#how-the-planner-chooses) |
[Reading a plan](#reading-a-plan) |
[Ordered reads, windows and pages](#ordered-reads-windows-and-pages) |
[Index maintenance under immutability and the commit](#index-maintenance-under-immutability-and-the-commit) |
[Cluster mode](#cluster-mode) |
[What it costs](#what-it-costs) |
[Sources](#sources)

## Why a full scan fails at scale

Without an index, every question is a walk: visit every element, test each one, keep those that
pass ([chapter 4](tutorial/04-collections-and-queries.md#queries)). The walk is always correct
and, for a small collection read once, it is the right plan. Its cost is the size of the
collection, **whatever the answer**: finding the one customer with a given tax number among a
million reads a million records. In protoBaseST, reading a record that is not in memory is a lazy
load and a decode, so the constant is not small.

An index changes what a question costs from "what is stored" to "what is returned": a lookup costs
a descent of a tree, about log2 of the number of distinct keys, plus the rows it answers.
Measured in T8 (bench Q1, RUNS=5 interleaved, the minimum; [deviations.md](deviations.md#q1-q4-queries-indexed-against-a-forced-scan)): a point lookup
by an equality index took about 1 ms in protoBaseST at 10^2, 10^3 and 10^4 elements (`proto_db`
about 0.1 ms), while a forced scan of the same collection without indexes took 5.5 ms, 59 ms and
565 ms (`proto_db` 0.3, 2.8 and 28 ms). 10^5 elements was not measured: protoST's indexed build of
it is too slow for the bench.

The hand-made alternative of chapter 4, a second root kept by the program, fails differently: it
is only as good as every writer's memory, in both languages, and nothing checks that it agrees with
the data ([chapter 17](tutorial/17-indexes.md#the-next-obvious-solution-keep-the-lookup-yourself)).

## The index model

**An index is part of the collection version.** Every collection (`PBIndexedCollection`, as
`proto_db`'s `IndexedCollection`) carries an immutable index set mapping a name to an index; it is
empty by default. `addIndex:` builds the index over the elements the collection holds now and
answers a new version of the collection holding it; `removeIndex:` answers a version without it
(`proto_db`, `indexing-framework.rst`, "The model").

**Every mutator computes content and indexes in one step.** `setAt:value:`, `removeAt:`, `add:` and
the rest compute the new structure and the new index set together and answer one version holding
both (`proto_db`, `collections/base.py:1-13`, `:450-473`). There is no code path that answers a
collection with a stale index; `proto_db` checks it with a contract test for every mutator of every
collection, and protoBaseST plans to port it (spec 7.2).

**An index is an immutable value.** Each index operation answers a new index that shares every
unchanged subtree with the last (path copying). A snapshot's indexes are the snapshot's, so a
reader never sees an index ahead of or behind its data.

**Exactness is the invariant.** For every collection, every index configuration and every query, a
plan that uses indexes answers the same multiset of elements as a full scan
(`indexing-framework.rst`, "Cost of indexes": "the first anti-goal of the project"). An index may
make a query faster or slower; it may never change its answer. `PBIndexedCollection >> validate`
compares every index with a scan and signals `PBCorruptionError` on any difference.

**Indexes persist as ordinary records.** An index is a format-4 atom under `proto_db`'s type name,
reachable from its collection; there is no index file and no commit-time index step. protoBaseST
already decodes these records; writing them means writing exactly what `proto_db` writes (spec
5.4), so an index written by either implementation is read and maintained by the other.

## Equality and range indexes

Both built-in kinds are key-group indexes (`proto_db`, `indexing/keyed.py:1-41`):

- `'groups'`: a weighted tree of *key groups*, ordered by the format's order key of the extracted
  key. `MISSING` and `nil` are ordinary keys at the bottom of the order.
- `'side'`: the one group of every element whose key cannot be ordered (a list, a map, NaN, or a
  tuple holding one).
- each group: a tree from a *member key* to `(element, count)`, and its total. The member key tells
  apart values that are equal but not identical (`1`, `1.0` and `Decimal 1.00` are one key and three
  members), so a plan answers the stored elements, never an equal representative. Counts make the
  index a multiset: a `PBList` holding an element twice stores it with count 2.
- `'total_count'`, and `'member_tokens'` (1 for an index written by format 4; absent on one written by
  format 3, which is rebuilt before its first change).

| Kind | Answers | Plans | Also |
|---|---|---|---|
| `PBEqualityIndex` | `==`, `'in'`, `!=`, `?N`, `?!N` | `IndexLookup` (`==`, `'in'`, `?N`), `IndexRange` (`?!N`), `IndexComplement` (`!=`) | |
| `PBRangeIndex` | the same, and `<`, `<=`, `>`, `>=`, the four `'between'` forms | the same, and `IndexRange` for the comparisons | ordered iteration: `IndexOrderedScan` |

<!-- example: examples/queries/lookups.st -->

What each kind answers, and how, from [examples/queries/lookups.st](../examples/queries/lookups.st)
(the block planOf names the plan of a query by its nodes, from the root down its first children):

```smalltalk
people := people addIndex: (PBEqualityIndex name: 'by_city' path: 'city').
city := PBField path: 'city'.
lesson check: 'a lookup' is: (planOf value: (city eq: 'Oslo')) equals: 'IndexLookup'.
lesson check: 'in: is one lookup of several keys' is: (planOf value: (city in: #('Oslo' 'Rome'))) equals: 'IndexLookup'.
lesson check: 'isNone looks up nil and MISSING' is: (planOf value: city isNone) equals: 'IndexLookup'.
lesson check: 'notNone is a range over the present keys' is: (planOf value: city notNone) equals: 'IndexRange'.
lesson check: 'ne: is the complement of a group' is: (planOf value: (city ne: 'Oslo')) equals: 'IndexComplement'.
```

Every node of both trees carries a *weight*, the number of occurrences below it, so occurrence *r*
is found by one descent. That is what gives windows and pages their O(log n + page size) cost
([below](#ordered-reads-windows-and-pages)).

A `PBVectorIndex` and any index kind protoBaseST does not know are read and kept, never maintained:
a collection holding one keeps refusing every change with `PBNotSupportedError` naming it, because
maintaining its other indexes and not that one would write a stale index (spec 3.3, ruling IQ5).
Vector search (`near[]`) is out of scope; a term with that operator is `PBNotSupportedError` when
built.

## Key specs, MISSING and nil

<!-- example: examples/queries/keys.st -->

The program of this section is [examples/queries/keys.st](../examples/queries/keys.st).

An index is defined by its name and its *key spec*, a persistable `(kind, arg)` description of the
key (`proto_db`, `indexing/keyspec.py:165-267`):

| Key spec | Key of an element | In a term, `describe` and `explain` |
|---|---|---|
| `PBKeySpec path: 'address.zip'` | the value at a dotted path of attributes or map keys | `'address.zip'` |
| `PBKeySpec element` | the element itself | the path `nil`; described as `'<element>'` |
| `PBKeySpec extractor: 'name_length'` | the answer of the block registered under that name | `'@name_length'` |

**Path steps.** A step reads an own attribute of a record (`PBObject`, never an inherited
behaviour), a persisted field of another atom (a collection's `count`), or a key of a map
(`PBFrozenDict`). Private names (starting with `_`) and the format's
reserved names are never read. A step through an absent attribute, through a value that is neither a
record nor a map, or through `nil`, yields `MISSING` (`keyspec.py:149-162`). In protoBaseST
`MISSING` is `PBMissing default`, the value the format already decodes as `@missing`, and
`extract:` answers it. (`PBObject >> at:` answers `nil` for an absent attribute, so the port uses a
probe that tells absence from `nil`.)

**`MISSING` is not `nil`.** An explicit `nil` is a present value; an absent attribute is not a value
at all. They are two different keys, and the operators treat them differently (decision D28, from
`proto_db/query/terms.py`, module docstring):

| Operator | Matches `nil` | Matches `MISSING` |
|---|---|---|
| `==` / `eq:`, `'in'` | when the operand is `nil` | never |
| `!=` / `ne:` | when the operand is not `nil` | **never**: an absent key satisfies no comparison |
| `<`, `<=`, `>`, `>=`, `'between'` | never (only keys of the operand's type rank compare) | never |
| `?N` / `isNone` | yes | yes |
| `?!N` / `notNone` | no | no |
| `?T`, `?!T`, `'contains'` | by the value | never |

Four contacts: Ada's zip is `'1010'`, Bob's is an explicit `nil`, Cy has an address without a zip,
and Di has no address at all:

```smalltalk
spec := PBKeySpec path: 'address.zip'.
lesson check: 'a present zip is its value' is: (spec extract: (contacts getAt: 0)) equals: '1010'.
lesson check: 'an explicit nil stays nil' is: (spec extract: (contacts getAt: 1)) equals: nil.
lesson check: 'an absent zip is MISSING' is: (spec extract: (contacts getAt: 2)) equals: PBMissing default.
lesson check: 'no address at all is MISSING too' is: (spec extract: (contacts getAt: 3)) equals: PBMissing default.
lesson check: 'at: cannot tell absence from nil' is: ((contacts getAt: 3) at: 'address') equals: nil.
```

```smalltalk
zip := PBField path: 'address.zip'.
count := [:condition | ((PBQuery from: contacts) where: condition) count].
lesson check: 'eq: nil finds the explicit nil only' is: (count value: (zip eq: nil)) equals: 1.
lesson check: 'ne: matches a present key only' is: (count value: (zip ne: '1010')) equals: 1.
lesson check: 'isNone finds nil and MISSING' is: (count value: zip isNone) equals: 3.
lesson check: 'notNone finds the rest' is: (count value: zip notNone) equals: 1.
lesson check: 'a range compares keys of its own rank only' is: (count value: zip > 5) equals: 0.
```

A key that cannot be ordered (a list, a map, NaN) matches only `!=`, `?!N`, `'contains'`, `?T` and
`?!T`. Ordering operators compare only keys of the operand's type rank: `nil < 5` is false and
`'a' > 1` is false, rather than an error.

`proto_db` persists the key spec as the tuple `('path' 'address.zip')`, `('element' nil)` or
`('extractor' 'name_length')`. In protoBaseST `PBIndex >> keySpec` keeps answering that tuple, as
it does in 0.1.0 (plan call IP3); `PBIndex >> keySpecObject` answers it as a
`PBKeySpec`. An index is built from a `PBKeySpec`, as in
`PBEqualityIndex name: 'by_zip' keySpec: (PBKeySpec path: 'address.zip')`, or, for one path, with
the convenience `PBEqualityIndex name: 'by_city' path: 'city'`; a String given as a key spec is
`PBValidationError` (ruling CR3):

```smalltalk
byZip := (contacts addIndex: (PBEqualityIndex name: 'by_zip' keySpec: spec)) getIndex: 'by_zip'.
lesson check: 'keySpec answers the persisted tuple' is: byZip keySpec asArray equals: #('path' 'address.zip').
lesson check: 'keySpecObject answers the key spec' is: byZip keySpecObject equals: spec.
lesson check: 'a String is not a key spec'
    signals: PBValidationError containing: 'must be a PBKeySpec'
    during: [PBEqualityIndex name: 'by_zip' keySpec: 'address.zip'].
```

## Extractors and their purity contract

An extractor key is a block registered under a name, process-wide:
`PBKeySpec registerExtractor: 'name_length' block: [:p | ...] version: '1'`. Only the name is
stored in the database, never the block, so every process that changes an indexed collection, or
validates it, must register the same name first. A process that has not can still read the
collection and answer lookups (a lookup reads only the stored trees); any change or `validate`
signals `PBValidationError` naming the extractor and telling the program to register it. The index
is never rebuilt or dropped silently (spec 5.4).

**The purity contract** (`proto_db`, `keyspec.py:60-83`, kept by protoBaseST's registry):

- **Pure.** The same element always gives the same key, whatever the time, the process or any state
  outside the element. The index stores the keys the block computed; an extractor that reads a
  clock or a global produces keys no later scan can reproduce, and the index disagrees with its
  elements silently. Nothing can check purity, so it is a documented contract.
- **Thread-safe.** It may run on any actor, and during a merge in the publisher (next point).
- **Identity is the name and the declared version, never the code.** Binding a registered name to
  another block or version is `PBValidationError`. Changing what an extractor computes needs a new
  name or version, and a rebuilt index, exactly as changing an index definition does.

**An extractor runs inside the commit.** A merge of a blind write onto an indexed collection replays
the transaction's intents through the current version's mutators
([below](#merges-of-blind-writes)), so the current version's extractors run during the commit's
build, in the publisher (standalone) or in the round's build (cluster). That is application code in
the commit, which the publisher otherwise never runs. Ruling IQ1 accepts it, exactly as `proto_db`
does: **an exception raised by an extractor fails only the commit whose merge ran it, standalone, in
a group commit and in a cluster round, and it passes through unwrapped.** There is no protoBaseST error class for it and no wrapping, because
`proto_db`'s `KeySpec.extract` does not wrap either (plan call IP2). The caller of that commit sees
the block's exception (as a copy: same class, text and fields, not the same object); other
commits, before and after it and in the same round, are not affected. In a cluster round this is a
deviation from `proto_db` rc4, whose `_permit_round` fails the whole round on a build error that is
not a `ProtoDBError`: the maintainer chose one rule for every mode (2026-11-19;
[deviations.md](deviations.md#cluster-mode), and an unsent proposal in
[decisions.md](decisions.md#proposals-to-proto_db)). So an extractor
that can fail should say in its own message what it was extracting. Outside a merge the same
exception appears at the mutator call, in the transaction's own thread.

## The expression language

<!-- example: examples/queries/expressions.st -->

The program of this section is [examples/queries/expressions.st](../examples/queries/expressions.st);
the block on the list syntax comes from [reading_plans.st](../examples/queries/reading_plans.st).

A condition is a *term* `(path, op, value)` or a combination of conditions. The operators are
`proto_db`'s strings, so a condition, its list form and its `explain` read the same in both
languages (call IC3):

| Builder (ruling IQ2) | Operator | Notes |
|---|---|---|
| `f eq: v`, `f ne: v` | `==`, `!=` | `=` is not overridden on a field: `=` must stay an equality for collections and tests (IC4). `f = v` answers a Boolean, and `where:` refuses it as a malformed query. |
| `f < v`, `f <= v`, `f > v`, `f >= v` | `<` `<=` `>` `>=` | The field must be the receiver: `30 < f` sends `<` to an Integer. |
| `f between: a and: b`, `betweenOpen:and:` and the two half-open forms | `between[]`, `between()`, `between(]`, `between[)` | Both bounds share a type rank. |
| `f in: #(...)` | `'in'` | |
| `f isNone`, `f notNone` | `?N`, `?!N` | |
| `f isTrue`, `f notTrue`, `f contains: v` | `?T`, `?!T`, `'contains'` | Truthiness of a present key; substring, item or key membership. |
| `a & b`, `a \| b`, `a not` | `And`, `Or`, `Not` | n-ary and flattened; `a not not` is the original condition. Binary messages have no precedence between them: use parentheses. |

A field is `PBField path: 'city'`, `PBField element` or `PBField extractor: 'name_length'`.

```smalltalk
city := PBField path: 'city'.
age := PBField path: 'age'.
lesson check: 'eq: builds a term' is: (city eq: 'Oslo') equals: (PBTerm path: 'city' op: '==' value: 'Oslo').
lesson check: 'between:and: includes both bounds' is: (age between: 30 and: 35) op equals: 'between[]'.
lesson check: '& builds a PBAnd' is: ((city eq: 'Oslo') & (age > 70)) class equals: PBAnd.
lesson check: 'not not is the condition itself' is: (age > 70) not not equals: age > 70.
lesson check: 'a field compared with = is a Boolean, not a condition' is: city = 'Oslo' equals: false.
```

**The list syntax.** `proto_db`'s 0.1 prefix syntax is accepted by `PBPlanner` (and by
`PBExpression class >> compile:`), from an `Array`: `{ 'city'. '=='. 'Oslo' }`; several terms in one
array are joined by an implicit AND; `'&'`, `'|'` (binary, prefix) and `'!'` (unary) combine them
(`proto_db/query/expressions.py`, module docstring). It is language neutral, which is why the query
vectors of spec 6.2 are written in it.

```smalltalk
lesson check: 'the list syntax compiles to the same condition'
    is: (PBExpression compile: { 'city'. '=='. 'Oslo'. 'age'. '>'. 70 })
    equals: (city eq: 'Oslo') & (age > 70).
lesson check: 'asList answers the list syntax' is: (city eq: 'Oslo') asList equals: #('city' '==' 'Oslo').
```

```smalltalk
lesson check: 'PBPlanner with the list syntax plans the same tree'
    is: (PBPlanner plan: people where: { 'city'. '=='. 'Oslo' } orderBy: nil limit: nil offset: 0) explain
    equals: plan.
```

**Evaluation** is two-valued: every term answers true or false on an element, by the table of the
previous section; `&` and `|` short-circuit left to right; `not` is the logical negation. So
`(age < 5) not` is **true** for an element without an age. Ask for presence explicitly (`notNone`)
when that matters.

```smalltalk
lesson check: 'age < 5 is false for an element without an age' is: ((age < 5) evaluate: ageless) equals: false.
lesson check: 'so (age < 5) not is true for it' is: ((age < 5) not evaluate: ageless) equals: true.
lesson check: 'notNone asks for presence' is: (age notNone evaluate: ageless) equals: false.
```

**Blocks.** A plain block enters a query only through `where:`
(`q where: [:p | (p at: 'age') \\ 7 = 0]`); `&`, `|` and `not` take expressions only, and chained
`where:` calls combine with AND (ruling CR5). `where:` given anything else, a Boolean included,
signals `PBValidationError` with the text
`where: expects a PBExpression or a one-argument block, got a <class name>` (ruling CR6). A block
is opaque: no index answers it, and `explain` shows it as a `BlockFilter` node (`proto_db`'s
`PythonFilter`, named after the language that runs it; a listed deviation, call IC6). The mixing
rule is `proto_db`'s (`linq.py:48-61`): in a top-level conjunction the conditions built from fields
go to the planner and each block becomes its own filter on top; an `|` or a `not` holding a
`PBBlockPredicate` (a block with a description, itself an expression) is one block filter for the
whole condition.

```smalltalk
q := PBQuery from: people.
lesson check: 'where: refuses a Boolean'
    signals: PBValidationError containing: 'where: expects a PBExpression or a one-argument block, got a Boolean'
    during: [q where: city = 'Oslo'].
sevens := q where: [:p | (p at: 'age') \\ 7 = 0].
lesson check: 'a block is a BlockFilter over a scan' is: (planOf value: sevens) equals: 'BlockFilter <- CollectionScan'.
oldSevens := (q where: age > 70) where: [:p | (p at: 'age') \\ 7 = 0].
lesson check: 'chained where: is AND: the block filters on top' is: (planOf value: oldSevens) equals: 'BlockFilter <- IndexRange'.
inOslo := PBBlockPredicate block: [:p | (p at: 'city') = 'Oslo'] description: 'city is Oslo'.
lesson check: 'an OR holding a block is one BlockFilter for the whole condition'
    is: ((q where: (age > 70) | inOslo) explain at: 'description') equals: '(age > 70) | (city is Oslo)'.
```

**Selection blocks are not in the first release** (ruling IQ2). Translating
`[:p | (p at: 'city') = 'Oslo']` into a term by running it on a recording object reads like
GemStone's selection blocks, but it fails silently: `30 < (p at: 'age')` sends `<` to an Integer,
`ifTrue:` and `==` are inlined by the compiler, and a block that calls a method of the element
records nothing.

## How the planner chooses

`PBPlanner plan: source where: condition orderBy: keys limit: n offset: m` is a line for line port
of `proto_db`'s `plan_query` (`proto_db/query/planner.py`; `src/protobase/planner.st`, plan Task 7);
`PBQuery` (Task 8) builds its arguments. It is a pure function of its arguments and of the
collection version: nothing is cached between calls, and the plan it answers is the plan that runs.
Its argument errors are `proto_db`'s (`planner.py:278-343`): a source that is neither an indexed
collection nor a plan, a condition that is not an expression or the list syntax, sort keys that are
not a non-empty list of `PBSortKey`s, and a limit or an offset that is not an Integer >= 0 are each
`PBValidationError`. Two kinds of index are never consulted: an index of a kind protoBaseST does not
know (loaded as an opaque atom) and a `PBVectorIndex` (design spec 3.3); another index or a scan
answers the query instead, exactly. Three properties are tested: the 38 behaviours of `proto_db`'s
`test_planner.py` (`tests/unit/qry_planner.st`); a planned query answers what a scan answers, as a
multiset, and in the order of its keys, over random collections of every kind, random index sets
and random conditions of every operator, read back from a file and by concurrent actors
(`tests/unit/qry_prop_equals_scan.st`); and the plans of 314 recorded queries, node for node and
cost for cost, are `proto_db`'s own (`tests/conformance/queries.st`, vectors written by
`tests/interop/py_query_vectors.py`; 0 near ties).

**1. Normalise** (`planner.py:98-126`). `&` and `|` are flattened; negations are pushed inward by De
Morgan's laws, which is exact because evaluation is two-valued. A negated term stays a residual
`not` filter, with one exception: `not isNone` becomes `notNone` and `not notNone` becomes
`isNone`, the one exact rewrite. `not (x = 5)` is never rewritten to `x ne: 5`: an element without an
x satisfies the first and not the second.

**2. Candidates for a conjunction** (`planner.py:195-218`). Duplicate conjuncts are dropped, order
kept. The candidates are: a full scan with every conjunct as a residual `Filter`; and, for each
conjunct some index answers, the cheapest such index plan with the other conjuncts as a residual
filter. Indexes are consulted in sorted name order. No conjunct is ever dropped: each is answered by
the access path or by the filter.

**3. The cost model** (decisions D30, D36). One unit per row produced, per key group visited and per
tree level descended. The estimate of each plan node:

| Node | rows | cost | Source |
|---|---|---|---|
| `CollectionScan` | n | n | `plans.py`, `CollectionScanPlan.estimate` |
| `IndexLookup` (`==`, `'in'`, `?N`) | the sizes of the groups looked up | rows + (groups looked up) × log2 (G + 2) | `keyed.py:596-622` |
| `IndexRange` for `?!N` | total − (`MISSING` and `nil` groups) | rows + log2 (G + 2) + groups visited | same |
| `IndexComplement` (`!=`) | total − `MISSING` group − the excluded group | total + G + 1 (a full pass) | same |
| `IndexRange` for a comparison | keys in the range × (total − side) / G | rows + log2 (G + 2) + keys in the range | same |
| `IndexOrderedScan` | total | total + G + 1 | `keyed.py:626-647` |
| `Filter` | source rows × selectivity | source cost + source rows | `plans.py`, `Filter.estimate` |
| `BlockFilter` | source rows × 0.5 | source cost + source rows | `PythonFilter.estimate` |
| `Union` | sum of source rows | sum of source costs + sum of source rows | `Union.estimate` |
| `Intersect` | smallest source rows | sum of (source cost + source rows) | `Intersect.estimate` |
| `Sort` | source rows | source cost + n log2 n | `Sort.estimate` |
| `Limit` | min (limit, source rows − offset) | source cost | `Limit.estimate` |
| `Project`, `Distinct` | source rows | source cost + source rows | `Project.estimate`, `Distinct.estimate` |
| `Count` | 1 | source cost | `Count.estimate` |

G is the number of key groups of the index. A filter keeps 0.5 of its input per term
(`FILTER_SELECTIVITY`); `&` multiplies, `|` is `1 − Π(1 − s)`, `not` is `1 − s`. The planner keeps
no statistics of values; the only exact figures are the group sizes the index records.

**4. Ranking and ties** (`planner.py:148-175`). The cheapest candidate wins. On equal cost, a plan
without a full scan wins, then the plan whose sorted tuple of index names is smaller, so the choice
is deterministic.

**5. Disjunctions** (`planner.py:250-261`). A `|` gets a `Union` candidate only when every branch has
an index-only plan; otherwise the only plan is the scan filtered by the whole `|`, because a union
that includes a scan always costs more than the scan alone. A union keeps each element with its
largest multiplicity over its branches, so it equals the scan's multiset.

<!-- example: examples/queries/compound.st -->

Compound conditions over chapter 18's 600 people, indexed by city and by age, from
[examples/queries/compound.st](../examples/queries/compound.st):

```smalltalk
both := q where: (city eq: 'Oslo') & (age > 70).
lesson check: 'AND: one access path, the other conjunct a residual filter' is: (planOf value: both) equals: 'Filter <- IndexRange'.
lesson check: 'the filter holds the city term' is: ((both explain at: 'predicate') at: 'path') equals: 'city'.
either := q where: (city eq: 'Oslo') | (age > 70).
lesson check: 'OR of two indexed branches: a union' is: (planOf value: either) equals: 'Union <- IndexLookup'.
lesson check: 'the union keeps each person once' is: either count equals: 200.
unindexed := q where: (city eq: 'Oslo') | ((PBField path: 'name') contains: '7').
lesson check: 'OR with an unindexed branch: one scan for the whole condition' is: (planOf value: unindexed) equals: 'Filter <- CollectionScan'.
notOslo := q where: (city eq: 'Oslo') not.
lesson check: 'NOT of a term: a residual filter over a scan' is: (planOf value: notOslo) equals: 'Filter <- CollectionScan'.
```

**6. Order** (`planner.py:263-275`). For an order on one key, each index that yields that key in
order contributes an ordered scan with the whole condition as a residual filter, competing with a
`Sort` over the planned condition. A selective condition is planned by index and sorted; an
unselective one streams the ordered index. With several keys the plan uses `Sort`. A limit and
an offset add a `Limit` on top.

**Why there is no intersection.** Two indexed conjuncts invite the plan "ask both indexes and
intersect". Under this model `Intersect(a, b)` costs `cost(a) + rows(a) + cost(b) + rows(b)`, never
less than `Filter(a, b)` at `cost(a) + rows(a)`, so `proto_db` does not enumerate intersections at all
(`planner.py`, module docstring, "Access paths and cost"; `query-planner.rst`). That is a claim of
the model; measured in T7 (bench P3, one size and one selectivity: 2000 records, 29 rows, 5 runs): the
hand-built intersection took 3.9x the filter plan's time in `proto_db` and 13.2x in protoBaseST
(model: 2.4x), so the claim holds at both speeds on that data ([deviations.md](deviations.md#p1-p2-p3-the-planners-overhead-the-cost-model-against-timings-the-intersection)).

**The crossover where scanning wins.** For a tiny collection the scan and its filter (two units per
element) are cheaper than any descent. With one element, a matching lookup costs 1 + log2 3 ≈ 2.58
against the scan's 2 (model estimates), and the planner scans; with two elements in two groups the
lookup costs 3 and the scan 4, and it looks up. In the model, then, the switch in collection size
comes at once, so size is not what bench P2 sweeps (ruling CR2). Whether the timings cross where the
model says is a measurement: measured in T7 (bench P2, 2000 records, both plans forced): the model switches to the scan only
between 99 % and 100 % of a unique range key, and for `ne:` on an index of n groups. It switches
early: in `proto_db` the forced index plan is still faster at both points (by 31 % and 19 %), and
in protoBaseST the `ne:` complement is 30 % faster than the scan it rejects, while on the range
key the two plans converge, within the run's noise. Below the switch the index wins in proportion
to the rows. The model is slightly pessimistic about the index, never wrong about the answer
([deviations.md](deviations.md#p1-p2-p3-the-planners-overhead-the-cost-model-against-timings-the-intersection)).

**`!=` and the complement.** An `IndexComplement` is charged a full pass over the index (total + G
+ 1), yet it is still cheaper than a scan with a filter (2n) whenever the index has fewer than
n − 1 groups, so a lone `ne:` uses the index (`proto_db`'s test
test_ne_term_alone_prefers_the_index_complement_over_scan_plus_filter). Combined with a selective
indexed conjunct, it becomes a residual filter instead.

**Known limits of the model**, as `proto_db` states them (`query-planner.rst`, "The invariant and
the cost of a wrong estimate"): a `Limit` is charged its whole source, so a top-k query may sort
where streaming an ordered index would stop early; and the selectivity of a filter is a constant.
The planner can only be slow by choosing badly, never wrong, because of the exactness invariant.

**Floating-point parity (deviation R2, ruling IQ4).** Costs are Floats computed by the same formulas
in the same order as `proto_db`'s. The descent term `log2 (G + 2)` is computed in protoST as
`ln x / ln 2`, which can differ from C's log2 in the last bit, so two candidates whose costs differ
by one unit in the last place could rank differently in the two implementations: the same answer
by another plan. The query vectors compare plans and report such near ties by name; results must
always be equal.

**No fallback.** Nothing in the query path catches an error to answer something else. A malformed
query is `PBValidationError`; an unsupported one `PBNotSupportedError`.

Measured in T7 (bench P1): `plan` and `explain` alone take 0.04 to 4.5 ms a query in `proto_db`
and 0.71 to 47 ms in protoBaseST, from one conjunct without an index to 32 conjuncts over 8 indexes;
the cost grows with conjuncts times indexes ([deviations.md](deviations.md#p1-p2-p3-the-planners-overhead-the-cost-model-against-timings-the-intersection)).

## Reading a plan

`explain` answers the plan that `execute` runs, never a description of another one. It is a
`PBFrozenDict` of Strings, Numbers, `nil`, Booleans and `PBFrozenList`s (what a decoded
MessagePack list is), in `proto_db`'s shape (`plans.py`, `QueryPlan._explain`), so
`PBNotation describe:` prints it and the conformance runner compares it with `proto_db`'s. The
nodes and `explain` exist since plan Task 6 (`src/protobase/plans.st`), the planner that chooses
among them since Task 7 (`tests/conformance/queries.st` compares the whole explain of every
recorded query with `proto_db`'s). For every term of the conformance vector, an index plan's explain,
less its estimate, is byte for byte `proto_db`'s, and its estimate equal within 1e-12 relative
(`tests/unit/qry_index_plans.st`):

```
{ 'plan' -> <node name>.  <the node's own fields>.
  'estimate' -> { 'rows' -> r. 'cost' -> c }.
  'children' -> { <the explain of each source, in order> } }
```

### The nodes and their fields

| Node | Fields besides `'plan'`, `'estimate'`, `'children'` | Children |
|---|---|---|
| `CollectionScan` | `'collection'` (`proto_db`'s class name of the collection, `'Dictionary'`, `'List'`, `'HashDictionary'`, `'Set'`, `'CountedSet'` or `'RepeatedKeysDictionary'`, never the protoST class name, so the explain of both languages compares equal), `'rows'` (its count), `'indexes'` (its index names) | none |
| `IndexLookup`, `IndexRange`, `IndexComplement` | `'index'` (the index's own explain, below), `'term'` (the term's description) | none |
| `IndexOrderedScan` | `'index'`, `'term'` (`nil`), `'descending'` | none |
| `Filter` | `'predicate'`: the residual condition's description | its source |
| `BlockFilter` | `'description'`: the block's description (protoBaseST; `proto_db`'s `PythonFilter`) | its source |
| `Union`, `Intersect` | none | two or more sources |
| `Project` | `'fields'` (output name to path) or `'function'` (a block's description) | its source |
| `Sort` | `'keys'`: an Array of `{ 'key' -> path or description. 'descending' -> aBoolean }` | its source |
| `Limit` | `'limit'` (`nil` when unbounded), `'offset'`, and `'by_rank'`: true when the window is sought by rank | its source |
| `Count` | `'by_rank'`: true when the count is read from the source's exact row count | its source |
| `Distinct` | none | its source |

An index explains itself as a `PBFrozenDict` with `'index'` (its name), `'kind'` (`proto_db`'s class
name, `'EqualityIndex'` or `'RangeIndex'`, ruling CR4), `'key'` (the key spec's description),
`'entries'` (occurrences), `'keys'` (distinct orderable keys) and `'unorderable'` (occurrences in
the side group) (`indexing/base.py:309-311`, `keyed.py`, `explain`). A term
describes itself as `{ 'path' -> path. 'op' -> operator. 'value' -> operand }`; an `&` as
`{ 'and' -> { ... } }`, an `|` as `{ 'or' -> { ... } }`, a `not` as `{ 'not' -> ... }`.

`'by_rank'` appears only when it is true. When it does, the subtree under that `Limit` or `Count` is
not executed row by row: it is sought (`plans.py`, `Limit.explain`).

### What the estimate means

`rows` is how many rows the planner expects the node to produce; `cost` is an abstract number of
units of work for the node **and everything under it**. Neither is a time or a promise. Costs are
comparable only between plans of the same query on the same collection version; their purpose is
to rank candidates. `rows` is exact for an index lookup (the group records its size) and an
estimate everywhere else: a filter guesses half per term.

To see **why the planner chose** a plan, compare it with the candidate it rejected. The rejected
candidates are not in `explain`, but each can be made the cheapest by removing the index the winner
used (`removeIndex:` answers a new version; the stored collection is unchanged) and explaining the
same query again. Plan 2 below does exactly that.

### Plan 1: a lookup

The data, here and in the next two plans: 600 people, cities Lima, Oslo, Paris and Rome in turn
(150 each), ages 18 to 77 (ten each), with a `PBEqualityIndex` `'by_city'` and a `PBRangeIndex`
`'by_age'`. **Every figure in these three plans is a model estimate**: the output of the cost model
above, never a measurement and never a promise of time. Ruling CR10 requires each to equal
`proto_db`'s own planner output for the same data, generated from `proto_db` by a script
(`tests/interop/py_guide_plans.py`); `tests/docs/guide_plans.sh` checks every figure below against
that output, and the program checks that protoBaseST's planner computes the same. Costs are
compared within 1e-9 because of R2. Built node by node (Task 6, before the planner), the plans below
give these figures exactly, model estimate for model estimate, including the rejected candidates'
(`tests/unit/qry_plans.st`, check 'the three plans of the guide give its model estimates exactly').

```smalltalk
oslo := q where: (city eq: 'Oslo').
plan := oslo explain.
index := plan at: 'index'.
lesson check: 'plan 1 is an index lookup' is: (plan at: 'plan') equals: 'IndexLookup'.
lesson check: 'the index explains itself' is: { index at: 'index'. index at: 'kind'. index at: 'key' } equals: #('by_city' 'EqualityIndex' 'city').
lesson check: 'its size: entries, keys, unorderable' is: { index at: 'entries'. index at: 'keys'. index at: 'unorderable' } equals: #(600 4 0).
lesson check: 'the term' is: { (plan at: 'term') at: 'path'. (plan at: 'term') at: 'op'. (plan at: 'term') at: 'value' } equals: #('city' '==' 'Oslo').
lesson check: 'rows: the size of the Oslo group' is: ((plan at: 'estimate') at: 'rows') equals: 150.
lesson check: 'cost: rows plus one descent, log2 (4 + 2)' isTrue: (close value: ((plan at: 'estimate') at: 'cost') value: 152.58496250072116).
lesson check: 'a leaf has no children' isTrue: (plan at: 'children') isEmpty.
```

Reading it (model estimates): one node, an `IndexLookup` of `'by_city'` for `city == 'Oslo'`. The
index has 600 entries in 4 key groups. The lookup produces the Oslo group, 150 rows, exactly; its
cost is those 150 rows plus one descent of `log2 (4 + 2)` ≈ 2.585. The rejected candidate, a scan
with a filter, costs 600 + 600 = 1200 and would produce an estimated 300 rows.

### Plan 2: two conditions

```smalltalk
old := q where: ((city eq: 'Oslo') & (age > 70)).
filter := old explain.
range := (filter at: 'children') at: 1.
lesson check: 'plan 2 is a filter over the age range' is: { filter at: 'plan'. range at: 'plan' } equals: #('Filter' 'IndexRange').
lesson check: 'the range: 7 keys of 10 rows' is: ((range at: 'estimate') at: 'rows') equals: 70.
lesson check: 'its cost: rows + log2 (60 + 2) + keys' isTrue: (close value: ((range at: 'estimate') at: 'cost') value: 82.95419631038688).
lesson check: 'the filter halves the rows, per term' is: ((filter at: 'estimate') at: 'rows') equals: 35.
lesson check: 'and pays one unit per row it reads' isTrue: (close value: ((filter at: 'estimate') at: 'cost') value: 152.95419631038686).
withoutAge := (PBQuery from: (people removeIndex: 'by_age')) where: ((city eq: 'Oslo') & (age > 70)).
lesson check: 'the rejected candidate, made visible: the city lookup and a filter'
    isTrue: (close value: ((withoutAge explain at: 'estimate') at: 'cost') value: 302.5849625007212).
scanOnly := (PBQuery from: ((people removeIndex: 'by_age') removeIndex: 'by_city')) where: ((city eq: 'Oslo') & (age > 70)).
lesson check: 'and the scan: two units per element' is: ((scanOnly explain at: 'estimate') at: 'cost') equals: 1200.
```

Reading it from the leaf up (model estimates). The `IndexRange` of `'by_age'` for `age > 70` covers the keys 71 to 77,
7 of the 60 groups; with 600 entries in 60 groups it estimates 10 rows per key, 70 rows, at a cost
of 70 + `log2 (60 + 2)` + 7 ≈ 82.95. The `Filter` above it tests `city == 'Oslo'` on those 70 rows:
it pays one unit per row read (cost ≈ 152.95) and is estimated to keep half (35 rows).

The three candidates were:

| Candidate | Estimated cost (model estimate) |
|---|---|
| `Filter (city) <- IndexRange (age > 70)` | ≈ 152.95, chosen |
| `Filter (age) <- IndexLookup (city == 'Oslo')` | ≈ 302.58 |
| `Filter (both) <- CollectionScan` | 1200 |

The query really answers 20 rows, not 35: in this data the city and the age are correlated, and the
model assumes nothing about correlations. The estimate only had to rank the candidates, and the
ranking is right: the age range reads 70 rows, the city lookup 150.

### Plan 3: an ordered window

```smalltalk
window := (((q where: (age between: 30 and: 35)) orderBy: 'age') take: 5) explain.
sort := (window at: 'children') at: 1.
lesson check: 'plan 3: a limit over a sort over the range' is: { window at: 'plan'. sort at: 'plan'. ((sort at: 'children') at: 1) at: 'plan' } equals: #('Limit' 'Sort' 'IndexRange').
lesson check: 'the limit: its window, read by rank' is: { window at: 'limit'. window at: 'offset'. window at: 'by_rank' } equals: #(5 0 true).
lesson check: 'the sort key' is: ((sort at: 'keys') at: 1) equals: (PBFrozenDict withAssociations: { 'key' -> 'age'. 'descending' -> false }).
lesson check: 'the sort pays n log2 n on 60 rows'
    isTrue: (close value: ((sort at: 'estimate') at: 'cost') value: 426.367632046898).
lesson check: 'the limit is charged its whole source' isTrue: (close value: ((window at: 'estimate') at: 'cost') value: 426.367632046898).
```

Reading it from the leaf up (model estimates). The `IndexRange` for `between[] 30 35` covers 6 keys, 60 rows, at
60 + `log2 62` + 6 ≈ 71.95. The `Sort` by `'age'` adds 60 × `log2 60` ≈ 354.41, for ≈ 426.37. The
`Limit` keeps 5 rows from offset 0 and is charged its whole source, ≈ 426.37 (the model's known
limit).

The rejected candidate streams the ordered index and filters every element:
`Filter <- IndexOrderedScan`, at a model estimate of (600 + 60 + 1) + 600 = 1261. A selective condition is found by its
index and sorted; without the condition the ordered scan (661) would beat sorting all 600 rows
(600 + 600 × `log2 600` ≈ 6137), and the plan would be `Limit <- IndexOrderedScan`
([chapter 19](tutorial/19-ordered-reads-and-pages.md#an-order-on-an-indexed-key)).

`'by_rank'` is true although there is a `Sort`: the source of the sort is an index plan of the sort's
only key, and an index range is already in key order, so the sort can serve rows 0 to 4 by rank
without sorting (`plans.py`, `Sort._rank`; the plan's `execute` still describes a sort, and its rows
are identical to a sort's).

## Ordered reads, windows and pages

**Rank access** (`proto_db` D56; `keyed.py`, "Rank access"; `plans.py`, its window and exact_rows methods).
A plan may offer `windowFrom:to:`, rows `start` to `stop − 1` without producing the rows before
`start`, and `exactRows`, its row count without producing it. These are offered by:

- an index lookup, range or ordered scan of a weighted index;
- a scan of a `PBList` or a `PBDictionary` (positional and keyed trees count their nodes);
- a `Limit` over a plan that offers it;
- a `Filter` of a single term over an ordered scan of the index that answers that term;
- a `Sort` on one key over an index plan of that key.

Anything else (a block key, two sort keys, a filter of several terms, a union) has no rank access.

<!-- example: examples/queries/ranges.st -->

Ranges and ordered reads over a range index on the age of chapter 18's 600 people (ten of each age,
18 to 77), from [examples/queries/ranges.st](../examples/queries/ranges.st):

```smalltalk
lesson check: 'a comparison is a range of the index' is: (planOf value: (q where: age > 70)) equals: 'IndexRange'.
lesson check: 'seven ages of ten people' is: (q where: age > 70) count equals: 70.
lesson check: 'counted by rank' is: ((PBCountPlan source: (q where: age > 70) plan) explain at: 'by_rank') equals: true.
youngest := (q orderBy: 'age') take: 5.
lesson check: 'an ordered read streams the index' is: (planOf value: youngest) equals: 'Limit <- IndexOrderedScan'.
lesson check: 'and seeks its window by rank' is: (youngest explain at: 'by_rank') equals: true.
lesson check: 'the five youngest' is: (youngest asArray collect: [:p | p at: 'age']) equals: #(18 18 18 18 18).
oldest := (q orderBy: 'age' descending: true) take: 3.
lesson check: 'descending reads the index backwards' is: (oldest asArray collect: [:p | p at: 'age']) equals: #(77 77 77).
lesson check: 'a window of any plan with rank access'
    is: (((q orderBy: 'age') plan windowFrom: 100 to: 103) collect: [:p | p at: 'age']) equals: #(28 28 28).
```

**Windows.** A `Limit` over a plan with rank access seeks its window in O(log n + its size)
(`'by_rank'` in `explain`). A `Count` over one reads the count.

**Pagers** (spec 5.7). `PBPager on: aPlanOrQuery pageSize: n`, or `aQuery pagerSize: n`, holds one
plan built on one snapshot. With rank access page k costs O(log n + page size); otherwise the
result is materialised once and sliced. A pager never shows a row twice and never skips one,
whatever commits meanwhile, because the snapshot's versions do not change. It lives in one process:
`proto_db`'s portable pager tokens are deferred (spec 3.2), because the token's plan digest is
computed over Python's `repr` of the plan.

[measured in T9: bench Q5, the time of page k for every k, by rank and materialised, and `count` by
rank.] Measured in T8 (bench Q4, 2000 elements, 20 queries of `take: 5`, the minimum;
[deviations.md](deviations.md#q1-q4-queries-indexed-against-a-forced-scan)): the ordered index scan answered in 0.9 ms per query against 180 ms for a
`Sort` over a scan; with a condition the planner sorts over a lookup, 2.5 ms per query for ten
rows and 58 ms for 500. `proto_db`: 0.12, 5.0, 0.23 and 1.7 ms.

## Index maintenance under immutability and the commit

### Where it happens

Exactly where `proto_db` does it: inside each mutator, in the transaction's own thread, before the
commit (spec 5.3). There is no commit-time index step, so a version a transaction reads back always
agrees with its own indexes, and a snapshot's indexes are the snapshot's.

| Collection | Index work per mutator |
|---|---|
| `PBList` | `appendFirst:`, `appendLast:`, `insertAt:value:` add; `setAt:value:` replaces; `removeAt:` removes; `extend:` adds each; `sliceFrom:to:`, `head:`, `tail:` remove what they drop |
| `PBDictionary`, `PBHashDictionary` | `setAt:value:` adds the value for a new key and replaces it for a present one; `removeAt:` of a present key removes its value |
| `PBSet` | `add:` of an absent element adds; `remove:` of a present one removes; `union:`, `intersection:`, `difference:` fold those |
| `PBCountedSet` | each occurrence added or removed is one index occurrence |

The element an index sees is what `elements` answers: a list's items, a dictionary's values, a
set's members. The order of the index calls in each mutator is `proto_db`'s, because it decides the
shape of the persisted trees, and the conformance tests compare nodes. A mutator call that changes
nothing (adding a present set member) does no index work.

**Stale indexes.** An index written by format 3 (`hasMemberTokens` false) is rebuilt from the
elements before the collection's first change (`proto_db` D58, call IC7). A first change to a large
stale collection pays a full build: in bench M2, on an `EqualityIndex` over 10^4 records, the bulk
build took 10.0 s against 30.6 s for the fold of single additions (`proto_db`: 0.26 s against
1.0 s; [deviations.md](deviations.md#m2-the-bulk-build-against-the-fold-of-single-additions)).

**Unsaved atoms.** A new index version is an unsaved atom like a new collection version; its trees
are new dependents of the collection, saved by the writer's existing dependents-first walk.

### Merges of blind writes

A blind write of a collection built from new merges at commit by replaying the net effect of its
operation log onto the current version (chapter 6). Onto an indexed current, the obvious merge would
replace the root, and a concurrent commit's change would be lost silently. The merge instead
replays the intents through **the public mutators of the current version**, which maintain the
current version's indexes (`proto_db`, `collections/base.py:594-631`); it needs no index-specific
rule.

<!-- example: examples/queries/merge_indexed.st -->

From [examples/queries/merge_indexed.st](../examples/queries/merge_indexed.st): two blind writes
onto a dictionary of 600 people indexed by city, committed one after the other.

```smalltalk
mine setRootObject: 'people' value: (mine newDictionary
    setAt: 700 value: (mine newObject: { 'name' -> 'person700'. 'city' -> 'Oslo' })).
theirs setRootObject: 'people' value: (theirs newDictionary
    setAt: 701 value: (theirs newObject: { 'name' -> 'person701'. 'city' -> 'Oslo' })).
mine commit.
theirs commit.
people := db newTransaction getRootObject: 'people'.
lesson check: 'both blind writes merged, and the index counts them' is: (inOslo value: people) equals: 152.
lesson check: 'the merged version keeps its index' is: people indexNames equals: #('by_city').
lesson check: 'and the index equals a scan'
    is: ([people validate. 'clean'] on: PBCorruptionError do: [:e | e messageText]) equals: 'clean'.
```

Index definitions are logged too: `addIndex:` logs `('@index_add' name index)` and `removeIndex:`
logs `('@index_remove' name)`, on every logged collection class, never on `PBList`
(`base.py:572-573`). A merge replays the element operations first, then the index-definition
operations per name. An index that this log created and that the current version also has is a
concurrent creation: that commit is `PBConflictError`.

```smalltalk
one setRootObject: 'tags' value: (one newDictionary addIndex: (PBEqualityIndex name: 'by_tag' path: 'tag')).
two setRootObject: 'tags' value: (two newDictionary addIndex: (PBEqualityIndex name: 'by_tag' path: 'tag')).
one commit.
lesson check: 'the second creation of the same index is a conflict'
    signals: PBConflictError containing: 'by_tag' during: [two commit].
```

Three consequences follow, each explicit:

- **The merge runs index work in the commit's build**, so an indexed root lengthens the commit.
  Bench M3 (120 blind writes merged onto a 600-record dictionary): standalone, protoBaseST
  commits 34.2, 11.9 and 5.1 times per second with 0, 1 and 3 indexes (`proto_db` 141, 110 and
  81), what a read-modify-write costs (M1); in a three-member cluster 17.4, 6.8 and 1.1, because
  the build (34, 91 and 189 ms) runs under the write permission and, with three indexes, leaves
  too little of it for the send, so rounds are refused and retried
  ([deviations.md](deviations.md#m3-a-blind-write-merged-onto-an-indexed-current-standalone-and-in-a-cluster);
  indicative only).
- **Extractors run in the commit's build** ([above](#extractors-and-their-purity-contract)): an
  exception fails only that commit, standalone, in a group commit and in a cluster round.
- **What is still refused.** A merge onto a collection holding a vector index or an index of an
  unknown kind is `PBNotSupportedError`, as any change to it is.

The cost on every write, merged or not, is a new version of two trees per index (the key groups,
and the members of one group), on top of the collection's own. protoBaseST's tree operations are
12 to 31 times slower than `proto_db`'s ([deviations.md](deviations.md#avl-operations)), so index
what you query. Bench M1 (200 single-element transactions on a 600-record dictionary): with 0, 1
and 3 indexes protoBaseST commits 38, 11.9 and 5.2 times per second, `proto_db` 150, 115 and 83;
each index adds about 55 ms per commit here and 2 ms in `proto_db`
([deviations.md](deviations.md#m1-commits-per-second-with-0-1-and-3-indexes); indicative only).

## Cluster mode

Indexes change nothing in cluster mode's protocol (spec 5.8):

- **Nothing on the wire changes.** Indexes are ordinary records, shipped and persisted with the
  commit like any other; no message names an index. The cluster messages named `'query'` and
  `'commit_query'` are not database queries: `'query'` asks a peer for its acceptor state, and
  `'commit_query'` asks where a commit's records are (Phase D, not ported).
- **Reads.** A query reads the transaction's snapshot, so in a cluster it has exactly the
  consistency `getRootObject:` has there. It never contacts a peer.
- **Writes and merges.** Index maintenance happens in the writer's mutators before the round. A
  merge onto an indexed current happens in the round's build, on the member that holds the write
  permission, which is the member whose transaction it is (or its group-commit leader in the same
  process). An extractor index therefore needs the extractor registered in that process, as in
  standalone mode, and a merge onto an indexed root lengthens the build, which runs under the
  cluster-wide permission (bench M3 above, cluster profile).
- **No new safety argument.** The build is deterministic given the transaction and the current
  root; replaying it after a lost round gives the same root, as today. An extractor's purity is
  what makes that true for an extractor index.

## What it costs

Every figure of this feature is owed by a benchmark of spec 7.3, run on both implementations with
the same seed, data and queries (the list syntax), and refused by its runner unless both report the
same rows, checksum and plan. None exists yet.

| What | Bench | Task |
|---|---|---|
| A point lookup against collection size, indexed and scanned | Q1 | Measured in T8, sizes 10^2 to 10^4: about 1 ms per lookup at every size against a scan of 5.5 to 565 ms; `proto_db` 0.1 ms against 0.3 to 28 ms ([deviations.md](deviations.md#q1-q4-queries-indexed-against-a-forced-scan)) |
| `'in'` of 1, 10, 100 values; ranges of 0.1 % to 50 % selectivity | Q2 | Measured in T8: the index wins at every point, 1.4 to 49 ms per query against 130 to 430 ms for the scan; 11x to 26x `proto_db`'s time ([deviations.md](deviations.md#q1-q4-queries-indexed-against-a-forced-scan)) |
| AND, OR of two indexed branches and of an indexed and an unindexed one, NOT | Q3 | Measured in T8: AND 2.5 ms against a 168 ms scan; the Union of two lookups is slower than the scan in protoBaseST (313 ms against 251 ms), an open item; the other two plan a scan ([deviations.md](deviations.md#q1-q4-queries-indexed-against-a-forced-scan)) |
| Ordered scan against sort, with `take:` | Q4 | Measured in T8: an ordered index scan 0.9 ms per query against 180 ms for a sort over a scan ([deviations.md](deviations.md#q1-q4-queries-indexed-against-a-forced-scan)) |
| Page k by rank against materialised; `count` by rank | Q5 | [measured in T9: Q5] |
| Commits per second with 0, 1 and 3 indexes | M1 | Measured in T4a: protoBaseST 38, 11.9 and 5.2 commits/s, `proto_db` 150, 115 and 83; about 55 ms per index per commit against 2 ms ([deviations.md](deviations.md#m1-commits-per-second-with-0-1-and-3-indexes)) |
| Bulk `addIndex:` against the fold of single additions | M2 | Measured in T3: build 3.1x faster than the fold at 10^4, protoBaseST 16.7x (10^2) to 38.3x (10^4) slower than `proto_db` ([deviations.md](deviations.md#m2-the-bulk-build-against-the-fold-of-single-additions)) |
| Merges onto an indexed current, standalone and in a cluster | M3 | Measured in T4b: standalone protoBaseST 34.2, 11.9 and 5.1 commits/s with 0, 1 and 3 indexes, `proto_db` 141, 110 and 81; a three-member protoBaseST cluster 17.4, 6.8 and 1.1, its three-index build (189 ms) refused for the send reserve 135 to 210 times per 120 commits ([deviations.md](deviations.md#m3-a-blind-write-merged-onto-an-indexed-current-standalone-and-in-a-cluster)) |
| `plan` and `explain` alone, 1 to 32 conjuncts, 0 to 8 indexes | P1 | Measured in T7: 0.71 to 47 ms a query in protoBaseST, 0.04 to 4.5 ms in `proto_db` ([deviations.md](deviations.md#p1-p2-p3-the-planners-overhead-the-cost-model-against-timings-the-intersection)) |
| Where the cost model switches between index and scan, and whether the timings cross there | P2 | Measured in T7: the model switches to the scan at 99-100 % of a unique key and for `!=` on n groups, early: in `proto_db` the forced index plan is still 31 % and 19 % faster there; in protoBaseST the `!=` complement 30 %, the range plans within noise ([deviations.md](deviations.md#p1-p2-p3-the-planners-overhead-the-cost-model-against-timings-the-intersection)) |
| The two-index intersection against the filter plan | P3 | Measured in T7 at one size and selectivity: the intersection takes 3.9x (`proto_db`) and 13.2x (protoBaseST) the filter plan's time; model 2.4x ([deviations.md](deviations.md#p1-p2-p3-the-planners-overhead-the-cost-model-against-timings-the-intersection)) |
| protoBaseST against `proto_db` on every workload above | all | [measured in T10: the full `bench/run_query.sh` comparison, recorded in deviations.md#performance with date, machine, load, commits and binaries] |

## Sources

`proto_db` at `v2.0.0rc4` (protoBase repository, b99285b): `docs/source/indexing-framework.rst`,
`docs/source/query-planner.rst`, `docs/source/tutorials/indexing-querying.rst`;
`proto_db/indexing/keyspec.py`, `base.py`, `keyed.py`; `proto_db/query/terms.py`, `expressions.py`,
`planner.py`, `plans.py`, `pager.py`, `linq.py`; `proto_db/collections/base.py`;
`tests/unit/test_planner.py`. The decisions cited (D28, D30, D36, D56, D58) are `proto_db`'s.

protoBaseST: the [indexed-queries spec](superpowers/specs/2026-11-18-indexed-queries-design.md)
(the rulings IQ1 to IQ8 in its section 9.2, the calls IC1 to IC10 in 9.1) and its implementation
plan, `docs/superpowers/plans/2026-11-18-indexed-queries.md` (the calls IP1 to IP17).
