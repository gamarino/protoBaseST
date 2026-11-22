"EXPECT: ok 4"
"Vectors phase V7 (Addendum V, 2.8 and 5.1): the planner's near[] rules (proto_db
 proto_db/query/planner.py at v2.0.0rc4, lines 98-135 and 194-275). The four near[] behaviours of
 proto_db's tests/unit/test_planner.py (test_near_without_index_raises,
 test_near_with_index_uses_vector_search_never_a_filter,
 test_near_in_a_disjunction_forces_a_union_with_a_filtered_scan_branch and
 test_near_where_with_order_by_never_filters_on_the_ordered_scan), over its data: 20 records with
 id 0..19, v = (id, 0.0) and z = id mod 3, and its two test indexes, ported below: NearScanIndex
 answers near[] on its key by a brute-force l2 kNN over its stored members and cannot restrict its
 search to a predicate; FilteredNearScanIndex can. Each check gathers its mismatches and requires
 none, so one label covers one behaviour. Mapped in tests/unit/queries_checklist.tsv."
Import from: 'protobase'.
Import from: '_check'.

"test_planner.py NearScanIndex: a test index answering near[] on its key by a brute-force l2 kNN
 over its stored members (an equality index's groups), estimating rows k (0 without k) at the cost
 of a full pass; its plans are of kind VectorKnn."
PBEqualityIndex subclass: #NearScanIndex.

NearScanIndex >> supports: aTerm
  self _checkTerm: aTerm.
  ^ aTerm op = PBTerm nearOperator and: [aTerm keySpecObject = self keySpecObject].

NearScanIndex >> estimate: aTerm
  self _checkSupported: aTerm.
  ^ PBEstimate rows: (aTerm value k ifNil: [0]) cost: self count.

"The members satisfying aBlock, nearest to the query first (l2, math.dist), the first k of them
 (all without k), each occurrence once."
NearScanIndex >> _knn: aTerm among: aBlock
  | q k spec members dist ranked |
  q := aTerm value vector.
  k := aTerm value k.
  spec := self keySpecObject.
  members := OrderedCollection new.
  self membersDo: [:element :count | (aBlock value: element) ifTrue: [members add: { element. count }]].
  dist := [:pair | | v s |
    v := spec extract: (pair at: 1).
    s := 0.0.
    1 to: q size do: [:i | s := s + (((v at: i) - (q at: i)) * ((v at: i) - (q at: i)))].
    s sqrt].
  ranked := members asArray asSortedCollection: [:a :b | (dist value: a) <= (dist value: b)].
  ranked := ranked asArray.
  k isNil ifFalse: [ranked := ranked first: (k min: ranked size)].
  ^ PBIndexPlan index: self term: aTerm part: (PBIndexPart kind: 'VectorKnn' producer: [:out |
    ranked do: [:pair | (pair at: 2) timesRepeat: [out value: (pair at: 1)]]]).

NearScanIndex >> plan: aTerm
  self _checkSupported: aTerm.
  ^ self _knn: aTerm among: [:element | true].

"test_planner.py FilteredNearScanIndex: a NearScanIndex that can restrict its kNN to a residual
 predicate (ruling R27)."
NearScanIndex subclass: #FilteredNearScanIndex.

FilteredNearScanIndex >> supportsFiltered: aTerm
  ^ self supports: aTerm.

FilteredNearScanIndex >> filteredPlan: aTerm where: aWhere
  | expr |
  self _checkSupported: aTerm.
  expr := PBExpression compile: aWhere.
  ^ self _knn: aTerm among: [:element | expr evaluate: element].

| c fails expect refused names ids records list near t coll filtered plan info |
c := Check new.
expect := [:label :actual :expected |
  actual = expected ifFalse: [fails add: label , ': expected ' , expected printString , ', got ' , actual printString]].
"The class of the error aBlock signals with its text's check, or #none: { class name. whether the
 text holds aString }."
refused := [:aBlock :aString | [aBlock value. #none] on: Error do: [:e |
  e return: { e class name. e messageText includesSubstring: aString }]].
names := nil.
names := [:anInfo | | out |
  out := OrderedCollection with: (anInfo at: 'plan').
  (anInfo at: 'children') do: [:kid | out addAll: (names value: kid)].
  out asArray].
ids := [:aPlan | (aPlan execute collect: [:e | e at: 'id']) asSortedCollection asArray].
records := (0 to: 19) asArray collect: [:i |
  PBObject withAll: { 'id' -> i. 'v' -> (PBTuple withAll: { i asFloat. 0.0 }). 'z' -> (i \\ 3) }].
list := PBList new extend: records.
near := [:k :at | PBTerm path: 'v' op: 'near[]' value: (PBNearQuery vector: { at. 0.0 } k: k)].
t := [:path :op :value | PBTerm path: path op: op value: value].
plan := [:aSource :aCondition | PBPlanner plan: aSource where: aCondition orderBy: nil limit: nil offset: 0].

"test_near_without_index_raises: with no index that supports it, a near[] term, alone, with
 another conjunct or in a disjunction, is PBNotSupportedError naming near, never a filtered scan;
 so it is over the collection's scan (its indexes are consulted) and over a plan (no index)."
fails := OrderedCollection new.
coll := list addIndex: (PBEqualityIndex name: 'by_z' path: 'z').
{ near value: 3 value: 4.1. (near value: 3 value: 4.1) & (t value: 'z' value: '==' value: 1).
  (near value: 3 value: 4.1) | (t value: 'z' value: '==' value: 1) } do: [:expr |
    expect value: expr printString value: (refused value: [plan value: coll value: expr] value: 'near')
      value: #(#PBNotSupportedError true)].
expect value: 'over the scan' value: (refused value: [plan value: coll asQueryPlan value: (near value: 3 value: 4.1)] value: 'near')
  value: #(#PBNotSupportedError true).
expect value: 'over a Limit' value: (refused value: [plan value: (PBLimit source: coll asQueryPlan limit: 5 offset: 0)
    value: (near value: 3 value: 4.1)] value: 'near')
  value: #(#PBNotSupportedError true).
expect value: 'the text' value: ([plan value: coll value: (near value: 3 value: 4.1)] on: PBNotSupportedError do: [:e | e return: e messageText])
  value: 'No index supports the ''near[]'' term in PBTerm(''v'', ''near[]'', PBNearQuery(vector=(4.1, 0.0), k=3, threshold=None, metric=None)), and a ''near[]'' term cannot be evaluated by a filter; add a vector index on its path'.
c that: 'a near[] term no index supports is PBNotSupportedError, never a filtered scan' is: fails asArray equals: #().

"test_near_with_index_uses_vector_search_never_a_filter: near(k) alone is a VectorSearch; near(k)
 AND P is the k nearest among the elements satisfying P (R27), so an index that cannot restrict
 its search refuses instead of post-filtering to fewer than k, and one that can answers with P as
 the VectorSearch's where; a threshold-only near[] keeps the post-filter; two near[] conjuncts are
 the Intersect of their searches."
fails := OrderedCollection new.
coll := (list addIndex: (NearScanIndex name: 'vec' keySpec: (PBKeySpec path: 'v'))) addIndex: (PBEqualityIndex name: 'by_z' path: 'z').
info := (plan value: coll value: (near value: 3 value: 4.1)).
expect value: 'near(k) alone' value: { info class. ids value: info } value: { PBVectorSearch. #(3 4 5) }.
expect value: 'an index that cannot restrict refuses'
  value: (refused value: [plan value: coll value: (t value: 'z' value: '==' value: 1) & (near value: 3 value: 4.1)] value: 'restrict')
  value: #(#PBNotSupportedError true).
expect value: 'its text' value: ([plan value: coll value: (t value: 'z' value: '==' value: 1) & (near value: 3 value: 4.1)]
    on: PBNotSupportedError do: [:e | e return: e messageText])
  value: '''near[]'' with k combined with other conjuncts means the k nearest among the elements satisfying them, but no index supporting PBTerm(''v'', ''near[]'', PBNearQuery(vector=(4.1, 0.0), k=3, threshold=None, metric=None)) can restrict its search to a predicate'.
filtered := list addIndex: (FilteredNearScanIndex name: 'vec' keySpec: (PBKeySpec path: 'v')).
info := plan value: filtered value: (t value: 'z' value: '==' value: 1) & (near value: 3 value: 4.1).
expect value: 'near(k) AND P' value: { names value: info explain. (info explain at: 'where') = (t value: 'z' value: '==' value: 1) describe.
    ids value: info }
  value: { #('VectorSearch' 'VectorKnn'). true. #(1 4 7) }.
info := plan value: coll value: (t value: 'z' value: '==' value: 1)
  & (PBTerm path: 'v' op: 'near[]' value: (PBNearQuery vector: #(4.1 0.0) threshold: 1.0)).
expect value: 'threshold-only: the post-filter' value: ((names value: info explain) first: 2) value: #('Filter' 'VectorSearch').
info := plan value: coll value: (near value: 5 value: 4.1) & (near value: 3 value: 6.0).
expect value: 'two near[]: Intersect' value: { info explain at: 'plan'. ids value: info } value: { 'Intersect'. #(5 6) }.
c that: 'near[] is answered by a VectorSearch, near(k) AND P inside it, never by a filter' is: fails asArray equals: #().

"test_near_in_a_disjunction_forces_a_union_with_a_filtered_scan_branch: a disjunction holding
 near[] is a Union, its branch without an index a filtered scan; a negated near[] term, directly or
 through De Morgan, is PBNotSupportedError."
fails := OrderedCollection new.
coll := list addIndex: (NearScanIndex name: 'vec' keySpec: (PBKeySpec path: 'v')).
info := plan value: coll value: (near value: 2 value: 4.1) | (t value: 'id' value: '==' value: 17).
expect value: 'a Union' value: { info explain at: 'plan'. (info explain at: 'children') asArray collect: [:kid | kid at: 'plan'].
    ids value: info }
  value: { 'Union'. #('VectorSearch' 'Filter'). #(4 5 17) }.
expect value: 'not near' value: (refused value: [plan value: coll value: (near value: 3 value: 4.1) not] value: 'near')
  value: #(#PBNotSupportedError true).
expect value: 'not (near and id == 1)'
  value: (refused value: [plan value: coll value: ((near value: 3 value: 4.1) & (t value: 'id' value: '==' value: 1)) not] value: 'near')
  value: #(#PBNotSupportedError true).
c that: 'near[] in a disjunction forces a Union; a negated near[] is PBNotSupportedError' is: fails asArray equals: #().

"test_near_where_with_order_by_never_filters_on_the_ordered_scan: an order over a condition
 holding near[] sorts the VectorSearch; the range index on the key is never an ordered scan with
 the near[] term as its filter."
fails := OrderedCollection new.
coll := (list addIndex: (NearScanIndex name: 'vec' keySpec: (PBKeySpec path: 'v'))) addIndex: (PBRangeIndex name: 'by_id' path: 'id').
info := PBPlanner plan: coll where: (near value: 3 value: 4.1) orderBy: { PBSortKey key: 'id' descending: true } limit: nil offset: 0.
expect value: 'Sort over the VectorSearch' value: { names value: info explain. info execute collect: [:e | e at: 'id'] }
  value: { #('Sort' 'VectorSearch' 'VectorKnn'). #(5 4 3) }.
c that: 'an order over near[] sorts the VectorSearch, never an ordered index scan' is: fails asArray equals: #().

c report displayNl.
