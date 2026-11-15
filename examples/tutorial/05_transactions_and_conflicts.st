"EXPECT: 05 transactions and conflicts ok (15 checks)"
"Lesson 05: snapshots, read sets, conflicts and retries.
 Tutorial chapter: docs/tutorial/05-transactions-and-conflicts.md

 What it teaches:
 - a transaction reads one snapshot: what others commit after it started is invisible to it;
 - every root it reads is recorded (its read set). At commit, if any of them was changed by
   a commit since, the commit fails with PBConflictError and the transaction is aborted.
   This includes roots it only read and did not write: a value computed from stale input is
   refused;
 - abort, or an exception inside newTransactionDo:, discards the writes;
 - run: is the read-modify-write loop: on a conflict it starts a fresh transaction and runs
   the block again, after a short randomised wait. The block may run more than once, so it
   must have no effect outside the transaction.

 Run it: STPATH=<repository>/src protost 05_transactions_and_conflicts.st"
Import from: 'protobase'.
Import from: '_lesson'.

| lesson dir space db early tr outcome attempts v |
lesson := Lesson named: '05 transactions and conflicts'.
dir := FileSystem temp / ('pbst-tutorial-05-' , Smalltalk pid printString).
dir deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'bank'.
db newTransactionDo: [:t |
    t setRootObject: 'balance' value: 100.
    t setRootObject: 'rate' value: 5.
    t setRootObject: 'interest' value: 0].

"Snapshot isolation: early started before the next commit and keeps seeing its snapshot."
early := db newTransaction.
db newTransactionDo: [:t | t setRootObject: 'balance' value: 150].
lesson check: 'an older transaction sees its snapshot' is: (early getRootObject: 'balance') equals: 100.
lesson check: 'a new transaction sees the commit' is: (db newTransaction getRootObject: 'balance') equals: 150.
early abort.

"A write computed from a value that changed meanwhile is refused."
tr := db newTransaction.
v := tr getRootObject: 'balance'.
db newTransactionDo: [:t | t setRootObject: 'balance' value: 175].
tr setRootObject: 'balance' value: v + 10.
outcome := lesson check: 'the stale write conflicts'
    signals: PBConflictError containing: 'balance' during: [tr commit].
lesson say: outcome.
lesson check: 'the failed transaction is over' isTrue: tr isActive not.
lesson check: 'the concurrent commit stands' is: (db newTransaction getRootObject: 'balance') equals: 175.

"Reading is enough to be protected: interest is computed from rate, and rate changes."
tr := db newTransaction.
v := (tr getRootObject: 'balance') * (tr getRootObject: 'rate') // 100.
db newTransactionDo: [:t | t setRootObject: 'rate' value: 7].
tr setRootObject: 'interest' value: v.
lesson check: 'a root that was only read conflicts too'
    signals: PBConflictError containing: 'rate' during: [tr commit].

"abort discards; so does an exception inside newTransactionDo: (the exception goes on)."
tr := db newTransaction.
tr setRootObject: 'balance' value: 0.
tr abort.
lesson check: 'abort discarded the write' is: (db newTransaction getRootObject: 'balance') equals: 175.
lesson check: 'the exception goes on'
    signals: ZeroDivide containing: '' during: [
        db newTransactionDo: [:t | t setRootObject: 'balance' value: 0. 1 / 0]].
lesson check: 'and the write was discarded' is: (db newTransaction getRootObject: 'balance') equals: 175.
lesson check: 'a used transaction refuses more work'
    signals: PBUserError containing: 'aborted' during: [tr getRootObject: 'balance'].

"run: retries. The first attempt is made to conflict on purpose: a rival commits in between."
attempts := 0.
db run: [:t |
    attempts := attempts + 1.
    v := t getRootObject: 'balance'.
    attempts = 1 ifTrue: [db newTransactionDo: [:rival | rival setRootObject: 'balance' value: 200]].
    t setRootObject: 'balance' value: v + 1].
lesson check: 'the block ran twice' is: attempts equals: 2.
lesson check: 'the second run built on the rival' is: (db newTransaction getRootObject: 'balance') equals: 201.

"With retries: 0 the conflict reaches the caller."
attempts := 0.
lesson check: 'no retries: the conflict is signalled'
    signals: PBConflictError containing: 'balance' during: [
        db run: [:t |
            attempts := attempts + 1.
            v := t getRootObject: 'balance'.
            db newTransactionDo: [:rival | rival setRootObject: 'balance' value: 300].
            t setRootObject: 'balance' value: v + 1]
          retries: 0].
lesson check: 'it ran once' is: attempts equals: 1.
lesson check: 'every successful commit is a version, no failed one' is: db history size equals: 8.
space close.
dir deleteAll.
lesson finish.
