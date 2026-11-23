"-- vectors.st: the vector math kernel, Python's random sample and near queries --

The numbers under vector indexes (Addendum V, docs/superpowers/specs/2026-11-19-vectors-addendum.md,
sections 2.2 and 2.5), computed exactly as proto_db v2.0.0rc4 computes them in
proto_db/indexing/vector_backends.py with CPython 3.14, so that answers, list numbers and centroids
are the same bits (format spec, 'Vector indexes': scores are defined with math.fsum and IEEE sqrt).
PBVectorMath and PBPythonRandom are not public API: nothing outside the vector port should depend
on them. PBNearQuery is the public value of a near[] term (terms.st).

  PBVectorMath (class side only)
    floatOf: x                      Python's float(x) of an Integer, a Float or a Decimal: one
                                    rounding; nil for an Integer beyond the Float range (Python's
                                    OverflowError); a signalling-NaN Decimal is PBValidationError
                                    with CPython's text
    canonicalVector: key dim: d     canonical_vector: a PBTuple of d finite Floats, or nil
    fsum: floats                    CPython's math.fsum (Shewchuk, with the half-way correction)
    sumNonNegative: floats          _sum_nonnegative: fsum, an overflowing sum is infinity
    score: metric query: q vector: v      exact_score ('cosine', 'l2', 'ip')
    scorerFor: metric query: q      a block answering score: metric query: q vector: v for each v,
                                    its per-query work done once (rank: and the IVF loops use it)
    scoreFloor: metric threshold: t       score_floor
    rank: entries query: q metric: m k: k threshold: t
                                    rank_entries: entries {memberKey. element. count. vector};
                                    answers {element. count} pairs, nearest first, ties by the
                                    member key's order key
    normalized: v                   _normalized (an Array of Floats)
    trainingOrderOf: v              _training_order: the vector's big-endian IEEE bytes, read as
                                    one unsigned Integer (equal sizes: Integer order is byte order)
    kmeans: vectors nlist: n iterations: i seed: s
                                    _kmeans, its pure-Python path (an Array of n centroids, each an
                                    Array of Floats)
    usesPrimitives                  whether the kernel calls protoST's Float fsum:,
                                    fsumOfProducts:with:, fsumOfSquaredDifferences:with: and
                                    fsumOfPowSquaredDifferences:with:: true, unless a test forced
                                    the Smalltalk kernel (_forceSmalltalkKernel:, tests only)

  PBPythonRandom (class side only)
    sampleRange: n count: k seed: s     random.Random(s).sample(range(n), k), an Array of Integers
    bits: k count: m seed: s            the first m values of random.Random(s).getrandbits(k)

  PBNearQuery (public; vectors phase V2)
    vector: v k: k threshold: t metric: m      proto_db's NearQuery (terms.py:98-125): v a
                                    non-empty sequence of finite numbers, stored as a PBTuple of
                                    Floats (floatOf:); k an Integer >= 1 or nil; t a finite number
                                    (a Float) or nil, not both nil; m 'cosine', 'l2', 'ip' or nil
                                    (the index's metric). Also vector:k:, vector:threshold:,
                                    vector:k:threshold: (a mapping of its fields is converted by
                                    PBTerm, terms.st, as terms.py _near_query). Equal and hashed by
                                    value, 0.0 = -0.0; describe is terms.py's display_value of it

  PBVectorBackend, PBVectorExact, PBVectorIvfFlat, PBVectorHnsw (class side only; vectors phase V3)
    named: aString                  backend_for: the backend class, or PBValidationError
    backendName, kindName, defaults the backend's name, its plan kind ('VectorExact'...) and its
                                    parameters with their defaults
    check: aDictionary              the backend's parameter checks, in proto_db's order, answering
                                    the completed parameters (Associations)
    normalize: params backend: name normalize_params: the PBTuple of (name, value) PBTuples a
                                    vector index stores, sorted by name in code-point order
    listFor: index vector: v, needsTraining: index, train: index vectors: vs, explainOf: index
                                    the list of a vector (0 for exact and hnsw; for ivf_flat the
                                    nearest centroid's number, -1 untrained), the retrain test,
                                    the centroids (vectors phase V4), the backend's explain entries
    PBVectorIvfFlat probeOrder: index query: q
                                    _probe_order: -1, then the lists by descending centroid score
    search: index query: q k: k threshold: t eligible: aBlockOrNil
                                    the { element. count } pairs answering a near[] query (vectors
                                    phase V6): exact ranks every accepted member; ivf_flat probes
                                    the best nprobe non-empty lists, widening for k; hnsw is
                                    PBNotSupportedError (ruling VQ1, DV1)
    estimate: index k: k threshold: t filtered: aBoolean
                                    the backend's PBEstimate, in Python's arithmetic (S30)
    Values quoted in refusals are rendered as Python's repr (PBCodec _pyRepr:).
    The index (PBVectorIndex, indexes.st) holds every value; the backends are stateless and this
    module never imports indexes.st.

Floats. protoST's Float + - * / are one IEEE double operation each, sqrt is std::sqrt and
Float raisedTo: an Integer is libm pow (Addendum V, 2.2.3); no build flag contracts or
reassociates them (tests/unit/vec_math.st's IEEE self-test pins it). Three squares, three
spellings, each where proto_db has it: the scores and the norms multiply (x * x), the k-means
distance is Python's (a - b) ** 2, which is libm pow (vector_backends.py:548) and not always the
correctly rounded square; squared, which is x * x in protoST, is never used.

The fsum primitives (Addendum V, 2.2.4; task VP-adopt). protoST 0.15.0's Float fsum:,
fsumOfProducts:with: and fsumOfSquaredDifferences:with: are CPython's math_fsum in C++, checked
against CPython's vectors in protoST and against this module's in tests/conformance/vector_math.st.
The protoST floor, 0.16.1, has them, so the kernel always calls them (feature probes chose them
while the floor was 0.14.1; on 0.16.1 they could choose nothing else and are gone). The primitives
serve fsum:,
sumNonNegative: and the scores (the products and the squared differences, each rounded as the
Smalltalk kernel rounds them, and cosine's norms), normalized: and canonicalVector:dim:'s norm;
k-means squares with raisedTo: 2 (libm pow) and sums with sumNonNegative:; protoST 0.16.0's
Float fsumOfPowSquaredDifferences:with: computes that whole distance, the same bytes, and k-means
calls it. The Smalltalk kernel stays as the primitives' oracle (the tests run every case on both
paths, _forceSmalltalkKernel:), and answers wherever a primitive cannot: an Integer term (the primitive takes Floats only; the
Smalltalk kernel's answer is kept), and sequences of unequal sizes in a score (zip). The
primitive's own errors (Error, 'fsum: intermediate overflow' and 'fsum: -inf + inf') are matched by
their text around the primitive call only and become the kernel's: PBValidationError with
CPython's text, or infinity in sumNonNegative:; any other error passes. A NaN made inside a term
(inf * 0, inf - inf) has a platform-defined sign on either path; no case reaches it from canonical
vectors, and no test pins its bytes.

Errors. Where CPython raises an error of its own (fsum's OverflowError and ValueError, float()'s
ValueError on a signalling NaN), the port signals PBValidationError with CPython's text (deviation
DV7: only the class differs).

State. The generator's state (624 words and an index) is an Array local to one call of
sampleRange:count:seed: or bits:count:seed:, passed to the private methods that draw from it; it is
never kept in a class or instance variable. The kernel's one class variable is set once when the
module loads: SmalltalkForced, an Atom whose value only the tests change (_forceSmalltalkKernel:)."

Import from: 'protobase/errors'.
Import from: 'protobase/floor'.
Import from: 'protobase/keys'.
Import from: 'protobase/values'.
Import from: 'protobase/codec'.
Import from: 'protobase/keyspec'.
Import from: 'decimal'.

Object subclass: #PBVectorMath classVariableNames: 'SmalltalkForced'.
PBVectorMath comment: 'The vector math kernel of the vector indexes (class side only): CPython''s float(), math.fsum and proto_db v2.0.0rc4''s scores, ranking and pure-Python k-means, bit for bit; protoST 0.15.0''s Float fsum primitives and 0.16.0''s k-means distance primitive, which the protoST floor (0.16.1, checked when the package loads: PBFloor) always has, the Smalltalk kernel as their oracle. Not public API.'.

Object subclass: #PBNearQuery instanceVariableNames: 'vector k threshold metric'.
PBNearQuery comment: 'proto_db''s NearQuery: the frozen value of a near[] term, a query vector of finite Floats with k nearest members and/or a threshold, and a metric or nil.'.

Object subclass: #PBPythonRandom.
PBPythonRandom comment: 'CPython 3.14''s random.Random (MT19937, its integer seeding, getrandbits, _randbelow and sample), for the initial centroids of proto_db''s k-means. Class side only; the state is local to each call. Not public API.'.

"=== PBVectorMath: numbers =================================================="

"Python's float(aNumber) (vector_backends.py:111, canonical_vector; Addendum V, 2.2.2), for an
 Integer, a Float or a Decimal; one rounding, as in Python.
   Float: itself.
   Integer: asFloat, correctly rounded (a value within 64 bits is cast to double, a larger one goes
     through strtod on its exact digits); beyond the Float range that is infinity, which is exactly
     where Python's float(int) raises OverflowError: nil (the caller's overflow case).
   Decimal: CPython's PyDec_AsFloat is float(str(d)), one correctly rounded conversion of the exact
     value: a zero coefficient is 0.0 or -0.0 by its sign; any other finite value is String >>
     asNumber of '[-]<coefficient>e<exponent>' (the same value as str(d), always in the Float
     syntax), which is correctly rounded and subnormal-aware, infinity beyond the range and a
     signed zero below half the smallest subnormal, as Python's float(str). A quiet NaN is float('nan')
     or float('-nan') by its sign (CPython's bits, 0x7FF8... and 0xFFF8...), an infinity keeps its
     sign, a signalling NaN is PBValidationError, 'cannot convert signaling NaN to float' (CPython's
     ValueError, DV7).
 Anything else is PBValidationError (the callers refuse Booleans and other classes first)."
PBVectorMath class >> floatOf: aNumber
  | f |
  aNumber isFloat ifTrue: [^ aNumber].
  aNumber isInteger ifTrue: [
    f := aNumber asFloat.
    ^ (self _isFinite: f) ifTrue: [f] ifFalse: [nil]].
  (aNumber isClassObject not and: [aNumber isKindOf: Decimal]) ifTrue: [^ self _floatOfDecimal: aNumber].
  ^ PBValidationError signal: 'PBVectorMath floatOf: an Integer, a Float or a Decimal was expected, not a '
    , aNumber class name.

PBVectorMath class >> _floatOfDecimal: aDecimal
  | text f |
  aDecimal isSignaling ifTrue: [^ PBValidationError signal: 'cannot convert signaling NaN to float'].
  aDecimal isNaN ifTrue: [
    ^ self _floatFromBits: (aDecimal sign = 1 ifTrue: [16rFFF8000000000000] ifFalse: [16r7FF8000000000000])].
  aDecimal isInfinite ifTrue: [
    ^ aDecimal sign = 1 ifTrue: [Float infinity negated] ifFalse: [Float infinity]].
  aDecimal coefficient = 0 ifTrue: [^ aDecimal sign = 1 ifTrue: [-0.0] ifFalse: [0.0]].
  text := (aDecimal sign = 1 ifTrue: ['-'] ifFalse: ['']) , aDecimal coefficient printString
    , 'e' , aDecimal exponent printString.
  f := text asNumber.
  f isFloat ifFalse: [
    ^ PBValidationError signal: 'PBVectorMath floatOf: String >> asNumber did not read a Float from the Decimal '
      , aDecimal printString].
  ^ f.

"The Float whose IEEE 754 binary64 bits are anInteger (0 to 2^64 - 1)."
PBVectorMath class >> _floatFromBits: anInteger
  | w |
  w := WriteStream on: ByteArray new.
  w nextPutUnsigned: anInteger width: 8 bigEndian: true.
  ^ w contents float64At: 1 bigEndian: true.

"Python's math.isfinite of a Float: x - x is 0.0 for a finite x and NaN for an infinity or a NaN."
PBVectorMath class >> _isFinite: aFloat
  ^ aFloat - aFloat = 0.0.

"Whether canonical_vector accepts aValue as a component: an Integer, a Float or a Decimal, not a
 Boolean (vector_backends.py:110)."
PBVectorMath class >> _isComponent: aValue
  aValue isClassObject ifTrue: [^ false].
  ^ aValue isInteger or: [aValue isFloat or: [aValue isKindOf: Decimal]].

"canonical_vector (vector_backends.py:100-122): aKey as a PBTuple of anInteger Floats, or nil when
 it is not a valid vector. Valid: a tuple or a list (PBTuple, PBFrozenList) of exactly anInteger
 numbers (Integer, Float, Decimal; not Boolean), every one finite as a Float, with a finite squared
 norm (fsum of x * x, an overflow being infinity). Components are read in order, so a signalling-NaN
 Decimal signals PBValidationError (floatOf:) unless an earlier component already made the key
 invalid, as in Python."
PBVectorMath class >> canonicalVector: aKey dim: anInteger
  | out |
  (aKey isClassObject not and: [(aKey isKindOf: PBTuple) or: [aKey isKindOf: PBFrozenList]]) ifFalse: [^ nil].
  aKey size = anInteger ifFalse: [^ nil].
  out := Array new: anInteger.
  1 to: anInteger do: [:i | | x f |
    x := aKey at: i.
    (self _isComponent: x) ifFalse: [^ nil].
    f := self floatOf: x.
    (f isNil or: [(self _isFinite: f) not]) ifTrue: [^ nil].
    out at: i put: f].
  (self _isFinite: (self _fsumOfProducts: out with: out size: anInteger overflow: [Float infinity])) ifFalse: [^ nil].
  ^ PBTuple _trustedOn: out.

"=== PBVectorMath: the fsum primitives and the test-only switch ============"

"protoST 0.16.1 is the floor (checked when the package loads: PBFloor), so Float fsum:, fsumOfProducts:with: and
 fsumOfSquaredDifferences:with: (protoST 0.15.0) and Float fsumOfPowSquaredDifferences:with: (0.16.0)
 always exist; the feature probes that chose them while the floor was 0.14.1 could no longer choose
 anything else and are gone. Made once when the module loads: the Atom of the test-only switch,
 false."
PBVectorMath class >> _initializeKernel
  SmalltalkForced isNil ifTrue: [SmalltalkForced := Atom on: false].

"Whether the kernel calls protoST's primitives (the fsum family and the k-means distance): true
 unless a test forced the Smalltalk kernel, which stays as their oracle."
PBVectorMath class >> usesPrimitives
  ^ SmalltalkForced value not.

"For the tests only: aBoolean true makes the kernel compute with its Smalltalk code even where
 the primitives exist, false restores the primitives; both paths can so be checked in one
 process (tests/unit/vec_math.st, tests/conformance/vector_math.st). Never called by protoBaseST."
PBVectorMath class >> _forceSmalltalkKernel: aBoolean
  [ | current |
    current := SmalltalkForced value.
    SmalltalkForced value: aBoolean == true ifCurrent: current ] whileFalse.

"The Float aPrimitiveBlock answers (a call of one fsum primitive), with the primitive's own errors
 made the kernel's: an intermediate overflow is the value of anOverflowBlock, '-inf + inf' is
 PBValidationError with CPython's text, and a term that is not a Float (an Integer, which the
 Smalltalk kernel sums as it always has) answers aSmalltalkBlock's value. Only those errors, raised
 by the primitive itself, are caught, by their text; any other error passes."
PBVectorMath class >> _primitive: aPrimitiveBlock overflow: anOverflowBlock otherwise: aSmalltalkBlock
  | outcome |
  outcome := aPrimitiveBlock on: Error do: [:e | | kind |
    kind := self _fsumFailure: e messageText.
    kind isNil ifTrue: [e pass].
    e return: kind].
  outcome == #overflow ifTrue: [^ anOverflowBlock value].
  outcome == #infinities ifTrue: [^ PBValidationError signal: '-inf + inf in fsum'].
  outcome == #notFloat ifTrue: [^ aSmalltalkBlock value].
  ^ outcome.

"Which of the fsum primitives' errors aText is (protoST src/primitives/fsum_prims.cpp): #overflow,
 #infinities, #notFloat (an element that is not a Float), or nil for any other text."
PBVectorMath class >> _fsumFailure: aText
  (aText isString and: [aText beginsWith: 'fsum']) ifFalse: [^ nil].
  aText = 'fsum: intermediate overflow' ifTrue: [^ #overflow].
  aText = 'fsum: -inf + inf' ifTrue: [^ #infinities].
  (aText endsWith: ' is not a Float') ifTrue: [^ #notFloat].
  ^ nil.

"fsum of aSequence (anOverflowBlock's value on an intermediate overflow): the primitive Float
 fsum: when the kernel uses it, the Smalltalk kernel otherwise."
PBVectorMath class >> _fsum: aSequence overflow: anOverflowBlock
  self usesPrimitives ifFalse: [^ self _smalltalkFsum: aSequence overflow: anOverflowBlock].
  ^ self _primitive: [Float fsum: aSequence] overflow: anOverflowBlock
    otherwise: [self _smalltalkFsum: aSequence overflow: anOverflowBlock].

"aSequence as the fsum primitives read it fastest: itself when it is an Array or an
 OrderedCollection, or when the kernel does not use the primitives; a fresh Array of its items
 otherwise (a PBTuple or a PBFrozenList, which the primitives would read through size and at:).
 The answer is never changed. Callers that score one query against many vectors do it through
 scorerFor:query:, which converts the query once with it; each score then copies only the stored
 vector."
PBVectorMath class >> _primitiveOperand: aSequence
  self usesPrimitives ifFalse: [^ aSequence].
  ((aSequence isKindOf: Array) or: [aSequence isKindOf: OrderedCollection]) ifTrue: [^ aSequence].
  ^ aSequence asArray.

"fsum of (a at: i) * (b at: i) for i from 1 to anInteger (Python's zip of the two): one IEEE
 product each, then fsum. The primitive fsumOfProducts:with: when both sequences hold exactly
 anInteger items, the products made here otherwise."
PBVectorMath class >> _fsumOfProducts: a with: b size: anInteger overflow: anOverflowBlock
  | products |
  products := [(1 to: anInteger) asArray collect: [:i | (a at: i) * (b at: i)]].
  (self usesPrimitives and: [a size = anInteger and: [b size = anInteger]]) ifFalse: [
    ^ self _fsum: products value overflow: anOverflowBlock].
  ^ self _primitive: [Float fsumOfProducts: a with: b] overflow: anOverflowBlock
    otherwise: [self _smalltalkFsum: products value overflow: anOverflowBlock].

"_sum_nonnegative of d * d, d = (a at: i) - (b at: i), for i from 1 to anInteger: the difference
 rounded, then the product, then fsum, an overflow being infinity. The primitive
 fsumOfSquaredDifferences:with: when both sequences hold exactly anInteger items."
PBVectorMath class >> _sumSquaredDifferences: a with: b size: anInteger
  | squares |
  squares := [(1 to: anInteger) asArray collect: [:i | | d | d := (a at: i) - (b at: i). d * d]].
  (self usesPrimitives and: [a size = anInteger and: [b size = anInteger]]) ifFalse: [
    ^ self sumNonNegative: squares value].
  ^ self _primitive: [Float fsumOfSquaredDifferences: a with: b] overflow: [Float infinity]
    otherwise: [self _smalltalkFsum: squares value overflow: [Float infinity]].

"=== PBVectorMath: fsum ====================================================="

"CPython's math.fsum of aSequence of Floats (Modules/mathmodule.c, math_fsum, 3.14), line for line:
 Shewchuk's exact partials, then the sum of the partials from the top, stopped when it becomes
 inexact, with the final half-way correction (so sum([1e-16, 1, 1e16]) rounds as the exact sum
 does). Special values: an infinite or NaN term resets the partials and accumulates into a special
 sum, which is the answer (a NaN term makes it NaN); +infinity and -infinity together signal
 PBValidationError '-inf + inf in fsum' (CPython's ValueError); a non-finite partial from finite
 terms signals PBValidationError 'intermediate overflow in fsum' (CPython's OverflowError). DV7."
PBVectorMath class >> fsum: aSequence
  ^ self _fsum: aSequence overflow: [self _overflow].

"CPython's OverflowError of math.fsum, as PBValidationError (DV7)."
PBVectorMath class >> _overflow
  ^ PBValidationError signal: 'intermediate overflow in fsum'.

"_sum_nonnegative (vector_backends.py:92-97): fsum of non-negative terms; an intermediate overflow
 is infinity, its true value."
PBVectorMath class >> sumNonNegative: aSequence
  ^ self _fsum: aSequence overflow: [Float infinity].

"math_fsum in Smalltalk, answering the value of anOverflowBlock where CPython raises OverflowError:
 the kernel's reference implementation and the fsum primitives' oracle (_forceSmalltalkKernel:), and
 the sum of the terms the primitives do not take (an Integer term, see _primitive:overflow:otherwise:)."
PBVectorMath class >> _smalltalkFsum: aSequence overflow: anOverflowBlock
  | p n count x y t hi yr lo xsave specialSum infSum done |
  count := aSequence size.
  p := Array new: count + 1.
  n := 0.
  specialSum := 0.0.
  infSum := 0.0.
  lo := 0.0.
  1 to: count do: [:k | | i |
    x := aSequence at: k.
    xsave := x.
    i := 0.
    1 to: n do: [:j |
      y := p at: j.
      x abs < y abs ifTrue: [t := x. x := y. y := t].
      hi := x + y.
      yr := hi - x.
      lo := y - yr.
      lo = 0.0 ifFalse: [i := i + 1. p at: i put: lo].
      x := hi].
    n := i.
    x = 0.0 ifFalse: [
      (self _isFinite: x)
        ifTrue: [n := n + 1. p at: n put: x]
        ifFalse: [
          "A non-finite x comes from an intermediate overflow or from a NaN or an infinity among
           the terms."
          (self _isFinite: xsave) ifTrue: [^ anOverflowBlock value].
          xsave isInfinite ifTrue: [infSum := infSum + xsave].
          specialSum := specialSum + xsave.
          n := 0]]].
  specialSum = 0.0 ifFalse: [
    ^ infSum isNaN
      ifTrue: [PBValidationError signal: '-inf + inf in fsum']
      ifFalse: [specialSum]].
  hi := 0.0.
  n > 0 ifTrue: [
    hi := p at: n.
    n := n - 1.
    "Sum the partials from the top; stop when the sum becomes inexact."
    done := false.
    [done not and: [n > 0]] whileTrue: [
      x := hi.
      y := p at: n.
      n := n - 1.
      hi := x + y.
      yr := hi - x.
      lo := y - yr.
      lo = 0.0 ifFalse: [done := true]].
    "Make half-even rounding work across multiple partials."
    (n > 0 and: [(lo < 0.0 and: [(p at: n) < 0.0]) or: [lo > 0.0 and: [(p at: n) > 0.0]]]) ifTrue: [
      y := lo * 2.0.
      x := hi + y.
      yr := x - hi.
      y = yr ifTrue: [hi := x]]].
  ^ hi.

"=== PBVectorMath: scores and ranking ========================================"

"exact_score (vector_backends.py:125-137), operation for operation; higher is nearer.
   ip:     fsum of a * b.
   l2:     minus the sqrt of _sum_nonnegative of (a - b) * (a - b), the difference rounded first.
   cosine: (fsum(a * b) / |q|) / |v|, each norm the sqrt of fsum of x * x; 0.0 when either is zero.
 Pairs as Python's zip (the shorter sequence ends it). ip and the cosine's sums are not guarded in
 proto_db: an exact sum that overflows is PBValidationError (Python's OverflowError, DV7). An
 unknown metric is PBValidationError with proto_db's text. With the fsum primitives, a PBTuple or
 PBFrozenList operand is first copied to an Array (_primitiveOperand:), which the primitives read
 directly: measured 1.2 to 5.3 times faster per score than their generic size/at: path, the copy
 included (docs/deviations.md, Performance, Vectors)."
PBVectorMath class >> score: aMetric query: aQuery vector: aVector
  | q v n nq nv |
  q := self _primitiveOperand: aQuery.
  v := self _primitiveOperand: aVector.
  n := q size min: v size.
  aMetric = 'ip' ifTrue: [^ self _fsumOfProducts: q with: v size: n overflow: [self _overflow]].
  aMetric = 'l2' ifTrue: [^ (self _sumSquaredDifferences: q with: v size: n) sqrt negated].
  aMetric = 'cosine' ifTrue: [
    nq := (self _fsumOfProducts: q with: q size: q size overflow: [self _overflow]) sqrt.
    nv := (self _fsumOfProducts: v with: v size: v size overflow: [self _overflow]) sqrt.
    (nq = 0.0 or: [nv = 0.0]) ifTrue: [^ 0.0].
    ^ (self _fsumOfProducts: q with: v size: n overflow: [self _overflow]) / nq / nv].
  ^ PBValidationError signal: 'Unknown metric ' , (PBCodec repr: aMetric)
    , '; expected one of [''cosine'', ''l2'', ''ip'']'.

"A one-argument block answering, for a vector, what score: aMetric query: aQuery vector: answers
 (the same bytes and the same refusals, at the same score), for callers that score one query
 against many vectors: rank:, and PBVectorIvfFlat's probe loop, listFor:vector: and
 probeOrder:query:. Once per query instead of once per score: the metric dispatch, the query's
 copy to an Array (_primitiveOperand:) and, for cosine, the query's norm. proto_db's exact_score
 recomputes sqrt(fsum(a * a for a in q)) at every score; it is a pure function of q, so it is
 computed at the first score and reused, and a refusal it raises is raised at that first score,
 as proto_db raises it, never when the scorer is made nor without a score. With the primitives and
 operands of one size, a score calls them directly under one handler (where score:query:vector:
 wraps each call in its own, _primitive:overflow:otherwise:); any fsum failure, and operands of
 unequal sizes, fall back to score:query:vector:, which answers or raises as proto_db does. The
 sums, their order, sqrt and (dot / nq) / nv are score:query:vector:'s."
PBVectorMath class >> scorerFor: aMetric query: aQuery
  | q nq |
  q := self _primitiveOperand: aQuery.
  self usesPrimitives ifFalse: [
    aMetric = 'cosine' ifFalse: [^ [:aVector | self score: aMetric query: q vector: aVector]].
    ^ [:aVector | | n nv |
      n := q size min: aVector size.
      nq isNil ifTrue: [nq := (self _fsumOfProducts: q with: q size: q size overflow: [self _overflow]) sqrt].
      nv := (self _fsumOfProducts: aVector with: aVector size: aVector size overflow: [self _overflow]) sqrt.
      (nq = 0.0 or: [nv = 0.0])
        ifTrue: [0.0]
        ifFalse: [(self _fsumOfProducts: q with: aVector size: n overflow: [self _overflow]) / nq / nv]]].
  aMetric = 'ip' ifTrue: [
    ^ [:aVector | | v r |
      v := self _primitiveOperand: aVector.
      r := q size = v size ifTrue: [self _unlessFsumFails: [Float fsumOfProducts: q with: v]].
      r isNil ifTrue: [self score: aMetric query: q vector: v] ifFalse: [r]]].
  aMetric = 'l2' ifTrue: [
    ^ [:aVector | | v r |
      v := self _primitiveOperand: aVector.
      r := q size = v size ifTrue: [self _unlessFsumFails: [(Float fsumOfSquaredDifferences: q with: v) sqrt negated]].
      r isNil ifTrue: [self score: aMetric query: q vector: v] ifFalse: [r]]].
  aMetric = 'cosine' ifFalse: [^ [:aVector | self score: aMetric query: q vector: aVector]].
  ^ [:aVector | | v r |
    v := self _primitiveOperand: aVector.
    r := q size = v size ifTrue: [
      self _unlessFsumFails: [ | nv |
        nq isNil ifTrue: [nq := (Float fsumOfProducts: q with: q) sqrt].
        nv := (Float fsumOfProducts: v with: v) sqrt.
        (nq = 0.0 or: [nv = 0.0])
          ifTrue: [0.0]
          ifFalse: [(Float fsumOfProducts: q with: v) / nq / nv]]].
    r isNil ifTrue: [self score: aMetric query: q vector: v] ifFalse: [r]].

"The value of aBlock (calls of the fsum primitives), or nil when one of them raises one of its own
 errors (_fsumFailure:): the caller then computes the score with score:query:vector:, which turns
 that error into the kernel's answer or refusal. Any other error passes."
PBVectorMath class >> _unlessFsumFails: aBlock
  ^ aBlock on: Error do: [:e |
    (self _fsumFailure: e messageText) isNil ifTrue: [e pass].
    e return: nil].

"score_floor (vector_backends.py:140-144): the least score aThreshold admits (l2: minus the
 distance), or nil without a threshold."
PBVectorMath class >> scoreFloor: aMetric threshold: aThreshold
  aThreshold isNil ifTrue: [^ nil].
  ^ aMetric = 'l2' ifTrue: [aThreshold negated] ifFalse: [aThreshold].

"rank_entries (vector_backends.py:147-167): the {element. count} pairs of the best anInteger
 entries (all of them when nil; cut as Python's del scored[k:], so 0 keeps none and a negative k
 drops that many from the end) that pass aThreshold, nearest first. anEntries holds
 {memberKey. element. count. vector}, optionally a fifth item, the member key's order key when the
 caller holds it already (a store node caches it). The sort key is Python's (-score,
 order_key(memberKey)): ties, -0.0 and 0.0 included, go to the smaller order key (PBKeys
 orderKey:)."
PBVectorMath class >> rank: anEntries query: q metric: aMetric k: anInteger threshold: aThreshold
  | floor scored sorted query |
  floor := self scoreFloor: aMetric threshold: aThreshold.
  "The metric dispatch, the query's copy and its cosine norm once per ranking, not once per entry."
  query := self scorerFor: aMetric query: q.
  scored := OrderedCollection new.
  anEntries do: [:entry | | s |
    s := query value: (entry at: 4).
    (floor notNil and: [(s >= floor) not]) ifFalse: [
      scored add: {s negated. entry size > 4 ifTrue: [entry at: 5] ifFalse: [PBKeys orderKey: (entry at: 1)]. entry at: 2. entry at: 3}]].
  sorted := scored asArray sort: [:a :b |
    (a at: 1) < (b at: 1) or: [(a at: 1) = (b at: 1) and: [(a at: 2) <= (b at: 2)]]].
  anInteger isNil ifFalse: [sorted := sorted copyFrom: 1 to: (self _sliceEnd: anInteger size: sorted size)].
  ^ sorted collect: [:each | {each at: 3. each at: 4}].

"How many items Python's del aList[anInteger:] keeps of aSize: the slice start anInteger, a negative
 one counted from the end (aSize + anInteger), clamped to 0..aSize (CPython's PySlice_AdjustIndices).
 So k = 0 keeps nothing, k = -1 drops the last item, and a k beyond either end keeps all or nothing."
PBVectorMath class >> _sliceEnd: anInteger size: aSize
  ^ anInteger < 0
    ifTrue: [aSize + anInteger max: 0]
    ifFalse: [anInteger min: aSize].

"_normalized (vector_backends.py:561-563): aVector divided by its norm (the sqrt of fsum of
 x * x), or aVector itself when the norm is 0.0; an Array of Floats."
PBVectorMath class >> normalized: aVector
  | n items |
  items := aVector asArray.
  n := (self _fsumOfProducts: items with: items size: items size overflow: [self _overflow]) sqrt.
  n = 0.0 ifTrue: [^ items].
  ^ items collect: [:x | x / n].

"_training_order (vector_backends.py:555-558): struct.pack('>Nd', *v), the components' big-endian
 IEEE 754 bytes (so -0.0 and 0.0 differ), read back as one unsigned Integer: every vector of one
 index has the same number of components, so the byte strings have equal lengths and the Integers
 order exactly as Python's bytes do (Addendum V, 2.2.2)."
PBVectorMath class >> trainingOrderOf: aVector
  | w bytes |
  w := WriteStream on: ByteArray new.
  aVector do: [:x | w nextPutFloat64: x bigEndian: true].
  bytes := w contents.
  ^ bytes unsignedIntegerFrom: 1 to: bytes size bigEndian: true.

"=== PBVectorMath: k-means =================================================="

"_kmeans (vector_backends.py:527-552), its pure-Python path (Addendum V, 2.5 step 3; DV3):
 the initial centroids are the vectors at random.Random(seed).sample(range(len(vectors)), nlist),
 sorted; then anIterations Lloyd iterations: each vector goes to the centroid of least
 _sum_nonnegative of (a - b) ** 2 (libm pow: raisedTo: 2), ties to the lowest index; each new
 centroid is the component sums, added in data order with plain IEEE + from 0.0, divided by the
 count (a Float by an Integer below 2^53: one rounding); an empty cluster keeps its centroid.
 aVectors is a sequence of equal-length sequences of Floats; the answer an Array of nlist Arrays.
 Each distance is _kmeansDistance:to:'s, into one squares buffer reused for every distance."
PBVectorMath class >> kmeans: aVectors nlist: anNlist iterations: anIterations seed: aSeed
  | vectors dim centroids sums counts squares |
  "Each vector copied to an Array once (a PBTuple's at: is dearer), one squares buffer for every
   distance, and the sums accumulated in place: the same operations in the same order as a fresh
   buffer and a fresh sum per vector, so the centroids are the same bytes."
  vectors := aVectors asArray collect: [:v | v asArray].
  centroids := ((PBPythonRandom sampleRange: vectors size count: anNlist seed: aSeed) sort: [:a :b | a <= b])
    collect: [:i | (vectors at: i + 1) copy].
  dim := (vectors at: 1) size.
  squares := Array new: dim.
  anIterations timesRepeat: [
    sums := (1 to: anNlist) asArray collect: [:j | Array new: dim withAll: 0.0].
    counts := Array new: anNlist withAll: 0.
    vectors do: [:v | | best bestDistance sum |
      best := nil.
      1 to: anNlist do: [:c | | d |
        d := self _kmeansDistance: v to: (centroids at: c) squares: squares.
        (best isNil or: [d < bestDistance]) ifTrue: [best := c. bestDistance := d]].
      counts at: best put: (counts at: best) + 1.
      sum := sums at: best.
      1 to: dim do: [:i | sum at: i put: (sum at: i) + (v at: i)]].
    centroids := (1 to: anNlist) asArray collect: [:j |
      (counts at: j) = 0
        ifTrue: [centroids at: j]
        ifFalse: [(sums at: j) collect: [:s | s / (counts at: j)]]]].
  ^ centroids.

"_sum_nonnegative((a - b) ** 2 for a, b in zip(v, centroid)) (vector_backends.py:548): CPython's
 float ** 2 is libm pow, raisedTo: 2 here; an overflowing square is infinity in both (CPython's
 OverflowError is caught by _sum_nonnegative), so the distance is the same."
PBVectorMath class >> _kmeansDistance: aVector to: aCentroid
  ^ self _kmeansDistance: aVector to: aCentroid squares: (Array new: (aVector size min: aCentroid size)).

"_kmeansDistance:to: with aBuffer (an Array of the zip's size) for the squares. protoST 0.16.0's
 Float fsumOfPowSquaredDifferences:with: unless the Smalltalk kernel is forced, when both sequences have the
 buffer's size: pow(a - b, 2.0) by libm and the msum of fsum:, the same bytes as raisedTo: 2 and
 sumNonNegative: (protoST docs/LANGUAGE.md, the pow form); an intermediate overflow is infinity, as
 in sumNonNegative:, and a term that is not a Float falls back to the Smalltalk loop. Otherwise the
 Smalltalk loop, the primitive's oracle: each raisedTo: 2 into aBuffer, then sumNonNegative:."
PBVectorMath class >> _kmeansDistance: aVector to: aCentroid squares: aBuffer
  (self usesPrimitives and: [aVector size = aBuffer size and: [aCentroid size = aBuffer size]])
    ifFalse: [^ self _kmeansSquares: aVector to: aCentroid into: aBuffer].
  ^ self _primitive: [Float fsumOfPowSquaredDifferences: aVector with: aCentroid] overflow: [Float infinity]
    otherwise: [self _kmeansSquares: aVector to: aCentroid into: aBuffer].

"The Smalltalk loop of the k-means distance: (a at: i) - (b at: i) raisedTo: 2 into aBuffer for i
 from 1 to its size, then sumNonNegative: of aBuffer."
PBVectorMath class >> _kmeansSquares: aVector to: aCentroid into: aBuffer
  1 to: aBuffer size do: [:i | aBuffer at: i put: ((aVector at: i) - (aCentroid at: i) raisedTo: 2)].
  ^ self sumNonNegative: aBuffer.

"=== PBPythonRandom ========================================================="

"random.Random(aSeed).sample(range(anInteger), aCount) (Lib/random.py, Random.sample, 3.14): an
 Array of aCount distinct Integers from 0 to anInteger - 1. Both of CPython's branches: with
 setsize = 21, plus 4 ** ceil(log(3k, 4)) when k > 5 (math.log(x, base) is log(x) / log(base) with
 libm log, as protoST's log: is), a population of at most setsize draws from a shrinking pool,
 a larger one redraws into a selection set. A count below 0 or above the population is
 PBValidationError with CPython's text. aSeed is an Integer (its absolute value seeds)."
PBPythonRandom class >> sampleRange: anInteger count: aCount seed: aSeed
  | state setsize result pool selected |
  (aCount between: 0 and: anInteger) ifFalse: [
    ^ PBValidationError signal: 'Sample larger than population or is negative'].
  state := self _seeded: aSeed.
  setsize := 21.
  aCount > 5 ifTrue: [setsize := setsize + (4 raisedTo: ((aCount * 3) log: 4) ceiling)].
  result := Array new: aCount.
  anInteger <= setsize
    ifTrue: [
      pool := (0 to: anInteger - 1) asArray.
      1 to: aCount do: [:i | | j |
        j := self _randbelow: anInteger - (i - 1) state: state.
        result at: i put: (pool at: j + 1).
        pool at: j + 1 put: (pool at: anInteger - (i - 1))]]
    ifFalse: [
      selected := Set new.
      1 to: aCount do: [:i | | j |
        j := self _randbelow: anInteger state: state.
        [selected includes: j] whileTrue: [j := self _randbelow: anInteger state: state].
        selected add: j.
        result at: i put: j]].
  ^ result.

"The first aCount values of random.Random(aSeed).getrandbits(aBits), an Array of Integers (a test
 entry point: it pins the generator below sample)."
PBPythonRandom class >> bits: aBits count: aCount seed: aSeed
  | state |
  state := self _seeded: aSeed.
  ^ (1 to: aCount) asArray collect: [:i | self _getrandbits: aBits state: state].

"MT19937's period parameters (Modules/_randommodule.c)."
PBPythonRandom class >> _n
  ^ 624.

PBPythonRandom class >> _m
  ^ 397.

"A fresh state for aSeed (random_seed): an Array of 625 slots, the 624 words mt[0..623] at 1..624
 and the C index (0..624) at 625. The key is the 32-bit words of |aSeed|, least significant first
 (_PyLong_AsByteArray, little-endian); 0 is a key of one zero word (keyused = 1), not an empty one.
 Seeding products reach 2^63, beyond the SmallInteger range: every step is reduced to 32 bits with
 bitAnd: 16rFFFFFFFF, as the C code's uint32_t arithmetic is (slow, once per sample)."
PBPythonRandom class >> _seeded: aSeed
  | key n |
  aSeed isInteger ifFalse: [^ PBValidationError signal: 'PBPythonRandom: the seed must be an Integer, not a '
    , aSeed class name].
  key := OrderedCollection new.
  n := aSeed abs.
  [n > 0] whileTrue: [key add: (n bitAnd: 16rFFFFFFFF). n := n bitShift: -32].
  key isEmpty ifTrue: [key add: 0].
  ^ self _initByArray: key asArray.

"init_genrand(s) into aState (index left at N)."
PBPythonRandom class >> _initGenrand: anInteger into: aState
  | prev |
  aState at: 1 put: anInteger.
  2 to: self _n do: [:i |
    prev := aState at: i - 1.
    aState at: i put: (1812433253 * (prev bitXor: (prev bitShift: -30)) + (i - 1) bitAnd: 16rFFFFFFFF)].
  aState at: self _n + 1 put: self _n.

"init_by_array(init_key, key_length): a fresh state. i and j are the C indices (0-based); the
 state's word mt[i] is at i + 1."
PBPythonRandom class >> _initByArray: aKey
  | state n i j prev |
  n := self _n.
  state := Array new: n + 1.
  self _initGenrand: 19650218 into: state.
  i := 1.
  j := 0.
  (n max: aKey size) timesRepeat: [
    prev := state at: i.
    state at: i + 1
      put: (((state at: i + 1) bitXor: (prev bitXor: (prev bitShift: -30)) * 1664525) + (aKey at: j + 1) + j
        bitAnd: 16rFFFFFFFF).
    i := i + 1.
    j := j + 1.
    i >= n ifTrue: [state at: 1 put: (state at: n). i := 1].
    j >= aKey size ifTrue: [j := 0]].
  n - 1 timesRepeat: [
    prev := state at: i.
    state at: i + 1
      put: (((state at: i + 1) bitXor: (prev bitXor: (prev bitShift: -30)) * 1566083941) - i bitAnd: 16rFFFFFFFF).
    i := i + 1.
    i >= n ifTrue: [state at: 1 put: (state at: n). i := 1]].
  state at: 1 put: 16r80000000.
  ^ state.

"genrand_uint32: the next 32-bit word, twisting all 624 words when the index reaches N, then
 tempered."
PBPythonRandom class >> _next32: aState
  | index y |
  index := aState at: self _n + 1.
  index >= self _n ifTrue: [self _twist: aState. index := 0].
  y := aState at: index + 1.
  aState at: self _n + 1 put: index + 1.
  y := y bitXor: (y bitShift: -11).
  y := y bitXor: ((y bitShift: 7) bitAnd: 16r9D2C5680).
  y := y bitXor: ((y bitShift: 15) bitAnd: 16rEFC60000).
  ^ y bitXor: (y bitShift: -18).

"The generation step of genrand_uint32 (kk is the C index; mt[kk] is at kk + 1)."
PBPythonRandom class >> _twist: aState
  | n m y |
  n := self _n.
  m := self _m.
  0 to: n - 2 do: [:kk |
    y := ((aState at: kk + 1) bitAnd: 16r80000000) bitOr: ((aState at: kk + 2) bitAnd: 16r7FFFFFFF).
    aState at: kk + 1 put: (((aState at: (kk < (n - m) ifTrue: [kk + m] ifFalse: [kk + m - n]) + 1)
      bitXor: (y bitShift: -1)) bitXor: ((y bitAnd: 1) = 0 ifTrue: [0] ifFalse: [16r9908B0DF]))].
  y := ((aState at: n) bitAnd: 16r80000000) bitOr: ((aState at: 1) bitAnd: 16r7FFFFFFF).
  aState at: n put: (((aState at: m) bitXor: (y bitShift: -1))
    bitXor: ((y bitAnd: 1) = 0 ifTrue: [0] ifFalse: [16r9908B0DF])).

"getrandbits(k) (_random_Random_getrandbits_impl): 0 for k = 0; for k <= 32 one word shifted
 right by 32 - k; otherwise ceil(k / 32) words, least significant first, the last one shifted
 right by 32 - (k mod 32) when k is not a multiple of 32. A negative k is PBValidationError with
 CPython's text."
PBPythonRandom class >> _getrandbits: aBits state: aState
  | words result shift remaining r |
  aBits < 0 ifTrue: [^ PBValidationError signal: 'number of bits must be non-negative'].
  aBits = 0 ifTrue: [^ 0].
  aBits <= 32 ifTrue: [^ (self _next32: aState) bitShift: aBits - 32].
  words := aBits - 1 // 32 + 1.
  result := 0.
  shift := 0.
  remaining := aBits.
  words timesRepeat: [
    r := self _next32: aState.
    remaining < 32 ifTrue: [r := r bitShift: remaining - 32].
    result := result + (r bitShift: shift).
    shift := shift + 32.
    remaining := remaining - 32].
  ^ result.

"_randbelow_with_getrandbits(n) (Lib/random.py): k = n.bit_length() (highBit), getrandbits(k)
 redrawn while it is >= n. Defined for n > 0."
PBPythonRandom class >> _randbelow: anInteger state: aState
  | k r |
  k := anInteger highBit.
  r := self _getrandbits: k state: aState.
  [r >= anInteger] whileTrue: [r := self _getrandbits: k state: aState].
  ^ r.

"=== PBNearQuery ============================================================"

"The query aSequence with anIntegerOrNil nearest members and/or within aNumberOrNil, ranked by the
 metric aStringOrNil (nil: the index's own), validated as terms.py NearQuery.__post_init__
 (terms.py:113-125), in its order: the vector (a non-empty Array, OrderedCollection, PBFrozenList
 or PBTuple, Python's list or tuple; every component a finite number, converted to a Float), then
 k and the threshold (at least one; k an Integer >= 1, not a Boolean; the threshold a finite
 number), then the metric. Refusals are PBValidationError with proto_db's text, or with CPython's
 where proto_db fails with one of Python's own errors (deviation DV7; _finiteNumber:what:, and an
 unhashable metric, Python's TypeError from set membership, refused with proto_db's metric text)."
PBNearQuery class >> vector: aSequence k: anIntegerOrNil threshold: aNumberOrNil metric: aStringOrNil
  | components threshold |
  ((self _isSequence: aSequence) and: [aSequence isEmpty not]) ifFalse: [
    ^ PBValidationError signal: 'near[] needs a non-empty vector, not ' , (PBCodec _pyRepr: aSequence)].
  components := aSequence asArray collect: [:x | self _finiteNumber: x what: 'A vector component'].
  (anIntegerOrNil isNil and: [aNumberOrNil isNil]) ifTrue: [
    ^ PBValidationError signal: 'near[] needs k, threshold or both'].
  (anIntegerOrNil isNil or: [anIntegerOrNil isClassObject not and: [anIntegerOrNil isInteger and: [anIntegerOrNil >= 1]]]) ifFalse: [
    ^ PBValidationError signal: 'near[] k must be an int >= 1, not ' , (PBCodec _pyRepr: anIntegerOrNil)].
  threshold := aNumberOrNil isNil ifTrue: [nil] ifFalse: [self _finiteNumber: aNumberOrNil what: 'near[] threshold'].
  (aStringOrNil isNil or: [(self _isText: aStringOrNil) and: [self _metrics includes: aStringOrNil]]) ifFalse: [
    ^ PBValidationError signal: 'near[] metric must be one of [''cosine'', ''ip'', ''l2''] or None, not '
      , (PBCodec _pyRepr: aStringOrNil)].
  ^ self basicNew _setVector: (PBTuple _trustedOn: components) k: anIntegerOrNil threshold: threshold
    metric: (aStringOrNil isNil ifTrue: [nil] ifFalse: [aStringOrNil copy]).

PBNearQuery class >> vector: aSequence k: anInteger
  ^ self vector: aSequence k: anInteger threshold: nil metric: nil.

PBNearQuery class >> vector: aSequence threshold: aNumber
  ^ self vector: aSequence k: nil threshold: aNumber metric: nil.

PBNearQuery class >> vector: aSequence k: anInteger threshold: aNumber
  ^ self vector: aSequence k: anInteger threshold: aNumber metric: nil.

"The metrics a query may name (terms.py NEAR_METRICS)."
PBNearQuery class >> _metrics
  ^ #('cosine' 'l2' 'ip').

"terms.py _finite_number: aValue as a Float when it is an Integer, a Float or a Decimal (not a
 Boolean) that is finite; PBValidationError '<what> must be a finite number, not <repr>'
 otherwise. Python's math.isfinite converts with float() first, so an Integer beyond the Float
 range is 'int too large to convert to float' (its OverflowError) and a signalling-NaN Decimal
 'cannot convert signaling NaN to float' (float()'s ValueError, PBVectorMath floatOf:): DV7."
PBNearQuery class >> _finiteNumber: aValue what: aText
  | f |
  (PBVectorMath _isComponent: aValue) ifFalse: [
    ^ PBValidationError signal: aText , ' must be a finite number, not ' , (PBCodec _pyRepr: aValue)].
  f := PBVectorMath floatOf: aValue.
  f isNil ifTrue: [^ PBValidationError signal: 'int too large to convert to float'].
  (PBVectorMath _isFinite: f) ifFalse: [
    ^ PBValidationError signal: aText , ' must be a finite number, not ' , (PBCodec _pyRepr: aValue)].
  ^ f.

"Python's list or tuple: an Array, an OrderedCollection, a PBFrozenList or a PBTuple."
PBNearQuery class >> _isSequence: anObject
  anObject isClassObject ifTrue: [^ false].
  ^ (anObject isKindOf: Array) or: [(anObject isKindOf: OrderedCollection) or: [
    (anObject isKindOf: PBFrozenList) or: [anObject isKindOf: PBTuple]]].

"Whether anObject is a String (not a Symbol): Python's str."
PBNearQuery class >> _isText: anObject
  ^ anObject isClassObject not and: [anObject isString and: [anObject isSymbol not]].

PBNearQuery >> _setVector: aTuple k: anIntegerOrNil threshold: aFloatOrNil metric: aStringOrNil
  "Runs once, on a fresh instance."
  vector isNil ifFalse: [^ PBUserError signal: 'PBNearQuery is immutable'].
  vector := aTuple.
  k := anIntegerOrNil.
  threshold := aFloatOrNil.
  metric := aStringOrNil.
  ^ self.

"The query vector, a PBTuple of finite Floats."
PBNearQuery >> vector
  ^ vector.

"The number of nearest members, an Integer >= 1, or nil."
PBNearQuery >> k
  ^ k.

"The threshold, a finite Float, or nil."
PBNearQuery >> threshold
  ^ threshold.

"'cosine', 'l2', 'ip', or nil for the index's own metric."
PBNearQuery >> metric
  ^ metric.

"{ 'vector'. 'k'. 'threshold'. 'metric' } as a PBFrozenDict, the vector an Array (terms.py
 display_value of a NearQuery, terms.py:323-325)."
PBNearQuery >> describe
  ^ PBFrozenDict withAssociations: { 'vector' -> vector asArray. 'k' -> k. 'threshold' -> threshold. 'metric' -> metric }.

"Equal by fields, the Floats by Python's float equality (0.0 = -0.0), as the dataclass's __eq__."
PBNearQuery >> = anObject
  (anObject isClassObject not and: [anObject class == PBNearQuery]) ifFalse: [^ false].
  (k = anObject k and: [threshold = anObject threshold and: [metric = anObject metric]]) ifFalse: [^ false].
  vector size = anObject vector size ifFalse: [^ false].
  1 to: vector size do: [:i | (vector at: i) = (anObject vector at: i) ifFalse: [^ false]].
  ^ true.

"Equal queries hash alike: a zero Float, 0.0 or -0.0, hashes as 0.0."
PBNearQuery >> hash
  | h |
  h := ((k hash bitXor: metric hash) bitXor: (self class _floatHash: threshold)) \\ 1073741824.
  vector do: [:x | h := (h * 31 + (self class _floatHash: x)) \\ 1073741824].
  ^ h.

PBNearQuery class >> _floatHash: aFloatOrNil
  aFloatOrNil isNil ifTrue: [^ nil hash].
  ^ aFloatOrNil = 0.0 ifTrue: [0.0 hash] ifFalse: [aFloatOrNil hash].

"PBNearQuery(vector=(1.0, 0.0), k=3, threshold=None, metric=None): the fields as Python's dataclass
 repr prints them (PBCodec _pyRepr:)."
PBNearQuery >> printOn: aStream
  aStream nextPutAll: 'PBNearQuery(vector='; nextPutAll: (PBCodec _pyRepr: vector);
    nextPutAll: ', k='; nextPutAll: (PBCodec _pyRepr: k);
    nextPutAll: ', threshold='; nextPutAll: (PBCodec _pyRepr: threshold);
    nextPutAll: ', metric='; nextPutAll: (PBCodec _pyRepr: metric); nextPut: $).

"The parts of proto_db's repr (PBCodec _pyRepr:): the four fields."
PBNearQuery >> _pyReprParts
  ^ { vector. k. threshold. metric }.

"NearQuery(vector=..., k=..., threshold=..., metric=...): the dataclass repr of terms.py NearQuery,
 anArray the reprs of _pyReprParts."
PBNearQuery >> _pyReprWith: anArray
  ^ 'NearQuery(vector=' , (anArray at: 1) , ', k=' , (anArray at: 2) , ', threshold=' , (anArray at: 3)
    , ', metric=' , (anArray at: 4) , ')'.

"=== PBVectorBackend: the backends of PBVectorIndex (vector_backends.py:305-333, 338-383, 480-524,
     566-734, 751-832) ===========================================================================

Stateless strategies, class side only, as proto_db's backend objects are: every method takes the
index, and every value it needs (its params, centroids, store) is read from it. PBVectorBackend
named: is backend_for. The index lives in indexes.st, which imports this module; this module never
imports indexes.st."

Object subclass: #PBVectorBackend.
PBVectorBackend comment: 'The backends of PBVectorIndex (proto_db vector_backends.py _Backend): parameter checks, list numbers, training and explain entries; class side only, stateless.'.

PBVectorBackend subclass: #PBVectorExact.
PBVectorExact comment: 'proto_db''s ExactBackend: every member in list 0, no training.'.

PBVectorBackend subclass: #PBVectorIvfFlat.
PBVectorIvfFlat comment: 'proto_db''s IvfFlatBackend: inverted lists around persisted centroids, trained by the pure-Python k-means (deviation DV3), searched by probing the nearest lists (vectors phase V6).'.

PBVectorBackend subclass: #PBVectorHnsw.
PBVectorHnsw comment: 'proto_db''s HnswBackend: maintained and validated like the exact backend (list 0, no training); its search is refused (ruling VQ1).'.

"The backend named aName (vector_backends.py backend_for): PBVectorExact, PBVectorIvfFlat or
 PBVectorHnsw; anything else, a non-String included, is PBValidationError with proto_db's text."
PBVectorBackend class >> named: aName
  (PBNearQuery _isText: aName) ifTrue: [
    aName = 'exact' ifTrue: [^ PBVectorExact].
    aName = 'ivf_flat' ifTrue: [^ PBVectorIvfFlat].
    aName = 'hnsw' ifTrue: [^ PBVectorHnsw]].
  ^ PBValidationError signal: 'Unknown vector backend ' , (PBCodec _pyRepr: aName)
    , '; expected one of [''exact'', ''ivf_flat'', ''hnsw'']'.

"The backend's name, as an index stores it in 'backend'."
PBVectorBackend class >> backendName
  ^ self _subclassResponsibility: 'backendName'.

"The kind of its index plans: 'VectorExact', 'VectorIvfFlat' or 'VectorHnsw' (_Backend.kind)."
PBVectorBackend class >> kindName
  ^ self _subclassResponsibility: 'kindName'.

"The parameter names and their defaults, an Array of Associations (_Backend.DEFAULTS)."
PBVectorBackend class >> defaults
  ^ self _subclassResponsibility: 'defaults'.

"The validated complete parameters of aDictionary (a Dictionary or PBFrozenDict of the given
 ones; names it does not know were refused before), an Array of name -> value Associations in
 the order proto_db's dict literal evaluates them (_Backend.check). Refusals are
 PBValidationError with proto_db's texts."
PBVectorBackend class >> check: aDictionary
  ^ self _subclassResponsibility: 'check:'.

"The list number of aVector in anIndex's store: 0 for a backend without lists (_Backend.list_for)."
PBVectorBackend class >> listFor: anIndex vector: aVector
  ^ 0.

"Whether anIndex, just grown by one member, must be retrained: never for a backend without lists
 (_Backend.needs_training)."
PBVectorBackend class >> needsTraining: anIndex
  ^ false.

"The centroids for aVectors: none for a backend without lists, the empty PBTuple
 (_Backend.train)."
PBVectorBackend class >> train: anIndex vectors: aVectors
  ^ PBTuple withAll: #().

"The backend's own entries of explain, an Array of Associations: none (_Backend.explain)."
PBVectorBackend class >> explainOf: anIndex
  ^ #().

PBVectorBackend class >> _subclassResponsibility: aSelector
  ^ PBUserError signal: self name , ' must implement ' , aSelector.

"vector_backends.py normalize_params: aParams (nil, a Dictionary or a PBFrozenDict from parameter
 name to value) validated and completed by the backend aName, as a PBTuple of (name, value)
 PBTuples sorted by name in code-point order (Python's sorted of str): ('M', 16) before
 ('ef_construction', 200). Checked in proto_db's order: the backend name, the parameter names
 (unknown ones listed sorted), then the backend's check:. A params that is neither nil nor a
 dictionary, or a name that is not a String, is PBValidationError (Python's keyword arguments are
 always str)."
PBVectorBackend class >> normalize: aParams backend: aName
  | backend given names unknown |
  backend := self named: aName.
  given := Dictionary new.
  aParams isNil ifFalse: [
    (aParams isClassObject not and: [(aParams isKindOf: Dictionary) or: [aParams isKindOf: PBFrozenDict]]) ifFalse: [
      ^ PBValidationError signal: 'PBVectorIndex params must be nil, a Dictionary or a PBFrozenDict of parameter names to values, not '
        , (PBCodec _pyRepr: aParams)].
    aParams keysAndValuesDo: [:k :v |
      (PBNearQuery _isText: k) ifFalse: [
        ^ PBValidationError signal: 'PBVectorIndex parameter names must be Strings, not ' , (PBCodec _pyRepr: k)].
      given at: k put: v]].
  names := backend defaults collect: [:a | a key].
  unknown := (given keys reject: [:k | names includes: k]) asArray.
  unknown isEmpty ifFalse: [
    ^ PBValidationError signal: 'Unknown parameters ' , (self _reprList: unknown) , ' for the '
      , (PBCodec _pyRepr: aName) , ' vector backend; expected ' , (self _reprList: names)].
  ^ PBTuple withAll: (((backend check: given) asArray sort: [:a :b | self _codePoints: a key notAfter: b key])
    collect: [:a | PBTuple withAll: { a key. a value }]).

"Whether aString sorts before or equal to anotherString by code point (Python's str order)."
PBVectorBackend class >> _codePoints: aString notAfter: anotherString
  1 to: (aString size min: anotherString size) do: [:i | | x y |
    x := (aString at: i) asInteger.
    y := (anotherString at: i) asInteger.
    x = y ifFalse: [^ x < y]].
  ^ aString size <= anotherString size.

"Python's repr of sorted(aStrings), a list of str: ['a', 'b']."
PBVectorBackend class >> _reprList: aStrings
  ^ PBCodec _pyRepr: (aStrings asArray sort: [:a :b | self _codePoints: a notAfter: b]).

"Whether aValue is an Integer that is not a Boolean (Python's isinstance(v, int) and not bool)."
PBVectorBackend class >> _isInt: aValue
  aValue isClassObject ifTrue: [^ false].
  ^ aValue isInteger and: [aValue ~~ true and: [aValue ~~ false]].

"_positive_int: aValue, an Integer >= 1, or PBValidationError naming the parameter aName."
PBVectorBackend class >> _positiveInt: aName value: aValue
  ((self _isInt: aValue) and: [aValue >= 1]) ifFalse: [
    ^ PBValidationError signal: 'Vector index parameter ' , (PBCodec repr: aName) , ' must be an int >= 1, not '
      , (PBCodec _pyRepr: aValue)].
  ^ aValue.

"_bool: aValue, a Boolean, or PBValidationError naming the parameter aName."
PBVectorBackend class >> _bool: aName value: aValue
  (aValue == true or: [aValue == false]) ifFalse: [
    ^ PBValidationError signal: 'Vector index parameter ' , (PBCodec repr: aName) , ' must be a bool, not '
      , (PBCodec _pyRepr: aValue)].
  ^ aValue.

"The seed checks of the ivf_flat and hnsw backends: an Integer >= 0."
PBVectorBackend class >> _seed: aValue
  ((self _isInt: aValue) and: [aValue >= 0]) ifFalse: [
    ^ PBValidationError signal: 'Vector index parameter ''seed'' must be an int >= 0, not ' , (PBCodec _pyRepr: aValue)].
  ^ aValue.

"_growth (vector_backends.py:319-322): aValue, an Integer or a Float (not a Boolean), finite and
 above 1, as a Float. Python's math.isfinite converts an int with float() first, so an Integer
 beyond the Float range is CPython's OverflowError, 'int too large to convert to float',
 signalled as PBValidationError (deviation DV7 e). The comparison with 1 is exact for an Integer,
 as Python's; the Float stored is float(value), one rounding (PBVectorMath floatOf:)."
PBVectorBackend class >> _growth: aName value: aValue
  | f |
  f := nil.
  (self _isInt: aValue) ifTrue: [
    f := PBVectorMath floatOf: aValue.
    f isNil ifTrue: [^ PBValidationError signal: 'int too large to convert to float']].
  (aValue isClassObject not and: [aValue isFloat]) ifTrue: [
    (PBVectorMath _isFinite: aValue) ifTrue: [f := aValue]].
  (f notNil and: [aValue > 1]) ifFalse: [
    ^ PBValidationError signal: 'Vector index parameter ' , (PBCodec repr: aName) , ' must be a finite number > 1, not '
      , (PBCodec _pyRepr: aValue)].
  ^ f.

"--- PBVectorExact (ExactBackend, vector_backends.py:480-524) ---"

PBVectorExact class >> backendName
  ^ 'exact'.

PBVectorExact class >> kindName
  ^ 'VectorExact'.

PBVectorExact class >> defaults
  ^ { 'numpy' -> true }.

"numpy (a Boolean, default true): kept and written; protoBaseST has no numpy screening, whose
 answers are the exact ones by construction (deviation DV2)."
PBVectorExact class >> check: aDictionary
  ^ { 'numpy' -> (self _bool: 'numpy' value: (aDictionary at: 'numpy' ifAbsent: [true])) }.

"--- PBVectorIvfFlat (IvfFlatBackend, vector_backends.py:566-734) ---"

PBVectorIvfFlat class >> backendName
  ^ 'ivf_flat'.

PBVectorIvfFlat class >> kindName
  ^ 'VectorIvfFlat'.

PBVectorIvfFlat class >> defaults
  ^ { 'nlist' -> 16. 'nprobe' -> 4. 'train_iters' -> 10. 'seed' -> 0. 'retrain_growth' -> 4.0 }.

"nlist (an Integer >= 1, default 16), nprobe (1 to nlist, default 4 min: nlist), seed (an
 Integer >= 0, default 0), train_iters (an Integer >= 1, default 10), retrain_growth (a finite
 number above 1, default 4.0, stored as a Float), checked in that order, the order in which
 proto_db's dict literal evaluates them (vector_backends.py:577-586)."
PBVectorIvfFlat class >> check: aDictionary
  | nlist nprobe seed |
  nlist := self _positiveInt: 'nlist' value: (aDictionary at: 'nlist' ifAbsent: [16]).
  nprobe := self _positiveInt: 'nprobe' value: (aDictionary at: 'nprobe' ifAbsent: [4 min: nlist]).
  nprobe > nlist ifTrue: [
    ^ PBValidationError signal: 'nprobe (' , nprobe printString , ') cannot exceed nlist (' , nlist printString , ')'].
  seed := self _seed: (aDictionary at: 'seed' ifAbsent: [0]).
  ^ { 'nlist' -> nlist. 'nprobe' -> nprobe.
    'train_iters' -> (self _positiveInt: 'train_iters' value: (aDictionary at: 'train_iters' ifAbsent: [10])).
    'seed' -> seed.
    'retrain_growth' -> (self _growth: 'retrain_growth' value: (aDictionary at: 'retrain_growth' ifAbsent: [4.0])) }.

"The list number of the vectors of an untrained index (vector_backends.py UNTRAINED)."
PBVectorIvfFlat class >> untrained
  ^ -1.

"_assign_metric (vector_backends.py:588-590): lists are assigned by cosine for a cosine index and
 by l2 for the others (ip included)."
PBVectorIvfFlat class >> _assignMetric: aMetric
  ^ aMetric = 'cosine' ifTrue: ['cosine'] ifFalse: ['l2'].

"list_for (vector_backends.py:606-634): the number (from 0) of the centroid of anIndex whose exact
 score for aVector (PBVectorMath score:query:vector:, the vector as the query, the centroid as
 the stored vector, as proto_db passes them) is the highest, the lowest number on ties (a strictly
 higher score replaces the best); -1 when the index is untrained (no centroids). proto_db's numpy
 screen only skips centroids that cannot win, so every centroid is scored here (Addendum V, 2.4)."
PBVectorIvfFlat class >> listFor: anIndex vector: aVector
  | centroids metric best bestScore query |
  centroids := anIndex centroids.
  centroids isEmpty ifTrue: [^ self untrained].
  metric := self _assignMetric: anIndex metric.
  best := 0.
  bestScore := nil.
  "The vector as the query of one scorer: its copy (and its cosine norm) once, not once per centroid."
  query := PBVectorMath scorerFor: metric query: aVector.
  1 to: centroids size do: [:j | | s |
    s := query value: (centroids at: j).
    (bestScore isNil or: [s > bestScore]) ifTrue: [best := j - 1. bestScore := s]].
  ^ best.

"needs_training (vector_backends.py:636-642): untrained, whether anIndex holds at least nlist
 members; trained, whether its members reach retrain_growth times trained_size. Python compares
 the int count with the Float product (retrain_growth is stored as a Float, the int trained_size
 converted exactly): members asFloat and trainedSize asFloat are exact below 2^53, which every
 count is, so this is Python's exact comparison, one IEEE rounding in the product (Addendum V,
 2.4). So 2.2 * 25 is 55.00000000000001: 55 members do not retrain, 56 do (tests/unit/vec_ivf.st)."
PBVectorIvfFlat class >> needsTraining: anIndex
  | members |
  members := anIndex memberCount.
  anIndex centroids isEmpty ifTrue: [^ members >= (anIndex paramAt: 'nlist')].
  ^ members asFloat >= ((anIndex paramAt: 'retrain_growth') * anIndex trainedSize asFloat).

"train (vector_backends.py:644-661; Addendum V, 2.5): the centroids for aVectors (canonical
 vectors of anIndex), the empty PBTuple below nlist vectors. The vectors are sorted by their
 values (trainingOrderOf:, R128: never by the members' oids), normalised for a cosine index, given
 to the pure-Python k-means (PBVectorMath kmeans:nlist:iterations:seed:, deviation DV3), and the
 centroids normalised again for cosine; a PBTuple of nlist PBTuples of Floats. Equal sort keys are
 equal bytes, so the order among them changes nothing."
PBVectorIvfFlat class >> train: anIndex vectors: aVectors
  | nlist cosine data centroids |
  nlist := anIndex paramAt: 'nlist'.
  aVectors size < nlist ifTrue: [^ PBTuple withAll: #()].
  cosine := anIndex metric = 'cosine'.
  data := (aVectors asArray collect: [:v | { PBVectorMath trainingOrderOf: v. v }])
    sort: [:a :b | (a at: 1) <= (b at: 1)].
  data := data collect: [:pair | cosine ifTrue: [PBVectorMath normalized: (pair at: 2)] ifFalse: [pair at: 2]].
  centroids := PBVectorMath kmeans: data nlist: nlist iterations: (anIndex paramAt: 'train_iters')
    seed: (anIndex paramAt: 'seed').
  cosine ifTrue: [centroids := centroids collect: [:c | PBVectorMath normalized: c]].
  ^ PBTuple withAll: (centroids collect: [:c | PBTuple withAll: c asArray]).

"_probe_order (vector_backends.py:663-669): the list numbers a search of aQuery probes, in order:
 -1 (the untrained vectors) first, then, when anIndex is trained, every centroid's number by
 descending exact score (the assignment metric, the query first), ties by ascending number, as
 Python sorts the pairs (-score, number). An Array of Integers (search:query:k:threshold:eligible:
 probes the non-empty ones in this order)."
PBVectorIvfFlat class >> probeOrder: anIndex query: aQuery
  | centroids metric scored query |
  centroids := anIndex centroids.
  centroids isEmpty ifTrue: [^ { self untrained }].
  metric := self _assignMetric: anIndex metric.
  "One scorer: the query's copy (and its cosine norm) once, not once per centroid."
  query := PBVectorMath scorerFor: metric query: aQuery.
  scored := (1 to: centroids size) asArray collect: [:j |
    { (query value: (centroids at: j)) negated. j - 1 }].
  scored := scored sort: [:a :b | (a at: 1) < (b at: 1) or: [(a at: 1) = (b at: 1) and: [(a at: 2) <= (b at: 2)]]].
  ^ { self untrained } , (scored collect: [:pair | pair at: 2]).

"lists (the number of centroids, 0 untrained) and trained_size (IvfFlatBackend.explain,
 vector_backends.py:732-734): read from the index, so they need no training of its own."
PBVectorIvfFlat class >> explainOf: anIndex
  ^ { 'lists' -> anIndex centroids size. 'trained_size' -> anIndex trainedSize }.

"--- PBVectorHnsw (HnswBackend, vector_backends.py:751-821) ---"

PBVectorHnsw class >> backendName
  ^ 'hnsw'.

PBVectorHnsw class >> kindName
  ^ 'VectorHnsw'.

PBVectorHnsw class >> defaults
  ^ { 'M' -> 16. 'ef_construction' -> 200. 'ef_search' -> 64. 'seed' -> 0 }.

"M (an Integer >= 2, default 16), seed (an Integer >= 0, default 0), ef_construction and
 ef_search (Integers >= 1, defaults 200 and 64), checked in proto_db's order
 (vector_backends.py:763-770). The graph they parameterise is hnswlib's and is never built here
 (deviation DV1); they are kept and written."
PBVectorHnsw class >> check: aDictionary
  | m seed |
  m := self _positiveInt: 'M' value: (aDictionary at: 'M' ifAbsent: [16]).
  m < 2 ifTrue: [^ PBValidationError signal: 'Vector index parameter ''M'' must be >= 2, not ' , (PBCodec _pyRepr: m)].
  seed := self _seed: (aDictionary at: 'seed' ifAbsent: [0]).
  ^ { 'M' -> m.
    'ef_construction' -> (self _positiveInt: 'ef_construction' value: (aDictionary at: 'ef_construction' ifAbsent: [200])).
    'ef_search' -> (self _positiveInt: 'ef_search' value: (aDictionary at: 'ef_search' ifAbsent: [64])).
    'seed' -> seed }.

"=== search and estimates (vectors phase V6; vector_backends.py:147-167, 378-383, 505-524,
     685-730 and 790-821) ===

A backend answers a near[] query over one index version, which holds every value it reads (the
store, the centroids, the parameters): there is no derived cache (deviation DV4), so every search
walks the store of that version. anIndex's entry walkers (indexes.st) answer the store's entries
as rank:query:metric:k:threshold: takes them, { memberKey. element. count. vector. member order
key }. Every score is PBVectorMath's."

"The { element. count } pairs answering a near[] query over anIndex (_Backend.search): aQuery the
 canonical query vector (a PBTuple of Floats of the index's dimension), anInteger k or nil,
 aThreshold a Float or nil (not both nil), anEligible nil or a block of one element answering a
 Boolean (the residual predicate, ruling R27: the search runs among the elements it accepts).
 Nearest first, ties by the member key."
PBVectorBackend class >> search: anIndex query: aQuery k: anInteger threshold: aThreshold eligible: anEligible
  ^ self _subclassResponsibility: 'search:query:k:threshold:eligible:'.

"The PBEstimate of a search of anIndex (_Backend.estimate, the cost model D30), filtered when a
 residual predicate is evaluated."
PBVectorBackend class >> estimate: anIndex k: anInteger threshold: aThreshold filtered: aBoolean
  ^ self _subclassResponsibility: 'estimate:k:threshold:filtered:'.

"_Backend._rows (vector_backends.py:377-383), in Python's arithmetic: half the members without k,
 else min(k, members); halved again when k and a threshold are both given."
PBVectorBackend class >> _rows: anIndex k: anInteger threshold: aThreshold
  | members rows |
  members := anIndex memberCount.
  rows := anInteger isNil ifTrue: [members * PBCost filterSelectivity] ifFalse: [anInteger min: members].
  (aThreshold notNil and: [anInteger notNil]) ifTrue: [rows := rows * PBCost filterSelectivity].
  ^ rows.

"The entries of anEntries whose element anEligible accepts (vector_backends.py _filtered)."
PBVectorBackend class >> _filtered: anEntries eligible: anEligible
  anEligible isNil ifTrue: [^ anEntries].
  ^ anEntries select: [:entry | anEligible value: (entry at: 2)].

"--- PBVectorExact (ExactBackend.search and estimate, vector_backends.py:505-524) ---"

"Every member the predicate accepts, ranked exactly. proto_db screens with numpy when it is
 installed and re-scores exactly, which answers the same; protoBaseST has no screening (DV2)."
PBVectorExact class >> search: anIndex query: aQuery k: anInteger threshold: aThreshold eligible: anEligible
  | entries |
  entries := OrderedCollection new.
  anIndex _entriesDo: [:entry |
    (anEligible isNil or: [anEligible value: (entry at: 2)]) ifTrue: [entries addLast: entry]].
  ^ PBVectorMath rank: entries query: aQuery metric: anIndex metric k: anInteger threshold: aThreshold.

"Touches every member (twice when a predicate is evaluated): cost = members * (2 or 1) + rows + 1."
PBVectorExact class >> estimate: anIndex k: anInteger threshold: aThreshold filtered: aBoolean
  | rows |
  rows := self _rows: anIndex k: anInteger threshold: aThreshold.
  ^ PBEstimate rows: rows cost: anIndex memberCount * (aBoolean ifTrue: [2] ifFalse: [1]) + rows + 1.

"--- PBVectorIvfFlat (IvfFlatBackend.search and estimate, vector_backends.py:685-730) ---"

"Probes the best nprobe non-empty lists by probeOrder:query: (list -1, the untrained vectors, is
 always probed in addition), and, with k, doubles the probe while fewer than k members match (the
 predicate and the threshold included); then ranks the accepted members of the probed lists
 exactly. With nprobe = nlist every list is probed and the answer is the exact one.
 proto_db filters the probe order to the non-empty lists first (vector_backends.py:688, 'j in
 lists', over its per-version list cache); there is no cache here (DV4), so the walk reads the
 lists in probe order and skips an empty one as it reaches it: it never counts toward the probe,
 and the probe is exhausted when the probe order is. That is proto_db's loop, which reads the
 filtered order only as a prefix and, at exhaustion, its length: the same lists are probed in the
 same order (a doubled probe past the last non-empty list reads only empty ones), so the answer is
 the same, with one bounded walk per list reached instead of one per list and query."
PBVectorIvfFlat class >> search: anIndex query: aQuery k: anInteger threshold: aThreshold eligible: anEligible
  | order next taken probe floor probed matching query metric |
  order := self probeOrder: anIndex query: aQuery.
  probe := anIndex paramAt: 'nprobe'.
  metric := anIndex metric.
  floor := PBVectorMath scoreFloor: metric threshold: aThreshold.
  query := PBVectorMath scorerFor: metric query: aQuery.
  next := 0.
  taken := 0.
  probed := OrderedCollection new.
  matching := 0.
  [[taken < probe and: [next < order size]] whileTrue: [| list entries |
      next := next + 1.
      list := order at: next.
      entries := anIndex _listEntries: list.
      entries isEmpty ifFalse: [
        "List -1 first among the non-empty lists is probed in addition to nprobe."
        (taken = 0 and: [list = self untrained]) ifTrue: [probe := probe + 1].
        taken := taken + 1.
        probed addAll: entries.
        (anInteger notNil and: [anEligible isNil and: [floor isNil]])
          ifTrue: [matching := matching + entries size]
          ifFalse: [anInteger isNil ifFalse: [
            entries do: [:entry |
              ((anEligible isNil or: [anEligible value: (entry at: 2)])
                  and: [floor isNil or: [(query value: (entry at: 4)) >= floor]])
                ifTrue: [matching := matching + 1]]]]]].
    next >= order size or: [anInteger isNil or: [matching >= anInteger]]]
      whileFalse: [probe := 2 * probe].
  ^ PBVectorMath rank: (self _filtered: probed eligible: anEligible) query: aQuery metric: metric
    k: anInteger threshold: aThreshold.

"Touches the centroids and the probed fraction of the members: fraction = min(1.0, nprobe / nlist)
 when trained, else 1.0; cost = centroids + members * fraction * (2 or 1) + rows + 1."
PBVectorIvfFlat class >> estimate: anIndex k: anInteger threshold: aThreshold filtered: aBoolean
  | centroids fraction rows touched |
  centroids := anIndex centroids.
  fraction := centroids isEmpty
    ifTrue: [1.0]
    ifFalse: [1.0 min: (anIndex paramAt: 'nprobe') asFloat / (anIndex paramAt: 'nlist') asFloat].
  rows := self _rows: anIndex k: anInteger threshold: aThreshold.
  touched := anIndex memberCount * fraction * (aBoolean ifTrue: [2] ifFalse: [1]).
  ^ PBEstimate rows: rows cost: centroids size + touched + rows + 1.

"--- PBVectorHnsw (HnswBackend.search and estimate, vector_backends.py:790-821) ---"

"Refused (ruling VQ1, deviation DV1): the graph is hnswlib's, which protoST cannot load. Raised at
 the first execution of the plan, as proto_db raises it without hnswlib (load_hnswlib), never at
 planning; the text names the index and is rewritten for protoST (DV8)."
PBVectorHnsw class >> search: anIndex query: aQuery k: anInteger threshold: aThreshold eligible: anEligible
  ^ PBNotSupportedError signal: anIndex _subject , ': the ''hnsw'' vector backend needs hnswlib, which protoST '
    , 'cannot load; use the ''exact'' or ''ivf_flat'' backend'.

"About ef candidates per graph level visited, plus the predicate on those candidates:
 ef = max(ef_search, k or 0), visited = min(members, ef * log2(members + 2)), cost = visited *
 (2 or 1) + rows + 1. log2 is PBCost log2: (deviation DV6)."
PBVectorHnsw class >> estimate: anIndex k: anInteger threshold: aThreshold filtered: aBoolean
  | members ef rows visited |
  members := anIndex memberCount.
  ef := (anIndex paramAt: 'ef_search') max: (anInteger isNil ifTrue: [0] ifFalse: [anInteger]).
  rows := self _rows: anIndex k: anInteger threshold: aThreshold.
  visited := members min: ef * (PBCost log2: members + 2).
  ^ PBEstimate rows: rows cost: visited * (aBoolean ifTrue: [2] ifFalse: [1]) + rows + 1.

PBVectorMath _initializeKernel.
