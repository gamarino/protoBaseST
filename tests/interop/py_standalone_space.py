"""proto_db's side of standalone_into_cluster.sh (final review I3): a standalone space brought
into a protoBaseST cluster.

Usage: python py_standalone_space.py write <directory>
       python py_standalone_space.py pointer <directory>
       python py_standalone_space.py check <directory> <pointer> <token>

write    a standalone space through proto_db's public API (FileStorage, no cluster): database
         'legacy' with the root objects 'counter' (41) and 'tokens' (a Dictionary, 'old' ->
         'proto_db'), in one commit after the database's creation
pointer  prints the pointer of the space's current root (space.root), '<segment> <offset>', and
         that it is a root written outside cluster mode (label 0: cluster_fields)
check    proto_db reads the space a protoBaseST cluster converted: space.root holds a cluster
         root (label > 0); its cluster_previous chain ends at a root without cluster fields
         whose pointer is <pointer> (the plain root the standalone space published, quoted as
         'pointer' printed it); 'counter' is 42 and tokens['old'] is <token>

Exit 0 when every check holds, 1 otherwise (each failed check is printed).
Run with the interop venv (tests/interop/env.sh): proto_db at the tag setup_venv.sh pins on PYTHONPATH.
"""
import sys

from proto_db import Dictionary, FileStorage, ObjectSpace
from proto_db.cluster.persister import cluster_fields

FAILURES = []


def check(label, actual, expected):
    if actual != expected:
        FAILURES.append(f"{label}: expected {expected!r}, got {actual!r}")


def pointer_text(pointer):
    return f"{pointer.segment} {pointer.offset}"


def write(directory):
    space = ObjectSpace(FileStorage(directory))
    try:
        db = space.new_database("legacy")
        tx = db.new_transaction()
        tx.set_root_object("counter", 41)
        tx.set_root_object("tokens", Dictionary().set_at("old", "proto_db"))
        tx.commit()
    finally:
        space.close()


def pointer(directory):
    storage = FileStorage(directory)
    try:
        record = storage.read_root()
        label, _, previous = cluster_fields(storage, record)
        check("the standalone root's label", label, 0)
        check("the standalone root's predecessor link", previous, None)
        print(pointer_text(record.pointer))
    finally:
        storage.close()


def check_converted(directory, plain, token):
    storage = FileStorage(directory)
    try:
        record = storage.read_root()
        label, _, previous = cluster_fields(storage, record)
        check("space.root is a cluster root (label > 0)", label > 0, True)
        links = 0
        last = previous
        while last is not None and last.cluster_epoch is not None:
            links += 1
            last = last.cluster_previous
        check("the chain ends at a root", last is not None, True)
        if last is not None:
            check("the last link has no cluster term", last.cluster_term, None)
            check("the last link is the plain root", pointer_text(last.atom_pointer), plain)
    finally:
        storage.close()
    space = ObjectSpace(FileStorage(directory))
    try:
        tx = space.open_database("legacy").new_transaction()
        check("counter", tx.get_root_object("counter"), 42)
        check("tokens['old']", tx.get_root_object("tokens").get_at("old"), token)
        tx.abort()
    finally:
        space.close()


def main(argv):
    mode = argv[1] if len(argv) > 1 else ""
    if mode == "write" and len(argv) == 3:
        write(argv[2])
    elif mode == "pointer" and len(argv) == 3:
        pointer(argv[2])
    elif mode == "check" and len(argv) == 5:
        check_converted(argv[2], argv[3], argv[4])
    else:
        print(__doc__)
        return 2
    for failure in FAILURES:
        print("FAILED: " + failure)
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
