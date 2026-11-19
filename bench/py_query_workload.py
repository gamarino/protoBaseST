"""The Python side of bench/query_workload.st: the same workloads on proto_db (the interop venv),
the same data, the same WORK and TIME lines (impl=py). See query_workload.st for the workloads
and the checksum; bench/run_query.sh runs both and verifies the work.

Usage: python py_query_workload.py [ids...]
"""
import os
import sys
import time

from proto_db.collections import avl
from proto_db.core.dbobject import DBObject
from proto_db.indexing import EqualityIndex

P = (1 << 61) - 1
ALL = ["M2"]
SIZES = [int(n) for n in os.environ.get("QUERY_M2_SIZES", "100 1000 10000 100000").split()]


def records(n):
    out = []
    for i in range(n):
        attrs = {"id": i}
        if i % 17 != 0:
            if i % 19 == 0:
                attrs["age"] = None
            else:
                attrs["age"] = (i * 7919) % (n // 4 + 1) + (0.5 if i % 5 == 0 else 0)
        out.append(DBObject(**attrs))
    return out


def report(index):
    g = total = 0
    for _, (members, _n) in avl.key_iter(index.groups):
        g += 1
        for _, (e, k) in avl.key_iter(members):
            total = (total + g * e.id * k) % P
    g += 1
    for _, (e, k) in avl.key_iter(index.side[0]):
        total = (total + g * e.id * k) % P
    return index.total_count, 0 if index.groups is None else index.groups.count, total


def m2():
    for n in SIZES:
        data = records(n)
        empty = EqualityIndex("by_age", "age")
        t0 = time.perf_counter_ns()
        built = empty.build(data)
        us1 = (time.perf_counter_ns() - t0) // 1000
        t0 = time.perf_counter_ns()
        folded = empty
        for e in data:
            folded = folded.with_added(e)
        us2 = (time.perf_counter_ns() - t0) // 1000
        a, b = report(built), report(folded)
        if a != b or a[0] != n:
            raise SystemExit(f"M2 {n}: build answers {a}, the fold {b}")
        for plan, us in (("build", us1), ("fold", us2)):
            print(f"WORK id=M2 impl=py size={n} rows={a[0]} queries=1 plan={plan} checksum={a[2]}")
            print(f"TIME id=M2 impl=py size={n} plan={plan} us={us}")


def main():
    ids = sys.argv[1:] or ALL
    for i in ids:
        if i not in ALL:
            raise SystemExit(f"py_query_workload: unknown workload {i}")
    if "M2" in ids:
        m2()
    print("query_workload ok")


if __name__ == "__main__":
    main()
