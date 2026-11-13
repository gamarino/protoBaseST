"EXPECT: 10 crash recovery ok (12 checks)"
"Lesson 10: what a crash leaves on disk, and reopening after it.
 Tutorial chapter: docs/tutorial/10-crash-recovery.md

 What it teaches:
 - files are only appended to, and a version is published by one atomic rename of
   space.root after the segments are synced (fsync). A crash can leave bytes after the last
   published record (a torn tail) or a half-written space.root.tmp; neither is ever read;
 - reopening needs no recovery step: the space opens at the last published version, and the
   next commit writes to a new segment of its own, leaving the leftovers as they are;
 - a writer process killed with SIGKILL in the middle of its commits loses at most the
   commit in flight: every version on disk is a whole commit.
 Part 1 is deterministic (the torn bytes are written on purpose); part 2 kills a real
 process, so where it dies varies from run to run, and the checks hold wherever it dies.

 Run it: STPATH=<repository>/src PROTOST=<the protost binary> protost 10_crash_recovery.st"
Import from: 'protobase'.
Import from: '_lesson'.

| lesson dir space db segment file before protost writer sentinel pid deadline committed status snap |
lesson := Lesson named: '10 crash recovery'.
dir := FileSystem temp / ('pbst-tutorial-10-' , Smalltalk pid printString).
dir deleteAll.

"--- Part 1: a torn tail and a torn space.root.tmp, written on purpose ---"
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'crash'.
db newTransactionDo: [:t |
    t setRootObject: 'counter' value: 0.
    t setRootObject: 'log' value: t newDictionary].
space close.
before := (dir / 'space.root') binaryContents.
"What a crash in the middle of an append leaves: the first bytes of a record, no more."
segment := (dir children select: [:f | f basename endsWith: '.seg']) first.
file := BinaryFile open: segment pathString options: #(#append).
file append: #[1 200 0 0 0 0 0 0 0 7 7].
file close.
"What a crash before the rename leaves: a partial next root."
(dir / 'space.root.tmp') binaryContents: #[80 66 0 0 3].
lesson say: 'left a torn record at the end of ' , segment basename , ' and a torn space.root.tmp'.

space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space openDatabase: 'crash'.
lesson check: 'reopens at the last published version' is: db history first version equals: 1.
lesson check: 'its data is intact' is: (db newTransaction getRootObject: 'counter') equals: 0.
db newTransactionDo: [:t | t setRootObject: 'counter' value: 1].
lesson check: 'a commit after the crash works' is: db history first version equals: 2.
lesson check: 'it wrote a new segment of its own' is: (dir children select: [:f | f basename endsWith: '.seg']) size
    equals: 2.
lesson check: 'the published root moved on' isTrue: (dir / 'space.root') binaryContents ~= before.
lesson check: 'the torn bytes were left as they were (never truncated)'
    isTrue: ((segment binaryContents) copyFrom: segment size - 9 to: segment size) = #[200 0 0 0 0 0 0 0 7 7].
space close.

"--- Part 2: a writer process killed with SIGKILL ---"
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space openDatabase: 'crash'.
db newTransactionDo: [:t | t setRootObject: 'counter' value: 0. t setRootObject: 'log' value: t newDictionary].
space close.
protost := (Smalltalk getenv: 'PROTOST') ifNil: ['protost'].
writer := (Smalltalk programPath asFileReference parent / '_crash_writer.st') fullName.
"The writer runs while this file exists, and stops by itself after 1000 commits or 60 s."
sentinel := dir / 'keep-writing'.
sentinel contents: 'delete me to stop the writer'.
pid := OSProcess spawn: protost arguments: { writer. dir pathString. sentinel pathString }.
"Wait until it has committed a few versions (at most 60 seconds), then kill it. The kill is in
 an ensure: block, so an error while waiting still ends the writer; only its own pid is killed."
committed := 0.
[deadline := Time millisecondClockValue + 60000.
 [committed < 5 and: [Time millisecondClockValue < deadline]] whileTrue: [
    (Future after: 50) wait.
    space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
    [committed := (space openDatabase: 'crash') newTransaction getRootObject: 'counter']
        ensure: [space close]]]
  ensure: [
    sentinel ensureDelete.
    OSProcess kill: pid signal: 9.
    status := OSProcess waitFor: pid].
lesson check: 'the writer committed before it was killed' isTrue: committed >= 5.
lesson check: 'it died by SIGKILL' is: status equals: 137.

space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space openDatabase: 'crash'.
snap := db newTransaction.
lesson say: 'killed after ' , (snap getRootObject: 'counter') printString , ' commits'.
lesson check: 'every version is a whole commit: counter = log size'
    is: (snap getRootObject: 'counter') equals: (snap getRootObject: 'log') count.
lesson check: 'one version per commit, none half-made'
    is: db history first version equals: 3 + (snap getRootObject: 'counter').
lesson check: 'and in every version since the writer started' isTrue: ((db history select: [:entry | entry version >= 3]) allSatisfy: [:entry |
    | s |
    s := db snapshotAt: entry.
    (s getRootObject: 'counter') = (s getRootObject: 'log') count]).
"The lock of a killed process is released by the operating system: we can commit."
db newTransactionDo: [:t | t setRootObject: 'counter' value: (t getRootObject: 'counter') + 1.
    t setRootObject: 'log' value: ((t getRootObject: 'log') setAt: 0 value: Smalltalk pid)].
snap := db newTransaction.
lesson check: 'the next commit works' is: (snap getRootObject: 'counter') equals: (snap getRootObject: 'log') count.
space close.
dir deleteAll.
lesson finish.
