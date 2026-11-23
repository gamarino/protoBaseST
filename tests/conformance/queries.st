"EXPECT: query vectors ok"
"The query vectors of the indexed queries (plan Task 7, spec 6.2, plan call IP11):
 vectors-queries/, written once by tests/conformance/fetch_query_vectors.sh with proto_db at
 v2.0.0rc4 (tests/interop/py_query_vectors.py, whose docstring states the database, the cases and
 the oracle each recorded answer was checked against). Every file is checked against
 manifest.sha256 first, and the space is read from a copy under out/queries (git ignores out/; a
 new directory per run, nothing removed).

 For every case of queries.msgpack, PBPlanner plans the same root (or its scan, or a PBDistinct of
 its scan) with the same condition (the 0.1 list syntax, decoded from its wire form), order (a
 PBSortKey per [path, descending]), limit and offset, and puts the same node on top (PBCountPlan,
 PBDistinct, PBProject in both forms, PBIntersect with a second planned condition, a PBBlockFilter
 of the even ids). Then:
   - the plan tree is proto_db's: node for node, the explain of each node without its estimate and
     children has the same MessagePack bytes (a BlockFilter is proto_db's PythonFilter: deviation
     'BlockFilter'), and each node's estimate rows and cost equal proto_db's within plan call IP8
     (|a - b| <= 1e-12 * max(|a|, |b|)); so the access path, the index chosen and every cost agree;
   - the rows, in order, are proto_db's (a record by its id, a Count's row by its number, any other
     value by its wire form). This holds for the vector cases too (vectors phase V7, Addendum V
     5.3: near[] alone, with k, a threshold or both; with a condition, as a VectorSearch's where or
     a Filter over it; two near[] terms, an Intersect; near[] in a disjunction, a forced Union; an
     order, a window, a count), and is stricter than the rule of 5.3, which needs the order only
     where proto_db defines one (a VectorSearch and a Filter directly over one): the other nodes
     (Intersect, Union, a Sort's ties) are deterministic ports, so their order is checked too.
     Over the IVF root probing fewer lists than it has (approximate by design) the rows must be
     proto_db's exactly as well: both read the same stored centroids;
   - a refused vector case (its 'error', the class proto_db refused it with) is refused with the
     same class (ProtoNotSupportedError is PBNotSupportedError): when its 'error_at' is 'plan',
     PBPlanner refuses it (no supporting index for its metric, a negated near[], a plan source
     without indexes); when it is 'execute', the plan is built, its tree is proto_db's as above,
     and its execution is refused (the hnsw root: deviation DV1, proto_db's refusal without
     hnswlib). A planning refusal's text ('error_text') is proto_db's, byte for byte: a term or a
     near query it quotes is written as proto_db's repr writes it, Term(path='vec', op='near[]',
     value=NearQuery(...)) (PBCodec _pyRepr:). An execution refusal's text is not compared: the
     hnsw text is rewritten for protoST (DV8);
   - a different tree is a near tie only when it is a different choice (the sequence of node
     names and index names differs: a node that differs in anything else is a defect) and the root
     costs agree within IP8 but are not bit-equal (ruling IQ4, deviation R2: a log2 that differs in
     the last bit can reorder two candidates of equal model cost; bit-equal costs ranked otherwise
     are a tie-break defect and fail); a near tie fails unless its case is in the allowlist below
     with its reason, and the number of near ties must be the expected one (0); it is reported by name, and its rows must still be proto_db's as a multiset (or, with a
     window, as many); any other difference fails.
 It prints proto_db's mode (numpy and hnswlib blocked, its CPython and C library), the refusals,
 'near ties: N', the case count, then 'query vectors ok'."
Import from: 'protobase'.

"Refuses atoms: the cases' values have none."
Object subclass: #NoAtoms.

NoAtoms >> refTo: aSegmentBytes offset: anInteger tag: aTag
  ^ Error signal: 'the query vectors hold no atom references'.

| dir manifest blob data space db snap roots extractor fails nearTies tree closeTo nodeBytes rowBytes sameTree
  decode keysOf count atomRef out choicesOf theirChoicesOf allowedTies expectedNearTies refusalClasses refusals planOf |
dir := 'vectors-queries'.
fails := OrderedCollection new.
nearTies := OrderedCollection new.
manifest := ((dir , '/manifest.sha256') asFileReference contents lines reject: [:line | line isEmpty])
  collect: [:line | { line copyFrom: 1 to: 64. line copyFrom: 67 to: line size }].
manifest do: [:entry |
  ((dir , '/' , (entry at: 2)) asFileReference binaryContents sha256 hex asLowercase) = (entry at: 1) ifFalse: [
    Error signal: dir , '/' , (entry at: 2) , ' does not match manifest.sha256']].
(manifest anySatisfy: [:entry | (entry at: 2) = 'queries.msgpack']) ifFalse: [Error signal: 'manifest.sha256 does not list queries.msgpack'].
out := 'out/queries' asFileReference / ('run-' , Smalltalk pid printString , '-' , Time microsecondClockValue printString).
manifest do: [:entry |
  ((entry at: 2) beginsWith: 'space/') ifTrue: [ | target |
    target := out / (entry at: 2).
    target parent ensureCreateDirectory.
    target binaryContents: (dir , '/' , (entry at: 2)) asFileReference binaryContents]].
blob := (dir , '/queries.msgpack') asFileReference binaryContents.
data := MessagePack decode: blob.
extractor := data at: 'extractor'.
"py_query_vectors.py name_len: the length of name, PBMissing when name is not a String."
PBKeySpec registerExtractor: extractor block: [:e | | name |
  name := (PBKeySpec path: 'name') extract: e.
  (name isString and: [name isSymbol not]) ifTrue: [name size] ifFalse: [PBMissing default]] version: '1'.
space := PBObjectSpace storage: (PBFileStorage path: (out / 'space') pathString).
db := space openDatabase: 'queries'.
snap := db snapshotAt: db history first.
roots := Dictionary new.

"IP8."
closeTo := [:a :b | (a - b) abs <= (1.0e-12 * (a abs max: b abs))].
"A description or explain as a MessagePack tree (PBFrozenDict to MessagePackMap, lists to Arrays)."
tree := nil.
tree := [:d |
  (d isKindOf: PBFrozenDict)
    ifTrue: [MessagePackMap withAll: (d associations collect: [:each | each key -> (tree value: each value)])]
    ifFalse: [((d isKindOf: Array) or: [d isKindOf: PBFrozenList])
      ifTrue: [d asArray collect: [:each | tree value: each]]
      ifFalse: [d]]].
"The MessagePack bytes of an explain without its estimate and children, BlockFilter written as
 proto_db's PythonFilter."
nodeBytes := [:info |
  MessagePack encode: (tree value: (PBFrozenDict withAssociations: ((info associations
    reject: [:a | a key = 'estimate' or: [a key = 'children']])
    collect: [:a | (a key = 'plan' and: [a value = 'BlockFilter']) ifTrue: ['plan' -> 'PythonFilter'] ifFalse: [a]])))].
"Whether the explain anInfo is proto_db's tree aNode (the class comment); mismatches go to aList."
sameTree := nil.
sameTree := [:info :node :aList | | est kids theirs |
  est := info at: 'estimate'.
  theirs := node at: 'estimate'.
  (nodeBytes value: info) = (node at: 'node') ifFalse: [aList add: (info at: 'plan') , ' differs from proto_db''s node'].
  ((closeTo value: (est at: 'rows') value: (theirs at: 1)) and: [closeTo value: (est at: 'cost') value: (theirs at: 2)]) ifFalse: [
    aList add: (info at: 'plan') , ' estimate ' , { est at: 'rows'. est at: 'cost' } printString , ', proto_db ' , theirs printString].
  kids := (info at: 'children') asArray.
  kids size = (node at: 'children') size
    ifFalse: [aList add: (info at: 'plan') , ' has ' , kids size printString , ' children']
    ifTrue: [kids with: (node at: 'children') do: [:kid :theirKid | sameTree value: kid value: theirKid value: aList]].
  aList isEmpty].
"The choices of a plan tree, depth first: each node's name (BlockFilter as PythonFilter) and the
 index it reads, if any. A near tie must differ here: a node that differs in anything else is a
 defect, whatever the costs."
choicesOf := nil.
choicesOf := [:info | | name index out |
  name := (info at: 'plan') = 'BlockFilter' ifTrue: ['PythonFilter'] ifFalse: [info at: 'plan'].
  index := (info includesKey: 'index') ifTrue: [(info at: 'index') at: 'index'] ifFalse: [nil].
  out := OrderedCollection with: { name. index }.
  (info at: 'children') do: [:kid | out addAll: (choicesOf value: kid)].
  out asArray].
theirChoicesOf := nil.
theirChoicesOf := [:node | | info out |
  info := MessagePack decode: (node at: 'node').
  out := OrderedCollection with: { info at: 'plan'. (info includesKey: 'index') ifTrue: [(info at: 'index') at: 'index'] ifFalse: [nil] }.
  (node at: 'children') do: [:kid | out addAll: (theirChoicesOf value: kid)].
  out asArray].
atomRef := [:anAtom | Error signal: 'an atom in a row that is not a record'].
"py_query_vectors.py row_bytes."
rowBytes := [:row :counted |
  counted
    ifTrue: [MessagePack encode: { 'n'. row }]
    ifFalse: [(row isKindOf: PBObject)
      ifTrue: [MessagePack encode: { 'id'. row at: 'id' }]
      ifFalse: [MessagePack encode: { 'v'. PBCodec toWire: row atomRef: atomRef }]]].
decode := [:bytes | PBCodec fromWire: (MessagePack decodeOrdered: bytes strictKeys: false) resolver: NoAtoms new].
keysOf := [:order | order isNil ifTrue: [nil] ifFalse: [order asArray collect: [:pair | PBSortKey key: (pair at: 1) descending: (pair at: 2)]]].
"proto_db's refusal classes, as protoBaseST names them."
refusalClasses := Dictionary new.
refusalClasses at: 'ProtoNotSupportedError' put: PBNotSupportedError; at: 'ProtoValidationError' put: PBValidationError.
refusals := 0.
"The near ties this vector set is known to have, each case id with its reason (ruling IQ4,
 deviation R2); any other near tie fails, and so does a change of their number. Measured at Task 7:
 none."
allowedTies := Dictionary new.
expectedNearTies := 0.
count := 0.
(data at: 'cases') do: [:case |
  | id coll source where plan wrap mine problems rootCost theirCost got want errorClass errorAt refusedBy |
  id := case at: 'id'.
  [coll := roots at: (case at: 'root') ifAbsentPut: [snap getRootObject: (case at: 'root')].
   source := (case at: 'source') = 'collection' ifTrue: [coll] ifFalse: [
     (case at: 'source') = 'scan' ifTrue: [coll asQueryPlan] ifFalse: [PBDistinct source: coll asQueryPlan]].
   where := (case at: 'where') isNil ifTrue: [nil] ifFalse: [decode value: (case at: 'where')].
   errorClass := (case at: 'error' ifAbsent: [nil]) isNil ifTrue: [nil] ifFalse: [refusalClasses at: (case at: 'error')].
   errorAt := case at: 'error_at' ifAbsent: [nil].
   planOf := [PBPlanner plan: source where: where orderBy: (keysOf value: (case at: 'order')) limit: (case at: 'limit') offset: (case at: 'offset')].
   errorAt = 'plan'
     ifTrue: [
       refusedBy := [planOf value. nil] on: Error do: [:e | e return: { e class. e messageText }].
       (refusedBy notNil and: [(refusedBy at: 1) == errorClass])
         ifFalse: [fails add: id , ': planning answered ' , refusedBy printString , ', proto_db refused it with ' , (case at: 'error')]
         ifTrue: [(refusedBy at: 2) = (case at: 'error_text') ifFalse: [
           fails add: id , ': the refusal text ' , (refusedBy at: 2) printString , ' is not proto_db''s '
             , (case at: 'error_text') printString]].
       refusals := refusals + 1.
       plan := nil]
     ifFalse: [plan := planOf value].
   wrap := case at: 'wrap'.
   plan isNil ifFalse: [
     wrap = 'count' ifTrue: [plan := PBCountPlan source: plan].
     wrap = 'distinct' ifTrue: [plan := PBDistinct source: plan].
     wrap = 'block_even' ifTrue: [plan := PBBlockFilter source: plan predicate: (PBBlockPredicate block: [:e | (e at: 'id') even] description: 'even id')].
     (wrap isString not and: [wrap notNil]) ifTrue: [
       (wrap at: 1) = 'project' ifTrue: [plan := PBProject source: plan fields: (wrap at: 2) asArray].
       (wrap at: 1) = 'project_map' ifTrue: [plan := PBProject source: plan fields: (PBFrozenDict withAssociations: ((wrap at: 2) asArray collect: [:pair | (pair at: 1) -> (pair at: 2)]))].
       (wrap at: 1) = 'intersect' ifTrue: [plan := PBIntersect withAll: { plan. PBPlanner plan: coll where: (decode value: (wrap at: 2)) orderBy: nil limit: nil offset: 0 }]]].
   problems := OrderedCollection new.
   errorAt = 'execute' ifTrue: [
     (sameTree value: plan explain value: (case at: 'plan') value: problems) ifFalse: [
       fails add: id , ': ' , problems first].
     refusedBy := [plan execute. nil] on: Error do: [:e | e return: e class].
     refusedBy == errorClass ifFalse: [
       fails add: id , ': its execution answered ' , refusedBy printString , ', proto_db refused it with ' , (case at: 'error')].
     refusals := refusals + 1].
   (errorAt = 'plan' or: [errorAt = 'execute']) ifFalse: [
     got := plan execute collect: [:row | rowBytes value: row value: wrap = 'count'].
     want := (case at: 'rows') asArray.
     (sameTree value: plan explain value: (case at: 'plan') value: problems)
       ifTrue: [got = want ifFalse: [fails add: id , ': the rows differ from proto_db''s']]
       ifFalse: [
         rootCost := plan estimate cost.
         theirCost := ((case at: 'plan') at: 'estimate') at: 2.
         ((closeTo value: rootCost value: theirCost)
             and: [(choicesOf value: plan explain) ~= (theirChoicesOf value: (case at: 'plan'))])
           ifTrue: [
             nearTies add: id.
             rootCost = theirCost ifTrue: [
               fails add: id , ': another plan at a bit-equal cost (' , rootCost printString
                 , '): R2 cannot explain it, only a tie-break defect can'].
             (allowedTies includesKey: id) ifFalse: [
               fails add: id , ': a near tie not in the allowlist (proto_db chose ' , (theirChoicesOf value: (case at: 'plan')) printString , ')'].
             ((case at: 'limit') isNil and: [(case at: 'offset') = 0])
               ifTrue: [(got asSortedCollection: [:a :b | a hex <= b hex]) asArray = (want asSortedCollection: [:a :b | a hex <= b hex]) asArray
                 ifFalse: [fails add: id , ': a near tie whose rows differ from proto_db''s']]
               ifFalse: [got size = want size ifFalse: [fails add: id , ': a near tie whose window differs in size']]]
           ifFalse: [fails add: id , ': ' , problems first , ' (root cost ' , rootCost printString , ', proto_db ' , theirCost printString , ')']]].
   count := count + 1]
    on: Error do: [:e | fails add: id , ': ' , e class name , ': ' , e messageText printString. e return: nil]].
space close.
count = (data at: 'cases') size ifFalse: [fails add: 'only ' , count printString , ' cases ran'].
nearTies size = expectedNearTies ifFalse: [
  fails add: nearTies size printString , ' near ties, ' , expectedNearTies printString , ' expected'].
(allowedTies keys reject: [:each | nearTies includes: each]) do: [:each |
  fails add: 'the allowed near tie ' , each , ' did not occur (a stale allowlist entry)'].
('proto_db mode: ' , (', ' join: (data at: 'mode' ifAbsent: [#('unrecorded')]))) displayNl.
('refusals: ' , refusals printString) displayNl.
nearTies do: [:each | ('near tie: ' , each) displayNl].
('near ties: ' , nearTies size printString) displayNl.
('cases: ' , count printString) displayNl.
fails do: [:each | ('FAIL ' , each) displayNl].
(fails isEmpty ifTrue: ['query vectors ok'] ifFalse: ['failed']) displayNl.
