"_st_vector_index.st: protoBaseST's side of tests/interop/vector_index_identical.sh (vectors phases
 V3 and V4). A helper: the runner never runs files whose name starts with _.

 Usage: protost _st_vector_index.st <directory>

 Reads the space tests/interop/py_vector_index.py made (database 'vec': the element sets 'recs',
 'vals', 'big', 'd1' and 'd16', and the operation sequences and invalid-tree histories 'ops'),
 builds the same vector indexes, replays the same withAdded:, withRemoved: and withReplaced:with:
 sequences, the three histories and the ivf_flat growth histories (the index after each operation
 that trained or retrained it, and at its end), and prints them in the dump format py_vector_index.py
 documents: 'index <label>', then one line per atom reached from the index, breadth first in the
 order the encoder meets the references, '<number> <type name> <hex>', a saved atom written as its
 own pointer, an unsaved one as the pointer (fixed segment, its number). Then the refusals, as
 py_vector_index.py refusals prints them ('refusal <label>: <class>: <text>', or ': none'), the
 same definitions and tampered indexes built here. Last line 'end'."
Import from: 'protobase'.

| dir space tx sets ops specs kinds segment dump show params all refused tup empty values index store members total mk
  vkey entry put one abc |
dir := Smalltalk arguments first.
segment := ByteArray fromHex: '0123456789abcdef0123456789abcdef'.
space := PBObjectSpace storage: (PBFileStorage path: dir).
tx := (space openDatabase: 'vec') history first.
tx := (space openDatabase: 'vec') snapshotAt: tx.
sets := Dictionary new.
#('recs' 'vals' 'big' 'd1' 'd16') do: [:name | | out |
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
  { 'hnsw-cosine'. 'cosine'. 'hnsw'. params value: #() }.
  { 'ivf-l2'. 'l2'. 'ivf_flat'. params value: { 'nlist' -> 4. 'nprobe' -> 2. 'train_iters' -> 4. 'seed' -> 11 } }.
  { 'ivf-cosine'. 'cosine'. 'ivf_flat'. params value: { 'nlist' -> 6. 'retrain_growth' -> 1.5 } } }.
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
"{ label. dim. metric. backend. params. set. key spec }: KINDS over SPECS, then DIM_KINDS."
all := OrderedCollection new.
kinds do: [:kind | specs do: [:pair |
  all addLast: { kind at: 1. 3. kind at: 2. kind at: 3. kind at: 4. pair key. pair value }]].
all addAll: {
  { 'd1-cosine-exact'. 1. 'cosine'. 'exact'. params value: #(). 'd1'. 'element' }.
  { 'd1-l2-hnsw'. 1. 'l2'. 'hnsw'. params value: { 'M' -> 2 }. 'd1'. 'element' }.
  { 'd1-ip-exact'. 1. 'ip'. 'exact'. params value: { 'numpy' -> false }. 'd1'. 'element' }.
  { 'd16-cosine-hnsw'. 16. 'cosine'. 'hnsw'. params value: { 'M' -> 4. 'seed' -> 9 }. 'd16'. 'path vec' }.
  { 'd16-l2-exact'. 16. 'l2'. 'exact'. params value: #(). 'd16'. 'path vec' }.
  { 'd16-ip-hnsw'. 16. 'ip'. 'hnsw'. params value: #(). 'd16'. 'path vec' } }.
all do: [:kind |
  | elements seq empty index label |
  elements := sets at: (kind at: 6).
  seq := ops at: (kind at: 6) , '/' , (kind at: 7).
  empty := PBVectorIndex name: 'vi'
    keySpec: ((kind at: 7) = 'element' ifTrue: [PBKeySpec element] ifFalse: [PBKeySpec path: 'vec'])
    dim: (kind at: 2) metric: (kind at: 3) backend: (kind at: 4) params: (kind at: 5).
  label := (kind at: 1) , ' ' , (kind at: 6) , ' ' , (kind at: 7).
  show value: label , ' build' value: (empty build: elements).
  index := empty build: (elements copyFrom: 1 to: elements size // 2).
  seq do: [:op | | i j |
    i := (op at: 2) + 1. j := (op at: 3) + 1.
    (op at: 1) = 0 ifTrue: [index := index withAdded: (elements at: i)].
    (op at: 1) = 1 ifTrue: [index := index withRemoved: (elements at: i)].
    (op at: 1) = 2 ifTrue: [index := index withReplaced: (elements at: i) with: (elements at: j)]].
  show value: label , ' hooks' value: index].
"The invalid-tree histories: { built. removed. added } indices of 'recs'."
kinds do: [:kind |
  #('built with invalid' 'built without invalid' 'built, emptied, regrown') with: (ops at: 'histories') asArray do: [:name :history |
    | recs index |
    recs := sets at: 'recs'.
    index := (PBVectorIndex name: 'vi' keySpec: (PBKeySpec path: 'vec') dim: 3 metric: (kind at: 2) backend: (kind at: 3)
      params: (kind at: 4)) build: ((history at: 1) asArray collect: [:i | recs at: i + 1]).
    (history at: 2) do: [:i | index := index withRemoved: (recs at: i + 1)].
    show value: (kind at: 1) , ' history ' , name value: (index withAdded: (recs at: (history at: 3) + 1))]].
"The ivf_flat growth histories, py_vector_index.py's IVF_GROWTH: { label. dim. metric. params. set.
 key spec }, each from an empty index."
{ { 'ivf-l2 growth big'. 3. 'l2'. params value: { 'nlist' -> 4. 'nprobe' -> 2. 'train_iters' -> 3. 'seed' -> 5. 'retrain_growth' -> 1.5 }.
    'big'. 'path vec' }.
  { 'ivf-cosine growth recs'. 3. 'cosine'. params value: { 'nlist' -> 3. 'seed' -> (2 raisedTo: 40). 'retrain_growth' -> 2 }.
    'recs'. 'path vec' }.
  { 'ivf-ip growth d16'. 16. 'ip'. params value: { 'nlist' -> 5. 'train_iters' -> 2. 'seed' -> 7. 'retrain_growth' -> 1.25 }.
    'd16'. 'path vec' }.
  { 'ivf-l2 growth vals'. 3. 'l2'. params value: { 'nlist' -> 2. 'retrain_growth' -> 3.0 }. 'vals'. 'element' } } do: [:growth |
  | elements index |
  elements := sets at: (growth at: 5).
  index := PBVectorIndex name: 'vi'
    keySpec: ((growth at: 6) = 'element' ifTrue: [PBKeySpec element] ifFalse: [PBKeySpec path: 'vec'])
    dim: (growth at: 2) metric: (growth at: 3) backend: 'ivf_flat' params: (growth at: 4).
  (ops at: (growth at: 1)) asArray doWithIndex: [:op :n | | before |
    before := index trainedSize.
    index := (op at: 1) = 0
      ifTrue: [index withAdded: (elements at: (op at: 2) + 1)]
      ifFalse: [index withRemoved: (elements at: (op at: 2) + 1)].
    index trainedSize = before ifFalse: [
      show value: (growth at: 1) , ' op ' , n printString , ' trained at ' , index trainedSize printString value: index]].
  show value: (growth at: 1) , ' end' value: index].
"The refusals, as py_vector_index.py refusals prints them."
refused := [:label :block | | text |
  text := [block value. 'none'] on: PBDBError do: [:e |
    e return: ((e isKindOf: PBValidationError) ifTrue: ['validation'] ifFalse: [
      (e isKindOf: PBCorruptionError) ifTrue: ['corruption'] ifFalse: [
        (e isKindOf: PBNotSupportedError) ifTrue: ['not supported'] ifFalse: [e class name]]]) , ': ' , e messageText].
  ('refusal ' , label , ': ' , text) displayNl].
{ { 0. 'cosine'. 'exact'. #() }. { true. 'cosine'. 'exact'. #() }. { 2.0. 'cosine'. 'exact'. #() }.
  { '3'. 'cosine'. 'exact'. #() }. { nil. 'cosine'. 'exact'. #() }. { 3. 'dot'. 'exact'. #() }.
  { 3. nil. 'exact'. #() }. { 3. 3. 'exact'. #() }. { 3. 'l2'. 'annoy'. #() }. { 3. 'l2'. nil. #() }.
  { 3. 'l2'. 'exact'. { 'numpy' -> 1 } }. { 3. 'l2'. 'exact'. { 'numpy' -> nil } }. { 3. 'l2'. 'exact'. { 'nlist' -> 3 } }.
  { 3. 'l2'. 'hnsw'. { 'M' -> 1 } }. { 3. 'l2'. 'hnsw'. { 'M' -> true } }. { 3. 'l2'. 'hnsw'. { 'seed' -> -1 } }.
  { 3. 'l2'. 'hnsw'. { 'seed' -> 1.5 } }. { 3. 'l2'. 'hnsw'. { 'ef_search' -> 0 } }.
  { 3. 'l2'. 'hnsw'. { 'zz' -> 1. 'aa' -> 2 } }. { 3. 'l2'. 'ivf_flat'. { 'nlist' -> 0 } }.
  { 3. 'l2'. 'ivf_flat'. { 'nlist' -> 4. 'nprobe' -> 5 } }. { 3. 'l2'. 'ivf_flat'. { 'retrain_growth' -> (Decimal fromString: '2') } }.
  { 3. 'l2'. 'ivf_flat'. { 'retrain_growth' -> '2' } }. { 3. 'l2'. 'ivf_flat'. { 'retrain_growth' -> Float infinity } }.
  { 3. 'l2'. 'ivf_flat'. { 'retrain_growth' -> true } }. { 3. 'l2'. 'ivf_flat'. { 'retrain_growth' -> 1 } }.
  { 3. 'l2'. 'ivf_flat'. { 'retrain_growth' -> (10 raisedTo: 400) } }. { 3. 'l2'. 'ivf_flat'. { 'train_iters' -> nil } } }
  doWithIndex: [:d :n |
    refused value: 'definition ' , n printString value: [PBVectorIndex name: 'vi' keySpec: PBKeySpec element
      dim: (d at: 1) metric: (d at: 2) backend: (d at: 3) params: (params value: (d at: 4))]].
tup := [:anArray | PBTuple withAll: anArray].
empty := PBVectorIndex name: 'vi' keySpec: PBKeySpec element dim: 3 metric: 'l2' backend: 'exact' params: nil.
refused value: 'not held, a vector' value: [empty withRemoved: (tup value: #(1.0 0.5 0.0))].
refused value: 'not held, an invalid key' value: [empty withRemoved: 'abc'].
values := { tup value: #(1.0 0.0 0.0). tup value: #(0.0 1.0 0.0). tup value: #(1 2 3). nil. 'abc'. tup value: #(1.0 2.0) }.
index := empty build: values.
store := index store.
members := index invalid at: 1.
total := index invalid at: 2.
mk := [:v | PBMemberKeys memberKeyOf: v].
vkey := tup value: { 0. mk value: (values at: 1) }.
entry := (index storeEntries detect: [:a | a key = vkey]) value.
put := [:tree :k :v | (PBAvl keyPut: tree key: k value: v nodeClass: PBKeyNode) at: 1].
one := empty build: { values at: 1 }.
abc := empty build: #('abc').
{ 'invalid None' -> (index _with: { 'invalid' -> nil }).
  'invalid triple' -> (index _with: { 'invalid' -> (tup value: { nil. 0. 0 }) }).
  'invalid list' -> (index _with: { 'invalid' -> (PBFrozenList withAll: { nil. 0 }) }).
  'invalid entry single' -> (index _with: { 'invalid' -> (tup value: { put value: members value: (mk value: 'abc') value: (tup value: #('abc')). total }) }).
  'invalid count True' -> (index _with: { 'invalid' -> (tup value: { put value: members value: (mk value: 'abc') value: (tup value: { 'abc'. true }). total }) }).
  'invalid count 0' -> (index _with: { 'invalid' -> (tup value: { put value: members value: (mk value: 'abc') value: (tup value: #('abc' 0)). total }) }).
  'invalid wrong key' -> (index _with: { 'invalid' -> (tup value: {
    put value: ((PBAvl keyRemove: members key: (mk value: 'abc')) at: 1) value: (mk value: 'abd') value: (tup value: #('abc' 1)). total }) }).
  'invalid valid vector' -> (index _with: { 'invalid' -> (tup value: { put value: members value: (mk value: (values at: 1))
    value: (tup value: { values at: 1. 1 }). total + 1 }). 'total_count' -> (index totalCount + 1) }).
  'invalid total 5' -> (index _with: { 'invalid' -> (tup value: { members. 5 }) }).
  'invalid total True' -> (abc _with: { 'invalid' -> (tup value: { abc invalid at: 1. true }) }).
  'store key str' -> (index _with: { 'store' -> (put value: store value: 'x' value: entry) }).
  'store key True' -> (index _with: { 'store' -> (put value: store value: (tup value: { true. vkey at: 2 }) value: entry) }).
  'store key triple' -> (index _with: { 'store' -> (put value: store value: (tup value: { 0. vkey at: 2. 0 }) value: entry) }).
  'store entry pair' -> (index _with: { 'store' -> (put value: store value: vkey value: (tup value: { entry at: 1. entry at: 2 })) }).
  'store count True' -> (index _with: { 'store' -> (put value: store value: vkey value: (tup value: { entry at: 1. true. entry at: 3 })) }).
  'store count 1.0' -> (index _with: { 'store' -> (put value: store value: vkey value: (tup value: { entry at: 1. 1.0. entry at: 3 })) }).
  'store wrong key' -> (index _with: { 'store' -> (put value: store value: (tup value: { 0. mk value: (values at: 2) }) value: entry) }).
  'store vector' -> (index _with: { 'store' -> (put value: store value: vkey value: (tup value: { entry at: 1. 1. tup value: #(9.0 9.0 9.0) })) }).
  'store vector list' -> (index _with: { 'store' -> (put value: store value: vkey value: (tup value: { entry at: 1. 1. PBFrozenList withAll: #(1.0 0.0 0.0) })) }).
  'store vector True' -> (index _with: { 'store' -> (put value: store value: vkey value: (tup value: { entry at: 1. 1. tup value: { true. 0. 0 } })) }).
  'store vector None' -> (index _with: { 'store' -> (put value: store value: (tup value: { 0. mk value: 'abc' }) value: (tup value: { 'abc'. 1. nil })) }).
  'trained_size True' -> (index _with: { 'trained_size' -> true }).
  'centroids list' -> (index _with: { 'centroids' -> (PBFrozenList withAll: #()) }).
  'centroids on exact' -> (index _with: { 'centroids' -> (tup value: { tup value: #(1.0 0.0 0.0) }). 'trained_size' -> 1 }).
  'total_count 7' -> (index _with: { 'total_count' -> 7 }).
  'total_count 6.0' -> (index _with: { 'total_count' -> 6.0 }).
  'total_count Decimal' -> (index _with: { 'total_count' -> (Decimal fromString: '6') }).
  'total_count False' -> (one _with: { 'total_count' -> false }).
  'total_count True' -> (one _with: { 'total_count' -> true }) } do: [:case | | elements |
    elements := (#('total_count False' 'total_count True') includes: case key)
      ifTrue: [{ values at: 1 }]
      ifFalse: [case key = 'invalid total True' ifTrue: [#('abc')] ifFalse: [values]].
    refused value: 'validate ' , case key value: [case value validate: elements]].
"The tampered ivf_flat index, as py_vector_index.py refusals tampers it."
index := (PBVectorIndex name: 'vi' keySpec: PBKeySpec element dim: 3 metric: 'l2' backend: 'ivf_flat'
  params: (params value: { 'nlist' -> 2. 'nprobe' -> 1 })) build: values.
store := index store.
entry := index storeEntries first.
vkey := entry key.
entry := entry value.
{ 'ivf' -> index.
  'ivf centroid removed' -> (index _with: { 'centroids' -> (tup value: { index centroids at: 1 }) }).
  'ivf centroid added' -> (index _with: { 'centroids' -> (tup value: { index centroids at: 1. index centroids at: 2. index centroids at: 2 }) }).
  'ivf centroid list' -> (index _with: { 'centroids' -> (tup value: { PBFrozenList withAll: (index centroids at: 1) asArray. index centroids at: 2 }) }).
  'ivf centroid ints' -> (index _with: { 'centroids' -> (tup value: { tup value: #(1 0 0). index centroids at: 2 }) }).
  'ivf centroid nan' -> (index _with: { 'centroids' -> (tup value: { tup value: { Float nan. 0.0. 0.0 }. index centroids at: 2 }) }).
  'ivf centroid short' -> (index _with: { 'centroids' -> (tup value: { tup value: #(1.0 0.0). index centroids at: 2 }) }).
  'ivf centroid True' -> (index _with: { 'centroids' -> (tup value: { tup value: { true. 0.0. 0.0 }. index centroids at: 2 }) }).
  'ivf trained_size 0' -> (index _with: { 'trained_size' -> 0 }).
  'ivf untrained with trained_size' -> (index _with: { 'centroids' -> (tup value: #()). 'trained_size' -> 3 }).
  'ivf untrained in list 0' -> (index _with: { 'centroids' -> (tup value: #()). 'trained_size' -> 0 }).
  'ivf in the other list' -> (index _with: { 'store' -> (put value: ((PBAvl keyRemove: store key: vkey) at: 1)
    value: (tup value: { 1 - (vkey at: 1). vkey at: 2 }) value: entry) }).
  'ivf in list -1' -> (index _with: { 'store' -> (put value: ((PBAvl keyRemove: store key: vkey) at: 1)
    value: (tup value: { -1. vkey at: 2 }) value: entry) }).
  'ivf swapped centroids' -> (index _with: { 'centroids' -> (tup value: { index centroids at: 2. index centroids at: 1 }) }) }
  do: [:case | refused value: 'validate ' , case key value: [case value validate: values]].
space close.
'end' displayNl.
