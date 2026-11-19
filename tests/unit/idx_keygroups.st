"EXPECT: ok 16"
"Indexed queries, plan Task 3: the key-group indexes as structures (proto_db
 proto_db/indexing/base.py and keyed.py at v2.0.0rc4; the structure-level behaviours of
 tests/unit/test_index_base.py, test_equality_index.py, test_range_index.py and
 test_index_key_neutrality.py, mapped in tests/unit/queries_checklist.tsv). Every hook answers a
 new index and leaves its receiver unchanged; elements are counted (a multiset); removing an
 element the index does not hold is PBValidationError, as proto_db decides; unorderable keys go
 to the side group; 1, 1.0 and Decimal 1 share one key group and stay three members (Review
 Focus 2); empty keeps the definition; build: equals the fold of withAdded: node for node, and the
 stored bytes do not depend on how a value was built; explain keeps proto_db's keys and kind
 names (plan call CR4); validate: passes on built indexes and tells corruption from misfiling; a
 vector index and an index of an unknown kind refuse every hook (spec 3.3); keySpec stays the
 tuple and keySpecObject answers the PBKeySpec (plan call IP3); the depth refusal is proto_db's
 sentence word for word; index sets apply the hooks to every index. Each check gathers its
 mismatches and requires none, so one label covers one behaviour."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.

Decimal subclass: #Price.

"An index kind that implements no hook (test_index_requires_every_abstract_hook)."
PBIndex subclass: #HooklessIndex.
HooklessIndex class >> typeName
  ^ 'tests.idx_keygroups.HooklessIndex'.
CalendarDate subclass: #Holiday.

| c fails expect refused refusedText missing rec rec2 oslo rome idx idx2 built folded elements people
  values members before after hooks result group misfiled info spec deep text vector opaque set set2
  stale x plain by n cases build fold kinds paris byValue byCity rest ages |
c := Check new.
missing := PBMissing default.
"Adds a mismatch to fails unless actual = expected (identity for PBMissing)."
expect := [:label :actual :expected |
  (expected == missing ifTrue: [actual == missing] ifFalse: [actual = expected])
    ifFalse: [fails add: label , ': expected ' , expected printString , ', got ' , actual printString]].
"The class of the error aBlock signals, or nil."
refused := [:aBlock | [aBlock value. nil] on: Error do: [:e | e return: e class]].
refusedText := [:aBlock | [aBlock value. nil] on: Error do: [:e | e return: e messageText]].
"The { element. count } pairs of an index, in membersDo: order."
members := [:index | | out | out := OrderedCollection new. index membersDo: [:e :k | out add: { e. k }]. out asArray].
people := QData people: 60 seed: 20261118.
values := QData values: 200 seed: 20261118.
kinds := { PBEqualityIndex. PBRangeIndex }.
PBKeySpec registerExtractor: 'tests.idx_keygroups.city' block: [:e | (PBKeySpec path: 'city') extract: e] version: nil.

"test_definition_type_name_and_str_key, test_range_index test_definition_and_type_name,
 test_definition_is_validated, test_index_requires_every_abstract_hook, test_abstract_base_type_name,
 test_with_rejects_unknown_fields; name:path: is name:keySpec: (PBKeySpec path:) (plan call CR3)."
fails := OrderedCollection new.
kinds do: [:k |
  idx := k name: 'by_city' path: 'city'.
  expect value: k name , ' name:path:' value: (QData dump: idx) value: (QData dump: (k name: 'by_city' keySpec: (PBKeySpec path: 'city'))).
  expect value: k name , ' fields' value: idx state keys value: k persistedFields.
  expect value: k name , ' empty state' value: { idx groups. idx side. idx totalCount. idx stateAt: 'member_tokens' }
    value: { nil. PBTuple withAll: { nil. 0 }. 0. 1 }.
  expect value: k name , ' unsaved' value: idx isSaved value: false.
  expect value: k name , ' element' value: (k name: 'e' keySpec: PBKeySpec element) keySpecObject value: PBKeySpec element.
  { 'city'. 3. nil } do: [:bad |
    expect value: k name , ' keySpec: ' , bad printString value: (refused value: [k name: 'i' keySpec: bad]) value: PBValidationError].
  { ''. nil. 3. #foobarbaz. 'a' , (String with: (Character value: 16rD800)) } do: [:bad |
    expect value: k name , ' name ' , bad printString value: (refused value: [k name: bad keySpec: PBKeySpec element]) value: PBValidationError]].
expect value: 'the String key spec message' value: (refusedText value: [PBEqualityIndex name: 'bad' keySpec: 'city'])
  value: 'key_spec must be a PBKeySpec, not a String'.
expect value: 'type names' value: (kinds collect: [:k | k typeName]) value: #('proto_db.indexing.EqualityIndex' 'proto_db.indexing.RangeIndex').
expect value: 'the base type name' value: PBIndex typeName value: 'proto_db.indexing.Index'.
expect value: 'abstract Index' value: (refused value: [PBIndex name: 'i' keySpec: PBKeySpec element]) value: PBUserError.
expect value: 'abstract KeyGroupIndex' value: (refused value: [PBKeyGroupIndex name: 'i' keySpec: PBKeySpec element]) value: PBUserError.
idx := HooklessIndex name: 'h' keySpec: PBKeySpec element.
{ [idx withAdded: 1]. [idx withRemoved: 1]. [idx withReplaced: 1 with: 2]. [idx build: #(1)]. [idx validate: #()] } doWithIndex: [:hook :i |
  expect value: 'a missing hook ' , i printString value: (refused value: hook) value: PBUserError].
expect value: 'a hookless index explains' value: idx explain
  value: (PBFrozenDict withAssociations: { 'index' -> 'h'. 'kind' -> 'HooklessIndex'. 'key' -> '<element>' }).
expect value: 'unknown _with: field' value: (refused value: [(PBEqualityIndex name: 'i' path: 'a') _with: { 'bogus' -> 1 }]) value: PBValidationError.
c that: 'the definition is validated; name:path: is name:keySpec:' is: fails asArray equals: #().

"IP3: keySpec answers the persisted tuple, keySpecObject an equal PBKeySpec; a malformed tuple is
 PBValidationError naming the index, when asked."
fails := OrderedCollection new.
{ PBKeySpec path: 'address.zip'. PBKeySpec element. PBKeySpec extractor: 'tests.idx_keygroups.city' } do: [:s |
  idx := PBRangeIndex name: 'p' keySpec: s.
  expect value: s printString , ' keySpec' value: idx keySpec value: s asData.
  expect value: s printString , ' keySpec class' value: idx keySpec class value: PBTuple.
  expect value: s printString , ' keySpecObject' value: idx keySpecObject value: s.
  expect value: s printString , ' after a hook' value: (idx withAdded: 5) keySpecObject value: s].
idx := (PBEqualityIndex name: 'broken' path: 'a') _with: { 'key_spec' -> (PBTuple withAll: #('nope' 1)) }.
expect value: 'a malformed tuple reads' value: idx keySpec value: (PBTuple withAll: #('nope' 1)).
expect value: 'keySpecObject of a malformed tuple' value: (refused value: [idx keySpecObject]) value: PBValidationError.
expect value: 'it names the index' value: ((refusedText value: [idx keySpecObject]) includesSubstring: '''broken''') value: true.
c that: 'keySpec answers the tuple, keySpecObject a PBKeySpec' is: fails asArray equals: #().

"Hooks answer new versions and leave the receiver unchanged (index_contract.py check (g), at
 structure level)."
fails := OrderedCollection new.
kinds do: [:k |
  idx := k name: 'by_age' path: 'age'.
  idx := idx build: people.
  before := { QData dump: idx. idx explain }.
  hooks := {
    'withAdded:' -> [idx withAdded: people first].
    'withRemoved:' -> [idx withRemoved: people last].
    'withReplaced:with:' -> [idx withReplaced: people last with: people first].
    'build:' -> [idx build: { people first }].
    'empty' -> [idx empty] }.
  hooks do: [:hook |
    result := hook value value.
    expect value: k name , ' ' , hook key , ' receiver' value: { QData dump: idx. idx explain } value: before.
    expect value: k name , ' ' , hook key , ' class' value: result class value: k.
    expect value: k name , ' ' , hook key , ' definition' value: { result name. result keySpec } value: { idx name. idx keySpec }.
    expect value: k name , ' ' , hook key , ' new' value: result == idx value: false]].
c that: 'hooks answer new versions and leave the receiver unchanged' is: fails asArray equals: #().

"test_duplicates_are_counted"
fails := OrderedCollection new.
x := PBObject withAll: { 'city' -> 'Oslo' }.
idx := (PBEqualityIndex name: 'by_city' path: 'city') build: { x. x. PBObject withAll: { 'city' -> 'Oslo' } }.
expect value: 'three Oslo' value: (idx countOfKey: 'Oslo') value: 3.
expect value: 'x twice' value: ((members value: idx) detect: [:p | p first == x]) last value: 2.
idx2 := idx withRemoved: x.
expect value: 'x once' value: ((members value: idx2) detect: [:p | p first == x]) last value: 1.
expect value: 'two Oslo' value: (idx2 countOfKey: 'Oslo') value: 2.
expect value: 'x gone' value: (((members value: (idx2 withRemoved: x)) select: [:p | p first == x]) size) value: 0.
expect value: 'count' value: { idx count. idx2 count } value: #(3 2).
plain := (PBEqualityIndex name: 'v' keySpec: PBKeySpec element) build: { 3. 3. 3.0. true }.
expect value: 'three 3' value: (plain countOfKey: 3) value: 3.
expect value: 'two groups' value: plain groupCount value: 2.
expect value: 'without 3.0' value: ((plain withRemoved: 3.0) countOfKey: 3) value: 2.
expect value: '3.0 is its own member' value: ((members value: plain) collect: [:p | p last]) value: #(1 2 1).
c that: 'duplicates are counted in a multiset' is: fails asArray equals: #().

"test_removing_an_absent_element_raises: proto_db refuses (ProtoValidationError), it never takes
 an equal member instead."
fails := OrderedCollection new.
idx := (PBEqualityIndex name: 'by_city' path: 'city') build: { PBObject withAll: { 'city' -> 'Oslo' } }.
expect value: 'same key, another element' value: (refused value: [idx withRemoved: (PBObject withAll: { 'city' -> 'Oslo' })]) value: PBValidationError.
expect value: 'another key' value: (refused value: [idx withRemoved: (PBObject withAll: { 'city' -> 'Rome' })]) value: PBValidationError.
expect value: 'an unorderable element' value: (refused value: [(PBEqualityIndex name: 'v' keySpec: PBKeySpec element) withRemoved: (PBFrozenList withAll: #(1))]) value: PBValidationError.
expect value: 'an equal value with another token' value: (refused value: [((PBEqualityIndex name: 'v' keySpec: PBKeySpec element) withAdded: 1) withRemoved: 1.0]) value: PBValidationError.
text := refusedText value: [idx withRemoved: (PBObject withAll: { 'city' -> 'Rome' })].
expect value: 'the message' value: ((text beginsWith: 'Index ''by_city'' (EqualityIndex on city) does not hold ')
  and: [text endsWith: '; an index can only remove an element it holds']) value: true.
c that: 'removing an absent element is refused as proto_db decides' is: fails asArray equals: #().

"test_unorderable_keys_and_elements"
fails := OrderedCollection new.
paris := PBFrozenDict withAssociations: { 'city' -> 'Paris' }.
elements := { PBFrozenList withAll: #(1). PBFrozenList withAll: #(1). PBFrozenDict withAssociations: { 'a' -> 1 }. Float nan.
  PBTuple withAll: { PBFrozenList withAll: #(2). 1 }. paris. PBFrozenDict withAssociations: { 'city' -> 'Paris'. 'n' -> 2 }. 4 }.
byValue := (PBEqualityIndex name: 'v' keySpec: PBKeySpec element) build: elements.
byCity := (PBEqualityIndex name: 'c' path: 'city') build: elements.
expect value: 'by value: side' value: (byValue explain at: 'unorderable') value: 7.
expect value: 'by value: one key' value: byValue groupCount value: 1.
"The order and counts proto_db's build gives for these elements (computed with proto_db at the
 tag): the key group of 4, then the side group in member order, the two equal lists one member."
expect value: 'by value: proto_db''s member order' value: ((members value: byValue) collect: [:p |
    (1 to: elements size) detect: [:i | (elements at: i) == p first] ifNone: [0]])
  value: #(8 3 6 7 1 4 5).
expect value: 'by value: the two equal lists are one member' value: ((members value: byValue) collect: [:p | p last]) value: #(1 1 1 1 2 1 1).
expect value: 'by city: Paris' value: (byCity countOfKey: 'Paris') value: 2.
expect value: 'by city: missing' value: (byCity countOfKey: missing) value: 6.
expect value: 'by city: no side' value: (byCity explain at: 'unorderable') value: 0.
expect value: 'validate by value' value: (refused value: [byValue validate: elements]) value: nil.
expect value: 'validate by city' value: (refused value: [byCity validate: elements]) value: nil.
rest := { PBFrozenList withAll: #(1). PBFrozenDict withAssociations: { 'a' -> 1 }. PBTuple withAll: { PBFrozenList withAll: #(2). 1 }.
  paris. PBFrozenDict withAssociations: { 'city' -> 'Paris'. 'n' -> 2 }. 4 }.
expect value: 'after removals' value: (refused value: [((byValue withRemoved: (PBFrozenList withAll: #(1))) withRemoved: Float nan) validate: rest]) value: nil.
expect value: 'countOfKey: of an unorderable key' value: (refused value: [byValue countOfKey: (PBFrozenList withAll: #(1))]) value: PBValidationError.
c that: 'unorderable keys go to the side group' is: fails asArray equals: #().

"Review Focus 2: 1, 1.0, Decimal 1 and Decimal 1.00 are one key and four members, nil, PBMissing
 and true are three other keys, a map and a list holding a map are unorderable."
fails := OrderedCollection new.
cases := { 1. 1.0. Decimal fromString: '1'. Decimal fromString: '1.00'. nil. missing. true.
  PBFrozenDict withAssociations: { 'a' -> 1 }. PBFrozenList withAll: { PBFrozenDict withAssociations: { 'b' -> 2 } } }.
elements := cases collect: [:v | v == missing ifTrue: [PBObject withAll: { 'other' -> 0 }] ifFalse: [PBObject withAll: { 'v' -> v }]].
kinds do: [:k |
  idx := (k name: 'by_v' path: 'v') build: elements.
  { 1. 1.0. Decimal fromString: '1'. Decimal fromString: '1.00' } do: [:one |
    expect value: k name , ' one key ' , one printString value: (idx countOfKey: one) value: 4].
  expect value: k name , ' nil' value: (idx countOfKey: nil) value: 1.
  expect value: k name , ' missing' value: (idx countOfKey: missing) value: 1.
  expect value: k name , ' true' value: (idx countOfKey: true) value: 1.
  expect value: k name , ' keys' value: idx groupCount value: 4.
  expect value: k name , ' unorderable' value: (idx explain at: 'unorderable') value: 2.
  "Key order: PBMissing, nil, true, the numbers, then the side group; records order by oid in a
   group."
  n := (members value: idx) collect: [:p | elements indexOf: p first].
  expect value: k name , ' key order' value: { n copyFrom: 1 to: 3. (n copyFrom: 4 to: 7) asSet. (n copyFrom: 8 to: 9) asSet }
    value: { #(6 5 7). #(1 2 3 4) asSet. #(8 9) asSet }.
  expect value: k name , ' validate' value: (refused value: [idx validate: elements]) value: nil.
  idx2 := idx withRemoved: (elements at: 2).
  expect value: k name , ' without the 1.0' value: (idx2 countOfKey: 1) value: 3.
  expect value: k name , ' validate after' value: (refused value: [idx2 validate: (elements copyWithout: (elements at: 2))]) value: nil].
"test_element_identity: PBMemberKeys identityOf: is proto_db's element_identity."
rec := PBObject withAll: { 'a' -> 1 }.
{ { 1. 1.0. true }. { 1. Decimal fromString: '1.00'. true }. { rec. rec. PBObject withAll: { 'a' -> 1 } }.
  { PBFrozenList withAll: { 1. PBTuple withAll: { 2.0. 'x' } }. PBFrozenList withAll: { 1.0. PBTuple withAll: { 2. 'x' } }. PBTuple withAll: { 1. PBTuple withAll: { 2.0. 'x' } } }.
  { PBFrozenList withAll: #(1). PBFrozenList withAll: #(1.0). PBTuple withAll: #(1) }.
  { PBFrozenDict withAssociations: { 'a' -> (PBFrozenList withAll: #(1)) }. PBFrozenDict withAssociations: { 'a' -> (PBFrozenList withAll: #(1.0)) }. PBFrozenDict withAssociations: { 'a' -> 1 } }.
  { Float nan. Float nan. nil }. { missing. missing. nil } } do: [:t |
  expect value: 'identity ' , t printString
    value: { (PBMemberKeys identityOf: (t at: 1)) = (PBMemberKeys identityOf: (t at: 2)). (PBMemberKeys identityOf: (t at: 1)) = (PBMemberKeys identityOf: (t at: 3)) }
    value: { true. false }].
c that: 'mixed numeric and unorderable keys' is: fails asArray equals: #().

"test_empty_keeps_the_whole_definition, test_build_starts_from_empty_and_folds_with_added,
 test_build_accepts_any_iterable"
fails := OrderedCollection new.
kinds do: [:k |
  idx := (k name: 'by_city' path: 'city') withAdded: (PBObject withAll: { 'city' -> 'Rome' }).
  idx2 := idx empty.
  expect value: k name , ' empty definition' value: { idx2 class. idx2 name. idx2 keySpecObject } value: { k. 'by_city'. PBKeySpec path: 'city' }.
  expect value: k name , ' empty content' value: { idx2 count. idx2 groupCount. idx count } value: #(0 0 1).
  expect value: k name , ' empty is a fresh empty index' value: (QData dump: idx2) value: (QData dump: (k name: 'by_city' path: 'city')).
  oslo := { PBObject withAll: { 'city' -> 'Oslo' }. PBObject withAll: { 'city' -> 'Oslo' }. PBObject new }.
  built := idx build: oslo.
  expect value: k name , ' the receiver''s content is not kept' value: (built countOfKey: 'Rome') value: 0.
  expect value: k name , ' Oslo' value: (built countOfKey: 'Oslo') value: 2.
  expect value: k name , ' missing' value: (built countOfKey: missing) value: 1.
  expect value: k name , ' receiver unchanged' value: (idx countOfKey: 'Rome') value: 1.
  expect value: k name , ' validate' value: (refused value: [built validate: oslo]) value: nil.
  expect value: k name , ' any collection' value: (QData dump: (idx build: (OrderedCollection withAll: oslo)))
    value: (QData dump: built).
  expect value: k name , ' a PBList' value: (QData dump: (idx build: ((PBList new appendLast: 'a') appendLast: 'b')))
    value: (QData dump: (idx build: #('a' 'b')))].
c that: 'empty keeps the definition; build: ignores the receiver' is: fails asArray equals: #().

"test_build_equals_fold_and_ignores_the_receiver, test_range_index test_build_equals_fold: the bulk
 build (keyed.py build: sorted entries, balanced trees by keyFromSortedOrderKeys:, plan call IP13)
 holds, node for node in key order, the keys, groups, member keys, elements and counts of the fold
 of withAdded:, in trees of the same node class; only the shapes differ (balanced, against AVL
 insertion order), as in proto_db, whose test compares the answers. Built and folded both pass
 validate: and PBAvl check:."
fails := OrderedCollection new.
fold := [:index :all | | out | out := index. all do: [:e | out := out withAdded: e]. out].
kinds do: [:k |
  { { PBKeySpec path: 'city'. people , people , people }. { PBKeySpec path: 'age'. people }.
    { PBKeySpec element. values }. { PBKeySpec element. values , values }. { PBKeySpec path: 'v'. #() } } do: [:sc |
    idx := k name: 'b' keySpec: sc first.
    built := idx build: sc last.
    folded := fold value: idx value: sc last.
    expect value: k name , ' ' , sc first printString , ' ' , sc last size printString
      value: (QData contents: built) value: (QData contents: folded).
    expect value: k name , ' total' value: built count value: sc last size.
    expect value: k name , ' validate' value: (refused value: [built validate: sc last. folded validate: sc last. PBAvl check: built groups]) value: nil.
    expect value: k name , ' build: of nothing' value: (QData dump: (built build: #())) value: (QData dump: idx)]].
c that: 'build: holds the fold of withAdded: node for node in key order' is: fails asArray equals: #().

"test_index_key_neutrality: the stored bytes of an index (every node, the index atom) do not
 depend on how a value was built: a value as the program built it and the same value as a load
 decodes it (a ZoneOffset named UTC and ZoneOffset utc, an offset with and without a name, a
 Decimal subclass, a CalendarDate subclass, the same inside a tuple), for an element index, a
 field index and an extractor index. Atoms are written as one placeholder (the records differ by
 oid only, as proto_db's test strips oids)."
fails := OrderedCollection new.
cases := {
  'utc-named' -> { DateTime year: 2026 month: 1 day: 1 hour: 0 minute: 0 second: 0 microsecond: 0 fold: 0 zone: (ZoneOffset microseconds: 0 name: 'UTC').
    DateTime year: 2026 month: 1 day: 1 hour: 0 minute: 0 second: 0 microsecond: 0 fold: 0 zone: ZoneOffset utc }.
  'offset-default-name' -> { DateTime year: 2026 month: 1 day: 1 hour: 0 minute: 0 second: 0 microsecond: 0 fold: 0 zone: (ZoneOffset microseconds: 3600000000 name: 'UTC+01:00').
    DateTime year: 2026 month: 1 day: 1 hour: 0 minute: 0 second: 0 microsecond: 0 fold: 0 zone: (ZoneOffset microseconds: 3600000000) }.
  'decimal-subclass' -> { Price sign: 0 coefficient: 1999 exponent: -2. Decimal fromString: '19.99' }.
  'date-subclass' -> { Holiday year: 2026 month: 12 day: 25. CalendarDate year: 2026 month: 12 day: 25 }.
  'in-a-tuple' -> { PBTuple withAll: { Price sign: 0 coefficient: 3 exponent: 0. Holiday year: 2026 month: 1 day: 2 }.
    PBTuple withAll: { Decimal fromString: '3'. CalendarDate year: 2026 month: 1 day: 2 } } }.
by := [:spec :element | QData strippedDump: (((PBEqualityIndex name: 'ix' keySpec: spec) withAdded: element) withAdded: element)].
cases do: [:case |
  | made plain cell |
  made := case value first.
  plain := case value last.
  expect value: case key , ' element' value: (by value: PBKeySpec element value: made) value: (by value: PBKeySpec element value: plain).
  expect value: case key , ' range element' value: (QData strippedDump: ((PBRangeIndex name: 'ix' keySpec: PBKeySpec element) build: { made }))
    value: (QData strippedDump: ((PBRangeIndex name: 'ix' keySpec: PBKeySpec element) build: { plain })).
  expect value: case key , ' field' value: (by value: (PBKeySpec path: 'k') value: (PBObject withAll: { 'k' -> made. 'n' -> 1 }))
    value: (by value: (PBKeySpec path: 'k') value: (PBObject withAll: { 'k' -> plain. 'n' -> 1 })).
  cell := Atom on: made.
  PBKeySpec registerExtractor: 'tests.idx_keygroups.' , case key block: [:e | cell value] version: nil.
  text := by value: (PBKeySpec extractor: 'tests.idx_keygroups.' , case key) value: (PBObject withAll: { 'n' -> 1 }).
  cell value: plain ifCurrent: made.
  expect value: case key , ' extractor' value: text
    value: (by value: (PBKeySpec extractor: 'tests.idx_keygroups.' , case key) value: (PBObject withAll: { 'n' -> 1 })).
  PBKeySpec unregisterExtractor: 'tests.idx_keygroups.' , case key].
c that: 'the stored bytes do not depend on how a value was built' is: fails asArray equals: #().

"test_explain_default, test_explain_reports_the_structure: kind is proto_db's class name (plan call
 CR4)."
fails := OrderedCollection new.
kinds with: #('EqualityIndex' 'RangeIndex') do: [:k :kind |
  idx := (k name: 'by_city' path: 'city') build: people.
  info := idx explain.
  expect value: kind , ' class' value: info class value: PBFrozenDict.
  expect value: kind , ' keys' value: info keys value: #('index' 'kind' 'key' 'entries' 'keys' 'unorderable').
  expect value: kind , ' values' value: info
    value: (PBFrozenDict withAssociations: { 'index' -> 'by_city'. 'kind' -> kind. 'key' -> 'city'.
      'entries' -> 60. 'keys' -> idx groupCount. 'unorderable' -> 0 }).
  expect value: kind , ' keys >= 5' value: (info at: 'keys') >= 5 value: true.
  expect value: kind , ' element key' value: ((k name: 'e' keySpec: PBKeySpec element) explain at: 'key') value: '<element>'.
  expect value: kind , ' extractor key' value: ((k name: 'x' keySpec: (PBKeySpec extractor: 'tests.idx_keygroups.city')) explain at: 'key')
    value: '@tests.idx_keygroups.city'.
  expect value: kind , ' unorderable' value: (((k name: 'e' keySpec: PBKeySpec element) build: values) explain at: 'unorderable')
    value: (values select: [:v | (PBKeys isOrderable: v) not]) size].
c that: 'explain keys and values' is: fails asArray equals: #().

"test_validate_detects_stale_and_miscounted_entries, test_range_index
 test_validate_detects_corruption, test_validate_detects_an_inconsistent_index,
 test_validate_covers_missing_keys_and_stale_keys, test_validate_skips_unorderable_keys"
fails := OrderedCollection new.
kinds do: [:k |
  idx := (k name: 'by_city' path: 'city') build: people.
  expect value: k name , ' passes' value: (idx validate: people) == idx value: true.
  expect value: k name , ' an entry no element has' value: (refused value: [idx validate: (people copyFrom: 1 to: people size - 1)]) value: PBCorruptionError.
  expect value: k name , ' a count too low' value: (refused value: [idx validate: people , { people first }]) value: PBCorruptionError.
  expect value: k name , ' total_count' value: (refused value: [(idx _with: { 'total_count' -> (idx totalCount + 1) }) validate: people]) value: PBCorruptionError.
  expect value: k name , ' it names the index' value: ((refusedText value: [idx validate: (people copyFrom: 1 to: people size - 1)]) beginsWith: 'Index ''by_city'' (' , k kindName , ' on city) is corrupt: ') value: true.
  expect value: k name , ' elements it never saw' value: (refused value: [(k name: 'by_city' path: 'city') validate: { PBObject withAll: { 'city' -> 'Rome' } }]) value: PBCorruptionError.
  expect value: k name , ' a missing key' value: (refused value: [((k name: 'by_city' path: 'city') withAdded: PBObject new) validate: #()]) value: PBCorruptionError.
  rome := PBObject withAll: { 'city' -> 'Gone' }.
  expect value: k name , ' a stale key' value: (refused value: [((k name: 'by_city' path: 'city') build: { rome }) validate: #()]) value: PBCorruptionError.
  rec := PBObject withAll: { 'city' -> (PBFrozenList withAll: #(1 2)) }.
  expect value: k name , ' an unorderable key validates' value: (refused value: [((k name: 'by_city' path: 'city') withAdded: rec) validate: { rec }]) value: nil.
  "A broken tree: two node classes in one tree."
  rome := PBObject withAll: { 'city' -> 'Rome' }.
  idx2 := (k name: 'by_city' path: 'city') build: { rome }.
  group := (PBAvl keyAt: idx2 groups key: 'Rome') value.
  expect value: k name , ' a broken tree' value: (refused value: [(idx2 _with: { 'groups' ->
      (PBKeyNode key: 'Rome' value: group left: nil right: (PBCountedKeyNode key: 'Zz' value: group left: nil right: nil)) }) validate: { rome }])
    value: PBCorruptionError.
  "A miscounted member."
  misfiled := (PBAvl keyPut: idx2 groups key: 'Rome' value: (PBTuple withAll: { group at: 1. 2 }) nodeClass: PBCountedKeyNode) first.
  expect value: k name , ' a group total' value: (refused value: [(idx2 _with: { 'groups' -> misfiled }) validate: { rome }]) value: PBCorruptionError].
c that: 'validate: passes on built indexes and detects corruption' is: fails asArray equals: #().

"A hand-misfiled member is PBMisfiledError (keyed.py _misfiled), a PBCorruptionError: a group
 under another key than its elements', and a key tree out of key order."
fails := OrderedCollection new.
kinds do: [:k |
  rome := PBObject withAll: { 'city' -> 'Rome' }.
  idx := (k name: 'by_city' path: 'city') build: { rome }.
  group := (PBAvl keyAt: idx groups key: 'Rome') value.
  misfiled := (PBAvl keyPut: ((PBAvl keyRemove: idx groups key: 'Rome') at: 1) key: 'Paris' value: group nodeClass: PBCountedKeyNode) at: 1.
  expect value: k name , ' under another key' value: (refused value: [(idx _with: { 'groups' -> misfiled }) validate: { rome }]) value: PBMisfiledError.
  ages := { PBObject withAll: { 'age' -> 1 }. PBObject withAll: { 'age' -> 2 } }.
  idx := (k name: 'by_age' path: 'age') build: ages.
  group := (PBAvl keyAt: idx groups key: 1) value.
  misfiled := (PBAvl keyPut: ((PBAvl keyRemove: idx groups key: 1) at: 1) key: 7 value: group nodeClass: PBCountedKeyNode) at: 1.
  expect value: k name , ' 1 under 7' value: (refused value: [(idx _with: { 'groups' -> misfiled }) validate: ages]) value: PBMisfiledError.
  misfiled := PBCountedKeyNode key: 'Rome' value: (PBAvl keyAt: ((k name: 'c' path: 'city') build: { rome }) groups key: 'Rome') value
    left: (PBCountedKeyNode key: 'Zz' value: (PBTuple withAll: { nil. 0 }) left: nil right: nil) right: nil.
  text := refusedText value: [((k name: 'c' path: 'city') _with: { 'groups' -> misfiled }) validate: { rome }].
  expect value: k name , ' out of key order' value: (refused value: [((k name: 'c' path: 'city') _with: { 'groups' -> misfiled }) validate: { rome }]) value: PBMisfiledError.
  expect value: k name , ' the message' value: (text includesSubstring: 'holds a misfiled entry: the key ''Rome'' is stored after ''Zz''') value: true].
c that: 'validate: signals PBMisfiledError on a misfiled member' is: fails asArray equals: #().

"Spec 3.3: a vector index refuses every hook, and so does an index set over an index of a kind
 protoBaseST does not know (an opaque atom)."
fails := OrderedCollection new.
vector := PBVectorIndex _unsavedWithState: (PBFrozenDict withAssociations: {
  'name' -> 'by_emb'. 'key_spec' -> (PBTuple withAll: #('path' 'emb')). 'dim' -> 2. 'metric' -> 'l2'. 'backend' -> 'flat'.
  'params' -> nil. 'store' -> nil. 'invalid' -> nil. 'total_count' -> 0. 'centroids' -> (PBTuple withAll: #()).
  'trained_size' -> 0. 'member_tokens' -> 1 }).
{ [vector withAdded: 1]. [vector withRemoved: 1]. [vector withReplaced: 1 with: 2]. [vector empty]. [vector build: #(1)].
  [vector validate: #()]. [vector explain]. [PBVectorIndex name: 'v' keySpec: PBKeySpec element] } doWithIndex: [:hook :i |
  expect value: 'vector hook ' , i printString value: (refused value: hook) value: PBNotSupportedError.
  expect value: 'vector hook ' , i printString , ' message' value: ((refusedText value: hook) includesSubstring: 'vector') value: true].
expect value: 'vector names itself' value: ((refusedText value: [vector withAdded: 1]) beginsWith: 'Index ''by_emb'' (VectorIndex on emb) withAdded:') value: true.
expect value: 'vector key spec reads' value: vector keySpecObject value: (PBKeySpec path: 'emb').
set := PBIndexSet new withIndex: vector.
expect value: 'an index set with a vector index' value: ((refusedText value: [set onAdd: 1]) includesSubstring: 'vector') value: true.
opaque := PBOpaqueAtom named: 'acme.indexing.CustomIndex' unloadedAt: (PBAtomPointer segment: (ByteArray new: 16) offset: 1) storage: Object new.
set := PBIndexSet _unsavedWithState: (PBFrozenDict withAssociations: {
  'root' -> ((PBAvl keyPut: nil key: 'custom' value: opaque nodeClass: PBKeyNode) at: 1) }).
{ [set onAdd: 1]. [set onRemove: 1]. [set onReplace: 1 with: 2] } doWithIndex: [:hook :i |
  expect value: 'unknown kind ' , i printString value: (refused value: hook) value: PBNotSupportedError.
  expect value: 'unknown kind ' , i printString , ' message' value: (refusedText value: hook)
    value: 'The index ''custom'' is of the type acme.indexing.CustomIndex, which protoBaseST does not know: a collection holding it is read only (design spec 3.3)'].
c that: 'vector and unknown index kinds refuse every hook' is: fails asArray equals: #().

"The depth refusal of checkDepth:index: (keyed.py check_member_key) is proto_db's sentence, word
 for word (taken from proto_db at the tag), from withAdded: and from build: alike; one level less
 is stored."
fails := OrderedCollection new.
deep := 1.
254 timesRepeat: [deep := PBFrozenList withAll: { deep }].
expect value: '254 lists are stored' value: ((PBEqualityIndex name: 'n' path: 'a.b') withAdded: deep) count value: 1.
deep := PBFrozenList withAll: { deep }.
text := 'Index ''n'' (EqualityIndex on a.b) cannot store this element: its member key would nest 1026 MessagePack containers deep, more than MAX_VALUE_DEPTH = 1022 (format spec, "Value nesting depth"). The index stores an orderable element inside 4 containers, so it may nest at most 1018; an unorderable one (holding a list, a map or NaN) through its surrogate, 4 containers per list level and 6 per map level: at most 254 nested lists or 169 nested maps'.
expect value: 'withAdded:' value: (refusedText value: [(PBEqualityIndex name: 'n' path: 'a.b') withAdded: deep]) value: text.
expect value: 'build:' value: (refusedText value: [(PBEqualityIndex name: 'n' path: 'a.b') build: { 1. deep }]) value: text.
expect value: 'checkDepth:index:' value: (refusedText value: [PBMemberKeys checkDepth: deep index: (PBEqualityIndex name: 'n' path: 'a.b')]) value: text.
deep := 1.
170 timesRepeat: [deep := PBFrozenDict withAssociations: { 'k' -> deep }].
expect value: 'a range index on 170 maps' value: (refusedText value: [(PBRangeIndex name: 'by_m' keySpec: PBKeySpec element) withAdded: deep])
  value: ('Index ''by_m'' (RangeIndex on <element>)' , (text copyFrom: 'Index ''n'' (EqualityIndex on a.b)' size + 1 to: text size)).
c that: 'the depth refusal is proto_db''s sentence' is: fails asArray equals: #().

"PBIndexSet (proto_db IndexSet): withIndex:, without:, and the element hooks over every index;
 rebuiltStale: rebuilds a format-3 index (member_tokens absent or not 1) from the elements."
fails := OrderedCollection new.
idx := PBEqualityIndex name: 'by_city' path: 'city'.
idx2 := PBRangeIndex name: 'by_age' path: 'age'.
set := (PBIndexSet new withIndex: idx) withIndex: idx2.
expect value: 'names' value: set names value: #('by_age' 'by_city').
expect value: 'a taken name' value: (refused value: [set withIndex: (PBRangeIndex name: 'by_city' path: 'x')]) value: PBValidationError.
expect value: 'not an index' value: (refused value: [set withIndex: 3]) value: PBValidationError.
expect value: 'without' value: (set without: 'by_city') names value: #('by_age').
expect value: 'without an absent name' value: (refused value: [set without: 'nope']) value: PBValidationError.
expect value: 'the empty set answers itself' value: (PBIndexSet new onAdd: 1) isEmpty value: true.
set2 := people inject: set into: [:s :p | s onAdd: p].
fold := [:index :all | | out | out := index. all do: [:e | out := out withAdded: e]. out].
expect value: 'onAdd: on both' value: (set2 names collect: [:nm | QData dump: (set2 get: nm)])
  value: { QData dump: (fold value: idx2 value: people). QData dump: (fold value: idx value: people) }.
set2 := (set2 onRemove: people first) onReplace: people last with: people first.
expect value: 'onRemove: and onReplace:with:' value: (set2 names collect: [:nm | QData dump: (set2 get: nm)])
  value: { QData dump: (((fold value: idx2 value: people) withRemoved: people first) withReplaced: people last with: people first).
    QData dump: (((fold value: idx value: people) withRemoved: people first) withReplaced: people last with: people first) }.
expect value: 'the receiver keeps no element' value: ((set get: 'by_city') count) value: 0.
stale := (idx build: people) _with: { 'member_tokens' -> 0 }.
set2 := (PBIndexSet new withIndex: stale) withIndex: (idx2 build: people).
expect value: 'a set with a stale index answers a new set' value: (set2 rebuiltStale: people) == set2 value: false.
expect value: 'a stale index is rebuilt' value: (QData dump: ((set2 rebuiltStale: people) get: 'by_city')) value: (QData dump: (idx build: people)).
expect value: 'a current one is kept' value: ((set2 rebuiltStale: people) get: 'by_age') == (set2 get: 'by_age') value: true.
set2 := PBIndexSet new withIndex: (idx build: people).
expect value: 'no stale index: the set itself' value: (set2 rebuiltStale: people) == set2 value: true.
c that: 'index sets apply the hooks to every index' is: fails asArray equals: #().

c report displayNl.
