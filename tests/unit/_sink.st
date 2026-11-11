"_sink.st: a storage double that the save writes records to (a helper).

  sink := SegmentSink segment: aByteArray16.
  anAtom _saveInto: sink         saves anAtom and its dependents: each record is
                                 appended to the sink's segment (pushAtom:)
  sink writeTo: aDirectory       writes the segment file <hex>.seg there (no
                                 space.root) and answers aDirectory, which
                                 PBFileStorage path: then opens and reads
  sink offsets                   the offsets of the records pushed, in order

The file storage's write side is plan Task 17. Until then the tests save into
this double: an in-memory segment with the framing of format 4 (a segment
header, then one ATOM record per pushAtom:). Its stubs load from that memory
(loadAt:expecting:within:, refTo:offset:tag:), so a saved atom's stub and its
decoded twin read back what was written."

Import from: 'protobase'.

Object subclass: #SegmentSink instanceVariableNames: 'segment stream offsets'.

SegmentSink class >> segment: aByteArray
  ^ self basicNew setSegment: aByteArray.

SegmentSink >> setSegment: aByteArray
  segment := aByteArray.
  stream := WriteStream on: ByteArray new.
  stream nextPutAll: (PBSegmentHeader encodeSegment: segment).
  offsets := OrderedCollection new.

SegmentSink >> segment
  ^ segment.

SegmentSink >> offsets
  ^ offsets asArray.

SegmentSink >> pushAtom: anEnvelope
  | offset |
  offset := stream contents size.
  stream nextPutAll: (PBRecordHeader encodeKind: PBRecordHeader atomKind payload: anEnvelope encode).
  offsets addLast: offset.
  ^ PBAtomPointer segment: segment offset: offset.

SegmentSink >> loadAt: aPointer expecting: aTag within: aChain
  | bytes header payload |
  bytes := stream contents.
  header := PBRecordHeader decode: (bytes copyFrom: aPointer offset + 1 to: aPointer offset + PBRecordHeader byteSize).
  payload := header payloadIn: bytes at: aPointer offset + PBRecordHeader byteSize + 1.
  ^ PBAtomEnvelope decode: payload expecting: aTag resolver: (_PBLoadResolver storage: self chain: aChain).

SegmentSink >> loadAt: aPointer expecting: aTag
  ^ self loadAt: aPointer expecting: aTag within: { aPointer }.

SegmentSink >> refTo: aSegmentBytes offset: anOffset tag: aTag
  ^ PBTypeRegistry unloadedAtomFor: aTag at: (PBAtomPointer segment: aSegmentBytes offset: anOffset) storage: self.

SegmentSink >> writeTo: aDirectory
  aDirectory ensureCreateDirectory.
  (aDirectory / (segment hex asLowercase , '.seg')) binaryContents: stream contents.
  ^ aDirectory.

SegmentSink >> printOn: aStream
  aStream nextPutAll: 'SegmentSink'.
