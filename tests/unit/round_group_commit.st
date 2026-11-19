"EXPECT: ok 5"
"Group commit on a standalone storage (cluster plan Task 22, proto_db D52 and
 _standalone_round). The commits queued on the space's round runner are decided together: one
 root lock, one root read, each built on the root the previous build produced, one flush and
 one publish. A test-only storage (GateStorage) makes the grouping deterministic, with no
 timing: its tryLockRoot answers false (the lock is held, as by another process) until step 0
 has saved the written atoms of every commit of the group, so every commit is queued before the
 round that takes the lock; it counts the replaceRoot: calls. Checks: (1) 20 transactions
 committed from 20 actors all succeed; (2) the history holds 20 more versions; (3) one
 replaceRoot: and one epoch for the 20 commits (fewer than commits); (4) a conflicting member of
 a group fails alone with PBConflictError, the others commit; (5) a failure of the round reaches
 every entry it concerns: a publish that fails gives every built entry the outcome of step 8
 (the original error when the failure is before the rename, nothing published; success when it
 is after it), a failed flush gives every built entry its error, while a member whose build
 failed keeps its own PBConflictError; a failed lock gives every entry its error. Every wait has
 a generous deadline (120 s) that turns a hang into a failed check."
Import from: 'protobase'.
Import from: '_check'.

"gate: n, the number of distinct atoms step 0 must have saved before the lock can be taken (nil:
 open); armed: #before or #after fails the next rename seam of replaceRoot:, before or after the
 rename; #flush the next flushSegment; #lock the next tryLockRoot past the gate. Only the space's
 round runner calls these, one round at a time."
PBFileStorage subclass: #GateStorage instanceVariableNames: 'gate seen replaces armed'.
GateStorage >> gate: n
  gate := n.
  seen := OrderedCollection new.
GateStorage >> arm: aSymbol
  armed := aSymbol.
GateStorage >> replaces
  ^ replaces ifNil: [0].
GateStorage >> save: anAtom
  (seen isNil or: [seen anySatisfy: [:each | each == anAtom]]) ifFalse: [seen add: anAtom].
  ^ super save: anAtom.
GateStorage >> tryLockRoot
  (gate notNil and: [seen size < gate]) ifTrue: [^ false].
  gate := nil.
  seen := nil.
  armed == #lock ifTrue: [armed := nil. ^ PBUnexpectedError signal: 'injected failure of the lock'].
  ^ super tryLockRoot.
GateStorage >> flushSegment
  armed == #flush ifTrue: [armed := nil. ^ PBUnexpectedError signal: 'injected failure of the flush'].
  ^ super flushSegment.
GateStorage >> replaceRoot: aRecord
  replaces := self replaces + 1.
  ^ super replaceRoot: aRecord.
GateStorage >> _log: aString
  ^ nil.
GateStorage >> _replaceRootFile
  | mode |
  mode := armed.
  armed := nil.
  mode == #before ifTrue: [^ FileSystemError signal: 'injected failure before the rename'].
  super _replaceRootFile.
  mode == #after ifTrue: [^ FileSystemError signal: 'injected failure after the rename'].

Object subclass: #Committer.
"The outcome of aFuture, or 'no outcome within 120 s'."
Committer class >> settle: aFuture
  ^ [aFuture waitWithin: 120000] on: TimeoutError do: [:e | 'no outcome within 120 s'].
"Commits aTransaction; answers 'ok' or { the error's class name. its text }."
Committer >> commit: aTransaction
  ^ [aTransaction commit. 'ok'] on: Error do: [:e | { e class name. e messageText }].
"Commits a root of its own in db (a new list, one written atom); answers 'ok' or the error."
Committer >> commitRoot: aKey in: db
  ^ [db newTransactionDo: [:t | t setRootObject: aKey value: (t newList appendLast: aKey)]. 'ok']
    on: Error do: [:e | { e class name. e messageText }].

| c base storage space db n versions epoch calls results group failed |
c := Check new.
base := FileSystem temp / ('pbst-round-group-commit-' , Smalltalk pid printString).
base deleteAll.

"(1)-(3) 20 commits from 20 actors, one group."
storage := GateStorage path: (base / 'twenty') pathString.
space := PBObjectSpace storage: storage lockTimeout: 600000.
db := space newDatabase: 'db'.
versions := db history size.
epoch := storage readRoot epoch.
calls := storage replaces.
n := 20.
storage gate: n.
results := ((1 to: n) collect: [:i | Committer new asActor commitRoot: 'r' , i printString in: db])
  collect: [:f | Committer settle: f].
c that: '20 transactions committed from 20 actors all succeed' is: results asArray equals: (Array new: n withAll: 'ok').
c that: 'the history holds 20 more versions, each root present'
  is: { db history size - versions. db newTransaction rootNames size }
  equals: { n. n }.
c that: 'fewer publishes than commits: one replaceRoot: and one epoch for the group'
  is: { storage replaces - calls < n. storage replaces - calls. storage readRoot epoch - epoch }
  equals: { true. 1. 1 }.
space close.

"Three transactions started on one version: a and b read and write the root x, c writes y. In
 one group, the one built second of a and b conflicts, alone."
group := [:aStorage |
  | txs |
  txs := (1 to: 3) collect: [:i | db newTransaction].
  (txs at: 1) getRootObject: 'x'.
  (txs at: 2) getRootObject: 'x'.
  (txs at: 1) setRootObject: 'x' value: ((txs at: 1) newList appendLast: 'a').
  (txs at: 2) setRootObject: 'x' value: ((txs at: 2) newList appendLast: 'b').
  (txs at: 3) setRootObject: 'y' value: ((txs at: 3) newList appendLast: 'c').
  aStorage gate: 3.
  (txs collect: [:t | Committer new asActor commit: t]) collect: [:f | Committer settle: f]].

"(4) A conflicting member fails alone."
storage := GateStorage path: (base / 'conflict') pathString.
space := PBObjectSpace storage: storage lockTimeout: 600000.
db := space newDatabase: 'db'.
versions := db history size.
calls := storage replaces.
results := group value: storage.
c that: 'a conflicting member of a group fails alone with PBConflictError'
  is: { ((results first: 2) collect: [:r | r = 'ok' ifTrue: ['ok'] ifFalse: [r first]]) asSortedCollection asArray.
    results last. db history size - versions. storage replaces - calls }
  equals: { #('PBConflictError' 'ok'). 'ok'. 2. 1 }.
space close.

"(5) A failure of the round, for each mode of GateStorage: { versions added. entries committed.
 entries with PBConflictError. entries with the injected error. distinct texts of the injected
 errors (1: one error, every entry's). each injected error the mode's }. Before the rename, the
 root read back is the one the group was built on: the original error, for the two built
 entries, nothing published. After the rename, the group's root is visible: both built entries
 succeed. A failed flush: its error for the two built entries. The conflicting entry keeps its
 own PBConflictError in all three. A failed lock: its error for every entry, none was built."
failed := [:mode :text |
  | dir s outcome injected |
  dir := base / mode asString.
  storage := GateStorage path: dir pathString.
  space := PBObjectSpace storage: storage lockTimeout: 600000.
  db := space newDatabase: 'db'.
  versions := db history size.
  storage arm: mode.
  results := group value: storage.
  injected := results select: [:r | r isArray and: [(r at: 2) includesSubstring: 'injected failure']].
  outcome := { db history size - versions. results count: [:r | r = 'ok'].
    results count: [:r | r isArray and: [r first = 'PBConflictError']]. injected size.
    (injected collect: [:r | r at: 2]) asSet size.
    injected allSatisfy: [:r | (r at: 2) includesSubstring: text] }.
  space close.
  outcome].
c that: 'a failure of the round reaches every entry it concerns (the publish: step 8''s outcome)'
  is: { failed value: #before value: 'injected failure before the rename'.
    failed value: #after value: 'injected failure after the rename'.
    failed value: #flush value: 'injected failure of the flush'.
    failed value: #lock value: 'injected failure of the lock' }
  equals: { #(0 0 1 2 1 true). #(2 2 1 0 0 true). #(0 0 1 2 1 true). #(0 0 0 3 1 true) }.

base deleteAll.
c report displayNl.
