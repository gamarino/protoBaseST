"-- planner.st: the query planner, PBPlanner --

A port of proto_db's proto_db/query/planner.py at v2.0.0rc4 (proto_db spec section 10, decision
D37), line by line, less the near[] rules of planning (planner.py:15-26, 129-135 and 194-275,
vectors phase V7); normalize: has its near[] refusal (planner.py:114-116, V2). Until V7 no vector
index is consulted, so a near[] conjunct is left to the residual PBFilter, which refuses it
(PBValidationError, plans.py:458-462) where proto_db's planner refuses it as unsupported.

  PBPlanner plan: aSource where: aCondition orderBy: keys limit: anIntegerOrNil offset: anInteger
      the cheapest plan answering the multiset a scan filtered by the condition answers
      (planner.py plan_query). aSource is a PBIndexedCollection (its indexes are consulted), a
      PBCollectionScan (its collection's indexes are consulted) or any other PBQueryPlan (no
      index: the condition is a Filter on top). aCondition is a PBExpression, the 0.1 prefix list
      syntax (PBExpression compile:), or nil. keys is nil or a non-empty Array of PBSortKeys
      (plan call IP14); limit nil or an Integer >= 0; offset an Integer >= 0. A malformed argument
      is PBValidationError (planner.py:278-343).
  PBPlanner normalize: anExpression
      negations pushed through PBAnd and PBOr by De Morgan, junctions flattened; a negated term
      stays a PBNot of the term, except the one exact rewrite not '?N' = '?!N' and not '?!N' = '?N'
      (planner.py normalize; D36 amendment: not (x == 5) is not x != 5, since PBMissing satisfies
      only the former); a negated near[] term is PBNotSupportedError (planner.py:114-116).

The rules, as planner.py's module docstring states them:

  - every conjunct is answered either by an index access path or by a residual PBFilter; none is
    ever dropped, so the plan answers what a scan answers;
  - the candidates of a conjunction (its conjuncts without repetitions, in order) are a full scan
    with every conjunct as residual, and for each conjunct with an access path the cheapest such
    path with the other conjuncts as residual. A term's access path is the cheapest plan of the
    indexes whose supports: accepts it; a disjunction's is a PBUnion of index-only plans of every
    branch (each branch a conjunction planned recursively), or none; a negated term has none;
  - the cost of a candidate is its plan's estimate cost (plans.st, the D30/D36 model); candidates
    rank by { cost. scans. sorted index names }: the cheapest first, on equal cost the plan
    without a scan, then the lexicographically smaller tuple of index names (code points, as
    Python compares str), and on a full tie the first candidate made;
  - an order of one key may be answered by an ordered index scan (an index whose supportsOrder:
    accepts the key's key spec) with the whole condition as a PBFilter on top, when that is
    cheaper than a PBSort of the planned result; several keys, or a block key, always sort;
  - limit or a non-zero offset puts a PBLimit on top, after the order.

Indexes are consulted in sorted name order. An index that is not a PBIndex (a PBOpaqueAtom of a
kind this process does not know, which understands neither supports: nor supportsOrder:) is
never consulted, nor is a PBVectorIndex (its supports: answers false and it offers no order):
neither can answer a term here, as in proto_db a vector index answers only near[] (plan Task 6
review). The planner is a pure function of its arguments: collections and indexes are immutable
versions and nothing is kept between calls."

Import from: 'protobase/errors'.
Import from: 'protobase/keyspec'.
Import from: 'protobase/collections'.
Import from: 'protobase/indexes'.
Import from: 'protobase/terms'.
Import from: 'protobase/plans'.

Object subclass: #PBPlanner instanceVariableNames: 'base indexes'.
Object subclass: #_PBCandidate instanceVariableNames: 'plan names scans cost'.

"=== _PBCandidate (planner.py _Candidate) ====================================="

"A candidate plan with what ranks it: aPlan's estimate cost, whether it scans (aBoolean), and the
 names of the indexes it uses (anArray, sorted)."
_PBCandidate class >> plan: aPlan names: anArray scans: aBoolean
  ^ self basicNew _setPlan: aPlan names: anArray scans: aBoolean cost: aPlan estimate cost.

_PBCandidate >> _setPlan: aPlan names: anArray scans: aBoolean cost: aCost
  "Runs once, on a fresh instance."
  plan isNil ifFalse: [^ PBUserError signal: '_PBCandidate is immutable'].
  plan := aPlan.
  names := anArray.
  scans := aBoolean.
  cost := aCost.
  ^ self.

_PBCandidate >> queryPlan
  ^ plan.

_PBCandidate >> names
  ^ names.

_PBCandidate >> scans
  ^ scans.

_PBCandidate >> cost
  ^ cost.

"The same access path under a new top node (planner.py _Candidate.wrap)."
_PBCandidate >> wrap: aPlan
  ^ _PBCandidate plan: aPlan names: names scans: scans.

"Whether the receiver ranks strictly before aCandidate: Python's comparison of the tuples
 (cost, scans, names), False before True, names compared item by item (planner.py
 _Candidate.rank)."
_PBCandidate >> ranksBefore: aCandidate
  cost = aCandidate cost ifFalse: [^ cost < aCandidate cost].
  scans = aCandidate scans ifFalse: [^ aCandidate scans].
  ^ (PBPlanner compareNames: names with: aCandidate names) < 0.

"=== PBPlanner: the entry points ============================================="

"The plan of a query (planner.py plan_query; the class comment)."
PBPlanner class >> plan: aSource where: aCondition orderBy: aKeys limit: aLimit offset: anOffset
  | pair expr keys planner candidate plan |
  pair := self _source: aSource.
  expr := aCondition isNil ifTrue: [nil] ifFalse: [self normalize: (PBExpression compile: aCondition)].
  keys := self _orderKeys: aKeys.
  (aLimit isNil or: [self _isCount: aLimit]) ifFalse: [
    ^ PBValidationError signal: 'PBPlanner limit must be an Integer >= 0, not ' , (PBKeySpec _repr: aLimit)].
  (self _isCount: anOffset) ifFalse: [
    ^ PBValidationError signal: 'PBPlanner offset must be an Integer >= 0, not ' , (PBKeySpec _repr: anOffset)].
  planner := self basicNew _setBase: (pair at: 1) indexes: (pair at: 2).
  candidate := expr isNil
    ifTrue: [_PBCandidate plan: (pair at: 1) names: #() scans: true]
    ifFalse: [planner plan: expr].
  plan := planner order: candidate where: expr keys: keys.
  (aLimit notNil or: [anOffset ~= 0]) ifTrue: [plan := PBLimit source: plan limit: aLimit offset: anOffset].
  ^ plan.

"anExpression with negations pushed through PBAnd and PBOr and junctions flattened (planner.py
 normalize); PBValidationError for anything that is not a PBExpression, PBNotSupportedError for a
 negated near[] term (planner.py:114-116)."
PBPlanner class >> normalize: anExpression
  (PBExpression _isExpression: anExpression) ifFalse: [
    ^ PBValidationError signal: 'normalize: needs a PBExpression, not ' , (PBKeySpec _repr: anExpression)].
  ^ self _normalize: anExpression negate: false.

"planner.py _normalize."
PBPlanner class >> _normalize: anExpression negate: aBoolean
  | operands junction |
  (anExpression isKindOf: PBTerm) ifTrue: [
    aBoolean ifFalse: [^ anExpression].
    anExpression op = '?N' ifTrue: [^ PBTerm path: anExpression path op: '?!N'].
    anExpression op = '?!N' ifTrue: [^ PBTerm path: anExpression path op: '?N'].
    anExpression op = PBTerm nearOperator ifTrue: [
      ^ PBNotSupportedError signal: 'A negated ''near[]'' term cannot be planned (' , anExpression printString
        , '): there is no per-element semantics to complement a vector search'].
    ^ PBNot of: anExpression].
  (anExpression isKindOf: PBBlockPredicate) ifTrue: [
    ^ aBoolean ifTrue: [PBNot of: anExpression] ifFalse: [anExpression]].
  (anExpression isKindOf: PBNot) ifTrue: [^ self _normalize: anExpression operand negate: aBoolean not].
  (anExpression isKindOf: _PBJunction) ifTrue: [
    operands := anExpression operands collect: [:each | self _normalize: each negate: aBoolean].
    junction := aBoolean
      ifFalse: [anExpression class]
      ifTrue: [(anExpression isKindOf: PBAnd) ifTrue: [PBOr] ifFalse: [PBAnd]].
    ^ junction withAll: operands].
  ^ PBValidationError signal: 'Cannot normalise ' , (PBKeySpec _repr: anExpression).

"{ base plan. Array of { name. index } } of a planner source (planner.py _source): the indexes in
 sorted name order, less those that cannot answer a term (the class comment)."
PBPlanner class >> _source: aSource
  | collection base |
  aSource isClassObject ifFalse: [
    (aSource isKindOf: PBIndexedCollection) ifTrue: [collection := aSource. base := aSource asQueryPlan].
    (aSource isKindOf: PBCollectionScan) ifTrue: [collection := aSource collection. base := aSource].
    (collection isNil and: [aSource isKindOf: PBQueryPlan]) ifTrue: [^ { aSource. #() }]].
  collection isNil ifTrue: [
    ^ PBValidationError signal: 'PBPlanner needs a PBIndexedCollection or a PBQueryPlan source, not '
      , (aSource isClassObject ifTrue: ['a class'] ifFalse: [aSource class name])].
  ^ { base. ((self sortNames: collection indexNames) collect: [:name | { name. collection getIndex: name }])
      select: [:pair | self _consults: (pair at: 2)] }.

"Whether the planner consults anIndex: a PBIndex that is not a PBVectorIndex."
PBPlanner class >> _consults: anIndex
  anIndex isClassObject ifTrue: [^ false].
  ^ (anIndex isKindOf: PBIndex) and: [(anIndex isKindOf: PBVectorIndex) not].

"aKeys as an Array of PBSortKeys, empty for nil (planner.py _order_keys, with plan call IP14's
 PBSortKey for its (path, descending) pairs): PBValidationError for anything but nil or a
 non-empty Array or OrderedCollection of PBSortKeys."
PBPlanner class >> _orderKeys: aKeys
  aKeys isNil ifTrue: [^ #()].
  ((aKeys isClassObject not and: [(aKeys isKindOf: Array) or: [aKeys isKindOf: OrderedCollection]]) and: [aKeys notEmpty]) ifFalse: [
    ^ PBValidationError signal: 'PBPlanner orderBy: must be nil or a non-empty Array of PBSortKeys, not '
      , (PBKeySpec _repr: aKeys)].
  aKeys do: [:each |
    (each isClassObject not and: [each isKindOf: PBSortKey]) ifFalse: [
      ^ PBValidationError signal: 'PBPlanner order keys are PBSortKeys (PBSortKey key:descending:), not '
        , (PBKeySpec _repr: each)]].
  ^ aKeys asArray copy.

"Whether anObject is an Integer >= 0 (a Boolean is not one: planner.py plan_query)."
PBPlanner class >> _isCount: anObject
  ^ anObject isClassObject not and: [anObject isInteger and: [anObject >= 0]].

"-1, 0 or 1 comparing two Arrays of Strings as Python compares tuples of str: item by item by
 code point, a prefix first."
PBPlanner class >> compareNames: a with: b
  | c |
  1 to: (a size min: b size) do: [:i |
    c := self compareString: (a at: i) with: (b at: i).
    c = 0 ifFalse: [^ c]].
  ^ a size = b size ifTrue: [0] ifFalse: [a size < b size ifTrue: [-1] ifFalse: [1]].

"-1, 0 or 1 comparing two Strings by code point, a prefix first (Python's str order)."
PBPlanner class >> compareString: a with: b
  | x y |
  1 to: (a size min: b size) do: [:i |
    x := (a at: i) asInteger.
    y := (b at: i) asInteger.
    x = y ifFalse: [^ x < y ifTrue: [-1] ifFalse: [1]]].
  ^ a size = b size ifTrue: [0] ifFalse: [a size < b size ifTrue: [-1] ifFalse: [1]].

"anArray's Strings sorted by code point, a new Array (Python's sorted)."
PBPlanner class >> sortNames: anArray
  ^ (Array withAll: anArray) sort: [:a :b | (self compareString: a with: b) <= 0].

"The candidate that ranks first in anArray, the first made on a full tie; nil when anArray is
 empty (planner.py _best: min by rank)."
PBPlanner class >> best: anArray
  | best |
  anArray do: [:each | (best isNil or: [each ranksBefore: best]) ifTrue: [best := each]].
  ^ best.

"The sorted names of every index the candidates of anArray use (planner.py _merge_names)."
PBPlanner class >> mergeNames: anArray
  | all |
  all := OrderedCollection new.
  anArray do: [:each | each names do: [:name | (all includes: name) ifFalse: [all add: name]]].
  ^ self sortNames: all asArray.

"The conjuncts of anExpression without repetitions (PBAnd is idempotent), in order (planner.py
 _conjuncts)."
PBPlanner class >> conjunctsOf: anExpression
  ^ self withoutRepetitions: ((anExpression isKindOf: PBAnd) ifTrue: [anExpression operands] ifFalse: [{ anExpression }]).

"anArray's expressions, the first of each set of equal ones kept, in order (dict.fromkeys)."
PBPlanner class >> withoutRepetitions: anArray
  | out |
  out := OrderedCollection new.
  anArray do: [:each | (out includes: each) ifFalse: [out add: each]].
  ^ out asArray.

"The one conjunct of anArray, or their PBAnd (planner.py _conjunction)."
PBPlanner class >> conjunctionOf: anArray
  ^ anArray size = 1 ifTrue: [anArray first] ifFalse: [PBAnd withAll: anArray].

"=== PBPlanner: one planning (planner.py _Planner) ============================="

PBPlanner >> _setBase: aPlan indexes: anArray
  "Runs once, on a fresh instance."
  base isNil ifFalse: [^ PBUserError signal: 'PBPlanner is immutable'].
  base := aPlan.
  indexes := anArray.
  ^ self.

"aCandidate under a PBFilter of the residual conjuncts anArray, or aCandidate when there is none
 (planner.py with_residual)."
PBPlanner >> withResidual: aCandidate conjuncts: anArray
  anArray isEmpty ifTrue: [^ aCandidate].
  ^ aCandidate wrap: (PBFilter source: aCandidate queryPlan terms: (self class conjunctionOf: anArray)).

"The cheapest candidate of a normalised expression (planner.py _Planner.plan)."
PBPlanner >> plan: anExpression
  ^ self conjunction: (self class conjunctsOf: anExpression) requireIndex: false.

"The cheapest candidate of the conjunction of anArray; with aBoolean, among index-only candidates
 only, nil when there is none (planner.py _Planner.conjunction, less the near[] rules)."
PBPlanner >> conjunction: anArray requireIndex: aBoolean
  | conjuncts access candidates |
  conjuncts := self class withoutRepetitions: anArray.
  access := conjuncts collect: [:each | self access: each].
  candidates := OrderedCollection new.
  aBoolean ifFalse: [
    candidates add: (self withResidual: (_PBCandidate plan: base names: #() scans: true) conjuncts: conjuncts)].
  access doWithIndex: [:option :i |
    option isNil ifFalse: [
      candidates add: (self withResidual: option
        conjuncts: (conjuncts copyFrom: 1 to: i - 1) , (conjuncts copyFrom: i + 1 to: conjuncts size))]].
  ^ self class best: candidates.

"The cheapest access path answering aConjunct exactly without a full scan, else nil (planner.py
 _Planner.access): a term by the cheapest index that supports it, a disjunction by a PBUnion."
PBPlanner >> access: aConjunct
  (aConjunct isKindOf: PBTerm) ifTrue: [
    ^ self class best: ((indexes select: [:pair | (pair at: 2) supports: aConjunct]) collect: [:pair |
      _PBCandidate plan: ((pair at: 2) plan: aConjunct) names: { pair at: 1 } scans: false])].
  (aConjunct isKindOf: PBOr) ifTrue: [^ self union: aConjunct].
  ^ nil.

"A PBUnion of the branches' index-only plans when every branch has one, else nil (planner.py
 _Planner.union, less the near[] rules)."
PBPlanner >> union: aDisjunction
  | branches |
  branches := aDisjunction operands collect: [:branch | | planned |
    planned := self conjunction: (self class conjunctsOf: branch) requireIndex: true.
    planned isNil ifTrue: [^ nil].
    planned].
  ^ _PBCandidate
    plan: (PBUnion withAll: (branches collect: [:each | each queryPlan]))
    names: (self class mergeNames: branches)
    scans: (branches anySatisfy: [:each | each scans]).

"aCandidate's plan ordered by anArray's PBSortKeys (planner.py _Planner.order): a PBSort, or, for
 one key with a key spec, an ordered index scan with the whole condition anExpression (nil: none)
 as a PBFilter on top, whichever ranks first."
PBPlanner >> order: aCandidate where: anExpression keys: anArray
  | options spec ordered |
  anArray isEmpty ifTrue: [^ aCandidate queryPlan].
  options := OrderedCollection with: (aCandidate wrap: (PBSort source: aCandidate queryPlan keys: anArray)).
  (anArray size = 1 and: [(spec := anArray first keySpecObject) notNil]) ifTrue: [
    indexes do: [:pair |
      ((pair at: 2) supportsOrder: spec) ifTrue: [
        ordered := (pair at: 2) orderedPlan: spec descending: anArray first descending.
        options add: (_PBCandidate
          plan: (anExpression isNil ifTrue: [ordered] ifFalse: [PBFilter source: ordered terms: anExpression])
          names: { pair at: 1 } scans: false)]]].
  ^ (self class best: options) queryPlan.
