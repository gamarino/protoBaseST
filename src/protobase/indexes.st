"-- indexes.st: the indexes of format 4, decoded, kept and written --

ProtoBase's indexes (format spec v2.0.0rc1, 'Indexes', 'Key-group indexes',
'Vector indexes'; ProtoBase proto_db/indexing/*.py at the tag). The equality
and range indexes are written as proto_db writes them (indexed queries, plan
Task 3: a port of base.py's Index and keyed.py's KeyGroupIndex): every hook
answers a new, unsaved index version and never changes its receiver, and the
trees it builds are node-identical to proto_db's for the same operations. The
vector index is read only (design spec 3.3, ruling IQ5): each of its hooks is
PBNotSupportedError naming it.

  PBIndex           proto_db.indexing.Index (abstract): name, key_spec
  PBKeyGroupIndex   proto_db.indexing.keyed.KeyGroupIndex (abstract): groups,
                    side, total_count, member_tokens
  PBEqualityIndex   proto_db.indexing.EqualityIndex
  PBRangeIndex      proto_db.indexing.RangeIndex
  PBVectorIndex     proto_db.indexing.VectorIndex: dim, metric, backend, params,
                    store, invalid, total_count, centroids, trained_size,
                    member_tokens

The definition and its reads:

  PBEqualityIndex name: n keySpec: aPBKeySpec
                     an empty unsaved index (plan call CR3: a PBKeySpec only);
                     PBRangeIndex the same
  PBEqualityIndex name: n path: 'a.b'
                     the convenience, name: n keySpec: (PBKeySpec path: 'a.b')
  name               the index name
  keySpec            the persisted (kind, arg) tuple, as in 0.1.0 (plan call IP3)
  keySpecObject      the same as a PBKeySpec (PBKeySpec fromData:), parsed once
                     per version; a malformed tuple is PBValidationError naming
                     the index, when asked, never at read
  hasMemberTokens    whether member_tokens is 1: the member keys hold format-4
                     exact tokens. Absent (format 3) or another value: false, and a
                     writer must rebuild the index before changing it (ProtoBase
                     has_current_tokens, which compares member_tokens == 1)

The hooks (base.py Index, keyed.py KeyGroupIndex), each answering a new index:

  withAdded: e, withRemoved: e, withReplaced: old with: new
                     one occurrence more, fewer (an occurrence the index does not
                     hold is PBValidationError), replaced (remove, then add)
  empty              an empty index of the same definition
  build: aCollection an index over exactly the elements of aCollection (anything
                     answering do:), the receiver's content never kept; a
                     key-group index builds it in bulk (group, sort, balanced
                     trees: keyed.py build), node-identical to the fold of
                     withAdded: from empty
  explain            a PBFrozenDict: index, kind (proto_db's class name,
                     'EqualityIndex', plan call CR4), key; a key-group index adds
                     entries, keys, unorderable
  validate: aCollection
                     the structural checks of keyed.py validate against the
                     elements: PBCorruptionError, or PBMisfiledError for an entry
                     its own key does not place

A key-group index files each element under the key its key spec extracts:
groups is a PBCountedKeyNode tree from key to group (PBKeyGroups, keygroups.st),
side the group of every element whose key is unorderable. Its reads:
groupCount, count, countOfKey: aKey, membersDo: [:element :count] (groups in
key order, the side group last).

PBVectorIndex also answers centroids, trainedSize and storeEntries (the store
tree's key -> (element, count, vector) Associations, in key order: the list
number of a member is its key's first item)."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/registry'.
Import from: 'protobase/keys'.
Import from: 'protobase/codec'.
Import from: 'protobase/keyspec'.
Import from: 'protobase/avl'.
Import from: 'protobase/keygroups'.

"=== PBIndex ================================================================="

"keySpecCell holds the PBKeySpec of the persisted key_spec once it is asked for
 (keySpecObject): published by compare-and-swap, and carried into each version a
 hook derives (_with:)."
PBAtom subclass: #PBIndex instanceVariableNames: 'keySpecCell'.

PBIndex class >> typeName
  ^ 'proto_db.indexing.Index'.

PBIndex class >> requiredFields
  ^ #('name' 'key_spec').

PBIndex class >> persistedFields
  ^ #('name' 'key_spec').

"The name proto_db gives this kind in explain and in its messages (type(self).__name__,
 plan call CR4): the last part of the type name, 'EqualityIndex' for
 'proto_db.indexing.EqualityIndex'."
PBIndex class >> kindName
  | name |
  name := self typeName.
  name isNil ifTrue: [^ self name].
  ^ (name subStrings: '.') last.

"Whether the class is abstract, as proto_db's Index and KeyGroupIndex are (they lack hooks): it
 makes no index."
PBIndex class >> isAbstract
  ^ self == PBIndex or: [self == PBKeyGroupIndex].

"An empty unsaved index named aString on aPBKeySpec (base.py Index.__init__ and the subclass's
 constructor): a non-empty String name with no lone surrogate, and a PBKeySpec (plan call CR3:
 anything else, a String included, is PBValidationError). The fields are set in proto_db's
 constructor order, persistedFields."
PBIndex class >> name: aString keySpec: aPBKeySpec
  self isAbstract ifTrue: [
    ^ PBUserError signal: self name , ' is abstract: make a PBEqualityIndex or a PBRangeIndex'].
  ((aString isString and: [aString isSymbol not]) and: [aString notEmpty]) ifFalse: [
    ^ PBValidationError signal: 'An index needs a non-empty String name, not ' , (PBKeySpec _repr: aString)].
  PBCodec _checkUTF8: aString.
  (aPBKeySpec isClassObject not and: [aPBKeySpec isKindOf: PBKeySpec]) ifFalse: [
    ^ PBValidationError signal: 'key_spec must be a PBKeySpec, not a ' , aPBKeySpec class name].
  ^ (self _unsavedWithState: (PBFrozenDict withAssociations: (self _emptyFieldsName: aString keySpec: aPBKeySpec)))
    _publishKeySpec: aPBKeySpec.

"The convenience for a single path: name: aString keySpec: (PBKeySpec path: aPath)."
PBIndex class >> name: aString path: aPath
  ^ self name: aString keySpec: (PBKeySpec path: aPath).

"The fields of an empty index, in persistedFields order."
PBIndex class >> _emptyFieldsName: aString keySpec: aPBKeySpec
  ^ { 'name' -> aString. 'key_spec' -> aPBKeySpec asData }.

PBIndex >> _setOid: anOid pointer: aPointer storage: aStorage
  "Runs once, on a fresh instance (every constructor of an atom calls it)."
  super _setOid: anOid pointer: aPointer storage: aStorage.
  keySpecCell := Atom on: nil.
  ^ self.

"Installs aPBKeySpec as this version's key spec object, unless one is installed (nil installs
 nothing); answers the index."
PBIndex >> _publishKeySpec: aPBKeySpec
  aPBKeySpec isNil ifFalse: [keySpecCell value: aPBKeySpec ifCurrent: nil].
  ^ self.

"The index name."
PBIndex >> name
  ^ self stateAt: 'name'.

"The persisted key spec, a (kind, arg) tuple: ('path', 'a.b'), ('element',
 nil) or ('extractor', name)."
PBIndex >> keySpec
  ^ self stateAt: 'key_spec'.

"The key spec as a PBKeySpec (plan call IP3), parsed once per version: a malformed tuple is
 PBValidationError naming the index (PBKeySpec fromData:'s PBCorruptionError, converted), when
 asked, never when the index is read."
PBIndex >> keySpecObject
  | spec data problem |
  spec := keySpecCell value.
  spec isNil ifFalse: [^ spec].
  data := self keySpec.
  problem := nil.
  spec := [PBKeySpec fromData: data] on: PBCorruptionError do: [:e | problem := e messageText. e return: nil].
  problem isNil ifFalse: [
    ^ PBValidationError signal: 'Index ' , (PBKeySpec _repr: self name) , ' (' , self class kindName
      , ') has a key spec this process cannot use: ' , problem].
  self _publishKeySpec: spec.
  ^ keySpecCell value.

"How proto_db's messages name the index: Index 'n' (EqualityIndex on a.b)."
PBIndex >> _subject
  ^ 'Index ' , (PBKeySpec _repr: self name) , ' (' , self class kindName , ' on ' , self keySpecObject describe , ')'.

"Whether member_tokens == 1 as ProtoBase compares it (keyed.py, vector.py):
 true, 1, 1.0 and any Decimal equal to 1 (Decimal 1, 1.00) count; a NaN
 never does."
PBIndex >> hasMemberTokens
  | v |
  v := self stateAt: 'member_tokens'.
  v == true ifTrue: [^ true].
  (v isKindOf: Decimal) ifTrue: [^ v isNaN not and: [v = 1]].
  ^ v isNumber and: [v = 1].

PBIndex >> totalCount
  ^ _PBTree integer: (self stateAt: 'total_count') field: 'total_count' of: self.

"A new unsaved index of this class (base.py Index._with): the receiver's persisted state, in its
 order, with the fields aFields names (an Array of Associations, or a PBFrozenDict) changed. A
 field the receiver does not hold is PBValidationError. The receiver never changes."
PBIndex >> _with: aFields
  | changes state names values unknown |
  changes := (aFields isKindOf: PBFrozenDict) ifTrue: [aFields associations] ifFalse: [aFields].
  state := self state.
  unknown := (changes reject: [:each | state includesKey: each key]) collect: [:each | each key].
  unknown isEmpty ifFalse: [
    ^ PBValidationError signal: self class name , ' _with: got unknown fields '
      , (unknown asArray sort: [:a :b | a <= b]) printString].
  names := state keys.
  values := names collect: [:f |
    | change |
    change := changes detect: [:each | each key = f] ifNone: [nil].
    change isNil ifTrue: [state at: f] ifFalse: [change value]].
  "The parsed key spec is carried over unless the change replaces it."
  ^ (self class _unsavedWithState: (state _withValues: values))
    _publishKeySpec: ((changes anySatisfy: [:each | each key = 'key_spec']) ifTrue: [nil] ifFalse: [keySpecCell value]).

"--- hooks (base.py Index) ---"

PBIndex >> _subclassResponsibility: aSelector
  ^ PBUserError signal: self class name , ' must implement ' , aSelector , ': an index kind implements every hook'.

"The index after one more occurrence of anElement."
PBIndex >> withAdded: anElement
  ^ self _subclassResponsibility: 'withAdded:'.

"The index after one occurrence of anElement fewer (one it holds)."
PBIndex >> withRemoved: anElement
  ^ self _subclassResponsibility: 'withRemoved:'.

"Checks the index against the elements of aCollection: PBCorruptionError on a mismatch."
PBIndex >> validate: aCollection
  ^ self _subclassResponsibility: 'validate:'.

"The index after replacing one occurrence of anOld by aNew (base.py with_replaced: remove, then
 add)."
PBIndex >> withReplaced: anOld with: aNew
  ^ (self withRemoved: anOld) withAdded: aNew.

"An empty index of the same definition (base.py empty)."
PBIndex >> empty
  ^ self class name: self name keySpec: self keySpecObject.

"An index over exactly the elements of aCollection (anything answering do:): a fold of withAdded:
 from empty (base.py build). The receiver's content is never kept."
PBIndex >> build: aCollection
  | index |
  index := self empty.
  aCollection do: [:each | index := index withAdded: each].
  ^ index.

"index, kind (proto_db's class name, plan call CR4) and key, a PBFrozenDict (base.py explain)."
PBIndex >> explain
  ^ PBFrozenDict withAssociations: self _explained.

PBIndex >> _explained
  ^ { 'index' -> self name. 'kind' -> self class kindName. 'key' -> self keySpecObject describe }.

"=== PBKeyGroupIndex (keyed.py KeyGroupIndex) ================================="

PBIndex subclass: #PBKeyGroupIndex.

PBKeyGroupIndex class >> typeName
  ^ 'proto_db.indexing.keyed.KeyGroupIndex'.

PBKeyGroupIndex class >> requiredFields
  ^ #('name' 'key_spec' 'groups' 'side' 'total_count').

PBKeyGroupIndex class >> persistedFields
  ^ #('name' 'key_spec' 'groups' 'side' 'total_count' 'member_tokens').

"keyed.py MEMBER_TOKENS: the member-token scheme of format 4 (D58)."
PBKeyGroupIndex class >> memberTokens
  ^ 1.

"keyed.py KeyGroupIndex.__init__: no groups, an empty side group, no occurrences, current
 tokens."
PBKeyGroupIndex class >> _emptyFieldsName: aString keySpec: aPBKeySpec
  ^ (super _emptyFieldsName: aString keySpec: aPBKeySpec) , {
    'groups' -> nil. 'side' -> PBKeyGroups empty. 'total_count' -> 0. 'member_tokens' -> self memberTokens }.

"The key tree: nil or a PBCountedKeyNode tree (a PBKeyNode tree in an index written before
 weights) from key to group."
PBKeyGroupIndex >> groups
  ^ _PBTree node: (self stateAt: 'groups') kind: PBKeyNode in: self.

"The group of the elements whose key is unorderable, the PBTuple (members, total)."
PBKeyGroupIndex >> side
  ^ self stateAt: 'side'.

"The stored occurrences."
PBKeyGroupIndex >> count
  ^ self totalCount.

"The number of key groups (distinct orderable keys)."
PBKeyGroupIndex >> groupCount
  ^ _PBTree count: (self stateAt: 'groups') kind: PBKeyNode in: self.

"The occurrences filed under the orderable key aKey (1, 1.0 and Decimal 1 are one key); 0 when
 there are none. An unorderable key has no group of its own (every one is in the side group,
 explain's 'unorderable'): PBValidationError."
PBKeyGroupIndex >> countOfKey: aKey
  | node |
  (PBMemberKeys orderKeyOrNil: aKey) isNil ifTrue: [
    ^ PBValidationError signal: self _subject , ' countOfKey: ' , (PBKeys _preview: aKey)
      , ' is unorderable: unorderable keys have no group of their own (explain''s unorderable counts them)'].
  node := PBAvl keyAt: self groups key: aKey.
  ^ node isNil ifTrue: [0] ifFalse: [node value at: 2].

"Evaluates aBlock with each stored element and its count: the groups in key order, each in member
 order, then the side group (the order of keyed.py's ordered plan, ascending)."
PBKeyGroupIndex >> membersDo: aBlock
  PBAvl keysAndValuesDo: [:key :group | PBKeyGroups group: group do: aBlock] over: self groups.
  PBKeyGroups group: self side do: aBlock.

"--- element hooks (keyed.py 404-457) ---"

"The index after one more occurrence of anElement, filed under its key (PBMissing included);
 an unorderable key files it in the side group. An element whose member key would nest too deep
 is PBValidationError naming the index (check_member_key)."
PBKeyGroupIndex >> withAdded: anElement
  | member key groups node group |
  member := PBMemberKeys memberKeyOf: anElement.
  PBMemberKeys checkDepth: anElement memberKey: member index: self.
  key := self keySpecObject extract: anElement.
  (PBMemberKeys orderKeyOrNil: key) isNil ifTrue: [
    ^ self _with: {
      'side' -> (PBKeyGroups group: self side with: anElement memberKey: member).
      'total_count' -> (self totalCount + 1) }].
  groups := self groups.
  node := PBAvl keyAt: groups key: key.
  group := node isNil ifTrue: [PBKeyGroups empty] ifFalse: [node value].
  groups := (PBAvl keyPut: groups key: key value: (PBKeyGroups group: group with: anElement memberKey: member)
    nodeClass: PBCountedKeyNode) at: 1.
  ^ self _with: { 'groups' -> groups. 'total_count' -> (self totalCount + 1) }.

"The index after one occurrence of anElement fewer: the member whose member key is anElement's
 (never an equal member with another token, D58). An element the index does not hold is
 PBValidationError (keyed.py with_removed)."
PBKeyGroupIndex >> withRemoved: anElement
  | key side groups node group |
  key := self keySpecObject extract: anElement.
  (PBMemberKeys orderKeyOrNil: key) isNil ifTrue: [
    side := PBKeyGroups group: self side without: anElement.
    side isNil ifTrue: [^ self _notHeld: anElement key: key].
    ^ self _with: { 'side' -> side. 'total_count' -> (self totalCount - 1) }].
  groups := self groups.
  node := PBAvl keyAt: groups key: key.
  group := node isNil ifTrue: [nil] ifFalse: [PBKeyGroups group: node value without: anElement].
  group isNil ifTrue: [^ self _notHeld: anElement key: key].
  groups := (group at: 2) = 0
    ifTrue: [(PBAvl keyRemove: groups key: key) at: 1]
    ifFalse: [(PBAvl keyPut: groups key: key value: group nodeClass: PBCountedKeyNode) at: 1].
  ^ self _with: { 'groups' -> groups. 'total_count' -> (self totalCount - 1) }.

PBKeyGroupIndex >> _notHeld: anElement key: aKey
  ^ PBValidationError signal: self _subject , ' does not hold ' , (PBKeys _preview: anElement) , ' under the key '
    , (PBKeys _preview: aKey) , '; an index can only remove an element it holds'.

"An index over exactly the elements of aCollection (anything answering do:), built in bulk
 (keyed.py build, ruling R10): the elements are grouped by the order key of their key and, in
 each group, by the order key of their member key, then each tree is built balanced from the
 sorted entries (PBAvl keyFromSortedOrderKeys:nodeClass:), the algorithm of proto_db's build. The
 trees hold, in key order, the keys, members and counts of the fold of withAdded: from empty (only
 their shapes differ: balanced against insertion order); a group keeps the first key it met, as
 keyPut: keeps the stored key. O(n log n); the receiver's content is never kept. The builders are
 local mutable Dictionaries, never stored."
PBKeyGroupIndex >> build: aCollection
  | spec builders order side total groups entries |
  spec := self keySpecObject.
  builders := Dictionary new.
  order := OrderedCollection new.
  side := self _newBuilder: nil orderKey: nil.
  total := 0.
  aCollection do: [:element |
    | key okey builder |
    total := total + 1.
    key := spec extract: element.
    okey := PBMemberKeys orderKeyOrNil: key.
    builder := okey isNil
      ifTrue: [side]
      ifFalse: [builders at: okey ifAbsent: [
        | fresh |
        fresh := self _newBuilder: key orderKey: okey.
        builders at: okey put: fresh.
        order addLast: fresh.
        fresh]].
    self _builder: builder add: element].
  entries := (order asArray sort: [:a :b | (a at: 2) <= (b at: 2)]) collect: [:b |
    { b at: 2. b at: 1. self _groupOfBuilder: b }].
  groups := PBAvl keyFromSortedOrderKeys: entries nodeClass: PBCountedKeyNode.
  ^ self empty _with: { 'groups' -> groups. 'side' -> (self _groupOfBuilder: side). 'total_count' -> total }.

"A group under construction (keyed.py _GroupBuilder): { key. order key. members by member order
 key. total }, an Array local to one build."
PBKeyGroupIndex >> _newBuilder: aKey orderKey: anOrderKey
  ^ { aKey. anOrderKey. Dictionary new. 0 }.

PBKeyGroupIndex >> _builder: aBuilder add: anElement
  | member mokey members slot |
  aBuilder at: 4 put: (aBuilder at: 4) + 1.
  member := PBMemberKeys memberKeyOf: anElement.
  PBMemberKeys checkDepth: anElement memberKey: member index: self.
  mokey := PBKeys orderKey: member.
  members := aBuilder at: 3.
  slot := members at: mokey ifAbsent: [nil].
  slot isNil
    ifTrue: [members at: mokey put: { mokey. member. anElement. 1 }]
    ifFalse: [slot at: 4 put: (slot at: 4) + 1].

PBKeyGroupIndex >> _groupOfBuilder: aBuilder
  ^ PBKeyGroups sortedMembers: (aBuilder at: 3) values total: (aBuilder at: 4).

"--- explain and validate (keyed.py 651-737) ---"

"The base entries plus entries (occurrences), keys (distinct orderable keys) and unorderable
 (occurrences whose key is unorderable)."
PBKeyGroupIndex >> _explained
  ^ super _explained , {
    'entries' -> self totalCount. 'keys' -> self groupCount. 'unorderable' -> (self side at: 2) }.

PBKeyGroupIndex >> _corrupt: aString
  ^ PBCorruptionError signal: self _subject , ' is corrupt: ' , aString.

PBKeyGroupIndex >> _misfiled: aString
  ^ PBMisfiledError signal: self _subject , ' holds a misfiled entry: ' , aString
    , '. Format 3 wrote built-in subclasses (a (str, Enum) member) through their own conversion but filed them '
    , 'by their base value (D58); the collection must be rebuilt from its elements (proto_db''s '
    , 'collection.rebuilt(), which protoBaseST does not offer: docs/not-done.md)'.

"Where a key files an element (keyed.py _slot): (0, key) for an orderable key, (1) for an
 unorderable one; two slots are one when their order keys are equal."
PBKeyGroupIndex >> _slot: aKey
  (PBMemberKeys orderKeyOrNil: aKey) isNil ifTrue: [^ PBTuple withAll: #(1)].
  ^ PBTuple withAll: { 0. aKey }.

"Whether aKey is the member key of anElement (keyed.py member_key_matches): the whole key on an
 index with current tokens; on one written by format 3 everything but the token, which is only
 checked to be a tuple."
PBKeyGroupIndex >> _memberKey: aKey matches: anElement current: aBoolean
  ((aKey isKindOf: PBTuple) and: [aKey size = 2]) ifFalse: [^ false].
  aBoolean ifTrue: [^ (PBKeys orderKey: aKey) = (PBKeys orderKey: (PBMemberKeys memberKeyOf: anElement))].
  ^ ((aKey at: 2) isKindOf: PBTuple)
    and: [(PBKeys orderKey: (aKey at: 1)) = (PBKeys orderKey: (PBMemberKeys _equalityPart: anElement))].

"The occurrences of aGroup filed under aSlot, counted into aStored (keyed.py _check_group)."
PBKeyGroupIndex >> _checkGroup: aGroup slot: aSlot into: aStored
  | current members total seen entries spec slotKey |
  ((aGroup isKindOf: PBTuple) and: [aGroup size = 2]) ifFalse: [
    ^ self _corrupt: 'malformed group ' , (PBKeys _preview: aGroup)].
  current := self hasMemberTokens.
  members := aGroup at: 1.
  total := aGroup at: 2.
  PBAvl check: members.
  seen := 0.
  entries := OrderedCollection new.
  PBAvl keysAndValuesDo: [:key :entry |
    ((entry isKindOf: PBTuple) and: [entry size = 2]) ifFalse: [
      ^ self _corrupt: 'malformed entry ' , (PBKeys _preview: entry)].
    (self _memberKey: key matches: (entry at: 1) current: current) ifFalse: [
      ^ self _corrupt: 'element ' , (PBKeys _preview: (entry at: 1)) , ' is stored under the wrong member key '
        , (PBKeys _preview: key)].
    entries addLast: entry] over: members.
  spec := self keySpecObject.
  slotKey := PBKeys orderKey: aSlot.
  entries do: [:entry |
    | element n id |
    element := entry at: 1.
    n := entry at: 2.
    ((n isInteger and: [n ~~ true and: [n ~~ false]]) and: [n >= 1]) ifFalse: [
      ^ self _corrupt: 'element ' , (PBKeys _preview: element) , ' has the count ' , (PBKeys _preview: n)].
    (PBKeys orderKey: (self _slot: (spec extract: element))) = slotKey ifFalse: [
      ^ self _misfiled: 'element ' , (PBKeys _preview: element) , ' is filed under another key than its own'].
    id := self _storedIdentity: element slot: aSlot.
    aStored at: id put: (aStored at: id ifAbsent: [0]) + n.
    seen := seen + n].
  total = seen ifFalse: [
    ^ self _corrupt: 'a group records ' , (PBKeys _preview: total) , ' occurrences but holds ' , seen printString].
  ^ seen.

"The identity of an occurrence in the stored multiset: (slot, element identity, exact token),
 one order key, that of (slot, member key)."
PBKeyGroupIndex >> _storedIdentity: anElement slot: aSlot
  ^ PBKeys orderKey: (PBTuple withAll: { aSlot. PBMemberKeys memberKeyOf: anElement }).

"Checks this index against the elements of aCollection (anything answering do:): the key order
 of the key tree (PBMisfiledError for a key stored out of order), the AVL invariants of every
 tree, each stored element under its own key and member key with a positive count, the group and
 index totals, and the stored multiset of (key, element, exact token) against that of the
 elements. On an index written by format 3 (hasMemberTokens false) the member keys' tokens are not
 compared: such an index is stale, not corrupt. Anything else is PBCorruptionError naming the
 index (keyed.py validate). Answers the index."
PBKeyGroupIndex >> validate: aCollection
  | groups previous stored total expected spec extra missing |
  groups := self groups.
  previous := nil.
  PBAvl keysAndValuesDo: [:key :group |
    | okey |
    okey := PBMemberKeys orderKeyOrNil: key.
    (okey notNil and: [previous notNil and: [((previous at: 1) < okey) not]]) ifTrue: [
      ^ self _misfiled: 'the key ' , (PBKeys _preview: key) , ' is stored after ' , (PBKeys _preview: (previous at: 2))
        , ', which its key order places after it'].
    okey isNil ifFalse: [previous := { okey. key }]] over: groups.
  PBAvl check: groups.
  stored := Dictionary new.
  total := 0.
  PBAvl keysAndValuesDo: [:key :group |
    | n |
    (PBMemberKeys orderKeyOrNil: key) isNil ifTrue: [
      ^ self _corrupt: 'unorderable key ' , (PBKeys _preview: key) , ' in the key tree'].
    n := self _checkGroup: group slot: (self _slot: key) into: stored.
    n = 0 ifTrue: [^ self _corrupt: 'empty group under the key ' , (PBKeys _preview: key)].
    total := total + n] over: groups.
  total := total + (self _checkGroup: self side slot: (PBTuple withAll: #(1)) into: stored).
  total = self totalCount ifFalse: [
    ^ self _corrupt: 'total_count is ' , self totalCount printString , ' but ' , total printString
      , ' occurrences are stored'].
  spec := self keySpecObject.
  expected := Dictionary new.
  aCollection do: [:element |
    | id |
    id := self _storedIdentity: element slot: (self _slot: (spec extract: element)).
    expected at: id put: (expected at: id ifAbsent: [0]) + 1].
  extra := 0.
  missing := 0.
  stored keysAndValuesDo: [:id :n | extra := extra + (n - (expected at: id ifAbsent: [0]) max: 0)].
  expected keysAndValuesDo: [:id :n | missing := missing + (n - (stored at: id ifAbsent: [0]) max: 0)].
  (extra = 0 and: [missing = 0]) ifFalse: [
    ^ self _corrupt: extra printString , ' stored occurrences no element accounts for, ' , missing printString
      , ' element occurrences not stored'].
  ^ self.

"=== the concrete key-group indexes ========================================="

PBKeyGroupIndex subclass: #PBEqualityIndex.

PBEqualityIndex class >> typeName
  ^ 'proto_db.indexing.EqualityIndex'.

PBKeyGroupIndex subclass: #PBRangeIndex.

PBRangeIndex class >> typeName
  ^ 'proto_db.indexing.RangeIndex'.

"=== PBVectorIndex (read only: design spec 3.3, ruling IQ5) ================="

PBIndex subclass: #PBVectorIndex.

PBVectorIndex class >> typeName
  ^ 'proto_db.indexing.VectorIndex'.

PBVectorIndex class >> requiredFields
  ^ #('name' 'key_spec' 'dim' 'metric' 'backend' 'params' 'store' 'invalid' 'total_count' 'centroids' 'trained_size').

PBVectorIndex class >> persistedFields
  ^ #('name' 'key_spec' 'dim' 'metric' 'backend' 'params' 'store' 'invalid' 'total_count' 'centroids'
      'trained_size' 'member_tokens').

PBVectorIndex >> dim
  ^ _PBTree integer: (self stateAt: 'dim') field: 'dim' of: self.

PBVectorIndex >> metric
  ^ self stateAt: 'metric'.

PBVectorIndex >> backend
  ^ self stateAt: 'backend'.

PBVectorIndex >> params
  ^ self stateAt: 'params'.

"The trained centroids, a tuple of vectors (empty when untrained)."
PBVectorIndex >> centroids
  ^ self stateAt: 'centroids'.

PBVectorIndex >> trainedSize
  ^ _PBTree integer: (self stateAt: 'trained_size') field: 'trained_size' of: self.

"The store tree's key -> value Associations, in key order: the key is
 (list number, member key), the value (element, count, vector)."
PBVectorIndex >> storeEntries
  | out |
  out := OrderedCollection new.
  _PBTree nodesOf: (self stateAt: 'store') kind: PBKeyNode in: self do: [:node | out add: node key -> node value].
  ^ out asArray.

"--- the refusals: protoBaseST reads a vector index and never writes, builds or validates one ---"

"A vector index is never made here: PBNotSupportedError."
PBVectorIndex class >> name: aString keySpec: aPBKeySpec
  ^ PBNotSupportedError signal: 'PBVectorIndex name:keySpec:: protoBaseST reads vector indexes but never makes, '
    , 'writes, rebuilds or validates them (design spec 3.3, ruling IQ5)'.

PBVectorIndex >> _refuse: aSelector
  ^ PBNotSupportedError signal: self _subject , ' ' , aSelector , ': protoBaseST reads vector indexes but never '
    , 'writes, rebuilds or validates them; a collection holding one is read only (design spec 3.3, ruling IQ5)'.

PBVectorIndex >> withAdded: anElement
  ^ self _refuse: 'withAdded:'.

PBVectorIndex >> withRemoved: anElement
  ^ self _refuse: 'withRemoved:'.

PBVectorIndex >> withReplaced: anOld with: aNew
  ^ self _refuse: 'withReplaced:with:'.

PBVectorIndex >> empty
  ^ self _refuse: 'empty'.

PBVectorIndex >> build: aCollection
  ^ self _refuse: 'build:'.

PBVectorIndex >> validate: aCollection
  ^ self _refuse: 'validate:'.

"proto_db's VectorIndex.explain adds its training state, which protoBaseST does not compute."
PBVectorIndex >> explain
  ^ self _refuse: 'explain'.

{ PBIndex. PBKeyGroupIndex. PBEqualityIndex. PBRangeIndex. PBVectorIndex } do: [:each | PBTypeRegistry register: each].
