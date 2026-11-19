"""The index trees of protoBaseST and ProtoBase, node for node (indexed queries, plan Task 3).

Usage: python py_index_build.py make <directory>    write the shared space
       python py_index_build.py dump <directory>    print ProtoBase's index dumps

'make' writes, with ProtoBase, one database 'idx' whose roots hold the elements both sides index,
so that the records are the same atoms with the same oids on both sides:
  'values'   plain values and records (the element key spec): duplicates; 1, 1.0, Decimal 1 and
             Decimal 1.00; equal instants written in different offsets; strings, bytes, dates,
             tuples, nil and the Booleans; the unorderable values (NaN, lists, maps, a tuple
             holding a list), which go to the side group
  'records'  records whose field 'v' is drawn from those values, absent or nil, and whose field
             'w' is a small Integer (the path 'v' and the extractor 'interop.index_build.w');
             some records occur twice
  'big'      2500 records over about 40 distinct ages (Integers and Floats, a fifth of them
             occurring twice): groups and member trees several levels deep
  'ops'      per element set, a seeded sequence of [op, i, j]: 0 adds element i, 1 removes
             element i (always one the index holds), 2 replaces element i by element j
'dump' (and _st_index_build.st on the same space) builds, for EqualityIndex and RangeIndex and
for each (set, key spec) of SPECS, the index by build over the set, then the index the ops
derive from the build over the set's first half, and prints each as lines: 'index <label>', then
one line per atom reached from the index, breadth first in the order the encoder meets the
references: '<number> <type name> <hex of the msgpack of the encoded state>', where a saved atom
(an element) is written as its own pointer and an unsaved one (a node, a value box) as the
pointer (fixed segment, its number). Equal lines mean the same trees, node for node and byte for
byte. tests/interop/index_build_identical.sh compares the two outputs.
"""
import random
import sys
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal

import msgpack

from proto_db import FileStorage, ObjectSpace
from proto_db.core import codec
from proto_db.core.atom import AtomPointer
from proto_db.core.dbobject import DBObject
from proto_db.indexing import EqualityIndex, KeySpec, RangeIndex, register_extractor
from proto_db.values import FrozenDict, FrozenList

SEGMENT = uuid.UUID(bytes=bytes.fromhex("0123456789abcdef0123456789abcdef"))
SEED = 20261119
EXTRACTOR = "interop.index_build.w"
SPECS = [("values", "element"), ("records", "path v"), ("records", "extractor"), ("big", "path v")]


def spec_of(name):
    if name == "element":
        return KeySpec.element()
    if name == "path v":
        return KeySpec.path("v")
    return KeySpec.extractor(EXTRACTOR)


def plain_values():
    utc = timezone.utc
    return [
        1, 1, 1.0, Decimal("1"), Decimal("1.00"), 2, 2.5, -3, 0.0, -0.0, 10**20,
        "a", "a", "b", "é", b"x", None, True, False, date(2026, 1, 2),
        datetime(2026, 1, 1, 12, tzinfo=utc),
        datetime(2026, 1, 1, 9, tzinfo=timezone(timedelta(hours=-3))),
        datetime(2026, 1, 1, 17, tzinfo=timezone(timedelta(hours=5))),
        (1, "x"), (1.0, "x"),
        FrozenList([1]), FrozenList([1.0]), FrozenList([1]),
        FrozenDict({"a": 1}), FrozenDict({"a": 1.0, "b": 2}), float("nan"), float("nan"),
        (FrozenList([2]), 1),
    ]


def make(directory):
    rnd = random.Random(SEED)
    space = ObjectSpace(FileStorage(directory))
    try:
        db = space.new_database("idx")
        tx = db.new_transaction()
        pool = plain_values()
        records = []
        for i in range(60):
            attrs = {"n": i, "w": rnd.randrange(5)}
            r = rnd.random()
            if r < 0.8:
                attrs["v"] = rnd.choice(pool)
            elif r < 0.9:
                attrs["v"] = None
            records.append(DBObject(**attrs))
        records += [records[3], records[7], records[7]]
        values = pool + records[:6] + [records[2]]
        big = []
        for i in range(2500):
            age = (i * 7919) % 41 + (0.5 if i % 7 == 0 else 0)
            big.append(DBObject(n=i, v=age))
        big += big[:500]
        sets = {"values": values, "records": records, "big": big}
        ops = {}
        for set_name, spec in SPECS:
            elements = sets[set_name]
            held = list(range(len(elements) // 2))
            seq = []
            for _ in range(60):
                r = rnd.random()
                if not held or r < 0.45:
                    i = rnd.randrange(len(elements))
                    seq.append([0, i, 0])
                    held.append(i)
                elif r < 0.75:
                    i = held.pop(rnd.randrange(len(held)))
                    seq.append([1, i, 0])
                else:
                    k = rnd.randrange(len(held))
                    j = rnd.randrange(len(elements))
                    seq.append([2, held[k], j])
                    held[k] = j
            ops[f"{set_name}/{spec}"] = seq
        tx.set_root_object("values", values)
        tx.set_root_object("records", records)
        tx.set_root_object("big", big)
        tx.set_root_object("ops", ops)
        tx.commit()
    finally:
        space.close()


def dump(index):
    numbers = {id(index): 0}
    keep = [index]
    queue = [index]
    lines = []
    while queue:
        atom = queue.pop(0)

        def save_child(child):
            if child.atom_pointer is not None:
                return child.atom_pointer
            if id(child) not in numbers:
                numbers[id(child)] = len(numbers)
                keep.append(child)
                queue.append(child)
            return AtomPointer(SEGMENT, numbers[id(child)])

        encoded = codec.encode_state(atom._state(), save_child)
        lines.append(f"{numbers[id(atom)]} {type(atom).__type_name__} {msgpack.packb(encoded).hex()}")
    return lines


def run(directory):
    register_extractor(EXTRACTOR, lambda e: KeySpec.path("w").extract(e), version="1")
    space = ObjectSpace(FileStorage(directory))
    try:
        tx = space.open_database("idx").new_transaction()
        sets = {name: list(tx.get_root_object(name)) for name in ("values", "records", "big")}
        ops = tx.get_root_object("ops")
        for set_name, spec_name in SPECS:
            elements = sets[set_name]
            seq = ops[f"{set_name}/{spec_name}"]
            for kind in (EqualityIndex, RangeIndex):
                empty = kind("idx", spec_of(spec_name))
                label = f"{kind.__name__} {set_name} {spec_name}"
                print(f"index {label} build")
                for line in dump(empty.build(elements)):
                    print(line)
                index = empty.build(elements[: len(elements) // 2])
                for op, i, j in seq:
                    if op == 0:
                        index = index.with_added(elements[i])
                    elif op == 1:
                        index = index.with_removed(elements[i])
                    else:
                        index = index.with_replaced(elements[i], elements[j])
                print(f"index {label} hooks")
                for line in dump(index):
                    print(line)
        tx.abort()
    finally:
        space.close()
    print("end")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("make", "dump"):
        raise SystemExit("usage: py_index_build.py make|dump <directory>")
    (make if sys.argv[1] == "make" else run)(sys.argv[2])
