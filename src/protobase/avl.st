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

Writes (path copying, balancing, boxing on write) come with plan Task 14."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/registry'.
Import from: 'protobase/keys'.

"=== the node classes ========================================================"

PBAtom subclass: #PBNode.

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
  self isClassObject ifTrue: [^ self].
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
  self isClassObject ifTrue: [^ self].
  ^ self stateAt: 'value'.

{ PBNode. PBPosNode. PBKeyNode. PBCountedKeyNode. PBValueBox } do: [:each | PBTypeRegistry register: each].

"=== the walks ==============================================================="

Object subclass: #_PBTree.

"anObject's value as an Integer field (not a Boolean); PBCorruptionError otherwise."
_PBTree class >> integer: anObject field: aName of: anAtom
  (anObject isInteger and: [anObject ~~ true and: [anObject ~~ false]]) ifTrue: [^ anObject].
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
