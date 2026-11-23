"EXPECT: ok 13"
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
 byte identity of whole histories with proto_db is tests/interop/vector_index_identical.sh's.
 Then the search rows (vectors phase V6; vector_backends.py:663-730, vector.py:272-319):
 test_ivf_flat_with_full_probe_equals_exact, the search halves of the two tests above,
 test_ivf_flat_partial_probe_has_good_recall_and_widens_for_k and
 test_ivf_flat_round_trip_through_file_storage_keeps_centroids, on fewer vectors than proto_db's
 (sizes chosen when the floor, protoST 0.14.1, had only the interpreted kernel; it is now 0.16.1); the list walk and the probe loop against
 the forms they replaced (review I1 of task V6); and the non-empty lists rule of the probe against
 answers computed by proto_db itself (review I3). Each check gathers its mismatches and requires
 none, so one label covers one behaviour."
Import from: 'protobase'.
Import from: '_check'.

| c fails expect refused tup rec hex hexes vi defs coords records index elements trained lists
  build first again other key value store tampered entry summary sizes near ids oracle shrunk exact
  queries answers hits recall dir storage pointer loaded extra q term grownLater kept oldList oldSearch same
  cases emptied listOf gone answer probes |
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
shrunk := index.
kept := elements copyFrom: 41 to: 80.

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

"=== the search rows (vectors phase V6) ==="
near := [:v :k :t | PBTerm path: 'vec' op: 'near[]' value: (PBNearQuery vector: v k: k threshold: t metric: nil)].
"The stored elements themselves, in order: exact token and identity of each."
ids := [:anArray | anArray asArray collect: [:e | (PBKeys exactToken: e) hex , ':' , (PBMemberKeys identityOf: e) printString]].
oracle := [:anIndex :anArray :aTerm | ids value: (PBVectorIndex nearOracle: anArray keySpec: anIndex keySpecObject
  query: aTerm value metric: anIndex metric predicate: nil)].

"test_ivf_flat_with_full_probe_equals_exact: with nprobe = nlist an ivf_flat index probes every
 list, so for every metric, k, threshold and both it answers what the exact index and the brute
 force answer, nearest first."
fails := OrderedCollection new.
elements := records value: (coords value: 160 value: 6 value: 11).
queries := coords value: 8 value: 6 value: 12.
#('cosine' 'l2' 'ip') do: [:metric | | ivf thresholds |
  ivf := (vi value: (PBKeySpec path: 'vec') value: 6 value: metric value: { 'nlist' -> 8. 'nprobe' -> 8 }) build: elements.
  exact := (PBVectorIndex name: 'v' keySpec: (PBKeySpec path: 'vec') dim: 6 metric: metric) build: elements.
  ivf centroids size = 8 ifFalse: [fails add: metric , ': ' , ivf centroids size printString , ' centroids'].
  thresholds := metric = 'cosine' ifTrue: [#(-0.5 0.3 0.9)] ifFalse: [metric = 'l2' ifTrue: [#(0.5 1.5 3.0)] ifFalse: [#(-1.0 0.5 2.0)]].
  queries doWithIndex: [:v :j |
    { near value: v value: (#(1 10 50) at: j \\ 3 + 1) value: nil. near value: v value: nil value: (thresholds at: j \\ 3 + 1).
      near value: v value: 7 value: (thresholds at: (j + 1) \\ 3 + 1) } do: [:aTerm | | got |
      got := ids value: (ivf plan: aTerm) execute.
      (got = (ids value: (exact plan: aTerm) execute) and: [got = (oracle value: ivf value: elements value: aTerm)]) ifFalse: [
        fails add: metric , ' ' , aTerm describe printString]]]].
c that: 'an ivf_flat index probing every list answers what the exact index answers' is: fails asArray equals: #().

"test_ivf_flat_trains_on_growth_and_stays_consistent, its search half: the index grown by withAdded:
 and shrunk by withRemoved: (the first check above), nprobe = nlist, answers what the brute force
 answers over the elements it holds."
fails := OrderedCollection new.
elements := kept.
(coords value: 3 value: 4 value: 33) do: [:v | | term |
  term := near value: v value: 9 value: nil.
  (ids value: (shrunk plan: term) execute) = (oracle value: shrunk value: elements value: term) ifFalse: [
    fails add: 'grown and shrunk ' , term describe printString]].
expect value: 'it holds 40 members' value: elements size value: 40.
c that: 'an ivf_flat index grown and shrunk answers what the brute force answers' is: fails asArray equals: #().

"test_ivf_flat_partial_probe_has_good_recall_and_widens_for_k: 600 records of dim 8, nlist 16,
 nprobe 4; recall at 10 against the exact index over 20 queries is at least 0.6, as proto_db
 requires; a k beyond what the nprobe lists hold widens the probe until k members are found."
fails := OrderedCollection new.
elements := records value: (coords value: 600 value: 8 value: 5).
index := (vi value: (PBKeySpec path: 'vec') value: 8 value: 'l2' value: { 'nlist' -> 16. 'nprobe' -> 4 }) build: elements.
exact := (PBVectorIndex name: 'v' keySpec: (PBKeySpec path: 'vec') dim: 8 metric: 'l2') build: elements.
hits := 0.
(coords value: 20 value: 8 value: 6) do: [:v | | a b |
  a := (index plan: (near value: v value: 10 value: nil)) execute.
  b := (exact plan: (near value: v value: 10 value: nil)) execute.
  a size = 10 ifFalse: [fails add: 'a query answered ' , a size printString].
  hits := hits + ((a collect: [:e | e at: 'i']) asSet select: [:i | (b collect: [:e | e at: 'i']) includes: i]) size].
recall := hits / 200.
expect value: 'recall at least 0.6' value: recall >= (6 / 10) value: true.
expect value: 'k = 450 widens to 450 members'
  value: (index plan: (near value: (coords value: 1 value: 8 value: 7) first value: 450 value: nil)) execute size value: 450.
c that: 'a partial probe has good recall and widens for k' is: fails asArray equals: #().

"test_ivf_flat_training_depends_on_the_data_and_seed_only, its search half (R128): the same records
 built in three orders answer the same records for the same queries."
fails := OrderedCollection new.
elements := records value: (coords value: 90 value: 5 value: 11).
#('l2' 'cosine') do: [:metric |
  build := [:orderSeed :seed | | permutation |
    permutation := PBPythonRandom sampleRange: 90 count: 90 seed: orderSeed.
    (vi value: (PBKeySpec path: 'vec') value: 5 value: metric value: { 'nlist' -> 6. 'nprobe' -> 2. 'seed' -> seed })
      build: (permutation collect: [:k | elements at: k + 1])].
  queries := coords value: 6 value: 5 value: 13.
  answers := [:anIndex | queries collect: [:v |
    ((anIndex plan: (near value: v value: 10 value: nil)) execute collect: [:e | e at: 'i']) asSortedCollection asArray]].
  first := answers value: (build value: 1 value: 0).
  #(2 3) do: [:orderSeed |
    (answers value: (build value: orderSeed value: 0)) = first ifFalse: [fails add: metric , ' order ' , orderSeed printString]]].
c that: 'ivf_flat answers depend on the data and the seed only' is: fails asArray equals: #().

"The list walk and the probe loop of PBVectorIvfFlat search: (review I1 of task V6) against the
 forms they replaced, kept here as the reference: a list walk bounded by list_bounds' tuple order
 keys, (j) and (j, a key above every rank), both exclusive, and proto_db's loop over the probe
 order filtered to the non-empty lists first (vector_backends.py:685-707). On the indexes of the
 rows above (every metric at nprobe 8 and 2, the 600-member index, the shrunk one), an untrained
 one and one with a list emptied by removals, every list (-1 to nlist, one past the last) visits
 the same nodes (==) in the same order, and every query (k, k widened by a predicate or by a
 threshold, a threshold alone) answers the same elements (==) and counts."
fails := OrderedCollection new.
oldList := [:anIndex :j | | out jk |
  out := OrderedCollection new.
  jk := PBKeys orderKey: j.
  PBAvl nodeDo: [:node | out addLast: node] over: anIndex store
    fromOrderKey: (PBOrderKey rank: PBMemberKeys _tupleRank payload: { jk }) inclusive: false
    toOrderKey: (PBOrderKey rank: PBMemberKeys _tupleRank payload: { jk. PBMemberKeys _aboveEveryRank }) inclusive: false.
  out asArray].
oldSearch := [:anIndex :aQuery :k :t :eligible | | order probe floor done probed matching metric |
  order := (PBVectorIvfFlat probeOrder: anIndex query: aQuery) select: [:j | (oldList value: anIndex value: j) notEmpty].
  probe := (anIndex paramAt: 'nprobe') + ((order notEmpty and: [order first = -1]) ifTrue: [1] ifFalse: [0]).
  metric := anIndex metric.
  floor := PBVectorMath scoreFloor: metric threshold: t.
  done := 0.
  probed := OrderedCollection new.
  matching := 0.
  [done + 1 to: (probe min: order size) do: [:i | | entries |
      entries := (oldList value: anIndex value: (order at: i)) collect: [:node | anIndex _entryOf: node].
      probed addAll: entries.
      (k notNil and: [eligible isNil and: [floor isNil]])
        ifTrue: [matching := matching + entries size]
        ifFalse: [k isNil ifFalse: [entries do: [:entry |
          ((eligible isNil or: [eligible value: (entry at: 2)])
              and: [floor isNil or: [(PBVectorMath score: metric query: aQuery vector: (entry at: 4)) >= floor]])
            ifTrue: [matching := matching + 1]]]]].
    done := probe min: order size.
    done >= order size or: [k isNil or: [matching >= k]]]
      whileFalse: [probe := order size min: 2 * probe].
  PBVectorMath rank: (PBVectorBackend _filtered: probed eligible: eligible) query: aQuery metric: metric k: k threshold: t].
same := [:a :b | a size = b size and: [(1 to: a size) allSatisfy: [:i |
  ((a at: i) at: 1) == ((b at: i) at: 1) and: [((a at: i) at: 2) = ((b at: i) at: 2)]]]].
elements := records value: (coords value: 160 value: 6 value: 11).
cases := OrderedCollection new.
#('cosine' 'l2' 'ip') do: [:metric | #(8 2) do: [:p |
  cases add: metric , ' nprobe ' , p printString
    -> ((vi value: (PBKeySpec path: 'vec') value: 6 value: metric value: { 'nlist' -> 8. 'nprobe' -> p }) build: elements)]].
cases add: 'partial probe' -> index.
cases add: 'grown and shrunk' -> shrunk.
cases add: 'untrained' -> ((vi value: (PBKeySpec path: 'vec') value: 6 value: 'l2' value: { 'nlist' -> 8. 'nprobe' -> 2 })
  build: (elements copyFrom: 1 to: 5)).
emptied := (cases at: 2) value.
emptied := (elements select: [:e | (PBVectorIvfFlat listFor: emptied vector: (e at: 'vec')) = 3])
  inject: emptied into: [:acc :e | acc withRemoved: e].
cases add: 'list 3 emptied' -> emptied.
cases do: [:case | | anIndex dim nlist |
  anIndex := case value.
  dim := anIndex dim.
  nlist := anIndex paramAt: 'nlist'.
  -1 to: nlist do: [:j | | old new |
    old := oldList value: anIndex value: j.
    new := OrderedCollection new.
    anIndex _listNodesOf: j do: [:node | new addLast: node].
    (old size = new size and: [(1 to: old size) allSatisfy: [:i | (old at: i) == (new at: i)]]) ifFalse: [
      fails add: case key , ' list ' , j printString]].
  (coords value: 4 value: dim value: 21) doWithIndex: [:v :n | | qv t |
    qv := PBVectorMath canonicalVector: v dim: dim.
    t := anIndex metric = 'l2' ifTrue: [1.2] ifFalse: [0.1].
    { { 10. nil. nil }. { 40. nil. [:e | (e at: 'i') \\ 7 = 0] }. { 30. t. nil }. { nil. t. nil }. { 5. nil. [:e | false] } }
      doWithIndex: [:query :m |
        ((same value: (oldSearch value: anIndex value: qv value: (query at: 1) value: (query at: 2) value: (query at: 3))
            value: (PBVectorIvfFlat search: anIndex query: qv k: (query at: 1) threshold: (query at: 2) eligible: (query at: 3))))
          ifFalse: [fails add: case key , ' query ' , n printString , '.' , m printString]]]].
expect value: 'list 3 emptied' value: (emptied _listEntries: 3) size value: 0.
c that: 'the list walk and the probe loop read what the order-key walk and proto_db''s loop read' is: fails asArray equals: #().

"The non-empty lists rule of the probe (vector_backends.py:688, 'j in lists'; Addendum V 2.4: same
 lists, same order, same answer): an empty list never counts toward nprobe. 60 records of dim 3
 (integer residues, the same Floats in both languages), l2, nlist 6, nprobe 2; the members of list
 0, the nearest to the query, are removed (the training stays), and the queries run before and
 after: a threshold alone that every member passes (the answer is the probed lists: their count
 is the probe), k 5, and k 12 widened by a predicate and by a threshold. Expected: proto_db
 v2.0.0rc4 itself (CPython 3.14, numpy and hnswlib blocked; its probed lists are the answers'
 lists here); an emptied list counted toward the probe would probe list 3 alone."
fails := OrderedCollection new.
elements := (1 to: 60) asArray collect: [:i | rec value: i value: (tup value: {
  (i * 37 \\ 23) asFloat / 11.0 - 1.0. (i * 53 \\ 29) asFloat / 14.0 - 1.0. (i * 71 \\ 31) asFloat / 15.0 - 1.0 })].
index := (vi value: (PBKeySpec path: 'vec') value: 3 value: 'l2' value: { 'nlist' -> 6. 'nprobe' -> 2 }) build: elements.
q := tup value: #(0.3 -0.2 0.1).
listOf := [:e | PBVectorIvfFlat listFor: index vector: (e at: 'vec')].
expect value: 'probe order and list sizes'
  value: { PBVectorIvfFlat probeOrder: index query: q. (0 to: 5) asArray collect: [:j | (elements select: [:e | (listOf value: e) = j]) size] }
  value: #(#(-1 0 3 2 1 5 4) #(9 12 9 11 9 10)).
gone := elements select: [:e | (listOf value: e) = 0].
expect value: 'list 0' value: (gone collect: [:e | e at: 'i']) value: #(11 16 22 29 34 39 50 52 57).
emptied := gone inject: index into: [:acc :e | acc withRemoved: e].
expect value: 'the training stays' value: emptied centroids = index centroids value: true.
answer := [:anIndex :k :t :eligible | | qv out |
  qv := PBVectorMath canonicalVector: q dim: 3.
  out := OrderedCollection new.
  (PBVectorIvfFlat search: anIndex query: qv k: k threshold: t eligible: eligible) do: [:pair |
    (pair at: 2) timesRepeat: [out addLast: (pair at: 1)]].
  out asArray].
probes := [:anIndex :label | | all |
  all := answer value: anIndex value: nil value: 100.0 value: nil.
  expect value: label , ' threshold 100.0'
    value: { ((all collect: [:e | listOf value: e]) asSet asSortedCollection asArray). all collect: [:e | e at: 'i'] }
    value: (label = 'full'
      ifTrue: [#(#(0 3) #(9 50 16 57 39 22 37 19 29 34 11 55 2 43 20 52 30 53 12 48))]
      ifFalse: [#(#(2 3) #(9 26 44 37 19 3 54 55 2 43 47 13 20 30 53 6 12 24 48 41))]).
  expect value: label , ' k 5' value: ((anIndex plan: (near value: q value: 5 value: nil)) execute collect: [:e | e at: 'i'])
    value: (label = 'full' ifTrue: [#(9 50 16 57 39)] ifFalse: [#(9 26 44 37 19)]).
  all := answer value: anIndex value: 12 value: nil value: [:e | (e at: 'i') \\ 3 = 0].
  expect value: label , ' k 12, i \\ 3 = 0'
    value: { ((all collect: [:e | listOf value: e]) asSet asSortedCollection asArray). all collect: [:e | e at: 'i'] }
    value: (label = 'full'
      ifTrue: [#(#(0 1 2 3) #(9 57 39 60 3 54 21 42 36 30 6 12))]
      ifFalse: [#(#(1 2 3 5) #(9 60 3 54 21 42 36 15 45 30 6 12))]).
  expect value: label , ' k 12, threshold 0.9'
    value: ((anIndex plan: (near value: q value: 12 value: 0.9)) execute collect: [:e | e at: 'i'])
    value: (label = 'full'
      ifTrue: [#(9 50 16 57 26 39 44 60 22 37 19 8)]
      ifFalse: [#(9 26 44 32 60 37 19 8 49 3 54 4)])].
probes value: index value: 'full'.
probes value: emptied value: 'emptied'.
c that: 'an ivf_flat probe skips the lists that removals emptied, as proto_db''s does' is: fails asArray equals: #().

"test_ivf_flat_round_trip_through_file_storage_keeps_centroids: saved to a file storage and loaded
 back by its tag, the index has the same centroids, parameters and explain, answers the same,
 validates, and keeps working: one more record, at the query vector, is its own nearest member.
 The space goes to out/vec_ivf (git ignores out/), a new directory per run; nothing is removed."
fails := OrderedCollection new.
elements := records value: (coords value: 120 value: 5 value: 9).
index := (vi value: (PBKeySpec path: 'vec') value: 5 value: 'cosine' value: { 'nlist' -> 6. 'nprobe' -> 2 }) build: elements.
dir := ('out/vec_ivf' asFileReference / ('run-' , Smalltalk pid printString , '-' , Time microsecondClockValue printString)) pathString.
storage := PBFileStorage path: dir.
index _saveInto: storage.
pointer := index pointer.
storage close.
storage := PBFileStorage path: dir.
loaded := PBTypeRegistry unloadedAtomFor: index tag at: pointer storage: storage.
expect value: 'centroids, params and explain' value: { loaded centroids = index centroids. loaded centroids size.
    loaded params = index params. loaded explain = index explain }
  value: #(true 6 true true).
q := (coords value: 1 value: 5 value: 10) first.
term := near value: q value: 8 value: nil.
expect value: 'the same answer' value: ((loaded plan: term) execute collect: [:e | e at: 'i'])
  value: ((index plan: term) execute collect: [:e | e at: 'i']).
expect value: 'the loaded index validates' value: (loaded validate: elements) == loaded value: true.
extra := rec value: -1 value: q.
grownLater := loaded withAdded: extra.
expect value: 'grown, its own nearest' value: ((grownLater plan: (near value: q value: 1 value: nil)) execute collect: [:e | e at: 'i'])
  value: #(-1).
expect value: 'grown, it validates' value: (grownLater validate: elements , { extra }) == grownLater value: true.
storage close.
c that: 'an ivf_flat index keeps its centroids and answers through a file storage' is: fails asArray equals: #().

c report displayNl.
