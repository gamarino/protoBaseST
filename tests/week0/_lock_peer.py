"""Lock peer for lock_excludes_protobase.sh.

Opens <dir>/space.lock the way ProtoBase's FileStorage does (proto_db/storage/file.py:
os.open on the lock file, then fcntl.flock(LOCK_EX | LOCK_NB)), prints "locked" and holds the
lock until its stdin reaches end of file.
"""
import fcntl
import os
import sys

path = os.path.join(sys.argv[1], "space.lock")
fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o644)
try:
    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
except OSError:
    print("busy", flush=True)
    sys.exit(2)
print("locked", flush=True)
sys.stdin.read()          # blocks until the shell closes the FIFO
fcntl.flock(fd, fcntl.LOCK_UN)
os.close(fd)
