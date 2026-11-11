"EXPECT: ok 53"
"PBFileStorage, read side (plan Task 11): opening a space (refusals of ProtoBase's
 FileStorage and of the prototype: cluster/), the root, record loads with lazy
 references, the segment walk, the segment header against the file name, and close.
 Every space is built here with the framing encoders, in a temporary directory
 named after the process id, removed at the start and at the end."
Import from: 'protobase'.
Import from: '_check'.

PBAtom subclass: #StoreTestThing.

StoreTestThing class >> typeName
  ^ 'storetest.Thing'.

PBTypeRegistry register: StoreTestThing.

| oidOf c base seg other w offsets add atom spaceAt good st root env friend alien stub bad bytes torn |
c := Check new.
oidOf := [:n | ByteArray withAll: ((1 to: 16) asArray collect: [:i | n])].
base := FileSystem temp / ('pbst-store-unit-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
seg := ByteArray fromHex: '11111111111111111111111111111111'.
other := ByteArray fromHex: '33333333333333333333333333333333'.

"One segment: B (a Thing), Alien (an opaque type), a BLOB, then A (a Thing that
 references B and Alien)."
w := WriteStream on: ByteArray new.
w nextPutAll: (PBSegmentHeader encodeSegment: seg).
offsets := OrderedCollection new.
add := [:kind :payload |
  offsets add: w contents size.
  w nextPutAll: (PBRecordHeader encodeKind: kind payload: payload)].
atom := [:tag :n :pairs |
  (PBAtomEnvelope tag: tag oid: (oidOf value: n)
    state: (PBFrozenDict withAssociations: pairs)) encode].
add value: 1 value: (atom value: 'storetest.Thing' value: 1 value: { 'name' -> 'b' }).
add value: 1 value: (atom value: 'polyglot.st.Alien' value: 2 value: { 'x' -> 1 }).
add value: 2 value: #[1 2 3].
add value: 1 value: (atom value: 'storetest.Thing' value: 3 value: {
  'name' -> 'a'.
  'friend' -> (PBUnresolvedRef pointer: (PBAtomPointer segment: seg offset: (offsets at: 1)) tag: 'storetest.Thing').
  'alien' -> (PBUnresolvedRef pointer: (PBAtomPointer segment: seg offset: (offsets at: 2)) tag: 'polyglot.st.Alien') }).
good := w contents.

"A space directory named aName: the segment bytes under the file name of fileSeg,
 and a root (bytes) unless nil."
spaceAt := [:aName :fileSeg :segBytes :rootBytes |
  | dir |
  dir := base / aName.
  dir ensureCreateDirectory.
  (dir / (fileSeg hex asLowercase , '.seg')) binaryContents: segBytes.
  rootBytes isNil ifFalse: [(dir / 'space.root') binaryContents: rootBytes].
  dir].
root := (PBRootRecord segment: seg offset: (offsets at: 4) epoch: 7) encode.

"--- a new space ---"
st := PBFileStorage path: (base / 'fresh') pathString.
c that: 'a missing directory is created' isTrue: (base / 'fresh') isDirectory.
c that: 'an empty space has no root' is: st readRoot equals: nil.
st close.

"--- reading a space ---"
st := PBFileStorage path: (spaceAt value: 'good' value: seg value: good value: root).
c that: 'readRoot epoch' is: st readRoot epoch equals: 7.
c that: 'readRoot pointer' is: st readRoot pointer equals: (PBAtomPointer segment: seg offset: (offsets at: 4)).
env := st loadAt: st readRoot pointer expecting: 'storetest.Thing'.
c that: 'the envelope oid' is: env oid equals: (oidOf value: 3).
c that: 'the envelope state, in order' is: env state keys asArray equals: #('name' 'friend' 'alien').
c that: 'a plain attribute' is: (env state at: 'name') equals: 'a'.
friend := env state at: 'friend'.
c that: 'a reference resolves to its class' is: friend class equals: StoreTestThing.
c that: 'the resolved atom is not loaded' is: friend isLoaded equals: false.
c that: 'its pointer' is: friend pointer equals: (PBAtomPointer segment: seg offset: (offsets at: 1)).
c that: 'it loads through the storage' is: (friend stateAt: 'name') equals: 'b'.
c that: 'its oid' is: friend oid equals: (oidOf value: 1).
alien := env state at: 'alien'.
c that: 'an unknown application type is opaque' is: alien class equals: PBOpaqueAtom.
c that: 'the opaque atom keeps the referenced name' is: alien tag equals: 'polyglot.st.Alien'.
c that: 'its field' is: (alien stateAt: 'x') equals: 1.
c that: 'one reader per segment' is: st openSegmentCount equals: 1.
stub := st refTo: other offset: 26 tag: 'storetest.Thing'.
c that: 'refTo:offset:tag: answers a stub' is: { stub class. stub pointer. stub isLoaded }
  equals: { StoreTestThing. PBAtomPointer segment: other offset: 26. false }.
stub := st refTo: other offset: 26 tag: 'polyglot.st.Other'.
c that: 'refTo: an unknown name' is: { stub class. stub tag } equals: { PBOpaqueAtom. 'polyglot.st.Other' }.
c that: 'refTo: a malformed name' signals: PBCorruptionError during: [st refTo: other offset: 26 tag: 'nodots'].
c that: 'the walk offsets' is: ((st recordsOfSegment: seg) collect: [:r | r at: 1]) equals: offsets asArray.
c that: 'the walk kinds' is: ((st recordsOfSegment: seg) collect: [:r | (r at: 2) kind]) equals: #(1 1 2 1).
c that: 'the walk payloads' is: ((st recordsOfSegment: seg) at: 3) last equals: #[1 2 3].
c that: 'the walk by hex' is: (st recordsOfSegment: seg hex asLowercase) size equals: 4.
c that: 'a BLOB is not an ATOM' signals: PBCorruptionError containing: 'BLOB' during: [
  st loadAt: (PBAtomPointer segment: seg offset: (offsets at: 3)) expecting: 'storetest.Thing'].
c that: 'offset 0' signals: PBCorruptionError during: [
  st loadAt: (PBAtomPointer segment: seg offset: 0) expecting: 'storetest.Thing'].
c that: 'an offset inside the header' signals: PBCorruptionError during: [
  st loadAt: (PBAtomPointer segment: seg offset: 25) expecting: 'storetest.Thing'].
c that: 'an offset inside a record' signals: PBCorruptionError during: [
  st loadAt: (PBAtomPointer segment: seg offset: (offsets at: 1) + 1) expecting: 'storetest.Thing'].
c that: 'an offset past the end' signals: PBCorruptionError containing: 'truncated' during: [
  st loadAt: (PBAtomPointer segment: seg offset: good size) expecting: 'storetest.Thing'].
c that: 'a record of another type' signals: PBCorruptionError during: [
  st loadAt: (PBAtomPointer segment: seg offset: (offsets at: 1)) expecting: 'polyglot.st.Alien'].
c that: 'a missing segment' signals: PBCorruptionError containing: 'missing' during: [
  st loadAt: (PBAtomPointer segment: other offset: 26) expecting: 'storetest.Thing'].
c that: 'a missing segment opens no reader' is: st openSegmentCount equals: 1.
c that: 'not a pointer' signals: PBValidationError during: [st loadAt: 26 expecting: 'storetest.Thing'].
c that: 'not a segment' signals: PBValidationError during: [st recordsOfSegment: 'xyz'].
stub := st refTo: seg offset: (offsets at: 1) tag: 'storetest.Thing'.
st close.
c that: 'closed: isClosed' isTrue: st isClosed.
c that: 'closed: loadAt:' signals: PBClosedError during: [st loadAt: (PBAtomPointer segment: seg offset: (offsets at: 1)) expecting: 'storetest.Thing'].
c that: 'closed: readRoot' signals: PBClosedError during: [st readRoot].
c that: 'closed: the walk' signals: PBClosedError during: [st recordsOfSegment: seg].
c that: 'closed: a stub load' signals: PBClosedError during: [stub stateAt: 'name'].
c that: 'closed: an atom loaded before keeps its state' is: (friend stateAt: 'name') equals: 'b'.
st close.
c that: 'close twice' isTrue: st isClosed.

"--- refusals at open ---"
(base / 'node' / 'cluster') ensureCreateDirectory.
c that: 'a directory with cluster/' signals: PBNotSupportedError containing: 'cluster' during: [
  PBFileStorage path: (base / 'node') pathString].
(base / 'afile') binaryContents: #[1].
c that: 'a path that is a file' signals: PBValidationError during: [PBFileStorage path: (base / 'afile') pathString].
c that: 'a path that is not a path' signals: PBValidationError during: [PBFileStorage path: 42].
bad := root copyReplaceFrom: 1 to: 1 with: (ByteArray withAll: { (root at: 1) bitXor: 1 }).
c that: 'a space.root with a bad CRC' signals: PBCorruptionError containing: 'CRC' during: [
  PBFileStorage path: (spaceAt value: 'badcrc' value: seg value: good value: bad)].
c that: 'a root into a missing segment' signals: PBCorruptionError containing: 'missing' during: [
  PBFileStorage path: (spaceAt value: 'noseg' value: other value: good value: root)].
c that: 'a root at a damaged record' signals: PBCorruptionError during: [
  PBFileStorage path: (spaceAt value: 'damaged' value: seg
    value: (good copyFrom: 1 to: good size - 1) value: root)].

"--- the segment header against the file name ---"
st := PBFileStorage path: (spaceAt value: 'foreign' value: other value: good value: nil).
c that: 'a foreign header refuses a load' signals: PBCorruptionError containing: 'header of the segment' during: [
  st loadAt: (PBAtomPointer segment: other offset: (offsets at: 1)) expecting: 'storetest.Thing'].
c that: 'a foreign header refuses the walk' signals: PBCorruptionError during: [st recordsOfSegment: other].
c that: 'a foreign header is not cached' is: st openSegmentCount equals: 0.
st close.
c that: 'a root into a foreign segment' signals: PBCorruptionError containing: 'header of the segment' during: [
  PBFileStorage path: (spaceAt value: 'foreignroot' value: other value: good
    value: (PBRootRecord segment: other offset: (offsets at: 4) epoch: 1) encode)].
bytes := good copyReplaceFrom: 9 to: 10 with: #[5 0].
st := PBFileStorage path: (spaceAt value: 'v5' value: seg value: bytes value: nil).
c that: 'a segment of version 5' signals: PBNotSupportedError during: [st recordsOfSegment: seg].
st close.
torn := good copyFrom: 1 to: good size - 2.
st := PBFileStorage path: (spaceAt value: 'torn' value: seg value: torn value: nil).
c that: 'the walk refuses a torn tail' signals: PBCorruptionError during: [st recordsOfSegment: seg].
c that: 'records before a torn tail load' is: ((st loadAt: (PBAtomPointer segment: seg offset: (offsets at: 1))
  expecting: 'storetest.Thing') state at: 'name') equals: 'b'.
st close.

base deleteAll.
c report displayNl.
