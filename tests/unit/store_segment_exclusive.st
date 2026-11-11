"EXPECT: ok 16"
"The owned segment is created #create #exclusive (plan Task 17): a file already there with
 the drawn name makes the creation fail loudly (PBUnexpectedError naming the segment), the
 file is left as it was, and the storage is failed: every later write is PBUnexpectedError
 while reads keep working. The name is injected by a test subclass that overrides
 newSegmentId. Without a clash, the segment is named by the drawn UUID, holds the header and
 the records, and receives every later record. newSegmentId draws a fresh version-4 UUID."
Import from: 'protobase'.
Import from: '_check'.

PBFileStorage subclass: #FixedIdStorage.
FixedIdStorage >> newSegmentId
  ^ UUID fromString: '7e7e7e7e7e7e4e7e8e7e7e7e7e7e7e7e'.

| c base st clash bytes a b u1 u2 records |
c := Check new.
base := FileSystem temp / ('pbst-store-exclusive-' , Smalltalk pid printString).
base deleteAll.

"No clash."
st := FixedIdStorage path: (base / 'free') pathString.
a := PBObject withAll: { 'a' -> 1 }.
st save: a.
c that: 'the segment is the drawn one' is: st currentSegment hex asLowercase equals: '7e7e7e7e7e7e4e7e8e7e7e7e7e7e7e7e'.
c that: 'its file' isTrue: (base / 'free' / '7e7e7e7e7e7e4e7e8e7e7e7e7e7e7e7e.seg') exists.
b := PBObject withAll: { 'b' -> 2 }.
st save: b.
records := st recordsOfSegment: st currentSegment.
c that: 'later saves append to it' is: (records collect: [:r | r at: 1]) equals: { a pointer offset. b pointer offset }.
c that: 'the first record follows the header' is: a pointer offset equals: PBSegmentHeader byteSize.
st close.

"A clash."
clash := base / 'clash' / '7e7e7e7e7e7e4e7e8e7e7e7e7e7e7e7e.seg'.
(base / 'clash') ensureCreateDirectory.
bytes := #[1 2 3 4 5].
clash binaryContents: bytes.
st := FixedIdStorage path: (base / 'clash') pathString.
a := PBObject withAll: { 'a' -> 1 }.
c that: 'the creation fails loudly' signals: PBUnexpectedError containing: '7e7e7e7e7e7e4e7e8e7e7e7e7e7e7e7e' during: [st save: a].
c that: 'the existing file is untouched' is: clash binaryContents equals: bytes.
c that: 'the atom is not saved' is: a pointer equals: nil.
c that: 'no segment is owned' is: st currentSegment equals: nil.
c that: 'the storage is failed' is: st isFailed equals: true.
c that: 'a later save is refused' signals: PBUnexpectedError containing: 'earlier write' during: [st save: a].
c that: 'and a flush' signals: PBUnexpectedError containing: 'earlier write' during: [st flushSegment].
st tryLockRoot.
c that: 'and a publish' signals: PBUnexpectedError containing: 'earlier write' during: [
  st replaceRoot: (PBRootRecord segment: (ByteArray fromHex: '7e7e7e7e7e7e4e7e8e7e7e7e7e7e7e7e') offset: 26 epoch: 1)].
c that: 'reads keep working' is: st readRoot equals: nil.
st close.

"The default name."
st := PBFileStorage path: (base / 'default') pathString.
u1 := st newSegmentId.
u2 := st newSegmentId.
c that: 'a UUID' is: u1 class equals: UUID.
c that: 'of version 4' is: ((u1 bytes at: 7) bitShift: -4) equals: 4.
c that: 'fresh on each call' isTrue: u1 ~= u2.
st close.
base deleteAll.
c report displayNl.
