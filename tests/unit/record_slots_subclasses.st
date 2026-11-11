"EXPECT: ok 49"
"Plan Task 16b, fix round 1 (review I1, M2): an application subclass of a node class gets its
 own record shape, derived from its declarations when it is registered. A subclass that
 reorders its persistedFields keeps the slot layout of the accessors it inherits; the AVL
 writes build its nodes in its own record order and every walk reads them (check: accepts
 the three built-in node classes only, as ProtoBase's check_invariants). A subclass with a
 later field keeps the inherited slots and adds its own; the writes leave that field absent
 (as in a record written before it existed), and an integer field that is not required may
 be absent (nil) in an older record, while a present one must be an Integer. A subclass whose
 declared slot layout does not start with its superclass's, or whose integer field is not a
 field, is refused when it is registered."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_sink'.

PBKeyNode subclass: #ReorderedNode.
ReorderedNode class >> typeName
  ^ 'slotstest.ReorderedNode'.
ReorderedNode class >> persistedFields
  ^ #('left' 'right' 'key' 'value' 'height' 'count').

PBKeyNode subclass: #ExtendedNode.
ExtendedNode class >> typeName
  ^ 'slotstest.ExtendedNode'.
ExtendedNode class >> persistedFields
  ^ #('key' 'value' 'left' 'right' 'height' 'count' 'priority').
ExtendedNode class >> slotFields
  ^ ExtendedNode persistedFields.
ExtendedNode class >> integerFields
  ^ #('height' 'count' 'priority').
ExtendedNode >> priority
  ^ self _slotAt: 7.

PBKeyNode subclass: #BadLayoutNode.
BadLayoutNode class >> typeName
  ^ 'slotstest.BadLayoutNode'.
BadLayoutNode class >> slotFields
  ^ #('left' 'key' 'value' 'right' 'height' 'count').

PBKeyNode subclass: #DuplicateFieldNode.
DuplicateFieldNode class >> typeName
  ^ 'slotstest.DuplicateFieldNode'.
DuplicateFieldNode class >> persistedFields
  ^ #('key' 'value' 'left' 'right' 'height' 'count' 'key').

PBPosNode subclass: #PositionalNode.
PositionalNode class >> typeName
  ^ 'slotstest.PositionalNode'.

PBPosNode subclass: #InMemoryPositionalNode.
InMemoryPositionalNode class >> typeName
  ^ 'slotstest.InMemoryPositionalNode'.

PBKeyNode subclass: #BadIntegerNode.
BadIntegerNode class >> typeName
  ^ 'slotstest.BadIntegerNode'.
BadIntegerNode class >> integerFields
  ^ #('height' 'count' 'rank').

| c root keys sink stub node older bad tree walked seed prios put pos classes |
c := Check new.
PBTypeRegistry register: ReorderedNode; register: ExtendedNode.

"A reordered subclass: the writes, the walks and check: work on its nodes."
root := nil.
#(5 3 8 1 4 7 9 2 6 10) do: [:k | root := (PBAvl keyPut: root key: k value: k * 10 nodeClass: ReorderedNode) first].
c that: 'reordered: the root is of the subclass' is: root class equals: ReorderedNode.
c that: 'reordered: check: accepts the built-in kinds only, as ProtoBase''s check_invariants' signals: PBCorruptionError
  containing: 'not an AVL node' during: [PBAvl check: root].
c that: 'reordered: keyAt: reads through the inherited accessors' is: (PBAvl keyAt: root key: 7) value equals: 70.
c that: 'reordered: the record order is its own' is: root state keys equals: ReorderedNode persistedFields.
c that: 'reordered: count' is: root count equals: 10.
sink := SegmentSink segment: (ByteArray fromHex: '16c016c016c016c016c016c016c016c0').
root _saveInto: sink.
stub := root unloadedCopy.
walked := OrderedCollection new.
PBAvl keysAndValuesDo: [:k :v | walked add: k -> v] over: stub.
c that: 'reordered: a loaded tree walks in order' is: (walked collect: [:a | a key]) asArray equals: (1 to: 10) asArray.
c that: 'reordered: and its values' is: (walked collect: [:a | a value]) asArray equals: ((1 to: 10) asArray collect: [:k | k * 10]).
c that: 'reordered: a loaded record shares its class keys' isTrue: (stub state _hasKeys: ReorderedNode _recordShape persisted).
c that: 'reordered: nodesDo: visits every node' is: ([:r | | n | n := 0. PBAvl nodesDo: [:x | n := n + 1] over: r. n] value: stub) equals: 10.

"An extended subclass: the writes leave its later field absent."
root := nil.
1 to: 8 do: [:k | root := (PBAvl keyPut: root key: k value: k nodeClass: ExtendedNode) first].
c that: 'extended: count' is: root count equals: 8.
c that: 'extended: a written node has no priority' is: root priority equals: nil.
c that: 'extended: nor the field in its record' isTrue: (root state includesKey: 'priority') not.
c that: 'extended: keyAt:' is: (PBAvl keyAt: root key: 6) value equals: 6.

"Fix round 2 (review R2-I1): a write that copies a node carries the fields it does not know,
 past the built-in layout, into the copy: a path copy on insert, the replaced node, all four
 rotations and a removal keep each copied node's priority; only the nodes the write creates lack
 it."
seed := [:k :l :r | ExtendedNode _unsavedWithSlots:
  ((ExtendedNode _fieldsKey: k value: k left: l right: r) copyWith: k * 100)].
prios := [:r | | out | out := OrderedCollection new.
  PBAvl nodesDo: [:x | out add: { x key. x priority }] over: r. out asArray].
put := [:r :k | (PBAvl keyPut: r key: k value: k nodeClass: ExtendedNode) first].
root := put value: (seed value: 3 value: (seed value: 2 value: nil value: nil) value: nil) value: 1.
c that: 'right rotation: the left child rises' is: root key equals: 2.
c that: 'right rotation: the copied nodes keep their priority' is: (prios value: root) equals: { {1. nil}. {2. 200}. {3. 300} }.
root := put value: (seed value: 1 value: nil value: (seed value: 2 value: nil value: nil)) value: 3.
c that: 'left rotation: the right child rises' is: root key equals: 2.
c that: 'left rotation: the copied nodes keep their priority' is: (prios value: root) equals: { {1. 100}. {2. 200}. {3. nil} }.
root := put value: (seed value: 3 value: (seed value: 1 value: nil value: nil) value: nil) value: 2.
c that: 'left-right rotation: the new node rises' is: root key equals: 2.
c that: 'left-right rotation: the copied nodes keep their priority' is: (prios value: root) equals: { {1. 100}. {2. nil}. {3. 300} }.
root := put value: (seed value: 1 value: nil value: (seed value: 3 value: nil value: nil)) value: 2.
c that: 'right-left rotation: the new node rises' is: root key equals: 2.
c that: 'right-left rotation: the copied nodes keep their priority' is: (prios value: root) equals: { {1. 100}. {2. nil}. {3. 300} }.
tree := seed value: 2 value: (seed value: 1 value: nil value: nil) value: (seed value: 3 value: nil value: nil).
root := put value: tree value: 4.
c that: 'insert: the path copies keep their priority' is: (prios value: root) equals: { {1. 100}. {2. 200}. {3. 300}. {4. nil} }.
root := (PBAvl keyPut: tree key: 1 value: 99 nodeClass: ExtendedNode) first.
c that: 'replace: the new value is stored' is: (PBAvl keyAt: root key: 1) value equals: 99.
c that: 'replace: the replaced node and its path keep their priority' is: (prios value: root) equals: { {1. 100}. {2. 200}. {3. 300} }.
root := (PBAvl keyRemove: tree key: 2) first.
c that: 'remove: the remaining nodes keep their priority' is: (prios value: root) equals: { {1. 100}. {3. 300} }.
root := (PBAvl keyRemove: tree key: 1) first.
c that: 'remove of a leaf: the copied root keeps its priority' is: (prios value: root) equals: { {2. 200}. {3. 300} }.
c that: 'and the copies are still of the subclass' is: root class equals: ExtendedNode.
root _saveInto: sink.
c that: 'a saved copy reads its carried priority back' is: root unloadedCopy priority equals: 200.

"M2: an older record without the optional integer field loads; a present one is checked."
older := ExtendedNode _unsavedWithState: (PBFrozenDict withAssociations: {
  'key' -> 1. 'value' -> 2. 'left' -> nil. 'right' -> nil. 'height' -> 1. 'count' -> 1 }).
older _saveInto: sink.
stub := older unloadedCopy.
c that: 'an older record reads its key' is: stub key equals: 1.
c that: 'and its optional integer field as nil' is: stub priority equals: nil.
node := ExtendedNode _unsavedWithState: (PBFrozenDict withAssociations: {
  'key' -> 1. 'value' -> 2. 'left' -> nil. 'right' -> nil. 'height' -> 1. 'count' -> 1. 'priority' -> 5 }).
node _saveInto: sink.
c that: 'a present optional integer field reads back' is: node unloadedCopy priority equals: 5.
c that: 'an optional integer field that is not an Integer' signals: PBCorruptionError containing: 'the priority of' during: [
  ExtendedNode _unsavedWithState: (PBFrozenDict withAssociations: {
    'key' -> 1. 'value' -> 2. 'left' -> nil. 'right' -> nil. 'height' -> 1. 'count' -> 1. 'priority' -> 'high' })].
bad := SegmentSink segment: (ByteArray fromHex: '16c116c116c116c116c116c116c116c1').
stub := ExtendedNode unloadedAt: (bad pushAtom: (PBAtomEnvelope tag: 'slotstest.ExtendedNode'
  oid: (ByteArray fromHex: '07070707070707070707070707070707')
  state: (PBFrozenDict withAssociations: { 'key' -> 1. 'value' -> 2. 'left' -> nil. 'right' -> nil.
    'height' -> 1. 'count' -> 1. 'priority' -> true })))
  storage: bad.
c that: 'a loaded Boolean optional integer field' signals: PBCorruptionError containing: 'the priority of' during: [stub key].
c that: 'a required integer field may not be absent' signals: PBCorruptionError containing: 'the height of' during: [
  PBPosNode _unsavedWithState: (PBFrozenDict withAssociations: { 'value' -> 1. 'left' -> nil. 'right' -> nil. 'count' -> 1 })].

"Refused at registration."
c that: 'a slot layout that does not extend the superclass''s' signals: PBUserError containing: 'slotFields' during: [
  PBTypeRegistry register: BadLayoutNode].
c that: 'and the class is not registered' isTrue: (PBTypeRegistry isRegistered: 'slotstest.BadLayoutNode') not.
c that: 'an integer field that is not a field' signals: PBUserError containing: 'rank' during: [
  PBTypeRegistry register: BadIntegerNode].
c that: 'persistedFields that name a field twice (review R2-M1)' signals: PBUserError containing: 'name a field twice' during: [
  PBTypeRegistry register: DuplicateFieldNode].
c that: 'and that class is not registered' isTrue: (PBTypeRegistry isRegistered: 'slotstest.DuplicateFieldNode') not.

"Fix round 3 (review R3-I1): positional trees are not subclassable, as ProtoBase's PosNode
 (whose writes all build PosNode). A subclass is refused when it is registered, and an
 unregistered one is refused when it is built or given to a positional operation, rather than
 degraded into a tree of mixed classes. The writes build plain PBPosNodes."
c that: 'a positional subclass is refused at registration' signals: PBUserError
  containing: 'positional trees are not subclassable' during: [PBTypeRegistry register: PositionalNode].
c that: 'and it is not registered' isTrue: (PBTypeRegistry isRegistered: 'slotstest.PositionalNode') not.
c that: 'an unregistered positional subclass is not built' signals: PBNotSupportedError
  containing: 'positional trees are not subclassable' during: [InMemoryPositionalNode value: 1 left: nil right: nil].
stub := InMemoryPositionalNode unloadedAt: (bad pushAtom: (PBAtomEnvelope tag: PBPosNode typeName
  oid: (ByteArray fromHex: '08080808080808080808080808080808')
  state: (PBFrozenDict withAssociations: { 'value' -> 1. 'left' -> nil. 'right' -> nil. 'height' -> 1. 'count' -> 1 })))
  storage: bad.
c that: 'posAppend: refuses a positional subclass root' signals: PBNotSupportedError
  containing: 'InMemoryPositionalNode: positional trees are not subclassable' during: [PBAvl posAppend: stub value: 2].
c that: 'posAt: refuses it too' signals: PBNotSupportedError
  containing: 'positional trees are not subclassable' during: [PBAvl posAt: stub index: 0].
c that: 'posSet: refuses it too' signals: PBNotSupportedError
  containing: 'positional trees are not subclassable' during: [PBAvl posSet: stub at: 0 value: 3].
c that: 'posConcat: refuses it on either side' signals: PBNotSupportedError
  containing: 'positional trees are not subclassable' during: [PBAvl posConcat: nil with: stub].
pos := nil.
1 to: 12 do: [:i | pos := PBAvl posAppend: pos value: i].
pos := PBAvl posSet: pos at: 3 value: 40.
pos := PBAvl posRemove: pos at: 5.
classes := Set new.
PBAvl nodesDo: [:x | classes add: x class] over: pos.
c that: 'positional writes build plain PBPosNodes' is: classes asArray equals: { PBPosNode }.
c that: 'and keep the values' is: ([:r | | out | out := OrderedCollection new. PBAvl posDo: [:v | out add: v] over: r. out asArray] value: pos)
  equals: #(1 2 3 40 5 7 8 9 10 11 12).
c that: 'and the tree checks' is: (PBAvl check: pos) equals: pos.
c report displayNl.
