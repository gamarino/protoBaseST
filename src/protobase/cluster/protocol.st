"-- cluster/protocol.st: the wire messages of cluster protocol 13 --

The messages of proto_db cluster/protocol.py at v2.0.0rc3 (MESSAGE_TYPES, _check_field,
validate_message, encode_root, decode_labeled_root; format spec, 'Cluster wire protocol').
Every message is a msgpack map: v (the protocol version, 13), type, from (the sender's node
id, a String), then the fields of its type in the order of the table, which is proto_db's
MESSAGE_TYPES copied verbatim. The frame around a message (the 4-byte length) is not here.

  PBClusterMessage  a validated message: type, from, at: aFieldName, encode. Class side:
                    protocolVersion, schema, type:from:fields: (a message protoBaseST sends:
                    built wrong is PBValidationError, a bug of ours), decode: (received bytes:
                    anything invalid is PBClusterProtocolError, and the receiver drops the
                    connection), and the readers and writers of the field values: rootFrom: /
                    rootValue: (CC17), rangesFrom: / rangesValue:, afterFrom:.

Field kinds (format spec, 'Field types'; proto_db _check_field):
  #int       an Integer >= 0 (never a Boolean or a Float)
  #number    an Integer or a Float, >= 0 (a NaN is refused)
  #str #bool a String; true or false
  #root      nil (unknown), { 0. nil. nil. label } (the empty space, known) or { epoch.
             16 segment bytes. offset. label }; the 3-item form without the label reads with
             label 0 and is never written (CC17)
  #records   an Array of { 16 segment bytes. offset. framed record bytes or nil }
  #uuid      16 bytes; #optBytes / #optStr: bytes or nil / a String or nil
  #ranges    nil or an Array of { 16 segment bytes. start. end } with 0 <= start <= end
  #strs      an Array of Strings
  #after     nil or { seq > 0. holder String } (DEPTH 0 never sends a non-nil after)

Received maps are read as proto_db reads them (msgpack-python unpackb, strict_map_key): a map
key that is not a str or a bin is refused, a repeated key keeps its last value, extra fields
are ignored and never re-encoded. As Python's 13.0 == 13, a version written as the Float 13.0
is protocol 13. A message holds its own copies of the field values and at: answers a fresh
copy: every value here is immutable."

Import from: 'protobase/errors'.
Import from: 'protobase/framing'.
Import from: 'protobase/cluster/rootlog'.

Object subclass: #PBClusterMessage instanceVariableNames: 'type from values' classVariableNames: 'Schema'.

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

PBClusterMessage class >> protocolVersion
  ^ 13.

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

"A message protoBaseST sends: aString a type, anId the sender's node id, anArrayOfAssociations
 exactly the fields of the type (field name -> wire value), in any order. Anything else is
 PBValidationError: a message built wrong is a bug of the sender, never sent."
PBClusterMessage class >> type: aString from: anId fields: anArrayOfAssociations
  | fields names |
  fields := self _fieldsOf: aString.
  fields isNil ifTrue: [^ PBValidationError signal: 'Unknown message type ' , aString printString].
  anId isString ifFalse: [^ PBValidationError signal: 'A message names its sender with a String, not ' , anId printString].
  (anArrayOfAssociations isArray and: [anArrayOfAssociations allSatisfy: [:each | each isKindOf: Association]]) ifFalse: [
    ^ PBValidationError signal: 'The fields of a message are an Array of Associations, not ' , anArrayOfAssociations printString].
  names := fields collect: [:each | each key].
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
      self _copyWire: given value]).

"The message of aByteArray, the body of one frame (proto_db decode_message, validate_message).
 PBClusterProtocolError for bytes that are not one msgpack map, a key that is not a str or a
 bin, a missing v, type or from, another version, an unknown type, a missing or ill-typed
 field; extra fields are ignored."
PBClusterMessage class >> decode: aByteArray
  | map version kind fields from |
  (aByteArray isKindOf: ByteArray) ifFalse: [
    ^ PBValidationError signal: 'PBClusterMessage decode: a ByteArray was expected, not ' , aByteArray class name].
  map := [MessagePack decodeOrdered: aByteArray strictKeys: true]
    on: Error do: [:e |
      (e isKindOf: MessageNotUnderstood) ifTrue: [e pass].
      PBClusterProtocolError signal: 'Undecodable message: ' , e messageText].
  (map isKindOf: MessagePackMap) ifFalse: [
    ^ PBClusterProtocolError signal: 'A message must be a map, got ' , map class name].
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
      value]).

PBClusterMessage class >> _field: aField of: aType refusing: aValue
  | text problem |
  text := 'Field ' , aField key printString , ' of a ' , aType printString , ' message must be a valid '
    , aField value , ', got ' , aValue printString.
  aField value = #root ifFalse: [^ text].
  problem := self _rootProblem: aValue.
  ^ text , ': ' , problem.

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

"nil when aValue is a wire root, else what is wrong with it (proto_db decode_labeled_root)."
PBClusterMessage class >> _rootProblem: aValue
  | epoch segment offset label |
  aValue isNil ifTrue: [^ nil].
  (aValue isArray and: [aValue size = 3 or: [aValue size = 4]]) ifFalse: [^ 'Malformed root ' , aValue printString].
  epoch := aValue at: 1.
  segment := aValue at: 2.
  offset := aValue at: 3.
  label := aValue size = 4 ifTrue: [aValue at: 4] ifFalse: [0].
  ((self _isCount: epoch) and: [self _isCount: label]) ifFalse: [
    ^ 'Malformed root epoch or term ' , aValue printString].
  epoch = 0 ifTrue: [
    ^ (segment isNil and: [offset isNil]) ifTrue: [nil] ifFalse: ['The empty root (epoch 0) has no pointer']].
  ((self _isSegment: segment) and: [self _isCount: offset]) ifFalse: [^ 'Malformed root pointer ' , aValue printString].
  ^ nil.

"The root a wire root names (CC17): nil (unknown) or a PBLabeledRoot, the empty space for
 epoch 0, label 0 for the 3-item form. PBClusterProtocolError for anything else."
PBClusterMessage class >> rootFrom: aWireValue
  | problem label |
  problem := self _rootProblem: aWireValue.
  problem isNil ifFalse: [^ PBClusterProtocolError signal: problem].
  aWireValue isNil ifTrue: [^ nil].
  label := aWireValue size = 4 ifTrue: [aWireValue at: 4] ifFalse: [0].
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

"A fresh copy of the wire value of the field aFieldName; PBValidationError when the type has no
 such field."
PBClusterMessage >> at: aFieldName
  | fields |
  fields := self class _fieldsOf: type.
  1 to: fields size do: [:i |
    (fields at: i) key = aFieldName ifTrue: [^ self class _copyWire: (values at: i)]].
  ^ PBValidationError signal: 'A ' , type printString , ' message has no field ' , aFieldName printString.

"The msgpack bytes of the message: a map of v, type, from, then the fields in the order of the
 table (proto_db encode_message of a message make_message built in that order)."
PBClusterMessage >> encode
  | fields |
  fields := self class _fieldsOf: type.
  ^ MessagePack encode: (MessagePackMap withAll: { 'v' -> self class protocolVersion. 'type' -> type. 'from' -> from }
    , ((1 to: fields size) asArray collect: [:i | (fields at: i) key -> (values at: i)])).

PBClusterMessage _initializeSchema.
