"""The guide's worked plans, planned by proto_db at v2.0.0rc4 (ruling CR10, plan Task 7 Step 5b).

Usage: python py_guide_plans.py

Builds the data of docs/queries.md ("Reading a plan": 600 people, cities Lima, Oslo, Paris and Rome
in turn, ages 18 + (i mod 60), a PBEqualityIndex 'by_city' and a PBRangeIndex 'by_age'; "The
crossover where scanning wins" and chapter 18's "Why the planner sometimes scans": one person, and
two people in two cities, with 'by_city', a lookup of the first one's city) and prints, one per line, '<key> <value>' for every
model estimate the guide quotes: the costs and rows of the nodes of proto_db's own plans
(plan_query and explain()), of the rejected candidates (the same query with the winner's index
removed, or the candidate built from proto_db's plan classes), and the differences the text quotes
(a descent, a sort's increment). Floats are printed with repr, so a figure can be compared within
plan call IP8. tests/docs/guide_plans.sh compares the guide's text with this output. Refuses to
run unless the imported proto_db is the commit tests/interop/setup_venv.sh pins.
"""
import sys
from pathlib import Path

from proto_db.collections.lists import List
from proto_db.core.dbobject import DBObject
from proto_db.indexing import EqualityIndex, KeySpec, RangeIndex, VectorIndex
from proto_db.query.expressions import Expression
from proto_db.query.planner import plan_query
from proto_db.query.plans import Filter, Sort
from proto_db.query.terms import NearQuery

HERE = Path(__file__).resolve().parent


def check_pinned() -> None:
    import proto_db
    setup = HERE / "setup_venv.sh"
    pinned = next((line.split('"')[1] for line in setup.read_text().splitlines()
                   if line.startswith('TAG_COMMIT="')), None)
    held_file = Path(proto_db.__file__).resolve().parent.parent / ".commit"
    held = held_file.read_text().strip() if held_file.is_file() else None
    if not pinned or not held or not held.startswith(pinned):
        sys.exit(f"py_guide_plans: proto_db at {Path(proto_db.__file__).parent} is commit {held or 'unknown'}, "
                 f"not the pinned {pinned} of setup_venv.sh; run it through the interop venv")


def people(n):
    coll = List()
    for j in range(n):
        coll = coll.append_last(DBObject(city=("Lima", "Oslo", "Paris", "Rome")[j % 4], age=18 + j % 60))
    return coll


def documents(n):
    """vector_plans.st's documents: Park and Miller's generator, seed 7, 8 components each."""
    topics, seed, docs = ("sports", "music", "science"), 7, []
    for i in range(n):
        vec = []
        for _ in range(8):
            seed = seed * 16807 % 2147483647
            vec.append(seed / 2147483647.0 * 2.0 - 1.0)
        docs.append(DBObject(i=i, topic=topics[i % 3], vec=vec))
    return docs


def vector_plans():
    """The worked vector plan (docs/queries.md, 'A worked vector plan'; examples/queries/vector_plans.st)."""
    docs = documents(300)
    both = (List().add_index(VectorIndex("by_vec", "vec", 8, "cosine"))
            .add_index(VectorIndex("by_vec_ivf", KeySpec.path("vec"), 8, "cosine", "ivf_flat", nlist=8, nprobe=2)))
    for d in docs:
        both = both.append_last(d)
    exact = both.remove_index("by_vec_ivf")
    q = docs[42].vec  # vector_plans.st: (docs at: 43), document 42
    cases = {"vplan1": ["vec", "near[]", NearQuery(q, k=5)],
             "vplan2": ["vec", "near[]", NearQuery(q, k=3), "topic", "==", "music"],
             "vplan3": ["vec", "near[]", NearQuery(q, threshold=0.6)]}
    for key, cond in cases.items():
        for suffix, coll, name in (("", both, "by_vec_ivf"), (".exact", exact, "by_vec")):
            info = plan_query(coll, cond).explain()
            assert (info["plan"], info["index"]["index"]) == ("VectorSearch", name), (key, info["plan"], info["index"])
            assert ("where" in info) == (key == "vplan2"), (key, info.keys())
            out(f"{key}{suffix}.rows", info["estimate"]["rows"])
            out(f"{key}{suffix}.cost", info["estimate"]["cost"])
    found = {d.i for d in plan_query(both, cases["vplan1"]).execute()}
    truth = {d.i for d in plan_query(exact, cases["vplan1"]).execute()}
    out("vplan1.overlap", len(found & truth))


def out(key, value):
    print(f"{key} {value!r}")


def est(plan):
    e = plan.explain()["estimate"]
    return e["rows"], e["cost"]


def main():
    check_pinned()
    guide = (people(600).add_index(EqualityIndex("by_city", KeySpec.path("city")))
             .add_index(RangeIndex("by_age", KeySpec.path("age"))))
    oslo = ["city", "==", "Oslo"]

    # Plan 1: a lookup; the rejected scan with a filter.
    plan1 = plan_query(guide, oslo)
    info = plan1.explain()
    assert info["plan"] == "IndexLookup", info["plan"]
    out("plan1.rows", info["estimate"]["rows"])
    out("plan1.cost", info["estimate"]["cost"])
    out("plan1.descent", info["estimate"]["cost"] - info["estimate"]["rows"])
    scan1 = Filter(guide.as_query_plan(), Expression.compile(oslo))
    out("plan1.scan.rows", est(scan1)[0])
    out("plan1.scan.cost", est(scan1)[1])

    # Plan 2: two conditions, and the two rejected candidates made visible.
    both = ["city", "==", "Oslo", "age", ">", 70]
    info = plan_query(guide, both).explain()
    rng = info["children"][0]
    assert (info["plan"], rng["plan"]) == ("Filter", "IndexRange"), (info["plan"], rng["plan"])
    out("plan2.range.rows", rng["estimate"]["rows"])
    out("plan2.range.cost", rng["estimate"]["cost"])
    out("plan2.filter.rows", info["estimate"]["rows"])
    out("plan2.filter.cost", info["estimate"]["cost"])
    city_only = plan_query(guide.remove_index("by_age"), both).explain()
    assert [city_only["plan"], city_only["children"][0]["plan"]] == ["Filter", "IndexLookup"]
    out("plan2.city.cost", city_only["estimate"]["cost"])
    scan_only = plan_query(guide.remove_index("by_age").remove_index("by_city"), both).explain()
    assert [scan_only["plan"], scan_only["children"][0]["plan"]] == ["Filter", "CollectionScan"]
    out("plan2.scan.cost", scan_only["estimate"]["cost"])
    out("plan2.answer", len(list(plan_query(guide, both).execute())))

    # Plan 3: an ordered window; the rejected ordered scan with a filter; without the condition.
    window = ["age", "between[]", 30, 35]
    info = plan_query(guide, window, order_by=["age"], limit=5).explain()
    sort = info["children"][0]
    rng = sort["children"][0]
    assert [info["plan"], sort["plan"], rng["plan"]] == ["Limit", "Sort", "IndexRange"]
    out("plan3.range.rows", rng["estimate"]["rows"])
    out("plan3.range.cost", rng["estimate"]["cost"])
    out("plan3.sort.cost", sort["estimate"]["cost"])
    out("plan3.sort.increment", sort["estimate"]["cost"] - rng["estimate"]["cost"])
    out("plan3.limit.cost", info["estimate"]["cost"])
    ordered = guide.get_index("by_age").ordered_plan(False)
    out("plan3.ordered.cost", est(ordered)[1])
    out("plan3.ordered_filter.cost", est(Filter(ordered, Expression.compile(window)))[1])
    unconditioned = plan_query(guide, None, order_by=["age"], limit=5).explain()
    assert [unconditioned["plan"], unconditioned["children"][0]["plan"]] == ["Limit", "IndexOrderedScan"]
    out("plan3.unconditioned.cost", unconditioned["estimate"]["cost"])
    out("plan3.sort_all.cost", est(Sort(guide.as_query_plan(), ["age"]))[1])

    # The crossover: one element, then two elements in two groups, a matching lookup ('Lima').
    lima = ["city", "==", "Lima"]
    for n in (1, 2):
        tiny = people(n).add_index(EqualityIndex("by_city", KeySpec.path("city")))
        chosen = plan_query(tiny, lima).explain()
        lookup = tiny.get_index("by_city").plan(Expression.compile(lima))
        scan = Filter(tiny.as_query_plan(), Expression.compile(lima))
        out(f"tiny{n}.lookup.cost", est(lookup)[1])
        out(f"tiny{n}.scan.cost", est(scan)[1])
        print(f"tiny{n}.chosen {chosen['plan']}")

    vector_plans()


if __name__ == "__main__":
    main()
