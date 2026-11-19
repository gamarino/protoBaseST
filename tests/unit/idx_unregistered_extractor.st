"EXPECT: ok 4"
"Indexed queries, plan Task 4a, Review Focus 5 (design spec 5.4): a collection whose index names
 an extractor this process has not registered. The space is written here with the extractor
 'gone' registered (a PBDictionary of records with an equality index on it), then 'gone' is
 unregistered and the dictionary is read back through a fresh storage. Reading, getAt: and
 indexNames work; setAt:value:, addIndex: of another index and validate signal PBValidationError
 naming the extractor (proto_db's text, keyspec.py _registered); nothing is rebuilt or dropped:
 the stored index read again is the same record with the same content. The space goes to
 out/idx_unregistered_extractor (git ignores out/), a new directory per run."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.

| c people dir space tx dict loaded pointer reopen |
c := Check new.
people := QData people: 12 seed: 4200.
dir := 'out/idx_unregistered_extractor' asFileReference / ('run-' , Smalltalk pid printString , '-'
  , Time microsecondClockValue printString).
dir ensureCreateDirectory.
PBKeySpec registerExtractor: 'gone' block: [:p | (PBKeySpec path: 'name') extract: p] version: '1'.
dict := PBDictionary new.
people doWithIndex: [:p :i | dict := dict setAt: i value: p].
dict := dict addIndex: (PBEqualityIndex name: 'by_gone' keySpec: (PBKeySpec extractor: 'gone')).
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
tx := (space newDatabase: 'db') newTransaction.
tx setRootObject: 'people' value: dict.
tx commit.
space close.
PBKeySpec unregisterExtractor: 'gone'.

reopen := [:aBlock |
  | result |
  space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
  tx := (space openDatabase: 'db') newTransaction.
  result := aBlock value: (tx getRootObject: 'people').
  tx abort.
  space close.
  result].
pointer := reopen value: [:people2 | (people2 getIndex: 'by_gone') pointer].
reopen value: [:people2 |
  c that: 'setAt:value: names the extractor' signals: PBValidationError containing: '''gone'''
    during: [people2 setAt: 99 value: people first].
  c that: 'addIndex: of another index names it too' signals: PBValidationError containing: '''gone'''
    during: [people2 addIndex: (PBEqualityIndex name: 'by_city' path: 'city')].
  c that: 'validate names it' signals: PBValidationError containing: '''gone''' during: [people2 validate]].
c that: 'reading and indexNames work, and the stored index is unchanged'
  is: (reopen value: [:people2 | { people2 indexNames. people2 count. ((people2 getAt: 3) at: 'id').
    (people2 getIndex: 'by_gone') pointer = pointer. (people2 getIndex: 'by_gone') count }])
  equals: { #('by_gone'). 12. 2. true. 12 }.
c report displayNl.
