# 19. Ordered reads and pages

<!-- example: examples/queries/pending/19_ordered_reads_and_pages.st.pending -->
Program, pending: [examples/queries/pending/19_ordered_reads_and_pages.st.pending](../../examples/queries/pending/19_ordered_reads_and_pages.st.pending).
Previous: [18. Queries and the planner](18-queries-and-plans.md). Back to the [index](README.md).

> **Draft: the API in this chapter is not implemented.** It is planned for protoBaseST 0.3.0 by
> the approved [indexed-queries spec](../superpowers/specs/2026-11-18-indexed-queries-design.md)
> (sections 5.5 and 5.7). Every block below comes from a program written against the spec's API
> that **has never run**. Rank access and pagers are `proto_db`'s, read from its code and cited.
> Figures marked `[measured in T<n>: ...]` do not exist yet.

A report shows people by age, fifty to a page, and the user asks for page 50. This chapter is about
the two questions behind that request: what page 50 costs, and whether page 50 is still the page
that follows page 49 when someone commits in between. The data is chapter 18's 600 people, with a
range index `by_age`.

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

## `by_rank`: a window that is sought, not skipped

Both windows above show `by_rank`: true in their `Limit` node. It means the `Limit` does not run its
source and throw rows away until it reaches the window: it asks the source for rows `offset` to
`offset + limit` directly. The index trees carry, in every node, the number of occurrences below it
(a *weight*), so occurrence number *r* is found by one descent, as a position is found in a
`PBList` (`proto_db/indexing/keyed.py`, "Rank access"). A window then costs O(log n + its size)
instead of O(offset + its size).

Rank access is offered by an index lookup, range or ordered scan; by a scan of a `PBList` or a
`PBDictionary`; by a `Limit` over one of those; by a filter of a single term over an ordered scan of
the index that answers that term; and by a sort on one key over an index plan of that same key, as
in `narrow` above, because the range is already in key order (`proto_db/query/plans.py`, `window`
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
`page:` seeks the page; otherwise the pager runs the plan once, keeps the result, and slices it, so
a block key costs one full run, not one per page. `byRank` says which, and `explain` on a pager
shows its plan. Pages are numbered from 0, as `proto_db`'s and as `PBList` positions.

How much the seek saves is a measurement: [measured in T9, bench Q5: the time of page k for every
k from the first to the last, by rank and by skipping, on an ordered index scan of 10^4 and 10^5
elements; and `count` by rank against counting the rows, RUNS=5 interleaved].

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
every committed version stays readable (chapter 7).

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
walking the rows. A `Count` node in a plan shows `by_rank`: true when it does so.

## What to take away

- An order on an indexed key streams the index; a selective condition is found by its index and
  sorted.
- `by_rank` means a window is sought in O(log n + its size), not skipped.
- Skipping k pages costs k pages; a pager seeks page k when its plan has rank access, and
  materialises once when it does not.
- A pager reads one snapshot: every row once, whatever commits meanwhile. A new query per page
  does not.
