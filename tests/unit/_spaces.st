"_spaces.st: a builder of small file-storage spaces for the unit tests (a helper).

  b := SpaceBuilder segment: aByteArray16.
  ref := b add: aTag oid: n state: { 'name' -> value. ... }
                                 writes an ATOM record (oid: 16 bytes of n) and
                                 answers a PBUnresolvedRef to it, tagged aTag
  ref := b add: aTag oidBytes: bytes16 state: { ... }
                                 the same with the oid given
  b writeTo: aDirectory root: ref
                                 writes the segment and a space.root pointing at
                                 ref, and answers aDirectory
  ref := b addPayload: bytes tag: aTag
                                 writes an ATOM record whose payload is the raw
                                 msgpack bytes given (for records no writer may
                                 write), and answers a PBUnresolvedRef to it
  b nextRef: aTag, b refAt: anOffset tag: aTag, b nextOffset, b sizeOf:oid:state:
                                 references and offsets ahead of the records

A state value may hold the references add: answered: they encode as @ref."

Import from: 'protobase'.

Object subclass: #SpaceBuilder instanceVariableNames: 'segment stream'.

SpaceBuilder class >> segment: aByteArray
  ^ self basicNew setSegment: aByteArray.

SpaceBuilder >> setSegment: aByteArray
  segment := aByteArray.
  stream := WriteStream on: ByteArray new.
  stream nextPutAll: (PBSegmentHeader encodeSegment: segment).

SpaceBuilder >> add: aTag oid: n state: anArray
  ^ self add: aTag oidBytes: (ByteArray withAll: ((1 to: 16) asArray collect: [:i | n])) state: anArray.

"As add:oid:state:, with the record's oid given as its 16 bytes."
SpaceBuilder >> add: aTag oidBytes: aByteArray state: anArray
  | offset |
  offset := stream contents size.
  stream nextPutAll: (PBRecordHeader encodeKind: 1 payload: (PBAtomEnvelope
    tag: aTag
    oid: aByteArray
    state: (PBFrozenDict withAssociations: anArray)) encode).
  ^ PBUnresolvedRef pointer: (PBAtomPointer segment: segment offset: offset) tag: aTag.

"As add:oid:state:, with the payload given as raw msgpack bytes."
SpaceBuilder >> addPayload: aByteArray tag: aTag
  | offset |
  offset := stream contents size.
  stream nextPutAll: (PBRecordHeader encodeKind: 1 payload: aByteArray).
  ^ PBUnresolvedRef pointer: (PBAtomPointer segment: segment offset: offset) tag: aTag.

"A reference, tagged aTag, to the record the next add: writes (a record that
 refers to itself, for the tests of a load that needs its own record)."
SpaceBuilder >> nextRef: aTag
  ^ self refAt: stream contents size tag: aTag.

"A reference, tagged aTag, to the record at anOffset of this segment."
SpaceBuilder >> refAt: anOffset tag: aTag
  ^ PBUnresolvedRef pointer: (PBAtomPointer segment: segment offset: anOffset) tag: aTag.

"The offset the next add: writes at."
SpaceBuilder >> nextOffset
  ^ stream contents size.

"The size of the record add: would write for these arguments."
SpaceBuilder >> sizeOf: aTag oid: n state: anArray
  ^ (PBRecordHeader encodeKind: 1 payload: (PBAtomEnvelope
    tag: aTag
    oid: (ByteArray withAll: ((1 to: 16) asArray collect: [:i | n]))
    state: (PBFrozenDict withAssociations: anArray)) encode) size.

SpaceBuilder >> writeTo: aDirectory root: aRef
  aDirectory ensureCreateDirectory.
  (aDirectory / (segment hex asLowercase , '.seg')) binaryContents: stream contents.
  (aDirectory / 'space.root') binaryContents:
    (PBRootRecord segment: segment offset: aRef pointer offset epoch: 1) encode.
  ^ aDirectory.

"=== whole spaces ==============================================================

  ref := b spaceWithDatabase: aName roots: { 'name' -> value. ... }
           mutables: { 'cell' -> value. ... } oids: n
                                 writes the IndexSet, the two Dictionaries (a
                                 balanced KeyNode tree each), the DatabaseRoot
                                 (version 0) and the SpaceRoot, with the oids n,
                                 n + 1, ... (each record's oid is 16 bytes of
                                 one number, so keep n + 40 < 256 and apart from
                                 the test's own), and answers the ref to the
                                 SpaceRoot, for writeTo:root:"

SpaceBuilder >> spaceWithDatabase: aName roots: aRoots mutables: aMutables oids: n
  | counter next idx objects mutables dbRoot databases |
  counter := n - 1.
  next := [counter := counter + 1. counter].
  idx := self add: 3 oid: next value state: { 'root' -> nil }.
  objects := self _dictionary: aRoots indexes: idx oids: next.
  mutables := self _dictionary: aMutables indexes: idx oids: next.
  dbRoot := self add: 18 oid: next value state: {
    'objects' -> objects. 'mutables' -> mutables. 'version' -> 0.
    'committed_at' -> (DateTime year: 2026 month: 1 day: 1 hour: 0 minute: 0 second: 0 microsecond: 0 fold: 0
      zone: (ZoneOffset microseconds: 0 name: 'UTC')).
    'previous' -> nil }.
  databases := self _dictionary: { aName -> dbRoot } indexes: idx oids: next.
  ^ self add: 17 oid: next value state: { 'databases' -> databases }.

SpaceBuilder >> _dictionary: anArray indexes: anIndexSet oids: aBlock
  | sorted |
  sorted := anArray asArray sorted: [:a :b | (PBKeys compare: a key with: b key) <= 0].
  ^ self add: 6 oid: aBlock value state: {
    'root' -> (self _tree: sorted from: 1 to: sorted size oids: aBlock) first.
    'count' -> sorted size. 'indexes' -> anIndexSet }.

"{ ref or nil. height } of the balanced KeyNode tree of the sorted Associations
 from i to j."
SpaceBuilder >> _tree: sorted from: i to: j oids: aBlock
  | mid left right height |
  i > j ifTrue: [^ { nil. 0 }].
  mid := (i + j) // 2.
  left := self _tree: sorted from: i to: mid - 1 oids: aBlock.
  right := self _tree: sorted from: mid + 1 to: j oids: aBlock.
  height := ((left at: 2) max: (right at: 2)) + 1.
  ^ { self add: 0 oid: aBlock value state: {
      'key' -> (sorted at: mid) key. 'value' -> (sorted at: mid) value.
      'left' -> left first. 'right' -> right first. 'height' -> height. 'count' -> (j - i + 1) }.
    height }.
