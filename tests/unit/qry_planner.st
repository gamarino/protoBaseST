"EXPECT: ok 16"
"Indexed queries, plan Task 7: PBPlanner (proto_db proto_db/query/planner.py at v2.0.0rc4, less the
 near[] rules). The behaviours of proto_db's tests/unit/test_planner.py that apply (the near[] tests
 are excluded by spec 3.3; the property is tests/unit/qry_prop_equals_scan.st), over its data: 200
 records with x unique 0..199, z = x mod 10, name 'n<x>' and y = x mod 4, y absent from every tenth.
 Every plan is checked as test_planner.py's check does: its rows equal the scan oracle's (QData scan:
 over evaluate:) as a multiset, twice, and its explain's estimate is its estimate. Then two checks of
 this port: an index the planner cannot consult (an opaque atom of an unknown kind, a vector index)
 is skipped, and a collection whose extractor index names an unregistered extractor answers by the
 index while a scan or a residual filter on the extractor signals PBValidationError naming it
 (Review Focus 5). Mapped in tests/unit/queries_checklist.tsv."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.

"An equality index estimating a full pass (proto_db's tests/support/scan_index.py ScanIndex: rows =
 cost = n), so an index named after it but cheaper wins (test_cheaper_index_wins_over_a_dearer_one)."
PBEqualityIndex subclass: #ScanCostIndex.

ScanCostIndex >> estimate: aTerm
  self _checkSupported: aTerm.
  ^ PBEstimate rows: self count cost: self count.

| c desc recs records t t1 plan p bad check names find missing keysOf sortedKeys info expr residual x y z
  coll a b r mixed d1 items got opaque vector set base withBad onlyBad kids walk plans u v1 v2 v3 plan2 lower
  idx unreg row |
c := Check new.
missing := PBMissing default.
d1 := Decimal fromString: '1'.
recs := (0 to: 199) asArray collect: [:i |
  PBObject withAll: { 'x' -> i. 'z' -> (i \\ 10). 'name' -> ('n' , i printString) }
    , (i \\ 10 = 0 ifTrue: [#()] ifFalse: [{ 'y' -> (i \\ 4) }])].
records := [:indexes | indexes inject: (PBList new extend: recs) into: [:acc :each | acc addIndex: each]].
t := [:path :op :value | PBTerm path: path op: op value: value].
t1 := [:path :op | PBTerm path: path op: op].
x := [:op :value | t value: 'x' value: op value: value].
y := [:op :value | t value: 'y' value: op value: value].
z := [:op :value | t value: 'z' value: op value: value].
plan := [:source :where :keys :limit :offset | PBPlanner plan: source where: where orderBy: keys limit: limit offset: offset].
p := [:source :where | plan value: source value: where value: nil value: nil value: 0].
bad := OrderedCollection new.
"The describe of an expression as explain freezes it (its lists are PBFrozenLists)."
desc := [:anExpr | PBQueryPlan _frozen: anExpr describe].
"test_planner.py check: the plan answers the scan's multiset, twice, and explains with its own
 estimate; answers the explain."
check := [:aPlan :aCollection :anExpr | | expected |
  expected := QData scan: aCollection where: [:e | anExpr isNil or: [anExpr evaluate: e]].
  ((QData bagOf: aPlan execute) = expected and: [(QData bagOf: aPlan execute) = expected]) ifFalse: [
    bad add: 'rows of ' , anExpr printString].
  (aPlan explain at: 'estimate') = aPlan estimate describe ifFalse: [bad add: 'estimate of ' , anExpr printString].
  aPlan explain].
names := nil.
names := [:anInfo | | out |
  out := OrderedCollection with: (anInfo at: 'plan').
  (anInfo at: 'children') do: [:kid | out addAll: (names value: kid)].
  out asArray].
"The keys of path aPath in the rows of aPlan, PBMissing as #missing."
keysOf := [:aPlan :aPath | aPlan execute collect: [:e | | k |
  k := (PBKeySpec forTermPath: aPath) extract: e.
  k == missing ifTrue: [#missing] ifFalse: [k]]].
"The key tuples of anArray's paths in the rows of a Sort over a filtered scan (test_planner.py sorted_keys)."
sortedKeys := [:aCollection :anExpr :aKeys | | src |
  src := anExpr isNil ifTrue: [aCollection asQueryPlan] ifFalse: [PBFilter source: aCollection asQueryPlan terms: anExpr].
  (PBSort source: src keys: aKeys) execute collect: [:e | aKeys collect: [:k | | v |
    v := k extract: e. v == missing ifTrue: [#missing] ifFalse: [v]]]].

"=== sources and arguments ==="
coll := records value: { PBEqualityIndex name: 'by_x' path: 'x' }.
r := { p value: coll value: nil.
  p value: coll asQueryPlan value: (x value: '==' value: 7).
  p value: (PBLimit source: coll asQueryPlan limit: 50 offset: 0) value: (x value: '==' value: 7).
  p value: coll value: { 'x'. '=='. 3. 'z'. '<'. 5 } }.
check value: (r at: 1) value: coll value: nil.
check value: (r at: 2) value: coll value: (x value: '==' value: 7).
info := check value: (r at: 4) value: coll value: ((x value: '==' value: 3) & (z value: '<' value: 5)).
c that: 'no condition is the scan itself; a scan source and the list syntax use the indexes; another plan gets a Filter'
  is: { (r at: 1) class. (r at: 1) collection == coll.
    (r at: 2) class. (r at: 2) index == (coll getIndex: 'by_x').
    (r at: 3) class. (r at: 3) source class. ((r at: 3) execute collect: [:e | e at: 'x']). (r at: 3) predicate = (x value: '==' value: 7).
    info at: 'plan'. (info at: 'predicate') = (desc value: (z value: '<' value: 5)). bad asArray }
  equals: { PBCollectionScan. true. PBIndexPlan. true. PBFilter. PBLimit. #(7). true. 'Filter'. true. #() }.

coll := records value: #().
c that: 'malformed arguments are PBValidationError (test_invalid_arguments_raise)'
  is: ({ [p value: #(1 2 3) value: nil]. [p value: coll value: 'x == 1']. [p value: PBList value: nil].
      [plan value: coll value: nil value: 5 value: nil value: 0].
      [plan value: coll value: nil value: #() value: nil value: 0].
      [plan value: coll value: nil value: #('x') value: nil value: 0].
      [plan value: coll value: nil value: { PBSortKey key: 'x' descending: false. 3 } value: nil value: 0].
      [plan value: coll value: nil value: nil value: -1 value: 0].
      [plan value: coll value: nil value: nil value: 1.5 value: 0].
      [plan value: coll value: nil value: nil value: true value: 0].
      [plan value: coll value: nil value: nil value: 1 value: -1].
      [plan value: coll value: nil value: nil value: nil value: nil].
      [plan value: coll value: nil value: nil value: 1 value: 1/2].
      [PBPlanner normalize: 'x'] }
    collect: [:each | [each value. #accepted] on: PBValidationError do: [:e | e return: #refused]])
  equals: ((1 to: 14) asArray collect: [:i | #refused]).

"=== access path selection ==="
coll := records value: { PBEqualityIndex name: 'by_y' path: 'y'. PBEqualityIndex name: 'by_x' path: 'x'. PBRangeIndex name: 'by_z' path: 'z' }.
expr := PBAnd withAll: { y value: '==' value: 1. z value: '==' value: 3. x value: 'in' value: #(3 13 23 4) }.
r := p value: coll value: expr.
info := check value: r value: coll value: expr.
a := records value: { ScanCostIndex name: 'a_scan' path: 'x'. PBEqualityIndex name: 'b_eq' path: 'x' }.
b := records value: { PBRangeIndex name: 'm_range' path: 'x'. PBEqualityIndex name: 'k_eq' path: 'x'. PBEqualityIndex name: 'z_eq' path: 'x' }.
u := records value: { PBEqualityIndex name: 'by_z' path: 'z' }.
"Equal cost: the full-pass index plus a residual filter costs n + n, as the scan and its filter do."
v1 := records value: { ScanCostIndex name: 'a_scan' path: 'x' }.
c that: 'the cheapest index answers and the rest stays residual; a dearer index loses; ties go to the smaller name; != uses the complement; on equal cost an index plan beats the scan'
  is: { info at: 'plan'. (info at: 'predicate') = (desc value: ((y value: '==' value: 1) & (z value: '==' value: 3))).
    (((info at: 'children') at: 1) at: 'plan'). ((((info at: 'children') at: 1) at: 'index') at: 'index').
    r execute collect: [:e | e at: 'x'].
    ((p value: a value: (x value: '==' value: 5)) explain at: 'index') at: 'index'.
    ((b getIndex: 'm_range') estimate: (x value: '==' value: 5)) = ((b getIndex: 'k_eq') estimate: (x value: '==' value: 5)).
    (1 to: 3) asArray collect: [:i | ((p value: b value: (x value: '==' value: 5)) explain at: 'index') at: 'index'].
    (check value: (p value: u value: (z value: '!=' value: 3)) value: u value: (z value: '!=' value: 3)) at: 'plan'.
    (p value: v1 value: (x value: '==' value: 5) & (z value: '<' value: 8)) estimate cost.
    names value: (p value: v1 value: (x value: '==' value: 5) & (z value: '<' value: 8)) explain.
    bad asArray }
  equals: { 'Filter'. true. 'IndexLookup'. 'by_x'. #(13). 'b_eq'. true. #('k_eq' 'k_eq' 'k_eq'). 'IndexComplement'.
    400.0. #('Filter' 'IndexLookup'). #() }.

coll := records value: { PBEqualityIndex name: 'by_x' path: 'x' }.
residual := { t value: 'name' value: 'contains' value: '1'. t1 value: 'z' value: '?T'. (y value: '<' value: 2) not. t1 value: 'z' value: '?!T' }.
expr := PBAnd withAll: { residual first. x value: 'in' value: (0 to: 199 by: 7) asArray } , (residual copyFrom: 2 to: 4).
info := check value: (p value: coll value: expr) value: coll value: expr.
expr := PBAnd withAll: { x value: '==' value: 5. z value: '<' value: 8. x value: '==' value: 5.0. z value: '<' value: 8 }.
a := check value: (p value: coll value: expr) value: coll value: expr.
expr := (x value: '==' value: 5) & (z value: '<' value: 8).
b := check value: (p value: (records value: #()) value: expr) value: (records value: #()) value: expr.
c that: 'every unindexed conjunct is kept in order; duplicate conjuncts are planned once; no index is a scan and a filter'
  is: { (info at: 'predicate') = (desc value: (PBAnd withAll: residual)). names value: info.
    a at: 'plan'. (a at: 'predicate') = (desc value: (z value: '<' value: 8)).
    names value: b. (b at: 'predicate') = (desc value: expr). bad asArray }
  equals: { true. #('Filter' 'IndexLookup'). 'Filter'. true. #('Filter' 'CollectionScan'). true. #() }.

"=== disjunctions ==="
coll := records value: { PBEqualityIndex name: 'by_x' path: 'x'. PBRangeIndex name: 'by_z' path: 'z' }.
expr := PBOr withAll: { x value: '==' value: 5. (z value: '==' value: 3) & (y value: '==' value: 1). x value: 'in' value: #(6 7) }.
info := check value: (p value: coll value: expr) value: coll value: expr.
a := records value: { PBEqualityIndex name: 'by_x' path: 'x' }.
plans := { (x value: '==' value: 5) | (z value: '==' value: 3). (x value: '==' value: 5) | (x value: '<' value: 190) not } collect: [:e |
  check value: (p value: a value: e) value: a value: e].
b := records value: { PBEqualityIndex name: 'by_z' path: 'z' }.
expr := PBOr withAll: ((0 to: 9) asArray collect: [:i | z value: '==' value: i]).
u := check value: (p value: b value: expr) value: b value: expr.
expr := (z value: '<' value: 9) & ((x value: '==' value: 5) | (x value: '==' value: 9)).
r := check value: (p value: a value: expr) value: a value: expr.
c that: 'a disjunction is a Union only when every branch has an index plan and it is cheaper; an Or conjunct is an access path'
  is: { info at: 'plan'. (info at: 'children') asArray collect: [:kid | kid at: 'plan'].
    ((info at: 'children') at: 2) at: 'predicate'.
    names value: plans first. (plans first at: 'predicate') = (desc value: ((x value: '==' value: 5) | (z value: '==' value: 3))).
    names value: plans last. names value: u.
    r at: 'plan'. (r at: 'predicate') = (desc value: (z value: '<' value: 9)). (((r at: 'children') at: 1) at: 'plan'). bad asArray }
  equals: { 'Union'. #('IndexLookup' 'Filter' 'IndexLookup'). (y value: '==' value: 1) describe.
    #('Filter' 'CollectionScan'). true. #('Filter' 'CollectionScan'). #('Filter' 'CollectionScan').
    'Filter'. true. 'Union'. #() }.

a := PBObject withAll: { 'k' -> 1. 't' -> 'p' }.
b := PBObject withAll: { 'k' -> 2. 't' -> 'q' }.
u := PBObject withAll: { 'k' -> 1. 't' -> 'q' }.
coll := ((PBList new extend: { a. a. b. u. u. u. b } , ((1 to: 100) asArray collect: [:i | PBObject withAll: { 'k' -> 9. 't' -> 'z' }]))
  addIndex: (PBEqualityIndex name: 'by_k' path: 'k')) addIndex: (PBEqualityIndex name: 'by_t' path: 't').
plans := { (t value: 'k' value: '==' value: 1) | (t value: 't' value: '==' value: 'q').
  (t value: 'k' value: '==' value: 1) | (t value: 't' value: '==' value: 'p').
  (t value: 'k' value: '==' value: 2) | (t value: 't' value: '==' value: 'zz') } collect: [:e | | q |
  q := p value: coll value: e.
  check value: q value: coll value: e.
  q class].
got := QData bagOf: (p value: coll value: (t value: 'k' value: '==' value: 1) | (t value: 't' value: '==' value: 'q')) execute.
c that: 'a Union keeps List duplicates exactly'
  is: { plans. (got values asArray asSortedCollection: [:m :n | m <= n]) asArray. bad asArray }
  equals: { { PBUnion. PBUnion. PBUnion }. #(2 2 3). #() }.

"=== negation ==="
a := x value: '==' value: 1.
b := y value: '<' value: 2.
c that: 'normalize: pushes negations by De Morgan and rewrites only not ?N and not ?!N'
  is: { PBPlanner normalize: (a & b) not. PBPlanner normalize: (a | b) not.
    PBPlanner normalize: (t1 value: 'x' value: '?N') not. PBPlanner normalize: (t1 value: 'x' value: '?!N') not.
    PBPlanner normalize: (PBNot of: (PBNot of: a)). PBPlanner normalize: a not. PBPlanner normalize: (t1 value: 'x' value: '?T') not.
    PBPlanner normalize: (a & (b & (a | (t1 value: 'x' value: '?N')) not)) }
  equals: { PBOr withAll: { a not. b not }. PBAnd withAll: { a not. b not }.
    t1 value: 'x' value: '?!N'. t1 value: 'x' value: '?N'. a. PBNot of: a. PBNot of: (t1 value: 'x' value: '?T').
    PBAnd withAll: { a. b. a not. t1 value: 'x' value: '?!N' } }.

coll := records value: { PBRangeIndex name: 'by_y' path: 'y'. PBEqualityIndex name: 'by_x' path: 'x' }.
info := check value: (p value: coll value: (t1 value: 'y' value: '?!N') not) value: coll value: (t1 value: 'y' value: '?!N') not.
expr := (x value: 'in' value: #(0 1 2 3 10)) & (y value: '==' value: 1) not.
r := p value: coll value: expr.
a := check value: r value: coll value: expr.
coll := records value: { PBEqualityIndex name: 'by_x' path: 'x' }.
expr := ((x value: '>=' value: 0) & (y value: '==' value: 1)) not.
b := check value: (p value: coll value: expr) value: coll value: expr.
coll := records value: { PBEqualityIndex name: 'by_y' path: 'y'. PBEqualityIndex name: 'by_x' path: 'x' }.
expr := ((t1 value: 'y' value: '?N') | (t1 value: 'x' value: '?!N')) not.
u := check value: (p value: coll value: expr) value: coll value: expr.
c that: 'not presence uses the index, a negated comparison stays residual, not over and scans, not over or of presence terms is indexed'
  is: { info at: 'plan'. (info at: 'term') at: 'op'. a at: 'plan'. (a at: 'predicate') = (y value: '==' value: 1) not describe.
    ((r execute collect: [:e | e at: 'x']) asSortedCollection: [:m :n | m <= n]) asArray.
    b at: 'plan'. (b at: 'predicate') = (desc value: (PBPlanner normalize: ((x value: '>=' value: 0) & (y value: '==' value: 1)) not)).
    (names value: u) includes: 'CollectionScan'. bad asArray }
  equals: { 'IndexLookup'. '?N'. 'Filter'. true. #(0 2 3 10). 'Filter'. true. false. #() }.

"=== equal-but-distinct and odd values ==="
mixed := { true. 1. 1.0. d1. Decimal fromString: '1.00'. (10 raisedTo: 16) + 1. 10 raisedTo: 16. nil. 0. false. '1'. 2.5 }.
got := { PBEqualityIndex. PBRangeIndex } collect: [:kind | | e |
  coll := (PBList new extend: mixed , (mixed copyFrom: 1 to: 4)) addIndex: (kind name: 'e' keySpec: PBKeySpec element).
  e := [:op :v | t value: nil value: op value: v].
  { e value: '==' value: 1. e value: '==' value: true. e value: 'in' value: { true. (10 raisedTo: 16) + 1 }.
    e value: '!=' value: 1. t1 value: nil value: '?N'. (e value: '==' value: 1) | (e value: '==' value: false).
    (t1 value: nil value: '?!N') & (e value: '==' value: 1) not. e value: '==' value: (10 raisedTo: 16) } do: [:each |
    check value: (p value: coll value: each) value: coll value: each].
  (QData bagOf: (p value: coll value: (e value: '==' value: 1)) execute) = (QData bagOf: { 1. 1.0. d1. Decimal fromString: '1.00'. 1. 1.0. d1 })].
items := (mixed collect: [:each | PBObject withAll: { 'v' -> each }]) , { PBObject withAll: { 'w' -> 1 }. PBObject withAll: #(). PBObject withAll: { 'v' -> nil } }.
coll := (PBList new extend: items) addIndex: (PBRangeIndex name: 'by_v' path: 'v').
{ t value: 'v' value: '>=' value: 1. t value: 'v' value: '<' value: (10 raisedTo: 16) + 1. t value: 'v' value: 'between[]' value: #(0 1).
  t1 value: 'v' value: '?N'. (t value: 'v' value: '==' value: 1) not. t value: 'v' value: '!=' value: nil.
  (t1 value: 'v' value: '?N') | (t value: 'v' value: '>' value: 2) } do: [:each |
  check value: (p value: coll value: each) value: coll value: each].
c that: 'equal-but-distinct values stay apart, by element and by path, PBMissing and nil included'
  is: { got. (p value: coll value: (t1 value: 'v' value: '?N')) execute size. bad asArray }
  equals: { #(true true). 4. #() }.

"=== order, limit and offset ==="
coll := records value: { PBRangeIndex name: 'by_y' path: 'y' }.
r := #(false true) collect: [:desc | | q |
  q := plan value: coll value: nil value: { PBSortKey key: 'y' descending: desc } value: nil value: 0.
  info := check value: q value: coll value: nil.
  { info at: 'plan'. info at: 'descending'.
    (keysOf value: q value: 'y') = ((sortedKeys value: coll value: nil value: { PBSortKey key: 'y' descending: desc }) collect: [:k | k first]) }].
expr := z value: '<' value: 8.
a := plan value: coll value: expr value: { PBSortKey key: 'y' descending: false } value: nil value: 0.
info := check value: a value: coll value: expr.
b := records value: { PBEqualityIndex name: 'by_y' path: 'y' }.
u := plan value: b value: nil value: { PBSortKey key: 'y' descending: true } value: nil value: 0.
v1 := plan value: coll value: nil value: { PBSortKey key: 'y' descending: false. PBSortKey key: 'x' descending: true } value: nil value: 0.
c that: 'a range index orders both ways, under the whole condition as a filter; without one, or for two keys, a Sort'
  is: { r. names value: info.
    (keysOf value: a value: 'y') = ((sortedKeys value: coll value: expr value: { PBSortKey key: 'y' descending: false }) collect: [:k | k first]).
    (check value: u value: b value: nil) at: 'plan'. (u explain at: 'keys') = (PBFrozenList withAll: { PBFrozenDict withAssociations: { 'key' -> 'y'. 'descending' -> true } }).
    (keysOf value: u value: 'y') = ((sortedKeys value: b value: nil value: { PBSortKey key: 'y' descending: true }) collect: [:k | k first]).
    (check value: v1 value: coll value: nil) at: 'plan'.
    (v1 execute collect: [:e | { (keysOf value: (PBCollectionScan on: (PBList new appendLast: e)) value: 'y') first. e at: 'x' }])
      = (sortedKeys value: coll value: nil value: { PBSortKey key: 'y' descending: false. PBSortKey key: 'x' descending: true }).
    bad asArray }
  equals: { { { 'IndexOrderedScan'. false. true }. { 'IndexOrderedScan'. true. true } }. #('Filter' 'IndexOrderedScan'). true.
    'Sort'. true. true. 'Sort'. true. #() }.

coll := records value: { PBRangeIndex name: 'by_y' path: 'y'. PBEqualityIndex name: 'by_x' path: 'x' }.
expr := x value: 'in' value: #(5 6 7).
a := check value: (plan value: coll value: expr value: { PBSortKey key: 'y' descending: false } value: nil value: 0) value: coll value: expr.
coll := records value: { PBRangeIndex name: 'by_x' path: 'x' }.
b := check value: (plan value: coll value: (x value: '<' value: 5) value: { PBSortKey key: 'x' descending: true } value: nil value: 0)
  value: coll value: (x value: '<' value: 5).
u := plan value: coll value: (x value: '>=' value: 0) value: { PBSortKey key: 'x' descending: true } value: nil value: 0.
c that: 'a selective condition then a Sort beats an ordered scan; on one key, the cost decides'
  is: { names value: a. names value: b. names value: (check value: u value: coll value: (x value: '>=' value: 0)).
    (keysOf value: u value: 'x') = (199 to: 0 by: -1) asArray. bad asArray }
  equals: { #('Sort' 'IndexLookup'). #('Sort' 'IndexRange'). #('Filter' 'IndexOrderedScan'). true. #() }.

a := plan value: coll value: (z value: '==' value: 3) value: { PBSortKey key: 'x' descending: true } value: 3 value: 2.
b := plan value: coll value: nil value: { PBSortKey key: 'x' descending: false } value: nil value: 197.
c that: 'limit and offset apply after the order'
  is: { a explain at: 'plan'. a explain at: 'limit'. a explain at: 'offset'. keysOf value: a value: 'x'.
    b explain at: 'limit'. keysOf value: b value: 'x'.
    (plan value: coll value: nil value: nil value: nil value: 0) class.
    keysOf value: (plan value: coll value: nil value: { PBSortKey key: 'x' descending: false } value: 0 value: 0) value: 'x' }
  equals: { 'Limit'. 3. 2. #(173 163 153). nil. #(197 198 199). PBCollectionScan. #() }.

"=== explain is the node tree; planning is per version ==="
coll := records value: { PBEqualityIndex name: 'by_x' path: 'x'. PBRangeIndex name: 'by_z' path: 'z'. PBRangeIndex name: 'by_y' path: 'y' }.
kids := [:node |
  (node isKindOf: _PBOneSourcePlan) ifTrue: [{ node source }] ifFalse: [
    (node isKindOf: _PBSetPlan) ifTrue: [node sources] ifFalse: [#()]]].
walk := nil.
walk := [:node :anInfo |
  (node explain at: 'plan') = (anInfo at: 'plan') and: [
    (kids value: node) size = (anInfo at: 'children') size and: [
      ((1 to: (kids value: node) size) asArray allSatisfy: [:i | walk value: ((kids value: node) at: i) value: ((anInfo at: 'children') at: i)])]]].
plans := {
  { (x value: 'in' value: #(1 2 3)) & (t value: 'name' value: 'contains' value: '2'). nil. nil }.
  { (x value: '==' value: 4) | ((z value: '==' value: 3) & (y value: '==' value: 1)). nil. nil }.
  { z value: '>=' value: 0. { PBSortKey key: 'z' descending: true }. 7 }.
  { (x value: '==' value: 4) | (t value: 'name' value: '==' value: 'n5'). { PBSortKey key: 'y' descending: false. PBSortKey key: 'x' descending: true }. 4 } }
  collect: [:case | | q |
    q := plan value: coll value: (case at: 1) value: (case at: 2) value: (case at: 3) value: 0.
    { walk value: q value: q explain. q explain = q explain. (check value: ((case at: 3) isNil ifTrue: [q] ifFalse: [q source]) value: coll value: (case at: 1)) notNil }].
c that: 'explain is exactly the node tree the plan runs, and is deterministic'
  is: { plans. bad asArray } equals: { (1 to: 4) asArray collect: [:i | #(true true true)]. #() }.

v1 := records value: { PBEqualityIndex name: 'by_x' path: 'x' }.
expr := x value: '==' value: 500.
v2 := v1 appendLast: (PBObject withAll: { 'x' -> 500 }).
plan2 := p value: v2 value: expr.
v3 := v2 removeIndex: 'by_x'.
c that: 'planning is per version: a plan keeps answering for its version'
  is: { (p value: v1 value: expr) execute. plan2 execute collect: [:e | e at: 'x']. (p value: v1 value: expr) execute.
    names value: (p value: v3 value: expr) explain. plan2 execute collect: [:e | e at: 'x'] }
  equals: { #(). #(500). #(). #('Filter' 'CollectionScan'). #(500) }.

"=== this port: indexes the planner cannot consult (plan Task 6 review) ==="
opaque := PBOpaqueAtom named: 'acme.indexing.CustomIndex' unloadedAt: (PBAtomPointer segment: (ByteArray new: 16) offset: 1) storage: Object new.
vector := PBVectorIndex _unsavedWithState: (PBFrozenDict withAssociations: {
  'name' -> 'b_vec'. 'key_spec' -> (PBTuple withAll: #('path' 'x')). 'dim' -> 2. 'metric' -> 'l2'. 'backend' -> 'flat'.
  'params' -> nil. 'store' -> nil. 'invalid' -> nil. 'total_count' -> 0. 'centroids' -> (PBTuple withAll: #()).
  'trained_size' -> 0. 'member_tokens' -> 1 }).
"aCollection with the opaque index 'a_custom' and the vector index 'b_vec' added to its index set."
withBad := [:aCollection | | set2 |
  set2 := aCollection indexes.
  set2 := set2 _withRoot: ((PBAvl keyPut: (set2 stateAt: 'root') key: 'a_custom' value: opaque nodeClass: PBKeyNode) at: 1).
  set2 := set2 _withRoot: ((PBAvl keyPut: (set2 stateAt: 'root') key: 'b_vec' value: vector nodeClass: PBKeyNode) at: 1).
  aCollection _withChanges: { 'indexes' -> set2 }].
base := withBad value: (records value: { PBRangeIndex name: 'c_x' path: 'x' }).
onlyBad := withBad value: (records value: #()).
expr := x value: '==' value: 7.
r := { p value: base value: expr. p value: onlyBad value: expr.
  plan value: base value: (x value: '<' value: 3) value: { PBSortKey key: 'x' descending: true } value: nil value: 0.
  plan value: onlyBad value: (x value: '<' value: 3) value: { PBSortKey key: 'x' descending: true } value: nil value: 0 }.
check value: (r at: 1) value: base value: expr.
check value: (r at: 2) value: onlyBad value: expr.
c that: 'an opaque index and a vector index are skipped: another index or a scan answers'
  is: { base indexNames. names value: (r at: 1) explain. ((r at: 1) explain at: 'index') at: 'index'. names value: (r at: 2) explain.
    (r at: 2) execute collect: [:e | e at: 'x']. (r at: 3) execute collect: [:e | e at: 'x']. names value: (r at: 4) explain.
    (r at: 4) execute collect: [:e | e at: 'x']. bad asArray }
  equals: { #('a_custom' 'b_vec' 'c_x'). #('IndexLookup'). 'c_x'. #('Filter' 'CollectionScan'). #(7). #(2 1 0).
    #('Sort' 'Filter' 'CollectionScan'). #(2 1 0). #() }.

"=== this port: an unregistered extractor (Review Focus 5) ==="
PBKeySpec registerExtractor: 'qry_planner.name' block: [:e | (PBKeySpec path: 'name') extract: e] version: '1'.
idx := records value: { PBEqualityIndex name: 'by_name' keySpec: (PBKeySpec extractor: 'qry_planner.name') }.
lower := t value: '@qry_planner.name' value: '==' value: 'n5'.
PBKeySpec unregisterExtractor: 'qry_planner.name'.
unreg := [:aBlock | [aBlock value. #answered] on: PBValidationError do: [:e |
  e return: ((e messageText includesSubstring: 'qry_planner.name') ifTrue: [#namesIt] ifFalse: [e messageText])]].
row := p value: idx value: lower.
c that: 'unregistered extractor: lookup runs, scan signals'
  is: { row explain at: 'plan'. row execute collect: [:e | e at: 'x'].
    unreg value: [(p value: (records value: #()) value: lower) execute].
    unreg value: [(p value: idx value: lower & (t value: '@qry_planner.name' value: 'contains' value: '5')) execute] }
  equals: { 'IndexLookup'. #(5). #namesIt. #namesIt }.

c report displayNl.
