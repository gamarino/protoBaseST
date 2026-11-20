"EXPECT: ok 9"
"Indexed queries, plan Task 4b: merges onto indexed currents (proto_db collections/base.py
 ConcurrentOptimized.rebase_onto, add_index and remove_index at v2.0.0rc4, lines 341-360 and
 594-631; transactions.py _merged).

 (1)-(4) Two transactions blind-write one root (a new collection with one write, the root never
 read) whose current value is an indexed PBDictionary, PBSet, PBCountedSet and PBHashDictionary:
 both commit, the later one's log replayed through the current version's mutators, and every
 index of the result holds what build: of its elements holds (entry for entry in key order, a
 group's key compared by order key, as idx_collections.st compares them), validate passing.
 (5) Two transactions each blind-write the root as a new dictionary with addIndex: of the same
 name: the later commit is PBConflictError naming the index (base.py 627-628). (6) Different
 names: both commit and both indexes are on the result, built over the merged elements.
 (7) removeIndex: of a loaded version rebased onto a version with a concurrent write keeps the
 write and drops the index; onto a version where the index was removed already, a no-op
 (proto_db test_collection_base.py test_rebase_index_removal). (8) A merge onto a current that
 holds a vector index is PBNotSupportedError naming it (design spec 3.3, ruling IQ5). (9) The
 index operations are replayed per name, as proto_db's: removed then added redefines the index
 over the merged elements; added then removed leaves the current version's index untouched
 (test_rebase_index_redefinition, test_rebase_index_added_then_removed_is_no_op); addIndex: and
 removeIndex: log ('@index_add' name index) and ('@index_remove' name) and keep the log complete,
 and a PBList logs nothing (base.py 475-476). Spaces go to out/idx_merge (git ignores out/), a new
 directory per run."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.

| c dir space db entries agree person city age seed blind outcomes merged names a b err stored mine
  theirs vector hnsw vspace redefined untouched logged list ops |
c := Check new.
dir := 'out/idx_merge' asFileReference / ('run-' , Smalltalk pid printString , '-'
  , Time microsecondClockValue printString).
dir ensureCreateDirectory.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'db'.
city := PBEqualityIndex name: 'by_city' path: 'city'.
age := PBRangeIndex name: 'by_age' path: 'age'.

"An index's entries in key order, a group's key as its order key (idx_collections.st)."
entries := [:index |
  | keys |
  keys := OrderedCollection new.
  PBAvl keysAndValuesDo: [:k :g | keys addLast: (PBKeys orderKey: k)] over: index groups.
  { keys asArray. (QData contents: index) collect: [:row |
    (row isArray and: [row first = 'group']) ifTrue: [{ row at: 2. row at: 4 }] ifFalse: [row]] }].
"true when every index of aCollection holds what build: of its elements holds and validate
 passes; otherwise what differs."
agree := [:aCollection |
  | problem |
  problem := nil.
  aCollection indexNames do: [:name |
    | index |
    index := aCollection getIndex: name.
    (entries value: index) = (entries value: (index empty build: aCollection)) ifFalse: [
      problem := name , ' differs from a rebuild']].
  problem isNil ifTrue: [
    problem := [aCollection validate. true] on: PBDBError do: [:e | e class name , ': ' , e messageText]].
  problem].
person := [:id :town :years | PBObject withAll: { 'id' -> id. 'city' -> town. 'age' -> years }].
seed := (1 to: 12) collect: [:i | person value: i value: (#('Oslo' 'Rome' 'Lima') at: i \\ 3 + 1) value: 20 + (i \\ 7)].

"The indexed roots, committed once."
db newTransactionDo: [:t |
  | d s bag h |
  d := PBDictionary new. s := PBSet new. bag := PBCountedSet new. h := PBHashDictionary new.
  seed do: [:p |
    d := d setAt: (p at: 'id') value: p. s := s add: p. bag := (bag add: p) add: p. h := h setAt: (p at: 'id') value: p].
  { 'd' -> d. 's' -> s. 'b' -> bag. 'h' -> h } do: [:each |
    t setRootObject: each key value: ((each value addIndex: city) addIndex: age)]].

"Two blind writers of root aName: aBlock value: transaction value: record answers the written
 value. Answers { outcome of A. outcome of B. the root read back }; B commits first."
blind := [:aName :aBlock |
  | ta tb ra rb |
  ta := db newTransaction.
  tb := db newTransaction.
  ta setRootObject: aName value: (aBlock value: ta value: (person value: 100 value: 'Kyiv' value: 41)).
  tb setRootObject: aName value: (aBlock value: tb value: (person value: 101 value: 'Oslo' value: 42)).
  rb := [tb commit. 'committed'] on: Error do: [:e | e class name].
  ra := [ta commit. 'committed'] on: Error do: [:e | e class name].
  { ra. rb. db newTransaction getRootObject: aName }].
outcomes := [:r | { r at: 1. r at: 2 }].

"(1)-(4)"
merged := blind value: 'd' value: [:t :p | t newDictionary setAt: (p at: 'id') value: p].
c that: 'blind writes onto an indexed PBDictionary both commit; its indexes equal a rebuild'
  is: { outcomes value: merged. (merged at: 3) count. ((merged at: 3) getAt: 100) notNil. ((merged at: 3) getAt: 101) notNil.
    (merged at: 3) indexNames. ((merged at: 3) getIndex: 'by_city') count. agree value: (merged at: 3) }
  equals: { #('committed' 'committed'). 14. true. true. #('by_age' 'by_city'). 14. true }.
merged := blind value: 's' value: [:t :p | t newSet add: p].
c that: 'blind writes onto an indexed PBSet both commit; its indexes equal a rebuild'
  is: { outcomes value: merged. (merged at: 3) count. ((merged at: 3) getIndex: 'by_age') count. agree value: (merged at: 3) }
  equals: { #('committed' 'committed'). 14. 14. true }.
merged := blind value: 'b' value: [:t :p | (t newCountedSet add: p) add: p].
c that: 'blind writes onto an indexed PBCountedSet both commit (the counter transform); its indexes equal a rebuild'
  is: { outcomes value: merged. (merged at: 3) count. (merged at: 3) totalCount. ((merged at: 3) getIndex: 'by_city') count.
    agree value: (merged at: 3) }
  equals: { #('committed' 'committed'). 14. 28. 14. true }.
merged := blind value: 'h' value: [:t :p | t newHashDictionary setAt: (p at: 'id') value: p].
c that: 'blind writes onto an indexed PBHashDictionary both commit; its indexes equal a rebuild'
  is: { outcomes value: merged. (merged at: 3) count. ((merged at: 3) getIndex: 'by_age') count. agree value: (merged at: 3) }
  equals: { #('committed' 'committed'). 14. 14. true }.

"(5)"
a := db newTransaction.
b := db newTransaction.
a setRootObject: 'd' value: (a newDictionary addIndex: (PBEqualityIndex name: 'by_id' path: 'id')).
b setRootObject: 'd' value: (b newDictionary addIndex: (PBEqualityIndex name: 'by_id' path: 'id')).
b commit.
err := [a commit. nil] on: Error do: [:e | e].
c that: 'the same index created by two blind writers: the later commit is PBConflictError naming it'
  is: { err class name. err messageText includesSubstring: '''by_id'''. (db newTransaction getRootObject: 'd') indexNames }
  equals: { #PBConflictError. true. #('by_age' 'by_city' 'by_id') }.

"(6)"
a := db newTransaction.
b := db newTransaction.
a setRootObject: 'd' value: ((a newDictionary addIndex: (PBEqualityIndex name: 'by_x' path: 'x')) setAt: 200 value: (person value: 200 value: 'Rome' value: 30)).
b setRootObject: 'd' value: ((b newDictionary setAt: 201 value: (person value: 201 value: 'Lima' value: 31)) addIndex: (PBRangeIndex name: 'by_y' path: 'y')).
b commit.
a commit.
merged := db newTransaction getRootObject: 'd'.
c that: 'different index names created by two blind writers: both commit and both indexes are built over the merged elements'
  is: { merged indexNames. merged count. (merged getIndex: 'by_x') count. (merged getIndex: 'by_y') count. agree value: merged }
  equals: { #('by_age' 'by_city' 'by_id' 'by_x' 'by_y'). 16. 16. 16. true }.

"(7) A loaded version: its log is empty, so a removeIndex: is its only op."
stored := db newTransaction getRootObject: 'd'.
mine := stored removeIndex: 'by_x'.
theirs := stored setAt: 300 value: (person value: 300 value: 'Oslo' value: 50).
merged := mine rebaseOnto: theirs.
c that: 'removeIndex: replayed onto a concurrent write keeps the write and drops the index; onto a removal, a no-op'
  is: { merged indexNames. (merged getAt: 300) notNil. merged count. agree value: merged.
    (mine rebaseOnto: (stored removeIndex: 'by_x')) indexNames }
  equals: { #('by_age' 'by_city' 'by_id' 'by_y'). true. 17. true. #('by_age' 'by_city' 'by_id' 'by_y') }.

"(8) A Dictionary whose index set holds the vector index of the conformance vector's 'hnsw'."
(dir / 'vector') ensureCreateDirectory.
'../conformance/vectors/database' asFileReference files do: [:f | f copyTo: dir / 'vector' / f basename].
vspace := PBObjectSpace storage: (PBFileStorage path: (dir / 'vector') pathString).
hnsw := ((vspace openDatabase: 'db') newTransaction getRootObject: 'hnsw') getIndex: 'hnsw'.
vector := PBDictionary new _withChanges: { 'indexes' -> (PBIndexSet new withIndex: hnsw) }.
c that: 'a merge onto a current holding a vector index is PBNotSupportedError naming it'
  signals: PBNotSupportedError containing: '''hnsw''' during: [(PBDictionary new setAt: 1 value: 2) rebaseOnto: vector].
vspace close.

"(9)"
stored := db newTransaction getRootObject: 'd'.
redefined := (stored removeIndex: 'by_city') addIndex: (PBEqualityIndex name: 'by_city' path: 'age').
merged := redefined rebaseOnto: (stored setAt: 400 value: (person value: 400 value: 'Quito' value: 60)).
untouched := ((PBDictionary new addIndex: (PBEqualityIndex name: 'by_z' path: 'z')) removeIndex: 'by_z')
  rebaseOnto: (stored addIndex: (PBRangeIndex name: 'by_z' path: 'id')).
logged := ((PBDictionary new addIndex: city) setAt: 1 value: (seed at: 1)) removeIndex: 'by_city'.
list := (PBList new addIndex: city) removeIndex: 'by_city'.
ops := logged opLog asArray.
c that: 'index operations replay per name: a redefinition is built over the merged elements, an index created and removed leaves the current one; they are logged, the log complete, never on a PBList'
  is: { merged indexNames. (merged getIndex: 'by_city') keySpecObject. (merged getIndex: 'by_city') count. agree value: merged.
    (untouched getIndex: 'by_z') class name. (untouched getIndex: 'by_z') keySpecObject.
    ops collect: [:op | op at: 1]. (ops first at: 2). (ops first at: 3) == city.
    ops last asArray. logged isMergeable. list opLog size }
  equals: { #('by_age' 'by_city' 'by_id' 'by_x' 'by_y'). PBKeySpec path: 'age'. 17. true.
    #PBRangeIndex. PBKeySpec path: 'id'.
    #('@index_add' 'set' '@index_remove'). 'by_city'. true. #('@index_remove' 'by_city'). true. 0 }.
space close.
c report displayNl.
