"EXPECT: ok 5"
"Every entry the round runner takes is settled, and never reported as a success it is not
 (cluster plan Task 22, fix round 1, review m1 and m2; proto_db _standalone_round's
 except BaseException). A test space (SeamSpace) gives its runner a scripted publisher
 (PBObjectSpace >> _newRunner, PBRoundRunner space:publisher:) whose publishGroup: answers the
 next results of a script, one per entry, and publishes nothing. Each commit is made alone, from
 an actor, and waited for with a generous deadline (120 s) that turns a hang into a failed
 check. (1) Results that are not decisions (nil, 42) end both commits in PBOutcomeUnknownError,
 never in a success, and add no version. (2) In a batch of two, a result whose settlement fails
 (it cannot be printed) ends its commit in PBOutcomeUnknownError naming the cause, and the other
 commit is still settled normally. (3) A failure of the round after the batch was taken (the retry of a #locked entry
 cannot be scheduled) ends that commit in PBUnexpectedError naming the cause, not
 PBOutcomeUnknownError (the lock was held: nothing was published), and takes it out of the
 queue: the next round holds only the next commit. (4) When the rejection of a failed
 settlement fails too (building the error naming the cause signals), the entry still ends, in
 the fixed fallback PBOutcomeUnknownError (review n1). (5) When the runner cannot post the round
 to its own proxy, the commit is rejected with that error and is never queued, and the runner
 is not left believing a round is coming: the next commit is decided alone (review n2)."
Import from: 'protobase'.
Import from: '_check'.

"A result that cannot be printed: its settlement as an undecided result fails."
Object subclass: #Unprintable.
Unprintable >> printOn: aStream
  ^ Error signal: 'injected failure: this result cannot be printed'.
Unprintable >> printString
  ^ Error signal: 'injected failure: this result cannot be printed'.

"failFailure: true makes SeamRunner's building of a settlement error fail; failPost: true makes
 its next post of a round to its own proxy fail (once).
 answers: anArray, the results of the next entries, in order (nil: the real publisher);
 group: n answers #locked for every entry of a batch smaller than n, consuming no answer, so
 the next n commits are decided in one batch; failRetry: true makes SeamRunner's retry
 scheduling fail; sizes, the size of each batch answered from the script."
PBPublisher subclass: #ScriptedPublisher instanceVariableNames: 'answers next failRetry sizes group failFailure failPost'.
ScriptedPublisher >> failFailure: aBoolean
  failFailure := aBoolean.
ScriptedPublisher >> failFailure
  ^ failFailure == true.
ScriptedPublisher >> failPost: aBoolean
  failPost := aBoolean.
"Whether the next post fails; answers true once per failPost: true."
ScriptedPublisher >> takeFailPost
  failPost == true ifFalse: [^ false].
  failPost := false.
  ^ true.
ScriptedPublisher >> group: n
  group := n.
ScriptedPublisher >> answers: anArray
  answers := anArray.
  next := 0.
ScriptedPublisher >> failRetry: aBoolean
  failRetry := aBoolean.
ScriptedPublisher >> failRetry
  ^ failRetry == true.
ScriptedPublisher >> sizes
  ^ sizes ifNil: [sizes := OrderedCollection new].
ScriptedPublisher >> publishGroup: entries
  answers isNil ifTrue: [^ super publishGroup: entries].
  (group notNil and: [entries size < group]) ifTrue: [^ entries collect: [:each | #locked]].
  group := nil.
  self sizes addLast: entries size.
  ^ entries collect: [:each | next := next + 1. answers at: next].

PBRoundRunner subclass: #SeamRunner.
SeamRunner >> _retryAfterLockFor: aCollection now: microseconds
  publisher failRetry ifTrue: [^ Error signal: 'injected failure of the retry scheduling'].
  ^ super _retryAfterLockFor: aCollection now: microseconds.
SeamRunner >> _failure: anError of: aResult while: aString
  publisher failFailure ifTrue: [^ Error signal: 'injected failure while building the settlement error'].
  ^ super _failure: anError of: aResult while: aString.
SeamRunner >> _postRound
  publisher takeFailPost ifTrue: [^ Error signal: 'injected failure of the post'].
  ^ super _postRound.

PBObjectSpace subclass: #SeamSpace instanceVariableNames: 'scripted'.
SeamSpace >> _newRunner
  scripted := ScriptedPublisher space: self.
  ^ SeamRunner space: self publisher: scripted.
SeamSpace >> scripted
  ^ scripted.

Object subclass: #Committer.
"Commits the root aKey in db; answers 'ok' or { the error's class name. its text }."
Committer >> commit: aKey in: db
  ^ [db newTransactionDo: [:t | t setRootObject: aKey value: 1]. 'ok'] on: Error do: [:e | { e class name. e messageText }].
"The outcome of committing aKey in db from a new actor: 'ok' or { class name. text }; a hang
 is { 'no outcome within 120 s'. '' }."
Committer class >> commit: aKey in: db
  ^ self settle: (self new asActor commit: aKey in: db).
"The outcome of aFuture, as commit:in: answers it."
Committer class >> settle: aFuture
  ^ [aFuture waitWithin: 120000] on: TimeoutError do: [:e | { 'no outcome within 120 s'. '' }].

| c base space db versions a b kind text |
c := Check new.
base := FileSystem temp / ('pbst-round-settlement-' , Smalltalk pid printString).
base deleteAll.
space := SeamSpace storage: (PBFileStorage path: base pathString) lockTimeout: 600000.
db := space newDatabase: 'db'.
versions := db history size.
"The class name (or 'ok') and the text ('' for 'ok') of an outcome."
kind := [:r | r isArray ifTrue: [r first] ifFalse: [r]].
text := [:r | r isArray ifTrue: [r at: 2] ifFalse: ['']].

"(1) Undecided results are never a success."
space scripted answers: { nil. 42 }.
a := Committer commit: 'a' in: db.
b := Committer commit: 'b' in: db.
c that: 'results that are not decisions end in PBOutcomeUnknownError, never a success'
  is: { kind value: a. kind value: b. (text value: a) includesSubstring: 'undecided'. (text value: b) includesSubstring: 'undecided'.
    db history size - versions }
  equals: { 'PBOutcomeUnknownError'. 'PBOutcomeUnknownError'. true. true. 0 }.

"(2) A settlement that fails ends its own commit, naming the cause; the other entry of the same
 batch is still settled. The two commits are made from two actors at once and decided in one
 batch (group: 2); which of them gets the unprintable result is not fixed, so the outcomes are
 compared as a set."
space scripted answers: { Unprintable new. true }; group: 2.
a := { 'c'. 'd' } collect: [:k | Committer new asActor commit: k in: db].
a := a collect: [:f | Committer settle: f].
b := a detect: [:r | r ~= 'ok'] ifNone: [{ 'none failed'. '' }].
c that: 'a failed settlement ends that commit in PBOutcomeUnknownError naming the cause; the other entry of its batch is settled'
  is: { (a select: [:r | r = 'ok']) size. kind value: b. (text value: b) includesSubstring: 'injected failure: this result cannot be printed'.
    space scripted sizes last }
  equals: { 1. 'PBOutcomeUnknownError'. true. 2 }.

"(3) A failure of the round after the batch was taken settles what it took."
space scripted answers: { #locked. true }; failRetry: true.
a := Committer commit: 'e' in: db.
space scripted failRetry: false.
b := Committer commit: 'f' in: db.
c that: 'a failure of the round settles every entry it took (PBUnexpectedError naming the cause) and leaves the queue'
  is: { kind value: a. (text value: a) includesSubstring: 'injected failure of the retry scheduling'. b.
    space scripted sizes asArray copyFrom: space scripted sizes size - 1 to: space scripted sizes size }
  equals: { 'PBUnexpectedError'. true. 'ok'. #(1 1) }.

"(4) The rejection of a failed settlement fails too: the fallback still ends the commit."
space scripted answers: { Unprintable new }; failFailure: true.
a := Committer commit: 'g' in: db.
space scripted failFailure: false.
c that: 'a settlement whose rejection fails ends in the fallback PBOutcomeUnknownError'
  is: { kind value: a. text value: a }
  equals: { 'PBOutcomeUnknownError'. 'The commit round failed unexpectedly; the outcome of the commit is unknown' }.

"(5) The post of a round fails: that commit is rejected and never queued; the next is decided
 alone."
space scripted answers: { true }; failPost: true.
a := Committer commit: 'h' in: db.
b := Committer commit: 'i' in: db.
c that: 'a failed post rejects its commit, which is never queued; the runner still schedules the next'
  is: { kind value: a. (text value: a) includesSubstring: 'injected failure of the post'. b. space scripted sizes last }
  equals: { 'Error'. true. 'ok'. 1 }.

space close.
base deleteAll.
c report displayNl.
"An entry left unsettled leaves its committing actor blocked for ever, which would keep this
 process alive after the report: exit explicitly, so such a defect fails the check above and
 ends the run."
Smalltalk exit: 0.
