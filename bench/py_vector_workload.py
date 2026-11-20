"""The Python side of bench/vector_workload.st: the vector workloads on proto_db (the interop venv,
numpy and hnswlib blocked, so every score is proto_db's pure-Python function), the same data, the
same WORK and TIME lines (impl=py). See vector_workload.st for the units and the checksums;
bench/run_query.sh runs both, each unit in a process of its own, verifies the work and prints the
timings.

Usage: python py_vector_workload.py <unit>      (QUERY_VECTOR_DATA names the data file of the unit's
                                                 size and dim, written by bench/py_vector_data.py;
                                                 VB3 and VB5 also need QUERY_DATA, a new directory
                                                 for their spaces)

VB3 and VB5 (task V5) are vector_workload.st's; the indexes, the starting collections and the
checksum are bench/_vector_bench.st's, computed here with the same formulas.
"""
import math
import os
import struct
import sys
import time
import zlib
from pathlib import Path

sys.modules["numpy"] = None
sys.modules["hnswlib"] = None

import msgpack  # noqa: E402

from proto_db import FileStorage, ObjectSpace  # noqa: E402
from proto_db.collections.dictionaries import Dictionary  # noqa: E402
from proto_db.collections.lists import List  # noqa: E402
from proto_db.indexing import KeySpec  # noqa: E402
from proto_db.indexing import vector_backends as vb  # noqa: E402
from proto_db.indexing.vector import VectorIndex  # noqa: E402

OPS = ("products", "naive", "fsum", "ip", "l2", "cosine")


def checksum(values) -> int:
    """zlib.crc32 of the results' IEEE 754 binary64 big-endian bytes, in order (a result that is a
    list of Floats contributes each of them)."""
    out = bytearray()
    for v in values:
        if isinstance(v, list):
            for x in v:
                out += struct.pack(">d", x)
        else:
            out += struct.pack(">d", v)
    return zlib.crc32(bytes(out))


def naive(terms) -> float:
    """A plain left-to-right IEEE sum from 0.0 (not sum(): CPython 3.12+ compensates float sums)."""
    s = 0.0
    for x in terms:
        s = s + x
    return s


def read_vectors(path: str, n: int, dim: int) -> list:
    """VectorBench vectorsFrom:n:dim: (bench/_vector_bench.st)."""
    with open(path, "rb") as f:
        data = msgpack.unpackb(f.read(), raw=False)
    if data["n"] != n or data["dim"] != dim:
        raise SystemExit(f"vector bench: {path} holds {data['n']} vectors of dim {data['dim']}, not {n} of dim {dim}")
    return [tuple(v) for v in data["vectors"]]


def indexes_of(plan: str, dim: int) -> list:
    """VectorBench indexesOf:dim:."""
    if plan == "none":
        return []
    if plan == "exact":
        return [VectorIndex("near", KeySpec.element(), dim, "l2", "exact")]
    if plan == "ivf":
        return [VectorIndex("near", KeySpec.element(), dim, "l2", "ivf_flat",
                            nlist=16, train_iters=10, seed=51, retrain_growth=1.03)]
    raise SystemExit(f"vector bench: unknown plan {plan!r}")


def bench_checksum(coll, keyed: bool, centroids: bool) -> int:
    """VectorBench checksumOf:keyed:centroids:."""
    out = bytearray()

    def put(x):
        out.extend(struct.pack(">d", float(x)))
    if keyed:
        for k, v in coll.items():
            put(k)
            for x in v:
                put(x)
    else:
        for v in coll:
            for x in v:
                put(x)
    for name in sorted(coll.index_names()):
        index = coll.get_index(name)
        info = index.explain()
        put(info["members"])
        put(info["invalid"])
        put(index.trained_size)
        put(len(index.centroids))
        if centroids:
            for c in index.centroids:
                for x in c:
                    put(x)
    return zlib.crc32(bytes(out))


def maintenance(id_: str, n: int, plan: str, dim: int, op: str, path: str):
    """VB3 (blind false) and VB5 (blind true); see vector_workload.st."""
    blind = id_ == "VB5"
    commits = int(os.environ.get("QUERY_VB5_COMMITS" if blind else "QUERY_VB3_COMMITS", "120" if blind else "200"))
    data = os.environ.get("QUERY_DATA")
    if not data:
        raise SystemExit(f"{id_} needs QUERY_DATA, a new directory for its space")
    data = Path(data) / plan
    data.mkdir(parents=True, exist_ok=True)
    vectors = read_vectors(path, n + commits, dim)
    if blind:
        coll = Dictionary()
        for i in range(n):
            coll = coll.set_at(i, vectors[i])
    else:
        coll = List().extend(vectors[:n])
    for index in indexes_of(op, dim):
        coll = coll.add_index(index)
    space = ObjectSpace(FileStorage(str(data)))
    try:
        db = space.new_database("bench")
        tx = db.new_transaction()
        tx.set_root_object("vecs", coll)
        tx.commit()
        t0 = time.perf_counter_ns()
        for j in range(commits):
            t = db.new_transaction()
            if blind:
                t.set_root_object("vecs", t.new_dictionary().set_at(n + j, vectors[n + j]))
            else:
                t.set_root_object("vecs", t.get_root_object("vecs").append_last(vectors[n + j]))
            t.commit()
        us = (time.perf_counter_ns() - t0) // 1000
        tx = db.new_transaction()
        coll = tx.get_root_object("vecs")
        coll.validate()
        count = coll.count
        if count != n + commits:
            raise SystemExit(f"{id_}: {count} elements after the commits")
        if op == "ivf" and coll.get_index("near").trained_size <= n:
            raise SystemExit(f"{id_}: the IVF index never retrained (trained size {coll.get_index('near').trained_size})")
        check = bench_checksum(coll, blind, not blind)
        tx.abort()
    finally:
        space.close()
    print(f"WORK id={id_} impl=py size={n} rows={count} queries={commits} plan={plan} checksum={check}")
    print(f"TIME id={id_} impl=py size={n} plan={plan} us={us}")


def run(unit: str):
    id_, n, plan = unit.split(":")
    n = int(n)
    dim_text, op = plan.split("-", 1)
    dim = int(dim_text[1:]) if dim_text.startswith("d") and dim_text[1:].isdigit() else -1
    path = os.environ.get("QUERY_VECTOR_DATA")
    if not path:
        raise SystemExit("py_vector_workload: QUERY_VECTOR_DATA names the data file")
    if (id_ == "VB3" and op in ("none", "exact", "ivf")) or (id_ == "VB5" and op in ("exact", "ivf")):
        if dim < 1:
            raise SystemExit(f"py_vector_workload: unknown unit {unit}")
        return maintenance(id_, n, plan, dim, op, path)
    if id_ != "VB0" or op not in OPS or dim < 1:
        raise SystemExit(f"py_vector_workload: unknown unit {unit}")
    with open(path, "rb") as f:
        data = msgpack.unpackb(f.read(), raw=False)
    if data["n"] != n or data["dim"] != dim:
        raise SystemExit(f"py_vector_workload: {path} holds n={data['n']} dim={data['dim']}, not {n} {dim}")
    vectors = [tuple(v) for v in data["vectors"]]
    q = tuple(data["query"])
    products = [[a * b for a, b in zip(q, v)] for v in vectors]
    t0 = time.perf_counter_ns()
    if op == "products":
        results = [[a * b for a, b in zip(q, v)] for v in vectors]
    elif op == "naive":
        results = [naive(p) for p in products]
    elif op == "fsum":
        results = [math.fsum(p) for p in products]
    else:
        results = [vb.exact_score(op, q, v) for v in vectors]
    us = (time.perf_counter_ns() - t0) // 1000
    print(f"WORK id={id_} impl=py size={n} rows={len(results)} queries=1 plan={plan} checksum={checksum(results)}")
    print(f"TIME id={id_} impl=py size={n} plan={plan} us={us}")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    if vb.numpy_module() is not None:
        sys.exit("py_vector_workload: numpy is importable although blocked")
    run(sys.argv[1])
    print("query_workload ok")


if __name__ == "__main__":
    main()
