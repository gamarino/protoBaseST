"EXPECT: ok 15"
"Indexed queries, plan Task 4a: every collection keeps its indexes in step with its content in
 every mutator, as proto_db's collections do (collections/base.py, lists.py, dictionaries.py,
 hash_dictionaries.py, sets.py at v2.0.0rc4; design spec 5.3).

 For each collection kind (PBList, PBDictionary, PBHashDictionary, PBSet, PBCountedSet) a seeded
 sequence of 200 mutations runs with 0, 1 and 3 indexes (an equality index on the path 'city', a
 range index on the path 'age', a range index on an extractor of 'name'); the mutators take turns,
 so each one runs, with random arguments over 60 QData people records. The indexes are added by
 addIndex: after the 30th mutation (built over the elements then). Every 20 mutations and at the
 end, every index must hold what build: of the collection's elements holds, entry for entry in key
 order (QData contents:, whatever the tree shapes; a group's key compared by its order key, see
 entries), validate must pass, and without indexes the index set must stay the one the collection
 was made with. Node identity with proto_db is tests/interop/index_ops_identical.sh's.

 Then the collection rows of proto_db's test_index_base.py (test_index_attached_to_a_collection_
 persists) and of base.py: addIndex: of a taken name and removeIndex: of an absent one signal; a
 blind write (a set add: of a present element, a removeAt: of an absent key) answers the
 receiver's index set itself; a format-3 index (member_tokens absent, written here with
 SpaceBuilder as read_records_indexes.st writes one) is read as it is, survives a blind write,
 and is rebuilt with format-4 tokens by the first change; validate signals an index that does not
 hold the elements; a version written as a root reads back
 in the same transaction agreeing with its own indexes, and so does the committed one read from
 storage. Spaces go to out/idx_collections (git ignores out/), a new directory per run."
Import from: 'random'.
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.
Import from: '_spaces'.

| entries classes c people extractor indexSets agree random pick run kinds failures base dir space db tx d loaded
  idx set present dict stale b node wrongRef indexRef indexSet dictRef st blind changed list fresh |
c := Check new.
classes := Dictionary new.
{ PBList. PBDictionary. PBHashDictionary. PBSet. PBCountedSet } do: [:each | classes at: each name put: each].
extractor := 'tests.idx_collections.name'.
PBKeySpec registerExtractor: extractor block: [:p | (PBKeySpec path: 'name') extract: p] version: '1'.
people := QData people: 60 seed: 4100.
indexSets := {
  #().
  { PBEqualityIndex name: 'by_city' path: 'city' }.
  { PBEqualityIndex name: 'by_city' path: 'city'. PBRangeIndex name: 'by_age' path: 'age'.
    PBRangeIndex name: 'by_name' keySpec: (PBKeySpec extractor: extractor) } }.

"An index's entries in key order (QData contents:) with each group's key as its order key: a
 group keeps the key object first stored under it (keyPut:), so after removals and additions an
 incremental index may hold 30.0 where build: met 30 first, equal keys of different types, as in
 proto_db; everything else (members, elements, counts, totals) is compared as stored."
entries := [:index |
  | keys |
  keys := OrderedCollection new.
  PBAvl keysAndValuesDo: [:k :g | keys addLast: (PBKeys orderKey: k)] over: index groups.
  { keys asArray. (QData contents: index) collect: [:row |
    (row isArray and: [row first = 'group']) ifTrue: [{ row at: 2. row at: 4 }] ifFalse: [row]] }].

"nil when every index of aCollection holds what build: of its elements holds and validate passes;
 otherwise what differs."
agree := [:aCollection |
  | problem |
  problem := nil.
  aCollection indexNames do: [:name |
    | index |
    index := aCollection getIndex: name.
    (problem isNil and: [(entries value: index) ~= (entries value: (index empty build: aCollection))]) ifTrue: [
      problem := 'index ' , name , ' differs from build: of the elements']].
  problem isNil ifTrue: [
    [aCollection validate] on: Error do: [:e | problem := 'validate: ' , e messageText. e return: nil]].
  problem].

"The mutators of each kind, taking turns: each is a block [:collection | new version]."
kinds := Dictionary new.
kinds at: 'PBList' put: {
  [:l | l insertAt: (random between: 0 and: l count) value: (pick value: people)].
  [:l | l appendFirst: (pick value: people)].
  [:l | l appendLast: (pick value: people)].
  [:l | l isEmpty ifTrue: [l appendLast: (pick value: people)] ifFalse: [
    l setAt: (random between: 0 and: l count - 1) value: (pick value: people)]].
  [:l | l isEmpty ifTrue: [l appendLast: (pick value: people)] ifFalse: [l removeAt: (random between: 0 and: l count - 1)]].
  [:l | l extend: { pick value: people. pick value: people. pick value: people }].
  [:l | l sliceFrom: (random between: 0 and: 1) to: l count - (random between: 0 and: 1)].
  [:l | l head: l count - (random between: 0 and: 1)].
  [:l | l tail: (random between: 0 and: 1)].
  [:l | l extend: #()] }.
kinds at: 'PBDictionary' put: {
  [:m | m setAt: (random between: 0 and: 40) value: (pick value: people)].
  [:m | m removeAt: (random between: 0 and: 40)] }.
kinds at: 'PBHashDictionary' put: (kinds at: 'PBDictionary').
kinds at: 'PBSet' put: {
  [:s | s add: (pick value: people)].
  [:s | s remove: (pick value: people)].
  [:s | s union: { pick value: people. pick value: people }].
  [:s | s intersection: ((1 to: 50) collect: [:i | pick value: people])].
  [:s | s difference: { pick value: people. pick value: people }] }.
kinds at: 'PBCountedSet' put: {
  [:s | s add: (pick value: people)].
  [:s | s add: (pick value: people)].
  [:s | s remove: (pick value: people)] }.

"The 200 mutations of one kind with one index set; adds what failed to failures."
run := [:className :indexes :seed |
  | coll mutators empty |
  random := QData spreadOn: seed.
  coll := (classes at: className) new.
  empty := coll stateAt: 'indexes'.
  mutators := kinds at: className.
  1 to: 200 do: [:step |
    | problem |
    coll := (mutators at: step \\ mutators size + 1) value: coll.
    step = 30 ifTrue: [indexes do: [:each | coll := coll addIndex: each]].
    (step \\ 20 = 0 or: [step = 200]) ifTrue: [
      problem := agree value: coll.
      (indexes isEmpty and: [(coll stateAt: 'indexes') ~~ empty]) ifTrue: [problem := 'the index set changed'].
      (problem isNil and: [step >= 30 and: [coll indexNames size ~= indexes size]]) ifTrue: [problem := 'indexNames ' , coll indexNames printString].
      problem isNil ifFalse: [
        failures addLast: className , ' with ' , indexes size printString , ' indexes, seed ' , seed printString
          , ', step ' , step printString , ': ' , problem]]]].
pick := [:anArray | anArray at: (random between: 1 and: anArray size)].

#('PBList' 'PBDictionary' 'PBHashDictionary' 'PBSet' 'PBCountedSet') doWithIndex: [:className :k |
  failures := OrderedCollection new.
  indexSets doWithIndex: [:indexes :i | run value: className value: indexes value: 4100 + (k * 10) + i].
  c that: className , ': 200 mutations with 0, 1 and 3 indexes keep every index equal to build: of the elements'
    is: failures asArray equals: #()].

"base.py add_index and remove_index."
idx := PBEqualityIndex name: 'by_city' path: 'city'.
dict := (PBDictionary new setAt: 1 value: people first) addIndex: idx.
c that: 'addIndex: of a taken name' signals: PBValidationError containing: 'already exists'
  during: [dict addIndex: (PBRangeIndex name: 'by_city' path: 'age')].
c that: 'removeIndex: of an absent name' signals: PBValidationError containing: 'No index named'
  during: [dict removeIndex: 'by_age'].
c that: 'addIndex: and removeIndex: answer new versions and leave the receiver as it was'
  is: { (dict addIndex: (PBRangeIndex name: 'by_age' path: 'age')) indexNames. (dict removeIndex: 'by_city') indexNames.
    dict indexNames. (dict getIndex: 'by_city') count }
  equals: { #('by_age' 'by_city'). #(). #('by_city'). 1 }.

"Blind writes (base.py 513-519): the receiver's index set, no index work."
present := people at: 3.
set := ((PBSet new add: present) add: (people at: 4)) addIndex: idx.
c that: 'a set add: of a present element keeps the index set identical'
  isTrue: ((set add: present) stateAt: 'indexes') == (set stateAt: 'indexes').
c that: 'a removeAt: of an absent key keeps the index set identical'
  isTrue: ((dict removeAt: 99) stateAt: 'indexes') == (dict stateAt: 'indexes').

"A format-3 index (D58): member_tokens absent, its content not rebuilt (empty here, while the
 dictionary holds 'a'). Read as it is; a blind write keeps it; the first change rebuilds it from
 the elements before the change, as _current_indexes does."
base := 'out/idx_collections' asFileReference / ('run-' , Smalltalk pid printString , '-'
  , Time microsecondClockValue printString).
base ensureCreateDirectory.
b := SpaceBuilder segment: (ByteArray fromHex: '4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a').
indexRef := b add: 14 oid: 1 state: { 'name' -> 'by_v'. 'key_spec' -> (PBTuple withAll: { 'element'. nil }).
  'groups' -> nil. 'side' -> (PBTuple withAll: { nil. 0 }). 'total_count' -> 0 }.
node := b add: 0 oid: 2 state: { 'key' -> 'by_v'. 'value' -> indexRef. 'left' -> nil. 'right' -> nil.
  'height' -> 1. 'count' -> 1 }.
indexSet := b add: 3 oid: 3 state: { 'root' -> node }.
node := b add: 0 oid: 4 state: { 'key' -> 'k1'. 'value' -> 'a'. 'left' -> nil. 'right' -> nil. 'height' -> 1. 'count' -> 1 }.
dictRef := b add: 6 oid: 5 state: { 'root' -> node. 'count' -> 1. 'indexes' -> indexSet }.
"A format-4 index whose content disagrees with the dictionary's (it holds nothing): validate signals."
wrongRef := b add: 14 oid: 6 state: { 'name' -> 'by_w'. 'key_spec' -> (PBTuple withAll: { 'element'. nil }).
  'groups' -> nil. 'side' -> (PBTuple withAll: { nil. 0 }). 'total_count' -> 0. 'member_tokens' -> 1 }.
wrongRef := b add: 6 oid: 7 state: { 'root' -> node. 'count' -> 1. 'indexes' -> (b add: 3 oid: 8 state: { 'root' ->
  (b add: 0 oid: 9 state: { 'key' -> 'by_w'. 'value' -> wrongRef. 'left' -> nil. 'right' -> nil. 'height' -> 1. 'count' -> 1 }) }) }.
b writeTo: base / 'stale' root: dictRef.
st := PBFileStorage path: (base / 'stale') pathString.
stale := PBTypeRegistry unloadedAtomFor: dictRef tag at: dictRef pointer storage: st.
blind := stale removeAt: 'zz'.
c that: 'a format-3 index is read as it is, and a blind write keeps it'
  is: { (stale getIndex: 'by_v') hasMemberTokens. (stale getIndex: 'by_v') count.
    (blind getIndex: 'by_v') == (stale getIndex: 'by_v') }
  equals: #(false 0 true).
changed := stale setAt: 'k2' value: 'b'.
c that: 'the first change rebuilds it with format-4 tokens, from the elements'
  is: { (changed getIndex: 'by_v') hasMemberTokens. (changed getIndex: 'by_v') count. agree value: changed.
    (stale getIndex: 'by_v') hasMemberTokens }
  equals: #(true 2 nil false).
c that: 'validate checks every index against the elements' signals: PBCorruptionError containing: 'by_w'
  during: [(PBTypeRegistry unloadedAtomFor: wrongRef tag at: wrongRef pointer storage: st) validate].
st close.

"test_index_attached_to_a_collection_persists, and a version read back in the same transaction."
dir := base / 'space'.
dir ensureCreateDirectory.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'db'.
tx := db newTransaction.
list := (PBList new appendLast: (PBObject withAll: { 'city' -> 'a' })) addIndex: idx.
d := dict setAt: 2 value: (people at: 2).
tx setRootObject: 'list' value: list.
tx setRootObject: 'dict' value: d.
c that: 'a version read back in the same transaction agrees with its own indexes'
  is: { (tx getRootObject: 'dict') == d. agree value: (tx getRootObject: 'dict') } equals: #(true nil).
tx commit.
space close.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
tx := (space openDatabase: 'db') newTransaction.
loaded := tx getRootObject: 'list'.
fresh := tx getRootObject: 'dict'.
c that: 'an index attached to a collection persists (test_index_base.py), and validates read back'
  is: { loaded indexNames. ((loaded getIndex: 'by_city') validate: loaded elements) == (loaded getIndex: 'by_city').
    fresh indexNames. agree value: fresh. agree value: (fresh setAt: 3 value: (people at: 3)) }
  equals: { #('by_city'). true. #('by_city'). nil. nil }.
tx abort.
space close.
c report displayNl.
