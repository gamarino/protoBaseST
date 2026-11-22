"-- query.st: the query front end, PBField and PBQuery --

A port of proto_db's proto_db/query/linq.py at v2.0.0rc4 (proto_db spec section 10, decision D38):
the field builder F (Field and _Operand, linq.py:360-484 and 600-640), the predicate mixing rule
(linq.py:48-61, 169-358) and Queryable (linq.py:906-1189), with protoST's names (ruling IQ2) and
less what spec 3.2 defers (group_by, join, select_many, computed values, startswith and endswith,
ValuesScan, the query cache, portable pager tokens). near: and the R27 mixing rule are the vectors
phase's V7 (Addendum V 2.9; linq.py:53-58, 644-647, 996-1008 and 1099-1105).

PBField names a key, as a term path does (PBKeySpec forTermPath:): PBField path: 'address.zip',
PBField element, PBField extractor: 'name_length'. Its messages answer PBTerms, the pure
conditions the planner answers with indexes:

  eq: v  ne: v  < v  <= v  > v  >= v     '==' '!=' '<' '<=' '>' '>='
  in: aCollection                       'in' (never a map or a String)
  between: a and: b, betweenOpen:and:, betweenLeftOpen:and:, betweenRightOpen:and:
                                        'between[]' 'between()' 'between(]' 'between[)'
  betweenClosed: a and: b               'between[]' (linq.py between_closed)
  between: a and: b inclusive: { includeLow. includeHigh }
                                        the four between operators (linq.py between inclusive=)
  range: a to: b, range: a to: b bounds: '[)'
                                        by bounds '[]' '()' '(]' '[)' (linq.py range)
  isNone notNone isTrue notTrue contains: v
                                        '?N' '?!N' '?T' '?!T' 'contains'
  near: aPBNearQuery, near: aVector k: k, near:threshold:, near:k:threshold:,
  near:k:threshold:metric:              'near[]' (linq.py near; nil allowed for k, threshold and
                                        metric, PBNearQuery's validation and texts)

= is not overridden (call IC4): a field compared with = answers a Boolean, which where: refuses.
Conditions combine with &, | and not (terms.st), expressions only (ruling CR5).

PBQuery is an immutable, lazy query over a source: every message but the terminals answers a new
query and leaves the receiver unchanged, so a cascade (q where: p; take: 5) keeps only its last
answer. PBQuery from: takes a PBIndexedCollection (its indexes are consulted), a PBQueryPlan (a
collection's scan keeps its indexes) or a PBQuery (answered as is); anything else is
PBValidationError (a host collection would need ValuesScan, deferred). The operators are where:,
orderBy:, orderBy:descending:, thenBy:, thenBy:descending:, skip:, take:, project:, collect: and
distinct; the terminals asArray, do:, count, count:, first, first:, firstOrNil, firstOrNil:, plan,
explain and explainCount (count:, first: and firstOrNil: take a condition, as where: does, and
answer for the query with it added). There is no
select: (ruling IQ2): Smalltalk's select: filters, so proto_db's name would read backwards.

where: takes a PBExpression or a one-argument block (ruling CR6; anything else is
PBValidationError 'where: expects a PBExpression or a one-argument block, got a <class name>'). A
block becomes a PBBlockPredicate described as 'block'; it is opaque and runs in a BlockFilter
(proto_db's PythonFilter, call IC6). Chained where: calls combine with AND (ruling CR5). The mixing
rule is proto_db's: in a top-level AND, the pure conjuncts (no PBBlockPredicate inside) go to the
planner and each impure conjunct becomes its own BlockFilter on top, in order; an OR or a NOT
holding a block is one BlockFilter for the whole condition, never partly indexed, never dropped.
The exception is ruling R27 (linq.py:53-58): when the pure part of the leading run's condition
(below) has exactly one conjunct holding near[] and it is a bare near[] term with k, the impure
conjuncts join the condition handed to the planner as conjuncts (a PBBlockPredicate as it is, any
other one as a PBBlockPredicate of its evaluation, described as render: renders it), so they are
the PBVectorSearch's where: the k nearest among the elements they accept, not k nearest then
filtered. A near[] term inside an OR or a NOT holding a block (linq.py:344-353) cannot be built
here: &, | and not take expressions only, and a block enters only through where: (CR5).

The plan (linq.py Queryable.plan, 'Placement'): the leading where: and orderBy:/thenBy: calls are
merged (the conditions ANDed, the keys composed: orderBy: puts its key first, so earlier keys
break its ties; thenBy: appends) and handed to PBPlanner with the skip:/take: calls that directly
follow them, so indexes answer conditions and may stream ordered rows. When the merged condition
has impure parts, or a key is a block, the planner gets the pure condition (and the keys when they
are all paths) and the BlockFilters, a PBSort and a PBLimit are stacked on top in that order. The
R27 rule applies to this leading run only: a where: after a window step or any other operator
filters that step's result, as below. Every
later operator is a node on top, in call order: a later orderBy: run re-sorts (PBSort), a skip:/take:
run is one PBLimit (composed like slicing), a where: is a PBFilter and BlockFilters, project: and
collect: a PBProject, distinct a PBDistinct. explain is the explain of exactly that plan.

A query holds the collection version it was built from, so it answers the same rows however the
transaction writes after it (Review Focus 3). No error is caught in the query path: an error of a
block, a key or the planner reaches the caller."

Import from: 'protobase/errors'.
Import from: 'protobase/keyspec'.
Import from: 'protobase/collections'.
Import from: 'protobase/terms'.
Import from: 'protobase/plans'.
Import from: 'protobase/planner'.

Object subclass: #PBField instanceVariableNames: 'path spec'.
Object subclass: #PBQuery instanceVariableNames: 'source ops'.

"=== PBField (linq.py Field) =================================================="

"The field at a term path aString: a dotted path, or '@name' for a registered extractor
 (PBKeySpec forTermPath:); PBValidationError for anything else (PBField element names the
 element itself)."
PBField class >> path: aString
  (PBExpression _isText: aString) ifFalse: [
    ^ PBValidationError signal: 'PBField path: needs a String (PBField element names the element), not '
      , (PBKeySpec _repr: aString)].
  ^ self _path: aString.

"The element itself (proto_db's F())."
PBField class >> element
  ^ self _path: nil.

"The key the extractor registered under aName computes (proto_db's F['@name'])."
PBField class >> extractor: aName
  (PBExpression _isText: aName) ifFalse: [
    ^ PBValidationError signal: 'PBField extractor: needs an extractor name (a String), not ' , (PBKeySpec _repr: aName)].
  ^ self _path: '@' , aName.

PBField class >> _path: aStringOrNil
  | copy |
  copy := aStringOrNil isNil ifTrue: [nil] ifFalse: [aStringOrNil copy].
  ^ self basicNew _setPath: copy spec: (PBKeySpec forTermPath: copy).

PBField >> _setPath: aStringOrNil spec: aKeySpec
  "Runs once, on a fresh instance."
  spec isNil ifFalse: [^ PBUserError signal: 'PBField is immutable'].
  path := aStringOrNil.
  spec := aKeySpec.
  ^ self.

"The term path: a dotted path, nil for the element, '@name' for an extractor (linq.py path_of)."
PBField >> path
  ^ path.

"The PBKeySpec the path names."
PBField >> keySpecObject
  ^ spec.

PBField >> _op: anOperator value: aValue
  ^ PBTerm path: path op: anOperator value: aValue.

PBField >> _op: anOperator
  ^ PBTerm path: path op: anOperator.

"key == aValue (D28: values_equal; eq: nil matches an explicit nil only, never an absent key)."
PBField >> eq: aValue
  ^ self _op: '==' value: aValue.

"key != aValue: a present key not equal to aValue; an element without the key does not match."
PBField >> ne: aValue
  ^ self _op: '!=' value: aValue.

PBField >> < aValue
  ^ self _op: '<' value: aValue.

PBField >> <= aValue
  ^ self _op: '<=' value: aValue.

PBField >> > aValue
  ^ self _op: '>' value: aValue.

PBField >> >= aValue
  ^ self _op: '>=' value: aValue.

"Membership in aCollection (linq.py in_): a map is refused, so are a String and a ByteArray; an
 Array, OrderedCollection, PBFrozenList, PBTuple or Set is the term's operand as it is; any other
 collection is read as a sequence."
PBField >> in: aCollection
  | values |
  values := aCollection.
  (values isClassObject not and: [(values isKindOf: PBFrozenDict) or: [values isKindOf: Dictionary]]) ifTrue: [
    ^ PBValidationError signal: 'in: needs a collection of values, not a map ' , (PBKeySpec _repr: values)
      , '; pass its keys or its values'].
  (PBTerm _isOperandCollection: values) ifFalse: [
    (values isClassObject not and: [values isCollection and: [values isString not and: [(values isKindOf: ByteArray) not]]])
      ifFalse: [^ PBValidationError signal: 'in: needs a collection of values, not ' , (PBKeySpec _repr: values)].
    values := values asArray].
  ^ self _op: 'in' value: values.

"low <= key <= high."
PBField >> between: low and: high
  ^ self _op: 'between[]' value: { low. high }.

"low <= key <= high (linq.py between_closed)."
PBField >> betweenClosed: low and: high
  ^ self between: low and: high.

"A between whose bound inclusion is aPair, { include low. include high }: an Array of two
 Booleans (linq.py between with inclusive=); anything else is PBValidationError."
PBField >> between: low and: high inclusive: aPair
  | op |
  ((aPair isClassObject not and: [aPair class == Array]) and: [
    aPair size = 2 and: [aPair allSatisfy: [:each | each == true or: [each == false]]]])
      ifFalse: [^ PBValidationError signal: 'between:and:inclusive: needs a pair of Booleans, not '
        , (PBKeySpec _repr: aPair)].
  op := (aPair at: 1)
    ifTrue: [(aPair at: 2) ifTrue: ['between[]'] ifFalse: ['between[)']]
    ifFalse: [(aPair at: 2) ifTrue: ['between(]'] ifFalse: ['between()']].
  ^ self _op: op value: { low. high }.

"low <= key <= high: range:to:bounds: with '[]'."
PBField >> range: low to: high
  ^ self range: low to: high bounds: '[]'.

"A between whose bounds are aString, one of '[]', '()', '(]', '[)' (surrounding blanks ignored),
 as linq.py range; anything else is PBValidationError."
PBField >> range: low to: high bounds: aString
  | bounds |
  bounds := (aString isClassObject not and: [aString isString]) ifTrue: [aString trimBoth] ifFalse: [nil].
  (#('()' '(]' '[)' '[]') includes: bounds) ifFalse: [
    ^ PBValidationError signal: 'range:to:bounds: needs bounds ''()'', ''(]'', ''[)'' or ''[]'', not '
      , (PBKeySpec _repr: aString)].
  ^ self _op: 'between' , bounds value: { low. high }.

"low < key < high."
PBField >> betweenOpen: low and: high
  ^ self _op: 'between()' value: { low. high }.

"low < key <= high."
PBField >> betweenLeftOpen: low and: high
  ^ self _op: 'between(]' value: { low. high }.

"low <= key < high."
PBField >> betweenRightOpen: low and: high
  ^ self _op: 'between[)' value: { low. high }.

"The near[] term of aPBNearQuery (linq.py near): the nearest elements, answered by a vector index
 only (PBQuery's plan refuses it without one, PBNotSupportedError). PBValidationError, the term's
 text, for anything but a PBNearQuery or a mapping of its fields."
PBField >> near: aPBNearQuery
  ^ self _op: PBTerm nearOperator value: aPBNearQuery.

"The k nearest to aVector, by the index's metric."
PBField >> near: aVector k: anInteger
  ^ self near: aVector k: anInteger threshold: nil metric: nil.

"Those within aNumber of aVector (a similarity of at least aNumber for cosine and ip, a distance of
 at most aNumber for l2)."
PBField >> near: aVector threshold: aNumber
  ^ self near: aVector k: nil threshold: aNumber metric: nil.

"The k nearest within aNumber of aVector."
PBField >> near: aVector k: anInteger threshold: aNumber
  ^ self near: aVector k: anInteger threshold: aNumber metric: nil.

"The near[] term of PBNearQuery vector: aVector k: anIntegerOrNil threshold: aNumberOrNil metric:
 aStringOrNil (its validation and texts; at least one of k and the threshold)."
PBField >> near: aVector k: anIntegerOrNil threshold: aNumberOrNil metric: aStringOrNil
  ^ self near: (PBNearQuery vector: aVector k: anIntegerOrNil threshold: aNumberOrNil metric: aStringOrNil).

"A substring of a String or ByteArray key, an item of a list, a key of a map, a member of a
 collection."
PBField >> contains: aValue
  ^ self _op: 'contains' value: aValue.

"The key is absent or nil ('?N')."
PBField >> isNone
  ^ self _op: '?N'.

"The key is present and not nil ('?!N')."
PBField >> notNone
  ^ self _op: '?!N'.

"The key is present and truthy ('?T')."
PBField >> isTrue
  ^ self _op: '?T'.

"The key is present and falsy ('?!T')."
PBField >> notTrue
  ^ self _op: '?!T'.

PBField >> printOn: aStream
  aStream nextPutAll: 'PBField('; print: path; nextPut: $).

"=== PBQuery: construction (linq.py from_collection, Queryable) ===================="

"A query over aSource: a PBIndexedCollection, a PBQueryPlan, or a PBQuery (answered as is)."
PBQuery class >> from: aSource
  aSource isClassObject ifFalse: [
    (aSource isKindOf: PBQuery) ifTrue: [^ aSource].
    ((aSource isKindOf: PBIndexedCollection) or: [aSource isKindOf: PBQueryPlan]) ifTrue: [
      ^ self basicNew _setSource: aSource ops: #()]].
  ^ PBValidationError signal: 'PBQuery from: needs a PBIndexedCollection, a PBQueryPlan or a PBQuery, not '
    , (aSource isClassObject ifTrue: ['the class ' , aSource name] ifFalse: [PBKeySpec _repr: aSource]).

PBQuery >> _setSource: aSource ops: anArray
  "Runs once, on a fresh instance."
  ops isNil ifFalse: [^ PBUserError signal: 'PBQuery is immutable; every operator answers a new PBQuery'].
  source := aSource.
  ops := anArray.
  ^ self.

"A new query: the receiver's source and operators, then anOp (linq.py Queryable._with)."
PBQuery >> _with: anOp
  ^ PBQuery basicNew _setSource: source ops: ops , { anOp }.

"=== PBQuery: operators =========================================================="

"The rows satisfying anExpressionOrBlock: a PBExpression, or a block of one argument (an opaque
 PBBlockPredicate described as 'block'). Anything else is PBValidationError (ruling CR6)."
PBQuery >> where: anExpressionOrBlock
  ^ self _with: { #where. self class _condition: anExpressionOrBlock }.

"Rows sorted stably by aKey, ascending (linq.py order_by): a path String, a PBField or a block of
 one argument; a previous order only breaks the ties of this one."
PBQuery >> orderBy: aKey
  ^ self orderBy: aKey descending: false.

PBQuery >> orderBy: aKey descending: aBoolean
  ^ self _with: { #order. self class _sortKey: aKey descending: aBoolean. true }.

"Breaks the ties of the directly preceding orderBy: or thenBy: by aKey (linq.py then_by);
 PBUserError when the last operator is not one."
PBQuery >> thenBy: aKey
  ^ self thenBy: aKey descending: false.

PBQuery >> thenBy: aKey descending: aBoolean
  (ops notEmpty and: [ops last first = #order]) ifFalse: [
    ^ PBUserError signal: 'thenBy: must directly follow orderBy: or thenBy:'].
  ^ self _with: { #order. self class _sortKey: aKey descending: aBoolean. false }.

"Drops the first anInteger rows (an Integer >= 0)."
PBQuery >> skip: anInteger
  ^ self _with: { #skip. self class _count: anInteger named: 'skip:' }.

"Keeps at most the first anInteger rows (an Integer >= 0)."
PBQuery >> take: anInteger
  ^ self _with: { #take. self class _count: anInteger named: 'take:' }.

"Each row as a PBFrozenDict of the fields anArray names (paths or PBFields of a path, each its own
 output name; an absent value leaves its field out), or of a PBFrozenDict mapping output name to
 path (linq.py select of a list or a mapping of paths). Validated now."
PBQuery >> project: anArrayOrMapping
  | fields |
  fields := anArrayOrMapping.
  (fields isClassObject not and: [(fields isKindOf: Array) or: [(fields isKindOf: OrderedCollection) or: [fields isKindOf: PBFrozenDict]]]) ifFalse: [
    ^ PBValidationError signal: 'project: needs an Array of paths or PBFields, or a PBFrozenDict mapping output name to path, not '
      , (PBKeySpec _repr: fields) , '; collect: takes a block'].
  (fields isKindOf: PBFrozenDict) ifFalse: [
    fields := fields asArray collect: [:each |
      (each isClassObject not and: [each isKindOf: PBField])
        ifTrue: [
          each path isNil ifTrue: [
            ^ PBValidationError signal: 'project: holds paths or fields of a path, not the element itself'].
          each path]
        ifFalse: [each]]].
  PBProject _mappingOf: fields.
  ^ self _with: { #project. fields }.

"Each row through aBlock of one argument (linq.py select of a callable; described as 'block')."
PBQuery >> collect: aBlock
  (aBlock isClassObject not and: [(aBlock isKindOf: BlockClosure) and: [aBlock numArgs = 1]]) ifFalse: [
    ^ PBValidationError signal: 'collect: needs a block of one argument, not ' , (PBKeySpec _repr: aBlock)].
  ^ self _with: { #project. aBlock }.

"The first occurrence of each element identity (proto_db's element key, R19)."
PBQuery >> distinct
  ^ self _with: { #distinct }.

"=== PBQuery: the plan (linq.py Queryable.plan) =================================="

"The PBQueryPlan this query runs (the class comment, 'The plan')."
PBQuery >> plan
  | n i predicates keys window offset limit split expr impure pathKeys plan op |
  n := ops size.
  i := 1.
  predicates := OrderedCollection new.
  keys := #().
  [i <= n and: [#(#where #order) includes: (ops at: i) first]] whileTrue: [
    (ops at: i) first = #where
      ifTrue: [predicates addLast: ((ops at: i) at: 2)]
      ifFalse: [keys := self class _keys: keys with: (ops at: i)].
    i := i + 1].
  window := self class _window: ops from: i.
  offset := window at: 1.
  limit := window at: 2.
  i := window at: 3.
  split := predicates isEmpty
    ifTrue: [{ nil. #() }]
    ifFalse: [self class _split: (PBPlanner conjunctionOf: predicates asArray)].
  expr := split at: 1.
  impure := split at: 2.
  (impure notEmpty and: [self class _singleKnn: expr]) ifTrue: [
    "near(k) AND a block is the k nearest among the elements the block accepts (ruling R27): the
     impure parts join the vector plan's where instead of filtering its result."
    expr := PBAnd withAll: { expr } , (impure collect: [:part | self class _predicateOf: part]).
    impure := #()].
  pathKeys := keys allSatisfy: [:each | each keySpecObject notNil].
  (impure isEmpty and: [pathKeys])
    ifTrue: [
      plan := PBPlanner plan: source where: expr orderBy: (keys isEmpty ifTrue: [nil] ifFalse: [keys])
        limit: limit offset: offset]
    ifFalse: [
      "Filtering commutes with a stable sort, so the planner may still order by path keys (an
       ordered index scan) below the BlockFilters; the window stays above them."
      plan := PBPlanner plan: source where: expr orderBy: ((pathKeys and: [keys notEmpty]) ifTrue: [keys] ifFalse: [nil])
        limit: nil offset: 0.
      impure do: [:part | plan := self class _blockFilter: plan for: part].
      (keys notEmpty and: [pathKeys not]) ifTrue: [plan := PBSort source: plan keys: keys].
      (limit notNil or: [offset ~= 0]) ifTrue: [plan := PBLimit source: plan limit: limit offset: offset]].
  [i <= n] whileTrue: [
    op := ops at: i.
    op first = #order
      ifTrue: [
        keys := #().
        [i <= n and: [(ops at: i) first = #order]] whileTrue: [
          keys := self class _keys: keys with: (ops at: i).
          i := i + 1].
        plan := PBSort source: plan keys: keys]
      ifFalse: [
        (op first = #skip or: [op first = #take])
          ifTrue: [
            window := self class _window: ops from: i.
            plan := PBLimit source: plan limit: (window at: 2) offset: (window at: 1).
            i := window at: 3]
          ifFalse: [
            plan := self class _apply: op to: plan.
            i := i + 1]]].
  ^ plan.

"The explain of the plan this query runs: exactly the tree that do: and asArray execute."
PBQuery >> explain
  ^ self plan explain.

"=== PBQuery: terminals =========================================================="

"The rows, as a new Array."
PBQuery >> asArray
  ^ self plan execute.

"Evaluates aBlock with each row, lazily (a non-local return stops the plan)."
PBQuery >> do: aBlock
  self plan do: aBlock.

"The number of rows, by a PBCountPlan (read by rank when the plan knows it exactly)."
PBQuery >> count
  ^ (PBCountPlan source: self plan) execute first.

"The number of rows that also satisfy aCondition (an expression or a one-argument block, as for
 where:) (linq.py count with a predicate)."
PBQuery >> count: aCondition
  ^ (self where: aCondition) count.

"The explain of the plan count runs: a Count over this query's plan (linq.py explain_count)."
PBQuery >> explainCount
  ^ (PBCountPlan source: self plan) explain.

"The first row that also satisfies aCondition; PBUserError when there is none."
PBQuery >> first: aCondition
  ^ (self where: aCondition) first.

"The first row that also satisfies aCondition, or nil when there is none."
PBQuery >> firstOrNil: aCondition
  ^ (self where: aCondition) firstOrNil.

"The first row; PBUserError when there is none (linq.py first)."
PBQuery >> first
  self plan do: [:each | ^ each].
  ^ PBUserError signal: 'first of an empty query; use firstOrNil when no row is expected'.

"The first row, or nil when there is none (linq.py first_or_none)."
PBQuery >> firstOrNil
  self plan do: [:each | ^ each].
  ^ nil.

PBQuery >> printOn: aStream
  aStream nextPutAll: 'PBQuery('; nextPutAll: source class name; nextPutAll: ', '.
  aStream print: (ops collect: [:each | each first]); nextPut: $).

"=== PBQuery: the helpers (linq.py, module level) ================================"

"A where: condition: a PBExpression as is, a block of one argument as a PBBlockPredicate described
 as 'block'; PBValidationError with the CR6 text otherwise."
PBQuery class >> _condition: anObject
  (PBExpression _isExpression: anObject) ifTrue: [^ anObject].
  (anObject isClassObject not and: [(anObject isKindOf: BlockClosure) and: [anObject numArgs = 1]]) ifTrue: [
    ^ PBBlockPredicate block: anObject description: 'block'].
  ^ PBValidationError signal: 'where: expects a PBExpression or a one-argument block, got a ' , anObject class name.

"The PBSortKey of an orderBy: or thenBy: key: a PBField by its path, a path String or a block as
 PBSortKey takes them (PBValidationError otherwise; linq.py _key)."
PBQuery class >> _sortKey: aKey descending: aBoolean
  (aKey isClassObject not and: [aKey isKindOf: PBField]) ifTrue: [^ PBSortKey key: aKey path descending: aBoolean].
  ^ PBSortKey key: aKey descending: aBoolean.

"anObject when it is an Integer >= 0 (a Boolean is not one), else PBValidationError (linq.py
 _count)."
PBQuery class >> _count: anObject named: aSelector
  (anObject isClassObject not and: [anObject isInteger and: [anObject >= 0]]) ifFalse: [
    ^ PBValidationError signal: aSelector , ' needs an Integer >= 0, not ' , (PBKeySpec _repr: anObject)].
  ^ anObject.

"anArray of PBSortKeys with an order operator's key: first for orderBy: (earlier keys break its
 ties), last for thenBy: (linq.py _add_key)."
PBQuery class >> _keys: anArray with: anOp
  ^ (anOp at: 3) ifTrue: [{ anOp at: 2 } , anArray] ifFalse: [anArray , { anOp at: 2 }].

"{ offset. limit or nil. index after the run } composing the run of skip: and take: operators of
 anArray starting at anIndex like slicing (linq.py _window)."
PBQuery class >> _window: anArray from: anIndex
  | offset limit i m |
  offset := 0.
  i := anIndex.
  [i <= anArray size and: [#(#skip #take) includes: (anArray at: i) first]] whileTrue: [
    m := (anArray at: i) at: 2.
    (anArray at: i) first = #skip
      ifTrue: [
        offset := offset + m.
        limit isNil ifFalse: [limit := limit - m max: 0]]
      ifFalse: [limit := limit isNil ifTrue: [m] ifFalse: [limit min: m]].
    i := i + 1].
  ^ { offset. limit. i }.

"Whether anExpression holds no PBBlockPredicate (linq.py Predicate.expression is not None)."
PBQuery class >> _isPure: anExpression
  (anExpression isKindOf: PBBlockPredicate) ifTrue: [^ false].
  (anExpression isKindOf: _PBNode) ifTrue: [^ anExpression operands allSatisfy: [:each | self _isPure: each]].
  ^ true.

"{ pure expression or nil. Array of impure conditions } (linq.py _split): a pure condition goes
 whole to the planner; a top-level PBAnd is split into its pure conjuncts (their conjunction) and
 its impure ones, in order; any other impure condition is one impure part."
PBQuery class >> _split: anExpression
  | operands pure |
  (self _isPure: anExpression) ifTrue: [^ { anExpression. #() }].
  (anExpression isKindOf: PBAnd) ifFalse: [^ { nil. { anExpression } }].
  operands := anExpression operands.
  pure := operands select: [:each | self _isPure: each].
  ^ { pure isEmpty ifTrue: [nil] ifFalse: [PBPlanner conjunctionOf: pure].
    operands reject: [:each | self _isPure: each] }.

"Whether anExpressionOrNil has exactly one conjunct holding near[], and it is a bare near[] term
 with k (linq.py _single_knn)."
PBQuery class >> _singleKnn: anExpressionOrNil
  | near |
  anExpressionOrNil isNil ifTrue: [^ false].
  near := ((anExpressionOrNil isKindOf: PBAnd) ifTrue: [anExpressionOrNil operands] ifFalse: [{ anExpressionOrNil }])
    select: [:each | PBPlanner hasNear: each].
  ^ near size = 1 and: [PBPlanner isKnn: near first].

"The impure condition anExpression as one opaque conjunct (linq.py PythonPredicate(part,
 part.describe())): a PBBlockPredicate as it is, any other one a PBBlockPredicate of its
 evaluation, described as render: renders it (as _blockFilter:for: describes it)."
PBQuery class >> _predicateOf: anExpression
  (anExpression isKindOf: PBBlockPredicate) ifTrue: [^ anExpression].
  ^ PBBlockPredicate block: [:each | anExpression evaluate: each] description: (self render: anExpression).

"aPlan under a BlockFilter of the impure condition anExpression: a PBBlockPredicate as is, any
 other one evaluated whole, described as proto_db renders it (linq.py PythonFilter of an impure
 predicate)."
PBQuery class >> _blockFilter: aPlan for: anExpression
  ^ PBBlockFilter source: aPlan predicate: (self _predicateOf: anExpression).

"A one-line rendering of anExpression (linq.py _render and the describe of its impure predicates):
 a term 'path op value' (the element as 'element', a unary operator without a value), a PBAnd or
 PBOr each operand parenthesised and joined by ' & ' or ' | ', a PBNot '~(...)', a block predicate
 its description."
PBQuery class >> render: anExpression
  | path |
  (anExpression isKindOf: PBBlockPredicate) ifTrue: [^ anExpression description].
  (anExpression isKindOf: PBTerm) ifTrue: [
    path := anExpression path isNil ifTrue: ['element'] ifFalse: [anExpression path].
    (PBTerm unaryOperators includes: anExpression op) ifTrue: [^ path , ' ' , anExpression op].
    ^ path , ' ' , anExpression op , ' ' , (PBKeySpec _repr: anExpression value)].
  (anExpression isKindOf: PBNot) ifTrue: [^ '~(' , (self render: anExpression operand) , ')'].
  ^ ((anExpression isKindOf: PBAnd) ifTrue: [' & '] ifFalse: [' | '])
    join: (anExpression operands collect: [:each | '(' , (self render: each) , ')']).

"The node(s) of one later operator above aPlan (linq.py _apply)."
PBQuery class >> _apply: anOp to: aPlan
  | split plan |
  anOp first = #where ifTrue: [
    split := self _split: (anOp at: 2).
    plan := (split at: 1) isNil ifTrue: [aPlan] ifFalse: [PBFilter source: aPlan terms: (split at: 1)].
    (split at: 2) do: [:part | plan := self _blockFilter: plan for: part].
    ^ plan].
  anOp first = #project ifTrue: [^ PBProject source: aPlan fields: (anOp at: 2)].
  anOp first = #distinct ifTrue: [^ PBDistinct source: aPlan].
  ^ PBValidationError signal: 'Unknown query operator ' , anOp first printString.
