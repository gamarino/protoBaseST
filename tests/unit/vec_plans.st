"EXPECT: ok 7"
"Vectors phase V6 (Addendum V, 2.4, 2.7 and 5.1): PBVectorSearch and the vector index plans, against
 proto_db v2.0.0rc4 (proto_db/query/plans.py:389-436, proto_db/indexing/vector.py:92-122 and
 272-319, vector_backends.py:378-383, 505-524, 685-730 and 790-821). The behaviours of
 tests/unit/test_plans.py's test_vector_search_wraps_the_index_plan and of
 tests/unit/test_vector_index.py's test_near_k_and_predicate_returns_k_among_the_matching,
 test_near_k_with_threshold_and_predicate_and_threshold_only_post_filter,
 test_several_near_terms_and_disjunctions_keep_set_semantics,
 test_oracle_with_predicate_callable_and_expression_agree,
 test_missing_hnswlib_raises_not_supported_at_first_use (ruling VQ1, deviation DV1) and
 test_eight_threads_query_one_version (eight actors), mapped in tests/unit/queries_checklist.tsv;
 plus the estimates of the three backends in Python's arithmetic (S30), compared by their IEEE 754
 bytes with the figures proto_db's own estimate functions answer for the same indexes (computed
 with CPython 3.14, numpy and hnswlib blocked; the hnsw descent log2(1002) is the same Float as
 PBCost log2:, so deviation DV6 does not show here). The plans proto_db's planner builds for these
 tests (VectorSearch with a residual predicate, a Filter over a VectorSearch, an Intersect and a
 Union of them) are built here by hand, node for node, so these checks pin the plan nodes apart
 from the planner, whose near[] rules (vectors phase V7) tests/unit/vec_planner.st and
 tests/conformance/queries.st check; their answers are checked as proto_db's tests check them. Each check gathers its mismatches and requires none, so one label
 covers one behaviour."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.

"test_plans.py BruteVectorIndex: a duck-typed index answering near[] on 'v' by a brute-force l2
 kNN over its items, whose explain names its kind."
Object subclass: #BruteVectorIndex instanceVariableNames: 'items'.

BruteVectorIndex class >> items: anArray
  ^ self basicNew setItems: anArray.

BruteVectorIndex >> setItems: anArray
  items := anArray.

BruteVectorIndex >> supports: aTerm
  ^ aTerm op = 'near[]' and: [aTerm path = 'v'].

BruteVectorIndex >> estimate: aTerm
  ^ PBEstimate rows: (aTerm value k ifNil: [items size]) cost: items size.

BruteVectorIndex >> explain
  ^ PBFrozenDict withAssociations: { 'index' -> 'vec'. 'kind' -> 'BruteVectorIndex'. 'key' -> 'v' }.

BruteVectorIndex >> plan: aTerm
  | q k dist |
  q := aTerm value vector.
  k := aTerm value k.
  dist := [:item | | s | s := 0.0. 1 to: q size do: [:i | s := s + (((item at: 'v') at: i) - (q at: i) raisedTo: 2)]. s sqrt].
  ^ PBIndexPlan index: self term: aTerm part: (PBIndexPart kind: 'VectorKnn' producer: [:aBlock |
    ((items asArray asSortedCollection: [:a :b | (dist value: a) <= (dist value: b)]) asArray first: k) do: aBlock]).

"Runs every term of a version on its own actor (test_eight_threads_query_one_version)."
Object subclass: #VectorReader.

VectorReader >> answers: anIndex terms: aTerms
  ^ aTerms collect: [:t | (anIndex plan: t) execute collect: [:e | PBMemberKeys identityOf: e]].

| c fails expect refused tup rec near nq ids oracle coords records hex estimates items idx term plan
  info vs elements coll index where got q q1 q2 a b pred backends twin terms expected dir storage
  pointer stub futures outputs data built hnsw msg |
c := Check new.
expect := [:label :actual :expected |
  actual = expected ifFalse: [fails add: label , ': expected ' , expected printString , ', got ' , actual printString]].
refused := [:aBlock | [aBlock value. nil] on: Error do: [:e | e return: e class]].
msg := [:aBlock | [aBlock value. 'no error'] on: Error do: [:e | e return: e class name , ': ' , e messageText]].
tup := [:anArray | PBTuple withAll: anArray].
rec := [:i :v | PBObject withAll: { 'i' -> i. 'g' -> (i \\ 3). 'vec' -> v }].
nq := [:v :k :t | PBNearQuery vector: v k: k threshold: t metric: nil].
near := [:v :k :t | PBTerm path: 'vec' op: 'near[]' value: (nq value: v value: k value: t)].
"Exact multisets of the stored elements themselves (exact token and identity), sorted."
ids := [:anArray | (anArray asArray collect: [:e | (PBKeys exactToken: e) hex , ':' , (PBMemberKeys identityOf: e) printString])
  asSortedCollection asArray].
oracle := [:anArray :aQuery :aMetric :aPredicate | PBVectorIndex nearOracle: anArray keySpec: (PBKeySpec path: 'vec')
  query: aQuery metric: aMetric predicate: aPredicate].
coords := [:n :d :s | | r |
  r := PBPythonRandom bits: 20 count: n * d seed: s.
  (1 to: n) asArray collect: [:i |
    tup value: ((1 to: d) asArray collect: [:j | (r at: (i - 1) * d + j) asFloat / 524288.0 - 1.0])]].
records := [:vectors | (1 to: vectors size) asArray collect: [:i | rec value: i - 1 value: (vectors at: i)]].
hex := [:aFloat | | w | w := WriteStream on: ByteArray new. w nextPutFloat64: aFloat bigEndian: true. w contents hex asLowercase].

"test_vector_search_wraps_the_index_plan: PBVectorSearch over any index that supports the term
 runs its plan, explains it as its child and estimates as it does; a term that is not near[] is
 PBValidationError, an unsupported one PBNotSupportedError. Then plans.py's other checks, with
 their texts: a residual predicate holding near[], and an index that cannot restrict its search.
 Then S30: the estimates of exact, ivf_flat (trained and not) and hnsw indexes (store sizes 0, 5,
 7, 50 and 1000), for k, a threshold, both and a k above the members, unfiltered (estimate:) and
 filtered (filteredPlan:where:), byte for byte as proto_db's."
fails := OrderedCollection new.
items := (0 to: 9) asArray collect: [:i | PBObject withAll: { 'id' -> i. 'v' -> (tup value: { i asFloat. 0.0 }) }].
idx := BruteVectorIndex items: items.
term := PBTerm path: 'v' op: 'near[]' value: (PBNearQuery vector: #(3.2 0.0) k: 3).
plan := PBVectorSearch index: idx term: term where: nil.
expect value: 'its rows, twice' value: { plan execute collect: [:e | e at: 'id']. plan execute collect: [:e | e at: 'id'] }
  value: #(#(3 4 2) #(3 4 2)).
info := plan explain.
expect value: 'explain' value: { info at: 'plan'. (info at: 'index') at: 'kind'. ((info at: 'term') at: 'value') at: 'k'.
    ((info at: 'children') at: 1) at: 'plan'. (info at: 'estimate') at: 'rows'. info includesKey: 'where' }
  value: #('VectorSearch' 'BruteVectorIndex' 3 'VectorKnn' 3.0 false).
expect value: 'estimate' value: plan estimate value: (PBEstimate rows: 3 cost: 10).
expect value: 'refusals' value: {
    msg value: [PBVectorSearch index: idx term: (PBTerm path: 'v' op: '==' value: 1) where: nil].
    refused value: [PBVectorSearch index: idx term: (PBTerm path: 'w' op: 'near[]' value: (PBNearQuery vector: #(1.0) k: 1)) where: nil].
    msg value: [PBVectorSearch index: idx term: term where: (PBTerm path: 'w' op: 'near[]' value: (PBNearQuery vector: #(1.0) k: 1))].
    msg value: [PBVectorSearch index: (PBVectorIndex name: 'h' path: 'v' dim: 2 metric: 'l2') term: term where: nil] }
  value: { 'PBValidationError: VectorSearch needs a ''near[]'' term, not Term(path=''v'', op=''=='', value=1)'. PBNotSupportedError.
    'PBValidationError: A VectorSearch residual predicate cannot hold ''near[]'' terms (Term(path=''w'', op=''near[]'', value=NearQuery(vector=(1.0,), k=1, threshold=None, metric=None)))'.
    'no error' }.
expect value: 'an index without supportsFiltered: (Python: AttributeError)'
  value: (refused value: [PBVectorSearch index: idx term: term where: (PBTerm path: 'id' op: '==' value: 1)])
  value: MessageNotUnderstood.
expect value: 'an index that restricts nothing' value: (msg value: [PBVectorSearch index: (((PBList new extend: items)
    addIndex: (PBEqualityIndex name: 'e' path: 'id')) getIndex: 'e') term: term where: nil])
  value: 'PBNotSupportedError: Index ''e'' does not support Term(path=''v'', op=''near[]'', value=NearQuery(vector=(3.2, 0.0), k=3, threshold=None, metric=None))'.
estimates := OrderedCollection new.
{ { 'exact'. nil. 7 }. { 'ivf_flat'. { 'nlist' -> 7. 'nprobe' -> 3 }. 50 }. { 'ivf_flat'. { 'nlist' -> 7. 'nprobe' -> 3 }. 5 }.
  { 'hnsw'. nil. 5 }. { 'hnsw'. nil. 1000 }. { 'exact'. nil. 0 } } do: [:case | | d vi |
  d := nil.
  (case at: 2) isNil ifFalse: [d := Dictionary new. (case at: 2) do: [:p | d at: p key put: p value]].
  vi := (PBVectorIndex name: 'v' keySpec: PBKeySpec element dim: 2 metric: 'l2' backend: (case at: 1) params: d)
    build: ((0 to: (case at: 3) - 1) asArray collect: [:i | tup value: { i asFloat. (i \\ 7) asFloat }]).
  #(#(3 nil) #(nil 1.5) #(3 1.5) #(100 nil)) do: [:kt | | t |
    t := PBTerm path: nil op: 'near[]' value: (PBNearQuery vector: #(1.0 2.0) k: (kt at: 1) threshold: (kt at: 2) metric: nil).
    { vi estimate: t. (vi filteredPlan: t where: (PBTerm path: nil op: '?!N')) estimate } do: [:e |
      estimates add: (hex value: e rows) , ' ' , (hex value: e cost)]]].
expect value: 'S30: the estimates in Python''s arithmetic' value: estimates asArray value: #(
  '4008000000000000 4026000000000000' '4008000000000000 4032000000000000' '400c000000000000 4027000000000000'
  '400c000000000000 4032800000000000' '3ff8000000000000 4023000000000000' '3ff8000000000000 4030800000000000'
  '401c000000000000 402e000000000000' '401c000000000000 4036000000000000'
  '4008000000000000 404036db6db6db6e' '4008000000000000 404aedb6db6db6db' '4039000000000000 404b36db6db6db6e'
  '4039000000000000 4052f6db6db6db6e' '3ff8000000000000 403eedb6db6db6db' '3ff8000000000000 404a2db6db6db6db'
  '4049000000000000 4053db6db6db6db7' '4049000000000000 405936db6db6db6e'
  '4008000000000000 4022000000000000' '4008000000000000 402c000000000000' '4004000000000000 4021000000000000'
  '4004000000000000 402b000000000000' '3ff8000000000000 401e000000000000' '3ff8000000000000 4029000000000000'
  '4014000000000000 4026000000000000' '4014000000000000 4030000000000000'
  '4008000000000000 4022000000000000' '4008000000000000 402c000000000000' '4004000000000000 4021000000000000'
  '4004000000000000 402b000000000000' '3ff8000000000000 401e000000000000' '3ff8000000000000 4029000000000000'
  '4014000000000000 4026000000000000' '4014000000000000 4030000000000000'
  '4008000000000000 40840ff5180afd3e' '4008000000000000 4093fff5180afd3e' '407f400000000000 4091cbfa8c057e9f'
  '407f400000000000 409bc3f5180afd3e' '3ff8000000000000 408403f5180afd3e' '3ff8000000000000 4093f9f5180afd3e'
  '4059000000000000 409127777ac895d8' '4059000000000000 40a05d777ac895d8'
  '0000000000000000 3ff0000000000000' '0000000000000000 3ff0000000000000' '0000000000000000 3ff0000000000000'
  '0000000000000000 3ff0000000000000' '0000000000000000 3ff0000000000000' '0000000000000000 3ff0000000000000'
  '0000000000000000 3ff0000000000000' '0000000000000000 3ff0000000000000').
c that: 'PBVectorSearch wraps the index plan; the estimates are proto_db''s, bit for bit' is: fails asArray equals: #().

"test_near_k_and_predicate_returns_k_among_the_matching: near(k) with a residual predicate is the k
 nearest among the elements that satisfy it, never a post-filtered kNN: VectorSearch with 'where'
 (proto_db's planner's plan for near(k) AND P), for the exact backend and for ivf_flat with
 nprobe 1, which widens its probe until k members match; with fewer matches than k, every match."
fails := OrderedCollection new.
elements := records value: (coords value: 150 value: 6 value: 4).
backends := { 'exact' -> nil. 'ivf_flat' -> (Dictionary new at: 'nlist' put: 8; at: 'nprobe' put: 1; yourself) }.
backends do: [:bp |
  coll := (PBList new extend: elements) addIndex: (PBVectorIndex name: 'vec_idx' keySpec: (PBKeySpec path: 'vec') dim: 6
    metric: 'l2' backend: bp key params: bp value).
  index := coll getIndex: 'vec_idx'.
  where := PBTerm path: 'g' op: '==' value: 1.
  (coords value: 5 value: 6 value: 40) do: [:v |
    plan := PBVectorSearch index: index term: (near value: v value: 5 value: nil) where: where.
    info := plan explain.
    got := plan execute.
    ({ info at: 'plan'. info at: 'where'. got size. got allSatisfy: [:e | (e at: 'g') = 1] }
      = { 'VectorSearch'. where describe. 5. true }) ifFalse: [fails add: bp key , ' ' , info printString].
    (bp key = 'exact' and: [(ids value: got) ~= (ids value: (oracle value: elements value: (nq value: v value: 5 value: nil) value: 'l2' value: where))])
      ifTrue: [fails add: 'exact differs from the oracle']].
  got := (PBVectorSearch index: index term: (near value: (coords value: 1 value: 6 value: 41) first value: 50 value: nil)
    where: (PBTerm path: 'i' op: '<' value: 7)) execute.
  expect value: bp key , ' fewer matches than k' value: (got collect: [:e | e at: 'i']) asSortedCollection asArray
    value: #(0 1 2 3 4 5 6)].
c that: 'near(k) with a residual predicate answers k among the matching' is: fails asArray equals: #().

"test_near_k_with_threshold_and_predicate_and_threshold_only_post_filter: near(k, threshold) with a
 predicate is a VectorSearch with 'where' (the k nearest among the matching within the threshold);
 a threshold-only near[] and a predicate is a Filter over a VectorSearch (proto_db's planner keeps
 the predicate out of a search without k: the same answer either way, and the search alone is
 cacheable), and both equal the oracle."
fails := OrderedCollection new.
elements := records value: (coords value: 120 value: 4 value: 8).
coll := (PBList new extend: elements) addIndex: (PBVectorIndex name: 'vec_idx' keySpec: (PBKeySpec path: 'vec') dim: 4 metric: 'l2').
index := coll getIndex: 'vec_idx'.
q := (coords value: 1 value: 4 value: 9) first.
pred := PBTerm path: 'g' op: '==' value: 2.
plan := PBVectorSearch index: index term: (near value: q value: 6 value: 1.0) where: pred.
expect value: 'k, threshold and a predicate' value: (ids value: plan execute)
  value: (ids value: (oracle value: elements value: (nq value: q value: 6 value: 1.0) value: 'l2' value: pred)).
plan := PBFilter source: (PBVectorSearch index: index term: (near value: q value: nil value: 1.0) where: nil) terms: pred.
info := plan explain.
expect value: 'a Filter over a VectorSearch' value: { info at: 'plan'. ((info at: 'children') at: 1) at: 'plan' }
  value: #('Filter' 'VectorSearch').
expect value: 'threshold only, filtered' value: (ids value: plan execute)
  value: (ids value: (oracle value: elements value: (nq value: q value: nil value: 1.0) value: 'l2' value: pred)).
expect value: 'not empty' value: plan execute isEmpty value: false.
c that: 'a threshold with a predicate, and a threshold-only search under a Filter, answer the oracle' is: fails asArray equals: #().

"test_several_near_terms_and_disjunctions_keep_set_semantics: two near[] conjuncts and a condition
 are a Filter over the Intersect of two searches (proto_db's planner's plan); near(k) AND P OR a
 condition is a Union of a VectorSearch with 'where' and a Filter over a scan."
fails := OrderedCollection new.
elements := records value: (coords value: 100 value: 3 value: 6).
coll := (PBList new extend: elements) addIndex: (PBVectorIndex name: 'vec_idx' keySpec: (PBKeySpec path: 'vec') dim: 3 metric: 'l2').
index := coll getIndex: 'vec_idx'.
q1 := (coords value: 2 value: 3 value: 61) at: 1.
q2 := (coords value: 2 value: 3 value: 61) at: 2.
plan := PBFilter source: (PBIntersect withAll: {
    PBVectorSearch index: index term: (near value: q1 value: 30 value: nil) where: nil.
    PBVectorSearch index: index term: (near value: q2 value: 30 value: nil) where: nil })
  terms: (PBTerm path: 'g' op: '==' value: 0).
info := plan explain.
expect value: 'Filter over Intersect' value: { info at: 'plan'. ((info at: 'children') at: 1) at: 'plan' } value: #('Filter' 'Intersect').
a := ((oracle value: elements value: (nq value: q1 value: 30 value: nil) value: 'l2' value: nil) collect: [:e | e at: 'i']) asSet.
b := ((oracle value: elements value: (nq value: q2 value: 30 value: nil) value: 'l2' value: nil) collect: [:e | e at: 'i']) asSet.
expect value: 'the intersection, filtered' value: (plan execute collect: [:e | e at: 'i']) asSortedCollection asArray
  value: ((a select: [:i | (b includes: i) and: [i \\ 3 = 0]]) asSortedCollection asArray).
plan := PBUnion withAll: {
  PBVectorSearch index: index term: (near value: q1 value: 3 value: nil) where: (PBTerm path: 'g' op: '==' value: 1).
  PBFilter source: (PBCollectionScan on: coll) terms: (PBTerm path: 'i' op: '==' value: 99) }.
expect value: 'Union' value: (plan explain at: 'plan') value: 'Union'.
got := (plan execute collect: [:e | e at: 'i']) asSet.
expect value: 'the union' value: { got includes: 99. (got select: [:i | i \\ 3 = 1 and: [i ~= 99]]) size } value: #(true 3).
c that: 'several near[] terms and disjunctions keep set semantics' is: fails asArray equals: #().

"test_oracle_with_predicate_callable_and_expression_agree: nearOracle: restricted by an expression,
 by the same condition in the 0.1 list syntax and by a block answers the same four elements."
fails := OrderedCollection new.
elements := records value: (coords value: 50 value: 3 value: 1).
q := nq value: (coords value: 1 value: 3 value: 2) first value: 4 value: nil.
got := { oracle value: elements value: q value: 'ip' value: (PBTerm path: 'g' op: '==' value: 0).
  oracle value: elements value: q value: 'ip' value: #('g' '==' 0).
  oracle value: elements value: q value: 'ip' value: [:e | (e at: 'g') = 0].
  oracle value: elements value: q value: 'ip' value: (PBBlockPredicate block: [:e | (e at: 'g') = 0] description: 'g is 0') }.
expect value: 'four elements, the same each way' value: { (got at: 1) size. (got collect: [:each | ids value: each]) asSet size }
  value: #(4 1).
expect value: 'nearOracle: refusals' value: {
    msg value: [PBVectorIndex nearOracle: elements keySpec: (PBKeySpec path: 'vec') query: #(1.0) metric: 'l2' predicate: nil].
    msg value: [PBVectorIndex nearOracle: elements keySpec: 'vec' query: q metric: 'l2' predicate: nil].
    msg value: [PBVectorIndex nearOracle: elements keySpec: (PBKeySpec path: 'vec') query: q metric: 'dot' predicate: nil] }
  value: { 'PBValidationError: near_oracle needs a NearQuery, not [1.0]'. 'PBValidationError: near_oracle needs a KeySpec, not ''vec'''.
    'PBValidationError: Unknown vector metric ''dot''; expected one of [''cosine'', ''l2'', ''ip'']' }.
c that: 'the oracle restricted by an expression, the list syntax or a block agrees' is: fails asArray equals: #().

"test_missing_hnswlib_raises_not_supported_at_first_use (ruling VQ1, deviation DV1): an hnsw index
 is built, validated, planned, explained and estimated; executing its plan, alone, under a
 VectorSearch or restricted to a predicate, is PBNotSupportedError naming hnswlib."
fails := OrderedCollection new.
elements := records value: (coords value: 20 value: 4 value: 0).
hnsw := (PBVectorIndex name: 'v' keySpec: (PBKeySpec path: 'vec') dim: 4 metric: 'cosine' backend: 'hnsw' params: nil) build: elements.
term := near value: (coords value: 1 value: 4 value: 3) first value: 3 value: nil.
plan := hnsw plan: term.
expect value: 'maintained, planned, explained' value: { (hnsw validate: elements) == hnsw. plan kind. (plan explain at: 'plan').
    plan estimate rows. (PBVectorSearch index: hnsw term: term where: nil) explain at: 'plan' }
  value: #(true 'VectorHnsw' 'VectorHnsw' 3.0 'VectorSearch').
expect value: 'executed, refused' value: { refused value: [plan execute].
    refused value: [(PBVectorSearch index: hnsw term: term where: nil) execute].
    refused value: [(hnsw filteredPlan: term where: (PBTerm path: 'g' op: '==' value: 1)) execute].
    ([plan execute] on: PBNotSupportedError do: [:e | e return: (e messageText includesSubstring: 'hnswlib')]) }
  value: { PBNotSupportedError. PBNotSupportedError. PBNotSupportedError. true }.
c that: 'an hnsw search is refused at its first execution, not before' is: fails asArray equals: #().

"test_eight_threads_query_one_version: for the exact and ivf_flat backends, one index version and
 the same version saved and loaded back as a stub, each read by eight actors at once running 12
 near[] plans, answer what an equal twin answers. The space goes to out/vec_plans (git ignores
 out/), a new directory per run; nothing is removed."
fails := OrderedCollection new.
terms := (1 to: 12) asArray collect: [:j | near value: ((coords value: 12 value: 8 value: 11) at: j) value: (#(1 5 20) at: j \\ 3 + 1) value: nil].
{ { 'exact'. nil }. { 'exact'. { 'numpy' -> false } }. { 'ivf_flat'. { 'nlist' -> 8. 'nprobe' -> 3 } } } do: [:bp | | make d |
  d := nil.
  (bp at: 2) isNil ifFalse: [d := Dictionary new. (bp at: 2) do: [:p | d at: p key put: p value]].
  "Records of their own per backend: a saved record belongs to its storage."
  elements := records value: (coords value: 200 value: 8 value: 10).
  make := [(PBVectorIndex name: 'v' keySpec: (PBKeySpec path: 'vec') dim: 8 metric: 'l2' backend: (bp at: 1) params: d) build: elements].
  index := make value.
  dir := ('out/vec_plans' asFileReference / ('run-' , Smalltalk pid printString , '-' , Time microsecondClockValue printString)) pathString.
  storage := PBFileStorage path: dir.
  index _saveInto: storage.
  pointer := index pointer.
  storage close.
  storage := PBFileStorage path: dir.
  stub := PBTypeRegistry unloadedAtomFor: index tag at: pointer storage: storage.
  twin := make value.
  expected := VectorReader new answers: twin terms: terms.
  { index. stub } do: [:version |
    futures := (1 to: 8) asArray collect: [:j | VectorReader new asActor answers: version terms: terms].
    outputs := futures collect: [:f | f waitWithin: 300000].
    (outputs allSatisfy: [:o | o = expected]) ifFalse: [fails add: (bp at: 1) , ' ' , (version == stub ifTrue: ['stub'] ifFalse: ['version'])]].
  storage close].
c that: 'eight actors reading one version, and its loaded stub, get the twin''s answers' is: fails asArray equals: #().

c report displayNl.
