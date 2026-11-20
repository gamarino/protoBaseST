"-- plans.st: the physical query plans, their estimates and explain --

A port of proto_db's proto_db/query/plans.py at v2.0.0rc4, lines 75-880 (spec section 10, rulings
R5 and R19, decisions D29, D30, D36 and D56), less ValuesScan, VectorSearch, GroupBy, Join and
Unnest (design spec 3.2 and 3.3).

Every plan is a PBQueryPlan, immutable once built and holding only immutable inputs (collection
and index versions, frozen expressions, the caller's blocks), so it runs many times and on any
actor:

  do: aBlock          the rows one by one, lazily: a non-local return from aBlock stops the plan
                      (plan call IP9)
  execute             a new Array of the rows, each time
  explain             a PBFrozenDict in proto_db's shape: 'plan' (the node name), the node's own
                      fields, 'estimate' ({ 'rows'. 'cost' }) and 'children' (the explains of its
                      sources); lists are PBFrozenLists (what a decoded MessagePack list is), so
                      PBNotation describe: prints it and it compares with proto_db's explain
  estimate            a PBEstimate: rows and an abstract cost (the cost model D30)
  windowFrom: start to: stop
                      rows start .. stop - 1 of execute (stop nil: to the end) as a new Array:
                      sought by rank when the plan offers rank access (D56), otherwise read
                      through do:; start and stop are non-negative Integers (stop may be nil),
                      else PBValidationError
  byRank              whether the plan offers rank access (proto_db: window(0, 0) is not None)
  exactRows           the exact number of rows when known without producing them, or nil

The nodes, by explain name:

  CollectionScan      PBCollectionScan on: aCollection (aCollection asQueryPlan)
  IndexLookup, IndexRange, IndexComplement, IndexOrderedScan
                      PBIndexPlan index: anIndex term: aTermOrNil part: aPBIndexPart, built by the
                      indexes' plan: and orderedPlan:descending:
  Filter              PBFilter source: aPlan terms: anArray (the conjunction of anArray's
                      expressions, or the 0.1 list syntax: PBExpression compile:)
  BlockFilter         PBBlockFilter source: aPlan predicate: aPBBlockPredicate (proto_db's
                      PythonFilter)
  Union, Intersect    PBUnion withAll: plans, PBIntersect withAll: plans (two or more)
  Project             PBProject source: aPlan fields: anArrayOfPathsOrABlock, and
                      source:fields:description: for a block
  Sort                PBSort source: aPlan keys: anArrayOfPBSortKeys
  Limit               PBLimit source: aPlan limit: anIntegerOrNil offset: anInteger
  Count               PBCountPlan source: aPlan
  Distinct            PBDistinct source: aPlan

PBCost log2: is the one place a logarithm is computed (plan call IP7). Element identity for
Union, Intersect and Distinct is proto_db's element_key, (element_identity, exact_token): the order
key of the element's member key (PBMemberKeys), so 1, 1.0 and Decimal 1 are three elements, an atom
is identified by its oid. No node catches an error: an error of a source, a predicate or a block
reaches the caller."

Import from: 'protobase/errors'.
Import from: 'protobase/keys'.
Import from: 'protobase/values'.
Import from: 'protobase/keyspec'.
Import from: 'protobase/avl'.
Import from: 'protobase/keygroups'.
Import from: 'protobase/collections'.
Import from: 'protobase/indexes'.
Import from: 'protobase/terms'.

Object subclass: #PBCost.
Object subclass: #PBEstimate instanceVariableNames: 'rows cost'.
Object subclass: #PBRankAccess instanceVariableNames: 'segments'.
Object subclass: #PBIndexPart instanceVariableNames: 'kind producer estimate details rank sortedRank'.
Object subclass: #PBSortKey instanceVariableNames: 'key descending spec description'.
Object subclass: #PBQueryPlan.
PBQueryPlan subclass: #PBCollectionScan instanceVariableNames: 'collection'.
PBQueryPlan subclass: #PBIndexPlan instanceVariableNames: 'index term part'.
PBQueryPlan subclass: #_PBOneSourcePlan instanceVariableNames: 'source'.
_PBOneSourcePlan subclass: #PBFilter instanceVariableNames: 'predicate'.
_PBOneSourcePlan subclass: #PBBlockFilter instanceVariableNames: 'predicate'.
_PBOneSourcePlan subclass: #PBProject instanceVariableNames: 'fields block description'.
_PBOneSourcePlan subclass: #PBSort instanceVariableNames: 'keys'.
_PBOneSourcePlan subclass: #PBLimit instanceVariableNames: 'limit offset'.
_PBOneSourcePlan subclass: #PBCountPlan.
_PBOneSourcePlan subclass: #PBDistinct.
PBQueryPlan subclass: #_PBSetPlan instanceVariableNames: 'sources'.
_PBSetPlan subclass: #PBUnion.
_PBSetPlan subclass: #PBIntersect.

"=== PBCost and PBEstimate ===================================================="

"plans.py FILTER_SELECTIVITY: the fraction of rows one term (or one block) is estimated to keep."
PBCost class >> filterSelectivity
  ^ 0.5.

"log2 of aNumber as a Float, the descent term of the cost model (plan call IP7): protoST's log:
 is ln x / ln 2, which can differ from C's log2 in the last bit (deviation R2, ruling IQ4)."
PBCost class >> log2: aNumber
  ^ aNumber asFloat log: 2.

"A planner estimate (plans.py Estimate): rows and cost, each an Integer or a Float that is finite
 and not negative, kept as a Float; anything else is PBValidationError."
PBEstimate class >> rows: aRows cost: aCost
  ^ self basicNew _setRows: (self _check: aRows named: 'rows') cost: (self _check: aCost named: 'cost').

PBEstimate class >> _check: aNumber named: aName
  ((aNumber isClassObject not and: [aNumber isInteger or: [aNumber isFloat]]) and: [aNumber ~~ true and: [aNumber ~~ false]]) ifFalse: [
    ^ PBValidationError signal: 'PBEstimate ' , aName , ' must be an Integer or a Float, not ' , (PBKeySpec _repr: aNumber)].
  ((aNumber isFloat and: [aNumber isNaN or: [aNumber isInfinite]]) or: [aNumber < 0]) ifTrue: [
    ^ PBValidationError signal: 'PBEstimate ' , aName , ' must be finite and non-negative, not ' , (PBKeySpec _repr: aNumber)].
  ^ aNumber asFloat.

PBEstimate >> _setRows: aRows cost: aCost
  "Runs once, on a fresh instance."
  rows isNil ifFalse: [^ PBUserError signal: 'PBEstimate is immutable'].
  rows := aRows.
  cost := aCost.
  ^ self.

PBEstimate >> rows
  ^ rows.

PBEstimate >> cost
  ^ cost.

"{ 'rows'. 'cost' } for explain (plans.py Estimate.describe)."
PBEstimate >> describe
  ^ PBFrozenDict withAssociations: { 'rows' -> rows. 'cost' -> cost }.

PBEstimate >> = anObject
  (anObject isClassObject not and: [anObject class == PBEstimate]) ifFalse: [^ false].
  ^ rows = anObject rows and: [cost = anObject cost].

PBEstimate >> hash
  ^ (rows hash bitXor: cost hash) \\ 1073741824.

PBEstimate >> printOn: aStream
  aStream nextPutAll: 'PBEstimate(rows: '; print: rows; nextPutAll: ', cost: '; print: cost; nextPut: $).

"=== PBRankAccess: rank access over index segments (keyed.py _rank_access, D56) ====="

"Rank access to the rows the segments aBlock answers (PBKeyGroups' segments, computed when asked,
 from the immutable trees of one index version)."
PBRankAccess class >> segments: aBlock
  ^ self basicNew _setSegments: aBlock.

PBRankAccess >> _setSegments: aBlock
  "Runs once, on a fresh instance."
  segments isNil ifFalse: [^ PBUserError signal: 'PBRankAccess is immutable'].
  segments := aBlock.
  ^ self.

"Rows aStart .. aStop - 1 (aStop nil: to the end), a new Array."
PBRankAccess >> windowFrom: aStart to: aStop
  ^ PBKeyGroups window: segments value from: aStart to: aStop.

"The exact number of rows."
PBRankAccess >> rows
  ^ PBKeyGroups rowsOfSegments: segments value.

"=== PBIndexPart: how an index answers one access path (plans.py IndexPlan's arguments) ==="

"An access path of an index: aKind (a non-empty String: 'IndexLookup', 'IndexRange',
 'IndexComplement', 'IndexOrderedScan'), aProducer (a block of one argument, evaluated with a block
 that it evaluates with each row, holding only immutable state)."
PBIndexPart class >> kind: aKind producer: aProducer
  ^ self kind: aKind producer: aProducer estimate: nil details: nil rank: nil sortedRank: nil.

"With an explicit estimate (required when the plan has no term), details for explain (a
 PBFrozenDict that may not redefine 'plan', 'index', 'term', 'estimate' or 'children')."
PBIndexPart class >> kind: aKind producer: aProducer estimate: anEstimate details: aDetails
  ^ self kind: aKind producer: aProducer estimate: anEstimate details: aDetails rank: nil sortedRank: nil.

"With rank access (a PBRankAccess, or nil) and sortedRank (a block of a key spec and a Boolean
 answering a PBRankAccess to the rows in the order a stable Sort by that key spec gives them, or
 nil; plans.py IndexPlan sorted_rank). PBValidationError for a malformed argument (plans.py
 IndexPlan.__init__)."
PBIndexPart class >> kind: aKind producer: aProducer estimate: anEstimate details: aDetails rank: aRank sortedRank: aSortedRank
  | clash |
  ((aProducer isClassObject not and: [aProducer isKindOf: BlockClosure]) and: [aProducer numArgs = 1]) ifFalse: [
    ^ PBValidationError signal: 'PBIndexPart needs a producer block of one argument, not ' , (PBKeySpec _repr: aProducer)].
  ((PBExpression _isText: aKind) and: [aKind notEmpty]) ifFalse: [
    ^ PBValidationError signal: 'PBIndexPart kind must be a non-empty String, not ' , (PBKeySpec _repr: aKind)].
  (anEstimate isNil or: [anEstimate isClassObject not and: [anEstimate isKindOf: PBEstimate]]) ifFalse: [
    ^ PBValidationError signal: 'PBIndexPart estimate must be a PBEstimate, not ' , (PBKeySpec _repr: anEstimate)].
  (aDetails isNil or: [aDetails isClassObject not and: [aDetails isKindOf: PBFrozenDict]]) ifFalse: [
    ^ PBValidationError signal: 'PBIndexPart details must be a PBFrozenDict, not ' , (PBKeySpec _repr: aDetails)].
  clash := aDetails isNil ifTrue: [#()] ifFalse: [
    #('children' 'estimate' 'index' 'plan' 'term') select: [:k | aDetails includesKey: k]].
  clash isEmpty ifFalse: [^ PBValidationError signal: 'PBIndexPart details may not redefine ' , clash printString].
  (aRank isNil or: [aRank isClassObject not and: [aRank isKindOf: PBRankAccess]]) ifFalse: [
    ^ PBValidationError signal: 'PBIndexPart rank must be a PBRankAccess, not ' , (PBKeySpec _repr: aRank)].
  (aSortedRank isNil or: [(aSortedRank isClassObject not and: [aSortedRank isKindOf: BlockClosure]) and: [aSortedRank numArgs = 2]]) ifFalse: [
    ^ PBValidationError signal: 'PBIndexPart sortedRank must be a block of two arguments, not ' , (PBKeySpec _repr: aSortedRank)].
  ^ self basicNew _setKind: aKind copy producer: aProducer estimate: anEstimate
    details: (aDetails isNil ifTrue: [PBFrozenDict withAssociations: #()] ifFalse: [aDetails]) rank: aRank sortedRank: aSortedRank.

PBIndexPart >> _setKind: aKind producer: aProducer estimate: anEstimate details: aDetails rank: aRank sortedRank: aSortedRank
  "Runs once, on a fresh instance."
  kind isNil ifFalse: [^ PBUserError signal: 'PBIndexPart is immutable'].
  kind := aKind.
  producer := aProducer.
  estimate := anEstimate.
  details := aDetails.
  rank := aRank.
  sortedRank := aSortedRank.
  ^ self.

PBIndexPart >> kind
  ^ kind.

PBIndexPart >> producer
  ^ producer.

"The explicit estimate, or nil (the index's estimate: of the term then)."
PBIndexPart >> estimate
  ^ estimate.

PBIndexPart >> details
  ^ details.

PBIndexPart >> rank
  ^ rank.

"The PBRankAccess to the rows in the order a stable Sort by aKeySpec, descending when aBoolean,
 gives them, or nil."
PBIndexPart >> sortedRank: aKeySpec descending: aBoolean
  ^ sortedRank isNil ifTrue: [nil] ifFalse: [sortedRank value: aKeySpec value: aBoolean].

"=== PBSortKey (plan call IP14) =============================================="

"A sort key: a path (a String, nil for the element itself, '@name' for an extractor; PBKeySpec
 forTermPath:), a PBKeySpec, or a block of one argument (described as 'block'); descending a
 Boolean. Anything else is PBValidationError (plans.py Sort and _key_function)."
PBSortKey class >> key: aPathOrFieldOrBlock descending: aBoolean
  ^ self key: aPathOrFieldOrBlock descending: aBoolean description: nil.

"As key:descending:, aDescription (a non-empty String, or nil) naming a block key in explain
 (plans.py Sort's description of a callable key); a path or key spec is described by its key
 spec."
PBSortKey class >> key: aPathOrFieldOrBlock descending: aBoolean description: aDescription
  | spec described |
  (aBoolean == true or: [aBoolean == false]) ifFalse: [
    ^ PBValidationError signal: 'Sort descending flag must be a Boolean, not ' , (PBKeySpec _repr: aBoolean)].
  (aDescription isNil or: [(PBExpression _isText: aDescription) and: [aDescription notEmpty]]) ifFalse: [
    ^ PBValidationError signal: 'Sort key description must be a non-empty String, not ' , (PBKeySpec _repr: aDescription)].
  (aPathOrFieldOrBlock isClassObject not and: [aPathOrFieldOrBlock isKindOf: BlockClosure]) ifTrue: [
    aPathOrFieldOrBlock numArgs = 1 ifFalse: [
      ^ PBValidationError signal: 'A sort key block takes one argument, not ' , aPathOrFieldOrBlock numArgs printString].
    ^ self basicNew _setKey: aPathOrFieldOrBlock descending: aBoolean spec: nil
      description: (aDescription isNil ifTrue: ['block'] ifFalse: [aDescription copy])].
  aDescription isNil ifFalse: [^ PBValidationError signal: 'Sort key descriptions label block keys only'].
  spec := (aPathOrFieldOrBlock isClassObject not and: [aPathOrFieldOrBlock isKindOf: PBKeySpec])
    ifTrue: [aPathOrFieldOrBlock]
    ifFalse: [
      (aPathOrFieldOrBlock isNil or: [PBExpression _isText: aPathOrFieldOrBlock]) ifFalse: [
        ^ PBValidationError signal: 'A sort key is a path (a String or nil), a PBKeySpec or a block of one argument, not '
          , (PBKeySpec _repr: aPathOrFieldOrBlock)].
      PBKeySpec forTermPath: aPathOrFieldOrBlock].
  described := spec describe.
  ^ self basicNew _setKey: aPathOrFieldOrBlock descending: aBoolean spec: spec description: described.

PBSortKey >> _setKey: aKey descending: aBoolean spec: aSpec description: aDescription
  "Runs once, on a fresh instance."
  descending isNil ifFalse: [^ PBUserError signal: 'PBSortKey is immutable'].
  key := aKey.
  descending := aBoolean.
  spec := aSpec.
  description := aDescription.
  ^ self.

"The key as given."
PBSortKey >> key
  ^ key.

PBSortKey >> descending
  ^ descending.

"The PBKeySpec of a path or key spec key; nil for a block."
PBSortKey >> keySpecObject
  ^ spec.

"How explain names the key: the key spec's describe, or the block's description."
PBSortKey >> describe
  ^ description.

"The key of anElement: the key spec's extract:, or the block's answer."
PBSortKey >> extract: anElement
  ^ spec isNil ifTrue: [key value: anElement] ifFalse: [spec extract: anElement].

"=== PBQueryPlan ============================================================="

"An abstract plan: a node is built by its own constructor (plans.py QueryPlan is abstract)."
PBQueryPlan class >> new
  ^ PBUserError signal: self name , ' is abstract or built by its own constructor: use a node''s constructor'.

"aPlan, or PBValidationError naming anOwner (plans.py _check_plan)."
PBQueryPlan class >> _check: aPlan owner: anOwner
  (aPlan isClassObject not and: [aPlan isKindOf: PBQueryPlan]) ifFalse: [
    ^ PBValidationError signal: anOwner , ' needs a PBQueryPlan source, not ' , (PBKeySpec _repr: aPlan)].
  ^ aPlan.

"aValue with every Array and OrderedCollection made a PBFrozenList, at any depth through
 PBFrozenDicts and lists: explain's lists are what a decoded MessagePack list is."
PBQueryPlan class >> _frozen: aValue
  ^ _PBValueFrame fold: aValue
    children: [:v |
      (v isClassObject not and: [(v isKindOf: Array) or: [(v isKindOf: OrderedCollection) or: [v isKindOf: PBFrozenList]]])
        ifTrue: [v asArray]
        ifFalse: [
          (v isClassObject not and: [v isKindOf: PBFrozenDict])
            ifTrue: [v keys asArray , (v keys asArray collect: [:k | v at: k])]
            ifFalse: [nil]]]
    leaf: [:v | v]
    node: [:v :results |
      (v isKindOf: PBFrozenDict)
        ifTrue: [ | n |
          n := results size // 2.
          PBFrozenDict withAssociations: ((1 to: n) asArray collect: [:i | (results at: i) -> (results at: n + i)])]
        ifFalse: [PBFrozenList withAll: results asArray]].

"Evaluates aBlock with each row, lazily. Every node answers it."
PBQueryPlan >> do: aBlock
  ^ self subclassResponsibility.

"A new Array of the rows (plans.py execute: a new iterator per call)."
PBQueryPlan >> execute
  | out |
  out := OrderedCollection new.
  self do: [:each | out addLast: each].
  ^ out asArray.

"The planner's estimate."
PBQueryPlan >> estimate
  ^ self _estimateIn: nil.

"The estimate, computed once per node of one explain when aMemo is a Dictionary (plans.py _est
 with _explain_memo): a node reads its sources' estimates through the memo, so an explain is
 linear in the plan's size. With aMemo nil, computed directly."
PBQueryPlan >> _estimateIn: aMemo
  aMemo isNil ifTrue: [^ self _estimateWith: nil].
  ^ aMemo at: self ifAbsent: [aMemo at: self put: (self _estimateWith: aMemo)].

"The estimate of this node from its sources' estimates, each read by _estimateIn: aMemo. Every
 node answers it."
PBQueryPlan >> _estimateWith: aMemo
  ^ self subclassResponsibility.

"The explain of this plan (plans.py explain): estimates are computed once per node and explain
 (plans.py _explain_memo, as a local memo)."
PBQueryPlan >> explain
  ^ self _explainWith: Dictionary new.

PBQueryPlan >> _explainWith: aMemo
  ^ self subclassResponsibility.

"The estimate of aPlan, computed once per explain."
PBQueryPlan >> _estimateOf: aPlan memo: aMemo
  ^ aPlan _estimateIn: aMemo.

"The common explain shape (plans.py _explain): { 'plan' -> aName. anArray of Associations (the
 node's fields). 'estimate'. 'children' }."
PBQueryPlan >> _explain: aName params: anArray children: aPlans memo: aMemo
  ^ PBFrozenDict withAssociations: { 'plan' -> aName } , (anArray collect: [:each | each key -> (PBQueryPlan _frozen: each value)]) , {
    'estimate' -> (self _estimateOf: self memo: aMemo) describe.
    'children' -> (PBFrozenList withAll: (aPlans collect: [:each | each _explainWith: aMemo])) }.

"Rows aStart .. aStop - 1 by rank, a new Array, or nil when the plan cannot seek (plans.py window;
 the default). The bounds are checked by the caller."
PBQueryPlan >> _rankWindowFrom: aStart to: aStop
  ^ nil.

"The exact number of rows when known without producing them; nil otherwise (plans.py
 exact_rows)."
PBQueryPlan >> exactRows
  ^ nil.

"Whether the plan offers rank access (plans.py: window(0, 0) is not None)."
PBQueryPlan >> byRank
  ^ (self _rankWindowFrom: 0 to: 0) notNil.

"Rows aStart .. aStop - 1 of execute (aStop nil: to the end), a new Array: by rank when the plan
 offers it, otherwise through do:, stopping after the window. PBValidationError for bounds that are
 not non-negative Integers (plans.py _check_window)."
PBQueryPlan >> windowFrom: aStart to: aStop
  | rows out n |
  self _checkWindowFrom: aStart to: aStop.
  rows := self _rankWindowFrom: aStart to: aStop.
  rows isNil ifFalse: [^ rows].
  (aStop notNil and: [aStop <= aStart]) ifTrue: [^ Array new: 0].
  out := OrderedCollection new.
  n := 0.
  self _rows: [:each |
      n >= aStart ifTrue: [out addLast: each].
      n := n + 1.
      aStop notNil and: [n >= aStop]].
  ^ out asArray.

"Evaluates aBlock with each row until it answers true."
PBQueryPlan >> _rows: aBlock
  self do: [:each | (aBlock value: each) ifTrue: [^ self]].

PBQueryPlan >> _checkWindowFrom: aStart to: aStop
  (aStart isClassObject not and: [aStart isInteger and: [aStart >= 0]]) ifFalse: [
    ^ PBValidationError signal: 'A window start must be an Integer >= 0, not ' , (PBKeySpec _repr: aStart)].
  (aStop isNil or: [aStop isClassObject not and: [aStop isInteger and: [aStop >= 0]]]) ifFalse: [
    ^ PBValidationError signal: 'A window stop must be an Integer >= 0 or nil, not ' , (PBKeySpec _repr: aStop)].

"=== PBCollectionScan (plans.py CollectionScanPlan) ========================="

"A full scan of aCollection (a PBIndexedCollection, else PBValidationError); it carries the
 collection so the planner can consult its indexes."
PBCollectionScan class >> on: aCollection
  (aCollection isClassObject not and: [aCollection isKindOf: PBIndexedCollection]) ifFalse: [
    ^ PBValidationError signal: 'PBCollectionScan needs a collection (a PBIndexedCollection), not ' , (PBKeySpec _repr: aCollection)].
  ^ self basicNew _setCollection: aCollection.

PBCollectionScan >> _setCollection: aCollection
  "Runs once, on a fresh instance."
  collection isNil ifFalse: [^ PBUserError signal: 'PBCollectionScan is immutable'].
  collection := aCollection.
  ^ self.

PBCollectionScan >> collection
  ^ collection.

"Every element of the collection, in its own order."
PBCollectionScan >> do: aBlock
  collection do: aBlock.

"A scan produces and touches every element: rows = cost = count."
PBCollectionScan >> _estimateWith: aMemo
  ^ PBEstimate rows: collection count cost: collection count.

"'collection' is proto_db's class name of the collection (type(c).__name__: the last segment of
 its typeName, 'List', 'Dictionary', ...; ruling 2026-11-19), 'rows' its count, 'indexes' its
 index names."
PBCollectionScan >> _explainWith: aMemo
  ^ self _explain: 'CollectionScan' params: {
      'collection' -> (collection class typeName subStrings: '.') last.
      'rows' -> collection count.
      'indexes' -> collection indexNames asArray }
    children: #() memo: aMemo.

"Rows by position when the collection can seek (PBList, PBDictionary)."
PBCollectionScan >> _rankWindowFrom: aStart to: aStop
  ^ collection _scanWindowFrom: aStart to: aStop.

"The count when the collection can seek (its count is then its number of elements)."
PBCollectionScan >> exactRows
  ^ (collection _scanWindowFrom: 0 to: 0) isNil ifTrue: [nil] ifFalse: [collection count].

"=== PBIndexPlan (plans.py IndexPlan) ========================================"

"The elements anIndex answers through aPart (a PBIndexPart): those matching aTerm, or with aTerm
 nil every element in key order (aPart then needs an explicit estimate). PBValidationError
 otherwise."
PBIndexPlan class >> index: anIndex term: aTermOrNil part: aPart
  (aPart isClassObject not and: [aPart isKindOf: PBIndexPart]) ifFalse: [
    ^ PBValidationError signal: 'PBIndexPlan needs a PBIndexPart, not ' , (PBKeySpec _repr: aPart)].
  (aTermOrNil isNil or: [aTermOrNil isClassObject not and: [aTermOrNil isKindOf: PBTerm]]) ifFalse: [
    ^ PBValidationError signal: 'PBIndexPlan needs a PBTerm or nil, not ' , (PBKeySpec _repr: aTermOrNil)].
  (aTermOrNil isNil and: [aPart estimate isNil]) ifTrue: [
    ^ PBValidationError signal: 'A PBIndexPlan without a term needs an explicit estimate'].
  ^ self basicNew _setIndex: anIndex term: aTermOrNil part: aPart.

PBIndexPlan >> _setIndex: anIndex term: aTerm part: aPart
  "Runs once, on a fresh instance."
  part isNil ifFalse: [^ PBUserError signal: 'PBIndexPlan is immutable'].
  index := anIndex.
  term := aTerm.
  part := aPart.
  ^ self.

PBIndexPlan >> index
  ^ index.

"The term, nil for an ordered scan."
PBIndexPlan >> term
  ^ term.

"The access path: 'IndexLookup', 'IndexRange', 'IndexComplement' or 'IndexOrderedScan'."
PBIndexPlan >> kind
  ^ part kind.

PBIndexPlan >> details
  ^ part details.

PBIndexPlan >> do: aBlock
  part producer value: aBlock.

"The explicit estimate, else the index's estimate of the term."
PBIndexPlan >> _estimateWith: aMemo
  ^ part estimate isNil ifTrue: [index estimate: term] ifFalse: [part estimate].

"{ 'plan' -> kind. 'index' -> the index's explain. 'term' -> its describe or nil. details... }."
PBIndexPlan >> _explainWith: aMemo
  ^ self _explain: part kind
    params: { 'index' -> index explain. 'term' -> (term isNil ifTrue: [nil] ifFalse: [term describe]) } , part details associations
    children: #() memo: aMemo.

PBIndexPlan >> _rankWindowFrom: aStart to: aStop
  ^ part rank isNil ifTrue: [nil] ifFalse: [part rank windowFrom: aStart to: aStop].

PBIndexPlan >> exactRows
  ^ part rank isNil ifTrue: [nil] ifFalse: [part rank rows].

"Rank access to the rows in the order a stable Sort by aKeySpec gives them, or nil (plans.py
 IndexPlan.sorted_rank)."
PBIndexPlan >> sortedRank: aKeySpec descending: aBoolean
  ^ part sortedRank: aKeySpec descending: aBoolean.

"=== the nodes over one source ================================================"

_PBOneSourcePlan >> _setSource: aPlan
  "Runs once, on a fresh instance (the subclass constructors call it first)."
  source isNil ifFalse: [^ PBUserError signal: self class name , ' is immutable'].
  source := aPlan.
  ^ self.

_PBOneSourcePlan >> source
  ^ source.

"--- PBFilter (plans.py Filter) ---"

"The source rows for which the conjunction of anArray's expressions holds: PBExpression compile:
 anArray, so anArray holds expressions or is the 0.1 list syntax; a lone expression is accepted as
 itself. A near[] term has no per-element semantics: an expression holding one is
 PBValidationError (plans.py:458-462; a PBVectorSearch answers it). Checked in proto_db's order:
 the expression is compiled, then checked for near[], then the source."
PBFilter class >> source: aPlan terms: anArray
  | expr near |
  "proto_db's order: compile, refuse near[], then check the source."
  expr := PBExpression compile: anArray.
  near := nil.
  expr termsDo: [:each | (near isNil and: [each op = PBTerm nearOperator]) ifTrue: [near := each]].
  near isNil ifFalse: [
    ^ PBValidationError signal: 'A Filter cannot evaluate ''near[]'' terms (' , near printString , '); use a VectorSearch plan'].
  PBQueryPlan _check: aPlan owner: 'PBFilter'.
  ^ (self basicNew _setSource: aPlan) _setPredicate: expr.

PBFilter >> _setPredicate: anExpression
  "Runs once, on a fresh instance."
  predicate isNil ifFalse: [^ PBUserError signal: 'PBFilter is immutable'].
  predicate := anExpression.
  ^ self.

"The condition, a PBExpression."
PBFilter >> predicate
  ^ predicate.

PBFilter >> do: aBlock
  source do: [:each | (predicate evaluate: each) ifTrue: [aBlock value: each]].

"The estimated fraction of rows anExpression keeps (plans.py _selectivity): a PBAnd multiplies, a
 PBOr is 1 - prod(1 - s), a PBNot is 1 - s, anything else filterSelectivity; products are taken
 from 1, left to right, as math.prod takes them."
PBFilter class >> selectivityOf: anExpression
  (anExpression isKindOf: PBAnd) ifTrue: [
    ^ anExpression operands inject: 1 into: [:p :each | p * (self selectivityOf: each)]].
  (anExpression isKindOf: PBOr) ifTrue: [
    ^ 1 - (anExpression operands inject: 1 into: [:p :each | p * (1 - (self selectivityOf: each))])].
  (anExpression isKindOf: PBNot) ifTrue: [^ 1 - (self selectivityOf: anExpression operand)].
  ^ PBCost filterSelectivity.

"rows = source rows * selectivity; cost = source cost + source rows."
PBFilter >> _estimateWith: aMemo
  | src |
  src := source _estimateIn: aMemo.
  ^ PBEstimate rows: src rows * (self class selectivityOf: predicate) cost: src cost + src rows.

PBFilter >> _explainWith: aMemo
  ^ self _explain: 'Filter' params: { 'predicate' -> predicate describe } children: { source } memo: aMemo.

"Rank access when the condition is one term over an ordered scan of an index that answers it: the
 rows are then the index's plan for the term, in the scan's key order (plans.py Filter._rank)."
PBFilter >> _rank
  | idx |
  ((source isKindOf: PBIndexPlan) and: [source kind = 'IndexOrderedScan']) ifFalse: [^ nil].
  (predicate isKindOf: PBTerm) ifFalse: [^ nil].
  idx := source index.
  (idx supports: predicate) ifFalse: [^ nil].
  ^ (idx plan: predicate) sortedRank: idx keySpecObject descending: (source details at: 'descending' ifAbsent: [false]) == true.

PBFilter >> _rankWindowFrom: aStart to: aStop
  | rank |
  rank := self _rank.
  ^ rank isNil ifTrue: [nil] ifFalse: [rank windowFrom: aStart to: aStop].

PBFilter >> exactRows
  | rank |
  rank := self _rank.
  ^ rank isNil ifTrue: [nil] ifFalse: [rank rows].

"--- PBBlockFilter (plans.py PythonFilter) ---"

"The source rows aPBBlockPredicate accepts (its block's answer read as truthiness)."
PBBlockFilter class >> source: aPlan predicate: aPBBlockPredicate
  PBQueryPlan _check: aPlan owner: 'PBBlockFilter'.
  (aPBBlockPredicate isClassObject not and: [aPBBlockPredicate isKindOf: PBBlockPredicate]) ifFalse: [
    ^ PBValidationError signal: 'PBBlockFilter needs a PBBlockPredicate, not ' , (PBKeySpec _repr: aPBBlockPredicate)].
  ^ (self basicNew _setSource: aPlan) _setPredicate: aPBBlockPredicate.

PBBlockFilter >> _setPredicate: aPBBlockPredicate
  "Runs once, on a fresh instance."
  predicate isNil ifFalse: [^ PBUserError signal: 'PBBlockFilter is immutable'].
  predicate := aPBBlockPredicate.
  ^ self.

PBBlockFilter >> predicate
  ^ predicate.

PBBlockFilter >> do: aBlock
  source do: [:each | (predicate evaluate: each) ifTrue: [aBlock value: each]].

"Like a one-term Filter."
PBBlockFilter >> _estimateWith: aMemo
  | src |
  src := source _estimateIn: aMemo.
  ^ PBEstimate rows: src rows * PBCost filterSelectivity cost: src cost + src rows.

PBBlockFilter >> _explainWith: aMemo
  ^ self _explain: 'BlockFilter' params: { 'description' -> predicate description } children: { source } memo: aMemo.

"--- PBProject (plans.py Project) ---"

"Each source row as a PBFrozenDict of fields (a PBMissing value leaves its name out: absence is
 not a value): anArray of paths (output name = the path; a repeated path is one field) or a
 PBFrozenDict mapping output name to path, both Strings (plans.py Project's sequence and
 mapping forms); or, for a block of one argument, the block's answer, described as 'block' in
 explain. PBValidationError otherwise."
PBProject class >> source: aPlan fields: anArrayOrBlock
  ^ self source: aPlan fields: anArrayOrBlock description: nil.

"As source:fields:, aDescription (a non-empty String, or nil) naming a block in explain."
PBProject class >> source: aPlan fields: anArrayOrBlock description: aDescription
  | paths |
  PBQueryPlan _check: aPlan owner: 'PBProject'.
  (aDescription isNil or: [(PBExpression _isText: aDescription) and: [aDescription notEmpty]]) ifFalse: [
    ^ PBValidationError signal: 'PBProject description must be a non-empty String, not ' , (PBKeySpec _repr: aDescription)].
  (anArrayOrBlock isClassObject not and: [anArrayOrBlock isKindOf: BlockClosure]) ifTrue: [
    anArrayOrBlock numArgs = 1 ifFalse: [
      ^ PBValidationError signal: 'PBProject needs a block of one argument, not ' , anArrayOrBlock numArgs printString , ' arguments'].
    ^ (self basicNew _setSource: aPlan) _setFields: nil block: anArrayOrBlock
      description: (aDescription isNil ifTrue: ['block'] ifFalse: [aDescription copy])].
  aDescription isNil ifFalse: [^ PBValidationError signal: 'PBProject descriptions label a block only'].
  paths := self _mappingOf: anArrayOrBlock.
  ^ (self basicNew _setSource: aPlan) _setFields: (paths collect: [:each |
      { each key. each value. PBKeySpec forTermPath: each value }]) block: nil description: nil.

"The Associations output name -> path of a field list (each path its own name, first
 occurrence kept) or of a PBFrozenDict mapping, in order; PBValidationError unless there is at
 least one and every name and path is a String."
PBProject class >> _mappingOf: aFields
  | pairs seen |
  (aFields isClassObject not and: [aFields isKindOf: PBFrozenDict])
    ifTrue: [pairs := aFields associations asArray]
    ifFalse: [
      (aFields isClassObject not and: [(aFields isKindOf: Array) or: [aFields isKindOf: OrderedCollection]]) ifFalse: [
        ^ PBValidationError signal: 'PBProject needs an Array of paths, a PBFrozenDict mapping or a block, not '
          , (PBKeySpec _repr: aFields)].
      seen := Set new.
      pairs := OrderedCollection new.
      aFields do: [:each |
        (seen includes: each) ifFalse: [seen add: each. pairs addLast: each -> each]].
      pairs := pairs asArray].
  (pairs notEmpty and: [pairs allSatisfy: [:each | (PBExpression _isText: each key) and: [PBExpression _isText: each value]]]) ifFalse: [
    ^ PBValidationError signal: 'PBProject needs at least one field, names and paths as Strings, not ' , (PBKeySpec _repr: aFields)].
  ^ pairs collect: [:each | each key copy -> each value copy].

PBProject >> _setFields: anArray block: aBlock description: aDescription
  "Runs once, on a fresh instance."
  description isNil ifFalse: [^ PBUserError signal: 'PBProject is immutable'].
  fields := anArray.
  block := aBlock.
  description := aDescription.
  ^ self.

PBProject >> do: aBlock
  block isNil ifFalse: [^ source do: [:each | aBlock value: (block value: each)]].
  source do: [:each | aBlock value: (self _project: each)].

"The PBFrozenDict of the fields of anElement whose value is not PBMissing."
PBProject >> _project: anElement
  | out |
  out := OrderedCollection new.
  fields do: [:field | | v |
    v := (field at: 3) extract: anElement.
    v == PBMissing default ifFalse: [out addLast: (field at: 1) -> v]].
  ^ PBFrozenDict withAssociations: out asArray.

"rows = source rows; cost = source cost + rows."
PBProject >> _estimateWith: aMemo
  | src |
  src := source _estimateIn: aMemo.
  ^ PBEstimate rows: src rows cost: src cost + src rows.

"'fields' (output name to path) or 'function' (the block's description)."
PBProject >> _explainWith: aMemo
  ^ self _explain: 'Project'
    params: (block isNil
      ifTrue: [{ 'fields' -> (PBFrozenDict withAssociations: (fields collect: [:f | (f at: 1) -> (f at: 2)])) }]
      ifFalse: [{ 'function' -> description }])
    children: { source } memo: aMemo.

"--- PBSort (plans.py Sort) ---"

"The source rows sorted by anArray's PBSortKeys (at least one): stable, total (orderable keys by
 order key across type ranks, PBMissing and nil first, then the unorderable keys, equal to one
 another, R18); a descending key reverses the order of distinct keys (unorderable first) and keeps
 ties in input order."
PBSort class >> source: aPlan keys: anArray
  PBQueryPlan _check: aPlan owner: 'PBSort'.
  ((anArray isClassObject not and: [(anArray isKindOf: Array) or: [anArray isKindOf: OrderedCollection]]) and: [anArray notEmpty]) ifFalse: [
    ^ PBValidationError signal: 'PBSort needs a non-empty Array of PBSortKeys, not ' , (PBKeySpec _repr: anArray)].
  (anArray allSatisfy: [:each | each isClassObject not and: [each isKindOf: PBSortKey]]) ifFalse: [
    ^ PBValidationError signal: 'PBSort keys are PBSortKeys (PBSortKey key:descending:), not ' , (PBKeySpec _repr: anArray)].
  ^ (self basicNew _setSource: aPlan) _setKeys: anArray asArray copy.

PBSort >> _setKeys: anArray
  "Runs once, on a fresh instance."
  keys isNil ifFalse: [^ PBUserError signal: 'PBSort is immutable'].
  keys := anArray.
  ^ self.

PBSort >> keys
  ^ keys copy.

"The ascending sort slot of aKey (plans.py _sort_slot): { 0. its order key } for an orderable key,
 { 1 } for every unorderable one."
PBSort class >> slotOf: aKey
  | okey |
  okey := PBMemberKeys orderKeyOrNil: aKey.
  ^ okey isNil ifTrue: [#(1)] ifFalse: [{ 0. okey }].

"-1, 0 or 1 comparing two slots."
PBSort class >> compareSlot: a with: b
  (a at: 1) = (b at: 1) ifFalse: [^ (a at: 1) < (b at: 1) ifTrue: [-1] ifFalse: [1]].
  (a at: 1) = 1 ifTrue: [^ 0].
  ^ (a at: 2) compareWith: (b at: 2).

"Materialises the source and sorts it by every key at once: the order of the stable passes of
 plans.py Sort (last key first), with ties broken by input position, so the sort is stable
 whatever the host's sort algorithm."
PBSort >> do: aBlock
  | rows sorted |
  rows := OrderedCollection new.
  source do: [:each | rows addLast: { each. keys collect: [:k | self class slotOf: (k extract: each)]. rows size + 1 }].
  sorted := rows asArray sort: [:a :b | (self _compare: a with: b) <= 0].
  sorted do: [:row | aBlock value: (row at: 1)].

PBSort >> _compare: a with: b
  1 to: keys size do: [:i | | c |
    c := self class compareSlot: ((a at: 2) at: i) with: ((b at: 2) at: i).
    c = 0 ifFalse: [^ (keys at: i) descending ifTrue: [c negated] ifFalse: [c]]].
  ^ (a at: 3) < (b at: 3) ifTrue: [-1] ifFalse: [(a at: 3) = (b at: 3) ifTrue: [0] ifFalse: [1]].

"rows = n; cost = source cost + n log2 n."
PBSort >> _estimateWith: aMemo
  | src n |
  src := source _estimateIn: aMemo.
  n := src rows.
  ^ PBEstimate rows: n cost: src cost + (n > 1 ifTrue: [n * (PBCost log2: n)] ifFalse: [0]).

PBSort >> _explainWith: aMemo
  ^ self _explain: 'Sort'
    params: { 'keys' -> (keys collect: [:k | PBFrozenDict withAssociations: { 'key' -> k describe. 'descending' -> k descending }]) }
    children: { source } memo: aMemo.

"Rank access when sorting by one key that the source's index orders (plans.py Sort._rank)."
PBSort >> _rank
  keys size = 1 ifFalse: [^ nil].
  (source isKindOf: PBIndexPlan) ifFalse: [^ nil].
  (keys at: 1) keySpecObject isNil ifTrue: [^ nil].
  ^ source sortedRank: (keys at: 1) keySpecObject descending: (keys at: 1) descending.

PBSort >> _rankWindowFrom: aStart to: aStop
  | rank |
  rank := self _rank.
  ^ rank isNil ifTrue: [nil] ifFalse: [rank windowFrom: aStart to: aStop].

"A sort keeps every row: the source's exact row count."
PBSort >> exactRows
  ^ source exactRows.

"--- PBLimit (plans.py Limit) ---"

"At most anIntegerOrNil source rows (nil: no upper bound, an offset-only window) after skipping
 anOffset, both non-negative Integers (PBValidationError otherwise)."
PBLimit class >> source: aPlan limit: anIntegerOrNil offset: anOffset
  PBQueryPlan _check: aPlan owner: 'PBLimit'.
  (anIntegerOrNil isNil or: [self _isCount: anIntegerOrNil]) ifFalse: [
    ^ PBValidationError signal: 'PBLimit limit must be an Integer >= 0 or nil, not ' , (PBKeySpec _repr: anIntegerOrNil)].
  (self _isCount: anOffset) ifFalse: [
    ^ PBValidationError signal: 'PBLimit offset must be an Integer >= 0, not ' , (PBKeySpec _repr: anOffset)].
  ^ (self basicNew _setSource: aPlan) _setLimit: anIntegerOrNil offset: anOffset.

PBLimit class >> _isCount: anObject
  ^ anObject isClassObject not and: [anObject isInteger and: [anObject >= 0]].

PBLimit >> _setLimit: anIntegerOrNil offset: anOffset
  "Runs once, on a fresh instance."
  offset isNil ifFalse: [^ PBUserError signal: 'PBLimit is immutable'].
  limit := anIntegerOrNil.
  offset := anOffset.
  ^ self.

PBLimit >> limit
  ^ limit.

PBLimit >> offset
  ^ offset.

"The window: by rank when the source can seek (D56), else by skipping rows and stopping after the
 last."
PBLimit >> do: aBlock
  | stop seek n |
  stop := limit isNil ifTrue: [nil] ifFalse: [offset + limit].
  seek := source _rankWindowFrom: offset to: stop.
  seek isNil ifFalse: [^ seek do: aBlock].
  (stop notNil and: [stop <= offset]) ifTrue: [^ self].
  n := 0.
  source _rows: [:each |
    n >= offset ifTrue: [aBlock value: each].
    n := n + 1.
    stop notNil and: [n >= stop]].

"Rows aStart .. aStop - 1 of this window, by the source's rank access (nil without it)."
PBLimit >> _rankWindowFrom: aStart to: aStop
  | end |
  end := aStop isNil ifTrue: [limit] ifFalse: [limit isNil ifTrue: [aStop] ifFalse: [aStop min: limit]].
  (end notNil and: [end <= aStart]) ifTrue: [
    ^ (source _rankWindowFrom: 0 to: 0) isNil ifTrue: [nil] ifFalse: [Array new: 0]].
  ^ source _rankWindowFrom: offset + aStart to: (end isNil ifTrue: [nil] ifFalse: [offset + end]).

"min(limit, max(source rows - offset, 0)) when the source's row count is exact."
PBLimit >> exactRows
  | rows |
  rows := source exactRows.
  rows isNil ifTrue: [^ nil].
  rows := rows - offset max: 0.
  ^ limit isNil ifTrue: [rows] ifFalse: [rows min: limit].

"rows = min(limit, max(source rows - offset, 0)); cost = source cost (an upper bound)."
PBLimit >> _estimateWith: aMemo
  | src rows |
  src := source _estimateIn: aMemo.
  rows := src rows - offset max: 0.
  ^ PBEstimate rows: (limit isNil ifTrue: [rows] ifFalse: [limit min: rows]) cost: src cost.

"'limit' (nil when unbounded), 'offset', and 'by_rank' true when the window is sought by rank."
PBLimit >> _explainWith: aMemo
  | params |
  params := { 'limit' -> limit. 'offset' -> offset }.
  (source _rankWindowFrom: 0 to: 0) isNil ifFalse: [params := params , { 'by_rank' -> true }].
  ^ self _explain: 'Limit' params: params children: { source } memo: aMemo.

"--- PBCountPlan (plans.py Count) ---"

PBCountPlan class >> source: aPlan
  PBQueryPlan _check: aPlan owner: 'PBCountPlan'.
  ^ self basicNew _setSource: aPlan.

"One row: the number of source rows, read from the source's exact row count when it has one."
PBCountPlan >> do: aBlock
  | rows |
  rows := source exactRows.
  rows isNil ifTrue: [
    rows := 0.
    source do: [:each | rows := rows + 1]].
  aBlock value: rows.

"rows = 1; cost = source cost."
PBCountPlan >> _estimateWith: aMemo
  ^ PBEstimate rows: 1 cost: (source _estimateIn: aMemo) cost.

"'by_rank' true when the count is read from the source's exact row count."
PBCountPlan >> _explainWith: aMemo
  ^ self _explain: 'Count' params: (source exactRows isNil ifTrue: [#()] ifFalse: [{ 'by_rank' -> true }])
    children: { source } memo: aMemo.

"--- PBDistinct (plans.py Distinct) ---"

PBDistinct class >> source: aPlan
  PBQueryPlan _check: aPlan owner: 'PBDistinct'.
  ^ self basicNew _setSource: aPlan.

"The first occurrence of each element, by element identity."
PBDistinct >> do: aBlock
  | seen |
  seen := Set new.
  source do: [:each | | before |
    "One hash per row: the set grows only for an identity not seen before."
    before := seen size.
    seen add: (_PBSetPlan keyOf: each).
    seen size > before ifTrue: [aBlock value: each]].

"rows = source rows (an upper bound); cost = source cost + source rows."
PBDistinct >> _estimateWith: aMemo
  | src |
  src := source _estimateIn: aMemo.
  ^ PBEstimate rows: src rows cost: src cost + src rows.

PBDistinct >> _explainWith: aMemo
  ^ self _explain: 'Distinct' params: #() children: { source } memo: aMemo.

"=== Union and Intersect (plans.py _SetPlan) ================================="

"The identity of a row for Union, Intersect and Distinct (plans.py element_key: (element_identity,
 exact_token)). An atom answers its oid's bytes: every atom has the same exact token and its order
 key is its oid alone, so the oid is the whole identity, and a ByteArray never equals the
 PBOrderKey any other row answers. Any other row answers the order key of its member key, ((0,
 element) or (1, surrogate), exact token), built without the member tuple itself."
_PBSetPlan class >> keyOf: anElement
  ((anElement isClassObject not and: [anElement isKindOf: PBAtom]) and: [anElement isPBReference == true])
    ifTrue: [^ PBKeys _oidBytes: anElement oid].
  ^ PBMemberKeys memberOrderKeyOf: anElement.

"A node over anArray's plans (two or more; PBValidationError otherwise)."
_PBSetPlan class >> withAll: anArray
  ((anArray isClassObject not and: [(anArray isKindOf: Array) or: [anArray isKindOf: OrderedCollection]]) and: [anArray size >= 2]) ifFalse: [
    ^ PBValidationError signal: self name , ' needs at least two source plans, got ' , (PBKeySpec _repr: anArray)].
  anArray do: [:each | PBQueryPlan _check: each owner: self name].
  ^ self basicNew _setSources: anArray asArray copy.

_PBSetPlan >> _setSources: anArray
  "Runs once, on a fresh instance."
  sources isNil ifFalse: [^ PBUserError signal: self class name , ' is immutable'].
  sources := anArray.
  ^ self.

_PBSetPlan >> sources
  ^ sources copy.

"The explain name: Union or Intersect."
_PBSetPlan >> _name
  ^ self subclassResponsibility.

_PBSetPlan >> _explainWith: aMemo
  ^ self _explain: self _name params: #() children: sources memo: aMemo.

"Every occurrence of the first source, then from each later source the occurrences of an identity
 beyond those already produced: each identity with its largest multiplicity (first-seen order)."
PBUnion >> do: aBlock
  | entries |
  "One entry per identity, looked up once per row: { produced. seen in the current source. that
   source's number }; this run's own working state, never shared."
  entries := Dictionary new.
  sources doWithIndex: [:src :s |
    src do: [:each | | k e n |
      k := _PBSetPlan keyOf: each.
      e := entries at: k ifAbsent: [entries at: k put: (Array with: 0 with: 0 with: s)].
      (e at: 3) = s ifFalse: [e at: 2 put: 0; at: 3 put: s].
      n := (e at: 2) + 1.
      e at: 2 put: n.
      n > (e at: 1) ifTrue: [
        e at: 1 put: n.
        aBlock value: each]]].

"rows = sum of source rows (an upper bound); cost = sum of costs + rows."
PBUnion >> _estimateWith: aMemo
  | ests rows |
  ests := sources collect: [:each | each _estimateIn: aMemo].
  rows := ests inject: 0 into: [:sum :e | sum + e rows].
  ^ PBEstimate rows: rows cost: (ests inject: 0 into: [:sum :e | sum + e cost]) + rows.

PBUnion >> _name
  ^ 'Union'.

"The later sources are counted first; the first is then read, so the rows follow its order: each
 identity with its smallest multiplicity."
PBIntersect >> do: aBlock
  | entries m |
  "One entry per identity, looked up once per row: slot 1 counts the first source's occurrences
   produced so far, slot i (i > 1) source i's occurrences; this run's own working state."
  entries := Dictionary new.
  m := sources size.
  2 to: m do: [:s |
    (sources at: s) do: [:each | | k e |
      k := _PBSetPlan keyOf: each.
      e := entries at: k ifAbsent: [entries at: k put: (Array new: m withAll: 0)].
      e at: s put: (e at: s) + 1]].
  (sources at: 1) do: [:each | | e n |
    e := entries at: (_PBSetPlan keyOf: each) ifAbsent: [nil].
    e isNil ifFalse: [
      n := (e at: 1) + 1.
      e at: 1 put: n.
      ((2 to: m) allSatisfy: [:s | n <= (e at: s)]) ifTrue: [aBlock value: each]]].

"rows = smallest source rows; cost = sum of (source cost + source rows)."
PBIntersect >> _estimateWith: aMemo
  | ests |
  ests := sources collect: [:each | each _estimateIn: aMemo].
  ^ PBEstimate rows: ((ests collect: [:e | e rows]) inject: (ests at: 1) rows into: [:m :r | m min: r])
    cost: (ests inject: 0 into: [:sum :e | sum + (e cost + e rows)]).

PBIntersect >> _name
  ^ 'Intersect'.
