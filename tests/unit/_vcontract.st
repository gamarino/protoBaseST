"_vcontract.st: the index contract for PBVectorIndex (vectors phase V6; Addendum V, 2.4, 2.7 and
 5.1; proto_db tests/contracts/index_contract.py:704-835 and tests/unit/test_vector_index.py:574-643
 at v2.0.0rc4), run by tests/unit/vec_contract_exact.st (the exact registrations),
 tests/unit/vec_contract_ivf.st (the ivf_flat registrations and the teeth), and
 tests/unit/vec_contract_coll_cosine.st, vec_contract_coll_l2.st and vec_contract_coll_ip.st
 (check (f), the costliest, one file per metric), split so that each run keeps a wide margin
 under the runner's timeout (review I2 of task V6). A helper:
 nothing here runs on import but the registration of the two extractors. The checks of
 tests/unit/idx_contract_plans.st with the vector registrations' element and term strategies and
 near_oracle as the oracle of near[] (near[] has no per-element semantics, so a scan cannot answer
 it). The records' key spec is one of proto_db's three, 'vec', 'emb.v' and the reversing
 extractor, taken by the seed (proto_db runs each seed on each; unsupportedRaises runs all three),
 which keeps the run within the interpreted floor (protoST 0.14.1); the 'values' registration and
 the collections check use the value_vector extractor (proto_db's VALUE_VECTOR_SPEC).
   planMatchesScan     (a) every term of the strategy that the index supports (near[] with k, a
                       threshold and both, a stored vector half the time, so exact ties occur;
                       and with the index's own metric named) answers what near_oracle answers,
                       in order, the stored elements themselves (exact tokens), twice, with an
                       explain naming the index and a valid estimate
   mutationSequence    (b) proto_db's sequence: half the time a built start of 0 to 14 elements,
                       then 30 add (a quarter of them an element the model holds), remove and
                       replace steps; at every step validate: passes and every term of the
                       strategy over the elements ever seen answers what near_oracle answers over
                       the model (proto_db's focus terms are == and != on the touched keys, which
                       no vector index supports: (e) refuses that kind of term)
   persistence         (c) saved and loaded through a fresh storage by its tag, the index has its
                       class, definition and explain, answers every term as before and as the
                       oracle, and keeps working: loaded, then added; loaded, then removed
   concurrentReaders   (d) eight actors run every supported term over one version of 10 to 39
                       elements and over its loaded stub at once; each answers what near_oracle
                       answers
   unsupportedRaises   (e) on every key spec of the registration: the own metric named is
                       supported; a near[] naming another metric, of another dimension or on a
                       foreign path, and == 1 and ?N on four foreign paths (a path, a dotted
                       path, the element, an extractor; the key spec's own skipped) are not
                       supported, and each is refused by plan: and estimate:
   collections         (f) attached (before or after populating, by the draw) to every collection
                       kind protoBaseST writes with mutators (PBList, PBDictionary,
                       PBHashDictionary, PBSet, PBCountedSet: proto_db's factories of
                       tests/contracts/collection_contract.py, their populate and every mutator,
                       on plain values), the index on the value_vector extractor follows 20 random
                       mutators: after each, validate: passes and every term answers what
                       near_oracle answers over the collection's elements; saved and loaded, the
                       collection's index still does
   hooksDoNotMutate    (g) withAdded:, withRemoved:, withReplaced:with:, build: and empty leave the
                       receiver's state and explain as they were, and answer an index of its class
                       and name
   empty               (h) empty of a populated index holds nothing and keeps the definition
   orderedIteration    a vector index orders by nothing: an ordered plan is refused
   hookEquivalences    withReplaced:with: answers what withRemoved: then withAdded: answers, and
                       build: what the fold of withAdded: from empty answers, whatever the receiver
                       holds
   explain             explain names the index, its kind and its key
 Saves go to out/vec_contract (git ignores out/), a new directory per run; nothing is removed."
Import from: 'protobase'.
Import from: '_queries'.

Object subclass: #VContract instanceVariableNames: 'kind metric backend params set seed random spec groupedFor groupedKey grouped'.

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
  spec isNil ifFalse: [^ spec].
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

"index_contract.py _elements(rng, n): n elements, each, after the first, the same element as an
 earlier one once in five."
VContract >> randomElements: n
  | out |
  out := OrderedCollection new.
  n timesRepeat: [
    (out notEmpty and: [random next < 0.2])
      ifTrue: [out addLast: (self draw: out asArray)]
      ifFalse: [out addLast: (self newElements: 1) first]].
  ^ out asArray.

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
  ^ self termsForStored: (self storedOf: anArray).

"The valid stored vectors of anArray, canonical, in order (the strategy's stored)."
VContract >> storedOf: anArray
  ^ (anArray collect: [:e | | key |
    key := self keySpec extract: e.
    key == PBMissing default ifTrue: [nil] ifFalse: [PBVectorMath canonicalVector: key dim: VContract dim]]) reject: [:v | v isNil].

"The strategy's terms, its stored vectors given (storedOf: of the elements, which a caller that
 grows its elements by concatenation grows by concatenation too, without canonicalising them again)."
VContract >> termsForStored: aStored
  | path stored out q other d |
  d := VContract dim.
  path := self keySpec termPath.
  stored := aStored asArray.
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

"The stored elements themselves, in order: { exact token. identity } of each."
VContract class >> exact: anArray
  ^ anArray asArray collect: [:e | { PBKeys exactToken: e. PBMemberKeys identityOf: e }].

VContract >> exact: anArray
  ^ VContract exact: anArray.

VContract >> libraryOracle: anArray term: aTerm
  ^ self exact: (PBVectorIndex nearOracle: anArray keySpec: aTerm keySpecObject query: aTerm value metric: metric predicate: nil).

"near_oracle's answer, its grouping of anArray into members (canonical vector, member key and
 order key of each element: most of its cost) done once for every term over the same Array and key
 spec, then ranked per term as nearOracle:keySpec:query:metric:predicate: ranks it (planMatchesScan
 requires both forms to agree)."
VContract >> oracle: anArray term: aTerm
  | query key members out |
  query := aTerm value.
  key := { aTerm keySpecObject describe. query vector size }.
  (groupedFor == anArray and: [groupedKey = key]) ifFalse: [
    members := Dictionary new.
    grouped := OrderedCollection new.
    anArray do: [:element | | vector |
      vector := PBVectorMath canonicalVector: (aTerm keySpecObject extract: element) dim: query vector size.
      vector isNil ifFalse: [ | pair slot |
        pair := PBMemberKeys memberKeyAndOrderKeyOf: element.
        slot := members at: (pair at: 2) ifAbsent: [nil].
        slot isNil
          ifTrue: [
            slot := { pair at: 1. element. 1. vector. pair at: 2 }.
            members at: (pair at: 2) put: slot.
            grouped addLast: slot]
          ifFalse: [slot at: 3 put: (slot at: 3) + 1]]].
    groupedFor := anArray.
    groupedKey := key].
  out := OrderedCollection new.
  (PBVectorMath rank: grouped query: query vector metric: (query metric ifNil: [metric]) k: query k threshold: query threshold)
    do: [:pair | (pair at: 2) timesRepeat: [out addLast: (pair at: 1)]].
  ^ self exact: out.

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
          or: [(self oracle: elements term: term) ~= (self libraryOracle: elements term: term)
          or: [(self exact: plan execute) ~= (self exact: plan execute)
          or: [((info at: 'index') at: 'index') ~= 'idx'
          or: [est rows < 0 or: [est cost < 0]]]]]]]
      ifNone: [nil])
      failing: ' answers otherwise than the oracle, twice, with an explain and an estimate'].

VContract >> mutationSequence
  "seen: the stored vectors of every element ever added (removed keys stay in the term pivots)."
  ^ self run: [ | model seen index failure |
    index := self newIndex.
    model := #().
    seen := OrderedCollection new.
    random next < 0.5 ifTrue: [
      model := self randomElements: (self between: 0 and: 14).
      seen addAll: (self storedOf: model).
      index := index build: model].
    failure := nil.
    1 to: 30 do: [:step |
      failure isNil ifTrue: [ | r at new |
        r := random next.
        (model isEmpty or: [r < 0.45])
          ifTrue: [
            new := (model notEmpty and: [random next < 0.25]) ifTrue: [self draw: model] ifFalse: [(self newElements: 1) first].
            index := index withAdded: new.
            model := model , { new }.
            seen addAll: (self storedOf: { new })]
          ifFalse: [
            at := (random next * model size) truncated + 1.
            r < 0.75
              ifTrue: [
                index := index withRemoved: (model at: at).
                model := (model copyFrom: 1 to: at - 1) , (model copyFrom: at + 1 to: model size)]
              ifFalse: [
                new := (self newElements: 1) first.
                index := index withReplaced: (model at: at) with: new.
                model := model copy.
                model at: at put: new.
                seen addAll: (self storedOf: { new })]].
        failure := self consistent: index over: model terms: (self termsForStored: seen).
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

"A term, or nil when PBTerm refuses to make it."
VContract >> termOn: aPath op: anOp value: aValue
  ^ [PBTerm path: aPath op: anOp value: aValue] on: PBValidationError do: [:e | e return: nil].

"index_contract.py check_unsupported_raises, on every key spec of the registration."
VContract >> unsupportedRaises
  ^ self run: [ | specs failure |
    specs := set = 'values'
      ifTrue: [{ self keySpec }]
      ifFalse: [{ PBKeySpec path: 'vec'. PBKeySpec path: 'emb.v'. PBKeySpec extractor: 'tests.contracts.reversed_vec' }].
    failure := nil.
    [specs do: [:each |
      failure isNil ifTrue: [
        spec := each.
        failure := self unsupportedRaisesOnSpec]]] ensure: [spec := nil].
    failure].

"The last four terms of the strategy: the own metric named is supported; another metric, another
 dimension and a foreign path are not. Then == 1 and ?N on the four foreign paths. Every term on
 another path than the key spec's is unsupported, and every unsupported term is refused by plan:
 and by estimate:."
VContract >> unsupportedRaisesOnSpec
  | elements index terms own bad |
  elements := self elements.
  index := self newIndex build: elements.
  terms := (self termsFor: elements) asOrderedCollection.
  own := self keySpec termPath.
  (index supports: (terms at: terms size - 3)) ifFalse: [^ 'the index refuses its own metric named on ' , self keySpec describe].
  { 'zz_contract_foreign_path'. 'zz_contract_foreign_path.x'. nil. '@zz_contract_foreign_extractor' } do: [:other |
    other = own ifFalse: [
      (self termOn: other op: '==' value: 1) ifNotNil: [:t | terms addLast: t].
      (self termOn: other op: '?N' value: nil) ifNotNil: [:t | terms addLast: t]]].
  bad := terms detect: [:term |
      (term path ~= own and: [index supports: term])
        or: [(index supports: term) not
          and: [([index plan: term. false] on: PBNotSupportedError do: [:e | e return: true]) not
            or: [([index estimate: term. false] on: PBNotSupportedError do: [:e | e return: true]) not]]]]
    ifNone: [nil].
  ^ self term: bad failing: ' on ' , self keySpec describe , ' is supported on a foreign path, or not refused'.

"index_contract.py check_concurrent_readers: eight actors over one version and over its loaded
 stub; each answers what near_oracle answers, for every supported term."
VContract >> concurrentReaders
  ^ self run: [ | elements index terms expected dir storage pointer stub failure |
    elements := self randomElements: (self between: 10 and: 39).
    index := self newIndex build: elements.
    terms := (self termsFor: elements) select: [:t | index supports: t].
    expected := terms collect: [:t | self oracle: elements term: t].
    dir := VContract directory.
    storage := PBFileStorage path: dir.
    index _saveInto: storage.
    pointer := index pointer.
    storage close.
    storage := PBFileStorage path: dir.
    stub := PBTypeRegistry unloadedAtomFor: index tag at: pointer storage: storage.
    failure := nil.
    { index. stub } do: [:version |
      failure isNil ifTrue: [ | futures outputs |
        futures := (1 to: 8) asArray collect: [:j | VReader new asActor answers: version terms: terms].
        outputs := futures collect: [:f | f waitWithin: 300000].
        (outputs allSatisfy: [:o | o = expected]) ifFalse: [
          failure := (version == stub ifTrue: ['the stub'] ifFalse: ['the version']) , ': a reader answers otherwise than the oracle']]].
    storage close.
    failure].

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

"--- (f): the collections (tests/contracts/collection_contract.py's factories, plain values) ---"

VContract class >> collectionKinds
  ^ #('List' 'Dictionary' 'HashDictionary' 'Set' 'CountedSet').

"The mutator names of each kind, sorted, as proto_db draws them (sorted(factory.mutators))."
VContract class >> mutatorsOf: aKind
  aKind = 'List' ifTrue: [^ #('append_first' 'append_last' 'extend' 'insert_at' 'remove_at' 'set_at')].
  (aKind = 'Dictionary' or: [aKind = 'HashDictionary']) ifTrue: [^ #('remove_absent' 'remove_present' 'set_existing' 'set_new')].
  aKind = 'Set' ifTrue: [^ #('add_existing' 'add_new' 'difference' 'intersection' 'remove_absent' 'remove_present' 'union')].
  ^ #('add_existing' 'add_new' 'remove_absent' 'remove_decrement' 'remove_last').

VContract class >> emptyCollection: aKind
  aKind = 'List' ifTrue: [^ PBList new].
  aKind = 'Dictionary' ifTrue: [^ PBDictionary new].
  aKind = 'HashDictionary' ifTrue: [^ PBHashDictionary new].
  aKind = 'Set' ifTrue: [^ PBSet new].
  ^ PBCountedSet new.

"rng.choice over the alternatives anArray of blocks."
VContract >> choose: anArray
  ^ (self draw: anArray) value.

"_random_element: an Integer, a String, a Float, a Boolean or a pair."
VContract >> setElement
  ^ self choose: {
    [self between: 0 and: 59]. ['s' , (self between: 0 and: 29) printString]. [(self between: 0 and: 59) asFloat].
    [random next < 0.5]. [PBTuple withAll: { self between: 0 and: 2. 't' }] }.

"_fresh_element: a value aTest refuses."
VContract >> freshElement: aTest
  [ | e |
    e := self choose: { [self between: 0 and: 399]. ['s' , (self between: 0 and: 399) printString]. [(self between: 0 and: 399) asFloat] }.
    (aTest value: e) ifFalse: [^ e]] repeat.

"The dictionaries' fresh_key."
VContract >> freshKey: aDictionary
  [ | k |
    k := self choose: { [self between: 0 and: 199]. ['s' , (self between: 0 and: 199) printString]. [(self between: 0 and: 199) asFloat] }.
    (aDictionary has: k) ifFalse: [^ k]] repeat.

VContract >> pick: anArray
  ^ anArray isEmpty ifTrue: [nil] ifFalse: [self draw: anArray asArray].

VContract >> populate: aCollection kind: aKind
  | coll |
  coll := aCollection.
  aKind = 'List' ifTrue: [
    (self between: 0 and: 29) timesRepeat: [coll := coll insertAt: (self between: 0 and: coll count) value: (self between: 0 and: 39)].
    ^ coll].
  (aKind = 'Dictionary' or: [aKind = 'HashDictionary']) ifTrue: [
    (self between: 0 and: 29) timesRepeat: [
      coll := coll setAt: (self choose: { [self between: 0 and: 49]. ['s' , (self between: 0 and: 19) printString] })
        value: (self between: 0 and: 14)].
    ^ coll].
  aKind = 'Set' ifTrue: [
    (self between: 0 and: 29) timesRepeat: [coll := coll add: self setElement].
    ^ coll].
  (self between: 0 and: 39) timesRepeat: [
    coll := coll add: (self choose: { [self between: 0 and: 14]. ['s' , (self between: 0 and: 7) printString]. [true] })].
  ^ coll.

"The collection the mutator aName of aKind answers on aCollection, or nil when it does not apply
 (proto_db's None)."
VContract >> mutate: aCollection kind: aKind op: aName
  | n e k other |
  n := aCollection count.
  aKind = 'List' ifTrue: [
    aName = 'insert_at' ifTrue: [^ aCollection insertAt: (self between: n negated and: n) value: (self between: 0 and: 39)].
    aName = 'append_first' ifTrue: [^ aCollection appendFirst: (self between: 0 and: 39)].
    aName = 'append_last' ifTrue: [^ aCollection appendLast: (self between: 0 and: 39)].
    aName = 'extend' ifTrue: [^ aCollection extend: ((1 to: (self between: 0 and: 4)) asArray collect: [:i | self between: 0 and: 39])].
    n = 0 ifTrue: [^ nil].
    aName = 'set_at' ifTrue: [^ aCollection setAt: (self between: n negated and: n - 1) value: (self between: 0 and: 39)].
    ^ aCollection removeAt: (self between: n negated and: n - 1)].
  (aKind = 'Dictionary' or: [aKind = 'HashDictionary']) ifTrue: [
    aName = 'set_new' ifTrue: [^ aCollection setAt: (self freshKey: aCollection) value: (self between: 0 and: 14)].
    aName = 'remove_absent' ifTrue: [^ aCollection removeAt: (self freshKey: aCollection)].
    k := self pick: aCollection keys.
    k isNil ifTrue: [^ nil].
    aName = 'remove_present' ifTrue: [^ aCollection removeAt: k].
    "An equal key of another type (1 against 1.0) addresses the same entry."
    ((k isClassObject not and: [k isInteger]) and: [random next < 0.5]) ifTrue: [k := k asFloat].
    ^ aCollection setAt: k value: (self between: 0 and: 14)].
  aKind = 'Set' ifTrue: [
    aName = 'add_new' ifTrue: [^ aCollection add: (self freshElement: [:x | aCollection has: x])].
    aName = 'remove_absent' ifTrue: [^ aCollection remove: (self freshElement: [:x | aCollection has: x])].
    (#('union' 'intersection' 'difference') includes: aName) ifTrue: [
      other := PBSet new.
      aCollection elements do: [:x | random next < 0.4 ifTrue: [other := other add: x]].
      (self between: 0 and: 3) timesRepeat: [other := other add: (self freshElement: [:x | aCollection has: x])].
      aName = 'union' ifTrue: [^ aCollection union: other].
      aName = 'intersection' ifTrue: [^ aCollection intersection: other].
      ^ aCollection difference: other].
    e := self pick: aCollection elements.
    e isNil ifTrue: [^ nil].
    aName = 'remove_present' ifTrue: [^ aCollection remove: e].
    "1 and 1.0 are one member."
    ((e isClassObject not and: [e isInteger and: [e ~~ true and: [e ~~ false]]]) and: [random next < 0.5]) ifTrue: [e := e asFloat].
    ^ aCollection add: e].
  aName = 'add_new' ifTrue: [^ aCollection add: (self freshElement: [:x | aCollection has: x])].
  aName = 'remove_absent' ifTrue: [^ aCollection remove: (self freshElement: [:x | aCollection has: x])].
  aName = 'add_existing' ifTrue: [
    e := self pick: aCollection elements.
    ^ e isNil ifTrue: [nil] ifFalse: [aCollection add: e]].
  e := self pick: ((aCollection items select: [:a | aName = 'remove_last' ifTrue: [a value = 1] ifFalse: [a value > 1]])
    collect: [:a | a key]).
  ^ e isNil ifTrue: [nil] ifFalse: [aCollection remove: e].

"index_contract.py check_collections, every kind in turn, each with its own draws."
VContract >> collections
  ^ self run: [ | failure |
    failure := nil.
    [spec := PBKeySpec extractor: 'tests.contracts.value_vector'.
      VContract collectionKinds doWithIndex: [:aKind :i |
        failure isNil ifTrue: [
          random := QData random: seed + 9100 + i.
          failure := self collection: aKind]]] ensure: [spec := nil].
    failure].

VContract >> collection: aKind
  | coll early names seen dir storage pointer tag loaded failure |
  coll := VContract emptyCollection: aKind.
  early := random next < 0.5.
  early ifTrue: [coll := coll addIndex: self newIndex].
  coll := self populate: coll kind: aKind.
  early ifFalse: [coll := coll addIndex: self newIndex].
  names := VContract mutatorsOf: aKind.
  "The stored vectors of every element seen (proto_db's seen, extended by the elements at each step)."
  seen := OrderedCollection new.
  seen addAll: (self storedOf: coll elements).
  1 to: 20 do: [:step | | result elements index |
    result := self mutate: coll kind: aKind op: (self draw: names).
    result isNil ifFalse: [
      coll := result.
      elements := coll elements.
      seen addAll: (self storedOf: elements).
      index := coll getIndex: 'idx'.
      index class == kind ifFalse: [^ aKind , ' step ' , step printString , ': the index is a ' , index class name].
      (self consistent: index over: elements terms: (self termsForStored: seen))
        ifNotNil: [:f | ^ aKind , ' step ' , step printString , ': ' , f]]].
  dir := VContract directory.
  storage := PBFileStorage path: dir.
  coll _saveInto: storage.
  pointer := coll pointer.
  tag := coll tag.
  storage close.
  storage := PBFileStorage path: dir.
  loaded := PBTypeRegistry unloadedAtomFor: tag at: pointer storage: storage.
  failure := self consistent: (loaded getIndex: 'idx') over: loaded elements terms: (self termsForStored: seen).
  storage close.
  ^ failure isNil ifTrue: [nil] ifFalse: ['loaded ' , aKind , ': ' , failure].

"--- the run ---"

"The failures of every check of checks, for every registration ({ metric. backend. params. set })
 and every seed, each a line naming the contract, the check and the failure."
VContract class >> failuresOf: aRegistrations seeds: aSeeds checks: aChecks
  | fails |
  fails := OrderedCollection new.
  aRegistrations do: [:r |
    aSeeds do: [:aSeed |
      aChecks do: [:check | | contract failure |
        contract := VContract kind: PBVectorIndex metric: (r at: 1) backend: (r at: 2) params: (r at: 3) set: (r at: 4) seed: aSeed.
        failure := contract perform: check.
        failure isNil ifFalse: [fails add: contract label , ' ' , check , ': ' , failure printString]]]].
  ^ fails asArray.

"Every check, in proto_db's order (IndexContract.checks)."
VContract class >> checks
  ^ #(#planMatchesScan #mutationSequence #persistence #concurrentReaders #unsupportedRaises #collections
    #hooksDoNotMutate #empty #orderedIteration #hookEquivalences #explain).

"Runs every term of a version on its own actor (check (d))."
Object subclass: #VReader.

VReader >> answers: anIndex terms: aTerms
  ^ aTerms collect: [:t | VContract exact: (anIndex plan: t) execute].

PBKeySpec registerExtractor: 'tests.contracts.reversed_vec' block: [:e | | v |
  v := (PBKeySpec path: 'vec') extract: e.
  ((v isKindOf: PBTuple) or: [v isKindOf: PBFrozenList]) ifTrue: [PBTuple withAll: v asArray reverse] ifFalse: [v]] version: nil.
PBKeySpec registerExtractor: 'tests.contracts.value_vector' block: [:e | VContract valueVector: e] version: nil.

