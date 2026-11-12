"EXPECT: ok 2"
"The quick start of README.md, verbatim, with its two => lines asserted (plan Task 24).
 tutorial_sync.sh fails when the README's block is not in this file."
Import from: 'protobase'.
Import from: '../unit/_check'.

| c |
c := Check new.
| dir space db hits |
dir := FileSystem temp / 'protobase-hello'.
dir deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'hello'.
db newTransactionDo: [:tr |
    tr setRootObject: 'hits' value: 0.
    tr setRootObject: 'tags' value: (tr newDictionary setAt: 'first' value: true)].
db run: [:tr | tr setRootObject: 'hits' value: (tr getRootObject: 'hits') + 1].
hits := db newTransaction getRootObject: 'hits'.
hits.                                          "=> 1"
c that: 'hits' is: hits equals: 1.
db history size.                               "=> 3"
c that: 'history' is: db history size equals: 3.
space close.
dir deleteAll.
c report displayNl.
