"EXPECT: ok 11"
"Root-lock contention with many committing actors (plan Task 18, fix round 1, ruling R19;
 review C1). Another storage on the same directory holds the root lock, a stand-in for a
 ProtoBase process committing to the space; N actors each commit a root of their own. The
 publisher never waits: an attempt that finds the lock held answers at once, and each
 committing transaction owns its backoff. The lock is released from a seam of the space's
 storage after a fixed number of attempts, so nothing depends on timing (lockTimeout is ten
 minutes, never reached). Every commit must land: N roots, N new versions, and no error,
 in particular no 'deadlock:' Error from protoST's wait-cycle detection, which a publisher
 waiting inside a helping worker used to trigger. The written atoms are saved once, before
 the lock: the retries never save them again."
Import from: 'protobase'.
Import from: '_check'.

"The space's storage: on the releaseAfter-th attempt to take the root lock, the holder
 releases it first. Only the space's publisher calls tryLockRoot, one call at a time."
PBFileStorage subclass: #GateStorage instanceVariableNames: 'holder releaseAfter attempts pushes seen'.
GateStorage >> holder: aStorage releaseAfter: n
  holder := aStorage.
  releaseAfter := n.
  attempts := 0.
GateStorage >> attempts
  ^ attempts ifNil: [0].
GateStorage >> pushes
  ^ pushes ifNil: [0].
"The number of records pushed when each attempt to take the lock was made."
GateStorage >> seen
  ^ seen ifNil: [seen := OrderedCollection new].
GateStorage >> resetSeen
  seen := nil.
GateStorage >> pushAtom: anEnvelope
  pushes := self pushes + 1.
  ^ super pushAtom: anEnvelope.
GateStorage >> tryLockRoot
  self seen addLast: self pushes.
  attempts := self attempts + 1.
  attempts = releaseAfter ifTrue: [holder unlockRoot].
  ^ super tryLockRoot.

Object subclass: #Committer.
"Commits the root aKey in db and answers aKey; an error answers its class and text."
Committer >> commit: aKey in: db
  ^ [db newTransactionDo: [:t | t setRootObject: aKey value: (t newList appendLast: aKey)]. aKey]
    on: Error do: [:e | e class name , ': ' , e messageText].

| c base storage holder space db n futures results versions names before |
c := Check new.
n := 40.
base := FileSystem temp / ('pbst-tx-lock-contention-' , Smalltalk pid printString).
base deleteAll.
storage := GateStorage path: base pathString.
space := PBObjectSpace storage: storage lockTimeout: 600000.
db := space newDatabase: 'db'.
versions := db history size.
holder := PBFileStorage path: base pathString.
c that: 'another storage holds the root lock' is: holder tryLockRoot equals: true.
storage holder: holder releaseAfter: 3 * n.
futures := (1 to: n) collect: [:i | Committer new asActor commit: 'r' , i printString in: db].
results := futures collect: [:f | f wait].
c that: 'every commit landed, none failed' is: results asArray equals: ((1 to: n) collect: [:i | 'r' , i printString]) asArray.
c that: 'the lock was contended' isTrue: storage attempts >= (3 * n).
c that: 'one version per commit' is: db history size equals: versions + n.
names := db newTransaction rootNames asArray.
c that: 'every root is present' is: names size equals: n.
c that: 'with its value' isTrue: ((1 to: n) allSatisfy: [:i | | list |
  list := db newTransaction getRootObject: 'r' , i printString.
  list notNil and: [(list getAt: 0) = ('r' , i printString)]]).

"One transaction: its written atoms are saved before the first attempt, and never again."
storage holder: holder releaseAfter: 5.
c that: 'the holder takes the lock again' is: holder tryLockRoot equals: true.
storage resetSeen.
before := storage pushes.
futures := Committer new asActor commit: 'single' in: db.
c that: 'the single commit landed' is: futures wait equals: 'single'.
c that: 'five attempts' is: storage seen size equals: 5.
c that: 'its atoms were saved before the first attempt' isTrue: storage seen first > before.
c that: 'and not again while the lock was held' is: (storage seen asArray copyFrom: 1 to: 5) asSet size equals: 1.
holder close.
space close.
base deleteAll.
c report displayNl.
