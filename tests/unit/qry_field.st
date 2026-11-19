"EXPECT: ok 6"
"Indexed queries, plan Task 8: PBField, the predicate builder (proto_db proto_db/query/linq.py at
 v2.0.0rc4, Field and _Operand, lines 360-484 and 600-640, less the computed values, startswith,
 endswith and near, deferred or excluded by spec 3.2 and 3.3). The behaviours of proto_db's
 tests/unit/test_linq.py about the F builder (test_field_paths, test_field_predicates_are_pure_terms,
 test_combinators_build_expressions, test_predicates_evaluate_like_the_scan_oracle,
 test_in_rejects_a_mapping), with protoST's names (ruling IQ2): eq: and ne: for == and !=, the
 binary comparisons with the field as the receiver, & | and not over expressions only (ruling
 CR5), and no = override (call IC4). Mapped in tests/unit/queries_checklist.tsv."
Import from: 'protobase'.
Import from: '_check'.

| c t t1 a b f rows truth |
c := Check new.
t := [:path :op :value | PBTerm path: path op: op value: value].
t1 := [:path :op | PBTerm path: path op: op].
a := PBField path: 'a'.

"proto_db: test_field_paths."
c that: 'a field names a dotted path, the element or an extractor; malformed names are PBValidationError'
  is: { (a eq: 1) = (t value: 'a' value: '==' value: 1).
    ((PBField path: 'a.b.c') eq: 1) = (t value: 'a.b.c' value: '==' value: 1).
    (PBField element > 1) = (t value: nil value: '>' value: 1).
    ((PBField extractor: 'name_length') < 3) = (t value: '@name_length' value: '<' value: 3).
    ((PBField path: '@name_length') < 3) = (t value: '@name_length' value: '<' value: 3).
    a path. (PBField path: 'a.b') path. PBField element path. (PBField extractor: 'n') path.
    (PBField path: 'a.b') keySpecObject = (PBKeySpec path: 'a.b').
    PBField element keySpecObject = PBKeySpec element.
    (PBField extractor: 'n') keySpecObject = (PBKeySpec extractor: 'n').
    { [PBField path: 3]. [PBField path: nil]. [PBField path: (PBField path: 'a')]. [PBField path: ''].
      [PBField path: 'a..b']. [PBField extractor: 3]. [PBField extractor: ''] }
        collect: [:each | [each value. #accepted] on: PBValidationError do: [:e | e return: #refused]] }
  equals: { true. true. true. true. true. 'a'. 'a.b'. nil. '@n'. true. true. true.
    (1 to: 7) asArray collect: [:i | #refused] }.

"proto_db: test_field_predicates_are_pure_terms."
c that: 'every builder message answers the pure term of its operator'
  is: ({ a eq: 1. a ne: 1. a < 1. a <= 1. a > 1. a >= 1.
      a in: #(1 2). a in: (Set withAll: #(2 1)). a in: (OrderedCollection withAll: #(1 2)).
      a between: 1 and: 5. a betweenOpen: 1 and: 5. a betweenLeftOpen: 1 and: 5. a betweenRightOpen: 1 and: 5.
      a contains: 'x'. a isNone. a notNone. a isTrue. a notTrue }
    with: { t value: 'a' value: '==' value: 1. t value: 'a' value: '!=' value: 1. t value: 'a' value: '<' value: 1.
      t value: 'a' value: '<=' value: 1. t value: 'a' value: '>' value: 1. t value: 'a' value: '>=' value: 1.
      t value: 'a' value: 'in' value: #(1 2). t value: 'a' value: 'in' value: (Set withAll: #(1 2)).
      t value: 'a' value: 'in' value: #(1 2).
      t value: 'a' value: 'between[]' value: #(1 5). t value: 'a' value: 'between()' value: #(1 5).
      t value: 'a' value: 'between(]' value: #(1 5). t value: 'a' value: 'between[)' value: #(1 5).
      t value: 'a' value: 'contains' value: 'x'. t1 value: 'a' value: '?N'. t1 value: 'a' value: '?!N'.
      t1 value: 'a' value: '?T'. t1 value: 'a' value: '?!T' }
    collect: [:got :expected | (got isKindOf: PBTerm) and: [got = expected and: [got op = expected op]]])
  equals: ((1 to: 18) asArray collect: [:i | true]).

"proto_db: test_in_rejects_a_mapping."
c that: 'in: takes a collection of values, never a map or a String; any other collection is read as a sequence; a between needs bounds of one rank'
  is: { ((a in: (1 to: 3)) = (t value: 'a' value: 'in' value: #(1 2 3))).
    ((a in: (PBTuple withAll: #(1 2))) = (t value: 'a' value: 'in' value: #(1 2))).
    { [a in: (PBFrozenDict withAssociations: { 'x' -> 1 })]. [a in: (Dictionary new at: 'x' put: 1; yourself)].
      [a in: 'abc']. [a in: 5]. [a in: nil]. [a between: 1 and: 'z']. [a eq: PBMissing default] }
        collect: [:each | [each value. #accepted] on: PBValidationError do: [:e | e return: #refused]].
    [a in: (PBFrozenDict withAssociations: { 'x' -> 1 })] on: PBValidationError do: [:e | e return: (e messageText includesSubstring: 'map')] }
  equals: { true. true. (1 to: 7) asArray collect: [:i | #refused]. true }.

b := PBField path: 'b'.
f := PBField path: 'c'.
"proto_db: test_combinators_build_expressions. Ruling CR5."
c that: '& | and not build PBAnd, PBOr and PBNot over expressions only'
  is: { ((a eq: 1) & (b eq: 2)) = (PBAnd withAll: { t value: 'a' value: '==' value: 1. t value: 'b' value: '==' value: 2 }).
    ((a eq: 1) | (b eq: 2) | (f eq: 3)) = (PBOr withAll: { t value: 'a' value: '==' value: 1. t value: 'b' value: '==' value: 2. t value: 'c' value: '==' value: 3 }).
    (a eq: 1) not = (PBNot of: (t value: 'a' value: '==' value: 1)).
    (a eq: 1) not not = (a eq: 1).
    (((a eq: 1) & (b eq: 2)) not | (f eq: 3)) = (PBOr withAll: { PBNot of: (PBAnd withAll: { t value: 'a' value: '==' value: 1. t value: 'b' value: '==' value: 2 }). t value: 'c' value: '==' value: 3 }).
    { [(a eq: 1) & 5]. [(a eq: 1) | [:r | true]]. [(a eq: 1) & true]. [(a eq: 1) & a] }
      collect: [:each | [each value. #accepted] on: PBValidationError do: [:e | e return: #refused]] }
  equals: { true. true. true. true. true. #(#refused #refused #refused #refused) }.

"proto_db's AGES and a row without an age: 9, 10, 15, 20, 21, nil, absent."
rows := ((#(9 10 15 20 21) collect: [:n | PBFrozenDict withAssociations: { 'age' -> n }]) asOrderedCollection
  addLast: (PBFrozenDict withAssociations: { 'age' -> nil }); addLast: (PBFrozenDict withAssociations: { 'id' -> 7 }); yourself) asArray.
f := PBField path: 'age'.
truth := [:e | rows collect: [:r | e evaluate: r]].
"proto_db: test_predicates_evaluate_like_the_scan_oracle."
c that: 'built predicates evaluate as the scan oracle: an absent age satisfies no comparison and its negation does'
  is: { truth value: f > 10. truth value: (f > 10) not. truth value: f isNone.
    truth value: (f >= 10) & (f < 21). truth value: (f < 10) | f isNone. truth value: (f ne: 10) }
  equals: { #(false false true true true false false). #(true true false false false true true).
    #(false false false false false true true). #(false true true true false false false).
    #(true false false false false true true). #(true false true true true true false) }.

"Call IC4."
c that: 'a field is not a condition and does not override =: a field compared with = is a Boolean'
  is: { a = 1. (a = a). (PBField path: 'a') = (PBField path: 'a'). (PBExpression _isExpression: a).
    a printString. PBField element printString. (a respondsTo: #path:). (a respondsTo: #eq:) }
  equals: { false. true. false. false. 'PBField(''a'')'. 'PBField(nil)'. false. true }.

c report displayNl.
