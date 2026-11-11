"-- framing.st: segment headers, records, root records and atom envelopes --

The byte frames of format 4 (format spec v2.0.0rc1, 'Segments and records',
'Root records' and 'Atom records'; ProtoBase proto_db/storage/format.py and
the envelope checks of proto_db/core/atom.py Atom._load):

  PBSegmentHeader   PDB2SEG\0 | version u16 LE | segment UUID (16 bytes)
  PBRecordHeader    C1 D2 | kind u8 | length u32 LE | payload CRC32 | header CRC32
  PBRootRecord      CRC32 u32 LE | msgpack {version, segment, offset, epoch}
  PBAtomEnvelope    the ATOM payload: msgpack {t, oid, s}

Integers are little-endian; every CRC is zlib's CRC-32 (ByteArray crc32).
Readers accept versions 2, 3 and 4 and writers write 4. Every integrity
failure is PBCorruptionError; another version is PBNotSupportedError. Every
object here is immutable: a class-side constructor checks its arguments and
a private initialiser sets the fields once.

The type registry and PBAtom are in registry.st (PBCodec, below this module,
needs the registry)."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/registry'.
Import from: 'protobase/codec'.

"=== shared helpers ========================================================="

Object subclass: #_PBFrame.

"The 16 bytes of a UUID (anything answering bytes) or of a ByteArray of 16, or nil."
_PBFrame class >> uuidBytes: aUUID
  | bytes |
  bytes := (aUUID isKindOf: ByteArray)
    ifTrue: [aUUID]
    ifFalse: [(aUUID isClassObject not and: [aUUID respondsTo: #bytes]) ifTrue: [aUUID bytes] ifFalse: [nil]].
  ^ ((bytes isKindOf: ByteArray) and: [bytes size = 16]) ifTrue: [bytes] ifFalse: [nil].

"An Integer that is not a Boolean."
_PBFrame class >> isInt: x
  ^ x isInteger and: [x ~~ true and: [x ~~ false]].

_PBFrame class >> u32: anInteger on: aStream
  aStream nextPutUnsigned: anInteger width: 4 bigEndian: false.

"msgpack data decoded in order, map keys of any type kept; malformed bytes
 are PBCorruptionError naming aWhat."
_PBFrame class >> decodeMsgpack: aByteArray what: aWhat
  ^ self decodeMsgpack: aByteArray what: aWhat strictKeys: false.

"As decodeMsgpack:what:, refusing (with strictKeys true) a map key that is not
 a str or a bin, as msgpack-python's strict_map_key."
_PBFrame class >> decodeMsgpack: aByteArray what: aWhat strictKeys: aBoolean
  ^ [MessagePack decodeOrdered: aByteArray strictKeys: aBoolean]
    on: Error do: [:e |
      (e isKindOf: MessageNotUnderstood) ifTrue: [e pass].
      PBCorruptionError signal: aWhat , ': malformed msgpack: ' , e messageText].

"=== PBSegmentHeader ========================================================"

"The 26-byte header that starts every segment: the format version and the
 segment's UUID (as 16 bytes)."
Object subclass: #PBSegmentHeader instanceVariableNames: 'version segment'.

PBSegmentHeader class >> magic
  ^ #[80 68 66 50 83 69 71 0].

PBSegmentHeader class >> byteSize
  ^ 26.

"The header at the start of aByteArray (trailing bytes are ignored). A short
 header or another magic is PBCorruptionError; a version other than 2, 3 or 4
 is PBNotSupportedError."
PBSegmentHeader class >> decode: aByteArray
  | version |
  (aByteArray isKindOf: ByteArray) ifFalse: [
    ^ PBValidationError signal: 'PBSegmentHeader decode: a ByteArray was expected, not ' , aByteArray class name].
  aByteArray size < 26 ifTrue: [^ PBCorruptionError signal: 'PBSegmentHeader: truncated segment header'].
  (aByteArray copyFrom: 1 to: 8) = self magic ifFalse: [
    ^ PBCorruptionError signal: 'PBSegmentHeader: bad segment magic ' , (aByteArray copyFrom: 1 to: 8) hex].
  version := aByteArray unsignedShortAt: 9 bigEndian: false.
  (version between: 2 and: 4) ifFalse: [
    ^ PBNotSupportedError signal: 'PBSegmentHeader: unsupported segment format version ' , version printString].
  ^ self basicNew _setVersion: version segment: (aByteArray copyFrom: 11 to: 26).

"The 26 header bytes of a new segment (version 4); aUUID is a UUID or its 16 bytes."
PBSegmentHeader class >> encodeSegment: aUUID
  | bytes w |
  bytes := _PBFrame uuidBytes: aUUID.
  bytes isNil ifTrue: [
    ^ PBValidationError signal: 'PBSegmentHeader encodeSegment: a UUID or 16 bytes was expected, not ' , aUUID printString].
  w := WriteStream on: ByteArray new.
  w nextPutAll: self magic.
  w nextPutUnsigned: 4 width: 2 bigEndian: false.
  w nextPutAll: bytes.
  ^ w contents.

PBSegmentHeader >> _setVersion: anInteger segment: aByteArray
  "Runs once, on a fresh instance."
  segment isNil ifFalse: [^ PBUserError signal: 'PBSegmentHeader is immutable'].
  version := anInteger.
  segment := aByteArray.
  ^ self.

PBSegmentHeader >> version
  ^ version.

"The segment's UUID as 16 bytes (RFC 4122 order)."
PBSegmentHeader >> segment
  ^ segment.

PBSegmentHeader >> segmentHex
  ^ segment hex asLowercase.

"=== PBRecordHeader ========================================================="

"The 15-byte header of a record: kind (1 ATOM, 2 BLOB), payload length and
 payload CRC, trusted only when the magic, the kind and the header CRC hold."
Object subclass: #PBRecordHeader instanceVariableNames: 'kind length payloadCrc'.

PBRecordHeader class >> magic
  ^ #[193 210].

PBRecordHeader class >> byteSize
  ^ 15.

PBRecordHeader class >> atomKind
  ^ 1.

PBRecordHeader class >> blobKind
  ^ 2.

"The header in the first 15 bytes of aByteArray (the payload, if present, is
 not read). A short header, another magic, a header CRC mismatch or a kind
 other than 1 and 2 is PBCorruptionError."
PBRecordHeader class >> decode: aByteArray
  | k crc |
  (aByteArray isKindOf: ByteArray) ifFalse: [
    ^ PBValidationError signal: 'PBRecordHeader decode: a ByteArray was expected, not ' , aByteArray class name].
  aByteArray size < 15 ifTrue: [^ PBCorruptionError signal: 'PBRecordHeader: truncated record header'].
  (aByteArray copyFrom: 1 to: 2) = self magic ifFalse: [
    ^ PBCorruptionError signal: 'PBRecordHeader: bad record magic ' , (aByteArray copyFrom: 1 to: 2) hex].
  crc := aByteArray unsignedLongAt: 12 bigEndian: false.
  (aByteArray copyFrom: 1 to: 11) crc32 = crc ifFalse: [
    ^ PBCorruptionError signal: 'PBRecordHeader: header CRC mismatch'].
  k := aByteArray at: 3.
  (k = 1 or: [k = 2]) ifFalse: [
    ^ PBCorruptionError signal: 'PBRecordHeader: unknown record kind ' , k printString].
  ^ self basicNew _setKind: k
    length: (aByteArray unsignedLongAt: 4 bigEndian: false)
    payloadCrc: (aByteArray unsignedLongAt: 8 bigEndian: false).

"The record framing aByteArray as kind k: the 15 header bytes, then the payload."
PBRecordHeader class >> encodeKind: k payload: aByteArray
  | w body |
  (k = 1 or: [k = 2]) ifFalse: [^ PBValidationError signal: 'PBRecordHeader: unknown record kind ' , k printString].
  (aByteArray isKindOf: ByteArray) ifFalse: [
    ^ PBValidationError signal: 'PBRecordHeader: a record payload is a ByteArray, not a ' , aByteArray class name].
  aByteArray size > 4294967295 ifTrue: [^ PBValidationError signal: 'PBRecordHeader: record payload too large'].
  w := WriteStream on: ByteArray new.
  w nextPutAll: self magic.
  w nextPut: k.
  _PBFrame u32: aByteArray size on: w.
  _PBFrame u32: aByteArray crc32 on: w.
  body := w contents.
  w := WriteStream on: ByteArray new.
  w nextPutAll: body.
  _PBFrame u32: body crc32 on: w.
  w nextPutAll: aByteArray.
  ^ w contents.

PBRecordHeader >> _setKind: k length: n payloadCrc: crc
  "Runs once, on a fresh instance."
  kind isNil ifFalse: [^ PBUserError signal: 'PBRecordHeader is immutable'].
  kind := k.
  length := n.
  payloadCrc := crc.
  ^ self.

PBRecordHeader >> kind
  ^ kind.

PBRecordHeader >> length
  ^ length.

PBRecordHeader >> payloadCrc
  ^ payloadCrc.

PBRecordHeader >> isAtom
  ^ kind = 1.

"The payload of this record, which starts at anIndex (1-based) of aByteArray:
 a truncated payload or a payload CRC mismatch is PBCorruptionError."
PBRecordHeader >> payloadIn: aByteArray at: anIndex
  | payload |
  (anIndex isInteger and: [anIndex >= 1]) ifFalse: [
    ^ PBValidationError signal: 'PBRecordHeader payloadIn:at: an index >= 1 was expected'].
  aByteArray size - anIndex + 1 < length ifTrue: [
    ^ PBCorruptionError signal: 'PBRecordHeader: truncated record payload'].
  payload := aByteArray copyFrom: anIndex to: anIndex + length - 1.
  payload crc32 = payloadCrc ifFalse: [^ PBCorruptionError signal: 'PBRecordHeader: payload CRC mismatch'].
  ^ payload.

"The payload of the record that aByteArray starts with (the header at 1, the
 payload right after it)."
PBRecordHeader >> payloadOfRecord: aByteArray
  ^ self payloadIn: aByteArray at: 16.

"=== PBRootRecord ==========================================================="

"The published root of a space: the pointer of its SpaceRoot record and the
 publication epoch (the compare-and-swap token)."
Object subclass: #PBRootRecord instanceVariableNames: 'version segment offset epoch'.

"A root record to write (version 4)."
PBRootRecord class >> segment: aUUID offset: anOffset epoch: anEpoch
  ^ self _version: 4 segment: aUUID offset: anOffset epoch: anEpoch.

PBRootRecord class >> _version: v segment: aUUID offset: anOffset epoch: anEpoch
  | bytes |
  bytes := _PBFrame uuidBytes: aUUID.
  bytes isNil ifTrue: [^ PBValidationError signal: 'PBRootRecord: a segment UUID or 16 bytes was expected, not ' , aUUID printString].
  ((_PBFrame isInt: anOffset) and: [anOffset >= 0]) ifFalse: [
    ^ PBValidationError signal: 'PBRootRecord: an offset >= 0 was expected, not ' , anOffset printString].
  ((_PBFrame isInt: anEpoch) and: [anEpoch >= 0]) ifFalse: [
    ^ PBValidationError signal: 'PBRootRecord: an epoch >= 0 was expected, not ' , anEpoch printString].
  ^ self basicNew _setVersion: v segment: bytes offset: anOffset epoch: anEpoch.

"The root record of aByteArray (a space.root file). The CRC and the field types
 are checked (PBCorruptionError); a version other than 2, 3 or 4 is
 PBNotSupportedError. Extra keys are ignored (those of the cloud and tiered
 root objects included). The version read is kept."
PBRootRecord class >> decode: aByteArray
  | body fields get version raw offset epoch |
  (aByteArray isKindOf: ByteArray) ifFalse: [
    ^ PBValidationError signal: 'PBRootRecord decode: a ByteArray was expected, not ' , aByteArray class name].
  aByteArray size <= 4 ifTrue: [^ PBCorruptionError signal: 'PBRootRecord: truncated root record'].
  body := aByteArray copyFrom: 5 to: aByteArray size.
  body crc32 = (aByteArray unsignedLongAt: 1 bigEndian: false) ifFalse: [
    ^ PBCorruptionError signal: 'PBRootRecord: CRC mismatch in root record'].
  "Strict keys, as msgpack-python's default in ProtoBase decode_root: a map key that
   is not a string (or bin) is corruption."
  fields := _PBFrame decodeMsgpack: body what: 'PBRootRecord' strictKeys: true.
  (fields isKindOf: MessagePackMap) ifFalse: [^ PBCorruptionError signal: 'PBRootRecord: the body is not a map'].
  get := [:key | fields at: key ifAbsent: [^ PBCorruptionError signal: 'PBRootRecord: malformed root record: no ' , key]].
  version := get value: 'version'.
  raw := get value: 'segment'.
  offset := get value: 'offset'.
  epoch := get value: 'epoch'.
  ((_PBFrame isInt: version) and: [(_PBFrame isInt: offset) and: [(_PBFrame isInt: epoch)
      and: [offset >= 0 and: [epoch >= 0 and: [(raw isKindOf: ByteArray) and: [raw size = 16]]]]]])
    ifFalse: [^ PBCorruptionError signal: 'PBRootRecord: malformed root record'].
  (version between: 2 and: 4) ifFalse: [
    ^ PBNotSupportedError signal: 'PBRootRecord: unsupported root format version ' , version printString].
  ^ self basicNew _setVersion: version segment: raw offset: offset epoch: epoch.

PBRootRecord >> _setVersion: v segment: aByteArray offset: anOffset epoch: anEpoch
  "Runs once, on a fresh instance."
  segment isNil ifFalse: [^ PBUserError signal: 'PBRootRecord is immutable'].
  version := v.
  segment := aByteArray.
  offset := anOffset.
  epoch := anEpoch.
  ^ self.

PBRootRecord >> version
  ^ version.

"The segment of the SpaceRoot record, as 16 bytes."
PBRootRecord >> segment
  ^ segment.

PBRootRecord >> segmentHex
  ^ segment hex asLowercase.

PBRootRecord >> offset
  ^ offset.

PBRootRecord >> epoch
  ^ epoch.

PBRootRecord >> pointer
  ^ PBAtomPointer segment: segment offset: offset.

"The bytes of a space.root file: CRC32, then the msgpack map with the keys
 version (always 4), segment, offset, epoch, in that order."
PBRootRecord >> encode
  | body w |
  body := MessagePack encode: (MessagePackMap withAll: {
    'version' -> 4. 'segment' -> segment. 'offset' -> offset. 'epoch' -> epoch }).
  w := WriteStream on: ByteArray new.
  _PBFrame u32: body crc32 on: w.
  w nextPutAll: body.
  ^ w contents.

"=== PBAtomEnvelope ========================================================="

"The payload of an ATOM record: the type tag t, the 16-byte oid and the state
 s (attribute name to canonical value), with the checks of format spec 'Atom
 records'."
Object subclass: #PBAtomEnvelope instanceVariableNames: 'tag oid state slots'.

"An envelope to write: aTag is an alias Integer or a type name (written in
 its canonical form; a name every reader refuses is PBValidationError), anOid 16 bytes (or a UUID), aState a PBFrozenDict of
 attribute names to values. Each value is made canonical (PBCodec canonical:,
 two msgpack containers deep, as it sits in the record), so a value that
 cannot be stored is refused here, with PBValidationError."
PBAtomEnvelope class >> tag: aTag oid: anOid state: aState
  | bytes canonicalState |
  bytes := _PBFrame uuidBytes: anOid.
  bytes isNil ifTrue: [^ PBValidationError signal: 'PBAtomEnvelope: an oid of 16 bytes was expected, not ' , anOid printString].
  (aState isKindOf: PBFrozenDict) ifFalse: [
    ^ PBValidationError signal: 'PBAtomEnvelope: the state is a PBFrozenDict, not a ' , aState class name].
  aState keys do: [:name |
    | why |
    why := self _nameProblem: name.
    why isNil ifFalse: [^ PBValidationError signal: 'PBAtomEnvelope: ' , why]].
  canonicalState := PBFrozenDict withAssociations: (aState associations collect: [:each |
    each key -> (PBCodec canonical: each value enclosingDepth: 2)]).
  ^ self basicNew _setTag: (PBTypeRegistry writerTag: aTag) oid: bytes state: canonicalState.

"Why aName cannot be a persisted attribute name, or nil."
PBAtomEnvelope class >> _nameProblem: aName
  ((aName isString and: [aName isSymbol not]) and: [aName notEmpty]) ifFalse: [
    ^ 'an attribute name is a non-empty string, not ' , aName printString].
  aName first = $_ ifTrue: [^ 'the attribute name ' , aName printString , ' starts with _'].
  (#('oid' 'atom_pointer' 'context') includes: aName) ifTrue: [
    ^ 'the attribute name ' , aName printString , ' is reserved'].
  ^ nil.

"The envelope of an ATOM payload, loaded through a reference tagged aTypeTag;
 references in the state decode to PBUnresolvedRef."
PBAtomEnvelope class >> decode: aByteArray expecting: aTypeTag
  ^ self decode: aByteArray expecting: aTypeTag resolver: nil.

"As decode:expecting:, with aResolver for the references (PBCodec fromWire:resolver:).
 PBCorruptionError when the payload is not a map of exactly t, oid and s, the
 tag is malformed or names another type than aTypeTag, the oid is not 16
 bytes, the state is not a map of attribute names (non-empty strings, no
 leading _, not oid, atom_pointer or context, no name twice), or a value is
 not a canonical value."
PBAtomEnvelope class >> decode: aByteArray expecting: aTypeTag resolver: aResolver
  | map t oid s keys names pairs |
  (aByteArray isKindOf: ByteArray) ifFalse: [
    ^ PBValidationError signal: 'PBAtomEnvelope decode: a ByteArray was expected, not ' , aByteArray class name].
  map := _PBFrame decodeMsgpack: aByteArray what: 'PBAtomEnvelope'.
  (map isKindOf: MessagePackMap) ifFalse: [^ self _corrupt: 'the payload is not a map'].
  keys := map associations collect: [:each | each key].
  (keys size = 3 and: [#('t' 'oid' 's') allSatisfy: [:k | keys includes: k]]) ifFalse: [
    ^ self _corrupt: 'the payload has the keys ' , keys printString , ', not exactly t, oid and s'].
  t := map at: 't' ifAbsent: [nil].
  oid := map at: 'oid' ifAbsent: [nil].
  s := map at: 's' ifAbsent: [nil].
  self _checkTag: t expecting: aTypeTag.
  ((oid isKindOf: ByteArray) and: [oid size = 16]) ifFalse: [
    ^ self _corrupt: 'the oid is not 16 bytes: ' , oid printString].
  (s isKindOf: MessagePackMap) ifFalse: [^ self _corrupt: 'the state is not a map'].
  names := Set new.
  pairs := s associations collect: [:each |
    | why |
    why := self _nameProblem: each key.
    why isNil ifFalse: [^ self _corrupt: why].
    (names includes: each key) ifTrue: [^ self _corrupt: 'the attribute ' , each key printString , ' appears twice'].
    names add: each key.
    each key -> (PBCodec fromWire: each value resolver: aResolver)].
  ^ self basicNew _setTag: t oid: oid state: (PBFrozenDict withAssociations: pairs).

PBAtomEnvelope class >> _corrupt: aString
  ^ PBCorruptionError signal: 'PBAtomEnvelope: ' , aString.

"The record's tag t and the reference's tag must name one type (format spec,
 'How a reader resolves a reference'): equal names once aliases are mapped; or,
 when neither name has a class here, t is a valid opaque name (the reference
 may spell an alias only the owning implementation knows)."
PBAtomEnvelope class >> _checkTag: t expecting: aTypeTag
  | stored expected |
  stored := PBTypeRegistry nameOfTag: t.
  expected := PBTypeRegistry nameOfTag: aTypeTag.
  stored = expected ifTrue: [
    (self _isKnown: stored) ifFalse: [PBTypeRegistry checkOpaqueName: stored].
    ^ self].
  ((self _isKnown: expected) or: [self _isKnown: stored]) ifFalse: [
    PBTypeRegistry checkOpaqueName: expected; checkOpaqueName: stored.
    ^ self].
  ^ self _corrupt: 'the record is a ' , stored printString , ', the reference expects a ' , expected printString.

"Whether aName is a type this reader knows: a built-in type or a registered class."
PBAtomEnvelope class >> _isKnown: aName
  ^ (PBTypeRegistry aliasOf: aName) notNil or: [PBTypeRegistry isRegistered: aName].

PBAtomEnvelope >> _setTag: aTag oid: aByteArray state: aState
  ^ self _setTag: aTag oid: aByteArray state: aState slots: nil.

"anArray: the slots of an atom of a class with a record shape (_PBRecordShape),
 derived from aState; nil for an envelope that is not an atom's state (one a
 storage decoded or one to write) or an atom of another class."
PBAtomEnvelope >> _setTag: aTag oid: aByteArray state: aState slots: anArray
  "Runs once, on a fresh instance. The guard tests state, which every envelope
   holds (an envelope an atom builds in memory has no oid, and may have no tag)."
  state isNil ifFalse: [^ PBUserError signal: 'PBAtomEnvelope is immutable'].
  tag := aTag.
  oid := aByteArray.
  state := aState.
  slots := anArray.
  ^ self.

"The type tag as read (an alias Integer or a name)."
PBAtomEnvelope >> tag
  ^ tag.

"The oid, 16 bytes."
PBAtomEnvelope >> oid
  ^ oid.

"The state, a PBFrozenDict in the record's order."
PBAtomEnvelope >> state
  ^ state.

"The slots of the atom holding this envelope (see _setTag:oid:state:slots:),
 or nil. Runtime-only: never encoded."
PBAtomEnvelope >> slots
  ^ slots.

"The ATOM payload: the msgpack map t, oid, s, in that order; t is written in
 canonical form, references as their pointers, every value two containers
 deep."
PBAtomEnvelope >> encode
  | wireState |
  wireState := MessagePackMap withAll: (state associations collect: [:each |
    each key -> (PBCodec toWire: each value atomRef: PBCodec pointerRef enclosingDepth: 2)]).
  ^ MessagePack encode: (MessagePackMap withAll: {
    't' -> (PBTypeRegistry writerTag: tag). 'oid' -> oid. 's' -> wireState }).
