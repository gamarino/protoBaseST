"EXPECT: ok 51"
"PBNotation floatHex: and floatFromHex: against CPython's float.hex (literals pasted from
 CPython 3.12), bit exact in both directions."
Import from: 'protobase'.
Import from: '_check'.
| c pairs |
c := Check new.
"(bits as the 8 big-endian bytes in hexadecimal, CPython's float.hex)"
pairs := #(
  #('3ff8000000000000' '0x1.8000000000000p+0')
  #('3fb999999999999a' '0x1.999999999999ap-4')
  #('0000000000000000' '0x0.0p+0')
  #('8000000000000000' '-0x0.0p+0')
  #('0000000000000001' '0x0.0000000000001p-1022')
  #('8000000000000001' '-0x0.0000000000001p-1022')
  #('000fffffffffffff' '0x0.fffffffffffffp-1022')
  #('0010000000000000' '0x1.0000000000000p-1022')
  #('7fefffffffffffff' '0x1.fffffffffffffp+1023')
  #('ffefffffffffffff' '-0x1.fffffffffffffp+1023')
  #('3ff0000000000000' '0x1.0000000000000p+0')
  #('bff0000000000000' '-0x1.0000000000000p+0')
  #('4000000000000000' '0x1.0000000000000p+1')
  #('3fe0000000000000' '0x1.0000000000000p-1')
  #('4059000000000000' '0x1.9000000000000p+6')
  #('c02e000000000000' '-0x1.e000000000000p+3')).
pairs do: [:each |
  | bits text f |
  bits := each at: 1. text := each at: 2.
  f := (Check bytes: bits) float64At: 1 bigEndian: true.
  c that: text , ' floatHex:' is: (PBNotation floatHex: f) equals: text.
  c that: text , ' floatFromHex: bits' is: (MessagePack encode: (PBNotation floatFromHex: text)) hex
    equals: 'cb' , bits].
"The literals the task names."
c that: '1.5' is: (PBNotation floatHex: 1.5) equals: '0x1.8000000000000p+0'.
c that: '0.1' is: (PBNotation floatHex: 0.1) equals: '0x1.999999999999ap-4'.
c that: '1.7976931348623157e308' is: (PBNotation floatHex: 1.7976931348623157e308) equals: '0x1.fffffffffffffp+1023'.
c that: '-0.0' is: (PBNotation floatHex: -0.0) equals: '-0x0.0p+0'.
"nan, inf, -inf as repr."
c that: 'nan' is: (PBNotation floatHex: Float nan) equals: 'nan'.
c that: 'inf' is: (PBNotation floatHex: Float infinity) equals: 'inf'.
c that: '-inf' is: (PBNotation floatHex: Float infinity negated) equals: '-inf'.
c that: 'nan back' isTrue: (PBNotation floatFromHex: 'nan') isNaN.
c that: 'inf back' is: (PBNotation floatFromHex: 'inf') equals: Float infinity.
c that: '-inf back' is: (PBNotation floatFromHex: '-inf') equals: Float infinity negated.
"Texts the notation never writes are refused."
#('' '1.5' '0x1.8p+0' '0x1.8000000000000p0' '0x2.0000000000000p+0' '0x1.8000000000000p+1024'
  '0x0.0000000000001p-1021' '0X1.8000000000000p+0' 'NaN') do: [:bad |
  c that: bad printString , ' refused' signals: PBValidationError during: [PBNotation floatFromHex: bad]].
c report displayNl.
