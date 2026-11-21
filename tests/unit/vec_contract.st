"EXPECT: ok 2"
"Vectors phase V6 (Addendum V, 2.4, 2.7 and 5.1): the index contract for PBVectorIndex (proto_db
 tests/contracts/index_contract.py:704-835 and tests/unit/test_vector_index.py:574-643 at
 v2.0.0rc4), the checks of tests/unit/idx_contract_plans.st with the vector registrations'
 element and term strategies and near_oracle as the oracle of near[] (near[] has no per-element
 semantics, so a scan cannot answer it): exact cosine, l2 and ip; ivf_flat cosine, l2 and ip with
 nlist 3 and nprobe 3 (every list probed: the answers are exact); exact l2 with numpy false (a
 parameter protoBaseST stores and ignores, deviation DV2); and exact cosine on plain values through
 an extractor. Seeds 1..PBST_PROP_SEEDS (default 8, proto_db's SEEDS). The records' key spec is
 one of proto_db's three, 'vec', 'emb.v' and the reversing extractor, taken by the seed (proto_db
 runs each seed on each), which keeps the run within the interpreted floor (protoST 0.14.1).
   planMatchesScan     (a) every term of the strategy that the index supports (near[] with k, a
                       threshold and both, a stored vector half the time, so exact ties occur;
                       and with the index's own metric named) answers what near_oracle answers,
                       in order, the stored elements themselves (exact tokens), twice, with an
                       explain naming the index and a valid estimate
   mutationSequence    (b) 30 random add, remove and replace steps: validate: passes and six terms
                       answer what near_oracle answers over the model, at every step
   persistence         (c) saved and loaded through a fresh storage by its tag, the index has its
                       class, definition and explain, answers every term as before and as the
                       oracle, and keeps working: loaded, then added; loaded, then removed
   unsupportedRaises   (e) a near[] naming another metric, of another dimension or on a foreign
                       path is not supported, and is refused by plan: and estimate:
   hooksDoNotMutate    (g) withAdded:, withRemoved:, withReplaced:with:, build: and empty leave the
                       receiver's state and explain as they were, and answer an index of its class
                       and name
   empty               (h) empty of a populated index holds nothing and keeps the definition
   orderedIteration    a vector index orders by nothing: an ordered plan is refused
   hookEquivalences    withReplaced:with: answers what withRemoved: then withAdded: answers, and
                       build: what the fold of withAdded: from empty answers, whatever the receiver
                       holds
   explain             explain names the index, its kind and its key
 Then the teeth (test_vector_contract_rejects_broken_variants): each vector plant of _qplants.st,
 made exact on 'cosine' and 'l2', is rejected by planMatchesScan for at least one seed. Saves go to
 out/vec_contract (git ignores out/), a new directory per run; nothing is removed."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.
Import from: '_qplants'.

Object subclass: #VContract instanceVariableNames: 'kind metric backend params set seed random'.

VContract class >> directory
  ^ ('out/vec_contract' asFileReference / ('run-' , Smalltalk pid printString , '-'
    , Time microsecondClockValue printString)) pathString.

VContract class >> dim
  ^ 4.

"index_contract.py VECTOR_THRESHOLDS."
VContract class >> thresholds: aMetric
  aMetric = 'cosine' ifTrue: [^ #(-1.0 0.0 0.5 0.9 1.0)].
  aMetric = 'l2' ifTrue: [^ #(0.0 1.0 2.0 3.5)].
  ^ #(-2.0 0.0 1.0 4.0).

"index_contract.py _value_vector: a deterministic vector field of a plain value; equal values
 agree. Python's float % and // are floored, as \\ and // are here."
VContract class >> valueVector: aValue
  | n |
  (aValue == true or: [aValue == false]) ifTrue: [^ PBTuple withAll: #(1.0 -1.0 0.0 1.0)].
  (aValue isClassObject not and: [aValue isInteger or: [aValue isFloat]]) ifTrue: [
    n := aValue asFloat.
    ^ PBTuple withAll: { n \\ 5. (n // 5) asFloat \\ 3. 1.0. 0.0 }].
  (aValue isClassObject not and: [aValue isString and: [aValue isSymbol not]]) ifTrue: [
    ^ PBTuple withAll: { aValue size asFloat. ((aValue inject: 0 into: [:s :ch | s + ch value]) \\ 7) asFloat. 0.0. 1.0 }].
  ((aValue isKindOf: PBTuple) and: [aValue size > 0 and: [(aValue at: 1) isClassObject not and: [(aValue at: 1) isInteger]]])
    ifTrue: [^ PBTuple withAll: { (aValue at: 1) asFloat. 0.0. 0.0. 0.0 }].
  aValue isNil ifTrue: [^ nil].
  ^ PBMissing default.

VContract class >> kind: aClass metric: aMetric backend: aBackend params: anArray set: aName seed: anInteger
  ^ self basicNew setKind: aClass metric: aMetric backend: aBackend params: anArray set: aName seed: anInteger.

VContract >> setKind: aClass metric: aMetric backend: aBackend params: anArray set: aName seed: anInteger
  kind := aClass.
  metric := aMetric.
  backend := aBackend.
  params := anArray.
  set := aName.
  seed := anInteger.
  random := QData random: anInteger + 9000.

VContract >> label
  ^ kind name , ' ' , backend , ' ' , metric , ' ' , params printString , ' ' , set , ' seed ' , seed printString.

VContract >> keySpec
  set = 'values' ifTrue: [^ PBKeySpec extractor: 'tests.contracts.value_vector'].
  ^ { PBKeySpec path: 'vec'. PBKeySpec path: 'emb.v'. PBKeySpec extractor: 'tests.contracts.reversed_vec' } at: seed \\ 3 + 1.

VContract >> between: lo and: hi
  ^ lo + (random next * (hi - lo + 1)) truncated.

VContract >> draw: anArray
  ^ anArray at: (random next * anArray size) truncated + 1.

"index_contract.py vector_value: small Integers (ties), Floats, a PBFrozenList, zero, Decimals or,
 sometimes, a key that is not a valid vector."
VContract >> vectorValue
  | pick d |
  d := VContract dim.
  pick := random next.
  pick < 0.45 ifTrue: [^ PBTuple withAll: ((1 to: d) collect: [:i | self between: -2 and: 2]) asArray].
  pick < 0.72 ifTrue: [^ PBTuple withAll: ((1 to: d) collect: [:i | random next * 4.0 - 2.0]) asArray].
  pick < 0.77 ifTrue: [^ PBFrozenList withAll: ((1 to: d) collect: [:i | (self between: -1 and: 1) asFloat]) asArray].
  pick < 0.80 ifTrue: [^ PBTuple withAll: ((1 to: d) collect: [:i | 0.0]) asArray].
  pick < 0.83 ifTrue: [^ PBTuple withAll: ((1 to: d) collect: [:i |
    Decimal fromString: ((self between: -4 and: 4) / 2) asFloat printString]) asArray].
  ^ self draw: { nil. PBTuple withAll: #(1.0 2.0). PBTuple withAll: { 1.0. Float nan. 0.0. 0.0 }. 'abcd'.
    PBTuple withAll: #(true 0 0 0). PBTuple withAll: #(1.0e200 1.0e200 1.0e200 1.0e200). PBTuple withAll: #('a' 1 2 3). 7 }.

"index_contract.py vector_record_strategy: n, sometimes vec, sometimes emb.v (a mapping or a
 nested record)."
VContract >> record
  | fields r |
  fields := OrderedCollection new.
  fields add: 'n' -> (self between: 0 and: 4).
  random next < 0.85 ifTrue: [fields add: 'vec' -> self vectorValue].
  r := random next.
  r < 0.4 ifTrue: [fields add: 'emb' -> (PBFrozenDict withAssociations: { 'v' -> self vectorValue })].
  (r >= 0.4 and: [r < 0.7]) ifTrue: [fields add: 'emb' -> (PBObject withAll: { 'v' -> self vectorValue })].
  ^ PBObject withAll: fields asArray.

VContract >> newElements: n
  set = 'values' ifTrue: [^ QData values: n seed: seed + (random next * 1000) truncated].
  ^ (1 to: n) asArray collect: [:i | self record].

"30 elements, then five of them again (duplicates)."
VContract >> elements
  | base |
  base := self newElements: 30.
  ^ base , ((1 to: 5) collect: [:i | self draw: base]) asArray.

VContract >> newIndex
  | d |
  d := nil.
  params isNil ifFalse: [d := Dictionary new. params do: [:p | d at: p key put: p value]].
  ^ kind name: 'idx' keySpec: self keySpec dim: VContract dim metric: metric backend: backend params: d.

VContract >> near: aPath vector: v k: k threshold: t metric: m
  ^ PBTerm path: aPath op: PBTerm nearOperator value: (PBNearQuery vector: v k: k threshold: t metric: m).

"index_contract.py vector_term_strategy: four rounds of k, threshold and both, on a stored vector
 half the time; then the own metric named, another metric, another dimension, a foreign path."
VContract >> termsFor: anArray
  | path stored out q other d |
  d := VContract dim.
  path := self keySpec termPath.
  stored := (anArray collect: [:e | | key |
    key := self keySpec extract: e.
    key == PBMissing default ifTrue: [nil] ifFalse: [PBVectorMath canonicalVector: key dim: d]]) reject: [:v | v isNil].
  out := OrderedCollection new.
  4 timesRepeat: [ | r k thr |
    r := random next.
    q := (stored notEmpty and: [r < 0.5])
      ifTrue: [self draw: stored]
      ifFalse: [r < 0.75
        ifTrue: [(1 to: d) asArray collect: [:i | (self between: -2 and: 2) asFloat]]
        ifFalse: [(1 to: d) asArray collect: [:i | random next * 4.0 - 2.0]]].
    k := self draw: #(1 2 3 5 8 50).
    thr := self draw: (VContract thresholds: metric).
    out add: (self near: path vector: q k: k threshold: nil metric: nil);
      add: (self near: path vector: q k: nil threshold: thr metric: nil);
      add: (self near: path vector: q k: k threshold: thr metric: nil)].
  q := (1 to: d) asArray collect: [:i | (self between: -2 and: 2) asFloat].
  other := #('cosine' 'l2' 'ip') detect: [:m | m ~= metric].
  out add: (self near: path vector: q k: 3 threshold: nil metric: metric);
    add: (self near: path vector: q k: 3 threshold: nil metric: other);
    add: (self near: path vector: q , #(1.0) k: 3 threshold: nil metric: nil);
    add: (self near: 'zz_contract_foreign_path' vector: q k: 3 threshold: nil metric: nil).
  ^ out asArray.

"The stored elements themselves, in order: exact token and identity of each."
VContract >> exact: anArray
  ^ anArray asArray collect: [:e | (PBKeys exactToken: e) hex , ':' , (PBMemberKeys identityOf: e) printString].

VContract >> oracle: anArray term: aTerm
  ^ self exact: (PBVectorIndex nearOracle: anArray keySpec: aTerm keySpecObject query: aTerm value metric: metric predicate: nil).

"Nil, or the first term of aTerms that anIndex supports and answers otherwise than the oracle."
VContract >> answers: anIndex over: anArray terms: aTerms
  aTerms do: [:term |
    (anIndex supports: term) ifTrue: [
      (self exact: (anIndex plan: term) execute) = (self oracle: anArray term: term) ifFalse: [
        ^ 'plan of ' , term describe printString , ' differs from the oracle']]].
  ^ nil.

"As Contract >> run: (idx_contract_plans.st): a failure String, a PBCorruptionError's text, or
 { #error. text } for any other error (never a rejection of a plant)."
VContract >> run: aBlock
  ^ [[aBlock value] on: PBCorruptionError do: [:e | e return: 'PBCorruptionError: ' , e messageText printString]]
    on: Error do: [:e | e return: { #error. e class name , ': ' , e messageText printString }].

VContract >> consistent: anIndex over: anArray terms: aTerms
  anIndex validate: anArray.
  ^ self answers: anIndex over: anArray terms: aTerms.

VContract >> term: aTermOrNil failing: aText
  ^ aTermOrNil isNil ifTrue: [nil] ifFalse: [aTermOrNil describe printString , aText].

"--- the checks ---"

VContract >> planMatchesScan
  ^ self run: [ | elements index |
    elements := self elements.
    index := self newIndex build: elements.
    self term: ((self termsFor: elements) detect: [:term |
      (index supports: term) and: [ | plan est info |
        plan := index plan: term.
        est := plan estimate.
        info := plan explain.
        (self exact: plan execute) ~= (self oracle: elements term: term)
          or: [(self exact: plan execute) ~= (self exact: plan execute)
          or: [((info at: 'index') at: 'index') ~= 'idx'
          or: [est rows < 0 or: [est cost < 0]]]]]]
      ifNone: [nil])
      failing: ' answers otherwise than the oracle, twice, with an explain and an estimate'].

VContract >> mutationSequence
  ^ self run: [ | pool model index failure |
    pool := self elements , (self newElements: 10).
    model := #().
    index := self newIndex.
    failure := nil.
    1 to: 30 do: [:step |
      failure isNil ifTrue: [ | r terms |
        r := random next.
        (r < 0.5 or: [model isEmpty])
          ifTrue: [ | e | e := self draw: pool. model := model , { e }. index := index withAdded: e]
          ifFalse: [ | victim at |
            at := (random next * model size) truncated + 1.
            victim := model at: at.
            model := (model copyFrom: 1 to: at - 1) , (model copyFrom: at + 1 to: model size).
            r < 0.75
              ifTrue: [index := index withRemoved: victim]
              ifFalse: [ | e | e := self draw: pool. model := model , { e }. index := index withReplaced: victim with: e]].
        index validate: model asArray.
        terms := (self termsFor: model asArray) copyFrom: 1 to: 6.
        failure := self answers: index over: model asArray terms: terms.
        failure isNil ifFalse: [failure := 'step ' , step printString , ': ' , failure]]].
    failure].

VContract >> persistence
  ^ self run: [ | elements index storage pointer tag loaded dir terms extra at rest |
    elements := self elements.
    index := self newIndex build: elements.
    terms := self termsFor: elements.
    dir := VContract directory.
    storage := PBFileStorage path: dir.
    index _saveInto: storage.
    pointer := index pointer.
    tag := index tag.
    storage close.
    loaded := PBTypeRegistry unloadedAtomFor: tag at: pointer storage: (PBFileStorage path: dir).
    loaded class == index class ifFalse: [^ 'the loaded index is a ' , loaded class name].
    { loaded name. loaded keySpec } = { index name. index keySpec } ifFalse: [^ 'the loaded index has another definition'].
    loaded explain = index explain ifFalse: [^ 'the loaded index explains otherwise'].
    (terms collect: [:t | (loaded supports: t) ifTrue: [self exact: (loaded plan: t) execute] ifFalse: [nil]])
      = (terms collect: [:t | (index supports: t) ifTrue: [self exact: (index plan: t) execute] ifFalse: [nil]])
      ifFalse: [^ 'the loaded index answers otherwise than the saved one'].
    (self consistent: loaded over: elements terms: terms) ifNotNil: [:f | ^ '(loaded) ' , f].
    extra := (self newElements: 1) first.
    (self consistent: (loaded withAdded: extra) over: elements , { extra } terms: (self termsFor: elements , { extra }))
      ifNotNil: [:f | ^ '(loaded, then added) ' , f].
    at := (random next * elements size) truncated + 1.
    rest := (elements copyFrom: 1 to: at - 1) , (elements copyFrom: at + 1 to: elements size).
    (self consistent: (loaded withRemoved: (elements at: at)) over: rest terms: terms)
      ifNotNil: [:f | ^ '(loaded, then removed) ' , f].
    nil].

"The last four terms of the strategy: the own metric named is supported; another metric, another
 dimension and a foreign path are not, and are refused."
VContract >> unsupportedRaises
  ^ self run: [ | elements index terms bad |
    elements := self elements.
    index := self newIndex build: elements.
    terms := self termsFor: elements.
    bad := terms copyFrom: terms size - 2 to: terms size.
    (index supports: (terms at: terms size - 3))
      ifFalse: ['the index refuses its own metric named']
      ifTrue: [self term: (bad detect: [:term |
          (index supports: term)
            or: [([index plan: term. false] on: PBNotSupportedError do: [:e | e return: true]) not
            or: [([index estimate: term. false] on: PBNotSupportedError do: [:e | e return: true]) not]]]
        ifNone: [nil])
        failing: ' is supported, or not refused']].

VContract >> hooksDoNotMutate
  ^ self run: [ | elements index before snapshot answers |
    elements := self elements.
    index := self newIndex build: (elements copyFrom: 1 to: 20).
    snapshot := [{ QData dump: index. index explain }].
    before := snapshot value.
    answers := OrderedCollection new.
    answers add: (index withAdded: (elements at: 25)); add: (index withRemoved: (elements at: 1));
      add: (index withReplaced: (elements at: 2) with: (elements at: 26)); add: (index build: (elements copyFrom: 21 to: 30));
      add: index empty.
    (snapshot value) = before
      ifFalse: ['a hook changed its receiver']
      ifTrue: [(answers anySatisfy: [:each | each class ~~ kind or: [each name ~= 'idx']])
        ifTrue: ['a hook answered another class or name'] ifFalse: [nil]]].

VContract >> empty
  ^ self run: [ | index emptied |
    index := self newIndex build: self elements.
    emptied := index empty.
    (emptied explain at: 'entries') = 0
      ifFalse: ['empty holds ' , (emptied explain at: 'entries') printString]
      ifTrue: [({ emptied class. emptied name. emptied keySpecObject describe. emptied params }
          = { kind. index name. index keySpecObject describe. index params })
        ifFalse: ['empty lost the definition'] ifTrue: [nil]]].

VContract >> orderedIteration
  ^ self run: [ | index |
    index := self newIndex build: self elements.
    ((index supportsOrder: (PBKeySpec path: 'zz_contract_foreign_path')) or: [index supportsOrder: self keySpec])
      ifTrue: ['a vector index claims an order']
      ifFalse: [([index orderedPlan: self keySpec descending: false. false] on: PBNotSupportedError do: [:e | e return: true])
        ifTrue: [nil] ifFalse: ['an index without order answered an ordered plan']]].

VContract >> hookEquivalences
  ^ self run: [ | elements index terms other |
    elements := self elements.
    index := self newIndex build: (elements copyFrom: 1 to: 20).
    terms := self termsFor: elements.
    (self answers: (index withReplaced: (elements at: 3) with: (elements at: 27)) over:
        ((elements copyFrom: 1 to: 2) , (elements copyFrom: 4 to: 20) , { elements at: 27 }) terms: terms)
      ifNotNil: [:failure | 'withReplaced:with: ' , failure]
      ifNil: [
        other := index build: (elements copyFrom: 21 to: 35).
        (self answers: other over: (elements copyFrom: 21 to: 35) terms: terms)
          ifNotNil: [:failure | 'build: on a populated receiver: ' , failure] ifNil: [nil]]].

VContract >> explain
  ^ self run: [ | info |
    info := (self newIndex build: self elements) explain.
    ({ info at: 'index'. info at: 'kind'. info at: 'key' } = { 'idx'. kind kindName. self keySpec describe })
      ifTrue: [nil] ifFalse: ['explain does not name the index, its kind and its key']].

PBKeySpec registerExtractor: 'tests.contracts.reversed_vec' block: [:e | | v |
  v := (PBKeySpec path: 'vec') extract: e.
  ((v isKindOf: PBTuple) or: [v isKindOf: PBFrozenList]) ifTrue: [PBTuple withAll: v asArray reverse] ifFalse: [v]] version: nil.
PBKeySpec registerExtractor: 'tests.contracts.value_vector' block: [:e | VContract valueVector: e] version: nil.

| c seeds checks registrations fails teeth caught |
c := Check new.
seeds := (1 to: (QData seeds: 8)) asArray.
checks := #(#planMatchesScan #mutationSequence #persistence #unsupportedRaises #hooksDoNotMutate #empty
  #orderedIteration #hookEquivalences #explain).
registrations := OrderedCollection new.
#('cosine' 'l2' 'ip') do: [:m |
  registrations add: { m. 'exact'. nil. 'records' }; add: { m. 'ivf_flat'. { 'nlist' -> 3. 'nprobe' -> 3 }. 'records' }].
registrations add: { 'l2'. 'exact'. { 'numpy' -> false }. 'records' }; add: { 'cosine'. 'exact'. nil. 'values' }.
fails := OrderedCollection new.
registrations do: [:r |
  seeds do: [:seed |
    checks do: [:check | | contract failure |
      contract := VContract kind: PBVectorIndex metric: (r at: 1) backend: (r at: 2) params: (r at: 3) set: (r at: 4) seed: seed.
      failure := contract perform: check.
      failure isNil ifFalse: [fails add: contract label , ' ' , check , ': ' , failure printString]]]].
fails do: [:each | ('FAIL ' , each) displayNl].
c that: 'the whole contract holds for PBVectorIndex, every registration, every seed' is: fails size equals: 0.

"test_vector_contract_rejects_broken_variants: each plant, exact on cosine and on l2, is rejected by
 planMatchesScan for at least one seed (a failure String, never another error)."
teeth := { OnceVectorIndex. MetricBlindVectorIndex. LastTieVectorIndex }.
caught := teeth select: [:plant |
  #('cosine' 'l2') anySatisfy: [:m | seeds anySatisfy: [:seed |
    ((VContract kind: plant metric: m backend: 'exact' params: nil set: 'records' seed: seed) planMatchesScan) isString]]].
(teeth reject: [:plant | caught includes: plant]) do: [:plant | ('NOT CAUGHT ' , plant name) displayNl].
c that: 'every planted vector defect is rejected by planMatchesScan' is: caught size equals: teeth size.
c report displayNl.
