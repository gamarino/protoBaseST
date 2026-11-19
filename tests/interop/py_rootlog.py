"""proto_db's side of rootlog_both_ways.sh (plan Task 26): the acceptor log through proto_db's API.

Usage:
  python py_rootlog.py load <file>          prints RootsLog(<file>).load()
  python py_rootlog.py format <file>        prints the log format version in the file's header
  python py_rootlog.py write <file>         appends the entry sequence of _st_cluster_space.st
                                            write-log to the new log <file>, then closes it
  python py_rootlog.py name <dir> <id>...   for each id, the file _node_log names for a shared
                                            storage in <dir>, relative to <dir>

The text of a log is the one _st_cluster_space.st load-log prints: 'accepted' and 'committed' as
'<kind> none', '<kind> <label> empty' (the empty space) or '<kind> <label> <version> <segment
hex> <offset> <epoch>'; then 'promise <n>' (LoggedRoots.promised), 'top <n>', 'rejoined
true|false' (not LoggedRoots.empty).

An id given as hex:<hex of its UTF-8> is decoded first, so any id passes through the command
line. _node_log opens the log it names (RootsLog creates cluster/ and the file in <dir>); each is
closed before the next id.
"""
import os
import sys
import uuid

from proto_db.cluster.persister import _node_log
from proto_db.cluster.rootlog import RootsLog
from proto_db.storage.format import WRITE_FORMAT_VERSION, RootRecord
from proto_db.storage.logfile import HEADER_SIZE, header_version


def root_text(kind, root):
    if root is None:
        return f"{kind} none"
    label, record = root
    if record is None:
        return f"{kind} {label} empty"
    return f"{kind} {label} {record.version} {record.segment.bytes.hex()} {record.offset} {record.epoch}"


def load(path):
    log = RootsLog(path)
    try:
        roots = log.load()
    finally:
        log.close()
    print(root_text("accepted", roots.accepted))
    print(root_text("committed", roots.committed))
    print(f"promise {roots.promised}")
    print(f"top {roots.top}")
    print(f"rejoined {'false' if roots.empty else 'true'}")


def write(path):
    """The entry sequence of _st_cluster_space.st write-log (keep both in step)."""
    if os.path.exists(path):
        raise SystemExit(f"py_rootlog.py write: {path} exists; the sequence is written to a new log")
    seg1 = uuid.UUID(bytes=bytes(range(0, 16)))
    seg2 = uuid.UUID(bytes=bytes(range(240, 256)))
    seg3 = uuid.UUID(bytes=bytes(range(16, 32)))
    v = WRITE_FORMAT_VERSION
    log = RootsLog(path)
    try:
        log.promise(3)
        log.append("accepted", 3, None)
        log.append("committed", 3, None)
        log.promise(2)
        log.promise(7)
        log.append("accepted", 7, RootRecord(v, seg1, 1234, 5))
        log.append("committed", 7, RootRecord(v, seg1, 1234, 5))
        log.append("accepted", 7, RootRecord(v, seg2, 99, 6))
        log.append("committed", 3, RootRecord(v, seg3, 8, 9))
        log.promise(2 ** 63 + 1)
        log.mark_rejoined()
    finally:
        log.close()
    print("written")


class _SharedStorage:
    """What _node_log asks of a shared storage: a ``path`` that is a directory."""

    def __init__(self, path):
        self.path = path


def name(directory, ids):
    os.makedirs(directory, exist_ok=True)
    base = os.path.realpath(directory)
    storage = _SharedStorage(directory)
    for arg in ids:
        node_id = bytes.fromhex(arg[4:]).decode("utf-8") if arg.startswith("hex:") else arg
        log = _node_log(storage, node_id)
        try:
            print(os.path.relpath(log.path, base))
        finally:
            log.close()


def main(argv):
    if len(argv) >= 2 and argv[0] == "load" and len(argv) == 2:
        load(argv[1])
    elif len(argv) == 2 and argv[0] == "format":
        with open(argv[1], "rb") as f:
            print(header_version(f.read(HEADER_SIZE)))
    elif len(argv) == 2 and argv[0] == "write":
        write(argv[1])
    elif len(argv) >= 3 and argv[0] == "name":
        name(argv[1], argv[2:])
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
