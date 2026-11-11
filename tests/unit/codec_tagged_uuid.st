"EXPECT: ok 8"
"@uuid: the 16 bytes in RFC 4122 order, as protoST's UUID (lib/uuid.st,
 protoST 0.10.0), which PBCodec imports itself: the program does not. A
 host subclass of UUID is stored as its base value, read from the base
 instance variables, never through the subclass's methods, and reads back
 as a UUID."
Import from: 'protobase'.
Import from: '_check'.
UUID subclass: #TaggedUUID.
TaggedUUID >> bytes
  ^ ByteArray new: 16.
TaggedUUID >> printOn: aStream
  aStream nextPutAll: 'tagged'.
| c hex value tagged |
c := Check new.
c that: 'UUID is bound by importing protobase' isTrue: (Smalltalk at: #UUID ifAbsent: [nil]) notNil.
hex := '81a54075756964c41012345678123456781234567812345678'.
value := UUID fromString: '12345678-1234-5678-1234-567812345678'.
tagged := TaggedUUID fromString: '12345678-1234-5678-1234-567812345678'.
c that: '@uuid bytes' is: (PBCodec encode: value) hex equals: hex.
c that: '@uuid class' is: (PBCodec decode: (Check bytes: hex)) class equals: UUID.
c that: '@uuid value' is: (PBCodec decode: (Check bytes: hex)) equals: value.
c that: '@uuid re-encoded' is: (PBCodec encode: (PBCodec decode: (Check bytes: hex))) hex equals: hex.
c that: 'a UUID subclass is its base value' is: (PBCodec encode: tagged) hex equals: hex.
c that: 'a UUID subclass is canonically a UUID' is: (PBCodec canonical: tagged) class equals: UUID.
c that: 'a UUID subclass reads back a UUID' is: (PBCodec decode: (PBCodec encode: tagged)) class equals: UUID.
c report displayNl.
