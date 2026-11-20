"vector_workload.st: the vector benchmarks (Addendum V, 5.5); bench/py_vector_workload.py runs
 the same work in proto_db (numpy and hnswlib blocked), bench/run_query.sh runs both, verifies the
 work and prints the timings.

 Usage: protost vector_workload.st <unit>     (QUERY_VECTOR_DATA names the data file of the unit's
                                               dim, written by bench/py_vector_data.py)

 VB0, the kernel (task V1, an input to ruling VQ2): n = 10^4 vectors of dim 8, 32 or 128 and one
 query, proto_db's clustered benchmark data (bench/py_vector_data.py). Units VB0:10000:d<dim>-<op>,
 each op timed alone over the n vectors after the data is read and, for naive and fsum, after
 the products q_i * v_i of every vector are computed (untimed):
   products   the dim products of each vector (the rest of an ip score, without its sum)
   naive      a plain left-to-right IEEE sum of each vector's products
   fsum       PBVectorMath fsum: of each vector's products (CPython's math.fsum)
   ip, l2, cosine   PBVectorMath score:query:vector: (proto_db's exact_score)
 so fsum against naive is the cost of correct rounding, and fsum against ip the share of an ip
 score spent in its sum. rows is n, queries 1, and the checksum the CRC-32 of the results'
 IEEE 754 binary64 big-endian bytes in vector order (a products result contributes its dim
 Floats in order): the runner refuses a run whose checksum differs from proto_db's, so every
 measured sum, score and product is proto_db's to the bit. Each unit prints a WORK and a TIME line
 (plan call IP10) and the last line is 'query_workload ok'. Nothing is asserted about time."
Import from: 'protobase'.

| unit parts id n plan dash dim op path data vectors q products t0 us results w checksum naive |
Smalltalk arguments size = 1 ifFalse: [Error signal: 'usage: protost vector_workload.st <unit>'].
unit := Smalltalk arguments first.
parts := unit substrings: ':'.
id := parts at: 1.
n := (parts at: 2) asNumber.
plan := parts at: 3.
dash := plan indexOf: $-.
dim := (plan copyFrom: 2 to: dash - 1) asNumber.
op := plan copyFrom: dash + 1 to: plan size.
(id = 'VB0' and: [(plan at: 1) = $d and: [#('products' 'naive' 'fsum' 'ip' 'l2' 'cosine') includes: op]])
  ifFalse: [Error signal: 'vector_workload: unknown unit ' , unit].
path := Smalltalk getenv: 'QUERY_VECTOR_DATA'.
path isNil ifTrue: [Error signal: 'vector_workload: QUERY_VECTOR_DATA names the data file'].
data := MessagePack decode: path asFileReference binaryContents.
((data at: 'n') = n and: [(data at: 'dim') = dim]) ifFalse: [
  Error signal: 'vector_workload: ' , path , ' holds another n or dim'].
vectors := (data at: 'vectors') collect: [:v | PBTuple withAll: v].
q := PBTuple withAll: (data at: 'query').
"A plain left-to-right IEEE sum from 0.0."
naive := [:terms | | s | s := 0.0. terms do: [:x | s := s + x]. s].
products := vectors collect: [:v | (1 to: dim) asArray collect: [:i | (q at: i) * (v at: i)]].
t0 := Time microsecondClockValue.
op = 'products' ifTrue: [results := vectors collect: [:v | (1 to: dim) asArray collect: [:i | (q at: i) * (v at: i)]]].
op = 'naive' ifTrue: [results := products collect: [:p | naive value: p]].
op = 'fsum' ifTrue: [results := products collect: [:p | PBVectorMath fsum: p]].
(#('ip' 'l2' 'cosine') includes: op) ifTrue: [
  results := vectors collect: [:v | PBVectorMath score: op query: q vector: v]].
us := Time microsecondClockValue - t0.
w := WriteStream on: ByteArray new.
results do: [:r |
  r isFloat
    ifTrue: [w nextPutFloat64: r bigEndian: true]
    ifFalse: [r do: [:x | w nextPutFloat64: x bigEndian: true]]].
checksum := w contents crc32.
('WORK id=' , id , ' impl=st size=' , n printString , ' rows=' , results size printString , ' queries=1 plan=' , plan
  , ' checksum=' , checksum printString) displayNl.
('TIME id=' , id , ' impl=st size=' , n printString , ' plan=' , plan , ' us=' , us printString) displayNl.
'query_workload ok' displayNl.
