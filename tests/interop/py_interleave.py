"""ProtoBase's side of st_py_interleaved.sh (plan Task 18, fix round 1, review M2).

Usage: python py_interleave.py commit <directory>
       python py_interleave.py py-first <directory>

commit    one-shot, for _st_interleave.st st-first: x = 'py' and a blind write of tags {py}
py-first  transaction A reads x and B writes tags blindly; protoST commits in between
          (_st_interleave.st commit, run as a subprocess: x = 'st2' and a blind write of
          tags {st2}); then A's commit is ProtoConflictError and B's merges

Exit 0 when every check holds, 1 otherwise (each failed check is printed).
"""
import os
import subprocess
import sys
from pathlib import Path

from proto_db import FileStorage, ObjectSpace
from proto_db.errors import ProtoConflictError

HERE = Path(__file__).resolve().parent
FAILURES = []


def check(label, actual, expected):
    if actual != expected:
        FAILURES.append(f"{label}: expected {expected!r}, got {actual!r}")


def commit(directory):
    space = ObjectSpace(FileStorage(directory))
    try:
        tr = space.open_database("il").new_transaction()
        tr.set_root_object("x", "py")
        tr.set_root_object("tags", tr.new_dictionary().set_at("py", 1))
        tr.commit()
        print("committed")
    finally:
        space.close()


def py_first(directory):
    space = ObjectSpace(FileStorage(directory))
    try:
        db = space.open_database("il")
        a = db.new_transaction()
        b = db.new_transaction()
        check("A reads x", a.get_root_object("x"), "py")
        b.set_root_object("tags", b.new_dictionary().set_at("py2", 1))
        run = subprocess.run([os.environ["PROTOST"], "_st_interleave.st", "commit", directory],
                             cwd=HERE, capture_output=True, text=True)
        check("protoST commits in between", (run.returncode, run.stdout.strip()), (0, "committed"))
        a.set_root_object("x", "py2")
        try:
            a.commit()
            outcome = "committed"
        except ProtoConflictError:
            outcome = "conflict"
        check("A read x, which protoST changed", outcome, "conflict")
        b.commit()
        tr = db.new_transaction()
        check("x is protoST's", tr.get_root_object("x"), "st2")
        check("the blind writes merged", sorted(tr.get_root_object("tags").keys()), ["a", "py", "py2", "st", "st2"])
        tr.abort()
    finally:
        space.close()


def main(argv):
    mode, directory = argv
    {"commit": commit, "py-first": py_first}[mode](directory)
    for failure in FAILURES:
        print("FAIL:", failure)
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
