"EXPECT: ok 14"
"Indexed queries, plan Task 6: the plan operators (proto_db proto_db/query/plans.py at v2.0.0rc4,
 less ValuesScan, VectorSearch, GroupBy, Join and Unnest; spec 3.2). tests/unit/test_query_plans.py's
 four behaviours (the estimate, the abstract plan, the collection scan and its empty case), then
 every node's execute, estimate and explain over QData people: 200 seed: 6 in a PBList with an
 equality index on city and a range index on age: Filter keeps 0.5 per term (And multiplies, Or is
 1 - prod(1 - s), Not is 1 - s), BlockFilter one term; Union keeps each element with its largest
 multiplicity over the sources and Intersect with its smallest, by element identity (1 and 1.0 are
 two elements); Sort is stable and total (MISSING, nil, numbers, ... then the unorderable keys),
 descending reverses the keys and keeps ties in input order; Limit seeks its window by rank over an
 ordered scan; Count reads the count by rank; Distinct keeps first occurrences; Project answers a
 PBFrozenDict of the paths (an absent field is left out, so the field's key spec extracts PBMissing
 from the row) or a block's answer. explain has proto_db's keys in proto_db's order and is printable
 by PBNotation describe:; execute answers equal, distinct Arrays; do: is lazy. Mapped in
 tests/unit/queries_checklist.tsv."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.

| c people list byCity byAge scan city age bag ids keysOf est plans rows r1 a b u i k sorted
  sortRows fails seen limit count dist proj missing decimal1 expected composite filter |
c := Check new.
missing := PBMissing default.
decimal1 := Decimal fromString: '1'.
people := QData people: 200 seed: 6.
list := ((PBList new extend: people)
  addIndex: (PBEqualityIndex name: 'by_city' path: 'city'))
  addIndex: (PBRangeIndex name: 'by_age' path: 'age').
byCity := list getIndex: 'by_city'.
byAge := list getIndex: 'by_age'.
scan := list asQueryPlan.
city := [:op :v | PBTerm path: 'city' op: op value: v].
age := [:op :v | PBTerm path: 'age' op: op value: v].
bag := [:anArray | QData bagOf: anArray].
ids := [:anArray | anArray collect: [:each | each at: 'id']].
keysOf := [:aPlan | aPlan explain keys asArray].
est := [:aPlan | { aPlan estimate rows. aPlan estimate cost }].

"=== test_query_plans.py ==="
r1 := PBEstimate rows: 3 cost: 4.5.
c that: 'PBEstimate is frozen and validated'
  is: { r1 rows. r1 rows isFloat. r1 cost. r1 = (PBEstimate rows: 3.0 cost: 4.5). (r1 respondsTo: #rows:).
    { { -1. 0 }. { 0. -1 }. { Float nan. 0 }. { 0. Float infinity }. { '1'. 0 }. { true. 0 }. { 0. 3/4 } }
      collect: [:pair | [PBEstimate rows: (pair at: 1) cost: (pair at: 2). nil] on: PBValidationError do: [:e | e return: #refused]] }
  equals: { 3.0. true. 4.5. true. false. (1 to: 7) asArray collect: [:x | #refused] }.

c that: 'PBQueryPlan is abstract' signals: PBUserError during: [PBQueryPlan new].

a := ((PBSet new add: 2) add: 1) addIndex: (PBEqualityIndex name: 'i' keySpec: PBKeySpec element).
u := a asQueryPlan.
b := PBCollectionScan on: PBSet new.
c that: 'a collection scan executes, estimates and explains as proto_db, empty or not'
  is: { (u isKindOf: PBCollectionScan) and: [u isKindOf: PBQueryPlan]. u collection == a. u execute = a elements.
    u explain = (PBFrozenDict withAssociations: { 'plan' -> 'CollectionScan'. 'collection' -> 'Set'. 'rows' -> 2.
      'indexes' -> (PBFrozenList withAll: #('i')). 'estimate' -> (PBFrozenDict withAssociations: { 'rows' -> 2.0. 'cost' -> 2.0 }).
      'children' -> (PBFrozenList withAll: #()) }).
    u estimate = (PBEstimate rows: 2 cost: 2).
    b execute. b estimate = (PBEstimate rows: 0 cost: 0). (b explain at: 'indexes') isEmpty.
    { PBList new. PBDictionary new. PBHashDictionary new. PBSet new. PBCountedSet new. PBRepeatedKeysDictionary new }
      collect: [:each | each asQueryPlan explain at: 'collection'].
    [PBCollectionScan on: #(1 2). nil] on: PBValidationError do: [:e | e return: #refused] }
  equals: { true. true. true. true. true. #(). true. true.
    #('List' 'Dictionary' 'HashDictionary' 'Set' 'CountedSet' 'RepeatedKeysDictionary'). #refused }.

"=== the nodes over QData people: 200 ==="
filter := PBFilter source: scan terms: { city value: '==' value: 'Oslo' }.
plans := {
  filter.
  PBFilter source: scan terms: { city value: '==' value: 'Oslo'. age value: '<' value: 30 }.
  PBFilter source: scan terms: { (city value: '==' value: 'Oslo') | (age value: '<' value: 30) }.
  PBFilter source: scan terms: { (city value: '==' value: 'Oslo') not }.
  PBBlockFilter source: scan predicate: (PBBlockPredicate block: [:p | (p at: 'id') even] description: 'even id') }.
c that: 'Filter keeps half per term: And multiplies, Or is 1 - prod(1 - s), Not is 1 - s; BlockFilter is one term'
  is: { plans collect: [:p | est value: p].
    (plans copyFrom: 1 to: 4) collect: [:p | (bag value: p execute) = (QData scan: people where: [:e | p predicate evaluate: e])].
    (bag value: plans last execute) = (QData scan: people where: [:e | (e at: 'id') even]).
    filter explain at: 'predicate'. (plans last explain at: 'description').
    (PBFilter source: scan terms: { 'city'. '=='. 'Oslo' }) predicate = (city value: '==' value: 'Oslo') }
  equals: { { #(100.0 400.0). #(50.0 400.0). #(150.0 400.0). #(100.0 400.0). #(100.0 400.0) }.
    #(true true true true). true. (city value: '==' value: 'Oslo') describe. 'even id'. true }.

r1 := people at: 1.
a := PBCollectionScan on: (PBList new extend: { 1. 1. 2. 1.0. r1 }).
b := PBCollectionScan on: (PBList new extend: { 1. 2. 2. 3. decimal1 }).
u := PBUnion withAll: { a. b }.
i := PBIntersect withAll: { a. b }.
c that: 'Union keeps the largest multiplicity and Intersect the smallest, by element identity'
  is: { u execute collect: [:e | PBKeys exactToken: e]. i execute collect: [:e | PBKeys exactToken: e].
    est value: u. est value: i.
    (bag value: (PBUnion withAll: { byCity plan: (city value: '==' value: 'Oslo'). byAge plan: (age value: '<' value: 30) }) execute)
      = (QData scan: people where: [:e | ((city value: '==' value: 'Oslo') matches: e) or: [(age value: '<' value: 30) matches: e]]).
    (bag value: (PBIntersect withAll: { byCity plan: (city value: '==' value: 'Oslo'). byAge plan: (age value: '<' value: 30) }) execute)
      = (QData scan: people where: [:e | ((city value: '==' value: 'Oslo') matches: e) and: [(age value: '<' value: 30) matches: e]]).
    [PBUnion withAll: { a }. nil] on: PBValidationError do: [:e | e return: #refused].
    [PBIntersect withAll: { a. 3 }. nil] on: PBValidationError do: [:e | e return: #refused] }
  equals: { { 1. 1. 2. 1.0. r1. 2. 3. decimal1 } collect: [:e | PBKeys exactToken: e]. { 1. 2 } collect: [:e | PBKeys exactToken: e].
    #(10.0 20.0). #(5.0 20.0). true. true. #refused. #refused }.

"Sort: rows i -> k of 2, nil, 'a', 1, absent, a list, 1.0, 2, NaN"
sortRows := { 2. nil. 'a'. 1. missing. PBFrozenList withAll: #(1). 1.0. 2. Float nan } withIndexCollect: [:v :n |
  v == missing
    ifTrue: [PBFrozenDict withAssociations: { 'i' -> (n - 1). 'g' -> (n \\ 2) }]
    ifFalse: [PBFrozenDict withAssociations: { 'i' -> (n - 1). 'k' -> v. 'g' -> (n \\ 2) }]].
a := PBCollectionScan on: (PBList new extend: sortRows).
k := [:plan | plan execute collect: [:row | row at: 'i']].
sorted := PBSort source: a keys: { PBSortKey key: 'k' descending: false }.
c that: 'Sort is stable and total, unorderable keys last; descending reverses the keys, ties in input order'
  is: { k value: sorted. k value: (PBSort source: a keys: { PBSortKey key: 'k' descending: true }).
    k value: (PBSort source: a keys: { PBSortKey key: 'g' descending: false. PBSortKey key: 'i' descending: true }).
    k value: (PBSort source: a keys: { PBSortKey key: [:row | (row at: 'i') \\ 3] descending: false }).
    est value: sorted.
    (sorted explain at: 'keys') = (PBFrozenList withAll: { PBFrozenDict withAssociations: { 'key' -> 'k'. 'descending' -> false } }).
    ((PBSort source: a keys: { PBSortKey key: [:row | 1] descending: true }) explain at: 'keys') asArray first at: 'key'.
    ((PBSort source: a keys: { PBSortKey key: [:row | 1] descending: true description: 'one' }) explain at: 'keys') asArray first at: 'key'.
    [PBSortKey key: 'k' descending: nil. nil] on: PBValidationError do: [:e | e return: #refused].
    [PBSort source: a keys: #(). nil] on: PBValidationError do: [:e | e return: #refused] }
  equals: { #(4 1 3 6 0 7 2 5 8). #(5 8 2 0 7 3 6 1 4). #(7 5 3 1 8 6 4 2 0). #(0 3 6 1 4 7 2 5 8).
    { 9.0. 9 + (9 * (PBCost log2: 9)) }. true. 'block'. 'one'. #refused. #refused }.

limit := PBLimit source: (byAge orderedPlan: (PBKeySpec path: 'age') descending: false) limit: 5 offset: 3.
u := PBLimit source: (PBFilter source: scan terms: { city value: '!=' value: 'Oslo'. age value: '>' value: 20 }) limit: 4 offset: 2.
c that: 'Limit seeks its window by rank over an ordered scan, and skips rows otherwise'
  is: { limit execute = ((byAge orderedPlan: (PBKeySpec path: 'age') descending: false) execute copyFrom: 4 to: 8).
    (limit explain at: 'by_rank'). { limit explain at: 'limit'. limit explain at: 'offset' }. est value: limit.
    u execute = ((u source execute) copyFrom: 3 to: 6). (u explain includesKey: 'by_rank').
    (PBLimit source: scan limit: nil offset: 198) execute = (people copyFrom: 199 to: 200).
    (PBLimit source: scan limit: nil offset: 198) explain at: 'limit'.
    est value: (PBLimit source: scan limit: 10 offset: 195).
    [PBLimit source: scan limit: -1 offset: 0. nil] on: PBValidationError do: [:e | e return: #refused].
    [PBLimit source: scan limit: 1 offset: true. nil] on: PBValidationError do: [:e | e return: #refused] }
  equals: { true. true. #(5 3). { 5.0. (200 + byAge groupCount + 1) asFloat }. true. false. true. nil. #(5.0 200.0). #refused. #refused }.

count := PBCountPlan source: (byCity plan: (city value: '==' value: 'Oslo')).
u := PBCountPlan source: filter.
c that: 'Count reads the count of an index plan by rank and counts any other source'
  is: { count execute. (count explain at: 'by_rank'). u execute. (u explain includesKey: 'by_rank'). est value: count. est value: u.
    (PBCountPlan source: scan) execute. ((PBCountPlan source: scan) explain at: 'by_rank') }
  equals: { { (QData scan: people where: [:e | (city value: '==' value: 'Oslo') matches: e]) inject: 0 into: [:s :n | s + n] }.
    true. { filter execute size }. false. { 1.0. (byCity estimate: (city value: '==' value: 'Oslo')) cost }. #(1.0 400.0). #(200). true }.

dist := PBDistinct source: (PBCollectionScan on: (PBList new extend: {
  1. 1.0. decimal1. true. 1. r1. r1. PBFrozenList withAll: #(1). PBFrozenList withAll: #(1). PBFrozenList withAll: { 1.0 } })).
c that: 'Distinct keeps first occurrences by element identity'
  is: { dist execute collect: [:e | PBKeys exactToken: e]. est value: dist. dist explain keys asArray }
  equals: { { 1. 1.0. decimal1. true. r1. PBFrozenList withAll: #(1). PBFrozenList withAll: { 1.0 } } collect: [:e | PBKeys exactToken: e].
    #(10.0 20.0). #('plan' 'estimate' 'children') }.

proj := PBProject source: scan fields: #('name' 'city').
rows := proj execute.
expected := people collect: [:p | (p hasDefinedAttr: 'city')
  ifTrue: [PBFrozenDict withAssociations: { 'name' -> (p at: 'name'). 'city' -> (p at: 'city') }]
  ifFalse: [PBFrozenDict withAssociations: { 'name' -> (p at: 'name') }]].
c that: 'Project of fields answers maps without the absent fields, and of a block its answers'
  is: { rows = expected.
    (rows reject: [:row | row includesKey: 'city']) allSatisfy: [:row | ((PBKeySpec path: 'city') extract: row) == missing].
    (rows reject: [:row | row includesKey: 'city']) notEmpty.
    (PBProject source: scan fields: [:p | p at: 'id']) execute. est value: proj.
    proj explain at: 'fields'. (PBProject source: scan fields: [:p | 1] description: 'one') explain at: 'function'.
    [PBProject source: scan fields: #(). nil] on: PBValidationError do: [:e | e return: #refused].
    [PBProject source: scan fields: { 3 }. nil] on: PBValidationError do: [:e | e return: #refused] }
  equals: { true. true. true. (0 to: 199) asArray. #(200.0 400.0).
    PBFrozenDict withAssociations: { 'name' -> 'name'. 'city' -> 'city' }. 'one'. #refused. #refused }.

"One plan holding every node: its explain is printable, and every node's explain has proto_db's keys
 in proto_db's order."
composite := PBCountPlan source: (PBLimit source: (PBDistinct source: (PBProject source: (PBSort source:
  (PBUnion withAll: {
    PBFilter source: (byCity plan: (city value: 'in' value: #('Oslo' 'Rome'))) terms: { age value: '>=' value: 25 }.
    PBIntersect withAll: { byAge plan: (age value: 'between[]' value: #(20 30)). PBBlockFilter source: scan predicate: (PBBlockPredicate block: [:p | true] description: 'all') }.
    byAge orderedPlan: (PBKeySpec path: 'age') descending: true })
  keys: { PBSortKey key: 'id' descending: false }) fields: #('id' 'city'))) limit: 10 offset: 2).
c that: 'explain is printable by PBNotation describe:'
  is: ([PBNotation describe: composite explain. true] on: Error do: [:e | e return: e messageText])
  equals: true.

fails := OrderedCollection new.
seen := OrderedCollection new.
{ composite } , { scan. byCity plan: (city value: '==' value: 'Oslo'). byAge orderedPlan: (PBKeySpec path: 'age') descending: false.
  filter. plans last. u. limit. proj. sorted. dist. count. PBUnion withAll: { scan. scan }. PBIntersect withAll: { scan. scan } }
  do: [:p | | x y |
    x := p execute. y := p execute.
    (x = y and: [x ~~ y and: [x isKindOf: Array]]) ifFalse: [fails add: (p explain at: 'plan')]].
c that: 'execute answers equal, distinct Arrays every time' is: fails asArray equals: #().

c that: 'every node explains with proto_db''s keys in proto_db''s order'
  is: ({ scan. byCity plan: (city value: '==' value: 'Oslo'). byAge orderedPlan: (PBKeySpec path: 'age') descending: false.
    filter. plans last. PBUnion withAll: { scan. scan }. PBIntersect withAll: { scan. scan }. proj. sorted. limit. count. dist }
    collect: [:p | keysOf value: p])
  equals: { #('plan' 'collection' 'rows' 'indexes' 'estimate' 'children'). #('plan' 'index' 'term' 'estimate' 'children').
    #('plan' 'index' 'term' 'descending' 'estimate' 'children'). #('plan' 'predicate' 'estimate' 'children').
    #('plan' 'description' 'estimate' 'children'). #('plan' 'estimate' 'children'). #('plan' 'estimate' 'children').
    #('plan' 'fields' 'estimate' 'children'). #('plan' 'keys' 'estimate' 'children').
    #('plan' 'limit' 'offset' 'by_rank' 'estimate' 'children'). #('plan' 'by_rank' 'estimate' 'children').
    #('plan' 'estimate' 'children') }.

"do: is lazy: a Limit stops pulling from its source (IP9); a non-local return stops any node."
seen := 0.
limit := PBLimit source: (PBBlockFilter source: scan predicate: (PBBlockPredicate block: [:p | seen := seen + 1. true] description: 'count')) limit: 3 offset: 0.
rows := limit execute.
c that: 'do: is lazy: a Limit stops its source after its window'
  is: { rows size. seen. (PBFilter source: scan terms: { city value: '?!N' value: nil }) execute size > 3 }
  equals: { 3. 3. true }.

c report displayNl.
