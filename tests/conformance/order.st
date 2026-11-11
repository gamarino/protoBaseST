"EXPECT: order ascending 41/43 expected 2 equal 4/4 unorderable 5/5"
"The manifest's order section (FS 'Order keys'):
   ascending    every value orders after every earlier one (all pairs, both ways, through
                PBKeys compare:with: and PBOrderKey <), and compares 0 with itself
   equal        the values of one group compare 0 pairwise, their order keys are =, and they
                have one hash key
   unorderable  PBKeys orderKey: refuses the value with PBValidationError, and isOrderable:
                answers false
 Ids are 'kind body' (_keyvectors.st); a listed expected difference prints EXPECTED <id>."
Import from: 'protobase'.
Import from: '_vectors'.
Import from: '_keyvectors'.
| manifest order ascending built run lines failures groups unorderable |
manifest := Vectors manifest.
order := manifest at: 'order'.
lines := OrderedCollection new.
failures := 0.
ascending := order at: 'ascending'.
built := OrderedCollection new.
run := VectorRun section: 'order' ids: (ascending collect: [:e | KeyVectors idOf: e]).
ascending do: [:entry |
  | id |
  id := KeyVectors idOf: entry.
  run begin.
  run stage: 'order' of: id do: [
    | v why |
    v := PBNotation build: entry.
    why := nil.
    (PBKeys compare: v with: v) = 0 ifFalse: [why := 'does not compare 0 with itself'].
    built do: [:prior |
      why isNil ifTrue: [
        ((PBKeys compare: (prior at: 2) with: v) = -1 and: [(PBKeys compare: v with: (prior at: 2)) = 1
            and: [(PBKeys orderKey: (prior at: 2)) < (PBKeys orderKey: v)
            and: [((PBKeys orderKey: v) < (PBKeys orderKey: (prior at: 2))) not]]])
          ifFalse: [why := 'does not order after ' , (prior at: 1)]]].
    built add: { id. v }.
    why].
  run end: id].
failures := failures + run failures.
lines add: (run summaryAs: 'order ascending').
groups := order at: 'equal'.
run := VectorRun section: 'order-equal' ids: ((1 to: groups size) asArray collect: [:i | 'group ' , i printString]).
groups doWithIndex: [:group :i |
  | id |
  id := 'group ' , i printString.
  run begin.
  run stage: 'equal' of: id do: [
    | vs why |
    vs := group collect: [:e | PBNotation build: e].
    why := nil.
    vs do: [:a | vs do: [:b |
      why isNil ifTrue: [
        ((PBKeys compare: a with: b) = 0 and: [(PBKeys orderKey: a) = (PBKeys orderKey: b)
            and: [(PBKeys orderKey: a) hash = (PBKeys orderKey: b) hash
            and: [(PBKeys hashKey: a) = (PBKeys hashKey: b)]]])
          ifFalse: [why := a printString , ' and ' , b printString , ' are not one key']]]].
    why].
  run end: id].
failures := failures + run failures.
lines add: (run summaryAs: 'equal').
unorderable := order at: 'unorderable'.
run := VectorRun section: 'order-unorderable' ids: (unorderable collect: [:e | KeyVectors idOf: e]).
unorderable do: [:entry |
  | id |
  id := KeyVectors idOf: entry.
  run begin.
  run stage: 'unorderable' of: id do: [
    | v refused |
    v := PBNotation build: entry.
    refused := [PBKeys orderKey: v. false] on: PBValidationError do: [:e | true].
    (refused and: [(PBKeys isOrderable: v) == false])
      ifTrue: [nil]
      ifFalse: ['is orderable']].
  run end: id].
failures := failures + run failures.
lines add: (run summaryAs: 'unorderable').
failures > 0
  ifTrue: [('FAILED ' , failures printString , ' vector(s)') displayNl]
  ifFalse: [(' ' join: lines) displayNl]
