"EXPECT: ok 24"
"Review Focus 1 (plan Task 12): keys written by ProtoBase are found from protoST by
 their order keys. The space is written by ProtoBase v2.0.0rc1
 (tests/interop/py_make_keys_space.py, through the helper _make_keys_space.sh) into a
 temporary directory: a Dictionary, a HashDictionary, a Set and a CountedSet holding the
 int 1, the int 10**16 + 1 and the float 1.0e16. 1.0 and Decimal 1.00 find the key 1,
 true does not, and 10**16 + 1 and 1.0e16 are two keys. SKIP without the interop venv."
Import from: 'protobase'.
Import from: '_check'.

| c base made space tx d h s cs big bigFloat |
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
space close.
base deleteAll.
c report displayNl.
