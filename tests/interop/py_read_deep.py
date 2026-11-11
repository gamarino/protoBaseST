"""Read the 509-deep attribute that _st_deep_space.st writes, with ProtoBase (plan Task 13).

Usage: python py_read_deep.py <directory>

WORKAROUND (ask B12 to the ProtoBase maintainer): ProtoBase v2.0.0rc1 decodes nested lists
recursively, two Python frames per level, so with Python's default recursion limit (1000)
its reader raises RecursionError on this record (it does from about 333 nested lists; a
ProtoBase limit, reported, not a defect of the record). ProtoBase accepted B12: a
non-recursive codec and a normative MAX_VALUE_DEPTH (candidate 509), to be tagged
v2.0.0rc2. Until then this script raises the recursion limit to read the record, and says
so on every run: a NOTE line, which tests/run_tests.sh shows under the PASS line.

The script first reads with the default limit and requires RecursionError: a ProtoBase
that reads the record without it has resolved B12, and the script then fails, asking for
the raised limit to be dropped. Then it raises the limit and reads the record: the value
must be 509 lists around 1, and its canonical encoding must be the bytes stored.
Exit 0 when it reads back, 1 otherwise.
"""
import sys

from proto_db import FileStorage, ObjectSpace
from proto_db.core import codec

DEPTH = 509


def read(directory):
    space = ObjectSpace(FileStorage(directory))
    try:
        tx = space.open_database("db").new_transaction()
        record = tx.get_root_object("deep")
        value = record.v
        payload = space.storage.get_atom(record.atom_pointer)
        tx.abort()
        return value, payload
    finally:
        space.close()


def main(directory: str) -> int:
    try:
        read(directory)
    except RecursionError:
        pass
    else:
        print("py_read_deep: B12 resolved: ProtoBase reads the record with the default "
              "recursion limit; drop the raised limit from this script")
        return 1
    print(f"NOTE: ask B12 open: ProtoBase v2.0.0rc1 raises RecursionError on {DEPTH} nested "
          "lists at Python's default recursion limit; this test raises the limit to 20000 "
          "to read them (until ProtoBase v2.0.0rc2: non-recursive codec, MAX_VALUE_DEPTH)")
    sys.setrecursionlimit(20000)
    value, payload = read(directory)
    depth = 0
    while isinstance(value, (list, tuple)) and len(value) == 1:
        value = value[0]
        depth += 1
    if depth != DEPTH or value != 1:
        print(f"py_read_deep: expected {DEPTH} lists around 1, read {depth} around {value!r}")
        return 1
    stored = payload["s"]["v"]
    if codec.encode_value(codec.decode_value(stored, None), None) != stored:
        print("py_read_deep: the value does not re-encode to the stored form")
        return 1
    print(f"py_read_deep: {DEPTH} lists read back with the raised recursion limit")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
