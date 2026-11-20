"EXPECT: ok 10"
"Vectors phase V2 (Addendum V, 2.6 to 2.8 and 5.1): PBNearQuery, near[] terms and their refusals,
 against proto_db v2.0.0rc4 (proto_db/query/terms.py:92-137, 197-219, 259-279, 304-325;
 expressions.py:20-21, 352-356; plans.py:452-462; planner.py:114-116). The behaviours of
 tests/unit/test_terms.py's four near tests, test_expressions.py's
 test_evaluate_near_is_not_a_scan_predicate and test_plans.py's
 test_filter_accepts_prefix_lists_and_rejects_near (mapped in tests/unit/queries_checklist.tsv);
 the refusals where proto_db raises one of Python's own errors, PBValidationError with CPython's
 text (deviation DV7 c and d, and the unhashable metric, f); equality and hash with Python's float
 equality (0.0 = -0.0); and the near[] cases of ../conformance/vectors-index-keys/terms.msgpack
 (tests/interop/py_term_cases.py), proto_db's outcome for each list form, degenerate input
 included. Each check gathers its mismatches and requires none, so one label covers one
 behaviour."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.

| c fails expect refused msg rec t nq q term a1 people scan near blob listed data values atoms cases
  errorClass got want n dict |
c := Check new.
expect := [:label :actual :expected |
  actual = expected ifFalse: [fails add: label , ': expected ' , expected printString , ', got ' , actual printString]].
refused := [:aBlock | [aBlock value. nil] on: Error do: [:e | e return: e class]].
msg := [:aBlock | [aBlock value. 'no error'] on: Error do: [:err | err return: err class name , ': ' , err messageText]].
rec := [:pairs | PBObject withAll: pairs].
t := [:path :op :value | PBTerm path: path op: op value: value].
nq := [:v :k :th :m | PBNearQuery vector: v k: k threshold: th metric: m].
dict := [:assocs | PBFrozenDict withAssociations: assocs].
a1 := t value: 'a' value: '==' value: 1.

"test_near_query_validation (terms.py NearQuery.__post_init__): every invalid form is
 PBValidationError with proto_db's text"
fails := OrderedCollection new.
{ { #(). 1. nil. nil } -> 'near[] needs a non-empty vector, not []'.
  { #(1.0). nil. nil. nil } -> 'near[] needs k, threshold or both'.
  { #(1.0). 0. nil. nil } -> 'near[] k must be an int >= 1, not 0'.
  { #(1.0). true. nil. nil } -> 'near[] k must be an int >= 1, not True'.
  { #(1.0). 1.5. nil. nil } -> 'near[] k must be an int >= 1, not 1.5'.
  { { Float nan }. 1. nil. nil } -> 'A vector component must be a finite number, not nan'.
  { { Float infinity }. 1. nil. nil } -> 'A vector component must be a finite number, not inf'.
  { { Float infinity negated }. 1. nil. nil } -> 'A vector component must be a finite number, not -inf'.
  { { true }. 1. nil. nil } -> 'A vector component must be a finite number, not True'.
  { #('1'). 1. nil. nil } -> 'A vector component must be a finite number, not ''1'''.
  { 1.0. 1. nil. nil } -> 'near[] needs a non-empty vector, not 1.0'.
  { 'ab'. 1. nil. nil } -> 'near[] needs a non-empty vector, not ''ab'''.
  { #(1.0). nil. Float nan. nil } -> 'near[] threshold must be a finite number, not nan'.
  { #(1.0). nil. '0.1'. nil } -> 'near[] threshold must be a finite number, not ''0.1'''.
  { #(1.0). 1. nil. 'manhattan' } -> 'near[] metric must be one of [''cosine'', ''ip'', ''l2''] or None, not ''manhattan'''.
  { #(1.0). 1. nil. 'L2' } -> 'near[] metric must be one of [''cosine'', ''ip'', ''l2''] or None, not ''L2'''.
  { #(1.0). 1. nil. 3 } -> 'near[] metric must be one of [''cosine'', ''ip'', ''l2''] or None, not 3'.
  { { Decimal fromString: '1E+400' }. 1. nil. nil } -> 'A vector component must be a finite number, not Decimal(''1E+400'')'.
  { { Decimal fromString: 'NaN' }. 1. nil. nil } -> 'A vector component must be a finite number, not Decimal(''NaN'')'.
  { { PBTuple withAll: #(1.0) }. 1. nil. nil } -> 'A vector component must be a finite number, not (1.0,)'.
  { { PBFrozenDict withAssociations: { 'a' -> nil } }. 1. nil. nil } -> 'A vector component must be a finite number, not {''a'': None}'.
  { PBTuple withAll: #(). 1. nil. nil } -> 'near[] needs a non-empty vector, not ()' } do: [:each |
    expect value: each key printString value: (msg value: [nq valueWithArguments: each key]) value: 'PBValidationError: ' , each value].
"Values Python has no counterpart of are refused with the same sentence."
{ { { Object new }. 1. nil. nil } -> 'A vector component must be a finite number, not '.
  { Set new. 1. nil. nil } -> 'near[] needs a non-empty vector, not ' } do: [:each |
    expect value: each key printString value: ((msg value: [nq valueWithArguments: each key]) beginsWith: 'PBValidationError: ' , each value)
      value: true].
"The order of proto_db's checks: the vector first, then k and threshold, then the metric."
expect value: 'the vector is checked first' value: (msg value: [nq value: #() value: 0 value: Float nan value: 'x'])
  value: 'PBValidationError: near[] needs a non-empty vector, not []'.
expect value: 'then k' value: (msg value: [nq value: #(1) value: 0 value: Float nan value: 'x'])
  value: 'PBValidationError: near[] k must be an int >= 1, not 0'.
expect value: 'then the threshold' value: ((msg value: [nq value: #(1) value: 1 value: Float nan value: 'x']) beginsWith: 'PBValidationError: near[] threshold')
  value: true.
expect value: 'the conveniences' value: { PBNearQuery vector: #(1) k: 2. PBNearQuery vector: #(1) threshold: 0.5.
    PBNearQuery vector: #(1) k: 2 threshold: 0.5 } value: { nq value: #(1) value: 2 value: nil value: nil.
    nq value: #(1) value: nil value: 0.5 value: nil. nq value: #(1) value: 2 value: 0.5 value: nil }.
expect value: 'every metric' value: (#('cosine' 'l2' 'ip') collect: [:m | (nq value: #(1) value: 1 value: nil value: m) metric])
  value: #('cosine' 'l2' 'ip').
expect value: 'a huge k' value: (nq value: #(1) value: (2 raisedTo: 64) - 1 value: nil value: nil) k value: (2 raisedTo: 64) - 1.
expect value: 'the sequences a vector may be' value: ({ #(1 2). OrderedCollection with: 1 with: 2. PBFrozenList withAll: #(1 2).
    PBTuple withAll: #(1 2) } collect: [:v | (nq value: v value: 1 value: nil value: nil) vector]) value: ((1 to: 4) collect: [:i | PBTuple withAll: #(1.0 2.0)]).
c that: 'PBNearQuery validation is proto_db''s' is: fails asArray equals: #().

"Deviation DV7 (c, d, and f): where proto_db fails with one of Python's own errors (math.isfinite's
 OverflowError on an Integer beyond the Float range and float()'s ValueError on a signalling-NaN
 Decimal, terms.py:93; set membership's TypeError on an unhashable metric, terms.py:123),
 PBValidationError with CPython's text, at the same point of the checks"
fails := OrderedCollection new.
{ { { 2 raisedTo: 1100 }. 1. nil. nil } -> 'PBValidationError: int too large to convert to float'.
  { { (2 raisedTo: 1100) negated }. 1. nil. nil } -> 'PBValidationError: int too large to convert to float'.
  { { (2 raisedTo: 1024) - (2 raisedTo: 970) }. 1. nil. nil } -> 'PBValidationError: int too large to convert to float'.
  { #(1.0). nil. 2 raisedTo: 1100. nil } -> 'PBValidationError: int too large to convert to float'.
  { { Decimal fromString: 'sNaN' }. 1. nil. nil } -> 'PBValidationError: cannot convert signaling NaN to float'.
  { { 1. Decimal fromString: '-sNaN' }. 1. nil. nil } -> 'PBValidationError: cannot convert signaling NaN to float'.
  { #(1.0). nil. Decimal fromString: 'sNaN'. nil } -> 'PBValidationError: cannot convert signaling NaN to float'.
  { #(1.0). 1. nil. #('l2') } -> 'PBValidationError: near[] metric must be one of [''cosine'', ''ip'', ''l2''] or None, not [''l2'']' } do: [:each |
    expect value: each key printString value: (msg value: [nq valueWithArguments: each key]) value: each value].
"An earlier refusal wins, as in Python: the components are read in order, then k."
expect value: 'a string before an sNaN' value: ((msg value: [nq value: { 'x'. Decimal fromString: 'sNaN' } value: 1 value: nil value: nil])
  includesSubstring: 'must be a finite number') value: true.
expect value: 'k before the threshold' value: (msg value: [nq value: #(1) value: 0 value: (2 raisedTo: 1100) value: nil])
  value: 'PBValidationError: near[] k must be an int >= 1, not 0'.
expect value: 'the largest Float' value: (nq value: { (2 raisedTo: 1024) - (2 raisedTo: 971) } value: 1 value: nil value: nil) vector asArray first
  value: ((Check bytes: '7fefffffffffffff') float64At: 1 bigEndian: true).
c that: 'Python''s own errors are PBValidationError with CPython''s text (DV7)' is: fails asArray equals: #().

"test_near_values_are_canonical_and_hashable, and equality with Python's float equality"
fails := OrderedCollection new.
q := nq value: { 1. 0.5 } value: 2 value: nil value: 'cosine'.
expect value: 'the vector is a PBTuple of Floats' value: { q vector. q vector class. q vector asArray allSatisfy: [:x | x isFloat] }
  value: { PBTuple withAll: #(1.0 0.5). PBTuple. true }.
term := t value: 'v' value: 'near[]' value: q.
expect value: 'equal terms hash alike' value: term hash = (t value: 'v' value: 'near[]' value: (nq value: (PBTuple withAll: #(1.0 0.5)) value: 2 value: nil value: 'cosine')) hash
  value: true.
n := Dictionary new. n at: term put: 1.
expect value: 'a mapping of its fields is the same key' value: (n at: (t value: 'v' value: 'near[]'
  value: (dict value: { 'vector' -> #(1.0 0.5). 'k' -> 2. 'metric' -> 'cosine' })) ifAbsent: [nil]) value: 1.
expect value: 'a threshold mapping' value: (t value: 'v' value: 'near[]' value: (dict value: { 'vector' -> #(1.0). 'threshold' -> 0.3 })) value
  value: (PBNearQuery vector: #(1.0) threshold: 0.3).
expect value: 'nil is the index''s metric' value: (PBNearQuery vector: #(1.0) k: 1) metric value: nil.
expect value: 'Integers and Decimals become Floats' value: (nq value: { 3. Decimal fromString: '0.1'. (2 raisedTo: 64) + 1. Decimal fromString: '-0' }
  value: 1 value: nil value: nil) vector asArray value: { 3.0. 0.1. 18446744073709551616.0. -0.0 }.
expect value: 'an Integer threshold becomes a Float' value: { (PBNearQuery vector: #(1) threshold: 2) threshold. (PBNearQuery vector: #(1) threshold: 2) threshold isFloat }
  value: #(2.0 true).
expect value: '-0.0 equals 0.0' value: { (nq value: { -0.0 } value: 1 value: nil value: nil) = (nq value: { 0.0 } value: 1 value: nil value: nil).
    (nq value: { -0.0 } value: 1 value: nil value: nil) hash = (nq value: { 0.0 } value: 1 value: nil value: nil) hash.
    (PBNearQuery vector: #(1) threshold: -0.0) = (PBNearQuery vector: #(1) threshold: 0.0).
    (PBNearQuery vector: #(1) threshold: -0.0) hash = (PBNearQuery vector: #(1) threshold: 0.0) hash.
    (t value: 'v' value: 'near[]' value: (PBNearQuery vector: { -0.0. 1 } k: 1)) = (t value: 'v' value: 'near[]' value: (PBNearQuery vector: { 0.0. 1.0 } k: 1)) }
  value: #(true true true true true).
expect value: 'unequal fields' value: ({ nq value: #(1.0 0.5) value: 3 value: nil value: 'cosine'. nq value: #(1.0 0.5) value: 2 value: nil value: nil.
    nq value: #(1.0 0.5) value: 2 value: 0.1 value: 'cosine'. nq value: #(1.0 0.25) value: 2 value: nil value: 'cosine'.
    nq value: #(1.0 0.5 0.0) value: 2 value: nil value: 'cosine' } collect: [:other | other = q]) value: #(false false false false false).
expect value: 'not equal to other objects' value: { q = q vector. q = nil. (t value: 'v' value: 'near[]' value: q) = (t value: 'v' value: '==' value: 1) }
  value: #(false false false).
expect value: 'frozen' value: { (#(#vector: #k: #threshold: #metric:) select: [:sel | q respondsTo: sel]) asArray.
    refused value: [q _setVector: #() k: 1 threshold: nil metric: nil] } value: { #(). PBUserError }.
n := Array with: 1 with: 2.
q := PBNearQuery vector: n k: 1.
n at: 1 put: 5.
expect value: 'the caller''s Array is copied' value: q vector asArray value: #(1.0 2.0).
c that: 'near queries are frozen values with Python''s float equality' is: fails asArray equals: #().

"test_near_terms_need_a_near_query: the value of a near[] term is a PBNearQuery or a mapping
 (a Dictionary or a PBFrozenDict) of its fields, converted"
fails := OrderedCollection new.
{ PBTuple withAll: { #(1.0 0.0). 3 }. #(1.0). 5. dict value: { 'vector' -> #(1.0) }.
  dict value: { 'vector' -> #(1.0). 'k' -> 1. 'x' -> 2 }. dict value: { 'k' -> 1 }. nil } do: [:each |
    expect value: each printString value: (refused value: [t value: 'v' value: 'near[]' value: each]) value: PBValidationError].
expect value: 'the mapping message' value: (msg value: [t value: 'v' value: 'near[]' value: (dict value: { 'vector' -> #(1.0). 'k' -> 1. 'x' -> 2 })])
  value: 'PBValidationError: A near[] mapping needs ''vector'' and only vector/k/threshold/metric, got [''k'', ''vector'', ''x'']'.
expect value: 'the other message' value: (msg value: [t value: 'v' value: 'near[]' value: 5])
  value: 'PBValidationError: near[] needs a NearQuery (or a mapping of its fields), not 5'.
n := Dictionary new. n at: 'vector' put: #(1 2); at: 'k' put: 2; at: 'threshold' put: 0.5; at: 'metric' put: 'l2'.
term := t value: 'v' value: 'near[]' value: n.
expect value: 'a Dictionary is converted' value: { term value. term op. term path }
  value: { nq value: #(1 2) value: 2 value: 0.5 value: 'l2'. 'near[]'. 'v' }.
n at: 'k' put: 9.
expect value: 'and not kept' value: term value k value: 2.
expect value: 'a PBNearQuery is kept' value: (t value: 'v' value: 'near[]' value: q) value == q value: true.
expect value: 'near[] is an operator' value: { PBTerm operators includes: 'near[]'. PBTerm unaryOperators includes: 'near[]' } value: #(true false).
expect value: 'an unknown operator lists it' value: ((msg value: [t value: 'v' value: 'nearest' value: q]) includesSubstring: '''in'', ''near[]''')
  value: true.
expect value: 'on the element and on an extractor path' value: ({ nil. 'a.b' } collect: [:p | (t value: p value: 'near[]' value: q) keySpecObject])
  value: { PBKeySpec element. PBKeySpec path: 'a.b' }.
c that: 'near[] terms take a PBNearQuery or a mapping of its fields' is: fails asArray equals: #().

"test_near_is_not_answered_by_the_scan_oracle"
near := t value: 'v' value: 'near[]' value: (PBNearQuery vector: #(1.0 0.0) k: 3).
c that: 'matches: of a near[] term is PBNotSupportedError'
  signals: PBNotSupportedError containing: '''near[]'' terms are answered by vector plans, not by a scan'
  during: [near matches: (rec value: { 'v' -> (PBTuple withAll: #(1.0 0.0)) })].

"test_evaluate_near_is_not_a_scan_predicate; evaluate: is expressions.py's evaluate, which reaches
 the term only where the short circuit does not stop first"
fails := OrderedCollection new.
near := t value: 'v' value: 'near[]' value: (PBNearQuery vector: #(1 0) k: 1).
n := rec value: { 'v' -> (PBTuple withAll: #(1 0)). 'a' -> 1 }.
{ near. near not. near & a1. a1 & near. near | a1. (a1 not) | near } do: [:each |
  expect value: each printString value: (refused value: [each evaluate: n]) value: PBNotSupportedError].
expect value: 'a false conjunct stops first' value: ((a1 not & near) evaluate: n) value: false.
expect value: 'a true disjunct stops first' value: ((a1 | near) evaluate: n) value: true.
c that: 'evaluate: refuses a near[] term it reaches' is: fails asArray equals: #().

"The list syntax (expressions.py:352-356, terms.py:273-276) and describe (terms.py:323-325)"
fails := OrderedCollection new.
term := PBExpression compile: #('v' 'near[]' #(1 0) 0.8).
expect value: 'the 0.1 form' value: term value: (t value: 'v' value: 'near[]' value: (nq value: #(1.0 0.0) value: nil value: 0.8 value: 'cosine')).
expect value: 'its list' value: term asList value: #('v' 'near[]' #(1.0 0.0) 0.8).
expect value: 'a cosine threshold query is listed in the 0.1 form' value: (t value: 'v' value: 'near[]' value: (nq value: { 1. Decimal fromString: '2' } value: nil value: 2 value: 'cosine')) asList
  value: #('v' 'near[]' #(1.0 2.0) 2.0).
{ nq value: #(1 0) value: 2 value: nil value: nil. nq value: #(1 0) value: nil value: 0.8 value: nil.
  nq value: #(1 0) value: 2 value: 0.8 value: 'cosine'. nq value: #(1 0) value: nil value: 0.8 value: 'l2' } do: [:each |
    expect value: 'listed with its query ' , each printString value: (t value: 'v' value: 'near[]' value: each) asList value: { 'v'. 'near[]'. each }].
{ { 'v'. 'near[]'. dict value: { 'vector' -> #(1 0). 'k' -> 2 } }. { 'v'. 'near[]'. nq value: #(1 0) value: 2 value: nil value: 'l2' }.
  { 'v'. 'near[]'. #(1 0). 0.8 }. PBFrozenList withAll: { 'v'. 'near[]'. PBFrozenList withAll: #(1 0). 0.8 }.
  OrderedCollection withAll: { nil. 'near[]'. dict value: { 'vector' -> #(1). 'threshold' -> -1. 'metric' -> 'ip' } } } do: [:tokens |
    term := PBExpression compile: tokens.
    expect value: 'round trip ' , tokens printString value: (PBExpression compile: term asList) value: term].
term := (PBExpression compile: { '|'. 'v'. 'near[]'. nq value: #(1 2) value: 4 value: nil value: nil. 'y'. 'in'. #('a' 'b') }) not.
expect value: 'a nested round trip' value: (PBExpression compile: term asList) value: term.
expect value: 'a near[] without its threshold' value: (msg value: [PBExpression compile: #('v' 'near[]' #(1 0))])
  value: 'PBValidationError: ''near[]'' at position 1 needs a vector and a threshold (or a NearQuery / mapping of its fields)'.
expect value: 'a nil threshold' value: (msg value: [PBExpression compile: #('v' 'near[]' #(1 0) nil)])
  value: 'PBValidationError: near[] needs k, threshold or both'.
expect value: 'a scalar vector' value: (msg value: [PBExpression compile: #('v' 'near[]' 5 0.3)])
  value: 'PBValidationError: near[] needs a non-empty vector, not 5'.
expect value: 'a mapping does not take a threshold token' value: (refused value: [PBExpression compile: { 'v'. 'near[]'. dict value: { 'vector' -> #(1). 'k' -> 1 }. 0.5 }])
  value: PBValidationError.
q := nq value: #(1 0) value: 3 value: nil value: nil.
expect value: 'describe of the query' value: q describe
  value: (dict value: { 'vector' -> #(1.0 0.0). 'k' -> 3. 'threshold' -> nil. 'metric' -> nil }).
expect value: 'describe of the term' value: (t value: 'v' value: 'near[]' value: (nq value: #(1) value: nil value: 0.5 value: 'l2')) describe
  value: (dict value: { 'path' -> 'v'. 'op' -> 'near[]'. 'value' -> (dict value: { 'vector' -> #(1.0). 'k' -> nil. 'threshold' -> 0.5. 'metric' -> 'l2' }) }).
expect value: 'displayValue: of a query' value: (PBTerm displayValue: q) value: q describe.
expect value: 'describe is plain data' value: (refused value: [PBCodec canonical: (t value: 'v' value: 'near[]' value: q) describe]) value: nil.
expect value: 'a query prints' value: q printString value: 'PBNearQuery(vector=(1.0, 0.0), k=3, threshold=None, metric=None)'.
expect value: 'a query prints its values as Python does' value: (nq value: #(1 1.0e16) value: nil value: 0.5 value: 'l2') printString
  value: 'PBNearQuery(vector=(1.0, 1e+16), k=None, threshold=0.5, metric=''l2'')'.
c that: 'the list syntax reads and writes both near[] forms, and describe is proto_db''s' is: fails asArray equals: #().

"test_filter_accepts_prefix_lists_and_rejects_near"
fails := OrderedCollection new.
people := { rec value: { 'name' -> 'ann'. 'city' -> 'Rome' }. rec value: { 'name' -> 'bob'. 'city' -> 'Oslo' }.
  rec value: { 'name' -> 'cy'. 'city' -> 'Paris' }. rec value: { 'name' -> 'dan'. 'city' -> 'Oslo' } }.
scan := (PBList new extend: people) asQueryPlan.
expect value: 'a prefix list' value: (PBFilter source: scan terms: #('city' '==' 'Oslo')) execute asArray value: { people at: 2. people at: 4 }.
expect value: 'a near[] term' value: (msg value: [PBFilter source: scan terms: { t value: 'v' value: 'near[]' value: (PBNearQuery vector: #(1.0) k: 1) }])
  value: 'PBValidationError: A Filter cannot evaluate ''near[]'' terms (PBTerm(''v'', ''near[]'', PBNearQuery(vector=(1.0,), k=1, threshold=None, metric=None))); use a VectorSearch plan'.
{ { 'v'. 'near[]'. #(1). 0.5 }. { a1. { '!'. 'v'. 'near[]'. #(1). 0.5 } }. { '|'. a1. { 'v'. 'near[]'. #(1). 0.5 } } } do: [:tokens |
  expect value: 'a near[] inside ' , tokens printString value: (refused value: [PBFilter source: scan terms: tokens]) value: PBValidationError].
expect value: 'a String' value: (refused value: [PBFilter source: scan terms: 'city == ''Oslo''']) value: PBValidationError.
"proto_db's order (plans.py Filter.__init__): the expression is compiled, then checked for near[],
 then the source, so with both wrong the expression's refusal is the one reported."
expect value: 'a malformed list before a bad source' value: ((msg value: [PBFilter source: #(1 2) terms: #('a' '=~' 1)])
  beginsWith: 'PBValidationError: Unknown operator ''=~'' at position 1;') value: true.
expect value: 'a near[] term before a bad source' value: ((msg value: [PBFilter source: #(1 2) terms: { t value: 'v' value: 'near[]' value: (PBNearQuery vector: #(1.0) k: 1) }])
  beginsWith: 'PBValidationError: A Filter cannot evaluate ''near[]'' terms') value: true.
expect value: 'a source that is not a plan' value: ((msg value: [PBFilter source: #(1 2) terms: { t value: nil value: '==' value: 1 }]) includesSubstring: 'QueryPlan')
  value: true.
c that: 'PBFilter takes prefix lists and refuses near[]' is: fails asArray equals: #().

"planner.py normalize: a negated near[] term has no per-element complement (planner.py:114-116)"
fails := OrderedCollection new.
near := t value: 'v' value: 'near[]' value: (PBNearQuery vector: #(1.0) k: 1).
{ near not. (near | a1) not. (a1 & near) not. ((near not) | a1) } do: [:each |
  expect value: each printString value: (msg value: [PBPlanner normalize: each])
    value: 'PBNotSupportedError: A negated ''near[]'' term cannot be planned (' , near printString
      , '): there is no per-element semantics to complement a vector search'].
expect value: 'a near[] term' value: (PBPlanner normalize: near) == near value: true.
expect value: 'a double negation' value: (PBPlanner normalize: (PBNot of: (PBNot of: near))) == near value: true.
expect value: 'in a conjunction' value: (PBPlanner normalize: (near & a1 not) not not) value: near & a1 not.
c that: 'normalize: refuses a negated near[] term' is: fails asArray equals: #().

"The near[] cases of the term vector: the outcome of compile: (the error class, Python's own
 errors being PBValidationError, DV7), the refusal of evaluate:, the list and the description, as
 proto_db's"
blob := '../conformance/vectors-index-keys/terms.msgpack' asFileReference binaryContents.
listed := ('../conformance/vectors-index-keys/manifest.sha256' asFileReference contents lines)
  detect: [:line | line endsWith: '  terms.msgpack'] ifNone: [''].
(listed copyFrom: 1 to: (64 min: listed size)) = blob sha256 hex asLowercase ifFalse: [
  Error signal: 'vectors-index-keys/terms.msgpack does not match manifest.sha256'].
data := MessagePack decode: blob.
values := QData pinOids: (QData termValues: (data at: 'count') seed: (data at: 'seed')).
atoms := TermAtoms on: values.
cases := (data at: 'cases') select: [:case | (case at: 'id') includesSubstring: 'near[]'].
errorClass := [:name |
  name isNil ifTrue: [nil] ifFalse: [
    (#('ProtoValidationError' 'OverflowError' 'ValueError' 'TypeError') includes: name) ifTrue: [PBValidationError] ifFalse: [
      name = 'ProtoNotSupportedError' ifTrue: [PBNotSupportedError] ifFalse: [Error signal: 'unknown class ' , name]]]].
fails := OrderedCollection new.
cases do: [:case | | id expr |
  id := case at: 'id'.
  got := [PBExpression compile: (atoms decode: (case at: 'tokens')). nil] on: Error do: [:e | e return: e class].
  want := errorClass value: (case at: 'error').
  got = want ifFalse: [fails add: id , ': compile: signals ' , got printString , ', proto_db ' , want printString].
  (got isNil and: [want isNil]) ifTrue: [
    expr := PBExpression compile: (atoms decode: (case at: 'tokens')).
    got := [values do: [:v | expr evaluate: v]. nil] on: Error do: [:e | e return: e class].
    got = (errorClass value: (case at: 'match_error')) ifFalse: [fails add: id , ': evaluate: signals ' , got printString].
    ((case at: 'to_list') notNil and: [(atoms bytesOf: expr asList) ~= (case at: 'to_list')]) ifTrue: [
      fails add: id , ': asList ' , expr asList printString].
    (MessagePack encode: (TermAtoms tree: expr describe)) = (case at: 'describe') ifFalse: [
      fails add: id , ': describe ' , expr describe printString]]].
"Every refusal that is proto_db's own carries proto_db's text, the values it quotes rendered as
 Python renders them (repr, or str for the keys of a mapping)."
(cases select: [:case | (case at: 'error') = 'ProtoValidationError']) do: [:case |
  expect value: (case at: 'id') value: (msg value: [PBExpression compile: (atoms decode: (case at: 'tokens'))])
    value: 'PBValidationError: ' , (case at: 'error_text')].
"The DV7 cases carry CPython's text."
(cases select: [:case | (case at: 'id') includesSubstring: '(DV7'])
  do: [:case | | text |
    text := msg value: [PBExpression compile: (atoms decode: (case at: 'tokens'))].
    ((text = 'PBValidationError: int too large to convert to float' or: [text = 'PBValidationError: cannot convert signaling NaN to float'])
      or: [text beginsWith: 'PBValidationError: near[] metric must be one of']) ifFalse: [fails add: (case at: 'id') , ': ' , text]].
"Counts of the vector: 42 near[] cases, 11 compiled (2 of them listed in the 0.1 form), 5 of
 Python's own errors, 26 of proto_db's own refusals."
expect value: 'counts' value: { cases size. (cases select: [:case | (case at: 'error') isNil]) size.
    (cases select: [:case | (case at: 'to_list') notNil]) size.
    (cases select: [:case | (case at: 'id') includesSubstring: '(DV7']) size.
    (cases select: [:case | (case at: 'error') = 'ProtoValidationError']) size } value: #(42 11 2 5 26).
c that: 'the near[] cases of the term vector are proto_db''s' is: fails asArray equals: #().

c report displayNl.
