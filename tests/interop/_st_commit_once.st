"_st_commit_once.st <directory> <lockTimeout>: the protoST side of lock_timeout.sh (design
 spec 10.7, plan call C13; a helper, never run as a test). Opens the space in <directory>
 with the root lock timeout <lockTimeout> (SmallInteger milliseconds), commits one root
 'protoST' to the database 'db' (which Python created) and prints 'committed'. A commit that
 ends in an Error prints the class name of the error (for the lock held by another process,
 PBTimeoutError) and exits 1."
Import from: 'protobase'.

| args space |
args := Smalltalk arguments.
args size = 2 ifFalse: [
  'usage: _st_commit_once.st <directory> <lockTimeout>' displayNl.
  Smalltalk exit: 2].
space := PBObjectSpace storage: (PBFileStorage path: (args at: 1)) lockTimeout: (args at: 2) asNumber.
[(space openDatabase: 'db') newTransactionDo: [:t | t setRootObject: 'protoST' value: 'committed by protoST'].
 'committed' displayNl]
  on: Error do: [:e |
    space close.
    e class name displayNl.
    Smalltalk exit: 1].
space close.
