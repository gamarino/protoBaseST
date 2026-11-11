"EXPECT: ok 64"
"PBList positions as ProtoBase's List takes them (plan Review Focus 5, call C15). Each line
 below is what ProtoBase v2.0.0rc1 answered for List [10, 20, 30, 40, 50], recorded by
 tests/interop/py_list_positions.py and pasted here: '<message> => <elements after it, or
 the element read, or the error class>'. The test sends each message to the same PBList
 and requires the same line, with ProtoValidationError read as PBValidationError and
 Python's None as nil. Positions are 0-based; a negative one counts from the end; getAt:
 count, setAt: count, removeAt: count and insertAt: count + 1 are refused, insertAt: count
 appends; a position that is not an Integer ('a', true, 1.0) is refused; slices, head: and
 tail: clamp like Python slices.

 Intended deviations, listed in 'deviations' with protoBaseST's answer: a slice bound
 that is neither an Integer nor nil is PBValidationError. ProtoBase hands its bounds to
 Python's slice.indices, which takes True as 1 and raises TypeError for 'a' and 1.0; in
 Smalltalk a Boolean is not a number, and ProtoBase's own _position refuses bool."
Import from: 'protobase'.
Import from: '_check'.

| c base recorded deviations arg run l |
c := Check new.
recorded := #(
  'getAt: 0 => 10'
  'getAt: 4 => 50'
  'getAt: 5 => error ProtoValidationError'
  'getAt: -1 => 50'
  'getAt: -5 => 10'
  'getAt: -6 => error ProtoValidationError'
  'getAt: ''a'' => error ProtoValidationError'
  'getAt: true => error ProtoValidationError'
  'getAt: 1.0 => error ProtoValidationError'
  'setAt: 0 value: 99 => 99 20 30 40 50'
  'setAt: 4 value: 99 => 10 20 30 40 99'
  'setAt: 5 value: 99 => error ProtoValidationError'
  'setAt: -1 value: 99 => 10 20 30 40 99'
  'setAt: -5 value: 99 => 99 20 30 40 50'
  'setAt: -6 value: 99 => error ProtoValidationError'
  'insertAt: 0 value: 99 => 99 10 20 30 40 50'
  'insertAt: 4 value: 99 => 10 20 30 40 99 50'
  'insertAt: 5 value: 99 => 10 20 30 40 50 99'
  'insertAt: 6 value: 99 => error ProtoValidationError'
  'insertAt: -1 value: 99 => 10 20 30 40 99 50'
  'insertAt: -5 value: 99 => 99 10 20 30 40 50'
  'insertAt: -6 value: 99 => error ProtoValidationError'
  'removeAt: 0 => 20 30 40 50'
  'removeAt: 4 => 10 20 30 40'
  'removeAt: 5 => error ProtoValidationError'
  'removeAt: -1 => 10 20 30 40'
  'removeAt: -5 => 20 30 40 50'
  'removeAt: -6 => error ProtoValidationError'
  'sliceFrom: nil to: nil => 10 20 30 40 50'
  'sliceFrom: 1 to: 3 => 20 30'
  'sliceFrom: -2 to: nil => 40 50'
  'sliceFrom: nil to: -2 => 10 20 30'
  'sliceFrom: 3 to: 1 => []'
  'sliceFrom: -10 to: 10 => 10 20 30 40 50'
  'sliceFrom: 10 to: 20 => []'
  'sliceFrom: 2 to: 2 => []'
  'sliceFrom: -3 to: -1 => 30 40'
  'sliceFrom: 0 to: 5 => 10 20 30 40 50'
  'sliceFrom: true to: nil => 20 30 40 50'
  'sliceFrom: ''a'' to: nil => error TypeError'
  'sliceFrom: 1.0 to: nil => error TypeError'
  'head: 0 => []'
  'tail: 0 => 10 20 30 40 50'
  'head: 2 => 10 20'
  'tail: 2 => 30 40 50'
  'head: -1 => 10 20 30 40'
  'tail: -1 => 50'
  'head: 5 => 10 20 30 40 50'
  'tail: 5 => []'
  'head: 10 => 10 20 30 40 50'
  'tail: 10 => []'
  'head: -10 => []'
  'tail: -10 => 10 20 30 40 50'
  'appendFirst: 99 => 99 10 20 30 40 50'
  'appendLast: 99 => 10 20 30 40 50 99'
  'extend: 1 2 3 => 10 20 30 40 50 1 2 3'
  'extend: empty => 10 20 30 40 50'
).
deviations := Dictionary new.
deviations
  at: 'sliceFrom: true to: nil' put: 'error ProtoValidationError';
  at: 'sliceFrom: ''a'' to: nil' put: 'error ProtoValidationError';
  at: 'sliceFrom: 1.0 to: nil' put: 'error ProtoValidationError'.
base := PBList new extend: #(10 20 30 40 50).
"An argument word of a recorded message."
arg := [:w |
  w = 'nil' ifTrue: [nil] ifFalse: [
  w = 'true' ifTrue: [true] ifFalse: [
  w first = $' ifTrue: [w copyFrom: 2 to: w size - 1] ifFalse: [
  (w includes: $.) ifTrue: [w asNumber asFloat] ifFalse: [w asNumber]]]]].
"The line protoBaseST gives for a recorded message."
run := [:text |
  | words result |
  words := text subStrings: ' '.
  result := [ | sel |
    sel := words first.
    sel = 'extend:'
      ifTrue: [base extend: ((words at: 2) = 'empty'
        ifTrue: [#()]
        ifFalse: [((words copyFrom: 2 to: words size) collect: [:w | arg value: w]) asArray])]
      ifFalse: [words size = 2
        ifTrue: [base perform: sel asSymbol with: (arg value: (words at: 2))]
        ifFalse: [base perform: (sel , (words at: 3)) asSymbol with: (arg value: (words at: 2)) with: (arg value: (words at: 4))]]]
    on: PBDBError do: [:e | e return: 'error ' , (e class name copyReplaceAll: 'PB' with: 'Proto')].
  (result isKindOf: PBList)
    ifTrue: [result := result isEmpty ifTrue: ['[]'] ifFalse: [
      result elements inject: '' into: [:acc :each | acc isEmpty ifTrue: [each printString] ifFalse: [acc , ' ' , each printString]]]]
    ifFalse: [result isString ifFalse: [result := result printString]].
  text , ' => ' , result].
recorded do: [:line |
  | text |
  text := line copyFrom: 1 to: (line findString: ' => ') - 1.
  c that: text is: (run value: text) equals: (deviations at: text
    ifPresent: [:mine | text , ' => ' , mine]
    ifAbsent: [line])].
c that: 'every deviation is a recorded case' isTrue: (deviations keys allSatisfy: [:k |
  recorded anySatisfy: [:line | line beginsWith: k , ' => ']]).
"The cases of the plan, by name."
l := base count.
c that: 'getAt: -1 is the last element' is: (base getAt: -1) equals: 50.
c that: 'getAt: count' signals: PBValidationError during: [base getAt: l].
c that: 'insertAt: count appends' is: (base insertAt: l value: 99) elements equals: #(10 20 30 40 50 99).
c that: 'insertAt: count + 1' signals: PBValidationError during: [base insertAt: l + 1 value: 99].
c that: 'getAt: ''a''' signals: PBValidationError during: [base getAt: 'a'].
c that: 'the base list is unchanged' is: base elements equals: #(10 20 30 40 50).
c report displayNl.
