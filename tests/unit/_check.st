"_check.st: a small assertion helper for the unit tests (a helper: the runner
 never runs files whose name starts with _).

  c := Check new.
  c that: 'label' is: actual equals: expected.
  c that: 'label' signals: PBCorruptionError during: [ ... ].
  c that: 'label' signals: PBCorruptionError containing: 'text' during: [ ... ].
  c report displayNl.  prints each failure; answers 'ok N' (N checks) or 'failed'"

Object subclass: #Check instanceVariableNames: 'failures count'.

Check class >> new
  ^ self basicNew setUp.

Check >> setUp
  failures := OrderedCollection new.
  count := 0.

Check >> that: aLabel is: actual equals: expected
  count := count + 1.
  actual = expected ifFalse: [
    failures add: aLabel , ': expected ' , expected printString , ', got ' , actual printString].

Check >> that: aLabel isTrue: aBoolean
  ^ self that: aLabel is: aBoolean equals: true.

Check >> that: aLabel signals: anErrorClass during: aBlock
  ^ self that: aLabel signals: anErrorClass containing: '' during: aBlock.

Check >> that: aLabel signals: anErrorClass containing: aText during: aBlock
  | outcome |
  count := count + 1.
  outcome := [aBlock value. 'no error'] on: Error do: [:e |
    (e isKindOf: anErrorClass)
      ifTrue: [(aText isEmpty or: [e messageText includesSubstring: aText])
        ifTrue: [nil]
        ifFalse: ['a message without ' , aText printString , ': ' , e messageText]]
      ifFalse: [e class name , ': ' , e messageText printString]].
  outcome isNil ifFalse: [
    failures add: aLabel , ': expected ' , anErrorClass name , ', got ' , outcome].

Check >> report
  failures do: [:each | ('FAIL ' , each) displayNl].
  ^ failures isEmpty
    ifTrue: ['ok ' , count printString]
    ifFalse: ['failed'].

"The bytes of a hexadecimal text ('cb3ff8...')."
Check class >> bytes: aHexText
  ^ ByteArray withAll: ((1 to: aHexText size // 2) asArray collect: [:i |
    ('0123456789abcdef' indexOf: (aHexText at: 2 * i - 1)) - 1 * 16
      + (('0123456789abcdef' indexOf: (aHexText at: 2 * i)) - 1)]).
