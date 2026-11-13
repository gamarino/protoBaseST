"EXPECT: 09 actors ok (8 checks)"
"Lesson 09: several protoST actors on one database, at the same time.
 Tutorial chapter: docs/tutorial/09-actors.md

 What it teaches:
 - one PBDatabase is shared by any number of actors; each actor runs its own transactions,
   on its own worker thread, with no lock in the Smalltalk code. Commits are serialised by
   the space's publisher actor;
 - a transaction that read a contended root (the counter) conflicts and is retried by run:;
   blind writes to a shared dictionary (the log) merge and never retry;
 - every snapshot is consistent: a reader actor that samples the database while the
   writers run always sees counter = size of the log, because both change in one commit;
 - a stored value can be handed to several actors at once: it is immutable, so no copy and
   no lock are needed.

 Run it: STPATH=<repository>/src protost 09_actors.st"
Import from: 'protobase'.
Import from: '_lesson'.

"A writer: n transactions, each increments the counter and logs one entry."
Object subclass: #Writer instanceVariableNames: 'runs'.

"Answers how many times its transaction blocks ran (n plus the retries)."
Writer >> commit: n as: aName on: aDatabase
  runs := 0.
  1 to: n do: [:i |
    aDatabase run: [:tr |
        runs := runs + 1.
        tr setRootObject: 'counter' value: (tr getRootObject: 'counter') + 1.
        tr setRootObject: 'log' value: (tr newDictionary setAt: aName , '-' , i printString value: i)]
      retries: 100].
  ^ runs.

"A reader: samples the database and answers how many snapshots broke the invariant."
Object subclass: #Auditor.

Auditor >> sample: count on: aDatabase
  | broken tr |
  broken := 0.
  count timesRepeat: [
    tr := aDatabase newTransaction.
    (tr getRootObject: 'counter') = (tr getRootObject: 'log') count ifFalse: [broken := broken + 1].
    tr abort.
    (Future after: 10) wait].
  ^ broken.

"Sums the values of a dictionary it is given (a value shared by several actors)."
Auditor >> total: aDictionary
  | sum |
  sum := 0.
  aDictionary do: [:each | sum := sum + each].
  ^ sum.

| lesson dir space db names writers futures audit runs final log totals |
lesson := Lesson named: '09 actors'.
dir := FileSystem temp / ('pbst-tutorial-09-' , Smalltalk pid printString).
dir deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'shared'.
db newTransactionDo: [:t |
    t setRootObject: 'counter' value: 0.
    t setRootObject: 'log' value: t newDictionary].

names := #('ana' 'bruno' 'carla' 'dario').
writers := names collect: [:each | Writer new asActor].
"Each send answers a Future at once: the four writers and the auditor run together."
futures := (1 to: names size) collect: [:i | (writers at: i) commit: 10 as: (names at: i) on: db].
audit := Auditor new asActor sample: 30 on: db.
runs := futures inject: 0 into: [:sum :f | sum + f wait].
lesson check: 'no snapshot was ever inconsistent' is: audit wait equals: 0.

final := db newTransaction.
log := final getRootObject: 'log'.
lesson check: 'every increment counted' is: (final getRootObject: 'counter') equals: 40.
lesson check: 'every log entry kept (merged, never lost)' is: log count equals: 40.
lesson check: 'one version per commit' is: db history size equals: 42.
lesson check: 'each commit ran its block at least once' isTrue: runs >= 40.
lesson say: '40 commits from 4 actors; the blocks ran ' , runs printString , ' times (' , (runs - 40) printString , ' retries)'.

"One stored value, read by three actors at once: nothing to copy, nothing to lock."
totals := ((1 to: 3) collect: [:i | Auditor new asActor total: log]) collect: [:f | f wait].
lesson check: 'three actors read the same value' is: totals asArray equals: #(220 220 220).
lesson check: 'the log has each writer''s ten entries'
    is: (names collect: [:n | (log keys select: [:k | k beginsWith: n , '-']) size]) asArray equals: #(10 10 10 10).
lesson check: 'a new space sees the same' is: [ | other |
    other := PBObjectSpace storage: (PBFileStorage path: dir pathString).
    [(other openDatabase: 'shared') newTransaction getRootObject: 'counter'] ensure: [other close]] value
    equals: 40.
space close.
dir deleteAll.
lesson finish.
