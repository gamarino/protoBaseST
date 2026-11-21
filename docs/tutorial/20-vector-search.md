# 20. Vector search

<!-- example: examples/queries/pending/20_vector_search.st.pending -->
Program, pending: [examples/queries/pending/20_vector_search.st.pending](../../examples/queries/pending/20_vector_search.st.pending).
Previous: [19. Ordered reads and pages](19-ordered-reads-and-pages.md). Back to the [index](README.md).

> **Draft: the API in this chapter is not implemented.** It is planned for protoBaseST 0.4.0 by
> [Addendum V](../superpowers/specs/2026-11-19-vectors-addendum.md) to the indexed-queries spec
> (sections 2.3 to 2.9). Every block below comes from a program written against the addendum's
> API that **has never run**; task V9 makes it run and removes this banner. The vector feature
> is `proto_db`'s, read from its code at `v2.0.0rc4` and cited. Figures marked
> `[measured in V<n>: ...]` do not exist yet.

A vector index finds the elements whose embedding is nearest to a query vector. It is the third
index kind, after chapter 17's equality and range indexes, and it works like them: it belongs to a
collection version, every mutator keeps it current, and the planner of chapter 18 uses it, so a
nearest-neighbour search can be combined with ordinary conditions. This chapter ports `proto_db`'s
tutorial "Vector search" (`docs/source/tutorials/vector-search.rst`), with two sections of its own
on why two implementations give the same neighbours to the last bit. Unlike `proto_db`'s, it needs
no numpy: everything here is protoST.

What protoBaseST promises is `proto_db`'s answer, `proto_db`'s plan and `proto_db`'s bytes for the
same operations. It does not promise `proto_db`'s speed: the vector arithmetic here is interpreted
Smalltalk, and what it costs is measured, not assumed.

## Documents with embeddings

```smalltalk
topics := #('sports' 'music' 'science').
seed := 7.
next := [seed := seed * 16807 \\ 2147483647. seed / 2147483647.0 * 2.0 - 1.0].
docs := (0 to: 599) collect: [:i | { i. topics at: i \\ 3 + 1. (1 to: 8) collect: [:j | next value] }].
db newTransactionDo: [:t |
    | coll |
    coll := t newList addIndex: (PBVectorIndex name: 'by_vec' path: 'vec' dim: 8 metric: 'cosine').
    docs do: [:d |
        coll := coll appendLast: (t newObject: { 'i' -> (d at: 1). 'topic' -> (d at: 2). 'vec' -> (d at: 3) })].
    coll := coll appendLast: (t newObject: { 'i' -> 600. 'topic' -> 'music'. 'vec' -> #(1.0 2.0) }).
    t setRootObject: 'docs' value: coll].
```

The embeddings are numbers from a seeded generator written in the program, so every run builds the
same data. In an application they come from an embedding model: protoBaseST, like `proto_db`,
stores and indexes the vectors it is given and never computes them.

A vector index fixes three things. The dimension, `dim`. The metric: `'cosine'` (the default),
`'l2'` (Euclidean distance) or `'ip'` (the inner product). And the backend: `'exact'` (the
default) scores every vector; `'ivf_flat'` clusters them and searches a few clusters (below);
`'hnsw'` is maintained but not searched here (below). The constructor in full is
`name: aString keySpec: aKeySpec dim: anInteger metric: aString backend: aString params: aDictionary`;
`name:path:dim:metric:` is the convenience used above.

```smalltalk
lesson check: '601 documents, one index' is: { docs size. docs indexNames asArray } equals: #(601 #('by_vec')).
lesson check: 'the short vector is kept aside, not indexed'
    is: (((docs getIndex: 'by_vec') explain) at: 'invalid') equals: 1.
```

Document 600 has a vector of two numbers where the index wants eight. It is not refused: it is in
the collection, and the index keeps it aside, in a group of invalid elements, so that `validate`
can still account for every element. A search never returns it. The same holds for a document
without a `'vec'` at all, or with a component that is not a finite number
(`proto_db/indexing/vector_backends.py:100-122`).

## Nearest neighbours

The obvious way to find the five documents nearest to document 42 is the definition itself: score
every document against it and sort.

```smalltalk
dot := [:a :b | | s | s := 0.0. 1 to: a size do: [:j | s := s + ((a at: j) * (b at: j))]. s].
norm := [:a | (dot value: a value: a) sqrt].
cosine := [:a :b | (dot value: a value: b) / ((norm value: a) * (norm value: b))].
target := ((all detect: [:d | (d at: 'i') = 42]) at: 'vec') asArray.
ranked := ((all select: [:d | (d at: 'vec') size = 8])
    asSortedCollection: [:a :b | (cosine value: target value: (a at: 'vec')) >= (cosine value: target value: (b at: 'vec'))]) asArray.
```

It is correct, and it is what the `'exact'` backend does: it reads every vector of the index and
ranks them. What the index adds is that the work happens inside a plan, next to the conditions of
the query, and that the score is computed the way `proto_db` computes it, to the last bit (two
sections below). The same question to the index:

```smalltalk
nearest := (PBQuery from: docs) where: ((PBField path: 'vec') near: target k: 5).
lesson check: 'the index answers it' is: (planOf value: nearest) equals: 'VectorSearch <- VectorExact'.
lesson check: 'the same five, nearest first'
    is: (nearest asArray collect: [:d | d at: 'i']) equals: ((ranked first: 5) collect: [:d | d at: 'i']).
lesson check: 'document 42 is its own nearest neighbour' is: (nearest first at: 'i') equals: 42.
```

`near: aVector k: 5` builds the term `'vec' near[] ...`, `proto_db`'s operator, whose value is a
`PBNearQuery` (the vector, `k`, a threshold, a metric). The plan is a `VectorSearch` over the
index's own plan, `VectorExact`. Results come nearest first; two documents at exactly the same
score come in the order of their member keys, which for records is their oids
(`vector_backends.py:147-163`), so the order is total and the same in both implementations on
the same database.

What an exact search costs here, per query and for the first query after opening a database:
[measured in V6: bench VB1, exact kNN latency and the first query, 10^3 and 10^4 documents of 8 and 32 dimensions, both implementations].

## Combining `near:` with conditions

"The three nearest music documents" looks like "the three nearest documents, then keep the music
ones". It is not:

```smalltalk
firstThenFilter := (nearest asArray first: 3) select: [:d | (d at: 'topic') = 'music'].
lesson check: 'the k nearest, then filtered: fewer than three' isTrue: firstThenFilter size < 3.
```

Document 42 is a sports document, and it is its own nearest neighbour, so filtering the three
nearest can leave at most two. In general the obvious way returns anything from zero to k rows,
depending on how the topics happen to fall among the neighbours. The question asked for three.

`proto_db` hands the condition to the index, which finds the k nearest **among** the elements that
satisfy it (`VectorIndex.filtered_plan`, `proto_db/indexing/vector.py:289-319`):

```smalltalk
music := (PBQuery from: docs) where: (((PBField path: 'vec') near: target k: 3) & ((PBField path: 'topic') eq: 'music')).
musicMatches := (ranked select: [:d | (d at: 'topic') = 'music']) first: 3.
lesson check: 'three, the nearest among the music documents'
    is: (music asArray collect: [:d | d at: 'i']) equals: (musicMatches collect: [:d | d at: 'i']).
lesson check: 'the condition is inside the search' is: (planOf value: music) equals: 'VectorSearch <- VectorExact'.
```

The plan has no `Filter` above the search: the condition is the `'where'` field of the
`VectorSearch` node, evaluated on each candidate before it competes for a place among the k.
A block works too, when it is given to `where:` next to the `near:` term:

```smalltalk
lesson check: 'a block from where: joins it too'
    is: ((((PBQuery from: docs) where: ((PBField path: 'vec') near: target k: 3)) where: [:d | (d at: 'topic') = 'music']) asArray
        collect: [:d | d at: 'i'])
    equals: (musicMatches collect: [:d | d at: 'i']).
```

This is `proto_db`'s mixing rule (`proto_db/query/linq.py:53-58`): when the conditions of the
leading `where:` steps hold exactly one bare `near[]` term with a k, a block among those steps joins
the vector search's condition instead of filtering its result. Anywhere else (after a `take:`, for
instance) a block filters what it receives, as in chapter 18.

What the condition inside the search costs against the obvious post-filter, which is cheaper and
returns fewer rows: [measured in V7: bench VB4, filtered kNN against the post-filter at selectivity 1, 10 and 50 percent, with the rows each returns].

## Thresholds, and both

```smalltalk
close := ((PBQuery from: docs) where: ((PBField path: 'vec') near: target threshold: 0.6)) asArray.
closeRanked := ranked select: [:d | (cosine value: target value: (d at: 'vec')) >= 0.6].
lesson check: 'every document at least 0.6 similar, and only those'
    is: (close collect: [:d | d at: 'i']) asSet equals: (closeRanked collect: [:d | d at: 'i']) asSet.
both := ((PBQuery from: docs) where: ((PBField path: 'vec') near: target k: 3 threshold: 0.6)) asArray.
lesson check: 'k and a threshold: the k nearest of those'
    is: (both collect: [:d | d at: 'i']) equals: ((closeRanked first: (3 min: closeRanked size)) collect: [:d | d at: 'i']).
```

A threshold means what the metric measures (`vector.py:24-30`): for `'cosine'` a similarity of at
least t, for `'l2'` a distance of at most t, for `'ip'` a score of at least t. A threshold and a k
together are the k nearest among those within the threshold. Give at least one of the two.

## Why two implementations agree to the last bit

Ranking needs a score per document, and a score is a sum of products. The obvious way to add them
is a loop of `+`, the way the dot-product block above does. It works for most vectors, and it is wrong
for some:

```smalltalk
ipQuery := #(1.0 1.0 1.0).
```

```smalltalk
naive := (ipAll asSortedCollection: [:a :b | (dot value: ipQuery value: (a at: 'vec')) >= (dot value: ipQuery value: (b at: 'vec'))]) asArray.
lesson check: 'the plain loop ranks small first: it scored big 0.0'
    is: { (naive first at: 'name'). dot value: ipQuery value: #(1.0e16 1.0 -1.0e16) } equals: #('small' 0.0).
byIndex := ((PBQuery from: ipDocs) where: ((PBField path: 'vec') near: ipQuery k: 2)) asArray.
lesson check: 'the index ranks big first, as proto_db does' is: (byIndex collect: [:d | d at: 'name']) equals: #('big' 'small').
```

The inner product of (1, 1, 1) with the document "big", (1e16, 1, -1e16), is exactly 1; with
"small", (0.5, 0.25, 0), it is 0.75. The loop computes `1e16 + 1` first, which rounds back to
`1e16` (a float has 53 bits, and 1e16 + 1 needs 54), then subtracts 1e16 and answers 0. It ranks
"small" first. Floating-point addition is not associative: the order of the terms changes the
answer, and so does any other loop, any other order, or numpy's blocked sums.

Why that matters beyond one bad ranking: two implementations that add in different orders disagree
in the last bit on ordinary data too, and a last bit decides a near tie. On a near tie one
implementation returns one neighbour and the other another; an IVF index files a member under
another list, and `proto_db`'s `validate` then reports the index as corrupt
(`vector.py:372-374`).

`proto_db` defines every score with `math.fsum`, which is correctly rounded: it answers the exact
sum rounded once, whatever the order of the terms (`vector_backends.py:12-13`, `125-137`;
`docs/source/format-spec.rst:1432-1437`). protoBaseST ports CPython's `math.fsum` line for line
(Shewchuk's algorithm) on IEEE doubles, so both implementations compute the same score for the
same vectors, bit for bit, and rank and file them alike. The cost of the correctly rounded sum
against the plain loop: on 10^4 vectors of dim 8, 32 and 128, the interpreted fsum costs 4.9, 8.8 and 10.0 times the plain loop, and most of a score (68% to 87% of an inner-product score) is the sum, not the products (bench VB0, [Performance, Vectors](../deviations.md#vectors)). Correctness is what is paid for. protoST 0.15.0 adds the sum as primitives (Float fsum:, fsumOfProducts:with: and fsumOfSquaredDifferences:with:, the same algorithm in C++), and protoBaseST uses them when it finds them: the same answers, bit for bit, with the sum 9 to 76 times faster and a score 4 to 56 times faster than on 0.14.1 (bench VB0 on 0.15.0, same section). On 0.14.1 the Smalltalk port runs alone.

## Why `x ** 2` is not `x * x`

IVF training (next section) runs k-means, whose Python source squares each difference with
`(a - b) ** 2` (`vector_backends.py:548`). The obvious port is a multiplication, `d * d`, on the
argument that both are correctly rounded. The first draft of this phase's design said exactly
that. It is wrong:

```smalltalk
x := 130492547 asFloat.
lesson check: 'raisedTo: 2 and * disagree on a half-way square' isTrue: ((x raisedTo: 2) = (x * x)) not.
lesson check: 'raisedTo: 2 answers what CPython x ** 2 answers' is: (x raisedTo: 2) printString equals: '1.702830482254721e16'.
```

For a float, CPython's `**` calls the C library's pow function, and glibc's pow is not correctly
rounded.
The square of 130492547 needs 54 bits, so it lies exactly half-way between two floats; the product
rounds it to one, pow to the other. Measured while designing this phase (CPython 3.14.0, glibc
2.43): of 117,197 odd integers with such half-way squares, `x ** 2` differed from `x * x` on 55,729;
of a million uniform doubles in [-1000, 1000], on 845 (Addendum V, section 2.5). A port that
multiplies would pick another nearest centroid on a near tie, and the stored centroids would not be
`proto_db`'s.

So protoBaseST squares with protoST's `raisedTo: 2`, which calls the same pow function, and its tests pin
half-way cases computed by CPython, so that a change in either fails loudly instead of moving a
centroid. It also means "the same bytes" has a precise scope for IVF training: the same history,
`proto_db` training without numpy (numpy has its own arithmetic), and the same C library on the same
host. Scores never use pow: they multiply, as `proto_db` does.

## IVF-Flat

An exact search reads every vector. `'ivf_flat'` clusters the vectors (k-means, stored in the index
as centroids) into `'nlist'` lists and searches only the `'nprobe'` lists nearest to the query. It
trades recall for reading less; with `'nprobe'` equal to `'nlist'` it reads everything and is exact.

```smalltalk
recall := [:nprobe | | hits coll |
    db newTransactionDo: [:t |
        | ivf |
        ivf := t newList addIndex: (PBVectorIndex name: 'ivf' keySpec: (PBKeySpec path: 'vec') dim: 8 metric: 'cosine'
            backend: 'ivf_flat' params: (Dictionary new at: 'nlist' put: 16; at: 'nprobe' put: nprobe; yourself)).
        docs do: [:d | ivf := ivf appendLast: d].
        t setRootObject: 'ivf' value: ivf].
```

```smalltalk
#(1 4) do: [:nprobe | lesson say: 'nlist=16 nprobe=' , nprobe printString , ': recall@10 = ' , (recall value: nprobe) printString].
lesson check: 'nprobe = nlist is exact' is: (recall value: 16) equals: 1.0.
```

Recall at 1 and 4 probes of 16 lists, on these random vectors (which have no cluster structure for
the index to exploit): [measured in V6: recall at 10 for nprobe 1 and 4 of nlist 16, the chapter's block run several times in both implementations]. `proto_db`'s own tutorial
says its partial-probe recall varied between runs on identical data, while its code records the
cause as fixed (R128, below); this chapter will state what the repeated runs of V6 observe, in
both implementations, and nothing it has not observed.

Training is reproducible from the data and the seed. The obvious way to pick the initial centroids
is to sample the members in stored order, and that is what `proto_db` first did; it failed because
stored order follows the atoms' oids, which differ every run, so the same documents trained
different centroids. `proto_db`'s fix (R128) sorts the training vectors by their IEEE bytes first
(`vector_backends.py:650-655`), and then samples with Python's `random.Random(seed)`. protoBaseST
ports both: the byte order, and CPython's Mersenne Twister seeding and `random.sample`, since protoST's own
`Random` is a different generator. The IVF build and query costs, and recall against exact:
[measured in V6: bench VB2, IVF bulk build, query time by nprobe 1, 4 and nlist, recall at k against exact, 10^4 documents of 32 dimensions].

An index trained by either implementation is valid for the other: the format leaves training to
the writer, and list numbers, probes and rankings are computed from the stored centroids, whoever
trained them. What differs after a retrain of the same history is only this: protoBaseST's centroids
equal those of `proto_db` without numpy on the same C library, and may differ in the last bits from
those of `proto_db` with numpy.

## Limits and choices

- **`'exact'` first.** It needs no training, is never approximate, and is the default. Use it until
  its scan time exceeds your budget; then measure `'ivf_flat'`'s recall on your own data, as the
  block above does.
- **`'hnsw'` is maintained, not searched.** `proto_db` builds an hnsw graph with the native hnswlib
  library in each process; the graph is not stored and not deterministic even in `proto_db`. A
  collection holding an hnsw index is written, merged and validated by protoBaseST, and a search on
  it is refused with `PBNotSupportedError`, as `proto_db` refuses it when hnswlib is not installed
  (ruling VQ1):

```smalltalk
lesson check: 'an hnsw-indexed collection is written and validates' is: hnsw validate size equals: 1.
lesson check: 'its plan is built' is: (planOf value: ((PBQuery from: hnsw) where: ((PBField path: 'vec') near: target k: 1))) equals: 'VectorSearch <- VectorHnsw'.
lesson check: 'its search is refused' signals: PBNotSupportedError containing: 'hnsw'
    during: [((PBQuery from: hnsw) where: ((PBField path: 'vec') near: target k: 1)) asArray].
```

- **Every write pays for the index.** A vector index is part of the collection version, so every
  commit that adds a document adds it to the index, and a commit that crosses a retrain threshold
  of an IVF index runs k-means inside that commit, in the merge of a blind write too:
  appending to a list of 600 vectors commits 35.9 times per second with no index, 16.2 with an
  exact index and 5.0 with an IVF index retraining at every 3 % of growth (5000 vectors: 32.1,
  15.1 and 5.1; bench VB3, protoST 0.16.0, where `proto_db` commits 156, 133 and 52 times, 142,
  119 and 70 with numpy). In a cluster, that k-means runs in the round's build, under the
  cluster-wide write permission: 120 blind writes onto a vector-indexed dictionary commit 8.1
  times per second with an exact index and 3.7 with an IVF index in a three-member cluster (16.1
  and 4.7 standalone; bench VB5). A retrain takes about 1.6 to 1.9 s for 630 to 700 members on
  protoST 0.16.0, longer than the 667 ms a write permission lasts under the default lease, so an
  IVF index retrained in a cluster needs a longer `leaseDuration`, more than four times the
  measured retrain for its size; the cost per member grows, 2.5 ms at 631 to 3.7 ms at 5150, so
  count up to about 4 ms per member: about 11 s for 700 members, 80 s for 5000 (VB5 used 90 s). With the
  default lease such a commit never succeeds. The longer lease has a cost: if the member holding
  the permission dies, nobody writes until its lease and drift margin have passed
  ([deviations.md](../deviations.md#vectors)).
- **A dedicated vector database** is the better tool when vector search is the whole workload: such
  systems offer more index kinds, quantisation and GPU execution (general knowledge, not measured
  here). The point of a vector index in protoBaseST is the one `proto_db` makes: the vectors live in
  the same versions and transactions as the records they describe, so a document and its embedding
  commit together, and a past version answers with its past embeddings.

Next: back to the [index](README.md). The concepts behind this chapter (the index's store, its lists
and its invalid group, the planner's rules for `near[]`, the cost model) are in
[queries.md, Vector search](../queries.md#vector-search).
