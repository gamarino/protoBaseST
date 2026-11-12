"EXPECT: ok 15"
"A root read by a transaction and changed by a concurrent commit makes its commit signal
 PBConflictError (plan Task 18, design spec 7.1 and 7.3 step 3; ProtoBase _build_root and
 _token), step by step in one process: A and B read 'x', B writes and commits, A writes and
 commits. B's value stays, and A is aborted. Tokens are exact: B replacing the integer 1
 by the float 1.0 (equal keys, different tokens) still conflicts. A read of an absent root
 conflicts with its concurrent creation. Roots that were not read do not conflict: two
 transactions writing different roots both commit. A removed database is a conflict."
Import from: 'protobase'.
Import from: '_check'.

| c base space db a b history |
c := Check new.
base := FileSystem temp / ('pbst-tx-conflict-read-' , Smalltalk pid printString).
base deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: base pathString).
db := space newDatabase: 'db'.
db newTransactionDo: [:t | t setRootObject: 'x' value: 1].

"Both read and write one root."
a := db newTransaction.
b := db newTransaction.
c that: 'A reads x' is: (a getRootObject: 'x') equals: 1.
c that: 'B reads x' is: (b getRootObject: 'x') equals: 1.
b setRootObject: 'x' value: 2.
b commit.
a setRootObject: 'x' value: 3.
history := db history size.
c that: 'A conflicts' signals: PBConflictError containing: 'x' during: [a commit].
c that: 'A is aborted' is: a isActive equals: false.
c that: 'B''s value stays' is: (db newTransaction getRootObject: 'x') equals: 2.
c that: 'nothing was published by A' is: db history size equals: history.

"1 and 1.0: equal keys, different exact tokens."
db newTransactionDo: [:t | t setRootObject: 'x' value: 1].
a := db newTransaction.
b := db newTransaction.
a getRootObject: 'x'.
b setRootObject: 'x' value: 1.0.
b commit.
a setRootObject: 'x' value: 7.
c that: '1 replaced by 1.0 is a change' signals: PBConflictError during: [a commit].
c that: 'B''s float stays' is: (db newTransaction getRootObject: 'x') class equals: Float.

"The same value written again by B is still a new version of an atom: an atom's token is
 its pointer."
db newTransactionDo: [:t | t setRootObject: 'list' value: (t newList appendLast: 1)].
a := db newTransaction.
b := db newTransaction.
a getRootObject: 'list'.
b setRootObject: 'list' value: ((b getRootObject: 'list') appendLast: 2).
b commit.
a setRootObject: 'list' value: 0.
c that: 'an atom changed under a read' signals: PBConflictError during: [a commit].

"A read of an absent root while the other creates it."
a := db newTransaction.
b := db newTransaction.
c that: 'absent for A' is: (a getRootObject: 'fresh') equals: nil.
b setRootObject: 'fresh' value: 'B'.
b commit.
a setRootObject: 'fresh' value: 'A'.
c that: 'absence is a token' signals: PBConflictError during: [a commit].
c that: 'B created it' is: (db newTransaction getRootObject: 'fresh') equals: 'B'.

"A root read but unchanged by the concurrent commit: no conflict."
a := db newTransaction.
b := db newTransaction.
a getRootObject: 'x'.
b setRootObject: 'other' value: 'B'.
b commit.
a setRootObject: 'x' value: 8.
a commit.
c that: 'A committed on top of B' is: { db newTransaction getRootObject: 'x'. db newTransaction getRootObject: 'other' }
  equals: #(8 'B').

"Each writes a different root, unread: both commit."
a := db newTransaction.
b := db newTransaction.
a setRootObject: 'ra' value: 'A'.
b setRootObject: 'rb' value: 'B'.
b commit.
a commit.
c that: 'both roots present' is: { db newTransaction getRootObject: 'ra'. db newTransaction getRootObject: 'rb' }
  equals: #('A' 'B').
c that: 'and A was built on B''s version' is: db _currentRoot previous version equals: db _currentRoot version - 1.

space close.
base deleteAll.
c report displayNl.
