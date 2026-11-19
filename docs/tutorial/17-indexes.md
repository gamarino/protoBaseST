# 17. Indexes

<!-- example: examples/queries/pending/17_indexes.st.pending -->
Program, pending: [examples/queries/pending/17_indexes.st.pending](../../examples/queries/pending/17_indexes.st.pending).
Previous: [16. Operating a cluster](16-operating-a-cluster.md). Next: [18. Queries and the planner](18-queries-and-plans.md).

> **Draft: the API in this chapter is not implemented.** Indexed queries are planned for
> protoBaseST 0.3.0 by the approved
> [indexed-queries spec](../superpowers/specs/2026-11-18-indexed-queries-design.md). Today a
> collection with an index refuses every change (chapter 4). Every block below comes from a
> program written against the spec's API that **has never run**. Figures marked
> `[measured in T<n>: ...]` do not exist yet; they will come from the benchmarks of spec
> section 7.3, task T<n>. Read this chapter as the design explained, not as a description of
> working code.

Chapter 4 answered questions in two ways: a walk over the collection, or a second collection the
program keeps itself. This chapter shows why both stop working as the data and the number of
writers grow, and what `proto_db` does instead: the index becomes part of the collection.

The program builds 600 people: four cities in turn (Lima, Oslo, Paris, Rome), ages 18 to 77, ten
people of each age.

## The obvious solution: walk

```smalltalk
walk := [:ps :city | | found |
    found := 0.
    ps do: [:p | (p at: 'city') = city ifTrue: [found := found + 1]].
    found].
lesson check: 'a walk finds the people in Oslo' is: (walk value: (db newTransaction getRootObject: 'people') value: 'Oslo') equals: 150.
```

It is correct, and it is the right answer for 600 elements read once. Its cost is the size of the
collection, whatever the answer: finding one person among a million reads a million records.
In protoBaseST each record read is a lazy load and a decode, so the cost per element is not
small. [measured in T8: bench Q1, the time of one point lookup against collection size, 10^2 to
10^5 elements, by a walk and by an equality index, RUNS=5 interleaved, minimum and median.]

## The next obvious solution: keep the lookup yourself

Chapter 4 kept a second root, a dictionary from a year to the set of books, updated in the same
transaction as the books. The program here builds the same for cities, once:

```smalltalk
db newTransactionDo: [:t |
    | byCity |
    byCity := t newDictionary.
    (t getRootObject: 'people') keysAndValuesDo: [:id :p |
        byCity := byCity setAt: (p at: 'city') value: ((byCity getAt: (p at: 'city') default: PBSet new) add: id)].
    t setRootObject: 'byCity' value: byCity].
```

Then a writer adds a person and does not touch `'byCity'`. It might be a program written a year
later, or the Python side of chapter 11, which has never heard of a root named `'byCity'`:

```smalltalk
db run: [:t |
    t setRootObject: 'people' value: ((t getRootObject: 'people')
        setAt: 600 value: (t newObject: { 'name' -> 'person600'. 'city' -> 'Oslo'. 'age' -> 40 }))].
tr := db newTransaction.
lesson check: 'the walk sees the new person' is: (walk value: (tr getRootObject: 'people') value: 'Oslo') equals: 151.
lesson check: 'the hand-kept index does not, and nothing said so'
    is: ((tr getRootObject: 'byCity') getAt: 'Oslo') count equals: 150.
```

This is how a hand-kept index fails, and none of it is a bug in the program that kept it:

- **Every writer must remember it**, in both languages, forever. The database does not know that
  `'byCity'` describes `'people'`; to the database they are two unrelated roots.
- **Merges do not help.** Two blind writes to `'people'` merge (chapter 6), and two blind writes to
  `'byCity'` merge too, but each root is merged on its own. Nothing keeps the second in step with
  the first.
- **Nothing checks that the two agree.** The stale answer is a valid answer to the database. It
  is found later, by someone else, as a wrong report.

## An index is part of the version

`proto_db`'s answer is to make the index a field of the collection version itself. A collection
carries an index set; `addIndex:` builds the index over the elements held now and answers a new
version of the collection, holding both.

```smalltalk
db run: [:t |
    t setRootObject: 'people' value: (((t getRootObject: 'people')
        addIndex: (PBEqualityIndex name: 'by_city' path: 'city'))
        addIndex: (PBRangeIndex name: 'by_age' path: 'age'))].
people := db newTransaction getRootObject: 'people'.
lesson check: 'two indexes, part of the version' is: people indexNames equals: #('by_age' 'by_city').
oslo := (PBQuery from: people) where: ((PBField path: 'city') eq: 'Oslo').
lesson check: 'the index answers what the walk answered' is: oslo count equals: 151.
lesson check: 'and the planner used it' is: (oslo explain at: 'plan') equals: 'IndexLookup'.
```

(`PBQuery` and `explain` are chapter 18's subject; here they only ask the question.)

The decisive property is where the index is updated: **in every mutator**, in the transaction's
own thread, before the commit. `setAt:value:` computes the new tree of the dictionary and the new
version of each index in one step and answers one new collection holding both
(`proto_db`, `collections/base.py` lines 1-13). There is no code path that answers a collection with a
stale index, so a writer cannot forget: the writer that added person 600 above would have updated
`'by_city'` without knowing it existed.

Why not at commit time, in the publisher, for the roots that changed? Because a transaction reads
back its own uncommitted versions (chapter 5), and those would then disagree with their own
indexes until the commit; and a snapshot could see an index ahead of or behind its data.

The index costs no copy of itself per write. It is an immutable tree beside the data, and each new
version shares every unchanged subtree with the last (path copying, chapter 2): a write copies
about the height of the index's trees.

## Every change, and every snapshot

```smalltalk
inCity := [:ps :city | ((PBQuery from: ps) where: ((PBField path: 'city') eq: city)) count].
before := db newTransaction.
db run: [:t | | ps |
    ps := t getRootObject: 'people'.
    ps := ps setAt: 0 value: ((ps getAt: 0) with: 'city' value: 'Oslo').
    ps := ps removeAt: 1.
    t setRootObject: 'people' value: ps].
after := db newTransaction getRootObject: 'people'.
lesson check: 'person 0 left Lima' is: (inCity value: after value: 'Lima') equals: 149.
lesson check: 'person 0 came to Oslo, person 1 left it' is: (inCity value: after value: 'Oslo') equals: 151.
lesson check: 'the snapshot taken before keeps its own index' is: (inCity value: (before getRootObject: 'people') value: 'Lima') equals: 150.
lesson check: 'validate: every index equals a scan'
    is: ([after validate. 'clean'] on: PBCorruptionError do: [:e | e messageText]) equals: 'clean'.
```

Replacing person 0 by a version living in Oslo moved it from one key group of `'by_city'` to
another; removing person 1 took it out of the Oslo group. The transaction opened before the commit
still reads its own snapshot, and the snapshot's indexes are the snapshot's: an index is never
shared between versions in a way that could leak a later change into an earlier one.

`validate` compares every index of the collection with a scan of its elements and signals
`PBCorruptionError` on any difference. It is how a test, or a suspicious operator, checks the
invariant this whole design rests on: **for every collection, every index configuration and every
query, an index answers the same multiset of elements as a full scan.** `proto_db` property-tests
it (`tests/property/test_index_equals_scan.py`); protoBaseST will port that test (spec 7.2).

## Blind writes still merge

```smalltalk
mine setRootObject: 'people' value: (mine newDictionary
    setAt: 700 value: (mine newObject: { 'name' -> 'person700'. 'city' -> 'Oslo'. 'age' -> 30 })).
theirs setRootObject: 'people' value: (theirs newDictionary
    setAt: 701 value: (theirs newObject: { 'name' -> 'person701'. 'city' -> 'Oslo'. 'age' -> 31 })).
mine commit.
theirs commit.
after := db newTransaction getRootObject: 'people'.
lesson check: 'both blind writes merged, the index counts them' is: (inCity value: after value: 'Oslo') equals: 153.
lesson check: 'and the merged version keeps its indexes' is: after indexNames equals: #('by_age' 'by_city').
```

Neither transaction read `'people'`, and neither new dictionary has an index. The obvious way to
merge them onto the indexed root would be to replace it, and a concurrent commit's change would be
lost silently. Chapter 6's merge does something else: it replays each transaction's intents
(`setAt:value:` of 700, of 701) through the **public mutators of the current version**, and those
mutators maintain the current version's indexes (`proto_db`, `collections/base.py` lines 594-631). The
merge needs no index-specific rule at all.

Two consequences, both explained in [the guide](../queries.md#index-maintenance-under-immutability-and-the-commit):
the merge now runs index work during the commit, so it lengthens the commit
(bench M3: standalone, a merged blind write costs what a read-modify-write costs, 34, 12 and 5
commits per second with 0, 1 and 3 indexes on a 600-record dictionary; in a three-member cluster
17, 6.8 and 1.1, since the build runs under the write permission;
[deviations.md](../deviations.md#m3-a-blind-write-merged-onto-an-indexed-current-standalone-and-in-a-cluster)); and if two transactions add an index of the
same name concurrently, the second commit is `PBConflictError`.

## What an index costs on every write

Nothing is free. Each index adds, per write, a new version of two trees (the key groups and the
members of one group) on top of the collection's own. protoBaseST's tree operations are 12 to 31
times slower than `proto_db`'s ([deviations.md](../deviations.md#avl-operations)), so this cost
matters here more than in Python:

| Indexes on the collection | Commits per second, one element per commit, 600-element `PBDictionary` (protoBaseST / `proto_db`) |
|---|---|
| 0 | 38 / 150 |
| 1 (a `PBEqualityIndex`) | 11.9 / 115 |
| 3 (an equality, a range and an extractor index) | 5.2 / 83 |

Measured on one busy machine, five runs each (bench M1, [deviations.md](../deviations.md#m1-commits-per-second-with-0-1-and-3-indexes)):
indicative only. Each index costs about 55 ms per commit here, 2 ms in `proto_db`.

The rule that follows is `proto_db`'s: **index what you query**, and nothing else.

## Equality and range indexes

Both kinds store the same structure: a tree of *key groups*, ordered by the format's order key
(chapter 4), each group holding its members with a count. Duplicates are kept, so a `PBList`
holding an element twice is indexed twice, and a plan answers the stored elements themselves, never
an equal representative: `1`, `1.0` and `Decimal 1.00` are one key and three values.

| Kind | Answers | Also |
|---|---|---|
| `PBEqualityIndex` | `eq:`, `in:`, `ne:`, `isNone`, `notNone` | |
| `PBRangeIndex` | the same, and `<`, `<=`, `>`, `>=`, `between:and:` and its three half-open forms | yields its elements in key order, which ordered reads and pages use (chapter 19) |

A `PBVectorIndex` written by `proto_db` stays read only: a collection holding one keeps refusing
every change, naming it, because maintaining its other indexes and not that one would write a stale
index (spec 3.3, ruling IQ5). An index of a kind protoBaseST does not know is refused the same way.

## Keys: paths, MISSING and nil

An index is defined by its *key spec*: a path (`'city'`, or `'address.zip'` to reach into a nested
record or map), the element itself, or a named extractor. A path step through an absent attribute
yields `PBMissing default`, the format's `MISSING`; an explicit `nil` stays `nil`. **Absence is not
a value**, and the two are different keys:

```smalltalk
contacts := db newTransaction getRootObject: 'contacts'.
spec := PBKeySpec path: 'address.zip'.
lesson check: 'an explicit nil stays nil' is: (spec extract: (contacts getAt: 1)) equals: nil.
lesson check: 'an absent zip is MISSING' is: (spec extract: (contacts getAt: 2)) equals: PBMissing default.
lesson check: 'no address at all is MISSING too' is: (spec extract: (contacts getAt: 3)) equals: PBMissing default.
zip := PBField path: 'address.zip'.
count := [:predicate | ((PBQuery from: contacts) where: predicate) count].
lesson check: 'eq: nil finds the explicit nil only' is: (count value: (zip eq: nil)) equals: 1.
lesson check: 'isNone finds nil and MISSING' is: (count value: zip isNone) equals: 3.
lesson check: 'notNone finds the rest' is: (count value: zip notNone) equals: 1.
lesson check: 'ne: matches present keys only' is: (count value: (zip ne: '1010')) equals: 1.
```

The four contacts are Ada (zip `'1010'`), Bob (zip `nil`), Cy (an address without a zip) and Di (no
address). `ne: '1010'` finds Bob only: a `nil` zip is present and different, while Cy's and Di's
zips are absent, and an absent key satisfies no comparison at all. That rule is `proto_db`'s
(decision D28), and it is why chapter 18 shows that `not (x = 5)` and `x ne: 5` are different
questions.

Private and reserved names are never read by a path step, and a `PBObject`'s own attributes are
the only ones a step sees.

## Extractors

A key can also be computed: a block registered under a name, in every process that uses the
index. Only the name is stored in the database, never the block.

```smalltalk
Error subclass: #NamelessPerson.
PBKeySpec registerExtractor: 'name_length' block: [:p | | n |
    n := p at: 'name'.
    n isNil ifTrue: [NamelessPerson signal: 'a person without a name'].
    n size] version: '1'.
db run: [:t |
    t setRootObject: 'people' value: ((t getRootObject: 'people')
        addIndex: (PBRangeIndex name: 'by_name_length' keySpec: (PBKeySpec extractor: 'name_length')))].
people := db newTransaction getRootObject: 'people'.
lesson check: 'names of nine characters, by the extractor index'
    is: ((PBQuery from: people) where: ((PBField extractor: 'name_length') eq: 9)) count equals: 503.
lesson check: 'a name keeps its meaning: rebinding it is refused'
    signals: PBValidationError containing: 'name_length'
    during: [PBKeySpec registerExtractor: 'name_length' block: [:p | (p at: 'name') size + 1] version: '1'].
```

**The purity contract.** An extractor must be a pure function of the element: the same element
always gives the same key, whatever the time, the process or any state outside the element. The
index stores the keys the block computed; an extractor that reads the clock, a counter or a global
gives keys that no later scan can reproduce, and the index then disagrees with its elements
silently. Nothing can check purity, so it is a documented contract, as in `proto_db`
(`keyspec.py` lines 60-83). The block must also be thread-safe: it may run on any actor, and during a
merge it runs in the publisher.

**A name keeps its meaning.** The name and the declared version are the extractor's identity
across processes, never its code. Binding a registered name to another block is refused; changing
what an extractor computes needs a new name or a new version, and a rebuilt index, exactly as
changing an index definition does.

**Another process.** A database written by a process that registered `'name_length'` can be read by
one that did not: a lookup reads only the stored trees. But any change to that collection, or a
`validate`, needs the extractor and signals `PBValidationError` naming it and telling the program to
register it. It is never rebuilt or dropped silently.

## An extractor runs inside the commit

The merge of the previous sections replays intents through the current version's mutators, so
during a merge the publisher runs the current version's extractors. That is application code inside
the commit, which the publisher otherwise never runs. The maintainer's ruling IQ1 accepts it,
exactly as `proto_db` does: **an exception raised by an extractor fails only the commit whose merge
ran it, standalone and in a group commit; in a cluster round, as in `proto_db` rc4, the whole round
fails** (every commit of the round gets that exception). protoBaseST adds no error class of its
own and does not wrap it, because `proto_db`'s `KeySpec.extract` does not either
(`keyspec.py`, `KeySpec.extract`). The caller receives a copy of the exception: the same class,
text and fields, but not the same object, where `proto_db` raises the object itself
(`transactions.py:1121`); compare class and text, never identity.

```smalltalk
nameless setRootObject: 'people' value: (nameless newDictionary setAt: 800 value: (nameless newObject: { 'city' -> 'Oslo' })).
named setRootObject: 'people' value: (named newDictionary setAt: 801 value: (named newObject: { 'name' -> 'person801'. 'city' -> 'Oslo' })).
lesson check: 'the commit whose merge ran the failing extractor fails with the block''s own error'
    signals: NamelessPerson containing: 'a person without a name' during: [nameless commit].
named commit.
people := db newTransaction getRootObject: 'people'.
lesson check: 'the other commit went through' isTrue: (people has: 801).
lesson check: 'and the failed one left nothing behind' isTrue: (people has: 800) not.
```

The nameless person passed every check in its own transaction, because its new dictionary had no
index. Only the merge onto the indexed root ran `'name_length'`, and only then did it fail. Outside a
merge the same error appears earlier and more plainly: a mutator of an indexed collection runs the
extractor in the transaction's own thread, at the call.

The check names the program's own class, `NamelessPerson` (an `Error` subclass the program
defines), not `Error`: the commit signals exactly the block's exception, neither wrapped in a
protoBaseST error nor replaced by one. Because the exception is the block's own, its class and its
text are all the caller learns. An extractor that can
fail should say in its message what it was extracting, as `'name_length'` does above ("a person
without a name").

## What to take away

- A walk costs the size of the collection; a hand-kept index costs every writer's memory, and fails
  silently.
- An index is part of the collection version: every mutator, and every merge, answers data and
  indexes computed together, and a snapshot keeps its own.
- An index costs a tree update per write: index what you query.
- `MISSING` is not `nil`; an absent key satisfies no comparison.
- An extractor is a named, pure block, registered in every process that changes the collection; if
  it fails during a merge, only that commit fails, with the block's exception (standalone and in a
  group commit; in a cluster round, as in `proto_db` rc4, the whole round fails).
