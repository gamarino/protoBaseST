"_crash_writer.st: the process that lesson 10 kills (a helper: the test runner never runs
 files whose name starts with _).

 Usage: protost _crash_writer.st <directory>
 Commits for ever to the database 'crash' of the space in <directory>: each commit adds one
 to the root 'counter' and one entry to the dictionary 'log', so in every committed version
 counter = log count. It prints nothing; lesson 10 ends it with SIGKILL."
Import from: 'protobase'.

| space db i |
space := PBObjectSpace storage: (PBFileStorage path: Smalltalk arguments first).
db := space openDatabase: 'crash'.
i := 0.
[true] whileTrue: [
  i := i + 1.
  db run: [:tr |
    tr setRootObject: 'counter' value: (tr getRootObject: 'counter') + 1.
    tr setRootObject: 'log' value: ((tr getRootObject: 'log') setAt: i value: Smalltalk pid)]].
