"_st_vector_index.st: protoBaseST's side of tests/interop/vector_index_identical.sh (vectors phase
 V3). A helper: the runner never runs files whose name starts with _.

 Usage: protost _st_vector_index.st <directory>

 Reads the space tests/interop/py_vector_index.py made (database 'vec': the element sets 'recs',
 'vals' and 'big', and the operation sequences and invalid-tree histories 'ops'), builds the same
 vector indexes, replays the same withAdded:, withRemoved: and withReplaced:with: sequences and
 the two histories, and prints them in the dump format py_vector_index.py documents: 'index
 <label>', then one line per atom reached from the index, breadth first in the order the encoder
 meets the references, '<number> <type name> <hex>', a saved atom written as its own pointer, an
 unsaved one as the pointer (fixed segment, its number). Last line 'end'."
Import from: 'protobase'.

| dir space tx sets ops specs kinds segment dump show params |
dir := Smalltalk arguments first.
segment := ByteArray fromHex: '0123456789abcdef0123456789abcdef'.
space := PBObjectSpace storage: (PBFileStorage path: dir).
tx := (space openDatabase: 'vec') history first.
tx := (space openDatabase: 'vec') snapshotAt: tx.
sets := Dictionary new.
#('recs' 'vals' 'big') do: [:name | | out |
  out := OrderedCollection new.
  (tx getRootObject: name) do: [:e | out addLast: e].
  sets at: name put: out asArray].
ops := tx getRootObject: 'ops'.
specs := { 'recs' -> 'path vec'. 'vals' -> 'element'. 'big' -> 'path vec' }.
"{ label. metric. backend. params }, py_vector_index.py's KINDS."
params := [:assocs | | d | d := Dictionary new. assocs do: [:a | d at: a key put: a value]. d].
kinds := { { 'exact-l2'. 'l2'. 'exact'. params value: #() }.
  { 'exact-cosine-nonumpy'. 'cosine'. 'exact'. params value: { 'numpy' -> false } }.
  { 'hnsw-ip'. 'ip'. 'hnsw'. params value: { 'M' -> 8. 'seed' -> 3 } }.
  { 'hnsw-cosine'. 'cosine'. 'hnsw'. params value: #() } }.
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
show := [:label :index | ('index ' , label) displayNl. dump value: index].
kinds do: [:kind |
  specs do: [:pair |
    | elements seq empty index label |
    elements := sets at: pair key.
    seq := ops at: pair key , '/' , pair value.
    empty := PBVectorIndex name: 'vi'
      keySpec: (pair value = 'element' ifTrue: [PBKeySpec element] ifFalse: [PBKeySpec path: 'vec'])
      dim: 3 metric: (kind at: 2) backend: (kind at: 3) params: (kind at: 4).
    label := (kind at: 1) , ' ' , pair key , ' ' , pair value.
    show value: label , ' build' value: (empty build: elements).
    index := empty build: (elements copyFrom: 1 to: elements size // 2).
    seq do: [:op | | i j |
      i := (op at: 2) + 1. j := (op at: 3) + 1.
      (op at: 1) = 0 ifTrue: [index := index withAdded: (elements at: i)].
      (op at: 1) = 1 ifTrue: [index := index withRemoved: (elements at: i)].
      (op at: 1) = 2 ifTrue: [index := index withReplaced: (elements at: i) with: (elements at: j)]].
    show value: label , ' hooks' value: index].
  #('built with invalid' 'built without invalid') with: (ops at: 'histories') asArray do: [:name :history |
    | recs empty |
    recs := sets at: 'recs'.
    empty := PBVectorIndex name: 'vi' keySpec: (PBKeySpec path: 'vec') dim: 3 metric: (kind at: 2) backend: (kind at: 3)
      params: (kind at: 4).
    show value: (kind at: 1) , ' history ' , name
      value: ((empty build: ((history at: 1) asArray collect: [:i | recs at: i + 1])) withAdded: (recs at: (history at: 2) + 1))]].
space close.
'end' displayNl.
