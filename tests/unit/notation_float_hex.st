"EXPECT: ok 81"
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
#('' '1.5' '0x1.8p+0' '0x0.0000000000000p+0' '-0x0.0000000000000p+0' '0x1.8000000000000p-0'
  '0x1.8000000000000p' '0x1.8000000000000p+' '0x1.8000000000000p+01' '0x1.8000000000000p+x'
  '0x1.800000000000p+0' '0x1.80000000000000p+0' '0x1.800000000000Ap+0' '0x0.0000000000001p-1022x'
  '0x1' '0x' '-' '0x1.8000000000000' '0x1.8000000000000p0' '0x2.0000000000000p+0' '0x1.8000000000000p+1024'
  '0x0.0000000000001p-1021' '0X1.8000000000000p+0' 'NaN') do: [:bad |
  c that: bad printString , ' refused' signals: PBValidationError during: [PBNotation floatFromHex: bad]].

"5e-324, the smallest subnormal, written as a literal (protoST D51)."
c that: '5e-324' is: (PBNotation floatHex: 5e-324) equals: '0x0.0000000000001p-1022'.
c that: '5e-324 is CPython''s bits 0x0000000000000001' is: (MessagePack encode: 5e-324) hex equals: 'cb0000000000000001'.
c that: '5e-324 back' is: (MessagePack encode: (PBNotation floatFromHex: '0x0.0000000000001p-1022')) hex
  equals: 'cb0000000000000001'.
"NaNs of any payload and sign describe as 'nan' (Python writes repr); reading it gives a NaN."
#('7ff8000000000001' '7ff0000000000001' 'fff8000000000000' '7ffdeadbeef00001') do: [:bits |
  | nan |
  nan := (Check bytes: bits) float64At: 1 bigEndian: true.
  c that: bits , ' is a NaN' isTrue: nan isNaN.
  c that: bits , ' floatHex:' is: (PBNotation floatHex: nan) equals: 'nan'.
  c that: bits , ' describe:' is: (PBNotation describe: nan) equals: (Dictionary new at: 'float' put: 'nan'; yourself)].
c report displayNl.
