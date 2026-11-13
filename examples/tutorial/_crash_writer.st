"_crash_writer.st: the process that lesson 10 kills (a helper: the test runner never runs
 files whose name starts with _).

 Usage: protost _crash_writer.st <directory> <sentinel file>
 Commits to the database 'crash' of the space in <directory>: each commit adds one to the root
 'counter' and one entry to the dictionary 'log', so in every committed version counter = log
 count. It prints nothing; lesson 10 ends it with SIGKILL. It can never run for ever: it stops
 by itself when the sentinel file is gone, after 1000 commits, or after 60 seconds, whichever
 comes first, so a lesson that dies before its kill leaves no process behind."
Import from: 'protobase'.

| space db sentinel deadline i |
space := PBObjectSpace storage: (PBFileStorage path: Smalltalk arguments first).
db := space openDatabase: 'crash'.
sentinel := (Smalltalk arguments at: 2) asFileReference.
deadline := Time millisecondClockValue + 60000.
i := 0.
[i < 1000 and: [sentinel exists and: [Time millisecondClockValue < deadline]]] whileTrue: [
  i := i + 1.
  db run: [:tr |
    tr setRootObject: 'counter' value: (tr getRootObject: 'counter') + 1.
    tr setRootObject: 'log' value: ((tr getRootObject: 'log') setAt: i value: Smalltalk pid)]].
space close.
