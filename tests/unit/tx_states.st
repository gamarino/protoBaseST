"EXPECT: ok 15"
"The states of a transaction, read side (plan Task 13; ProtoBase Transaction._check_active):
 a new transaction is active; abort ends it, and then getRootObject:, rootNames,
 getMutable:, mutableNames, PBMutableObject get: and abort itself each signal PBUserError
 naming the state. isActive, database and the two read sets answer in any state. A name
 is checked before the state, as in ProtoBase. newTransaction on a closed space is
 PBClosedError."
Import from: 'protobase'.
Import from: '_check'.

| c base space db tx |
c := Check new.
base := FileSystem temp / ('pbst-tx-states-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
'../conformance/vectors/database' asFileReference files do: [:f | f copyTo: base / f basename].
space := PBObjectSpace storage: (PBFileStorage path: base).
db := space openDatabase: 'db'.
tx := db newTransaction.
c that: 'a new transaction is active' is: tx isActive equals: true.
c that: 'its database' is: tx database equals: db.
tx getRootObject: 'people'.
tx abort.
c that: 'aborted' is: tx isActive equals: false.
c that: 'getRootObject: after abort' signals: PBUserError containing: 'aborted' during: [tx getRootObject: 'people'].
c that: 'rootNames after abort' signals: PBUserError containing: 'aborted' during: [tx rootNames].
c that: 'getMutable: after abort' signals: PBUserError containing: 'aborted' during: [tx getMutable: 'counter'].
c that: 'mutableNames after abort' signals: PBUserError containing: 'aborted' during: [tx mutableNames].
c that: 'PBMutableObject get: after abort' signals: PBUserError during: [(PBMutableObject name: 'counter') get: tx].
c that: 'abort twice' signals: PBUserError containing: 'aborted' during: [tx abort].
c that: 'an invalid name is checked first' signals: PBValidationError during: [tx getRootObject: ''].
c that: 'the read set survives the end' is: tx readSet keys asArray equals: #('people').
c that: 'the mutable read set too' is: tx mutableReadSet size equals: 0.
c that: 'the database too' is: tx database name equals: 'db'.
c that: 'a state is one of four' signals: PBValidationError during: [PBTxState initial withState: #done].
space close.
c that: 'newTransaction on a closed space' signals: PBClosedError during: [db newTransaction].
base deleteAll.
c report displayNl.
