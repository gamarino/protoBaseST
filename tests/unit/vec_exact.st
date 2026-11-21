"EXPECT: ok 6"
"Vectors phase V6 (Addendum V, 2.4, 2.7 and 5.1): the exact backend's search against proto_db
 v2.0.0rc4 (proto_db/indexing/vector.py:92-122 and 272-319, vector_backends.py:147-167 and
 480-524, base.py:274-281). The behaviours of tests/unit/test_vector_index.py's
 test_supports_only_near_on_its_key_with_matching_dimension_and_metric,
 test_exact_backend_equals_brute_force, test_exact_backend_equals_brute_force_at_extreme_magnitudes,
 test_results_are_nearest_first_and_ties_follow_the_member_key,
 test_duplicates_are_counted_and_equal_values_come_back_exactly and
 test_invalid_vectors_are_kept_aside_and_never_returned (mapped in tests/unit/queries_checklist.tsv),
 on fewer elements and queries than proto_db's (the interpreted kernel of protoST 0.14.1 is the
 floor): every answer of the index equals PBVectorIndex nearOracle:keySpec:query:metric:predicate:
 (near_oracle, the brute-force definition), compared in order (nearest first, ties by member key)
 and as the stored elements themselves (exact token and identity). proto_db runs the exact test
 with and without numpy; protoBaseST has no numpy screening (deviation DV2), so it has one mode.
 The data are drawn from CPython's getrandbits (PBPythonRandom): any fixed data will do. Each check
 gathers its mismatches and requires none, so one label covers one behaviour."
Import from: 'protobase'.
Import from: '_check'.

| c fails expect refused tup rec vi near ids answer oracle coords ints bits elements index q k thr
  term metrics thresholds choose draw a b cc first good bad info got one oneD scales vec n spec |
c := Check new.
expect := [:label :actual :expected |
  actual = expected ifFalse: [fails add: label , ': expected ' , expected printString , ', got ' , actual printString]].
refused := [:aBlock | [aBlock value. nil] on: Error do: [:e | e return: e class]].
tup := [:anArray | PBTuple withAll: anArray].
rec := [:i :v | PBObject withAll: { 'i' -> i. 'g' -> (i \\ 3). 'vec' -> v }].
vi := [:d :m | PBVectorIndex name: 'v' keySpec: (PBKeySpec path: 'vec') dim: d metric: m].
near := [:v :k :t :m | PBTerm path: 'vec' op: 'near[]' value: (PBNearQuery vector: v k: k threshold: t metric: m)].
"The stored elements themselves, in order: exact token and identity of each."
ids := [:anArray | anArray asArray collect: [:e | (PBKeys exactToken: e) hex , ':' , (PBMemberKeys identityOf: e) printString]].
answer := [:anIndex :aTerm | ids value: (anIndex plan: aTerm) execute].
oracle := [:anIndex :anArray :aTerm | ids value: (PBVectorIndex nearOracle: anArray keySpec: anIndex keySpecObject
  query: aTerm value metric: anIndex metric predicate: nil)].
"n vectors of d Floats in [-1, 1), from CPython's getrandbits(20) of seed s."
coords := [:n0 :d :s | | r |
  r := PBPythonRandom bits: 20 count: n0 * d seed: s.
  (1 to: n0) asArray collect: [:i |
    tup value: ((1 to: d) asArray collect: [:j | (r at: (i - 1) * d + j) asFloat / 524288.0 - 1.0])]].
"n vectors of d Floats among -2.0 .. 2.0 (exact ties)."
ints := [:n0 :d :s | | r |
  r := PBPythonRandom bits: 20 count: n0 * d seed: s.
  (1 to: n0) asArray collect: [:i |
    tup value: ((1 to: d) asArray collect: [:j | ((r at: (i - 1) * d + j) \\ 5 - 2) asFloat])]].
"A deterministic choice among anArray, the i-th draw."
bits := PBPythonRandom bits: 16 count: 2000 seed: 99.
draw := 0.
choose := [:anArray | draw := draw \\ bits size + 1. anArray at: (bits at: draw) \\ anArray size + 1].

"test_supports_only_near_on_its_key_with_matching_dimension_and_metric: near[] on the index's own
 key, of its dimension, with its metric or none; plan: and estimate: of anything else are
 PBNotSupportedError; every supported term may be restricted to a predicate (supportsFiltered:), a
 key-group index restricts none (base.py's defaults, with their text)."
fails := OrderedCollection new.
index := vi value: 3 value: 'l2'.
expect value: 'supports:' value: {
    index supports: (near value: #(1 2 3) value: 2 value: nil value: nil).
    index supports: (near value: #(1 2 3) value: 2 value: nil value: 'l2').
    index supports: (near value: #(1 2 3) value: 2 value: nil value: 'cosine').
    index supports: (near value: #(1 2) value: 2 value: nil value: nil).
    index supports: (PBTerm path: 'other' op: 'near[]' value: (PBNearQuery vector: #(1 2 3) k: 2)).
    index supports: (PBTerm path: 'vec' op: '==' value: 1) }
  value: #(true true false false false false).
expect value: 'plan: and estimate: refuse an unsupported term' value: {
    refused value: [index plan: (near value: #(1 2) value: 1 value: nil value: nil)].
    refused value: [index estimate: (near value: #(1 2) value: 1 value: nil value: nil)].
    [index plan: (near value: #(1 2) value: 1 value: nil value: nil)] on: PBNotSupportedError do: [:e | e return: e messageText] }
  value: { PBNotSupportedError. PBNotSupportedError. 'Index ''v'' (VectorIndex on vec) does not support ''near[]'' on ''vec''' }.
expect value: 'supportsFiltered:' value: {
    index supportsFiltered: (near value: #(1 2 3) value: 2 value: nil value: nil).
    index supportsFiltered: (near value: #(1 2) value: 2 value: nil value: nil) }
  value: #(true false).
expect value: 'filteredPlan:where: refuses an unsupported term'
  value: (refused value: [index filteredPlan: (near value: #(1 2) value: 1 value: nil value: nil) where: (PBTerm path: 'g' op: '==' value: 1)])
  value: PBNotSupportedError.
expect value: 'a residual predicate holding near[] is refused'
  value: (refused value: [index filteredPlan: (near value: #(1 2 3) value: 1 value: nil value: nil)
    where: (near value: #(1 2 3) value: 1 value: nil value: nil)])
  value: PBValidationError.
a := PBEqualityIndex name: 'e' path: 'g'.
expect value: 'a key-group index restricts no term (base.py)' value: {
    a supportsFiltered: (PBTerm path: 'g' op: '==' value: 1).
    [a filteredPlan: (PBTerm path: 'g' op: '==' value: 1) where: (PBTerm path: 'h' op: '==' value: 2)]
      on: PBNotSupportedError do: [:e | e return: e messageText] }
  value: #(false 'Index ''e'' (EqualityIndex) cannot answer ''=='' restricted to a predicate').
c that: 'supports: answers near[] on its own key, its dimension and its metric only' is: fails asArray equals: #().

"test_exact_backend_equals_brute_force: 90 records of random Floats and 20 of small integers
 (exact ties), three of them again (duplicates), for each metric; 8 queries (random, a stored
 vector, small integers), each with k, a threshold, and both."
fails := OrderedCollection new.
vec := (coords value: 90 value: 8 value: 7) , (ints value: 20 value: 8 value: 8).
elements := (1 to: vec size) asArray collect: [:i | rec value: i - 1 value: (vec at: i)].
elements := elements , { elements at: 4. elements at: 4. elements at: 81 }.
thresholds := Dictionary new.
thresholds at: 'cosine' put: #(-0.5 0.0 0.3 0.9 1.0); at: 'l2' put: #(0.0 0.5 1.5 3.0); at: 'ip' put: #(-1.0 0.0 0.5 2.0).
#('cosine' 'l2' 'ip') do: [:metric |
  index := (vi value: 8 value: metric) build: elements.
  1 to: 8 do: [:j |
    q := choose value: { (coords value: 1 value: 8 value: 100 + j) first. (choose value: elements) at: 'vec'.
      (ints value: 1 value: 8 value: 200 + j) first }.
    k := choose value: #(1 2 5 17 400).
    thr := choose value: (thresholds at: metric).
    { near value: q value: k value: nil value: nil. near value: q value: nil value: thr value: nil.
      near value: q value: k value: thr value: nil } do: [:aTerm |
      got := answer value: index value: aTerm.
      got = (oracle value: index value: elements value: aTerm) ifFalse: [
        fails add: metric , ' query ' , j printString , ' ' , aTerm describe printString]]]].
c that: 'the exact backend answers what the brute force answers, for every metric, k and threshold' is: fails asArray equals: #().

"test_exact_backend_equals_brute_force_at_extreme_magnitudes: positive small multiples of a tiny
 or a huge scale (many near-equal cosines; products near the subnormal and the overflow ranges),
 40 records, 4 queries with k, and k with a threshold, per metric and scale."
fails := OrderedCollection new.
scales := #(1.0e-161 1.0e-155 1.0e-140 1.0e140 1.0e152).
#('cosine' 'l2' 'ip') do: [:metric |
  scales do: [:scale | | mk |
    mk := [tup value: ((1 to: 4) asArray collect: [:j | (choose value: #(1 2 3 5 7)) * scale])].
    elements := (1 to: 40) asArray collect: [:i | rec value: i value: mk value].
    index := (vi value: 4 value: metric) build: elements.
    ((index explain) at: 'vectors') = 40 ifFalse: [fails add: metric , ' ' , scale printString , ': vectors'].
    1 to: 4 do: [:j |
      q := choose value: { mk value. (choose value: elements) at: 'vec' }.
      { near value: q value: (choose value: #(1 3 10)) value: nil value: nil.
        near value: q value: 5 value: (metric = 'cosine' ifTrue: [0.5] ifFalse: [metric = 'ip' ifTrue: [-1.0] ifFalse: [10 * scale]])
          value: nil } do: [:aTerm |
        (answer value: index value: aTerm) = (oracle value: index value: elements value: aTerm) ifFalse: [
          fails add: metric , ' ' , scale printString , ' ' , aTerm describe printString]]]]].
c that: 'the exact backend answers what the brute force answers at extreme magnitudes' is: fails asArray equals: #().

"test_results_are_nearest_first_and_ties_follow_the_member_key: a and b tie; the one with the
 smaller member key (an atom's: its identity) comes first, every time; c is third."
fails := OrderedCollection new.
a := PBObject withAll: { 'vec' -> (tup value: #(1.0 0.0)) }.
b := PBObject withAll: { 'vec' -> (tup value: #(1.0 0.0)) }.
cc := PBObject withAll: { 'vec' -> (tup value: #(0.0 1.0)) }.
index := (vi value: 2 value: 'l2') build: { cc. b. a }.
first := (PBKeys orderKey: (PBMemberKeys memberKeyOf: a)) <= (PBKeys orderKey: (PBMemberKeys memberKeyOf: b))
  ifTrue: [a] ifFalse: [b].
expect value: 'k = 1 takes the smaller member key' value: ((index plan: (near value: #(1.0 0.0) value: 1 value: nil value: nil)) execute first == first)
  value: true.
expect value: 'in any build order, every time' value: ({ { a. b. cc }. { b. a. cc }. { cc. a. b }. { b. cc. a } } collect: [:order |
    (((vi value: 2 value: 'l2') build: order) plan: (near value: #(1.0 0.0) value: 1 value: nil value: nil)) execute first == first])
  value: #(true true true true).
expect value: 'c is third' value: ((index plan: (near value: #(1.0 0.0) value: 3 value: nil value: nil)) execute at: 3) == cc value: true.
c that: 'results come nearest first and ties follow the member key' is: fails asArray equals: #().

"test_duplicates_are_counted_and_equal_values_come_back_exactly: on the element key spec, (1.0, 0.0)
 held twice is one member of count 2 and comes back twice; (Decimal 1, 0) is an equal vector but
 another member (its exact token differs), and comes back as itself."
fails := OrderedCollection new.
spec := PBKeySpec element.
one := tup value: #(1.0 0.0).
oneD := tup value: { Decimal fromString: '1'. 0 }.
elements := { one. one. tup value: #(0.0 1.0). oneD }.
index := (PBVectorIndex name: 'v' keySpec: spec dim: 2 metric: 'l2') build: elements.
term := PBTerm path: nil op: 'near[]' value: (PBNearQuery vector: #(1.0 0.0) k: 1).
got := (index plan: term) execute.
expect value: 'k = 1: one member, all its occurrences' value: { got size between: 1 and: 2.
    ids value: got }
  value: { true. ids value: (PBVectorIndex nearOracle: elements keySpec: spec query: term value metric: 'l2' predicate: nil) }.
got := (index plan: (PBTerm path: nil op: 'near[]' value: (PBNearQuery vector: #(1.0 0.0) k: 2))) execute.
expect value: 'k = 2: both members, as stored' value: (ids value: got) asSortedCollection asArray
  value: (ids value: { one. one. oneD }) asSortedCollection asArray.
expect value: 'one and the Decimal one are two members' value: index memberCount value: 3.
c that: 'duplicates are counted and equal values come back exactly' is: fails asArray equals: #().

"test_invalid_vectors_are_kept_aside_and_never_returned: elements without a vector of two finite
 numbers are counted by explain, never returned, and accounted for by validate:."
fails := OrderedCollection new.
good := { PBObject withAll: { 'vec' -> (tup value: #(1.0 0.0)) }. PBObject withAll: { 'vec' -> #(0.0 1.0) } }.
bad := { PBObject new. PBObject withAll: { 'vec' -> nil }. PBObject withAll: { 'vec' -> (tup value: #(1.0)) }.
  PBObject withAll: { 'vec' -> (tup value: { 1.0. Float nan }) }. PBObject withAll: { 'vec' -> (tup value: #(true 0.0)) }.
  PBObject withAll: { 'vec' -> 'ab' }. PBObject withAll: { 'vec' -> (tup value: #(1.0e200 1.0e200)) }.
  PBObject withAll: { 'vec' -> (tup value: { Float infinity. 0.0 }) } }.
index := (vi value: 2 value: 'l2') build: good , bad.
info := index explain.
expect value: 'explain counts them' value: { info at: 'entries'. info at: 'vectors'. info at: 'invalid' } value: #(10 2 8).
expect value: 'never returned' value: (answer value: index value: (near value: #(0.0 0.0) value: 20 value: nil value: nil)) asSortedCollection asArray
  value: (ids value: good) asSortedCollection asArray.
expect value: 'never returned by a threshold either' value: (index plan: (near value: #(0.0 0.0) value: nil value: 1.0e300 value: nil)) execute size
  value: 2.
expect value: 'validate: accounts for them' value: (index validate: good , bad) == index value: true.
expect value: 'validate: misses none' value: (refused value: [index validate: good]) value: PBCorruptionError.
expect value: 'one removed' value: ((index withRemoved: (bad at: 3)) validate: good , (bad copyFrom: 1 to: 2) , (bad copyFrom: 4 to: 8)) notNil
  value: true.
c that: 'invalid vectors are kept aside and never returned' is: fails asArray equals: #().

c report displayNl.
