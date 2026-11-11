"""Read the 509-deep attribute that _st_deep_space.st writes, with ProtoBase (plan Task 13).

Usage: python py_read_deep.py <directory>

ProtoBase decodes nested lists recursively, two Python frames per level, so with
Python's default recursion limit (1000) its reader raises RecursionError on this record
(it does from about 333 nested lists; a ProtoBase limit, reported, not a defect of the
record). The script records that outcome, then raises the limit and reads the record:
the value must be 509 lists around 1, and its canonical encoding must be the bytes stored.
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
        default = "read"
    except RecursionError:
        default = "RecursionError"
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
    print(f"py_read_deep: {DEPTH} lists read back (default recursion limit: {default})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
