"EXPECT: ok 128 0"
"Week-0 check of the cluster plan (Task 1): protoST's open question K23 (docs/deviations.md),
 whether a wait can raise a false deadlock: when the Futures waited on are settled by network
 events, as the cluster's replies will be. A hub actor answers, for request i, a pending Future
 it keeps in a Dictionary (its own state, held in an Atom it shares with the reader). A reader
 actor, blocked on a socket, resolves Future i when it reads the 4-byte id i. 64 caller actors
 wait nested (inside an ensure: block, which blocks the worker) and 64 wait at the top level of
 their method (which suspends the actor). The program's thread writes the 128 ids once an Atom
 counter shows the 128 registrations, then prints the number of callers that answered the right
 value and the number of deadlock: errors caught. Nothing depends on time; the polling waits for
 a count, and a hang shows as the runner's timeout."
Import from: 'net'.

Object subclass: #K23Hub instanceVariableNames: 'pending registered'.
Object subclass: #K23Reader instanceVariableNames: ''.
Object subclass: #K23Caller instanceVariableNames: ''.

K23Hub >> pending: anAtom registered: aCounter
  pending := anAtom.
  registered := aCounter.

"A new pending Future for request i, kept in the Dictionary until the reader settles it."
K23Hub >> request: i
  | f |
  f := Future new.
  pending swap: [:d | | copy | copy := d copy. copy at: i put: f. copy].
  registered swap: [:n | n + 1].
  ^ f

"Read exactly n bytes, whatever nextBytes: answers mid-stream; nil at the end of the stream."
K23Reader >> readExactly: n from: aSocket
  | got more |
  got := ByteArray new.
  [got size < n] whileTrue: [
      more := aSocket nextBytes: n - got size.
      (more isNil or: [more isEmpty]) ifTrue: [^ nil].
      got := got , more].
  ^ got

"Read count 4-byte big-endian ids; resolve the pending Future of each with id * 10."
K23Reader >> serve: count from: aSocket pending: anAtom
  | bytes id |
  1 to: count do: [:k |
      bytes := self readExactly: 4 from: aSocket.
      bytes isNil ifTrue: [^ Error signal: 'the stream ended after ' , (k - 1) printString , ' ids'].
      id := bytes unsignedLongAt: 1 bigEndian: true.
      (anAtom value at: id) resolve: id * 10].
  ^ count

"The wait nested in a block a primitive evaluates: it blocks the worker."
K23Caller >> nested: i on: hub
  | answer |
  [answer := (hub request: i) wait wait] ensure: [].
  ^ answer

"The waits at the top level of the method: they suspend the actor."
K23Caller >> top: i on: hub
  ^ (hub request: i) wait wait

| n server writer conn pending registered hub reader readerFuture callers answered deadlocks |
n := 128.
server := ServerSocket listenOn: 0 host: '127.0.0.1'.
writer := Socket connectTo: '127.0.0.1' port: server port.
conn := server accept.
pending := Atom on: Dictionary new.
registered := Atom on: 0.
hub := K23Hub new asActor.
(hub pending: pending registered: registered) wait.
reader := K23Reader new asActor.
readerFuture := reader serve: n from: conn pending: pending.
callers := (1 to: n) collect: [:i |
    i <= (n // 2)
        ifTrue: [K23Caller new asActor nested: i on: hub]
        ifFalse: [K23Caller new asActor top: i on: hub]].
[registered value < n] whileTrue: [(Future after: 1) wait].
1 to: n do: [:i | | out |
    out := WriteStream on: ByteArray new.
    out nextPutUnsigned: i width: 4 bigEndian: true.
    writer nextPutBytes: out contents].
answered := 0.
deadlocks := 0.
callers doWithIndex: [:f :i |
    [f wait = (i * 10)
        ifTrue: [answered := answered + 1]
        ifFalse: [Error signal: 'caller ' , i printString , ' answered a wrong value']]
      on: Error
      do: [:e | (e messageText notNil and: [e messageText beginsWith: 'deadlock:'])
            ifTrue: [('NOTE: caller ' , i printString , ': ' , e messageText) displayNl.
                     deadlocks := deadlocks + 1]
            ifFalse: [e pass]]].
readerFuture wait = n ifFalse: [Error signal: 'the reader did not read every id'].
writer close.
conn close.
server close.
('ok ' , answered printString , ' ' , deadlocks printString) displayNl
