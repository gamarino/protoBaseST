"EXPECT: ok 6"
"The drop rule of run: (transactions.st PBDatabase >> run:retries:backoff:; proto_db Database.run:
 retry_left = attempt < retries; on a held conflict continue, no backoff; finally, unless held,
 _drop_kept). A stub database whose attempts follow a script (no storage, no round, no timing):
 each attempt is recorded with its willRetry, each PBObjectSpace >> _dropKept: of the stub space
 with its caller. (1) A held conflict makes no drop before the next attempt; the success after it
 drops once. (2) A plain conflict drops once before the next attempt, the success once more.
 (3) Another error drops once and goes on. (4) The last attempt's conflict drops once and is
 signalled; willRetry is false on the last attempt only. (5) A held conflict on the last attempt
 is signalled and drops once. (6) Every drop names the one caller of the run:, the same in every
 attempt, and two run:s have two callers."
Import from: 'protobase'.
Import from: '_check'.

Object subclass: #DropStub instanceVariableNames: 'trace'.
DropStub class >> trace: anAtom
  ^ self basicNew setTrace: anAtom.
DropStub >> setTrace: anAtom
  trace := anAtom.
DropStub >> _dropKept: aCaller
  trace swap: [:old | old , { { #drop. aCaller } }].

PBDatabase subclass: #ScriptedDb instanceVariableNames: 'script trace'.
ScriptedDb class >> script: anArray trace: anAtom
  ^ (self basicNew _setSpace: (DropStub trace: anAtom) name: 'db') setScript: (Atom on: anArray) trace: anAtom.
ScriptedDb >> setScript: anAtom trace: aTrace
  script := anAtom.
  trace := aTrace.
"One attempt: the next outcome of the script (#held, #conflict, #error, #ok), recorded with its
 caller and willRetry."
ScriptedDb >> _transactionDo: aBlock caller: aCaller willRetry: aBoolean
  | next |
  next := script value first.
  script swap: [:old | old allButFirst].
  trace swap: [:old | old , { { #attempt. aCaller. aBoolean } }].
  next = #held ifTrue: [^ (PBConflictError held: 'scripted held conflict') signal].
  next = #conflict ifTrue: [^ PBConflictError signal: 'scripted conflict'].
  next = #error ifTrue: [^ PBValidationError signal: 'scripted error'].
  ^ #done.

| c run shape t1 t2 |
c := Check new.
"{ the outcome (#done or the error's class name). the trace as #attempt willRetry / #drop }"
run := [:aScript :retries | | trace db result |
  trace := Atom on: #().
  db := ScriptedDb script: aScript trace: trace.
  result := [db run: [:t | nil] retries: retries backoff: #(0 0)] on: Error do: [:e | e return: e class name].
  { result. trace value }].
shape := [:r | { r first. (r last collect: [:x | x first = #drop ifTrue: [#drop] ifFalse: [x last]]) }].

c that: 'a held conflict drops nothing before the next attempt; the success after it drops once'
  is: (shape value: (run value: #(#held #ok) value: 3))
  equals: { #done. { true. true. #drop } }.
c that: 'a plain conflict drops once before the next attempt, the success once more'
  is: (shape value: (run value: #(#conflict #ok) value: 3))
  equals: { #done. { true. #drop. true. #drop } }.
c that: 'another error drops once and goes on'
  is: (shape value: (run value: #(#error) value: 3))
  equals: { #PBValidationError. { true. #drop } }.
c that: 'the last attempt''s conflict drops once and is signalled; willRetry false on the last attempt only'
  is: (shape value: (run value: #(#conflict #conflict) value: 1))
  equals: { #PBConflictError. { true. #drop. false. #drop } }.
c that: 'a held conflict on the last attempt is signalled and drops once'
  is: (shape value: (run value: #(#held #held) value: 1))
  equals: { #PBConflictError. { true. false. #drop } }.
t1 := (run value: #(#held #conflict #ok) value: 3) last.
t2 := (run value: #(#ok) value: 3) last.
c that: 'every attempt and drop of a run: name its one caller; two run:s have two callers'
  is: { (t1 collect: [:x | x at: 2]) asSet size. (t1 first at: 2) == (t2 first at: 2). t1 size }
  equals: { 1. false. 5 }.
c report.
