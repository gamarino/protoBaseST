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

Every collection answers a new version on a change (plan Tasks 14-16); this
module reads. The messages:

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

"=== PBIndexedCollection ======================================================"

PBAtom subclass: #PBIndexedCollection.

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

"=== PBList ==================================================================="

PBIndexedCollection subclass: #PBList.

PBList class >> typeName
  ^ 'proto_db.collections.List'.

PBList class >> requiredFields
  ^ #('root' 'count' 'indexes').

PBList class >> persistedFields
  ^ #('root' 'count' 'indexes').

PBList >> do: aBlock
  _PBTree nodesOf: (self stateAt: 'root') kind: PBPosNode in: self do: [:node | aBlock value: node value].

"The element at anIndex: 0-based, a negative index counts from the end
 (ProtoBase List._position, plan call C15)."
PBList >> getAt: anIndex
  | n position |
  n := self count.
  (anIndex isInteger and: [anIndex ~~ true and: [anIndex ~~ false]]) ifFalse: [
    ^ PBValidationError signal: 'A list position must be an Integer, not ' , (PBKeys _preview: anIndex)].
  position := anIndex < 0 ifTrue: [anIndex + n] ifFalse: [anIndex].
  (position between: 0 and: n - 1) ifFalse: [
    ^ PBValidationError signal: 'List position ' , anIndex printString , ' out of range for a list of '
      , n printString].
  ^ (_PBTree nodeAt: position of: (self stateAt: 'root') in: self) value.

"=== PBDictionary ============================================================="

PBIndexedCollection subclass: #PBDictionary.

PBDictionary class >> typeName
  ^ 'proto_db.collections.Dictionary'.

PBDictionary class >> requiredFields
  ^ #('root' 'count' 'indexes').

PBDictionary class >> persistedFields
  ^ #('root' 'count' 'indexes').

PBDictionary >> _nodeAt: aKey
  ^ _PBTree nodeWithKey: (PBKeys orderKey: (self _probe: aKey)) of: (self stateAt: 'root') in: self.

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

PBSet class >> typeName
  ^ 'proto_db.collections.Set'.

PBSet >> _pairs
  ^ false.

PBHashBuckets subclass: #PBCountedSet.

PBCountedSet class >> typeName
  ^ 'proto_db.collections.CountedSet'.

PBCountedSet class >> requiredFields
  ^ #('root' 'count' 'total_count' 'indexes').

PBCountedSet class >> persistedFields
  ^ #('root' 'count' 'total_count' 'indexes').

"An empty CountedSet that is not stored (what RepeatedKeysDictionary getAt:
 answers for an absent key, as ProtoBase's get_at does). Public constructors
 come with the writer (plan Task 15)."
PBCountedSet class >> _emptyUnsaved
  ^ self _unsavedWithState: (PBFrozenDict withAssociations: {
    'root' -> nil. 'count' -> 0. 'total_count' -> 0.
    'indexes' -> (PBIndexSet _unsavedWithState: (PBFrozenDict withAssociations: { 'root' -> nil })) }).

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

PBRepeatedKeysDictionary >> totalCount
  ^ _PBTree integer: (self stateAt: 'total_count') field: 'total_count' of: self.

PBRepeatedKeysDictionary >> _recordsOf: aNode
  ^ _PBTree node: aNode value kind: PBCountedSet in: self.

"The PBCountedSet of the records under aKey (an empty one, not stored, when
 absent)."
PBRepeatedKeysDictionary >> getAt: aKey
  | node |
  node := _PBTree nodeWithKey: (PBKeys orderKey: (self _probe: aKey)) of: (self stateAt: 'root') in: self.
  ^ node isNil ifTrue: [PBCountedSet _emptyUnsaved] ifFalse: [self _recordsOf: node].

PBRepeatedKeysDictionary >> has: aKey
  ^ (_PBTree nodeWithKey: (PBKeys orderKey: (self _probe: aKey)) of: (self stateAt: 'root') in: self) notNil.

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
