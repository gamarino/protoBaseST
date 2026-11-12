"EXPECT: ok 21"
"newTransactionDo: and exceptions (plan Task 18, fix round 2, ruling R20; review N1): the
 transaction is committed when the block ends, normally or by a non-local return (Python's
 return inside with), and aborted when an exception ends the block (ProtoBase's __exit__
 aborts on any exception). A resumable exception that an enclosing handler resumes does not
 end the block: the block goes on and its writes are committed. One that an enclosing
 handler ends (return:, falling off its end) unwinds the block: aborted. An Error, or an
 exception that is not resumable, aborts the transaction at once and goes on unchanged."
Import from: 'protobase'.
Import from: '_check'.

"An exception that is not resumable and not an Error (the ANSI way to declare it)."
Exception subclass: #Stop.
Stop >> isResumable
  ^ false.

Object subclass: #Early.
"A non-local return out of the block."
Early >> returnIn: db name: aName
  db newTransactionDo: [:t | t setRootObject: aName value: 'kept'. ^ 5].
  ^ 0.
"A non-local return after a Notification that the caller's handler resumes."
Early >> notifyThenReturnIn: db name: aName
  db newTransactionDo: [:t | t setRootObject: aName value: (Notification signal: 'which value?'). ^ 9].
  ^ 0.

| c base space db read tx r |
c := Check new.
base := FileSystem temp / ('pbst-tx-do-exceptions-' , Smalltalk pid printString).
base deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: base pathString).
db := space newDatabase: 'db'.
read := [:aName | db newTransaction getRootObject: aName].

"A resumed Notification: the block goes on; committed."
r := [db newTransactionDo: [:t | tx := t. t setRootObject: 'n1' value: (Notification signal: 'which value?'). 'end']]
  on: Notification do: [:e | e resume: 'answer'].
c that: 'a resumed Notification: the block''s value' is: r equals: 'end'.
c that: 'and its writes are committed' is: (read value: 'n1') equals: 'answer'.
c that: 'the transaction is committed, not aborted' is: tx isActive equals: false.
"An unhandled Notification resumes with nil: committed too."
db newTransactionDo: [:t | t setRootObject: 'n2' value: ((Notification signal: 'nobody listens') ifNil: ['nil'])].
c that: 'an unhandled Notification: committed' is: (read value: 'n2') equals: 'nil'.
"A resumed Warning."
r := [db newTransactionDo: [:t | t setRootObject: 'w1' value: (Warning signal: 'low ink'). 'end']]
  on: Warning do: [:e | e resume: 'resumed'].
c that: 'a resumed Warning: committed' is: { r. read value: 'w1' } equals: #('end' 'resumed').

"An enclosing handler that ends the exception: the block is unwound; aborted."
r := [db newTransactionDo: [:t | tx := t. t setRootObject: 'w2' value: 1. Warning signal: 'stop here'. 'end']]
  on: Warning do: [:e | e return: 'out'].
c that: 'a Warning ended by return: answers the handler''s value' is: r equals: 'out'.
c that: 'and nothing is committed' is: (read value: 'w2') equals: nil.
c that: 'the transaction was aborted' is: tx isActive equals: false.
r := [db newTransactionDo: [:t | t setRootObject: 'n3' value: 1. Notification signal: 'stop'. 'end']]
  on: Notification do: [:e | 'fell off'].
c that: 'a Notification whose handler falls off its end' is: { r. read value: 'n3' } equals: { 'fell off'. nil }.

"Non-local returns commit."
c that: 'a ^ answers the method''s value' is: (Early new returnIn: db name: 'nlr') equals: 5.
c that: 'and commits' is: (read value: 'nlr') equals: 'kept'.
r := [Early new notifyThenReturnIn: db name: 'nlr2'] on: Notification do: [:e | e resume: 'resumed'].
c that: 'a ^ after a resumed Notification answers the method''s value' is: r equals: 9.
c that: 'and commits (no exception is in flight then)' is: (read value: 'nlr2') equals: 'resumed'.

"An Error aborts and is signalled again."
c that: 'an Error is signalled again' signals: ZeroDivide during: [
  db newTransactionDo: [:t | tx := t. t setRootObject: 'e1' value: 1. 1 / 0]].
c that: 'the transaction was aborted' is: tx isActive equals: false.
c that: 'nothing is committed' is: (read value: 'e1') equals: nil.
r := [db newTransactionDo: [:t | tx := t. t setRootObject: 'e2' value: 1. (1 / 0) + 1]]
  on: ZeroDivide do: [:e | e resume: 1].
c that: 'a resumable Error resumed by the caller: the transaction is aborted all the same' is: tx isActive equals: false.
c that: 'so nothing is committed' is: (read value: 'e2') equals: nil.

"A non-resumable exception that is not an Error aborts."
r := [db newTransactionDo: [:t | tx := t. t setRootObject: 's1' value: 1. Stop new signal: 'stop'. 'end']]
  on: Stop do: [:e | e return: 'stopped'].
c that: 'a non-resumable exception: the handler''s value' is: r equals: 'stopped'.
c that: 'and nothing is committed' is: (read value: 's1') equals: nil.
c that: 'the transaction was aborted' is: tx isActive equals: false.

space close.
base deleteAll.
c report displayNl.
