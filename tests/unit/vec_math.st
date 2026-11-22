"EXPECT: ok 17"
"Vectors phase V1 (Addendum V, 2.2 and 5.1): PBVectorMath, the vector math kernel, against
 CPython and proto_db v2.0.0rc4 (proto_db/indexing/vector_backends.py). Every expected Float is
 written as its IEEE 754 binary64 bytes (big-endian hex) and every result is compared by its bytes,
 so -0.0 against 0.0 and a last-bit difference both fail. The expected values were computed by
 CPython 3.14 (glibc 2.43, the host libm) and by proto_db's own functions with numpy blocked; the
 bulk of the CPython vectors is tests/conformance/vector_math.st.

 Checks: floatOf: of Integers (one rounding, nil beyond the Float range: 2^1024 - 2^970 overflows,
 2^1024 - 2^971 is the largest Float); floatOf: of Decimals (subnormal half-way values, extreme
 exponents, zeros, NaN, infinities, and the signalling NaN refused with CPython's text); the exact
 nearest-Float oracle (2.2.2): for seeded and adversarial Decimals the answer is the nearest Float,
 ties to the even significand, decided by exact Integer arithmetic on the Float's bits;
 canonicalVector:dim: (every invalid form of tests/unit/test_vector_index.py:178-193); fsum: on
 CPython's msum cases (Lib/test/test_math.py testFsum) and its special values and two errors;
 the scores of test_zero_vectors_have_cosine_similarity_zero (:195-199); the scores' order of
 operations, scoreFloor:threshold:, normalized: and the overflow refusals (DV7 a); rank: ties
 (nearest first, then the member key's order key) and its cut, Python's del scored[k:] for k = 0 and
 negative k; the three squares (x * x in scores and norms,
 raisedTo: 2 in k-means, on a half-way case, with a k-means witness whose centroids change if the
 square multiplies); trainingOrderOf: against byte order; and the IEEE self-test of 2.2.3 (error-free
 transformations, signed zeros, subnormals, half-way products, sqrt, the libm pow square). Then the
 fsum primitives of protoST 0.15.0 (Addendum V, 2.2.4; task VP-adopt): the feature probe selects
 them from protoST 0.15.0 on, and only there (Smalltalk version), and the test-only switch forces
 the Smalltalk kernel; on both paths the kernel answers alike and the primitives' errors become
 the kernel's (PBValidationError with CPython's text, infinity in sumNonNegative:), an Integer term
 keeps the Smalltalk kernel's answer, and sequences of unequal sizes pair as Python's zip. Last,
 the k-means distance's primitive of protoST 0.16.0 (Float fsumOfPowSquaredDifferences:with:): its
 own probe selects it from 0.16.0 on, and only there (0.15.0 has fsum: but not it), the same
 test-only switch forces the Smalltalk loop, and both paths answer the same bytes: the libm pow
 half-way square of a positive and of a negative difference, an overflowing square (infinity), an overflowing sum (infinity, as
 sumNonNegative:), an Integer term, and k-means centroids over seeded data. Then scorerFor:query:
 (task V8, fix round 1), the per-query scorer that rank:, the IVF probe loop, listFor:vector: and
 probeOrder:query: use: on both kernels it answers, score after score (the cosine query norm
 computed at the first and reused), what score:query:vector: answers, the same bytes and the same
 refusals, at the first score and never when the scorer is made."
Import from: 'protobase'.
Import from: '_check'.

| c f hex hexes outcome tuple list pow2 bitsOf floatOfBits unitsOf nearest seed next decimals
  oracleFails half five entries ranked q x witness vs sorted hi lo yr version released paths
  released16 seedPow nextPow data scorerCases viaScore viaScorer refusedAtCreation |
c := Check new.
"A Float from its big-endian hex bytes, and the hex bytes of a Float (nil answers 'nil')."
f := [:h | (Check bytes: h) float64At: 1 bigEndian: true].
hex := [:aFloat | | w |
  aFloat isNil
    ifTrue: ['nil']
    ifFalse: [w := WriteStream on: ByteArray new. w nextPutFloat64: aFloat bigEndian: true. w contents hex asLowercase]].
hexes := [:aSequence | aSequence isNil ifTrue: ['nil'] ifFalse: [aSequence asArray collect: [:each | hex value: each]]].
"The result of aBlock (a Float as its hex), or 'refused: <text>' for a PBValidationError."
outcome := [:aBlock |
  [ | r | r := aBlock value. r isFloat ifTrue: [hex value: r] ifFalse: [r]]
    on: PBValidationError do: [:e | e return: 'refused: ' , e messageText]].
tuple := [:anArray | PBTuple withAll: anArray].
list := [:anArray | PBFrozenList withAll: anArray].
bitsOf := [:aFloat | | w | w := WriteStream on: ByteArray new. w nextPutFloat64: aFloat bigEndian: true.
  w contents unsignedLong64At: 1 bigEndian: true].
floatOfBits := [:anInteger | | w | w := WriteStream on: ByteArray new.
  w nextPutUnsigned: anInteger width: 8 bigEndian: true. w contents float64At: 1 bigEndian: true].
"2^e as a Float, exactly, from its bits (-1074 <= e <= 1023)."
pow2 := [:e | e >= -1022
  ifTrue: [floatOfBits value: (e + 1023 bitShift: 52)]
  ifFalse: [floatOfBits value: (1 bitShift: e + 1074)]].

"--- 1. floatOf: Integers ---"
c that: 'floatOf: an Integer is rounded once, nil beyond the Float range'
  is: ({(2 raisedTo: 53) + 1. (2 raisedTo: 53) + 3. (2 raisedTo: 64) - 1. (2 raisedTo: 64) + 1.
        ((2 raisedTo: 64) + (2 raisedTo: 11) + 1) negated. (2 raisedTo: 1024) - (2 raisedTo: 971).
        ((2 raisedTo: 1024) - (2 raisedTo: 971)) negated. 3. 0. (2 raisedTo: 55) + 3. (2 raisedTo: 63) negated.
        (2 raisedTo: 1024) - (2 raisedTo: 970). ((2 raisedTo: 1024) - (2 raisedTo: 970)) negated. 10 raisedTo: 400}
       collect: [:each | hex value: (PBVectorMath floatOf: each)])
  equals: #('4340000000000000' '4340000000000002' '43f0000000000000' '43f0000000000000' 'c3f0000000000001'
            '7fefffffffffffff' 'ffefffffffffffff' '4008000000000000' '0000000000000000' '4360000000000000'
            'c3e0000000000000' 'nil' 'nil' 'nil').

"--- 2. floatOf: Decimals ---"
c that: 'floatOf: a Decimal is rounded once (subnormals, extreme exponents, zeros, specials); sNaN is refused'
  is: ((#('1E-310' '2.5E-324' '0E-1000000000' '-0' '-0E+999999' '1E+400' '-1E+400' '1.20' '-123'
          '1.7976931348623158E+308' '-Infinity' 'Infinity' '1E-999999' '-1E-999999')
        collect: [:t | hex value: (PBVectorMath floatOf: (Decimal fromString: t))])
       , {hex value: (PBVectorMath floatOf: (Decimal fromString: (5 raisedTo: 1075) printString , 'E-1075')).
          hex value: (PBVectorMath floatOf: (Decimal fromString: (3 * (5 raisedTo: 1075)) printString , 'E-1075')).
          (PBVectorMath floatOf: (Decimal fromString: 'NaN')) isNaN.
          (PBVectorMath floatOf: (Decimal fromString: '-NaN7')) isNaN.
          outcome value: [PBVectorMath floatOf: (Decimal fromString: 'sNaN')].
          outcome value: [PBVectorMath floatOf: (Decimal fromString: '-sNaN12')]})
  equals: #('000012688b70e62b' '0000000000000001' '0000000000000000' '8000000000000000' '8000000000000000'
            '7ff0000000000000' 'fff0000000000000' '3ff3333333333333' 'c05ec00000000000' '7fefffffffffffff'
            'fff0000000000000' '7ff0000000000000' '0000000000000000' '8000000000000000'
            '0000000000000000' '0000000000000002' true true
            'refused: cannot convert signaling NaN to float' 'refused: cannot convert signaling NaN to float').

"--- 3. The exact oracle (2.2.2) ---"
"The magnitude of the Float whose bits without the sign are anInteger, as an exact Integer count
 of 2^-1075 (never protoST's Float conversions): a subnormal m 2^-1074 is 2m units, a normal
 (2^52 + m) 2^(E-1075) is (2^52 + m) 2^E units; the infinity's pattern gives 2^1024 exactly."
unitsOf := [:abits | | e m |
  e := abits bitShift: -52.
  m := abits bitAnd: (1 bitShift: 52) - 1.
  e = 0 ifTrue: [2 * m] ifFalse: [m + (1 bitShift: 52) bitShift: e]].
"nil when floatOf: aDecimal is the nearest Float to its exact value, else a description. The exact
 value is N / D (N = coefficient 10^max(e, 0), D = 10^max(-e, 0)); the Float f is the nearest when
 the value lies between the midpoints of f and its two neighbours, (units(f) + units(neighbour)) /
 2^1076, and on a midpoint only when f's significand is even (ties to even); beyond the range the
 answer is infinity exactly from 2^1024 - 2^970 up; a zero keeps the Decimal's sign. Every
 comparison is exact Integer arithmetic (N T <= M D); no Fraction is built, so no gcd of
 thousand-digit numbers is ever taken."
nearest := [:d | | x bits sign abits n den big au hi lo cmpHi cmpLo |
  x := PBVectorMath floatOf: d.
  bits := bitsOf value: x.
  sign := bits bitShift: -63.
  abits := bits bitAnd: 16r7FFFFFFFFFFFFFFF.
  n := d coefficient * (10 raisedTo: (d exponent max: 0)).
  den := 10 raisedTo: (d exponent negated max: 0).
  big := 1 bitShift: 1076.
  n = 0
    ifTrue: [(abits = 0 and: [sign = d sign]) ifTrue: [nil] ifFalse: [d printString , ': not a zero of its sign']]
    ifFalse: [sign ~= d sign
      ifTrue: [d printString , ': the sign of ' , x printString]
      ifFalse: [abits = 16r7FF0000000000000
        ifTrue: [n >= (((2 raisedTo: 1024) - (2 raisedTo: 970)) * den)
          ifTrue: [nil] ifFalse: [d printString , ': infinity below the half-way']]
        ifFalse: [
          au := unitsOf value: abits.
          hi := au + (unitsOf value: abits + 1).
          "-1, 0, 1: the exact value below, on, above the upper midpoint (and the lower one)."
          cmpHi := (n * big) < (hi * den) ifTrue: [-1] ifFalse: [(n * big) = (hi * den) ifTrue: [0] ifFalse: [1]].
          cmpLo := abits = 0
            ifTrue: [1]
            ifFalse: [
              lo := au + (unitsOf value: abits - 1).
              (n * big) < (lo * den) ifTrue: [-1] ifFalse: [(n * big) = (lo * den) ifTrue: [0] ifFalse: [1]]].
          (cmpHi > 0 or: [cmpLo < 0])
            ifTrue: [d printString , ': not the nearest Float, ' , x printString]
            ifFalse: [((cmpHi = 0 or: [cmpLo = 0]) and: [abits odd])
              ifTrue: [d printString , ': a tie not to the even significand, ' , x printString]
              ifFalse: [nil]]]]]].
"Seeded Decimals (a 64-bit LCG): coefficients of 1 to 32 digits, exponents around the subnormal
 range, the normal range and the top of the Float range."
seed := 20261120.
next := [:bound | seed := seed * 6364136223846793005 + 1442695040888963407 \\ (2 raisedTo: 64).
  (seed bitShift: -11) \\ bound].
decimals := OrderedCollection new.
1 to: 400 do: [:i | | digits coef exp |
  digits := (next value: 32) + 1.
  coef := ((next value: (2 raisedTo: 53)) * (2 raisedTo: 53) + (next value: (2 raisedTo: 53))) \\ (10 raisedTo: digits) max: 1.
  exp := #(-360 -1100 -30 280) at: (next value: 4) + 1.
  exp := exp + (next value: (exp = -1100 ifTrue: [800] ifFalse: [60])).
  decimals add: (Decimal sign: (next value: 3) // 2 coefficient: coef exponent: exp)].
"Adversarial: exact half-way values between two subnormals ((2m + 1) 2^-1075), between two
 normals ((2m + 1) 2^(e-1)), the largest Float's half-way neighbour (2^1024 - 2^970), each nudged
 up and down; zeros and -0."
five := 5 raisedTo: 1075.
#(0 1 2 3 4 5 4503599627370495 4503599627370494 2251799813685248) do: [:m | | exact |
  exact := 2 * m + 1 * five.
  decimals add: (Decimal sign: 0 coefficient: exact exponent: -1075);
    add: (Decimal sign: 1 coefficient: exact exponent: -1075);
    add: (Decimal sign: 0 coefficient: exact * 10 + 1 exponent: -1076);
    add: (Decimal sign: 0 coefficient: exact * 10 - 1 exponent: -1076)].
#(-1060 -700 -100 -60) do: [:e | | m exact |
  m := (1 bitShift: 52) + (next value: (1 bitShift: 52)).
  exact := 2 * m + 1 * (5 raisedTo: 1 - e).
  decimals add: (Decimal sign: 0 coefficient: exact exponent: e - 1);
    add: (Decimal sign: 0 coefficient: exact * 10 + 1 exponent: e - 2);
    add: (Decimal sign: 0 coefficient: exact * 10 - 1 exponent: e - 2)].
half := (2 raisedTo: 1024) - (2 raisedTo: 970).
decimals add: (Decimal sign: 0 coefficient: half exponent: 0);
  add: (Decimal sign: 1 coefficient: half exponent: 0);
  add: (Decimal sign: 0 coefficient: half * 10 - 1 exponent: -1);
  add: (Decimal sign: 0 coefficient: half * 10 + 1 exponent: -1);
  add: (Decimal sign: 0 coefficient: 0 exponent: -1100);
  add: (Decimal sign: 1 coefficient: 0 exponent: 900);
  add: (Decimal fromString: '-0').
oracleFails := (decimals collect: [:d | nearest value: d]) reject: [:each | each isNil].
oracleFails do: [:each | ('oracle: ' , each) displayNl].
c that: 'floatOf: every Decimal answers the nearest Float, ties to even (exact oracle, '
    , decimals size printString , ' Decimals)'
  is: oracleFails size equals: 0.

"--- 4. canonicalVector:dim: (test_vector_index.py:178-193 and more) ---"
c that: 'canonicalVector:dim: answers a PBTuple of Floats, or nil for every invalid form; sNaN is refused'
  is: ({nil. PBMissing default. 'ab'. tuple value: {1.0}. tuple value: {1.0. Float nan}.
        tuple value: {true. 0.0}. tuple value: {0.0. false}. tuple value: {f value: '6974e718d7d7625a'. f value: '6974e718d7d7625a'}.
        tuple value: {Float infinity. 0.0}. tuple value: {Float infinity negated. 0.0}.
        tuple value: {2 raisedTo: 1024. 0.0}. tuple value: {Decimal fromString: '1E+400'. 0.0}.
        tuple value: {Decimal fromString: 'NaN'. 0.0}. tuple value: {'a'. 1.0}. tuple value: {nil. 1.0}.
        tuple value: {1.0. 2.0. 3.0}. tuple value: {(1/2). 1.0}. {1.0. 0.0}}
       collect: [:key | PBVectorMath canonicalVector: key dim: 2])
     , {hexes value: (PBVectorMath canonicalVector: (tuple value: {1.0. 0.0}) dim: 2).
        hexes value: (PBVectorMath canonicalVector: (list value: {0.0. 1.0}) dim: 2).
        hexes value: (PBVectorMath canonicalVector: (tuple value: {1. 2.5. Decimal fromString: '-3'}) dim: 3).
        hexes value: (PBVectorMath canonicalVector: (tuple value: {(2 raisedTo: 1024) - (2 raisedTo: 971). 0}) dim: 2).
        hexes value: (PBVectorMath canonicalVector: (tuple value: {Decimal fromString: '1E-400'. -0.0}) dim: 2).
        (PBVectorMath canonicalVector: (tuple value: {}) dim: 0) class.
        PBVectorMath canonicalVector: (tuple value: {f value: '5fef06d5a4bf631f'. f value: '5fef06d5a4bf631f'}) dim: 2.
        outcome value: [PBVectorMath canonicalVector: (tuple value: {Decimal fromString: 'sNaN'. 0.0}) dim: 2]}
  equals: {nil. nil. nil. nil. nil. nil. nil. nil. nil. nil. nil. nil. nil. nil. nil. nil. nil. nil.
           #('3ff0000000000000' '0000000000000000'). #('0000000000000000' '3ff0000000000000').
           #('3ff0000000000000' '4004000000000000' 'c008000000000000'). 'nil'.
           #('0000000000000000' '8000000000000000'). PBTuple. nil.
           'refused: cannot convert signaling NaN to float'}.

"--- 5. fsum: CPython's msum cases (Lib/test/test_math.py testFsum) ---"
c that: 'fsum: is correctly rounded on CPython''s msum cases'
  is: ({#().
        {0.0}.
        #('54b249ad2594c37d' '3ff0000000000000' 'd4b249ad2594c37d' '2b2bff2ee48e0530' '4a511b0ec57e649a' 'bff0000000000000' 'ca511b0ec57e649a') collect: f.
        #('4340000000000000' 'bfe0000000000000' 'bc90000000000000') collect: f.
        #('4340000000000000' '3ff0000000000000' '39b0000000000000') collect: f.
        #('4340000000000005' '3ff0000000000000' '39b0000000000000') collect: f.
        #('433ffffffffffffc' '3fe0000000000000' '3c90000000000000') collect: f.
        (1 to: 1000) asArray collect: [:n | 1.0 / n].
        (1 to: 1000) asArray collect: [:n | (n odd ifTrue: [-1.0] ifFalse: [1.0]) / n].
        #('4341c37937e08000' '3ff0000000000000' '3c9cd2b297d889bc') collect: f.
        #('4341c37937e07fff' '3fefffffffffffff' 'c341c37937e07fff' 'bfefffffffffffff') collect: f.
        ((((-1074 to: 970 by: 2) asArray collect: [:n | (pow2 value: n) - (pow2 value: n + 50) + (pow2 value: n + 52)]) asOrderedCollection)
          add: (pow2 value: 1022) negated; yourself) asArray}
       collect: [:terms | hex value: (PBVectorMath fsum: terms)])
  equals: #('0000000000000000' '0000000000000000' '2b2bff2ee48e0530' '433fffffffffffff' '4340000000000001'
            '4340000000000006' '433ffffffffffffd' '401df11f45f4e61a' 'bfe62a2af1bd3624' '4341c37937e08001'
            '0000000000000000' '7c95555555555555').

"--- 6. fsum: special values and errors; sumNonNegative: ---"
c that: 'fsum: special values and CPython''s two errors; sumNonNegative: maps overflow to infinity'
  is: ({{-0.0}. {-0.0. -0.0}. {Float infinity. 1.0}. {Float infinity. Float infinity}. {Float infinity negated}.
        {Float infinity. Float infinity negated}. {f value: '7fe1ccf385ebc8a0'. f value: '7fe1ccf385ebc8a0'}.
        {Float infinity negated. f value: '7fe1ccf385ebc8a0'. f value: '7fe1ccf385ebc8a0'}.
        {f value: '7fe1ccf385ebc8a0'. f value: '7fe1ccf385ebc8a0'. (f value: '7fe1ccf385ebc8a0') negated}.
        {f value: '0000000000000001'. f value: '0000000000000001'}. {f value: '0000000000000001'. f value: '8000000000000001'}}
       collect: [:terms | outcome value: [PBVectorMath fsum: terms]])
     , {(PBVectorMath fsum: {Float nan}) isNaN. (PBVectorMath fsum: {Float nan. Float infinity}) isNaN.
        outcome value: [PBVectorMath sumNonNegative: {f value: '7fe1ccf385ebc8a0'. f value: '7fe1ccf385ebc8a0'}].
        outcome value: [PBVectorMath sumNonNegative: {f value: '0000000000000001'. 2.0}]}
  equals: #('0000000000000000' '0000000000000000' '7ff0000000000000' '7ff0000000000000' 'fff0000000000000'
            'refused: -inf + inf in fsum' 'refused: intermediate overflow in fsum'
            'refused: intermediate overflow in fsum' 'refused: intermediate overflow in fsum'
            '0000000000000002' '0000000000000000'), {true. true. '7ff0000000000000'. '4000000000000000'}.

"--- 7. test_zero_vectors_have_cosine_similarity_zero (test_vector_index.py:195-199) ---"
c that: 'zero vectors have cosine similarity zero; l2 and ip of small vectors'
  is: {PBVectorMath score: 'cosine' query: {0.0. 0.0} vector: {1.0. 2.0}.
       PBVectorMath score: 'cosine' query: {1.0. 0.0} vector: {2.0. 0.0}.
       PBVectorMath score: 'l2' query: {0.0. 0.0} vector: {3.0. 4.0}.
       PBVectorMath score: 'ip' query: {1.0. 2.0} vector: {3.0. 4.0}}
  equals: {0.0. 1.0. -5.0. 11.0}.

"--- 8. Scores: operation order, scoreFloor:threshold:, normalized:, refusals ---"
c that: 'scores follow vector_backends.py operation for operation; scoreFloor:, normalized:; overflow is refused'
  is: {outcome value: [PBVectorMath score: 'cosine'
         query: (#('3fe59ae0a7548546' '3fbce794bb052320' '3fd236b3a19999e0') collect: f)
         vector: (#('bfe41a1c9af715d4' '3fef85d4cdca033e' '3fe7095d2a5f01ec') collect: f)].
       outcome value: [PBVectorMath score: 'l2' query: (#('bfe252e00b618fda' '3fe3ae8dcc42a2d6') collect: f)
         vector: (#('bfd8a427ad392588' '3f8391b889fd3180') collect: f)].
       outcome value: [PBVectorMath score: 'cosine' query: {1.0. 2.0} vector: {0.0. -0.0}].
       outcome value: [PBVectorMath score: 'ip' query: {-0.0} vector: {0.0}].
       outcome value: [PBVectorMath score: 'l2' query: {f value: '7fe1ccf385ebc8a0'. (f value: '7fe1ccf385ebc8a0') negated}
         vector: {(f value: '7fe1ccf385ebc8a0') negated. f value: '7fe1ccf385ebc8a0'}].
       outcome value: [PBVectorMath score: 'ip' query: {f value: '7fe1ccf385ebc8a0'. f value: '7fe1ccf385ebc8a0'} vector: {1.0. 1.0}].
       outcome value: [PBVectorMath score: 'cosine' query: {f value: '5fef06d5a4bf631f'. f value: '5fef06d5a4bf631f'} vector: {1.0. 1.0}].
       outcome value: [PBVectorMath score: 'euclid' query: {1.0} vector: {1.0}].
       PBVectorMath scoreFloor: 'l2' threshold: 1.5. PBVectorMath scoreFloor: 'cosine' threshold: 0.3.
       PBVectorMath scoreFloor: 'ip' threshold: -2.25. PBVectorMath scoreFloor: 'l2' threshold: nil.
       hexes value: (PBVectorMath normalized: {3.0. 4.0}).
       hexes value: (PBVectorMath normalized: {f value: '16687e92154ef7ac'. f value: '16687e92154ef7ac'}).
       hexes value: (PBVectorMath normalized: {0.0. -0.0})}
  equals: {'bfbb2ee618ac3b51'. 'bfe448e38eea804a'. '0000000000000000'. '0000000000000000'. 'fff0000000000000'.
           'refused: intermediate overflow in fsum'. 'refused: intermediate overflow in fsum'.
           'refused: Unknown metric ''euclid''; expected one of [''cosine'', ''l2'', ''ip'']'.
           -1.5. 0.3. -2.25. nil.
           #('3fe3333333333333' '3fe999999999999a'). #('16687e92154ef7ac' '16687e92154ef7ac'). #('0000000000000000' '8000000000000000')}.

"--- 9. rank: nearest first, ties by the member key's order key ---"
entries := {{5. 'a'. 1. {1.0. 0.0}}. {'m'. 'b'. 2. {0.0. 1.0}}. {-3. 'c'. 1. {0.0. -1.0}}.
  {tuple value: {1. 'x'}. 'd'. 3. {-1.0. 0.0}}. {2.5. 'e'. 1. {1.0. 0.0}}. {'k'. 'f'. 1. {2.0. 0.0}}.
  {0. 'g'. 2. {-0.0. 0.0}}}.
ranked := [:q :m :k :t | (PBVectorMath rank: entries query: q metric: m k: k threshold: t)
  collect: [:pair | (pair at: 1) , (pair at: 2) printString]].
c that: 'rank: answers {element. count} nearest first, ties by the member key''s order key; k is cut as Python''s del scored[k:] (0 and negative k included)'
  is: {ranked value: {1.0. 1.0} value: 'cosine' value: nil value: nil.
       ranked value: {1.0. 0.0} value: 'cosine' value: 3 value: nil.
       ranked value: {1.0. 0.0} value: 'cosine' value: nil value: 0.5.
       ranked value: {0.0. 0.0} value: 'l2' value: nil value: nil.
       ranked value: {1.0. 0.0} value: 'l2' value: 3 value: nil.
       ranked value: {1.0. 0.0} value: 'l2' value: nil value: 0.5.
       ranked value: {0.0. 0.0} value: 'ip' value: nil value: nil.
       ranked value: {1.0. 0.0} value: 'ip' value: 3 value: nil.
       ranked value: {1.0. 0.0} value: 'ip' value: nil value: 0.5.
       ranked value: {1.0. 0.0} value: 'ip' value: 0 value: nil.
       ranked value: {1.0. 0.0} value: 'ip' value: -1 value: nil.
       ranked value: {1.0. 0.0} value: 'ip' value: -3 value: nil.
       ranked value: {1.0. 0.0} value: 'ip' value: -10 value: nil}
  equals: {#('e1' 'a1' 'f1' 'b2' 'g2' 'c1' 'd3'). #('e1' 'a1' 'f1'). #('e1' 'a1' 'f1').
           #('g2' 'c1' 'e1' 'a1' 'b2' 'd3' 'f1'). #('e1' 'a1' 'g2'). #('e1' 'a1').
           #('c1' 'g2' 'e1' 'a1' 'f1' 'b2' 'd3'). #('f1' 'e1' 'a1'). #('f1' 'e1' 'a1'). #().
           #('f1' 'e1' 'a1' 'c1' 'g2' 'b2'). #('f1' 'e1' 'a1' 'c1'). #()}.

"--- 10. The three squares (2.2.2, 2.5 step 3) ---"
x := 130492547.0.
witness := PBVectorMath kmeans: {{0.0. 0.0}. {99924809.0. 132238537.0}. {111524509.0. 122614363.0}}
  nlist: 2 iterations: 1 seed: 0.
c that: 'three squares: x * x in scores and norms, raisedTo: 2 (libm pow) in k-means, on half-way cases'
  is: {hex value: x * x. hex value: (x raisedTo: 2). hex value: (x negated raisedTo: 2).
       hex value: (PBVectorMath score: 'l2' query: {x} vector: {0.0}).
       hex value: (PBVectorMath score: 'l2' query: {x. 3.0} vector: {0.0. 1.0}).
       witness collect: [:centroid | hexes value: centroid]}
  equals: {'434e3f9396099984'. '434e3f9396099985'. '434e3f9396099985'. 'c19f1ca20c000000'. 'c19f1ca20c000001'.
           {#('4197d2ed24000000' '419f873324000000'). #('418a96ea74000000' '418d3bc96c000000')}}.

"--- 11. trainingOrderOf: (vector_backends.py:555-558) ---"
vs := {{-1.0. 0.0}. {1.0. 0.0}. {0.0. 0.0}. {-0.0. 0.0}. {0.0. -0.0}. {1.0. -1.0}}.
sorted := (1 to: vs size) asArray sort: [:i :j | | a b |
  a := PBVectorMath trainingOrderOf: (vs at: i). b := PBVectorMath trainingOrderOf: (vs at: j).
  a < b or: [a = b and: [i <= j]]].
c that: 'trainingOrderOf: is the vector''s big-endian IEEE bytes as one unsigned Integer'
  is: {PBVectorMath trainingOrderOf: {1.0. -1.0}. PBVectorMath trainingOrderOf: (tuple value: {-0.0}).
       PBVectorMath trainingOrderOf: {}. sorted}
  equals: {(Check bytes: '3ff0000000000000bff0000000000000') unsignedIntegerFrom: 1 to: 16 bigEndian: true.
           16r8000000000000000. 0. #(3 5 2 6 4 1)}.

"--- 12. The IEEE self-test of 2.2.3 ---"
hi := 1.0e16 + 1.0. yr := hi - 1.0e16. lo := 1.0 - yr.
c that: 'IEEE self-test: TwoSum keeps its low part, signed zeros, subnormals, half-way products, sqrt, pow'
  is: {hex value: hi. hex value: lo. hex value: -0.0 + -0.0. hex value: -0.0 + 0.0. hex value: -0.0 * 1.0.
       hex value: (f value: '0000000000000001') + (f value: '0000000000000001').
       hex value: (f value: '0010000000000000') - (f value: '000fffffffffffff').
       hex value: (f value: '0000000000000001') * 0.5. hex value: x * x. hex value: (x raisedTo: 2).
       hex value: 2.0 sqrt. hex value: 16.0 sqrt. hex value: (f value: '7fefffffffffffff') sqrt. hex value: 1.0 / 3.0}
  equals: #('4341c37937e08000' '3ff0000000000000' '8000000000000000' '0000000000000000' '8000000000000000'
            '0000000000000002' '0000000000000001' '0000000000000000' '434e3f9396099984' '434e3f9396099985'
            '3ff6a09e667f3bcd' '4010000000000000' '5fefffffffffffff' '3fd5555555555555').

"--- 13. The fsum primitives: the feature probe and the test-only switch ---"
version := ((Smalltalk version subStrings: ' ') last subStrings: '.') collect: [:each | each asNumber].
released := ((version at: 1) * 1000000) + ((version at: 2) * 1000) + (version at: 3) >= 15000.
paths := OrderedCollection new.
paths add: { PBVectorMath hasFsumPrimitive. PBVectorMath usesFsumPrimitive }.
PBVectorMath _forceSmalltalkKernel: true.
paths add: { PBVectorMath hasFsumPrimitive. PBVectorMath usesFsumPrimitive }.
PBVectorMath _forceSmalltalkKernel: false.
paths add: { PBVectorMath hasFsumPrimitive. PBVectorMath usesFsumPrimitive }.
c that: 'the probe selects the fsum primitives from protoST 0.15.0 on; the switch forces the Smalltalk kernel'
  is: { (Float respondsTo: #fsum:) = released. paths asArray }
  equals: { true. { { released. released }. { released. false }. { released. released } } }.

"--- 14. The same answers and errors on both paths ---"
"Each case's outcome (a Float as its hex, or the error's class and text) with the primitives (when
 the binary has them) and with the Smalltalk kernel forced: both must be the expected one."
paths := { false. true } collect: [:forced |
  PBVectorMath _forceSmalltalkKernel: forced.
  [ { [PBVectorMath fsum: #(1.0e16 1.0 1.0e-16)].
      [PBVectorMath fsum: (tuple value: #(1.0e308 1.0e308 -1.0e308))].
      [PBVectorMath fsum: {Float infinity. Float infinity negated}].
      [PBVectorMath fsum: {1.0. Float infinity. 2.0}].
      [PBVectorMath fsum: #()].
      [PBVectorMath sumNonNegative: #(1.0e308 1.0e308)].
      [PBVectorMath sumNonNegative: (list value: #(0.5 0.25))].
      [PBVectorMath fsum: #(1 2 0.5)].
      [PBVectorMath score: 'ip' query: #(1.0e308 1.0e308) vector: #(1.0 1.0)].
      [PBVectorMath score: 'ip' query: (tuple value: #(1.0 2.0 3.0)) vector: (tuple value: #(4.0 5.0))].
      [PBVectorMath score: 'l2' query: #(1.0e308 0.0) vector: #(-1.0e308 0.0)].
      [PBVectorMath score: 'l2' query: (tuple value: #(0.1 0.2 0.3)) vector: #(0.3 0.2)].
      [PBVectorMath score: 'cosine' query: (tuple value: #(1.0e200 1.0e200)) vector: (tuple value: #(1.0e200 -1.0e199))].
      [PBVectorMath score: 'cosine' query: #(1.0 2.0) vector: #(1 2)].
      [PBVectorMath score: 'cosine' query: #(0.0 0.0) vector: #(1.0 2.0)].
      [PBVectorMath normalized: (tuple value: #(3.0 4.0))].
      [PBVectorMath canonicalVector: (tuple value: #(1.0e200 1.0e200)) dim: 2] }
    collect: [:block | outcome value: [ | r | r := block value. r isFloat ifTrue: [r] ifFalse: [r isNil ifTrue: ['nil'] ifFalse: [hexes value: r]]]] ]
    ensure: [PBVectorMath _forceSmalltalkKernel: false]].
c that: 'the primitives'' errors become the kernel''s, and both paths answer alike'
  is: { paths first = paths last. paths last }
  equals: { true. { '4341c37937e08001'. 'refused: intermediate overflow in fsum'. 'refused: -inf + inf in fsum'. '7ff0000000000000'.
    '0000000000000000'. '7ff0000000000000'. '3fe8000000000000'. '400c000000000000'. 'refused: intermediate overflow in fsum'.
    '402c000000000000'. 'fff0000000000000'. 'bfc9999999999999'. 'refused: -inf + inf in fsum'. '3ff0000000000000'. '0000000000000000'.
    #('3fe3333333333333' '3fe999999999999a'). 'nil' } }.

"--- 15. The k-means distance's primitive: its own probe and the same switch ---"
released16 := ((version at: 1) * 1000000) + ((version at: 2) * 1000) + (version at: 3) >= 16000.
paths := OrderedCollection new.
paths add: { PBVectorMath hasPowSquaresPrimitive. PBVectorMath usesPowSquaresPrimitive }.
PBVectorMath _forceSmalltalkKernel: true.
paths add: { PBVectorMath hasPowSquaresPrimitive. PBVectorMath usesPowSquaresPrimitive }.
PBVectorMath _forceSmalltalkKernel: false.
paths add: { PBVectorMath hasPowSquaresPrimitive. PBVectorMath usesPowSquaresPrimitive }.
c that: 'the k-means distance primitive is probed on its own, from protoST 0.16.0 on; the switch forces the Smalltalk loop'
  is: { (Float respondsTo: #fsumOfPowSquaredDifferences:with:) = released16. paths asArray }
  equals: { true. { { released16. released16 }. { released16. false }. { released16. released16 } } }.

"--- 16. The k-means distance and centroids: the same bytes on both paths ---"
seedPow := 4242.
nextPow := [seedPow := (seedPow * 1103515245 + 12345) \\ 2147483648. (seedPow / 2147483648.0) * 10.0 - 5.0].
data := (1 to: 120) asArray collect: [:i | tuple value: ((1 to: 5) asArray collect: [:j | nextPow value])].
paths := { false. true } collect: [:forced |
  PBVectorMath _forceSmalltalkKernel: forced.
  [ { hex value: (PBVectorMath _kmeansDistance: {x} to: {0.0}).
      hex value: (PBVectorMath _kmeansDistance: {0.0} to: {x}).
      hex value: (PBVectorMath _kmeansDistance: {x. 3.0} to: {0.0. 1.0}).
      hex value: (PBVectorMath _kmeansDistance: {1.0e200. 1.0} to: {-1.0e200. 0.0}).
      hex value: (PBVectorMath _kmeansDistance: {1.0e154. 1.0e154} to: {0.0. 0.0}).
      hex value: (PBVectorMath _kmeansDistance: #(1 2) to: #(0.5 0.5)).
      hex value: (PBVectorMath _kmeansDistance: (tuple value: #(0.1 0.2 0.3)) to: #(0.3 0.2)).
      (PBVectorMath kmeans: data nlist: 7 iterations: 6 seed: 13) collect: [:centroid | hexes value: centroid].
      witness := PBVectorMath kmeans: {{0.0. 0.0}. {99924809.0. 132238537.0}. {111524509.0. 122614363.0}}
        nlist: 2 iterations: 1 seed: 0.
      witness collect: [:centroid | hexes value: centroid] } ]
    ensure: [PBVectorMath _forceSmalltalkKernel: false]].
c that: 'the k-means distance answers the same bytes with the pow primitive and with the Smalltalk loop'
  is: { paths first = paths last. (paths last copyFrom: 1 to: 7). paths last last }
  equals: { true. #('434e3f9396099985' '434e3f9396099985' '434e3f9396099987' '7ff0000000000000' '7ff0000000000000' '4004000000000000' '3fa47ae147ae147a').
    {#('4197d2ed24000000' '419f873324000000'). #('418a96ea74000000' '418d3bc96c000000')} }.

"--- 17. scorerFor:query: answers what score:query:vector: answers, score after score ---"
scorerCases := {
  {'cosine'. {1.0. 2.0. 3.0}. {{4.0. 5.0. 6.0}. {0.0. 0.0. 0.0}. {-1.0. 0.5. 2.0}. {7.0. 8.0}}}.
  {'cosine'. {0.0. 0.0}. {{1.0. 2.0}. {3.0. 4.0}}}.
  {'cosine'. {f value: '5fef06d5a4bf631f'. f value: '5fef06d5a4bf631f'}. {{1.0. 1.0}. {2.0. 3.0}}}.
  {'cosine'. {1.0. 2.0}. {{f value: '5fef06d5a4bf631f'. 1.0}. {1.0. 3.0}}}.
  {'cosine'. #(1 2). {#(3 4). {0.5. 0.25}}}.
  {'cosine'. tuple value: {(f value: '3fe59ae0a7548546'). (f value: '3fbce794bb052320'). (f value: '3fd236b3a19999e0')}.
    {tuple value: {(f value: 'bfe41a1c9af715d4'). (f value: '3fef85d4cdca033e'). (f value: '3fe7095d2a5f01ec')}. list value: {1.0. -0.0. 2.0}}}.
  {'l2'. {1.0. 2.0}. {{4.0. 6.0}. {1.0}. {f value: '7fe1ccf385ebc8a0'. (f value: '7fe1ccf385ebc8a0') negated}}}.
  {'l2'. tuple value: {0.0. 0.0}. {tuple value: {3.0. 4.0}. #(1 1)}}.
  {'ip'. {1.0. 2.0}. {{3.0. 4.0}. {f value: '7fe1ccf385ebc8a0'. f value: '7fe1ccf385ebc8a0'}. {-0.0. 0.0}. {1.0. 1.0. 1.0}}}.
  {'euclid'. {1.0}. {{1.0}. {2.0}}} }.
viaScore := { false. true } collect: [:forced |
  PBVectorMath _forceSmalltalkKernel: forced.
  [scorerCases collect: [:case |
    (case at: 3) collect: [:v | outcome value: [PBVectorMath score: (case at: 1) query: (case at: 2) vector: v]]]]
    ensure: [PBVectorMath _forceSmalltalkKernel: false]].
refusedAtCreation := false.
viaScorer := { false. true } collect: [:forced |
  PBVectorMath _forceSmalltalkKernel: forced.
  [scorerCases collect: [:case | | scorer |
    scorer := [PBVectorMath scorerFor: (case at: 1) query: (case at: 2)]
      on: PBValidationError do: [:e | refusedAtCreation := true. e return: nil].
    "Each vector twice: the second score reuses what the first computed."
    (case at: 3) collect: [:v | | first second |
      first := outcome value: [scorer value: v].
      second := outcome value: [scorer value: v].
      first = second ifTrue: [first] ifFalse: [{first. second}]]]]
    ensure: [PBVectorMath _forceSmalltalkKernel: false]].
c that: 'scorerFor:query: answers score:query:vector:''s bytes and refusals at every score, on both kernels; nothing is refused when it is made'
  is: { viaScorer = viaScore. viaScore first = viaScore last. refusedAtCreation. (viaScore first at: 3) first. (viaScore first at: 10) first }
  equals: { true. true. false. 'refused: intermediate overflow in fsum'. 'refused: Unknown metric ''euclid''; expected one of [''cosine'', ''l2'', ''ip'']' }.

c report displayNl.
