"""ProtoBase's side of st_write_to_py.sh: read the space protoST wrote and commit on top of it.

Usage: python py_extend_st_space.py check-create <directory>
       python py_extend_st_space.py commit <directory>
       python py_extend_st_space.py check-extend <directory>
       python py_extend_st_space.py hold-lock <directory>

check-create  the database 'st' has versions 1 and 0, its roots read back as protoST wrote them
commit        commits version 2 of 'st' through ProtoBase's API (the root 'py' = 'from Python')
check-extend  version 3, written by protoST on top of Python's commit, holds 'py' and 'st2'
hold-lock     takes FileStorage.root_lock, prints 'locked', and holds it until stdin closes

Exit 0 when every check holds, 1 otherwise (each failed check is printed).
"""
import sys

from proto_db import FileStorage, ObjectSpace

FAILURES = []


def check(label, actual, expected):
    if actual != expected:
        FAILURES.append(f"{label}: expected {expected!r}, got {actual!r}")


def check_create(directory):
    space = ObjectSpace(FileStorage(directory))
    try:
        db = space.open_database("st")
        check("versions", [e.version for e in db.history()], [1, 0])
        tx = db.new_transaction()
        numbers = tx.get_root_object("numbers")
        check("the list", list(numbers), list(range(1, 301)))
        acme = tx.get_root_object("acme")
        check("the record", (acme.name, str(acme.since), acme.score), ("ACME", "2026-11-11", 4.5))
        check("the dictionary", dict(tx.get_root_object("rates").items()), {"ARS": 1, "USD": 1450})
        check("version 1's root", list(tx.get_root_object("later")), ["a", "b"])
        tx.abort()
    finally:
        space.close()


def commit(directory):
    space = ObjectSpace(FileStorage(directory))
    try:
        tx = space.open_database("st").new_transaction()
        tx.set_root_object("py", "from Python")
        tx.commit()
    finally:
        space.close()


def check_extend(directory):
    space = ObjectSpace(FileStorage(directory))
    try:
        db = space.open_database("st")
        check("versions", [e.version for e in db.history()], [3, 2, 1, 0])
        tx = db.new_transaction()
        check("Python's root", tx.get_root_object("py"), "from Python")
        check("protoST's root", getattr(tx.get_root_object("st2"), "from"), "protoST")
        check("the list", len(tx.get_root_object("numbers")), 300)
        tx.abort()
    finally:
        space.close()


def hold_lock(directory):
    storage = FileStorage(directory)
    try:
        with storage.root_lock():
            print("locked", flush=True)
            sys.stdin.read()
    finally:
        storage.close()


def main(mode, directory):
    {"check-create": check_create, "commit": commit, "check-extend": check_extend,
     "hold-lock": hold_lock}[mode](directory)
    for failure in FAILURES:
        print(f"py_extend_st_space: FAIL {failure}")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
