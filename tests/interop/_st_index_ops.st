"_st_index_ops.st: protoBaseST's side of tests/interop/index_ops_identical.sh (indexed queries,
 plan Task 4a, spec 6.1.2). A helper: the runner never runs files whose name starts with _.

 Usage: protost _st_index_ops.st <directory>

 Reads a copy of the spaces tests/interop/py_index_replay.py made (<directory>/main: 'records' and
 the operation sequences 'ops'; <directory>/stale: the Dictionary 'stale' holding a format-3
 index), replays every sequence from a new collection of its kind (the element mutators and
 addIndex: / removeIndex:), then on 'stale' a blind removeAt: of an absent key (the stale index
 must stay the same object, still stale) and a setAt:value: (it must be rebuilt with format-4
 tokens). Each result must pass validate. Prints each result in the dump format
 py_index_replay.py documents ('collection <name>', then one line per atom reached from it that is
 not saved yet, breadth first in the order the encoder meets the references), and commits the
 results as py_index_replay.py does: the roots 'out_<kind>' and 'merged_<kind>' of main (the
 merges of plan Task 4b: py_index_replay.py merge_log rebased onto the replayed dictionary, hash
 dictionary and counted set) and the new 'stale'. Last line 'end'."
Import from: 'protobase'.

| dir space tx records ops defs segment dump kinds classes results apply stale before blind changed print
  currents mergeLog plant |
dir := Smalltalk arguments first.
segment := ByteArray fromHex: '0123456789abcdef0123456789abcdef'.
PBKeySpec registerExtractor: 'interop.index_ops.w' block: [:e | (PBKeySpec path: 'w') extract: e] version: '1'.
space := PBObjectSpace storage: (PBFileStorage path: dir , '/main').
tx := (space openDatabase: 'idx') newTransaction.
records := OrderedCollection new.
(tx getRootObject: 'records') do: [:e | records addLast: e].
records := records asArray.
ops := tx getRootObject: 'ops'.
defs := { PBEqualityIndex name: 'eq_v' path: 'v'. PBRangeIndex name: 'rg_w' keySpec: (PBKeySpec extractor: 'interop.index_ops.w').
  PBRangeIndex name: 'rg_v' path: 'v' }.
kinds := #('list' 'dict' 'hash' 'set' 'bag').
classes := Dictionary new.
classes at: 'list' put: PBList; at: 'dict' put: PBDictionary; at: 'hash' put: PBHashDictionary; at: 'set' put: PBSet;
  at: 'bag' put: PBCountedSet.

"aCollection after one op (py_index_replay.py apply; positions and keys as written, a record by
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

"The dump of py_index_replay.py: numbers: identityHash -> Associations atom -> number (protoST
 has no IdentityDictionary)."
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

"py_index_replay.py merge_log: the blind write of aKind rebased onto the replayed collection."
mergeLog := [:aKind | | coll |
  coll := (classes at: aKind) new addIndex: (PBEqualityIndex name: 'eq_m' path: 'v').
  (aKind = 'dict' or: [aKind = 'hash'])
    ifTrue: [
      coll := (((coll setAt: 3 value: (records at: 41)) setAt: 17 value: (records at: 42)) removeAt: 5) setAt: 3 value: (records at: 43).
      coll := (coll removeAt: 9) setAt: 21 value: (records at: 44)]
    ifFalse: [
      coll := (((coll add: (records at: 41)) add: (records at: 41)) add: (records at: 42)) remove: (records at: 41).
      1 to: 3 do: [:i | coll := coll remove: (records at: i)].
      coll := coll add: (records at: 43)].
  coll := coll addIndex: (PBRangeIndex name: 'tmp' path: 'w').
  coll := (coll removeIndex: 'eq_m') addIndex: (PBEqualityIndex name: 'eq_m' path: 'w').
  coll removeIndex: 'tmp'].
"INDEX_OPS_PLANT=index-first (index_ops_identical.sh's planted fault): the merge replays the index
 ops before the element ops, the wrong order, which the comparison with ProtoBase must catch."
plant := (Smalltalk getenv: 'INDEX_OPS_PLANT') = 'index-first'.

print := [:aResults | aResults do: [:each |
  ('collection ' , each key) displayNl.
  dump value: each value]].
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
#('dict' 'hash' 'bag') do: [:kind | | log merged |
  log := mergeLog value: kind.
  merged := plant
    ifTrue: [ | target |
      target := log _replayIndexOps: (log opLog asArray select: [:op | log class _isIndexOp: op])
        onto: (currents at: kind).
      log _netOps inject: target into: [:acc :op | log _replay: op onto: acc]]
    ifFalse: [log rebaseOnto: (currents at: kind)].
  merged validate.
  results addLast: 'merged_' , kind -> merged.
  tx setRootObject: 'merged_' , kind value: merged].
print value: results.
tx commit.
space close.
space := PBObjectSpace storage: (PBFileStorage path: dir , '/stale').
tx := (space openDatabase: 'idx') newTransaction.
stale := tx getRootObject: 'stale'.
before := stale getIndex: 'eq'.
before hasMemberTokens ifTrue: [Error signal: 'the stale index reads as current'].
blind := stale removeAt: 30.
(blind getIndex: 'eq') == before ifFalse: [Error signal: 'a blind write rebuilt the stale index'].
changed := blind setAt: 7 value: 'h'.
(changed getIndex: 'eq') hasMemberTokens ifFalse: [Error signal: 'the first change did not rebuild the stale index'].
changed validate.
print value: { 'stale' -> changed }.
tx setRootObject: 'stale' value: changed.
tx commit.
space close.
'end' displayNl.
