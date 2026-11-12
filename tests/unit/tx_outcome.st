"EXPECT: ok 21"
"The outcome of a commit whose publish fails (plan Task 18 and call C17, design spec 7.3
 step 8; ProtoBase _publish): the publisher re-reads space.root under the root lock.
 Three test-only subclasses of PBFileStorage fail the rename seam of replaceRoot: once
 armed, with no flag or hook in product code:
  - FailAfterRename renames, then fails: the root read back is the commit's own, so the
    commit is reported successful;
  - FailBeforeRename fails before renaming: the root read back is the one the commit was
    built on, so the original error is re-signalled and no version is added;
  - FailOtherRoot fails before renaming, after a writer that ignores the root lock
    published another root (another epoch): nothing of the commit was published, and
    the commit is PBConflictError, as ProtoBase's _publish;
  - FailReread renames, fails, and then cannot read space.root: PBOutcomeUnknownError,
    never a guess (the version was in fact published).
 In every case the root lock is released and the transaction has ended (committed, or
 aborted after the failure). The failed storage accepts no more writes (ProtoBase's
 failure policy)."
Import from: 'protobase'.
Import from: '_check'.

PBFileStorage subclass: #FailAfterRename instanceVariableNames: 'armed logged'.
FailAfterRename >> arm
  armed := true.
FailAfterRename >> logged
  ^ logged ifNil: [logged := OrderedCollection new].
FailAfterRename >> _log: aString
  self logged add: aString.
FailAfterRename >> _replaceRootFile
  super _replaceRootFile.
  armed == true ifTrue: [armed := false. ^ FileSystemError signal: 'injected failure after the rename'].

PBFileStorage subclass: #FailBeforeRename instanceVariableNames: 'armed'.
FailBeforeRename >> arm
  armed := true.
FailBeforeRename >> _replaceRootFile
  armed == true ifTrue: [armed := false. ^ FileSystemError signal: 'injected failure before the rename'].
  ^ super _replaceRootFile.

PBFileStorage subclass: #FailOtherRoot instanceVariableNames: 'armed'.
FailOtherRoot >> arm
  armed := true.
FailOtherRoot >> _replaceRootFile
  | current |
  armed == true ifTrue: [
    armed := false.
    current := self readRoot.
    (self directory / 'space.root') binaryContents:
      (PBRootRecord segment: current segment offset: current offset epoch: current epoch + 5) encode.
    ^ FileSystemError signal: 'injected failure: another writer published meanwhile'].
  ^ super _replaceRootFile.

PBFileStorage subclass: #FailReread instanceVariableNames: 'armed unreadable'.
FailReread >> arm
  armed := true.
FailReread >> _replaceRootFile
  super _replaceRootFile.
  armed == true ifTrue: [
    armed := false.
    unreadable := true.
    ^ FileSystemError signal: 'injected failure after the rename'].
FailReread >> readRoot
  unreadable == true ifTrue: [^ PBUnexpectedError signal: 'injected failure: space.root cannot be read'].
  ^ super readRoot.

| c base dir run storage space db tx versions other otherSpace |
c := Check new.
base := FileSystem temp / ('pbst-tx-outcome-' , Smalltalk pid printString).
base deleteAll.
"The versions of the database 'db' in dir, read through a fresh storage."
versions := [:aDir | | s v |
  s := PBObjectSpace storage: (PBFileStorage path: aDir pathString).
  v := ((s openDatabase: 'db') history collect: [:e | e version]) asArray.
  s close.
  v].
"Whether another storage can take the root lock of aDir now."
other := [:aDir | | s took |
  s := PBFileStorage path: aDir pathString.
  took := s tryLockRoot.
  took ifTrue: [s unlockRoot].
  s close.
  took].

"Fails after the rename: the commit succeeded."
dir := base / 'after'.
storage := FailAfterRename path: dir pathString.
space := PBObjectSpace storage: storage.
db := space newDatabase: 'db'.
tx := db newTransaction.
tx setRootObject: 'x' value: 1.
storage arm.
tx commit.
c that: 'after the rename: the commit is reported successful' is: tx isActive equals: false.
c that: 'the storage failed' is: storage isFailed equals: true.
c that: 'the version is published' is: (versions value: dir) equals: #(1 0).
c that: 'the success after a failure is logged' isTrue: (storage logged last includesSubstring: 'the commit succeeded').
c that: 'with the value' is: (db newTransaction getRootObject: 'x') equals: 1.
c that: 'the root lock is released' is: (other value: dir) equals: true.
tx := db newTransaction.
tx setRootObject: 'x' value: 2.
c that: 'the failed storage accepts no more writes' signals: PBUnexpectedError containing: 'no more writes' during: [tx commit].
c that: 'and that transaction is aborted' is: tx isActive equals: false.
c that: 'the lock is released after that failure too' is: (other value: dir) equals: true.
space close.

"Fails before the rename: the original error, no new version."
dir := base / 'before'.
storage := FailBeforeRename path: dir pathString.
space := PBObjectSpace storage: storage.
db := space newDatabase: 'db'.
tx := db newTransaction.
tx setRootObject: 'x' value: 1.
storage arm.
c that: 'before the rename: the original error, not an unknown outcome' is: ([tx commit. 'none'] on: Error do: [:e |
  { e class name. e messageText includesSubstring: 'injected failure before the rename' }])
  equals: { 'PBUnexpectedError'. true }.
c that: 'the transaction is aborted' is: tx isActive equals: false.
c that: 'no version was added' is: (versions value: dir) equals: #(0).
c that: 'the root lock is released' is: (other value: dir) equals: true.
space close.

"Another root appeared under the lock: a conflict, nothing of the commit published."
dir := base / 'other'.
storage := FailOtherRoot path: dir pathString.
space := PBObjectSpace storage: storage.
db := space newDatabase: 'db'.
tx := db newTransaction.
tx setRootObject: 'x' value: 1.
storage arm.
c that: 'another root: a conflict' signals: PBConflictError containing: 'Another root was published' during: [tx commit].
c that: 'the transaction is aborted' is: tx isActive equals: false.
c that: 'the root is the other writer''s' is: storage readRoot epoch equals: 6.
c that: 'the root lock is released' is: (other value: dir) equals: true.
space close.

"Fails after the rename, and the re-read fails: the outcome is unknown."
dir := base / 'reread'.
storage := FailReread path: dir pathString.
space := PBObjectSpace storage: storage.
db := space newDatabase: 'db'.
tx := db newTransaction.
tx setRootObject: 'x' value: 1.
storage arm.
c that: 'the outcome is unknown' signals: PBOutcomeUnknownError containing: 'unknown' during: [tx commit].
c that: 'the transaction has ended' is: tx isActive equals: false.
c that: 'the version was in fact published' is: (versions value: dir) equals: #(1 0).
c that: 'the root lock is released' is: (other value: dir) equals: true.
space close.

base deleteAll.
c report displayNl.
