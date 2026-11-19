"-- cluster/protocol.st: the wire messages of cluster protocol 14 --

The messages of proto_db cluster/protocol.py at v2.0.0rc4 (MESSAGE_TYPES, OPTIONAL_FIELDS,
_check_field, validate_message, encode_root, decode_labeled_root; format spec, 'Cluster wire
protocol'). Every message is a msgpack map: v (the protocol version, 14), type, from (the
sender's node id, a String), then the fields of its type in the order of the table, which is
proto_db's MESSAGE_TYPES copied verbatim, then the optional fields it carries (OPTIONAL_FIELDS:
unknown, a Boolean, on fetched and commit_info, R240L; checked when present, absent reads
false). Protocol 14 also lets the records a message carries be format 5 and a root carry its
format version as a fifth item; protoBaseST reads and writes format 4 only, so it never writes
a 5-item root and refuses every one it receives (docs/deviations.md, 'Reading'). PBClusterFrame puts a message in a frame (the 4-byte length) and
optionally authenticates it (CC4).

  PBClusterMessage  a validated message: type, from, at: aFieldName, encode. Class side:
                    protocolVersion, schema, type:from:fields: (a message protoBaseST sends:
                    built wrong is PBValidationError, a bug of ours), decode: (received bytes:
                    anything invalid is PBClusterProtocolError, and the receiver drops the
                    connection), and the readers and writers of the field values: rootFrom: /
                    rootValue: (CC17), rangesFrom: / rangesValue:, afterFrom:.
  PBClusterFrame    the frame of a message (proto_db encode_frame, FrameDecoder): a 4-byte
                    big-endian length, then the body, at most maxFrameBytes (64 MiB). With a key
                    (CC4, design spec 8.4 Q5) the body is the msgpack bytes then a tagSize-byte
                    tag, HMAC-SHA-256(key, UTF-8(receiver id) || 0x00 || msgpack bytes); without
                    one the frame is protocol 14 byte for byte. Class side only: encode:to:key:,
                    lengthFrom:, decodeBody:to:key:, decode:to:key:.

Field kinds (format spec, 'Field types'; proto_db _check_field):
  #int       an Integer >= 0 (never a Boolean or a Float)
  #number    an Integer or a Float, >= 0 (a NaN is refused)
  #str #bool a String; true or false
  #root      nil (unknown), { 0. nil. nil. label } (the empty space, known) or { epoch.
             16 segment bytes. offset. label }; the 3-item form without the label reads with
             label 0 and is never written (CC17); a 5-item form (a fifth item, the root's
             format version above 4) is refused: a fifth item that is not an Integer above 4
             is malformed, any other names a version this node does not read
  #records   an Array of { 16 segment bytes. offset. framed record bytes or nil }
  #uuid      16 bytes; #optBytes / #optStr: bytes or nil / a String or nil
  #ranges    nil or an Array of { 16 segment bytes. start. end } with 0 <= start <= end
  #strs      an Array of Strings
  #after     nil or { seq > 0. holder String } (DEPTH 0 never sends a non-nil after)

Received maps are read as proto_db reads them (msgpack-python unpackb, strict_map_key): a map
key that is not a str or a bin is refused, a repeated key keeps its last value, extra fields
are ignored and never re-encoded; an optional field is carried and re-encoded. As Python's
14.0 == 14, a version written as the Float 14.0 is protocol 14. A timestamp ext (type -1) anywhere in the map, extra fields included, is refused
where msgpack-python's Timestamp refuses it. A message protoBaseST builds holds no integer
outside msgpack's range and never the 3-item root form. A message holds its own copies of the field values and at: answers a fresh
copy: every value here is immutable."

Import from: 'protobase/errors'.
Import from: 'protobase/framing'.
Import from: 'protobase/cluster/rootlog'.

Object subclass: #PBClusterMessage instanceVariableNames: 'type from values' classVariableNames: 'Schema OptionalSchema'.

"The table, made once when the module loads: type -> an Array of (field name -> kind), in the
 order of proto_db's MESSAGE_TYPES (format spec, 'Message types')."
PBClusterMessage class >> _initializeSchema
  | table rows |
  Schema isNil ifFalse: [^ self].
  table := Dictionary new.
  rows := #(
    'request' ('term' #int 'rid' #int 'inc' #int 'vs' #int)
    'grant' ('term' #int 'rid' #int 'inc' #int 'root' #root 'committed' #root 'certain' #bool)
    'reject' ('term' #int 'rid' #int 'inc' #int 'root' #root 'certain' #bool 'reason' #str
      'highest' #int 'remaining' #number)
    'release' ('term' #int 'inc' #int 'root' #root 'committed' #root 'certain' #bool
      'held' #bool 'next' #optStr 'more' #bool)
    'records' ('term' #int 'rid' #int 'inc' #int 'index' #int 'records' #records)
    'warm' ('term' #int 'records' #records)
    'replicate' ('term' #int 'rid' #int 'inc' #int 'root' #root 'committed' #root 'records' #records
      'chunks' #int 'base' #root 'base_ranges' #ranges 'seq' #int 'pred' #root
      'vs' #int 'copies' #strs 'ranges' #ranges)
    'store' ('term' #int 'rid' #int 'inc' #int 'root' #root 'records' #records 'chunks' #int
      'ranges' #ranges 'copies' #strs 'vs' #int)
    'propose' ('term' #int 'seq' #int 'inc' #int 'root' #root 'pred' #root)
    'renew' ('term' #int 'rid' #int 'inc' #int 'vs' #int)
    'permit_req' ('term' #int 'rid' #int 'inc' #int)
    'permit' ('term' #int 'rid' #int 'seq' #int 'inc' #int 'root' #root 'certain' #bool
      'valid' #number 'after' #after)
    'permit_no' ('term' #int 'rid' #int 'inc' #int 'reason' #str)
    'done' ('term' #int 'seq' #int 'inc' #int 'outcome' #str 'root' #root 'copies' #strs
      'ranges' #ranges)
    'ack' ('term' #int 'rid' #int 'inc' #int 'ok' #bool 'root' #root 'stored' #bool)
    'want' ()
    'query' ('rid' #int 'inc' #int 'ballot' #int 'vs' #int)
    'answer' ('rid' #int 'inc' #int 'root' #root 'committed' #root 'certain' #bool 'promised' #int
      'state' #str 'ballot' #int)
    'fetch' ('rid' #int 'inc' #int 'segment' #uuid 'offset' #int)
    'fetched' ('rid' #int 'inc' #int 'segment' #uuid 'offset' #int 'data' #optBytes)
    'commit_query' ('rid' #int 'inc' #int 'root' #root)
    'commit_info' ('rid' #int 'inc' #int 'persisted' #bool 'ranges' #ranges)
  ).
  1 to: rows size by: 2 do: [:k |
    | pairs |
    pairs := rows at: k + 1.
    table at: (rows at: k) put: ((1 to: pairs size // 2) asArray collect: [:i |
      (pairs at: 2 * i - 1) -> (pairs at: 2 * i)])].
  Schema := table.
  OptionalSchema := Dictionary new.
  OptionalSchema at: 'fetched' put: { 'unknown' -> #bool }; at: 'commit_info' put: { 'unknown' -> #bool }.

PBClusterMessage class >> protocolVersion
  ^ 14.

"A fresh Dictionary from each type to an Array of (field name -> kind), in the order of the
 table (format spec, 'Message types')."
PBClusterMessage class >> schema
  | copy |
  copy := Dictionary new.
  Schema keysAndValuesDo: [:kind :fields |
    copy at: kind put: (fields collect: [:each | each key -> each value])].
  ^ copy.

"The (field name -> kind) Array of the type aString, nil for an unknown type."
PBClusterMessage class >> _fieldsOf: aString
  ^ aString isString ifTrue: [Schema at: aString ifAbsent: [nil]] ifFalse: [nil].

"The optional (field name -> kind) Array of the type aString (proto_db OPTIONAL_FIELDS): empty
 for a type with none or an unknown type."
PBClusterMessage class >> _optionalFieldsOf: aString
  ^ aString isString ifTrue: [OptionalSchema at: aString ifAbsent: [#()]] ifFalse: [#()].

"A message protoBaseST sends: aString a type, anId the sender's node id, anArrayOfAssociations
 exactly the fields of the type (field name -> wire value), in any order, plus any of its
 optional fields. Anything else is PBValidationError: a message built wrong is a bug of the
 sender, never sent."
PBClusterMessage class >> type: aString from: anId fields: anArrayOfAssociations
  | fields optional names |
  fields := self _fieldsOf: aString.
  fields isNil ifTrue: [^ PBValidationError signal: 'Unknown message type ' , aString printString].
  anId isString ifFalse: [^ PBValidationError signal: 'A message names its sender with a String, not ' , anId printString].
  (anArrayOfAssociations isArray and: [anArrayOfAssociations allSatisfy: [:each | each isKindOf: Association]]) ifFalse: [
    ^ PBValidationError signal: 'The fields of a message are an Array of Associations, not ' , anArrayOfAssociations printString].
  optional := self _optionalFieldsOf: aString.
  names := (fields , optional) collect: [:each | each key].
  anArrayOfAssociations do: [:each |
    (names includes: each key) ifFalse: [
      ^ PBValidationError signal: 'A ' , aString printString , ' message has no field ' , each key printString]].
  (anArrayOfAssociations collect: [:each | each key]) asSet size = anArrayOfAssociations size ifFalse: [
    ^ PBValidationError signal: 'A field of a ' , aString printString , ' message is given twice'].
  ^ self basicNew
    _setType: aString asString
    from: anId asString
    values: (fields collect: [:field |
      | given |
      given := anArrayOfAssociations detect: [:each | each key = field key] ifNone: [
        ^ PBValidationError signal: 'A ' , aString printString , ' message lacks the field ' , field key printString].
      (self _is: given value kind: field value) ifFalse: [
        ^ PBValidationError signal: (self _field: field of: aString refusing: given value)].
      (self _isWritable: given value kind: field value) ifFalse: [
        ^ PBValidationError signal: (self _field: field of: aString refusing: given value)
          , ': a message protoBaseST writes holds integers below 2^64 and roots of 4 items (CC17)'].
      self _copyWire: given value])
      , (optional collect: [:field |
        | given |
        given := anArrayOfAssociations detect: [:each | each key = field key] ifNone: [nil].
        given isNil
          ifTrue: [nil]
          ifFalse: [
            (self _is: given value kind: field value) ifFalse: [
              ^ PBValidationError signal: (self _field: field of: aString refusing: given value)].
            given value]]).

"Whether aValue, a wire value of aKind, may be written: every Integer in it below 2^64 (the
 largest msgpack uint is 2^64 - 1), and a root never in the 3-item form (CC17)."
PBClusterMessage class >> _isWritable: aValue kind: aKind
  | pending |
  (aKind = #root and: [aValue notNil and: [aValue size ~= 4]]) ifTrue: [^ false].
  pending := OrderedCollection with: aValue.
  [pending notEmpty] whileTrue: [
    | x |
    x := pending removeLast.
    (x isInteger and: [x >= (2 raisedTo: 64)]) ifTrue: [^ false].
    x isArray ifTrue: [pending addAll: x]].
  ^ true.

"The message of aByteArray, the body of one frame (proto_db decode_message, validate_message).
 PBClusterProtocolError for bytes that are not one msgpack map, a key that is not a str or a
 bin, a missing v, type or from, another version, an unknown type, a missing or ill-typed
 field, an ill-typed optional field; extra fields are ignored."
PBClusterMessage class >> decode: aByteArray
  | map version kind fields from absent |
  (aByteArray isKindOf: ByteArray) ifFalse: [
    ^ PBValidationError signal: 'PBClusterMessage decode: a ByteArray was expected, not ' , aByteArray class name].
  map := [MessagePack decodeOrdered: aByteArray strictKeys: true]
    on: Error do: [:e |
      (e isKindOf: MessageNotUnderstood) ifTrue: [e pass].
      PBClusterProtocolError signal: 'Undecodable message: ' , e messageText].
  (map isKindOf: MessagePackMap) ifFalse: [
    ^ PBClusterProtocolError signal: 'A message must be a map, got ' , map class name].
  self _checkTimestampsIn: map.
  version := map at: 'v' ifAbsent: [nil].
  (((_PBFrame isInt: version) or: [version isFloat])
      and: [version = self protocolVersion or: [version = self protocolVersion asFloat]]) ifFalse: [
    ^ PBClusterProtocolError signal: 'Unsupported protocol version ' , version printString
      , ' (this node speaks version ' , self protocolVersion printString , ')'].
  kind := map at: 'type' ifAbsent: [nil].
  fields := self _fieldsOf: kind.
  fields isNil ifTrue: [^ PBClusterProtocolError signal: 'Unknown message type ' , kind printString].
  from := map at: 'from' ifAbsent: [nil].
  from isString ifFalse: [^ PBClusterProtocolError signal: 'A message must name its sender in ''from'''].
  ^ self basicNew
    _setType: kind
    from: from
    values: (fields collect: [:field |
      | value |
      value := map at: field key ifAbsent: [
        ^ PBClusterProtocolError signal: 'A ' , kind printString , ' message lacks the field ' , field key printString].
      (self _is: value kind: field value) ifFalse: [
        ^ PBClusterProtocolError signal: (self _field: field of: kind refusing: value)].
      value])
      , ((self _optionalFieldsOf: kind) collect: [:field |
        | value |
        absent isNil ifTrue: [absent := Object new].
        value := map at: field key ifAbsent: [absent].
        value == absent
          ifTrue: [nil]
          ifFalse: [
            (self _is: value kind: field value) ifFalse: [
              ^ PBClusterProtocolError signal: (self _field: field of: kind refusing: value)].
            value]]).

"Refuses (PBClusterProtocolError) a timestamp ext (type -1) anywhere in aTree that
 msgpack-python's unpackb refuses while decoding, before proto_db looks at any field: data of 4
 bytes, 8 bytes whose upper 30 bits (nanoseconds) are below 10^9, or 12 bytes whose first 4 (big
 endian nanoseconds) are below 10^9; other ext types are kept as they are. An explicit stack:
 a map nests up to 1024 containers."
PBClusterMessage class >> _checkTimestampsIn: aTree
  | pending |
  pending := OrderedCollection with: aTree.
  [pending notEmpty] whileTrue: [
    | x |
    x := pending removeLast.
    x isArray ifTrue: [pending addAll: x].
    (x isKindOf: MessagePackMap) ifTrue: [x associations do: [:each | pending add: each value]].
    ((x isKindOf: MessagePackExt) and: [x type = -1]) ifTrue: [
      | data nanoseconds |
      data := x data.
      nanoseconds := data size = 8
        ifTrue: [(data unsignedLongAt: 1 bigEndian: true) bitShift: -2]
        ifFalse: [data size = 12 ifTrue: [data unsignedLongAt: 1 bigEndian: true] ifFalse: [0]].
      ((#(4 8 12) includes: data size) and: [nanoseconds < 1000000000]) ifFalse: [
        ^ PBClusterProtocolError signal: 'Undecodable message: invalid timestamp data ' , data printString]]].

PBClusterMessage class >> _field: aField of: aType refusing: aValue
  | text problem |
  text := 'Field ' , aField key printString , ' of a ' , aType printString , ' message must be a valid '
    , aField value , ', got ' , aValue printString.
  problem := aField value = #root ifTrue: [self _rootProblem: aValue] ifFalse: [nil].
  ^ problem isNil ifTrue: [text] ifFalse: [text , ': ' , problem].

"Whether aValue is a wire value of aKind (proto_db _check_field)."
PBClusterMessage class >> _is: aValue kind: aKind
  aKind = #int ifTrue: [^ self _isCount: aValue].
  aKind = #number ifTrue: [^ ((_PBFrame isInt: aValue) or: [aValue isFloat]) and: [aValue >= 0]].
  aKind = #str ifTrue: [^ aValue isString].
  aKind = #bool ifTrue: [^ aValue == true or: [aValue == false]].
  aKind = #root ifTrue: [^ (self _rootProblem: aValue) isNil].
  aKind = #uuid ifTrue: [^ self _isSegment: aValue].
  aKind = #optBytes ifTrue: [^ aValue isNil or: [aValue isKindOf: ByteArray]].
  aKind = #optStr ifTrue: [^ aValue isNil or: [aValue isString]].
  aKind = #strs ifTrue: [^ aValue isArray and: [aValue allSatisfy: [:each | each isString]]].
  aKind = #after ifTrue: [
    ^ aValue isNil or: [aValue isArray and: [aValue size = 2
      and: [(self _isCount: aValue first) and: [aValue first > 0 and: [aValue last isString]]]]]].
  aKind = #ranges ifTrue: [^ aValue isNil or: [aValue isArray and: [aValue allSatisfy: [:r | self _isRange: r]]]].
  aKind = #records ifTrue: [^ aValue isArray and: [aValue allSatisfy: [:r | self _isRecord: r]]].
  ^ PBValidationError signal: 'PBClusterMessage: no field kind ' , aKind printString.

"{ 16 segment bytes. start. end } with 0 <= start <= end."
PBClusterMessage class >> _isRange: aValue
  (aValue isArray and: [aValue size = 3]) ifFalse: [^ false].
  ^ (self _isSegment: (aValue at: 1)) and: [(self _isCount: (aValue at: 2))
    and: [(_PBFrame isInt: (aValue at: 3)) and: [(aValue at: 2) <= (aValue at: 3)]]].

"{ 16 segment bytes. offset. framed record bytes or nil }."
PBClusterMessage class >> _isRecord: aValue
  (aValue isArray and: [aValue size = 3]) ifFalse: [^ false].
  ^ (self _isSegment: (aValue at: 1)) and: [(self _isCount: (aValue at: 2))
    and: [(aValue at: 3) isNil or: [(aValue at: 3) isKindOf: ByteArray]]].

PBClusterMessage class >> _isCount: aValue
  ^ (_PBFrame isInt: aValue) and: [aValue >= 0].

PBClusterMessage class >> _isSegment: aValue
  ^ (aValue isKindOf: ByteArray) and: [aValue size = 16].

"nil when aValue is a wire root, else what is wrong with it (proto_db decode_labeled_root, in
 its order: the length, the format version of a 5-item root, then the epoch and label). A
 5-item root is never one: this node reads formats 2 to 4 (readableRootVersions), and a fifth
 item of 4 or less, or not an Integer, is malformed."
PBClusterMessage class >> _rootProblem: aValue
  | epoch segment offset label |
  aValue isNil ifTrue: [^ nil].
  (aValue isArray and: [aValue size between: 3 and: 5]) ifFalse: [^ 'Malformed root ' , aValue printString].
  aValue size = 5 ifTrue: [
    | version |
    version := aValue at: 5.
    ((_PBFrame isInt: version) and: [version > 4]) ifFalse: [^ 'Malformed root format version ' , aValue printString].
    (self readableRootVersions includes: version) ifFalse: [
      ^ 'A root of format version ' , version printString , ', which this version does not read']].
  epoch := aValue at: 1.
  segment := aValue at: 2.
  offset := aValue at: 3.
  label := aValue size >= 4 ifTrue: [aValue at: 4] ifFalse: [0].
  ((self _isCount: epoch) and: [self _isCount: label]) ifFalse: [
    ^ 'Malformed root epoch or term ' , aValue printString].
  epoch = 0 ifTrue: [
    ^ (segment isNil and: [offset isNil]) ifTrue: [nil] ifFalse: ['The empty root (epoch 0) has no pointer']].
  ((self _isSegment: segment) and: [self _isCount: offset]) ifFalse: [^ 'Malformed root pointer ' , aValue printString].
  ^ nil.

"The format versions of a root this node reads (proto_db READABLE_FORMAT_VERSIONS): 2 to 4,
 as PBSegmentHeader and PBRootRecord; format 5 is refused (docs/deviations.md, 'Reading')."
PBClusterMessage class >> readableRootVersions
  ^ #(2 3 4).

"The root a wire root names (CC17): nil (unknown) or a PBLabeledRoot, the empty space for
 epoch 0, label 0 for the 3-item form. PBClusterProtocolError for anything else."
PBClusterMessage class >> rootFrom: aWireValue
  | problem label |
  problem := self _rootProblem: aWireValue.
  problem isNil ifFalse: [^ PBClusterProtocolError signal: problem].
  aWireValue isNil ifTrue: [^ nil].
  label := aWireValue size >= 4 ifTrue: [aWireValue at: 4] ifFalse: [0].
  (aWireValue at: 1) = 0 ifTrue: [^ PBLabeledRoot label: label record: nil].
  ^ PBLabeledRoot label: label
    record: (PBRootRecord segment: (aWireValue at: 2) offset: (aWireValue at: 3) epoch: (aWireValue at: 1)).

"The wire root of aLabeledRootOrNil (proto_db encode_root): nil (unknown), { 0. nil. nil.
 label } for the empty space, else { epoch. segment bytes. offset. label }. The 3-item form is
 never written."
PBClusterMessage class >> rootValue: aLabeledRootOrNil
  | record |
  aLabeledRootOrNil isNil ifTrue: [^ nil].
  (aLabeledRootOrNil isClassObject not and: [aLabeledRootOrNil class == PBLabeledRoot]) ifFalse: [
    ^ PBValidationError signal: 'PBClusterMessage rootValue: a PBLabeledRoot or nil, not ' , aLabeledRootOrNil printString].
  record := aLabeledRootOrNil record.
  record isNil ifTrue: [^ { 0. nil. nil. aLabeledRootOrNil label }].
  ^ { record epoch. record segment. record offset. aLabeledRootOrNil label }.

"The byte ranges of a received ranges value: nil, or a fresh Array of { 16 segment bytes.
 start. end }. PBClusterProtocolError when it is not a ranges value."
PBClusterMessage class >> rangesFrom: aWireValue
  (self _is: aWireValue kind: #ranges) ifFalse: [
    ^ PBClusterProtocolError signal: 'Malformed ranges ' , aWireValue printString].
  ^ self _copyWire: aWireValue.

"The wire value of byte ranges protoBaseST sends (proto_db encode_ranges): nil, or an Array of
 { 16 segment bytes. start. end } with 0 <= start <= end, copied. PBValidationError otherwise."
PBClusterMessage class >> rangesValue: anArrayOrNil
  (self _is: anArrayOrNil kind: #ranges) ifFalse: [
    ^ PBValidationError signal: 'PBClusterMessage rangesValue: nil or an Array of { segment. start. end }, not '
      , anArrayOrNil printString].
  ^ self _copyWire: anArrayOrNil.

"The after of a received permit: nil, or a fresh { seq. holder }. PBClusterProtocolError when
 it is not an after value."
PBClusterMessage class >> afterFrom: aWireValue
  (self _is: aWireValue kind: #after) ifFalse: [
    ^ PBClusterProtocolError signal: 'Malformed after ' , aWireValue printString].
  ^ self _copyWire: aWireValue.

"aValue with every Array copied (ByteArrays and Strings are immutable in protoST)."
PBClusterMessage class >> _copyWire: aValue
  ^ aValue isArray ifTrue: [aValue collect: [:each | self _copyWire: each]] ifFalse: [aValue].

PBClusterMessage >> _setType: aString from: anId values: anArray
  "Runs once, on a fresh instance."
  type isNil ifFalse: [^ PBUserError signal: 'PBClusterMessage is immutable'].
  type := aString.
  from := anId.
  values := anArray.
  ^ self.

PBClusterMessage >> type
  ^ type.

"The sender's node id."
PBClusterMessage >> from
  ^ from.

"A fresh copy of the wire value of the field aFieldName; an optional field the message does not
 carry reads false (proto_db msg.get('unknown', False); every optional field is a Boolean).
 PBValidationError when the type has no such field."
PBClusterMessage >> at: aFieldName
  | fields optional |
  fields := self class _fieldsOf: type.
  1 to: fields size do: [:i |
    (fields at: i) key = aFieldName ifTrue: [^ self class _copyWire: (values at: i)]].
  optional := self class _optionalFieldsOf: type.
  1 to: optional size do: [:i |
    (optional at: i) key = aFieldName ifTrue: [
      | value |
      value := values at: fields size + i.
      ^ value isNil ifTrue: [false] ifFalse: [value]]].
  ^ PBValidationError signal: 'A ' , type printString , ' message has no field ' , aFieldName printString.

"Whether the message carries the field aFieldName: every field of its type, and an optional
 field only when present."
PBClusterMessage >> includesField: aFieldName
  | all |
  all := self _allFields.
  1 to: all size do: [:i |
    (all at: i) key = aFieldName ifTrue: [
      ^ i <= (self class _fieldsOf: type) size or: [(values at: i) notNil]]].
  ^ false.

"The fields of the type then its optional fields, (name -> kind), in the order of values."
PBClusterMessage >> _allFields
  ^ (self class _fieldsOf: type) , (self class _optionalFieldsOf: type).

"The msgpack bytes of the message: a map of v, type, from, then the fields in the order of the
 table, then the optional fields it carries (proto_db encode_message of a message make_message
 built in that order)."
PBClusterMessage >> encode
  | all required |
  all := self _allFields.
  required := (self class _fieldsOf: type) size.
  ^ MessagePack encode: (MessagePackMap withAll: { 'v' -> self class protocolVersion. 'type' -> type. 'from' -> from }
    , (((1 to: all size) asArray select: [:i | i <= required or: [(values at: i) notNil]])
      collect: [:i | (all at: i) key -> (values at: i)])).

PBClusterMessage _initializeSchema.

Object subclass: #PBClusterFrame.

"The largest frame body, in bytes (proto_db MAX_FRAME_BYTES, 64 MiB); a tag counts in it."
PBClusterFrame class >> maxFrameBytes
  ^ 67108864.

"The size of the authentication tag, in bytes (HMAC-SHA-256)."
PBClusterFrame class >> tagSize
  ^ 32.

"The frame of aMessage (a PBClusterMessage) sent to the node aNodeId: the 4-byte big-endian
 length of the body, then the body: the msgpack bytes of the message, followed by their tag when
 aKeyOrNil is a key (CC4). PBClusterProtocolError, with proto_db check_frame_size's text, when
 the body would exceed maxFrameBytes, checked before the tag is computed; PBValidationError for
 anything that is not a message, a node id or a key."
PBClusterFrame class >> encode: aMessage to: aNodeId key: aKeyOrNil
  | payload size body |
  (aMessage isClassObject not and: [aMessage class == PBClusterMessage]) ifFalse: [
    ^ PBValidationError signal: 'PBClusterFrame encode: a PBClusterMessage, not ' , aMessage printString].
  self _checkReceiver: aNodeId key: aKeyOrNil.
  payload := aMessage encode.
  size := payload size + (aKeyOrNil isNil ifTrue: [0] ifFalse: [self tagSize]).
  size > self maxFrameBytes ifTrue: [
    ^ PBClusterProtocolError signal: 'A message of ' , size printString , ' bytes exceeds the frame limit of '
      , self maxFrameBytes printString].
  body := aKeyOrNil isNil
    ifTrue: [payload]
    ifFalse: [payload , (self _tagOf: payload to: aNodeId key: aKeyOrNil)].
  ^ (ByteArray withAll: (#(24 16 8 0) collect: [:shift | (body size bitShift: shift negated) bitAnd: 255])) , body.

"The body length a frame announces in aFourByteArray, its first 4 bytes (big endian).
 PBClusterProtocolError above maxFrameBytes, with proto_db FrameDecoder's text: the caller reads
 nothing more and drops the connection."
PBClusterFrame class >> lengthFrom: aFourByteArray
  | size |
  ((aFourByteArray isKindOf: ByteArray) and: [aFourByteArray size = 4]) ifFalse: [
    ^ PBValidationError signal: 'PBClusterFrame lengthFrom: 4 bytes, not ' , aFourByteArray printString].
  size := aFourByteArray unsignedLongAt: 1 bigEndian: true.
  size > self maxFrameBytes ifTrue: [
    ^ PBClusterProtocolError signal: 'A frame of ' , size printString , ' bytes exceeds the limit of '
      , self maxFrameBytes printString].
  ^ size.

"The message of aByteArray, the body of a frame received by the node aNodeId. With a key, the
 last tagSize bytes must be the tag of the bytes before them for aNodeId, else
 PBClusterProtocolError (authentication); the comparison runs over every byte of the tag.
 Then PBClusterMessage decode: refuses what is not a valid message."
PBClusterFrame class >> decodeBody: aByteArray to: aNodeId key: aKeyOrNil
  | payload tag |
  (aByteArray isKindOf: ByteArray) ifFalse: [
    ^ PBValidationError signal: 'PBClusterFrame decodeBody: a ByteArray, not ' , aByteArray printString].
  self _checkReceiver: aNodeId key: aKeyOrNil.
  aKeyOrNil isNil ifTrue: [^ PBClusterMessage decode: aByteArray].
  aByteArray size < self tagSize ifTrue: [
    ^ PBClusterProtocolError signal: 'Frame authentication failed: a body of ' , aByteArray size printString
      , ' bytes cannot hold a tag of ' , self tagSize printString].
  payload := aByteArray copyFrom: 1 to: aByteArray size - self tagSize.
  tag := aByteArray copyFrom: aByteArray size - self tagSize + 1 to: aByteArray size.
  (self _tag: tag matches: (self _tagOf: payload to: aNodeId key: aKeyOrNil)) ifFalse: [
    ^ PBClusterProtocolError signal: 'Frame authentication failed: the tag does not match the key and the receiver '
      , aNodeId printString].
  ^ PBClusterMessage decode: payload.

"The message of aFrame, a whole frame (length and body) received by the node aNodeId.
 PBClusterProtocolError when the length exceeds maxFrameBytes or is not the size of the body,
 then as decodeBody:to:key:."
PBClusterFrame class >> decode: aFrame to: aNodeId key: aKeyOrNil
  | size |
  (aFrame isKindOf: ByteArray) ifFalse: [
    ^ PBValidationError signal: 'PBClusterFrame decode: a ByteArray, not ' , aFrame printString].
  aFrame size < 4 ifTrue: [
    ^ PBClusterProtocolError signal: 'A frame of ' , aFrame size printString , ' bytes has no 4-byte length'].
  size := self lengthFrom: (aFrame copyFrom: 1 to: 4).
  size = (aFrame size - 4) ifFalse: [
    ^ PBClusterProtocolError signal: 'The frame length ' , size printString , ' is not the size of its body, '
      , (aFrame size - 4) printString , ' bytes'].
  ^ self decodeBody: (aFrame copyFrom: 5 to: aFrame size) to: aNodeId key: aKeyOrNil.

"PBValidationError unless aNodeId is a non-empty String without NUL (so UTF-8(id) || 0x00 ||
 msgpack names one pair; docs/deviations.md, 'Cluster mode') and aKeyOrNil is nil or a ByteArray
 of at least tagSize bytes (CC4)."
PBClusterFrame class >> _checkReceiver: aNodeId key: aKeyOrNil
  (aNodeId isString and: [aNodeId notEmpty and: [(aNodeId includes: (Character value: 0)) not]]) ifFalse: [
    ^ PBValidationError signal: 'A frame names its receiver with a non-empty String without NUL, not '
      , aNodeId printString].
  (aKeyOrNil isNil or: [(aKeyOrNil isKindOf: ByteArray) and: [aKeyOrNil size >= self tagSize]]) ifFalse: [
    ^ PBValidationError signal: 'A cluster key is nil or a ByteArray of at least ' , self tagSize printString
      , ' bytes, not ' , ((aKeyOrNil isKindOf: ByteArray) ifTrue: [aKeyOrNil size printString , ' bytes'] ifFalse: [aKeyOrNil class name])].

"The tag of aPayload sent to aNodeId (CC4): HMAC-SHA-256(aKey, UTF-8(aNodeId) || 0x00 || aPayload)."
PBClusterFrame class >> _tagOf: aPayload to: aNodeId key: aKey
  ^ HMAC sha256Key: aKey message: aNodeId utf8Encoded , #[0] , aPayload.

"Whether two tags of tagSize bytes are equal: the XOR of every pair of bytes is accumulated and
 tested once, with no early exit (best effort: the timing is not measured). protoST has no
 constant-time comparison of its own."
PBClusterFrame class >> _tag: aTag matches: anExpectedTag
  | difference |
  difference := 0.
  1 to: self tagSize do: [:i | difference := difference bitOr: ((aTag at: i) bitXor: (anExpectedTag at: i))].
  ^ difference = 0.
