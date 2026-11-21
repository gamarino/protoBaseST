"_qplants.st: the planted defects of the index contract (plan call IP4; proto_db
 tests/unit/test_index_contract.py at v2.0.0rc4, its broken ScanIndex variants), each a subclass of
 a correct index kind with one hook broken, used by tests/unit/idx_contract_plans.st (and, for the
 vector plants, tests/unit/vec_contract.st) to prove that
 the contract has teeth: each must be rejected by the check aimed at its defect. A helper: nothing
 here runs on import but the registration of the plants' type names (tests.qplants.<class>), so
 a saved plant loads as itself. The class comments name proto_db's variant each one plants."
Import from: 'protobase'.

"NoopRemoveIndex: withRemoved: answers an index with unchanged content."
PBEqualityIndex subclass: #NoopRemoveIndex.

NoopRemoveIndex class >> typeName
  ^ 'tests.qplants.NoopRemoveIndex'.

NoopRemoveIndex >> withRemoved: anElement
  ^ self.

"DroppingPlanIndex: plan: silently drops the first match."
PBEqualityIndex subclass: #DroppingPlanIndex.

DroppingPlanIndex class >> typeName
  ^ 'tests.qplants.DroppingPlanIndex'.

DroppingPlanIndex >> plan: aTerm
  | inner |
  inner := super plan: aTerm.
  ^ PBIndexPlan index: self term: aTerm part: (PBIndexPart kind: inner kind
    producer: [:aBlock | | first |
      first := true.
      inner do: [:e | first ifTrue: [first := false] ifFalse: [aBlock value: e]]]
    estimate: nil details: nil rank: nil sortedRank: nil).

"PathBlindIndex: supports: ignores the term's path, so a term on another attribute is answered
 with the index's own key."
PBEqualityIndex subclass: #PathBlindIndex.

PathBlindIndex class >> typeName
  ^ 'tests.qplants.PathBlindIndex'.

PathBlindIndex >> supports: aTerm
  ^ self class supportedOperators includes: aTerm op.

"LenientPlanIndex: plan: on an unsupported term answers an empty plan instead of refusing."
PBEqualityIndex subclass: #LenientPlanIndex.

LenientPlanIndex class >> typeName
  ^ 'tests.qplants.LenientPlanIndex'.

LenientPlanIndex >> plan: aTerm
  (self supports: aTerm) ifFalse: [
    ^ PBIndexPlan index: self term: aTerm part: (PBIndexPart kind: 'IndexLookup' producer: [:aBlock | nil]
      estimate: (PBEstimate rows: 0 cost: 0) details: nil rank: nil sortedRank: nil)].
  ^ super plan: aTerm.

"MutatingIndex: withAdded: updates the receiver in place and answers it. protoBaseST's atoms set
 their state once; the defect writes the state cell behind that rule (instVarNamed:put:), which is
 what a broken subclass could do."
PBEqualityIndex subclass: #MutatingIndex.

MutatingIndex class >> typeName
  ^ 'tests.qplants.MutatingIndex'.

MutatingIndex >> withAdded: anElement
  | added |
  added := super withAdded: anElement.
  self instVarNamed: 'slots' put: (added instVarNamed: 'slots').
  ^ self.

"ContentKeepingBuildIndex: build: folds onto the receiver instead of an empty index."
PBEqualityIndex subclass: #ContentKeepingBuildIndex.

ContentKeepingBuildIndex class >> typeName
  ^ 'tests.qplants.ContentKeepingBuildIndex'.

ContentKeepingBuildIndex >> build: aCollection
  | index |
  index := self.
  aCollection do: [:each | index := index withAdded: each].
  ^ index.

"ForgetfulEmptyIndex: empty answers the receiver, content kept."
PBEqualityIndex subclass: #ForgetfulEmptyIndex.

ForgetfulEmptyIndex class >> typeName
  ^ 'tests.qplants.ForgetfulEmptyIndex'.

ForgetfulEmptyIndex >> empty
  ^ self.

"WrongOrderIndex: a descending ordered scan answers the ascending order."
PBRangeIndex subclass: #WrongOrderIndex.

WrongOrderIndex class >> typeName
  ^ 'tests.qplants.WrongOrderIndex'.

WrongOrderIndex >> orderedPlan: aKeySpec descending: aBoolean
  ^ super orderedPlan: aKeySpec descending: false.

"UnstableOrderIndex: orders by a hash of the key instead of its order key."
PBRangeIndex subclass: #UnstableOrderIndex.

UnstableOrderIndex class >> typeName
  ^ 'tests.qplants.UnstableOrderIndex'.

UnstableOrderIndex >> orderedPlan: aKeySpec descending: aBoolean
  | rows spec |
  spec := self keySpecObject.
  rows := (Array withAll: (super orderedPlan: aKeySpec descending: false) execute asArray)
    sort: [:a :b | (spec extract: a) printString hash <= (spec extract: b) printString hash].
  ^ PBIndexPlan index: self term: nil part: (PBIndexPart kind: 'IndexOrderedScan' producer: [:aBlock | rows do: aBlock]
    estimate: (PBEstimate rows: 0 cost: 0) details: nil rank: nil sortedRank: nil).

"OrderClaimingIndex: claims ordered iteration on every key but cannot provide it."
PBEqualityIndex subclass: #OrderClaimingIndex.

OrderClaimingIndex class >> typeName
  ^ 'tests.qplants.OrderClaimingIndex'.

OrderClaimingIndex >> supportsOrder: aKeySpec
  ^ true.

"The vector contract's teeth (test_vector_index.py:574-628, test_vector_contract_rejects_broken_variants),
 each caught by vec_contract.st's planMatchesScan.
 OnceVectorIndex: plan: answers each member once, whatever its count."
PBVectorIndex subclass: #OnceVectorIndex.

OnceVectorIndex class >> typeName
  ^ 'tests.qplants.OnceVectorIndex'.

OnceVectorIndex >> plan: aTerm
  | inner |
  inner := super plan: aTerm.
  ^ PBIndexPlan index: self term: aTerm part: (PBIndexPart kind: 'Broken'
    producer: [:aBlock | | seen |
      seen := Set new.
      inner do: [:e | | key |
        key := (PBMemberKeys identityOf: e) printString , ((e isKindOf: PBObject) ifTrue: [''] ifFalse: [(PBKeys exactToken: e) hex]).
        (seen includes: key) ifFalse: [seen add: key. aBlock value: e]]]
    estimate: nil details: nil rank: nil sortedRank: nil).

"MetricBlindVectorIndex: supports: accepts a query naming another metric (and answers it with its
 own)."
PBVectorIndex subclass: #MetricBlindVectorIndex.

MetricBlindVectorIndex class >> typeName
  ^ 'tests.qplants.MetricBlindVectorIndex'.

MetricBlindVectorIndex >> supports: aTerm
  ^ aTerm op = PBTerm nearOperator and: [aTerm path = self keySpecObject termPath
    and: [aTerm value vector size = self dim]].

"LastTieVectorIndex: breaks score ties by the largest member key instead of the smallest (its
 scores are PBVectorMath's, as the index's own)."
PBVectorIndex subclass: #LastTieVectorIndex.

LastTieVectorIndex class >> typeName
  ^ 'tests.qplants.LastTieVectorIndex'.

LastTieVectorIndex >> plan: aTerm
  | q k floor entries sorted |
  q := aTerm value vector.
  k := aTerm value k.
  floor := PBVectorMath scoreFloor: self metric threshold: aTerm value threshold.
  entries := OrderedCollection new.
  self storeEntries do: [:assoc | | s |
    s := PBVectorMath score: self metric query: q vector: (assoc value at: 3).
    (floor isNil or: [s >= floor]) ifTrue: [
      entries add: { s. PBKeys orderKey: (assoc key at: 2). assoc value at: 1. assoc value at: 2 }]].
  sorted := entries asArray sort: [:a :b |
    (a at: 1) > (b at: 1) or: [(a at: 1) = (b at: 1) and: [(a at: 2) >= (b at: 2)]]].
  k isNil ifFalse: [sorted := sorted copyFrom: 1 to: (k min: sorted size)].
  ^ PBIndexPlan index: self term: aTerm part: (PBIndexPart kind: 'Broken'
    producer: [:aBlock | sorted do: [:e | (e at: 4) timesRepeat: [aBlock value: (e at: 3)]]]
    estimate: nil details: nil rank: nil sortedRank: nil).

"Registered under names of their own, so a saved plant loads as itself (check (c))."
PBTypeRegistry register: NoopRemoveIndex; register: DroppingPlanIndex; register: PathBlindIndex; register: LenientPlanIndex; register: MutatingIndex; register: ContentKeepingBuildIndex; register: ForgetfulEmptyIndex; register: WrongOrderIndex; register: UnstableOrderIndex; register: OrderClaimingIndex;
  register: OnceVectorIndex; register: MetricBlindVectorIndex; register: LastTieVectorIndex.
