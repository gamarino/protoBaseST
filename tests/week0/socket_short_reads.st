"EXPECT: ok"
"Week-0 check of the cluster plan (Task 1): what protoST's IOStream >> nextBytes: answers on a
 socket. Case 1, mid-stream: a reader actor is in nextBytes: 10 while the peer writes 4 bytes,
 lets 200 ms pass, then writes 6 more; the answer is either the 4 bytes already there (a short
 read) or all 10. Case 2, end of stream: the peer writes 4 bytes and closes; the answer is the 4
 bytes, nil or an error. Both outcomes of each case pass: the run records them in NOTE lines,
 for the cluster's _readExactly:from: (plan Task 19), which loops until it has n bytes whatever
 the answer. The 200 ms pause only gives a short read the chance to happen; nothing asserts on
 time."
Import from: 'net'.

Object subclass: #ShortReadProbe instanceVariableNames: ''.

"Resolve started, then read n bytes from aSocket; answer the bytes, nil or the error's class name."
ShortReadProbe >> read: n from: aSocket started: started
  started resolve: true.
  ^ [aSocket nextBytes: n] on: Error do: [:e | e class name]

| describe server pair reader started answer |
describe := [:x |
    x isNil
        ifTrue: ['nil']
        ifFalse: [(x isKindOf: ByteArray)
            ifTrue: [x size printString , ' bytes']
            ifFalse: ['the error ' , x asString]]].
pair := [ | client conn |
    client := Socket connectTo: '127.0.0.1' port: server port.
    conn := server accept.
    {client. conn}].
server := ServerSocket listenOn: 0 host: '127.0.0.1'.
reader := ShortReadProbe new asActor.

"Case 1: mid-stream."
[ | sockets |
  sockets := pair value.
  started := Future new.
  answer := reader read: 10 from: (sockets at: 2) started: started.
  started wait.
  (sockets at: 1) nextPutBytes: #[1 2 3 4].
  (Future after: 200) wait.
  (sockets at: 1) nextPutBytes: #[5 6 7 8 9 10].
  answer := answer wait.
  ((answer isKindOf: ByteArray) and: [answer size = 4 or: [answer size = 10]])
      ifFalse: [Error signal: 'mid-stream: unexpected answer ' , answer printString].
  answer = (#[1 2 3 4 5 6 7 8 9 10] copyFrom: 1 to: answer size)
      ifFalse: [Error signal: 'mid-stream: wrong bytes ' , answer printString].
  ('NOTE: nextBytes: answered ' , answer size printString , ' bytes mid-stream') displayNl.
  sockets do: [:s | s close]] value.

"Case 2: end of stream."
[ | sockets again |
  sockets := pair value.
  started := Future new.
  answer := reader read: 10 from: (sockets at: 2) started: started.
  started wait.
  (sockets at: 1) nextPutBytes: #[1 2 3 4].
  (sockets at: 1) close.
  answer := answer wait.
  again := (reader read: 10 from: (sockets at: 2) started: Future new) wait.
  ('NOTE: nextBytes: 10 at end of stream after 4 bytes answered ' , (describe value: answer) ,
      ', and the next nextBytes: 10 answered ' , (describe value: again)) displayNl.
  (sockets at: 2) close] value.

server close.
'ok' displayNl
