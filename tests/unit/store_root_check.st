"EXPECT: ok 12"
"How replaceRoot: checks the record a root record points to. The SpaceRoot this storage
 pushed last is read back (framing and CRC, as ProtoBase's publish_root reads it) and its
 payload compared with the bytes encoded when it was saved; it is not decoded again. A
 record that differs from those bytes, or fails its CRC, is refused with PBCorruptionError
 and nothing is published. Any other pointer (an earlier SpaceRoot, a record of another
 type, no record) is decoded in full as before. The cluster check reads the current
 SpaceRoot as an atom of the storage."
Import from: 'protobase'.
Import from: '_check'.

"Counts the full decodes (loadAt:expecting:within:); swaps in another record's bytes for
 one pointer when asked."
PBFileStorage subclass: #CheckedStorage instanceVariableNames: 'loads swapAt swapWith'.
CheckedStorage >> loads
  ^ loads ifNil: [0].
CheckedStorage >> loadAt: aPointer expecting: aTag within: aChain
  loads := self loads + 1.
  ^ super loadAt: aPointer expecting: aTag within: aChain.
CheckedStorage >> answerAt: aPointer recordOf: anotherPointer
  swapAt := aPointer.
  swapWith := anotherPointer.
CheckedStorage >> recordAt: aPointer
  (swapAt notNil and: [aPointer = swapAt]) ifTrue: [^ super recordAt: swapWith].
  ^ super recordAt: aPointer.

| c base st spaceRoot publish p1 p2 p3 obj loads file |
c := Check new.
base := FileSystem temp / ('pbst-store-root-check-' , Smalltalk pid printString).
base deleteAll.
spaceRoot := [:aStorage :n |
  aStorage save: (PBSpaceRoot _unsavedWithState: (PBFrozenDict withAssociations: {
    'databases' -> (PBDictionary new setAt: 'n' value: n) }))].
publish := [:aStorage :aPointer :anEpoch |
  aStorage replaceRoot: (PBRootRecord segment: aPointer segmentBytes offset: aPointer offset epoch: anEpoch)].

st := CheckedStorage path: (base / 'fast') pathString.
st tryLockRoot.
p1 := spaceRoot value: st value: 1.
loads := st loads.
publish value: st value: p1 value: 1.
c that: 'the SpaceRoot just saved is published' is: st readRoot pointer equals: p1.
c that: 'without decoding it again' is: st loads - loads equals: 0.
p2 := spaceRoot value: st value: 2.
p3 := spaceRoot value: st value: 3.
loads := st loads.
publish value: st value: p2 value: 2.
c that: 'an earlier SpaceRoot is published too' is: st readRoot pointer equals: p2.
c that: 'decoded in full (and the current root read for the cluster check)' isTrue: st loads - loads >= 1.
obj := st save: (PBObject withAll: { 'x' -> 1 }).
c that: 'a record of another type, saved last, is refused' signals: PBCorruptionError during: [
  publish value: st value: obj value: 3].
c that: 'and nothing was published' is: st readRoot pointer equals: p2.
st close.

"The record on disk differs from the bytes written: another SpaceRoot's record answered."
st := CheckedStorage path: (base / 'swapped') pathString.
st tryLockRoot.
p1 := spaceRoot value: st value: 1.
p2 := spaceRoot value: st value: 2.
st answerAt: p2 recordOf: p1.
c that: 'a record that is not the bytes written is refused' signals: PBCorruptionError
  containing: 'does not hold the bytes of the SpaceRoot written there' during: [publish value: st value: p2 value: 1].
c that: 'nothing was published' is: st readRoot equals: nil.
st close.

"A byte of the record's payload changes on disk after the flush: its CRC fails."
st := CheckedStorage path: (base / 'crc') pathString.
st tryLockRoot.
p1 := spaceRoot value: st value: 1.
st flushSegment.
file := BinaryFile open: base / 'crc' / (p1 segmentBytes hex asLowercase , '.seg') options: #(#read #write).
[file writeAt: p1 offset + PBRecordHeader byteSize + 5 bytes: #[255]] ensure: [file close].
c that: 'a record whose CRC fails is refused' signals: PBCorruptionError during: [publish value: st value: p1 value: 1].
c that: 'nothing was published there either' is: st readRoot equals: nil.
st close.

"The cluster check: a current SpaceRoot carrying cluster_term is still refused."
st := CheckedStorage path: (base / 'cluster') pathString.
st tryLockRoot.
p1 := st save: (PBSpaceRoot _unsavedWithState: (PBFrozenDict withAssociations: {
  'databases' -> PBDictionary new. 'cluster_term' -> 4 })).
publish value: st value: p1 value: 1.
p2 := spaceRoot value: st value: 2.
c that: 'over a cluster SpaceRoot, the publish is refused' signals: PBNotSupportedError containing: 'cluster_term 4' during: [
  publish value: st value: p2 value: 2].
c that: 'and the root is the cluster one' is: st readRoot pointer equals: p1.
st close.
base deleteAll.
c report displayNl.
