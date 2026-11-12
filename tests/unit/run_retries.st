"EXPECT: ok 12"
"Database run:retries: (plan Task 19; ProtoBase Database.run): a PBConflictError, raised by the commit,
 aborts the attempt and retries with a fresh transaction. The conflicts are driven from inside the block
 (a nested competing commit on the attempts listed in a script-held Atom), never by timing. After the last
 retry the conflict is signalled again; the validations of ProtoBase run first."
Import from: 'protobase'.
Import from: '_check'.

| c base space db attempts competeOn work r tx |
c := Check new.
base := FileSystem temp / ('pbst-run-retries-' , Smalltalk pid printString).
base deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: base pathString).
db := space newDatabase: 'db'.
attempts := Atom on: 0.
competeOn := Atom on: #(1 2).

"One attempt: read 'x', maybe let a competitor commit a change of 'x', then write it and commit."
work := [:t | | n |
  n := attempts swap: [:v | v + 1].
  tx := t.
  t getRootObject: 'x'.
  (competeOn value includes: n) ifTrue: [db newTransactionDo: [:o | o setRootObject: 'x' value: 'rival ' , n printString]].
  t setRootObject: 'x' value: 'mine ' , n printString.
  'done ' , n printString].

r := db run: work retries: 10 backoff: #(0 0).
c that: 'attempts 1 and 2 conflict, attempt 3 succeeds' is: attempts value equals: 3.
c that: 'the value of the block is answered' is: r equals: 'done 3'.
c that: 'the successful attempt committed' is: (db newTransaction getRootObject: 'x') equals: 'mine 3'.
c that: 'and its transaction is ended' is: tx isActive equals: false.

"retries: 1 allows two attempts; the second conflict is signalled again."
attempts swap: [:v | 0].
competeOn swap: [:v | #(1 2 3)].
c that: 'retries: 1 ends in PBConflictError' signals: PBConflictError during: [db run: work retries: 1 backoff: #(0 0)].
c that: 'after exactly 2 attempts' is: attempts value equals: 2.
c that: 'the last attempt is aborted' is: tx isActive equals: false.

"retries: 0 is one attempt."
attempts swap: [:v | 0].
c that: 'retries: 0 signals the first conflict' signals: PBConflictError during: [db run: work retries: 0 backoff: #(0 0)].
c that: 'after 1 attempt' is: attempts value equals: 1.

"The default is retries: 10 backoff: #(1 200) and answers the value."
attempts swap: [:v | 0].
competeOn swap: [:v | #()].
c that: 'run: answers the block''s value' is: (db run: work) equals: 'done 1'.

"Validation, as ProtoBase's."
c that: 'a negative retries count is refused' signals: PBValidationError during: [db run: work retries: -1 backoff: #(1 2)].
c that: 'an inverted backoff is refused' signals: PBValidationError during: [db run: work retries: 1 backoff: #(5 2)].
space close.
base deleteAll.
'ok 12' displayNl.
