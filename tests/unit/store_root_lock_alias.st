"EXPECT: ok 2"
"The root lock (space.lock, PBFileStorage tryLockRoot) through another name of the space. proto_db's
 FileStorage names it os.path.join(path, 'space.lock') without realpath, and so does protoBaseST:
 the lock file lives inside the space directory, so every alias of the directory, and a symbolic
 link standing for space.lock itself, opens the same file, and the OS lock (flock) excludes the
 second holder. Only a lock file named as a sibling of the last path component (the acceptor
 log's <path>.lock) needs the real path (cluster_acceptor_log.st, cases 11 and 12)."
Import from: 'protobase'.
| failures tests check base real alias a b |
failures := OrderedCollection new.
tests := Set new.
check := [:name :ok | ok ifFalse: [failures add: name]].
base := FileSystem temp / ('pbst-root-lock-alias-' , Smalltalk pid printString).
base deleteAll.
real := base / 'space'.
real ensureCreateDirectory.
alias := base / 'alias'.

tests add: 1.
"1. a symbolic link to the space directory: the second storage cannot take the held lock"
check value: 'directory link made' value: (OSProcess run: 'ln' arguments: { '-s'. real pathString. alias pathString }) exitCode = 0.
a := PBFileStorage path: real.
b := PBFileStorage path: alias.
check value: 'first takes the lock' value: a tryLockRoot.
check value: 'the alias is excluded' value: b tryLockRoot not.
a unlockRoot.
check value: 'the alias takes it once released' value: b tryLockRoot.
b unlockRoot.
a close.
b close.

tests add: 2.
"2. space.lock itself a symbolic link to another space's lock: the same file, excluded"
(base / 'other') ensureCreateDirectory.
a := PBFileStorage path: real.
a tryLockRoot.
check value: 'lock link made' value: (OSProcess run: 'ln' arguments: { '-s'. (real / 'space.lock') pathString. (base / 'other' / 'space.lock') pathString }) exitCode = 0.
b := PBFileStorage path: base / 'other'.
check value: 'a linked space.lock is excluded' value: b tryLockRoot not.
a unlockRoot.
a close.
b close.
base deleteAll.
failures isEmpty ifFalse: [failures do: [:f | ('FAIL ' , f) displayNl]. Smalltalk exit: 1].
'ok ' , tests size printString
