"EXPECT: ok 15"
"Indexed queries, plan Task 8: PBQuery, the immutable query front end (proto_db
 proto_db/query/linq.py at v2.0.0rc4, Queryable and the predicate mixing rule, lines 169-358 and
 906-1189, less group_by, join, select_many, computed values, ValuesScan and the cache, deferred by
 spec 3.2, and near, excluded by 3.3). The behaviours of proto_db's tests/unit/test_linq.py that
 apply, over its data: 600 records (proto_db: 2000) with id 1..600, category 'c0'..'c49', status
 's0'..'s29' and value 0..100000 drawn from QData random: 123, indexed by_id, by_category,
 by_status (equality) and by_value (range); USERS, AGES and PRODUCTS as maps in a PBList (proto_db:
 Python lists, a ValuesScan here a CollectionScan). Node names are proto_db's, with BlockFilter for
 PythonFilter (call IC6); every explain is checked equal to the explain of the plan that runs
 (test_linq.py explained). Then this port's own cases: the cascade does not chain, a query keeps
 the version it was built from (Review Focus 3), chained where: is AND (ruling CR5), where:'s exact
 refusal text (ruling CR6), and PBQuery does not understand select: (ruling IQ2). Mapped in
 tests/unit/queries_checklist.tsv."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.

Error subclass: #Boom.

| c data rows coll q bad names find ids bag explained users ages products listOf id category status value
  target cats cat st c1 c2 r info lam lam1 lam2 lam3 blk refusal boom outcomes field before cascaded kept
  dir space db tr people old fresh rnd ref element mixed d1 out emails dict ten evens scores top3 |
c := Check new.
bad := OrderedCollection new.
names := nil.
names := [:anInfo | | acc |
  acc := OrderedCollection with: (anInfo at: 'plan').
  (anInfo at: 'children') do: [:kid | acc addAll: (names value: kid)].
  acc asArray].
find := nil.
find := [:anInfo :aName |
  (anInfo at: 'plan') = aName
    ifTrue: [anInfo]
    ifFalse: [((anInfo at: 'children') asArray collect: [:kid | find value: kid value: aName])
      detect: [:each | each notNil] ifNone: [nil]]].
ids := [:aRows | aRows asArray collect: [:each | each at: 'id']].
bag := [:aRows | QData bagOf: aRows asArray].
"test_linq.py explained: the query's explain is the explain of the plan that runs; answers it."
explained := [:aQuery | | e |
  e := aQuery explain.
  e = aQuery plan explain ifFalse: [bad add: 'explain of ' , aQuery printString].
  e].
listOf := [:anArray | PBList new extend: (anArray collect: [:assocs | PBFrozenDict withAssociations: assocs])].

data := QData spreadOn: 123.
rows := (1 to: 600) asArray collect: [:i |
  PBObject withAll: { 'id' -> i. 'category' -> ('c' , (data between: 0 and: 49) printString).
    'status' -> ('s' , (data between: 0 and: 29) printString). 'value' -> (data between: 0 and: 100000) }].
coll := { PBEqualityIndex name: 'by_id' path: 'id'. PBEqualityIndex name: 'by_category' path: 'category'.
    PBEqualityIndex name: 'by_status' path: 'status'. PBRangeIndex name: 'by_value' path: 'value' }
  inject: (PBList new extend: rows) into: [:acc :each | acc addIndex: each].
q := PBQuery from: coll.
id := PBField path: 'id'.
category := PBField path: 'category'.
status := PBField path: 'status'.
value := PBField path: 'value'.
users := listOf value: {
  { 'id' -> 1. 'first_name' -> 'Alice'. 'last_name' -> 'Zeus'. 'age' -> 30. 'country' -> 'ES'. 'status' -> 'active'. 'email' -> 'a@example.com'. 'last_login' -> 5 }.
  { 'id' -> 2. 'first_name' -> 'Bob'. 'last_name' -> 'Young'. 'age' -> 17. 'country' -> 'AR'. 'status' -> 'inactive'. 'email' -> 'b@example.com'. 'last_login' -> 10 }.
  { 'id' -> 3. 'first_name' -> 'Carol'. 'last_name' -> 'Xavier'. 'age' -> 25. 'country' -> 'US'. 'status' -> 'active'. 'email' -> 'c@example.com'. 'last_login' -> 2 }.
  { 'id' -> 4. 'first_name' -> 'Dan'. 'last_name' -> 'White'. 'age' -> 22. 'country' -> 'AR'. 'status' -> 'active'. 'email' -> 'd@example.com'. 'last_login' -> 7 } }.
ages := listOf value: ((1 to: 5) asArray collect: [:i | { 'id' -> i. 'age' -> (#(9 10 15 20 21) at: i) }]) , { { 'id' -> 6. 'age' -> nil } }.
products := listOf value: {
  { 'id' -> 1. 'category' -> 'A'. 'price' -> 10 }. { 'id' -> 2. 'category' -> 'A'. 'price' -> 20 }.
  { 'id' -> 3. 'category' -> 'B'. 'price' -> 5 }. { 'id' -> 4. 'category' -> 'B'. 'price' -> 5 }.
  { 'id' -> 5. 'category' -> 'A'. 'price' -> 10 }. { 'id' -> 6. 'category' -> 'C' } }.

"=== sources ==="
cat := (rows at: 8) at: 'category'.
r := { (PBQuery from: coll) asArray size.
  ((q where: (category eq: cat)) asArray size > 0) and: [
    (bag value: (q where: (category eq: cat)) asArray) = (QData scan: rows where: [:e | (e at: 'category') = cat])].
  (bag value: (q where: [:e | (e at: 'value') > 50000]) asArray) = (QData scan: rows where: [:e | (e at: 'value') > 50000]).
  (explained value: q) at: 'plan'.
  (explained value: ((PBQuery from: coll asQueryPlan) where: (id eq: 5))) at: 'plan'.
  names value: (explained value: ((PBQuery from: (PBLimit source: coll asQueryPlan limit: 10 offset: 0)) where: (id eq: 5))).
  ids value: ((PBQuery from: (PBLimit source: coll asQueryPlan limit: 10 offset: 0)) where: (id eq: 5)) asArray.
  (PBQuery from: q) == q.
  (PBQuery from: (q where: (id < 4))) explain = (q where: (id < 4)) explain.
  ids value: (PBQuery from: ((PBQuery from: users) where: ((PBField path: 'age') > 18))) asArray.
  { 'abc'. #(1 2). (PBFrozenDict withAssociations: #()). 5. nil. PBList. users asQueryPlan explain }
    collect: [:each | [PBQuery from: each. #accepted] on: PBValidationError do: [:e | e return: #refused]].
  bad asArray }.
"proto_db: test_sources_collection_plan_iterable_and_queryable,
 test_regression_linq_over_a_collection_returns_the_rows_not_an_empty_list,
 test_invalid_sources_raise, test_queryable_of_a_queryable_keeps_its_operators."
c that: 'sources: a collection, its scan, another plan or a query (answered as is); anything else is PBValidationError; a query over a collection answers its rows'
  is: r
  equals: { 600. true. true. 'CollectionScan'. 'IndexLookup'. #('Filter' 'Limit' 'CollectionScan'). #(5). true. true. #(1 3 4).
    (1 to: 7) asArray collect: [:i | #refused]. #() }.

"=== immutability ==="
q := PBQuery from: users.
before := q explain.
field := PBField path: 'age'.
r := { (q where: field > 18) == q. (q where: field > 18) class.
  ids value: (q where: field > 18) asArray.
  ids value: ((q where: field > 18) orderBy: field) asArray.
  ids value: (q where: field > 18) asArray.
  { q project: #('id'). q collect: [:u | u]. q skip: 1. q take: 1. q distinct. q orderBy: 'id'. q where: [:u | true].
    (q orderBy: 'id') thenBy: 'age'. q orderBy: 'id' descending: true. (q orderBy: 'id') thenBy: 'age' descending: true }
      collect: [:each | (each isKindOf: PBQuery) and: [each ~~ q]].
  q explain = before. ids value: q asArray }.
"proto_db: test_queryable_is_immutable."
c that: 'a query is immutable: every message answers a new query and leaves the receiver and its explain unchanged'
  is: r
  equals: { false. PBQuery. #(1 3 4). #(4 3 1). #(1 3 4). (1 to: 10) asArray collect: [:i | true]. true. #(1 2 3 4) }.

q := PBQuery from: coll.
before := q explain.
cascaded := q where: (category eq: cat); take: 5.
kept := (q where: (category eq: cat)) take: 5.
c that: 'the cascade does not chain: q where: p; take: 5 sends both to q and keeps only the take:'
  is: { names value: cascaded explain. cascaded asArray size. q explain = before. names value: kept explain. (ids value: kept asArray) = ((ids value: (q where: (category eq: cat)) asArray) copyFrom: 1 to: 5) }
  equals: { #('Limit' 'CollectionScan'). 5. true. #('Limit' 'IndexLookup'). true }.

"=== a query keeps its version (Review Focus 3) ==="
dir := 'out/qry_query' asFileReference / ('run-' , Smalltalk pid printString , '-' , Time microsecondClockValue printString).
dir ensureCreateDirectory.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'db'.
db run: [:t | t setRootObject: 'people' value: ((t newDictionary
    setAt: 1 value: (t newObject: { 'city' -> 'Oslo' }))
    addIndex: (PBEqualityIndex name: 'by_city' path: 'city'))].
tr := db newTransaction.
people := tr getRootObject: 'people'.
old := (PBQuery from: people) where: ((PBField path: 'city') eq: 'Oslo').
tr setRootObject: 'people' value: ((people setAt: 2 value: (tr newObject: { 'city' -> 'Oslo' })) setAt: 3 value: (tr newObject: { 'city' -> 'Oslo' })).
r := { old count. names value: old explain. ((PBQuery from: (tr getRootObject: 'people')) where: ((PBField path: 'city') eq: 'Oslo')) count }.
tr commit.
fresh := (PBQuery from: (db newTransaction getRootObject: 'people')) where: ((PBField path: 'city') eq: 'Oslo').
c that: 'query keeps its version: writes after it in the same transaction, and their commit, leave its answer; a new query sees them'
  is: r , { old count. old asArray size. fresh count }
  equals: { 1. #('Filter' 'CollectionScan'). 3. 1. 1. 3 }.
space close.

"=== the indexes answer (the 0.1 fast-path tests) ==="
q := PBQuery from: coll.
target := (rows at: 101) at: 'id'.
cats := { (rows at: 11) at: 'category'. (rows at: 21) at: 'category' }.
cat := (rows at: 6) at: 'category'.
st := (rows at: 8) at: 'status'.
c1 := (rows at: 16) at: 'category'.
c2 := (rows at: 26) at: 'category'.
r := OrderedCollection new.
info := explained value: (q where: (id eq: target)).
r add: { info at: 'plan'. (info at: 'index') at: 'index'. ids value: (q where: (id eq: target)) asArray }.
info := explained value: (q where: (category in: cats)).
r add: { info at: 'plan'. (info at: 'index') at: 'index'.
  (bag value: (q where: (category in: cats)) asArray) = (QData scan: rows where: [:e | cats includes: (e at: 'category')]) }.
info := explained value: (q where: (value betweenOpen: 1000 and: 20000)).
r add: { info at: 'plan'. (info at: 'index') at: 'index'.
  (bag value: (q where: (value betweenOpen: 1000 and: 20000)) asArray) = (QData scan: rows where: [:e | (e at: 'value') > 1000 and: [(e at: 'value') < 20000]]) }.
info := explained value: (q where: ((category eq: cat) & (status eq: st)) & (value between: 100 and: 90000)).
r add: { info at: 'plan'. #('IndexLookup' 'IndexRange') includes: (((info at: 'children') at: 1) at: 'plan').
  (bag value: (q where: ((category eq: cat) & (status eq: st)) & (value between: 100 and: 90000)) asArray)
    = (QData scan: rows where: [:e | (e at: 'category') = cat and: [(e at: 'status') = st and: [(e at: 'value') between: 100 and: 90000]]]) }.
info := explained value: (q where: (category eq: c1) | (category eq: c2)).
r add: { info at: 'plan'. ((names value: info) select: [:each | each = 'IndexLookup']) size.
  (bag value: (q where: (category eq: c1) | (category eq: c2)) asArray) = (QData scan: rows where: [:e | { c1. c2 } includes: (e at: 'category')]) }.
r add: bad asArray.
"proto_db: test_indexed_equality_uses_the_index, test_indexed_in_uses_the_index,
 test_indexed_between_uses_a_range_and_executes, test_indexed_and_uses_one_index_and_a_residual,
 test_indexed_or_uses_a_union."
c that: 'equality, in:, a between, an AND and an OR use their indexes and answer the scan''s rows'
  is: r asArray
  equals: { { 'IndexLookup'. 'by_id'. { target } }. #('IndexLookup' 'by_category' true). #('IndexRange' 'by_value' true).
    #('Filter' true true). #('Union' 2 true). #() }.

"=== chained where: is AND (ruling CR5) ==="
blk := [:e | (e at: 'value') odd].
r := { (explained value: ((q where: (status eq: 's3')) where: (id eq: 77))) = (q where: (status eq: 's3') & (id eq: 77)) explain.
  (find value: ((q where: (status eq: 's3')) where: (id eq: 77)) explain value: 'CollectionScan') isNil.
  (bag value: ((q where: (status eq: 's3')) where: (id eq: 77)) asArray) = (QData scan: rows where: [:e | (e at: 'status') = 's3' and: [(e at: 'id') = 77]]).
  ((q where: (category eq: cat)) where: (value > 50000)) explain = (q where: (category eq: cat) & (value > 50000)) explain.
  (bag value: ((q where: (category eq: cat)) where: (value > 50000)) asArray) = (bag value: (q where: (category eq: cat) & (value > 50000)) asArray).
  names value: ((q where: (category eq: cat)) where: blk) explain.
  names value: (q where: (category eq: cat) & (PBBlockPredicate block: blk description: 'block')) explain.
  (bag value: ((q where: blk) where: (category eq: cat)) asArray) = (QData scan: rows where: [:e | (e at: 'category') = cat and: [(e at: 'value') odd]]) }.
"proto_db: test_consecutive_wheres_are_merged_into_one_planned_predicate."
c that: 'chained where: is AND: (q where: a) where: b plans and answers as q where: a & b, a block included'
  is: r
  equals: { true. true. true. true. true. #('BlockFilter' 'IndexLookup'). #('BlockFilter' 'IndexLookup'). true }.

"=== what where: takes (ruling CR6) ==="
refusal := [:anArgument | [q where: anArgument. 'accepted'] on: PBValidationError do: [:e | e return: e messageText]].
r := { ids value: (q where: (PBTerm path: 'id' op: '==' value: 9)) asArray.
  (ids value: (q where: (PBExpression compile: #('id' '<' 4))) asArray) asSortedCollection asArray.
  refusal value: true.
  refusal value: [:a :b | a].
  refusal value: #('id' '<' 4).
  refusal value: 5.
  refusal value: nil.
  refusal value: [5].
  refusal value: (PBField path: 'id') }.
"proto_db: test_where_accepts_expressions_and_the_list_syntax."
c that: 'where: takes an expression or a one-argument block; anything else, the list syntax and a Boolean included, is PBValidationError with the CR6 text'
  is: r
  equals: { #(9). #(1 2 3).
    'where: expects a PBExpression or a one-argument block, got a Boolean'.
    'where: expects a PBExpression or a one-argument block, got a BlockClosure'.
    'where: expects a PBExpression or a one-argument block, got a Array'.
    'where: expects a PBExpression or a one-argument block, got a SmallInteger'.
    'where: expects a PBExpression or a one-argument block, got a UndefinedObject'.
    'where: expects a PBExpression or a one-argument block, got a BlockClosure'.
    'where: expects a PBExpression or a one-argument block, got a PBField' }.

"=== the mixing rule (linq.py:48-61): proto_db's node names, BlockFilter for PythonFilter ==="
lam := PBBlockPredicate block: [:e | (e at: 'value') > 50000] description: 'value > 50000'.
lam1 := PBBlockPredicate block: [:e | (e at: 'value') > 1000] description: 'value > 1000'.
lam2 := PBBlockPredicate block: [:e | (e at: 'value') < 90000] description: 'value < 90000'.
r := OrderedCollection new.
info := explained value: (q where: [:e | (e at: 'value') \\ 7 = 0]).
r add: { names value: info. info at: 'description'.
  (bag value: (q where: [:e | (e at: 'value') \\ 7 = 0]) asArray) = (QData scan: rows where: [:e | (e at: 'value') \\ 7 = 0]) }.
mixed := QData scan: rows where: [:e | (e at: 'category') = 'c3' and: [(e at: 'value') > 50000]].
r add: ({ q where: (category eq: 'c3') & lam. q where: lam & (category eq: 'c3') } collect: [:each |
  { names value: (explained value: each). (bag value: each asArray) = mixed }]).
info := explained value: (q where: (category eq: 'c3') & lam1 & (status ne: 's1') & lam2).
r add: { names value: info. info at: 'description'. ((info at: 'children') at: 1) at: 'description'.
  (bag value: (q where: (category eq: 'c3') & lam1 & (status ne: 's1') & lam2) asArray)
    = (QData scan: rows where: [:e | (e at: 'category') = 'c3' and: [((e at: 'value') between: 1001 and: 89999) and: [(e at: 'status') ~= 's1']]]) }.
lam := PBBlockPredicate block: [:e | (e at: 'value') > 99000] description: 'value > 99000'.
info := explained value: (q where: (category eq: 'c3') | lam).
r add: { names value: info. info at: 'description'.
  (bag value: (q where: (category eq: 'c3') | lam) asArray) = (QData scan: rows where: [:e | (e at: 'category') = 'c3' or: [(e at: 'value') > 99000]]) }.
info := explained value: (q where: ((category eq: 'c3') & lam) not).
r add: { names value: info. info at: 'description'.
  (bag value: (q where: ((category eq: 'c3') & lam) not) asArray) = (QData scan: rows where: [:e | ((e at: 'category') = 'c3' and: [(e at: 'value') > 99000]) not]) }.
info := explained value: (q where: (status eq: 's2') & ((category eq: 'c3') | lam)).
r add: { names value: info.
  (bag value: (q where: (status eq: 's2') & ((category eq: 'c3') | lam)) asArray)
    = (QData scan: rows where: [:e | (e at: 'status') = 's2' and: [(e at: 'category') = 'c3' or: [(e at: 'value') > 99000]]]) }.
lam3 := [:e | (e at: 'value') \\ 3 = 0].
info := explained value: ((((q where: (id > 0)) where: lam3) orderBy: value) take: 7).
r add: { info at: 'plan'. ((info at: 'children') at: 1) at: 'plan'. (find value: info value: 'IndexOrderedScan') notNil. (find value: info value: 'Sort') isNil.
  ((((q where: (id > 0)) where: lam3) orderBy: value) take: 7) asArray collect: [:e | e at: 'value'] }.
r add: ((names value: (explained value: ((((q where: (id > 0)) where: lam3) orderBy: [:e | (e at: 'value') negated]) take: 3))) copyFrom: 1 to: 3).
r add: bad asArray.
"proto_db: test_lambda_becomes_a_visible_python_filter,
 test_mixed_and_is_split_into_index_and_python_filter, test_mixed_and_with_several_parts,
 test_or_or_not_with_a_lambda_is_one_whole_python_filter,
 test_impure_leading_predicate_still_lets_the_planner_order."
c that: 'the mixing rule: a block is a BlockFilter; a top-level AND sends its pure conjuncts to the planner and each block to its own BlockFilter on top; an OR or NOT holding a block is one BlockFilter'
  is: r asArray
  equals: { #(#('BlockFilter' 'CollectionScan') 'block' true).
    #(#(#('BlockFilter' 'IndexLookup') true) #(#('BlockFilter' 'IndexLookup') true)).
    #(#('BlockFilter' 'BlockFilter' 'Filter' 'IndexLookup') 'value < 90000' 'value > 1000' true).
    #(#('BlockFilter' 'CollectionScan') '(category == ''c3'') | (value > 99000)' true).
    #(#('BlockFilter' 'CollectionScan') '~((category == ''c3'') & (value > 99000))' true).
    #(#('BlockFilter' 'IndexLookup') true).
    { 'Limit'. 'BlockFilter'. true. true.
      (((rows select: [:e | (e at: 'value') \\ 3 = 0]) asSortedCollection: [:a :b | (a at: 'value') <= (b at: 'value')]) asArray
        copyFrom: 1 to: 7) collect: [:e | e at: 'value'] }.
    #('Limit' 'Sort' 'BlockFilter').
    #() }.

"=== errors raised by user code propagate ==="
boom := PBBlockPredicate block: [:e | Boom new signal: 'boom'] description: 'boom'.
outcomes := [:aBlock | [aBlock value. #none] on: Error do: [:e | e return: e class name]].
r := { outcomes value: [((PBQuery from: ages) where: [:x | 10 <= (x at: 'age') and: [(x at: 'age') <= 20]]) asArray].
  ids value: ((PBQuery from: ages) where: [:x | (x at: 'age') notNil and: [10 <= (x at: 'age') and: [(x at: 'age') <= 20]]]) asArray.
  { [(q where: (category eq: 'c3') & boom) asArray]. [(q where: (category eq: 'c3') | boom) asArray].
    [(q collect: [:e | Boom new signal: 'boom']) asArray]. [(q orderBy: [:e | Boom new signal: 'boom']) asArray].
    [(q where: boom) count]. [(q where: boom) firstOrNil]. [(q where: boom) first]. [(q where: boom) do: [:e | e]] }
      collect: [:each | outcomes value: each] }.
"proto_db: test_errors_raised_by_user_code_propagate."
c that: 'errors raised by user code propagate from where:, collect: and orderBy: blocks, through every terminal'
  is: { (r at: 1) ~= #none. r at: 2. r at: 3 }
  equals: { true. #(2 3 4). (1 to: 8) asArray collect: [:i | 'Boom'] }.

"=== the between family over a scan (the 0.1 between tests) ==="
q := PBQuery from: ages.
field := PBField path: 'age'.
"proto_db: test_between_inclusive_default, test_between_exclusive, test_between_sugars,
 test_between_range_bounds."
c that: 'between:and: includes both bounds, betweenOpen:and: neither, the half-open forms one'
  is: { ids value: (q where: (field between: 10 and: 20)) asArray. ids value: (q where: (field betweenOpen: 10 and: 20)) asArray.
    (q where: (field between: 10 and: 20)) count. (q where: (field betweenOpen: 10 and: 20)) count.
    (q where: (field betweenLeftOpen: 10 and: 20)) count. (q where: (field betweenRightOpen: 10 and: 20)) count.
    ids value: (q where: (field betweenRightOpen: 10 and: 20)) asArray }
  equals: { #(2 3 4). #(3). 3. 1. 2. 2. #(2 3) }.

"=== ordering ==="
q := PBQuery from: products.
field := PBField path: 'price'.
r := { ids value: (q orderBy: field) asArray.
  ids value: (q orderBy: field descending: true) asArray.
  ids value: ((q orderBy: (PBField path: 'category')) thenBy: field descending: true) asArray.
  ids value: ((q orderBy: 'category' descending: true) thenBy: 'price') asArray.
  ids value: (q orderBy: [:p | (p at: 'id') negated]) asArray.
  ids value: ((q orderBy: 'category') thenBy: [:p | (p at: 'id') negated]) asArray.
  (ids value: ((q orderBy: field) orderBy: 'category') asArray) = (ids value: ((q orderBy: 'category') thenBy: field) asArray).
  (explained value: ((q orderBy: 'category') thenBy: field descending: true)) at: 'plan'.
  (((q orderBy: 'category') thenBy: field descending: true) explain at: 'keys') asArray collect: [:k | k at: 'descending'].
  { q. q where: ((PBField path: 'id') > 1). (q orderBy: 'id') take: 2. (q orderBy: 'id') where: ((PBField path: 'id') > 1) }
    collect: [:each | [each thenBy: field. #accepted] on: PBUserError do: [:e | e return: #refused]].
  { [q orderBy: 'id' descending: nil]. [q orderBy: 5]. [q orderBy: [:a :b | a]] }
    collect: [:each | [each value. #accepted] on: PBValidationError do: [:e | e return: #refused]] }.
q := PBQuery from: coll.
info := explained value: ((q orderBy: value descending: true) take: 5).
r := r , { info at: 'plan'. (find value: info value: 'IndexOrderedScan') notNil.
  ((q orderBy: value descending: true) take: 5) asArray collect: [:e | e at: 'value'].
  bad asArray }.
"proto_db: test_order_by_then_by_stability_and_direction, test_then_by_needs_a_preceding_order_by,
 test_order_by_can_stream_an_ordered_index."
c that: 'orderBy: and thenBy: sort stably by direction, a later orderBy: re-sorts, thenBy: needs a preceding orderBy:, and an ordered index streams'
  is: r
  equals: { #(6 3 4 1 5 2). #(2 1 5 3 4 6). #(2 1 5 3 4 6). #(6 3 4 1 5 2). #(6 5 4 3 2 1). #(5 2 1 4 3 6). true. 'Sort'.
    #(false true). #(#refused #refused #refused #refused). #(#refused #refused #refused).
    'Limit'. true. (((rows collect: [:e | e at: 'value']) asSortedCollection: [:a :b | a >= b]) asArray copyFrom: 1 to: 5).
    #() }.

"=== windows ==="
q := PBQuery from: (PBList new extend: (0 to: 11) asArray).
rnd := QData spreadOn: 7.
out := OrderedCollection new.
200 timesRepeat: [ | query steps |
  query := q.
  ref := (0 to: 11) asArray.
  steps := rnd between: 1 and: 4.
  steps timesRepeat: [ | n |
    n := rnd between: 0 and: 5.
    (rnd chance: 0.5)
      ifTrue: [query := query skip: n. ref := ref copyFrom: (n + 1 min: ref size + 1) to: ref size]
      ifFalse: [query := query take: n. ref := ref copyFrom: 1 to: (n min: ref size)]].
  (query asArray = ref and: [((names value: query explain) select: [:each | each = 'Limit']) size <= 1]) ifFalse: [
    out add: query printString]].
element := PBField element.
ten := PBQuery from: (PBList new extend: (0 to: 9) asArray).
evens := (((ten where: [:x | x even]) orderBy: element descending: true) skip: 1) take: 2.
scores := (PBQuery from: (listOf value: { { 'score' -> 0.9 }. { 'score' -> 0.0 } })) where: [:x | ((x at: 'score') ifNil: [0]) > 0.8].
r := { out asArray.
  { -1. 1.5. true. nil } collect: [:n | { [q take: n]. [q skip: n] } collect: [:each |
    [each value. #accepted] on: PBValidationError do: [:e | e return: #refused]]].
  names value: (explained value: ((ten take: 5) where: element > 2)).
  ((ten take: 5) where: element > 2) asArray.
  names value: (explained value: evens).
  evens asArray.
  names value: (explained value: (scores take: 100)).
  (scores take: 100) asArray collect: [:x | x at: 'score'] }.
q := PBQuery from: coll.
info := explained value: ((((q where: (category eq: 'c3')) orderBy: value) skip: 2) take: 3).
r := r , { (names value: info) copyFrom: 1 to: 2. { info at: 'limit'. info at: 'offset' }.
  (ids value: ((((q where: (category eq: 'c3')) orderBy: value) skip: 2) take: 3) asArray)
    = ((((rows select: [:e | (e at: 'category') = 'c3']) asSortedCollection: [:a :b | (a at: 'value') <= (b at: 'value')]) asArray
      copyFrom: 3 to: 5) collect: [:e | e at: 'id']).
  bad asArray }.
"proto_db: test_skip_and_take_compose_like_slicing, test_where_after_take_is_applied_on_top,
 test_lambda_where_with_window, test_order_and_window_are_pushed_into_the_planner."
c that: 'skip: and take: compose like slicing into one window, where: after take: filters the window, the leading order and window go into the planner'
  is: r
  equals: { #(). (1 to: 4) asArray collect: [:i | #(#refused #refused)].
    #('Filter' 'Limit' 'CollectionScan'). #(3 4). #('Limit' 'BlockFilter' 'Sort' 'CollectionScan'). #(6 4).
    #('Limit' 'BlockFilter' 'CollectionScan'). #(0.9).
    #('Limit' 'Sort'). #(3 2). true. #() }.

"=== project:, collect:, distinct; no select: ==="
q := PBQuery from: (listOf value: (((PBQuery from: users) asArray collect: [:u | u associations asArray]) , { { 'id' -> 5 } })).
d1 := Decimal fromString: '1'.
dict := [:assocs | PBFrozenDict withAssociations: assocs].
out := ((PBQuery from: (PBList new extend: { 1. 1.0. d1. true. 1. 1.0. '1'. nil. nil.
  dict value: { 'a' -> 1 }. dict value: { 'a' -> 1 }. PBTuple withAll: #(1). PBFrozenList withAll: #(1) })) distinct) asArray.
emails := ((PBQuery from: (PBList new extend: (PBQuery from: users) asArray , (PBQuery from: users) asArray)) project: #('email')) distinct.
r := { ((q project: #('email')) asArray copyFrom: 1 to: 2) = { dict value: { 'email' -> 'a@example.com' }. dict value: { 'email' -> 'b@example.com' } }.
  ((q project: #('email')) asArray at: 5) = (PBFrozenDict withAssociations: #()).
  (q project: #('id')) asArray collect: [:each | each at: 'id'].
  ((q project: { PBField path: 'id'. 'age' }) asArray copyFrom: 1 to: 2) = { dict value: { 'id' -> 1. 'age' -> 30 }. dict value: { 'id' -> 2. 'age' -> 17 } }.
  ((q project: (dict value: { 'who' -> 'first_name' })) asArray at: 5) = (PBFrozenDict withAssociations: #()).
  (q collect: [:u | (u at: 'id') * 10]) asArray.
  ((explained value: (q project: (dict value: { 'n' -> 'id'. 'a' -> 'age' }))) at: 'fields') = (dict value: { 'n' -> 'id'. 'a' -> 'age' }).
  (explained value: (q collect: [:u | u])) at: 'function'.
  { [q project: 5]. [q project: #()]. [q project: { PBField element }]. [q project: { 3 }]. [q collect: [:a :b | a]]. [q collect: 5] }
    collect: [:each | [each value. #accepted] on: PBValidationError do: [:e | e return: #refused]].
  names value: (explained value: (((PBQuery from: users) project: #('first_name' 'age')) where: (PBField path: 'age') >= 18)).
  (((PBQuery from: users) project: #('first_name' 'age')) where: (PBField path: 'age') >= 18) asArray collect: [:each | each at: 'first_name'].
  names value: (explained value: (PBQuery from: (PBList new extend: { 1. 1.0 })) distinct).
  out size. { out first isInteger. (out at: 2) isFloat. (out at: 3) isKindOf: Decimal. (out at: 4) == true }.
  emails asArray collect: [:each | each at: 'email'].
  ((PBQuery from: users) where: ((PBField path: 'status') eq: 'active')) count.
  names value: (explained value: (((((PBQuery from: users) where: ((PBField path: 'age') >= 18) & ((PBField path: 'country') in: #('ES' 'AR')))
    orderBy: 'last_login' descending: true) collect: [:x | dict value: { 'id' -> (x at: 'id'). 'name' -> ((x at: 'first_name') , ' ' , (x at: 'last_name')) }]) take: 20)).
  (((((PBQuery from: users) where: ((PBField path: 'age') >= 18) & ((PBField path: 'country') in: #('ES' 'AR')))
    orderBy: 'last_login' descending: true) collect: [:x | dict value: { 'id' -> (x at: 'id'). 'name' -> ((x at: 'first_name') , ' ' , (x at: 'last_name')) }]) take: 20) asArray
    = { dict value: { 'id' -> 4. 'name' -> 'Dan White' }. dict value: { 'id' -> 1. 'name' -> 'Alice Zeus' } }.
  q respondsTo: #select:.
  [q select: [:x | true]. #understood] on: MessageNotUnderstood do: [:e | e return: #notUnderstood].
  bad asArray }.
"proto_db: test_select_forms, test_where_after_select_filters_the_projection,
 test_distinct_keeps_equal_but_distinct_values_apart, test_distinct_and_count,
 test_filter_projection_pagination. Ruling IQ2."
c that: 'project: answers maps of paths, collect: a block''s answers, distinct the first of each identity, and PBQuery does not understand select:'
  is: r
  equals: { true. true. #(1 2 3 4 5). true. true. #(10 20 30 40 50). true. 'block'. (1 to: 6) asArray collect: [:i | #refused].
    #('Filter' 'Project' 'CollectionScan'). #('Alice' 'Carol' 'Dan'). #('Distinct' 'CollectionScan').
    9. #(true true true true). #('a@example.com' 'b@example.com' 'c@example.com' 'd@example.com'). 3.
    #('Limit' 'Project' 'Sort' 'Filter' 'CollectionScan'). true. false. #notUnderstood. #() }.

"=== the terminals ==="
q := PBQuery from: coll.
top3 := ((q where: (category eq: 'c1')) orderBy: 'id') take: 3.
r := { q count. (q where: (category eq: 'c3')) count = (QData scan: rows where: [:e | (e at: 'category') = 'c3']) values sum.
  (q where: id < 11) count.
  ((q orderBy: value) first at: 'value') = ((rows collect: [:e | e at: 'value']) inject: 100001 into: [:m :v | m min: v]).
  (q where: (id eq: 42)) first at: 'id'.
  (q where: (id eq: -1)) firstOrNil.
  ((q where: (id eq: 3)) firstOrNil) at: 'id'.
  [(q where: (id eq: -1)) first. #accepted] on: PBUserError do: [:e | e return: #refused].
  names value: (PBCountPlan source: (q where: (id eq: 3)) plan) explain.
  top3 plan isKindOf: PBQueryPlan.
  (ids value: top3 asArray) = (ids value: top3 plan execute).
  top3 explain = top3 plan explain.
  (ids value: (Array streamContents: [:s | top3 do: [:e | s nextPut: e]])) = (ids value: top3 asArray) }.
"proto_db: test_count_first_and_first_or_none, test_iteration_executes_the_explained_plan."
c that: 'count, first, firstOrNil, asArray and do: run the plan explain describes; first of an empty query is PBUserError'
  is: r
  equals: { 600. true. 10. true. 42. nil. 3. #refused. #('Count' 'IndexLookup'). true. true. true. true }.

"proto_db: test_count_first_and_first_or_none, with a predicate; explain_count (linq.py:1069-1090;
 fix round 1 of Task 8)."
r := { q count: (category eq: 'c3'). (q where: (category eq: 'c3')) count.
  ((q orderBy: 'id') first: (id > 40)) at: 'id'.
  ((q orderBy: 'id') firstOrNil: [:e | (e at: 'id') > 598]) at: 'id'.
  (q firstOrNil: (id eq: -1)).
  [q first: (id eq: -1). #accepted] on: PBUserError do: [:e | e return: #refused].
  [q count: true. #accepted] on: PBValidationError do: [:e | e return: #refused].
  names value: (q where: (id eq: 3)) explainCount.
  (q where: (id eq: 3)) explainCount = (PBCountPlan source: (q where: (id eq: 3)) plan) explain.
  q count: [:e | (e at: 'id') <= 10] }.
c that: 'count:, first: and firstOrNil: take a condition as where: does; explainCount is the explain of count''s plan'
  is: r
  equals: { r at: 2. (QData scan: rows where: [:e | (e at: 'category') = 'c3']) values sum. 41. 599. nil. #refused. #refused.
    #('Count' 'IndexLookup'). true. 10 }.

c report displayNl.
