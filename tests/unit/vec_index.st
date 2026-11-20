"EXPECT: ok 11"
"Vectors phase V3 (Addendum V, 2.3, 2.4, 2.11 and 5.1): PBVectorIndex as a structure, with the exact
 and hnsw backends, against proto_db v2.0.0rc4 (proto_db/indexing/vector.py:125-268 and 323-425,
 vector_backends.py:305-333, 480-490, 566-586 and 751-770, keyed.py:190-215). The behaviours of
 tests/unit/test_vector_index.py's test_definition_type_names_and_validation and
 test_with_removed_of_an_absent_element_raises, the exact half of
 test_validate_detects_structural_corruption (its ivf half is V4's), and test_format_neutral.py's
 test_vector_removal_is_exact_too and test_validate_accepts_a_vector_index_with_format_3_tokens
 (mapped in tests/unit/queries_checklist.tsv); the first fault of a definition with two (2.3,
 'Validation order'), every text taken from proto_db at the tag; PBVectorIvfFlat check: (its
 defaults and order); the retrain_growth refusals (deviation DV7 e) and the signalling-NaN
 refusals (DV7 b); elements whose key is not a vector kept aside; the node classes of the invalid
 tree (2.11 item 3); the two containers a store key adds to the depth limit (keyed.py
 check_member_key's outer). Each check gathers its mismatches and requires none, so one label
 covers one behaviour."
Import from: 'protobase'.
Import from: '_check'.

| c fails expect refused msg rec tup vi defs index elements entry key value store tampered legacy
  invalids valids built grown text deep sNaN at over |
c := Check new.
expect := [:label :actual :expected |
  actual = expected ifFalse: [fails add: label , ': expected ' , expected printString , ', got ' , actual printString]].
refused := [:aBlock | [aBlock value. nil] on: Error do: [:e | e return: e class]].
msg := [:aBlock | [aBlock value. 'no error'] on: Error do: [:err | err return: err class name , ': ' , err messageText]].
rec := [:v | PBObject withAll: { 'vec' -> v }].
tup := [:anArray | PBTuple withAll: anArray].
"PBVectorIndex name: 'v' keySpec: (path 'vec') dim: d metric: m backend: b params: p."
vi := [:d :m :b :p | PBVectorIndex name: 'v' keySpec: (PBKeySpec path: 'vec') dim: d metric: m backend: b params: p].
defs := [:assocs | | d | d := Dictionary new. assocs do: [:a | d at: a key put: a value]. d].

"test_definition_type_names_and_validation, and 2.3's validation order: each definition below
 has two faults, and the first one proto_db checks is the one reported, with proto_db's text
 (taken from proto_db at the tag; the name's text is protoBaseST's, 'String' for 'str')."
fails := OrderedCollection new.
index := PBVectorIndex name: 'v' keySpec: (PBKeySpec path: 'vec') dim: 4.
expect value: 'the defaults' value: { index dim. index metric. index backend. index params. index keySpecObject }
  value: { 4. 'cosine'. 'exact'. tup value: { tup value: { 'numpy'. true } }. PBKeySpec path: 'vec' }.
expect value: 'the type name' value: PBVectorIndex typeName value: 'proto_db.indexing.VectorIndex'.
expect value: 'the fields' value: index state keys value: PBVectorIndex persistedFields.
expect value: 'the empty state' value: { index store. index invalid. index totalCount. index centroids. index trainedSize.
    index stateAt: 'member_tokens'. index memberCount. index invalidCount. index isSaved }
  value: { nil. tup value: { nil. 0 }. 0. tup value: #(). 0. 1. 0. 0. false }.
expect value: 'name:keySpec:dim:metric:' value: (PBVectorIndex name: 'v' keySpec: (PBKeySpec path: 'vec') dim: 4 metric: 'l2') metric
  value: 'l2'.
expect value: 'name:path:dim:metric:' value: (PBVectorIndex name: 'v' path: 'vec' dim: 4 metric: 'ip') state
  value: (PBVectorIndex name: 'v' keySpec: (PBKeySpec path: 'vec') dim: 4 metric: 'ip' backend: 'exact' params: nil) state.
index := vi value: 4 value: 'l2' value: 'ivf_flat' value: (defs value: { 'nlist' -> 8. 'nprobe' -> 2 }).
expect value: 'ivf params' value: { index paramAt: 'nlist'. index paramAt: 'nprobe'. index paramAt: 'absent' } value: #(8 2 nil).
expect value: 'hnsw params sorted by code point' value: (vi value: 2 value: 'cosine' value: 'hnsw' value: nil) params
  value: (tup value: { tup value: #('M' 16). tup value: #('ef_construction' 200). tup value: #('ef_search' 64). tup value: #('seed' 0) }).
expect value: 'a PBFrozenDict of params' value: (vi value: 2 value: 'l2' value: 'exact' value: (PBFrozenDict withAssociations: { 'numpy' -> false })) params
  value: (tup value: { tup value: { 'numpy'. false } }).
{ [PBVectorIndex name: '' keySpec: (PBKeySpec path: 'vec') dim: 0] -> 'PBValidationError: An index needs a non-empty String name, not '''''.
  [vi value: 0 value: 'dot' value: 'exact' value: nil] -> 'PBValidationError: A vector index needs an int dim >= 1, not 0'.
  [vi value: true value: 'cosine' value: 'exact' value: nil] -> 'PBValidationError: A vector index needs an int dim >= 1, not True'.
  [vi value: 2.0 value: 'cosine' value: 'exact' value: nil] -> 'PBValidationError: A vector index needs an int dim >= 1, not 2.0'.
  [vi value: 2 value: 'dot' value: 'annoy' value: nil] -> 'PBValidationError: Unknown vector metric ''dot''; expected one of [''cosine'', ''l2'', ''ip'']'.
  [vi value: 2 value: 'cosine' value: 'annoy' value: (defs value: { 'zz' -> 1 })] -> 'PBValidationError: Unknown vector backend ''annoy''; expected one of [''exact'', ''ivf_flat'', ''hnsw'']'.
  [vi value: 2 value: 'cosine' value: 'exact' value: (defs value: { 'nlist' -> 3. 'numpy' -> 'x' })] -> 'PBValidationError: Unknown parameters [''nlist''] for the ''exact'' vector backend; expected [''numpy'']'.
  [vi value: 2 value: 'cosine' value: 'exact' value: (defs value: { 'numpy' -> 1 })] -> 'PBValidationError: Vector index parameter ''numpy'' must be a bool, not 1'.
  [vi value: 2 value: 'cosine' value: 'hnsw' value: (defs value: { 'M' -> 1. 'ef_search' -> 0 })] -> 'PBValidationError: Vector index parameter ''M'' must be >= 2, not 1'.
  [vi value: 2 value: 'cosine' value: 'hnsw' value: (defs value: { 'M' -> true })] -> 'PBValidationError: Vector index parameter ''M'' must be an int >= 1, not True'.
  [vi value: 2 value: 'cosine' value: 'hnsw' value: (defs value: { 'seed' -> -1. 'ef_construction' -> 0 })] -> 'PBValidationError: Vector index parameter ''seed'' must be an int >= 0, not -1'.
  [vi value: 2 value: 'cosine' value: 'hnsw' value: (defs value: { 'ef_construction' -> 0. 'ef_search' -> 0 })] -> 'PBValidationError: Vector index parameter ''ef_construction'' must be an int >= 1, not 0'.
  [vi value: 2 value: 'cosine' value: 'hnsw' value: (defs value: { 'zz' -> 1. 'aa' -> 2 })] -> 'PBValidationError: Unknown parameters [''aa'', ''zz''] for the ''hnsw'' vector backend; expected [''M'', ''ef_construction'', ''ef_search'', ''seed'']'.
  [vi value: 2 value: 'cosine' value: 'ivf_flat' value: (defs value: { 'nlist' -> 4. 'nprobe' -> 5 })] -> 'PBValidationError: nprobe (5) cannot exceed nlist (4)'.
  [vi value: 2 value: 'cosine' value: 'exact' value: #(1 2)] -> 'PBValidationError: PBVectorIndex params must be nil, a Dictionary or a PBFrozenDict of parameter names to values, not #(1 2)'.
  [vi value: 2 value: 'cosine' value: 'exact' value: (defs value: { 1 -> true })] -> 'PBValidationError: PBVectorIndex parameter names must be Strings, not 1'.
  [PBVectorIndex name: 'v' keySpec: 'vec' dim: 2] -> 'PBValidationError: key_spec must be a PBKeySpec, not a String'.
  [PBVectorIndex name: 'v' keySpec: (PBKeySpec path: 'vec')] -> 'PBValidationError: A vector index needs a dim: make it with PBVectorIndex name:keySpec:dim: or name:keySpec:dim:metric:backend:params:'.
  [PBVectorIndex name: 'v' path: 'vec'] -> 'PBValidationError: A vector index needs a dim: make it with PBVectorIndex name:keySpec:dim: or name:keySpec:dim:metric:backend:params:' }
  doWithIndex: [:case :i | expect value: 'definition ' , i printString value: (msg value: case key) value: case value].
expect value: 'PBVectorBackend named:' value: ({ 'exact'. 'ivf_flat'. 'hnsw' } collect: [:n | (PBVectorBackend named: n) kindName])
  value: #('VectorExact' 'VectorIvfFlat' 'VectorHnsw').
index := vi value: 2 value: 'l2' value: 'ivf_flat' value: nil.
{ [index withAdded: (rec value: (tup value: #(1.0 0.0)))]. [index build: #()]. [index explain] } doWithIndex: [:hook :i |
  expect value: 'ivf_flat until V4 ' , i printString value: ((msg value: hook) beginsWith: 'PBNotSupportedError: PBVectorIvfFlat ')
    value: true].
expect value: 'PBVectorBackend named: an unknown name' value: (msg value: [PBVectorBackend named: #('exact')])
  value: 'PBValidationError: Unknown vector backend #(''exact''); expected one of [''exact'', ''ivf_flat'', ''hnsw'']'.
c that: 'the definition is validated in proto_db''s order, with its texts' is: fails asArray equals: #().

"PBVectorIvfFlat check: (vector_backends.py:574-586): the defaults (nprobe min(4, nlist)), the
 completed parameters sorted by name, retrain_growth a Float, and the order nlist, nprobe,
 nprobe > nlist, seed, train_iters, retrain_growth."
fails := OrderedCollection new.
expect value: 'the defaults' value: (vi value: 2 value: 'l2' value: 'ivf_flat' value: nil) params
  value: (tup value: { tup value: #('nlist' 16). tup value: #('nprobe' 4). tup value: #('retrain_growth' 4.0). tup value: #('seed' 0).
    tup value: #('train_iters' 10) }).
expect value: 'nprobe defaults to nlist below 4' value: ((vi value: 2 value: 'l2' value: 'ivf_flat' value: (defs value: { 'nlist' -> 2 })) paramAt: 'nprobe')
  value: 2.
expect value: 'a large seed' value: ((vi value: 2 value: 'l2' value: 'ivf_flat' value: (defs value: { 'seed' -> (2 raisedTo: 70) })) paramAt: 'seed')
  value: (2 raisedTo: 70).
expect value: 'PBVectorIvfFlat check: answers the completed parameters' value: ((PBVectorIvfFlat check: (defs value: { 'nlist' -> 3 })) collect: [:a | a key -> a value])
  value: { 'nlist' -> 3. 'nprobe' -> 3. 'train_iters' -> 10. 'seed' -> 0. 'retrain_growth' -> 4.0 }.
{ { 'nlist' -> 0. 'nprobe' -> 0 } -> 'Vector index parameter ''nlist'' must be an int >= 1, not 0'.
  { 'nlist' -> true } -> 'Vector index parameter ''nlist'' must be an int >= 1, not True'.
  { 'nprobe' -> 0. 'seed' -> -1 } -> 'Vector index parameter ''nprobe'' must be an int >= 1, not 0'.
  { 'nlist' -> 2. 'nprobe' -> 3. 'seed' -> -1 } -> 'nprobe (3) cannot exceed nlist (2)'.
  { 'seed' -> -1. 'train_iters' -> 0 } -> 'Vector index parameter ''seed'' must be an int >= 0, not -1'.
  { 'seed' -> true } -> 'Vector index parameter ''seed'' must be an int >= 0, not True'.
  { 'seed' -> 1.0 } -> 'Vector index parameter ''seed'' must be an int >= 0, not 1.0'.
  { 'train_iters' -> 0. 'retrain_growth' -> 1 } -> 'Vector index parameter ''train_iters'' must be an int >= 1, not 0' }
  doWithIndex: [:case :i |
    expect value: 'order ' , i printString value: (msg value: [PBVectorIvfFlat check: (defs value: case key)])
      value: 'PBValidationError: ' , case value].
c that: 'PBVectorIvfFlat check: completes the defaults and checks in proto_db''s order' is: fails asArray equals: #().

"retrain_growth (vector_backends.py _growth, 319-322): a finite number > 1, stored as a Float; an
 Integer beyond the Float range is CPython's OverflowError of math.isfinite, PBValidationError
 with its text (DV7 e)."
fails := OrderedCollection new.
{ 1 -> 'Vector index parameter ''retrain_growth'' must be a finite number > 1, not 1'.
  1.0 -> 'Vector index parameter ''retrain_growth'' must be a finite number > 1, not 1.0'.
  true -> 'Vector index parameter ''retrain_growth'' must be a finite number > 1, not True'.
  (Decimal fromString: '2') -> 'Vector index parameter ''retrain_growth'' must be a finite number > 1, not Decimal(''2'')'.
  '2' -> 'Vector index parameter ''retrain_growth'' must be a finite number > 1, not ''2'''.
  Float infinity -> 'Vector index parameter ''retrain_growth'' must be a finite number > 1, not inf'.
  Float nan -> 'Vector index parameter ''retrain_growth'' must be a finite number > 1, not nan'.
  (10 raisedTo: 400) -> 'int too large to convert to float'.
  (10 raisedTo: 400) negated -> 'int too large to convert to float' } doWithIndex: [:case :i |
    expect value: 'growth ' , i printString value: (msg value: [PBVectorIvfFlat check: (defs value: { 'retrain_growth' -> case key })])
      value: 'PBValidationError: ' , case value].
{ 3 -> 3.0. 1.5 -> 1.5. ((2 raisedTo: 60) + 1) -> 1.152921504606847e18 } do: [:case | | growth |
  growth := (vi value: 2 value: 'l2' value: 'ivf_flat' value: (defs value: { 'retrain_growth' -> case key })) paramAt: 'retrain_growth'.
  expect value: 'growth ' , case key printString value: { growth isFloat. growth } value: { true. case value }].
c that: 'retrain_growth is a finite number above 1, an overflowing Integer refused (DV7 e)' is: fails asArray equals: #().

"test_with_removed_of_an_absent_element_raises: an equal record the index does not hold, and an
 element whose key is not a vector, are PBValidationError."
fails := OrderedCollection new.
index := (PBVectorIndex name: 'v' keySpec: (PBKeySpec path: 'vec') dim: 2) build: { rec value: (tup value: #(1.0 0.0)) }.
expect value: 'an absent record' value: (msg value: [index withRemoved: (rec value: (tup value: #(1.0 0.0)))])
  value: 'PBValidationError: Index ''v'' (VectorIndex on vec) does not hold '
    , (PBKeys _preview: (rec value: (tup value: #(1.0 0.0)))) , '; an index can only remove an element it holds'.
expect value: 'an absent invalid element' value: (refused value: [index withRemoved: (rec value: nil)]) value: PBValidationError.
expect value: 'the receiver is unchanged' value: { index memberCount. index totalCount } value: #(1 1).
c that: 'withRemoved: of an element the index does not hold is PBValidationError' is: fails asArray equals: #().

"The exact half of test_validate_detects_structural_corruption: validate: accepts the build and
 rejects each tampered version (another vector, another count, a zero count, a missing member,
 a member in another list, a wrong total) with PBCorruptionError."
fails := OrderedCollection new.
elements := (1 to: 30) asArray collect: [:i |
  PBObject withAll: { 'i' -> i. 'vec' -> (tup value: { (i * 37 \\ 11) asFloat - 5.0. (i * 13 \\ 7) asFloat / 3.0. (i \\ 5) asFloat }) }].
index := (vi value: 3 value: 'l2' value: 'exact' value: nil) build: elements.
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
  index _with: { 'total_count' -> (index totalCount + 1) } }.
tampered doWithIndex: [:bad :i | expect value: 'tampered ' , i printString value: (refused value: [bad validate: elements]) value: PBCorruptionError].
expect value: 'the message names the index' value: (msg value: [(tampered at: 6) validate: elements])
  value: 'PBCorruptionError: Index ''v'' (VectorIndex on vec) is corrupt: total_count is 31 but 30 occurrences are stored'.
expect value: 'another list' value: (msg value: [(tampered at: 5) validate: elements])
  value: 'PBCorruptionError: Index ''v'' (VectorIndex on vec) is corrupt: element ' , (PBKeys _preview: (value at: 1))
    , ' is in list 1, its vector belongs to 0'.
expect value: 'missing elements' value: (msg value: [index validate: (elements copyFrom: 2 to: 30)])
  value: 'PBCorruptionError: Index ''v'' (VectorIndex on vec) is corrupt: 1 stored occurrences no element accounts for, 0 element occurrences not stored'.
expect value: 'centroids on an exact index' value: (msg value: [(index _with: { 'centroids' -> (tup value: { tup value: #(1.0 0.0 0.0) }). 'trained_size' -> 1 }) validate: elements])
  value: 'PBCorruptionError: Index ''v'' (VectorIndex on vec) is corrupt: a ''exact'' index holds IVF centroids'.
c that: 'validate: catches tampering on an exact index' is: fails asArray equals: #().

"Elements whose key is not a vector of dim finite numbers (absent, nil, another length, a String,
 a Boolean component, a NaN or an infinity, an Integer beyond the Float range, an overflowing
 norm) are kept in the invalid group: explain counts them apart, validate: accepts them, and a
 valid key may be a PBFrozenList, Integers or Decimals (canonical_vector)."
fails := OrderedCollection new.
invalids := { PBObject withAll: { 'other' -> 1 }. rec value: nil. rec value: (tup value: #(1.0 2.0)). rec value: 'abc'.
  rec value: (tup value: { 1.0. true. 0.0 }). rec value: (tup value: { Float nan. 0.0. 0.0 }).
  rec value: (tup value: { Float infinity. 0.0. 0.0 }). rec value: (tup value: { 10 raisedTo: 400. 0. 0 }).
  rec value: (tup value: #(1.0e200 1.0e200 1.0e200)) }.
valids := { rec value: (tup value: #(1 0 0)). rec value: (PBFrozenList withAll: #(0.0 1.0 0.0)).
  rec value: (tup value: { Decimal fromString: '0.5'. 0. -1 }) }.
elements := invalids , valids , { invalids first. valids first }.
index := (vi value: 3 value: 'cosine' value: 'hnsw' value: nil) build: elements.
expect value: 'explain' value: index explain associations
  value: { 'index' -> 'v'. 'kind' -> 'VectorIndex'. 'key' -> 'vec'. 'dim' -> 3. 'metric' -> 'cosine'. 'backend' -> 'hnsw'.
    'params' -> (PBFrozenDict withAssociations: { 'M' -> 16. 'ef_construction' -> 200. 'ef_search' -> 64. 'seed' -> 0 }).
    'entries' -> 14. 'vectors' -> 4. 'members' -> 3. 'invalid' -> 10 }.
expect value: 'readers' value: { index memberCount. index invalidCount. index totalCount } value: #(3 10 14).
value := index storeEntries collect: [:a | (a value at: 3) asArray].
expect value: 'the stored vectors are Floats'
  value: { value size. value allSatisfy: [:v | v allSatisfy: [:x | x isFloat]].
    { #(1.0 0.0 0.0). #(0.0 1.0 0.0). #(0.5 0.0 -1.0) } allSatisfy: [:v | value includes: v] }
  value: { 3. true. true }.
expect value: 'validate:' value: (index validate: elements) == index value: true.
expect value: 'validate: against fewer invalid elements' value: (refused value: [index validate: (elements copyFrom: 2 to: elements size)])
  value: PBCorruptionError.
built := (vi value: 3 value: 'cosine' value: 'hnsw' value: nil) empty.
elements do: [:e | built := built withAdded: e].
expect value: 'the fold counts as the build' value: (built explain = index explain) value: true.
expect value: 'the fold validates' value: (built validate: elements) == built value: true.
built := elements inject: built into: [:acc :e | acc withRemoved: e].
expect value: 'removing every element empties the index' value: { built totalCount. built memberCount. built invalidCount. built store }
  value: #(0 0 0 nil).
c that: 'elements whose key is not a vector are kept aside, counted and validated' is: fails asArray equals: #().

"DV7 b: a signalling-NaN Decimal component of a stored element is PBValidationError with CPython's
 text in withAdded:, withRemoved:, build: and validate:, where proto_db raises Python's ValueError;
 a component that already made the key invalid (a Boolean before it) masks it, as in Python."
fails := OrderedCollection new.
sNaN := rec value: (tup value: { 1.0. Decimal fromString: 'sNaN'. 0.0 }).
index := (vi value: 3 value: 'l2' value: 'exact' value: nil) build: valids.
{ [index withAdded: sNaN]. [index withRemoved: sNaN]. [index build: { valids first. sNaN }]. [index validate: valids , { sNaN }] }
  doWithIndex: [:hook :i |
    expect value: 'sNaN ' , i printString value: (msg value: hook) value: 'PBValidationError: cannot convert signaling NaN to float'].
expect value: 'masked by an earlier invalid component' value: (index withAdded: (rec value: (tup value: { true. Decimal fromString: 'sNaN'. 0.0 }))) invalidCount
  value: 1.
c that: 'a signalling-NaN Decimal component is PBValidationError (DV7 b)' is: fails asArray equals: #().

"test_vector_removal_is_exact_too: (1, 0) and (1.0, 0) are two members; removing (Decimal 1, 0),
 equal to both, is refused; removing (1.0, 0) leaves exactly (1, 0)."
fails := OrderedCollection new.
index := (PBVectorIndex name: 'v' keySpec: PBKeySpec element dim: 2 metric: 'l2') empty build: { tup value: #(1 0). tup value: #(1.0 0) }.
expect value: 'two members' value: index memberCount value: 2.
expect value: 'an equal value is not held' value: ((msg value: [index withRemoved: (tup value: { Decimal fromString: '1'. 0 })]) includesSubstring: 'does not hold')
  value: true.
expect value: 'the exact value is removed' value: ((index withRemoved: (tup value: #(1.0 0))) validate: { tup value: #(1 0) }) class value: PBVectorIndex.
c that: 'removal is exact: an equal value with another token is not removed' is: fails asArray equals: #().

"test_validate_accepts_a_vector_index_with_format_3_tokens: an index whose member keys hold
 another token (format 3: ('T', ())) and no member_tokens validates against its elements, and
 still checks the rest."
fails := OrderedCollection new.
elements := { PBObject withAll: { 'emb' -> (tup value: #(1.0 0.0)) }. PBObject withAll: { 'emb' -> (tup value: #(0.0 1.0)) } }.
index := (PBVectorIndex name: 'v' keySpec: (PBKeySpec path: 'emb') dim: 2) empty build: elements.
store := nil.
index storeEntries do: [:a |
  store := (PBAvl keyPut: store key: (tup value: { a key at: 1. tup value: { (a key at: 2) at: 1. tup value: { 'T'. tup value: #() } } })
    value: a value nodeClass: PBKeyNode) at: 1].
legacy := index _with: { 'store' -> store. 'member_tokens' -> nil }.
expect value: 'format 3' value: { legacy hasMemberTokens. (legacy validate: elements) == legacy. refused value: [legacy validate: (elements copyFrom: 1 to: 1)] }
  value: { false. true. PBCorruptionError }.
expect value: 'current tokens refuse the format-3 keys' value: (refused value: [(legacy _with: { 'member_tokens' -> 1 }) validate: elements])
  value: PBCorruptionError.
c that: 'validate: accepts a vector index with format-3 tokens and still checks the rest' is: fails asArray equals: #().

"2.11 item 3: proto_db's key_put gives a new node the class of the existing root and uses its
 node_class only on an empty tree. A build makes PBKeyNode trees (the store and the invalid
 members); a withAdded: of an invalid element onto a built invalid tree keeps PBKeyNode; onto an
 empty one it grows a PBCountedKeyNode tree (keyed.py group_add). The store grows PBKeyNodes."
fails := OrderedCollection new.
{ 'exact'. 'hnsw' } do: [:b |
  built := (vi value: 3 value: 'l2' value: b value: nil) build: invalids , valids.
  grown := built withAdded: (rec value: 'xyz').
  expect value: b , ' built' value: { (built invalid at: 1) class. built store class } value: { PBKeyNode. PBKeyNode }.
  expect value: b , ' built, then an invalid element' value: { (grown invalid at: 1) class. grown invalidCount } value: { PBKeyNode. 10 }.
  grown := ((vi value: 3 value: 'l2' value: b value: nil) build: valids) withAdded: (rec value: 'xyz').
  expect value: b , ' grown from empty' value: { (grown invalid at: 1) class. grown store class } value: { PBCountedKeyNode. PBKeyNode }.
  grown := (vi value: 3 value: 'l2' value: b value: nil) empty withAdded: valids first.
  expect value: b , ' a store grown from empty' value: grown store class value: PBKeyNode].
expect value: 'the store order key' value: (PBVectorIndex _storeOrderKey: 0 memberOrderKey: (PBKeys orderKey: (PBMemberKeys memberKeyOf: valids first)))
  value: (PBKeys orderKey: (tup value: { 0. PBMemberKeys memberKeyOf: valids first })).
c that: 'the invalid tree keeps the node class proto_db gives it' is: fails asArray equals: #().

"keyed.py check_member_key with outer: a member with a valid vector is stored under (list, member
 key), 2 containers more than an invalid one, whose member key is kept alone. Both texts are
 proto_db's, taken from proto_db at the tag; one list level less is stored."
fails := OrderedCollection new.
deep := 1.
252 timesRepeat: [deep := PBFrozenList withAll: { deep }].
at := { PBFrozenDict withAssociations: { 'v' -> (tup value: #(1.0 0.0)). 'x' -> deep }.
  PBFrozenDict withAssociations: { 'v' -> nil. 'x' -> deep } }.
deep := PBFrozenList withAll: { deep }.
over := { PBFrozenDict withAssociations: { 'v' -> (tup value: #(1.0 0.0)). 'x' -> deep }.
  PBFrozenDict withAssociations: { 'v' -> nil. 'x' -> deep } }.
index := PBVectorIndex name: 'near' keySpec: (PBKeySpec path: 'v') dim: 2 metric: 'l2'.
expect value: 'at the limit' value: (at collect: [:e | (index withAdded: e) totalCount]) value: #(1 1).
text := 'Index ''near'' (VectorIndex on v) cannot store this element: its member key would nest 1026 MessagePack containers deep, more than MAX_VALUE_DEPTH = 1022 (format spec, "Value nesting depth"). The index stores an orderable element inside 6 containers, so it may nest at most 1016; an unorderable one (holding a list, a map or NaN) through its surrogate, 4 containers per list level and 6 per map level: at most 253 nested lists or 169 nested maps'.
expect value: 'a valid vector, withAdded:' value: (msg value: [index withAdded: (over at: 1)]) value: 'PBValidationError: ' , text.
expect value: 'a valid vector, build:' value: (msg value: [index build: { over at: 1 }]) value: 'PBValidationError: ' , text.
text := 'Index ''near'' (VectorIndex on v) cannot store this element: its member key would nest 1024 MessagePack containers deep, more than MAX_VALUE_DEPTH = 1022 (format spec, "Value nesting depth"). The index stores an orderable element inside 4 containers, so it may nest at most 1018; an unorderable one (holding a list, a map or NaN) through its surrogate, 4 containers per list level and 6 per map level: at most 254 nested lists or 169 nested maps'.
expect value: 'an invalid key, withAdded:' value: (msg value: [index withAdded: (over at: 2)]) value: 'PBValidationError: ' , text.
expect value: 'an invalid key, build:' value: (msg value: [index build: { over at: 2 }]) value: 'PBValidationError: ' , text.
c that: 'a store key adds two containers to the member key''s depth limit' is: fails asArray equals: #().

c report displayNl.
