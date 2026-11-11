"EXPECT: ok 20"
"Hash buckets holding more than one entry (Task 16 review M2). ProtoBase's HashDictionary and
 _HashBuckets file an entry under _bucket_hash(key), which a subclass may override to force
 collisions; protoBaseST's seam is _bucketHash:. The subclasses below file every key under
 the hash 7, so every entry shares one bucket and the paths of a multi-entry bucket run:
 a find at a later position, a replace in the middle that keeps the entry's position and its
 stored key, a removal from the middle that leaves the rest of the bucket, and the removal
 of the last entries, after which the bucket leaves the tree. The bucket tuples (and their
 encoded bytes) are checked against ProtoBase's by tests/interop/bucket_collisions_identical.sh."
Import from: 'protobase'.
Import from: '_check'.

PBHashDictionary subclass: #CollidingHashDictionary.
CollidingHashDictionary >> _bucketHash: aCanonical
  ^ 7.
PBSet subclass: #CollidingSet.
CollidingSet >> _bucketHash: aCanonical
  ^ 7.

| c d bucket keyOf s r |
c := Check new.
bucket := [:coll | (coll stateAt: 'root') isNil ifTrue: [nil] ifFalse: [(coll stateAt: 'root') value]].
keyOf := [:coll | (coll stateAt: 'root') key].
d := ((CollidingHashDictionary new setAt: 'a' value: 1) setAt: 'b' value: 2) setAt: 'c' value: 3.
c that: 'one node, under the overridden hash' is: (keyOf value: d) equals: 7.
c that: 'three entries in insertion order' is: (bucket value: d) equals: (PBTuple withAll: {
  PBTuple withAll: #('a' 1). PBTuple withAll: #('b' 2). PBTuple withAll: #('c' 3) }).
c that: 'a find at the last position' is: (d getAt: 'c') equals: 3.
c that: 'an absent key of the same hash' is: (d has: 'z') equals: false.
d := d setAt: 'b' value: 20.
c that: 'a replace in the middle keeps the position' is: (bucket value: d) equals: (PBTuple withAll: {
  PBTuple withAll: #('a' 1). PBTuple withAll: #('b' 20). PBTuple withAll: #('c' 3) }).
c that: 'and the count' is: d count equals: 3.
d := (d setAt: 1 value: 'x') setAt: 1.0 value: 'y'.
c that: 'a replace keeps the stored key object' is: (((bucket value: d) at: 4) at: 1) class equals: SmallInteger.
c that: 'and takes the new value' is: (d getAt: 1) equals: 'y'.
d := d removeAt: 'b'.
c that: 'a removal from the middle leaves the rest' is: (bucket value: d) equals: (PBTuple withAll: {
  PBTuple withAll: #('a' 1). PBTuple withAll: #('c' 3). PBTuple withAll: #(1 'y') }).
c that: 'the count' is: d count equals: 3.
d := (d removeAt: 'c') removeAt: 'a'.
c that: 'the last entry left' is: (bucket value: d) equals: (PBTuple withAll: { PBTuple withAll: #(1 'y') }).
d := d removeAt: 1.
c that: 'the last removal empties the tree' is: (d stateAt: 'root') equals: nil.
c that: 'and the count' is: d count equals: 0.

s := (((CollidingSet new add: 'a') add: 'b') add: 'c') add: 1.
c that: 'a colliding set: one bucket' is: (bucket value: s) equals: (PBTuple withAll: #('a' 'b' 'c' 1)).
c that: 'an equal element of the same hash is found' is: (s add: 1.0) count equals: 4.
c that: 'membership at a later position' isTrue: (s has: (Decimal fromString: '1.0')).
r := s remove: 'b'.
c that: 'a removal from the middle' is: (bucket value: r) equals: (PBTuple withAll: #('a' 'c' 1)).
r := ((r remove: 'a') remove: 'c') remove: 1.
c that: 'the last removal empties the tree' is: (r stateAt: 'root') equals: nil.
c that: 'rebase replays through the subclass''s buckets'
  is: (bucket value: (((CollidingSet new add: 'q') remove: 'a') rebaseOnto: s)) equals: (PBTuple withAll: #('b' 'c' 1 'q')).
c that: 'the default bucket hash is the hash key' is: (PBSet new _bucketHash: 'a') equals: (PBKeys hashKey: 'a').
c report displayNl.
