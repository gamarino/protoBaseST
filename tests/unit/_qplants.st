"_qplants.st: the planted defects of the index contract (plan call IP4; proto_db
 tests/unit/test_index_contract.py at v2.0.0rc4, its broken ScanIndex variants), each a subclass of
 a correct index kind with one hook broken, used by tests/unit/idx_contract_plans.st to prove that
 the contract has teeth: each must be rejected by the check aimed at its defect. A helper: nothing
 here runs on import. The class comments name proto_db's variant each one plants."
Import from: 'protobase'.

"NoopRemoveIndex: withRemoved: answers an index with unchanged content."
PBEqualityIndex subclass: #NoopRemoveIndex.

NoopRemoveIndex >> withRemoved: anElement
  ^ self.

"DroppingPlanIndex: plan: silently drops the first match."
PBEqualityIndex subclass: #DroppingPlanIndex.

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

PathBlindIndex >> supports: aTerm
  ^ self class supportedOperators includes: aTerm op.

"LenientPlanIndex: plan: on an unsupported term answers an empty plan instead of refusing."
PBEqualityIndex subclass: #LenientPlanIndex.

LenientPlanIndex >> plan: aTerm
  (self supports: aTerm) ifFalse: [
    ^ PBIndexPlan index: self term: aTerm part: (PBIndexPart kind: 'IndexLookup' producer: [:aBlock | nil]
      estimate: (PBEstimate rows: 0 cost: 0) details: nil rank: nil sortedRank: nil)].
  ^ super plan: aTerm.

"MutatingIndex: withAdded: updates the receiver in place and answers it. protoBaseST's atoms set
 their state once; the defect writes the state cell behind that rule (instVarNamed:put:), which is
 what a broken subclass could do."
PBEqualityIndex subclass: #MutatingIndex.

MutatingIndex >> withAdded: anElement
  | added |
  added := super withAdded: anElement.
  self instVarNamed: 'slots' put: (added instVarNamed: 'slots').
  ^ self.

"ContentKeepingBuildIndex: build: folds onto the receiver instead of an empty index."
PBEqualityIndex subclass: #ContentKeepingBuildIndex.

ContentKeepingBuildIndex >> build: aCollection
  | index |
  index := self.
  aCollection do: [:each | index := index withAdded: each].
  ^ index.

"ForgetfulEmptyIndex: empty answers the receiver, content kept."
PBEqualityIndex subclass: #ForgetfulEmptyIndex.

ForgetfulEmptyIndex >> empty
  ^ self.

"WrongOrderIndex: a descending ordered scan answers the ascending order."
PBRangeIndex subclass: #WrongOrderIndex.

WrongOrderIndex >> orderedPlan: aKeySpec descending: aBoolean
  ^ super orderedPlan: aKeySpec descending: false.

"UnstableOrderIndex: orders by a hash of the key instead of its order key."
PBRangeIndex subclass: #UnstableOrderIndex.

UnstableOrderIndex >> orderedPlan: aKeySpec descending: aBoolean
  | rows spec |
  spec := self keySpecObject.
  rows := (Array withAll: (super orderedPlan: aKeySpec descending: false) execute asArray)
    sort: [:a :b | (spec extract: a) printString hash <= (spec extract: b) printString hash].
  ^ PBIndexPlan index: self term: nil part: (PBIndexPart kind: 'IndexOrderedScan' producer: [:aBlock | rows do: aBlock]
    estimate: (PBEstimate rows: 0 cost: 0) details: nil rank: nil sortedRank: nil).

"OrderClaimingIndex: claims ordered iteration on every key but cannot provide it."
PBEqualityIndex subclass: #OrderClaimingIndex.

OrderClaimingIndex >> supportsOrder: aKeySpec
  ^ true.
