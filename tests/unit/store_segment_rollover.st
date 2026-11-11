"EXPECT: ok 16"
"Segment rollover (plan Task 17 review, I2; ProtoBase FileStorage segment_max_bytes, 256 MiB by
 default): a record that would take the owned segment past the cap goes to a new segment,
 created as the first one (exclusive, header synced, directory synced), unless the segment
 holds no record yet (a larger record then goes alone). Before a root is published, every
 segment written since its last sync is synced, the sealed ones included, and a sealed segment
 is closed once synced; a failure to sync a sealed segment fails the storage. A cap of the
 headers' size or less is refused. Here a cap of 400 bytes spreads a list of 300 integers over
 several segments; a root referring to all of them publishes and reads back."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_seams'.

| c base st list obj sr p fresh list2 segs big sizes first |
c := Check new.
base := FileSystem temp / ('pbst-rollover-' , Smalltalk pid printString).
base deleteAll.
segs := [:aDir | aDir children select: [:f | f basename endsWith: '.seg']].

c that: 'the default cap is ProtoBase''s' is: PBFileStorage defaultSegmentMaxBytes equals: 256 * 1024 * 1024.
c that: 'a cap of the headers'' size is refused' signals: PBValidationError during: [
  PBFileStorage path: (base / 'bad') pathString segmentMaxBytes: PBSegmentHeader byteSize + PBRecordHeader byteSize].
c that: 'a cap that is not an Integer is refused' signals: PBValidationError during: [
  PBFileStorage path: (base / 'bad') pathString segmentMaxBytes: 1.5].

st := SeamStorage path: (base / 'small') pathString segmentMaxBytes: 400.
list := PBList new extend: (1 to: 300) asArray.
big := PBObject withAll: { 'text' -> (String new: 1000 withAll: $x) }.
obj := PBObject withAll: { 'list' -> list. 'big' -> big }.
st save: obj.
c that: 'the records span several segments' isTrue: (segs value: base / 'small') size > 2.
sizes := (segs value: base / 'small') collect: [:f | f size].
c that: 'only a segment holding one larger record exceeds the cap' isTrue:
  ((segs value: base / 'small') allSatisfy: [:f | f size <= 400 or: [
    (st recordsOfSegment: (ByteArray fromHex: f basenameWithoutExtension)) size = 1]]).
c that: 'the larger record went alone' is: (st recordsOfSegment: big pointer segmentBytes) size equals: 1.
c that: 'every segment file is a writer of this storage' is: st writers size equals: (segs value: base / 'small') size.
c that: 'the current segment is the last one created' is: st currentSegment equals: st writers last segment.
sr := PBSpaceRoot _unsavedWithState: (PBFrozenDict withAssociations: { 'databases' -> (PBDictionary new setAt: 'x' value: obj) }).
p := st save: sr.
st tryLockRoot.
st replaceRoot: (PBRootRecord segment: p segmentBytes offset: p offset epoch: 1).
c that: 'publishing synced every segment' isTrue: (st writers allSatisfy: [:w | w syncs >= 1]).
c that: 'and closed the sealed ones' isTrue: ((st writers allButLast) allSatisfy: [:w | w isClosed]).
c that: 'the current one stays open' is: st writers last isClosed equals: false.
st close.
fresh := PBFileStorage path: (base / 'small') pathString.
list2 := ((PBTypeRegistry unloadedAtomFor: 19 at: obj pointer storage: fresh) at: 'list').
c that: 'the list reads back across segments' is: list2 elements asArray equals: (1 to: 300) asArray.
c that: 'its tree is valid' isTrue: (PBAvl check: (list2 stateAt: 'root')) notNil.
c that: 'the larger record reads back' is: (((PBTypeRegistry unloadedAtomFor: 19 at: obj pointer storage: fresh) at: 'big') at: 'text') size equals: 1000.
fresh close.

"A sealed segment whose sync fails fails the storage."
st := SeamStorage path: (base / 'sealedsync') pathString segmentMaxBytes: 400.
st save: (PBList new extend: (1 to: 100) asArray).
first := st writers first.
first beforeSync: [FileSystemError signal: 'injected failure in the sealed segment''s sync'].
c that: 'a sealed segment sync failure' signals: PBUnexpectedError containing: first segmentHex during: [st flushSegment].
c that: 'fails the storage' is: st isFailed equals: true.
st close.
base deleteAll.
c report displayNl.
