"-- collections.st: the collections of format 4, read side --

ProtoBase's collections (format spec v2.0.0rc1, 'Collections'; ProtoBase
proto_db/collections/*.py at the tag), with the read API of the design spec
5.2. Every collection persists count and indexes (a reference to a
PBIndexSet) plus its own fields:

  PBIndexSet                 proto_db.collections.IndexSet: root, a KeyNode tree
                             from index name to index (not a collection)
  PBIndexedCollection        proto_db.collections.IndexedCollection (abstract)
  PBList                     List: root, a PosNode tree of the elements in order
  PBDictionary               Dictionary: root, a KeyNode tree by the order key of
                             the key, node value the mapped value
  PBHashDictionary           HashDictionary: root, a KeyNode tree from the hash
                             key of a key to a bucket tuple of (key, value) tuples
  PBHashBuckets              sets._HashBuckets (abstract): the bucket trees of
  PBSet                      Set (a bucket holds elements) and
  PBCountedSet               CountedSet (a bucket holds (element, count) pairs;
                             count distinct elements, total_count their sum)
  PBRepeatedKeysDictionary   RepeatedKeysDictionary: root, a KeyNode tree by key
                             whose values are non-empty CountedSets of records

Every collection message answers a new version; the receiver never changes
(plan Tasks 15-16). The read messages:

  count, size                  the persisted count (size is the synonym)
  do: aBlock                   the elements, in the collection's own order
  elements                     the same, as an Array
  indexNames, getIndex: aName  the indexes (sorted names; nil when absent)
  PBList >> getAt: i           the element at the 0-based position i; a negative
                               i counts from the end; another i (out of range, not
                               an Integer) is PBValidationError (plan call C15)
  getAt: k, getAt: k default: d, has: k
                               the dictionaries (and has: of the sets): a key is
                               found by its order key, so 1, 1.0 and Decimal 1.00
                               find one key and true another; an unorderable key
                               is PBValidationError (ProtoBase: order_key raises)
  keys, values, items, keysAndValuesDo: aBlock
                               the dictionaries; items are Associations
  countOf: e, items            PBCountedSet (items: element -> count)
  totalCount                   PBCountedSet and PBRepeatedKeysDictionary

The writes (plan Task 15; the operation logs and the set algebra come with
Task 16). Each answers a new collection, a new atom with its own oid (drawn
on first need), and leaves the receiver as it was; values (and keys and
elements) pass through PBCodec canonical: at once:

  PBList new, PBDictionary new, PBSet new, ...
                               an empty collection with an empty PBIndexSet
  PBList >> setAt: i value: v, insertAt: i value: v, removeAt: i,
            appendFirst: v, appendLast: v, extend: aCollection,
            sliceFrom: a to: b, head: n, tail: n
                               ProtoBase's List: 0-based positions, a
                               negative one counting from the end; a position
                               out of range or not an Integer is
                               PBValidationError (insertAt: count appends);
                               slices clamp like Python slices (a bound may
                               be nil); extend: of nothing answers the
                               receiver, as ProtoBase's
  PBDictionary >> setAt: k value: v, removeAt: k
                               an absent key's removeAt: answers a new version
                               with the same content, as ProtoBase's
  PBSet >> add: e, remove: e   the same for a present element's add: and an
                               absent element's remove:

The trees are built by PBAvl, as ProtoBase's avl.py builds them, so one
sequence of operations gives the same nodes in both implementations. A
collection with an index refuses every change with PBNotSupportedError naming
the indexes (design spec 7.4): ProtoBase maintains the indexes in the same
step, which protoBaseST cannot do. A new collection writes its fields in the
order ProtoBase sets them: indexes, count, then its own fields for an empty
one, persistedFields for a later version.

These names keep ProtoBase's meaning, which differs from Pharo's for add:,
remove: and removeAt: (design spec 5.3): their result is the new version, and
a statement that discards it changes nothing.

The iteration orders are ProtoBase's: a List by position, a Dictionary and a
RepeatedKeysDictionary by key order; a HashDictionary, a Set and a CountedSet
in tree order (the hash key), then bucket order. A Dictionary's elements (what
its indexes see) are its values; a RepeatedKeysDictionary's are the distinct
records of each key, key by key.

A probe key is made canonical first (PBCodec canonical:, so an Array finds a
list) and then ordered or hashed (PBKeys). A bucket that is not a tuple, or an
entry that is not a pair, is PBCorruptionError."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/registry'.
Import from: 'protobase/keys'.
Import from: 'protobase/codec'.
Import from: 'protobase/avl'.

"=== PBIndexSet ==============================================================="

PBAtom subclass: #PBIndexSet.

PBIndexSet class >> typeName
  ^ 'proto_db.collections.IndexSet'.

PBIndexSet class >> requiredFields
  ^ #('root').

PBIndexSet class >> persistedFields
  ^ #('root').

"The names of the indexes, sorted."
PBIndexSet >> names
  | out |
  out := OrderedCollection new.
  _PBTree nodesOf: (self stateAt: 'root') kind: PBKeyNode in: self do: [:node | out add: node key].
  ^ out asArray.

"The index named aName, or nil."
PBIndexSet >> get: aName
  | node |
  (aName isString and: [aName isSymbol not]) ifFalse: [^ nil].
  node := _PBTree nodeWithKey: (PBKeys orderKey: aName) of: (self stateAt: 'root') in: self.
  ^ node isNil ifTrue: [nil] ifFalse: [node value].

PBIndexSet >> size
  ^ _PBTree count: (self stateAt: 'root') kind: PBKeyNode in: self.

"An empty index set (ProtoBase IndexSet())."
PBIndexSet class >> new
  ^ self _unsavedWithState: (PBFrozenDict withAssociations: { 'root' -> nil }).

PBIndexSet >> isEmpty
  ^ (self stateAt: 'root') isNil.

"=== PBIndexedCollection ======================================================"

PBAtom subclass: #PBIndexedCollection classVariableNames: 'Shapes'.

PBIndexedCollection class >> typeName
  ^ 'proto_db.collections.IndexedCollection'.

PBIndexedCollection class >> requiredFields
  ^ #('count' 'indexes').

PBIndexedCollection class >> persistedFields
  ^ #('count' 'indexes').

"The persisted count."
PBIndexedCollection >> count
  ^ _PBTree integer: (self stateAt: 'count') field: 'count' of: self.

PBIndexedCollection >> size
  ^ self count.

PBIndexedCollection >> isEmpty
  ^ self count = 0.

PBIndexedCollection >> notEmpty
  ^ self isEmpty not.

"The PBIndexSet of the collection."
PBIndexedCollection >> indexes
  | set |
  set := self stateAt: 'indexes'.
  (set isKindOf: PBIndexSet) ifTrue: [^ set].
  ^ _PBTree node: set kind: PBIndexSet in: self.

PBIndexedCollection >> indexNames
  | set |
  set := self indexes.
  ^ set isNil ifTrue: [#()] ifFalse: [set names].

"The index named aName, or nil."
PBIndexedCollection >> getIndex: aName
  | set |
  set := self indexes.
  ^ set isNil ifTrue: [nil] ifFalse: [set get: aName].

"Evaluates aBlock with each element (what the indexes see), in order."
PBIndexedCollection >> do: aBlock
  ^ PBNotSupportedError signal: self class name , ': ' , self class typeName , ' is abstract: it has no elements'.

"The elements, in order, as an Array."
PBIndexedCollection >> elements
  | out |
  out := OrderedCollection new.
  self do: [:each | out add: each].
  ^ out asArray.

"The canonical form of a probe key."
PBIndexedCollection >> _probe: aKey
  ^ PBCodec canonical: aKey.

"--- new versions ---"

"An empty collection of this class (ProtoBase's constructor): no elements, an
 empty PBIndexSet, and the fields in the order ProtoBase sets them (indexes,
 count, then the class's own)."
PBIndexedCollection class >> new
  | fields |
  (self == PBIndexedCollection or: [self == PBHashBuckets]) ifTrue: [
    ^ PBNotSupportedError signal: self name , ' is abstract: make a concrete collection'].
  fields := OrderedCollection new.
  fields addLast: 'indexes' -> PBIndexSet new; addLast: 'count' -> 0.
  self persistedFields do: [:f |
    (f = 'count' or: [f = 'indexes']) ifFalse: [fields addLast: f -> (self _emptyValueOf: f)]].
  ^ self _unsavedWithState: (PBFrozenDict withAssociations: fields asArray).

"The value of a field of an empty collection, other than count and indexes."
PBIndexedCollection class >> _emptyValueOf: aField
  ^ nil.

"The PBMapKeyIndex of persistedFields: computed once for the built-in
 classes when the module loads (Shapes), on each call for another class."
PBIndexedCollection class >> _fieldIndex
  ^ Shapes at: self ifAbsent: [PBMapKeyIndex on: self persistedFields].

PBIndexedCollection class >> _initializeShapes
  | shapes |
  shapes := Dictionary new.
  { PBList. PBDictionary. PBHashDictionary. PBSet. PBCountedSet. PBRepeatedKeysDictionary } do: [:each |
    shapes at: each put: (PBMapKeyIndex on: each persistedFields)].
  Shapes := shapes.

"A new version of this collection (ProtoBase IndexedCollection._with): root
 and count as given, every other field (indexes included) carried over, in
 persistedFields order."
PBIndexedCollection >> _withRoot: aRoot count: aCount
  | cls fields values |
  cls := self class.
  fields := cls persistedFields.
  values := Array new: fields size.
  1 to: fields size do: [:i |
    | f |
    f := fields at: i.
    values at: i put: (f = 'root'
      ifTrue: [aRoot]
      ifFalse: [f = 'count' ifTrue: [aCount] ifFalse: [self stateAt: f]])].
  ^ cls _unsavedWithState: (PBFrozenDict _keys: fields index: cls _fieldIndex values: values) tag: nil.

"Signals PBNotSupportedError naming the indexes when the collection has any:
 protoBaseST cannot maintain an index, so it refuses every change to an
 indexed collection (design spec 7.4), where ProtoBase would update the
 indexes in the same step."
PBIndexedCollection >> _checkWritable: aSelector
  | set |
  set := self indexes.
  (set isNil or: [set isEmpty]) ifTrue: [^ self].
  ^ PBNotSupportedError signal: self class name , ' ' , aSelector , ': the collection has the indexes '
    , (set names inject: '' into: [:acc :each | acc isEmpty ifTrue: [each] ifFalse: [acc , ', ' , each]])
    , ', which protoBaseST cannot maintain: it refuses every change to an indexed collection (design spec 7.4)'.

"=== PBList ==================================================================="

PBIndexedCollection subclass: #PBList.
PBList comment: 'Every message answers a new version; the receiver never changes. Positions are zero-based, as in ProtoBase. getAt: 0 is the first element, and a negative position counts from the end. ProtoBase''s List (proto_db.collections.List): a sequence over a positional AVL tree. setAt:value:, insertAt:value:, removeAt:, appendFirst:, appendLast:, extend:, sliceFrom:to:, head: and tail: answer the new list; a statement that discards the result changes nothing.'.

PBList class >> typeName
  ^ 'proto_db.collections.List'.

PBList class >> requiredFields
  ^ #('root' 'count' 'indexes').

PBList class >> persistedFields
  ^ #('root' 'count' 'indexes').

PBList >> do: aBlock
  _PBTree nodesOf: (self stateAt: 'root') kind: PBPosNode in: self do: [:node | aBlock value: node value].

"The position anIndex stands for, in 0 .. anUpper (ProtoBase List._position,
 plan call C15): a negative index counts from the end; an index that is not an
 Integer (a Boolean included), or outside, is PBValidationError."
PBList >> _position: anIndex upper: anUpper
  | position |
  (anIndex isInteger and: [anIndex ~~ true and: [anIndex ~~ false]]) ifFalse: [
    ^ PBValidationError signal: 'A list position must be an Integer, not ' , (PBKeys _preview: anIndex)].
  position := anIndex < 0 ifTrue: [anIndex + self count] ifFalse: [anIndex].
  (position between: 0 and: anUpper) ifFalse: [
    ^ PBValidationError signal: 'List position ' , anIndex printString , ' out of range for a list of '
      , self count printString].
  ^ position.

"The element at anIndex: 0-based, a negative index counts from the end."
PBList >> getAt: anIndex
  | position |
  position := self _position: anIndex upper: self count - 1.
  ^ (_PBTree nodeAt: position of: (self stateAt: 'root') in: self) value.

"--- writes (ProtoBase List mutators) ---"

"A list whose element at anIndex is aValue."
PBList >> setAt: anIndex value: aValue
  | position value |
  self _checkWritable: 'setAt:value:'.
  position := self _position: anIndex upper: self count - 1.
  value := PBCodec canonical: aValue.
  ^ self _withRoot: (PBAvl posSet: (self stateAt: 'root') at: position value: value) count: self count.

"A list with aValue inserted before position anIndex (insertAt: count appends)."
PBList >> insertAt: anIndex value: aValue
  | position value |
  self _checkWritable: 'insertAt:value:'.
  position := self _position: anIndex upper: self count.
  value := PBCodec canonical: aValue.
  ^ self _withRoot: (PBAvl posInsert: (self stateAt: 'root') at: position value: value) count: self count + 1.

"A list without the element at anIndex (a new list, unlike Pharo's
 removeAt:, which removes in place and answers the element)."
PBList >> removeAt: anIndex
  | position |
  self _checkWritable: 'removeAt:'.
  position := self _position: anIndex upper: self count - 1.
  ^ self _withRoot: (PBAvl posRemove: (self stateAt: 'root') at: position) count: self count - 1.

"A list with aValue before the first element."
PBList >> appendFirst: aValue
  ^ self insertAt: 0 value: aValue.

"A list with aValue after the last element."
PBList >> appendLast: aValue
  ^ self insertAt: self count value: aValue.

"A list with the elements of aCollection (anything answering do:, a PBList
 included) appended in order; read in full before anything is built. An empty
 aCollection answers the receiver, as ProtoBase's extend."
PBList >> extend: aCollection
  | values |
  self _checkWritable: 'extend:'.
  (aCollection isClassObject not and: [aCollection respondsTo: #do:]) ifFalse: [
    ^ PBValidationError signal: 'PBList extend: a collection was expected, not ' , (PBKeys _preview: aCollection)].
  values := OrderedCollection new.
  aCollection do: [:each | values addLast: (PBCodec canonical: each)].
  values isEmpty ifTrue: [^ self].
  ^ self
    _withRoot: (PBAvl posConcat: (self stateAt: 'root') with: (PBAvl posFromArray: values asArray))
    count: self count + values size.

"The list of the elements at aStart .. aStop - 1, with Python slice rules
 (ProtoBase List.slice): a bound may be nil (the start or the end), a negative
 one counts from the end, and both are clamped to the list; a stop before the
 start gives an empty list. A new list, built in O(log n)."
PBList >> sliceFrom: aStart to: aStop
  | n lo hi |
  self _checkWritable: 'sliceFrom:to:'.
  n := self count.
  lo := self _sliceBound: aStart default: 0 count: n.
  hi := (self _sliceBound: aStop default: n count: n) max: lo.
  ^ self _withRoot: (PBAvl posSlice: (self stateAt: 'root') from: lo to: hi) count: hi - lo.

"The first anInteger elements (sliceFrom: nil to: anInteger: a negative
 anInteger drops elements from the end)."
PBList >> head: anInteger
  ^ self sliceFrom: nil to: anInteger.

"The elements from position anInteger on (sliceFrom: anInteger to: nil: a
 negative anInteger keeps the last elements)."
PBList >> tail: anInteger
  ^ self sliceFrom: anInteger to: nil.

"A slice bound as Python's slice.indices computes it for step 1: nil is
 aDefault, a negative bound counts from the end, and the result is clamped to
 0 .. n. A bound that is not an Integer (a Boolean included) is
 PBValidationError."
PBList >> _sliceBound: aBound default: aDefault count: n
  | b |
  aBound isNil ifTrue: [^ aDefault].
  (aBound isInteger and: [aBound ~~ true and: [aBound ~~ false]]) ifFalse: [
    ^ PBValidationError signal: 'A slice bound must be an Integer or nil, not ' , (PBKeys _preview: aBound)].
  b := aBound < 0 ifTrue: [aBound + n] ifFalse: [aBound].
  ^ (b max: 0) min: n.

"=== PBDictionary ============================================================="

PBIndexedCollection subclass: #PBDictionary.
PBDictionary comment: 'Every message answers a new version; the receiver never changes. ProtoBase''s Dictionary (proto_db.collections.Dictionary): a map over a keyed AVL tree ordered by the order key of the key, so 1, 1.0 and Decimal 1.00 are one key and true another. setAt:value: and removeAt: answer the new dictionary (removeAt: of an absent key a new version with the same content); a statement that discards the result changes nothing.'.

PBDictionary class >> typeName
  ^ 'proto_db.collections.Dictionary'.

PBDictionary class >> requiredFields
  ^ #('root' 'count' 'indexes').

PBDictionary class >> persistedFields
  ^ #('root' 'count' 'indexes').

PBDictionary >> _nodeAt: aKey
  | key |
  key := self _probe: aKey.
  ^ _PBTree nodeWithKey: (PBKeys orderKey: key) of: (self stateAt: 'root') in: self.

PBDictionary >> getAt: aKey
  ^ self getAt: aKey default: nil.

PBDictionary >> getAt: aKey default: aDefault
  | node |
  node := self _nodeAt: aKey.
  ^ node isNil ifTrue: [aDefault] ifFalse: [node value].

PBDictionary >> has: aKey
  ^ (self _nodeAt: aKey) notNil.

"Evaluates aBlock with each key and its value, in key order."
PBDictionary >> keysAndValuesDo: aBlock
  _PBTree nodesOf: (self stateAt: 'root') kind: PBKeyNode in: self do: [:node |
    aBlock value: node key value: node value].

"The values, in key order (the elements)."
PBDictionary >> do: aBlock
  self keysAndValuesDo: [:k :v | aBlock value: v].

PBDictionary >> keys
  | out |
  out := OrderedCollection new.
  self keysAndValuesDo: [:k :v | out add: k].
  ^ out asArray.

PBDictionary >> values
  ^ self elements.

"key -> value Associations, in key order."
PBDictionary >> items
  | out |
  out := OrderedCollection new.
  self keysAndValuesDo: [:k :v | out add: k -> v].
  ^ out asArray.

"--- writes (ProtoBase Dictionary set_at, remove_at) ---"

"A dictionary with aKey mapped to aValue. The key must be orderable (a list,
 a map or a NaN is PBValidationError); an existing key keeps its stored key
 object."
PBDictionary >> setAt: aKey value: aValue
  | key value put |
  self _checkWritable: 'setAt:value:'.
  key := PBCodec canonical: aKey.
  value := PBCodec canonical: aValue.
  put := PBAvl keyPut: (self stateAt: 'root') key: key value: value nodeClass: PBKeyNode.
  ^ self _withRoot: (put at: 1) count: ((put at: 2) ifTrue: [self count] ifFalse: [self count + 1]).

"A dictionary without aKey; for an absent key, a new version with the same
 content (ProtoBase's remove_at)."
PBDictionary >> removeAt: aKey
  | removed |
  self _checkWritable: 'removeAt:'.
  removed := PBAvl keyRemove: (self stateAt: 'root') key: (PBCodec canonical: aKey).
  ^ self _withRoot: (removed at: 1) count: ((removed at: 2) ifTrue: [self count - 1] ifFalse: [self count]).

"=== PBHashDictionary ========================================================="

PBIndexedCollection subclass: #PBHashDictionary.

PBHashDictionary class >> typeName
  ^ 'proto_db.collections.HashDictionary'.

PBHashDictionary class >> requiredFields
  ^ #('root' 'count' 'indexes').

PBHashDictionary class >> persistedFields
  ^ #('root' 'count' 'indexes').

"The bucket tuple of the hash key aHash (an empty Array when absent), checked."
PBHashDictionary >> _bucket: aHash
  | node |
  node := _PBTree nodeWithKey: (PBKeys orderKey: aHash) of: (self stateAt: 'root') in: self.
  ^ node isNil ifTrue: [#()] ifFalse: [_PBBuckets entriesOf: node value pairs: true in: self].

"The (key, value) entry of aKey, or nil."
PBHashDictionary >> _entryAt: aKey
  | key okey |
  key := self _probe: aKey.
  okey := PBKeys orderKey: key.
  (self _bucket: (PBKeys hashKey: key)) do: [:entry |
    (PBKeys orderKey: (entry at: 1)) = okey ifTrue: [^ entry]].
  ^ nil.

PBHashDictionary >> getAt: aKey
  ^ self getAt: aKey default: nil.

PBHashDictionary >> getAt: aKey default: aDefault
  | entry |
  entry := self _entryAt: aKey.
  ^ entry isNil ifTrue: [aDefault] ifFalse: [entry at: 2].

PBHashDictionary >> has: aKey
  ^ (self _entryAt: aKey) notNil.

"Evaluates aBlock with each key and its value: tree order, then bucket order."
PBHashDictionary >> keysAndValuesDo: aBlock
  _PBTree nodesOf: (self stateAt: 'root') kind: PBKeyNode in: self do: [:node |
    (_PBBuckets entriesOf: node value pairs: true in: self) do: [:entry |
      aBlock value: (entry at: 1) value: (entry at: 2)]].

PBHashDictionary >> do: aBlock
  self keysAndValuesDo: [:k :v | aBlock value: v].

PBHashDictionary >> keys
  | out |
  out := OrderedCollection new.
  self keysAndValuesDo: [:k :v | out add: k].
  ^ out asArray.

PBHashDictionary >> values
  ^ self elements.

PBHashDictionary >> items
  | out |
  out := OrderedCollection new.
  self keysAndValuesDo: [:k :v | out add: k -> v].
  ^ out asArray.

"=== the hash sets ==========================================================="

Object subclass: #_PBBuckets.

"The entries of a bucket: a tuple of entries; with pairs, each entry is a
 2-item tuple. Anything else is PBCorruptionError."
_PBBuckets class >> entriesOf: aBucket pairs: aBoolean in: anOwner
  | entries |
  (aBucket isKindOf: PBTuple) ifFalse: [
    ^ PBCorruptionError signal: anOwner printString , ' holds a bucket that is not a tuple: '
      , (PBKeys _preview: aBucket)].
  entries := aBucket asArray.
  aBoolean ifTrue: [
    entries do: [:entry |
      ((entry isKindOf: PBTuple) and: [entry size = 2]) ifFalse: [
        ^ PBCorruptionError signal: anOwner printString , ' holds a bucket entry that is not a pair: '
          , (PBKeys _preview: entry)]]].
  ^ entries.

PBIndexedCollection subclass: #PBHashBuckets.

PBHashBuckets class >> typeName
  ^ 'proto_db.collections.sets._HashBuckets'.

PBHashBuckets class >> requiredFields
  ^ #('root' 'count' 'indexes').

PBHashBuckets class >> persistedFields
  ^ #('root' 'count' 'indexes').

"Whether a bucket entry is an (element, count) pair."
PBHashBuckets >> _pairs
  ^ PBNotSupportedError signal: self class name , ': ' , self class typeName , ' is abstract: it has no elements'.

PBHashBuckets >> _elementOf: anEntry
  ^ self _pairs ifTrue: [anEntry at: 1] ifFalse: [anEntry].

"Evaluates aBlock with each entry: tree order, then bucket order."
PBHashBuckets >> entriesDo: aBlock
  | pairs |
  pairs := self _pairs.
  _PBTree nodesOf: (self stateAt: 'root') kind: PBKeyNode in: self do: [:node |
    (_PBBuckets entriesOf: node value pairs: pairs in: self) do: aBlock].

PBHashBuckets >> do: aBlock
  self entriesDo: [:entry | aBlock value: (self _elementOf: entry)].

"The entry of anElement, or nil."
PBHashBuckets >> _entryAt: anElement
  | element okey node pairs |
  element := self _probe: anElement.
  okey := PBKeys orderKey: element.
  pairs := self _pairs.
  node := _PBTree nodeWithKey: (PBKeys orderKey: (PBKeys hashKey: element)) of: (self stateAt: 'root') in: self.
  node isNil ifTrue: [^ nil].
  (_PBBuckets entriesOf: node value pairs: pairs in: self) do: [:entry |
    (PBKeys orderKey: (self _elementOf: entry)) = okey ifTrue: [^ entry]].
  ^ nil.

PBHashBuckets >> has: anElement
  ^ (self _entryAt: anElement) notNil.

PBHashBuckets subclass: #PBSet.
PBSet comment: 'Every message answers a new version; the receiver never changes. ProtoBase''s Set (proto_db.collections.Set): a hash set over a keyed AVL tree from the hash key of an element to a bucket tuple of the elements of that hash; membership is by order key, so 1, 1.0 and Decimal 1.00 are one element and true another. add: and remove: answer the new set (unlike Pharo''s, which change the set in place and answer the element); a statement that discards the result changes nothing.'.

PBSet class >> typeName
  ^ 'proto_db.collections.Set'.

PBSet >> _pairs
  ^ false.

"--- writes (ProtoBase Set add, remove; the set algebra comes with plan Task 16) ---"

"{ hash key. bucket tuple (empty when absent). 1-based position of anElement
 in it, or 0 } for a canonical anElement (ProtoBase _HashBuckets._find)."
PBSet >> _find: anElement
  | h okey node bucket |
  h := PBKeys hashKey: anElement.
  okey := PBKeys orderKey: anElement.
  node := _PBTree nodeWithKey: (PBKeys orderKey: h) of: (self stateAt: 'root') in: self.
  bucket := node isNil ifTrue: [PBTuple withAll: #()] ifFalse: [node value].
  (_PBBuckets entriesOf: bucket pairs: false in: self) doWithIndex: [:each :i |
    (PBKeys orderKey: each) = okey ifTrue: [^ { h. bucket. i }]].
  ^ { h. bucket. 0 }.

"A set holding anElement; when it is present already, a new version with the
 same content. The element must be orderable (PBValidationError otherwise)."
PBSet >> add: anElement
  | element found bucket |
  self _checkWritable: 'add:'.
  element := PBCodec canonical: anElement.
  found := self _find: element.
  (found at: 3) > 0 ifTrue: [^ self _withRoot: (self stateAt: 'root') count: self count].
  bucket := PBTuple withAll: ((found at: 2) asArray copyWith: element).
  ^ self
    _withRoot: ((PBAvl keyPut: (self stateAt: 'root') key: (found at: 1) value: bucket nodeClass: PBKeyNode) at: 1)
    count: self count + 1.

"A set without anElement; when it is absent, a new version with the same
 content (unlike Pharo's remove:, which signals)."
PBSet >> remove: anElement
  | element found entries root |
  self _checkWritable: 'remove:'.
  element := PBCodec canonical: anElement.
  found := self _find: element.
  (found at: 3) = 0 ifTrue: [^ self _withRoot: (self stateAt: 'root') count: self count].
  entries := (found at: 2) asArray.
  entries := (entries copyFrom: 1 to: (found at: 3) - 1) , (entries copyFrom: (found at: 3) + 1 to: entries size).
  root := entries isEmpty
    ifTrue: [(PBAvl keyRemove: (self stateAt: 'root') key: (found at: 1)) at: 1]
    ifFalse: [(PBAvl keyPut: (self stateAt: 'root') key: (found at: 1) value: (PBTuple withAll: entries) nodeClass: PBKeyNode) at: 1].
  ^ self _withRoot: root count: self count - 1.

PBHashBuckets subclass: #PBCountedSet.
PBCountedSet comment: 'Every message answers a new version; the receiver never changes. ProtoBase''s CountedSet (proto_db.collections.CountedSet): a hash set whose bucket entries are (element, count) pairs; count is the number of distinct elements and totalCount the sum of the counts. Its writes (add:, remove:, answering the new set) come with plan Task 22.'.

PBCountedSet class >> typeName
  ^ 'proto_db.collections.CountedSet'.

PBCountedSet class >> requiredFields
  ^ #('root' 'count' 'total_count' 'indexes').

PBCountedSet class >> persistedFields
  ^ #('root' 'count' 'total_count' 'indexes').

PBCountedSet class >> _emptyValueOf: aField
  aField = 'total_count' ifTrue: [^ 0].
  ^ super _emptyValueOf: aField.

PBCountedSet >> _pairs
  ^ true.

"The sum of the counts."
PBCountedSet >> totalCount
  ^ _PBTree integer: (self stateAt: 'total_count') field: 'total_count' of: self.

"The number of occurrences of anElement (0 when absent)."
PBCountedSet >> countOf: anElement
  | entry |
  entry := self _entryAt: anElement.
  ^ entry isNil ifTrue: [0] ifFalse: [_PBTree integer: (entry at: 2) field: 'count of an element' of: self].

"Evaluates aBlock with each element and its count."
PBCountedSet >> keysAndValuesDo: aBlock
  self entriesDo: [:entry | aBlock value: (entry at: 1) value: (entry at: 2)].

"element -> count Associations: tree order, then bucket order."
PBCountedSet >> items
  | out |
  out := OrderedCollection new.
  self keysAndValuesDo: [:e :n | out add: e -> n].
  ^ out asArray.

"=== PBRepeatedKeysDictionary ================================================="

PBIndexedCollection subclass: #PBRepeatedKeysDictionary.

PBRepeatedKeysDictionary class >> typeName
  ^ 'proto_db.collections.RepeatedKeysDictionary'.

PBRepeatedKeysDictionary class >> requiredFields
  ^ #('root' 'count' 'total_count' 'indexes').

PBRepeatedKeysDictionary class >> persistedFields
  ^ #('root' 'count' 'total_count' 'indexes').

PBRepeatedKeysDictionary class >> _emptyValueOf: aField
  aField = 'total_count' ifTrue: [^ 0].
  ^ super _emptyValueOf: aField.

PBRepeatedKeysDictionary >> totalCount
  ^ _PBTree integer: (self stateAt: 'total_count') field: 'total_count' of: self.

PBRepeatedKeysDictionary >> _recordsOf: aNode
  ^ _PBTree node: aNode value kind: PBCountedSet in: self.

"The PBCountedSet of the records under aKey (an empty one, not stored, when
 absent)."
PBRepeatedKeysDictionary >> getAt: aKey
  | node |
  node := self _nodeAt: aKey.
  ^ node isNil ifTrue: [PBCountedSet new] ifFalse: [self _recordsOf: node].

PBRepeatedKeysDictionary >> has: aKey
  ^ (self _nodeAt: aKey) notNil.

PBRepeatedKeysDictionary >> _nodeAt: aKey
  | key |
  key := self _probe: aKey.
  ^ _PBTree nodeWithKey: (PBKeys orderKey: key) of: (self stateAt: 'root') in: self.

"Evaluates aBlock with each key and its PBCountedSet, in key order."
PBRepeatedKeysDictionary >> keysAndValuesDo: aBlock
  _PBTree nodesOf: (self stateAt: 'root') kind: PBKeyNode in: self do: [:node |
    aBlock value: node key value: (self _recordsOf: node)].

"Each distinct record of each key, key by key (the elements)."
PBRepeatedKeysDictionary >> do: aBlock
  self keysAndValuesDo: [:k :records | records do: aBlock].

PBRepeatedKeysDictionary >> keys
  | out |
  out := OrderedCollection new.
  self keysAndValuesDo: [:k :v | out add: k].
  ^ out asArray.

PBRepeatedKeysDictionary >> values
  | out |
  out := OrderedCollection new.
  self keysAndValuesDo: [:k :v | out add: v].
  ^ out asArray.

"key -> PBCountedSet Associations, in key order."
PBRepeatedKeysDictionary >> items
  | out |
  out := OrderedCollection new.
  self keysAndValuesDo: [:k :v | out add: k -> v].
  ^ out asArray.

{ PBIndexSet. PBIndexedCollection. PBList. PBDictionary. PBHashDictionary. PBHashBuckets. PBSet.
  PBCountedSet. PBRepeatedKeysDictionary } do: [:each | PBTypeRegistry register: each].
PBIndexedCollection _initializeShapes.
