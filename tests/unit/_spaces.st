"_spaces.st: a builder of small file-storage spaces for the unit tests (a helper).

  b := SpaceBuilder segment: aByteArray16.
  ref := b add: aTag oid: n state: { 'name' -> value. ... }
                                 writes an ATOM record (oid: 16 bytes of n) and
                                 answers a PBUnresolvedRef to it, tagged aTag
  b writeTo: aDirectory root: ref
                                 writes the segment and a space.root pointing at
                                 ref, and answers aDirectory

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
  | offset |
  offset := stream contents size.
  stream nextPutAll: (PBRecordHeader encodeKind: 1 payload: (PBAtomEnvelope
    tag: aTag
    oid: (ByteArray withAll: ((1 to: 16) asArray collect: [:i | n]))
    state: (PBFrozenDict withAssociations: anArray)) encode).
  ^ PBUnresolvedRef pointer: (PBAtomPointer segment: segment offset: offset) tag: aTag.

SpaceBuilder >> writeTo: aDirectory root: aRef
  aDirectory ensureCreateDirectory.
  (aDirectory / (segment hex asLowercase , '.seg')) binaryContents: stream contents.
  (aDirectory / 'space.root') binaryContents:
    (PBRootRecord segment: segment offset: aRef pointer offset epoch: 1) encode.
  ^ aDirectory.
