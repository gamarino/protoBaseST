"""The vector indexes of protoBaseST and proto_db, node for node at the index level (vectors V3).

Usage: python py_vector_index.py make <directory>    write the shared space
       python py_vector_index.py dump <directory>    print proto_db's index dumps

numpy and hnswlib are blocked before proto_db is imported (sys.modules[...] = None, Addendum V,
5.2), so proto_db runs its pure-Python paths whatever the venv can import; maintaining an exact or
hnsw index never imports either, and the block makes that a guarantee. 'dump' writes the mode,
the CPython version and the libc (the libm that IVF training will use, V4) to stderr.

'make' writes, with proto_db, one database 'vec' whose roots hold the elements both sides index,
so that the records are the same atoms with the same oids on both sides:
  'recs'   records whose field 'vec' is a valid 3-vector (Floats, Integers, Decimals equal to
           one another with other tokens, a list, signed zeros, a subnormal, an Integer that
           rounds, a zero vector) or not one (another length, a String, a Boolean component, a
           NaN, an infinity, an Integer beyond the Float range, an overflowing norm, a Decimal
           NaN or infinity, a map), or absent; some records occur twice
  'vals'   the same keys as plain values (the element key spec), equal values with other
           tokens, repeated values, a NaN and unorderable values (lists, maps) among them
  'big'    600 records over 125 distinct small vectors, a sixth of them occurring twice:
           store trees several levels deep
  'ops'    per element set, a seeded sequence of [op, i, j] (0 adds element i, 1 removes element
           i, always one the index holds, 2 replaces element i by element j); and 'histories',
           the two invalid-tree histories of Addendum V 2.11 item 3: [build indices, added index]
           of 'recs', built with invalid elements then given another, and built without, then
           given one
'dump' (and _st_vector_index.st on the same space) prints, for each index kind of KINDS and each
(set, key spec) of SPECS, the index build makes over the set, then the index the ops derive from
the build over the set's first half; then, per kind, the two histories. Each index is printed as
'index <label>', then one line per atom reached from it, breadth first in the order the encoder
meets the references: '<number> <type name> <hex of the msgpack of the encoded state>', a saved
atom (an element) written as its own pointer, an unsaved one (a node) as the pointer (fixed
segment, its number). Equal lines are the same trees, node for node and byte for byte.
tests/interop/vector_index_identical.sh compares the two outputs.
"""
import sys

sys.modules["numpy"] = None
sys.modules["hnswlib"] = None

import platform  # noqa: E402
import random  # noqa: E402
import uuid  # noqa: E402
from decimal import Decimal  # noqa: E402

import msgpack  # noqa: E402

from proto_db import FileStorage, ObjectSpace  # noqa: E402
from proto_db.core import codec  # noqa: E402
from proto_db.core.atom import AtomPointer  # noqa: E402
from proto_db.core.dbobject import DBObject  # noqa: E402
from proto_db.indexing import KeySpec  # noqa: E402
from proto_db.indexing.vector import VectorIndex  # noqa: E402
from proto_db.indexing.vector_backends import numpy_module  # noqa: E402
from proto_db.values import FrozenDict, FrozenList  # noqa: E402

SEGMENT = uuid.UUID(bytes=bytes.fromhex("0123456789abcdef0123456789abcdef"))
SEED = 20261120
SPECS = [("recs", "path vec"), ("vals", "element"), ("big", "path vec")]
#: (label, metric, backend, params): the index kinds, each over every (set, key spec).
KINDS = [("exact-l2", "l2", "exact", {}),
         ("exact-cosine-nonumpy", "cosine", "exact", {"numpy": False}),
         ("hnsw-ip", "ip", "hnsw", {"M": 8, "seed": 3}),
         ("hnsw-cosine", "cosine", "hnsw", {})]
ABSENT = object()


def valid_keys():
    return [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (1, 2, 3), (1.0, 2.0, 3.0), FrozenList([0.5, -0.5, 0.25]),
            (Decimal("1.5"), 0, -2), (Decimal("1.50"), 0, -2), (-0.0, 0.0, 1.0), (0.0, -0.0, 1.0),
            (5e-324, 1.0, 0.0), (3, 4, 0), (2**60 + 1, 0, 0), (0, 0, 0), (1e150, 1e150, 0.0)]


def invalid_keys():
    return [None, (1.0, 2.0), "abc", (1.0, True, 0.0), (float("nan"), 0.0, 0.0), (float("inf"), 0.0, 0.0),
            (10**400, 0, 0), (1e200, 1e200, 1e200), 7, FrozenDict({"a": 1}), (Decimal("NaN"), 0, 0),
            (Decimal("Infinity"), 0, 0), (Decimal("1E+400"), 0, 0), FrozenList([1.0, FrozenList([2.0]), 3.0])]


def make(directory):
    rnd = random.Random(SEED)
    space = ObjectSpace(FileStorage(directory))
    try:
        db = space.new_database("vec")
        tx = db.new_transaction()
        valid, invalid = valid_keys(), invalid_keys()
        recs, kinds = [], []
        for i in range(70):
            r = rnd.random()
            if r < 0.6:
                recs.append(DBObject(n=i, vec=rnd.choice(valid)))
                kinds.append("valid")
            elif r < 0.9:
                recs.append(DBObject(n=i, vec=rnd.choice(invalid)))
                kinds.append("invalid")
            else:
                recs.append(DBObject(n=i))
                kinds.append("invalid")
        for i in (3, 7, 7, 11):
            recs.append(recs[i])
            kinds.append(kinds[i])
        vals = valid + invalid + [float("nan"), FrozenList([1, 0, 0]), (1, 0, 0), (1.0, 0.0, 0.0), (1, 0, 0),
                                  FrozenDict({"v": (1.0, 0.0, 0.0)}), recs[0]]
        grid = [(float(a), float(b), float(c)) for a in range(-2, 3) for b in range(-2, 3) for c in range(-2, 3)]
        big = [DBObject(n=i, vec=grid[(i * 7919) % len(grid)]) for i in range(600)]
        big += big[:100]
        sets = {"recs": recs, "vals": vals, "big": big}
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
        valid_at = [i for i, k in enumerate(kinds) if k == "valid"]
        invalid_at = [i for i, k in enumerate(kinds) if k == "invalid"]
        ops["histories"] = [[valid_at[:20] + invalid_at[:8], invalid_at[8]], [valid_at[:20], invalid_at[0]]]
        tx.set_root_object("recs", recs)
        tx.set_root_object("vals", vals)
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


def show(label, index):
    print(f"index {label}")
    for line in dump(index):
        print(line)


def run(directory):
    if numpy_module() is not None:
        raise SystemExit("numpy is importable although it was blocked")
    print(f"numpy: blocked; hnswlib: blocked; python {platform.python_version()}; "
          f"libc {' '.join(platform.libc_ver())}", file=sys.stderr)
    space = ObjectSpace(FileStorage(directory))
    try:
        tx = space.open_database("vec").new_transaction()
        sets = {name: list(tx.get_root_object(name)) for name in ("recs", "vals", "big")}
        ops = tx.get_root_object("ops")
        for kind, metric, backend, params in KINDS:
            for set_name, spec_name in SPECS:
                elements = sets[set_name]
                spec = KeySpec.element() if spec_name == "element" else KeySpec.path("vec")
                empty = VectorIndex("vi", spec, 3, metric, backend, **params)
                label = f"{kind} {set_name} {spec_name}"
                show(f"{label} build", empty.build(elements))
                index = empty.build(elements[: len(elements) // 2])
                for op, i, j in ops[f"{set_name}/{spec_name}"]:
                    if op == 0:
                        index = index.with_added(elements[i])
                    elif op == 1:
                        index = index.with_removed(elements[i])
                    else:
                        index = index.with_replaced(elements[i], elements[j])
                show(f"{label} hooks", index)
            recs = sets["recs"]
            for name, (built, added) in zip(("built with invalid", "built without invalid"), ops["histories"]):
                empty = VectorIndex("vi", KeySpec.path("vec"), 3, metric, backend, **params)
                show(f"{kind} history {name}", empty.build([recs[i] for i in built]).with_added(recs[added]))
        tx.abort()
    finally:
        space.close()
    print("end")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("make", "dump"):
        raise SystemExit("usage: py_vector_index.py make|dump <directory>")
    (make if sys.argv[1] == "make" else run)(sys.argv[2])
