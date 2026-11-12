"""Design spec 10.7 / plan call C13: a protoST commit while another process holds the lock.

Usage: python hold_lock.py <protost> <directory>

1. Creates the database 'db' in <directory> (ProtoBase's API) and releases everything.
2. Takes the space's root lock (FileStorage.root_lock: the flock on space.lock) and prints
   'locked'.
3. While holding it, runs ``<protost> _st_commit_once.st <directory> 50``: protoST's commit
   must wait for the lock and end in PBTimeoutError once its 50 ms lockTimeout is over. The
   outcome does not depend on how long that takes, because the lock is not released until
   protoST's process has exited (the handshake is the process's exit status, never a sleep).
   The last line of its output must be PBTimeoutError, its exit status 1, and no root
   'protoST' may exist afterwards.
4. Releases the lock, and runs the script again with a lockTimeout of 30000: it must print
   'committed' and exit 0.
5. Prints 'lock timeout ok'.

The lock is held through ProtoBase's own storage object, which is the other process of the
format's inter-process protocol. Exit 0 when every check holds, 1 otherwise.
"""
import os
import subprocess
import sys
from pathlib import Path

from proto_db import FileStorage, ObjectSpace

HERE = Path(__file__).resolve().parent
FAILURES = []


def check(label, actual, expected):
    if actual != expected:
        FAILURES.append(f"{label}: expected {expected!r}, got {actual!r}")


def run_protost(protost, directory, timeout_ms):
    done = subprocess.run([protost, "_st_commit_once.st", directory, str(timeout_ms)],
                          cwd=HERE, capture_output=True, text=True, check=False)
    lines = done.stdout.strip().splitlines()
    return done.returncode, lines[-1] if lines else "", done.stderr


def committed_root(directory):
    """The root 'protoST' of database 'db' (None when absent)."""
    space = ObjectSpace(FileStorage(directory))
    try:
        tx = space.open_database("db").new_transaction()
        value = tx.get_root_object("protoST")
        tx.abort()
        return value
    finally:
        space.close()


def main(protost, directory):
    if os.sep in protost:
        protost = os.path.abspath(protost)  # the script runs from its own directory
    space = ObjectSpace(FileStorage(directory))
    space.new_database("db")
    space.close()

    storage = FileStorage(directory)
    try:
        with storage.root_lock():
            print("locked", flush=True)
            status, last, stderr = run_protost(protost, directory, 50)
            check("protoST's commit with 50 ms, last line", last, "PBTimeoutError")
            check("protoST's commit with 50 ms, exit status", status, 1)
            if status not in (0, 1):
                FAILURES.append(f"protoST's stderr: {stderr}")
    finally:
        storage.close()
    check("no root was written by the timed out commit", committed_root(directory), None)

    status, last, stderr = run_protost(protost, directory, 30000)
    check("protoST's commit with 30000 ms, last line", last, "committed")
    check("protoST's commit with 30000 ms, exit status", status, 0)
    if stderr:
        FAILURES.append(f"protoST's stderr: {stderr}")
    check("the committed root", committed_root(directory), "committed by protoST")

    for failure in FAILURES:
        print(f"hold_lock: FAIL {failure}")
    if not FAILURES:
        print("lock timeout ok")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
