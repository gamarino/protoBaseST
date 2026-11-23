"""The Python side of bench/vector_workload.st: the vector workloads on proto_db (the interop venv,
numpy and hnswlib blocked, so every score is proto_db's pure-Python function), the same data, the
same WORK and TIME lines (impl=py). See vector_workload.st for the units and the checksums;
bench/run_query.sh runs both, each unit in a process of its own, verifies the work and prints the
timings.

Usage: python py_vector_workload.py <unit>      (QUERY_VECTOR_DATA names the data file of the unit's
                                                 size and dim, written by bench/py_vector_data.py;
                                                 VB3 and VB5 also need QUERY_DATA, a new directory
                                                 for their spaces)

VB3 and VB5 (task V5), VB1 and VB2 (task V6) and VB4 (task V7) are vector_workload.st's; the
indexes, the starting collections and the checksums are bench/_vector_bench.st's, computed here with
the same formulas.
"""
import math
import os
import struct
import sys
import time
import zlib
from pathlib import Path

# QUERY_PY_NUMPY=1 runs proto_db's default mode (numpy importable, tests/interop/.venv-numpy) for
# VB1, VB2, VB3 and VB5, reported as impl=pyn: its centroids are numpy's (deviation DV3), so only the
# work that does not depend on them is verified (the COUNTS lines; the WORK lines too where no
# centroid decides them: VB1's exact answers are verified, VB2's are reported by recall). Otherwise numpy and hnswlib are blocked: the reference mode, impl=py.
NUMPY_MODE = os.environ.get("QUERY_PY_NUMPY") == "1"
IMPL = "pyn" if NUMPY_MODE else "py"
if not NUMPY_MODE:
    sys.modules["numpy"] = None
    sys.modules["hnswlib"] = None

import msgpack  # noqa: E402

from proto_db import FileStorage, ObjectSpace  # noqa: E402
from proto_db.collections.dictionaries import Dictionary  # noqa: E402
from proto_db.collections.lists import List  # noqa: E402
from proto_db.indexing import KeySpec  # noqa: E402
from proto_db.indexing import vector_backends as vb  # noqa: E402
from proto_db.indexing.vector import VectorIndex  # noqa: E402
from proto_db import DBObject  # noqa: E402
from proto_db.query.terms import NEAR, NearQuery, Term  # noqa: E402

OPS = ("products", "naive", "fsum", "ip", "l2", "cosine", "ip-scorer", "l2-scorer", "cosine-scorer")


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
        counts = bench_checksum(coll, blind, False)
        tx.abort()
    finally:
        space.close()
    print(f"WORK id={id_} impl={IMPL} size={n} rows={count} queries={commits} plan={plan} checksum={check}")
    print(f"COUNTS id={id_} impl={IMPL} size={n} plan={plan} checksum={counts}")
    print(f"TIME id={id_} impl={IMPL} size={n} plan={plan} us={us}")


def read_queries(path: str, dim: int) -> list:
    """VectorBench queriesFrom:dim:."""
    with open(path, "rb") as f:
        data = msgpack.unpackb(f.read(), raw=False)
    queries = [tuple(q) for q in data["queries"]]
    if any(len(q) != dim for q in queries):
        raise SystemExit(f"vector bench: {path} holds queries of another dim than {dim}")
    return queries


def records(vectors) -> list:
    """VectorBench records:."""
    return [DBObject(i=i, vec=v) for i, v in enumerate(vectors)]


def answers_checksum(answers) -> int:
    """VectorBench answersChecksum:."""
    out = bytearray()
    for answer in answers:
        for i in answer:
            out += struct.pack(">d", float(i))
    return zlib.crc32(bytes(out))


def search(index, q, k: int = 10) -> list:
    """VectorBench search:query:k:, a VectorSearch over the index's plan (the plan proto_db's planner
    builds for near(k) on a collection indexed by it)."""
    from proto_db.query.plans import VectorSearch
    return [e.i for e in VectorSearch(index, Term("vec", NEAR, NearQuery(q, k=k))).execute()]


def knn(id_: str, n: int, plan: str, dim: int, op: str, path: str):
    """VB1 and VB2; see vector_workload.st."""
    vectors = read_vectors(path, n, dim)
    queries = read_queries(path, dim)
    recs = records(vectors)
    if id_ == "VB1":
        index = VectorIndex("by_vec", KeySpec.path("vec"), dim, op, "exact").build(recs)
        t0 = time.perf_counter_ns()
        first = search(index, queries[0])
        us_first = (time.perf_counter_ns() - t0) // 1000
        t0 = time.perf_counter_ns()
        answers = [search(index, q) for q in queries]
        us = (time.perf_counter_ns() - t0) // 1000
        print(f"WORK id={id_} impl={IMPL} size={n} rows={len(first)} queries=1 plan={plan}-first checksum={answers_checksum([first])}")
        print(f"WORK id={id_} impl={IMPL} size={n} rows={sum(map(len, answers))} queries={len(queries)} plan={plan}-knn "
              f"checksum={answers_checksum(answers)}")
        print(f"TIME id={id_} impl={IMPL} size={n} plan={plan}-first us={us_first}")
        print(f"TIME id={id_} impl={IMPL} size={n} plan={plan}-knn us={us}")
        return
    nlist = max(4, int(n ** 0.5))
    exact = VectorIndex("by_vec", KeySpec.path("vec"), dim, "cosine", "exact").build(recs)
    truth = [search(exact, q) for q in queries]
    t0 = time.perf_counter_ns()
    built = VectorIndex("by_vec", KeySpec.path("vec"), dim, "cosine", "ivf_flat", nlist=nlist, nprobe=1).build(recs)
    us_build = (time.perf_counter_ns() - t0) // 1000
    out = bytearray()
    for c in built.centroids:
        for x in c:
            out += struct.pack(">d", x)
    print(f"WORK id={id_} impl={IMPL} size={n} rows={len(built.centroids)} queries=0 plan={plan}-build checksum={zlib.crc32(bytes(out))}")
    print(f"COUNTS id={id_} impl={IMPL} size={n} plan={plan}-build members={built.explain()['members']} lists={len(built.centroids)}")
    print(f"TIME id={id_} impl={IMPL} size={n} plan={plan}-build us={us_build}")
    for nprobe in (1, 4, nlist):
        # The built index with another nprobe: the same store and centroids (training does not read
        # nprobe), so the three probes are measured on one training.
        index = built._with(params=vb.normalize_params("ivf_flat", {**dict(built.params), "nprobe": nprobe}))
        search(index, queries[0])
        t0 = time.perf_counter_ns()
        answers = [search(index, q) for q in queries]
        us = (time.perf_counter_ns() - t0) // 1000
        hits = sum(len(set(a) & set(t)) for a, t in zip(answers, truth))
        label = f"{plan}-nprobe{nprobe}"
        print(f"WORK id={id_} impl={IMPL} size={n} rows={sum(map(len, answers))} queries={len(queries)} plan={label} "
              f"checksum={answers_checksum(answers)}")
        print(f"COUNTS id={id_} impl={IMPL} size={n} plan={label} rows={sum(map(len, answers))}")
        print(f"RECALL id={id_} impl={IMPL} size={n} plan={label} hits={hits} of={10 * len(queries)}")
        print(f"TIME id={id_} impl={IMPL} size={n} plan={label} us={us}")


def filtered(id_: str, n: int, plan: str, dim: int, op: str, path: str):
    """VB4; see vector_workload.st."""
    from proto_db.query.planner import plan_query
    from proto_db.query.plans import VectorSearch
    percent = int(op[1:])
    vectors = read_vectors(path, n, dim)
    queries = read_queries(path, dim)
    recs = [DBObject(i=i, s=i % 100, vec=v) for i, v in enumerate(vectors)]
    coll = List().extend(recs).add_index(VectorIndex("by_vec", KeySpec.path("vec"), dim, "l2", "exact"))
    cond = Term("s", "<", percent)

    def knn(q):
        return Term("vec", NEAR, NearQuery(q, k=10))

    shape = plan_query(coll, [knn(queries[0]), cond])
    if not isinstance(shape, VectorSearch) or shape.explain().get("where") != cond.describe():
        raise SystemExit(f"{id_}: near(k) AND s < {percent} is not one VectorSearch with its where: {shape.explain()}")
    t0 = time.perf_counter_ns()
    inside = [[e.i for e in plan_query(coll, [knn(q), cond]).execute()] for q in queries]
    us_inside = (time.perf_counter_ns() - t0) // 1000
    t0 = time.perf_counter_ns()
    post = [[e.i for e in plan_query(coll, knn(q)).execute() if e.s < percent] for q in queries]
    us_post = (time.perf_counter_ns() - t0) // 1000
    for label, answers, us in ((f"{plan}-filtered", inside, us_inside), (f"{plan}-post", post, us_post)):
        print(f"WORK id={id_} impl={IMPL} size={n} rows={sum(map(len, answers))} queries={len(queries)} plan={label} "
              f"checksum={answers_checksum(answers)}")
        print(f"TIME id={id_} impl={IMPL} size={n} plan={label} us={us}")


def run(unit: str):
    id_, n, plan = unit.split(":")
    n = int(n)
    dim_text, op = plan.split("-", 1)
    dim = int(dim_text[1:]) if dim_text.startswith("d") and dim_text[1:].isdigit() else -1
    path = os.environ.get("QUERY_VECTOR_DATA")
    if not path:
        raise SystemExit("py_vector_workload: QUERY_VECTOR_DATA names the data file")
    if (id_ == "VB1" and op in ("cosine", "l2")) or (id_ == "VB2" and op == "ivf"):
        if dim < 1:
            raise SystemExit(f"py_vector_workload: unknown unit {unit}")
        return knn(id_, n, plan, dim, op, path)
    if id_ == "VB4" and op in ("s01", "s10", "s50"):
        if dim < 1:
            raise SystemExit(f"py_vector_workload: unknown unit {unit}")
        return filtered(id_, n, plan, dim, op, path)
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
        # The -scorer units are protoBaseST's scorerFor:query: of the same scores (task V8, fix
        # round 1); proto_db has no such object, its side is exact_score again.
        metric = op.removesuffix("-scorer")
        results = [vb.exact_score(metric, q, v) for v in vectors]
    us = (time.perf_counter_ns() - t0) // 1000
    print(f"WORK id={id_} impl=py size={n} rows={len(results)} queries=1 plan={plan} checksum={checksum(results)}")
    print(f"TIME id={id_} impl=py size={n} plan={plan} us={us}")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    if NUMPY_MODE:
        if vb.numpy_module() is None:
            sys.exit("py_vector_workload: QUERY_PY_NUMPY=1 but proto_db does not see numpy")
        if not sys.argv[1].startswith(("VB1:", "VB2:", "VB3:", "VB5:")):
            sys.exit("py_vector_workload: proto_db's numpy mode is measured for VB1, VB2, VB3 and VB5 only")
    elif vb.numpy_module() is not None:
        sys.exit("py_vector_workload: numpy is importable although blocked")
    run(sys.argv[1])
    print("query_workload ok")


if __name__ == "__main__":
    main()
