"EXPECT: ok 15"
"Indexed queries, plan Task 2: PBKeySpec and the extractor registry (proto_db
 proto_db/indexing/keyspec.py at v2.0.0rc4; the behaviours of tests/unit/test_keyspec.py that
 apply, mapped in tests/unit/queries_checklist.tsv). A path step reads a record's own
 attributes, another atom's persisted fields and a map's keys; an absent one, or a step through
 any other value, is PBMissing default; nil stays nil; names starting with _ and the reserved
 names are never read from an atom (a map's keys are data). Key specs are frozen values, equal
 by value, persisted as the (kind, arg) tuple; malformed data is PBCorruptionError. The registry
 is one Atom of a PBFrozenDict: a name keeps its block and version; an unregistered name fails
 at use naming it; an extractor's exception passes through extract: unchanged (ruling IQ1, plan
 call IP2), and eight actors registering at once leave eight names (compare-and-swap). Each check
 gathers its mismatches and requires none, so one label covers one behaviour."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_spaces'.

Object subclass: #KeySpecRegistrar instanceVariableNames: 'extractorName'.

KeySpecRegistrar class >> extractorName: aString
  ^ self basicNew setExtractorName: aString.

KeySpecRegistrar >> setExtractorName: aString
  extractorName := aString.

"Registers the extractor of this registrar's name, then answers whether it is registered."
KeySpecRegistrar >> run
  PBKeySpec registerExtractor: extractorName block: [:e | extractorName] version: '1'.
  ^ PBKeySpec isExtractorRegistered: extractorName.

| c fails expect refused missing rec dir sb inner outer st stub list spec data same other
  boom actors results first |
c := Check new.
missing := PBMissing default.
"Adds a mismatch to fails unless actual = expected (identity for PBMissing)."
expect := [:label :actual :expected |
  (expected == missing ifTrue: [actual == missing] ifFalse: [actual = expected])
    ifFalse: [fails add: label , ': expected ' , expected printString , ', got ' , actual printString]].
"The class of the error aBlock signals, or nil."
refused := [:aBlock | [aBlock value. nil] on: Error do: [:e | e return: e class]].

"test_path_reads_record_attributes_and_absent_is_missing, test_dotted_path_through_records_and_mappings,
 test_path_reads_persisted_attributes_of_other_atoms_only"
fails := OrderedCollection new.
spec := PBKeySpec path: 'city'.
expect value: 'city' value: (spec extract: (PBObject withAll: { 'city' -> 'Rome' })) value: 'Rome'.
expect value: 'city nil' value: (spec extract: (PBObject withAll: { 'city' -> nil })) value: nil.
expect value: 'city absent' value: (spec extract: (PBObject withAll: { 'zip' -> 1 })) value: missing.
spec := PBKeySpec path: 'address.zip'.
expect value: 'record.record' value: (spec extract: (PBObject withAll: { 'address' -> (PBObject withAll: { 'zip' -> 1000 }) })) value: 1000.
expect value: 'record.map' value: (spec extract: (PBObject withAll: { 'address' -> (PBFrozenDict withAssociations: { 'zip' -> 2000 }) })) value: 2000.
expect value: 'map.map' value: (spec extract: (PBFrozenDict withAssociations: { 'address' -> (PBFrozenDict withAssociations: { 'zip' -> 3000 }) })) value: 3000.
expect value: 'map.map nil' value: (spec extract: (PBFrozenDict withAssociations: { 'address' -> (PBFrozenDict withAssociations: { 'zip' -> nil }) })) value: nil.
expect value: 'map without the key' value: (spec extract: (PBObject withAll: { 'address' -> (PBFrozenDict withAssociations: { 'street' -> 'x' }) })) value: missing.
expect value: 'through nil' value: (spec extract: (PBObject withAll: { 'address' -> nil })) value: missing.
expect value: 'through a number' value: (spec extract: (PBObject withAll: { 'address' -> 5 })) value: missing.
expect value: 'empty record' value: (spec extract: PBObject new) value: missing.
expect value: 'a number' value: (spec extract: 7) value: missing.
expect value: 'nil' value: (spec extract: nil) value: missing.
list := (PBList new appendLast: 1) appendLast: 2.
expect value: 'a list''s count' value: ((PBKeySpec path: 'count') extract: list) value: 2.
expect value: 'a list''s elements (not persisted)' value: ((PBKeySpec path: 'elements') extract: list) value: missing.
c that: 'path steps read records, maps and other atoms' is: fails asArray equals: #().

"test_private_and_reserved_names_are_never_read"
fails := OrderedCollection new.
rec := PBObject withAll: { 'a' -> 1 }.
#('context' 'oid' 'atom_pointer' '_loaded') do: [:name |
  expect value: name value: ((PBKeySpec path: name) extract: rec) value: missing].
expect value: 'oid of a list' value: ((PBKeySpec path: 'oid') extract: list) value: missing.
expect value: 'a map key _x is data' value: ((PBKeySpec path: '_x') extract: (PBFrozenDict withAssociations: { '_x' -> 1 })) value: 1.
c that: 'private and reserved names are never read' is: fails asArray equals: #().

"test_path_extraction_loads_lazy_stubs: a record stored in a space, read through a new stub
 (the directory out/ is ignored by git; the files are overwritten on every run)."
fails := OrderedCollection new.
dir := 'out/idx_keyspec' asFileReference.
sb := SpaceBuilder segment: (ByteArray fromHex: '2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d').
inner := sb add: 'proto_db.core.dbobject.DBObject' oid: 1 state: { 'zip' -> 42 }.
outer := sb add: 'proto_db.core.dbobject.DBObject' oid: 2 state: { 'address' -> inner. 'city' -> 'Oslo' }.
sb writeTo: dir root: outer.
st := PBFileStorage path: dir pathString.
stub := PBObject unloadedAt: outer pointer storage: st.
expect value: 'not loaded before' value: stub isLoaded value: false.
expect value: 'address.zip' value: ((PBKeySpec path: 'address.zip') extract: stub) value: 42.
expect value: 'city' value: ((PBKeySpec path: 'city') extract: (PBObject unloadedAt: outer pointer storage: st)) value: 'Oslo'.
expect value: 'zip' value: ((PBKeySpec path: 'zip') extract: (PBObject unloadedAt: outer pointer storage: st)) value: missing.
st close.
c that: 'path extraction loads stubs' is: fails asArray equals: #().

"test_element_returns_the_element_itself"
fails := OrderedCollection new.
spec := PBKeySpec element.
expect value: 'a record, itself' value: (spec extract: rec) == rec value: true.
expect value: '5' value: (spec extract: 5) value: 5.
expect value: 'missing' value: (spec extract: missing) value: missing.
c that: 'element answers the element itself' is: fails asArray equals: #().

"test_invalid_paths_are_rejected, test_extractor_name_validated_on_construction,
 test_direct_construction_is_validated (fromData: is the direct construction here; its
 refusals are corruption, checked below), test_register_extractor_validates"
fails := OrderedCollection new.
{ ''. 'a..b'. '.a'. 'a.'. '@x'. 'a. b'. ' a'. 3. nil. #[97] } do: [:bad |
  expect value: 'path: ' , bad printString value: (refused value: [PBKeySpec path: bad]) value: PBValidationError].
{ ''. nil. 3. 'has space'. '@x'. 'tab	in' } do: [:bad |
  expect value: 'extractor: ' , bad printString value: (refused value: [PBKeySpec extractor: bad]) value: PBValidationError].
{ { ''. [:e | e] }. { nil. [:e | e] }. { 3. [:e | e] }. { 'ok.name'. 'not a block' }. { 'has space'. [:e | e] } } do: [:pair |
  expect value: 'register ' , pair printString
    value: (refused value: [PBKeySpec registerExtractor: pair first block: pair last version: nil])
    value: PBValidationError].
expect value: 'register with an empty version' value: (refused value: [PBKeySpec registerExtractor: 'tests.keyspec.v' block: [:e | e] version: '']) value: PBValidationError.
expect value: 'register with a non-String version' value: (refused value: [PBKeySpec registerExtractor: 'tests.keyspec.v' block: [:e | e] version: 1]) value: PBValidationError.
expect value: 'the path message' value: ([PBKeySpec path: '@x'] on: PBValidationError do: [:e | e return: e messageText])
  value: 'A key path must be a non-empty String not starting with ''@'', not ''@x'''.
expect value: 'the segment message' value: ([PBKeySpec path: 'a..b'] on: PBValidationError do: [:e | e return: e messageText])
  value: 'Invalid key path ''a..b'': empty or blank segment'.
expect value: 'the extractor name message' value: ([PBKeySpec extractor: 'has space'] on: PBValidationError do: [:e | e return: e messageText])
  value: 'An extractor name must be a non-empty String without whitespace or a leading ''@'', not ''has space'''.
expect value: 'a valid path' value: (PBKeySpec path: 'a.b_c.d') arg value: 'a.b_c.d'.
c that: 'invalid paths and names are refused' is: fails asArray equals: #().

"test_term_paths, test_describe"
fails := OrderedCollection new.
expect value: 'path termPath' value: (PBKeySpec path: 'a.b') termPath value: 'a.b'.
expect value: 'element termPath' value: PBKeySpec element termPath value: nil.
expect value: 'extractor termPath' value: (PBKeySpec extractor: 'f') termPath value: '@f'.
{ PBKeySpec path: 'a.b'. PBKeySpec element. PBKeySpec extractor: 'f' } do: [:s |
  expect value: 'forTermPath: ' , s printString value: (PBKeySpec forTermPath: s termPath) value: s].
expect value: 'forTermPath: 3' value: (refused value: [PBKeySpec forTermPath: 3]) value: PBValidationError.
expect value: 'path describe' value: (PBKeySpec path: 'a.b') describe value: 'a.b'.
expect value: 'element describe' value: PBKeySpec element describe value: '<element>'.
expect value: 'extractor describe' value: (PBKeySpec extractor: 'f') describe value: '@f'.
expect value: 'kinds' value: ({ PBKeySpec path: 'a'. PBKeySpec element. PBKeySpec extractor: 'f' } collect: [:s | s kind])
  value: #('path' 'element' 'extractor').
c that: 'term paths and describe' is: fails asArray equals: #().

"test_plain_data_round_trip, test_malformed_data_is_corruption, test_direct_construction_is_validated"
fails := OrderedCollection new.
{ PBKeySpec path: 'a.b'. PBKeySpec element. PBKeySpec extractor: 'e.f' } do: [:s |
  data := s asData.
  expect value: 'asData is a PBTuple' value: data class value: PBTuple.
  expect value: 'asData holds Strings or nil' value: (data asArray allSatisfy: [:x | x isNil or: [x isString]]) value: true.
  expect value: 'fromData: asData' value: (PBKeySpec fromData: data) value: s.
  expect value: 'fromData: a list' value: (PBKeySpec fromData: (PBFrozenList withAll: data asArray)) value: s.
  expect value: 'fromData: an Array' value: (PBKeySpec fromData: data asArray) value: s].
expect value: 'asData of a path' value: (PBKeySpec path: 'a.b') asData value: (PBTuple withAll: #('path' 'a.b')).
expect value: 'asData of the element' value: PBKeySpec element asData value: (PBTuple withAll: { 'element'. nil }).
expect value: 'direct construction' value: (PBKeySpec fromData: #('path' 'a')) value: (PBKeySpec path: 'a').
{ nil. 'path'. #('path'). #('path' 'a' 'b'). #('bogus' 'a'). #('path' ''). #('element' 'a'). { 'path'. nil }. #('extractor' '') } do: [:bad |
  expect value: 'fromData: ' , bad printString value: (refused value: [PBKeySpec fromData: bad]) value: PBCorruptionError].
expect value: 'the kind message' value: ([PBKeySpec fromData: #('bogus' 'a')] on: PBCorruptionError do: [:e | e return: e messageText])
  value: 'Malformed persisted key spec (''bogus'', ''a''): Unknown key spec kind ''bogus''; expected one of (''path'', ''element'', ''extractor'')'.
c that: 'data round trip and corruption' is: fails asArray equals: #().

"test_keyspec_is_a_frozen_value (a frozen value: no setter; the initialiser runs once)"
fails := OrderedCollection new.
spec := PBKeySpec path: 'a.b'.
same := PBKeySpec path: 'a.b'.
expect value: 'equal' value: spec = same value: true.
expect value: 'equal hashes' value: spec hash = same hash value: true.
expect value: 'another path' value: spec = (PBKeySpec path: 'a') value: false.
expect value: 'elements' value: PBKeySpec element = PBKeySpec element value: true.
expect value: 'an extractor is not a path' value: (PBKeySpec extractor: 'x') = (PBKeySpec path: 'x') value: false.
expect value: 'not a tuple' value: spec = spec asData value: false.
expect value: 'no setter' value: (spec respondsTo: #arg:) value: false.
expect value: 'initialised once' value: (refused value: [spec _setKind: 'path' arg: 'c' segments: #('c')]) value: PBUserError.
expect value: 'unchanged' value: spec arg value: 'a.b'.
c that: 'key specs are frozen values' is: fails asArray equals: #().

"test_named_extractor_registry, test_extractor_results_are_canonical"
fails := OrderedCollection new.
PBKeySpec registerExtractor: 'tests.keyspec.city' block: [:e | (PBKeySpec path: 'city') extract: e] version: nil.
PBKeySpec registerExtractor: 'tests.keyspec.as_list' block: [:e | { e. e }] version: nil.
PBKeySpec registerExtractor: 'tests.keyspec.bad_value' block: [:e | Object new] version: nil.
spec := PBKeySpec extractor: 'tests.keyspec.city'.
expect value: 'city' value: (spec extract: (PBObject withAll: { 'city' -> 'x' })) value: 'x'.
expect value: 'no city' value: (spec extract: PBObject new) value: missing.
data := (PBKeySpec extractor: 'tests.keyspec.as_list') extract: 1.
expect value: 'canonical class' value: data class value: PBFrozenList.
expect value: 'canonical items' value: data asArray value: #(1 1).
expect value: 'a value the codec refuses' value: (refused value: [(PBKeySpec extractor: 'tests.keyspec.bad_value') extract: 1]) value: PBValidationError.
c that: 'extractor results are canonical' is: fails asArray equals: #().

"test_extractor_names_cannot_be_redefined, with versions (R101)"
fails := OrderedCollection new.
first := [:e | 1].
PBKeySpec registerExtractor: 'tests.keyspec.stable' block: first version: '2'.
expect value: 'same block and version' value: (refused value: [PBKeySpec registerExtractor: 'tests.keyspec.stable' block: first version: '2']) value: nil.
expect value: 'another block' value: (refused value: [PBKeySpec registerExtractor: 'tests.keyspec.stable' block: [:e | 2] version: '2']) value: PBValidationError.
expect value: 'another version' value: (refused value: [PBKeySpec registerExtractor: 'tests.keyspec.stable' block: first version: '3']) value: PBValidationError.
expect value: 'no version' value: (refused value: [PBKeySpec registerExtractor: 'tests.keyspec.stable' block: first version: nil]) value: PBValidationError.
expect value: 'still the first block' value: ((PBKeySpec extractor: 'tests.keyspec.stable') extract: nil) value: 1.
expect value: 'its version' value: (PBKeySpec extractorVersion: 'tests.keyspec.stable') value: '2'.
expect value: 'no version declared' value: (PBKeySpec extractorVersion: 'tests.keyspec.city') value: nil.
c that: 'a name keeps its block and version' is: fails asArray equals: #().

"unregister_extractor"
fails := OrderedCollection new.
PBKeySpec unregisterExtractor: 'tests.keyspec.stable'.
expect value: 'used after unregistering' value: (refused value: [(PBKeySpec extractor: 'tests.keyspec.stable') extract: nil]) value: PBValidationError.
expect value: 'its version after unregistering' value: (refused value: [PBKeySpec extractorVersion: 'tests.keyspec.stable']) value: PBValidationError.
expect value: 'unregistered twice' value: (refused value: [PBKeySpec unregisterExtractor: 'tests.keyspec.stable']) value: PBValidationError.
PBKeySpec registerExtractor: 'tests.keyspec.stable' block: [:e | 2] version: nil.
expect value: 'registered again with another block' value: ((PBKeySpec extractor: 'tests.keyspec.stable') extract: nil) value: 2.
expect value: 'the others kept' value: ((PBKeySpec extractor: 'tests.keyspec.city') extract: PBObject new) value: missing.
c that: 'unregister' is: fails asArray equals: #().

"isExtractorRegistered: (pre-flight F21)"
fails := OrderedCollection new.
expect value: 'before' value: (PBKeySpec isExtractorRegistered: 'tests.keyspec.probe') value: false.
PBKeySpec registerExtractor: 'tests.keyspec.probe' block: [:e | e] version: nil.
expect value: 'after registering' value: (PBKeySpec isExtractorRegistered: 'tests.keyspec.probe') value: true.
PBKeySpec unregisterExtractor: 'tests.keyspec.probe'.
expect value: 'after unregistering' value: (PBKeySpec isExtractorRegistered: 'tests.keyspec.probe') value: false.
expect value: 'not a name' value: (PBKeySpec isExtractorRegistered: 3) value: false.
c that: 'isExtractorRegistered' is: fails asArray equals: #().

"test_unregistered_extractor_fails_at_use_with_a_clear_message"
spec := PBKeySpec extractor: 'tests.keyspec.never_registered'.
c that: 'an unregistered extractor fails at use, naming it'
  signals: PBValidationError
  containing: 'No key extractor is registered under ''tests.keyspec.never_registered''; call PBKeySpec registerExtractor:'
  during: [spec extract: PBObject new].

"Ruling IQ1, plan call IP2: the block's own exception, unchanged."
PBKeySpec registerExtractor: 'boom' block: [:e | 1 / 0] version: nil.
boom := [(PBKeySpec extractor: 'boom') extract: PBObject new. nil]
  on: Error do: [:e | e return: { e class. e isKindOf: PBDBError }].
c that: 'extractor error passes through' is: boom equals: { ZeroDivide. false }.

"Eight actors register eight names at once: no registration is lost (compare-and-swap)."
actors := (1 to: 8) asArray collect: [:i | (KeySpecRegistrar extractorName: 'tests.keyspec.actor' , i printString) asActor].
results := (actors collect: [:a | a run]) collect: [:f | f wait].
c that: 'eight actors register eight names'
  is: { results. (1 to: 8) asArray collect: [:i | PBKeySpec isExtractorRegistered: 'tests.keyspec.actor' , i printString] }
  equals: { (1 to: 8) asArray collect: [:i | true]. (1 to: 8) asArray collect: [:i | true] }.

c report displayNl.
