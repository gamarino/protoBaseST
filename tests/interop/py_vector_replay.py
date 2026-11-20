"""Collections holding vector indexes, written and merged: proto_db's side (vectors phase V5,
Addendum V 2.10, 2.11 and 5.2).

Usage: python py_vector_replay.py make <directory>     write the shared spaces
       python py_vector_replay.py replay <directory>   replay, print the dumps, commit the results
       python py_vector_replay.py check <directory>    the verifier and validate() on the results
       python py_vector_replay.py write <directory>    vector_both_directions.sh: write a space
       python py_vector_replay.py change <directory>   vector_both_directions.sh: change it
       python py_vector_replay.py verify <directory>   vector_both_directions.sh: validate and query

make, replay and check (tests/interop/vector_ops_identical.sh) block numpy and hnswlib before
proto_db is imported (sys.modules[...] = None, Addendum V 5.2), so IVF training takes proto_db's
pure-Python k-means (deviation DV3) whatever the venv holds. write, change and verify
(tests/interop/vector_both_directions.sh) run in proto_db's default mode: they import numpy when
the venv has it (tests/interop/.venv-numpy). Every mode writes its mode line to stderr: 'numpy:
blocked' or 'numpy: <version>', the CPython version and the libc (platform.libc_ver(), the libm of
the pure path's pow).

'make' writes, with proto_db, two spaces whose roots both sides read, so that the records are the
same atoms with the same oids on both sides:
  main, database 'vec':
    'records'  60 records: 'n' (0..59) and 'vec' drawn from VALID (3-vectors of Floats, Integers,
               Decimals, a list, signed zeros) or INVALID (another length, a String, None, a NaN,
               a map), absent in one record in ten
    'ops'      per collection kind (list, dict, hash, set, bag), a seeded sequence of integer
               lists: the element mutators of the kind taking turns (OPS), with random arguments,
               and the index definitions: [90, k] adds indexes()[k], [91, k] removes it. Index 2
               (ivf_flat, nlist 3, retrain_growth 1.5) is added to the empty collection first, so
               the sequence trains it and retrains it again and again; indexes 0 (exact) and 1
               (hnsw) after 25 operations, index 3 (ivf_flat, nlist 4) after 55, over the
               elements already held (build: trains it once); index 0 is removed after 80
  legacy:      a copy of the conformance vector tests/conformance/vectors/legacy (proto_db's
               format-3 space): its root 'vectors' is a List holding the format-3 exact index
               'near'. A space of its own: its other roots are misfiled on purpose (D58), so the
               verifier does not run on it.

'replay' (and _st_vector_ops.st on a copy of the same spaces) runs each sequence from a new
collection, validates it, then rebases a fixed blind write of a dictionary, a hash dictionary and a
counted set (merge_log: element writes and removals, addIndex: of an ivf_flat index, a temporary
index added and removed, a redefinition) onto the replayed collection of its kind, which holds
vector indexes ('merged_<kind>'), and validates the answer. On legacy it changes 'vectors' by a
blind extend of nothing (its format-3 index must stay the same object) and an append_last of its
first element (the index must be rebuilt, current: rebuilt_stale), validated. It prints each
resulting collection as 'collection <name>' and one line per atom reached from it that is not
saved yet, breadth first in the order the encoder meets the references: '<number> <type name> <hex
of the msgpack of the encoded state>' (py_index_replay.py's dump); then 'end'. Equal lines mean the
same collection and index trees, node for node and byte for byte, centroids included. It commits
the results as the roots 'out_<kind>' and 'merged_<kind>' of main, and the new 'vectors' of legacy.

'check' runs proto_db's verifier on main (every record decoded and canonical, validate() on every
collection; its dump to <directory>/verify.json) and validate() on the committed 'vectors' of
legacy, whose index must be current.

'write' writes a new space, database 'bd': 'records' (40 records, 'vec' a 3-vector or not, from
a fixed formula) and the roots 'list', 'dict', 'hash', 'set' and 'bag', each the collection of its
kind built through its mutators with the three indexes of BD_INDEXES (exact cosine, hnsw l2,
ivf_flat l2 trained and retrained), committed. 'change' opens such a space (written by either
implementation), runs every mutator of each kind on its root (bd_changes), adds and removes an
index, commits, then makes two transactions blind-write 'dict' and 'bag' (new collections, the
roots never read) and commits both: the second commit merges onto the vector-indexed current, and
its four new members take each ivf index from 28 to 32, past 1.5 times its trained size of 21, so
that merge retrains it over the other writer's centroids; 'change' refuses a merge that did not
and prints each root's trained sizes before and after.
'verify' validates every root and, for the exact index and for the ivf_flat index probed in full
(nprobe = nlist, the exact answer), runs near queries and compares them with near_oracle; it
prints one summary line per root.
"""
import sys

MODE = sys.argv[1] if len(sys.argv) > 1 else ""
if MODE in ("make", "replay", "check"):
    sys.modules["numpy"] = None
    sys.modules["hnswlib"] = None

import platform  # noqa: E402
import random  # noqa: E402
import shutil  # noqa: E402
import uuid  # noqa: E402
from decimal import Decimal  # noqa: E402
from pathlib import Path  # noqa: E402

import msgpack  # noqa: E402

from proto_db import FileStorage, ObjectSpace  # noqa: E402
from proto_db.collections.dictionaries import Dictionary  # noqa: E402
from proto_db.collections.hash_dictionaries import HashDictionary  # noqa: E402
from proto_db.collections.lists import List  # noqa: E402
from proto_db.collections.sets import CountedSet, Set  # noqa: E402
from proto_db.core import codec  # noqa: E402
from proto_db.core.atom import AtomPointer  # noqa: E402
from proto_db.core.dbobject import DBObject  # noqa: E402
from proto_db.indexing import KeySpec  # noqa: E402
from proto_db.indexing.vector import VectorIndex, near_oracle  # noqa: E402
from proto_db.indexing.vector_backends import numpy_module  # noqa: E402
from proto_db.query.terms import NEAR, NearQuery, Term  # noqa: E402
from proto_db.values import FrozenDict, FrozenList  # noqa: E402

HERE = Path(__file__).resolve().parent
LEGACY = HERE.parent / "conformance" / "vectors" / "legacy"
SEGMENT = uuid.UUID(bytes=bytes.fromhex("0123456789abcdef0123456789abcdef"))
SEED = 20261121
KINDS = ["list", "dict", "hash", "set", "bag"]
#: The opcodes of each kind's element mutators, which take turns in the sequence.
OPS = {
    "list": [0, 1, 2, 3, 4, 5, 6, 7, 8],   # insert_at, append_first, append_last, set_at, remove_at,
                                           # extend, slice, head, tail
    "dict": [0, 0, 1],                     # set_at, set_at, remove_at
    "hash": [0, 0, 1],
    "set": [0, 1, 0, 2, 3, 4],             # add, remove, add, union, intersection, difference
    "bag": [0, 0, 1],                      # add, add, remove
}
CLASSES = {"list": List, "dict": Dictionary, "hash": HashDictionary, "set": Set, "bag": CountedSet}


def mode_line():
    """The mode of this process (Addendum V 5.2): numpy blocked or its version, CPython, libc."""
    np = numpy_module()
    numpy_text = "blocked" if sys.modules.get("numpy", 0) is None else (
        "absent" if np is None else np.__version__)
    return f"numpy: {numpy_text}; CPython {platform.python_version()}; libc {' '.join(platform.libc_ver())}"


def indexes():
    """The index definitions the sequences add and remove by number."""
    return [VectorIndex("exact", "vec", 3, "cosine"),
            VectorIndex("hnsw", "vec", 3, "ip", "hnsw", M=4, seed=3),
            VectorIndex("ivf", "vec", 3, "l2", "ivf_flat", nlist=3, retrain_growth=1.5, train_iters=3, seed=5),
            VectorIndex("ivf4", "vec", 3, "cosine", "ivf_flat", nlist=4, nprobe=2, seed=11)]


def valid():
    return [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (1, 2, 3), (1.0, 2.0, 3.0),
            FrozenList([0.5, -0.5, 0.25]), (Decimal("1.5"), 0, -2), (Decimal("1.50"), 0, -2), (-0.0, 0.0, 1.0),
            (3, 4, 0), (0.9, 0.1, 0.0), (-1.0, 0.5, 2.0), (2.0, 2.0, 2.0), (0.1, 0.2, 0.3)]


def invalid():
    return [None, (1.0, 2.0), "abc", (float("nan"), 0.0, 0.0), FrozenDict({"a": 1})]


def sequence(rnd, kind, size):
    """A seeded op sequence for one kind: add index 2, 25 element ops, add indexes 0 and 1, 30 ops,
    add index 3, 25 ops, remove index 0, 20 ops. A list's positions follow its count."""
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
                if code in (3, 4, 6, 7, 8) and c == 0:
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
                key = rnd.randrange(24)
                out.append([0, key, r()] if code == 0 else [1, key])
            elif kind == "set":
                if code in (0, 1):
                    out.append([code, r()])
                elif code == 3:
                    out.append([3] + [r() for _ in range(45)])
                else:
                    out.append([code, r(), r()])
            else:
                out.append([code, r()])

    out.append([90, 2])
    element_ops(25)
    out += [[90, 0], [90, 1]]
    element_ops(30)
    out.append([90, 3])
    element_ops(25)
    out.append([91, 0])
    element_ops(20)
    return out


def make(directory):
    rnd = random.Random(SEED)
    space = ObjectSpace(FileStorage(f"{directory}/main"))
    try:
        tx = space.new_database("vec").new_transaction()
        good, bad = valid(), invalid()
        records = []
        for i in range(60):
            r = rnd.random()
            attrs = {"n": i}
            if r < 0.75:
                attrs["vec"] = rnd.choice(good)
            elif r < 0.9:
                attrs["vec"] = rnd.choice(bad)
            records.append(DBObject(**attrs))
        tx.set_root_object("records", records)
        tx.set_root_object("ops", {kind: sequence(rnd, kind, len(records)) for kind in KINDS})
        tx.commit()
    finally:
        space.close()
    shutil.copytree(LEGACY, f"{directory}/legacy")


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


#: The kinds whose replayed collection is also the vector-indexed current of a merge.
MERGE_KINDS = ["dict", "hash", "bag"]


def merge_log(kind, records):
    """A blind write of kind, built from new (a complete log), that 'replay' rebases onto the
    replayed collection of that kind, which holds the indexes hnsw, ivf and ivf4: an ivf_flat index
    'late' (nlist 2) added, element writes over several keys with removals, an index 'tmp' added,
    'late' removed and added again as an exact index (a redefinition), 'tmp' removed (created then
    removed: the current keeps nothing of it)."""
    coll = CLASSES[kind]().add_index(VectorIndex("late", "vec", 3, "l2", "ivf_flat", nlist=2, seed=1))
    if kind in ("dict", "hash"):
        coll = coll.set_at(3, records[40]).set_at(17, records[41]).remove_at(5).set_at(3, records[42])
        coll = coll.remove_at(9).set_at(21, records[43]).set_at(30, records[44]).set_at(31, records[45])
    else:
        coll = coll.add(records[40]).add(records[40]).add(records[41]).remove(records[40])
        for i in range(3):
            coll = coll.remove(records[i])
        coll = coll.add(records[42]).add(records[43]).add(records[44])
    coll = coll.add_index(VectorIndex("tmp", "vec", 3, "cosine", "hnsw"))
    coll = coll.remove_index("late").add_index(VectorIndex("late", "vec", 3, "l2", "exact"))
    return coll.remove_index("tmp")


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


def print_dumps(results):
    for name, coll in results:
        print(f"collection {name}")
        for line in dump(coll):
            print(line)


def replay(directory):
    results = []
    space = ObjectSpace(FileStorage(f"{directory}/main"))
    try:
        tx = space.open_database("vec").new_transaction()
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
        currents = dict(results)
        for kind in MERGE_KINDS:
            merged = merge_log(kind, records).rebase_onto(currents[kind])
            merged.validate()
            results.append((f"merged_{kind}", merged))
            tx.set_root_object(f"merged_{kind}", merged)
        print_dumps(results)
        tx.commit()
    finally:
        space.close()
    space = ObjectSpace(FileStorage(f"{directory}/legacy"))
    try:
        tx = space.open_database("db").new_transaction()
        old = tx.get_root_object("vectors")
        before = old.get_index("near")
        if before.has_current_tokens():
            raise SystemExit("the format-3 vector index reads as current")
        blind = old.extend([])
        if blind.get_index("near") is not before:
            raise SystemExit("a blind change rebuilt the format-3 vector index")
        changed = old.append_last(old.get_at(0))
        if not changed.get_index("near").has_current_tokens():
            raise SystemExit("the first change did not rebuild the format-3 vector index")
        changed.validate()
        print_dumps([("legacy_vectors", changed)])
        tx.set_root_object("vectors", changed)
        tx.commit()
    finally:
        space.close()
    print("end")


def check(directory):
    """proto_db's verifier on <directory>/main (exit status as the verifier's, its dump to
    <directory>/verify.json), then validate() of the committed 'vectors' of <directory>/legacy,
    whose index must be current."""
    from proto_db.tools.verify import main as verify_main
    status = verify_main([f"{directory}/main", "--out", f"{directory}/verify.json"])
    if status != 0:
        return status
    space = ObjectSpace(FileStorage(f"{directory}/legacy"))
    try:
        tx = space.open_database("db").new_transaction()
        vectors = tx.get_root_object("vectors")
        vectors.validate()
        index = vectors.get_index("near")
        if not index.has_current_tokens() or index.total_count != 4:
            print("FAILED the committed 'vectors' does not hold the rebuilt index", file=sys.stderr)
            return 1
        tx.abort()
    finally:
        space.close()
    return 0


# -- both directions (tests/interop/vector_both_directions.sh) ------------------------------------

#: The indexes of the roots 'write' makes: exact cosine, hnsw l2, ivf_flat l2 (trained at 4
#: members, retrained at 6, 9, 14, ...).
def bd_indexes():
    return [VectorIndex("exact", "vec", 3, "cosine"),
            VectorIndex("hnsw", "vec", 3, "l2", "hnsw"),
            VectorIndex("ivf", "vec", 3, "l2", "ivf_flat", nlist=4, retrain_growth=1.5, train_iters=4, seed=9)]


def bd_vec(i):
    """The key of record i: a 3-vector of Floats, Integers or a Decimal, or (every seventh) not a
    3-vector. The same formula in _st_vector_ops.st."""
    if i % 7 == 3:
        return (float(i), 1.0) if i % 2 else "none"
    if i % 3 == 0:
        return (i % 5, (i * 3) % 7 - 3, 1)
    if i % 3 == 1:
        return (i / 8, 1.0 - i / 16, (i % 4) * 0.5)
    return (Decimal(i) / Decimal(4), 0.5, -1.0)


def bd_record(i):
    return DBObject(n=i, vec=bd_vec(i))


def bd_build(kind, records):
    """The collection of kind holding the BD_INDEXES, built through its mutators over records."""
    coll = CLASSES[kind]()
    for index in bd_indexes():
        coll = coll.add_index(index)
    for i, r in enumerate(records):
        if kind == "list":
            coll = coll.append_last(r) if i % 2 else coll.append_first(r)
        elif kind in ("dict", "hash"):
            coll = coll.set_at(i, r)
        else:
            coll = coll.add(r)
    return coll


def write(directory):
    print(mode_line(), file=sys.stderr)
    space = ObjectSpace(FileStorage(directory))
    try:
        tx = space.new_database("bd").new_transaction()
        records = [bd_record(i) for i in range(40)]
        tx.set_root_object("records", records)
        for kind in KINDS:
            tx.set_root_object(kind, bd_build(kind, records[:30]))
        tx.commit()
    finally:
        space.close()


def bd_changes(kind, coll, records, extra):
    """Every mutator of kind on coll (records: the 40 stored, extra: 4 new ones), then addIndex: of
    an exact l2 index 'added' and removeIndex: of 'hnsw' (the same in _st_vector_ops.st)."""
    if kind == "list":
        coll = coll.insert_at(2, extra[0]).append_first(extra[1]).append_last(records[35])
        coll = coll.set_at(4, records[36]).remove_at(0).extend([records[37], extra[2], records[3]])
        coll = coll.slice(1, coll.count)
        coll = coll.head(coll.count - 1)
        coll = coll.tail(1).append_last(extra[3])
    elif kind in ("dict", "hash"):
        coll = coll.set_at(100, extra[0]).set_at(3, extra[1]).remove_at(4).remove_at(999)
        coll = coll.set_at(101, records[38]).set_at(102, extra[2]).set_at(103, extra[3])
    elif kind == "set":
        coll = coll.add(extra[0]).remove(records[2]).union([extra[1], records[36]])
        coll = coll.intersection(list(coll)[:-2] + [extra[2]]).difference([records[5]]).add(extra[3])
    else:
        coll = coll.add(extra[0]).add(records[1]).remove(records[2]).add(extra[1]).add(extra[2]).add(extra[3])
    return coll.add_index(VectorIndex("added", "vec", 3, "l2")).remove_index("hnsw")


def change(directory):
    print(mode_line(), file=sys.stderr)
    space = ObjectSpace(FileStorage(directory))
    try:
        db = space.open_database("bd")
        tx = db.new_transaction()
        records = list(tx.get_root_object("records"))
        extra = [bd_record(100 + i) for i in range(4)]
        for kind in KINDS:
            tx.set_root_object(kind, bd_changes(kind, tx.get_root_object(kind), records, extra))
        tx.commit()
        before = trained_sizes(db)
        a, b = db.new_transaction(), db.new_transaction()
        dict_a = a.new_dictionary()
        for i in range(200, 204):
            dict_a = dict_a.set_at(i, bd_record(i))
        a.set_root_object("dict", dict_a)
        a.set_root_object("bag", a.new_counted_set().add(bd_record(202)).add(bd_record(203))
                          .add(bd_record(204)).add(bd_record(205)).add(records[10]))
        b.set_root_object("dict", b.new_dictionary().set_at(210, bd_record(210)).remove_at(100))
        b.set_root_object("bag", b.new_counted_set().add(bd_record(211)).remove(records[11]))
        b.commit()
        a.commit()
        after = trained_sizes(db)
        for kind in ("dict", "bag"):
            if after[kind] == before[kind]:
                raise SystemExit(f"{kind}: the merge did not retrain the ivf index (trained size {before[kind]})")
            print(f"merged {kind}: ivf trained size {before[kind]} -> {after[kind]}")
    finally:
        space.close()


def trained_sizes(db):
    """The trained size of the ivf index of 'dict' and 'bag' in the current version."""
    tx = db.new_transaction()
    sizes = {kind: tx.get_root_object(kind).get_index("ivf").trained_size for kind in ("dict", "bag")}
    tx.abort()
    return sizes


def ids(elements):
    return [e.n for e in elements]


def verify(directory):
    """validate() of every root, and near queries against near_oracle on the exact index and on
    the ivf_flat index probed in full; prints one line per root."""
    print(mode_line(), file=sys.stderr)
    space = ObjectSpace(FileStorage(directory))
    try:
        tx = space.open_database("bd").new_transaction()
        queries = [(1.0, 0.0, 0.0), (0, 1, 1), (2.5, 0.5, -1.0), (0.3, 0.2, 0.1)]
        for kind in KINDS:
            coll = tx.get_root_object(kind)
            coll.validate()
            elements = list(coll.elements())
            answered = 0
            for name in coll.index_names():
                index = coll.get_index(name)
                if index.backend == "hnsw":
                    continue
                if index.backend == "ivf_flat":
                    full = dict(index.params)["nlist"]
                    index = index._with(params=tuple(sorted({**dict(index.params), "nprobe": full}.items())))
                for q in queries:
                    for k in (1, 3, 50):
                        term = Term("vec", NEAR, NearQuery(q, k=k))
                        got = list(index.plan(term).execute())
                        expected = near_oracle(elements, index.key_spec, term.value, index.metric)
                        if ids(got) != ids(expected):
                            raise SystemExit(f"{kind}.{name}: near {q} k={k} answered {ids(got)}, the oracle {ids(expected)}")
                        answered += 1
            explain = {n: coll.get_index(n).explain() for n in coll.index_names()}
            print(f"{kind} count={coll.count} indexes={','.join(coll.index_names())} queries={answered} "
                  + " ".join(f"{n}:members={e['members']},invalid={e['invalid']}" for n, e in sorted(explain.items())))
        tx.abort()
    finally:
        space.close()


if __name__ == "__main__":
    modes = {"make": make, "replay": replay, "check": check, "write": write, "change": change, "verify": verify}
    if len(sys.argv) != 3 or MODE not in modes:
        raise SystemExit("usage: py_vector_replay.py make|replay|check|write|change|verify <directory>")
    if MODE in ("make", "replay", "check"):
        print(mode_line(), file=sys.stderr)
    result = modes[MODE](sys.argv[2])
    sys.exit(result if isinstance(result, int) else 0)
