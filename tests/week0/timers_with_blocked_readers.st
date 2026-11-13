"EXPECT: ok 3"
"Week-0 check of the cluster plan (Task 1): timers keep firing while many pool workers are
 blocked in socket reads. 64 reader actors (more than any initial worker pool) each block in
 nextBytes: 1 on a connected socket whose writer never writes. Then, from the program's thread:
 (1) (Future after: 1) wait answers nil; (2) a thenDo: on Future after: 1 resolves a second Future
 that the program's thread waits for (the callback runs on a pool worker); (3) closing the 64
 writers settles all 64 reader Futures, counted through an Atom. No check depends on time: each
 waits for an event, and a defect shows as the runner's timeout.
 What a pass of (1) and (2) supports: a timer's settle and its thenDo: callback need a free pool
 worker (LANGUAGE.md 10.3), so the pass shows that the pool adds workers past those blocked in
 I/O (LANGUAGE.md 12.11), as it does with PROTOST_WORKERS=1 too.
 Limit: each reader resolves started just before its nextBytes: 1, so the readers are likely but
 not forced to be blocked when the timers run; a pass is an absence of observed failure, not a
 proof."
Import from: 'net'.

Object subclass: #BlockedReader instanceVariableNames: ''.

"Resolve started, then read one byte from aSocket; count the read's end in counter (an Atom)."
BlockedReader >> readOneFrom: aSocket started: started counter: counter
  | answer |
  started resolve: true.
  answer := [aSocket nextBytes: 1] on: Error do: [:e | e class name].
  counter swap: [:n | n + 1].
  ^ answer

| n server writers conns startedAll readerFutures counter passed second |
n := 64.
passed := 0.
server := ServerSocket listenOn: 0 host: '127.0.0.1'.
writers := OrderedCollection new.
conns := OrderedCollection new.
startedAll := OrderedCollection new.
readerFutures := OrderedCollection new.
counter := Atom on: 0.
1 to: n do: [:i | | started |
    writers add: (Socket connectTo: '127.0.0.1' port: server port).
    conns add: server accept.
    started := Future new.
    startedAll add: started.
    readerFutures add: (BlockedReader new asActor readOneFrom: conns last started: started counter: counter)].
(Future whenAll: startedAll asArray) wait.

"(1) A timer settles while the readers block."
(Future after: 1) wait isNil ifFalse: [Error signal: 'Future after: 1 did not answer nil'].
passed := passed + 1.

"(2) A thenDo: callback on a timer's Future runs and resolves another Future."
second := Future new.
(Future after: 1) thenDo: [:v | second resolve: #fired].
second wait = #fired ifFalse: [Error signal: 'the thenDo: chain did not resolve the second Future'].
passed := passed + 1.

"(3) Closing the writers ends every blocked read (none has ended before: nothing was written)."
counter value = 0 ifFalse: [Error signal: 'a read ended before any writer closed'].
writers do: [:w | w close].
(Future whenAll: readerFutures asArray) wait.
counter value = n ifFalse: [Error signal: 'reads ended: ' , counter value printString , ' of ' , n printString].
passed := passed + 1.

conns do: [:c | c close].
server close.
('ok ' , passed printString) displayNl
