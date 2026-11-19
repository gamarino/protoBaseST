"EXPECT: ok 12"
"Indexed queries, plan Task 5: PBTerm, the term of the expression language and the scan oracle
 (proto_db proto_db/query/terms.py at v2.0.0rc4; the behaviours of tests/unit/test_terms.py that
 apply, mapped in tests/unit/queries_checklist.tsv). A term is (path, op, value): the key its path
 names (PBKeySpec forTermPath:) compared with the value by the operator, with proto_db's D28
 semantics: 1 = 1.0 = Decimal 1, true is not 1, nil is a value, PBMissing matches only '?N', '!='
 is not the complement of '==', range operators stay within the value's type rank, unorderable keys
 match only '?!N', '!=', 'contains', '?T' and '?!T'. Terms are frozen values, equal by order key.
 'near[]' is refused (vector search is out of scope, spec 3.3). The vector
 ../conformance/vectors-index-keys/terms.msgpack (tests/interop/py_term_cases.py, checked against
 the directory's manifest.sha256) holds proto_db's answers on the values of QData values: 160
 seed: 5 for every operator, its outcome for the degenerate terms of the plan's Review Focus 4, and
 the list form and description of each term proto_db compiled. Each check gathers its mismatches
 and requires none, so one label covers one behaviour."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.

"Resolves the vector's references to the atoms of the values drawn here (by oid), and writes them
 back the same way."
Object subclass: #TermAtoms instanceVariableNames: 'atoms'.

TermAtoms class >> on: aValues
  ^ self basicNew setAtoms: aValues.

TermAtoms >> setAtoms: aValues
  atoms := Dictionary new.
  aValues do: [:each | (each isKindOf: PBAtom) ifTrue: [atoms at: each oid hex put: each]].

TermAtoms >> refTo: aSegmentBytes offset: anInteger tag: aTag
  ^ atoms at: aSegmentBytes hex ifAbsent: [Error signal: 'no atom of oid ' , aSegmentBytes hex].

TermAtoms >> refBlock
  ^ [:anAtom | MessagePackMap withAll: { '@ref' -> { anAtom oid. 0. PBTypeRegistry writerTag: anAtom tag } }].

TermAtoms >> bytesOf: aValue
  ^ MessagePack encode: (PBCodec toWire: aValue atomRef: self refBlock).

TermAtoms >> decode: aByteArray
  ^ PBCodec fromWire: (MessagePack decodeOrdered: aByteArray strictKeys: false) resolver: self.

"The MessagePack tree of a description (PBFrozenDict to MessagePackMap), to compare its bytes with
 proto_db's describe() packed by msgpack."
TermAtoms class >> tree: aDescription
  (aDescription isKindOf: PBFrozenDict) ifTrue: [
    ^ MessagePackMap withAll: (aDescription associations collect: [:each | each key -> (self tree: each value)])].
  (aDescription isKindOf: Array) ifTrue: [^ aDescription collect: [:each | self tree: each]].
  ^ aDescription.

| c fails expect refused missing rec absent none one oneF tru five aStr aList all named matching
  t s blob listed data values atoms cases errorClass outcome dec decimal1 r x |
c := Check new.
missing := PBMissing default.
expect := [:label :actual :expected |
  actual = expected ifFalse: [fails add: label , ': expected ' , expected printString , ', got ' , actual printString]].
refused := [:aBlock | [aBlock value. nil] on: Error do: [:e | e return: e class]].
rec := [:pairs | PBObject withAll: pairs].
decimal1 := Decimal fromString: '1'.
absent := rec value: #(). none := rec value: { 'x' -> nil }. one := rec value: { 'x' -> 1 }.
oneF := rec value: { 'x' -> 1.0 }. tru := rec value: { 'x' -> true }. five := rec value: { 'x' -> 5 }.
aStr := rec value: { 'x' -> 'a' }. aList := rec value: { 'x' -> (PBFrozenList withAll: #(1)) }.
all := { absent. none. one. oneF. tru. five. aStr. aList }.
named := Dictionary new.
#('ABSENT' 'NONE' 'ONE' 'ONE_F' 'TRUE' 'FIVE' 'A_STR' 'A_LIST') doWithIndex: [:n :i | named at: (all at: i) put: n].
"The names of the elements of all that aTerm matches, in order (test_terms.py matching)."
matching := [:aTerm | ((all select: [:e | aTerm matches: e]) collect: [:e | named at: e]) asArray].
t := [:path :op :value | PBTerm path: path op: op value: value].

"test_operator_vocabulary_uses_the_0_1_spellings"
fails := OrderedCollection new.
expect value: 'operators' value: PBTerm operators asArray
  value: #('==' '!=' '<' '<=' '>' '>=' 'in' 'between[]' 'between()' 'between(]' 'between[)' '?N' '?!N' 'contains' '?T' '?!T').
expect value: 'unary operators' value: PBTerm unaryOperators asArray value: #('?N' '?!N' '?T' '?!T').
#('==' '!=' '<' '<=' '>' '>=' 'contains') do: [:op |
  expect value: op value: (t value: 'x' value: op value: 1) op value: op].
expect value: 'path:op:' value: (PBTerm path: 'x' op: '?N') value value: nil.
c that: 'the operator vocabulary is proto_db''s' is: fails asArray equals: #().

"near[] is refused (spec 3.3; test_near_* are n/a)"
c that: 'near[] is refused' signals: PBNotSupportedError containing: 'vector' during: [
  PBTerm path: 'v' op: 'near[]' value: #(1.0 0.0)].

"test_term_is_frozen_and_compares_by_value"
fails := OrderedCollection new.
s := t value: 'x' value: '==' value: 1.
expect value: 'equal' value: s = (t value: 'x' value: '==' value: 1) value: true.
expect value: 'equal hashes' value: s hash = (t value: 'x' value: '==' value: 1) hash value: true.
expect value: 'another path' value: s = (t value: 'y' value: '==' value: 1) value: false.
expect value: 'another operator' value: s = (t value: 'x' value: '!=' value: 1) value: false.
expect value: 'keySpecObject' value: s keySpecObject value: (PBKeySpec path: 'x').
expect value: 'keySpecObject of nil' value: (t value: nil value: '==' value: 1) keySpecObject value: PBKeySpec element.
expect value: 'no keySpec' value: (s respondsTo: #keySpec) value: false.
expect value: 'no setter' value: ((#(#path: #op: #value:) select: [:sel | s respondsTo: sel]) asArray) value: #().
expect value: 'initialised once' value: (refused value: [s _setPath: 'y' op: '==' value: 2 keySpecObject: PBKeySpec element valueKey: nil operandKeys: #()]) value: PBUserError.
expect value: 'unchanged' value: { s path. s op. s value } value: #('x' '==' 1).
c that: 'terms are frozen values' is: fails asArray equals: #().

"test_equality_follows_values_semantics, test_missing_never_matches_a_comparison,
 test_not_equal_is_present_and_not_equal, test_is_none_covers_missing_and_none"
fails := OrderedCollection new.
expect value: '== 1' value: (matching value: (t value: 'x' value: '==' value: 1)) value: #('ONE' 'ONE_F').
expect value: '== Decimal 1' value: (matching value: (t value: 'x' value: '==' value: decimal1)) value: #('ONE' 'ONE_F').
expect value: '== true' value: (matching value: (t value: 'x' value: '==' value: true)) value: #('TRUE').
expect value: '== nil' value: (matching value: (t value: 'x' value: '==' value: nil)) value: #('NONE').
{ t value: 'x' value: '!=' value: 1. t value: 'x' value: '<' value: 100. t value: 'x' value: '>=' value: -100.
  t value: 'x' value: 'in' value: { 1. nil }. t value: 'x' value: 'between[]' value: #(-10 10).
  t value: 'x' value: '==' value: nil. t value: 'x' value: '!=' value: nil } do: [:each |
    expect value: 'missing never matches ' , each printString value: (each matches: absent) value: false].
expect value: '!= 1' value: (matching value: (t value: 'x' value: '!=' value: 1)) value: #('NONE' 'TRUE' 'FIVE' 'A_STR' 'A_LIST').
expect value: '!= nil' value: (matching value: (t value: 'x' value: '!=' value: nil)) value: #('ONE' 'ONE_F' 'TRUE' 'FIVE' 'A_STR' 'A_LIST').
expect value: '?N' value: (matching value: (PBTerm path: 'x' op: '?N')) value: #('ABSENT' 'NONE').
expect value: '?!N' value: (matching value: (PBTerm path: 'x' op: '?!N')) value: #('ONE' 'ONE_F' 'TRUE' 'FIVE' 'A_STR' 'A_LIST').
c that: 'equality, missing and nil follow the value semantics' is: fails asArray equals: #().

"test_range_operators_stay_within_the_value_rank, test_between_variants"
fails := OrderedCollection new.
expect value: '< 5' value: (matching value: (t value: 'x' value: '<' value: 5)) value: #('ONE' 'ONE_F').
expect value: '<= 5' value: (matching value: (t value: 'x' value: '<=' value: 5)) value: #('ONE' 'ONE_F' 'FIVE').
expect value: '> 1' value: (matching value: (t value: 'x' value: '>' value: 1)) value: #('FIVE').
expect value: '>= 1' value: (matching value: (t value: 'x' value: '>=' value: 1)) value: #('ONE' 'ONE_F' 'FIVE').
expect value: '> empty' value: (matching value: (t value: 'x' value: '>' value: '')) value: #('A_STR').
expect value: '< nil' value: (matching value: (t value: 'x' value: '<' value: nil)) value: #().
expect value: '<= nil' value: (matching value: (t value: 'x' value: '<=' value: nil)) value: #('NONE').
expect value: '>= false' value: (matching value: (t value: 'x' value: '>=' value: false)) value: #('TRUE').
expect value: 'between[]' value: (matching value: (t value: 'x' value: 'between[]' value: #(1 5))) value: #('ONE' 'ONE_F' 'FIVE').
expect value: 'between()' value: (matching value: (t value: 'x' value: 'between()' value: #(1 5))) value: #().
expect value: 'between(]' value: (matching value: (t value: 'x' value: 'between(]' value: #(1 5))) value: #('FIVE').
expect value: 'between[)' value: (matching value: (t value: 'x' value: 'between[)' value: #(1 5))) value: #('ONE' 'ONE_F').
expect value: 'between a tuple' value: (matching value: (t value: 'x' value: 'between[]' value: (PBTuple withAll: #(0 1)))) value: #('ONE' 'ONE_F').
expect value: 'bounds stored as a tuple' value: (t value: 'x' value: 'between[]' value: #(0 1)) value value: (PBTuple withAll: #(0 1)).
c that: 'range operators stay within the value rank' is: fails asArray equals: #().

"test_in, test_in_over_a_set_is_stored_in_a_canonical_order"
fails := OrderedCollection new.
s := t value: 'x' value: 'in' value: #(5 'a' 9).
expect value: 'operands' value: s value value: (PBTuple withAll: #(5 'a' 9)).
expect value: 'in matches' value: (matching value: s) value: #('FIVE' 'A_STR').
expect value: 'in a Set' value: (matching value: (t value: 'x' value: 'in' value: (Set withAll: #(1)))) value: #('ONE' 'ONE_F').
expect value: 'in nothing' value: (matching value: (t value: 'x' value: 'in' value: #())) value: #().
expect value: 'in a list or a tuple' value: ({ PBFrozenList withAll: #(5). PBTuple withAll: #(5). OrderedCollection with: 5 }
  collect: [:each | matching value: (t value: 'x' value: 'in' value: each)]) value: #(#('FIVE') #('FIVE') #('FIVE')).
s := t value: 'x' value: 'in' value: (Set withAll: { 3. 'b'. 1. 2.5. 'a' }).
expect value: 'a Set sorted by order key' value: s value value: (PBTuple withAll: { 1. 2.5. 3. 'a'. 'b' }).
expect value: 'equal Sets, equal terms' value: s = (t value: 'x' value: 'in' value: (Set withAll: { 'a'. 2.5. 1. 'b'. 3 })) value: true.
expect value: 'equal hashes' value: s hash = (t value: 'x' value: 'in' value: (Set withAll: { 'a'. 2.5. 1. 'b'. 3 })) hash value: true.
expect value: 'a sequence keeps its order' value: (t value: 'x' value: 'in' value: #(3 1)) value value: (PBTuple withAll: #(3 1)).
c that: 'in over sequences and sets' is: fails asArray equals: #().

"test_unorderable_keys_only_match_presence_and_not_equal, test_path_none_is_the_element_itself,
 test_dotted_and_extractor_paths"
fails := OrderedCollection new.
expect value: '?!N on a list' value: ((PBTerm path: 'x' op: '?!N') matches: aList) value: true.
expect value: '!= on a list' value: ((t value: 'x' value: '!=' value: 1) matches: aList) value: true.
{ '==' -> 1. '<' -> 100. '>' -> -1. 'in' -> #(1). 'between[]' -> #(-10 10) } do: [:each |
  expect value: each key , ' on a list' value: ((t value: 'x' value: each key value: each value) matches: aList) value: false].
expect value: 'element 3' value: ((t value: nil value: '==' value: 3) matches: 3) value: true.
expect value: 'element 4' value: ((t value: nil value: '==' value: 3) matches: 4) value: false.
expect value: '?N nil' value: ((PBTerm path: nil op: '?N') matches: nil) value: true.
expect value: '?N missing' value: ((PBTerm path: nil op: '?N') matches: missing) value: true.
r := rec value: { 'a' -> 1 }.
expect value: 'an atom by itself' value: ((t value: nil value: '==' value: r) matches: r) value: true.
expect value: 'an atom by oid' value: ((t value: nil value: '==' value: r) matches: (rec value: { 'a' -> 1 })) value: false.
expect value: 'a dotted path' value: ((t value: 'a.b' value: '==' value: 2) matches: (rec value: { 'a' -> (PBFrozenDict withAssociations: { 'b' -> 2 }) })) value: true.
PBKeySpec registerExtractor: 'tests.terms.double_x' block: [:e |
  x := (PBKeySpec path: 'x') extract: e.
  (x isInteger and: [(x == true or: [x == false]) not]) ifTrue: [x * 2] ifFalse: [missing]] version: nil.
s := t value: '@tests.terms.double_x' value: '==' value: 10.
expect value: 'an extractor path' value: s keySpecObject value: (PBKeySpec extractor: 'tests.terms.double_x').
expect value: 'an extractor matches' value: (matching value: s) value: #('FIVE').
c that: 'unorderable keys, the element itself and paths' is: fails asArray equals: #().

"test_invalid_terms_are_rejected"
fails := OrderedCollection new.
{ { 'x'. 'bogus'. 1 }. { ''. '=='. 1 }. { 'a..b'. '=='. 1 }. { 3. '=='. 1 }. { 'x'. '=='. missing }.
  { 'x'. '=='. #(1) }. { 'x'. '<'. PBFrozenDict withAssociations: { 'a' -> 1 } }. { 'x'. '=='. Float nan }.
  { 'x'. '=='. Object new }. { 'x'. 'in'. 5 }. { 'x'. 'in'. 'abc' }. { 'x'. 'in'. { 1. missing } }.
  { 'x'. 'in'. { #(1) } }. { 'x'. 'between[]'. 5 }. { 'x'. 'between[]'. #(1) }. { 'x'. 'between[]'. #(1 2 3) }.
  { 'x'. 'between[]'. #(1 'z') }. { 'x'. 'between(]'. { missing. 1 } }. { 'x'. '?N'. 1 }. { 'x'. '?!N'. 0 } } do: [:each |
    expect value: each printString value: (refused value: [t value: each first value: (each at: 2) value: each last]) value: PBValidationError].
expect value: 'an operator that is not a String' value: (refused value: [t value: 'x' value: 3 value: 1]) value: PBValidationError.
expect value: 'the unknown-operator message' value: ([t value: 'x' value: 'bogus' value: 1] on: PBValidationError do: [:e | e return: (e messageText copyFrom: 1 to: 25)])
  value: 'Unknown operator ''bogus'';'.
c that: 'invalid terms are refused' is: fails asArray equals: #().

"test_describe, and display values as proto_db's display_value"
fails := OrderedCollection new.
expect value: '== 1' value: (t value: 'x' value: '==' value: 1) describe
  value: (PBFrozenDict withAssociations: { 'path' -> 'x'. 'op' -> '=='. 'value' -> 1 }).
expect value: '?N' value: (PBTerm path: nil op: '?N') describe
  value: (PBFrozenDict withAssociations: { 'path' -> nil. 'op' -> '?N'. 'value' -> nil }).
{ (Decimal fromString: '1.50') -> 'Decimal(''1.50'')'. (ByteArray withAll: #(0 9 92 65 255)) -> 'b''\x00\t\\A\xff'''.
  (ByteArray withAll: #(0 39 92 65 255)) -> 'b"\x00''\\A\xff"'. (ByteArray withAll: #(39 34)) -> 'b''\''"'''. Float infinity -> 'inf'. Float infinity negated -> '-inf'.
  (CalendarDate year: 2026 month: 1 day: 2) -> 'datetime.date(2026, 1, 2)'.
  (TimeSpan days: 0 seconds: 0 microseconds: 0) -> 'datetime.timedelta(0)'.
  (TimeSpan days: 0 seconds: -10800 microseconds: 0) -> 'datetime.timedelta(days=-1, seconds=75600)'.
  (DateTime year: 2026 month: 1 day: 1 hour: 9 minute: 0 second: 0 microsecond: 0 fold: 0 zone: (ZoneOffset microseconds: -10800000000))
    -> 'datetime.datetime(2026, 1, 1, 9, 0, tzinfo=datetime.timezone(datetime.timedelta(days=-1, seconds=75600)))'.
  (DateTime year: 2026 month: 1 day: 1 hour: 9 minute: 0 second: 5 microsecond: 0 fold: 0 zone: ZoneOffset utc)
    -> 'datetime.datetime(2026, 1, 1, 9, 0, 5, tzinfo=datetime.timezone.utc)'.
  (DateTime year: 2026 month: 1 day: 1 hour: 9 minute: 0 second: 0 microsecond: 0 fold: 0 zone: (ZoneOffset microseconds: 7200000000 name: 'CEST'))
    -> 'datetime.datetime(2026, 1, 1, 9, 0, tzinfo=datetime.timezone(datetime.timedelta(seconds=7200), ''CEST''))'.
  (TimeOfDay hour: 12 minute: 30 second: 0 microsecond: 7 fold: 1 zone: nil) -> 'datetime.time(12, 30, 0, 7, fold=1)'.
  (UUID fromString: '12345678-1234-5678-1234-567812345678') -> 'UUID(''12345678-1234-5678-1234-567812345678'')'.
  (PBMutableObject name: 'cell') -> 'MutableObject(''cell'')' } do: [:each |
    expect value: each value value: ((t value: 'x' value: '==' value: each key) describe at: 'value') value: each value].
expect value: 'a tuple operand' value: ((t value: 'x' value: '==' value: (PBTuple withAll: { 1. Decimal fromString: '2' })) describe at: 'value')
  value: { 1. 'Decimal(''2'')' }.
expect value: 'between bounds' value: ((t value: 'x' value: 'between[]' value: #(1 5)) describe at: 'value') value: #(1 5).
expect value: 'a map key' value: (PBTerm displayValue: (PBFrozenDict withAssociations: { 1 -> 'x'. '1' -> 2.5 }))
  value: (PBFrozenDict withAssociations: { '@dict' -> #(#(1 'x') #('1' 2.5)) }).
expect value: 'NaN and missing' value: { PBTerm displayValue: Float nan. PBTerm displayValue: missing } value: #('nan' 'MISSING').
"Values a term cannot hold as an operand (not orderable) but explain may show (index keys)."
{ (TimeOfDay hour: 12 minute: 30 second: 0 microsecond: 7 fold: 1 zone: (ZoneName key: 'Europe/Rome'))
    -> 'datetime.time(12, 30, 0, 7, tzinfo=zoneinfo.ZoneInfo(key=''Europe/Rome''), fold=1)'.
  (TimeOfDay hour: 1 minute: 2 second: 0 microsecond: 0 fold: 1 zone: ZoneOffset utc)
    -> 'datetime.time(1, 2, tzinfo=datetime.timezone.utc, fold=1)'.
  (DateTime year: 2026 month: 1 day: 1 hour: 1 minute: 2 second: 0 microsecond: 0 fold: 1 zone: ZoneOffset utc)
    -> 'datetime.datetime(2026, 1, 1, 1, 2, fold=1, tzinfo=datetime.timezone.utc)'.
  (PBLegacyZoneDateTime wallClockFields: #(2026 1 1 1 2 0 0) fold: 1 zoneName: (ZoneName key: 'Europe/Rome'))
    -> 'datetime.datetime(2026, 1, 1, 1, 2, fold=1, tzinfo=zoneinfo.ZoneInfo(key=''Europe/Rome''))'.
  (Decimal fromString: 'Infinity') -> 'Decimal(''Infinity'')'. (Decimal fromString: '-Infinity') -> 'Decimal(''-Infinity'')'.
  (Decimal fromString: 'NaN') -> 'Decimal(''NaN'')'. (Decimal fromString: '-NaN') -> 'Decimal(''-NaN'')'.
  (Decimal fromString: 'sNaN') -> 'Decimal(''sNaN'')' } do: [:each |
    expect value: each value value: (PBTerm displayValue: each key) value: each value].
c that: 'describe and display values' is: fails asArray equals: #().

"=== the vector: proto_db's answers on QData values: 160 seed: 5 ==="
blob := '../conformance/vectors-index-keys/terms.msgpack' asFileReference binaryContents.
listed := ('../conformance/vectors-index-keys/manifest.sha256' asFileReference contents lines)
  detect: [:line | line endsWith: '  terms.msgpack'] ifNone: [''].
(listed copyFrom: 1 to: (64 min: listed size)) = blob sha256 hex asLowercase ifFalse: [
  Error signal: 'vectors-index-keys/terms.msgpack does not match manifest.sha256'].
data := MessagePack decode: blob.
values := QData pinOids: (QData values: (data at: 'count') seed: (data at: 'seed')).
atoms := TermAtoms on: values.
(data at: 'values') size = values size ifFalse: [Error signal: 'the vector holds another count of values'].
(data at: 'values') doWithIndex: [:bytes :i |
  (PBKeys exactToken: (atoms decode: bytes)) = (PBKeys exactToken: (values at: i)) ifFalse: [
    Error signal: 'QData values: no longer draws the values of the vector (value ' , i printString , ')']].
cases := data at: 'cases'.
errorClass := [:name |
  name isNil ifTrue: [nil] ifFalse: [
    name = 'ProtoValidationError' ifTrue: [PBValidationError] ifFalse: [
      name = 'ProtoNotSupportedError' ifTrue: [PBNotSupportedError] ifFalse: [Error signal: 'unknown class ' , name]]]].
"For each case: (the error class of compile:, nil) or (nil, the expression)."
outcome := [:case | | tokens |
  tokens := atoms decode: (case at: 'tokens').
  [nil -> (PBExpression compile: tokens)] on: PBDBError do: [:e | e return: e class -> nil]].
dec := cases collect: [:case | outcome value: case].

"matches: equals proto_db's answers on QData values for every operator"
fails := OrderedCollection new.
cases doWithIndex: [:case :i |
  | expr got want |
  expr := (dec at: i) value.
  want := case at: 'answers'.
  (want notNil and: [expr notNil]) ifTrue: [
    got := [values collect: [:v | expr evaluate: v]] on: PBDBError do: [:e | e return: e class].
    got = want asArray ifFalse: [
      fails add: (case at: 'id') , ': ' , ((1 to: values size) detect: [:k | ((got isKindOf: Array) and: [(got at: k) = (want at: k)]) not] ifNone: [0]) printString]]].
"Value domain of the vector (Task 6 extends the generator and these counts): QData values: draws
 no naive datetime, time, timedelta, UUID, empty String or ByteArray, and no collection atom; those
 are covered by the unit checks above and in qry_expressions.st only."
expect value: 'cases with answers' value: (cases select: [:case | (case at: 'answers') notNil]) size value: 176.
c that: 'matches: on QData values equals proto_db''s answers for every operator' is: fails asArray equals: #().

"degenerate terms as proto_db (Review Focus 4): the same result or the same error class"
fails := OrderedCollection new.
cases doWithIndex: [:case :i |
  | got want id expr |
  id := case at: 'id'.
  got := (dec at: i) key.
  expr := (dec at: i) value.
  want := errorClass value: (case at: 'error').
  "near[] is refused when the term is made (spec 3.3); proto_db refuses it when it is evaluated"
  ((id includesSubstring: 'near[]') and: [(case at: 'match_error') = 'ProtoNotSupportedError']) ifTrue: [want := PBNotSupportedError].
  got = want ifFalse: [fails add: id , ': compile: signals ' , got printString , ', proto_db ' , want printString].
  (expr notNil and: [(case at: 'match_error') notNil]) ifTrue: [
    got := [values do: [:v | expr evaluate: v]. nil] on: PBDBError do: [:e | e return: e class].
    got = (errorClass value: (case at: 'match_error')) ifFalse: [
      fails add: id , ': evaluate: signals ' , got printString , ', proto_db ' , (case at: 'match_error')]]].
"A count of the vector: Task 6 updates it with the generator (value-domain note above)."
expect value: 'degenerate cases' value: (cases select: [:case | (case at: 'id') includesSubstring: '(degenerate)']) size value: 12.
s := t value: nil value: 'in' value: { 1. 1.0. decimal1. true. 's1'. nil. 1 }.
expect value: 'in keeps duplicates and mixed types' value: s value size value: 7.
s := t value: nil value: 'in' value: (-500 to: 499) asArray.
expect value: 'a 1000-value in' value: ({ -500. 499. 500. 0.5 } collect: [:v | s matches: v]) value: #(true true false false).
c that: 'degenerate terms as proto_db' is: fails asArray equals: #().

"compile: of every recorded list: asList is proto_db's to_list, describe proto_db's describe()"
fails := OrderedCollection new.
cases doWithIndex: [:case :i |
  | expr |
  expr := (dec at: i) value.
  (expr notNil and: [(case at: 'to_list') notNil]) ifTrue: [
    (atoms bytesOf: expr asList) = (case at: 'to_list') ifFalse: [
      fails add: (case at: 'id') , ': asList ' , expr asList printString].
    ((case at: 'id') endsWith: ' atom')
      ifTrue: [ | theirs |
        "An atom operand is displayed as <type name oid=...>, where proto_db prints the record
         (docs/deviations.md): the rest of the description is the same."
        theirs := MessagePack decode: (case at: 'describe').
        ((((theirs at: 'path') = (expr describe at: 'path') and: [(theirs at: 'op') = (expr describe at: 'op')])
            and: [(theirs at: 'value') = 'DBObject(r=1)'])
            and: [(expr describe at: 'value') = '<proto_db.core.dbobject.DBObject oid=00000000-0000-0000-0000-000000000001>']) ifFalse: [
          fails add: (case at: 'id') , ': describe ' , expr describe printString]]
      ifFalse: [
        (MessagePack encode: (TermAtoms tree: expr describe)) = (case at: 'describe') ifFalse: [
          fails add: (case at: 'id') , ': describe ' , expr describe printString]]]].
"A count of the vector: Task 6 updates it with the generator (value-domain note above)."
expect value: 'compiled cases' value: (dec select: [:each | each value notNil]) size value: 177.
c that: 'compile: of every recorded list gives proto_db''s list and description' is: fails asArray equals: #().

c report displayNl.
