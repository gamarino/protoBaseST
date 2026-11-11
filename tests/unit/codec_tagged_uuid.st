"EXPECT: ok 4"
"@uuid: the 16 bytes in RFC 4122 order. It needs protoST's UUID (lib/uuid.st,
 plan Task 5, which waits for the build-gated Task 2): without it the test
 is a visible SKIP, and the codec refuses @uuid with PBNotSupportedError."
Import from: 'protobase'.
Import from: '_check'.
| c uuid hex value |
uuid := Smalltalk at: #UUID ifAbsent: [nil].
uuid isNil ifTrue: [
  [PBCodec decode: (Check bytes: '81a54075756964c41012345678123456781234567812345678')]
    on: PBNotSupportedError do: [:e | 'SKIP: lib/uuid.st is not in this protoST (plan Task 5); @uuid is refused with PBNotSupportedError' displayNl.
      Smalltalk exit: 0].
  'FAIL: @uuid was not refused without lib/uuid.st' displayNl.
  Smalltalk exit: 1].
c := Check new.
hex := '81a54075756964c41012345678123456781234567812345678'.
value := uuid fromString: '12345678-1234-5678-1234-567812345678'.
c that: '@uuid bytes' is: (PBCodec encode: value) hex equals: hex.
c that: '@uuid class' is: (PBCodec decode: (Check bytes: hex)) class equals: uuid.
c that: '@uuid value' is: (PBCodec decode: (Check bytes: hex)) equals: value.
c that: '@uuid re-encoded' is: (PBCodec encode: (PBCodec decode: (Check bytes: hex))) hex equals: hex.
c report displayNl.
