"EXPECT: ok 6"
"Indexed queries, plan Task 4a, Review Focus 5 (design spec 5.4): a collection whose index names
 an extractor this process has not registered. The space is written here with the extractor
 'gone' registered (a PBDictionary of records with an equality index on it), then 'gone' is
 unregistered and the dictionary is read back through a fresh storage. As in proto_db (whose
 registry is checked only inside KeySpec.extract, keyspec.py 232), only what evaluates the
 extractor fails: setAt:value: of a new key and validate signal PBValidationError naming it;
 removeAt: of an absent key (a blind write), removeIndex: 'by_gone' and addIndex: of a path index
 succeed. Reading, getAt: and indexNames work; nothing is rebuilt or dropped: the stored index
 read again is the same record with the same content. The space goes to
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
  c that: 'setAt:value: of a new key evaluates the extractor and names it' signals: PBValidationError
    containing: '''gone''' during: [people2 setAt: 99 value: people first].
  c that: 'validate names it' signals: PBValidationError containing: '''gone''' during: [people2 validate].
  c that: 'removeAt: of an absent key, a blind write, succeeds and keeps the index set'
    is: ((people2 removeAt: 99) indexes == people2 indexes) equals: true.
  c that: 'removeIndex: of the extractor index succeeds'
    is: (people2 removeIndex: 'by_gone') indexNames equals: #().
  c that: 'addIndex: of a path index succeeds'
    is: (people2 addIndex: (PBEqualityIndex name: 'by_city' path: 'city')) indexNames equals: #('by_city' 'by_gone')].
c that: 'reading and indexNames work, and the stored index is unchanged'
  is: (reopen value: [:people2 | { people2 indexNames. people2 count. ((people2 getAt: 3) at: 'id').
    (people2 getIndex: 'by_gone') pointer = pointer. (people2 getIndex: 'by_gone') count }])
  equals: { #('by_gone'). 12. 2. true. 12 }.
c report displayNl.
