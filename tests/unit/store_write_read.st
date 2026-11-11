"EXPECT: ok 30"
"PBFileStorage, write side (plan Task 17): a PBList of 300 elements and a PBObject are saved
 under a hand-built SpaceRoot (a database 'db', version 0), the root is published, and a
 fresh storage reads the space back equal: the list's elements and its valid AVL tree
 (PBAvl check:), the record's fields, and every oid drawn in memory. The space directory
 holds one segment, named by a version-4 UUID and with the format-4 header, space.root at
 epoch 1 and no space.root.tmp. A second save of a saved atom writes nothing, and a later
 save appends to the same segment."
Import from: 'protobase'.
Import from: '_check'.

| c base st list obj objects mutables dbRoot databases spaceRoot ptr root segs seg header
  before space db snapshot list2 obj2 st2 late |
c := Check new.
base := FileSystem temp / ('pbst-store-write-read-' , Smalltalk pid printString).
base deleteAll.

st := PBFileStorage path: base pathString.
c that: 'no segment before the first save' is: st currentSegment equals: nil.
list := PBList new extend: (1 to: 300) asArray.
obj := PBObject withAll: { 'name' -> 'acme'. 'n' -> 42. 'tags' -> #('a' 'b') }.
objects := (PBDictionary new setAt: 'list' value: list) setAt: 'obj' value: obj.
mutables := PBDictionary new.
dbRoot := PBDatabaseRoot _unsavedWithState: (PBFrozenDict withAssociations: {
  'objects' -> objects. 'mutables' -> mutables. 'version' -> 0.
  'committed_at' -> (DateTime year: 2026 month: 11 day: 11 hour: 12 minute: 0 second: 0 microsecond: 0 fold: 0
    zone: (ZoneOffset microseconds: 0 name: 'UTC')).
  'origin' -> (ByteArray fromHex: '0a0b0c0d0a0b0c0d0a0b0c0d0a0b0c0d').
  'previous' -> nil }).
databases := PBDictionary new setAt: 'db' value: dbRoot.
spaceRoot := PBSpaceRoot _unsavedWithState: (PBFrozenDict withAssociations: { 'databases' -> databases }).

ptr := st save: spaceRoot.
c that: 'save: answers the atom''s pointer' is: ptr equals: spaceRoot pointer.
c that: 'the pointer is in the owned segment' is: ptr segmentBytes equals: st currentSegment.
c that: 'the dependents were saved first' isTrue: (list pointer offset < ptr offset and: [obj pointer offset < ptr offset]).
before := (st recordsOfSegment: st currentSegment) size.
c that: 'a second save answers the same pointer' is: (st save: spaceRoot) equals: ptr.
c that: 'and writes nothing' is: (st recordsOfSegment: st currentSegment) size equals: before.
c that: 'save: refuses what is not an atom' signals: PBValidationError during: [st save: 42].
st flushSegment.
c that: 'the root lock is taken' is: st tryLockRoot equals: true.
root := st replaceRoot: (PBRootRecord segment: ptr segmentBytes offset: ptr offset epoch: 1).
st unlockRoot.
c that: 'replaceRoot: answers the record' is: root epoch equals: 1.
c that: 'readRoot sees it' is: st readRoot pointer equals: ptr.

"The directory."
segs := base children select: [:f | f basename endsWith: '.seg'].
c that: 'one segment file' is: segs size equals: 1.
seg := st currentSegment.
c that: 'named by the owned segment' is: segs first basename equals: seg hex asLowercase , '.seg'.
c that: 'a version-4 UUID' is: { ((seg at: 7) bitShift: -4). ((seg at: 9) bitShift: -6) } equals: #(4 2).
header := PBSegmentHeader decode: (segs first binaryContents copyFrom: 1 to: PBSegmentHeader byteSize).
c that: 'its header: version 4, its own UUID' is: { header version. header segment } equals: { 4. seg }.
c that: 'no space.root.tmp left' is: (base / 'space.root.tmp') exists equals: false.
c that: 'space.root at epoch 1' is: (PBRootRecord decode: (base / 'space.root') binaryContents) epoch equals: 1.
st close.

"A fresh storage reads it back."
st2 := PBFileStorage path: base pathString.
space := PBObjectSpace storage: st2.
c that: 'the database' is: space listDatabases equals: #('db').
db := space openDatabase: 'db'.
snapshot := db snapshotAt: db history first.
c that: 'version 0' is: snapshot version equals: 0.
c that: 'the roots' is: snapshot rootNames equals: #('list' 'obj').
list2 := snapshot getRootObject: 'list'.
c that: 'a list' is: list2 class equals: PBList.
c that: 'of 300 elements' is: list2 count equals: 300.
c that: 'equal elements, in order' is: list2 elements asArray equals: (1 to: 300) asArray.
c that: 'its stored tree is valid' isTrue: (PBAvl check: (list2 stateAt: 'root')) notNil.
c that: 'the list''s oid' is: list2 oid equals: list oid.
obj2 := snapshot getRootObject: 'obj'.
c that: 'the record' is: { obj2 class. obj2 at: 'name'. obj2 at: 'n'. (obj2 at: 'tags') asArray }
  equals: { PBObject. 'acme'. 42. #('a' 'b') }.
c that: 'the record''s oid' is: obj2 oid equals: obj oid.
c that: 'the origin' is: ((PBTypeRegistry unloadedAtomFor: 17 at: st2 readRoot pointer storage: st2) databases getAt: 'db') origin equals: (ByteArray fromHex: '0a0b0c0d0a0b0c0d0a0b0c0d0a0b0c0d').
space close.

"A later storage appends to its own new segment; the first one is untouched."
st := PBFileStorage path: base pathString.
late := PBObject withAll: { 'late' -> true }.
st save: late.
c that: 'a new storage owns a new segment' isTrue: st currentSegment ~= seg.
c that: 'two segment files now' is: (base children select: [:f | f basename endsWith: '.seg']) size equals: 2.
c that: 'the record reads back' is: ((PBTypeRegistry unloadedAtomFor: 19 at: late pointer storage: st) at: 'late') equals: true.
st close.
base deleteAll.
c report displayNl.
