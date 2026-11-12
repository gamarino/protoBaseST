"""ProtoBase's side of st_commit_to_py.sh (plan Task 18): read and extend the database protoST
committed through its transactions and publisher.

Usage: python py_commit_space.py check-create <directory>
       python py_commit_space.py commit <directory>
       python py_commit_space.py check-extend <directory>

check-create  the database 'tx' has versions 2, 1, 0 with protoST's values; its DatabaseRoot
              and SpaceRoot records hold their fields in the order ProtoBase writes them,
              compared with the records of a database ProtoBase creates and commits in a
              scratch space; committed_at never goes back and is UTC; origin is 16 bytes,
              carried by every version
commit        version 3 through ProtoBase's API: a blind merge of 'py' into 'tags' and the
              cell 'counter' set to 7
check-extend  version 4, protoST's blind merge on top of ProtoBase's, holds every key

Exit 0 when every check holds, 1 otherwise (each failed check is printed).
"""
import datetime
import sys
import tempfile

import msgpack

from proto_db import FileStorage, ObjectSpace
from proto_db.transactions import _SpaceContext

FAILURES = []


def check(label, actual, expected):
    if actual != expected:
        FAILURES.append(f"{label}: expected {expected!r}, got {actual!r}")


def field_order(storage, atom):
    """The attribute names of ``atom``'s record, in the order the record holds them."""
    _, payload = storage.get_record(atom.atom_pointer)
    return list(msgpack.unpackb(payload, raw=False, strict_map_key=False)["s"].keys())


def roots(storage, db):
    record = storage.read_root()
    context = _SpaceContext(storage)
    root = db._root_in(context, record)
    space = context.load(record.pointer, "proto_db.transactions.SpaceRoot")
    return space, root


def python_orders():
    """The field orders of a SpaceRoot and of DatabaseRoots versions 0 and 1 ProtoBase writes."""
    with tempfile.TemporaryDirectory() as scratch:
        storage = FileStorage(scratch)
        space = ObjectSpace(storage)
        try:
            db = space.new_database("py")
            _, root0 = roots(storage, db)
            v0 = field_order(storage, root0)
            tx = db.new_transaction()
            tx.set_root_object("x", 1)
            tx.commit()
            space_root, root1 = roots(storage, db)
            return field_order(storage, space_root), v0, field_order(storage, root1)
        finally:
            space.close()


def check_create(directory):
    storage = FileStorage(directory)
    space = ObjectSpace(storage)
    try:
        db = space.open_database("tx")
        history = db.history()
        check("versions", [e.version for e in history], [2, 1, 0])
        tx = db.new_transaction()
        check("n", tx.get_root_object("n"), 42)
        check("tags (protoST's blind merge)", dict(tx.get_root_object("tags").items()), {"a": 1, "b": 2})
        check("list", list(tx.get_root_object("list")), ["x", "y"])
        person = tx.get_root_object("person")
        check("person", (person.name, person.born), ("Ada", 1815))
        check("counter", tx.get_mutable("counter"), 6)
        tx.abort()
        times = [e.committed_at for e in reversed(history)]
        check("committed_at never goes back", times, sorted(times))
        check("committed_at is UTC", {t.utcoffset() for t in times}, {datetime.timedelta(0)})
        origins = {e.root.origin for e in history}
        check("one origin, 16 bytes", [len(o) for o in origins], [16])
        space_order, py_v0, py_v1 = python_orders()
        space_root, root = roots(storage, db)
        check("SpaceRoot field order", field_order(storage, space_root), space_order)
        check("DatabaseRoot field order", field_order(storage, root), py_v1)
        check("DatabaseRoot version 0 field order", field_order(storage, history[-1].root), py_v0)
    finally:
        space.close()


def commit(directory):
    space = ObjectSpace(FileStorage(directory))
    try:
        tx = space.open_database("tx").new_transaction()
        tx.set_root_object("tags", tx.new_dictionary().set_at("py", 3))
        tx.set_mutable("counter", 7)
        tx.commit()
    finally:
        space.close()


def check_extend(directory):
    space = ObjectSpace(FileStorage(directory))
    try:
        db = space.open_database("tx")
        check("versions", [e.version for e in db.history()], [4, 3, 2, 1, 0])
        tx = db.new_transaction()
        check("tags", dict(tx.get_root_object("tags").items()), {"a": 1, "b": 2, "py": 3, "st2": True})
        check("counter", tx.get_mutable("counter"), 7)
        tx.abort()
    finally:
        space.close()


def main(argv):
    mode, directory = argv
    {"check-create": check_create, "commit": commit, "check-extend": check_extend}[mode](directory)
    for failure in FAILURES:
        print("FAIL:", failure)
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
