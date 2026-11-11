"-- indexes.st: the indexes of format 4, decoded and kept --

ProtoBase's indexes (format spec v2.0.0rc1, 'Indexes', 'Key-group indexes',
'Vector indexes'; ProtoBase proto_db/indexing/*.py at the tag). The prototype
reads them and keeps them; it never queries or maintains them (an indexed
collection is not changed before plan Task 16, and the vector index is read
only, design spec 5.1).

  PBIndex           proto_db.indexing.Index (abstract): name, key_spec
  PBKeyGroupIndex   proto_db.indexing.keyed.KeyGroupIndex (abstract): groups,
                    side, total_count, member_tokens
  PBEqualityIndex   proto_db.indexing.EqualityIndex
  PBRangeIndex      proto_db.indexing.RangeIndex
  PBVectorIndex     proto_db.indexing.VectorIndex: dim, metric, backend, params,
                    store, invalid, total_count, centroids, trained_size,
                    member_tokens

  name               the index name (the class name when sent to the class, K14)
  keySpec            the persisted (kind, arg) tuple
  hasMemberTokens    whether member_tokens is 1: the member keys hold format-4
                     exact tokens. Absent (format 3) or another value: false, and a
                     writer must rebuild the index before changing it (ProtoBase
                     has_current_tokens, which compares member_tokens == 1)

PBVectorIndex also answers centroids, trainedSize and storeEntries (the store
tree's key -> (element, count, vector) Associations, in key order: the list
number of a member is its key's first item)."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/registry'.
Import from: 'protobase/avl'.

PBAtom subclass: #PBIndex.

PBIndex class >> typeName
  ^ 'proto_db.indexing.Index'.

PBIndex class >> requiredFields
  ^ #('name' 'key_spec').

PBIndex class >> persistedFields
  ^ #('name' 'key_spec').

"The index name."
PBIndex >> name
  self isClassObject ifTrue: [^ super name].
  ^ self stateAt: 'name'.

"The persisted key spec, a (kind, arg) tuple: ('path', 'a.b'), ('element',
 nil) or ('extractor', name)."
PBIndex >> keySpec
  ^ self stateAt: 'key_spec'.

"Whether member_tokens is 1 (true is 1 too, as Python's == says)."
PBIndex >> hasMemberTokens
  | v |
  v := self stateAt: 'member_tokens'.
  ^ v == true or: [(v isInteger or: [v isFloat]) and: [v = 1]].

PBIndex >> totalCount
  ^ _PBTree integer: (self stateAt: 'total_count') field: 'total_count' of: self.

PBIndex subclass: #PBKeyGroupIndex.

PBKeyGroupIndex class >> typeName
  ^ 'proto_db.indexing.keyed.KeyGroupIndex'.

PBKeyGroupIndex class >> requiredFields
  ^ #('name' 'key_spec' 'groups' 'side' 'total_count').

PBKeyGroupIndex class >> persistedFields
  ^ #('name' 'key_spec' 'groups' 'side' 'total_count' 'member_tokens').

PBKeyGroupIndex subclass: #PBEqualityIndex.

PBEqualityIndex class >> typeName
  ^ 'proto_db.indexing.EqualityIndex'.

PBKeyGroupIndex subclass: #PBRangeIndex.

PBRangeIndex class >> typeName
  ^ 'proto_db.indexing.RangeIndex'.

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

{ PBIndex. PBKeyGroupIndex. PBEqualityIndex. PBRangeIndex. PBVectorIndex } do: [:each | PBTypeRegistry register: each].
