# 4. Collections and queries

<!-- example: examples/tutorial/04_collections_and_queries.st -->
Program: [examples/tutorial/04_collections_and_queries.st](../../examples/tutorial/04_collections_and_queries.st).
Previous: [3. Records](03-records.md). Next: [5. Transactions and conflicts](05-transactions-and-conflicts.md).

## The collections

| Class | What it is | Order |
|---|---|---|
| `PBList` | a sequence, zero-based positions | positional |
| `PBDictionary` | keys to values | the format's order of keys |
| `PBHashDictionary` | keys to values | hash order |
| `PBSet` | elements | the format's order |
| `PBCountedSet` | elements with a count each | the format's order |

All of them answer new versions (chapter 2). A transaction makes empty ones with `newList`,
`newDictionary`, `newHashDictionary`, `newSet` and `newCountedSet`; `PBDictionary new` and the
like make the same outside a transaction.

## Keys follow the format, not `=`

```smalltalk
prices := PBDictionary new setAt: 1 value: 'one'.
prices := prices setAt: 1.0 value: 'one, as a float'.
prices := prices setAt: (Decimal fromString: '1.00') value: 'one, as a decimal'.
lesson check: '1, 1.0 and 1.00 are one key' is: prices count equals: 1.
lesson check: 'the last write won' is: (prices getAt: 1) equals: 'one, as a decimal'.
lesson check: 'true is not 1' isTrue: (prices has: true) not.
```

Two languages read the same dictionary, so the database cannot use either language's `=`. It uses
the format's order key: numbers that are equal are one key whatever their class, and `true` is
not `1`. A key must be orderable: strings, numbers, dates, tuples. A list or a map is not a key.

A `PBTuple` is the composite key, ordered item by item:

```smalltalk
byYear := byYear setAt: (PBTuple withAll: #(1989 'The Language')) value: 'blue'.
byYear := byYear setAt: (PBTuple withAll: #(1983 'Bits of History')) value: 'green'.
byYear := byYear setAt: (PBTuple withAll: #(1983 'The Interactive Programming Environment')) value: 'orange'.
lesson check: 'iteration is in key order' is: byYear values asArray equals: #('green' 'orange' 'blue').
```

## Sets and counted sets

```smalltalk
lesson check: 'union' is: (a union: b) elements equals: #('gemstone' 'pharo' 'protost').
lesson check: 'intersection' is: (a intersection: b) elements equals: #('gemstone').
lesson check: 'difference' is: (a difference: b) elements equals: #('pharo').
counts := ((PBCountedSet new add: 'loan') add: 'loan') add: 'return'.
lesson check: 'a counted set counts occurrences' is: (counts countOf: 'loan') equals: 2.
```

A `PBCountedSet` is the collection for counters that many writers increment: its concurrent
increments merge (chapter 6).

## Queries

> **Indexed queries (0.3.0).** Maintained indexes, a query front end (`PBQuery`,
> `PBField`) and a cost-based planner are in [chapters 17](17-indexes.md) and
> [18](18-queries-and-plans.md), and pagers in [chapter 19](19-ordered-reads-and-pages.md). This
> section shows the two ways a question is answered without them, which chapter 17 starts from.

Without an index, a question is answered in one of two ways.

A walk over a collection, which visits every element:

```smalltalk
old := OrderedCollection new.
books keysAndValuesDo: [:isbn :book | (book at: 'year') < 1985 ifTrue: [old add: isbn]].
```

Or a lookup in a second collection that the program keeps up to date itself, **in the same
transaction** as the data, so both change or neither does. (`run:` is `newTransactionDo:` that
retries when another commit got there first; chapter 5 explains it.)

```smalltalk
addBook := [:isbn :title :year |
    db run: [:tr |
        | catalogue index |
        catalogue := tr getRootObject: 'books'.
        index := tr getRootObject: 'byYear'.
        tr setRootObject: 'books' value: (catalogue setAt: isbn
            value: (tr newObject: { 'title' -> title. 'year' -> year })).
        tr setRootObject: 'byYear' value: (index setAt: year
            value: ((index getAt: year default: PBSet new) add: isbn))]].
```

Because a `PBDictionary` iterates in key order, a dictionary keyed by year (or by a tuple) is
also the way to scan a range: walk it and stop at the first key past the range.

`tr newObject:` makes a plain `PBObject` (stored under `proto_db`'s own type name for `DBObject`)
for a record that needs no class of its own.

## `proto_db`'s indexes

`proto_db` has equality, range and vector indexes that it maintains itself. protoBaseST reads them,
and maintains an equality or range index in every change, in the same step, as `proto_db` does
(0.3.0): the new version's indexes agree with its elements.

```smalltalk
people := (space openDatabase: 'db') newTransaction getRootObject: 'people'.
lesson check: 'the indexes are read' is: people indexNames equals: #('by_age' 'by_city').
lesson check: 'an index keeps its definition' is: (people getIndex: 'by_age') name equals: 'by_age'.
lesson check: 'the indexed collection is read as usual' is: people count equals: people keys size.
changed := people setAt: 'zed' value: (PBObject withAll: { 'name' -> 'Zed'. 'age' -> 40 }).
lesson check: 'a change answers a new version with one more element' is: changed count equals: people count + 1.
lesson check: 'whose indexes were maintained in the same step'
    is: ([changed validate. 'clean'] on: PBCorruptionError do: [:e | e messageText]) equals: 'clean'.
```

So a directory shared with Python can use indexes from both languages. Since 0.4.0 that includes
vector indexes ([chapter 20](20-vector-search.md)); a collection holding an index of a kind
protoBaseST does not know still refuses every change, naming it ([chapter 12](12-refusals.md)). [Chapter 17](17-indexes.md) explains why a hand-kept index fails
and what replaces it; [chapter 18](18-queries-and-plans.md) queries the indexes.

## What to take away

- Keys compare by the format's rule; tuples are composite keys.
- Queries are walks or hand-kept lookup collections, updated in the same transaction.
- `proto_db`'s indexes are read, not queried or maintained.
