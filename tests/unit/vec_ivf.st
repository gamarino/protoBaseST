"EXPECT: ok 6"
"Vectors phase V4 (Addendum V, 2.4, 2.5 and 5.1): the ivf_flat backend's lists, training and
 retraining (PBVectorIvfFlat listFor:vector:, needsTraining:, train:vectors:, probeOrder:query:),
 against proto_db v2.0.0rc4 (proto_db/indexing/vector_backends.py:527-563, 566-670 and 732-734,
 vector.py:182-268). The training halves of tests/unit/test_vector_index.py's
 test_ivf_flat_trains_on_growth_and_stays_consistent and
 test_ivf_flat_training_depends_on_the_data_and_seed_only, without their searches (V6), on fewer
 vectors; the ivf half of test_validate_detects_structural_corruption (its row is mapped here, in
 tests/unit/queries_checklist.tsv); the retrain thresholds in Python's arithmetic (an int compared
 with the Float retrain_growth * trained_size); and two cases computed by proto_db itself with
 numpy blocked (CPython 3.14, glibc 2.43, the host libm), compared by their IEEE 754 bytes:
 a k-means whose squared distances are subnormal (they decide the nearest centroid, where a
 flush to zero would tie them), and a half-way case, where the libm pow squares of k-means put a
 vector nearer the second centroid while the correctly rounded squares (x * x) would tie it with
 the first. Rows 1 to 4 check the port against proto_db's rules and against itself; the
 byte identity of whole histories with proto_db is tests/interop/vector_index_identical.sh's. Each check gathers its mismatches and requires none,
 so one label covers one behaviour."
Import from: 'protobase'.
Import from: '_check'.

| c fails expect refused tup rec hex hexes vi defs coords records index elements trained lists
  build first again other key value store tampered entry summary sizes |
c := Check new.
expect := [:label :actual :expected |
  actual = expected ifFalse: [fails add: label , ': expected ' , expected printString , ', got ' , actual printString]].
refused := [:aBlock | [aBlock value. nil] on: Error do: [:e | e return: e class]].
tup := [:anArray | PBTuple withAll: anArray].
rec := [:i :v | PBObject withAll: { 'i' -> i. 'vec' -> v }].
hex := [:aFloat | | w | w := WriteStream on: ByteArray new. w nextPutFloat64: aFloat bigEndian: true. w contents hex asLowercase].
hexes := [:aVector | aVector asArray collect: [:x | hex value: x]].
defs := [:assocs | | d | d := Dictionary new. assocs do: [:a | d at: a key put: a value]. d].
"PBVectorIndex name: 'v' over aKeySpec, dim d, metric m, the ivf_flat backend with the parameters p."
vi := [:spec :d :m :p | PBVectorIndex name: 'v' keySpec: spec dim: d metric: m backend: 'ivf_flat' params: (defs value: p)].
"n vectors of d Floats in [-1, 1), from CPython's getrandbits(20) of seed s (any fixed data will do)."
coords := [:n :d :s | | bits |
  bits := PBPythonRandom bits: 20 count: n * d seed: s.
  (1 to: n) asArray collect: [:i |
    tup value: ((1 to: d) asArray collect: [:j | (bits at: (i - 1) * d + j) asFloat / 524288.0 - 1.0])]].
records := [:vectors | (1 to: vectors size) asArray collect: [:i | rec value: i value: (vectors at: i)]].
"The centroids and the (list number, vector) of each store entry, every Float as its hex bytes."
trained := [:anIndex | anIndex centroids asArray collect: [:centroid | hexes value: centroid]].
lists := [:anIndex | anIndex storeEntries collect: [:a | { a key at: 1. hexes value: (a value at: 3) }]].

"test_ivf_flat_trains_on_growth_and_stays_consistent, its training half: an index grown by
 withAdded: keeps every member in list -1 below nlist members, trains at nlist, retrains as it
 grows, files every member under one of its nlist lists, validates, and still validates after half
 its members are removed (a removal never retrains)."
fails := OrderedCollection new.
elements := records value: (coords value: 80 value: 4 value: 3).
index := vi value: (PBKeySpec path: 'vec') value: 4 value: 'l2' value: { 'nlist' -> 4. 'nprobe' -> 4 }.
sizes := OrderedCollection new.
elements doWithIndex: [:e :i |
  index := index withAdded: e.
  (sizes isEmpty or: [sizes last ~= index trainedSize]) ifTrue: [sizes add: index trainedSize].
  i = 3 ifTrue: [
    expect value: 'untrained below nlist' value: { index centroids size. index trainedSize. (index storeEntries collect: [:a | a key at: 1]) asSet asArray }
      value: { 0. 0. #(-1) }]].
expect value: 'trained at 4, retrained at 16 and 64 (retrain_growth 4.0)' value: { index centroids size. sizes asArray }
  value: #(4 #(0 4 16 64)).
expect value: 'every member in a trained list'
  value: (index storeEntries reject: [:a | (a key at: 1) between: 0 and: 3]) size value: 0.
expect value: 'the grown index validates' value: (index validate: elements) == index value: true.
summary := { index centroids. index trainedSize }.
(elements copyFrom: 1 to: 40) do: [:e | index := index withRemoved: e].
expect value: 'removals keep the training' value: { index centroids. index trainedSize } value: summary.
expect value: 'the shrunk index validates' value: (index validate: (elements copyFrom: 41 to: 80)) == index value: true.
c that: 'an ivf_flat index trains on growth and stays consistent' is: fails asArray equals: #().

"test_ivf_flat_training_depends_on_the_data_and_seed_only, its training half (R128): build: over the
 same vectors in three orders, in fresh records each time (other member keys), gives the same
 centroids, for l2 and cosine; another seed trains elsewhere."
fails := OrderedCollection new.
#('l2' 'cosine') do: [:metric |
  build := [:orderSeed :seed | | vectors permutation |
    vectors := coords value: 90 value: 5 value: 11.
    permutation := PBPythonRandom sampleRange: 90 count: 90 seed: orderSeed.
    (vi value: (PBKeySpec path: 'vec') value: 5 value: metric value: { 'nlist' -> 6. 'nprobe' -> 2. 'seed' -> seed })
      build: (records value: (permutation collect: [:k | vectors at: k + 1]))].
  first := build value: 1 value: 0.
  expect value: metric , ' trained' value: { first centroids size. first trainedSize } value: #(6 90).
  #(2 3) do: [:orderSeed |
    again := build value: orderSeed value: 0.
    expect value: metric , ' order ' , orderSeed printString value: (trained value: again) value: (trained value: first)].
  other := build value: 1 value: 7.
  expect value: metric , ' another seed' value: (trained value: other) ~= (trained value: first) value: true].
c that: 'ivf_flat training depends on the data and the seed only' is: fails asArray equals: #().

"The retrain thresholds (vector_backends.py:636-642, vector.py:197): untrained, an index trains when
 it first holds nlist members; trained, when its members reach retrain_growth * trained_size, a
 Float product compared exactly with the member count: 1.5 * 2 = 3.0 retrains at 3, 1.5 * 3 = 4.5
 at 5, and 2.2 * 25 = 55.00000000000001 not at 55 but at 56. Only a new member can trigger it: a
 second occurrence of a member, a removal, or an element whose key is not a vector never does.
 An Integer retrain_growth is stored as a Float and compared the same way. A trained index never
 untrains: emptied by removals (below nlist, then to no member) it keeps its centroids and
 trained_size, and members added again are filed under the old centroids, without a retrain until
 the threshold (tests/interop/vector_index_identical.sh's shrink history pins the same against
 proto_db)."
fails := OrderedCollection new.
index := vi value: PBKeySpec element value: 1 value: 'l2' value: { 'nlist' -> 2. 'retrain_growth' -> 1.5 }.
sizes := OrderedCollection new.
{ tup value: #(1.0). tup value: #(2.0). tup value: #(3.0). tup value: #(3.0). 'x'. tup value: #(4.0). tup value: #(5.0).
  tup value: #(6.0). tup value: #(7.0). tup value: #(8.0) } do: [:e |
  index := index withAdded: e.
  sizes add: { index memberCount. index trainedSize. PBVectorIvfFlat needsTraining: index }].
expect value: 'growth 1.5' value: sizes asArray
  value: #(#(1 0 false) #(2 2 false) #(3 3 false) #(3 3 false) #(3 3 false) #(4 3 false) #(5 5 false) #(6 5 false)
    #(7 5 false) #(8 8 false)).
index := index withRemoved: (tup value: #(8.0)).
expect value: 'a removal keeps the training' value: { index memberCount. index trainedSize. PBVectorIvfFlat needsTraining: index }
  value: #(7 8 false).
summary := index centroids.
#(7.0 6.0 5.0 4.0 3.0 2.0 1.0) do: [:x | index := index withRemoved: (tup value: { x })].
index := index withRemoved: (tup value: #(3.0)).
expect value: 'emptied, still trained' value: { index memberCount. index trainedSize. index centroids = summary. PBVectorIvfFlat needsTraining: index }
  value: #(0 8 true false).
index := (index withAdded: (tup value: #(1.0))) withAdded: (tup value: #(9.0)).
expect value: 'regrown under the old centroids'
  value: { index memberCount. index trainedSize. index centroids = summary.
    index storeEntries collect: [:a | a key at: 1].
    { PBVectorIvfFlat listFor: index vector: (tup value: #(1.0)). PBVectorIvfFlat listFor: index vector: (tup value: #(9.0)) } }
  value: { 2. 8. true. #(0 1). #(0 1) }.
index := (vi value: PBKeySpec element value: 1 value: 'l2' value: { 'nlist' -> 2. 'retrain_growth' -> 2.2 })
  build: ((1 to: 25) asArray collect: [:i | tup value: { i asFloat }]).
expect value: 'built at 25' value: { index trainedSize. 2.2 * 25.0 > 55.0 } value: #(25 true).
26 to: 55 do: [:i | index := index withAdded: (tup value: { i asFloat })].
expect value: '55 < 55.00000000000001' value: { index memberCount. index trainedSize } value: #(55 25).
index := index withAdded: (tup value: #(56.0)).
expect value: '56 retrains' value: { index memberCount. index trainedSize } value: #(56 56).
index := (vi value: PBKeySpec element value: 1 value: 'l2' value: { 'nlist' -> 1. 'retrain_growth' -> 2 })
  build: { tup value: #(1.0) }.
index := (index withAdded: (tup value: #(2.0))) withAdded: (tup value: #(3.0)).
expect value: 'an Integer growth' value: { index paramAt: 'retrain_growth'. index trainedSize } value: #(2.0 2).
expect value: 'needsTraining: of an empty index' value: (PBVectorIvfFlat needsTraining: (vi value: PBKeySpec element value: 1 value: 'l2' value: #()))
  value: false.
c that: 'retrain thresholds are compared in Python''s arithmetic' is: fails asArray equals: #().

"The ivf half of test_validate_detects_structural_corruption: a trained ivf_flat index validates,
 and each tampered version (another vector, another count, a zero count, a missing member, a member
 in the next list, a wrong total, a centroid removed) is PBCorruptionError."
fails := OrderedCollection new.
elements := (1 to: 30) asArray collect: [:i |
  rec value: i value: (tup value: { (i * 37 \\ 11) asFloat - 5.0. (i * 13 \\ 7) asFloat / 3.0. (i \\ 5) asFloat })].
index := (vi value: (PBKeySpec path: 'vec') value: 3 value: 'l2' value: { 'nlist' -> 3. 'nprobe' -> 1 }) build: elements.
expect value: 'trained' value: { index centroids size. index trainedSize } value: #(3 30).
expect value: 'the build validates' value: (index validate: elements) == index value: true.
entry := index storeEntries first.
key := entry key.
value := entry value.
store := index store.
tampered := {
  index _with: { 'store' -> ((PBAvl keyPut: store key: key value: (tup value: { value at: 1. value at: 2. tup value: #(9.0 9.0 9.0) }) nodeClass: PBKeyNode) at: 1) }.
  index _with: { 'store' -> ((PBAvl keyPut: store key: key value: (tup value: { value at: 1. (value at: 2) + 1. value at: 3 }) nodeClass: PBKeyNode) at: 1) }.
  index _with: { 'store' -> ((PBAvl keyPut: store key: key value: (tup value: { value at: 1. 0. value at: 3 }) nodeClass: PBKeyNode) at: 1) }.
  index _with: { 'store' -> ((PBAvl keyRemove: store key: key) at: 1) }.
  index _with: { 'store' -> ((PBAvl keyPut: store key: (tup value: { (key at: 1) + 1. key at: 2 }) value: value nodeClass: PBKeyNode) at: 1) }.
  index _with: { 'total_count' -> (index totalCount + 1) }.
  index _with: { 'centroids' -> (tup value: (index centroids asArray copyFrom: 1 to: 2)) } }.
tampered doWithIndex: [:bad :i | expect value: 'tampered ' , i printString value: (refused value: [bad validate: elements]) value: PBCorruptionError].
expect value: 'a removed centroid' value: ([(tampered at: 7) validate: elements. nil] on: PBCorruptionError do: [:e | e return: e messageText])
  value: 'Index ''v'' (VectorIndex on vec) is corrupt: 2 centroids for nlist=3'.
c that: 'validate: catches tampering on an ivf_flat index, a removed centroid included' is: fails asArray equals: #().

"Subnormal squares: five 1-vectors between 0 and 1.2e-161, trained by proto_db (l2, nlist 2, three
 iterations, seed 0; CPython 3.14 and glibc 2.43, numpy blocked). Their squared differences are
 subnormal (raisedTo: 2 is libm pow, which, as CPython's float ** 2, answers them without flushing
 them to zero), and they decide the nearest centroid: flushed to zero, the centroids would be
 (1e74dffd6106001a) and (1e859843e8c86a09). The lists come from the scores' x * x, subnormal too."
fails := OrderedCollection new.
index := (vi value: PBKeySpec element value: 1 value: 'l2' value: { 'nlist' -> 2. 'nprobe' -> 1. 'train_iters' -> 3 })
  build: (#(0.0 3.0e-162 5.0e-162 9.0e-162 1.2e-161) collect: [:x | tup value: { x }]).
expect value: 'the squares are subnormal' value: { hex value: (3.0e-162 raisedTo: 2). hex value: (2.0e-162 raisedTo: 2) }
  value: #('0000000000000002' '0000000000000001').
expect value: 'centroids' value: { trained value: index. index trainedSize }
  value: { #(#('1e6332037995b397') #('1e82e53b6baf5cc8')). 5 }.
expect value: 'lists' value: (lists value: index)
  value: #(#(0 #('0000000000000000')) #(0 #('1e659843e8c86a09')) #(0 #('1e71fee341fc585d')) #(1 #('1e803232ee964f87'))
    #(1 #('1e859843e8c86a09'))).
expect value: 'it validates' value: (index validate: (index storeEntries collect: [:a | a value at: 1])) == index value: true.
c that: 'a subnormal-square distance decides the centroid as in proto_db' is: fails asArray equals: #().

"A half-way tie: v = (2^28, 2^28), c0 = v + (113218723, -73036029), c1 = v + (113729583, -72237959).
 Both differences have the same exact squared length (113218723^2 + 73036029^2 =
 113729583^2 + 72237959^2), and all four squares are half-way cases. Sorted by training order the
 vectors are v, c0, c1; seed 0 samples c0 and c1 as the initial centroids. The correctly rounded
 squares (x * x) tie v between them, and the tie would go to centroid 0; libm pow's squares, which
 proto_db's k-means takes (CPython's float ** 2), put v nearer centroid 1 (1.815274076983957e16
 against 1.8152740769839572e16). After one iteration proto_db's centroids are c0 and (c1 + v) / 2,
 whatever order the vectors were given in; the lists come from the scores, which multiply. Then
 an exact tie in listFor:vector: and in probeOrder:query: goes to the lowest list number, as
 IvfFlatBackend.list_for's strict > and _probe_order's sort by (-score, number) do."
fails := OrderedCollection new.
elements := { tup value: #(382165039.0 196197497.0). tup value: #(268435456.0 268435456.0). tup value: #(381654179.0 195399427.0) }.
index := (vi value: PBKeySpec element value: 2 value: 'l2' value: { 'nlist' -> 2. 'nprobe' -> 1. 'train_iters' -> 1 })
  build: elements.
expect value: 'the squares tie, the pow squares do not'
  value: { (PBVectorMath sumNonNegative: { 113218723.0 * 113218723.0. 73036029.0 * 73036029.0 })
      = (PBVectorMath sumNonNegative: { 113729583.0 * 113729583.0. 72237959.0 * 72237959.0 }).
    hex value: (PBVectorMath _kmeansDistance: (elements at: 2) to: (elements at: 3)).
    hex value: (PBVectorMath _kmeansDistance: (elements at: 2) to: (elements at: 1)) }
  value: { true. '43501f7494524e75'. '43501f7494524e74' }.
expect value: 'centroids' value: { trained value: index. index trainedSize }
  value: { #(#('41b6bf94a3000000' '41a74b1e06000000') #('41b363b017800000' '41abb1bc79000000')). 3 }.
expect value: 'lists' value: (lists value: index)
  value: #(#(0 #('41b6bf94a3000000' '41a74b1e06000000')) #(0 #('41b6c7602f000000' '41a76378f2000000'))
    #(1 #('41b0000000000000' '41b0000000000000'))).
expect value: 'any order' value: (trained value: (index build: elements reverse)) value: (trained value: index).
index := index _with: { 'centroids' -> (tup value: { tup value: #(1.0 0.0). tup value: #(-1.0 0.0) }). 'trained_size' -> 3 }.
expect value: 'listFor:vector: ties to the lowest number'
  value: { PBVectorIvfFlat listFor: index vector: (tup value: #(0.0 5.0)). PBVectorIvfFlat listFor: index vector: (tup value: #(-0.5 5.0)) }
  value: #(0 1).
expect value: 'probeOrder:query: ties by number'
  value: { PBVectorIvfFlat probeOrder: index query: (tup value: #(0.0 5.0)). PBVectorIvfFlat probeOrder: index query: (tup value: #(-0.5 5.0)).
    PBVectorIvfFlat probeOrder: (index _with: { 'centroids' -> (tup value: #()). 'trained_size' -> 0 }) query: (tup value: #(0.0 5.0)) }
  value: #(#(-1 0 1) #(-1 1 0) #(-1)).
c that: 'a half-way distance tie between two centroids is resolved as proto_db resolves it' is: fails asArray equals: #().

c report displayNl.
