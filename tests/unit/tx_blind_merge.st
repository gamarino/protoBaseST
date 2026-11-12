"EXPECT: ok 11"
"Blind writes merge (plan Task 18, design spec 6.4, 7.2 and 7.3 step 4; ProtoBase _merged):
 A and B each set the root 'tags' to a newDictionary with a different key, without reading
 it; both commit, and both keys are present, because the later commit replays its log onto
 the dictionary current at commit time. The same holds for a PBHashDictionary and a PBSet.
 Blind writes of the same key: the later commit's value wins. A blind PBList is not
 mergeable: the last writer wins. D33: a committed dictionary reused in a later blind write
 replaces, it does not replay its log twice. A blind Set add and a concurrent remove of the
 same element: the net intent, in commit order."
Import from: 'protobase'.
Import from: '_check'.

| c base space db a b tags reused |
c := Check new.
base := FileSystem temp / ('pbst-tx-blind-merge-' , Smalltalk pid printString).
base deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: base pathString).
db := space newDatabase: 'db'.

"Dictionaries, onto an absent root first: A creates it, B merges."
a := db newTransaction.
b := db newTransaction.
a setRootObject: 'tags' value: (a newDictionary setAt: 'urgent' value: true).
b setRootObject: 'tags' value: (b newDictionary setAt: 'paid' value: false).
a commit.
b commit.
tags := db newTransaction getRootObject: 'tags'.
c that: 'both keys are present' is: tags keys asArray equals: #('paid' 'urgent').
c that: 'with their values' is: { tags getAt: 'urgent'. tags getAt: 'paid' } equals: #(true false).

"Onto an existing root, a third key; and the same key twice: the later value wins."
a := db newTransaction.
b := db newTransaction.
a setRootObject: 'tags' value: ((a newDictionary setAt: 'late' value: 1) setAt: 'shared' value: 'A').
b setRootObject: 'tags' value: (b newDictionary setAt: 'shared' value: 'B').
b commit.
a commit.
tags := db newTransaction getRootObject: 'tags'.
c that: 'the keys of every commit' is: tags keys asArray equals: #('late' 'paid' 'shared' 'urgent').
c that: 'the same key: the later commit wins' is: (tags getAt: 'shared') equals: 'A'.

"A blind removal is replayed too."
db newTransactionDo: [:t | t setRootObject: 'tags' value: (t newDictionary removeAt: 'late')].
c that: 'a blind removeAt: merged' is: (db newTransaction getRootObject: 'tags') keys asArray
  equals: #('paid' 'shared' 'urgent').

"PBHashDictionary and PBSet."
a := db newTransaction.
b := db newTransaction.
a setRootObject: 'h' value: (a newHashDictionary setAt: 1 value: 'one').
b setRootObject: 'h' value: (b newHashDictionary setAt: 2 value: 'two').
a setRootObject: 's' value: (a newSet add: 'x').
b setRootObject: 's' value: (b newSet add: 'y').
a commit.
b commit.
c that: 'hash dictionaries merge' is: ((db newTransaction getRootObject: 'h') keys asArray asSortedCollection: [:p :q | p <= q]) asArray
  equals: #(1 2).
c that: 'sets merge' is: ((db newTransaction getRootObject: 's') elements asArray asSortedCollection: [:p :q | p <= q]) asArray
  equals: #('x' 'y').

"A Set add and a concurrent remove of the same element: the net intent, in commit order."
a := db newTransaction.
b := db newTransaction.
a setRootObject: 's' value: (a newSet remove: 'x').
b setRootObject: 's' value: (b newSet add: 'x').
b commit.
a commit.
c that: 'the later remove wins' is: ((db newTransaction getRootObject: 's') has: 'x') equals: false.

"A blind PBList: last writer wins."
a := db newTransaction.
b := db newTransaction.
a setRootObject: 'list' value: (a newList appendLast: 'A').
b setRootObject: 'list' value: (b newList appendLast: 'B').
a commit.
b commit.
c that: 'a list is replaced' is: (db newTransaction getRootObject: 'list') elements asArray equals: #('B').

"D33: a committed collection, reused in a later blind write, replaces."
a := db newTransaction.
reused := a newDictionary setAt: 'only' value: 1.
a setRootObject: 'd33' value: reused.
a commit.
db newTransactionDo: [:t | t setRootObject: 'd33' value: (t newDictionary setAt: 'other' value: 2)].
c that: 'the root holds both keys' is: (db newTransaction getRootObject: 'd33') keys asArray equals: #('only' 'other').
db newTransactionDo: [:t | t setRootObject: 'd33' value: (reused setAt: 'again' value: 3)].
c that: 'the reused value replaced: other is gone' is: (db newTransaction getRootObject: 'd33') keys asArray
  equals: #('again' 'only').

space close.
base deleteAll.
c report displayNl.
