"EXPECT: ok 10"
"Indexed queries, plan Task 5: PBExpression, PBAnd, PBOr, PBNot, PBBlockPredicate and the 0.1
 prefix list syntax (proto_db proto_db/query/expressions.py at v2.0.0rc4; the behaviours of
 tests/unit/test_expressions.py that apply, mapped in tests/unit/queries_checklist.tsv). PBAnd and
 PBOr are n-ary, flattened, ordered and need two expressions; aCondition not not is the condition
 itself; nodes are frozen values compared by structure; evaluate: is two-valued and short-circuits
 left to right; PBExpression compile: reads the prefix syntax ('&' and '|' binary, '!' unary, an
 implicit AND, nested lists) and refuses malformed input with PBValidationError; '&', '|' and not
 take expressions only (ruling CR5). Each check gathers its mismatches and requires none, so one
 label covers one behaviour."
Import from: 'protobase'.
Import from: '_check'.

| c fails expect refused missing rec t a1 b2 c3 e nodes samples terms calls spy pred msg compiled list
  dict set counted dictionary nested d |
c := Check new.
missing := PBMissing default.
expect := [:label :actual :expected |
  actual = expected ifFalse: [fails add: label , ': expected ' , expected printString , ', got ' , actual printString]].
refused := [:aBlock | [aBlock value. nil] on: Error do: [:e | e return: e class]].
msg := [:aBlock | [aBlock value. 'no error'] on: PBDBError do: [:err | err return: err class name , ': ' , err messageText]].
rec := [:pairs | PBObject withAll: pairs].
t := [:path :op :value | PBTerm path: path op: op value: value].
a1 := t value: 'a' value: '==' value: 1.
b2 := t value: 'b' value: '>' value: 2.
c3 := t value: 'c' value: '<' value: 3.

"test_term_is_an_expression_and_stays_hashable, test_term_equality_and_hash_follow_values_equal"
fails := OrderedCollection new.
expect value: 'a term is an expression' value: (a1 isKindOf: PBExpression) value: true.
expect value: '1 and 1.0' value: { a1 = (t value: 'a' value: '==' value: 1.0). a1 hash = (t value: 'a' value: '==' value: 1.0) hash } value: #(true true).
expect value: 'a Set of equal terms' value: (Set withAll: { a1. t value: 'a' value: '==' value: 1 }) size value: 1.
expect value: 'true is not 1' value: (t value: 'x' value: '==' value: true) = (t value: 'x' value: '==' value: 1) value: false.
expect value: 'in (true) is not in (1)' value: (t value: 'x' value: 'in' value: { true }) = (t value: 'x' value: 'in' value: #(1)) value: false.
expect value: 'between true is not between 1' value: (t value: 'x' value: 'between[]' value: { true. true }) = (t value: 'x' value: 'between[]' value: #(1 1)) value: false.
expect value: 'two terms in a Set' value: (Set withAll: { t value: 'x' value: '==' value: true. t value: 'x' value: '==' value: 1 }) size value: 2.
d := Decimal fromString: '1.00'.
expect value: '1, 1.0 and Decimal 1.00' value: ({ t value: 'x' value: '==' value: 1.0. t value: 'x' value: '==' value: d } collect: [:x | x = (t value: 'x' value: '==' value: 1) and: [x hash = (t value: 'x' value: '==' value: 1) hash]]) value: #(true true).
expect value: 'in (1 2) and in (1.0 Decimal 2)' value: (t value: 'x' value: 'in' value: #(1 2)) = (t value: 'x' value: 'in' value: { 1.0. Decimal fromString: '2' }) value: true.
expect value: 'tuples' value: (t value: 'x' value: '==' value: (PBTuple withAll: { true. 1 })) = (t value: 'x' value: '==' value: (PBTuple withAll: #(1 1))) value: false.
expect value: 'and of true and 1' value: (PBAnd withAll: { t value: 'x' value: '==' value: true. b2 }) = (PBAnd withAll: { t value: 'x' value: '==' value: 1. b2 }) value: false.
expect value: 'not of true and 1' value: (t value: 'x' value: '==' value: true) not = (t value: 'x' value: '==' value: 1) not value: false.
expect value: 'equal terms match the same elements' value: { (t value: 'x' value: '==' value: true) matches: (PBFrozenDict withAssociations: { 'x' -> 1 }). (t value: 'x' value: '==' value: 1) matches: (PBFrozenDict withAssociations: { 'x' -> 1 }) } value: #(false true).
c that: 'terms are expressions, equal by value semantics' is: fails asArray equals: #().

"test_and_or_flatten_nested_same_type, test_and_or_need_two_expression_operands"
fails := OrderedCollection new.
expect value: 'and of and' value: (PBAnd withAll: { a1 & b2. c3 }) value: (PBAnd withAll: { a1. b2. c3 }).
expect value: 'and flattens on the right' value: (PBAnd withAll: { a1. b2 & c3 }) operands value: { a1. b2. c3 }.
expect value: 'or of ors' value: (PBOr withAll: { a1 | b2. c3 | a1 }) operands value: { a1. b2. c3. a1 }.
expect value: 'and does not flatten an or' value: (PBAnd withAll: { a1 | b2. c3 }) operands value: { a1 | b2. c3 }.
expect value: '& chains flatten' value: (a1 & b2 & c3) operands value: { a1. b2. c3 }.
{ PBAnd. PBOr } do: [:cls |
  expect value: cls name , ' of one' value: ((msg value: [cls withAll: { a1 }]) includesSubstring: 'at least two') value: true.
  expect value: cls name , ' of none' value: ((msg value: [cls withAll: #()]) includesSubstring: 'at least two') value: true.
  expect value: cls name , ' of a list' value: ((msg value: [cls withAll: { a1. #('a' '==' 1) }]) includesSubstring: 'PBExpression') value: true].
c that: 'and and or flatten and need two expressions' is: fails asArray equals: #().

"test_not_not_simplifies"
fails := OrderedCollection new.
expect value: 'not not' value: a1 not not == a1 value: true.
expect value: 'PBNot of: a PBNot' value: (PBNot of: (PBNot of: a1)) == a1 value: true.
expect value: 'not not not' value: a1 not not not value: (PBNot of: a1).
expect value: 'the operand' value: a1 not operand == a1 value: true.
expect value: 'PBNot of: a String' value: ((msg value: [PBNot of: 'a']) includesSubstring: 'PBExpression') value: true.
c that: 'not not answers the original' is: fails asArray equals: #().

"test_nodes_are_immutable_hashable_and_comparable, test_repr_is_readable"
fails := OrderedCollection new.
e := a1 & (b2 | c3 not).
expect value: 'equal hashes' value: e hash = (a1 & (b2 | c3 not)) hash value: true.
expect value: 'equal' value: e = (a1 & (b2 | c3 not)) value: true.
expect value: 'an or is not an and' value: e = (PBOr withAll: { a1. b2 | c3 not }) value: false.
expect value: 'order is kept' value: (a1 & b2) = (b2 & a1) value: false.
expect value: 'a Set' value: (Set withAll: { e. a1 & (b2 | c3 not) }) size value: 1.
{ e. a1 not. a1 | b2 } do: [:node |
  expect value: node class name , ' has no setter' value: ((#(#operands: #operand: #setOperands:) select: [:sel | node respondsTo: sel]) asArray) value: #().
  expect value: node class name , ' is initialised once' value: (refused value: [node _setOperands: #()]) value: PBUserError].
expect value: 'not prints' value: a1 not printString value: 'PBNot(' , a1 printString , ')'.
expect value: 'and prints' value: (a1 & b2) printString value: 'PBAnd(' , a1 printString , ', ' , b2 printString , ')'.
expect value: 'or prints' value: (a1 | b2) printString value: 'PBOr(' , a1 printString , ', ' , b2 printString , ')'.
expect value: 'a term prints' value: a1 printString value: 'PBTerm(''a'', ''=='', 1)'.
c that: 'nodes are frozen values compared by structure' is: fails asArray equals: #().

"test_describe_is_json_serialisable, test_iter_terms_walks_the_tree_in_order"
fails := OrderedCollection new.
d := (t value: 'd' value: '==' value: (Decimal fromString: '1.50'))
  & ((t value: 't' value: 'between[]' value: #(1 5)) | (PBTerm path: 'n' op: '?N') not).
expect value: 'and' value: ((d describe at: 'and') first) value: (PBFrozenDict withAssociations: { 'path' -> 'd'. 'op' -> '=='. 'value' -> 'Decimal(''1.50'')' }).
expect value: 'or' value: ((((d describe at: 'and') at: 2) at: 'or') first at: 'value') value: #(1 5).
expect value: 'not' value: ((((d describe at: 'and') at: 2) at: 'or') at: 2)
  value: (PBFrozenDict withAssociations: { 'not' -> (PBFrozenDict withAssociations: { 'path' -> 'n'. 'op' -> '?N'. 'value' -> nil }) }).
expect value: 'describe is plain data (canonical)' value: (refused value: [PBCodec canonical: d describe]) value: nil.
list := OrderedCollection new.
(a1 & (b2 | c3 not)) termsDo: [:each | list add: each].
expect value: 'termsDo:' value: list asArray value: { a1. b2. c3 }.
list := OrderedCollection new.
a1 termsDo: [:each | list add: each].
expect value: 'termsDo: of a term' value: list asArray value: { a1 }.
list := OrderedCollection new.
(a1 & (PBBlockPredicate block: [:x | true] description: 'always')) termsDo: [:each | list add: each].
expect value: 'termsDo: skips a block predicate' value: list asArray value: { a1 }.
c that: 'describe and termsDo:' is: fails asArray equals: #().

"test_compile_every_operator, test_compile_prefix_stream_operators,
 test_compile_implicit_and_and_nested_lists, test_compile_round_trips_nested_trees"
fails := OrderedCollection new.
{ #('a' '==' 1) -> a1. #('a' '!=' 'x') -> (t value: 'a' value: '!=' value: 'x'). #('a' '<' 1) -> (t value: 'a' value: '<' value: 1).
  #('a' '<=' 1) -> (t value: 'a' value: '<=' value: 1). #('a' '>' 1) -> (t value: 'a' value: '>' value: 1).
  #('a' '>=' 1) -> (t value: 'a' value: '>=' value: 1). { 'a'. 'in'. #(1 2) } -> (t value: 'a' value: 'in' value: (PBTuple withAll: #(1 2))).
  #('a' 'contains' 'x') -> (t value: 'a' value: 'contains' value: 'x').
  #('a' '?N') -> (PBTerm path: 'a' op: '?N'). #('a' '?!N') -> (PBTerm path: 'a' op: '?!N').
  #('a' '?T') -> (PBTerm path: 'a' op: '?T'). #('a' '?!T') -> (PBTerm path: 'a' op: '?!T').
  #('a' 'between[]' 1 5) -> (t value: 'a' value: 'between[]' value: #(1 5)). #('a' 'between()' 1 5) -> (t value: 'a' value: 'between()' value: #(1 5)).
  #('a' 'between(]' 1 5) -> (t value: 'a' value: 'between(]' value: #(1 5)). #('a' 'between[)' 1 5) -> (t value: 'a' value: 'between[)' value: #(1 5)).
  { nil. '=='. 5 } -> (t value: nil value: '==' value: 5). #('a.b.c' '==' 5) -> (t value: 'a.b.c' value: '==' value: 5) } do: [:each |
    compiled := PBExpression compile: each key.
    expect value: each key printString value: compiled value: each value.
    expect value: each key printString , ' round trip' value: (PBExpression compile: compiled asList) value: compiled].
expect value: '&' value: (PBExpression compile: #('&' 'a' '==' 1 'b' '>' 2)) value: a1 & b2.
expect value: '|' value: (PBExpression compile: #('|' 'a' '==' 1 'b' '>' 2)) value: a1 | b2.
expect value: '!' value: (PBExpression compile: #('!' 'a' '==' 1)) value: a1 not.
expect value: '! !' value: (PBExpression compile: #('!' '!' 'a' '==' 1)) value: a1.
expect value: '& binary, then the implicit and' value: (PBExpression compile: #('&' 'a' '==' 1 'b' '>' 2 'c' '<' 3)) value: (PBAnd withAll: { a1. b2. c3 }).
expect value: '| of &' value: (PBExpression compile: #('|' 'a' '==' 1 '&' 'b' '>' 2 'c' '<' 3)) value: a1 | (b2 & c3).
expect value: '& of |' value: (PBExpression compile: #('&' '|' 'a' '==' 1 'b' '>' 2 'c' '<' 3)) value: (a1 | b2) & c3.
expect value: 'implicit and' value: (PBExpression compile: #('a' '==' 1 'b' '>' 2)) value: a1 & b2.
expect value: 'nested lists' value: (PBExpression compile: #(#('a' '==' 1) #('b' '>' 2))) value: a1 & b2.
expect value: 'nested prefix lists' value: (PBExpression compile: #('|' #('a' '==' 1) #('&' #('b' '>' 2) #('c' '<' 3)))) value: a1 | (b2 & c3).
expect value: 'a nested and joins the implicit and' value: (PBExpression compile: #(#('&' 'a' '==' 1 'b' '>' 2) 'c' '<' 3)) value: (PBAnd withAll: { a1. b2. c3 }).
expect value: '! of a nested list' value: (PBExpression compile: #('!' #('|' 'a' '==' 1 'b' '>' 2))) value: (a1 | b2) not.
expect value: 'three levels' value: (PBExpression compile: #(#(#('a' '==' 1)))) value: a1.
expect value: 'built expressions as tokens' value: (PBExpression compile: { '&'. a1. #('b' '>' 2) }) value: a1 & b2.
expect value: 'an expression compiles to itself' value: (PBExpression compile: a1) == a1 value: true.
expect value: 'a PBFrozenList is a list' value: (PBExpression compile: (PBFrozenList withAll: { 'a'. '=='. 1 })) value: a1.
{ a1 & (b2 | c3 not). PBOr withAll: { (a1 & b2) not. c3. t value: 'x' value: 'between[]' value: #(1 9) }.
  ((t value: 'y' value: 'in' value: #('a' 'b')) | (PBTerm path: 'z' op: '?T')) not } do: [:tree |
    expect value: 'round trip ' , tree printString value: (PBExpression compile: tree asList) value: tree].
expect value: 'and lists nested to the right' value: (PBAnd withAll: { a1. b2. c3 }) asList
  value: { '&'. a1 asList. { '&'. b2 asList. c3 asList } }.
expect value: 'the list of an in' value: (t value: 'y' value: 'in' value: #('a' 'b')) asList value: #('y' 'in' #('a' 'b')).
c that: 'compile: reads every operator and the prefix stream' is: fails asArray equals: #().

"test_compile_rejects_invalid_input"
fails := OrderedCollection new.
{ #() -> 'empty'. 'a == 1' -> 'list'. (PBTuple withAll: #('a' '==' 1)) -> 'list'. #('a') -> 'operator'.
  #('a' '=~' 1) -> 'Unknown operator ''=~'''. #('a' '==') -> 'needs a value'. #('a' 'between[]' 1) -> 'needs a lower and an upper bound'.
  #('&' 'a' '==' 1) -> '''&'' needs two operands'. #('|') -> '''|'' needs two operands'. #('!') -> '''!'' needs an operand'.
  #(5 '==' 1) -> 'Expected a path'. { #('a' '==' 1). 7 } -> 'Expected a path'. #(#()) -> 'empty'.
  { 'a'. '=='. #(1 2) } -> 'orderable'. #('a' 'between[]' 1 'z') -> 'one type rank'. #('a' '?N' 3) -> 'Expected a path'.
  #('a' 'in' 3) -> 'list, tuple or set' } do: [:each | | text |
    text := msg value: [PBExpression compile: each key].
    ((text beginsWith: 'PBValidationError: ') and: [text includesSubstring: each value]) ifFalse: [
      fails add: each key printString , ': ' , text]].
expect value: 'near[] in the list syntax' value: (refused value: [PBExpression compile: #('v' 'near[]' #(1 0) 0.8)]) value: PBNotSupportedError.
c that: 'compile: refuses malformed input' is: fails asArray equals: #().

"test_evaluate_term_is_the_scan_oracle, test_evaluate_truth_tables,
 test_not_of_a_comparison_on_a_missing_key_is_true, test_mixed_types_and_equal_but_distinct_values,
 test_and_or_short_circuit"
fails := OrderedCollection new.
samples := { rec value: #(). rec value: { 'a' -> nil }. rec value: { 'a' -> 1 }. rec value: { 'a' -> 1.0 }.
  rec value: { 'a' -> (Decimal fromString: '1.00') }. rec value: { 'a' -> true }. rec value: { 'a' -> 0 }.
  rec value: { 'a' -> 7 }. rec value: { 'a' -> 'x' }. rec value: { 'a' -> (PBFrozenList withAll: #(1 2)) }.
  rec value: { 'a' -> Float nan }. PBFrozenDict withAssociations: { 'a' -> 3 }. PBFrozenDict withAssociations: { 'b' -> 1 }. 5. nil }.
terms := { t value: 'a' value: '==' value: 1. t value: 'a' value: '!=' value: 1. t value: 'a' value: '<' value: 5.
  t value: 'a' value: '>=' value: 1. PBTerm path: 'a' op: '?N'. PBTerm path: 'a' op: '?!N'.
  t value: 'a' value: 'in' value: #(1 'x'). t value: 'a' value: 'between[]' value: #(0 3). PBTerm path: 'a' op: '?T'.
  PBTerm path: 'a' op: '?!T'. t value: 'a' value: 'contains' value: 2. t value: nil value: '==' value: 5 }.
terms do: [:term | samples do: [:s |
  (term evaluate: s) == (term matches: s) ifFalse: [fails add: 'evaluate: ' , term printString]]].
terms do: [:t1 | terms do: [:t2 | samples do: [:s | | m1 m2 |
  m1 := t1 matches: s. m2 := t2 matches: s.
  ((t1 & t2) evaluate: s) == (m1 and: [m2]) ifFalse: [fails add: 'and ' , t1 printString , ' ' , t2 printString].
  ((t1 | t2) evaluate: s) == (m1 or: [m2]) ifFalse: [fails add: 'or ' , t1 printString , ' ' , t2 printString].
  (t1 not evaluate: s) == m1 not ifFalse: [fails add: 'not ' , t1 printString].
  ((t1 & t2) not evaluate: s) == (m1 and: [m2]) not ifFalse: [fails add: 'not and ' , t1 printString]]]].
expect value: 'a comparison on a missing key' value: ((t value: 'a' value: '<' value: 5) evaluate: (rec value: #())) value: false.
expect value: 'its negation' value: ((t value: 'a' value: '<' value: 5) not evaluate: (rec value: #())) value: true.
expect value: '!= on a missing key' value: ((t value: 'a' value: '!=' value: 5) evaluate: (rec value: #())) value: false.
expect value: 'not == on a missing key' value: ((t value: 'a' value: '==' value: 5) not evaluate: (rec value: #())) value: true.
expect value: 'equal but distinct values' value: ({ 1. 1.0. Decimal fromString: '1.00'. true } collect: [:v | a1 evaluate: (rec value: { 'a' -> v })]) value: #(true true true false).
expect value: 'cross-rank order' value: ((t value: 'a' value: '>' value: 0) evaluate: (rec value: { 'a' -> 'x' })) value: false.
calls := OrderedCollection new.
spy := [:label :answer | PBBlockPredicate block: [:x | calls add: label. answer] description: label].
expect value: 'and short-circuits' value: ((spy value: 'first' value: false) & (spy value: 'second' value: true) evaluate: 1) value: false.
expect value: 'and calls' value: calls asArray value: #('first').
calls := OrderedCollection new.
expect value: 'or short-circuits' value: ((spy value: 'first' value: true) | (spy value: 'second' value: false) evaluate: 1) value: true.
expect value: 'or calls' value: calls asArray value: #('first').
c that: 'evaluate: is the scan oracle and short-circuits' is: fails asArray equals: #().

"test_contains_semantics, test_truthiness_operators, test_contains_on_dicts_and_collection_atoms"
fails := OrderedCollection new.
e := t value: 'a' value: 'contains' value: 2.
expect value: 'lists and tuples' value: ({ PBFrozenList withAll: #(1 2). PBTuple withAll: { 2.0 }. PBFrozenList withAll: { PBFrozenList withAll: #(0). 2 } }
  collect: [:v | e matches: (rec value: { 'a' -> v })]) value: #(true true true).
expect value: 'not contained' value: ({ PBFrozenList withAll: #(1 3). nil. 2. PBFrozenDict withAssociations: { 'x' -> 2 } }
  collect: [:v | e matches: (rec value: { 'a' -> v })]) value: #(false false false false).
expect value: 'absent' value: (e matches: (rec value: #())) value: false.
expect value: 'true is not 1' value: ((t value: 'a' value: 'contains' value: true) matches: (rec value: { 'a' -> (PBFrozenList withAll: #(1)) })) value: false.
pred := t value: 'a' value: 'contains' value: 'ell'.
expect value: 'substrings' value: ({ 'hello'. 'help'. #[101 108 108] } collect: [:v | pred matches: (rec value: { 'a' -> v })]) value: #(true false false).
expect value: 'bytes' value: ((t value: 'a' value: 'contains' value: #[101 108]) matches: (rec value: { 'a' -> #[104 101 108 108 111] })) value: true.
expect value: 'contains a list' value: (refused value: [t value: 'a' value: 'contains' value: #(1)]) value: PBValidationError.
{ 1 -> true. 0 -> false. '' -> false. 'x' -> true. nil -> false. (PBFrozenList withAll: #()) -> false. (PBFrozenList withAll: #(0)) -> true.
  (Decimal fromString: '0') -> false. Float nan -> true. 0.0 -> false. (TimeSpan days: 0 seconds: 0 microseconds: 0) -> false.
  (CalendarDate year: 2026 month: 1 day: 1) -> true. PBList new -> false. (PBList new appendLast: 1) -> true. (rec value: #()) -> true } do: [:each |
    expect value: '?T ' , each key printString value: ((PBTerm path: 'a' op: '?T') matches: (PBFrozenDict withAssociations: { 'a' -> each key })) value: each value.
    expect value: '?!T ' , each key printString value: ((PBTerm path: 'a' op: '?!T') matches: (PBFrozenDict withAssociations: { 'a' -> each key })) value: each value not].
expect value: 'an empty host collection is false' value: { (PBTerm path: nil op: '?T') matches: Set new. (PBTerm path: nil op: '?T') matches: (Set withAll: #(0)). (PBBlockPredicate block: [:x | Set new] description: 'empty') evaluate: 1 } value: #(false true false).
expect value: 'missing matches neither' value: { (PBTerm path: 'a' op: '?T') matches: (rec value: #()). (PBTerm path: 'a' op: '?!T') matches: (rec value: #()) } value: #(false false).
expect value: '?T with a value' value: (refused value: [t value: 'a' value: '?T' value: 1]) value: PBValidationError.
e := t value: 'c' value: 'contains' value: 2.
dict := [:assocs | PBFrozenDict withAssociations: { 'c' -> (PBFrozenDict withAssociations: assocs) }].
expect value: 'map keys' value: { e matches: (dict value: { 2 -> 'a' }). e matches: (dict value: { 2.0 -> 'a' }). e matches: (dict value: { 'x' -> 2 }) } value: #(true true false).
expect value: 'a map key of another type' value: ((t value: 'c' value: 'contains' value: '2') matches: (dict value: { 2 -> 1 })) value: false.
list := [:items | (items inject: PBList new into: [:l :x | l appendLast: x])].
expect value: 'a PBList' value: (e matches: (rec value: { 'c' -> (list value: { 1. 2.0. PBFrozenList withAll: #(3) }) })) value: true.
expect value: 'a PBList without it' value: (e matches: (rec value: { 'c' -> (list value: { 1. PBFrozenList withAll: #(2). true }) })) value: false.
expect value: 'a PBList and true' value: ((t value: 'c' value: 'contains' value: true) matches: (rec value: { 'c' -> (list value: #(1)) })) value: false.
set := [:items | items inject: PBSet new into: [:s :x | s add: x]].
expect value: 'a PBSet' value: { e matches: (rec value: { 'c' -> (set value: #(2 3)) }). e matches: (rec value: { 'c' -> (set value: #(3)) }) } value: #(true false).
counted := (PBCountedSet new add: 2) add: 2.
expect value: 'a PBCountedSet' value: { e matches: (rec value: { 'c' -> counted }). e matches: (rec value: { 'c' -> PBCountedSet new }) } value: #(true false).
dictionary := PBDictionary new setAt: 'k' value: 2.
expect value: 'a PBDictionary by key' value: { (t value: 'c' value: 'contains' value: 'k') matches: (rec value: { 'c' -> dictionary }). e matches: (rec value: { 'c' -> dictionary }) } value: #(true false).
nested := rec value: { 'inner' -> (rec value: { 'c' -> (list value: #('a' 2)) }) }.
expect value: 'a dotted path' value: ((t value: 'inner.c' value: 'contains' value: 2) matches: nested) value: true.
expect value: 'other keys' value: ({ nil. 2. 2.5. rec value: { 'c' -> 1 } } collect: [:v | e matches: (PBFrozenDict withAssociations: { 'c' -> v })]) value: #(false false false false).
expect value: 'evaluate: on a missing key' value: (e evaluate: (rec value: #())) value: false.
c that: 'contains and truthiness' is: fails asArray equals: #().

"& | not take expressions only (ruling CR5); PBBlockPredicate (expressions.py PythonPredicate)"
fails := OrderedCollection new.
{ [a1 & [:x | true]]. [a1 | [:x | true]]. [a1 & #('b' '>' 2)]. [a1 | true]. [PBNot of: [:x | true]] } do: [:each |
  expect value: each printString value: (refused value: each) value: PBValidationError].
expect value: 'the message' value: ((msg value: [a1 & [:x | true]]) includesSubstring: 'PBAnd operands must be PBExpression instances') value: true.
pred := PBBlockPredicate block: [:x | x > 3] description: 'more than three'.
expect value: 'a block predicate evaluates its block' value: ({ 2. 5 } collect: [:v | pred evaluate: v]) value: #(false true).
expect value: 'its answer is read as truthiness' value: ((PBBlockPredicate block: [:x | nil] description: 'nil') evaluate: 1) value: false.
expect value: 'it combines' value: ((pred & (t value: nil value: '<' value: 10)) evaluate: 5) value: true.
expect value: 'it describes itself' value: pred describe value: (PBFrozenDict withAssociations: { 'block' -> 'more than three' }).
expect value: 'it has no list form' value: (refused value: [pred asList]) value: PBNotSupportedError.
expect value: 'equal for the same block and description' value: { pred = (PBBlockPredicate block: pred block description: 'more than three'). pred = (PBBlockPredicate block: [:x | x > 3] description: 'more than three') } value: #(true false).
expect value: 'a block of one argument' value: { refused value: [PBBlockPredicate block: [:x :y | x] description: 'two']. refused value: [PBBlockPredicate block: 3 description: 'three'] } value: { PBValidationError. PBValidationError }.
expect value: 'a non-empty description' value: { refused value: [PBBlockPredicate block: [:x | x] description: '']. refused value: [PBBlockPredicate block: [:x | x] description: nil] } value: { PBValidationError. PBValidationError }.
expect value: 'its exception passes through' value: (refused value: [(PBBlockPredicate block: [:x | ZeroDivide new signal] description: 'boom') evaluate: 1]) value: ZeroDivide.
c that: '& | not take expressions only' is: fails asArray equals: #().

c report displayNl.
