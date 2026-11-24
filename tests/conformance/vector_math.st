"EXPECT: vector math vectors ok"
"The vector math vectors (Addendum V, task V1, section 5.2): vectors-vector-math/cases.msgpack,
 written once by tests/conformance/fetch_vector_math_vectors.sh with proto_db at v2.0.0rc4 and its
 CPython, numpy and hnswlib blocked (tests/interop/py_vector_math_cases.py, whose docstring states
 every group, the inputs and the encoding). The file is checked against manifest.sha256 first.

 Every case of every group must agree bit for bit: a Float is compared by its IEEE 754 bytes, a
 tuple of Floats component by component, an Integer, a String and a count by =; a CPython or
 proto_db exception must be a PBValidationError carrying the same text (DV7), except where the
 port's interface answers nil in proto_db's place: floatOf: of an Integer beyond the Float range
 (CPython's OverflowError, which canonical_vector turns into 'not a vector'). The groups:
 float_of (floatOf:), canonical (canonicalVector:dim:), fsum (fsum:), sum_nonnegative
 (sumNonNegative:), score (score:query:vector:, then the same cases through scorerFor:query:
 three ways: a first score, a second score of the same scorer, PBTuple operands), score_floor (scoreFloor:threshold:), rank
 (rank:query:metric:k:threshold:), squares (raisedTo: 2 against libm pow, * against CPython's
 x * x; where CPython's ** raised OverflowError the pow answer is infinity, which _sum_nonnegative
 reads as the same distance), training_order (trainingOrderOf:: each vector's Integer equals its
 bytes read as one unsigned Integer, and sorting by it, ties by position, is CPython's stable sort),
 normalized (normalized:), getrandbits (PBPythonRandom bits:count:seed:), sample
 (sampleRange:count:seed:), kmeans (kmeans:nlist:iterations:seed:, proto_db's pure-Python path)
 and list_for (the best-scoring centroid under the assignment metric, cosine for cosine and l2
 otherwise, lowest number on ties: IvfFlatBackend.list_for, which PBVectorIvfFlat listFor:vector:
 ports; here it pins that the scores pick proto_db's list). Every group runs twice (task VP-adopt,
 Addendum V 2.2.4): with protoST's Float fsum primitives, which the floor (0.17.0) always has, and
 with the Smalltalk kernel forced (PBVectorMath _forceSmalltalkKernel:, a test-only switch), their
 oracle; both runs must agree with CPython. It
 prints the generator's CPython, libc and numpy lines, then per run its kernel and the number of
 cases per group, then 'vector math vectors ok'."
Import from: 'protobase'.

| dir manifest blob data meta fails counts hex num key res expect check floats group |
dir := 'vectors-vector-math'.
manifest := ((dir , '/manifest.sha256') asFileReference contents lines reject: [:line | line isEmpty])
  collect: [:line | { line copyFrom: 1 to: 64. line copyFrom: 67 to: line size }].
manifest do: [:entry |
  ((dir , '/' , (entry at: 2)) asFileReference binaryContents sha256 hex asLowercase) = (entry at: 1) ifFalse: [
    Error signal: dir , '/' , (entry at: 2) , ' does not match manifest.sha256']].
(manifest anySatisfy: [:entry | (entry at: 2) = 'cases.msgpack']) ifFalse: [Error signal: 'manifest.sha256 does not list cases.msgpack'].
blob := (dir , '/cases.msgpack') asFileReference binaryContents.
data := MessagePack decode: blob.
meta := data at: 'meta'.
('CPython ' , ((meta at: 'python') copyFrom: 1 to: ((meta at: 'python') indexOf: $ ) - 1) , '; libc ' , (meta at: 'libc') , '; numpy: ' , (meta at: 'numpy')
  , '; hnswlib: ' , (meta at: 'hnswlib') , '; proto_db ' , ((meta at: 'proto_db') copyFrom: 1 to: 7)) displayNl.
fails := OrderedCollection new.
counts := OrderedCollection new.

"The hex of a Float's bytes."
hex := [:aFloat | | w | w := WriteStream on: ByteArray new. w nextPutFloat64: aFloat bigEndian: true. w contents hex asLowercase].
"A tagged number or key (py_vector_math_cases.py, 'Value encoding') as a protoBaseST value."
num := nil.
num := [:t | | tag |
  tag := t at: 1.
  tag = 'f' ifTrue: [(t at: 2) float64At: 1 bigEndian: true] ifFalse: [
  tag = 'i' ifTrue: [(t at: 2) asNumber] ifFalse: [
  tag = 'd' ifTrue: [Decimal fromString: (t at: 2)] ifFalse: [
  tag = 'b' ifTrue: [t at: 2] ifFalse: [
  tag = 's' ifTrue: [t at: 2] ifFalse: [
  tag = 'n' ifTrue: [nil] ifFalse: [
  tag = 't' ifTrue: [PBTuple withAll: ((t at: 2) collect: [:each | num value: each])] ifFalse: [
  tag = 'l' ifTrue: [PBFrozenList withAll: ((t at: 2) collect: [:each | num value: each])] ifFalse: [
  Error signal: 'unknown tag ' , tag printString]]]]]]]]].
floats := [:anArray | anArray collect: [:b | b float64At: 1 bigEndian: true]].
"A port result in the tagged result form, compared as text: ['f', hex], ['n'], ['v', hexes],
 ['e', text] (the exception class is not compared: CPython's becomes PBValidationError, DV7)."
res := [:aBlock |
  [ | r |
    r := aBlock value.
    r isNil ifTrue: ['n'] ifFalse: [
    r isFloat ifTrue: ['f ' , (hex value: r)] ifFalse: [
    'v ' , (' ' join: (r asArray collect: [:each | hex value: each]))]]]
    on: PBValidationError do: [:e | e return: 'e ' , e messageText]].
expect := [:t | | tag |
  tag := t at: 1.
  tag = 'n' ifTrue: ['n'] ifFalse: [
  tag = 'f' ifTrue: ['f ' , (t at: 2) hex asLowercase] ifFalse: [
  tag = 'v' ifTrue: ['v ' , (' ' join: ((t at: 2) collect: [:b | b hex asLowercase]))] ifFalse: [
  'e ' , (t at: 3)]]]].
check := nil.
group := [:name :aBlock | | cases |
  cases := data at: name.
  cases doWithIndex: [:case :i | aBlock value: case value: i].
  counts add: name , ' ' , cases size printString].
{ false. true } do: [:forced | | kernel |
PBVectorMath _forceSmalltalkKernel: forced.
kernel := PBVectorMath usesPrimitives
  ifTrue: ['the fsum primitives']
  ifFalse: ['the Smalltalk kernel (forced)'].
counts := OrderedCollection new.
check := [:aGroup :anIndex :got :wanted |
  got = wanted ifFalse: [fails add: kernel , ': ' , aGroup , ' #' , anIndex printString , ': expected ' , wanted printString , ', got ' , got printString]].

group value: 'float_of' value: [:case :i | | x wanted |
  x := num value: (case at: 1).
  wanted := expect value: (case at: 2).
  ((case at: 2) first = 'e' and: [((case at: 2) at: 2) = 'OverflowError']) ifTrue: [wanted := 'n'].
  check value: 'float_of' value: i value: (res value: [PBVectorMath floatOf: x]) value: wanted].
group value: 'canonical' value: [:case :i |
  check value: 'canonical' value: i
    value: (res value: [PBVectorMath canonicalVector: (num value: (case at: 2)) dim: (case at: 1)])
    value: (expect value: (case at: 3))].
group value: 'fsum' value: [:case :i |
  check value: 'fsum' value: i value: (res value: [PBVectorMath fsum: (floats value: (case at: 1))]) value: (expect value: (case at: 2))].
group value: 'sum_nonnegative' value: [:case :i |
  check value: 'sum_nonnegative' value: i
    value: (res value: [PBVectorMath sumNonNegative: (floats value: (case at: 1))]) value: (expect value: (case at: 2))].
group value: 'score' value: [:case :i |
  check value: 'score' value: i
    value: (res value: [PBVectorMath score: (case at: 1) query: (floats value: (case at: 2)) vector: (floats value: (case at: 3))])
    value: (expect value: (case at: 4))].
"The same score cases through scorerFor:query: (task V8, fix round 1), three ways: the first
 score of a fresh scorer, a second score of the same scorer (the cosine query norm reused), and a
 fresh scorer over PBTuple operands."
(data at: 'score') doWithIndex: [:case :i | | sc |
  sc := PBVectorMath scorerFor: (case at: 1) query: (floats value: (case at: 2)).
  check value: 'score (scorer, first)' value: i value: (res value: [sc value: (floats value: (case at: 3))]) value: (expect value: (case at: 4)).
  check value: 'score (scorer, norm reused)' value: i value: (res value: [sc value: (floats value: (case at: 3))]) value: (expect value: (case at: 4)).
  sc := PBVectorMath scorerFor: (case at: 1) query: (PBTuple withAll: (floats value: (case at: 2))).
  check value: 'score (scorer, PBTuple operands)' value: i
    value: (res value: [sc value: (PBTuple withAll: (floats value: (case at: 3)))]) value: (expect value: (case at: 4))].
counts add: 'score through scorerFor:query: ' , (data at: 'score') size printString , ' x 3'.
group value: 'score_floor' value: [:case :i |
  check value: 'score_floor' value: i
    value: (res value: [PBVectorMath scoreFloor: (case at: 1) threshold: (num value: (case at: 2))])
    value: (expect value: (case at: 3))].
group value: 'rank' value: [:case :i | | entries got |
  entries := (case at: 1) collect: [:e | {num value: (e at: 1). e at: 2. e at: 3. PBTuple withAll: (floats value: (e at: 4))}].
  got := PBVectorMath rank: entries query: (PBTuple withAll: (floats value: (case at: 2))) metric: (case at: 3)
    k: (case at: 4) threshold: (num value: (case at: 5)).
  check value: 'rank' value: i value: (got collect: [:pair | {pair at: 1. pair at: 2}]) value: ((case at: 6) collect: [:pair | {pair at: 1. pair at: 2}])].
group value: 'squares' value: [:case :i | | x |
  x := (case at: 1) float64At: 1 bigEndian: true.
  check value: 'squares' value: i
    value: {hex value: (x raisedTo: 2). hex value: x * x}
    value: {(case at: 2) hex asLowercase. (case at: 3) hex asLowercase}.
  ((case at: 4) and: [(x raisedTo: 2) ~= Float infinity]) ifTrue: [
    fails add: 'squares #' , i printString , ': CPython''s ** overflowed but raisedTo: 2 is not infinity']].
group value: 'training_order' value: [:case :i | | vs keys order |
  vs := (case at: 1) collect: [:v | floats value: v].
  keys := vs collect: [:v | PBVectorMath trainingOrderOf: v].
  check value: 'training_order' value: i
    value: keys
    value: ((case at: 3) collect: [:b | b unsignedIntegerFrom: 1 to: b size bigEndian: true]).
  order := (1 to: vs size) asArray sort: [:a :b | (keys at: a) < (keys at: b) or: [(keys at: a) = (keys at: b) and: [a <= b]]].
  check value: 'training_order (sort)' value: i value: (order collect: [:p | p - 1]) value: (case at: 2) asArray].
group value: 'normalized' value: [:case :i |
  check value: 'normalized' value: i
    value: (res value: [PBVectorMath normalized: (floats value: (case at: 1))]) value: (expect value: (case at: 2))].
group value: 'getrandbits' value: [:case :i |
  check value: 'getrandbits' value: i
    value: (PBPythonRandom bits: (case at: 2) count: (case at: 3) size seed: (case at: 1) asNumber)
    value: ((case at: 3) collect: [:t | t asNumber])].
group value: 'sample' value: [:case :i |
  check value: 'sample' value: i
    value: (PBPythonRandom sampleRange: (case at: 2) asNumber count: (case at: 3) seed: (case at: 1) asNumber)
    value: ((case at: 4) collect: [:t | t asNumber])].
group value: 'kmeans' value: [:case :i | | got |
  got := PBVectorMath kmeans: ((case at: 1) collect: [:v | PBTuple withAll: (floats value: v)])
    nlist: (case at: 2) iterations: (case at: 3) seed: (case at: 4) asNumber.
  check value: 'kmeans' value: i
    value: (got collect: [:centroid | centroid asArray collect: [:x | hex value: x]])
    value: ((case at: 5) collect: [:centroid | centroid collect: [:b | b hex asLowercase]])].
group value: 'list_for' value: [:case :i | | metric v best bestScore |
  metric := (case at: 1) = 'cosine' ifTrue: ['cosine'] ifFalse: ['l2'].
  v := floats value: (case at: 3).
  best := 0. bestScore := nil.
  (case at: 2) doWithIndex: [:centroid :j | | s |
    s := PBVectorMath score: metric query: v vector: (floats value: centroid).
    (bestScore isNil or: [s > bestScore]) ifTrue: [best := j - 1. bestScore := s]].
  check value: 'list_for' value: i value: best value: (case at: 4)].
('kernel: ' , kernel , '; cases: ' , (', ' join: counts)) displayNl].
PBVectorMath _forceSmalltalkKernel: false.

fails do: [:each | ('FAIL ' , each) displayNl].
fails isEmpty ifFalse: [Error signal: fails size printString , ' vector math cases differ from proto_db'].
'vector math vectors ok' displayNl.
