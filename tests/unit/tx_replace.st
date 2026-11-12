"EXPECT: ok 5"
"setRootObject:value:replace: true substitutes (plan Task 18, design spec 6.4 and 7.1;
 ProtoBase set_root_object(replace=True)): A and B each write 'tags' as a newDictionary
 with a different key, unread; B commits with replace: true after A, so only B's key
 remains (last writer wins, no merge). A removal followed by a set of the same name in one
 transaction is a replacement too, and the mark stays for the rest of the transaction.
 replace: false is the default merge."
Import from: 'protobase'.
Import from: '_check'.

| c base space db a b t |
c := Check new.
base := FileSystem temp / ('pbst-tx-replace-' , Smalltalk pid printString).
base deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: base pathString).
db := space newDatabase: 'db'.
db newTransactionDo: [:x | x setRootObject: 'tags' value: (x newDictionary setAt: 'old' value: 0)].

a := db newTransaction.
b := db newTransaction.
a setRootObject: 'tags' value: (a newDictionary setAt: 'a' value: 1).
b setRootObject: 'tags' value: (b newDictionary setAt: 'b' value: 2) replace: true.
a commit.
c that: 'A merged onto the existing value' is: (db newTransaction getRootObject: 'tags') keys asArray equals: #('a' 'old').
b commit.
c that: 'B replaced: only its key remains' is: (db newTransaction getRootObject: 'tags') keys asArray equals: #('b').

"replace: false merges."
db newTransactionDo: [:x | x setRootObject: 'tags' value: (x newDictionary setAt: 'c' value: 3) replace: false].
c that: 'replace: false merges' is: (db newTransaction getRootObject: 'tags') keys asArray equals: #('b' 'c').

"A removal, then a set of the same name: a replacement, and it stays one."
t := db newTransaction.
t removeRootObject: 'tags'.
t setRootObject: 'tags' value: (t newDictionary setAt: 'd' value: 4).
t setRootObject: 'tags' value: (t newDictionary setAt: 'e' value: 5).
t commit.
c that: 'remove then set replaces' is: (db newTransaction getRootObject: 'tags') keys asArray equals: #('e').

"Once marked, a later set without replace: still replaces."
t := db newTransaction.
t setRootObject: 'tags' value: (t newDictionary setAt: 'f' value: 6) replace: true.
t setRootObject: 'tags' value: (t newDictionary setAt: 'g' value: 7).
t commit.
c that: 'the mark stays for the transaction' is: (db newTransaction getRootObject: 'tags') keys asArray equals: #('g').

space close.
base deleteAll.
c report displayNl.
