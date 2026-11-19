# 18. Queries and the planner

<!-- example: examples/tutorial/18_queries_and_plans.st -->
Program: [examples/tutorial/18_queries_and_plans.st](../../examples/tutorial/18_queries_and_plans.st).
Previous: [17. Indexes](17-indexes.md). Next: [19. Ordered reads and pages](19-ordered-reads-and-pages.md).

> **In progress for protoBaseST 0.3.0** (the approved
> [indexed-queries spec](../superpowers/specs/2026-11-18-indexed-queries-design.md)). Every block
> below comes from the chapter's program, which runs as a test and checks what it shows. The
> planner beneath the query API is a line for line port of `proto_db`'s (spec 5.6), and its plans
> are `proto_db`'s node for node on the conformance vectors.

Chapter 17 made indexes part of the collection. This chapter asks questions of it: how to write a
query, how to read the plan that answers it, and why the planner sometimes ignores an index that
exists. The data is chapter 17's: 600 people, four cities in turn, ages 18 to 77, ten people of
each age, with an equality index `'by_city'` and a range index `'by_age'`.

## A query is a value

`PBQuery from: people` makes a query; `where:`, `orderBy:`, `take:` and the rest each answer a
**new** query and leave the receiver as it was, like every value of this library (chapter 2). A
condition is built from a field:

```smalltalk
q := PBQuery from: people.
city := PBField path: 'city'.
age := PBField path: 'age'.
cascaded := q where: (city eq: 'Oslo'); take: 5.
lesson check: 'a cascade sent take: to q: the where: is lost' is: (planOf value: cascaded) equals: 'Limit <- CollectionScan'.
kept := (q where: (city eq: 'Oslo')) take: 5.
lesson check: 'keep each answer' is: (planOf value: kept) equals: 'Limit <- IndexLookup'.
```

The cascade is the trap to see first. `q where: ...; take: 5` sends both messages to q and
answers the last one's result: the first five people, from anywhere. It is the same trap as
`tags add: 'urgent'` with the answer discarded (README), and nothing fails. Parentheses keep each
answer. (planOf, a six-line block of the program, lists the node names of a plan from the
root down, `'Limit <- IndexLookup'`; it reads `explain`, which the next section explains.)

The second trap is `=`:

```smalltalk
lesson check: 'a field is not compared with =: that is a Boolean' is: (city = 'Oslo') equals: false.
lesson check: 'and where: refuses a Boolean'
    signals: PBValidationError containing: 'where: expects a PBExpression or a one-argument block, got a Boolean'
    during: [q where: city = 'Oslo'].
```

Python's `proto_db` writes `F.city == "Oslo"`. A Smalltalk field cannot do the same: `=` must stay
an equality, because collections and tests compare objects with it, and a builder that overrode it
would break them (spec ruling IQ2, call IC4). So equality is `eq:` and inequality `ne:`; the
comparisons `<`, `<=`, `>`, `>=` are kept, with the field as the receiver. `city = 'Oslo'` is
simply `false`, and `where:` refuses it with a `PBValidationError` whose text names what it got:
`where: expects a PBExpression or a one-argument block, got a Boolean` (ruling CR6).

| Write | Means (`proto_db`'s operator) |
|---|---|
| `city eq: 'Oslo'`, `city ne: 'Oslo'` | `==`, `!=` |
| `age < 30`, `age <= 30`, `age > 70`, `age >= 70` | `<`, `<=`, `>`, `>=` (the field must be the receiver: `30 < age` sends `<` to an Integer) |
| `age between: 30 and: 35` | `between[]`; also `betweenOpen:and:`, `betweenLeftOpen:and:`, `betweenRightOpen:and:` |
| `city in: #('Lima' 'Rome')` | `'in'` |
| `zip isNone`, `zip notNone` | `?N`, `?!N` |
| `active isTrue`, `active notTrue`, `tags contains: 'urgent'` | `?T`, `?!T`, `'contains'` |
| `a & b`, `a \| b`, `a not` | `And`, `Or`, `Not` |

`&` and `|` are binary messages, so Smalltalk evaluates them left to right with no precedence
between them: write parentheses. `and:` and `or:` are not used, because their argument is a block
and the compiler inlines them.

## Reading a plan

`explain` answers the plan that will run, as a `PBFrozenDict`: the node name under `plan`, its own
fields, an `'estimate'` with `'rows'` and `'cost'`, and `'children'`. The shape and the keys are
`proto_db`'s (`proto_db/query/plans.py`), so a plan reads the same in both languages.

```smalltalk
oslo := q where: (city eq: 'Oslo').
plan := oslo explain.
lesson check: 'the root node' is: (plan at: 'plan') equals: 'IndexLookup'.
lesson check: 'the index it reads' is: ((plan at: 'index') at: 'index') equals: 'by_city'.
lesson check: 'the term it answers' is: ((plan at: 'term') at: 'op') equals: '=='.
lesson check: 'the estimated rows: exact for an equality' is: ((plan at: 'estimate') at: 'rows') equals: 150.
lesson check: 'the rows it produces' is: oslo count equals: 150.
```

An `IndexLookup` descends the index to the Oslo group and produces its members. Its estimate is the
planner's prediction, not a measurement: `'rows'` is what it expects to produce (exact here, because
the group records its size), and `'cost'` is an abstract number of units, one per row produced, per
key group visited and per tree level descended (`proto_db/indexing/keyed.py` lines 596-622). Costs are
only for comparing candidate plans with each other. The guide reads every node and every field,
with three worked plans: [Reading a plan](../queries.md#reading-a-plan).

## Two conditions: one index and a filter

```smalltalk
oldInOslo := q where: ((city eq: 'Oslo') & (age > 70)).
lesson check: 'the age index, then a filter' is: (planOf value: oldInOslo) equals: 'Filter <- IndexRange'.
lesson check: 'the filter keeps the city test' is: ((oldInOslo explain at: 'predicate') at: 'path') equals: 'city'.
lesson check: 'estimated 35 rows, 20 found' is: { (oldInOslo explain at: 'estimate') at: 'rows'. oldInOslo count } equals: #(35 20).
```

For a conjunction the planner makes a list of candidates: a scan with every condition as a
residual filter, and, for each condition some index can answer, that index's plan with the other
conditions as a filter on top. It picks the cheapest. Here the age range (70 people) and a filter
of the city on them beat the Oslo lookup (150 people) and a filter of the age on them. No
condition is ever dropped: each is answered by the access path or by the filter.

The estimate said 35 and the query found 20. A filter is estimated to keep half of its input per
term (`proto_db`'s `FILTER_SELECTIVITY`, decision D36), because the planner keeps no statistics of
value correlations. A wrong estimate can only make the planner slow, never wrong:

```smalltalk
scan := (PBQuery from: ((people removeIndex: 'by_city') removeIndex: 'by_age')) where: ((city eq: 'Oslo') & (age > 70)).
lesson check: 'without indexes: a scan' is: (planOf value: scan) equals: 'Filter <- CollectionScan'.
lesson check: 'the same rows: an index never changes an answer'
    is: (scan asArray collect: [:p | p at: 'name']) asSortedCollection asArray
    equals: (oldInOslo asArray collect: [:p | p at: 'name']) asSortedCollection asArray.
```

## Why not use both indexes?

The obvious plan for two indexed conditions is to ask both indexes and intersect the two answers.
`proto_db`'s planner never builds it, and protoBaseST's does not either. Under the cost model an
intersection of a and b costs `cost(a) + rows(a) + cost(b) + rows(b)`, and a filter over the
better input costs `cost(a) + rows(a)`: the intersection can never be cheaper
(`proto_db/query/planner.py`, module docstring, "Access paths and cost"). So enumerating
intersections would only add untested code.

That is the model's claim. Whether it holds in time, at protoST's speed, is a measurement:
measured in T7 (bench P3, one size and one selectivity: 2000 records, 29 rows, 5 runs): the
hand-built intersection took 3.9x the filter plan's time in `proto_db` and 13.2x in protoBaseST
(model: 2.4x), so the claim holds at both speeds on that data ([deviations.md](../deviations.md#p1-p2-p3-the-planners-overhead-the-cost-model-against-timings-the-intersection)).

## Why the planner sometimes scans

The obvious rule is "use an index whenever one exists: an index is faster". The cost model says
otherwise for a tiny collection:

```smalltalk
tiny := (PBDictionary new setAt: 1 value: (people getAt: 1)) addIndex: (PBEqualityIndex name: 'by_city' path: 'city').
lesson check: 'the planner scans a tiny collection'
    is: (planOf value: ((PBQuery from: tiny) where: (city eq: 'Oslo'))) equals: 'Filter <- CollectionScan'.
```

With one element, the scan and its filter cost 2 units (one to produce the element, one to test
it); the lookup costs 1 row plus one descent of `log2 (1 + 2)`, about 2.58 (model estimates, as
every cost in this chapter). In this model the switch comes almost at once: with two elements in
two cities the lookup costs 3 and the scan 4. That is the model's crossover in collection size, and
it is too small to be worth measuring (ruling CR2). What matters to a program is whether the
timings agree with the model where it switches for a reason other than size, the selectivity of the
condition: measured in T7 (bench P2, 2000 records, both plans forced): the model switches to the scan only
between 99 % and 100 % of a unique range key, and for `ne:` on an index of n groups. It switches
early: in `proto_db` the forced index plan is still faster at both points (by 31 % and 19 %), and
in protoBaseST the `ne:` complement is 30 % faster than the scan it rejects, while on the range
key the two plans converge, within the run's noise. Below the switch the index wins in proportion
to the rows. The model is slightly pessimistic about the index, never wrong about the answer
([deviations.md](../deviations.md#p1-p2-p3-the-planners-overhead-the-cost-model-against-timings-the-intersection)).

## `not (age = 30)` is not `age ne: 30`

```smalltalk
lesson check: 'not (age = 30): the ageless one too' is: ((PBQuery from: few) where: (age eq: 30) not) count equals: 2.
lesson check: 'age ne: 30: a present age only' is: ((PBQuery from: few) where: (age ne: 30)) count equals: 1.
lesson check: 'a negation stays a residual filter' is: (planOf value: (q where: (age eq: 30) not)) equals: 'Filter <- CollectionScan'.
lesson check: 'ne: has an index plan, the complement' is: (planOf value: (q where: (age ne: 30))) equals: 'IndexComplement'.
lesson check: 'the one exact rewrite: not isNone is notNone' is: (planOf value: (q where: age isNone not)) equals: 'IndexRange'.
```

The list few holds three people: one aged 30, one aged 40, one without an age. The obvious optimisation
rewrites `not (age = 30)` as `age ne: 30` to use the index. It would change the answer: the ageless
person satisfies the first (it is not true that its age is 30) and not the second (`ne:` matches
present keys only, chapter 17). So the planner keeps a negated term as a residual filter, and the
only negation it rewrites is the exact one: `not isNone` is `notNone`
(`proto_db/query/planner.py`, its normalize function). Negations of `&` and `|` are pushed inward
by De Morgan's laws, which is exact because every term answers true or false.

`ne:` itself has an index plan, the complement: every group but one. It is charged a full pass
over the index, and it still beats a scan with a filter, which pays two units per element.

## OR: a union only when every branch has an index

```smalltalk
lesson check: 'two indexed branches: a union'
    is: (planOf value: (q where: ((city eq: 'Oslo') | (city eq: 'Rome')))) equals: 'Union <- IndexLookup'.
lesson check: 'an unindexed branch: one scan for the whole OR'
    is: (planOf value: (q where: ((city eq: 'Oslo') | ((PBField path: 'name') contains: '7')))) equals: 'Filter <- CollectionScan'.
```

A disjunction gets a `Union` of index plans only when every branch has one. If one branch needs a
scan, a union that includes that scan always costs more than the scan alone, filtered by the whole
`|`. A union keeps each element with its largest multiplicity over its branches, so it answers
the same multiset as a scan.

## Blocks: what no index can answer

```smalltalk
sevens := q where: [:p | (p at: 'age') \\ 7 = 0].
lesson check: 'a block predicate is a BlockFilter over a scan' is: (planOf value: sevens) equals: 'BlockFilter <- CollectionScan'.
mixed := (q where: (city eq: 'Oslo')) where: [:p | (p at: 'age') \\ 7 = 0].
lesson check: 'beside an indexed conjunct, the block filters on top' is: (planOf value: mixed) equals: 'BlockFilter <- IndexLookup'.
lesson check: 'Oslo people whose age is a multiple of 7' is: mixed count equals: 20.
```

A plain block enters a query only through `where:`; `&`, `|` and `not` take expressions only, and
chained `where:` calls combine with AND, as mixed above shows (ruling CR5). The planner cannot look
inside a block, so it runs element by element and never uses an index; `explain` names it
`BlockFilter` (`proto_db` calls the node `PythonFilter`, after the language that runs it; the
different name is a listed deviation). In a conjunction, the conditions built from fields go to the planner and the block filters what they
answer, so an indexed condition beside a block still uses its index. A `PBBlockPredicate` (a block
with a description, which is an expression) inside an `|` or a `not` makes the whole condition one
block filter.

The obvious next step would be to translate a block such as `[:p | (p at: 'city') = 'Oslo']` into
a condition, as GemStone's selection blocks are. The first release does not (ruling IQ2): a
translation by running the block on a recording object fails silently on `30 < (p at: 'age')`, on
inlined `ifTrue:` and `==`, and on a block that calls a method of the element. A course should not
teach a feature whose failures are silent.

## What to take away

- A query is a value: keep each answer; a cascade loses all but the last message.
- `eq:` and `ne:`, not `=`; the field is the receiver of `<` and its kin.
- `explain` is the plan that runs. Its estimates compare plans; they are not promises.
- One access path plus filters; no intersections; a union only of indexed branches.
- The cost model sometimes prefers the scan; an index never changes an answer.
- `not (x = 5)` is not `x ne: 5`: absence satisfies only the first.
- A block never uses an index, and `explain` says so.
