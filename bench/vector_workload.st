"vector_workload.st: the vector benchmarks (Addendum V, 5.5); bench/py_vector_workload.py runs
 the same work in proto_db (numpy and hnswlib blocked), bench/run_query.sh runs both, verifies the
 work and prints the timings.

 Usage: protost vector_workload.st <unit>     (QUERY_VECTOR_DATA names the data file of the unit's
                                               size and dim, written by bench/py_vector_data.py;
                                               VB3 and VB5 also need QUERY_DATA, a new directory
                                               for their spaces)

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
 (plan call IP10) and the last line is 'query_workload ok'. Nothing is asserted about time.

 VB3, maintenance on commit (task V5): units VB3:<n>:d8-<plan> for n 600 and 5000 and plan none,
 exact, ivf (bench/_vector_bench.st states the indexes; the IVF one retrains at every 3 % of
 growth). The data file holds n + QUERY_VB3_COMMITS (default 200) vectors of dim 8: a PBList of the
 first n with the plan's index is committed once, untimed; then the commits, timed together, each
 reading the list and committing it with the next vector appended (appendLast:), which maintains
 the index (an IVF retrain is k-means inside that commit). The read-back validates the list,
 requires an IVF index to have retrained past n (its trained size above n), and reports rows (the
 count), queries (the commits) and the checksum of VectorBench checksumOf: with the centroids,
 so the work verified includes every centroid proto_db computes.
 VB5, a blind write merged onto a vector-indexed current (task V5): units VB5:600:d8-exact and
 VB5:600:d8-ivf; a PBDictionary from i to vector i for the first 600, the plan's index added,
 committed once; then QUERY_VB5_COMMITS (default 120) commits, timed together, each committing a
 new dictionary holding key 600 + j alone (vector 600 + j), never reading the root, so the commit
 merges it onto the current version and the replayed add maintains its index (an IVF retrain in
 the commit's build). The read-back is VB3's, its checksum without the centroids (order-free, so
 bench/cluster_workload.st's vb5 profiles verify a three-member cluster against it).

 VB1, exact kNN (task V6): units VB1:<n>:d<dim>-<metric> for n 1000 and 10000, dim 8 and 32, metric
 cosine and l2, on the n vectors and the file's 10 query points. The records { 'i'. 'vec' }
 (VectorBench records:) are indexed by an exact index on 'vec' (build:, untimed); then two
 timings: '-first', the first query (k = 10, a PBVectorSearch); '-knn', the 10 queries (the
 first again among them). protoBaseST has no derived cache (DV4), so its first query costs what
 the others cost; proto_db's builds its flat snapshot (and, with numpy, its matrix) there. The
 WORK lines' checksums are the CRC-32 of the answers' positions, so the runner verifies every
 answer against proto_db's, in both of its modes (an exact answer does not depend on numpy).
 VB2, IVF (task V6): the unit VB2:10000:d32-ivf: the same records, an exact cosine index answering
 the 10 queries (the truth, untimed), then '-build', the ivf_flat index's build: with nlist =
 max(4, int(sqrt n)) = 100 (benchmarks/workloads/vector.py:118-119), its WORK checksum the
 CRC-32 of its centroids (DV3: equal to proto_db's reference mode); then, for nprobe 1, 4 and
 nlist, the built index with that nprobe (the same store and centroids: training does not read
 nprobe), one untimed warm query, and '-nprobe<p>', the 10 queries, with a RECALL line: the
 positions it shares with the truth, of 10 per query. A TIME line per timing, each a row of the
 runner's table."
Import from: 'protobase'.
Import from: '_vector_bench'.

| unit parts id n plan dash dim op path data vectors q products t0 us results w checksum naive emit
  commits dir space db tx coll count blind |
Smalltalk arguments size = 1 ifFalse: [Error signal: 'usage: protost vector_workload.st <unit>'].
unit := Smalltalk arguments first.
parts := unit substrings: ':'.
id := parts at: 1.
n := (parts at: 2) asNumber.
plan := parts at: 3.
dash := plan indexOf: $-.
dim := (plan copyFrom: 2 to: dash - 1) asNumber.
op := plan copyFrom: dash + 1 to: plan size.
path := Smalltalk getenv: 'QUERY_VECTOR_DATA'.
path isNil ifTrue: [Error signal: 'vector_workload: QUERY_VECTOR_DATA names the data file'].
emit := [:rows :queries :aChecksum :micros |
  ('WORK id=' , id , ' impl=st size=' , n printString , ' rows=' , rows printString , ' queries=' , queries printString
    , ' plan=' , plan , ' checksum=' , aChecksum printString) displayNl.
  ('TIME id=' , id , ' impl=st size=' , n printString , ' plan=' , plan , ' us=' , micros printString) displayNl].
((#('VB3' 'VB5') includes: id) and: [plan = ('d' , dim printString , '-' , op)
    and: [(id = 'VB3' and: [#('none' 'exact' 'ivf') includes: op]) or: [id = 'VB5' and: [#('exact' 'ivf') includes: op]]]])
  ifTrue: [
    blind := id = 'VB5'.
    commits := ((Smalltalk getenv: (blind ifTrue: ['QUERY_VB5_COMMITS'] ifFalse: ['QUERY_VB3_COMMITS']))
      ifNil: [blind ifTrue: ['120'] ifFalse: ['200']]) asInteger.
    dir := Smalltalk getenv: 'QUERY_DATA'.
    (dir isNil or: [dir isEmpty]) ifTrue: [Error signal: id , ' needs QUERY_DATA, a new directory for its space'].
    dir := dir asFileReference / plan.
    dir ensureCreateDirectory.
    vectors := VectorBench vectorsFrom: path n: n + commits dim: dim.
    coll := blind
      ifTrue: [VectorBench dictionary: (vectors copyFrom: 1 to: n) plan: op dim: dim]
      ifFalse: [VectorBench list: (vectors copyFrom: 1 to: n) plan: op dim: dim].
    space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
    db := space newDatabase: 'bench'.
    tx := db newTransaction.
    tx setRootObject: 'vecs' value: coll.
    tx commit.
    t0 := Time microsecondClockValue.
    0 to: commits - 1 do: [:j | | t |
      t := db newTransaction.
      t setRootObject: 'vecs' value: (blind
        ifTrue: [t newDictionary setAt: n + j value: (vectors at: n + j + 1)]
        ifFalse: [(t getRootObject: 'vecs') appendLast: (vectors at: n + j + 1)]).
      t commit].
    us := Time microsecondClockValue - t0.
    tx := db newTransaction.
    coll := tx getRootObject: 'vecs'.
    coll validate.
    count := coll count.
    count = (n + commits) ifFalse: [Error signal: id , ': ' , count printString , ' elements after the commits'].
    (op = 'ivf' and: [((coll getIndex: 'near') trainedSize) <= n]) ifTrue: [
      Error signal: id , ': the IVF index never retrained (trained size ' , (coll getIndex: 'near') trainedSize printString , ')'].
    checksum := VectorBench checksumOf: coll keyed: blind centroids: blind not.
    tx abort.
    space close.
    emit valueWithArguments: { count. commits. checksum. us }.
    'query_workload ok' displayNl.
    Smalltalk exit: 0].
((id = 'VB1' and: [plan = ('d' , dim printString , '-' , op) and: [#('cosine' 'l2') includes: op]])
    or: [id = 'VB2' and: [plan = ('d' , dim printString , '-ivf')]])
  ifTrue: [ | queries records index first answers search emitOne nlist exact truth built |
    vectors := VectorBench vectorsFrom: path n: n dim: dim.
    queries := VectorBench queriesFrom: path dim: dim.
    records := VectorBench records: vectors.
    search := [:anIndex :aQuery | VectorBench search: anIndex query: aQuery k: 10].
    emitOne := [:label :rows :count :aChecksum :micros |
      ('WORK id=' , id , ' impl=st size=' , n printString , ' rows=' , rows printString , ' queries=' , count printString
        , ' plan=' , label , ' checksum=' , aChecksum printString) displayNl.
      ('TIME id=' , id , ' impl=st size=' , n printString , ' plan=' , label , ' us=' , micros printString) displayNl].
    id = 'VB1' ifTrue: [
      index := (PBVectorIndex name: 'by_vec' keySpec: (PBKeySpec path: 'vec') dim: dim metric: op) build: records.
      t0 := Time microsecondClockValue.
      first := search value: index value: queries first.
      us := Time microsecondClockValue - t0.
      emitOne valueWithArguments: { plan , '-first'. first size. 1. VectorBench answersChecksum: { first }. us }.
      t0 := Time microsecondClockValue.
      answers := queries collect: [:q | search value: index value: q].
      us := Time microsecondClockValue - t0.
      emitOne valueWithArguments: { plan , '-knn'. answers inject: 0 into: [:s :a | s + a size]. queries size.
        VectorBench answersChecksum: answers. us }.
      'query_workload ok' displayNl.
      Smalltalk exit: 0].
    nlist := 4 max: n sqrt truncated.
    exact := (PBVectorIndex name: 'by_vec' keySpec: (PBKeySpec path: 'vec') dim: dim metric: 'cosine') build: records.
    truth := queries collect: [:q | search value: exact value: q].
    t0 := Time microsecondClockValue.
    built := (PBVectorIndex name: 'by_vec' keySpec: (PBKeySpec path: 'vec') dim: dim metric: 'cosine' backend: 'ivf_flat'
      params: (Dictionary new at: 'nlist' put: nlist; at: 'nprobe' put: 1; yourself)) build: records.
    us := Time microsecondClockValue - t0.
    w := WriteStream on: ByteArray new.
    built centroids do: [:c | c do: [:x | w nextPutFloat64: x bigEndian: true]].
    emitOne valueWithArguments: { plan , '-build'. built centroids size. 0. w contents crc32. us }.
    { 1. 4. nlist } do: [:nprobe | | probing hits label params |
      params := Dictionary new.
      built params do: [:pair | params at: (pair at: 1) put: (pair at: 2)].
      params at: 'nprobe' put: nprobe.
      "The built index with another nprobe: the same store and centroids (training does not read
       nprobe), so the three probes are measured on one training."
      probing := built _with: { 'params' -> (PBVectorBackend normalize: params backend: 'ivf_flat') }.
      search value: probing value: queries first.
      t0 := Time microsecondClockValue.
      answers := queries collect: [:q | search value: probing value: q].
      us := Time microsecondClockValue - t0.
      hits := 0.
      answers with: truth do: [:a :t | hits := hits + (a asSet select: [:i | t includes: i]) size].
      label := plan , '-nprobe' , nprobe printString.
      emitOne valueWithArguments: { label. answers inject: 0 into: [:s :a | s + a size]. queries size.
        VectorBench answersChecksum: answers. us }.
      ('RECALL id=' , id , ' impl=st size=' , n printString , ' plan=' , label , ' hits=' , hits printString
        , ' of=' , (10 * queries size) printString) displayNl].
    'query_workload ok' displayNl.
    Smalltalk exit: 0].
(id = 'VB0' and: [(plan at: 1) = $d and: [#('products' 'naive' 'fsum' 'ip' 'l2' 'cosine') includes: op]])
  ifFalse: [Error signal: 'vector_workload: unknown unit ' , unit].
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
emit valueWithArguments: { results size. 1. checksum. us }.
'query_workload ok' displayNl.
