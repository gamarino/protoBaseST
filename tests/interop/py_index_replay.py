"""Index maintenance in every mutator, ProtoBase's side (indexed queries, plan Task 4a, spec 6.1.2).

Usage: python py_index_replay.py make <directory>      write the shared spaces
       python py_index_replay.py replay <directory>    replay, print the dumps, commit the results
       python py_index_replay.py check <directory>     the verifier and validate() on the results

'make' writes, with ProtoBase, two spaces whose roots both sides read, so that the records are the
same atoms with the same oids on both sides:
  main, database 'idx':
    'records'  60 records: 'n' (0..59), 'v' drawn from mixed values (numbers of every type, 1 / 1.0
               / Decimal 1, strings, None, NaN, lists, maps, tuples; absent in one record in ten)
               and 'w' a small Integer
    'ops'      per collection kind (list, dict, hash, set, bag), a seeded sequence of integer
               lists: the element mutators of the kind taking turns (OPS), with random arguments,
               and the index definitions: [90, k] adds indexes()[k], [91, k] removes it
  stale, database 'idx':
    'stale'    a Dictionary of STALE_VALUES holding a format-3 index: 'eq' (the element) built over
               two of them, with member_tokens deleted (has_current_tokens() is False). A space of
               its own: the verifier validates every version it reaches, and this one does not.

'replay' (and _st_index_ops.st on a copy of the same spaces) runs each sequence from a new
collection, then on 'stale' a blind remove_at of an absent key (the stale index must stay the same
object, still stale) and a set_at (it must be rebuilt, current); every result must validate(). It
prints each resulting collection as 'collection <name>' and one line per atom reached from it that
is not saved yet, breadth first in the order the encoder meets the references: '<number> <type
name> <hex of the msgpack of the encoded state>', a saved atom written as its own pointer, an
unsaved one as the pointer (fixed segment, its number); then 'end'. Equal lines mean the same
collection and index trees, node for node and byte for byte. It commits the results as the roots
'out_<kind>' of main and as the new 'stale'.

'check' runs ProtoBase's verifier on main with the extractor registered (every record decoded and
canonical, validate() on every collection; its dump to <directory>/verify.json) and validate() on
the committed 'stale', whose index must be current (tests/interop/index_ops_identical.sh).
"""
import random
import sys
import uuid
from decimal import Decimal

import msgpack

from proto_db import FileStorage, ObjectSpace
from proto_db.collections.base import IndexSet
from proto_db.collections.dictionaries import Dictionary
from proto_db.collections.hash_dictionaries import HashDictionary
from proto_db.collections.lists import List
from proto_db.collections.sets import CountedSet, Set
from proto_db.core import codec
from proto_db.core.atom import AtomPointer
from proto_db.core.dbobject import DBObject
from proto_db.indexing import EqualityIndex, KeySpec, RangeIndex, register_extractor
from proto_db.values import FrozenDict, FrozenList

SEGMENT = uuid.UUID(bytes=bytes.fromhex("0123456789abcdef0123456789abcdef"))
SEED = 20261120
EXTRACTOR = "interop.index_ops.w"
KINDS = ["list", "dict", "hash", "set", "bag"]
#: The opcodes of each kind's element mutators, which take turns in the sequence.
OPS = {
    "list": [0, 1, 2, 3, 4, 5, 6, 7, 8],   # insert_at, append_first, append_last, set_at, remove_at,
                                           # extend, slice, head, tail
    "dict": [0, 1],                        # set_at, remove_at
    "hash": [0, 1],
    "set": [0, 1, 2, 3, 4],                # add, remove, union, intersection, difference
    "bag": [0, 0, 1],                      # add, add, remove
}
CLASSES = {"list": List, "dict": Dictionary, "hash": HashDictionary, "set": Set, "bag": CountedSet}


def indexes():
    """The index definitions the sequences add and remove by number."""
    return [EqualityIndex("eq_v", KeySpec.path("v")), RangeIndex("rg_w", KeySpec.extractor(EXTRACTOR)),
            RangeIndex("rg_v", KeySpec.path("v"))]


#: The values of the 'stale' Dictionary (keys 0..5).
STALE_VALUES = ["a", "b", "c", 1, 2.5, None]


def pool():
    return [1, 1.0, Decimal("1"), 2, 2.5, -3, 0.0, "a", "b", "é", None, True, (1, "x"),
            FrozenList([1]), FrozenDict({"a": 1}), float("nan"), Decimal("7.25"), 10**20]


def sequence(rnd, kind, size):
    """A seeded op sequence for one kind: 25 element ops, add indexes 0 and 1, 30 ops, add index 2,
    25 ops, remove index 0, 20 ops. A list's positions follow its count."""
    out = []
    count = [0]
    turn = [0]

    def element_ops(n):
        for _ in range(n):
            codes = OPS[kind]
            code = codes[turn[0] % len(codes)]
            turn[0] += 1
            r = lambda: rnd.randrange(size)  # noqa: E731
            if kind == "list":
                c = count[0]
                if code in (3, 4) and c == 0:
                    code = 2
                if code == 0:
                    out.append([0, rnd.randint(0, c), r()]); count[0] += 1
                elif code in (1, 2):
                    out.append([code, r()]); count[0] += 1
                elif code == 3:
                    out.append([3, rnd.randint(0, c - 1), r()])
                elif code == 4:
                    out.append([4, rnd.randint(0, c - 1)]); count[0] -= 1
                elif code == 5:
                    out.append([5, r(), r(), r()]); count[0] += 3
                elif code == 6:
                    lo, hi = rnd.randint(0, 1), c - rnd.randint(0, 1)
                    out.append([6, lo, hi]); count[0] = max(0, max(hi, lo) - lo)
                elif code == 7:
                    n2 = c - rnd.randint(0, 1)
                    out.append([7, n2]); count[0] = max(0, min(n2, c))
                else:
                    n2 = rnd.randint(0, 1)
                    out.append([8, n2]); count[0] = max(0, c - n2)
            elif kind in ("dict", "hash"):
                key = rnd.randrange(16)
                out.append([0, key, r()] if code == 0 else [1, key])
            elif kind == "set":
                if code in (0, 1):
                    out.append([code, r()])
                elif code == 3:
                    out.append([3] + [r() for _ in range(40)])
                else:
                    out.append([code, r(), r()])
            else:
                out.append([code, r()])

    element_ops(25)
    out += [[90, 0], [90, 1]]
    element_ops(30)
    out.append([90, 2])
    element_ops(25)
    out.append([91, 0])
    element_ops(20)
    return out


def make(directory):
    """<directory>/main: 'records' and 'ops'; <directory>/stale: the Dictionary 'stale' (plain values)
    holding a format-3 index, in a space of its own (the verifier validates every version it
    reaches, and a format-3 index does not validate)."""
    rnd = random.Random(SEED)
    space = ObjectSpace(FileStorage(f"{directory}/main"))
    try:
        tx = space.new_database("idx").new_transaction()
        values = pool()
        records = []
        for i in range(60):
            attrs = {"n": i, "w": rnd.randrange(7)}
            if rnd.random() >= 0.1:
                attrs["v"] = rnd.choice(values)
            records.append(DBObject(**attrs))
        tx.set_root_object("records", records)
        tx.set_root_object("ops", {kind: sequence(rnd, kind, len(records)) for kind in KINDS})
        tx.commit()
    finally:
        space.close()
    space = ObjectSpace(FileStorage(f"{directory}/stale"))
    try:
        tx = space.new_database("idx").new_transaction()
        stale = Dictionary()
        for i, value in enumerate(STALE_VALUES):
            stale = stale.set_at(i, value)
        stale_index = EqualityIndex("eq", KeySpec.element()).build(STALE_VALUES[:2])
        object.__delattr__(stale_index, "member_tokens")
        assert not stale_index.has_current_tokens()
        tx.set_root_object("stale", stale._with(indexes=IndexSet().with_index(stale_index)))
        tx.commit()
    finally:
        space.close()


def apply(kind, coll, op, records, defs):
    code = op[0]
    if code == 90:
        return coll.add_index(defs[op[1]])
    if code == 91:
        return coll.remove_index(defs[op[1]].name)
    rec = lambda k: records[op[k]]  # noqa: E731
    if kind == "list":
        if code == 0:
            return coll.insert_at(op[1], rec(2))
        if code == 1:
            return coll.append_first(rec(1))
        if code == 2:
            return coll.append_last(rec(1))
        if code == 3:
            return coll.set_at(op[1], rec(2))
        if code == 4:
            return coll.remove_at(op[1])
        if code == 5:
            return coll.extend([rec(1), rec(2), rec(3)])
        if code == 6:
            return coll.slice(op[1], op[2])
        if code == 7:
            return coll.head(op[1])
        return coll.tail(op[1])
    if kind in ("dict", "hash"):
        return coll.set_at(op[1], rec(2)) if code == 0 else coll.remove_at(op[1])
    if kind == "set":
        if code == 0:
            return coll.add(rec(1))
        if code == 1:
            return coll.remove(rec(1))
        if code == 2:
            return coll.union([rec(1), rec(2)])
        if code == 3:
            return coll.intersection([records[i] for i in op[1:]])
        return coll.difference([rec(1), rec(2)])
    return coll.add(rec(1)) if code == 0 else coll.remove(rec(1))


def dump(root):
    numbers = {id(root): 0}
    keep = [root]
    queue = [root]
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


def replay(directory):
    register_extractor(EXTRACTOR, lambda e: KeySpec.path("w").extract(e), version="1")
    results = []
    space = ObjectSpace(FileStorage(f"{directory}/main"))
    try:
        tx = space.open_database("idx").new_transaction()
        records = list(tx.get_root_object("records"))
        ops = tx.get_root_object("ops")
        defs = indexes()
        for kind in KINDS:
            coll = CLASSES[kind]()
            for op in ops[kind]:
                coll = apply(kind, coll, list(op), records, defs)
            coll.validate()
            results.append((kind, coll))
            tx.set_root_object(f"out_{kind}", coll)
        print_dumps(results)
        tx.commit()
    finally:
        space.close()
    space = ObjectSpace(FileStorage(f"{directory}/stale"))
    try:
        tx = space.open_database("idx").new_transaction()
        stale = tx.get_root_object("stale")
        before = stale.get_index("eq")
        if before.has_current_tokens():
            raise SystemExit("the stale index reads as current")
        blind = stale.remove_at(30)
        if blind.get_index("eq") is not before:
            raise SystemExit("a blind write rebuilt the stale index")
        changed = blind.set_at(7, "h")
        if not changed.get_index("eq").has_current_tokens():
            raise SystemExit("the first change did not rebuild the stale index")
        changed.validate()
        print_dumps([("stale", changed)])
        tx.set_root_object("stale", changed)
        tx.commit()
    finally:
        space.close()
    print("end")


def print_dumps(results):
    for name, coll in results:
        print(f"collection {name}")
        for line in dump(coll):
            print(line)


def check(directory):
    """ProtoBase's verifier on <directory>/main, with the extractor registered (exit status as the
    verifier's, its dump to <directory>/verify.json), then validate() of the current 'stale' of
    <directory>/stale, whose index must be current."""
    from proto_db.tools.verify import main as verify_main
    register_extractor(EXTRACTOR, lambda e: KeySpec.path("w").extract(e), version="1")
    status = verify_main([f"{directory}/main", "--out", f"{directory}/verify.json"])
    if status != 0:
        return status
    space = ObjectSpace(FileStorage(f"{directory}/stale"))
    try:
        tx = space.open_database("idx").new_transaction()
        stale = tx.get_root_object("stale")
        stale.validate()
        if not stale.get_index("eq").has_current_tokens() or stale.get_index("eq").total_count != len(STALE_VALUES) + 1:
            print("FAILED the committed 'stale' does not hold the rebuilt index", file=sys.stderr)
            return 1
        tx.abort()
    finally:
        space.close()
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("make", "replay", "check"):
        raise SystemExit("usage: py_index_replay.py make|replay|check <directory>")
    if sys.argv[1] == "check":
        sys.exit(check(sys.argv[2]))
    (make if sys.argv[1] == "make" else replay)(sys.argv[2])
