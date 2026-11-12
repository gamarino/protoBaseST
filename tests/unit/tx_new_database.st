"EXPECT: ok 29"
"PBObjectSpace >> newDatabase: (plan Task 18, design spec 5.2; ProtoBase
 ObjectSpace.new_database): through the publisher, it commits version 0 of the database
 with empty objects and mutables, previous nil, a 16-byte random origin and committedAt
 now in UTC. The first database of an empty space writes space.root (epoch 1); each
 later one publishes the next epoch and keeps the others. An existing name is
 PBValidationError and publishes nothing; so is an invalid name. Another storage on the
 same directory sees the database. A closed space is PBClosedError."
Import from: 'protobase'.
Import from: '_check'.

| c base space db root before after other otherSpace db2 epoch |
c := Check new.
base := FileSystem temp / ('pbst-tx-new-database-' , Smalltalk pid printString).
base deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: base pathString).
c that: 'an empty space has no database' is: space listDatabases asArray equals: #().
before := DateTime nowUTC.
db := space newDatabase: 'erp'.
after := DateTime nowUTC.
c that: 'newDatabase: answers the PBDatabase' is: { db class. db name } equals: { PBDatabase. 'erp' }.
c that: 'it is listed' is: space listDatabases asArray equals: #('erp').
c that: 'space.root is written, epoch 1' is: space storage readRoot epoch equals: 1.
root := db _currentRoot.
c that: 'version 0' is: root version equals: 0.
c that: 'no previous version' is: root previous equals: nil.
c that: 'empty objects' is: root objects size equals: 0.
c that: 'empty mutables' is: root mutables size equals: 0.
c that: 'the origin is 16 bytes' is: { root origin class. root origin size } equals: { ByteArray. 16 }.
c that: 'committedAt is a DateTime' is: root committedAt class equals: DateTime.
c that: 'in UTC' is: root committedAt isNaive equals: false.
c that: 'committedAt is now' isTrue: (before <= root committedAt and: [root committedAt <= after]).
c that: 'history: one version' is: (db history collect: [:e | e version]) asArray equals: #(0).
c that: 'a transaction reads it' is: (db newTransaction rootNames) asArray equals: #().
c that: 'the last-known root is the published one' is: space _lastKnownRoot encode equals: space storage readRoot encode.

"A second database: the next epoch, the first database kept as it was."
db2 := space newDatabase: 'audit'.
c that: 'both listed, sorted' is: space listDatabases asArray equals: #('audit' 'erp').
c that: 'epoch 2' is: space storage readRoot epoch equals: 2.
c that: 'the first database is unchanged' is: (space openDatabase: 'erp') _currentRoot origin equals: root origin.
c that: 'each database has its own origin' isTrue: db2 _currentRoot origin ~= root origin.

"Refusals publish nothing."
epoch := space storage readRoot epoch.
c that: 'an existing name' signals: PBValidationError containing: 'already exists' during: [space newDatabase: 'erp'].
c that: 'an empty name' signals: PBValidationError during: [space newDatabase: ''].
c that: 'a name that is not a String' signals: PBValidationError during: [space newDatabase: 42].
c that: 'nothing was published' is: space storage readRoot epoch equals: epoch.

"Another storage on the same directory sees both databases, written by protoBaseST."
otherSpace := PBObjectSpace storage: (PBFileStorage path: base pathString).
c that: 'another storage lists them' is: otherSpace listDatabases asArray equals: #('audit' 'erp').
other := otherSpace openDatabase: 'erp'.
c that: 'with the same origin' is: other _currentRoot origin equals: root origin.
c that: 'and version 0' is: other _currentRoot version equals: 0.
"A database created by the other space's publisher is seen by the first."
otherSpace newDatabase: 'third'.
c that: 'the first space sees the third database' is: space listDatabases asArray equals: #('audit' 'erp' 'third').
c that: 'epoch 3' is: space storage readRoot epoch equals: 3.
otherSpace close.

space close.
c that: 'a closed space' signals: PBClosedError during: [space newDatabase: 'late'].
base deleteAll.
c report displayNl.
