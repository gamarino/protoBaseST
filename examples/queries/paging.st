"EXPECT: paging ok (11 checks)"
"Pagers, by rank and materialised. Quoted by docs/queries.md, 'Ordered reads, windows and pages'.

 A PBPager holds one plan and serves page k of it, k from 0 (proto_db's query/pager.py, Pager;
 design spec 5.7). Over a range index on the age of chapter 18's 600 people (ten of each age, 18 to
 77), an order on the age is an IndexOrderedScan, which offers rank access, so each page is sought
 in O(log n + page size); an order on two keys is a Sort, which has none, so the pager runs the
 plan once and slices the result. Either way the pages, concatenated, are the query's rows. A
 pager takes a query, a plan or a collection.

 Run it: STPATH=<repository>/src protost paging.st"
Import from: 'protobase'.
Import from: '../tutorial/_lesson'.

| lesson cities people q age pager byAgeThenName seventies all |
lesson := Lesson named: 'paging'.
cities := #('Lima' 'Oslo' 'Paris' 'Rome').
people := PBDictionary new.
0 to: 599 do: [:i |
    people := people setAt: i value: (PBObject withAll: {
        'name' -> ('person' , i printString). 'city' -> (cities at: i \\ 4 + 1). 'age' -> (18 + (i \\ 60)) })].
people := people addIndex: (PBRangeIndex name: 'by_age' path: 'age').
q := PBQuery from: people.
age := PBField path: 'age'.

pager := (q orderBy: 'age') pagerSize: 50.
lesson check: 'an ordered index scan is paged by rank' isTrue: pager byRank.
lesson check: 'twelve pages of fifty, numbered from 0' is: { pager rows. pager pages } equals: #(600 12).
lesson check: 'page 0 is the fifty youngest' is: ((pager page: 0) collect: [:p | p at: 'age']) asSet asSortedCollection asArray equals: #(18 19 20 21 22).
lesson check: 'past the last page: an empty page' is: (pager page: 12) equals: #().
lesson check: 'explain: the pager, then the plan it pages'
    is: (pager explain at: 'pager') equals: (PBFrozenDict withAssociations: { 'page_size' -> 50. 'by_rank' -> true }).
byAgeThenName := ((q orderBy: 'age') thenBy: 'name') pagerSize: 50.
lesson check: 'two sort keys have no rank: the result is materialised once' isTrue: byAgeThenName byRank not.
lesson check: 'and sliced: its pages are the query''s rows'
    is: (byAgeThenName page: 3) equals: ((((q orderBy: 'age') thenBy: 'name') asArray) copyFrom: 151 to: 200).

"Every page, concatenated, is the query's rows, by rank or not."
all := [:aPager | (0 to: aPager pages - 1) inject: #() into: [:acc :k | acc , (aPager page: k)]].
lesson check: 'the pages of either pager are the rows of its query'
    isTrue: (all value: pager) = (q orderBy: 'age') asArray & ((all value: byAgeThenName) = ((q orderBy: 'age') thenBy: 'name') asArray).

"A pager of a plan, or of a collection (its scan: a PBDictionary scan seeks by rank too)."
seventies := PBPager on: (q where: age > 69) plan pageSize: 25.
lesson check: 'a pager of a plan: eighty people in four pages, the last of five'
    is: { seventies byRank. seventies rows. seventies pages. (seventies page: 3) size } equals: #(true 80 4 5).
lesson check: 'a pager of a collection pages its scan'
    is: { (PBPager on: people pageSize: 100) byRank. ((PBPager on: people pageSize: 100) page: 5) size } equals: #(true 100).
lesson check: 'a page number is an Integer from 0'
    is: ([pager page: -1. #accepted] on: PBValidationError do: [:e | e return: #refused]) equals: #refused.

lesson finish.
