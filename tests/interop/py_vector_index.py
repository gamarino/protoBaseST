"""The vector indexes of protoBaseST and proto_db, node for node at the index level (vectors V3, V4).

Usage: python py_vector_index.py make <directory>    write the shared space
       python py_vector_index.py dump <directory>    print proto_db's index dumps

numpy and hnswlib are blocked before proto_db is imported (sys.modules[...] = None, Addendum V,
5.2), so proto_db runs its pure-Python paths whatever the venv can import; maintaining an exact or
hnsw index never imports either, and the block makes that a guarantee; IVF training takes the
pure-Python k-means, whose squares are the host libm's pow (Addendum V, 2.5 and DV3). 'dump' writes
the mode, the CPython version and the libc (the libm of that pow) to stderr.

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
  'd1'     plain values whose keys are valid 1-vectors (every numeric form, signed zeros, a
           subnormal, equal values with other tokens) or not (another length, a Boolean, a NaN,
           an infinity, a String, None, an int), some repeated
  'd16'    records whose 'vec' is a valid 16-vector of Floats, Integers and Decimals, or one of
           another length, holding a NaN, or None, some repeated
  'ops'    per element set, a seeded sequence of [op, i, j] (0 adds element i, 1 removes element
           i, always one the index holds, 2 replaces element i by element j); and 'histories',
           the three invalid-tree histories of Addendum V 2.11 item 3: [build indices, removed
           indices, added index] of 'recs', built with invalid elements then given another, built
           without then given one, and built with invalid elements, all of them removed, then
           given another; and 'growth', per history of IVF_GROWTH, a seeded sequence of [op, i]
           over its set (0 adds element i, 1 removes element i, always one the index holds; mostly
           new elements, some added twice; 2 dumps the index), from an empty index
'dump' (and _st_vector_index.st on the same space) prints, for each index kind of KINDS and each
(set, key spec) of SPECS, then for each kind of DIM_KINDS (dims 1 and 16, the three metrics), the
index build makes over the set, then the index the ops derive from the build over the set's first
half; then, per kind of KINDS, the three histories; then, per history of IVF_GROWTH, the ivf_flat
index after each operation that trained or retrained it (its trained_size changed) and at its end,
from an empty index, so that every training is dumped: crossing nlist (the first training) and
retrain_growth (each retrain); then the refusal texts (refusals). Each index is printed as
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
from proto_db.collections import avl  # noqa: E402
from proto_db.indexing.keyed import member_key  # noqa: E402
from proto_db.indexing.vector import VectorIndex  # noqa: E402
from proto_db.indexing.vector_backends import numpy_module  # noqa: E402
from proto_db.values import FrozenDict, FrozenList  # noqa: E402

SEGMENT = uuid.UUID(bytes=bytes.fromhex("0123456789abcdef0123456789abcdef"))
SEED = 20261120
SPECS = [("recs", "path vec"), ("vals", "element"), ("big", "path vec")]
#: (set, key spec) of the element sets of other dimensions, replayed like SPECS.
DIM_SPECS = [("d1", "element"), ("d16", "path vec")]
#: (label, metric, backend, params): the index kinds, each over every (set, key spec).
KINDS = [("exact-l2", "l2", "exact", {}),
         ("exact-cosine-nonumpy", "cosine", "exact", {"numpy": False}),
         ("hnsw-ip", "ip", "hnsw", {"M": 8, "seed": 3}),
         ("hnsw-cosine", "cosine", "hnsw", {}),
         ("ivf-l2", "l2", "ivf_flat", {"nlist": 4, "nprobe": 2, "train_iters": 4, "seed": 11}),
         ("ivf-cosine", "cosine", "ivf_flat", {"nlist": 6, "retrain_growth": 1.5})]
#: (label, dim, metric, backend, params, set, key spec): dims 1 and 16, each over the three metrics.
DIM_KINDS = [("d1-cosine-exact", 1, "cosine", "exact", {}, "d1", "element"),
             ("d1-l2-hnsw", 1, "l2", "hnsw", {"M": 2}, "d1", "element"),
             ("d1-ip-exact", 1, "ip", "exact", {"numpy": False}, "d1", "element"),
             ("d1-l2-ivf", 1, "l2", "ivf_flat", {"nlist": 3, "retrain_growth": 1.5}, "d1", "element"),
             ("d16-cosine-hnsw", 16, "cosine", "hnsw", {"M": 4, "seed": 9}, "d16", "path vec"),
             ("d16-l2-exact", 16, "l2", "exact", {}, "d16", "path vec"),
             ("d16-ip-hnsw", 16, "ip", "hnsw", {}, "d16", "path vec")]
#: (label, dim, metric, params, set, key spec, operations): the ivf_flat growth histories, from an
#: empty index, crossing nlist and retrain_growth (vectors V4); the ip metric assigns lists by l2.
#: The last one, operations None, is not seeded: it adds every element of its set, then removes
#: them all (a trained index shrunk below nlist, to nothing: it stays trained), then adds ten again
#: (filed under the old centroids), with a dump at each turn (op 2).
IVF_GROWTH = [("ivf-l2 growth big", 3, "l2", {"nlist": 4, "nprobe": 2, "train_iters": 3, "seed": 5,
                                              "retrain_growth": 1.5}, "big", "path vec", 160),
              ("ivf-cosine growth recs", 3, "cosine", {"nlist": 3, "seed": 2**40, "retrain_growth": 2},
               "recs", "path vec", 90),
              ("ivf-ip growth d16", 16, "ip", {"nlist": 5, "train_iters": 2, "seed": 7, "retrain_growth": 1.25},
               "d16", "path vec", 110),
              ("ivf-l2 growth vals", 3, "l2", {"nlist": 2, "retrain_growth": 3.0}, "vals", "element", 60),
              ("ivf-cosine shrink d1", 1, "cosine", {"nlist": 2, "retrain_growth": 1.5}, "d1", "element", None)]
#: The values the refusal cases tamper with (an index over them, the element key spec, dim 3).
TAMPER_VALUES = [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (1, 2, 3), None, "abc", (1.0, 2.0)]
#: The invalid-tree histories, named as 'ops' lists them.
HISTORIES = ("built with invalid", "built without invalid", "built, emptied, regrown")
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
        d1 = [(1.0,), (-2.5,), (0,), (3,), (Decimal("0.5"),), (-0.0,), (0.0,), (1e300,), (2**60 + 1,), FrozenList([7]),
              (1,), (1.0,), (5e-324,), (1.0, 2.0), (), (True,), (float("nan"),), (float("inf"),), "x", None, 5,
              (Decimal("NaN"),), FrozenList([1.0, 2.0])]
        d1 += [d1[0], d1[2], d1[15], d1[19]]
        d16 = []
        for i in range(90):
            r = rnd.random()
            if r < 0.75:
                vec = tuple(rnd.choice((float(rnd.randint(-3, 3)), rnd.randint(-3, 3), Decimal(rnd.randint(-6, 6)) / 2))
                            for _ in range(16))
            elif r < 0.85:
                vec = tuple(float(rnd.randint(-3, 3)) for _ in range(rnd.choice((15, 17))))
            elif r < 0.95:
                vec = tuple([float("nan")] + [1.0] * 15)
            else:
                vec = None
            d16.append(DBObject(n=i, vec=vec))
        d16 += [d16[0], d16[5], d16[5]]
        sets = {"recs": recs, "vals": vals, "big": big, "d1": d1, "d16": d16}
        ops = {}
        for set_name, spec in SPECS + DIM_SPECS:
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
        ops["histories"] = [[valid_at[:20] + invalid_at[:8], [], invalid_at[8]], [valid_at[:20], [], invalid_at[0]],
                            [valid_at[:20] + invalid_at[:8], invalid_at[:8], invalid_at[8]]]
        for label, _, _, _, set_name, _, length in IVF_GROWTH:
            n = len(sets[set_name])
            if length is None:
                ops[label] = ([[0, i] for i in range(n)] + [[2, 0]] + [[1, i] for i in reversed(range(n))]
                              + [[2, 0]] + [[0, i] for i in range(10)])
                continue
            held, seq = [], []
            for _ in range(length):
                r = rnd.random()
                if held and r < 0.15:
                    seq.append([1, held.pop(rnd.randrange(len(held)))])
                elif held and r < 0.25:
                    i = rnd.choice(held)
                    seq.append([0, i])
                    held.append(i)
                else:
                    i = rnd.randrange(n)
                    seq.append([0, i])
                    held.append(i)
            ops[label] = seq
        for name, elements in sets.items():
            tx.set_root_object(name, elements)
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


#: The definitions refused, (dim, metric, backend, params), each in proto_db's order of checks.
DEFINITIONS = [(0, "cosine", "exact", {}), (True, "cosine", "exact", {}), (2.0, "cosine", "exact", {}),
               ("3", "cosine", "exact", {}), (None, "cosine", "exact", {}), (3, "dot", "exact", {}),
               (3, None, "exact", {}), (3, 3, "exact", {}), (3, "l2", "annoy", {}), (3, "l2", None, {}),
               (3, "l2", "exact", {"numpy": 1}), (3, "l2", "exact", {"numpy": None}), (3, "l2", "exact", {"nlist": 3}),
               (3, "l2", "hnsw", {"M": 1}), (3, "l2", "hnsw", {"M": True}), (3, "l2", "hnsw", {"seed": -1}),
               (3, "l2", "hnsw", {"seed": 1.5}), (3, "l2", "hnsw", {"ef_search": 0}),
               (3, "l2", "hnsw", {"zz": 1, "aa": 2}), (3, "l2", "ivf_flat", {"nlist": 0}),
               (3, "l2", "ivf_flat", {"nlist": 4, "nprobe": 5}), (3, "l2", "ivf_flat", {"retrain_growth": Decimal("2")}),
               (3, "l2", "ivf_flat", {"retrain_growth": "2"}), (3, "l2", "ivf_flat", {"retrain_growth": float("inf")}),
               (3, "l2", "ivf_flat", {"retrain_growth": True}), (3, "l2", "ivf_flat", {"retrain_growth": 1}),
               (3, "l2", "ivf_flat", {"retrain_growth": 10**400}), (3, "l2", "ivf_flat", {"train_iters": None})]
#: The class of each refusal as both sides name it (Python's own errors are PBValidationError, DV7).
CLASSES = {"ProtoValidationError": "validation", "ProtoCorruptionError": "corruption",
           "ProtoNotSupportedError": "not supported", "OverflowError": "validation", "ValueError": "validation"}


def refused(label, block):
    try:
        block()
        print(f"refusal {label}: none")
    except Exception as e:  # noqa: BLE001 - every refusal is printed and compared
        print(f"refusal {label}: {CLASSES.get(type(e).__name__, type(e).__name__)}: {e}")


def refusals():
    """The texts of the refusals both sides print: the definitions of DEFINITIONS, withRemoved: of
    a value not held, and validate: of an index over TAMPER_VALUES tampered as tests/unit/vec_index.st
    tampers it (Python's == on totals and stored components included)."""
    for n, (dim, metric, backend, params) in enumerate(DEFINITIONS, 1):
        refused(f"definition {n}", lambda: VectorIndex("vi", KeySpec.element(), dim, metric, backend, **params))
    empty = VectorIndex("vi", KeySpec.element(), 3, "l2", "exact")
    refused("not held, a vector", lambda: empty.with_removed((1.0, 0.5, 0.0)))
    refused("not held, an invalid key", lambda: empty.with_removed("abc"))
    values = TAMPER_VALUES
    index = empty.build(values)
    store, (members, total) = index.store, index.invalid
    mk = member_key
    vkey = (0, mk(values[0]))
    entry = avl.key_get(store, vkey)

    def put(tree, key, value):
        return avl.key_put(tree, key, value)[0]

    one = empty.build([values[0]])
    abc = empty.build(["abc"])
    tampered = [
        ("invalid None", index._with(invalid=None)),
        ("invalid triple", index._with(invalid=(None, 0, 0))),
        ("invalid list", index._with(invalid=FrozenList([None, 0]))),
        ("invalid entry single", index._with(invalid=(put(members, mk("abc"), ("abc",)), total))),
        ("invalid count True", index._with(invalid=(put(members, mk("abc"), ("abc", True)), total))),
        ("invalid count 0", index._with(invalid=(put(members, mk("abc"), ("abc", 0)), total))),
        ("invalid wrong key", index._with(invalid=(put(avl.key_remove(members, mk("abc"))[0], mk("abd"), ("abc", 1)),
                                                   total))),
        ("invalid valid vector", index._with(invalid=(put(members, mk(values[0]), (values[0], 1)), total + 1),
                                             total_count=index.total_count + 1)),
        ("invalid total 5", index._with(invalid=(members, 5))),
        ("invalid total True", abc._with(invalid=(abc.invalid[0], True))),
        ("store key str", index._with(store=put(store, "x", entry))),
        ("store key True", index._with(store=put(store, (True, vkey[1]), entry))),
        ("store key triple", index._with(store=put(store, (0, vkey[1], 0), entry))),
        ("store entry pair", index._with(store=put(store, vkey, entry[:2]))),
        ("store count True", index._with(store=put(store, vkey, (entry[0], True, entry[2])))),
        ("store count 1.0", index._with(store=put(store, vkey, (entry[0], 1.0, entry[2])))),
        ("store wrong key", index._with(store=put(store, (0, mk(values[1])), entry))),
        ("store vector", index._with(store=put(store, vkey, (entry[0], 1, (9.0, 9.0, 9.0))))),
        ("store vector list", index._with(store=put(store, vkey, (entry[0], 1, FrozenList([1.0, 0.0, 0.0]))))),
        ("store vector True", index._with(store=put(store, vkey, (entry[0], 1, (True, 0, 0))))),
        ("store vector None", index._with(store=put(store, (0, mk("abc")), ("abc", 1, None)))),
        ("trained_size True", index._with(trained_size=True)),
        ("centroids list", index._with(centroids=FrozenList([]))),
        ("centroids on exact", index._with(centroids=((1.0, 0.0, 0.0),), trained_size=1)),
        ("total_count 7", index._with(total_count=7)),
        ("total_count 6.0", index._with(total_count=6.0)),
        ("total_count Decimal", index._with(total_count=Decimal(6))),
        ("total_count False", one._with(total_count=False)),
        ("total_count True", one._with(total_count=True))]
    for label, bad in tampered:
        elements = [values[0]] if label in ("total_count False", "total_count True") else (
            ["abc"] if label == "invalid total True" else values)
        refused(f"validate {label}", lambda: bad.validate(elements))
    ivf = VectorIndex("vi", KeySpec.element(), 3, "l2", "ivf_flat", nlist=2, nprobe=1).build(values)
    ivf_store = ivf.store
    ikey, ientry = next(avl.key_iter(ivf_store))
    c0, c1 = ivf.centroids
    ivf_tampered = [
        ("ivf", ivf),
        ("ivf centroid removed", ivf._with(centroids=(c0,))),
        ("ivf centroid added", ivf._with(centroids=(c0, c1, c1))),
        ("ivf centroid list", ivf._with(centroids=(FrozenList(list(c0)), c1))),
        ("ivf centroid ints", ivf._with(centroids=((1, 0, 0), c1))),
        ("ivf centroid nan", ivf._with(centroids=((float("nan"), 0.0, 0.0), c1))),
        ("ivf centroid short", ivf._with(centroids=((1.0, 0.0), c1))),
        ("ivf centroid True", ivf._with(centroids=((True, 0.0, 0.0), c1))),
        ("ivf trained_size 0", ivf._with(trained_size=0)),
        ("ivf untrained with trained_size", ivf._with(centroids=(), trained_size=3)),
        ("ivf untrained in list 0", ivf._with(centroids=(), trained_size=0)),
        ("ivf in the other list", ivf._with(store=put(avl.key_remove(ivf_store, ikey)[0], (1 - ikey[0], ikey[1]), ientry))),
        ("ivf in list -1", ivf._with(store=put(avl.key_remove(ivf_store, ikey)[0], (-1, ikey[1]), ientry))),
        ("ivf swapped centroids", ivf._with(centroids=(c1, c0)))]
    for label, bad in ivf_tampered:
        refused(f"validate {label}", lambda: bad.validate(values))


def run(directory):
    if numpy_module() is not None:
        raise SystemExit("numpy is importable although it was blocked")
    print(f"numpy: blocked; hnswlib: blocked; python {platform.python_version()}; "
          f"libc {' '.join(platform.libc_ver())}", file=sys.stderr)
    space = ObjectSpace(FileStorage(directory))
    try:
        tx = space.open_database("vec").new_transaction()
        sets = {name: list(tx.get_root_object(name)) for name in ("recs", "vals", "big", "d1", "d16")}
        ops = tx.get_root_object("ops")
        kinds = [(kind, 3, metric, backend, params, set_name, spec_name)
                 for kind, metric, backend, params in KINDS for set_name, spec_name in SPECS] + DIM_KINDS
        for kind, dim, metric, backend, params, set_name, spec_name in kinds:
            elements = sets[set_name]
            spec = KeySpec.element() if spec_name == "element" else KeySpec.path("vec")
            empty = VectorIndex("vi", spec, dim, metric, backend, **params)
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
        for kind, metric, backend, params in KINDS:
            for name, (built, removed, added) in zip(HISTORIES, ops["histories"]):
                index = VectorIndex("vi", KeySpec.path("vec"), 3, metric, backend, **params).build([recs[i] for i in built])
                for i in removed:
                    index = index.with_removed(recs[i])
                show(f"{kind} history {name}", index.with_added(recs[added]))
        for label, dim, metric, params, set_name, spec_name, _ in IVF_GROWTH:
            elements = sets[set_name]
            spec = KeySpec.element() if spec_name == "element" else KeySpec.path("vec")
            index = VectorIndex("vi", spec, dim, metric, "ivf_flat", **params)
            for n, (op, i) in enumerate(ops[label], 1):
                if op == 2:
                    show(f"{label} op {n} checkpoint", index)
                    continue
                before = index.trained_size
                index = index.with_added(elements[i]) if op == 0 else index.with_removed(elements[i])
                if index.trained_size != before:
                    show(f"{label} op {n} trained at {index.trained_size}", index)
            show(f"{label} end", index)
        refusals()
        tx.abort()
    finally:
        space.close()
    print("end")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("make", "dump"):
        raise SystemExit("usage: py_vector_index.py make|dump <directory>")
    (make if sys.argv[1] == "make" else run)(sys.argv[2])
