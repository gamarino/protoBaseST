"-- avl.st: the persistent AVL nodes of format 4, read side --

The trees under every collection (format spec v2.0.0rc1, 'AVL nodes';
ProtoBase proto_db/collections/avl.py at the tag):

  PBNode            proto_db.avl._Node (abstract): left, right, height, count
  PBPosNode         proto_db.avl.PosNode: a positional tree (PBList); value
  PBKeyNode         proto_db.avl.KeyNode: a keyed tree ordered by the order key
                    of key (PBKeys); key, value
  PBCountedKeyNode  proto_db.avl.CountedKeyNode: a KeyNode whose value is a
                    (payload, count) pair, plus weight (the key-group indexes)
  PBValueBox        proto_db.avl.ValueBox: one large node value (a string of at
                    least 256 code points, bytes of at least 256 bytes), D51

A node's value reads unboxed: a node value that is a reference to a
PBValueBox answers the box's value (value), and storedValue answers what the
record holds. Boxes appear only as node values.

The walks are _PBTree's class methods. They never recurse: an in-order walk
keeps an explicit stack, and a lookup descends one path, as ProtoBase's
pos_get, key_get and _inorder do. A tree is nil (empty) or a node of the kind
the collection expects; every node a walk reaches is checked: a node of
another built-in kind, or a value that is not a node, is PBCorruptionError,
and an opaque atom (a type with no class here) is PBNotSupportedError naming
the type (format spec, 'Atoms of unknown types': its use where a built-in
type is expected). The integer fields of a node (height, count, weight) must
be Integers: each record's are checked once, when it is loaded or built from
a caller's state (the writes compute them, and are not checked again).

A node reads its fields from its slots (plan Task 16b, _PBRecordShape in
registry.st): an Array of the values of its slotFields (for the built-in
classes, their persistedFields), in that order, built once per record and
published once by compare-and-swap; each accessor reads a literal slot
number, which tests/unit/record_slots.st holds to slotFields. An application
subclass of a keyed node class inherits the layout (it may reorder its
persistedFields or add fields). The state (a PBFrozenDict in the record's order) stays the record:
the slots are never persisted, compared or hashed.

Writes (plan Task 14) are PBAvl's class methods, the functions of ProtoBase's
avl.py over a root node, or nil for the empty tree:

  PBAvl posAt: root index: i                  pos_get (the value, unboxed)
  PBAvl posInsert: root at: i value: v        pos_insert (0 <= i <= count)
  PBAvl posAppend: root value: v              pos_insert at count
  PBAvl posSet: root at: i value: v           pos_set (0 <= i < count)
  PBAvl posRemove: root at: i                 pos_remove (0 <= i < count)
  PBAvl posFromArray: anArray                 pos_from_iterable (a balanced tree)
  PBAvl posConcat: left with: right           pos_concat
  PBAvl posSlice: root from: a to: b          pos_slice (0 <= a <= b <= count)
  PBAvl keyAt: root key: k                    the node of key k, or nil
  PBAvl keyPut: root key: k value: v nodeClass: aClass     key_put:
                                              { root. replaced. old value }
  PBAvl keyAt: root orderKey: ok, keyPut: root key: k orderKey: ok value: v nodeClass: aClass,
  keyRemove: root orderKey: ok                the same, for a caller that has the order key ok
                                              of k (trusted: see 'The trust contract' below)

The trust contract of the order-key selectors (keyAt:orderKey:,
keyPut:key:orderKey:value:nodeClass:, keyRemove:orderKey: and
keyFromSortedOrderKeys:nodeClass:): the caller guarantees that each order key
it passes is exactly PBKeys orderKey: of its key (= by compareWith:, which is
what the walks compare). Nothing checks it on the write: a wrong key places
the node where its own key does not, and every later lookup of that key
misses it. PBAvl check: finds it: it recomputes each node's order key from
its key and compares it with the cached one and with its neighbours' (a
key-group index's validate: runs it on every tree). The callers in protoBaseST compute each
order key with PBKeys orderKey: or PBMemberKeys memberKeyAndOrderKeyOf:,
which tests/unit/idx_key_reuse.st checks against PBKeys orderKey:.

Node classes: a keyed tree's nodes are of the class nodeClass: names for an
empty tree (PBKeyNode, PBCountedKeyNode or an application subclass of
either), and every write keeps the root's class, carrying a subclass's own
fields into each copy (KeyNode uses type(self) in ProtoBase). Positional trees
are not subclassable, as ProtoBase's PosNode: their writes build PBPosNode
nodes only, and a PBPosNode subclass is refused when it is registered, built,
or given to a pos operation (PBPosNode class >> _refuseSubclass).
  PBAvl keyRemove: root key: k                key_remove:
                                              { root. removed. old value }
  PBAvl nodesDo: aBlock over: root            each node, in order (_inorder)
  PBAvl posDo: aBlock over: root              each value, unboxed (pos_iter)
  PBAvl keysAndValuesDo: aBlock over: root    each key and value (key_iter)
  PBAvl check: root                           check_invariants

The functions of the indexes and of the rank access (indexed queries, plan
Task 1); okey is an order key (PBKeys orderKey:), a nil bound is open:

  PBAvl keyDo: aBlock over: root fromOrderKey: lo inclusive: b1 toOrderKey: hi inclusive: b2
                                              key_iter_okey_range ([:key :value])
  PBAvl keyReverseDo: aBlock over: root       key_iter_reversed
  PBAvl keyCountBelow: root orderKey: okey inclusive: aBoolean    key_count_below
  PBAvl keyFromSorted: pairs nodeClass: aClass                    key_from_sorted
  PBAvl keyFromSortedOrderKeys: triples nodeClass: aClass         key_from_sorted_okeys
                                              (both over _build_balanced, plan call IP13)
  PBAvl keyWeight: root                       key_weight (a PBCountedKeyNode tree)
  PBAvl keyWeightBelow: root orderKey: okey inclusive: aBoolean   key_weight_below
  PBAvl keyDo: aBlock over: root fromWeight: rank descending: aBoolean
                                              key_iter_from_weight ([:key :value :skip])
  PBAvl posDo: aBlock over: root from: start  pos_iter_from
  PBAvl keyDo: aBlock over: root from: start  key_iter_from

Every write builds a new root and never changes a node: it builds new nodes
along the path it touches (path copying) and shares every other subtree with
its input. The balancing is ProtoBase's, step for step (_balance with its four
rotations, _pop_first, successor removal in _remove_node), so one operation
sequence gives the same nodes, field for field, in both implementations
(tests/interop/avl_ops_identical.sh). The helpers recurse along one
root-to-leaf path only, at most about 1.44 log2(n) deep.

A new node, and a new value box, is an unsaved atom: no pointer, and no oid
until its first need draws one (PBAtom >> oid, ProtoBase D21); the writer
saves it. Its state is a PBFrozenDict in persistedFields order, the order
ProtoBase's constructors set the attributes in (the order its records show).

Boxing (ProtoBase D51, VALUE_BOX_MIN): a node value that is a String of at
least 256 code points, or a ByteArray of at least 256 bytes, is held through
a new PBValueBox; a PBValueBox is kept as it is, so a path copy keeps the box
of the node it copies. Keys are never boxed, nor any other value (a tuple, a
bucket list), whatever it holds."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/registry'.
Import from: 'protobase/keys'.

"=== the node classes ========================================================"

PBAtom subclass: #PBNode classVariableNames: 'PosShape KeyShape CountedKeyShape'.

PBNode class >> typeName
  ^ 'proto_db.avl._Node'.

PBNode class >> requiredFields
  ^ #('left' 'right' 'height' 'count').

PBNode class >> persistedFields
  ^ #('left' 'right' 'height' 'count').

PBNode class >> integerFields
  ^ #('height' 'count').

"The fields of a node read by name (stateAt:): PBNode, the abstract type,
 declares no slotFields. Each concrete class reads its slots instead, at the
 literal slot number of the field in its slotFields, which are its
 persistedFields (tests/unit/record_slots.st holds each literal)."

PBNode >> left
  ^ self stateAt: 'left'.

PBNode >> right
  ^ self stateAt: 'right'.

PBNode >> height
  ^ _PBTree integer: (self stateAt: 'height') field: 'height' of: self.

"The number of nodes of this subtree."
PBNode >> count
  ^ _PBTree integer: (self stateAt: 'count') field: 'count' of: self.

"The node value as the record holds it (a PBValueBox for a large value)."
PBNode >> storedValue
  ^ self stateAt: 'value'.

"The node value, unboxed."
PBNode >> value
  ^ _PBTree unboxed: self storedValue.

PBNode subclass: #PBPosNode.

PBPosNode class >> typeName
  ^ 'proto_db.avl.PosNode'.

PBPosNode class >> requiredFields
  ^ #('value' 'left' 'right' 'height' 'count').

PBPosNode class >> persistedFields
  ^ #('value' 'left' 'right' 'height' 'count').

"The slots the accessors below read: PBPosNode's persistedFields (named, not
 self: a subclass that reorders its persistedFields keeps this layout)."
PBPosNode class >> slotFields
  ^ PBPosNode persistedFields.

"The accessors read the slots: value 1, left 2, right 3, height 4, count 5."
PBPosNode >> storedValue
  slots == nil ifTrue: [^ self _slots at: 1].
  ^ slots at: 1.

PBPosNode >> left
  slots == nil ifTrue: [^ self _slots at: 2].
  ^ slots at: 2.

PBPosNode >> right
  slots == nil ifTrue: [^ self _slots at: 3].
  ^ slots at: 3.

PBPosNode >> height
  slots == nil ifTrue: [^ self _slots at: 4].
  ^ slots at: 4.

PBPosNode >> count
  slots == nil ifTrue: [^ self _slots at: 5].
  ^ slots at: 5.

"A keyed node also holds the order key of its key (ProtoBase KeyNode._okey),
 never persisted: a node a write builds gets it when it is built (the put's
 order key, or the copied node's), in the write group of its state
 (_installSlots:memo:orderKey:); a stored node fills it on first use (orderKey),
 once, by a compare-and-swap from nil, like the oid: the value is derived from
 the immutable key, so two racing first readers compute equal values and both
 answer the installed one."
PBNode subclass: #PBKeyNode instanceVariableNames: 'orderKey'.

PBKeyNode class >> typeName
  ^ 'proto_db.avl.KeyNode'.

PBKeyNode class >> requiredFields
  ^ #('key' 'value' 'left' 'right' 'height' 'count').

PBKeyNode class >> persistedFields
  ^ #('key' 'value' 'left' 'right' 'height' 'count').

PBKeyNode class >> slotFields
  ^ PBKeyNode persistedFields.

"The accessors read the slots: key 1, value 2, left 3, right 4, height 5,
 count 6 (PBCountedKeyNode keeps them and adds weight 7)."
PBKeyNode >> key
  slots == nil ifTrue: [^ self _slots at: 1].
  ^ slots at: 1.

PBKeyNode >> storedValue
  slots == nil ifTrue: [^ self _slots at: 2].
  ^ slots at: 2.

PBKeyNode >> left
  slots == nil ifTrue: [^ self _slots at: 3].
  ^ slots at: 3.

PBKeyNode >> right
  slots == nil ifTrue: [^ self _slots at: 4].
  ^ slots at: 4.

PBKeyNode >> height
  slots == nil ifTrue: [^ self _slots at: 5].
  ^ slots at: 5.

PBKeyNode >> count
  slots == nil ifTrue: [^ self _slots at: 6].
  ^ slots at: 6.

"The order key of the key (PBKeys orderKey:), computed once per node."
PBKeyNode >> orderKey
  orderKey isNil ifFalse: [^ orderKey].
  ^ self _publishOrderKey: (PBKeys orderKey: self key).

"The cached order key, or nil when it was not needed yet (a stub)."
PBKeyNode >> knownOrderKey
  ^ orderKey.

"Installs anOrderKey, the order key of the key, unless one is installed, by a
 compare-and-swap from nil (PBAtom's write-once publishers); answers the
 installed order key."
PBKeyNode >> _publishOrderKey: anOrderKey
  self setInstVar: #orderKey from: nil to: anOrderKey.
  ^ orderKey.

"As PBAtom >> _installSlots:memo:, for a node a write builds: its slots, its
 memo and anOrderKey, the order key of its key, in one write group."
PBKeyNode >> _installSlots: anArray memo: aMemo orderKey: anOrderKey
  memo isNil ifFalse: [^ PBUserError signal: 'PBAtom: the state is installed once'].
  memo := aMemo.
  slots := anArray.
  orderKey := anOrderKey.
  ^ self.

PBKeyNode subclass: #PBCountedKeyNode.

PBCountedKeyNode class >> typeName
  ^ 'proto_db.avl.CountedKeyNode'.

PBCountedKeyNode class >> requiredFields
  ^ #('key' 'value' 'left' 'right' 'height' 'count' 'weight').

PBCountedKeyNode class >> persistedFields
  ^ #('key' 'value' 'left' 'right' 'height' 'count' 'weight').

"PBKeyNode's slots, then weight."
PBCountedKeyNode class >> slotFields
  ^ PBCountedKeyNode persistedFields.

PBCountedKeyNode class >> integerFields
  ^ #('height' 'count' 'weight').

"The sum of the counts (value at: 2) of this subtree: slot 7."
PBCountedKeyNode >> weight
  slots == nil ifTrue: [^ self _slots at: 7].
  ^ slots at: 7.

PBAtom subclass: #PBValueBox.

PBValueBox class >> typeName
  ^ 'proto_db.avl.ValueBox'.

PBValueBox class >> requiredFields
  ^ #('value').

PBValueBox class >> persistedFields
  ^ #('value').

PBValueBox class >> slotFields
  ^ PBValueBox persistedFields.

"The boxed value: slot 1."
PBValueBox >> value
  slots == nil ifTrue: [^ self _slots at: 1].
  ^ slots at: 1.

"The record shapes of the built-in node classes, which every write that builds
 a node reads: kept in class variables, set once when the module loads, so the
 write reads its shape without the lookup of _PBRecordShape for:. Any other
 class, an application subclass included, takes that lookup."
PBNode class >> _recordShape
  self == PBCountedKeyNode ifTrue: [^ CountedKeyShape].
  self == PBKeyNode ifTrue: [^ KeyShape].
  self == PBPosNode ifTrue: [^ PosShape].
  ^ super _recordShape.

PBNode class >> _initializeShapes
  "Runs once, when the module loads, before the classes are registered."
  PosShape := _PBRecordShape for: PBPosNode.
  KeyShape := _PBRecordShape for: PBKeyNode.
  CountedKeyShape := _PBRecordShape for: PBCountedKeyNode.

PBNode _initializeShapes.

{ PBNode. PBPosNode. PBKeyNode. PBCountedKeyNode. PBValueBox } do: [:each | PBTypeRegistry register: each].

"A new, unsaved atom of aClass whose slots are anArray: the values of the
 slotFields of the built-in class aClass descends from, in order (a node
 class's or PBValueBox's), computed by the writes (PBAtom class >>
 _unsavedWithSlots:). For the built-in classes the state shares the class's
 keys and anArray; a subclass's state follows its own persistedFields, and a
 later field of it is absent."
PBNode class >> _new: aClass values: anArray
  ^ aClass _unsavedWithSlots: anArray.

"=== the walks ==============================================================="

Object subclass: #_PBTree.

"anObject's value as an Integer field (not a Boolean); PBCorruptionError
 otherwise. The node classes check theirs once per record (_PBRecordShape)."
_PBTree class >> integer: anObject field: aName of: anAtom
  ^ _PBRecordShape integer: anObject field: aName of: anAtom.

"A stored node value without its box."
_PBTree class >> unboxed: aStoredValue
  "Exact class, as ProtoBase's unboxed (type(stored) is ValueBox)."
  aStoredValue class == PBValueBox ifTrue: [^ aStoredValue value].
  ^ aStoredValue.

"aNode, a node of aKind (a node class) or nil: another value is PBCorruptionError,
 an opaque atom PBNotSupportedError naming its type."
_PBTree class >> node: aNode kind: aKind in: anOwner
  aNode isNil ifTrue: [^ nil].
  "A node of exactly aKind first: the common case of every walk and write."
  aNode class == aKind ifTrue: [^ aNode].
  (aNode isKindOf: aKind) ifTrue: [^ aNode].
  ^ self notNode: aNode kind: aKind in: anOwner.

"The refusal of aValue, neither nil nor an atom of aKind, met in anOwner: an
 opaque atom is PBNotSupportedError naming its type, anything else
 PBCorruptionError."
_PBTree class >> notNode: aNode kind: aKind in: anOwner
  (aNode isKindOf: PBOpaqueAtom) ifTrue: [
    ^ PBNotSupportedError signal: 'the ' , aNode tag , ' atom ' , aNode printString
      , ' is used where a ' , aKind typeName , ' is expected (in ' , anOwner printString
      , '), and that type has no class registered in this process: its behaviour is not available here'].
  ^ PBCorruptionError signal: anOwner printString , ' holds ' , (PBKeys _preview: aNode)
    , ' where a ' , aKind typeName , ' (or nil) is expected'.

"aValue, a field aName of anOwner that must hold an atom of aKind: nil is
 PBCorruptionError naming the field, another value as node:kind:in:."
_PBTree class >> required: aValue kind: aKind field: aName in: anOwner
  aValue isNil ifTrue: [
    ^ PBCorruptionError signal: 'the ' , aName , ' of ' , anOwner printString , ' is nil where a '
      , aKind typeName , ' is required'].
  ^ self node: aValue kind: aKind in: anOwner.

"The node count of the tree aRoot (0 when empty)."
_PBTree class >> count: aRoot kind: aKind in: anOwner
  | root |
  root := self node: aRoot kind: aKind in: anOwner.
  ^ root isNil ifTrue: [0] ifFalse: [root count].

"Evaluates aBlock with each node of the tree aRoot, in order (explicit stack)."
_PBTree class >> nodesOf: aRoot kind: aKind in: anOwner do: aBlock
  "A child of the root's class is accepted at once (a tree has one node
   class); another one is checked against aKind as node:kind:in: checks it."
  | stack node same |
  stack := OrderedCollection new.
  node := self node: aRoot kind: aKind in: anOwner.
  same := node class.
  [stack notEmpty or: [node notNil]] whileTrue: [
    [node notNil] whileTrue: [
      stack addLast: node.
      node := node left.
      node isNil ifFalse: [node class == same ifFalse: [node := self node: node kind: aKind in: anOwner]]].
    node := stack removeLast.
    aBlock value: node.
    node := node right.
    node isNil ifFalse: [node class == same ifFalse: [node := self node: node kind: aKind in: anOwner]]].

"The node at position anIndex (0-based, 0 <= anIndex < count) of a positional
 tree (pos_get). A tree whose counts do not lead to a node is PBCorruptionError."
_PBTree class >> nodeAt: anIndex of: aRoot in: anOwner
  "Each child is read once and checked by one send (_pbPosNodeIn:)."
  | node index left leftCount |
  node := aRoot _pbPosNodeIn: anOwner.
  index := anIndex.
  [node notNil] whileTrue: [
    left := node left _pbPosNodeIn: anOwner.
    leftCount := left isNil ifTrue: [0] ifFalse: [left count].
    index < leftCount
      ifTrue: [node := left]
      ifFalse: [
        index = leftCount ifTrue: [^ node].
        index := index - leftCount - 1.
        node := node right _pbPosNodeIn: anOwner]].
  ^ PBCorruptionError signal: 'the positional tree of ' , anOwner printString , ' has no node at '
    , anIndex printString , ': its counts are inconsistent'.

"The node of the keyed tree aRoot whose key has the order key anOrderKey, or
 nil (key_get)."
_PBTree class >> nodeWithKey: anOrderKey of: aRoot in: anOwner
  | node c |
  node := aRoot _pbKeyNodeIn: anOwner.
  [node notNil] whileTrue: [
    c := anOrderKey compareWith: node orderKey.
    c = 0 ifTrue: [^ node].
    node := (c < 0 ifTrue: [node left] ifFalse: [node right]) _pbKeyNodeIn: anOwner].
  ^ nil.

"The checks of a descent, one send per child: the receiver as a node of a
 positional (_pbPosNodeIn:) or keyed (_pbKeyNodeIn:) tree of anOwner. A node
 of that kind (a subclass included, as isKindOf:) answers itself, nil answers
 nil, anything else is refused as _PBTree notNode:kind:in: refuses it."
Object >> _pbPosNodeIn: anOwner
  ^ _PBTree notNode: self kind: PBPosNode in: anOwner.

UndefinedObject >> _pbPosNodeIn: anOwner
  ^ nil.

PBPosNode >> _pbPosNodeIn: anOwner
  ^ self.

Object >> _pbKeyNodeIn: anOwner
  ^ _PBTree notNode: self kind: PBKeyNode in: anOwner.

UndefinedObject >> _pbKeyNodeIn: anOwner
  ^ nil.

PBKeyNode >> _pbKeyNodeIn: anOwner
  ^ self.

"=== new nodes (plan Task 14) ================================================="

"A new node of this class with this node's payload over aLeft and aRight
 (ProtoBase _Node._with_children); the stored value is kept, a box included."
PBNode >> withLeft: aLeft right: aRight
  ^ self subclassResponsibility.

"A new positional node holding aValue (boxed when large) over aLeft and aRight;
 height and count are computed from the children. A subclass is
 PBNotSupportedError (positional trees are not subclassable: see
 _refuseSubclass)."
PBPosNode class >> value: aValue left: aLeft right: aRight
  self == PBPosNode ifFalse: [^ PBNotSupportedError signal: self _refuseSubclass].
  ^ PBNode _new: self values: {
    _PBTree boxed: aValue. aLeft. aRight.
    _PBTree heightOf: aLeft and: aRight. _PBTree countOf: aLeft and: aRight }.

"A plain PBPosNode, whatever the receiver's class, as ProtoBase
 PosNode._with_children builds PosNode (review R3-I1)."
PBPosNode >> withLeft: aLeft right: aRight
  ^ PBPosNode value: self storedValue left: aLeft right: aRight.

"Positional trees are not subclassable, as in ProtoBase, whose positional
 writes (_pos_insert, _pos_set, pos_from_iterable, PosNode._with_children) all
 build PosNode: a subclass would come back as a tree of mixed classes, which
 the next write reports as corrupt. So a subclass is refused, never degraded
 (review R3-I1): when it is registered (PBUserError, _checkRecordClass), when
 it is built, and when a positional operation is given one as its root
 (PBNotSupportedError). The text of those refusals."
PBPosNode class >> _refuseSubclass
  ^ self name , ': positional trees are not subclassable, as ProtoBase''s PosNode'
    , ' (a positional tree holds PBPosNode nodes only; subclass PBKeyNode for a keyed tree)'.

"A subclass of PBPosNode has no record shape: PBUserError when it is
 registered (see _refuseSubclass)."
PBPosNode class >> _checkRecordClass
  self == PBPosNode ifFalse: [^ PBUserError signal: self _refuseSubclass].

"A new keyed node of key aKey (never boxed) holding aValue (boxed when large)
 over aLeft and aRight; anOrderKey is PBKeys orderKey: aKey, which the caller
 has (ProtoBase passes _okey the same way). The key's order is the caller's
 concern (PBAvl)."
PBKeyNode class >> key: aKey orderKey: anOrderKey value: aValue left: aLeft right: aRight
  ^ self _unsavedWithSlots: (self _fieldsKey: aKey value: aValue left: aLeft right: aRight) orderKey: anOrderKey.

"As PBAtom class >> _unsavedWithSlots:, for a keyed node: anOrderKey, the order
 key of its key, is written with its slots."
PBKeyNode class >> _unsavedWithSlots: anArray orderKey: anOrderKey
  | shape padded |
  shape := self _recordShape.
  padded := shape slotsPadded: anArray.
  ^ (self basicNew _setOid: nil pointer: nil storage: nil)
    _installSlots: padded memo: (self _memoOfSlots: anArray padded: padded shape: shape) orderKey: anOrderKey.

"As key:orderKey:value:left:right:, computing the order key."
PBKeyNode class >> key: aKey value: aValue left: aLeft right: aRight
  ^ self key: aKey orderKey: (PBKeys orderKey: aKey) value: aValue left: aLeft right: aRight.

"The values of persistedFields for a new node."
PBKeyNode class >> _fieldsKey: aKey value: aValue left: aLeft right: aRight
  ^ { aKey. _PBTree boxed: aValue. aLeft. aRight.
    _PBTree heightOf: aLeft and: aRight. _PBTree countOf: aLeft and: aRight }.

PBKeyNode >> withLeft: aLeft right: aRight
  ^ self _copyWithSlots: (self class _fieldsKey: self key value: self storedValue left: aLeft right: aRight).

"A new node of this class with this node's key and children, holding aValue
 (ProtoBase KeyNode._with_value: the stored key object is kept)."
PBKeyNode >> withValue: aValue
  ^ self _copyWithSlots: (self class _fieldsKey: self key value: aValue left: self left right: self right).

"A new node of this class whose built-in slots are anArray, the values a write
 computed for a copy of this node, holding this node's order key (the key is
 the same). The fields past them, an application subclass's own, which the
 writes do not know, are carried from this node unchanged: present when present
 here, with the same value, absent when absent (review R2-I1). A class's slot
 layout starts with its superclass's (_PBRecordShape build:), so those fields
 follow the built-in prefix. The built-in classes have none and take the plain
 constructor."
PBKeyNode >> _copyWithSlots: anArray
  | own cls shape all carried |
  own := slots == nil ifTrue: [self _slots] ifFalse: [slots].
  cls := self class.
  own size > anArray size ifFalse: [^ cls _unsavedWithSlots: anArray orderKey: self orderKey].
  shape := cls _recordShape.
  all := anArray , (own copyFrom: anArray size + 1 to: own size).
  carried := shape stateOfSlots: anArray carrying: self state.
  ^ (cls basicNew _setOid: nil pointer: nil storage: nil)
    _installSlots: all memo: (cls _memoOfState: carried slots: all tag: nil shape: shape) orderKey: self orderKey.

"As PBKeyNode's, for a value that is a (payload, count) pair (PBValidationError
 otherwise, ProtoBase _value_count); weight is the count plus the children's
 weights."
PBCountedKeyNode class >> _fieldsKey: aKey value: aValue left: aLeft right: aRight
  "One brace: PBKeyNode's six values, then weight."
  | own |
  own := _PBTree countOfPair: aValue.
  ^ { aKey. _PBTree boxed: aValue. aLeft. aRight.
    _PBTree heightOf: aLeft and: aRight. _PBTree countOf: aLeft and: aRight.
    own + (_PBTree weightOf: aLeft) + (_PBTree weightOf: aRight) }.

"=== the helpers of the writes ==============================================="

"ProtoBase VALUE_BOX_MIN: the smallest String (in code points) or ByteArray (in
 bytes) a node holds through a PBValueBox."
_PBTree class >> valueBoxMin
  ^ 256.

"The form a node stores aValue in (ProtoBase boxed): a new PBValueBox for a
 String or ByteArray of at least valueBoxMin, an existing PBValueBox as it is,
 any other value itself."
_PBTree class >> boxed: aValue
  aValue _pbIsLargeNodeValue ifTrue: [^ PBNode _new: PBValueBox values: { aValue }].
  ^ aValue.

"Whether a node holds the receiver through a new PBValueBox (_PBTree boxed:):
 a String (not a Symbol) of at least valueBoxMin code points or a ByteArray of
 at least valueBoxMin bytes. A PBValueBox is kept as it is."
Object >> _pbIsLargeNodeValue
  ^ false.

String >> _pbIsLargeNodeValue
  self isSymbol ifTrue: [^ false].
  ^ self size >= _PBTree valueBoxMin.

ByteArray >> _pbIsLargeNodeValue
  ^ self size >= _PBTree valueBoxMin.

_PBTree class >> heightOfNode: aNode
  ^ aNode isNil ifTrue: [0] ifFalse: [aNode height].

_PBTree class >> countOfNode: aNode
  ^ aNode isNil ifTrue: [0] ifFalse: [aNode count].

_PBTree class >> weightOf: aNode
  ^ aNode isNil ifTrue: [0] ifFalse: [aNode weight].

_PBTree class >> heightOf: aLeft and: aRight
  ^ 1 + ((self heightOfNode: aLeft) max: (self heightOfNode: aRight)).

_PBTree class >> countOf: aLeft and: aRight
  ^ 1 + (self countOfNode: aLeft) + (self countOfNode: aRight).

"The count of a weighted node value: aValue (unboxed) is a pair, a PBTuple or a
 list, whose second item is an Integer >= 0; PBValidationError otherwise
 (ProtoBase _value_count)."
_PBTree class >> countOfPair: aValue
  | value count |
  value := self unboxed: aValue.
  (((value isKindOf: PBTuple) or: [(value isKindOf: PBFrozenList) or: [value isKindOf: Array]])
    and: [value size = 2]) ifFalse: [
      ^ PBValidationError signal: 'a CountedKeyNode value must be a (payload, count) pair, not '
        , (PBKeys _preview: value)].
  count := value at: 2.
  ((count isInteger and: [count ~~ true and: [count ~~ false]]) and: [count >= 0]) ifFalse: [
    ^ PBValidationError signal: 'a CountedKeyNode count must be an Integer >= 0, not '
      , (PBKeys _preview: count)].
  ^ count.

"=== PBAvl ==================================================================="

"The persistent AVL functions (see the module comment). Class methods only."
Object subclass: #PBAvl.

PBAvl class >> valueBoxMin
  ^ _PBTree valueBoxMin.

"--- argument checks (ProtoBase _check_kind, _check_index) ---"

"aRoot is nil or a node of aKind; PBValidationError otherwise. A subclass of
 PBPosNode is PBNotSupportedError (positional trees are not subclassable)."
PBAvl class >> _root: aRoot kind: aKind
  "Nested ifTrue: (inlined), not or: (a block): every operation checks its root."
  aRoot isNil ifTrue: [^ nil].
  aRoot class == aKind ifTrue: [^ aRoot].
  (aRoot isKindOf: aKind) ifTrue: [
    aKind == PBPosNode ifTrue: [^ PBNotSupportedError signal: aRoot class _refuseSubclass].
    ^ aRoot].
  ^ PBValidationError signal: 'PBAvl: a ' , aKind typeName , ' tree (or nil) was expected, not '
    , (PBKeys _preview: aRoot).

"anIndex is an Integer (not a Boolean) in 0..anUpper; PBValidationError otherwise."
PBAvl class >> _index: anIndex upTo: anUpper
  ^ self _index: anIndex upTo: anUpper named: 'index'.

"As _index:upTo:, the refusal naming the argument aName ('index', 'start',
 'rank': ProtoBase _check_index's what, and key_iter_from_weight's rank check)."
PBAvl class >> _index: anIndex upTo: anUpper named: aName
  "The common case first, with nested ifTrue: (inlined), not and: (blocks):
   every positional operation checks its index."
  anIndex isInteger ifTrue: [
    anIndex == true ifFalse: [anIndex == false ifFalse: [
      anIndex >= 0 ifTrue: [anIndex <= anUpper ifTrue: [^ anIndex]]]]].
  (anIndex isInteger and: [anIndex ~~ true and: [anIndex ~~ false]]) ifFalse: [
    ^ PBValidationError signal: 'PBAvl: ' , (aName first isVowel ifTrue: ['an '] ifFalse: ['a ']) , aName
      , ' must be an Integer, not ' , (PBKeys _preview: anIndex)].
  (anIndex between: 0 and: anUpper) ifFalse: [
    ^ PBValidationError signal: 'PBAvl: ' , aName , ' ' , anIndex printString , ' out of range 0..' , anUpper printString].
  ^ anIndex.

"aClass, a keyed node class (PBKeyNode or a subclass); PBValidationError naming
 aSelector otherwise."
PBAvl class >> _keyedClass: aClass for: aSelector
  (aClass isClassObject and: [aClass == PBKeyNode or: [aClass inheritsFrom: PBKeyNode]]) ifFalse: [
    ^ PBValidationError signal: 'PBAvl ' , aSelector , ' nodeClass must be a keyed node class, not ' , aClass printString].
  ^ aClass.

"A child of aNode (a node of its own kind, or nil), checked as a walk checks it."
"A child of aNode: nil or a node of aNode's own class (a tree has one node
 class), checked as a walk checks it."
PBAvl class >> _left: aNode
  ^ _PBTree node: aNode left kind: aNode class in: aNode.

PBAvl class >> _right: aNode
  ^ _PBTree node: aNode right kind: aNode class in: aNode.

PBAvl class >> _height: aNode
  ^ _PBTree heightOfNode: aNode.

PBAvl class >> _count: aNode
  ^ _PBTree countOfNode: aNode.

"--- the balancing core (ProtoBase _balance, _pop_first, _remove_node) ---"

"A node with aPivot's payload over aLeft and aRight, whose heights differ by at
 most 2: one of the four rotations when they differ by 2."
PBAvl class >> _balance: aPivot left: aLeft right: aRight
  | hl hr |
  hl := self _height: aLeft.
  hr := self _height: aRight.
  hl > (hr + 1) ifTrue: [
    | ll lr |
    ll := self _left: aLeft.
    lr := self _right: aLeft.
    (self _height: ll) >= (self _height: lr) ifTrue: [
      "single right rotation"
      ^ aLeft withLeft: ll right: (aPivot withLeft: lr right: aRight)].
    "left-right double rotation"
    ^ lr withLeft: (aLeft withLeft: ll right: (self _left: lr))
      right: (aPivot withLeft: (self _right: lr) right: aRight)].
  hr > (hl + 1) ifTrue: [
    | rl rr |
    rl := self _left: aRight.
    rr := self _right: aRight.
    (self _height: rr) >= (self _height: rl) ifTrue: [
      "single left rotation"
      ^ aRight withLeft: (aPivot withLeft: aLeft right: rl) right: rr].
    "right-left double rotation"
    ^ rl withLeft: (aPivot withLeft: aLeft right: (self _left: rl))
      right: (aRight withLeft: (self _right: rl) right: rr)].
  ^ aPivot withLeft: aLeft right: aRight.

"{ the tree aNode without its first node. that first node }."
PBAvl class >> _popFirst: aNode
  | left popped |
  left := self _left: aNode.
  left isNil ifTrue: [^ { self _right: aNode. aNode }].
  popped := self _popFirst: left.
  ^ { self _balance: aNode left: (popped at: 1) right: (self _right: aNode). popped at: 2 }.

"The tree that replaces aNode once its own payload is deleted: its in-order
 successor takes its place."
PBAvl class >> _removeNode: aNode
  | left right popped |
  left := self _left: aNode.
  right := self _right: aNode.
  left isNil ifTrue: [^ right].
  right isNil ifTrue: [^ left].
  popped := self _popFirst: right.
  ^ self _balance: (popped at: 2) left: left right: (popped at: 1).

"--- positional trees ---"

"The value (unboxed) at anIndex, 0 <= anIndex < count (ProtoBase pos_get)."
PBAvl class >> posAt: aRoot index: anIndex
  self _root: aRoot kind: PBPosNode.
  self _index: anIndex upTo: (self _count: aRoot) - 1.
  ^ (_PBTree nodeAt: anIndex of: aRoot in: aRoot) value.

"A tree with aValue inserted before position anIndex, 0 <= anIndex <= count."
PBAvl class >> posInsert: aRoot at: anIndex value: aValue
  self _root: aRoot kind: PBPosNode.
  self _index: anIndex upTo: (self _count: aRoot).
  ^ self _posInsert: aRoot at: anIndex value: aValue.

"A tree with aValue after its last element."
PBAvl class >> posAppend: aRoot value: aValue
  self _root: aRoot kind: PBPosNode.
  ^ self _posInsert: aRoot at: (self _count: aRoot) value: aValue.

PBAvl class >> _posInsert: aNode at: anIndex value: aValue
  | left lc |
  aNode isNil ifTrue: [^ PBPosNode value: aValue left: nil right: nil].
  left := self _left: aNode.
  lc := self _count: left.
  anIndex <= lc ifTrue: [
    ^ self _balance: aNode left: (self _posInsert: left at: anIndex value: aValue) right: (self _right: aNode)].
  ^ self _balance: aNode left: left
    right: (self _posInsert: (self _right: aNode) at: anIndex - lc - 1 value: aValue).

"A tree whose element at anIndex is aValue, 0 <= anIndex < count (the shape is
 unchanged)."
PBAvl class >> posSet: aRoot at: anIndex value: aValue
  self _root: aRoot kind: PBPosNode.
  self _index: anIndex upTo: (self _count: aRoot) - 1.
  ^ self _posSet: aRoot at: anIndex value: aValue.

PBAvl class >> _posSet: aNode at: anIndex value: aValue
  | left right lc |
  left := self _left: aNode.
  right := self _right: aNode.
  lc := self _count: left.
  anIndex < lc ifTrue: [
    ^ PBPosNode value: aNode storedValue left: (self _posSet: left at: anIndex value: aValue) right: right].
  anIndex = lc ifTrue: [^ PBPosNode value: aValue left: left right: right].
  ^ PBPosNode value: aNode storedValue left: left right: (self _posSet: right at: anIndex - lc - 1 value: aValue).

"A tree without the element at anIndex, 0 <= anIndex < count (nil when it was
 the only one)."
PBAvl class >> posRemove: aRoot at: anIndex
  self _root: aRoot kind: PBPosNode.
  self _index: anIndex upTo: (self _count: aRoot) - 1.
  ^ self _posRemove: aRoot at: anIndex.

PBAvl class >> _posRemove: aNode at: anIndex
  | left lc |
  left := self _left: aNode.
  lc := self _count: left.
  anIndex < lc ifTrue: [
    ^ self _balance: aNode left: (self _posRemove: left at: anIndex) right: (self _right: aNode)].
  anIndex = lc ifTrue: [^ self _removeNode: aNode].
  ^ self _balance: aNode left: left right: (self _posRemove: (self _right: aNode) at: anIndex - lc - 1).

"A balanced positional tree of the values of anArray, in order (ProtoBase
 pos_from_iterable over _build_balanced: the middle value at the root, so
 subtree sizes differ by at most one); nil for an empty Array. Recursion depth
 is about log2 of the size."
PBAvl class >> posFromArray: anArray
  ^ self _buildFrom: anArray low: 1 high: anArray size + 1.

PBAvl class >> _buildFrom: anArray low: lo high: hi
  | mid |
  lo >= hi ifTrue: [^ nil].
  "ProtoBase's mid = (lo + hi) // 2 over 0-based bounds."
  mid := (lo - 1 + (hi - 1)) // 2 + 1.
  ^ PBPosNode value: (anArray at: mid)
    left: (self _buildFrom: anArray low: lo high: mid)
    right: (self _buildFrom: anArray low: mid + 1 high: hi).

"The tree of aLeft's values followed by aRight's (ProtoBase pos_concat), in
 O(log n)."
PBAvl class >> posConcat: aLeft with: aRight
  self _root: aLeft kind: PBPosNode.
  self _root: aRight kind: PBPosNode.
  ^ self _join2: aLeft with: aRight.

"The tree of the values at positions aStart .. aStop - 1, 0 <= aStart <= aStop
 <= count (ProtoBase pos_slice), in O(log n); the same root for the whole
 range."
PBAvl class >> posSlice: aRoot from: aStart to: aStop
  | n tail |
  self _root: aRoot kind: PBPosNode.
  n := self _count: aRoot.
  self _index: aStart upTo: n.
  self _index: aStop upTo: n.
  aStop < aStart ifTrue: [
    ^ PBValidationError signal: 'PBAvl: slice stop ' , aStop printString , ' is before start ' , aStart printString].
  (aStart = 0 and: [aStop = n]) ifTrue: [^ aRoot].
  tail := (self _posSplit: aRoot at: aStart) at: 2.
  ^ (self _posSplit: tail at: aStop - aStart) at: 1.

"--- joins and splits (ProtoBase _join, _join2, _pos_split) ---"

"The tree of aLeft, aPivot's payload and aRight, for trees of any heights
 (all of aLeft before the pivot, all of aRight after); descends the spine of
 the taller tree only."
PBAvl class >> _join: aPivot left: aLeft right: aRight
  | hl hr |
  hl := self _height: aLeft.
  hr := self _height: aRight.
  hl > (hr + 1) ifTrue: [
    ^ self _balance: aLeft left: (self _left: aLeft)
      right: (self _join: aPivot left: (self _right: aLeft) right: aRight)].
  hr > (hl + 1) ifTrue: [
    ^ self _balance: aRight left: (self _join: aPivot left: aLeft right: (self _left: aRight))
      right: (self _right: aRight)].
  ^ aPivot withLeft: aLeft right: aRight.

PBAvl class >> _join2: aLeft with: aRight
  | popped |
  aRight isNil ifTrue: [^ aLeft].
  aLeft isNil ifTrue: [^ aRight].
  popped := self _popFirst: aRight.
  ^ self _join: (popped at: 2) left: aLeft right: (popped at: 1).

"{ the first anIndex values of aNode. the rest }."
PBAvl class >> _posSplit: aNode at: anIndex
  | left lc split |
  aNode isNil ifTrue: [^ { nil. nil }].
  left := self _left: aNode.
  lc := self _count: left.
  anIndex <= lc ifTrue: [
    anIndex = lc ifTrue: [^ { left. self _join: aNode left: nil right: (self _right: aNode) }].
    split := self _posSplit: left at: anIndex.
    ^ { split at: 1. self _join: aNode left: (split at: 2) right: (self _right: aNode) }].
  split := self _posSplit: (self _right: aNode) at: anIndex - lc - 1.
  ^ { self _join: aNode left: left right: (split at: 1). split at: 2 }.

"--- keyed trees ---"

"The node of the keyed tree aRoot whose key is aKey (equal order keys: 1 and
 1.0 are one key), or nil. An unorderable aKey is PBValidationError."
PBAvl class >> keyAt: aRoot key: aKey
  ^ self keyAt: aRoot orderKey: (PBKeys orderKey: aKey).

"As keyAt:key:, for a caller that has anOrderKey, the order key of the key (PBKeys orderKey:);
 the key itself is not given. anOrderKey is trusted (the trust contract, module comment): a
 wrong one finds nothing or another node."
PBAvl class >> keyAt: aRoot orderKey: anOrderKey
  self _root: aRoot kind: PBKeyNode.
  ^ _PBTree nodeWithKey: anOrderKey of: aRoot in: aRoot.

"ProtoBase key_put: { new root. replaced. old value } with aKey mapped to
 aValue. An existing key keeps its stored key object and takes the new value;
 replaced is then true and the old value is its previous value, unboxed;
 otherwise false and nil. A new key gets a node of the tree's class (the
 root's), or of aClass (PBKeyNode, PBCountedKeyNode) when the tree is empty."
PBAvl class >> keyPut: aRoot key: aKey value: aValue nodeClass: aClass
  ^ self keyPut: aRoot key: aKey orderKey: (PBKeys orderKey: aKey) value: aValue nodeClass: aClass.

"As keyPut:key:value:nodeClass:, for a caller that has anOrderKey, the order key of aKey
 (PBKeys orderKey: aKey; ProtoBase passes _okey the same way). anOrderKey is trusted, never
 recomputed (the trust contract, module comment): a wrong one misfiles the node, which a new
 node also caches as its order key. With the right one the tree is the one
 keyPut:key:value:nodeClass: makes, node for node."
PBAvl class >> keyPut: aRoot key: aKey orderKey: anOrderKey value: aValue nodeClass: aClass
  | okey make out root |
  self _root: aRoot kind: PBKeyNode.
  okey := anOrderKey.
  make := self _keyedClass: (aRoot isNil ifTrue: [aClass] ifFalse: [aRoot class]) for: 'keyPut:'.
  out := Array new: 1.
  root := self _keyPut: aRoot okey: okey key: aKey value: aValue make: make out: out.
  ^ { root. (out at: 1) notNil. (out at: 1) isNil ifTrue: [nil] ifFalse: [(out at: 1) value] }.

"The put along one path; anArray at: 1 receives the node whose value is
 replaced (a local scratch cell of this call, as ProtoBase's out list)."
PBAvl class >> _keyPut: aNode okey: anOrderKey key: aKey value: aValue make: aClass out: anArray
  | c |
  aNode isNil ifTrue: [^ aClass key: aKey orderKey: anOrderKey value: aValue left: nil right: nil].
  c := anOrderKey compareWith: aNode orderKey.
  c < 0 ifTrue: [
    ^ self _balance: aNode
      left: (self _keyPut: (self _left: aNode) okey: anOrderKey key: aKey value: aValue make: aClass out: anArray)
      right: (self _right: aNode)].
  c > 0 ifTrue: [
    ^ self _balance: aNode
      left: (self _left: aNode)
      right: (self _keyPut: (self _right: aNode) okey: anOrderKey key: aKey value: aValue make: aClass out: anArray)].
  anArray at: 1 put: aNode.
  ^ aNode withValue: aValue.

"ProtoBase key_remove: { new root. removed. old value } without aKey; when
 aKey is absent, { aRoot itself. false. nil }. The old value is unboxed."
PBAvl class >> keyRemove: aRoot key: aKey
  ^ self keyRemove: aRoot orderKey: (PBKeys orderKey: aKey).

"As keyRemove:key:, for a caller that has anOrderKey, the order key of the key (PBKeys
 orderKey:), trusted as keyAt:orderKey: trusts it (the trust contract, module comment): a wrong
 one removes nothing or another node."
PBAvl class >> keyRemove: aRoot orderKey: anOrderKey
  | out root |
  self _root: aRoot kind: PBKeyNode.
  out := Array new: 1.
  root := self _keyRemove: aRoot okey: anOrderKey out: out.
  ^ { root. (out at: 1) notNil. (out at: 1) isNil ifTrue: [nil] ifFalse: [(out at: 1) value] }.

PBAvl class >> _keyRemove: aNode okey: anOrderKey out: anArray
  | c left right child |
  aNode isNil ifTrue: [^ nil].
  c := anOrderKey compareWith: aNode orderKey.
  c = 0 ifTrue: [
    anArray at: 1 put: aNode.
    ^ self _removeNode: aNode].
  left := self _left: aNode.
  right := self _right: aNode.
  c < 0 ifTrue: [
    child := self _keyRemove: left okey: anOrderKey out: anArray.
    ^ child == left ifTrue: [aNode] ifFalse: [self _balance: aNode left: child right: right]].
  child := self _keyRemove: right okey: anOrderKey out: anArray.
  ^ child == right ifTrue: [aNode] ifFalse: [self _balance: aNode left: left right: child].

"--- walks (ProtoBase _inorder, pos_iter, key_iter) ---"

"Evaluates aBlock with each node of the tree aRoot, in order (ProtoBase's
 _inorder; an explicit stack)."
PBAvl class >> nodesDo: aBlock over: aRoot
  self _root: aRoot kind: PBNode.
  _PBTree nodesOf: aRoot kind: PBNode in: aRoot do: aBlock.

"Evaluates aBlock with each value of the positional tree aRoot, in order,
 unboxed (ProtoBase pos_iter)."
PBAvl class >> posDo: aBlock over: aRoot
  self _root: aRoot kind: PBPosNode.
  _PBTree nodesOf: aRoot kind: PBPosNode in: aRoot do: [:node | aBlock value: node value].

"Evaluates aBlock with each key and value (unboxed) of the keyed tree aRoot,
 in key order (ProtoBase key_iter)."
PBAvl class >> keysAndValuesDo: aBlock over: aRoot
  self _root: aRoot kind: PBKeyNode.
  _PBTree nodesOf: aRoot kind: PBKeyNode in: aRoot do: [:node | aBlock value: node key value: node value].

"--- ranges, ranks and weights (ProtoBase avl.py: key_iter_okey_range to
    key_iter_from, _build_balanced; the indexes and the rank access) ---

 Every walk evaluates its block as it reaches each node, so a non-local return
 from the block (^ in the caller's method) stops it there: the walks are as lazy
 as ProtoBase's generators (plan call IP9). A walk keeps an explicit stack; the
 seeks descend one path."

"Evaluates aBlock with each key and value (unboxed) of the keyed tree aRoot whose
 order key is above aLow and below aHigh, in key order (ProtoBase
 key_iter_okey_range, _iter_okey_range). The bounds are order keys (PBKeys
 orderKey:, or any PBOrderKey: a bound need not be a value's); nil is an open
 side. aLowInclusive and aHighInclusive admit a key equal to the bound. O(log n
 + k) for k pairs."
PBAvl class >> keyDo: aBlock over: aRoot fromOrderKey: aLow inclusive: aLowInclusive toOrderKey: aHigh inclusive: aHighInclusive
  | stack node c |
  self _root: aRoot kind: PBKeyNode.
  stack := OrderedCollection new.
  node := aRoot.
  [stack notEmpty or: [node notNil]] whileTrue: [
    [node notNil] whileTrue: [
      "A node below the range has its left subtree below it too: skip both."
      (aLow notNil and: [
          c := node orderKey compareWith: aLow.
          c < 0 or: [c = 0 and: [aLowInclusive not]]])
        ifTrue: [node := self _right: node]
        ifFalse: [
          stack addLast: node.
          node := self _left: node]].
    stack isEmpty ifTrue: [^ self].
    node := stack removeLast.
    (aHigh notNil and: [
        c := node orderKey compareWith: aHigh.
        c > 0 or: [c = 0 and: [aHighInclusive not]]]) ifTrue: [^ self].
    aBlock value: node key value: node value.
    node := self _right: node].

"Evaluates aBlock with each key and value (unboxed) of the keyed tree aRoot, in
 descending key order (ProtoBase key_iter_reversed, _iter_reversed)."
PBAvl class >> keyReverseDo: aBlock over: aRoot
  | stack node |
  self _root: aRoot kind: PBKeyNode.
  stack := OrderedCollection new.
  node := aRoot.
  [stack notEmpty or: [node notNil]] whileTrue: [
    [node notNil] whileTrue: [
      stack addLast: node.
      node := self _right: node].
    node := stack removeLast.
    aBlock value: node key value: node value.
    node := self _left: node].

"The number of keys of the keyed tree aRoot whose order key is below anOrderKey
 (or equal to it, when aBoolean), in O(log n): one root-to-leaf walk over the
 subtree counts (ProtoBase key_count_below)."
PBAvl class >> keyCountBelow: aRoot orderKey: anOrderKey inclusive: aBoolean
  | below node c |
  self _root: aRoot kind: PBKeyNode.
  below := 0.
  node := aRoot.
  [node notNil] whileTrue: [
    c := node orderKey compareWith: anOrderKey.
    (c < 0 or: [aBoolean and: [c = 0]])
      ifTrue: [
        below := below + 1 + (self _count: (self _left: node)).
        node := self _right: node]
      ifFalse: [node := self _left: node]].
  ^ below.

"A balanced keyed tree of nodes of aClass (PBKeyNode, PBCountedKeyNode or a
 subclass) holding anArray's pairs { key. value }, in O(n); nil for an empty
 Array (ProtoBase key_from_sorted). The keys must be strictly increasing by
 order key: a key out of order, or repeated (1 and 1.0 are one key), is
 PBValidationError, and so is a key that has no order key. The shape is
 ProtoBase's _build_balanced (plan call IP13): see _keyBuild:class:low:high:."
PBAvl class >> keyFromSorted: anArray nodeClass: aClass
  | items prev |
  "The node class is checked even for an empty Array: stricter than ProtoBase,
   which never calls node_class then."
  self _keyedClass: aClass for: 'keyFromSorted:nodeClass:'.
  items := Array new: anArray size.
  prev := nil.
  anArray doWithIndex: [:pair :i |
    | okey |
    self _pair: pair size: 2 for: 'keyFromSorted:nodeClass:'.
    okey := PBKeys orderKey: (pair at: 1).
    (prev isNil or: [(prev compareWith: okey) < 0]) ifFalse: [
      ^ self _outOfOrder: (pair at: 1) for: 'keyFromSorted:nodeClass:'].
    items at: i put: { okey. pair at: 1. pair at: 2 }.
    prev := okey].
  ^ self _keyBuild: items class: aClass low: 1 high: items size + 1.

"As keyFromSorted:nodeClass:, for triples { order key. key. value } whose order
 keys the caller computed (PBKeys orderKey: of the key; the bulk builders sort
 by them): the order is checked, the order keys are trusted (ProtoBase
 key_from_sorted_okeys)."
PBAvl class >> keyFromSortedOrderKeys: anArray nodeClass: aClass
  | prev |
  "The node class is checked even for an empty Array: stricter than ProtoBase,
   which never calls node_class then."
  self _keyedClass: aClass for: 'keyFromSortedOrderKeys:nodeClass:'.
  prev := nil.
  anArray do: [:triple |
    self _pair: triple size: 3 for: 'keyFromSortedOrderKeys:nodeClass:'.
    (prev isNil or: [(prev compareWith: (triple at: 1)) < 0]) ifFalse: [
      ^ self _outOfOrder: (triple at: 2) for: 'keyFromSortedOrderKeys:nodeClass:'].
    prev := triple at: 1].
  ^ self _keyBuild: anArray class: aClass low: 1 high: anArray size + 1.

"anItem, an Array of aSize elements given to aSelector; PBValidationError
 otherwise (ProtoBase unpacks each item)."
PBAvl class >> _pair: anItem size: aSize for: aSelector
  ((anItem isKindOf: Array) and: [anItem size = aSize]) ifFalse: [
    ^ PBValidationError signal: 'PBAvl ' , aSelector , ' takes Arrays of ' , aSize printString , ' elements, not '
      , (PBKeys _preview: anItem)].
  ^ anItem.

PBAvl class >> _outOfOrder: aKey for: aSelector
  ^ PBValidationError signal: 'PBAvl ' , aSelector , ' needs strictly increasing keys; '
    , (PBKeys _preview: aKey) , ' is out of order'.

"The tree of the triples { order key. key. value } at lo .. hi - 1 of anArray
 (ProtoBase _build_balanced): the middle (lo + hi) // 2 over 0-based bounds at
 the root, so subtree sizes differ by at most one and an even count puts its
 upper middle at the root (plan call IP13). Recursion depth is about log2 of
 the size."
PBAvl class >> _keyBuild: anArray class: aClass low: lo high: hi
  | mid item |
  lo >= hi ifTrue: [^ nil].
  mid := (lo - 1 + (hi - 1)) // 2 + 1.
  item := anArray at: mid.
  ^ aClass key: (item at: 2) orderKey: (item at: 1) value: (item at: 3)
    left: (self _keyBuild: anArray class: aClass low: lo high: mid)
    right: (self _keyBuild: anArray class: aClass low: mid + 1 high: hi).

"The occurrences of the weighted tree aRoot (a PBCountedKeyNode tree, or nil):
 the root's weight, in O(1) (ProtoBase key_weight). Another tree is
 PBValidationError (ProtoBase _check_counted)."
PBAvl class >> keyWeight: aRoot
  self _root: aRoot kind: PBCountedKeyNode.
  ^ _PBTree weightOf: aRoot.

"The occurrences of the weighted tree aRoot under the keys whose order key is
 below anOrderKey (or equal to it, when aBoolean), in O(log n) (ProtoBase
 key_weight_below)."
PBAvl class >> keyWeightBelow: aRoot orderKey: anOrderKey inclusive: aBoolean
  | below node c |
  self _root: aRoot kind: PBCountedKeyNode.
  below := 0.
  node := aRoot.
  [node notNil] whileTrue: [
    c := node orderKey compareWith: anOrderKey.
    (c < 0 or: [aBoolean and: [c = 0]])
      ifTrue: [
        below := below + node weight - (_PBTree weightOf: (self _right: node)).
        node := self _right: node]
      ifFalse: [node := self _left: node]].
  ^ below.

"Evaluates aBlock with the key, the value (unboxed) and the skip of each node of
 the weighted tree aRoot from occurrence aRank on, in key order (descending when
 aBoolean) (ProtoBase key_iter_from_weight). A node stands for its count
 consecutive occurrences (its value's second item), which keep their order in
 both directions; skip is how many of them precede aRank, non-zero only for the
 first node. 0 <= aRank <= the tree's weight (an Integer; PBValidationError
 otherwise); aRank equal to the weight evaluates nothing. One seek, then
 O(log n + k) for k nodes."
PBAvl class >> keyDo: aBlock over: aRoot fromWeight: aRank descending: aBoolean
  self _root: aRoot kind: PBCountedKeyNode.
  self _index: aRank upTo: (_PBTree weightOf: aRoot) named: 'rank'.
  self _nodesDo: [:node :skip | aBlock value: node key value: node value value: skip]
    over: aRoot from: aRank descending: aBoolean weighted: true.

"Evaluates aBlock with each value (unboxed) of the positional tree aRoot from
 position aStart on, 0 <= aStart <= count, in O(log n + k): one seek, then an
 in-order walk (ProtoBase pos_iter_from)."
PBAvl class >> posDo: aBlock over: aRoot from: aStart
  self _root: aRoot kind: PBPosNode.
  self _index: aStart upTo: (self _count: aRoot) named: 'start'.
  self _nodesDo: [:node :skip | aBlock value: node value] over: aRoot from: aStart descending: false weighted: false.

"Evaluates aBlock with each key and value (unboxed) of the keyed tree aRoot from
 the aStart-th key on, 0 <= aStart <= count, in key order, in O(log n + k)
 (ProtoBase key_iter_from)."
PBAvl class >> keyDo: aBlock over: aRoot from: aStart
  self _root: aRoot kind: PBKeyNode.
  self _index: aStart upTo: (self _count: aRoot) named: 'start'.
  self _nodesDo: [:node :skip | aBlock value: node key value: node value] over: aRoot from: aStart descending: false weighted: false.

"Evaluates aBlock with each node of aRoot from position aRank on, and the skip of
 the first (ProtoBase _nodes_from). A position is one node (weighted false:
 ProtoBase's _count) or one occurrence (weighted true: _weight, a node's own
 being its value's count). The seek descends one path, keeping on the stack the
 ancestors where it went to the near side (the left one, or the right one when
 descending); a node's far child is loaded only when the walk reaches it."
PBAvl class >> _nodesDo: aBlock over: aRoot from: aRank descending: descending weighted: weighted
  | stack node rank skip near wn own |
  stack := OrderedCollection new.
  node := aRoot.
  rank := aRank.
  skip := 0.
  [node notNil] whileTrue: [
    near := descending ifTrue: [self _right: node] ifFalse: [self _left: node].
    wn := weighted ifTrue: [_PBTree weightOf: near] ifFalse: [self _count: near].
    rank < wn
      ifTrue: [
        stack addLast: node.
        node := near]
      ifFalse: [
        own := weighted ifTrue: [_PBTree countOfPair: node storedValue] ifFalse: [1].
        rank < (wn + own)
          ifTrue: [
            skip := rank - wn.
            stack addLast: node.
            node := nil]
          ifFalse: [
            rank := rank - wn - own.
            node := descending ifTrue: [self _left: node] ifFalse: [self _right: node]]]].
  [stack notEmpty] whileTrue: [
    node := stack removeLast.
    aBlock value: node value: skip.
    skip := 0.
    node := descending ifTrue: [self _left: node] ifFalse: [self _right: node].
    [node notNil] whileTrue: [
      stack addLast: node.
      node := descending ifTrue: [self _right: node] ifFalse: [self _left: node]]].

"--- invariants (ProtoBase check_invariants) ---"

"The height above which check: reports corruption without walking: an AVL tree
 of height 128 would need more than 10^26 nodes."
PBAvl class >> maxHeight
  ^ 128.

PBAvl class >> _corrupt: aString
  ^ PBCorruptionError signal: 'PBAvl check: ' , aString.

"Verifies the tree aRoot and answers it; PBCorruptionError describing the
 first violation. For every node: one node class throughout (PBPosNode,
 PBKeyNode or PBCountedKeyNode, exactly), height and count consistent with the
 children, AVL balance, and in a keyed tree strictly increasing order keys; in
 a PBCountedKeyNode tree, weight is the node's count plus its children's
 weights, and a value that is not a (payload, count) pair is corruption (as
 ProtoBase). A child that is not a node is PBCorruptionError (an opaque atom
 PBNotSupportedError, as every walk). A key that has no order key is
 PBCorruptionError too (ProtoBase lets its ProtoValidationError through): only
 a valid key can be in a tree. Each order key is recomputed from the key, as
 check_invariants does, and a node's cached order key (knownOrderKey), when
 present, must equal it. Post-order with an explicit stack, as ProtoBase: every node of a
 stored tree is loaded; a path longer than the root's height (a height lie) is
 reported, so the walk always ends. An error of a load (PBClosedError, say) is
 signalled as it is."
PBAvl class >> check: aRoot
  | kind maxDepth |
  aRoot isNil ifTrue: [^ nil].
  _PBTree node: aRoot kind: PBNode in: 'the tree checked'.
  kind := aRoot class.
  ({ PBPosNode. PBKeyNode. PBCountedKeyNode } includes: kind) ifFalse: [
    ^ self _corrupt: 'not an AVL node: ' , aRoot printString].
  maxDepth := aRoot height.
  (maxDepth between: 1 and: self maxHeight) ifFalse: [
    ^ self _corrupt: 'implausible root height ' , maxDepth printString , ' at ' , aRoot printString].
  ^ self _check: aRoot kind: kind maxDepth: maxDepth keyed: kind ~~ PBPosNode weighted: kind == PBCountedKeyNode.

"The walk of check:. A stack entry is { node. left. right. depth } before its
 children are checked and { node. left. right. nil } after; a result is
 { height. count. min order key. max order key. weight }.

 One handler covers the walk. While a node's key or weighted value is
 validated, what names it and validated holds the node; a PBValidationError
 signalled then is reported as corruption of that node's key or weighted
 value. Only that exact class is the refusal of an invalid value: any subclass
 (PBClosedError, PBReferenceError: a load), and any error signalled outside
 those two validations, passes as it is."
PBAvl class >> _check: aRoot kind: kind maxDepth: maxDepth keyed: keyed weighted: weighted
  | empty results stack what validated |
  empty := { 0. 0. nil. nil. 0 }.
  results := OrderedCollection new.
  stack := OrderedCollection new.
  what := nil.
  [stack addLast: (self _checkEntry: aRoot kind: kind depth: 1 maxDepth: maxDepth).
  [stack notEmpty] whileTrue: [
    | entry node left right depth |
    entry := stack removeLast.
    node := entry at: 1.
    left := entry at: 2.
    right := entry at: 3.
    depth := entry at: 4.
    depth isNil
      ifFalse: [
        stack addLast: { node. left. right. nil }.
        right isNil ifFalse: [stack addLast: (self _checkEntry: right kind: kind depth: depth + 1 maxDepth: maxDepth)].
        left isNil ifFalse: [stack addLast: (self _checkEntry: left kind: kind depth: depth + 1 maxDepth: maxDepth)]]
      ifTrue: [
        | rightRes leftRes lh rh height count nmin nmax weight |
        "Children were pushed right then left, so their results arrive left then right."
        rightRes := right isNil ifTrue: [empty] ifFalse: [results removeLast].
        leftRes := left isNil ifTrue: [empty] ifFalse: [results removeLast].
        lh := leftRes at: 1.
        rh := rightRes at: 1.
        height := node height.
        count := node count.
        height = (1 + (lh max: rh)) ifFalse: [
          ^ self _corrupt: 'wrong height ' , height printString , ' at ' , node printString
            , ': the children heights are ' , lh printString , ' and ' , rh printString].
        count = (1 + (leftRes at: 2) + (rightRes at: 2)) ifFalse: [
          ^ self _corrupt: 'wrong count ' , count printString , ' at ' , node printString , ': the children counts are '
            , (leftRes at: 2) printString , ' and ' , (rightRes at: 2) printString].
        (lh - rh) abs > 1 ifTrue: [
          ^ self _corrupt: 'AVL balance violated at ' , node printString , ': the children heights are '
            , lh printString , ' and ' , rh printString].
        nmin := nil.
        nmax := nil.
        keyed ifTrue: [
          | k |
          "Recomputed from the key, as check_invariants does, and compared with
           the cached one: the verifier never trusts what the writer cached."
          validated := node.
          what := 'key'.
          k := PBKeys orderKey: node key.
          what := nil.
          node knownOrderKey isNil ifFalse: [
            (k compareWith: node knownOrderKey) = 0 ifFalse: [
              ^ self _corrupt: 'the cached order key of ' , node printString , ' differs from the key''s ('
                , (PBKeys _preview: node key) , ')']].
          (leftRes at: 4) isNil ifFalse: [
            ((leftRes at: 4) compareWith: k) < 0 ifFalse: [^ self _keyOrderViolatedAt: node]].
          (rightRes at: 3) isNil ifFalse: [
            (k compareWith: (rightRes at: 3)) < 0 ifFalse: [^ self _keyOrderViolatedAt: node]].
          nmin := (leftRes at: 3) isNil ifTrue: [k] ifFalse: [leftRes at: 3].
          nmax := (rightRes at: 4) isNil ifTrue: [k] ifFalse: [rightRes at: 4]].
        weight := 0.
        weighted ifTrue: [
          | own |
          validated := node.
          what := 'weighted value'.
          own := _PBTree countOfPair: node value.
          what := nil.
          weight := node weight.
          weight = (own + (leftRes at: 5) + (rightRes at: 5)) ifFalse: [
            ^ self _corrupt: 'wrong weight ' , weight printString , ' at ' , node printString , ': its own count is '
              , own printString , ', the children weights ' , (leftRes at: 5) printString , ' and '
              , (rightRes at: 5) printString]].
        results addLast: { height. count. nmin. nmax. weight }]]]
    on: PBValidationError do: [:e |
      (what isNil or: [e class ~~ PBValidationError]) ifTrue: [^ e pass].
      self _corrupt: 'the ' , what , ' of ' , validated printString , ' is not valid: ' , e messageText].
  ^ aRoot.

"The stack entry of aNode at aDepth: its children read once and checked (a node
 of the tree's exact class, or nil)."
PBAvl class >> _checkEntry: aNode kind: kind depth: depth maxDepth: maxDepth
  depth > maxDepth ifTrue: [
    ^ self _corrupt: 'a path deeper than the root height ' , maxDepth printString , ' at ' , aNode printString
      , ' (a cycle or a wrong height)'].
  ^ { aNode. self _child: aNode left of: aNode kind: kind. self _child: aNode right of: aNode kind: kind. depth }.

PBAvl class >> _child: aChild of: aNode kind: kind
  "A child of the tree's exact class first (the common case, with no isKindOf:)."
  | child |
  aChild isNil ifTrue: [^ nil].
  aChild class == kind ifTrue: [^ aChild].
  child := _PBTree node: aChild kind: PBNode in: aNode.
  child isNil ifTrue: [^ nil].
  child class == kind ifFalse: [
    ^ self _corrupt: 'mixed node kind: a ' , child class typeName , ' under a ' , kind typeName , ' tree'].
  ^ child.

PBAvl class >> _keyOrderViolatedAt: aNode
  ^ self _corrupt: 'key order violated at ' , aNode printString , ' (key ' , (PBKeys _preview: aNode key) , ')'.
