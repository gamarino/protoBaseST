"EXPECT: ok 8"
"Indexed queries, plan Task 9: PBPager, in-process pages of one plan (proto_db
 proto_db/query/pager.py at v2.0.0rc4, Pager, lines 136-227; D56, rulings R77 and R77a). The
 behaviours of proto_db's tests/unit/test_pager.py that apply (portable tokens, snapshot
 references and the query cache are deferred by spec 3.2, rulings IQ3 and IQ7: those rows are
 n/a in tests/unit/queries_checklist.tsv), over its data: 500 records {k: (7919 i) mod n, v: i}
 in a PBList with a range index on k. Then this port's own cases: byRank is proto_db's Pager.by_rank
 for every plan shape of spec 5.7 and the shapes without rank (the expected table was printed by
 proto_db's Pager over the same plans); for every page k of ordered and unordered queries, by rank
 and materialised, the pages concatenated are asArray; writes after the pager, in the same
 transaction, do not move its pages (Review Focus 3); the refusals; explain is exactly
 { pager -> { page_size. by_rank }. plan } (ruling CR7). Pages are zero-based (CR7)."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.

| c dir space db tr items k q pager expected all vs r seen calls counted rec coll rk ek t shapes got
  rnd fails sizes people old fresh e refusals before n |
c := Check new.
vs := [:aRows | aRows asArray collect: [:each | each at: 'v']].
"Every page of aPager, from 0 until an empty one (test_pager.py _all_pages); a page longer than
 the page size is recorded as a failure (nil)."
all := [:aPager | | out page i long |
  out := OrderedCollection new.
  i := 0.
  long := false.
  [page := aPager page: i.
   page size > aPager pageSize ifTrue: [long := true].
   page isEmpty] whileFalse: [out addAll: page. i := i + 1].
  long ifTrue: [nil] ifFalse: [out asArray]].
rec := [:i :n | PBFrozenDict withAssociations: { 'k' -> (i * 7919 \\ n). 'v' -> i }].
dir := 'out/qry_pager' asFileReference / ('run-' , Smalltalk pid printString , '-' , Time microsecondClockValue printString).
dir ensureCreateDirectory.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).

"proto_db: test_ranked_pages_equal_the_ordered_result."
db := space newDatabase: 'db'.
db run: [:tx | tx setRootObject: 'items' value: ((tx newList addIndex: (PBRangeIndex name: 'k' path: 'k'))
  extend: ((0 to: 499) asArray collect: [:i | rec value: i value: 500]))].
tr := db newTransaction.
q := ((PBQuery from: (tr getRootObject: 'items')) where: ((PBField path: 'k') >= 100)) orderBy: 'k'.
pager := PBPager on: q pageSize: 37.
expected := q asArray.
c that: 'ranked pages equal the ordered result'
  is: { pager byRank. pager rows. expected size. pager pages. vs value: (all value: pager).
    vs value: (pager page: 3). pager page: 99 }
  equals: { true. 400. 400. 11. vs value: expected. vs value: (expected copyFrom: 112 to: 148). #() }.

"proto_db: test_unranked_pages_come_from_one_cached_result (the query cache is deferred, spec 3.2:
 here the materialised result is the pager's own, computed once: a counting block filter is run once
 per element however many pages are read, twice over)."
calls := Atom on: 0.
counted := ((PBQuery from: (tr getRootObject: 'items')) where: [:each | calls swap: [:x | x + 1]. (each at: 'v') < 50])
  orderBy: 'k' descending: true.
q := ((PBQuery from: (tr getRootObject: 'items')) where: ((PBField path: 'v') < 50)) orderBy: 'k' descending: true.
pager := PBPager on: q pageSize: 8.
expected := q asArray.
got := { pager byRank. vs value: (all value: pager) }.
pager := counted pagerSize: 8.
calls swap: [:x | 0].
got := got , { vs value: (all value: pager). vs value: (all value: pager). calls value. pager rows. pager pages }.
c that: 'unranked pages come from one materialised result'
  is: got
  equals: { false. vs value: expected. vs value: expected. vs value: expected. 500. 50. 7 }.

"proto_db: test_pages_are_stable_while_writers_insert_before_and_after_the_page (300 records)."
db := space newDatabase: 'stable'.
db run: [:tx | tx setRootObject: 'items' value: ((tx newList addIndex: (PBRangeIndex name: 'k' path: 'k'))
  extend: ((0 to: 299) asArray collect: [:i | rec value: i value: 300]))].
tr := db newTransaction.
q := (PBQuery from: (tr getRootObject: 'items')) orderBy: 'k'.
pager := q pagerSize: 20.
expected := q asArray.
seen := OrderedCollection new.
0 to: pager pages - 1 do: [:p |
  seen addAll: (pager page: p).
  "Keys below and above the current page, and a removal, between every two pages."
  db run: [:tx | tx setRootObject: 'items' value: ((((tx getRootObject: 'items')
    appendLast: (PBFrozenDict withAssociations: { 'k' -> (-1 - p). 'v' -> -1 }))
    appendLast: (PBFrozenDict withAssociations: { 'k' -> (10000 + p). 'v' -> -2 }))
    removeAt: 0)]].
c that: 'pages are stable while writers insert before and after the page and remove'
  is: { vs value: seen. (((PBQuery from: (db newTransaction getRootObject: 'items')) orderBy: 'k') pagerSize: 20) rows }
  equals: { vs value: expected. 300 + pager pages }.

"byRank as proto_db's Pager.by_rank: the plans of spec 5.7 (an index lookup, range, complement or
 ordered scan; a PBList or PBDictionary scan; a Limit over one of them; a single-term Filter over
 an ordered scan of the index that answers it; a single-key Sort over an index plan of that key)
 by rank, every other shape materialised. The table was printed by proto_db's Pager over the same
 plans and data (40 records {k: i mod 7, e: i mod 5, v: i}, range index by_k, equality index by_e)."
coll := ((PBList new extend: ((0 to: 39) asArray collect: [:i | PBFrozenDict withAssociations: { 'k' -> (i \\ 7). 'e' -> (i \\ 5). 'v' -> i }]))
  addIndex: (PBRangeIndex name: 'by_k' path: 'k')) addIndex: (PBEqualityIndex name: 'by_e' path: 'e').
rk := coll getIndex: 'by_k'.
ek := coll getIndex: 'by_e'.
t := [:path :op :value | PBTerm path: path op: op value: value].
shapes := {
  'lookup eq' -> (ek plan: (t value: 'e' value: '==' value: 2)).
  'range lookup' -> (rk plan: (t value: 'k' value: '==' value: 2)).
  'range' -> (rk plan: (t value: 'k' value: '>=' value: 3)).
  'complement eq' -> (ek plan: (t value: 'e' value: '!=' value: 2)).
  'complement range' -> (rk plan: (t value: 'k' value: '!=' value: 2)).
  'in' -> (ek plan: (t value: 'e' value: 'in' value: #(1 2))).
  'ordered' -> (rk orderedPlan: (PBKeySpec path: 'k') descending: false).
  'ordered desc' -> (rk orderedPlan: (PBKeySpec path: 'k') descending: true).
  'list scan' -> coll asQueryPlan.
  'dict scan' -> (((PBDictionary new setAt: 'a' value: 1) setAt: 'b' value: 2) asQueryPlan).
  'set scan' -> (((PBSet new add: 1) add: 2) asQueryPlan).
  'hashdict scan' -> ((PBHashDictionary new setAt: 1 value: 1) asQueryPlan).
  'limit over ordered' -> (PBLimit source: (rk orderedPlan: (PBKeySpec path: 'k') descending: false) limit: 5 offset: 3).
  'filter one term over ordered' -> (PBFilter source: (rk orderedPlan: (PBKeySpec path: 'k') descending: false) terms: { t value: 'k' value: '>=' value: 3 }).
  'filter two terms over ordered' -> (PBFilter source: (rk orderedPlan: (PBKeySpec path: 'k') descending: false)
    terms: { t value: 'k' value: '>=' value: 3. t value: 'v' value: '<' value: 30 }).
  'filter other term over ordered' -> (PBFilter source: (rk orderedPlan: (PBKeySpec path: 'k') descending: false) terms: { t value: 'v' value: '<' value: 30 }).
  'sort one key over range' -> (PBSort source: (rk plan: (t value: 'k' value: '>=' value: 3)) keys: { PBSortKey key: 'k' descending: false }).
  'sort other key over range' -> (PBSort source: (rk plan: (t value: 'k' value: '>=' value: 3)) keys: { PBSortKey key: 'v' descending: false }).
  'sort two keys over range' -> (PBSort source: (rk plan: (t value: 'k' value: '>=' value: 3))
    keys: { PBSortKey key: 'k' descending: false. PBSortKey key: 'v' descending: false }).
  'sort over scan' -> (PBSort source: coll asQueryPlan keys: { PBSortKey key: 'k' descending: false }).
  'union' -> (PBUnion withAll: { ek plan: (t value: 'e' value: '==' value: 1). ek plan: (t value: 'e' value: '==' value: 2) }).
  'project' -> (PBProject source: (rk orderedPlan: (PBKeySpec path: 'k') descending: false) fields: #('k')).
  'distinct' -> (PBDistinct source: (rk orderedPlan: (PBKeySpec path: 'k') descending: false)) }.
got := shapes collect: [:each | | p | p := PBPager on: each value pageSize: 7. { each key. p byRank. p rows }].
c that: 'byRank is proto_db''s Pager.by_rank for every plan shape, and rows its row count'
  is: got
  equals: {
    #('lookup eq' true 8). #('range lookup' true 6). #('range' true 22). #('complement eq' true 32).
    #('complement range' true 34). #('in' true 16). #('ordered' true 40). #('ordered desc' true 40).
    #('list scan' true 40). #('dict scan' true 2). #('set scan' false 2). #('hashdict scan' false 1).
    #('limit over ordered' true 5). #('filter one term over ordered' true 22).
    #('filter two terms over ordered' false 16). #('filter other term over ordered' false 30).
    #('sort one key over range' true 22). #('sort other key over range' false 22).
    #('sort two keys over range' false 22). #('sort over scan' false 40). #('union' false 16).
    #('project' false 40). #('distinct' false 40) }.

"For every page k of ordered and unordered queries, by rank and materialised, on seeded data and
 page sizes: the pages concatenated are asArray, rows is its size, pages is ceiling(rows / size),
 every page but the last is full and the page after the last is empty."
fails := OrderedCollection new.
sizes := Set new.
1 to: (QData seeds: 5) do: [:seed |
  | data recs base queries |
  rnd := QData spreadOn: 9100 + seed.
  recs := (1 to: (rnd between: 0 and: 120)) asArray collect: [:i |
    PBFrozenDict withAssociations: { 'id' -> i. 'k' -> (rnd between: 0 and: 15). 'g' -> (rnd between: 0 and: 3) }].
  base := ((PBList new extend: recs) addIndex: (PBRangeIndex name: 'by_k' path: 'k')) addIndex: (PBEqualityIndex name: 'by_g' path: 'g').
  data := PBQuery from: base.
  queries := {
    data.
    data where: ((PBField path: 'g') eq: 2).
    data where: ((PBField path: 'k') between: 3 and: 11).
    data orderBy: 'k'.
    data orderBy: 'k' descending: true.
    (data where: ((PBField path: 'k') > 4)) orderBy: 'k'.
    ((data orderBy: 'k') skip: 3) take: 40.
    data orderBy: 'id' descending: true.
    (data orderBy: 'k') thenBy: 'id' descending: true.
    data where: ((PBField path: 'g') eq: 1) | ((PBField path: 'k') < 3).
    (data where: [:each | (each at: 'id') odd]) orderBy: 'k'.
    data orderBy: [:each | (each at: 'id') \\ 7] }.
  queries do: [:query | | rows |
    rows := query asArray.
    #(1 3 7 50 500) do: [:size | | p pages ok |
      p := query pagerSize: size.
      sizes add: p byRank.
      pages := (0 to: p pages - 1) asArray collect: [:i | p page: i].
      ok := (pages inject: #() into: [:acc :each | acc , each]) = rows
        and: [p rows = rows size
        and: [p pages = (rows size + size - 1 // size)
        and: [(p page: p pages) isEmpty
        and: [pages allButLast allSatisfy: [:each | each size = size]]]]].
      ok ifFalse: [fails add: { seed. query printString. size }]]]].
c that: 'every page of ordered and unordered queries, by rank and materialised, concatenates to asArray'
  is: { fails asArray. sizes size }
  equals: { #(). 2 }.

"Review Focus 3: a pager over a version, then more writes in the same transaction; the pager keeps
 reading its version, a new pager sees the new one."
db := space newDatabase: 'people'.
db run: [:tx | tx setRootObject: 'people' value: ((tx newDictionary addIndex: (PBRangeIndex name: 'by_age' path: 'age'))
  setAt: 1 value: (tx newObject: { 'name' -> 'ann'. 'age' -> 30 }))].
tr := db newTransaction.
people := tr getRootObject: 'people'.
old := ((PBQuery from: people) orderBy: 'age') pagerSize: 2.
before := { old rows. old pages. (old page: 0) collect: [:each | each at: 'name'] }.
tr setRootObject: 'people' value: ((people setAt: 2 value: (tr newObject: { 'name' -> 'bob'. 'age' -> 20 }))
  setAt: 3 value: (tr newObject: { 'name' -> 'cid'. 'age' -> 25 })).
fresh := ((PBQuery from: (tr getRootObject: 'people')) orderBy: 'age') pagerSize: 2.
r := before , { old rows. old pages. (old page: 0) collect: [:each | each at: 'name'].
  fresh rows. fresh pages. (fresh page: 0) collect: [:each | each at: 'name'] }.
tr commit.
r := r , { (old page: 0) collect: [:each | each at: 'name']. old rows }.
c that: 'writes after the pager do not move its pages'
  is: r
  equals: { 1. 1. #('ann'). 1. 1. #('ann'). 3. 2. #('bob' 'cid'). #('ann'). 1 }.

"The refusals (pager.py: page_size an int >= 1, a page number an int >= 0; as_plan: a plan, a query
 or a collection), and what past the last page and an empty result answer."
q := PBQuery from: coll.
refusals := { 0. -1. 1.5. nil. '3'. PBQuery. true } collect: [:each |
  [PBPager on: q pageSize: each. #accepted] on: PBValidationError do: [:ex | ex return: #refused]].
refusals := refusals , ({ -1. 1.5. nil. '0'. Integer } collect: [:each |
  [(q pagerSize: 5) page: each. #accepted] on: PBValidationError do: [:ex | ex return: #refused]]).
refusals := refusals , ({ #(1 2). 3. nil. PBList } collect: [:each |
  [PBPager on: each pageSize: 5. #accepted] on: PBValidationError do: [:ex | ex return: #refused]]).
e := (PBQuery from: coll) where: ((PBField path: 'k') eq: 99).
n := {
  ((q pagerSize: 7) page: 5) size. (q pagerSize: 7) page: 6. (q pagerSize: 7) page: 1000.
  (e pagerSize: 3) rows. (e pagerSize: 3) pages. (e pagerSize: 3) page: 0.
  ((PBQuery from: PBSet new) pagerSize: 3) pages. ((PBQuery from: PBSet new) pagerSize: 3) page: 0.
  ((q pagerSize: 7) page: 6) ~~ ((q pagerSize: 7) page: 6).
  ((e pagerSize: 3) page: 0) ~~ ((e pagerSize: 3) page: 0).
  (((PBQuery from: PBSet new) pagerSize: 3) page: 0) ~~ (((PBQuery from: PBSet new) pagerSize: 3) page: 0) }.
[(q pagerSize: 5) page: -1] on: PBValidationError do: [:ex | n := n , { ex messageText }].
[PBPager on: q pageSize: 0] on: PBValidationError do: [:ex | n := n , { ex messageText }].
c that: 'page sizes, page numbers and sources are validated; past the last page is a new empty Array'
  is: { refusals asSet asArray. n }
  equals: { #(#refused). { 5. #(). #(). 0. 0. #(). 0. #(). true. true. true.
    'A page number must be an Integer >= 0, not -1'. 'A page size must be an Integer >= 1, not 0' } }.

"explain (ruling CR7): exactly pager -> { page_size. by_rank } and plan -> the plan's explain, no
 portable; the sources of on: (a query, a plan, a collection) give the same pager; pagerSize: is
 on: pageSize:; plan and pageSize are the pager's."
q := ((PBQuery from: coll) where: ((PBField path: 'k') >= 3)) orderBy: 'k'.
pager := q pagerSize: 6.
got := { pager explain keys asArray. (pager explain at: 'pager') keys asArray.
  (pager explain at: 'pager') at: 'page_size'. (pager explain at: 'pager') at: 'by_rank'.
  (pager explain at: 'plan') = q explain. (pager explain at: 'pager') = (PBFrozenDict withAssociations: { 'page_size' -> 6. 'by_rank' -> true }).
  pager explain class. pager pageSize. pager plan explain = q explain.
  (PBPager on: q plan pageSize: 6) explain = pager explain.
  (PBPager on: coll pageSize: 4) explain = (PBPager on: coll asQueryPlan pageSize: 4) explain.
  vs value: ((PBPager on: coll pageSize: 4) page: 2).
  ((PBPager on: ((PBQuery from: coll) where: [:each | true]) pageSize: 3) explain at: 'pager') at: 'by_rank'.
  pager printString. ((PBQuery from: PBSet new) pagerSize: 3) printString }.
c that: 'explain is exactly pager -> page_size, by_rank and plan -> the plan''s explain'
  is: got
  equals: { #('pager' 'plan'). #('page_size' 'by_rank'). 6. true. true. true. PBFrozenDict. 6. true. true. true.
    #(8 9 10 11). false. 'PBPager(page size 6, by rank)'. 'PBPager(page size 3, materialised)' }.

space close.
c report displayNl.
