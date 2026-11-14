"EXPECT: ok 17"
"PBClusterFrame (cluster/protocol.st): the frames of cluster protocol 13, a 4-byte big-endian
 length then the body, at most 64 MiB (proto_db cluster/protocol.py encode_frame,
 FrameDecoder), and the optional HMAC frame authentication of CC4 (design spec 8.4, Q5).
 Without a key the frame is protocol 13 byte for byte (the vector request.frame). With a key
 the body is the msgpack bytes followed by a 32-byte tag, HMAC-SHA-256(key, UTF-8(receiver id)
 || 0x00 || msgpack bytes), and the length covers both: a frame bound to another receiver, a
 flipped tag byte, a keyed frame read without the key and an unkeyed frame read with one are
 PBClusterProtocolError. A key shorter than 32 bytes is PBValidationError. A length over
 64 MiB (the vector message-oversized) is refused from the 4 length bytes alone, and a frame
 whose length is not the size of its body is refused. The tags of a non-ASCII receiver and of a
 100-byte key (HMAC hashes a key over 64 bytes) are those Python's hmac computes (constants
 below). An empty key, an empty receiver id and one holding NUL are PBValidationError: with no
 NUL in the id, UTF-8(id) || 0x00 || msgpack names one (id, msgpack) pair. A message whose
 msgpack bytes fit the limit only without the tag is refused when sent with a key, with
 proto_db check_frame_size's text (one 64 MiB buffer, about 1 s)."
Import from: 'protobase'.
Import from: '_check'.
| c vectors frame message key keyed body payload tag flipped big |
c := Check new.
vectors := '../conformance/vectors/' asFileReference.
frame := (vectors / 'cluster' / 'messages' / 'request.frame') binaryContents.
message := PBClusterMessage decode: (frame copyFrom: 5 to: frame size).
key := ByteArray withAll: ((1 to: 32) asArray collect: [:i | i * 7 \\ 256]).

c that: 'without a key, the frame is the protocol-13 vector byte for byte'
  is: (PBClusterFrame encode: message to: 'n1' key: nil) equals: frame.
c that: 'a length over 64 MiB is refused from the length bytes' signals: PBClusterProtocolError containing: 'exceeds'
  during: [PBClusterFrame lengthFrom: (vectors / 'invalid' / 'message-oversized.bin') binaryContents].

keyed := PBClusterFrame encode: message to: 'n1' key: key.
c that: 'with a key, a frame round-trips' is: (PBClusterFrame decode: keyed to: 'n1' key: key) encode equals: message encode.
body := keyed copyFrom: 5 to: keyed size.
payload := body copyFrom: 1 to: body size - 32.
tag := body copyFrom: body size - 31 to: body size.
c that: 'the tag is HMAC-SHA-256 over the receiver id, 0 and the msgpack bytes, covered by the length'
  is: { payload. tag. PBClusterFrame lengthFrom: (keyed copyFrom: 1 to: 4) }
  equals: { message encode. HMAC sha256Key: key message: ('n1' utf8Encoded , #[0] , payload). body size }.
c that: 'a frame bound to n1 is refused by n2' signals: PBClusterProtocolError containing: 'authentication'
  during: [PBClusterFrame decode: keyed to: 'n2' key: key].
flipped := (keyed copyFrom: 1 to: keyed size - 1) , (ByteArray withAll: { (keyed at: keyed size) bitXor: 1 }).
c that: 'a flipped tag byte is refused' signals: PBClusterProtocolError containing: 'authentication'
  during: [PBClusterFrame decode: flipped to: 'n1' key: key].
c that: 'a keyed frame read without a key is refused (the tag is not msgpack)' signals: PBClusterProtocolError
  during: [PBClusterFrame decode: keyed to: 'n1' key: nil].
c that: 'an unkeyed frame read with a key is refused' signals: PBClusterProtocolError containing: 'authentication'
  during: [PBClusterFrame decode: frame to: 'n1' key: key].
c that: 'a key of 31 bytes is refused' signals: PBValidationError containing: '32'
  during: [PBClusterFrame encode: message to: 'n1' key: (key copyFrom: 1 to: 31)].
c that: 'a frame whose length is not the size of its body is refused' signals: PBClusterProtocolError containing: 'length'
  during: [PBClusterFrame decode: (frame copyFrom: 1 to: frame size - 1) to: 'n1' key: nil].

"Python: hmac.new(key, 'nödo'.encode() + b'\0' + body, sha256), and the same for a 100-byte key."
keyed := PBClusterFrame encode: message to: 'nödo' key: key.
c that: 'the tag of a non-ASCII receiver is the UTF-8 one Python computes'
  is: (keyed copyFrom: keyed size - 31 to: keyed size)
  equals: (Check bytes: 'd4e4126e199f45ee7a259deeb97a99bc5cb6806b52783f130e9ad8cf2270c1fe').
c that: 'a non-ASCII receiver round-trips' is: (PBClusterFrame decode: keyed to: 'nödo' key: key) encode equals: message encode.
keyed := PBClusterFrame encode: message to: 'n1' key: (ByteArray withAll: ((1 to: 100) asArray collect: [:i | i * 3 \\ 256])).
c that: 'the tag of a 100-byte key is the one Python computes'
  is: (keyed copyFrom: keyed size - 31 to: keyed size)
  equals: (Check bytes: '70cbf4f0b4af6a6f72a6ae5bdfc206569e2dbed9675983eeb0f373abdf918923').
c that: 'an empty key is refused' signals: PBValidationError containing: '32'
  during: [PBClusterFrame encode: message to: 'n1' key: #[]].
c that: 'an empty receiver id is refused' signals: PBValidationError containing: 'receiver'
  during: [PBClusterFrame encode: message to: '' key: nil].
c that: 'a receiver id holding NUL is refused when decoding' signals: PBValidationError containing: 'receiver'
  during: [PBClusterFrame decode: frame to: 'n1' , (String with: (Character value: 0)) , 'x' key: key].
big := PBClusterMessage type: 'fetched' from: 'n1' fields: { 'rid' -> 1. 'inc' -> 1. 'segment' -> (ByteArray new: 16).
  'offset' -> 0. 'data' -> (ByteArray new: PBClusterFrame maxFrameBytes - 95) }.
c that: 'msgpack bytes 16 under the limit with a 32-byte tag are refused' is: { big encode size.
    [PBClusterFrame encode: big to: 'n2' key: key] on: PBClusterProtocolError do: [:e | e return: e messageText] }
  equals: { PBClusterFrame maxFrameBytes - 16. 'A message of 67108880 bytes exceeds the frame limit of 67108864' }.
big := nil.
c report displayNl.
