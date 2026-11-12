"""ProtoBase's side of the concurrency table (design spec 10.4, plan Task 21 and call C12).

Usage: python py_case.py setup <case> <directory>
       python py_case.py both  <case> <directory>
       python py_case.py a     <case> <directory>
       python py_case.py b     <case> <directory>
       python py_case.py dump  <case> <directory>
       python py_case.py expected <case> <variant>

The cases, their steps and the dump notation are in concurrency_cases.json.

setup  creates the case's database and runs its setup steps (one transaction)
both   the reference: starts A, starts B, commits B, commits A, all in ProtoBase; prints the
       outcome line 'A=<outcome> B=<outcome>' and the dump
a      starts A, runs protoST's B to completion as a subprocess ($PROTOST _st_case.st b), then
       commits A; prints the outcome line and the dump
b      one-shot: starts B and commits it; prints 'B=<outcome>'
dump   prints the dump of the case's roots and cells, read in a new transaction
expected  prints the outcome line and the dump the JSON records for the variant 'reference'
       (ProtoBase's outcome), or 'st_as_a', 'py_as_a' or 'actors': protoBaseST's documented
       outcome where the case has one (its 'protobasest' entry, allowed only on the ids of
       REFUSAL_IDS and only with PBNotSupportedError in each outcome), the reference otherwise

Exit 0 when the mode ran, whatever the outcomes; any other failure exits non-zero.
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

from proto_db import DBObject, Dictionary, FileStorage, List, ObjectSpace, Set
from proto_db.errors import ProtoDBError

HERE = Path(__file__).resolve().parent
CASES = HERE / "concurrency_cases.json"
VECTOR = HERE.parent / "conformance" / "vectors" / "database"
# The ids that may record protoBaseST's documented refusal in place of ProtoBase's outcome
# (design spec 7.4); the refusal must be PBNotSupportedError.
REFUSAL_IDS = ("indexed-root",)


def load_case(case_id):
    for case in json.loads(CASES.read_text())["cases"]:
        if case["id"] == case_id:
            return case
    raise SystemExit(f"py_case.py: no case {case_id!r} in {CASES.name}")


def uses_vector(case):
    return ["vector database"] in case["setup"]


def database_name(case):
    return "db" if uses_vector(case) else "cc"


def outcome_name(error):
    """protoBaseST's name of a ProtoBase error class: Proto... becomes PB... (plan call C14)."""
    name = type(error).__name__
    if not isinstance(error, ProtoDBError) or not name.startswith("Proto"):
        raise error
    return "PB" + name[len("Proto"):]


# -- the steps --------------------------------------------------------------------------------

def setup_value(value):
    if isinstance(value, dict):
        (kind, content), = value.items()
        if kind == "dict":
            result = Dictionary()
            for key, item in content.items():
                result = result.set_at(key, item)
            return result
        if kind == "list":
            return List.from_iterable(content)
        if kind == "set":
            return Set.from_iterable(content)
        raise SystemExit(f"py_case.py: unknown setup value {value!r}")
    return value


def prepare(db, steps):
    """The steps that run before the side's transaction starts: answers the values they committed."""
    committed = {}
    for step in steps:
        if step[0] == "reuse committed":
            _, root, key, value = step[:4]
            tr = db.new_transaction()
            written = tr.new_dictionary().set_at(key, value)
            tr.set_root_object(root, written)
            tr.commit()
            committed[root] = written
    return committed


def apply(tr, step, committed, in_setup=False):
    op, args = step[0], step[1:]
    if op == "read root":
        tr.get_root_object(args[0])
    elif op == "set root":
        tr.set_root_object(args[0], setup_value(args[1]) if in_setup else args[1])
    elif op == "blind dict set root":
        tr.set_root_object(args[0], tr.new_dictionary().set_at(args[1], args[2]))
    elif op == "replace":
        tr.set_root_object(args[0], tr.new_dictionary().set_at(args[1], args[2]), replace=True)
    elif op == "list set":
        tr.set_root_object(args[0], tr.new_list().append_last(args[1]))
    elif op == "set add":
        tr.set_root_object(args[0], tr.new_set().add(args[1]))
    elif op == "set remove":
        tr.set_root_object(args[0], tr.new_set().remove(args[1]))
    elif op == "new mutable":
        tr.new_mutable(args[0], args[1])
    elif op == "set mutable":
        tr.set_mutable(args[0], args[1])
    elif op == "remove mutable":
        tr.remove_mutable(args[0])
    elif op == "reuse committed":
        tr.set_root_object(args[0], committed[args[0]].set_at(args[3], args[4]))
    else:
        raise SystemExit(f"py_case.py: unknown step {step!r}")


class Side:
    """One transaction of a case: started with its steps, committed later. A step or a commit that
    fails ends the side with that error as its outcome."""

    def __init__(self, db, steps):
        committed = prepare(db, steps)
        self.tr = db.new_transaction()
        self.outcome = None
        try:
            for step in steps:
                apply(self.tr, step, committed)
        except ProtoDBError as error:
            self.outcome = outcome_name(error)
            if self.tr.is_active:
                self.tr.abort()

    def commit(self):
        if self.outcome is None:
            try:
                self.tr.commit()
                self.outcome = "committed"
            except ProtoDBError as error:
                self.outcome = outcome_name(error)
        return self.outcome


# -- the dump ---------------------------------------------------------------------------------

def render(value):
    if value is None:
        return "absent"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return "'" + value + "'"
    if isinstance(value, Dictionary):
        return "{" + ", ".join(f"{render(k)}: {render(v)}" for k, v in sorted(value.items())) + "}"
    if isinstance(value, List):
        return "[" + ", ".join(render(v) for v in value) + "]"
    if isinstance(value, Set):
        return "#{" + ", ".join(sorted(render(e) for e in value)) + "}"
    if isinstance(value, DBObject):
        return "<object>"
    raise SystemExit(f"py_case.py: no dump notation for {type(value).__name__}")


def dump_lines(db, case):
    tr = db.new_transaction()
    lines = [f"root {name} = {render(tr.get_root_object(name))}" for name in case["roots"]]
    lines += [f"mutable {name} = {render(tr.get_mutable(name))}" for name in case["mutables"]]
    tr.abort()
    return lines


# -- the modes --------------------------------------------------------------------------------

def setup(case, directory):
    if uses_vector(case):
        shutil.copytree(VECTOR, directory)
        return
    space = ObjectSpace(FileStorage(directory))
    try:
        db = space.new_database("cc")
        tr = db.new_transaction()
        for step in case["setup"]:
            apply(tr, step, {}, in_setup=True)
        tr.commit()
    finally:
        space.close()


def report(db, case, a, b):
    print(f"A={a} B={b}")
    for line in dump_lines(db, case):
        print(line)


def both(case, directory):
    space = ObjectSpace(FileStorage(directory))
    try:
        db = space.open_database(database_name(case))
        a = Side(db, case["a"])
        b = Side(db, case["b"])
        b_outcome = b.commit()
        report(db, case, a.commit(), b_outcome)
    finally:
        space.close()


def as_a(case, directory):
    space = ObjectSpace(FileStorage(directory))
    try:
        db = space.open_database(database_name(case))
        a = Side(db, case["a"])
        run = subprocess.run([os.environ["PROTOST"], "_st_case.st", "b", case["id"], directory],
                             cwd=HERE, capture_output=True, text=True)
        line = run.stdout.strip()
        if run.returncode != 0 or not line.startswith("B=") or "\n" in line:
            raise SystemExit(f"py_case.py: protoST's B failed (exit {run.returncode}): {run.stdout}{run.stderr}")
        report(db, case, a.commit(), line[len("B="):])
    finally:
        space.close()


def as_b(case, directory):
    space = ObjectSpace(FileStorage(directory))
    try:
        print(f"B={Side(space.open_database(database_name(case)), case['b']).commit()}")
    finally:
        space.close()


def dump(case, directory):
    space = ObjectSpace(FileStorage(directory))
    try:
        for line in dump_lines(space.open_database(database_name(case)), case):
            print(line)
    finally:
        space.close()


def expected(case, variant):
    if variant not in ("reference", "st_as_a", "py_as_a", "actors"):
        raise SystemExit(f"py_case.py: unknown variant {variant!r}")
    recorded = case["expected"]
    if "protobasest" in case:
        if case["id"] not in REFUSAL_IDS:
            raise SystemExit(f"py_case.py: only {REFUSAL_IDS} may record protoBaseST's refusal, not {case['id']!r}")
        for name, entry in case["protobasest"].items():
            if "PBNotSupportedError" not in entry["outcome"]:
                raise SystemExit(f"py_case.py: the refusal recorded for {case['id']!r} {name} is not "
                                 f"PBNotSupportedError: {entry['outcome']}")
        if variant != "reference":
            recorded = case["protobasest"][variant]
    print(recorded["outcome"])
    for line in recorded["dump"]:
        print(line)


def main(argv):
    mode, case_id, directory = argv
    {"setup": setup, "both": both, "a": as_a, "b": as_b, "dump": dump,
     "expected": expected}[mode](load_case(case_id), directory)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
