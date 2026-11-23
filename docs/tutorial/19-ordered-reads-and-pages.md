# 19. Ordered reads and pages

<!-- example: examples/tutorial/19_ordered_reads_and_pages.st -->
Program: [examples/tutorial/19_ordered_reads_and_pages.st](../../examples/tutorial/19_ordered_reads_and_pages.st).
Previous: [18. Queries and the planner](18-queries-and-plans.md). Back to the [index](README.md).

> **protoBaseST 0.3.0** (the
> [indexed-queries spec](../superpowers/specs/2026-11-18-indexed-queries-design.md), sections 5.5
> and 5.7). Every block below comes from the chapter's program, which runs as a test and checks
> what it shows. Rank access and pagers are `proto_db`'s (`proto_db/indexing/keyed.py`, "Rank
> access"; `proto_db/query/pager.py`, `Pager`), read from its code and cited; the
> [reference](../reference.md#pagers) lists every message.

A report shows people by age, fifty to a page, and the user asks for page 50. This chapter is about
the two questions behind that request: what page 50 costs, and whether page 50 is still the page
that follows page 49 when someone commits in between. The data is chapter 18's 600 people, with a
range index `'by_age'`.

## An order on an indexed key

```smalltalk
byAge := (PBQuery from: people) orderBy: 'age'.
youngest := byAge take: 5.
lesson check: 'the index yields the order' is: (planOf value: youngest) equals: 'Limit <- IndexOrderedScan'.
lesson check: 'the window is sought by rank' is: (youngest explain at: 'by_rank') equals: true.
lesson check: 'the five youngest' is: (youngest asArray collect: [:p | p at: 'age']) equals: #(18 18 18 18 18).
oldest := ((PBQuery from: people) orderBy: 'age' descending: true) take: 3.
lesson check: 'descending' is: (oldest asArray collect: [:p | p at: 'age']) equals: #(77 77 77).
```

A range index keeps its keys in order, so it can produce every element in key order without
sorting: an `IndexOrderedScan`. With no condition, that is far cheaper than sorting all 600 people
(the model charges a sort `n log2 n`), and the planner takes it.

The order is total, as `proto_db`'s: `MISSING` first, then `nil`, then the format's order of every
other key; keys that cannot be ordered (lists, maps, NaN) come last, equal to each other. Equal keys
keep a stable order. Descending reverses the keys and keeps each key's elements in order.

With a selective condition the decision flips:

```smalltalk
narrow := (((PBQuery from: people) where: ((PBField path: 'age') between: 30 and: 35)) orderBy: 'age') take: 5.
lesson check: 'a selective predicate: the index finds, a sort orders' is: (planOf value: narrow) equals: 'Limit <- Sort <- IndexRange'.
lesson check: 'still sought by rank: the range is already in key order' is: (narrow explain at: 'by_rank') equals: true.
```

For an order on one key, the planner compares two candidates: plan the condition (here the range,
60 people) and sort what it finds; or stream the whole ordered index and filter every element. The
first sorts 60 rows; the second reads 600. ([The guide](../queries.md#plan-3-an-ordered-window)
works out both costs.) With several order keys a `Sort` is always used.

## `'by_rank'`: a window that is sought, not skipped

Both windows above show `'by_rank'`: true in their `Limit` node. It means the `Limit` does not run its
source and throw rows away until it reaches the window: it asks the source for rows `offset` to
`offset + limit` directly. The index trees carry, in every node, the number of occurrences below it
(a *weight*), so occurrence number *r* is found by one descent, as a position is found in a
`PBList` (`proto_db/indexing/keyed.py`, "Rank access"). A window then costs O(log n + its size)
instead of O(offset + its size).

Rank access is offered by an index lookup, range or ordered scan; by a scan of a `PBList` or a
`PBDictionary`; by a `Limit` over one of those; by a filter of a single term over an ordered scan of
the index that answers that term; and by a sort on one key over an index plan of that same key, as
in the narrow query above, because the range is already in key order (`proto_db/query/plans.py`, the window method
of each node). Anything else, a block key, two order keys, a residual filter of two terms, has no
rank, and its rows must be produced to be counted.

## Page k: the obvious way, and a pager

The obvious way to show page k is to run the query and skip k pages:

```smalltalk
pageBySkipping := [:k | | rows |
    rows := OrderedCollection new.
    byAge do: [:p | rows add: p].
    (rows copyFrom: k * 50 + 1 to: k * 50 + 50) asArray].
pager := byAge pagerSize: 50.
lesson check: 'the pager seeks by rank' isTrue: pager byRank.
lesson check: 'twelve pages of fifty' is: { pager rows. pager pages } equals: #(600 12).
lesson check: 'page 3 is the same rows either way'
    is: ((pager page: 3) collect: [:p | p at: 'name']) equals: ((pageBySkipping value: 3) collect: [:p | p at: 'name']).
lesson check: 'a block key has no rank: the result is materialised once'
    is: (((PBQuery from: people) orderBy: [:p | (p at: 'name') size]) pagerSize: 50) byRank equals: false.
```

It answers the right rows, and it fails in two ways. Its cost grows with the page number: page 50
produces 2550 rows to show 50, and the user who pages to the end has paid for the whole result once
per page. And each call runs the query again, on whatever is committed by then (next section).

A `PBPager` holds one plan, built once, and serves page k of it. When the plan offers rank access,
`page:` seeks the page; otherwise the pager runs the plan once, when a page, `rows` or `pages`
first needs it, keeps the result, and slices it, so a block key costs one full run, not one per page. `byRank`
says which, and `explain` on a pager shows `'page_size'` and `'by_rank'` above its plan's explain.
Pages are numbered from 0, as `proto_db`'s and as `PBList` positions; past the last page, `page:`
answers a new empty `Array`. A pager is made from a query (`pagerSize:`), or by
`PBPager on: aSource pageSize: n` from a query, a plan or a collection.

What page k costs, for a page of size s over n rows:

| Way | Page k | Every page, k = 0 to n/s − 1 |
|---|---|---|
| Run the query and skip k pages | O(k s + s) when it stops after the page (the block above reads all n rows every time): the rows before the page are produced and dropped | O(n² / s) |
| A pager by rank | O(log n + s): one descent of the weighted index, then the page | O(n + (n / s) log n) |
| A pager over a plan without rank | the whole plan once, then O(s) per page | one run of the plan, then O(n) |

How much the seek saves is a measurement. Bench Q5 reads every page of 50 of an ordered query over
2000 and 10^4 records, three ways, five runs interleaved with `proto_db`'s (the minimum, in the
final comparison; the full table is in [deviations.md](../deviations.md#the-final-comparison-plan-task-10)):

| Every page of 50, ordered by an indexed key | 2000 records (40 pages) | 10^4 records (200 pages) |
|---|---|---|
| A pager by rank (`IndexOrderedScan`) | 76 ms, 1.9 ms per page | 321 ms, 1.6 ms per page |
| A pager over a `Sort` without rank: materialised once, then sliced | 145 ms | 867 ms |
| Skipping to each page | 1402 ms, 35 ms per page on average | 29488 ms, 147 ms per page on average |
| `proto_db`, the same three | 5.2, 5.2 and 53 ms | 24, 31 and 1417 ms |

A page by rank costs the same at both sizes; a skipped page costs more the further it is, so the
user who reads to the end pays 18 times the pager's price at 2000 records and 92 times at 10^4,
and the gap keeps growing with the collection (`proto_db`: 10 and 58 times). Materialising once is
not free, it pays the sort, but it pays it once: 1.9 and 2.7 times the pager by rank. protoBaseST is 13
to 28 times slower than `proto_db` in absolute terms, the gap of the whole port (chapter 18); the
shape of the costs is the same in both.

## Stable pages: one snapshot

```smalltalk
tr := db newTransaction.
pager := ((PBQuery from: (tr getRootObject: 'people')) orderBy: 'age') pagerSize: 50.
first := pager page: 0.
db run: [:t | t setRootObject: 'people' value: ((t getRootObject: 'people')
    setAt: 1000 value: (t newObject: { 'name' -> 'newcomer'. 'city' -> 'Oslo'. 'age' -> 18 }))].
seen := OrderedCollection new.
seen addAll: first.
1 to: pager pages - 1 do: [:k | seen addAll: (pager page: k)].
names := seen collect: [:p | p at: 'name'].
lesson check: 'every row once, none twice' is: { names size. names asSet size } equals: #(600 600).
lesson check: 'the commit made meanwhile is not in it' isTrue: (names includes: 'newcomer') not.
```

The pager was built on a transaction's snapshot. Between page 0 and page 1 another transaction
committed a newcomer aged 18, who sorts into page 0. The pager does not see it: its plan reads the
versions of its snapshot, and a version never changes (chapter 2). So a pager never shows a row
twice and never skips one, whatever is committed meanwhile, and it needs no lock and no pinning:
every committed version stays readable (chapter 7). The same holds under real concurrency:
`tests/unit/qry_pager_stability.st` runs three writer actors that insert before, inside and after
the pages and delete rows, while three reader actors page through snapshots, with one commit in
every round of page reads, so that a commit lands between any page and the next but one; and
`tests/unit/qry_pager_racing.st` makes the writers race, their commits grouped, conflicting and
retried, while pagers are open. In both, every reader sees exactly its snapshot's rows, by rank
and materialised.

The obvious alternative, a new query per page with an offset, reads a new snapshot each time:

```smalltalk
fresh := ((PBQuery from: (db newTransaction getRootObject: 'people')) orderBy: 'age') pagerSize: 50.
lesson check: 'the new snapshot has 601 rows' is: fresh rows equals: 601.
lesson check: 'its page 1 starts with the last row of the old page 0: shown twice'
    is: (((fresh page: 1) at: 1) at: 'name') equals: ((first at: 50) at: 'name').
```

The newcomer pushed every later row one place down, so the last row of the old page 0 is the first
row of the new page 1: the user sees it twice. A deletion would have made a row vanish between two
pages instead. Neither is an error anyone reports; both are wrong reports.

A pager lives in one process. `proto_db` also has portable pager tokens, which another process can
resume; they are deferred in protoBaseST, because the token's plan digest is computed over Python's
`repr` of the plan and cannot be reproduced exactly in protoST (spec 3.2, ruling IQ3).

## Counting

```smalltalk
lesson check: 'count of a range, by rank'
    is: ((PBQuery from: people) where: ((PBField path: 'age') between: 30 and: 35)) count equals: 60.
```

`count` uses the same weights: when the plan knows its exact number of rows without producing them
(an index plan does, from the weights of the groups it covers), the count is read, not computed by
walking the rows. A `Count` node in a plan shows `'by_rank'`: true when it does so. In bench Q5 a
count by rank took 1.6 ms at 2000 records and 2.2 ms at 10^4, against 104 and 439 ms for counting
a filtered scan of the same records (`proto_db`: 0.10 ms against 5.8 and 29 ms).

## What to take away

- An order on an indexed key streams the index; a selective condition is found by its index and
  sorted.
- `'by_rank'` means a window is sought in O(log n + its size), not skipped.
- Skipping k pages costs k pages; a pager seeks page k when its plan has rank access, and
  materialises once when it does not.
- A pager reads one snapshot: every row once, whatever commits meanwhile. A new query per page
  does not.
