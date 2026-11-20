"_st_vector_ops.st: protoBaseST's side of tests/interop/vector_ops_identical.sh and
 tests/interop/vector_both_directions.sh (vectors phase V5, Addendum V 2.10, 2.11 and 5.2). A
 helper: the runner never runs files whose name starts with _.

 Usage: protost _st_vector_ops.st replay <directory>
        protost _st_vector_ops.st write|change|verify <directory>

 replay reads a copy of the spaces tests/interop/py_vector_replay.py made (<directory>/main:
 'records' and the operation sequences 'ops'; <directory>/legacy: proto_db's format-3 space) and
 does what py_vector_replay.py replay does, in the same order: replays every sequence from a new
 collection of its kind (the element mutators and addIndex: / removeIndex: of the exact, hnsw and
 ivf_flat indexes), validates each result, rebases the blind write of py_vector_replay.py
 merge_log onto the replayed dictionary, hash dictionary and counted set, then changes the
 legacy root 'vectors' (a blind extend: of nothing keeps its format-3 index, the same object; an
 appendLast: of its first element rebuilds it). It prints each result in py_vector_replay.py's
 dump format ('collection <name>', then one line per atom reached from it that is not saved yet,
 breadth first in the order the encoder meets the references), commits them as py_vector_replay.py
 does, and prints 'end'.

 write, change and verify are py_vector_replay.py's modes of the same names, in protoBaseST, for
 tests/interop/vector_both_directions.sh: write makes the database 'bd' (the records of bd_vec and
 the five collections with the exact, hnsw and ivf_flat indexes); change runs every mutator of
 each kind on its root, adds and removes an index, commits, then commits two blind writes of
 'dict' and 'bag' (the second merged by its commit onto the vector-indexed current); verify
 validates every root and prints one line per root: its count, its index names, and each index's
 members and invalid occurrences (vector search, which py_vector_replay.py verify also runs, is
 the vectors phase's V6)."
Import from: 'protobase'.

| args mode dir segment dump print kinds classes records ops defs apply mergeLog results currents space
  tx old before blind changed vec record bdIndexes bdBuild bdChanges db extra a b tup |
args := Smalltalk arguments.
(args size = 2 and: [#('replay' 'write' 'change' 'verify') includes: args first]) ifFalse: [
  'usage: protost _st_vector_ops.st replay|write|change|verify <directory>' displayNl.
  Smalltalk exit: 2].
mode := args first.
dir := args at: 2.
segment := ByteArray fromHex: '0123456789abcdef0123456789abcdef'.
tup := [:anArray | PBTuple withAll: anArray].
kinds := #('list' 'dict' 'hash' 'set' 'bag').
classes := Dictionary new.
classes at: 'list' put: PBList; at: 'dict' put: PBDictionary; at: 'hash' put: PBHashDictionary; at: 'set' put: PBSet;
  at: 'bag' put: PBCountedSet.

"The dump of py_vector_replay.py (and py_index_replay.py): numbers: identityHash -> Associations
 atom -> number (protoST has no IdentityDictionary)."
dump := [:root | | numbers count queue numberOf |
  numbers := Dictionary new.
  count := 0.
  numberOf := [:atom | | bucket found |
    bucket := numbers at: atom identityHash ifAbsent: [numbers at: atom identityHash put: OrderedCollection new].
    found := bucket detect: [:each | each key == atom] ifNone: [nil].
    found isNil ifTrue: [
      found := atom -> count.
      count := count + 1.
      bucket addLast: found.
      atom == root ifFalse: [queue addLast: atom]].
    found value].
  queue := OrderedCollection new.
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
    ((numberOf value: atom) printString , ' ' , atom class typeName , ' ' , (MessagePack encode: map) hex) displayNl]].
print := [:aResults | aResults do: [:each |
  ('collection ' , each key) displayNl.
  dump value: each value]].
"aCollection after one op (py_vector_replay.py apply; positions and keys as written, a record by
 its 0-based number)."
apply := [:kind :coll :op |
  | code rec |
  code := op at: 1.
  rec := [:k | records at: (op at: k) + 1].
  code = 90
    ifTrue: [coll addIndex: (defs at: (op at: 2) + 1)]
    ifFalse: [
      code = 91
        ifTrue: [coll removeIndex: (defs at: (op at: 2) + 1) name]
        ifFalse: [
          kind = 'list'
            ifTrue: [
              code = 0 ifTrue: [coll insertAt: (op at: 2) value: (rec value: 3)] ifFalse: [
              code = 1 ifTrue: [coll appendFirst: (rec value: 2)] ifFalse: [
              code = 2 ifTrue: [coll appendLast: (rec value: 2)] ifFalse: [
              code = 3 ifTrue: [coll setAt: (op at: 2) value: (rec value: 3)] ifFalse: [
              code = 4 ifTrue: [coll removeAt: (op at: 2)] ifFalse: [
              code = 5 ifTrue: [coll extend: { rec value: 2. rec value: 3. rec value: 4 }] ifFalse: [
              code = 6 ifTrue: [coll sliceFrom: (op at: 2) to: (op at: 3)] ifFalse: [
              code = 7 ifTrue: [coll head: (op at: 2)] ifFalse: [coll tail: (op at: 2)]]]]]]]]]
            ifFalse: [
              (kind = 'dict' or: [kind = 'hash'])
                ifTrue: [code = 0 ifTrue: [coll setAt: (op at: 2) value: (rec value: 3)] ifFalse: [coll removeAt: (op at: 2)]]
                ifFalse: [
                  kind = 'set'
                    ifTrue: [
                      code = 0 ifTrue: [coll add: (rec value: 2)] ifFalse: [
                      code = 1 ifTrue: [coll remove: (rec value: 2)] ifFalse: [
                      code = 2 ifTrue: [coll union: { rec value: 2. rec value: 3 }] ifFalse: [
                      code = 3
                        ifTrue: [coll intersection: ((2 to: op size) collect: [:k | rec value: k])]
                        ifFalse: [coll difference: { rec value: 2. rec value: 3 }]]]]]
                    ifFalse: [code = 0 ifTrue: [coll add: (rec value: 2)] ifFalse: [coll remove: (rec value: 2)]]]]]]].

"py_vector_replay.py merge_log: the blind write of aKind rebased onto the replayed collection."
mergeLog := [:aKind | | coll |
  coll := (classes at: aKind) new addIndex: (PBVectorIndex name: 'late' keySpec: (PBKeySpec path: 'vec') dim: 3
    metric: 'l2' backend: 'ivf_flat' params: (Dictionary new at: 'nlist' put: 2; at: 'seed' put: 1; yourself)).
  (aKind = 'dict' or: [aKind = 'hash'])
    ifTrue: [
      coll := (((coll setAt: 3 value: (records at: 41)) setAt: 17 value: (records at: 42)) removeAt: 5) setAt: 3 value: (records at: 43).
      coll := ((((coll removeAt: 9) setAt: 21 value: (records at: 44)) setAt: 30 value: (records at: 45)) setAt: 31 value: (records at: 46))]
    ifFalse: [
      coll := (((coll add: (records at: 41)) add: (records at: 41)) add: (records at: 42)) remove: (records at: 41).
      1 to: 3 do: [:i | coll := coll remove: (records at: i)].
      coll := ((coll add: (records at: 43)) add: (records at: 44)) add: (records at: 45)].
  coll := coll addIndex: (PBVectorIndex name: 'tmp' keySpec: (PBKeySpec path: 'vec') dim: 3 metric: 'cosine' backend: 'hnsw' params: nil).
  coll := (coll removeIndex: 'late') addIndex: (PBVectorIndex name: 'late' keySpec: (PBKeySpec path: 'vec') dim: 3
    metric: 'l2' backend: 'exact' params: nil).
  coll removeIndex: 'tmp'].

mode = 'replay' ifTrue: [
  space := PBObjectSpace storage: (PBFileStorage path: dir , '/main').
  tx := (space openDatabase: 'vec') newTransaction.
  records := OrderedCollection new.
  (tx getRootObject: 'records') do: [:e | records addLast: e].
  records := records asArray.
  ops := tx getRootObject: 'ops'.
  "py_vector_replay.py indexes()."
  defs := {
    PBVectorIndex name: 'exact' keySpec: (PBKeySpec path: 'vec') dim: 3 metric: 'cosine' backend: 'exact' params: nil.
    PBVectorIndex name: 'hnsw' keySpec: (PBKeySpec path: 'vec') dim: 3 metric: 'ip' backend: 'hnsw'
      params: (Dictionary new at: 'M' put: 4; at: 'seed' put: 3; yourself).
    PBVectorIndex name: 'ivf' keySpec: (PBKeySpec path: 'vec') dim: 3 metric: 'l2' backend: 'ivf_flat'
      params: (Dictionary new at: 'nlist' put: 3; at: 'retrain_growth' put: 1.5; at: 'train_iters' put: 3; at: 'seed' put: 5; yourself).
    PBVectorIndex name: 'ivf4' keySpec: (PBKeySpec path: 'vec') dim: 3 metric: 'cosine' backend: 'ivf_flat'
      params: (Dictionary new at: 'nlist' put: 4; at: 'nprobe' put: 2; at: 'seed' put: 11; yourself) }.
  results := OrderedCollection new.
  kinds do: [:kind |
    | coll |
    coll := (classes at: kind) new.
    (ops at: kind) do: [:op | coll := apply value: kind value: coll value: op].
    coll validate.
    results addLast: kind -> coll.
    tx setRootObject: 'out_' , kind value: coll].
  currents := Dictionary new.
  results do: [:each | currents at: each key put: each value].
  #('dict' 'hash' 'bag') do: [:kind | | merged |
    merged := (mergeLog value: kind) rebaseOnto: (currents at: kind).
    merged validate.
    results addLast: 'merged_' , kind -> merged.
    tx setRootObject: 'merged_' , kind value: merged].
  print value: results.
  tx commit.
  space close.
  space := PBObjectSpace storage: (PBFileStorage path: dir , '/legacy').
  tx := (space openDatabase: 'db') newTransaction.
  old := tx getRootObject: 'vectors'.
  before := old getIndex: 'near'.
  before hasMemberTokens ifTrue: [Error signal: 'the format-3 vector index reads as current'].
  blind := old extend: #().
  (blind getIndex: 'near') == before ifFalse: [Error signal: 'a blind change rebuilt the format-3 vector index'].
  changed := old appendLast: (old getAt: 0).
  (changed getIndex: 'near') hasMemberTokens ifFalse: [Error signal: 'the first change did not rebuild the format-3 vector index'].
  changed validate.
  print value: { 'legacy_vectors' -> changed }.
  tx setRootObject: 'vectors' value: changed.
  tx commit.
  space close.
  'end' displayNl.
  Smalltalk exit: 0].

"--- both directions (py_vector_replay.py write, change, verify) ---"

"py_vector_replay.py bd_vec: the key of record i."
vec := [:i |
  i \\ 7 = 3
    ifTrue: [i odd ifTrue: [tup value: { i asFloat. 1.0 }] ifFalse: ['none']]
    ifFalse: [
      i \\ 3 = 0
        ifTrue: [tup value: { i \\ 5. (i * 3) \\ 7 - 3. 1 }]
        ifFalse: [
          i \\ 3 = 1
            ifTrue: [tup value: { i asFloat / 8.0. 1.0 - (i asFloat / 16.0). (i \\ 4) * 0.5 }]
            ifFalse: [tup value: {
              Decimal fromString: (i \\ 4 = 0
                ifTrue: [(i // 4) printString]
                ifFalse: [(i // 4) printString , '.' , (#('25' '5' '75') at: i \\ 4)]).
              0.5. -1.0 }]]]].
record := [:i | PBObject withAll: { 'n' -> i. 'vec' -> (vec value: i) }].
bdIndexes := [{
  PBVectorIndex name: 'exact' keySpec: (PBKeySpec path: 'vec') dim: 3 metric: 'cosine' backend: 'exact' params: nil.
  PBVectorIndex name: 'hnsw' keySpec: (PBKeySpec path: 'vec') dim: 3 metric: 'l2' backend: 'hnsw' params: nil.
  PBVectorIndex name: 'ivf' keySpec: (PBKeySpec path: 'vec') dim: 3 metric: 'l2' backend: 'ivf_flat'
    params: (Dictionary new at: 'nlist' put: 4; at: 'retrain_growth' put: 1.5; at: 'train_iters' put: 4; at: 'seed' put: 9; yourself) }].
"py_vector_replay.py bd_build."
bdBuild := [:kind :someRecords | | coll |
  coll := (classes at: kind) new.
  bdIndexes value do: [:index | coll := coll addIndex: index].
  someRecords doWithIndex: [:r :n | | i |
    i := n - 1.
    kind = 'list'
      ifTrue: [coll := i odd ifTrue: [coll appendLast: r] ifFalse: [coll appendFirst: r]]
      ifFalse: [
        (kind = 'dict' or: [kind = 'hash'])
          ifTrue: [coll := coll setAt: i value: r]
          ifFalse: [coll := coll add: r]]].
  coll].
"py_vector_replay.py bd_changes (records 0-based there, 1-based here)."
bdChanges := [:kind :aColl :someRecords :someExtra | | coll r e |
  coll := aColl.
  r := [:k | someRecords at: k + 1].
  e := [:k | someExtra at: k + 1].
  kind = 'list' ifTrue: [
    coll := ((coll insertAt: 2 value: (e value: 0)) appendFirst: (e value: 1)) appendLast: (r value: 35).
    coll := ((coll setAt: 4 value: (r value: 36)) removeAt: 0) extend: { r value: 37. e value: 2. r value: 3 }.
    coll := coll sliceFrom: 1 to: coll count.
    coll := coll head: coll count - 1.
    coll := (coll tail: 1) appendLast: (e value: 3)].
  (kind = 'dict' or: [kind = 'hash']) ifTrue: [
    coll := (((coll setAt: 100 value: (e value: 0)) setAt: 3 value: (e value: 1)) removeAt: 4) removeAt: 999.
    coll := ((coll setAt: 101 value: (r value: 38)) setAt: 102 value: (e value: 2)) setAt: 103 value: (e value: 3)].
  kind = 'set' ifTrue: [ | listed |
    coll := ((coll add: (e value: 0)) remove: (r value: 2)) union: { e value: 1. r value: 36 }.
    listed := OrderedCollection new.
    coll do: [:each | listed addLast: each].
    coll := ((coll intersection: (listed asArray copyFrom: 1 to: listed size - 2) , { e value: 2 })
      difference: { r value: 5 }) add: (e value: 3)].
  kind = 'bag' ifTrue: [
    coll := (((((coll add: (e value: 0)) add: (r value: 1)) remove: (r value: 2)) add: (e value: 1)) add: (e value: 2)) add: (e value: 3)].
  (coll addIndex: (PBVectorIndex name: 'added' keySpec: (PBKeySpec path: 'vec') dim: 3 metric: 'l2' backend: 'exact' params: nil))
    removeIndex: 'hnsw'].

mode = 'write' ifTrue: [
  space := PBObjectSpace storage: (PBFileStorage path: dir).
  tx := (space newDatabase: 'bd') newTransaction.
  records := (0 to: 39) collect: [:i | record value: i].
  tx setRootObject: 'records' value: (PBList new extend: records).
  kinds do: [:kind | tx setRootObject: kind value: (bdBuild value: kind value: (records copyFrom: 1 to: 30))].
  tx commit.
  space close.
  Smalltalk exit: 0].

mode = 'change' ifTrue: [
  space := PBObjectSpace storage: (PBFileStorage path: dir).
  db := space openDatabase: 'bd'.
  tx := db newTransaction.
  records := OrderedCollection new.
  (tx getRootObject: 'records') do: [:each | records addLast: each].
  records := records asArray.
  extra := (0 to: 3) collect: [:i | record value: 100 + i].
  kinds do: [:kind | tx setRootObject: kind value: (bdChanges value: kind value: (tx getRootObject: kind) value: records value: extra)].
  tx commit.
  a := db newTransaction.
  b := db newTransaction.
  a setRootObject: 'dict' value: ((a newDictionary setAt: 200 value: (record value: 200)) setAt: 201 value: (record value: 201)).
  a setRootObject: 'bag' value: ((a newCountedSet add: (record value: 202)) add: (records at: 11)).
  b setRootObject: 'dict' value: ((b newDictionary setAt: 210 value: (record value: 210)) removeAt: 100).
  b setRootObject: 'bag' value: ((b newCountedSet add: (record value: 211)) remove: (records at: 12)).
  b commit.
  a commit.
  space close.
  Smalltalk exit: 0].

mode = 'verify' ifTrue: [
  space := PBObjectSpace storage: (PBFileStorage path: dir).
  tx := (space openDatabase: 'bd') newTransaction.
  kinds do: [:kind | | coll line |
    coll := tx getRootObject: kind.
    coll validate.
    line := WriteStream on: String new.
    line nextPutAll: kind , ' count=' , coll count printString , ' indexes='.
    coll indexNames doWithIndex: [:name :i | i > 1 ifTrue: [line nextPutAll: ',']. line nextPutAll: name].
    coll indexNames do: [:name | | index |
      index := coll getIndex: name.
      line nextPutAll: ' ' , name , ':members=' , index memberCount printString , ',invalid=' , index invalidCount printString].
    line contents displayNl].
  tx abort.
  space close.
  Smalltalk exit: 0].
