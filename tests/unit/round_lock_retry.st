"EXPECT: ok 3"
"The round runner's lock retry (cluster plan Task 22, CC10, proto_db D52). (1) A peer process
 (_hold_lock.st, the pattern of tests/interop/hold_lock.py) holds space.lock and never releases
 it while this test waits: a commit with lockTimeout: 50, made from an actor, ends in
 PBTimeoutError, with the message lockTimeout always had, and publishes nothing (a hang is a
 failed check after 120 s). The outcome does not depend on timing:
 the lock is released only once the commit has ended, by killing the peer, and the handshake
 that the peer holds the lock is a file it creates (waited for with a generous deadline, never
 a sleep). (2) No actor method of the runner waits (carry-over (j) of cluster plan Task 20):
 the code of src/protobase/round.st, comments and strings left out, sends no wait, waitWithin:
 or sleep:, so a round is never driven synchronously from a caller's thread and the runner never
 blocks its worker. (3) The deadline of a commit queued now is lockTimeout milliseconds later,
 in microseconds of the monotonic clock (review m5): the clock read just before and just after
 PBObjectSpace >> _deadline brackets it exactly; values are compared, no duration is measured."
Import from: 'protobase'.
Import from: '_check'.

Object subclass: #Committer.
"Commits the root x in db; answers 'committed' or { the error's class name. its text }."
Committer >> commitIn: db
  ^ [db newTransactionDo: [:t | t setRootObject: 'x' value: 1]. 'committed']
    on: Error do: [:e | { e class name. e messageText }].

| c base protost lockFile ready pid deadline space db outcome versions source code state i n reaped a d z |
c := Check new.
base := FileSystem temp / ('pbst-round-lock-retry-' , Smalltalk pid printString).
base deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: base pathString) lockTimeout: 50.
db := space newDatabase: 'db'.
versions := db history size.
lockFile := base / 'space.lock'.
ready := base / 'holder.ready'.
protost := OSProcess command: 'printf %s "$PROTOST"'.
pid := OSProcess spawn: protost arguments: { '_hold_lock.st'. lockFile pathString. ready pathString }.
"The peer holds the lock once it has created the ready file (a condition, generous deadline)."
deadline := Time millisecondClockValue + 120000.
[ready exists or: [Time millisecondClockValue > deadline]] whileFalse: [(Future after: 10) wait].
outcome := ready exists
  ifFalse: ['the peer never took the lock']
  ifTrue: [
    "From an actor, with a generous deadline that turns a hang into a failed check."
    [(Committer new asActor commitIn: db) waitWithin: 120000] on: TimeoutError do: [:e | 'no outcome within 120 s']].
OSProcess kill: pid.
reaped := OSProcess waitFor: pid.
c that: 'a lock held by a peer process: the commit ends in PBTimeoutError, nothing published'
  is: { outcome. db history size - versions. (db newTransaction getRootObject: 'x') }
  equals: { { 'PBTimeoutError'. 'Could not acquire the root lock within 50 ms (held by another process or storage)' }. 0. nil }.
space close.

"(2) The source scan of round.st: the code, without comments and strings."
source := '../../src/protobase/round.st' asFileReference.
code := WriteStream on: String new.
source exists ifTrue: [
  | text |
  text := source contents.
  state := #code. i := 1. n := text size.
  [i <= n] whileTrue: [
    | ch |
    ch := text at: i.
    state = #code
      ifTrue: [
        ch = $" ifTrue: [state := #comment] ifFalse: [
          ch = $' ifTrue: [state := #string] ifFalse: [
            ch = $$ ifTrue: [i := i + 1. code nextPut: $ ] ifFalse: [code nextPut: ch]]]]
      ifFalse: [
        state = #comment
          ifTrue: [ch = $" ifTrue: [state := #code. code nextPut: $ ]]
          ifFalse: [ch = $' ifTrue: [
            (i < n and: [(text at: i + 1) = $']) ifTrue: [i := i + 1] ifFalse: [state := #code. code nextPut: $ ]]]].
    i := i + 1]].
code := code contents.
c that: 'round.st exists and no code of it waits (wait, waitWithin:, sleep:)'
  is: { source exists. code size > 0. (code includesSubstring: 'wait'). (code includesSubstring: 'sleep:') }
  equals: { true. true. false. false }.

"(3) The deadline's scale: before + 50 000 us <= deadline <= after + 50 000 us."
space := PBObjectSpace storage: (PBFileStorage path: (base / 'deadline') pathString) lockTimeout: 50.
a := Time microsecondClockValue.
d := space _deadline.
z := Time microsecondClockValue.
c that: 'a commit queued now has its deadline lockTimeout ms later, in monotonic microseconds'
  is: { d - a >= 50000. d - z <= 50000 }
  equals: { true. true }.
space close.

base deleteAll.
c report displayNl.
