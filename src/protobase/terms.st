"-- terms.st: PBTerm and the expression language (PBExpression, PBAnd, PBOr, PBNot, PBBlockPredicate) --

A port of proto_db's proto_db/query/terms.py and proto_db/query/expressions.py at v2.0.0rc4
(proto_db spec section 10, decisions D28 and D36), near[] included (vectors phase V2, Addendum V
2.6).

A PBTerm is (path, op, value): the key its path names (PBKeySpec forTermPath:, a dotted path, nil
for the element itself, '@name' for a registered extractor) compared with value by op, one of
proto_db's operator strings:

  '==' '!=' '<' '<=' '>' '>='     one orderable operand
  'in'                           a list, tuple or Set of orderable operands (a Set is sorted by
                                 order key, so equal Sets give equal terms; a sequence keeps its order)
  'between[]' 'between()'        a (low, high) pair of one type rank: [] includes both bounds, ()
  'between(]' 'between[)'        excludes both, (] the lower, [) the upper
  '?N' '?!N' '?T' '?!T'          no operand (PBTerm path:op:)
  'contains'                     one orderable operand
  'near[]'                       a PBNearQuery (vectors.st), or a Dictionary or PBFrozenDict of its
                                 fields (converted, PBTerm _nearQuery:)

An operand is made canonical (PBCodec canonical:) and must be orderable and not PBMissing; anything
else is PBValidationError (terms.py:152-213). A near[] term is answered by vector plans, never by
the scan oracle: its matches:, and so the evaluate: of an expression that reaches it, signal
PBNotSupportedError (terms.py:218-219), and it is equal to another by its PBNearQuery.

matches: is the scan oracle every index must agree with (terms.py:215-253, D28): '==' and 'in'
compare order keys (1 = 1.0 = Decimal 1, true is not 1, nil is a value); a PBMissing key (an absent
attribute) matches no comparison, '!=' included, and only '?N'; '?N' is true for PBMissing and nil,
'?!N' for every other key; '!=' matches a present key that is not '==' to the value, so it is not
the complement of '=='; the range operators match only keys of the value's type rank; unorderable
keys (lists, maps, NaN) match only '?!N', '!=', 'contains', '?T' and '?!T'. 'contains' is a
substring of a String or a ByteArray, an item of a list or tuple, a key of a map, and an element
of a collection atom by that collection's own membership (has: where it answers it, element
equality otherwise: terms.py _contains); '?T' and '?!T' test Python's truthiness of a present key
(nil, false, zero, empty strings and containers, a zero TimeSpan and an empty collection are
false). Terms are frozen values equal by path, operator and the order key of the value.

PBExpression is the abstract condition: a PBTerm, PBAnd and PBOr (n-ary, flattened, operand order
kept, at least two operands), PBNot (PBNot of: (PBNot of: e) is e) and PBBlockPredicate (an opaque
block with a description, the counterpart of proto_db's PythonPredicate). evaluate: is two-valued:
a term by matches:, PBAnd and PBOr short-circuit left to right, PBNot negates; so the negation of a
comparison is true for an element without the key. &, | and not combine expressions only (ruling
CR5): anything else is PBValidationError. Every node answers describe (a PBFrozenDict for explain:
a term {'path' 'op' 'value'}, {'and' -> {...}}, {'or' -> {...}}, {'not' -> ...}, {'block' ->
description}), asList (the 0.1 prefix list syntax) and termsDo:.

PBExpression compile: anArray reads the 0.1 prefix syntax (expressions.py module docstring): a list
(an Array, an OrderedCollection or a PBFrozenList) is a stream of expressions joined by an implicit
AND; an expression is 'path op' for the unary operators, 'path op value' for the comparisons, 'in'
and 'contains', 'path between-op low high', 'path near[] vector threshold' (the 0.1 cosine
threshold query) or 'path near[] aNearQueryOrMapping', '&' e1 e2 and '|' e1 e2 (binary, prefix),
'!' e, a nested list, or an expression already built. Malformed input is PBValidationError naming
the position (counted from 0, as proto_db counts it).

Messages follow proto_db's, with protoST's names; a value is quoted as Python's repr does for a
String (PBKeySpec _repr:). describe renders an operand as proto_db's display_value: nil, Booleans,
Integers, Strings and finite Floats as they are, tuples and lists as Arrays, a map as {'@dict' ->
pairs}, a PBNearQuery as its describe, any other value as Python's repr of it ('Decimal(''1.50'')', 'datetime.date(2026, 1, 2)',
b'...', 'inf'), so explain reads the same in both languages; the exceptions (an atom, an
instant-form datetime in an IANA zone) are listed in docs/deviations.md."

Import from: 'protobase/errors'.
Import from: 'protobase/keys'.
Import from: 'protobase/values'.
Import from: 'protobase/registry'.
Import from: 'protobase/codec'.
Import from: 'protobase/keyspec'.
Import from: 'protobase/collections'.
Import from: 'protobase/vectors'.
Import from: 'decimal'.
Import from: 'calendar'.
Import from: 'uuid'.

Object subclass: #PBExpression.
PBExpression subclass: #PBTerm instanceVariableNames: 'path op value keySpecObject valueKey operandKeys'.
PBExpression subclass: #_PBNode instanceVariableNames: 'operands'.
_PBNode subclass: #_PBJunction.
_PBJunction subclass: #PBAnd.
_PBJunction subclass: #PBOr.
_PBNode subclass: #PBNot.
PBExpression subclass: #PBBlockPredicate instanceVariableNames: 'block description'.

"=== PBExpression ============================================================="

"Whether anObject is a PBExpression."
PBExpression class >> _isExpression: anObject
  ^ anObject isClassObject not and: [anObject isKindOf: PBExpression].

"Whether anObject is a list of the 0.1 syntax: an Array, an OrderedCollection or a PBFrozenList
 (what Python's list is in protoST, and what a decoded MessagePack list is)."
PBExpression class >> _isList: anObject
  anObject isClassObject ifTrue: [^ false].
  ^ (anObject isKindOf: Array) or: [(anObject isKindOf: OrderedCollection) or: [anObject isKindOf: PBFrozenList]].

"anOperand, or PBValidationError when it is not an expression (expressions.py _check_operand)."
PBExpression class >> _checkOperand: anOperand owner: aName
  (self _isExpression: anOperand) ifFalse: [
    ^ PBValidationError signal: aName , ' operands must be PBExpression instances, not ' , (PBKeySpec _repr: anOperand)
      , '; use PBExpression compile: for the list syntax'].
  ^ anOperand.

"The expression of the 0.1 prefix syntax anObject (expressions.py Expression.compile); an
 expression is answered unchanged."
PBExpression class >> compile: anObject
  (self _isExpression: anObject) ifTrue: [^ anObject].
  (self _isList: anObject) ifFalse: [
    ^ PBValidationError signal: 'PBExpression compile: needs a list in the 0.1 prefix syntax, not a ' , anObject class name].
  ^ self _compileAll: anObject asArray.

"expressions.py _Compiler.compile_all: every expression of the stream, joined by AND."
PBExpression class >> _compileAll: aTokenArray
  | parsed i |
  aTokenArray isEmpty ifTrue: [^ PBValidationError signal: 'Cannot compile an empty expression list'].
  parsed := OrderedCollection new.
  i := 1.
  [i <= aTokenArray size] whileTrue: [
    | step |
    step := self _parse: aTokenArray at: i.
    parsed add: (step at: 1).
    i := step at: 2].
  parsed size = 1 ifTrue: [^ parsed first].
  ^ PBAnd withAll: parsed asArray.

"The expression starting at index anIndex of aTokenArray and the index after it, as an Array
 (expressions.py _Compiler.parse; positions in messages count from 0, as proto_db's)."
PBExpression class >> _parse: aTokenArray at: anIndex
  | token first second |
  token := aTokenArray at: anIndex.
  (self _isExpression: token) ifTrue: [^ { token. anIndex + 1 }].
  (self _isList: token) ifTrue: [^ { self compile: token. anIndex + 1 }].
  (self _isText: token) ifTrue: [
    token = '!' ifTrue: [
      anIndex + 1 > aTokenArray size ifTrue: [
        ^ PBValidationError signal: '''!'' needs an operand (position ' , (anIndex - 1) printString , ' of '
          , (PBKeys _preview: aTokenArray) , ')'].
      first := self _parse: aTokenArray at: anIndex + 1.
      ^ { PBNot of: (first at: 1). first at: 2 }].
    (token = '&' or: [token = '|']) ifTrue: [
      anIndex + 1 > aTokenArray size ifTrue: [^ self _twoOperands: token at: anIndex of: aTokenArray].
      first := self _parse: aTokenArray at: anIndex + 1.
      (first at: 2) > aTokenArray size ifTrue: [^ self _twoOperands: token at: anIndex of: aTokenArray].
      second := self _parse: aTokenArray at: (first at: 2).
      ^ { (token = '&' ifTrue: [PBAnd] ifFalse: [PBOr]) withAll: { first at: 1. second at: 1 }. second at: 2 }]].
  (token isNil or: [self _isText: token]) ifFalse: [
    ^ PBValidationError signal: 'Expected a path (a String or nil), ''&'', ''|'', ''!'' or a nested list at position '
      , (anIndex - 1) printString , ' of ' , (PBKeys _preview: aTokenArray) , ', got ' , (PBKeySpec _repr: token)].
  ^ self _parseTerm: aTokenArray at: anIndex.

PBExpression class >> _twoOperands: aToken at: anIndex of: aTokenArray
  ^ PBValidationError signal: (PBKeySpec _repr: aToken) , ' needs two operands (position ' , (anIndex - 1) printString
    , ' of ' , (PBKeys _preview: aTokenArray) , ')'.

"expressions.py _Compiler.parse_term: the term whose path is at anIndex."
PBExpression class >> _parseTerm: aTokenArray at: anIndex
  | path op rest value |
  path := aTokenArray at: anIndex.
  anIndex + 1 > aTokenArray size ifTrue: [
    ^ PBValidationError signal: 'Term at position ' , (anIndex - 1) printString , ' needs an operator after path '
      , (PBKeySpec _repr: path)].
  op := aTokenArray at: anIndex + 1.
  ((self _isText: op) and: [PBTerm operators includes: op]) ifFalse: [
    ^ PBValidationError signal: 'Unknown operator ' , (PBKeySpec _repr: op) , ' at position ' , anIndex printString
      , '; expected one of ' , PBTerm _operatorList].
  rest := aTokenArray size - (anIndex + 1).
  (PBTerm unaryOperators includes: op) ifTrue: [^ { PBTerm path: path op: op. anIndex + 2 }].
  (PBTerm betweenOperators includes: op) ifTrue: [
    rest < 2 ifTrue: [
      ^ PBValidationError signal: 'Operator ' , (PBKeySpec _repr: op) , ' at position ' , anIndex printString
        , ' needs a lower and an upper bound'].
    ^ { PBTerm path: path op: op value: { aTokenArray at: anIndex + 2. aTokenArray at: anIndex + 3 }. anIndex + 4 }].
  rest < 1 ifTrue: [
    ^ PBValidationError signal: 'Operator ' , (PBKeySpec _repr: op) , ' at position ' , anIndex printString , ' needs a value'].
  value := aTokenArray at: anIndex + 2.
  (op = PBTerm nearOperator and: [(self _isNearValue: value) not]) ifTrue: [
    "The 0.1 form: a cosine threshold query (expressions.py:352-356)."
    rest < 2 ifTrue: [
      ^ PBValidationError signal: '''near[]'' at position ' , anIndex printString
        , ' needs a vector and a threshold (or a NearQuery / mapping of its fields)'].
    ^ { PBTerm path: path op: op value: (PBNearQuery vector: value k: nil threshold: (aTokenArray at: anIndex + 3) metric: 'cosine').
      anIndex + 4 }].
  ^ { PBTerm path: path op: op value: value. anIndex + 3 }.

"Whether anObject is a near[] value of the long form: a PBNearQuery or a mapping (a Dictionary or
 a PBFrozenDict; expressions.py: isinstance(value, (NearQuery, dict)))."
PBExpression class >> _isNearValue: anObject
  anObject isClassObject ifTrue: [^ false].
  ^ (anObject isKindOf: PBNearQuery) or: [(anObject isKindOf: Dictionary) or: [anObject isKindOf: PBFrozenDict]].

"Whether anObject is a String (not a Symbol)."
PBExpression class >> _isText: anObject
  ^ anObject isClassObject not and: [anObject isString and: [anObject isSymbol not]].

"Whether anElement satisfies the receiver (expressions.py evaluate). Subclasses answer it."
PBExpression >> evaluate: anElement
  ^ self subclassResponsibility.

"A PBFrozenDict for explain. Subclasses answer it."
PBExpression >> describe
  ^ self subclassResponsibility.

"The receiver in the 0.1 prefix syntax: PBExpression compile: e asList is e. Subclasses answer it."
PBExpression >> asList
  ^ self subclassResponsibility.

"Evaluates aBlock with every PBTerm of the receiver, depth first, left to right (expressions.py
 iter_terms). Subclasses answer it."
PBExpression >> termsDo: aBlock
  ^ self subclassResponsibility.

"Both the receiver and anExpression: a PBAnd (flattened)."
PBExpression >> & anExpression
  ^ PBAnd withAll: { self. anExpression }.

"The receiver or anExpression: a PBOr (flattened)."
PBExpression >> | anExpression
  ^ PBOr withAll: { self. anExpression }.

"The negation of the receiver; the negation of a PBNot is its operand."
PBExpression >> not
  ^ PBNot of: self.

"=== PBTerm =================================================================="

"proto_db's operator strings (terms.py OPERATORS), in the order of test_terms.py's vocabulary test."
PBTerm class >> operators
  ^ #('==' '!=' '<' '<=' '>' '>=' 'in' 'between[]' 'between()' 'between(]' 'between[)' '?N' '?!N' 'near[]' 'contains' '?T' '?!T').

"The operators that take no value (terms.py UNARY_OPERATORS)."
PBTerm class >> unaryOperators
  ^ #('?N' '?!N' '?T' '?!T').

PBTerm class >> betweenOperators
  ^ #('between[]' 'between()' 'between(]' 'between[)').

PBTerm class >> scalarOperators
  ^ #('==' '!=' '<' '<=' '>' '>=').

"proto_db's vector operator (terms.py NEAR): its value is a PBNearQuery."
PBTerm class >> nearOperator
  ^ 'near[]'.

"The operators as Python prints sorted(OPERATORS)."
PBTerm class >> _operatorList
  ^ '[' , (', ' join: ((self operators asSortedCollection: [:a :b | a <= b]) asArray collect: [:each | PBCodec repr: each])) , ']'.

"The term (aStringOrNil, anOperator, aValue), validated as proto_db's Term.__post_init__."
PBTerm class >> path: aStringOrNil op: anOperator value: aValue
  | spec operands keys canonical low high |
  spec := PBKeySpec forTermPath: aStringOrNil.
  (PBExpression _isText: anOperator) ifFalse: [^ self _unknownOperator: anOperator].
  (self operators includes: anOperator) ifFalse: [^ self _unknownOperator: anOperator].
  anOperator = self nearOperator ifTrue: [
    canonical := self _nearQuery: aValue.
    ^ self _path: aStringOrNil op: anOperator value: canonical spec: spec valueKey: canonical operandKeys: #()].
  ((self scalarOperators includes: anOperator) or: [anOperator = 'contains']) ifTrue: [
    canonical := self _operand: aValue op: anOperator.
    keys := { PBKeys orderKey: canonical }.
    ^ self _path: aStringOrNil op: anOperator value: canonical spec: spec valueKey: keys first operandKeys: keys].
  anOperator = 'in' ifTrue: [
    (self _isOperandCollection: aValue) ifFalse: [
      ^ PBValidationError signal: 'Operator ''in'' needs a list, tuple or set of values (an Array, an OrderedCollection, a PBFrozenList, a PBTuple or a Set), not '
        , (PBKeySpec _repr: aValue)].
    operands := aValue asArray collect: [:each | self _operand: each op: anOperator].
    keys := operands collect: [:each | PBKeys orderKey: each].
    (aValue isKindOf: Set) ifTrue: [
      | sorted |
      sorted := ((1 to: operands size) asArray collect: [:i | (keys at: i) -> (operands at: i)])
        sorted: [:a :b | a key <= b key].
      operands := sorted collect: [:each | each value].
      keys := sorted collect: [:each | each key]].
    canonical := PBTuple withAll: operands.
    ^ self _path: aStringOrNil op: anOperator value: canonical spec: spec valueKey: (PBKeys orderKey: canonical) operandKeys: keys].
  (self betweenOperators includes: anOperator) ifTrue: [
    ((self _isPair: aValue) and: [aValue size = 2]) ifFalse: [
      ^ PBValidationError signal: 'Operator ' , (PBKeySpec _repr: anOperator) , ' needs a (low, high) pair, not '
        , (PBKeySpec _repr: aValue)].
    low := self _operand: (aValue asArray at: 1) op: anOperator.
    high := self _operand: (aValue asArray at: 2) op: anOperator.
    keys := { PBKeys orderKey: low. PBKeys orderKey: high }.
    (keys at: 1) rank = (keys at: 2) rank ifFalse: [
      ^ PBValidationError signal: 'Operator ' , (PBKeySpec _repr: anOperator) , ' needs bounds of one type rank, not '
        , (PBKeySpec _repr: low) , ', ' , (PBKeySpec _repr: high)].
    canonical := PBTuple _trustedOn: { low. high }.
    ^ self _path: aStringOrNil op: anOperator value: canonical spec: spec valueKey: (PBKeys orderKey: canonical) operandKeys: keys].
  aValue isNil ifFalse: [
    ^ PBValidationError signal: 'Operator ' , (PBKeySpec _repr: anOperator) , ' takes no value, got ' , (PBKeySpec _repr: aValue)].
  ^ self _path: aStringOrNil op: anOperator value: nil spec: spec valueKey: (PBKeys orderKey: nil) operandKeys: #().

"The PBNearQuery anObject names (terms.py _near_query, terms.py:128-137): itself, or a Dictionary
 or PBFrozenDict holding 'vector' and only 'vector', 'k', 'threshold' and 'metric' (String keys),
 converted; PBValidationError otherwise. The text of an unknown key lists the keys as Python's
 sorted(map(str, keys)) prints them (PBCodec _pyStr:)."
PBTerm class >> _nearQuery: anObject
  | keys texts at |
  (anObject isClassObject not and: [anObject isKindOf: PBNearQuery]) ifTrue: [^ anObject].
  (anObject isClassObject not and: [(anObject isKindOf: Dictionary) or: [anObject isKindOf: PBFrozenDict]]) ifFalse: [
    ^ PBValidationError signal: 'near[] needs a NearQuery (or a mapping of its fields), not ' , (PBKeySpec _repr: anObject)].
  keys := OrderedCollection new.
  anObject keysAndValuesDo: [:k :v | keys add: k].
  ((keys allSatisfy: [:k | (PBExpression _isText: k) and: [#('vector' 'k' 'threshold' 'metric') includes: k]])
      and: [keys anySatisfy: [:k | (PBExpression _isText: k) and: [k = 'vector']]]) ifFalse: [
    texts := (keys collect: [:k | PBCodec _pyStr: k]) asArray asSortedCollection: [:a :b | a <= b].
    ^ PBValidationError signal: 'A near[] mapping needs ''vector'' and only vector/k/threshold/metric, got ['
      , (', ' join: (texts asArray collect: [:each | PBCodec repr: each])) , ']'].
  at := [:name | | found | found := nil. anObject keysAndValuesDo: [:k :v | k = name ifTrue: [found := v]]. found].
  ^ PBNearQuery vector: (at value: 'vector') k: (at value: 'k') threshold: (at value: 'threshold') metric: (at value: 'metric').

"The term (aStringOrNil, anOperator) of a unary operator ('?N', '?!N', '?T', '?!T')."
PBTerm class >> path: aStringOrNil op: anOperator
  ^ self path: aStringOrNil op: anOperator value: nil.

PBTerm class >> _path: aStringOrNil op: anOperator value: aValue spec: aKeySpec valueKey: anOrderKey operandKeys: anArray
  ^ self basicNew _setPath: (aStringOrNil isNil ifTrue: [nil] ifFalse: [aStringOrNil copy]) op: anOperator copy value: aValue
    keySpecObject: aKeySpec valueKey: anOrderKey operandKeys: anArray.

PBTerm class >> _unknownOperator: anOperator
  ^ PBValidationError signal: 'Unknown operator ' , (PBKeySpec _repr: anOperator) , '; expected one of ' , self _operatorList.

"terms.py _operand: aValue made canonical, orderable and not PBMissing."
PBTerm class >> _operand: aValue op: anOperator
  | canonical |
  canonical := PBCodec canonical: aValue.
  (canonical == PBMissing default or: [(PBKeys isOrderable: canonical) not]) ifTrue: [
    ^ PBValidationError signal: 'Operator ' , (PBKeySpec _repr: anOperator) , ' needs an orderable value other than MISSING, not '
      , (PBKeySpec _repr: canonical)].
  ^ canonical.

"An 'in' operand: Python's list, tuple, set or frozenset (an Array, an OrderedCollection, a
 PBFrozenList, a PBTuple or a Set; never a String)."
PBTerm class >> _isOperandCollection: anObject
  anObject isClassObject ifTrue: [^ false].
  ^ (self _isPair: anObject) or: [anObject isKindOf: Set].

"A between operand: Python's list or tuple."
PBTerm class >> _isPair: anObject
  anObject isClassObject ifTrue: [^ false].
  ^ (PBExpression _isList: anObject) or: [anObject isKindOf: PBTuple].

"The order key of aKey, or nil when it has none (terms.py is_orderable)."
PBTerm class >> _orderKeyOrNil: aKey
  "An Integer's key is built directly: it is what PBKeys _orderKeyLeaf: builds for one, which never
   signals, without the handler and the fold."
  (aKey isClassObject not and: [aKey isInteger]) ifTrue: [^ PBOrderKey basicNew _setRank: 3 payload: aKey].
  ^ [PBKeys orderKey: aKey] on: PBValidationError do: [:e | e return: nil].

"Python's bool(aValue): nil, false, PBMissing, a zero number (a NaN is true), an empty String,
 ByteArray, list, tuple or map, a zero TimeSpan, an empty collection atom (proto_db's
 IndexedCollection.__len__) and any other empty host collection are false; everything else is true."
PBTerm class >> _truthy: aValue
  aValue isNil ifTrue: [^ false].
  aValue == true ifTrue: [^ true].
  aValue == false ifTrue: [^ false].
  aValue isClassObject ifTrue: [^ true].
  aValue == PBMissing default ifTrue: [^ false].
  (aValue isKindOf: Decimal) ifTrue: [^ aValue isNaN or: [aValue isZero not]].
  aValue isNumber ifTrue: [^ (aValue = 0) not].
  ((aValue isString or: [aValue isKindOf: ByteArray]) or: [
      (aValue isKindOf: _PBSequence) or: [(aValue isKindOf: PBFrozenDict) or: [
        (aValue isKindOf: Array) or: [(aValue isKindOf: OrderedCollection) or: [aValue isKindOf: Dictionary]]]]]) ifTrue: [
    ^ aValue isEmpty not].
  (aValue isKindOf: TimeSpan) ifTrue: [^ aValue totalMicroseconds ~= 0].
  (aValue isKindOf: PBIndexedCollection) ifTrue: [^ aValue count ~= 0].
  "Any other host collection (a Set, a Bag, an Interval): empty is false, as Python's bool of a
   container."
  (aValue isCollection and: [aValue isEmpty]) ifTrue: [^ false].
  ^ true.

"terms.py _contains: whether aKey contains anOperand, whose order key is anOrderKey."
PBTerm class >> _contains: aKey operand: anOperand key: anOrderKey
  | matches |
  aKey isClassObject ifTrue: [^ false].
  (PBExpression _isText: aKey) ifTrue: [^ (PBExpression _isText: anOperand) and: [aKey includesSubstring: anOperand]].
  (aKey isKindOf: ByteArray) ifTrue: [^ (anOperand isKindOf: ByteArray) and: [self _bytes: aKey include: anOperand]].
  matches := [:item | (self _orderKeyOrNil: item) = anOrderKey].
  (((aKey isKindOf: _PBSequence) or: [aKey isKindOf: Array]) or: [aKey isKindOf: OrderedCollection]) ifTrue: [
    ^ aKey asArray anySatisfy: matches].
  (aKey isKindOf: PBFrozenDict) ifTrue: [^ aKey keys anySatisfy: matches].
  (aKey isKindOf: Dictionary) ifTrue: [^ aKey keys anySatisfy: matches].
  (aKey isKindOf: PBIndexedCollection) ifTrue: [
    "A collection's own membership (proto_db: Dictionary, HashDictionary, Set, CountedSet and
     RepeatedKeysDictionary define __contains__ as has); element equality otherwise (List)."
    (aKey respondsTo: #has:) ifTrue: [^ aKey has: anOperand].
    aKey do: [:each | (matches value: each) ifTrue: [^ true]].
    ^ false].
  ^ false.

"Whether the bytes aNeedle occur in aByteArray (Python's bytes in bytes)."
PBTerm class >> _bytes: aByteArray include: aNeedle
  | n |
  n := aNeedle size.
  0 to: aByteArray size - n do: [:offset |
    ((1 to: n) allSatisfy: [:i | (aByteArray at: offset + i) = (aNeedle at: i)]) ifTrue: [^ true]].
  ^ false.

"proto_db's display_value: aValue as explain shows it (terms.py display_value). nil, Booleans,
 Integers, Strings and finite Floats are kept; tuples and lists become Arrays; a map becomes
 {'@dict' -> {{key. value}. ...}}; any other value becomes Python's repr of it (PBCodec _pyRepr:).
 Any depth (an explicit stack)."
PBTerm class >> displayValue: aValue
  ^ _PBValueFrame fold: aValue
    children: [:v | PBCodec _pyItems: v]
    leaf: [:v | self _displayLeaf: v]
    node: [:v :results |
      (v isKindOf: PBFrozenDict)
        ifTrue: [PBFrozenDict withAssociations: { '@dict' -> ((1 to: results size // 2) asArray collect: [:i |
          { results at: 2 * i - 1. results at: 2 * i }]) }]
        ifFalse: [results asArray]].

PBTerm class >> _displayLeaf: aValue
  aValue isNil ifTrue: [^ nil].
  (aValue == true or: [aValue == false]) ifTrue: [^ aValue].
  aValue isClassObject ifTrue: [^ aValue printString].
  aValue isInteger ifTrue: [^ aValue].
  (PBExpression _isText: aValue) ifTrue: [^ aValue].
  (aValue isFloat and: [aValue isNaN not and: [aValue isInfinite not]]) ifTrue: [^ aValue].
  (aValue isKindOf: PBNearQuery) ifTrue: [^ aValue describe].
  ^ PBCodec _pyRepr: aValue.

PBTerm >> _setPath: aStringOrNil op: anOperator value: aValue keySpecObject: aKeySpec valueKey: anOrderKey operandKeys: anArray
  "Runs once, on a fresh instance."
  op isNil ifFalse: [^ PBUserError signal: 'PBTerm is immutable'].
  path := aStringOrNil.
  op := anOperator.
  value := aValue.
  keySpecObject := aKeySpec.
  valueKey := anOrderKey.
  operandKeys := anArray.
  ^ self.

"The path: a dotted path, nil for the element itself, '@name' for an extractor."
PBTerm >> path
  ^ path.

PBTerm >> op
  ^ op.

"The canonical operand: one value, a PBTuple of operands for 'in', the PBTuple (low, high) for
 the between operators, the PBNearQuery for 'near[]', nil for the unary ones."
PBTerm >> value
  ^ value.

"The PBKeySpec the path names (PBKeySpec forTermPath: path)."
PBTerm >> keySpecObject
  ^ keySpecObject.

"Whether anElement satisfies the term: the scan oracle (terms.py Term.matches, D28; the module
 comment). An extractor's exception passes through unwrapped. A near[] term is
 PBNotSupportedError: its answer depends on the index's metric and on the whole collection.
 The operator is read once, by its first character, which tells every operator apart but '<' from
 '<=' and '>' from '>=' (by its size), the four between operators (by their brackets) and the four
 unary ones (by their second and last characters); each operator takes the steps of its own branch
 in proto_db's order: near[] refused before the key is read, then the key, the unary operators
 (MISSING and nil are none for ?N), MISSING false, contains, the order key (nil for an unorderable
 key: != true, every other operator false), then the comparison, an ordered one false across
 ranks."
PBTerm >> matches: anElement
  | c key k low high |
  c := op at: 1.
  c = $n ifTrue: [
    ^ PBNotSupportedError signal: '''near[]'' terms are answered by vector plans, not by a scan'].
  key := keySpecObject extract: anElement.
  c = $? ifTrue: [ | negated |
    negated := (op at: 2) = $!.
    (op at: op size) = $N ifTrue: [^ (key == PBMissing default or: [key isNil]) ~= negated].
    key == PBMissing default ifTrue: [^ false].
    ^ (self class _truthy: key) ~= negated].
  key == PBMissing default ifTrue: [^ false].
  c = $c ifTrue: [^ self class _contains: key operand: value key: valueKey].
  k := self class _orderKeyOrNil: key.
  c = $! ifTrue: [^ (k notNil and: [k = valueKey]) not].
  k isNil ifTrue: [^ false].
  c = $= ifTrue: [^ k = valueKey].
  c = $i ifTrue: [^ operandKeys anySatisfy: [:each | k = each]].
  c = $b ifTrue: [
    low := operandKeys at: 1.
    high := operandKeys at: 2.
    k rank = low rank ifFalse: [^ false].
    ^ ((op at: 8) = $[ ifTrue: [low <= k] ifFalse: [low < k])
      and: [(op at: 9) = $] ifTrue: [k <= high] ifFalse: [k < high]]].
  k rank = valueKey rank ifFalse: [^ false].
  c = $< ifTrue: [^ op size = 1 ifTrue: [k < valueKey] ifFalse: [k <= valueKey]].
  ^ op size = 1 ifTrue: [k > valueKey] ifFalse: [k >= valueKey].

PBTerm >> evaluate: anElement
  ^ self matches: anElement.

"The parts of proto_db's repr (PBCodec _pyRepr:): path, operator and value (nil for a unary
 operator, as proto_db stores it)."
PBTerm >> _pyReprParts
  ^ { path. op. (self class unaryOperators includes: op) ifTrue: [nil] ifFalse: [value] }.

"Term(path=..., op=..., value=...): the dataclass repr of terms.py Term (its key_spec is
 repr=False), anArray the reprs of _pyReprParts."
PBTerm >> _pyReprWith: anArray
  ^ 'Term(path=' , (anArray at: 1) , ', op=' , (anArray at: 2) , ', value=' , (anArray at: 3) , ')'.

"{ 'path'. 'op'. 'value' } as a PBFrozenDict, the value as proto_db's display_value renders it."
PBTerm >> describe
  ^ PBFrozenDict withAssociations: { 'path' -> path. 'op' -> op. 'value' -> (self class displayValue: value) }.

"{ path. op } for a unary operator, { path. op. low. high } for a between operator, { path.
 'near[]'. vector. threshold } for a cosine threshold query (the 0.1 form; vector an Array), { path.
 'in'. operands } for 'in', { path. op. value } otherwise, a near[] term's value its PBNearQuery
 (terms.py Term.to_list)."
PBTerm >> asList
  (self class unaryOperators includes: op) ifTrue: [^ { path. op }].
  (self class betweenOperators includes: op) ifTrue: [^ { path. op. value at: 1. value at: 2 }].
  op = self class nearOperator ifTrue: [
    (value k isNil and: [value metric = 'cosine']) ifTrue: [^ { path. op. value vector asArray. value threshold }].
    ^ { path. op. value }].
  op = 'in' ifTrue: [^ { path. op. value asArray }].
  ^ { path. op. value }.

PBTerm >> termsDo: aBlock
  aBlock value: self.

"Equal by path, operator and the order key of the value (terms.py Term.__eq__): two equal terms
 match the same elements."
PBTerm >> = anObject
  (anObject isClassObject not and: [anObject class == PBTerm]) ifFalse: [^ false].
  ^ (path = anObject path and: [op = anObject op]) and: [valueKey = anObject _valueKey].

PBTerm >> _valueKey
  ^ valueKey.

"The order keys of the operands, computed once when the term was made: { value's } for a scalar
 operator and 'contains', one per operand for 'in', { low's. high's } for a between operator, empty
 for a unary one (the index plans use them, never recompute them)."
PBTerm >> _operandKeys
  ^ operandKeys.

PBTerm >> hash
  ^ ((path hash bitXor: op hash) bitXor: valueKey hash) \\ 1073741824.

PBTerm >> printOn: aStream
  aStream nextPutAll: 'PBTerm('; print: path; nextPutAll: ', '; print: op.
  (self class unaryOperators includes: op) ifFalse: [aStream nextPutAll: ', '; print: value].
  aStream nextPut: $).

"=== PBAnd, PBOr, PBNot ======================================================"

_PBNode >> _setOperands: anArray
  "Runs once, on a fresh instance."
  operands isNil ifFalse: [^ PBUserError signal: self class name , ' is immutable'].
  operands := anArray.
  ^ self.

"The operands, in evaluation order (a fresh Array)."
_PBNode >> operands
  ^ operands copy.

_PBNode >> = anObject
  (anObject isClassObject not and: [anObject class == self class]) ifFalse: [^ false].
  ^ operands = anObject operands.

_PBNode >> hash
  | h |
  h := self class name hash.
  operands do: [:each | h := (h * 31 + each hash) \\ 1073741824].
  ^ h.

"The parts of proto_db's repr (PBCodec _pyRepr:): the operands."
_PBNode >> _pyReprParts
  ^ operands asArray.

"And(...), Or(...), Not(...): expressions.py _Node.__repr__, the class's proto_db name and the
 operands' reprs (anArray)."
_PBNode >> _pyReprWith: anArray
  ^ (self class name copyFrom: 3 to: self class name size) , '(' , (', ' join: anArray) , ')'.

_PBNode >> printOn: aStream
  aStream nextPutAll: self class name; nextPut: $(.
  operands doWithIndex: [:each :i |
    i > 1 ifTrue: [aStream nextPutAll: ', '].
    aStream print: each].
  aStream nextPut: $).

_PBNode >> termsDo: aBlock
  operands do: [:each | each termsDo: aBlock].

"A conjunction or disjunction of anArray's expressions: nested nodes of the same class are
 flattened, the order is kept, and at least two operands remain (expressions.py _Junction)."
_PBJunction class >> withAll: anArray
  | flat |
  (anArray isClassObject not and: [(anArray isKindOf: Array) or: [anArray isKindOf: OrderedCollection]]) ifFalse: [
    ^ PBValidationError signal: self name , ' withAll: needs an Array of expressions, not ' , (PBKeySpec _repr: anArray)].
  flat := OrderedCollection new.
  anArray do: [:each |
    PBExpression _checkOperand: each owner: self name.
    each class == self ifTrue: [flat addAll: each operands] ifFalse: [flat add: each]].
  flat size < 2 ifTrue: [
    ^ PBValidationError signal: self name , ' needs at least two operands, got ' , flat size printString].
  ^ self basicNew _setOperands: flat asArray.

"The prefix token of the 0.1 syntax."
_PBJunction >> _token
  ^ self subclassResponsibility.

"The key of describe."
_PBJunction >> _key
  ^ self subclassResponsibility.

_PBJunction >> describe
  ^ PBFrozenDict withAssociations: { self _key -> (operands collect: [:each | each describe]) }.

"{ token. e1. e2 }, nested to the right for more than two operands (flattened again by compile:)."
_PBJunction >> asList
  | items result |
  items := operands collect: [:each | each asList].
  result := items last.
  items size - 1 to: 1 by: -1 do: [:i | result := { self _token. items at: i. result }].
  ^ result.

PBAnd >> _token
  ^ '&'.

PBAnd >> _key
  ^ 'and'.

"True when every operand is, evaluated left to right until one is false."
PBAnd >> evaluate: anElement
  operands do: [:each | (each evaluate: anElement) ifFalse: [^ false]].
  ^ true.

PBOr >> _token
  ^ '|'.

PBOr >> _key
  ^ 'or'.

"True when some operand is, evaluated left to right until one is true."
PBOr >> evaluate: anElement
  operands do: [:each | (each evaluate: anElement) ifTrue: [^ true]].
  ^ false.

"The negation of anExpression; the negation of a PBNot is its operand (expressions.py Not)."
PBNot class >> of: anExpression
  PBExpression _checkOperand: anExpression owner: 'PBNot'.
  anExpression class == PBNot ifTrue: [^ anExpression operand].
  ^ self basicNew _setOperands: { anExpression }.

PBNot >> operand
  ^ operands at: 1.

PBNot >> evaluate: anElement
  ^ ((operands at: 1) evaluate: anElement) not.

PBNot >> describe
  ^ PBFrozenDict withAssociations: { 'not' -> (operands at: 1) describe }.

PBNot >> asList
  ^ { '!'. (operands at: 1) asList }.

"=== PBBlockPredicate ========================================================"

"An opaque condition (expressions.py PythonPredicate): aBlock of one argument, described by the
 non-empty aString in explain. No index answers it; it has no list form."
PBBlockPredicate class >> block: aBlock description: aString
  ((aBlock isClassObject not and: [aBlock isKindOf: BlockClosure]) and: [aBlock numArgs = 1]) ifFalse: [
    ^ PBValidationError signal: 'PBBlockPredicate needs a block of one argument, not ' , (PBKeySpec _repr: aBlock)].
  ((PBExpression _isText: aString) and: [aString notEmpty]) ifFalse: [
    ^ PBValidationError signal: 'PBBlockPredicate needs a non-empty description, not ' , (PBKeySpec _repr: aString)].
  ^ self basicNew _setBlock: aBlock description: aString copy.

PBBlockPredicate >> _setBlock: aBlock description: aString
  "Runs once, on a fresh instance."
  block isNil ifFalse: [^ PBUserError signal: 'PBBlockPredicate is immutable'].
  block := aBlock.
  description := aString.
  ^ self.

PBBlockPredicate >> block
  ^ block.

PBBlockPredicate >> description
  ^ description.

"The truthiness of the block's answer for anElement (Python's bool(fn(element))); its exceptions
 pass through."
PBBlockPredicate >> evaluate: anElement
  ^ PBTerm _truthy: (block value: anElement).

"{ 'block' -> description } (proto_db's {'python': description}, named after the language that
 runs it)."
PBBlockPredicate >> describe
  ^ PBFrozenDict withAssociations: { 'block' -> description }.

"Refused (expressions.py PythonPredicate.to_list): the predicate quoted as proto_db's repr, 'a
 block' where proto_db writes 'a Python callable' (docs/deviations.md, Block predicates)."
PBBlockPredicate >> asList
  ^ PBNotSupportedError signal: (PBCodec _pyRepr: self) , ' wraps a block and has no 0.1 list form'.

PBBlockPredicate >> termsDo: aBlock
  ^ self.

"Equal when it wraps the same block with the same description."
PBBlockPredicate >> = anObject
  (anObject isClassObject not and: [anObject class == PBBlockPredicate]) ifFalse: [^ false].
  ^ block == anObject block and: [description = anObject description].

PBBlockPredicate >> hash
  ^ description hash.

"The parts of proto_db's repr (PBCodec _pyRepr:): the description."
PBBlockPredicate >> _pyReprParts
  ^ { description }.

"PythonPredicate('...'): expressions.py PythonPredicate.__repr__ (the class protoBaseST ports as
 PBBlockPredicate), anArray the repr of the description."
PBBlockPredicate >> _pyReprWith: anArray
  ^ 'PythonPredicate(' , (anArray at: 1) , ')'.

PBBlockPredicate >> printOn: aStream
  aStream nextPutAll: 'PBBlockPredicate('; print: description; nextPut: $).
