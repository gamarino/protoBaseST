"EXPECT: ok 5"
"Vectors phase V7 (Addendum V, 2.9 and 5.1): near[] in the query front end, PBField near: and the
 mixing rule of ruling R27 (proto_db proto_db/query/linq.py at v2.0.0rc4, lines 53-58, 644-647,
 996-1008 and 1099-1105). The behaviours of proto_db's tests/unit/test_vector_index.py
 (test_commit_through_a_transaction_and_query_after_reopen,
 test_linq_near_k_and_lambda_is_k_nearest_among_the_lambda_matches,
 test_python_predicate_expression_node) and tests/unit/test_linq.py
 (test_near_without_a_vector_index_raises_instead_of_falling_back,
 test_near_and_lambda_split_like_two_wheres), with protoST's names: proto_db's lambda is a block
 given to where:, which joins a where: run with AND (ruling CR5), so F.v.near(q, k=4) & lambda is
 (q where: near) where: aBlock; PythonPredicate is PBBlockPredicate, described as { 'block' -> ...
 } (deviation DV5). A near[] term combined with a block by OR or NOT (a PBBlockPredicate, the
 public node a block becomes) is refused by where: as proto_db's where refuses it (linq.py:344-353,
 940-943): proto_db's lambda there is a PBBlockPredicate here. The
 rule's scope (Addendum V 2.9) is checked too: only the leading run of where: and orderBy: steps
 is merged, so a block after a window step filters the window. Each check gathers its mismatches
 and requires none. The space of the commit-and-reopen test goes to out/vec_query (git ignores
 out/), a new directory per run; nothing is removed. Mapped in tests/unit/queries_checklist.tsv."
Import from: 'protobase'.
Import from: '_check'.

| c fails expect refused tup rec coords records ids oracle near nq elements coll q got query info
  fn p dir space db tx vectors n first again coll2 cos |
c := Check new.
expect := [:label :actual :expected |
  actual = expected ifFalse: [fails add: label , ': expected ' , expected printString , ', got ' , actual printString]].
refused := [:aBlock :aString | [aBlock value. #none] on: Error do: [:e |
  e return: { e class name. e messageText includesSubstring: aString }]].
tup := [:anArray | PBTuple withAll: anArray].
rec := [:i :v | PBObject withAll: { 'i' -> i. 'g' -> (i \\ 3). 'vec' -> v }].
"n seeded vectors of dim d in [-1, 1) (Python's getrandbits, ported: vec_plans.st's generator)."
coords := [:count :d :s | | r |
  r := PBPythonRandom bits: 20 count: count * d seed: s.
  (1 to: count) asArray collect: [:i |
    tup value: ((1 to: d) asArray collect: [:j | (r at: (i - 1) * d + j) asFloat / 524288.0 - 1.0])]].
records := [:aVectors | (1 to: aVectors size) asArray collect: [:i | rec value: i - 1 value: (aVectors at: i)]].
"Exact multisets of the stored elements themselves (exact token and identity), sorted."
ids := [:anArray | (anArray asArray collect: [:e | (PBKeys exactToken: e) hex , ':' , (PBMemberKeys identityOf: e) printString])
  asSortedCollection asArray].
oracle := [:anArray :aQuery :aMetric :aPredicate | PBVectorIndex nearOracle: anArray keySpec: (PBKeySpec path: 'vec')
  query: aQuery metric: aMetric predicate: aPredicate].
near := PBField path: 'vec'.
nq := [:v :k | PBNearQuery vector: v k: k].

"test_commit_through_a_transaction_and_query_after_reopen: a list with an exact l2 index and an
 ivf_flat cosine index probing all its lists, filled over two commits to a file space, reopened:
 both indexes validate, the planner answers near(k) with an explicit metric as the oracle does, and
 the front end answers near(k) AND a condition (the k nearest among the matching) and a cosine
 query. Then PBField's near: selectors, each the term proto_db's F.v.near builds."
fails := OrderedCollection new.
vectors := coords value: 60 value: 4 value: 12.
dir := ('out/vec_query' asFileReference / ('run-' , Smalltalk pid printString , '-' , Time microsecondClockValue printString)) pathString.
space := PBObjectSpace storage: (PBFileStorage path: dir).
db := space newDatabase: 'vecs'.
tx := db newTransaction.
coll := (tx newList addIndex: (PBVectorIndex name: 'by_vec' path: 'vec' dim: 4 metric: 'l2'))
  addIndex: (PBVectorIndex name: 'by_vec_ivf' keySpec: (PBKeySpec path: 'vec') dim: 4 metric: 'cosine' backend: 'ivf_flat'
    params: (Dictionary new at: 'nlist' put: 4; at: 'nprobe' put: 4; yourself)).
1 to: 40 do: [:i | coll := coll appendLast: (tx newObject: { 'i' -> (i - 1). 'g' -> (i - 1 \\ 2). 'vec' -> (vectors at: i) })].
tx setRootObject: 'docs' value: coll.
tx commit.
tx := db newTransaction.
coll := tx getRootObject: 'docs'.
41 to: 60 do: [:i | coll := coll appendLast: (tx newObject: { 'i' -> (i - 1). 'g' -> (i - 1 \\ 2). 'vec' -> (vectors at: i) })].
tx setRootObject: 'docs' value: coll.
tx commit.
space close.
space := PBObjectSpace storage: (PBFileStorage path: dir).
tx := (space openDatabase: 'vecs') newTransaction.
coll := tx getRootObject: 'docs'.
elements := coll elements asArray.
expect value: 'reopened' value: { elements size. ((coll getIndex: 'by_vec') validate: elements) notNil.
    ((coll getIndex: 'by_vec_ivf') validate: elements) notNil }
  value: #(60 true true).
q := vectors at: 18.
got := (PBPlanner plan: coll where: (near near: q k: 3 threshold: nil metric: 'l2') orderBy: nil limit: nil offset: 0)
  execute collect: [:e | e at: 'i'].
expect value: 'the planner, l2' value: { got first. got size. got = ((oracle value: elements value: (nq value: q value: 3) value: 'l2' value: nil)
    collect: [:e | e at: 'i']) }
  value: #(17 3 true).
got := ((PBQuery from: coll) where: (near near: q asArray k: 4 threshold: nil metric: 'l2') & ((PBField path: 'g') eq: 0)) asArray.
expect value: 'the front end, near(k) AND a condition' value: { got size. got allSatisfy: [:e | (e at: 'g') = 0] } value: #(4 true).
cos := ((PBQuery from: coll) where: (near near: q asArray k: 2 threshold: nil metric: 'cosine')) asArray collect: [:e | e at: 'i'].
expect value: 'the front end, cosine' value: cos
  value: ((oracle value: elements value: (nq value: q value: 2) value: 'cosine' value: nil) collect: [:e | e at: 'i']).
tx abort.
space close.
p := PBNearQuery vector: #(1.0 0.0) k: 3.
expect value: 'PBField near: selectors' value: {
    (PBField path: 'v') near: #(1.0 0.0) k: 3.
    (PBField path: 'v') near: p.
    (PBField path: 'v') near: #(1.0 0.0) k: 3 threshold: nil metric: nil.
    (PBField path: 'v') near: #(1.0 0.0) threshold: 0.5.
    (PBField path: 'v') near: #(1.0 0.0) k: 3 threshold: 0.5.
    (PBField path: 'v') near: #(1.0 0.0) k: nil threshold: 0.5 metric: 'l2' }
  value: {
    PBTerm path: 'v' op: 'near[]' value: p.
    PBTerm path: 'v' op: 'near[]' value: p.
    PBTerm path: 'v' op: 'near[]' value: p.
    PBTerm path: 'v' op: 'near[]' value: (PBNearQuery vector: #(1.0 0.0) threshold: 0.5).
    PBTerm path: 'v' op: 'near[]' value: (PBNearQuery vector: #(1.0 0.0) k: 3 threshold: 0.5).
    PBTerm path: 'v' op: 'near[]' value: (PBNearQuery vector: #(1.0 0.0) k: nil threshold: 0.5 metric: 'l2') }.
expect value: 'PBNearQuery''s validation' value: {
    refused value: [(PBField path: 'v') near: #(1.0) k: nil threshold: nil metric: nil] value: 'k'.
    refused value: [(PBField path: 'v') near: #(1.0) k: 0] value: 'k'.
    refused value: [(PBField path: 'v') near: #(1.0)] value: 'near' }
  value: #(#(#PBValidationError true) #(#PBValidationError true) #(#PBValidationError true)).
c that: 'a vector-indexed list committed, reopened and queried through the planner and the front end' is: fails asArray equals: #().

"test_linq_near_k_and_lambda_is_k_nearest_among_the_lambda_matches: near(k) and a block given to
 the leading where: steps is the k nearest among the elements the block accepts (ruling R27): one
 VectorSearch whose where holds the block, the oracle's answer with the block as its predicate;
 with a pure condition too, both restrict the search; a threshold-only near[] keeps the block as a
 BlockFilter on top (the same answer). The rule's scope (Addendum V 2.9): a block after a window
 step filters the window's result, and so does a block after an orderBy: that follows a window."
fails := OrderedCollection new.
elements := records value: (coords value: 200 value: 4 value: 13).
coll := (PBList new extend: elements) addIndex: (PBVectorIndex name: 'by_vec' path: 'vec' dim: 4 metric: 'l2').
fn := [:e | (e at: 'g') = 0].
(coords value: 5 value: 4 value: 14) do: [:v |
  query := ((PBQuery from: coll) where: (near near: v k: 4)) where: fn.
  got := query asArray.
  expect value: 'k among the block''s' value: { got size. got allSatisfy: fn. ids value: got }
    value: { 4. true. ids value: (oracle value: elements value: (nq value: v value: 4) value: 'l2' value: fn) }.
  info := query explain.
  expect value: 'one VectorSearch, its where the block' value: { info at: 'plan'. (info at: 'where') printString includesSubstring: 'block' }
    value: { 'VectorSearch'. true }].
q := (coords value: 1 value: 4 value: 15) first.
got := (((PBQuery from: coll) where: (near near: q k: 3) & ((PBField path: 'i') < 100)) where: [:e | (e at: 'g') = 1]) asArray.
expect value: 'a pure and an impure part, both restricting' value: (ids value: got)
  value: (ids value: (oracle value: elements value: (nq value: q value: 3) value: 'l2' value: [:e | (e at: 'i') < 100 and: [(e at: 'g') = 1]])).
query := ((PBQuery from: coll) where: (near near: q threshold: 1.0)) where: [:e | (e at: 'g') = 1].
expect value: 'threshold-only: a BlockFilter on top' value: { query explain at: 'plan'. ids value: query asArray }
  value: { 'BlockFilter'. ids value: (oracle value: elements value: (PBNearQuery vector: q threshold: 1.0) value: 'l2' value: [:e | (e at: 'g') = 1]) }.
query := (((PBQuery from: coll) where: (near near: q k: 6)) take: 6) where: fn.
info := query explain.
expect value: 'scope: a block after a window filters the window'
  value: { info at: 'plan'. ((info at: 'children') asArray first at: 'plan'). ids value: query asArray }
  value: { 'BlockFilter'. 'Limit'. ids value: ((oracle value: elements value: (nq value: q value: 6) value: 'l2' value: nil) select: fn) }.
query := ((((PBQuery from: coll) where: (near near: q k: 6)) skip: 0) orderBy: 'i') where: fn.
expect value: 'scope: a block after a window and an order filters the sorted window'
  value: { query explain at: 'plan'. query asArray collect: [:e | e at: 'i'] }
  value: { 'BlockFilter'. (((oracle value: elements value: (nq value: q value: 6) value: 'l2' value: nil) select: fn)
    collect: [:e | e at: 'i']) asSortedCollection asArray }.
query := (((PBQuery from: coll) orderBy: 'i') where: (near near: q k: 4)) where: fn.
expect value: 'an orderBy: inside the leading run keeps the rule, sorted on top'
  value: { (query explain at: 'plan'). ((query explain at: 'children') asArray first at: 'plan'). ids value: query asArray }
  value: { 'Sort'. 'VectorSearch'. ids value: (oracle value: elements value: (nq value: q value: 4) value: 'l2' value: fn) }.
c that: 'near(k) and a block in the leading where: steps is the k nearest among the block''s matches' is: fails asArray equals: #().

"test_python_predicate_expression_node: a PBBlockPredicate is equal to another wrapping the same
 block with the same description, describes itself { 'block' -> description } (DV5), holds no
 term, evaluates its block, is negated through De Morgan by normalize:, has no list form, refuses
 a malformed construction, and a residual filter evaluates it."
fails := OrderedCollection new.
fn := [:e | (e at: 'g') = 1].
p := PBBlockPredicate block: fn description: 'g is one'.
n := 0.
p termsDo: [:each | n := n + 1].
expect value: 'equality and hash' value: { p = (PBBlockPredicate block: fn description: 'g is one').
    p hash = (PBBlockPredicate block: fn description: 'g is one') hash.
    p = (PBBlockPredicate block: [:e | (e at: 'g') = 1] description: 'g is one') }
  value: #(true true false).
expect value: 'describe, terms, evaluate' value: { p describe = (PBFrozenDict withAssociations: { 'block' -> 'g is one' }). n.
    p evaluate: (PBObject withAll: { 'g' -> 1 }). p not evaluate: (PBObject withAll: { 'g' -> 1 }) }
  value: #(true 0 true false).
expect value: 'normalize:' value: (PBPlanner normalize: (p & (PBTerm path: 'x' op: '==' value: 1)) not)
  value: p not | (PBTerm path: 'x' op: '==' value: 1) not.
expect value: 'no list form' value: (refused value: [p asList] value: 'list') value: #(#PBNotSupportedError true).
expect value: 'malformed' value: ({ { 3. 'x' }. { fn. '' }. { PBTerm path: 'x' op: '==' value: 1. 'x' } } collect: [:args |
    (refused value: [PBBlockPredicate block: (args at: 1) description: (args at: 2)] value: '') first])
  value: #(#PBValidationError #PBValidationError #PBValidationError).
coll := PBList new extend: ((0 to: 8) asArray collect: [:i | PBObject withAll: { 'g' -> (i \\ 3) }]).
expect value: 'a residual filter evaluates it'
  value: (PBPlanner plan: coll where: (PBTerm path: 'g' op: '>=' value: 1) & p orderBy: nil limit: nil offset: 0) execute size
  value: 3.
c that: 'a block predicate is an opaque, comparable expression node a filter evaluates' is: fails asArray equals: #().

"test_near_without_a_vector_index_raises_instead_of_falling_back: with no vector index, a query
 holding near[] is PBNotSupportedError when it is planned, never a scan; near[] OR a block is
 PBNotSupportedError when where: is sent (test_linq.py:368-369, a lambda there). (Its
 computed-value case, F.v.lower().near, is a computed value, deferred by spec 3.2.)"
fails := OrderedCollection new.
coll := (PBList new extend: (records value: (coords value: 10 value: 2 value: 16))) addIndex: (PBEqualityIndex name: 'by_g' path: 'g').
expect value: 'refused' value: (refused value: [((PBQuery from: coll) where: (near near: #(1.0 0.0) k: 2)) asArray] value: 'near')
  value: #(#PBNotSupportedError true).
expect value: 'and its count' value: (refused value: [((PBQuery from: coll) where: (near near: #(1.0 0.0) k: 2)) count] value: 'near')
  value: #(#PBNotSupportedError true).
expect value: 'near OR a block, at where:' value: (refused value: [(PBQuery from: coll)
    where: (near near: #(1.0) k: 1) | (PBBlockPredicate block: [:r | true] description: 'block')] value: 'OR/NOT')
  value: #(#PBNotSupportedError true).
expect value: 'its text' value: ([(PBQuery from: coll)
    where: (near near: #(1.0) k: 1) | (PBBlockPredicate block: [:r | true] description: 'block')]
      on: PBNotSupportedError do: [:e | e return: e messageText])
  value: 'A ''near[]'' term cannot run inside a Python predicate (it is combined with one by OR/NOT in (vec near[] PBNearQuery(vector=(1.0,), k=1, threshold=None, metric=None)) | (block)): it has no per-element semantics; AND it at the top level instead'.
expect value: 'NOT (near AND a block), at where:' value: (refused value: [(PBQuery from: coll)
    where: ((near near: #(1.0 0.0) k: 2) & (PBBlockPredicate block: [:r | true] description: 'block')) not] value: 'OR/NOT')
  value: #(#PBNotSupportedError true).
expect value: 'a near[] hidden in a later impure where:' value: (refused value: [((PBQuery from: coll) where: (near near: #(1.0 0.0) k: 2))
    where: (near near: #(0.0 1.0) k: 2) | (PBBlockPredicate block: [:r | true] description: 'block')] value: 'OR/NOT')
  value: #(#PBNotSupportedError true).
c that: 'near[] without a vector index is PBNotSupportedError, never a scan, nor run inside a block' is: fails asArray equals: #().

"test_near_and_lambda_split_like_two_wheres: near(k) and a block are accepted by where: (no error
 until the query is planned); without a vector index the planner refuses, its text naming the
 index; near[] OR a block is refused by where:, its text naming OR/NOT (test_linq.py:749-750)."
fails := OrderedCollection new.
query := ((PBQuery from: coll) where: (near near: #(1.0 0.0) k: 2)) where: [:r | true].
expect value: 'no error at where:' value: (query isKindOf: PBQuery) value: true.
expect value: 'the planner refuses, naming the index' value: (refused value: [query asArray] value: 'index')
  value: #(#PBNotSupportedError true).
expect value: 'near OR a block: OR/NOT' value: (refused value: [(PBQuery from: coll)
    where: (near near: #(1.0) k: 1) | (PBBlockPredicate block: [:r | true] description: 'block')] value: 'OR/NOT')
  value: #(#PBNotSupportedError true).
c that: 'near(k) and a block: accepted by where:, refused by the planner without a vector index; near[] OR a block refused by where:' is: fails asArray equals: #().

c report displayNl.
