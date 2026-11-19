"_hold_lock.st <lockFile> <readyFile>: a peer process that holds a space's root lock (a helper of
 round_lock_retry.st, never run as a test; the pattern of tests/interop/hold_lock.py without the
 Python venv). It opens <lockFile> (space.lock) as PBFileStorage tryLockRoot does, takes the
 OS lock (flock, the format's inter-process protocol), creates <readyFile> once the lock is held
 and then waits until it is killed: the lock is never released while the test waits on it. The
 wait is bounded (ten minutes) so that a test that dies without killing it leaves no process
 behind for ever. It prints nothing (it shares the test's standard streams); exit 2 when the
 lock cannot be taken."

| args lock |
args := Smalltalk arguments.
args size = 2 ifFalse: [Smalltalk exit: 2].
lock := BinaryFile open: (args at: 1) asFileReference options: #(#read #write #create).
lock tryLock ifFalse: [Smalltalk exit: 2].
(args at: 2) asFileReference binaryContents: #[1].
(Future after: 600000) wait.
Smalltalk exit: 0.
