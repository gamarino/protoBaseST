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
type is expected). The integer fields a walk reads (count) must be Integers.

Writes (plan Task 14) are PBAvl's class methods, the functions of ProtoBase's
avl.py over a root node, or nil for the empty tree:

  PBAvl posAt: root index: i                  pos_get (the value, unboxed)
  PBAvl posInsert: root at: i value: v        pos_insert (0 <= i <= count)
  PBAvl posAppend: root value: v              pos_insert at count
  PBAvl posSet: root at: i value: v           pos_set (0 <= i < count)
  PBAvl posRemove: root at: i                 pos_remove (0 <= i < count)
  PBAvl keyAt: root key: k                    the node of key k, or nil
  PBAvl keyPut: root key: k value: v nodeClass: aClass     key_put
  PBAvl keyRemove: root key: k                key_remove
  PBAvl do: aBlock over: root                 each node, in order
  PBAvl check: root                           check_invariants

Every write answers a new root and never changes a node: it builds new nodes
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

PBAtom subclass: #PBNode classVariableNames: 'Shapes'.

PBNode class >> typeName
  ^ 'proto_db.avl._Node'.

PBNode class >> requiredFields
  ^ #('left' 'right' 'height' 'count').

PBNode class >> persistedFields
  ^ #('left' 'right' 'height' 'count').

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

PBNode subclass: #PBKeyNode.

PBKeyNode class >> typeName
  ^ 'proto_db.avl.KeyNode'.

PBKeyNode class >> requiredFields
  ^ #('key' 'value' 'left' 'right' 'height' 'count').

PBKeyNode class >> persistedFields
  ^ #('key' 'value' 'left' 'right' 'height' 'count').

PBKeyNode >> key
  ^ self stateAt: 'key'.

PBKeyNode subclass: #PBCountedKeyNode.

PBCountedKeyNode class >> typeName
  ^ 'proto_db.avl.CountedKeyNode'.

PBCountedKeyNode class >> requiredFields
  ^ #('key' 'value' 'left' 'right' 'height' 'count' 'weight').

PBCountedKeyNode class >> persistedFields
  ^ #('key' 'value' 'left' 'right' 'height' 'count' 'weight').

"The sum of the counts (value at: 2) of this subtree."
PBCountedKeyNode >> weight
  ^ _PBTree integer: (self stateAt: 'weight') field: 'weight' of: self.

PBAtom subclass: #PBValueBox.

PBValueBox class >> typeName
  ^ 'proto_db.avl.ValueBox'.

PBValueBox class >> requiredFields
  ^ #('value').

PBValueBox class >> persistedFields
  ^ #('value').

"The boxed value."
PBValueBox >> value
  ^ self stateAt: 'value'.

{ PBNode. PBPosNode. PBKeyNode. PBCountedKeyNode. PBValueBox } do: [:each | PBTypeRegistry register: each].

"The shape of the new atoms of each concrete class (plan Task 14): { its
 persistedFields. the PBMapKeyIndex over them. its tag }, computed once, when
 the module loads, and shared by every state the writes build (a key array and
 its index are never changed)."
PBNode class >> _initializeShapes
  | shapes |
  shapes := Dictionary new.
  { PBPosNode. PBKeyNode. PBCountedKeyNode. PBValueBox } do: [:each |
    shapes at: each put: { each persistedFields. PBMapKeyIndex on: each persistedFields. PBTypeRegistry tagFor: each }].
  Shapes := shapes.

"A new, unsaved atom of aClass whose state holds anArray, the values of
 aClass persistedFields in order."
PBNode class >> _new: aClass values: anArray
  | shape |
  shape := Shapes at: aClass.
  ^ aClass
    _unsavedWithState: (PBFrozenDict _keys: (shape at: 1) index: (shape at: 2) values: anArray)
    tag: (shape at: 3).

PBNode _initializeShapes.

"=== the walks ==============================================================="

Object subclass: #_PBTree.

"anObject's value as an Integer field (not a Boolean); PBCorruptionError otherwise."
_PBTree class >> integer: anObject field: aName of: anAtom
  "Nested ifTrue: (inlined by the compiler), not and: (a block): every walk reads
   height and count through here."
  anObject isInteger ifTrue: [
    anObject == true ifFalse: [anObject == false ifFalse: [^ anObject]]].
  ^ PBCorruptionError signal: 'the ' , aName , ' of ' , anAtom printString , ' is not an integer: '
    , (PBKeys _preview: anObject).

"A stored node value without its box."
_PBTree class >> unboxed: aStoredValue
  (aStoredValue isKindOf: PBValueBox) ifTrue: [^ aStoredValue value].
  ^ aStoredValue.

"aNode, a node of aKind (a node class) or nil: another value is PBCorruptionError,
 an opaque atom PBNotSupportedError naming its type."
_PBTree class >> node: aNode kind: aKind in: anOwner
  aNode isNil ifTrue: [^ nil].
  (aNode isKindOf: aKind) ifTrue: [^ aNode].
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
  | stack node |
  stack := OrderedCollection new.
  node := self node: aRoot kind: aKind in: anOwner.
  [stack notEmpty or: [node notNil]] whileTrue: [
    [node notNil] whileTrue: [
      stack addLast: node.
      node := self node: node left kind: aKind in: anOwner].
    node := stack removeLast.
    aBlock value: node.
    node := self node: node right kind: aKind in: anOwner].

"The node at position anIndex (0-based, 0 <= anIndex < count) of a positional
 tree (pos_get). A tree whose counts do not lead to a node is PBCorruptionError."
_PBTree class >> nodeAt: anIndex of: aRoot in: anOwner
  | node index leftCount |
  node := self node: aRoot kind: PBPosNode in: anOwner.
  index := anIndex.
  [node notNil] whileTrue: [
    leftCount := self count: node left kind: PBPosNode in: anOwner.
    index < leftCount
      ifTrue: [node := self node: node left kind: PBPosNode in: anOwner]
      ifFalse: [
        index = leftCount ifTrue: [^ node].
        index := index - leftCount - 1.
        node := self node: node right kind: PBPosNode in: anOwner]].
  ^ PBCorruptionError signal: 'the positional tree of ' , anOwner printString , ' has no node at '
    , anIndex printString , ': its counts are inconsistent'.

"The node of the keyed tree aRoot whose key has the order key anOrderKey, or
 nil (key_get)."
_PBTree class >> nodeWithKey: anOrderKey of: aRoot in: anOwner
  | node c |
  node := self node: aRoot kind: PBKeyNode in: anOwner.
  [node notNil] whileTrue: [
    c := anOrderKey compareWith: (PBKeys orderKey: node key).
    c = 0 ifTrue: [^ node].
    node := self node: (c < 0 ifTrue: [node left] ifFalse: [node right]) kind: PBKeyNode in: anOwner].
  ^ nil.

"=== new nodes (plan Task 14) ================================================="

"A new node of this class with this node's payload over aLeft and aRight
 (ProtoBase _Node._with_children); the stored value is kept, a box included."
PBNode >> withLeft: aLeft right: aRight
  ^ self subclassResponsibility.

"A new positional node holding aValue (boxed when large) over aLeft and aRight;
 height and count are computed from the children."
PBPosNode class >> value: aValue left: aLeft right: aRight
  ^ PBNode _new: self values: {
    _PBTree boxed: aValue. aLeft. aRight.
    _PBTree heightOf: aLeft and: aRight. _PBTree countOf: aLeft and: aRight }.

PBPosNode >> withLeft: aLeft right: aRight
  ^ self class value: self storedValue left: aLeft right: aRight.

"A new keyed node of key aKey (never boxed) holding aValue (boxed when large)
 over aLeft and aRight. The key's order is the caller's concern (PBAvl)."
PBKeyNode class >> key: aKey value: aValue left: aLeft right: aRight
  ^ PBNode _new: self values: {
    aKey. _PBTree boxed: aValue. aLeft. aRight.
    _PBTree heightOf: aLeft and: aRight. _PBTree countOf: aLeft and: aRight }.

PBKeyNode >> withLeft: aLeft right: aRight
  ^ self class key: self key value: self storedValue left: aLeft right: aRight.

"A new node of this class with this node's key and children, holding aValue
 (ProtoBase KeyNode._with_value: the stored key object is kept)."
PBKeyNode >> withValue: aValue
  ^ self class key: self key value: aValue left: self left right: self right.

"As PBKeyNode's, for a value that is a (payload, count) pair (PBValidationError
 otherwise, ProtoBase _value_count); weight is the count plus the children's
 weights."
PBCountedKeyNode class >> key: aKey value: aValue left: aLeft right: aRight
  | own |
  own := _PBTree countOfPair: aValue.
  ^ PBNode _new: self values: {
    aKey. _PBTree boxed: aValue. aLeft. aRight.
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
  | large |
  (aValue isKindOf: PBValueBox) ifTrue: [^ aValue].
  large := false.
  aValue isString ifTrue: [aValue isSymbol ifFalse: [large := aValue size >= self valueBoxMin]].
  (aValue isKindOf: ByteArray) ifTrue: [large := aValue size >= self valueBoxMin].
  large ifTrue: [^ PBNode _new: PBValueBox values: { aValue }].
  ^ aValue.

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

"aRoot is nil or a node of aKind; PBValidationError otherwise."
PBAvl class >> _root: aRoot kind: aKind
  (aRoot isNil or: [aRoot isKindOf: aKind]) ifTrue: [^ aRoot].
  ^ PBValidationError signal: 'PBAvl: a ' , aKind typeName , ' tree (or nil) was expected, not '
    , (PBKeys _preview: aRoot).

"anIndex is an Integer (not a Boolean) in 0..anUpper; PBValidationError otherwise."
PBAvl class >> _index: anIndex upTo: anUpper
  (anIndex isInteger and: [anIndex ~~ true and: [anIndex ~~ false]]) ifFalse: [
    ^ PBValidationError signal: 'PBAvl: an index must be an Integer, not ' , (PBKeys _preview: anIndex)].
  (anIndex between: 0 and: anUpper) ifFalse: [
    ^ PBValidationError signal: 'PBAvl: index ' , anIndex printString , ' out of range 0..' , anUpper printString].
  ^ anIndex.

"A child of aNode (a node of its own kind, or nil), checked as a walk checks it."
PBAvl class >> _left: aNode
  ^ _PBTree node: aNode left kind: PBNode in: aNode.

PBAvl class >> _right: aNode
  ^ _PBTree node: aNode right kind: PBNode in: aNode.

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

"--- keyed trees ---"

"The node of the keyed tree aRoot whose key is aKey (equal order keys: 1 and
 1.0 are one key), or nil. An unorderable aKey is PBValidationError."
PBAvl class >> keyAt: aRoot key: aKey
  | okey |
  self _root: aRoot kind: PBKeyNode.
  okey := PBKeys orderKey: aKey.
  ^ _PBTree nodeWithKey: okey of: aRoot in: aRoot.

"A tree with aKey mapped to aValue (ProtoBase key_put). An existing key keeps
 its stored key object and takes the new value; a new key gets a node of the
 tree's class (the root's), or of aClass (PBKeyNode, PBCountedKeyNode) when the
 tree is empty."
PBAvl class >> keyPut: aRoot key: aKey value: aValue nodeClass: aClass
  | okey make |
  self _root: aRoot kind: PBKeyNode.
  okey := PBKeys orderKey: aKey.
  make := aRoot isNil ifTrue: [aClass] ifFalse: [aRoot class].
  (make isClassObject and: [make == PBKeyNode or: [make inheritsFrom: PBKeyNode]]) ifFalse: [
      ^ PBValidationError signal: 'PBAvl keyPut: nodeClass must be a keyed node class, not ' , make printString].
  ^ self _keyPut: aRoot okey: okey key: aKey value: aValue make: make.

PBAvl class >> _keyPut: aNode okey: anOrderKey key: aKey value: aValue make: aClass
  | c |
  aNode isNil ifTrue: [^ aClass key: aKey value: aValue left: nil right: nil].
  c := anOrderKey compareWith: (PBKeys orderKey: aNode key).
  c < 0 ifTrue: [
    ^ self _balance: aNode
      left: (self _keyPut: (self _left: aNode) okey: anOrderKey key: aKey value: aValue make: aClass)
      right: (self _right: aNode)].
  c > 0 ifTrue: [
    ^ self _balance: aNode
      left: (self _left: aNode)
      right: (self _keyPut: (self _right: aNode) okey: anOrderKey key: aKey value: aValue make: aClass)].
  ^ aNode withValue: aValue.

"A tree without aKey (ProtoBase key_remove); aRoot itself when aKey is absent."
PBAvl class >> keyRemove: aRoot key: aKey
  self _root: aRoot kind: PBKeyNode.
  ^ self _keyRemove: aRoot okey: (PBKeys orderKey: aKey).

PBAvl class >> _keyRemove: aNode okey: anOrderKey
  | c left right child |
  aNode isNil ifTrue: [^ nil].
  c := anOrderKey compareWith: (PBKeys orderKey: aNode key).
  c = 0 ifTrue: [^ self _removeNode: aNode].
  left := self _left: aNode.
  right := self _right: aNode.
  c < 0 ifTrue: [
    child := self _keyRemove: left okey: anOrderKey.
    ^ child == left ifTrue: [aNode] ifFalse: [self _balance: aNode left: child right: right]].
  child := self _keyRemove: right okey: anOrderKey.
  ^ child == right ifTrue: [aNode] ifFalse: [self _balance: aNode left: left right: child].

"--- walks ---"

"Evaluates aBlock with each node of the tree aRoot, in order (an explicit
 stack; node value answers a node's value unboxed)."
PBAvl class >> do: aBlock over: aRoot
  self _root: aRoot kind: PBNode.
  _PBTree nodesOf: aRoot kind: PBNode in: aRoot do: aBlock.

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
 weights. A child that is not a node is PBCorruptionError (an opaque atom
 PBNotSupportedError, as every walk). A key that has no order key, or a
 weighted value that is not a pair, is PBCorruptionError too: what a tree holds
 was checked when it was built. Post-order with an explicit stack, as
 ProtoBase: every node of a stored tree is loaded; a path longer than the
 root's height (a height lie) is reported, so the walk always ends.

 The walk runs once per operation in the randomized tests, so its loop reads
 each field once, uses ifTrue: (inlined) rather than and:/or: blocks, and
 turns the PBValidationError of a key or a weighted value into corruption with
 one handler around the walk."
PBAvl class >> check: aRoot
  | kind maxDepth keyed weighted current |
  aRoot isNil ifTrue: [^ nil].
  _PBTree node: aRoot kind: PBNode in: 'the tree checked'.
  kind := aRoot class.
  ({ PBPosNode. PBKeyNode. PBCountedKeyNode } includes: kind) ifFalse: [
    ^ self _corrupt: 'not an AVL node: ' , aRoot printString].
  maxDepth := aRoot height.
  (maxDepth between: 1 and: self maxHeight) ifFalse: [
    ^ self _corrupt: 'implausible root height ' , maxDepth printString , ' at ' , aRoot printString].
  keyed := kind ~~ PBPosNode.
  weighted := kind == PBCountedKeyNode.
  current := nil.
  [self _check: aRoot kind: kind maxDepth: maxDepth keyed: keyed weighted: weighted visiting: [:node | current := node]]
    on: PBValidationError do: [:e |
      ^ self _corrupt: 'the ' , (weighted ifTrue: ['key or weighted value'] ifFalse: ['key']) , ' of '
        , current printString , ' is not valid: ' , e messageText].
  ^ aRoot.

"The walk of check:. A stack entry is { node. left. right. depth } before its
 children are checked and { node. left. right. nil } after; a result is
 { height. count. min order key. max order key. weight }. aBlock is told the
 node whose key or value is being read."
PBAvl class >> _check: aRoot kind: kind maxDepth: maxDepth keyed: keyed weighted: weighted visiting: aBlock
  | empty results stack |
  empty := { 0. 0. nil. nil. 0 }.
  results := OrderedCollection new.
  stack := OrderedCollection new.
  stack addLast: (self _checkEntry: aRoot kind: kind depth: 1 maxDepth: maxDepth).
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
          aBlock value: node.
          k := PBKeys orderKey: node key.
          (leftRes at: 4) isNil ifFalse: [
            ((leftRes at: 4) compareWith: k) < 0 ifFalse: [^ self _keyOrderViolatedAt: node]].
          (rightRes at: 3) isNil ifFalse: [
            (k compareWith: (rightRes at: 3)) < 0 ifFalse: [^ self _keyOrderViolatedAt: node]].
          nmin := (leftRes at: 3) isNil ifTrue: [k] ifFalse: [leftRes at: 3].
          nmax := (rightRes at: 4) isNil ifTrue: [k] ifFalse: [rightRes at: 4]].
        weight := 0.
        weighted ifTrue: [
          | own |
          aBlock value: node.
          own := _PBTree countOfPair: node value.
          weight := node weight.
          weight = (own + (leftRes at: 5) + (rightRes at: 5)) ifFalse: [
            ^ self _corrupt: 'wrong weight ' , weight printString , ' at ' , node printString , ': its own count is '
              , own printString , ', the children weights ' , (leftRes at: 5) printString , ' and '
              , (rightRes at: 5) printString]].
        results addLast: { height. count. nmin. nmax. weight }]].
  ^ aRoot.

"The stack entry of aNode at aDepth: its children read once and checked (a node
 of the tree's exact class, or nil)."
PBAvl class >> _checkEntry: aNode kind: kind depth: depth maxDepth: maxDepth
  depth > maxDepth ifTrue: [
    ^ self _corrupt: 'a path deeper than the root height ' , maxDepth printString , ' at ' , aNode printString
      , ' (a cycle or a wrong height)'].
  ^ { aNode. self _child: aNode left of: aNode kind: kind. self _child: aNode right of: aNode kind: kind. depth }.

PBAvl class >> _child: aChild of: aNode kind: kind
  | child |
  child := _PBTree node: aChild kind: PBNode in: aNode.
  child isNil ifTrue: [^ nil].
  child class == kind ifFalse: [
    ^ self _corrupt: 'mixed node kind: a ' , child class typeName , ' under a ' , kind typeName , ' tree'].
  ^ child.

PBAvl class >> _keyOrderViolatedAt: aNode
  ^ self _corrupt: 'key order violated at ' , aNode printString , ' (key ' , (PBKeys _preview: aNode key) , ')'.
