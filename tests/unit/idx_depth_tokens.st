"EXPECT: ok 12"
"Indexed queries, vectors phase V0 fix round 1: the key-group index behaviours of
 tests/unit/test_format_neutral.py and tests/unit/test_structure_depth.py (proto_db at v2.0.0rc4)
 that no check held before. Member tokens (review C1, D58): removing a decoded value removes that
 member and never an equal one; an equal value under another token is refused, by the equality
 and the range index alike; validate: reports a member filed under another token; the reviewers'
 end-to-end case through a file storage; an index written by format 3 (member_tokens absent, the
 old ('i', element) token form) validates, and is rebuilt at the first change of its collection.
 Member-key depth (B12, D60), every boundary committed through a PBFileStorage so the encoder is
 the judge: an orderable element nests the limit less the member key's 4 containers; an
 unorderable one nests through its surrogate (254 lists, 169 maps); the member-key limit is exact
 at every leaf width; a field index over plain maps stores them through their surrogates; addIndex:
 over data it cannot store refuses at the call, the same way; and a refusal leaves the transaction
 usable. The limits are computed from PBMemberKeys' wrapping constants, never written as numbers
 alone. The vector halves of these files are deferred to the vectors phase (queries_checklist.tsv)."
Import from: 'protobase'.
Import from: '_check'.

| c base space db tx held utcNamed minus3 roundTrip element eq index after rows tokens refused refusedText
  members groups broken path legacy lst old new limits orderable lists maps leaves nest tuplesAt
  listsAt commit dbCount depthOfKey at over fails text deep |
c := Check new.
element := PBKeySpec element.
eq := [:op :v | PBTerm path: nil op: op value: v].
tokens := [:anArray | anArray collect: [:each | PBKeys exactToken: each]].
refused := [:aBlock | [aBlock value. nil] on: Error do: [:e | e return: e class]].
refusedText := [:aBlock | [aBlock value. nil] on: PBValidationError do: [:e | e return: e messageText]].
roundTrip := [:v | PBCodec decode: (PBCodec encode: v)].

"The application's UTC, named explicitly, and the same instant at -03:00 (review C1)."
utcNamed := DateTime year: 2026 month: 1 day: 1 hour: 0 minute: 0 second: 0 microsecond: 0 fold: 0
  zone: (ZoneOffset microseconds: 0 name: 'UTC').
minus3 := DateTime year: 2025 month: 12 day: 31 hour: 21 minute: 0 second: 0 microsecond: 0 fold: 0
  zone: (ZoneOffset microseconds: -10800000000).

"=== test_format_neutral.py: member tokens ==="

"test_removing_a_decoded_value_removes_that_member_not_an_equal_one"
index := (PBEqualityIndex name: 'e' keySpec: element) build: { utcNamed. minus3 }.
after := index withRemoved: (roundTrip value: utcNamed).
c that: 'removing a decoded value removes that member, not an equal one'
  is: { tokens value: (after plan: (eq value: '==' value: utcNamed)) execute. (after validate: { minus3 }) == after }
  equals: { tokens value: { minus3 }. true }.

"test_removing_an_equal_but_different_value_is_refused, for both key-group kinds"
c that: 'removing an equal but different value is refused by the equality and the range index'
  is: ({ PBEqualityIndex. PBRangeIndex } collect: [:kind |
    index := (kind name: 'e' keySpec: element) build: { 1. Decimal fromString: '1.00' }.
    { refused value: [index withRemoved: 1.0].
      ((refusedText value: [index withRemoved: 1.0]) ifNil: ['']) includesSubstring: 'does not hold'.
      tokens value: ((index withRemoved: (Decimal fromString: '1.00')) plan: (eq value: '==' value: 1)) execute }])
  equals: ({ 1. 2 } collect: [:k | { PBValidationError. true. tokens value: #(1) }]).

"test_validate_reports_a_member_under_another_token: the member of 1 stored as if it were 1.0
 (same group, same equality part, the wrong token)."
index := (PBEqualityIndex name: 'e' keySpec: element) build: #(1).
members := (PBAvl keyPut: nil key: (PBTuple withAll: { PBMemberKeys _equalityPart: 1. PBKeys exactToken: 1.0 })
  value: (PBTuple withAll: #(1 1)) nodeClass: PBCountedKeyNode) at: 1.
groups := (PBAvl keyPut: nil key: 1 value: (PBTuple withAll: { members. 1 }) nodeClass: PBCountedKeyNode) at: 1.
broken := index _with: { 'groups' -> groups }.
c that: 'validate: reports a member under another token'
  signals: PBCorruptionError containing: 'wrong member key' during: [broken validate: #(1)].

"test_the_reviewers_end_to_end_repro: written, reopened, the first element removed, reopened: the
 scan and the index answer the same single element, and the index validates."
base := FileSystem temp / ('pbst-idx-depth-tokens-' , Smalltalk pid printString).
base deleteAll.
path := (base / 'repro') pathString.
space := PBObjectSpace storage: (PBFileStorage path: path).
db := space newDatabase: 'd'.
tx := db newTransaction.
tx setRootObject: 'l' value: (((PBList new addIndex: (PBEqualityIndex name: 'e' keySpec: element)) appendLast: utcNamed) appendLast: minus3).
tx commit.
space close.
space := PBObjectSpace storage: (PBFileStorage path: path).
tx := (space openDatabase: 'd') newTransaction.
tx setRootObject: 'l' value: ((tx getRootObject: 'l') removeAt: 0).
tx commit.
space close.
space := PBObjectSpace storage: (PBFileStorage path: path).
lst := (space openDatabase: 'd') newTransaction getRootObject: 'l'.
rows := OrderedCollection new.
lst do: [:each | rows add: each].
c that: 'the reviewers'' end-to-end case: after a reopen the scan and the index answer the same element'
  is: { tokens value: rows asArray. tokens value: ((lst getIndex: 'e') plan: (eq value: '==' value: utcNamed)) execute.
    ((lst getIndex: 'e') validate: rows asArray) == (lst getIndex: 'e') }
  equals: { tokens value: { minus3 }. tokens value: { minus3 }. true }.
space close.

"A key-group index as a format-3 writer left it: member keys (equality part, ('i', element)) and
 no member_tokens (nil: the field absent)."
legacy := [:anIndex | | out |
  out := nil.
  PBAvl keysAndValuesDo: [:key :group | | old |
    old := nil.
    PBAvl keysAndValuesDo: [:mk :entry |
      old := (PBAvl keyPut: old key: (PBTuple withAll: { mk at: 1. PBTuple withAll: { 'i'. entry at: 1 } }) value: entry
        nodeClass: PBCountedKeyNode) at: 1] over: (group at: 1).
    out := (PBAvl keyPut: out key: key value: (PBTuple withAll: { old. group at: 2 }) nodeClass: PBCountedKeyNode) at: 1]
    over: anIndex groups.
  anIndex _with: { 'groups' -> out. 'member_tokens' -> nil }].

"test_validate_accepts_an_index_with_format_3_tokens"
lst := (PBList new extend: #(1 2 2)) addIndex: (PBEqualityIndex name: 'e' keySpec: element).
index := legacy value: (lst getIndex: 'e').
c that: 'validate: accepts an index with format-3 tokens and still checks the rest'
  is: { index hasMemberTokens. (index validate: #(1 2 2)) == index. refused value: [index validate: #(1 2)] }
  equals: { false. true. PBCorruptionError }.

"test_an_index_with_format_3_tokens_is_rebuilt_at_its_first_change"
old := lst _withChanges: { 'indexes' -> ((lst indexes without: 'e') withIndex: index) }.
new := old removeAt: 1.
after := new getIndex: 'e'.
rows := OrderedCollection new.
new do: [:each | rows add: each].
c that: 'an index with format-3 tokens is rebuilt at the first change of its collection'
  is: { (old getIndex: 'e') hasMemberTokens. after hasMemberTokens. (after validate: rows asArray) == after.
    (after plan: (eq value: '==' value: 2)) execute }
  equals: { false. true. true. #(2) }.

"=== test_structure_depth.py: the member key wraps the element ==="

space := PBObjectSpace storage: (PBFileStorage path: (base / 'depth') pathString).
dbCount := 0.
"Stores aValue as root aName of a new database, commits it through the encoder and answers what
 reads back."
commit := [:aName :aValue | | d t |
  dbCount := dbCount + 1.
  d := space newDatabase: aName , dbCount printString.
  t := d newTransaction.
  t setRootObject: aName value: aValue.
  t commit.
  d newTransaction getRootObject: aName].
limits := PBMemberKeys depthLimits.
orderable := limits at: 'orderable'.
lists := limits at: 'lists'.
maps := limits at: 'maps'.
"Scalars by the containers their wire form nests, 0 to 3 (the test's LEAVES)."
leaves := { 1. Decimal fromString: '1.5'. CalendarDate year: 2026 month: 1 day: 2.
  DateTime year: 2026 month: 1 day: 2 hour: 3 minute: 4 second: 0 microsecond: 0 fold: 0 zone: ZoneOffset utc }.
nest := [:n :leaf :kind | | v |
  v := leaf.
  n timesRepeat: [v := kind = #list ifTrue: [PBFrozenList withAll: { v }] ifFalse: [
    kind = #tuple ifTrue: [PBTuple withAll: { v }] ifFalse: [PBFrozenDict withAssociations: { 'k' -> v }]]].
  v].
"An orderable value (nested tuples) whose wire form nests exactly n containers."
tuplesAt := [:n | nest value: n // 2 value: (leaves at: n \\ 2 + 1) value: #tuple].
"An unorderable element (nested lists inside the maps anOuter names) whose member key nests
 exactly aDepth containers (the test's lists_with_member_key_at)."
listsAt := [:aDepth :anOuter | | room v |
  room := aDepth - PBMemberKeys memberKeyWrapping - PBMemberKeys surrogateLeaf - (PBMemberKeys surrogateMapLevel * anOuter size).
  v := nest value: room // PBMemberKeys surrogateListLevel value: (leaves at: room \\ PBMemberKeys surrogateListLevel + 1) value: #list.
  anOuter reverseDo: [:fields | v := PBFrozenDict withAssociations: fields , { 'deep' -> v }].
  v].
depthOfKey := [:v | PBCodec valueDepth: (PBMemberKeys memberKeyOf: (PBCodec canonical: v))].
"The index of the test: an equality index on the element, over an empty List."
held := [PBList new addIndex: (PBEqualityIndex name: 'e' keySpec: element)].

"test_an_orderable_element_of_an_index_may_nest_the_limit_less_the_member_key"
text := (refusedText value: [held value appendLast: (tuplesAt value: orderable + 1)]) ifNil: [''].
c that: 'an orderable element may nest the limit less the member key'
  is: { leaves collect: [:leaf | PBCodec valueDepth: (PBCodec canonical: leaf)].
    orderable = (PBCodec maxValueDepth - PBMemberKeys memberKeyWrapping). depthOfKey value: (tuplesAt value: orderable).
    (commit value: 'l' value: (held value appendLast: (tuplesAt value: orderable))) count.
    { 'Index ''e'' (EqualityIndex on'. 'at most ' , orderable printString. 'MAX_VALUE_DEPTH'. 'member key would nest' }
      allSatisfy: [:each | text includesSubstring: each] }
  equals: { #(0 1 2 3). true. PBCodec maxValueDepth. 1. true }.

"test_an_unorderable_element_nests_through_its_surrogate: about 254 nested lists or 169 nested
 maps, not 1022."
text := 'at most ' , lists printString , ' nested lists or ' , maps printString , ' nested maps'.
c that: 'an unorderable element nests through its surrogate: lists and maps'
  is: ({ { #list. lists. PBMemberKeys surrogateListLevel }. { #map. maps. PBMemberKeys surrogateMapLevel } } collect: [:t | | kind n |
    kind := t at: 1.
    n := t at: 2.
    { n = (PBCodec maxValueDepth - PBMemberKeys memberKeyWrapping - PBMemberKeys surrogateLeaf // (t at: 3)).
      (commit value: 'l' value: (held value appendLast: (nest value: n value: 1 value: kind))) count.
      ((refusedText value: [held value appendLast: (nest value: n + 1 value: 1 value: kind)]) ifNil: ['']) includesSubstring: text }])
  equals: #(#(true 1 true) #(true 1 true)).

"test_the_member_key_limit_is_exact: at every leaf width, a member key of exactly MAX_VALUE_DEPTH
 commits and one more is refused."
fails := OrderedCollection new.
0 to: PBMemberKeys surrogateListLevel - 1 do: [:extra |
  at := listsAt value: PBCodec maxValueDepth - extra value: #().
  (depthOfKey value: at) = (PBCodec maxValueDepth - extra) ifFalse: [fails add: 'depth at ' , extra printString].
  (commit value: 'l' value: (held value appendLast: at)) count = 1 ifFalse: [fails add: 'commit at ' , extra printString].
  over := listsAt value: PBCodec maxValueDepth + 1 + extra value: #().
  (((refusedText value: [held value appendLast: over]) ifNil: [''])
    includesSubstring: 'would nest ' , (PBCodec maxValueDepth + 1 + extra) printString , ' MessagePack containers')
    ifFalse: [fails add: 'refusal at ' , extra printString]].
c that: 'the member-key limit is exact at every leaf width' is: fails asArray equals: #().

"test_a_field_index_over_plain_maps_stores_the_maps_through_their_surrogates"
at := listsAt value: PBCodec maxValueDepth value: { { 'k' -> 1 } }.
over := listsAt value: PBCodec maxValueDepth + 1 value: { { 'k' -> 1 } }.
text := (refusedText value: [(PBList new addIndex: (PBRangeIndex name: 'k' path: 'k'))
  extend: { PBFrozenDict withAssociations: { 'k' -> 0. 'v' -> 1 }. over }]) ifNil: [''].
c that: 'a field index over plain maps stores the maps through their surrogates'
  is: { depthOfKey value: at. (commit value: 'l' value: ((PBList new addIndex: (PBRangeIndex name: 'k' path: 'k')) appendLast: at)) count.
    (text includesSubstring: 'Index ''k'' (RangeIndex on k)') and: [text includesSubstring: 'member key would nest'] }
  equals: { PBCodec maxValueDepth. 1. true }.

"test_an_index_added_over_existing_data_refuses_the_same_way, its equality index half (the vector
 index half is deferred to the vectors phase): addIndex: refuses at the call, and the transaction
 goes on."
deep := nest value: lists + 1 value: 1 value: #list.
db := space newDatabase: 'added'.
tx := db newTransaction.
tx setRootObject: 'l' value: (PBList new extend: { 1. deep }).
tx commit.
tx := db newTransaction.
lst := tx getRootObject: 'l'.
text := (refusedText value: [lst addIndex: (PBEqualityIndex name: 'e' keySpec: element)]) ifNil: [''].
tx setRootObject: 'l' value: ((lst removeAt: 1) addIndex: (PBEqualityIndex name: 'e' keySpec: element)).
tx setRootObject: 'other' value: (PBObject withAll: { 'x' -> 1 }).
tx commit.
tx := db newTransaction.
c that: 'an index added over existing data refuses the same way, and the transaction goes on'
  is: { { 'Index ''e'''. 'member key would nest'. 'at most ' , lists printString , ' nested lists' } allSatisfy: [:each | text includesSubstring: each].
    (tx getRootObject: 'l') count. (tx getRootObject: 'other') at: 'x' }
  equals: { true. 1. 1 }.

"test_a_refusal_leaves_the_transaction_usable: the refusal comes at appendLast:, nothing is
 written into the transaction, and its other work commits."
db := space newDatabase: 'usable'.
tx := db newTransaction.
tx setRootObject: 'l' value: held value.
tx commit.
tx := db newTransaction.
lst := tx getRootObject: 'l'.
rows := { ((refusedText value: [lst appendLast: deep]) ifNil: ['']) includesSubstring: 'Index ''e'''.
  ((refusedText value: [PBSet new add: (tuplesAt value: PBCodec maxValueDepth)]) ifNil: ['']) includesSubstring: 'Set element' }.
tx setRootObject: 'l' value: (lst appendLast: (nest value: lists value: 1 value: #list)).
tx setRootObject: 'other' value: (PBObject withAll: { 'x' -> 1 }).
tx commit.
tx := db newTransaction.
c that: 'a refusal leaves the transaction usable'
  is: rows , { (tx getRootObject: 'l') count. (tx getRootObject: 'other') at: 'x' }
  equals: { true. true. 1. 1 }.
space close.
base deleteAll.

c report displayNl.
