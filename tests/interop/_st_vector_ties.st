"Ties among atoms in an exact vector search (vectors phase V8, fix round 2; Addendum V, 2.4 and
 2.5): protoBaseST's side of tests/interop/vector_ties_identical.sh. The same 200 PBObjects
 { i. vec } of dim 4 as py_vector_ties.py, an exact index (ip, then cosine), a zero query, k = 10:
 every score is 0.0, so the answer is the tie rule's alone, PBVectorMath rank:'s (-score, order
 key of the member key), whose member key of an atom orders by its oid. Twice: with the random
 version-4 oids a new atom draws on first need (as proto_db's, D21), where the answer must be the
 ten records of least order key, ascending, in this process; then with injected oids (record i
 gets the 16-byte oid of the Integer (37 i mod 200) + 1, published by _publishOid:), where the
 answer must be proto_db's list. The lines are py_vector_ties.py's, Python's list form included."
Import from: 'protobase'.
| n dim vec zero run recs pyList |
n := 200. dim := 4.
vec := [:i | PBTuple withAll: ((0 to: dim - 1) asArray collect: [:j | (((i * 7 + (j * 3)) \\ 11) - 5) asFloat + 0.5])].
zero := PBTuple withAll: ((1 to: dim) asArray collect: [:j | 0.0]).
run := [:rs :m | | idx |
  idx := (PBVectorIndex name: 'by_vec' keySpec: (PBKeySpec path: 'vec') dim: dim metric: m) build: rs.
  ((PBVectorSearch index: idx term: (PBTerm path: 'vec' op: 'near[]' value: (PBNearQuery vector: zero k: 10)) where: nil)
    execute collect: [:e | e at: 'i']) asArray].
pyList := [:anArray | '[' , (', ' join: (anArray collect: [:x | x printString])) , ']'].
recs := (0 to: n - 1) asArray collect: [:i | PBObject withAll: { 'i' -> i. 'vec' -> (vec value: i) }].
#('ip' 'cosine') do: [:m | | byOid |
  byOid := ((recs asArray sort: [:a :b | (PBKeys orderKey: a) <= (PBKeys orderKey: b)]) copyFrom: 1 to: 10)
    collect: [:r | r at: 'i'].
  ('random-oids ' , m , ' answer-is-oid-order ' , ((run value: recs value: m) = byOid ifTrue: ['True'] ifFalse: ['False'])) displayNl].
recs := (0 to: n - 1) asArray collect: [:i | PBObject withAll: { 'i' -> i. 'vec' -> (vec value: i) }].
recs do: [:r | | v |
  v := (((r at: 'i') * 37) \\ n) + 1.
  r _publishOid: (ByteArray new: 14) , (ByteArray withAll: { v // 256. v \\ 256 })].
#('ip' 'cosine') do: [:m | ('injected-oids ' , m , ' ' , (pyList value: (run value: recs value: m))) displayNl].
'end' displayNl.
