"EXPECT: ok 52"
"The write side of a transaction and its commit (plan Task 18, design spec 7.1 and 7.3;
 ProtoBase Transaction.set_root_object, remove_root_object, the factories, commit and
 _build_root): a commit publishes version n + 1 with the written roots, the removed ones
 gone and the others kept; previous is the version before; committedAt never goes back
 and is in UTC; origin is carried. A transaction reads its own writes, rootNames shows
 them. The values written are read back by a new transaction, through a new storage too.
 newTransactionDo: commits when the block ends, also by a non-local return (as Python's
 return inside with; a commit failing then is signalled), and answers its value; it aborts
 when the block raises and re-signals the exception, and never retries. A commit on a closed space is
 PBClosedError. A commit that cannot take the
 root lock within lockTimeout is PBTimeoutError (the lock is held by another storage and
 never released while the commit waits, so the outcome holds for any duration), and the
 transaction is aborted."
Import from: 'protobase'.
Import from: '_check'.

"Non-local returns out of newTransactionDo: (Python's return inside a with block)."
Object subclass: #Early.
Early >> writeAndReturn: db
  db newTransactionDo: [:t | t setRootObject: 'nlr' value: 'kept'. ^ 5].
  ^ 0.
"Reads 'x', lets another transaction change it, writes it and returns: the commit on the way
 out conflicts."
Early >> conflictAndReturn: db
  db newTransactionDo: [:t |
    t getRootObject: 'x'.
    db newTransactionDo: [:other | other setRootObject: 'x' value: 'other'].
    t setRootObject: 'x' value: 'mine'.
    ^ 7].
  ^ 0.

| c base space db tx v0 v1 v2 list obj dict other otherSpace holder slow tx2 r counter |
c := Check new.
base := FileSystem temp / ('pbst-tx-commit-basic-' , Smalltalk pid printString).
base deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: base pathString).
db := space newDatabase: 'db'.
v0 := db _currentRoot.

tx := db newTransaction.
tx setRootObject: 'x' value: 1.
tx setRootObject: 'name' value: 'Ada'.
list := (tx newList appendLast: 1) appendLast: 'two'.
tx setRootObject: 'list' value: list.
obj := tx newObject: { 'name' -> 'Ada'. 'born' -> 1815 }.
tx setRootObject: 'person' value: obj.
dict := (tx newDictionary setAt: 'a' value: 1) setAt: 'b' value: 2.
tx setRootObject: 'dict' value: dict.
tx setRootObject: 'tuple' value: (PBTuple withAll: #(1 2)).
c that: 'a transaction reads its own write' is: (tx getRootObject: 'x') equals: 1.
c that: 'and records no read for it' is: tx readSet size equals: 0.
c that: 'rootNames shows the writes' is: tx rootNames asArray equals: #('dict' 'list' 'name' 'person' 'tuple' 'x').
c that: 'the factories: newList' is: tx newList class equals: PBList.
c that: 'newDictionary' is: tx newDictionary class equals: PBDictionary.
c that: 'newHashDictionary' is: tx newHashDictionary class equals: PBHashDictionary.
c that: 'newSet' is: tx newSet class equals: PBSet.
c that: 'newCountedSet' is: tx newCountedSet class equals: PBCountedSet.
c that: 'newObject:' is: { obj class. obj at: 'born' } equals: { PBObject. 1815 }.
c that: 'a new collection is mergeable' is: tx newDictionary isMergeable equals: true.
tx commit.
c that: 'committed' is: tx isActive equals: false.
v1 := db _currentRoot.
c that: 'version 1' is: v1 version equals: 1.
c that: 'previous is version 0' is: v1 previous version equals: 0.
c that: 'the origin is carried' is: v1 origin equals: v0 origin.
c that: 'committedAt does not go back' isTrue: v0 committedAt <= v1 committedAt.
c that: 'in UTC' is: v1 committedAt isNaive equals: false.
c that: 'history, newest first' is: (db history collect: [:e | e version]) asArray equals: #(1 0).
c that: 'the space root epoch' is: space storage readRoot epoch equals: 2.
c that: 'D33: a committed collection is consumed' is: dict isMergeable equals: false.

tx := db newTransaction.
c that: 'a new transaction reads the values' is: { tx getRootObject: 'x'. tx getRootObject: 'name' } equals: #(1 'Ada').
c that: 'the list' is: (tx getRootObject: 'list') elements asArray equals: #(1 'two').
c that: 'the record' is: ((tx getRootObject: 'person') at: 'name') equals: 'Ada'.
c that: 'the dictionary' is: ((tx getRootObject: 'dict') getAt: 'b') equals: 2.
c that: 'the tuple' is: (tx getRootObject: 'tuple') equals: (PBTuple withAll: #(1 2)).
tx removeRootObject: 'name'.
tx setRootObject: 'x' value: 2.
c that: 'a removed root reads nil in the transaction' is: (tx getRootObject: 'name') equals: nil.
c that: 'and leaves rootNames' is: tx rootNames asArray equals: #('dict' 'list' 'person' 'tuple' 'x').
tx removeRootObject: 'never-there'.
tx commit.
v2 := db _currentRoot.
c that: 'version 2' is: v2 version equals: 2.
c that: 'the removed root is gone' is: (db snapshotAt: db history first) rootNames asArray
  equals: #('dict' 'list' 'person' 'tuple' 'x').
c that: 'the written root' is: ((db snapshotAt: db history first) getRootObject: 'x') equals: 2.
c that: 'version 1 still reads as it was' is: ((db snapshotAt: (db history at: 2)) getRootObject: 'x') equals: 1.

"Mutable cells through the handle."
counter := nil.
db newTransactionDo: [:t | counter := t newMutable: 'counter' value: 0].
c that: 'newMutable:value: answers the handle' is: { counter class. counter name } equals: { PBMutableObject. 'counter' }.
db newTransactionDo: [:t | counter set: t value: (counter get: t) + 5].
c that: 'PBMutableObject set:value:' is: (db newTransaction getMutable: 'counter') equals: 5.

"newTransactionDo:."
r := db newTransactionDo: [:t | t setRootObject: 'y' value: 'why'. 42].
c that: 'newTransactionDo: answers the block''s value' is: r equals: 42.
c that: 'and committed' is: (db newTransaction getRootObject: 'y') equals: 'why'.
tx2 := nil.
c that: 'an error in the block is re-signalled' signals: ZeroDivide during: [
  db newTransactionDo: [:t | tx2 := t. t setRootObject: 'y' value: 'lost'. 1 / 0]].
c that: 'the transaction was aborted' is: tx2 isActive equals: false.
c that: 'nothing was committed' is: (db newTransaction getRootObject: 'y') equals: 'why'.
tx2 := nil.
c that: 'a block that ends the transaction itself is not committed again' is: (db newTransactionDo: [:t |
  tx2 := t. t setRootObject: 'z' value: 1. t abort. 'done']) equals: 'done'.
c that: 'so nothing was published' is: (db newTransaction getRootObject: 'z') equals: nil.

c that: 'a non-local return answers the method''s value' is: (Early new writeAndReturn: db) equals: 5.
c that: 'and commits, as Python''s return inside with' is: (db newTransaction getRootObject: 'nlr') equals: 'kept'.
c that: 'a commit that fails on the way out is signalled' signals: PBConflictError during: [Early new conflictAndReturn: db].
c that: 'and the other transaction''s value stays' is: (db newTransaction getRootObject: 'x') equals: 'other'.
db newTransactionDo: [:t | t setRootObject: 'x' value: 2].

"The root lock held by another storage: PBTimeoutError, the transaction aborted."
holder := PBFileStorage path: base pathString.
c that: 'another storage takes the root lock' is: holder tryLockRoot equals: true.
slow := PBObjectSpace storage: (PBFileStorage path: base pathString) lockTimeout: 5.
tx := (slow openDatabase: 'db') newTransaction.
tx setRootObject: 'x' value: 99.
c that: 'the commit times out' signals: PBTimeoutError containing: 'root lock' during: [tx commit].
c that: 'the transaction is aborted' is: tx isActive equals: false.
c that: 'newDatabase: times out too' signals: PBTimeoutError during: [slow newDatabase: 'other'].
holder unlockRoot.
holder close.
c that: 'nothing was published' is: ((db snapshotAt: db history first) getRootObject: 'x') equals: 2.
slow close.

"A new storage reads what was committed; a commit on a closed space is PBClosedError."
tx := db newTransaction.
tx setRootObject: 'late' value: 1.
space close.
c that: 'a commit after the space is closed' signals: PBClosedError during: [tx commit].
c that: 'that transaction is aborted' is: tx isActive equals: false.
otherSpace := PBObjectSpace storage: (PBFileStorage path: base pathString).
other := otherSpace openDatabase: 'db'.
tx := other newTransaction.
c that: 'through a new storage' is: { tx getRootObject: 'x'. ((tx getRootObject: 'dict') getAt: 'a'). tx getMutable: 'counter' }
  equals: #(2 1 5).
c that: 'the history through a new storage' is: (other history collect: [:e | e version]) asArray equals: #(8 7 6 5 4 3 2 1 0).
otherSpace close.
base deleteAll.
c report displayNl.
