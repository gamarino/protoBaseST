"""ProtoBase's side of py_deep_to_st.sh: write values at the nesting limit for protoST to read.

Usage: python py_write_deep.py <directory>

Writes, through ProtoBase's public API, the database 'db' whose roots are the shapes
_st_deep_space.st writes (format spec v2.0.0rc2, "Value nesting depth": MAX_VALUE_DEPTH = 1022
MessagePack containers per attribute value): 'deep' (a DBObject whose 'v' is 1022 lists around
1), 'keyed' (a DBObject whose 'v' is a list around a map whose key is 509 tuples around 1),
'list' (a List whose element is 1022 lists), 'dict' (a Dictionary from 511 tuples to 1022
lists), 'set' (a Set of 510 tuples) and 'hash' (a HashDictionary from 509 tuples to 1018
lists). Python's recursion limit stays the default. Exit 0 once committed.
"""
import sys

from proto_db import DBObject, Dictionary, FileStorage, HashDictionary, List, ObjectSpace, Set


def lists(n):
    v = 1
    for _ in range(n):
        v = [v]
    return v


def tuples(n):
    v = 1
    for _ in range(n):
        v = (v,)
    return v


def main(directory: str) -> int:
    space = ObjectSpace(FileStorage(directory))
    try:
        tx = space.new_database("db").new_transaction()
        tx.set_root_object("deep", DBObject(v=lists(1022)))
        tx.set_root_object("keyed", DBObject(v=[{tuples(509): "v"}]))
        tx.set_root_object("list", List().append_last(lists(1022)))
        tx.set_root_object("dict", Dictionary().set_at(tuples(511), lists(1022)))
        tx.set_root_object("set", Set().add(tuples(510)))
        tx.set_root_object("hash", HashDictionary().set_at(tuples(509), lists(1018)))
        tx.commit()
    finally:
        space.close()
    print("py_write_deep: written")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
