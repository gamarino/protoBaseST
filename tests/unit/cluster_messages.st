"EXPECT: ok 22"
"PBClusterMessage (cluster/protocol.st): the protocol-13 messages of proto_db
 cluster/protocol.py (validate_message, _check_field, decode_labeled_root). A received map
 is validated against the field table of its type: extra fields are ignored and never
 re-encoded; an int field refuses a Float, a number field takes one; a root is nil,
 [0, nil, nil, label] (the empty space) or [epoch, 16 segment bytes, offset, label], and the
 3-item form reads with label 0 (CC17); a range has start <= end; a map key that is not a str
 (or bin, msgpack-python's strict_map_key) is refused. Every refusal of received bytes is
 PBClusterProtocolError, a PBCorruptionError; a message built wrong by protoBaseST itself is
 PBValidationError (a bug of ours, not a peer's).
 Pinned where proto_db's code is followed over its format spec's wording (docs/deviations.md,
 'Cluster wire messages'): a bin key is accepted by the decoder, so a bin v is a missing v and
 an extra bin key is ignored; v written as the Float 13.0 is version 13 (Python's 13.0 == 13),
 true is not; a timestamp ext (type -1) anywhere in the map, extra fields included, is refused
 when msgpack-python's Timestamp would refuse it (data of 4, 8 or 12 bytes, nanoseconds below
 10^9). A message built with an integer outside msgpack's range (2^64 or more) or with the
 3-item root form (never written, CC17) is PBValidationError."
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

"proto_db's code over its format spec's wording."
c that: 'a bin v is a missing v' signals: PBClusterProtocolError containing: 'version'
  during: [PBClusterMessage decode: (raw value: { #[118] -> 13. 'type' -> 'want'. 'from' -> 'n1' })].
c that: 'an extra bin key is ignored' is: (PBClusterMessage decode: (raw value: (head value: 'want') , { #[120] -> 1 })) encode
  equals: (raw value: (head value: 'want')).
c that: 'v as the Float 13.0 is version 13' is: (PBClusterMessage decode: (raw value: { 'v' -> 13.0. 'type' -> 'want'. 'from' -> 'n1' })) type
  equals: 'want'.
c that: 'v as true is refused' signals: PBClusterProtocolError containing: 'version'
  during: [PBClusterMessage decode: (raw value: { 'v' -> true. 'type' -> 'want'. 'from' -> 'n1' })].

"Timestamp exts, as msgpack-python's Timestamp reads them."
c that: 'a 2-byte timestamp in an extra field is refused' signals: PBClusterProtocolError containing: 'timestamp'
  during: [PBClusterMessage decode: (raw value: (head value: 'want') , { 'extra' -> { MessagePackExt type: -1 data: #[0 0] } })].
c that: 'a 12-byte timestamp of 10^9 nanoseconds is refused' signals: PBClusterProtocolError containing: 'timestamp'
  during: [PBClusterMessage decode: (raw value: (head value: 'want') , { 'extra' -> (MessagePackMap withAll: {
    'k' -> (MessagePackExt type: -1 data: (Check bytes: '3b9aca000000000000000000')) }) })].
c that: 'a valid timestamp and another ext in extra fields are ignored' is: (PBClusterMessage decode: (raw value: (head value: 'want')
    , { 'a' -> (MessagePackExt type: -1 data: (Check bytes: '3b9ac9ff0000000000000000')). 'b' -> (MessagePackExt type: 5 data: #[0 0]) })) type
  equals: 'want'.

"Built wrong: integers outside msgpack's range, the 3-item root."
c that: 'an int field of 2^64 is refused when built' signals: PBValidationError containing: 'term'
  during: [PBClusterMessage type: 'request' from: 'n1' fields: { 'term' -> (2 raisedTo: 64). 'rid' -> 1. 'inc' -> 41. 'vs' -> 3 }].
c that: 'a range end of 2^64 is refused when built' signals: PBValidationError containing: 'ranges'
  during: [PBClusterMessage type: 'commit_info' from: 'n1' fields: { 'rid' -> 9. 'inc' -> 43. 'persisted' -> false.
    'ranges' -> { { seg. 26. 2 raisedTo: 64 } } }].
c that: 'the 3-item root form is refused when built' signals: PBValidationError containing: 'root'
  during: [PBClusterMessage type: 'commit_query' from: 'n1' fields: { 'rid' -> 9. 'inc' -> 43. 'root' -> { 3. seg. 16534 } }].
c report displayNl.
