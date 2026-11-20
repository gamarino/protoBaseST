"_st_index_build.st: protoBaseST's side of tests/interop/index_build_identical.sh (indexed
 queries, plan Task 3). A helper: the runner never runs files whose name starts with _.

 Usage: protost _st_index_build.st <directory>

 Reads the space tests/interop/py_index_build.py made (database 'idx': the element sets
 'values', 'records' and 'big', and the operation sequences 'ops'), builds the same indexes and
 replays the same withAdded:, withRemoved: and withReplaced:with: sequences, and prints them in
 the dump format py_index_build.py documents: 'index <label>', then one line per atom reached
 from the index, breadth first in the order the encoder meets the references, '<number> <type
 name> <hex>', a saved atom written as its own pointer, an unsaved one as the pointer (fixed
 segment, its number). Last line 'end'."
Import from: 'protobase'.

| dir space tx sets ops specs segment dump spec |
dir := Smalltalk arguments first.
segment := ByteArray fromHex: '0123456789abcdef0123456789abcdef'.
PBKeySpec registerExtractor: 'interop.index_build.w' block: [:e | (PBKeySpec path: 'w') extract: e] version: '1'.
space := PBObjectSpace storage: (PBFileStorage path: dir).
tx := (space openDatabase: 'idx') history first.
tx := (space openDatabase: 'idx') snapshotAt: tx.
sets := Dictionary new.
#('values' 'records' 'big') do: [:name | | out |
  out := OrderedCollection new.
  (tx getRootObject: name) do: [:e | out addLast: e].
  sets at: name put: out asArray].
ops := tx getRootObject: 'ops'.
specs := { 'values' -> 'element'. 'records' -> 'path v'. 'records' -> 'extractor'. 'big' -> 'path v' }.
spec := [:name |
  name = 'element' ifTrue: [PBKeySpec element] ifFalse: [
    name = 'path v' ifTrue: [PBKeySpec path: 'v'] ifFalse: [PBKeySpec extractor: 'interop.index_build.w']]].
"numbers: identityHash -> the Associations atom -> number of the atoms with that hash (protoST
 has no IdentityDictionary)."
dump := [:index | | numbers count queue numberOf |
  numbers := Dictionary new.
  count := 0.
  numberOf := [:atom | | bucket found |
    bucket := numbers at: atom identityHash ifAbsent: [numbers at: atom identityHash put: OrderedCollection new].
    found := bucket detect: [:each | each key == atom] ifNone: [nil].
    found isNil ifTrue: [
      found := atom -> count.
      count := count + 1.
      bucket addLast: found.
      atom == index ifFalse: [queue addLast: atom]].
    found value].
  queue := OrderedCollection new.
  numberOf value: index.
  queue addLast: index.
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
specs do: [:pair |
  | elements seq |
  elements := sets at: pair key.
  seq := ops at: pair key , '/' , pair value.
  { PBEqualityIndex. PBRangeIndex } do: [:kind |
    | empty index label |
    empty := kind name: 'idx' keySpec: (spec value: pair value).
    label := (kind name copyFrom: 3 to: kind name size) , ' ' , pair key , ' ' , pair value.
    ('index ' , label , ' build') displayNl.
    dump value: (empty build: elements).
    index := empty build: (elements copyFrom: 1 to: elements size // 2).
    seq do: [:op | | i j |
      i := (op at: 2) + 1. j := (op at: 3) + 1.
      (op at: 1) = 0 ifTrue: [index := index withAdded: (elements at: i)].
      (op at: 1) = 1 ifTrue: [index := index withRemoved: (elements at: i)].
      (op at: 1) = 2 ifTrue: [index := index withReplaced: (elements at: i) with: (elements at: j)]].
    ('index ' , label , ' hooks') displayNl.
    dump value: index]].
space close.
'end' displayNl.
