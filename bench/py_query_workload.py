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
from proto_db.collections.lists import List
from proto_db.indexing import EqualityIndex, KeySpec, RangeIndex, register_extractor
from proto_db.query.expressions import Expression
from proto_db.query.planner import plan_query
from proto_db.query.plans import Filter, Intersect

P = (1 << 61) - 1
ALL = ["M1", "M2", "M3", "P1", "P2", "P3"]
SIZES = [int(n) for n in os.environ.get("QUERY_M2_SIZES", "100 1000 10000 100000").split()]
COMMITS = int(os.environ.get("QUERY_M1_COMMITS", "200"))
BLIND_COMMITS = int(os.environ.get("QUERY_M3_COMMITS", "120"))
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


def m1(n, plan, id_="M1", count=COMMITS, blind=False):
    """M1, or M3 when blind: each transaction commits a new dictionary holding change j alone,
    never reading the root, so the commit merges it onto the current version."""
    def person(id_, name, i, years):
        return DBObject(id=id_, name=name, city=CITIES[i % 6], age=years)

    data = os.environ.get("QUERY_DATA")
    if not data:
        raise SystemExit(f"{id_} needs QUERY_DATA, a new directory for its space")
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
        for j in range(count):
            t = db.new_transaction()
            base = t.new_dictionary() if blind else t.get_root_object("people")
            t.set_root_object("people", base.set_at(
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
    emit(id_, n, rows, count, plan, check, us)


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


# The planner workloads P1, P2 and P3: bench/_query_bench.st PlannerBench states the data and
# the work; each answers (rows, queries, plan, checksum, us, model, model_line).
P1_UNITS = [("P1", c, k) for c in (1, 8, 32) for k in ("idx0", "idx2", "idx8")]
P2_UNITS = [("P2", 2000, f"{point}-{forced}")
            for point in ("r0001", "r0010", "r0100", "r0500", "r0900", "r0990", "r1000", "ne-few", "ne-many")
            for forced in ("index", "scan")]
P3_UNITS = [("P3", 2000, "intersect"), ("P3", 2000, "filter")]


def shape(info):
    out = [info["plan"]]
    for child in info["children"]:
        out.append(shape(child))
    return "/".join(out)


def fold(checksum, info):
    nodes = indexes = 0

    def walk(node):
        nonlocal nodes, indexes
        nodes += 1
        if "index" in node:
            indexes += int(node["index"]["index"][1:]) + 1
        for child in node["children"]:
            walk(child)
    walk(info)
    return (checksum * 31 + 64 * nodes + indexes) % P


def p1(c, plan):
    k = int(plan[3:])
    coll = List()
    for i in range(1000):
        coll = coll.append_last(DBObject(id=i, **{f"f{f}": i * (2 * f + 3) * 7919 % 50 for f in range(8)}))
    for m in range(k):
        index = RangeIndex if m % 2 == 0 else EqualityIndex
        coll = coll.add_index(index(f"i{m}", KeySpec.path(f"f{m}")))
    conditions = []
    for q in range(200):
        tokens = []
        for j in range(c):
            tokens.append(f"f{j % 8}")
            tokens += ["<", (7 * q + 13 * j) % 50] if j % 2 == 0 else ["==", (3 * q + j) % 50]
        conditions.append(Expression.compile(tokens))
    t0 = time.perf_counter_ns()
    explains = [plan_query(coll, each).explain() for each in conditions]
    us = (time.perf_counter_ns() - t0) // 1000
    check = 0
    for info in explains:
        check = fold(check, info)
    return 1000, 200, plan, check, us, shape(explains[-1]), None


def planner_records(n):
    coll = List()
    for i in range(n):
        coll = coll.append_last(DBObject(id=i, r=i, few=i % 4, many=i, x=i % 10, y=i % 7))
    return coll


def run(plan):
    t0 = time.perf_counter_ns()
    for _ in range(5):
        rows = list(plan.execute())
    us = (time.perf_counter_ns() - t0) // 1000
    return len(rows), sum(e.id + 1 for e in rows) % P, us


def p2(n, plan):
    coll = (planner_records(n).add_index(RangeIndex("by_r", KeySpec.path("r")))
            .add_index(EqualityIndex("by_few", KeySpec.path("few")))
            .add_index(EqualityIndex("by_many", KeySpec.path("many"))))
    forced = "index" if plan.endswith("-index") else "scan"
    point = plan[:len(plan) - len(forced) - 1]
    if point.startswith("r"):
        term, index = Expression.compile(["r", "<", n * int(point[1:]) // 1000]), "by_r"
    else:
        index = "by_few" if point == "ne-few" else "by_many"
        term = Expression.compile([index[3:], "!=", 0])
    index_plan = coll.get_index(index).plan(term)
    scan_plan = Filter(coll.as_query_plan(), term)
    chosen = plan_query(coll, term)
    rows, check, us = run(index_plan if forced == "index" else scan_plan)
    return (rows, 5, plan, check, us, shape(chosen.explain()),
            f"index_cost={round(index_plan.estimate().cost * 1000)} scan_cost={round(scan_plan.estimate().cost * 1000)}")


def p3(n, plan):
    coll = (planner_records(n).add_index(EqualityIndex("by_x", KeySpec.path("x")))
            .add_index(RangeIndex("by_y", KeySpec.path("y"))))
    hand = Intersect(coll.get_index("by_x").plan(Expression.compile(["x", "==", 3])),
                     coll.get_index("by_y").plan(Expression.compile(["y", "==", 2])))
    chosen = plan_query(coll, ["x", "==", 3, "y", "==", 2])
    if plan not in ("intersect", "filter"):
        raise SystemExit(f"P3: unknown plan {plan}")
    rows, check, us = run(hand if plan == "intersect" else chosen)
    return (rows, 5, plan, check, us, shape(chosen.explain()),
            f"intersect_cost={round(hand.estimate().cost * 1000)} filter_cost={round(chosen.estimate().cost * 1000)}")


def planner_unit(id_, n, plan):
    rows, queries, plan, check, us, model, line = {"P1": p1, "P2": p2, "P3": p3}[id_](n, plan)
    print(f"WORK id={id_} impl=py size={n} rows={rows} queries={queries} plan={plan} checksum={check} model={model}")
    print(f"TIME id={id_} impl=py size={n} plan={plan} us={us}")
    if line is not None:
        print(f"MODEL id={id_} impl=py size={n} plan={plan} {line}")


def main():
    units = []
    for arg in sys.argv[1:] or ALL:
        parts = arg.split(":")
        if parts[0] not in ALL:
            raise SystemExit(f"py_query_workload: unknown workload {arg}")
        if len(parts) == 1:
            if parts[0] in ("M1", "M3"):
                units += [(parts[0], 600, plan) for plan in ("idx0", "idx1", "idx3")]
            elif parts[0] == "M2":
                units += [("M2", n, None) for n in SIZES]
            else:
                units += {"P1": P1_UNITS, "P2": P2_UNITS, "P3": P3_UNITS}[parts[0]]
        elif len(parts) == 3:
            units.append((parts[0], int(parts[1]), parts[2]))
        else:
            raise SystemExit(f"py_query_workload: a unit is <id>:<size>:<plan>, not {arg}")
    for id_, n, plan in units:
        if id_ == "M1":
            m1(n, plan)
        elif id_ == "M3":
            m1(n, plan, "M3", BLIND_COMMITS, True)
        elif id_.startswith("P"):
            planner_unit(id_, n, plan)
        else:
            m2(n, ["build", "fold"] if plan is None else [plan])
    print("query_workload ok")


if __name__ == "__main__":
    main()
