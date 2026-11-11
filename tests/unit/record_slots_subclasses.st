"EXPECT: ok 22"
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

PBKeyNode subclass: #BadIntegerNode.
BadIntegerNode class >> typeName
  ^ 'slotstest.BadIntegerNode'.
BadIntegerNode class >> integerFields
  ^ #('height' 'count' 'rank').

| c root keys sink stub node older bad tree walked |
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
c report displayNl.
