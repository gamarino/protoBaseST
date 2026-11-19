"EXPECT: ok 2"
"Indexed queries, plan Task 7: the whole index contract (proto_db tests/contracts/index_contract.py
 and tests/unit/test_index_contract.py at v2.0.0rc4), the plan half that tests/unit/idx_contract.st
 (Task 3, the structure half) left to the planner's task, for PBEqualityIndex and PBRangeIndex, on
 QData people (the path 'age': mixed numbers, absent and nil) and QData values (the element key
 spec, every value rank, unorderable ones included), for the seeds 1..PBST_PROP_SEEDS (default 8,
 proto_db's SEEDS). Each check takes a kind, a set and a seed, and answers nil or what failed:
   planMatchesScan     (a) every supported term of the contract's vocabulary (index_contract.py
                       terms_for: presence, nil, an absent key, '?T' and '?!T', and per pivot key
                       'contains', '==', '!=' and a random range operator, an 'in', a between per
                       type rank, terms on a foreign path) answers what a scan answers, the stored
                       values themselves (exact tokens), twice, with an explain naming the index and
                       a valid estimate
   mutationSequence    (b) 30 random add, remove and replace steps: validate: passes and the terms of
                       the step's pivots answer what a scan of the model answers, at every step
   persistence         (c) saved and loaded through a fresh storage, the index answers every term
                       as before
   unsupportedRaises   (e) a term the index does not support is refused by plan: and estimate:
                       (PBNotSupportedError); a term on a foreign path is never supported
   hooksDoNotMutate    (g) withAdded:, withRemoved:, withReplaced:with:, build: and empty leave the
                       receiver's state and explain as they were, and answer an index of its class
                       and name
   empty               (h) empty of a populated index holds nothing and keeps the definition
   orderedIteration    for the index's own key spec and another (the records' 'id', a foreign
                       path of the values): when supportsOrder:, orderedPlan:descending: answers every
                       stored occurrence in the total order of the keys (unorderable keys last),
                       descending the exact reverse of the key-group order, each group the same
                       multiset; otherwise it is refused (PBNotSupportedError)
   hookEquivalences    withReplaced:with: answers what withRemoved: then withAdded: answers, and
                       build: what the fold of withAdded: from empty answers, whatever the receiver
                       holds
   explain             explain names the index, its kind and its key
 Check (d), concurrent readers, and (f), every collection kind, are run by idx_contract.st (index
 versions under writers) and qry_prop_equals_scan.st (planned queries over every collection kind
 read by four actors at once).
 Then the teeth (test_contract_rejects_broken_index): each planted defect of _qplants.st is rejected
 by the check aimed at it for at least one seed and set, as proto_db's table pairs them. Saves go to
 out/idx_contract_plans (git ignores out/), a new directory per run; nothing is removed."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.
Import from: '_qplants'.

Object subclass: #Contract instanceVariableNames: 'kind set seed random'.

Contract class >> directory
  ^ ('out/idx_contract_plans' asFileReference / ('run-' , Smalltalk pid printString , '-'
    , Time microsecondClockValue printString)) pathString.

Contract class >> kind: aClass set: aName seed: anInteger
  ^ self basicNew setKind: aClass set: aName seed: anInteger.

Contract >> setKind: aClass set: aName seed: anInteger
  kind := aClass.
  set := aName.
  seed := anInteger.
  random := QData random: anInteger + 7000.

Contract >> label
  ^ kind name , ' ' , set , ' seed ' , seed printString.

Contract >> keySpec
  ^ set = 'people' ifTrue: [PBKeySpec path: 'age'] ifFalse: [PBKeySpec element].

"30 elements of the set, then five of them again (duplicates)."
Contract >> elements
  | base |
  base := set = 'people' ifTrue: [QData people: 30 seed: seed] ifFalse: [QData values: 30 seed: seed].
  ^ base , ((1 to: 5) collect: [:i | base at: (random next * base size) truncated + 1]).

Contract >> newIndex
  ^ kind name: 'idx' keySpec: self keySpec.

Contract >> draw: anArray
  ^ anArray at: (random next * anArray size) truncated + 1.

"The term, or nil when protoBaseST refuses to build it (an operand it does not accept)."
Contract >> term: aPath op: anOp value: aValue
  ^ [PBTerm path: aPath op: anOp value: aValue] on: PBValidationError do: [:e | e return: nil].

"The distinct orderable keys of anArray, shuffled."
Contract >> keysOf: anArray
  | keys out |
  keys := Dictionary new.
  out := OrderedCollection new.
  anArray do: [:e | | k |
    k := self keySpec extract: e.
    ((k isKindOf: PBMissing) not and: [PBKeys isOrderable: k]) ifTrue: [
      | token |
      token := (PBKeys exactToken: k) hex.
      (keys includesKey: token) ifFalse: [keys at: token put: k. out add: k]]].
  out := out asArray.
  out size to: 2 by: -1 do: [:i | | j t |
    j := (random next * i) truncated + 1.
    t := out at: i. out at: i put: (out at: j). out at: j put: t].
  ^ out.

"index_contract.py terms_for: the generic vocabulary over anArray's keys."
Contract >> termsFor: anArray
  | path keys pivots terms ranks |
  path := self keySpec termPath.
  keys := self keysOf: anArray.
  pivots := keys copyFrom: 1 to: (keys size min: 8).
  terms := OrderedCollection new.
  terms add: (self term: path op: '?N' value: nil); add: (self term: path op: '?!N' value: nil);
    add: (self term: path op: '==' value: nil); add: (self term: path op: '==' value: (PBTuple withAll: { 'contract-absent-key'. 0 }));
    add: (self term: 'zz_contract_foreign_path' op: '==' value: 1); add: (self term: 'zz_contract_foreign_path' op: '?N' value: nil);
    add: (self term: path op: '?T' value: nil); add: (self term: path op: '?!T' value: nil).
  pivots do: [:k |
    terms add: (self term: path op: 'contains' value: k); add: (self term: path op: '==' value: k);
      add: (self term: path op: '!=' value: k); add: (self term: path op: (self draw: #('<' '<=' '>' '>=')) value: k)].
  keys isEmpty ifFalse: [
    terms add: (self term: path op: 'in' value: ((1 to: (3 min: keys size)) collect: [:i | self draw: keys]) asArray)].
  ranks := Dictionary new.
  keys do: [:k | (ranks at: (PBKeys orderKey: k) rank ifAbsentPut: [OrderedCollection new]) add: k].
  ((Array withAll: ranks keys asArray) sort: [:a :b | a <= b]) do: [:rank | | group a b |
    group := (ranks at: rank) asArray.
    a := self draw: group. b := self draw: group.
    ((PBMemberKeys orderKeyOrNil: a) compareWith: (PBMemberKeys orderKeyOrNil: b)) > 0 ifTrue: [| t | t := a. a := b. b := t].
    terms add: (self term: path op: (self draw: #('between[]' 'between()' 'between(]' 'between[)')) value: { a. b })].
  ^ (terms reject: [:each | each isNil]) asArray.

"The exact tokens of anArray's elements, sorted: a multiset of the stored values themselves."
Contract >> exact: anArray
  ^ (Array withAll: (anArray asArray collect: [:e | (PBKeys exactToken: e) hex , ':' , (PBMemberKeys identityOf: e) printString]))
    sort: [:a :b | a <= b].

Contract >> scan: anArray term: aTerm
  ^ self exact: (anArray select: [:e | aTerm matches: e]).

"Nil, or the first term of aTerms that anIndex answers otherwise than a scan of anArray."
Contract >> answers: anIndex over: anArray terms: aTerms
  aTerms do: [:term |
    (anIndex supports: term) ifTrue: [
      (self exact: (anIndex plan: term) execute) = (self scan: anArray term: term) ifFalse: [
        ^ 'plan of ' , term describe printString , ' differs from the scan']]].
  ^ nil.

"Answers nil, or the failure of aBlock (its answer, or the error it signalled)."
Contract >> run: aBlock
  ^ [aBlock value] on: Error do: [:e | e return: e class name , ': ' , e messageText printString].

"--- the checks ---"

Contract >> planMatchesScan
  ^ self run: [ | elements index |
    elements := self elements.
    index := self newIndex build: elements.
    (self termsFor: elements) detect: [:term |
      (index supports: term) and: [ | plan est info |
        plan := index plan: term.
        est := plan estimate.
        info := plan explain.
        (self exact: plan execute) ~= (self scan: elements term: term)
          or: [(self exact: plan execute) ~= (self exact: plan execute)
          or: [((info at: 'index') at: 'index') ~= 'idx'
          or: [est rows < 0 or: [est cost < 0]]]]]]
      ifNone: [nil]].

Contract >> mutationSequence
  ^ self run: [ | pool model index failure |
    pool := self elements.
    model := #().
    index := self newIndex.
    failure := nil.
    1 to: 30 do: [:step |
      failure isNil ifTrue: [ | r terms |
        r := random next.
        (r < 0.5 or: [model isEmpty])
          ifTrue: [ | e | e := self draw: pool. model := model , { e }. index := index withAdded: e]
          ifFalse: [ | victim at |
            "By position: 1, 1.0 and true are equal values but distinct elements."
            at := (random next * model size) truncated + 1.
            victim := model at: at.
            model := (model copyFrom: 1 to: at - 1) , (model copyFrom: at + 1 to: model size).
            r < 0.75
              ifTrue: [index := index withRemoved: victim]
              ifFalse: [ | e | e := self draw: pool. model := model , { e }. index := index withReplaced: victim with: e]].
        index validate: model asArray.
        terms := (self termsFor: model asArray) copyFrom: 1 to: (12 min: (self termsFor: model asArray) size).
        failure := self answers: index over: model asArray terms: terms.
        failure isNil ifFalse: [failure := 'step ' , step printString , ': ' , failure]]].
    failure].

Contract >> persistence
  ^ self run: [ | elements index storage pointer loaded dir |
    elements := self elements.
    index := self newIndex build: elements.
    dir := Contract directory.
    storage := PBFileStorage path: dir.
    index _saveInto: storage.
    pointer := index pointer.
    storage close.
    loaded := kind unloadedAt: pointer storage: (PBFileStorage path: dir).
    loaded explain = index explain
      ifFalse: ['the loaded index explains otherwise']
      ifTrue: [self answers: loaded over: elements terms: (self termsFor: elements)]].

Contract >> unsupportedRaises
  ^ self run: [ | elements index |
    elements := self elements.
    index := self newIndex build: elements.
    (self termsFor: elements) detect: [:term |
      ((term path = 'zz_contract_foreign_path') and: [index supports: term])
        or: [(index supports: term) not and: [
          ([index plan: term. false] on: PBNotSupportedError do: [:e | e return: true]) not
            or: [([index estimate: term. false] on: PBNotSupportedError do: [:e | e return: true]) not]]]]
      ifNone: [nil]].

Contract >> hooksDoNotMutate
  ^ self run: [ | elements index before snapshot answers |
    elements := self elements.
    index := self newIndex build: (elements copyFrom: 1 to: 20).
    snapshot := [{ (index instVarNamed: 'slots') copy. index explain }].
    before := snapshot value.
    answers := OrderedCollection new.
    answers add: (index withAdded: (elements at: 25)); add: (index withRemoved: (elements at: 1));
      add: (index withReplaced: (elements at: 2) with: (elements at: 26)); add: (index build: (elements copyFrom: 21 to: 30));
      add: index empty.
    (snapshot value) = before
      ifFalse: ['a hook changed its receiver']
      ifTrue: [(answers anySatisfy: [:each | each class ~~ kind or: [each name ~= 'idx']])
        ifTrue: ['a hook answered another class or name'] ifFalse: [nil]]].

Contract >> empty
  ^ self run: [ | index emptied |
    index := self newIndex build: self elements.
    emptied := index empty.
    emptied count = 0
      ifFalse: ['empty holds ' , emptied count printString]
      ifTrue: [({ emptied class. emptied name. emptied keySpecObject describe } = { kind. index name. index keySpecObject describe })
        ifFalse: ['empty lost the definition'] ifTrue: [nil]]].

"The runs of equal slots of anArray under aKeySpec (Oracle slot: the order key, unorderable keys
 last), each a { slot. exact multiset }."
Contract >> groupsOf: anArray spec: aKeySpec
  | groups slotOf |
  slotOf := [:e | | k | k := aKeySpec extract: e.
    (PBKeys isOrderable: k) ifTrue: [{ 0. PBMemberKeys orderKeyOrNil: k }] ifFalse: [#(1)]].
  groups := OrderedCollection new.
  anArray do: [:e | | s |
    s := slotOf value: e.
    (groups notEmpty and: [self same: groups last first as: s])
      ifTrue: [groups last last add: e]
      ifFalse: [groups add: { s. OrderedCollection with: e }]].
  ^ groups asArray collect: [:g | { g first. self exact: g last asArray }].

Contract >> same: a as: b
  (a at: 1) = (b at: 1) ifFalse: [^ false].
  (a at: 1) = 1 ifTrue: [^ true].
  ^ ((a at: 2) compareWith: (b at: 2)) = 0.

Contract >> before: a as: b
  (a at: 1) = (b at: 1) ifFalse: [^ (a at: 1) < (b at: 1)].
  (a at: 1) = 1 ifTrue: [^ false].
  ^ ((a at: 2) compareWith: (b at: 2)) < 0.

"For the index's own key spec and another one (the path 'id' of the records, a foreign path of
 the values)."
Contract >> orderedIteration
  ^ self run: [ | elements index |
    elements := self elements.
    index := self newIndex build: elements.
    { self keySpec. set = 'people' ifTrue: [PBKeySpec path: 'id'] ifFalse: [PBKeySpec path: 'zz_contract_foreign_path'] }
      inject: nil into: [:failure :spec |
        failure ifNil: [self orderedIteration: index spec: spec over: elements]]].

Contract >> orderedIteration: index spec: aKeySpec over: elements
  | up down ups downs |
  (index supportsOrder: aKeySpec) ifFalse: [
    ^ ([index orderedPlan: aKeySpec descending: false. false] on: PBNotSupportedError do: [:e | e return: true])
      ifTrue: [nil] ifFalse: ['an index without order answered an ordered plan']].
  up := (index orderedPlan: aKeySpec descending: false) execute asArray.
  down := (index orderedPlan: aKeySpec descending: true) execute asArray.
  ups := self groupsOf: up spec: aKeySpec.
  downs := self groupsOf: down spec: aKeySpec.
  (self exact: up) ~= (self exact: elements) ifTrue: [^ 'the ordered scan does not answer every stored occurrence'].
  ((1 to: ups size - 1) allSatisfy: [:i | self before: ((ups at: i) at: 1) as: ((ups at: i + 1) at: 1)])
    ifFalse: [^ 'the ascending scan is not in the order of ' , aKeySpec describe printString].
  (downs size = ups size and: [(1 to: ups size) allSatisfy: [:i |
      (self same: ((ups at: i) at: 1) as: ((downs at: ups size + 1 - i) at: 1))
        and: [((ups at: i) at: 2) = ((downs at: ups size + 1 - i) at: 2)]]])
    ifFalse: [^ 'the descending scan is not the reverse of the key-group order'].
  ^ nil.

Contract >> hookEquivalences
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

Contract >> explain
  ^ self run: [ | info |
    info := (self newIndex build: self elements) explain.
    ({ info at: 'index'. info at: 'kind'. info at: 'key' } = { 'idx'. kind kindName. self keySpec describe })
      ifTrue: [nil] ifFalse: ['explain does not name the index, its kind and its key']].

| c seeds checks sets fails teeth caught |
c := Check new.
seeds := (1 to: (QData seeds: 8)) asArray.
checks := #(#planMatchesScan #mutationSequence #persistence #unsupportedRaises #hooksDoNotMutate #empty
  #orderedIteration #hookEquivalences #explain).
sets := #('people' 'values').
fails := OrderedCollection new.
{ PBEqualityIndex. PBRangeIndex } do: [:k |
  sets do: [:s |
    seeds do: [:seed |
      checks do: [:check | | contract failure |
        contract := Contract kind: k set: s seed: seed.
        failure := contract perform: check.
        failure isNil ifFalse: [fails add: contract label , ' ' , check , ': ' , failure]]]]].
fails do: [:each | ('FAIL ' , each) displayNl].
c that: 'the whole contract holds for PBEqualityIndex and PBRangeIndex, on records and values, every seed'
  is: fails size equals: 0.

"test_contract_rejects_broken_index: proto_db's table of (defect, check)."
teeth := {
  { NoopRemoveIndex. #mutationSequence }. { NoopRemoveIndex. #hookEquivalences }.
  { DroppingPlanIndex. #planMatchesScan }. { DroppingPlanIndex. #mutationSequence }. { DroppingPlanIndex. #persistence }.
  { PathBlindIndex. #unsupportedRaises }. { LenientPlanIndex. #unsupportedRaises }.
  { MutatingIndex. #hooksDoNotMutate }. { ContentKeepingBuildIndex. #hookEquivalences }.
  { ForgetfulEmptyIndex. #empty }.
  { WrongOrderIndex. #orderedIteration }. { UnstableOrderIndex. #orderedIteration }. { OrderClaimingIndex. #orderedIteration } }.
caught := teeth select: [:pair |
  seeds anySatisfy: [:seed | sets anySatisfy: [:s |
    ((Contract kind: pair first set: s seed: seed) perform: pair last) notNil]]].
(teeth reject: [:pair | caught includes: pair]) do: [:pair |
  ('NOT CAUGHT ' , pair first name , ' by ' , pair last) displayNl].
c that: 'every planted defect is rejected by the check aimed at it' is: caught size equals: teeth size.
c report displayNl.
