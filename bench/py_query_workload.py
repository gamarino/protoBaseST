"""The Python side of bench/query_workload.st: the same workloads on proto_db (the interop venv),
the same data, the same WORK and TIME lines (impl=py). See query_workload.st for the workloads,
the units and the checksums; bench/run_query.sh runs both, each unit in a process of its own,
verifies the work and prints the timings.

Usage: python py_query_workload.py [units...]     (a unit is <id>:<size>:<plan>, or a bare id)
"""
import os
import sys
import time
from pathlib import Path

from proto_db import FileStorage, ObjectSpace
from proto_db.collections import avl
from proto_db.collections.dictionaries import Dictionary
from proto_db.core.dbobject import DBObject
from proto_db.indexing import EqualityIndex, KeySpec, RangeIndex, register_extractor

P = (1 << 61) - 1
ALL = ["M1", "M2"]
SIZES = [int(n) for n in os.environ.get("QUERY_M2_SIZES", "100 1000 10000 100000").split()]
COMMITS = int(os.environ.get("QUERY_M1_COMMITS", "200"))
CITIES = ["Oslo", "Rome", "Paris", "Lima", "Kyiv", "Quito"]


def emit(id_, n, rows, queries, plan, checksum, us):
    print(f"WORK id={id_} impl=py size={n} rows={rows} queries={queries} plan={plan} checksum={checksum}")
    print(f"TIME id={id_} impl=py size={n} plan={plan} us={us}")


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


def m1(n, plan):
    def person(id_, name, i, years):
        return DBObject(id=id_, name=name, city=CITIES[i % 6], age=years)

    data = os.environ.get("QUERY_DATA")
    if not data:
        raise SystemExit("M1 needs QUERY_DATA, a new directory for its space")
    data = Path(data) / plan
    data.mkdir(parents=True, exist_ok=True)
    register_extractor("bench.m1.name_length", lambda r: len(r.name), version="1")
    if plan == "idx0":
        indexes = []
    elif plan == "idx1":
        indexes = [EqualityIndex("by_city", KeySpec.path("city"))]
    elif plan == "idx3":
        indexes = [EqualityIndex("by_city", KeySpec.path("city")), RangeIndex("by_age", KeySpec.path("age")),
                   RangeIndex("by_name_length", KeySpec.extractor("bench.m1.name_length"))]
    else:
        raise SystemExit(f"M1: unknown plan {plan}")
    space = ObjectSpace(FileStorage(str(data)))
    try:
        db = space.new_database("bench")
        people = Dictionary()
        for i in range(n):
            people = people.set_at(i, person(i, f"p{i}", i, 18 + (7 * i % 23) + (0.5 if i % 5 == 0 else 0)))
        for index in indexes:
            people = people.add_index(index)
        tx = db.new_transaction()
        tx.set_root_object("people", people)
        tx.commit()
        t0 = time.perf_counter_ns()
        for j in range(COMMITS):
            t = db.new_transaction()
            t.set_root_object("people", t.get_root_object("people").set_at(
                7919 * j % n, person(n + j, f"q{j}", j, 18 + (11 * j % 23))))
            t.commit()
        us = (time.perf_counter_ns() - t0) // 1000
        tx = db.new_transaction()
        people = tx.get_root_object("people")
        people.validate()
        check = 0
        for k, v in people.items():
            check = (check + (k + 1) * v.id) % P
        for name in people.index_names():
            check = (check * 31 + report(people.get_index(name))[2]) % P
        rows = people.count
        tx.abort()
    finally:
        space.close()
    emit("M1", n, rows, COMMITS, plan, check, us)


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


def m2(n, plans):
    data = records(n)
    empty = EqualityIndex("by_age", "age")
    results = []
    for plan in plans:
        t0 = time.perf_counter_ns()
        if plan == "build":
            index = empty.build(data)
        elif plan == "fold":
            index = empty
            for e in data:
                index = index.with_added(e)
        else:
            raise SystemExit(f"M2: unknown plan {plan}")
        results.append((plan, report(index), (time.perf_counter_ns() - t0) // 1000))
    for plan, r, _ in results:
        if r != results[0][1] or r[0] != n:
            raise SystemExit(f"M2 {n}: {plan} answers {r}, {results[0][0]} {results[0][1]}")
    for plan, r, us in results:
        emit("M2", n, r[0], 1, plan, r[2], us)


def main():
    units = []
    for arg in sys.argv[1:] or ALL:
        parts = arg.split(":")
        if parts[0] not in ALL:
            raise SystemExit(f"py_query_workload: unknown workload {arg}")
        if len(parts) == 1:
            if parts[0] == "M1":
                units += [("M1", 600, plan) for plan in ("idx0", "idx1", "idx3")]
            else:
                units += [("M2", n, None) for n in SIZES]
        elif len(parts) == 3:
            units.append((parts[0], int(parts[1]), parts[2]))
        else:
            raise SystemExit(f"py_query_workload: a unit is <id>:<size>:<plan>, not {arg}")
    for id_, n, plan in units:
        if id_ == "M1":
            m1(n, plan)
        else:
            m2(n, ["build", "fold"] if plan is None else [plan])
    print("query_workload ok")


if __name__ == "__main__":
    main()
