"""ProtoBase's side of st_deep_to_py.sh: read the values at the nesting limit protoST wrote.

Usage: python py_read_deep.py <directory>

<directory> is what _st_deep_space.st writes (format spec v2.0.0rc2, "Value nesting depth":
MAX_VALUE_DEPTH = 1022 MessagePack containers per attribute value):

- space/: every root reads back with Python's default recursion limit: 'deep' and 'keyed'
  hold values exactly 1022 containers deep, and each re-encodes to the bytes stored in its
  record; the collections hold their elements, and every record of the space is at most
  1022 deep in each attribute (the stored node values of the Set and the HashDictionary
  are exactly 1022);
- over/: the root 'over' holds a value of 1023 lists (raw bytes): reading it raises
  ProtoCorruptionError;
- ProtoBase's writer refuses a value one container deeper than each limit with
  ProtoValidationError naming MAX_VALUE_DEPTH, as protoST's does, and with the very text
  protoST's unit tests expect (SAME_TEXT).

Exit 0 when every check holds, 1 otherwise (each failed check is printed).
"""
import sys

from proto_db import DBObject, Dictionary, FileStorage, HashDictionary, List, ObjectSpace, Set
from proto_db.core import codec
from proto_db.errors import ProtoCorruptionError, ProtoValidationError
from proto_db.values import MAX_VALUE_DEPTH, value_depth

FAILURES = []


def check(label, actual, expected):
    if actual != expected:
        FAILURES.append(f"{label}: expected {expected!r}, got {actual!r}")


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


def read_space(directory):
    space = ObjectSpace(FileStorage(directory))
    try:
        tx = space.open_database("db").new_transaction()
        for name in ("deep", "keyed"):
            record = tx.get_root_object(name)
            check(f"{name}: the depth of v", value_depth(record.v), MAX_VALUE_DEPTH)
            stored = space.storage.get_atom(record.atom_pointer)["s"]["v"]
            check(f"{name}: v re-encodes to the stored bytes",
                  codec.encode_value(codec.decode_value(stored, None), None) == stored, True)
        check("deep: the value", record_value(tx, "deep"), lists(1022))
        check("the List element", [value_depth(e) for e in tx.get_root_object("list")], [1022])
        d = tx.get_root_object("dict")
        check("the Dictionary", [(value_depth(k), value_depth(v)) for k, v in d.items()], [(1022, 1022)])
        check("the Set", [value_depth(e) for e in tx.get_root_object("set")], [1020])
        h = tx.get_root_object("hash")
        check("the HashDictionary", [(value_depth(k), value_depth(v)) for k, v in h.items()], [(1018, 1018)])
        for name, label in (("set", "the Set's bucket"), ("hash", "the HashDictionary's bucket")):
            root = tx.get_root_object(name).root
            check(f"{label} node value", value_depth(root.value), MAX_VALUE_DEPTH)
        tx.abort()
    finally:
        space.close()


def record_value(tx, name):
    return tx.get_root_object(name).v


def read_over(directory):
    space = ObjectSpace(FileStorage(directory))
    try:
        tx = space.open_database("db").new_transaction()
        try:
            value = tx.get_root_object("over").v
        except ProtoCorruptionError:
            pass
        else:
            FAILURES.append(f"over: a value 1023 deep was read ({value_depth(value)} containers)")
        tx.abort()
    finally:
        space.close()


def check_refusals():
    refusals = {
        "a DBObject field of 1023": lambda: DBObject(v=lists(1023)),
        "a List element of 1023": lambda: List().append_last(lists(1023)),
        "a Dictionary value of 1023": lambda: Dictionary().set_at(1, lists(1023)),
        "a Set element of 511 tuples": lambda: Set().add(tuples(511)),
        "a HashDictionary key of 510 tuples": lambda: HashDictionary().set_at(tuples(510), 1),
    }
    for label, build in refusals.items():
        try:
            build()
        except ProtoValidationError as e:
            if "MAX_VALUE_DEPTH" not in str(e):
                FAILURES.append(f"{label}: refused without naming MAX_VALUE_DEPTH: {e}")
        else:
            FAILURES.append(f"{label}: ProtoBase's writer accepted it")


#: The refusal texts tests/unit/tx_atom_depth.st and collection_depth.st expect from protoST's
#: writer, word for word (protoST names its own class, PBSet, where ProtoBase says Set).
SAME_TEXT = {
    "a DBObject field of 1023": (
        lambda: DBObject(v=lists(1023)),
        "Field 'v' of proto_db.core.dbobject.DBObject: The value nests deeper than MAX_VALUE_DEPTH = 1022 "
        "MessagePack containers, the most the storage format allows (format spec, \"Value nesting depth\")"),
    "a Set element of 511 tuples": (
        lambda: Set().add(tuples(511)),
        "Set element nests 1022 MessagePack containers deep, and its bucket tuple adds 2 around it, so it "
        "may nest at most 1020 (MAX_VALUE_DEPTH = 1022, format spec \"Value nesting depth\")"),
}


def check_texts():
    for label, (build, text) in SAME_TEXT.items():
        try:
            build()
        except ProtoValidationError as e:
            check(f"{label}: the refusal text", str(e), text)
        else:
            FAILURES.append(f"{label}: ProtoBase's writer accepted it")


def main(directory: str) -> int:
    check("MAX_VALUE_DEPTH", MAX_VALUE_DEPTH, 1022)
    check("Python's recursion limit is the default", sys.getrecursionlimit(), 1000)
    read_space(f"{directory}/space")
    read_over(f"{directory}/over")
    check_refusals()
    check_texts()
    for failure in FAILURES:
        print(f"py_read_deep: {failure}")
    if FAILURES:
        return 1
    print("py_read_deep: values at the limit read back, 1023 refused when read and when written")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
