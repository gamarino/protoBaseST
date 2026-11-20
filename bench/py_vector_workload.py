"""The Python side of bench/vector_workload.st: the vector workloads on proto_db (the interop venv,
numpy and hnswlib blocked, so every score is proto_db's pure-Python function), the same data, the
same WORK and TIME lines (impl=py). See vector_workload.st for the units and the checksums;
bench/run_query.sh runs both, each unit in a process of its own, verifies the work and prints the
timings.

Usage: python py_vector_workload.py <unit>      (QUERY_VECTOR_DATA names the data file of the unit's
                                                 dim, written by bench/py_vector_data.py)
"""
import math
import os
import struct
import sys
import time
import zlib

sys.modules["numpy"] = None
sys.modules["hnswlib"] = None

import msgpack  # noqa: E402

from proto_db.indexing import vector_backends as vb  # noqa: E402

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


def run(unit: str):
    id_, n, plan = unit.split(":")
    n = int(n)
    dim_text, op = plan.split("-")
    dim = int(dim_text[1:])
    if id_ != "VB0" or op not in OPS or not dim_text.startswith("d"):
        raise SystemExit(f"py_vector_workload: unknown unit {unit}")
    path = os.environ.get("QUERY_VECTOR_DATA")
    if not path:
        raise SystemExit("py_vector_workload: QUERY_VECTOR_DATA names the data file")
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
