"_lesson.st: the checks of the tutorial examples (a helper: the test runner never runs files
 whose name starts with _).

 Every example of examples/tutorial proves what it shows. It prints a line for each check it
 makes, 'ok - <what>' or 'FAIL - <what>: expected ..., got ...', and its last line is
 '<lesson> ok (N checks)' when every check held. A failed check makes the last line
 '<lesson> FAILED' and the exit status 1, so a silent failure is impossible: the test runner
 compares the last line with the example's EXPECT directive.

   lesson := Lesson named: '01 first commit'.
   lesson check: 'the root was stored' is: actual equals: expected.
   lesson check: 'a condition' isTrue: aBoolean.
   lesson check: 'a refusal' signals: PBValidationError containing: 'text' during: [ ... ].
   lesson say: 'a line that explains what happened'.
   lesson finish."

Object subclass: #Lesson instanceVariableNames: 'name failures count'.

Lesson class >> named: aString
  ^ self basicNew setName: aString.

Lesson >> setName: aString
  name := aString.
  failures := 0.
  count := 0.

"Prints a line of explanation, indented under the checks."
Lesson >> say: aString
  ('   ' , aString) displayNl.

Lesson >> check: aLabel is: actual equals: expected
  count := count + 1.
  actual = expected
    ifTrue: [('ok - ' , aLabel) displayNl]
    ifFalse: [
      failures := failures + 1.
      ('FAIL - ' , aLabel , ': expected ' , expected printString , ', got ' , actual printString) displayNl].

Lesson >> check: aLabel isTrue: aBoolean
  ^ self check: aLabel is: aBoolean equals: true.

"Runs aBlock, which must signal anErrorClass with aText in its message. Answers the message."
Lesson >> check: aLabel signals: anErrorClass containing: aText during: aBlock
  | outcome text |
  text := nil.
  outcome := [aBlock value. 'no error was signalled'] on: Error do: [:e |
    text := e messageText.
    (e isKindOf: anErrorClass)
      ifTrue: [(text includesSubstring: aText)
        ifTrue: [nil]
        ifFalse: ['a message without ' , aText printString , ': ' , text]]
      ifFalse: [e class name , ': ' , text printString]].
  count := count + 1.
  outcome isNil
    ifTrue: [('ok - ' , aLabel) displayNl]
    ifFalse: [
      failures := failures + 1.
      ('FAIL - ' , aLabel , ': expected ' , anErrorClass name , ', got ' , outcome) displayNl].
  ^ text.

"Prints the last line. A failed check ends the program with status 1."
Lesson >> finish
  failures = 0 ifTrue: [
    ^ (name , ' ok (' , count printString , ' checks)') displayNl].
  (name , ' FAILED (' , failures printString , ' of ' , count printString , ' checks)') displayNl.
  Smalltalk exit: 1.
