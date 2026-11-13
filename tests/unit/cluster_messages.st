"EXPECT: ok 12"
"PBClusterMessage (cluster/protocol.st): the protocol-13 messages of proto_db
 cluster/protocol.py (validate_message, _check_field, decode_labeled_root). A received map
 is validated against the field table of its type: extra fields are ignored and never
 re-encoded; an int field refuses a Float, a number field takes one; a root is nil,
 [0, nil, nil, label] (the empty space) or [epoch, 16 segment bytes, offset, label], and the
 3-item form reads with label 0 (CC17); a range has start <= end; a map key that is not a str
 (or bin, msgpack-python's strict_map_key) is refused. Every refusal of received bytes is
 PBClusterProtocolError, a PBCorruptionError; a message built wrong by protoBaseST itself is
 PBValidationError (a bug of ours, not a peer's)."
Import from: 'protobase'.
Import from: '_check'.
| c raw head seg request fields root rejectFields |
c := Check new.
raw := [:assocs | MessagePack encode: (MessagePackMap withAll: assocs)].
head := [:type | { 'v' -> 13. 'type' -> type. 'from' -> 'n1' }].
seg := Check bytes: '5eed0000000040008000000000001004'.
fields := { 'term' -> 7. 'rid' -> 1. 'inc' -> 41. 'vs' -> 3 }.
request := PBClusterMessage type: 'request' from: 'n1' fields: fields.

"An extra field is ignored: decoded, then re-encoded without it."
c that: 'an extra field decodes, ignored' is: ((PBClusterMessage decode: (raw value: (head value: 'request') , fields , { 'extra' -> #(1 2) }))
  at: 'vs') equals: 3.
c that: 'an extra field is not re-encoded' is: (PBClusterMessage decode: (raw value: (head value: 'request') , { 'extra' -> 'x' } , fields)) encode
  equals: request encode.

"int and number fields."
c that: 'term as a Float is refused' signals: PBClusterProtocolError containing: 'term'
  during: [PBClusterMessage decode: (raw value: (head value: 'request') , { 'term' -> 7.0. 'rid' -> 1. 'inc' -> 41. 'vs' -> 3 })].
rejectFields := [:remaining | { 'term' -> 7. 'rid' -> 1. 'inc' -> 41. 'root' -> nil. 'certain' -> true. 'reason' -> 'promised'.
  'highest' -> 9. 'remaining' -> remaining }].
c that: 'remaining as a Float is accepted' is: ((PBClusterMessage decode: (raw value: (head value: 'reject') , (rejectFields value: 0.5)))
  at: 'remaining') equals: 0.5.

"Roots (CC17)."
root := PBClusterMessage rootFrom: { 0. nil. nil. 9 }.
c that: '[0, nil, nil, 9] is the empty space of label 9' is: { root label. root record. root epoch } equals: { 9. nil. 0 }.
root := PBClusterMessage rootFrom: { 3. seg. 16534 }.
c that: 'the 3-item root reads with label 0' is: { root label. root epoch. root record segment. root record offset }
  equals: { 0. 3. seg. 16534 }.
c that: 'a root of a 15-byte segment is refused' signals: PBClusterProtocolError containing: 'root'
  during: [PBClusterMessage decode: (raw value: (head value: 'commit_query') , { 'rid' -> 9. 'inc' -> 43.
    'root' -> { 4. seg copyFrom: 1 to: 15. 26. 7 } })].

"Ranges and map keys."
c that: 'a range with start > end is refused' signals: PBClusterProtocolError containing: 'ranges'
  during: [PBClusterMessage decode: (raw value: (head value: 'commit_info') , { 'rid' -> 9. 'inc' -> 43. 'persisted' -> false.
    'ranges' -> { { seg. 184. 26 } } })].
c that: 'a map with an integer key is refused' signals: PBClusterProtocolError
  during: [PBClusterMessage decode: (raw value: (head value: 'request') , fields , { 5 -> 1 })].

c that: 'PBClusterProtocolError is a PBCorruptionError' isTrue: (PBClusterProtocolError inheritsFrom: PBCorruptionError).

"Built wrong by protoBaseST: PBValidationError."
c that: 'building a message without one of its fields is refused' signals: PBValidationError containing: 'vs'
  during: [PBClusterMessage type: 'request' from: 'n1' fields: (fields copyFrom: 1 to: 3)].
c that: 'building a message with a field of another type is refused' signals: PBValidationError containing: 'root'
  during: [PBClusterMessage type: 'request' from: 'n1' fields: fields , { 'root' -> nil }].
c report displayNl.
