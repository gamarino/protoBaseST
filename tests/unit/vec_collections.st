"EXPECT: ok 8"
"Vectors phase V5 (Addendum V, 2.10 and 2.11; ruling IQ5a): collections holding vector indexes are
 written and merged. proto_db v2.0.0rc4 maintains a VectorIndex through the same IndexSet hooks as
 a key-group index (collections/base.py on_add, on_remove, on_replace, rebuilt_stale, rebase_onto);
 protoBaseST's collections now do too, and refuse only an index of a kind they do not know (an
 opaque atom, tests/unit/indexed_refusal.st).

 (1) tests/unit/test_structure_depth.py test_a_vector_index_store_key_adds_its_own_tuple: a member
 with a valid vector is stored under (list number, member key), 2 containers more
 (STORE_KEY_WRAPPING); one without a vector in the invalid group under its member key alone; each
 boundary appended and committed through a PBFileStorage, so the encoder is the judge. (2)
 test_an_index_added_over_existing_data_refuses_the_same_way: addIndex: of an equality index and of
 a VectorIndex over an element their member keys cannot store refuses at the call, with the same
 error, and the transaction goes on. (3) Every mutator of a PBList (insertAt:value:, appendFirst:, appendLast:, setAt:value:,
 removeAt:, extend:, sliceFrom:to:, head:, tail:), a PBDictionary and a PBHashDictionary
 (setAt:value: of a new and of a held key, removeAt: of a held and of an absent key), records
 drawn from a pool of 45 (so an element occurs more than once, a member counted twice)
 indexed on the path 'vec' by an exact (cosine), an hnsw (l2) and an ivf_flat (l2, nlist 3,
 retrain_growth 1.5, trained and retrained again and again as the collection grows) index: after
 every operation each index holds the members build: of the elements holds (the same members,
 counts and invalid group; for exact and hnsw also the same store entries in key order: an ivf
 index trained at another size files its members under other lists), and validate passes; after a
 slice, which rebuilds its indexes (proto_db's List.slice), every index is node for node build:'s
 (the encoded bytes of every atom). (4) The same for a PBSet (add:, remove:, union:,
 intersection:, difference:) and a PBCountedSet (add:, remove:) of plain values indexed on the
 element. (5) addIndex: of each backend over existing elements is build: node for node (the
 ivf_flat index trained once over them); removeIndex: drops it. (6) A format-3 vector index
 (member keys under another token, no member_tokens: generate.py _format3_index), exact and
 ivf_flat: a blind write (removeAt: of an absent key) keeps it, the same object; the first change
 rebuilds it as proto_db's rebuilt_stale does (empty build: over the elements, then the change's
 hook), node for node, current tokens, validate passing. (7) Merges standalone: a blind write of a
 PBDictionary (element writes, a removal, addIndex: of a new ivf_flat index) and of a PBCountedSet
 rebased onto a vector-indexed current (rebaseOnto:), the replayed adds crossing the ivf index's
 retrain threshold; the new index built over the merged elements node for node; then two
 transactions blind-writing the root of a space, both committed, the second merged by its commit.
 (8) A group commit (D52): three writers blind-write the vector-indexed root, queued one after the
 other on a storage that holds the root lock until the three have saved their atoms, so one build
 merges the three in queue order, one of them crossing the ivf retrain threshold inside the
 build: all three commit, with one publish, and the root read back agrees with build: and
 validates. Node-for-node identity with proto_db's own incremental trees is
 tests/interop/vector_ops_identical.sh's. Spaces go to out/vec_collections (git ignores out/), a
 new directory per run; nothing is removed."
Import from: 'protobase'.
Import from: '_check'.

"A storage that refuses the root lock until gate distinct PBDictionary atoms are saved (the
 writers' blind writes), and counts the publishes (tests/unit/idx_merge_extractor.st's GroupGate)."
PBFileStorage subclass: #VecGate instanceVariableNames: 'gate seen replaces'.
VecGate >> gate: n
  gate := n.
  seen := Atom on: #().
VecGate >> saved
  ^ seen isNil ifTrue: [0] ifFalse: [seen value size].
VecGate >> replaces
  ^ replaces ifNil: [0].
VecGate >> save: anAtom
  ((anAtom isKindOf: PBDictionary) and: [seen notNil])
    ifTrue: [seen swap: [:old | (old anySatisfy: [:each | each == anAtom]) ifTrue: [old] ifFalse: [old copyWith: anAtom]]].
  ^ super save: anAtom.
VecGate >> tryLockRoot
  (gate notNil and: [self saved < gate]) ifTrue: [^ false].
  gate := nil.
  ^ super tryLockRoot.
VecGate >> replaceRoot: aRecord
  replaces := self replaces + 1.
  ^ super replaceRoot: aRecord.

Object subclass: #VecWriter.
"Blind-writes aValue at aKey into the root 'd' of aDatabase and commits: 'ok' or { class name. text }."
VecWriter >> write: aValue at: aKey in: aDatabase
  ^ [aDatabase newTransactionDo: [:t | t setRootObject: 'd' value: (t newDictionary setAt: aKey value: aValue)]. 'ok']
    on: Error do: [:e | e return: { e class name asString. e messageText }].

| c dir held segment tup rec pool plain seed next ivfParams defs path element dump members entries agree run
  failures trainings coll count r space commit dbCount limits wrapping listsAt nest leaves text at over
  invalidAt invalidOver db tx lst deep n index legacy store invalid old blind changed rebuilt expected
  current log merged bag bagLog late a b storage before waitFor writers results kinds |
c := Check new.
dir := 'out/vec_collections' asFileReference / ('run-' , Smalltalk pid printString , '-'
  , Time microsecondClockValue printString).
dir ensureCreateDirectory.
segment := ByteArray fromHex: '0123456789abcdef0123456789abcdef'.
tup := [:anArray | PBTuple withAll: anArray].
"3-vectors of every numeric form, and keys that are not 3-vectors (another length, a String, nil)."
pool := { tup value: #(1.0 0.0 0.0). tup value: #(0.0 1.0 0.0). tup value: #(0.0 0.0 1.0). tup value: #(1 2 3).
  tup value: #(0.5 -0.5 0.25). tup value: { Decimal fromString: '1.5'. 0. -2 }. tup value: #(-1.0 0.5 2.0).
  tup value: #(3 4 0). tup value: #(0.1 0.2 0.3). tup value: #(2.0 2.0 2.0). tup value: #(-0.0 1.0 0.0).
  tup value: #(0.9 0.1 0.0). tup value: #(1.0 2.0). 'abc'. nil }.
"The plain values of the sets: the distinct ones of pool, less nil."
plain := pool copyFrom: 1 to: pool size - 1.
rec := [:i | PBObject withAll: { 'n' -> i. 'vec' -> (pool at: i * 7 \\ pool size + 1) }].
seed := 20261120.
next := [:bound | seed := (seed * 1103515245 + 12345) \\ 2147483648. seed // 65536 \\ bound].
ivfParams := Dictionary new at: 'nlist' put: 3; at: 'retrain_growth' put: 1.5; at: 'train_iters' put: 3;
  at: 'seed' put: 7; yourself.
"The three indexes, on aKeySpec."
defs := [:aKeySpec | {
  PBVectorIndex name: 'exact' keySpec: aKeySpec dim: 3 metric: 'cosine' backend: 'exact' params: nil.
  PBVectorIndex name: 'hnsw' keySpec: aKeySpec dim: 3 metric: 'l2' backend: 'hnsw' params: nil.
  PBVectorIndex name: 'ivf' keySpec: aKeySpec dim: 3 metric: 'l2' backend: 'ivf_flat' params: ivfParams } ].
path := PBKeySpec path: 'vec'.
element := PBKeySpec element.

"The atoms reached from root that are not saved, breadth first in the order the encoder meets the
 references, one line each: number, type name, the hex of the msgpack of the encoded state
 (tests/interop/_st_index_ops.st's dump, answered instead of printed). Equal lines are the same
 trees, node for node and byte for byte."
dump := [:root | | numbers cnt queue numberOf lines |
  numbers := Dictionary new.
  cnt := 0.
  lines := OrderedCollection new.
  queue := OrderedCollection new.
  numberOf := [:atom | | bucket found |
    bucket := numbers at: atom identityHash ifAbsent: [numbers at: atom identityHash put: OrderedCollection new].
    found := bucket detect: [:each | each key == atom] ifNone: [nil].
    found isNil ifTrue: [
      found := atom -> cnt.
      cnt := cnt + 1.
      bucket addLast: found.
      atom == root ifFalse: [queue addLast: atom]].
    found value].
  numberOf value: root.
  queue addLast: root.
  [queue isEmpty] whileFalse: [
    | atom ref map |
    atom := queue removeFirst.
    ref := [:child |
      child pointer notNil
        ifTrue: [PBCodec pointerRef value: child]
        ifFalse: [PBCodec _tagged: '@ref' body: { segment. numberOf value: child. PBTypeRegistry writerTag: child tag }]].
    map := MessagePackMap withAll: (atom state associations collect: [:each |
      each key -> (PBCodec toWire: each value atomRef: ref)]).
    lines addLast: (numberOf value: atom) printString , ' ' , atom class typeName , ' ' , (MessagePack encode: map) hex].
  lines asArray].
"{ the members with a vector, by member order key: (order key, count). the invalid group's members
 in key order: (order key, count). total }: what an index holds, whatever lists it files them under."
members := [:anIndex | | valid inv |
  valid := (anIndex storeEntries collect: [:a | { PBKeys orderKey: (a key at: 2). a value at: 2 }]) asArray
    sort: [:x :y | (x at: 1) <= (y at: 1)].
  inv := OrderedCollection new.
  PBAvl keysAndValuesDo: [:k :v | inv addLast: { PBKeys orderKey: k. v at: 2 }] over: (anIndex invalid at: 1).
  { valid. inv asArray. anIndex totalCount }].
"The store entries in key order: (store key order key, count, vector)."
entries := [:anIndex | anIndex storeEntries collect: [:a | { PBKeys orderKey: a key. a value at: 2. a value at: 3 }]].
"nil when every index of aCollection holds what build: of its elements holds (exact and hnsw: entry
 for entry; ivf_flat: member for member; aNodes true: node for node) and validate passes;
 otherwise what differs."
agree := [:aCollection :aNodes | | problem |
  problem := [aCollection validate. nil] on: PBDBError do: [:e | e return: 'validate: ' , e class name , ': ' , e messageText].
  problem isNil ifTrue: [
    aCollection indexNames do: [:name | | index built |
      index := aCollection getIndex: name.
      built := index empty build: aCollection.
      (members value: index) = (members value: built) ifFalse: [problem := name , ' holds other members than build:'].
      (index backend ~= 'ivf_flat' and: [(entries value: index) ~= (entries value: built)])
        ifTrue: [problem := name , ' differs from build: entry for entry'].
      (aNodes and: [(dump value: index) ~= (dump value: built)]) ifTrue: [problem := name , ' differs from build: node for node']]].
  problem].
"Runs aSteps operations on aCollection, each chosen by anOp (a block: collection, step -> new
 collection and whether proto_db rebuilds its indexes, so build: is node for node); answers
 { failures. how many times the ivf index trained or retrained }."
run := [:aCollection :aSteps :anOp | | fails trained last |
  coll := aCollection.
  fails := OrderedCollection new.
  trained := 0.
  last := 0.
  1 to: aSteps do: [:step | | pair problem size |
    pair := anOp value: coll value: step.
    coll := pair at: 1.
    problem := agree value: coll value: (pair at: 2).
    problem isNil ifFalse: [fails addLast: coll class name , ' step ' , step printString , ': ' , problem].
    (coll indexNames includes: 'ivf') ifTrue: [
      size := (coll getIndex: 'ivf') trainedSize.
      size = last ifFalse: [trained := trained + 1. last := size]]].
  { fails asArray. trained }].

"(1) test_a_vector_index_store_key_adds_its_own_tuple."
space := PBObjectSpace storage: (PBFileStorage path: (dir / 'depth') pathString).
dbCount := 0.
commit := [:aName :aValue | | d t |
  dbCount := dbCount + 1.
  d := space newDatabase: aName , dbCount printString.
  t := d newTransaction.
  t setRootObject: aName value: aValue.
  t commit.
  d newTransaction getRootObject: aName].
leaves := { 1. Decimal fromString: '1.5'. CalendarDate year: 2026 month: 1 day: 2.
  DateTime year: 2026 month: 1 day: 2 hour: 3 minute: 4 second: 0 microsecond: 0 fold: 0 zone: ZoneOffset utc }.
nest := [:k :leaf | | v | v := leaf. k timesRepeat: [v := PBFrozenList withAll: { v }]. v].
"An unorderable element (nested lists inside the maps anOuter names) whose member key, inside
 aWrapping containers, nests exactly aDepth (the test's lists_with_member_key_at)."
listsAt := [:aDepth :aWrapping :anOuter | | room v |
  room := aDepth - aWrapping - PBMemberKeys surrogateLeaf - (PBMemberKeys surrogateMapLevel * anOuter size).
  v := nest value: room // PBMemberKeys surrogateListLevel value: (leaves at: room \\ PBMemberKeys surrogateListLevel + 1).
  anOuter reverseDo: [:fields | v := PBFrozenDict withAssociations: fields , { 'deep' -> v }].
  v].
wrapping := PBMemberKeys memberKeyWrapping + PBVectorIndex storeKeyWrapping.
index := [PBVectorIndex name: 'near' keySpec: (PBKeySpec path: 'v') dim: 2 metric: 'cosine' backend: 'exact' params: nil].
at := listsAt value: PBCodec maxValueDepth value: wrapping value: { { 'v' -> (tup value: #(1.0 0.0)) } }.
over := listsAt value: PBCodec maxValueDepth + 1 value: wrapping value: { { 'v' -> (tup value: #(1.0 0.0)) } }.
invalidAt := listsAt value: PBCodec maxValueDepth value: PBMemberKeys memberKeyWrapping value: { { 'v' -> nil } }.
invalidOver := listsAt value: PBCodec maxValueDepth + 1 value: PBMemberKeys memberKeyWrapping value: { { 'v' -> nil } }.
text := [:aBlock | [aBlock value. ''] on: PBValidationError do: [:e | e return: e messageText]].
limits := PBMemberKeys depthLimitsWrapping: wrapping.
c that: 'the store key of a vector index adds its own tuple; an invalid member is stored under its member key alone'
  is: { PBCodec valueDepth: (PBMemberKeys memberKeyOf: (PBCodec canonical: at)).
    (commit value: 'v' value: ((PBList new addIndex: index value) appendLast: at)) count.
    ((text value: [(PBList new addIndex: index value) appendLast: over]) includesSubstring: 'Index ''near'' (VectorIndex on v)')
      and: [(text value: [(PBList new addIndex: index value) appendLast: over])
        includesSubstring: 'at most ' , (limits at: 'lists') printString , ' nested lists'].
    (commit value: 'w' value: ((PBList new addIndex: index value) appendLast: invalidAt)) count.
    (text value: [(PBList new addIndex: index value) appendLast: invalidOver]) includesSubstring: 'Index ''near''' }
  equals: { PBCodec maxValueDepth - PBVectorIndex storeKeyWrapping. 1. true. 1. true }.

"(2) test_an_index_added_over_existing_data_refuses_the_same_way, as proto_db's loop: an equality
 index and a vector index (the element, deep nested lists, is not a 2-vector: it goes to the
 invalid group, under its member key alone) each refused at addIndex:, with the same error; then
 the element removed, the vector index added, and the transaction's other work committed."
n := PBMemberKeys depthLimits at: 'lists'.
deep := nest value: n + 1 value: 1.
db := space newDatabase: 'added'.
tx := db newTransaction.
tx setRootObject: 'l' value: (PBList new extend: { 1. deep }).
tx commit.
tx := db newTransaction.
lst := tx getRootObject: 'l'.
text := { PBEqualityIndex name: 'e' keySpec: element.
    PBVectorIndex name: 'near' keySpec: element dim: 2 metric: 'cosine' backend: 'exact' params: nil }
  collect: [:def | | t |
    t := text value: [lst addIndex: def].
    { 'Index ' , (PBCodec repr: def name). 'member key would nest'. 'at most ' , n printString , ' nested lists' }
      allSatisfy: [:each | t includesSubstring: each]].
tx setRootObject: 'l' value: ((lst removeAt: 1) addIndex: (PBVectorIndex name: 'near' keySpec: element dim: 2 metric: 'cosine' backend: 'exact' params: nil)).
tx setRootObject: 'other' value: (PBObject withAll: { 'x' -> 1 }).
tx commit.
tx := db newTransaction.
c that: 'addIndex: of a vector index over data it cannot store refuses the same way, and the transaction goes on'
  is: { text. (tx getRootObject: 'l') count. (tx getRootObject: 'l') indexNames. (tx getRootObject: 'other') at: 'x' }
  equals: { #(true true). 1. #('near'). 1 }.
space close.

"(3) Every mutator of a PBList, a PBDictionary and a PBHashDictionary of records."
failures := OrderedCollection new.
trainings := OrderedCollection new.
held := (1 to: 45) collect: [:i | rec value: i].
r := 0.
kinds := Dictionary new.
"A PBList: the nine mutators in turn, positions drawn; a slice drops one element at most."
kinds at: 'list' put: [:aList :step | | op cnt |
  cnt := aList count.
  op := step \\ 9.
  (cnt = 0 and: [#(3 4 6 7 8) includes: op]) ifTrue: [op := 2].
  r := (next value: held size) + 1.
  op = 0 ifTrue: [{ aList insertAt: (next value: cnt + 1) value: (held at: r). false }] ifFalse: [
  op = 1 ifTrue: [{ aList appendFirst: (held at: r). false }] ifFalse: [
  op = 2 ifTrue: [{ aList appendLast: (held at: r). false }] ifFalse: [
  op = 3 ifTrue: [{ aList setAt: (next value: cnt) value: (held at: r). false }] ifFalse: [
  op = 4 ifTrue: [{ aList removeAt: (next value: cnt). false }] ifFalse: [
  op = 5 ifTrue: [{ aList extend: { held at: r. held at: r \\ held size + 1. held at: r }. false }] ifFalse: [
  op = 6 ifTrue: [{ aList sliceFrom: (next value: 2) to: cnt. true }] ifFalse: [
  op = 7 ifTrue: [{ aList head: cnt - (next value: 2). true }] ifFalse: [
  { aList tail: (next value: 2). true }]]]]]]]]].
"A dictionary: setAt:value: of a key drawn among 20 (new or held), and every third step removeAt:
 of a key drawn the same way (held or absent)."
kinds at: 'dict' put: [:aDict :step |
  r := (next value: held size) + 1.
  step \\ 3 = 0
    ifTrue: [{ aDict removeAt: (next value: 20). false }]
    ifFalse: [{ aDict setAt: (next value: 20) value: (held at: r). false }]].
#('list' 'dict' 'hash') do: [:kind | | empty result |
  empty := kind = 'list' ifTrue: [PBList new] ifFalse: [kind = 'dict' ifTrue: [PBDictionary new] ifFalse: [PBHashDictionary new]].
  (defs value: path) do: [:each | empty := empty addIndex: each].
  result := run value: empty value: 90 value: (kinds at: (kind = 'hash' ifTrue: ['dict'] ifFalse: [kind])).
  failures addAll: (result at: 1).
  trainings addLast: (result at: 2) >= 3].
c that: 'every mutator of a PBList, a PBDictionary and a PBHashDictionary maintains exact, hnsw and ivf_flat indexes as build: (node for node after a slice), the ivf one retrained as it grows'
  is: { failures asArray. trainings asArray } equals: { #(). #(true true true) }.

"(4) A PBSet and a PBCountedSet of plain values, indexed on the element."
failures := OrderedCollection new.
trainings := OrderedCollection new.
#('set' 'bag') do: [:kind | | empty result |
  empty := kind = 'set' ifTrue: [PBSet new] ifFalse: [PBCountedSet new].
  (defs value: element) do: [:each | empty := empty addIndex: each].
  result := run value: empty value: 70 value: [:aSet :step | | pick op |
    pick := [plain at: (next value: plain size) + 1].
    op := kind = 'set' ifTrue: [step \\ 6] ifFalse: [#(0 0 1) at: step \\ 3 + 1].
    op = 0 ifTrue: [{ aSet add: pick value. false }] ifFalse: [
    op = 1 ifTrue: [{ aSet remove: pick value. false }] ifFalse: [
    op = 2 ifTrue: [{ aSet union: { pick value. pick value }. false }] ifFalse: [
    op = 3 ifTrue: [{ aSet intersection: ((1 to: 10) collect: [:i | pick value]). false }] ifFalse: [
    op = 4 ifTrue: [{ aSet difference: { pick value }. false }] ifFalse: [
    { aSet add: pick value. false }]]]]]].
  failures addAll: (result at: 1).
  trainings addLast: (result at: 2) >= 2].
c that: 'every mutator of a PBSet and a PBCountedSet maintains exact, hnsw and ivf_flat indexes on the element as build:'
  is: { failures asArray. trainings asArray } equals: { #(). #(true true) }.

"(5) addIndex: over existing elements is build:, node for node; removeIndex: drops the index."
coll := PBDictionary new.
1 to: 25 do: [:i | coll := coll setAt: i value: (rec value: i + 500)].
failures := OrderedCollection new.
(defs value: path) do: [:def | | added |
  added := coll addIndex: def.
  (dump value: (added getIndex: def name)) = (dump value: (def empty build: coll)) ifFalse: [
    failures addLast: def name , ' differs from build:'].
  (agree value: added value: true) isNil ifFalse: [failures addLast: (agree value: added value: true)].
  (added removeIndex: def name) indexNames isEmpty ifFalse: [failures addLast: def name , ' not removed']].
c that: 'addIndex: of each backend over existing elements is build: node for node (ivf trained once over them); removeIndex: drops it'
  is: { failures asArray. ((coll addIndex: ((defs value: path) at: 3)) getIndex: 'ivf') trainedSize > 0 } equals: { #(). true }.

"(6) A format-3 vector index: member keys under another token ('T', ()), no member_tokens."
legacy := [:anIndex |
  store := nil.
  anIndex storeEntries do: [:a |
    store := (PBAvl keyPut: store key: (tup value: { a key at: 1. tup value: { (a key at: 2) at: 1. tup value: { 'T'. tup value: #() } } })
      value: a value nodeClass: PBKeyNode) at: 1].
  invalid := nil.
  PBAvl keysAndValuesDo: [:k :v |
    invalid := (PBAvl keyPut: invalid key: (tup value: { k at: 1. tup value: { 'T'. tup value: #() } }) value: v nodeClass: PBKeyNode) at: 1]
    over: (anIndex invalid at: 1).
  anIndex _with: { 'store' -> store. 'invalid' -> (tup value: { invalid. anIndex invalid at: 2 }). 'member_tokens' -> nil }].
failures := OrderedCollection new.
coll := PBDictionary new.
1 to: 9 do: [:i | coll := coll setAt: i value: (rec value: i + 700)].
{ (defs value: path) at: 1. (defs value: path) at: 3 } do: [:def |
  old := coll _withChanges: { 'indexes' -> (PBIndexSet new withIndex: (legacy value: (def empty build: coll))) }.
  blind := old removeAt: 'absent'.
  changed := blind setAt: 50 value: (rec value: 750).
  rebuilt := changed getIndex: def name.
  expected := (def empty build: blind) withAdded: (changed getAt: 50).
  failures addAll: ({ (old getIndex: def name) hasMemberTokens. (blind getIndex: def name) == (old getIndex: def name).
      rebuilt hasMemberTokens. (dump value: rebuilt) = (dump value: expected). (rebuilt validate: changed elements) == rebuilt }
    = #(false true true true true) ifTrue: [#()] ifFalse: [{ def name }])].
c that: 'a format-3 vector index (exact, ivf_flat) is kept by a blind write and rebuilt at the first change, node for node as proto_db''s rebuilt_stale'
  is: failures asArray equals: #().

"(7) Merges standalone."
failures := OrderedCollection new.
current := PBDictionary new.
(defs value: path) do: [:each | current := current addIndex: each].
1 to: 4 do: [:i | current := current setAt: i value: (rec value: i + 800)].
late := PBVectorIndex name: 'late' keySpec: path dim: 3 metric: 'cosine' backend: 'ivf_flat'
  params: (Dictionary new at: 'nlist' put: 2; yourself).
log := (((((PBDictionary new setAt: 10 value: (rec value: 810)) setAt: 11 value: (rec value: 811)) removeAt: 2)
  setAt: 3 value: (rec value: 812)) addIndex: late) setAt: 12 value: (rec value: 813).
log := log setAt: 13 value: (rec value: 815).
merged := log rebaseOnto: current.
text := agree value: merged value: false.
text isNil ifFalse: [failures addLast: 'dict: ' , text].
(dump value: (merged getIndex: 'late')) = (dump value: (late empty build: merged)) ifFalse: [failures addLast: 'late is not build:'].
bag := PBCountedSet new.
(defs value: element) do: [:each | bag := bag addIndex: each].
bag := ((bag add: (plain at: 1)) add: (plain at: 2)) add: (plain at: 1).
bagLog := ((((PBCountedSet new add: (plain at: 4)) add: (plain at: 5)) remove: (plain at: 1)) add: (plain at: 6)) add: (plain at: 13).
text := agree value: (bagLog rebaseOnto: bag) value: false.
text isNil ifFalse: [failures addLast: 'counted set: ' , text].
space := PBObjectSpace storage: (PBFileStorage path: (dir / 'standalone') pathString).
db := space newDatabase: 'db'.
db newTransactionDo: [:t | t setRootObject: 'd' value: current].
a := db newTransaction.
b := db newTransaction.
a setRootObject: 'd' value: (a newDictionary setAt: 20 value: (rec value: 820)).
b setRootObject: 'd' value: ((b newDictionary setAt: 21 value: (rec value: 821)) setAt: 22 value: (rec value: 822)).
b commit.
a commit.
coll := db newTransaction getRootObject: 'd'.
text := agree value: coll value: false.
text isNil ifFalse: [failures addLast: 'committed: ' , text].
c that: 'a blind write rebased onto a vector-indexed current, standalone: the indexes agree with build: and validate; an index the log added is build: over the merged elements; two blind commits both land'
  is: { failures asArray. merged indexNames. merged count. (merged getIndex: 'ivf') trainedSize > (current getIndex: 'ivf') trainedSize.
    coll count. coll keys asArray }
  equals: { #(). #('exact' 'hnsw' 'ivf' 'late'). 7. true. 7. #(1 2 3 4 20 21 22) }.
space close.

"(8) A group commit: three writers in one build."
storage := VecGate path: (dir / 'group') pathString.
space := PBObjectSpace storage: storage lockTimeout: 600000.
db := space newDatabase: 'db'.
current := PBDictionary new.
(defs value: path) do: [:each | current := current addIndex: each].
current := ((current setAt: 1 value: (rec value: 900)) setAt: 2 value: (rec value: 901)) setAt: 3 value: (rec value: 903).
db newTransactionDo: [:t | t setRootObject: 'd' value: current].
before := storage replaces.
storage gate: 3.
waitFor := [:k | | deadline |
  deadline := Time millisecondClockValue + 120000.
  [storage saved >= k or: [Time millisecondClockValue > deadline]] whileFalse: [(Future after: 5) wait]].
writers := OrderedCollection new.
#(30 31 32) doWithIndex: [:key :i |
  writers addLast: (VecWriter new asActor write: (rec value: key + 900) at: key in: db).
  waitFor value: i].
results := writers asArray collect: [:fut | [fut waitWithin: 120000] on: TimeoutError do: [:e | e return: 'no outcome within 120 s']].
coll := db newTransaction getRootObject: 'd'.
c that: 'a group commit of three blind writes onto a vector-indexed root: all commit in one publish, the ivf index retrained inside the build, and the root agrees with build:'
  is: { results. storage replaces - before. coll keys asArray. agree value: coll value: false.
    (coll getIndex: 'ivf') trainedSize > (current getIndex: 'ivf') trainedSize }
  equals: { #('ok' 'ok' 'ok'). 1. #(1 2 3 30 31 32). nil. true }.
space close.
c report displayNl.
