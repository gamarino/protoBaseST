"EXPECT: ok 75"
"Review Focus 1 (plan Task 12): keys written by ProtoBase are found from protoST by
 their order keys. The space is written by ProtoBase v2.0.0rc1
 (tests/interop/py_make_keys_space.py, through the helper _make_keys_space.sh) into a
 temporary directory: a Dictionary, a HashDictionary, a Set and a CountedSet holding the
 int 1, the int 10**16 + 1 and the float 1.0e16. 1.0 and Decimal 1.00 find the key 1,
 true does not, and 10**16 + 1 and 1.0e16 are two keys.
 The lookup rules are pinned with keys = cannot find: the tuple (1, 'x') is found by
 (1.0, 'x') and (Decimal 1.00, 'x'), which protoST's = calls different but whose order
 keys are equal (a bucket scan comparing with = fails here); a stored Decimal('1.00') is
 found by 1, 1.0 and Decimal 1; True stored next to 1 is a second key. Each probe goes
 through PBCodec canonical: first; that step is pinned by a String holding a lone
 surrogate, which PBKeys orderKey: accepts and canonical: refuses (PBValidationError).
 This last check is the codec's documented refusal (plan Task 4), not ProtoBase parity:
 Python's canonical accepts lone surrogates. Keys float('inf') and float('-inf') written
 by ProtoBase in a plain map, a Dictionary and a HashDictionary (whose buckets hash the
 infinities) are found by Float and Decimal infinities (review I1 of plan Task 13). SKIP without the interop venv."
Import from: 'protobase'.
Import from: '_check'.

| c base made space tx d h s cs big bigFloat tupleProbes surrogate |
base := FileSystem temp / ('pbst-cross-keys-' , Smalltalk pid printString).
made := OSProcess run: 'bash' arguments: { '../interop/_make_keys_space.sh'. base pathString }.
made exitCode = 77 ifTrue: [
  'SKIP: the interop venv is missing (run tests/interop/setup_venv.sh)' displayNl.
  Smalltalk exit: 0].
made exitCode = 0 ifFalse: [
  ('FAIL: the Python writer exited ' , made exitCode printString , ': ' , made errorOutput) displayNl.
  Smalltalk exit: 1].
c := Check new.
big := (10 raisedTo: 16) + 1.
bigFloat := 1.0e16.
space := PBObjectSpace storage: (PBFileStorage path: base).
tx := (space openDatabase: 'keys') history first.
tx := (space openDatabase: 'keys') snapshotAt: tx.
d := tx getRootObject: 'd'.
h := tx getRootObject: 'h'.
s := tx getRootObject: 's'.
cs := tx getRootObject: 'cs'.
{ 'Dictionary' -> d. 'HashDictionary' -> h } do: [:each |
  | m |
  m := each value.
  c that: each key , ' count' is: m count equals: 3.
  c that: each key , ' getAt: 1' is: (m getAt: 1) equals: 'one'.
  c that: each key , ' getAt: 1.0' is: (m getAt: 1.0) equals: 'one'.
  c that: each key , ' getAt: Decimal 1.00' is: (m getAt: (Decimal fromString: '1.00')) equals: 'one'.
  c that: each key , ' getAt: true misses' is: (m getAt: true) equals: nil.
  c that: each key , ' getAt: true default:' is: (m getAt: true default: #none) equals: #none.
  c that: each key , ' 10**16 + 1' is: (m getAt: big) equals: 'big int'.
  c that: each key , ' 1.0e16' is: (m getAt: bigFloat) equals: 'big float'].
c that: 'Set has: 1.0' isTrue: (s has: 1.0).
c that: 'Set has: Decimal 1.00' isTrue: (s has: (Decimal fromString: '1.00')).
c that: 'Set has: true is false' is: (s has: true) equals: false.
c that: 'Set: 10**16 + 1 and 1.0e16 are two elements' is: s count equals: 3.
c that: 'CountedSet countOf: 1.0' is: (cs countOf: 1.0) equals: 2.
c that: 'CountedSet countOf: true' is: (cs countOf: true) equals: 0.
c that: 'CountedSet countOf: 10**16 + 1' is: (cs countOf: big) equals: 0.
c that: 'CountedSet countOf: 1.0e16' is: (cs countOf: bigFloat) equals: 1.

tupleProbes := { PBTuple withAll: { 1. 'x' }. PBTuple withAll: { 1.0. 'x' }. PBTuple withAll: { Decimal fromString: '1.00'. 'x' } }.
c that: 'protoST''s = tells (1, ''x'') from (1.0, ''x'')' is: (tupleProbes first = (tupleProbes at: 2)) equals: false.
tupleProbes do: [:probe |
  | label |
  label := ' ' , (PBNotation describe: probe) printString.
  c that: 'Dictionary getAt:' , label is: ((tx getRootObject: 'td') getAt: probe) equals: 'tuple'.
  c that: 'HashDictionary getAt:' , label is: ((tx getRootObject: 'th') getAt: probe) equals: 'tuple'.
  c that: 'Set has:' , label isTrue: ((tx getRootObject: 'ts') has: probe).
  c that: 'CountedSet countOf:' , label is: ((tx getRootObject: 'tcs') countOf: probe) equals: 2].

{ 1. 1.0. Decimal fromString: '1' } do: [:probe |
  | label |
  label := ' ' , probe printString , ' finds Decimal 1.00'.
  c that: 'Dictionary getAt:' , label is: ((tx getRootObject: 'dd') getAt: probe) equals: 'dec'.
  c that: 'HashDictionary getAt:' , label is: ((tx getRootObject: 'dh') getAt: probe) equals: 'dec'.
  c that: 'Set has:' , label isTrue: ((tx getRootObject: 'ds') has: probe).
  c that: 'CountedSet countOf:' , label is: ((tx getRootObject: 'dcs') countOf: probe) equals: 2].
c that: 'a stored Decimal key reads back as a Decimal' isTrue: ((tx getRootObject: 'dd') keys first isKindOf: Decimal).

{ 'Dictionary' -> (tx getRootObject: 'bd'). 'HashDictionary' -> (tx getRootObject: 'bh') } do: [:each |
  c that: each key , ' true and 1: two keys' is: each value count equals: 2.
  c that: each key , ' getAt: true' is: (each value getAt: true) equals: 'true'.
  c that: each key , ' getAt: 1' is: (each value getAt: 1) equals: 'one'.
  c that: each key , ' getAt: 1.0' is: (each value getAt: 1.0) equals: 'one'].

{ 'map' -> (tx getRootObject: 'inf'). 'Dictionary' -> (tx getRootObject: 'infd'). 'HashDictionary' -> (tx getRootObject: 'infh') } do: [:each |
  | m get |
  m := each value.
  get := (m isKindOf: PBFrozenDict)
    ifTrue: [[:k | m at: k ifAbsent: [nil]]]
    ifFalse: [[:k | m getAt: k]].
  c that: each key , ' keyed by infinity' is: (get value: Float infinity) equals: 'up'.
  c that: each key , ' keyed by -infinity' is: (get value: Float infinity negated) equals: 'down'.
  c that: each key , ' found by Decimal Infinity' is: (get value: (Decimal fromString: 'Infinity')) equals: 'up'].
c that: 'the plain map has three keys' is: (tx getRootObject: 'inf') size equals: 3.
c that: 'Dictionary: the infinities sort at the ends' is: (tx getRootObject: 'infd') keys asArray
  equals: { Float infinity negated. 2. Float infinity }.

surrogate := String with: (Character value: 16rD800).
c that: 'orderKey: accepts a lone surrogate' isTrue: (PBKeys orderKey: surrogate) notNil.
c that: 'Dictionary getAt: a lone surrogate' signals: PBValidationError during: [d getAt: surrogate].
c that: 'HashDictionary getAt: a lone surrogate' signals: PBValidationError during: [h getAt: surrogate].
c that: 'Dictionary has: a lone surrogate' signals: PBValidationError during: [d has: surrogate].
c that: 'Set has: a lone surrogate' signals: PBValidationError during: [s has: surrogate].
c that: 'CountedSet countOf: a lone surrogate' signals: PBValidationError during: [cs countOf: surrogate].
space close.
base deleteAll.
c report displayNl.
