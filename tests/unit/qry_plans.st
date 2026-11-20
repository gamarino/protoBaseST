"EXPECT: ok 24"
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
 PBFrozenDict of the paths, or of a PBFrozenDict mapping output names to paths (an absent field is
 left out, so the field's key spec extracts PBMissing from the row), or a block's answer. The three
 plans of docs/queries.md (section Reading a plan), built node by node, give the guide's model estimates
 exactly (proto_db's figures, ruling CR10). explain has proto_db's keys in proto_db's order and is printable
 by PBNotation describe:; execute answers equal, distinct Arrays; do: is lazy. The vectors phase's V0
 fix round ports the tests/unit/test_plans.py and test_plan_windows.py behaviours no check held:
 unorderable elements in Union and Intersect, immutable nodes and a nested explain, one composed plan
 on 8 actors, one estimate per node per explain, a Limit served by rank that produces no row before
 its window, and no window over a collection whose class redefines do:; its fix round 2, an empty
 Limit window and the remaining bad bounds, Count of an empty source, a BlockFilter that never
 swallows, and the Sort half of the per-key labels. Mapped in
 tests/unit/queries_checklist.tsv."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.

"An actor that runs a plan and answers the 'v' of its rows, in order (test_concurrent_execution_
 gives_identical_results)."
Object subclass: #PlansRunner.
PlansRunner >> valuesOf: aPlan
  ^ aPlan execute collect: [:e | e at: 'v'].

"A leaf counting how often its estimate is computed (test_explain_computes_each_estimate_once)."
PBQueryPlan subclass: #CountingPlan instanceVariableNames: 'items calls'.
CountingPlan class >> items: anArray
  ^ self basicNew setItems: anArray.
CountingPlan >> setItems: anArray
  items := anArray.
  calls := 0.
CountingPlan >> calls
  ^ calls.
CountingPlan >> do: aBlock
  items do: aBlock.
CountingPlan >> _estimateWith: aMemo
  calls := calls + 1.
  ^ PBEstimate rows: items size cost: items size.
CountingPlan >> _explainWith: aMemo
  ^ self _explain: 'Counting' params: #() children: #() memo: aMemo.

"A List whose do: answers only its odd elements, so its scan is not windowed by position
 (test_a_subclass_redefining_elements_is_not_windowed)."
PBList subclass: #OddList.
OddList class >> typeName
  ^ 'tests.qry_plans.OddList'.
OddList >> do: aBlock
  super do: [:v | v odd ifTrue: [aBlock value: v]].

| oidBytes c people list byCity byAge scan city age bag ids keysOf est plans rows r1 a b u i k sorted
  sortRows fails seen limit count dist proj missing decimal1 expected composite filter mapped
  guide gCity gAge oslo range gFilter rejected fullScan r30 gSort gLimit lists other nested names
  big bigIndex futures got leaf counted bigRank produced inner part odd info plan |
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

"Identity keys (fix round 1 of Task 8: an atom is keyed by its oid's bytes, any other row by its
 member order key): 1, 1.0 and Decimal 1 stay three elements, an atom given twice is one, and a
 ByteArray equal to the atom's oid bytes is another element, in all three nodes."
oidBytes := PBKeys _oidBytes: r1 oid.
a := PBCollectionScan on: (PBList new extend: { 1. 1.0. decimal1. r1. r1. oidBytes. 1 }).
b := PBCollectionScan on: (PBList new extend: { decimal1. r1. oidBytes. 1.0. 1 }).
c that: 'Union, Intersect and Distinct key an atom by its oid and keep 1, 1.0, Decimal 1 and the oid bytes apart'
  is: { (PBDistinct source: a) execute collect: [:e | PBKeys exactToken: e].
    (PBUnion withAll: { a. b }) execute collect: [:e | PBKeys exactToken: e].
    (PBIntersect withAll: { a. b }) execute collect: [:e | PBKeys exactToken: e] }
  equals: { { 1. 1.0. decimal1. r1. oidBytes } collect: [:e | PBKeys exactToken: e].
    { 1. 1.0. decimal1. r1. r1. oidBytes. 1 } collect: [:e | PBKeys exactToken: e].
    { 1. 1.0. decimal1. r1. oidBytes } collect: [:e | PBKeys exactToken: e] }.

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
    [PBLimit source: scan limit: 1 offset: true. nil] on: PBValidationError do: [:e | e return: #refused].
    "test_limit_offset_and_estimate: an empty window, an offset past the end, the other bad bounds"
    (PBLimit source: scan limit: 0 offset: 0) execute. est value: (PBLimit source: scan limit: 10 offset: 250).
    (PBLimit source: scan limit: 10 offset: 250) execute.
    { { 1. -1 }. { true. 0 }. { 1.5. 0 }. { 1. 1.5 } } collect: [:bad |
      [PBLimit source: scan limit: (bad at: 1) offset: (bad at: 2). nil] on: PBValidationError do: [:e | e return: #refused]] }
  equals: { true. true. #(5 3). { 5.0. (200 + byAge groupCount + 1) asFloat }. true. false. true. nil. #(5.0 200.0). #refused. #refused.
    #(). #(0.0 200.0). #(). #(#refused #refused #refused #refused) }.

count := PBCountPlan source: (byCity plan: (city value: '==' value: 'Oslo')).
u := PBCountPlan source: filter.
c that: 'Count reads the count of an index plan by rank and counts any other source'
  is: { count execute. (count explain at: 'by_rank'). u execute. (u explain includesKey: 'by_rank'). est value: count. est value: u.
    (PBCountPlan source: scan) execute. ((PBCountPlan source: scan) explain at: 'by_rank').
    (PBCountPlan source: (PBCollectionScan on: PBList new)) execute.
    (PBCountPlan source: (PBFilter source: scan terms: { city value: '==' value: 'Nowhere' })) execute }
  equals: { { (QData scan: people where: [:e | (city value: '==' value: 'Oslo') matches: e]) inject: 0 into: [:s :n | s + n] }.
    true. { filter execute size }. false. { 1.0. (byCity estimate: (city value: '==' value: 'Oslo')) cost }. #(1.0 400.0). #(200). true. #(0). #(0) }.

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
mapped := PBProject source: scan fields: (PBFrozenDict withAssociations: { 'who' -> 'name'. 'where' -> 'city' }).
c that: 'Project of fields answers maps without the absent fields, and of a block its answers'
  is: { rows = expected.
    (mapped execute detect: [:row | row includesKey: 'where']) keys asArray.
    (mapped execute reject: [:row | row includesKey: 'where']) allSatisfy: [:row | row keys asArray = #('who')].
    mapped explain at: 'fields'. (mapped execute at: 1) at: 'who'.
    (PBProject source: scan fields: #('name' 'name')) explain at: 'fields'.
    [PBProject source: scan fields: (PBFrozenDict withAssociations: { 'x' -> 3 }). nil] on: PBValidationError do: [:e | e return: #refused].
    (rows reject: [:row | row includesKey: 'city']) allSatisfy: [:row | ((PBKeySpec path: 'city') extract: row) == missing].
    (rows reject: [:row | row includesKey: 'city']) notEmpty.
    (PBProject source: scan fields: [:p | p at: 'id']) execute. est value: proj.
    proj explain at: 'fields'. (PBProject source: scan fields: [:p | 1] description: 'one') explain at: 'function'.
    [PBProject source: scan fields: #(). nil] on: PBValidationError do: [:e | e return: #refused].
    [PBProject source: scan fields: { 3 }. nil] on: PBValidationError do: [:e | e return: #refused] }
  equals: { true.
    #('who' 'where'). true.
    PBFrozenDict withAssociations: { 'who' -> 'name'. 'where' -> 'city' }. (people at: 1) at: 'name'.
    PBFrozenDict withAssociations: { 'name' -> 'name' }. #refused.
    true. true. (0 to: 199) asArray. #(200.0 400.0).
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

"docs/queries.md, Reading a plan: 600 people, cities Lima, Oslo, Paris and Rome in turn, ages 18 to
 77 (ten each), by_city and by_age. The planner (Task 7) is not used: each plan, the chosen ones
 and the rejected candidates, is built node by node, and its estimate is the guide's figure exactly."
guide := (0 to: 599) asArray collect: [:j |
  PBObject withAll: { 'city' -> (#('Lima' 'Oslo' 'Paris' 'Rome') at: j \\ 4 + 1). 'age' -> (18 + (j \\ 60)) }].
guide := ((PBList new extend: guide) addIndex: (PBEqualityIndex name: 'by_city' path: 'city'))
  addIndex: (PBRangeIndex name: 'by_age' path: 'age').
gCity := guide getIndex: 'by_city'.
gAge := guide getIndex: 'by_age'.
oslo := gCity plan: (city value: '==' value: 'Oslo').
range := gAge plan: (age value: '>' value: 70).
gFilter := PBFilter source: range terms: { city value: '==' value: 'Oslo' }.
rejected := PBFilter source: oslo terms: { age value: '>' value: 70 }.
fullScan := PBFilter source: guide asQueryPlan terms: { city value: '==' value: 'Oslo'. age value: '>' value: 70 }.
r30 := gAge plan: (age value: 'between[]' value: #(30 35)).
gSort := PBSort source: r30 keys: { PBSortKey key: 'age' descending: false }.
gLimit := PBLimit source: gSort limit: 5 offset: 0.
c that: 'the three plans of the guide give its model estimates exactly'
  is: { est value: oslo. est value: range. est value: gFilter. gFilter execute size. (est value: rejected) at: 2.
    (est value: fullScan) at: 2. est value: gSort. est value: gLimit. gLimit explain at: 'by_rank'. gLimit execute size }
  equals: { { 150.0. 152.58496250072116 }. { 70.0. 82.95419631038688 }. { 35.0. 152.95419631038686 }. 20. 302.5849625007212.
    1200.0. { 60.0. 426.367632046898 }. { 5.0. 426.367632046898 }. true. 5 }.

"=== Fix round 1 of the vectors phase's V0: the test_plans.py and test_plan_windows.py behaviours no
 check above held (Addendum V, section 5.4; queries_checklist.tsv) ==="

"test_union_intersect_with_unorderable_elements_and_atoms: lists, maps and NaN are elements too."
lists := PBCollectionScan on: (PBList new extend: { PBFrozenList withAll: #(1 2). PBFrozenDict withAssociations: { 'a' -> 1 }.
  PBFrozenList withAll: #(1 2). Float nan }).
other := PBCollectionScan on: (PBList new extend: { PBFrozenList withAll: #(1 2). PBFrozenDict withAssociations: { 'a' -> 1 } }).
c that: 'Union and Intersect keep unorderable elements: lists, maps and NaN'
  is: { (PBUnion withAll: { lists. other }) execute size.
    (PBIntersect withAll: { lists. other }) execute collect: [:e | PBKeys exactToken: e] }
  equals: { 4. { PBFrozenList withAll: #(1 2). PBFrozenDict withAssociations: { 'a' -> 1 } } collect: [:e | PBKeys exactToken: e] }.

"test_plans_are_immutable and test_composed_plan_explain_is_nested: a node has no setter, its
 one-shot initializers refuse a second call, and a composed plan explains as nested children."
nested := PBLimit source: (PBSort source: (PBFilter source: scan terms: { age value: 'in' value: #(25 30) })
  keys: { PBSortKey key: 'name' descending: true }) limit: 1 offset: 0.
names := OrderedCollection new.
info := nested explain.
[info isNil] whileFalse: [names add: (info at: 'plan').
  info := (info at: 'children') isEmpty ifTrue: [nil] ifFalse: [(info at: 'children') asArray first]].
c that: 'plans are immutable, and a composed plan explains as nested children'
  is: { { #source:. #predicate:. #limit:. #offset: } anySatisfy: [:sel | (nested respondsTo: sel) or: [filter respondsTo: sel]].
    [filter _setSource: scan. nil] on: PBUserError do: [:e | e return: #refused].
    [filter _setPredicate: (city value: '==' value: 'Rome'). nil] on: PBUserError do: [:e | e return: #refused].
    names asArray.
    nested execute = ((PBSort source: (PBFilter source: scan terms: { age value: 'in' value: #(25 30) })
      keys: { PBSortKey key: 'name' descending: true }) execute copyFrom: 1 to: 1) }
  equals: { false. #refused. #refused. #('Limit' 'Sort' 'Filter' 'CollectionScan'). true }.

"test_concurrent_execution_gives_identical_results: one composed plan run on 8 actors at once."
big := (PBList new extend: ((0 to: 399) asArray collect: [:j | PBFrozenDict withAssociations: { 'k' -> (j \\ 17). 'v' -> j }]))
  addIndex: (PBRangeIndex name: 'k' path: 'k').
bigIndex := big getIndex: 'k'.
plan := PBLimit source: (PBSort source: (PBUnion withAll: {
    PBFilter source: big asQueryPlan terms: { PBTerm path: 'v' op: '<' value: 300 }.
    bigIndex plan: (PBTerm path: 'k' op: '>=' value: 10) })
  keys: { PBSortKey key: 'k' descending: true. PBSortKey key: 'v' descending: false }) limit: 250 offset: 0.
expected := plan execute collect: [:e | e at: 'v'].
futures := (1 to: 8) asArray collect: [:j | PlansRunner new asActor valuesOf: plan].
got := futures collect: [:f | f waitWithin: 120000].
c that: 'one composed plan gives identical results on 8 actors at once'
  is: { expected size. got allSatisfy: [:each | each = expected] }
  equals: { 250. true }.

"test_explain_computes_each_estimate_once: one explain reads each node's estimate once; the memo
 lives for one explain."
leaf := CountingPlan items: #(1 2 3).
counted := PBCountPlan source: (PBLimit source: (PBSort source: (PBFilter source: (PBProject source: leaf fields: [:x | x])
  terms: { PBTerm path: nil op: '>' value: 0 }) keys: { PBSortKey key: nil descending: false }) limit: 2 offset: 0).
r1 := OrderedCollection new.
[PBNotation describe: counted explain] value.
r1 add: leaf calls.
counted explain.
r1 add: leaf calls.
counted estimate.
r1 add: leaf calls.
c that: 'one explain computes each estimate once'
  is: { r1 asArray. counted execute }
  equals: { #(1 2 3). #(2) }.

"test_limit_over_a_window_does_not_run_the_producer: a Limit served by rank produces no row
 before its window; without rank it produces them."
bigIndex := (PBRangeIndex name: 'k' path: 'k') build: ((0 to: 999) asArray collect: [:j | PBFrozenDict withAssociations: { 'k' -> j }]).
inner := bigIndex orderedPlan: (PBKeySpec path: 'k') descending: false.
produced := OrderedCollection new.
bigRank := [:aRank | PBLimit source: (PBIndexPlan index: bigIndex term: nil part: (PBIndexPart kind: 'IndexOrderedScan'
    producer: [:each | inner do: [:e | produced add: e. each value: e]] estimate: inner estimate details: nil
    rank: aRank sortedRank: nil)) limit: 3 offset: 900].
part := (bigRank value: (PBRankAccess segments: [bigIndex _orderedSegments: false])) execute collect: [:e | e at: 'k'].
r1 := { part. produced size }.
part := (bigRank value: nil) execute collect: [:e | e at: 'k'].
c that: 'a Limit served by rank produces no row before its window'
  is: r1 , { part. produced size }
  equals: { #(900 901 902). 0. #(900 901 902). 903 }.

"test_a_subclass_redefining_elements_is_not_windowed (proto_db's window(0, 2) is None reads byRank
 false here: windowFrom:to: answers the rows through do: when the plan cannot seek)."
odd := (OddList new extend: (0 to: 5) asArray) asQueryPlan.
c that: 'a collection whose class redefines do: offers no window'
  is: { odd byRank. odd exactRows. (odd windowFrom: 0 to: 2). (PBLimit source: odd limit: 2 offset: 1) execute.
    (PBList new extend: (0 to: 5) asArray) asQueryPlan byRank }
  equals: { false. nil. #(1 3). #(3 5). true }.

"test_python_filter_is_explicit_and_never_swallows: a BlockFilter explains its description, an error
 its block raises (here a number compared with a missing field's nil) propagates from execute,
 never an empty answer, and a predicate that is not a
 block of one argument with a non-empty description, or not a PBBlockPredicate, is refused."
plan := PBBlockFilter source: scan predicate: (PBBlockPredicate block: [:p | (p at: 'name') last = $7] description: 'name ends with 7').
r1 := PBBlockFilter source: scan predicate: (PBBlockPredicate block: [:p | (p at: 'no such field') > 1] description: 'boom').
c that: 'a BlockFilter is explicit and never swallows an error of its block'
  is: { plan explain at: 'plan'. plan explain at: 'description'.
    (plan execute collect: [:p | p at: 'name']) = ((people select: [:p | (p at: 'name') last = $7]) collect: [:p | p at: 'name']).
    [r1 execute. #swallowed] on: Error do: [:e | e return: #raised].
    [PBBlockPredicate block: 'nope' description: 'x'. nil] on: PBValidationError do: [:e | e return: #refused].
    [PBBlockPredicate block: [:p | true] description: ''. nil] on: PBValidationError do: [:e | e return: #refused].
    [PBBlockFilter source: scan predicate: [:p | true]. nil] on: PBValidationError do: [:e | e return: #refused] }
  equals: { 'BlockFilter'. 'name ends with 7'. true. #raised. #refused. #refused. #refused }.

"test_sort_and_group_by_label_each_callable, its Sort half: every sort key carries its own label
 (a path its path, a block 'block' or its description), so proto_db's 'exactly one callable'
 ambiguity cannot arise. Its GroupBy half is not ported: spec 3.2 defers GroupBy."
plan := PBSort source: scan keys: { PBSortKey key: [:p | p at: 'name'] descending: false.
  PBSortKey key: [:p | (p hasDefinedAttr: 'city') ifTrue: [(p at: 'city') ifNil: ['']] ifFalse: ['']] descending: true description: 'city or empty'.
  PBSortKey key: 'age' descending: true }.
c that: 'each sort key is labelled on its own: a path, a described block, or block (the GroupBy half is spec 3.2)'
  is: { ((plan explain at: 'keys') asArray collect: [:k | k at: 'key']) asArray.
    ((plan explain at: 'keys') asArray collect: [:k | k at: 'descending']) asArray.
    (plan execute collect: [:p | p at: 'name']) = ((people asSortedCollection: [:a :b | (a at: 'name') <= (b at: 'name')]) asArray collect: [:p | p at: 'name']) }
  equals: { #('block' 'city or empty' 'age'). #(false true true). true }.

c report displayNl.
