"EXPECT: ok 10"
"Indexed queries, plan Task 6: the index access paths (proto_db proto_db/indexing/keyed.py at
 v2.0.0rc4, lines 461-647; equality.py, range.py and base.py). The plan halves of
 tests/unit/test_equality_index.py and test_range_index.py, and test_index_base.py's supports, plan,
 estimate, ordered-scan and IndexPlan behaviours: supports: per operator per kind on the index's
 own key (a vector index near[] on its own key only, vectors phase V6), PBNotSupportedError for the rest; plans that answer
 what a scan answers (1 = 1.0 = Decimal 1, true is not 1, PBMissing matches only '?N', ranges stay
 within the operand's type rank, unorderable keys only '!=' and '?!N'), the stored values and not
 an equal representative; ordered scans in the total order, descending its exact reverse; the D30
 estimates. Then the vector ../conformance/vectors-index-keys/terms.msgpack
 (tests/interop/py_term_cases.py, extended at Task 6): for every case that is one term, an
 equality and a range index on the element, and one of each on the records' path 'r' (every other
 value PBMissing there), over QData termValues: 160 seed: 5 answer what
 QData scan: finds and as many rows as proto_db's plan, supports: and exactRows as proto_db,
 estimate: within the tolerance of plan call IP8 (|a - b| <= 1e-12 * max(|a|, |b|)), and explain
 (less its estimate) byte for byte as proto_db's, but for a term whose operand is an atom (described
 differently, docs/deviations.md). Mapped in tests/unit/queries_checklist.tsv."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.

"Runs a plan on its own actor (test_index_plan_concurrent_execution)."
Object subclass: #PlanRunner.

PlanRunner >> bagOf: aPlan
  ^ QData bagOf: aPlan execute.

| c rec people byCity eq range el mixed t run scan unsupported refused bagSize exact close fails blob listed
  data values atoms cases eqIndexes elIndexes tol plan futures tokensOf ordered noon elements
  orders stored want got expr kind index explainOf part kinds pathPairs |
c := Check new.
rec := [:pairs | PBObject withAll: pairs].
people := { rec value: { 'name' -> 'a'. 'city' -> 'Paris' }. rec value: { 'name' -> 'b'. 'city' -> 'Rome' }.
  rec value: { 'name' -> 'c' }. rec value: { 'name' -> 'd'. 'city' -> nil }. rec value: { 'name' -> 'e'. 'city' -> 'Paris' }.
  rec value: { 'name' -> 'f'. 'city' -> 1 }. rec value: { 'name' -> 'g'. 'city' -> 1.0 }. rec value: { 'name' -> 'h'. 'city' -> true }.
  rec value: { 'name' -> 'i'. 'city' -> (PBFrozenList withAll: #(1 2)) } }.
t := [:path :op :v | PBTerm path: path op: op value: v].
run := [:anIndex :aTerm | QData bagOf: (anIndex plan: aTerm) execute].
scan := [:anArray :aTerm | QData scan: anArray where: [:e | aTerm matches: e]].
bagSize := [:aBag | aBag inject: 0 into: [:s :n | s + n]].
refused := [:aBlock | [aBlock value. nil] on: Error do: [:e | e return: e class]].
exact := [:anArray | (anArray collect: [:e | (PBKeys exactToken: e) hex]) asSortedCollection asArray].
close := [:a :b | (a - b) abs <= (1.0e-12 * (a abs max: b abs))].
byCity := PBEqualityIndex name: 'by_city' path: 'city'.
range := PBRangeIndex name: 'by_age' path: 'age'.

"=== supports: (test_supported_operators, test_supported_operators_and_ordering,
     test_supports_checks_the_key_path) ==="
c that: 'supports: answers per operator and per kind, on the index''s own key only'
  is: { { '=='. 'in'. '!='. '?N'. '?!N'. '<'. '<='. '>'. '>='. 'between[]'. 'between()'. 'between(]'. 'between[)'. 'contains'. '?T'. '?!T' }
      collect: [:op | | term |
        term := (PBTerm unaryOperators includes: op)
          ifTrue: [PBTerm path: 'city' op: op]
          ifFalse: [t value: 'city' value: op value: ((PBTerm betweenOperators includes: op) ifTrue: [#(1 2)] ifFalse: [
            op = 'in' ifTrue: [#('x' 1)] ifFalse: ['x']])].
        { byCity supports: term. (PBRangeIndex name: 'r' path: 'city') supports: term }].
    byCity supports: (t value: 'zip' value: '==' value: 'x').
    byCity supports: (t value: nil value: '==' value: 'x').
    (PBRangeIndex name: 'r' path: 'age') supports: (t value: 'other' value: '<' value: 1).
    { range supportsOrder: (PBKeySpec path: 'age'). range supportsOrder: (PBKeySpec path: 'other').
      range supportsOrder: PBKeySpec element. byCity supportsOrder: (PBKeySpec path: 'city') }.
    { (PBVectorIndex name: 'v' path: 'city' dim: 2 metric: 'l2') supports: (t value: 'city' value: 'near[]' value: (PBNearQuery vector: #(1 2) k: 1)).
      (PBVectorIndex name: 'v' path: 'city' dim: 2 metric: 'l2') supports: (t value: 'city' value: '==' value: 'x') } }
  equals: { { #(true true). #(true true). #(true true). #(true true). #(true true). #(false true). #(false true). #(false true).
      #(false true). #(false true). #(false true). #(false true). #(false true). #(false false). #(false false). #(false false) }.
    false. false. false. #(true false false false). #(true false) }.

"=== unsupported terms and orders (test_plan_on_unsupported_term_raises_not_supported,
     test_estimate_on_unsupported_term_raises_not_supported, test_ordered_iteration_is_unsupported_by_default) ==="
unsupported := t value: 'city' value: '<' value: 1.
c that: 'an unsupported term, or order, is PBNotSupportedError; the order key is checked first (a key spec or a term path), then descending, then the order'
  is: { refused value: [byCity plan: unsupported]. refused value: [byCity estimate: unsupported].
    refused value: [byCity plan: (t value: 'zip' value: '==' value: 1)]. refused value: [range estimate: (t value: 'zip' value: '==' value: 1)].
    refused value: [byCity orderedPlan: (PBKeySpec path: 'city') descending: false].
    refused value: [byCity orderedPlan: (PBKeySpec path: 'city') descending: true].
    refused value: [range orderedPlan: (PBKeySpec path: 'other') descending: false].
    refused value: [range orderedPlan: (PBKeySpec path: 'age') descending: nil].
    refused value: [byCity supports: #('city' '==' 'x')].
    refused value: [range orderedPlan: 42 descending: nil].
    [range orderedPlan: 42 descending: nil] on: PBValidationError do: [:e | e return: e messageText].
    refused value: [byCity orderedPlan: 'city' descending: nil].
    ((range build: { rec value: { 'age' -> 2 }. rec value: { 'age' -> 1 } }) orderedPlan: 'age' descending: false) execute asArray
      collect: [:e | e at: 'age'].
    [byCity plan: unsupported] on: PBNotSupportedError do: [:e | e return: e messageText].
    [byCity orderedPlan: (PBKeySpec path: 'city') descending: false] on: PBNotSupportedError do: [:e | e return: e messageText].
    [range orderedPlan: (PBKeySpec path: 'other') descending: true] on: PBNotSupportedError do: [:e | e return: e messageText] }
  equals: { PBNotSupportedError. PBNotSupportedError. PBNotSupportedError. PBNotSupportedError. PBNotSupportedError.
    PBNotSupportedError. PBNotSupportedError. PBValidationError. PBValidationError.
    PBValidationError. 'A term path must be a String or nil, not a SmallInteger'. PBValidationError. #(1 2).
    'Index ''by_city'' (EqualityIndex on city) does not support ''<'' on ''city'''.
    'Index ''by_city'' cannot iterate in the order of city'. 'Index ''by_age'' cannot iterate in the order of other' }.

"=== test_answers_match_a_scan_with_value_semantics, test_missing_keys_are_recorded_and_never_match_ne ==="
eq := byCity build: people.
c that: 'an equality index answers like a scan, and PBMissing never matches !='
  is: { { t value: 'city' value: '==' value: 'Paris'. t value: 'city' value: '==' value: 1. t value: 'city' value: '==' value: (Decimal fromString: '1').
      t value: 'city' value: '==' value: true. t value: 'city' value: '==' value: nil. t value: 'city' value: 'in' value: { 'Rome'. 1.0. 1 }.
      t value: 'city' value: '!=' value: 'Paris'. t value: 'city' value: '!=' value: nil. PBTerm path: 'city' op: '?N'.
      PBTerm path: 'city' op: '?!N'. t value: 'city' value: '==' value: 'nowhere' }
        allSatisfy: [:term | (run value: eq value: term) = (scan value: people value: term)].
    bagSize value: (run value: eq value: (t value: 'city' value: '==' value: 1)).
    bagSize value: (run value: eq value: (t value: 'city' value: 'in' value: #(1 1.0))).
    (run value: eq value: (PBTerm path: 'city' op: '?N')) includesKey: (PBMemberKeys identityOf: (people at: 3)).
    (run value: eq value: (t value: 'city' value: '!=' value: 'Paris')) includesKey: (PBMemberKeys identityOf: (people at: 3)).
    (run value: eq value: (PBTerm path: 'city' op: '?!N')) includesKey: (PBMemberKeys identityOf: (people at: 3)).
    bagSize value: (run value: (eq withAdded: (rec value: { 'name' -> 'c' })) value: (PBTerm path: 'city' op: '?N')).
    ((eq plan: (t value: 'city' value: '==' value: 'Paris')) explain at: 'plan') }
  equals: { true. 2. 2. true. false. false. 3. 'IndexLookup' }.

"=== test_range_operators_stay_within_the_operand_rank, test_between_variants_inclusivity ==="
mixed := { nil. nil. false. true. -2. 0. 1. 1.0. Decimal fromString: '1.5'. 2. 2.5. 3. 10 raisedTo: 20. Float infinity. ''. 'a'.
  'b'. 'b'. ByteArray withAll: #(120). CalendarDate year: 2026 month: 1 day: 1. PBTuple withAll: #(1 'a'). PBTuple withAll: #(2).
  PBFrozenList withAll: #(1). Float nan }.
el := (PBRangeIndex name: 'v' keySpec: PBKeySpec element) build: mixed.
fails := OrderedCollection new.
#('<' '<=' '>' '>=') do: [:op |
  { nil. false. true. 0. 1. 1.5. Decimal fromString: '1.5'. 3. 'b'. ByteArray withAll: #(120). CalendarDate year: 2026 month: 1 day: 1.
    PBTuple withAll: #(2) } do: [:pivot | | term |
    term := t value: nil value: op value: pivot.
    (run value: el value: term) = (scan value: mixed value: term) ifFalse: [fails add: term printString]]].
PBTerm betweenOperators do: [:op |
  { #(1 2.5). #(1.0 1). { 0. 10 raisedTo: 20 }. #(2 1). #('a' 'b'). #(false true) } do: [:pair | | term |
    term := t value: nil value: op value: pair.
    (run value: el value: term) = (scan value: mixed value: term) ifFalse: [fails add: term printString]]].
c that: 'range operators stay within the operand''s type rank, and the between variants include their bounds as named'
  is: { fails asArray.
    (run value: el value: (t value: nil value: '<' value: 5)) = (QData bagOf: { -2. 0. 1. 1.0. Decimal fromString: '1.5'. 2. 2.5. 3 }).
    (run value: el value: (t value: nil value: '>' value: 'a')) = (QData bagOf: #('b' 'b')).
    (run value: el value: (t value: nil value: '>=' value: false)) = (QData bagOf: #(false true)).
    (run value: el value: (t value: nil value: '<=' value: nil)) = (QData bagOf: #(nil nil)).
    (run value: el value: (t value: nil value: '>' value: nil)) isEmpty.
    (run value: el value: (t value: nil value: '<' value: (PBTuple withAll: #(2)))) = (QData bagOf: { PBTuple withAll: #(1 'a') }).
    (run value: el value: (t value: nil value: '>' value: 3)) = (QData bagOf: { 10 raisedTo: 20. Float infinity }).
    bagSize value: (run value: el value: (t value: nil value: 'between[]' value: #(1 2))).
    bagSize value: (run value: el value: (t value: nil value: 'between()' value: #(1 2))) }
  equals: { #(). true. true. true. true. true. true. true. 4. 1 }.

"=== test_presence_equality_and_unorderable_keys, test_ordered_iteration_follows_the_total_order,
     test_ordered_scan_index ==="
elements := (mixed collect: [:a | rec value: { 'age' -> a }]) , { rec value: #(). rec value: { 'age' -> (PBFrozenList withAll: #(1 2)) } }.
index := range build: elements.
orders := [:aPlan | aPlan execute collect: [:e | | k |
  k := (PBKeySpec path: 'age') extract: e.
  (PBMemberKeys orderKeyOrNil: k) isNil ifTrue: [#(1)] ifFalse: [{ 0. PBMemberKeys orderKeyOrNil: k }]]].
ordered := orders value: (index orderedPlan: (PBKeySpec path: 'age') descending: false).
plan := index orderedPlan: (PBKeySpec path: 'age') descending: true.
c that: 'presence, equality and unorderable keys answer like a scan; ordered scans follow the total order'
  is: { { PBTerm path: 'age' op: '?N'. PBTerm path: 'age' op: '?!N'. t value: 'age' value: '==' value: 1.
      t value: 'age' value: 'in' value: { 1. 'b'. nil }. t value: 'age' value: '!=' value: 1. t value: 'age' value: '!=' value: nil.
      t value: 'age' value: '<' value: 2. t value: 'age' value: '==' value: nil }
        allSatisfy: [:term | (run value: index value: term) = (scan value: elements value: term)].
    ordered size = elements size.
    ((1 to: ordered size - 1) allSatisfy: [:j | | x y |
      x := ordered at: j. y := ordered at: j + 1.
      (x first < y first) or: [x first = y first and: [x first = 1 or: [(x at: 2) <= (y at: 2)]]]]).
    ordered first = { 0. PBKeys orderKey: PBMissing default }. ordered last. (orders value: plan) = ordered reverse.
    plan estimate = (PBEstimate rows: elements size cost: elements size + index groupCount + 1).
    (index orderedPlan: (PBKeySpec path: 'age') descending: false) explain at: 'plan'.
    plan explain keys asArray. plan explain at: 'term'. plan explain at: 'descending'. (plan explain at: 'index') = index explain.
    (plan explain at: 'children') isEmpty }
  equals: { true. true. true. true. #(1). true. true. 'IndexOrderedScan'. #('plan' 'index' 'term' 'descending' 'estimate' 'children').
    nil. true. true. true }.

"=== test_estimates, test_range_estimates_use_subtree_counts ==="
el := (PBRangeIndex name: 'v' keySpec: PBKeySpec element) build: ((0 to: 99) asArray , (0 to: 99) asArray).
c that: 'estimates are exact for lookups, use the subtree counts for ranges, and charge != a full pass'
  is: { (eq estimate: (t value: 'city' value: '==' value: 'Paris')) rows. (eq estimate: (t value: 'city' value: '==' value: 'nowhere')) rows.
    (eq estimate: (t value: 'city' value: 'in' value: #('Paris' 'Rome' 'Paris'))) rows. (eq estimate: (PBTerm path: 'city' op: '?N')) rows.
    (eq estimate: (PBTerm path: 'city' op: '?!N')) rows. (eq estimate: (t value: 'city' value: '!=' value: 'Paris')) rows.
    (eq estimate: (t value: 'city' value: '!=' value: 'Paris')) cost > (PBList new extend: people) asQueryPlan estimate cost.
    (eq estimate: (t value: 'city' value: '==' value: 'Paris')) cost < (PBList new extend: people) asQueryPlan estimate cost.
    (eq estimate: (t value: 'city' value: '==' value: 'Paris')) cost
      = (2 + (PBCost log2: eq groupCount + 2)).
    { t value: 'city' value: '==' value: 'Paris'. t value: 'city' value: '!=' value: 1. PBTerm path: 'city' op: '?!N' }
      allSatisfy: [:term | (eq plan: term) estimate = (eq estimate: term)].
    { t value: nil value: '==' value: 5. t value: nil value: '<' value: 10. t value: nil value: 'between[)' value: #(10 20).
      t value: nil value: '>' value: 1000. t value: nil value: '<' value: 'a' } collect: [:term | (el estimate: term) rows].
    (el estimate: (t value: nil value: '<' value: 10)) cost < (el estimate: (t value: nil value: '<' value: 90)) cost.
    (el estimate: (t value: nil value: '<' value: 90)) cost < (200 + 100 + 10).
    PBCost log2: 6 }
  equals: { 2.0. 0.0. 3.0. 2.0. 7.0. 6.0. true. true. true. true. #(2.0 20.0 20.0 0.0 0.0). true. true. 2.584962500721156 }.

"=== test_plans_return_the_stored_values_not_an_equal_representative ==="
noon := DateTime year: 2026 month: 1 day: 1 hour: 12 minute: 0 second: 0 microsecond: 0 fold: 0 zone: ZoneOffset utc.
stored := { 1. 1.0. Decimal fromString: '1.00'. 2.5. 0.0. -0.0. noon.
  DateTime year: 2026 month: 1 day: 1 hour: 15 minute: 0 second: 0 microsecond: 0 fold: 0 zone: (ZoneOffset microseconds: 3 * 3600000000) }.
fails := OrderedCollection new.
{ stored. stored reverse } do: [:order |
  | folded |
  folded := PBRangeIndex name: 'v' keySpec: PBKeySpec element.
  order do: [:e | folded := folded withAdded: e].
  { (PBRangeIndex name: 'v' keySpec: PBKeySpec element) build: order. folded } do: [:idx |
    { t value: nil value: '==' value: 1. t value: nil value: '==' value: 0. t value: nil value: '==' value: noon.
      t value: nil value: '<=' value: 2.5. t value: nil value: '!=' value: 2.5 } do: [:term |
      (exact value: (idx plan: term) execute) = (exact value: (order select: [:e | term matches: e])) ifFalse: [fails add: term printString]].
    (exact value: (idx orderedPlan: PBKeySpec element descending: false) execute) = (exact value: order) ifFalse: [fails add: 'ordered']]].
index := (PBRangeIndex name: 'v' keySpec: PBKeySpec element) build: stored.
c that: 'plans answer the stored values, not an equal representative'
  is: { fails asArray. exact value: ((index withRemoved: 1.0) plan: (t value: nil value: '==' value: 1)) execute.
    refused value: [index withRemoved: (Decimal fromString: '1.0')] }
  equals: { #(). exact value: { 1. Decimal fromString: '1.00' }. PBValidationError }.

"=== the vector: proto_db's plans, row counts, estimates and explains on QData termValues: 160 seed: 5 ==="
blob := '../conformance/vectors-index-keys/terms.msgpack' asFileReference binaryContents.
listed := ('../conformance/vectors-index-keys/manifest.sha256' asFileReference contents lines)
  detect: [:line | line endsWith: '  terms.msgpack'] ifNone: [''].
(listed copyFrom: 1 to: (64 min: listed size)) = blob sha256 hex asLowercase ifFalse: [
  Error signal: 'vectors-index-keys/terms.msgpack does not match manifest.sha256'].
data := MessagePack decode: blob.
values := QData pinOids: (QData termValues: (data at: 'count') seed: (data at: 'seed')).
atoms := TermAtoms on: values.
(data at: 'values') size = values size ifFalse: [Error signal: 'the vector holds another count of values'].
(data at: 'values') doWithIndex: [:bytes :i |
  (PBKeys exactToken: (atoms decode: bytes)) = (PBKeys exactToken: (values at: i)) ifFalse: [
    Error signal: 'QData termValues: no longer draws the values of the vector (value ' , i printString , ')']].
"The element indexes, and the indexes on the records' path 'r', under which every other value is
 PBMissing: proto_db's oracle sees the MISSING group in '?N', its exclusion from '!=' and the
 absent count of '?!N'."
elIndexes := PBFrozenDict withAssociations: {
  'EqualityIndex' -> ((PBEqualityIndex name: 'v' keySpec: PBKeySpec element) build: values).
  'RangeIndex' -> ((PBRangeIndex name: 'v' keySpec: PBKeySpec element) build: values).
  'EqualityIndex on r' -> ((PBEqualityIndex name: 'r' path: 'r') build: values).
  'RangeIndex on r' -> ((PBRangeIndex name: 'r' path: 'r') build: values) }.
kinds := elIndexes keys asArray.
ordered := { 'RangeIndex' -> PBKeySpec element. 'RangeIndex on r' -> (PBKeySpec path: 'r') }.
"The near[] terms are among the cases (vectors phase V2): no key-group index supports one, as in
 proto_db."
cases := (data at: 'cases') select: [:case | (case at: 'index') notNil].
tokensOf := [:case | PBExpression compile: (atoms decode: (case at: 'tokens'))].
"explain less its estimate, as MessagePack bytes (py_term_cases.py explained)"
explainOf := [:aPlan | MessagePack encode: (TermAtoms tree: (PBFrozenDict withAssociations:
  (aPlan explain associations reject: [:each | each key = 'estimate'])))].

fails := OrderedCollection new.
pathPairs := 0.
cases do: [:case |
  expr := tokensOf value: case.
  kinds do: [:k | | theirs |
    index := elIndexes at: k.
    theirs := (case at: 'index') at: k.
    ((index supports: expr) and: [theirs at: 'supports']) ifTrue: [
      (k endsWith: ' on r') ifTrue: [pathPairs := pathPairs + 1].
      got := (index plan: expr) execute.
      ((QData bagOf: got) = (scan value: values value: expr) and: [got size = (theirs at: 'rows')]) ifFalse: [
        fails add: (case at: 'id') , ' on ' , k]]]].
c that: 'plan: answers what a scan finds for every operator of the vector, as many rows as proto_db''s plan'
  is: { cases size. pathPairs. fails asArray } equals: { 183. 14. #() }.

fails := OrderedCollection new.
cases do: [:case |
  expr := tokensOf value: case.
  kinds do: [:k | | theirs mine |
    index := elIndexes at: k.
    theirs := (case at: 'index') at: k.
    (index supports: expr) = (theirs at: 'supports')
      ifFalse: [fails add: (case at: 'id') , ' on ' , k , ': supports:']
      ifTrue: [
        (theirs at: 'supports') ifTrue: [
          mine := index estimate: expr.
          ((close value: mine rows value: ((theirs at: 'estimate') at: 1)) and: [close value: mine cost value: ((theirs at: 'estimate') at: 2)])
            ifFalse: [fails add: (case at: 'id') , ' on ' , k , ': estimate ' , { mine rows. mine cost } printString].
          (index plan: expr) exactRows = (theirs at: 'exact_rows') ifFalse: [fails add: (case at: 'id') , ' on ' , k , ': exactRows']]]]].
c that: 'estimate: equals proto_db''s within the tolerance of IP8, and supports: and exactRows answer as proto_db'
  is: fails asArray equals: #().

fails := OrderedCollection new.
cases do: [:case |
  expr := tokensOf value: case.
  kinds do: [:k | | theirs mine |
    index := elIndexes at: k.
    theirs := (case at: 'index') at: k.
    ((theirs at: 'supports') and: [((case at: 'id') endsWith: ' atom') not]) ifTrue: [
      (explainOf value: (index plan: expr)) = (theirs at: 'explain') ifFalse: [fails add: (case at: 'id') , ' on ' , k]]]].
kinds do: [:k |
  (MessagePack encode: (TermAtoms tree: (elIndexes at: k) explain)) = (((data at: 'indexes') at: k) at: 'explain') ifFalse: [
    fails add: k , ' explain']].
ordered do: [:kindAndSpec |
  (((data at: 'indexes') at: kindAndSpec key) at: 'ordered') doWithIndex: [:theirs :j | | mine |
    mine := (elIndexes at: kindAndSpec key) orderedPlan: kindAndSpec value descending: j = 2.
    ((close value: mine estimate rows value: ((theirs at: 1) at: 1)) and: [close value: mine estimate cost value: ((theirs at: 1) at: 2)])
      ifFalse: [fails add: kindAndSpec key , ' ordered estimate ' , j printString].
    (explainOf value: mine) = (theirs at: 2) ifFalse: [fails add: kindAndSpec key , ' ordered explain ' , j printString]]].
"An IndexPlan: re-executable, its estimate the index's, its part validated (test_index_plan,
 test_index_plan_without_term_needs_an_estimate, test_index_plan_default_kind_and_validation)."
plan := eq plan: (t value: 'city' value: '==' value: 'Paris').
part := PBIndexPart kind: 'IndexLookup' producer: [:each | nil].
fails addAll: ({ plan execute = plan execute. (QData bagOf: plan execute) = (QData bagOf: { people at: 1. people at: 5 }). plan index == eq.
    plan term = (t value: 'city' value: '==' value: 'Paris'). plan estimate = (eq estimate: plan term). plan kind.
    refused value: [PBIndexPlan index: eq term: nil part: part].
    ((PBIndexPlan index: eq term: nil part: (PBIndexPart kind: 'IndexLookup' producer: [:each | nil] estimate: (PBEstimate rows: 0 cost: 1)
      details: (PBFrozenDict withAssociations: { 'x' -> 1 }))) explain at: 'x').
    refused value: [PBIndexPart kind: 'IndexLookup' producer: [:each | nil] estimate: #(0 1) details: nil].
    refused value: [PBIndexPart kind: 'IndexLookup' producer: [:each | nil] estimate: nil details: (PBFrozenDict withAssociations: { 'plan' -> 'x' })].
    refused value: [PBIndexPart kind: '' producer: [:each | nil]].
    refused value: [PBIndexPart kind: 'IndexLookup' producer: 'not a block'].
    (PBIndexPlan index: eq term: (t value: 'city' value: '==' value: 1) part: part) explain at: 'plan' }
  = { true. true. true. true. true. 'IndexLookup'. PBValidationError. 1. PBValidationError. PBValidationError. PBValidationError.
    PBValidationError. 'IndexLookup' } ifTrue: [#()] ifFalse: [#('IndexPlan protocol')]).
"test_index_plan_concurrent_execution: one plan run on 8 actors at once"
el := (PBEqualityIndex name: 'by_city' path: 'city') build: ((0 to: 59) asArray collect: [:j | rec value: { 'city' -> (j \\ 3) }]).
plan := el plan: (t value: 'city' value: '==' value: 1).
futures := (1 to: 8) asArray collect: [:j | PlanRunner new asActor bagOf: plan].
got := futures collect: [:f | f waitWithin: 120000].
({ (got collect: [:b | b = got first]) asSet asArray. bagSize value: got first } = { #(true). 20 }) ifFalse: [
  fails add: 'concurrent execution'].
c that: 'index plans and the indexes explain as proto_db''s, less the description of an atom operand; one plan runs on several actors at once'
  is: fails asArray equals: #().

c report displayNl.
