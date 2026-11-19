"""Write the query vectors of the indexed queries (plan Task 7, spec 6.2, plan call IP11) with proto_db
at v2.0.0rc4.

Usage: python py_query_vectors.py <out directory>

<out> must not exist. The script writes <out>/space, a proto_db database directory (FileStorage),
<out>/queries.msgpack, the cases, and <out>/manifest.sha256, the sha256 of queries.msgpack and of
every file under space/ (sha256sum's format, paths relative to <out>, sorted). It refuses to run
unless the imported proto_db is the commit tests/interop/setup_venv.sh pins, and refuses to write
when any recorded result disagrees with a scan (the oracle below). Run it through the interop venv
(tests/conformance/fetch_query_vectors.sh does); the vendored copy is
tests/conformance/vectors-queries/, read by tests/conformance/queries.st.

The database 'queries' (seed SEED) holds these roots, written in one transaction:

  list      a List of PEOPLE records, then 15 of them appended again (duplicates); indexes
            by_city (EqualityIndex on city), by_age (RangeIndex on age), by_id (RangeIndex on id),
            by_score (EqualityIndex on score) and by_len (RangeIndex on the extractor
            'queries.vectors.name_len', the length of name)
  dict      a Dictionary id -> record; by_city, by_age
  hash      a HashDictionary id -> record; by_city
  set       a Set of the records; by_age, by_city
  rkd       a RepeatedKeysDictionary id mod 7 -> record; by_age
  values    a List of 160 plain values (1, 1.0, Decimal 1, True, None, strings, bytes, dates,
            10**16 + 1, NaN, a list, a map, tuples), drawn with repetition; e_eq (EqualityIndex on
            the element) and e_rg (RangeIndex on the element)
  counted   a CountedSet of the orderable plain values, each counted 1 to 3 times; e_rg
  plain     the List of the records without indexes
  tiny      a List of two records; by_city (the planner scans it: an index costs more)

A record has id (0..PEOPLE-1), name 'p<id>', city (absent in about one in ten, None in one in ten),
age (absent in one in ten, None in one in twenty, otherwise an int, a float or a Decimal of the
same number or a half), score (an int 0..9, or a list or a map: unorderable, in one in fifteen) and
tags (a list of strings: unorderable).

queries.msgpack is a msgpack map: 'tag', 'seed', 'extractor' (the extractor's name) and 'cases',
an array of maps:

  id        a name for the case
  root      the root it queries
  source    'collection' (the root), 'scan' (root.as_query_plan()) or 'distinct'
            (Distinct(root.as_query_plan()): a plan source, so the planner puts a Filter on top)
  where     nil, or the wire form (codec.encode_value) of the 0.1 prefix list given to plan_query
  order     nil, or a list of [path, descending] pairs
  limit     nil or an int; offset an int
  wrap      nil, or what is put on top of the planned plan: 'count' (Count), 'distinct'
            (Distinct), ['project', [paths]] (Project, list form), ['project_map', [[name, path]...]]
            (Project, mapping form, in that order), ['intersect', wire of a second where]
            (Intersect of the plan and plan_query(root, that where)) or 'block_even'
            (PythonFilter(plan, id is even, 'even id'))
  plan      the explain tree of the final plan: a map 'node' (the msgpack bytes of the node's
            explain() without 'estimate' and 'children'), 'estimate' ([rows, cost]) and 'children'
            (the same maps of its sources, in order)
  rows      the rows of plan.execute(), in order, each the msgpack bytes of ['id', id] for a
            record, ['n', n] for the row of a Count, ['v', wire form] for any other value

The oracle: the elements of the source for which evaluate holds, sorted as test_index_equals_scan.py
sorts them (a stable pass per key, last key first, unorderable keys last); the planned rows must be
its multiset (no window), carry its key sequence (an order), and be a window of it; Count must count
it, Distinct keep its distinct identities, Project project it, Intersect answer the elements both
conditions hold for, PythonFilter its even ids.
"""
import hashlib
import random
import sys
from collections import Counter
from datetime import date
from decimal import Decimal
from pathlib import Path

import msgpack

from proto_db import FileStorage, ObjectSpace
from proto_db.core import codec
from proto_db.core.dbobject import DBObject
from proto_db.indexing import EqualityIndex, KeySpec, RangeIndex, element_identity, register_extractor
from proto_db.query.expressions import Expression, evaluate
from proto_db.query.planner import plan_query
from proto_db.query.plans import Count, Distinct, Intersect, Project, PythonFilter
from proto_db.values import MISSING, FrozenList, exact_token, is_orderable, order_key

TAG = "v2.0.0rc4"
SEED = 20261119
PEOPLE = 240
EXTRACTOR = "queries.vectors.name_len"
HERE = Path(__file__).resolve().parent
CITIES = ("Oslo", "Rome", "Paris", "Lima", "Kyiv", "Quito")


def check_pinned() -> None:
    """Refuse to run unless the imported proto_db is the commit setup_venv.sh pins (TAG_COMMIT)."""
    import proto_db
    setup = HERE / "setup_venv.sh"
    pinned = next((line.split('"')[1] for line in setup.read_text().splitlines()
                   if line.startswith('TAG_COMMIT="')), None)
    held_file = Path(proto_db.__file__).resolve().parent.parent / ".commit"
    held = held_file.read_text().strip() if held_file.is_file() else None
    if not pinned or not held or not held.startswith(pinned):
        sys.exit(f"py_query_vectors: proto_db at {Path(proto_db.__file__).parent} is commit {held or 'unknown'}, "
                 f"not the pinned {pinned} of setup_venv.sh ({TAG}); run it through the interop venv")


def name_len(element):
    name = KeySpec.path("name").extract(element)
    return len(name) if isinstance(name, str) else MISSING


def person(rng: random.Random, i: int) -> dict:
    attrs = {"id": i, "name": f"p{i}"}
    r = rng.random()
    if r >= 0.1:
        attrs["city"] = None if r < 0.2 else rng.choice(CITIES)
    r = rng.random()
    if r >= 0.1:
        years = rng.randrange(18, 61)
        attrs["age"] = None if r < 0.15 else rng.choice([years, float(years), Decimal(years), years + 0.5])
    attrs["score"] = (rng.choice([FrozenList([1]), {"a": 1}]) if rng.random() < 1 / 15 else rng.randrange(0, 10))
    attrs["tags"] = FrozenList(rng.sample(["x", "y", "z", "w"], rng.randrange(0, 3)))
    return attrs


PLAIN = [1, 1.0, Decimal("1"), Decimal("1.00"), True, False, None, 0, 2, 2.5, -1, 10 ** 16, 10 ** 16 + 1, "a", "b", "",
         "ab", b"x", b"", date(2026, 1, 1), date(2026, 1, 3), (1, "t"), (0, "a"), FrozenList([1]), {"k": 1},
         float("nan")]


def build(directory: Path, rng: random.Random) -> None:
    """Writes the database 'queries' (the module docstring)."""
    space = ObjectSpace(FileStorage(str(directory)))
    try:
        db = space.new_database("queries")
        tr = db.new_transaction()
        people = [tr.new_object(**person(rng, i)) for i in range(PEOPLE)]
        by_city, by_age = EqualityIndex("by_city", KeySpec.path("city")), RangeIndex("by_age", KeySpec.path("age"))
        lst = tr.new_list()
        for p in people:
            lst = lst.append_last(p)
        for p in rng.sample(people, 15):
            lst = lst.append_last(p)
        for index in (by_city, by_age, RangeIndex("by_id", KeySpec.path("id")),
                      EqualityIndex("by_score", KeySpec.path("score")), RangeIndex("by_len", KeySpec.extractor(EXTRACTOR))):
            lst = lst.add_index(index)
        d, h, s, rkd, plain = (tr.new_dictionary(), tr.new_hash_dictionary(), tr.new_set(),
                               tr.new_repeated_keys_dictionary(), tr.new_list())
        for p in people:
            d = d.set_at(p.id, p)
            h = h.set_at(p.id, p)
            s = s.add(p)
            rkd = rkd.set_at(p.id % 7, p)
            plain = plain.append_last(p)
        values = tr.new_list()
        for _ in range(160):
            values = values.append_last(rng.choice(PLAIN))
        counted = tr.new_counted_set()
        for v in PLAIN:
            if is_orderable(v):
                for _ in range(rng.randrange(1, 4)):
                    counted = counted.add(v)
        tiny = tr.new_list().append_last(people[0]).append_last(people[1])
        roots = {
            "list": lst,
            "dict": d.add_index(by_city).add_index(by_age),
            "hash": h.add_index(by_city),
            "set": s.add_index(by_age).add_index(by_city),
            "rkd": rkd.add_index(by_age),
            "values": values.add_index(EqualityIndex("e_eq", KeySpec.element())).add_index(RangeIndex("e_rg", KeySpec.element())),
            "counted": counted.add_index(RangeIndex("e_rg", KeySpec.element())),
            "plain": plain,
            "tiny": tiny.add_index(by_city),
        }
        for name, coll in roots.items():
            tr.set_root_object(name, coll)
        tr.commit()
    finally:
        space.close()


RECORD_ROOTS = ("list", "dict", "hash", "set", "rkd", "plain")


def record_cases():
    """(id suffix, where, order, limit, offset, wrap) over the records."""
    return [
        ("all", None, None, None, 0, None),
        ("city == Oslo", ["city", "==", "Oslo"], None, None, 0, None),
        ("city != Oslo", ["city", "!=", "Oslo"], None, None, 0, None),
        ("city ?N", ["city", "?N"], None, None, 0, None),
        ("! city ?N", ["!", "city", "?N"], None, None, 0, None),
        ("! city == Oslo", ["!", "city", "==", "Oslo"], None, None, 0, None),
        ("age < 30", ["age", "<", 30], None, None, 0, None),
        ("age == 30 (mixed numerics)", ["age", "==", 30], None, None, 0, None),
        ("age in 30, 31.0, Decimal 40", ["age", "in", [30, 31.0, Decimal("40")]], None, None, 0, None),
        ("age between[] 25 35", ["age", "between[]", 25, 35], None, None, 0, None),
        ("age between() 25 35", ["age", "between()", 25, 35], None, None, 0, None),
        ("age >= 0 (unselective)", ["age", ">=", 0], None, None, 0, None),
        ("age ?!N and city == Rome", ["age", "?!N", "city", "==", "Rome"], None, None, 0, None),
        ("age >= 18 and city == Rome", ["age", ">=", 18, "city", "==", "Rome"], None, None, 0, None),
        ("Oslo or Lima", ["|", "city", "==", "Oslo", "city", "==", "Lima"], None, None, 0, None),
        ("Oslo or age < 20", ["|", "city", "==", "Oslo", "age", "<", 20], None, None, 0, None),
        ("Oslo or name contains 7", ["|", "city", "==", "Oslo", "name", "contains", "7"], None, None, 0, None),
        ("(Oslo or Rome) and age > 40", ["&", ["|", "city", "==", "Oslo", "city", "==", "Rome"], "age", ">", 40],
         None, None, 0, None),
        ("not (Oslo and age < 30)", ["!", ["&", "city", "==", "Oslo", "age", "<", 30]], None, None, 0, None),
        ("not (city ?N or age ?N)", ["!", ["|", "city", "?N", "age", "?N"]], None, None, 0, None),
        ("id in", ["id", "in", [1, 5, 9, 200, 999]], None, None, 0, None),
        ("id < 10 and id < 10.0 (duplicate)", ["id", "<", 10, "id", "<", 10.0], None, None, 0, None),
        ("score == 3", ["score", "==", 3], None, None, 0, None),
        ("score ?T", ["score", "?T"], None, None, 0, None),
        ("score != 3", ["score", "!=", 3], None, None, 0, None),
        ("tags contains x", ["tags", "contains", "x"], None, None, 0, None),
        ("name length == 3 (extractor)", ["@" + EXTRACTOR, "==", 3], None, None, 0, None),
        ("name length >= 3 and city ?!N", ["@" + EXTRACTOR, ">=", 3, "city", "?!N"], None, None, 0, None),
        ("order age", None, [["age", False]], None, 0, None),
        ("order age desc", None, [["age", True]], None, 0, None),
        ("order city, id desc", None, [["city", False], ["id", True]], None, 0, None),
        ("Oslo order id desc", ["city", "==", "Oslo"], [["id", True]], None, 0, None),
        ("age > 25 order age", ["age", ">", 25], [["age", False]], None, 0, None),
        ("order id window 3+5", None, [["id", False]], 5, 3, None),
        ("Rome order id desc limit 3", ["city", "==", "Rome"], [["id", True]], 3, 0, None),
        ("order age offset 230", None, [["age", False]], None, 230, None),
        ("order name length desc limit 4", None, [["@" + EXTRACTOR, True]], 4, 0, None),
        ("order id limit 0", None, [["id", False]], 0, 0, None),
        ("Oslo count", ["city", "==", "Oslo"], None, None, 0, "count"),
        ("count", None, None, None, 0, "count"),
        ("age < 30 distinct", ["age", "<", 30], None, None, 0, "distinct"),
        ("Oslo project list", ["city", "==", "Oslo"], None, None, 0, ["project", ["name", "age", "zz"]]),
        ("Oslo project mapping", ["city", "==", "Oslo"], None, None, 0, ["project_map", [["who", "name"], ["years", "age"]]]),
        ("Oslo intersect age < 40", ["city", "==", "Oslo"], None, None, 0, ["intersect", ["age", "<", 40]]),
        ("age < 40 order id block filter", ["age", "<", 40], [["id", False]], None, 0, "block_even"),
    ]


def value_cases():
    """(id suffix, where, order, limit, offset, wrap) over the plain values."""
    return [
        ("all", None, None, None, 0, None),
        ("== 1", [None, "==", 1], None, None, 0, None),
        ("== True", [None, "==", True], None, None, 0, None),
        ("in 1, True, 10**16+1", [None, "in", [1, True, 10 ** 16 + 1]], None, None, 0, None),
        ("!= 1", [None, "!=", 1], None, None, 0, None),
        ("?N", [None, "?N"], None, None, 0, None),
        ("?!N", [None, "?!N"], None, None, 0, None),
        ("< 2", [None, "<", 2], None, None, 0, None),
        ("between() 0 2", [None, "between()", 0, 2], None, None, 0, None),
        ("between[] dates", [None, "between[]", date(2026, 1, 1), date(2026, 1, 2)], None, None, 0, None),
        ("== 1 or == a", ["|", None, "==", 1, None, "==", "a"], None, None, 0, None),
        ("not == 1", ["!", None, "==", 1], None, None, 0, None),
        ("contains a", [None, "contains", "a"], None, None, 0, None),
        ("?T", [None, "?T"], None, None, 0, None),
        ("order element", None, [[None, False]], None, 0, None),
        ("order element desc window 10+7", None, [[None, True]], 7, 10, None),
        ("?!N order element desc", [None, "?!N"], [[None, True]], None, 0, None),
        ("distinct", None, None, None, 0, "distinct"),
        ("< 2 count", [None, "<", 2], None, None, 0, "count"),
    ]


def cases():
    out = []
    for root in RECORD_ROOTS:
        for name, where, order, limit, offset, wrap in record_cases():
            out.append((f"{root}: {name}", root, "collection", where, order, limit, offset, wrap))
    for root in ("values", "counted"):
        for name, where, order, limit, offset, wrap in value_cases():
            out.append((f"{root}: {name}", root, "collection", where, order, limit, offset, wrap))
    out += [
        ("list scan: city == Oslo", "list", "scan", ["city", "==", "Oslo"], None, None, 0, None),
        ("list scan: Oslo or Lima order age", "list", "scan", ["|", "city", "==", "Oslo", "city", "==", "Lima"],
         [["age", False]], None, 0, None),
        ("list distinct source: city == Oslo", "list", "distinct", ["city", "==", "Oslo"], None, None, 0, None),
        ("list distinct source: order id limit 4", "list", "distinct", None, [["id", False]], 4, 0, None),
        ("tiny: city == Oslo", "tiny", "collection", ["city", "==", "Oslo"], None, None, 0, None),
        ("tiny: order city", "tiny", "collection", None, [["city", False]], None, 0, None),
    ]
    return out


def wire_bytes(value) -> bytes:
    return msgpack.packb(codec.encode_value(value, lambda a: (_ for _ in ()).throw(ValueError("an atom"))),
                         use_bin_type=True)


def tree(plan) -> dict:
    """The explain tree of plan (the module docstring, 'plan')."""
    info = plan.explain()
    return _tree(info)


def _tree(info) -> dict:
    node = {k: v for k, v in info.items() if k not in ("estimate", "children")}
    return {"node": msgpack.packb(node, use_bin_type=True),
            "estimate": [info["estimate"]["rows"], info["estimate"]["cost"]],
            "children": [_tree(child) for child in info["children"]]}


def row_bytes(row, counted: bool) -> bytes:
    if counted:
        return msgpack.packb(["n", row], use_bin_type=True)
    if isinstance(row, DBObject):
        return msgpack.packb(["id", row.id], use_bin_type=True)
    return msgpack.packb(["v", codec.encode_value(row, lambda a: (_ for _ in ()).throw(ValueError("an atom")))],
                         use_bin_type=True)


def ident(e):
    return element_identity(e), exact_token(e)


def slot(value):
    return (0, order_key(value)) if is_orderable(value) else (1,)


def key_slots(element, order):
    return tuple(slot(KeySpec.for_term_path(path).extract(element)) for path, _ in order)


def oracle(elements, expr, order):
    rows = [e for e in elements if expr is None or evaluate(expr, e)]
    for path, descending in reversed(order or []):
        spec = KeySpec.for_term_path(path)
        rows.sort(key=lambda e: slot(spec.extract(e)), reverse=descending)
    return rows


def check(case_id, got, expected, order, limit, offset, wrap, elements, where2) -> None:
    """Refuses (exits) unless got is what the scan oracle says (the module docstring)."""
    def refuse(why):
        sys.exit(f"py_query_vectors: {case_id}: {why}; nothing written")
    if wrap == "count":
        if got != [len(expected)]:
            refuse(f"count {got} is not {len(expected)}")
        return
    if wrap == "distinct":
        if Counter(map(ident, got)) != Counter(set(map(ident, expected))):
            refuse("distinct rows differ from the scan's distinct elements")
        return
    if isinstance(wrap, list) and wrap[0] in ("project", "project_map"):
        pairs = [(p, p) for p in wrap[1]] if wrap[0] == "project" else [tuple(pair) for pair in wrap[1]]
        want = [{n: KeySpec.for_term_path(p).extract(e) for n, p in pairs
                 if KeySpec.for_term_path(p).extract(e) is not MISSING} for e in expected]
        if sorted(map(repr, got)) != sorted(map(repr, want)):
            refuse("projected rows differ from the scan projected")
        return
    if isinstance(wrap, list) and wrap[0] == "intersect":
        second = Expression.compile(where2)
        want = [e for e in expected if evaluate(second, e)]
        if Counter(map(ident, got)) != Counter(map(ident, want)):
            refuse("the intersection differs from the scan of both conditions")
        return
    if wrap == "block_even":
        expected = [e for e in expected if e.id % 2 == 0]
    stop = None if limit is None else offset + limit
    window = expected[offset:stop]
    if len(got) != len(window):
        refuse(f"{len(got)} rows, the scan's window has {len(window)}")
    if limit is None and not offset and Counter(map(ident, got)) != Counter(map(ident, expected)):
        refuse("rows differ from the scan")
    if order:
        if [key_slots(e, order) for e in got] != [key_slots(e, order) for e in window]:
            refuse("the key sequence differs from the sorted scan")
    elif not Counter(map(ident, got)) <= Counter(map(ident, expected)):
        refuse("an unordered window holds rows the scan does not")


def main() -> None:
    check_pinned()
    register_extractor(EXTRACTOR, name_len, version="1")
    out = Path(sys.argv[1])
    if out.exists():
        sys.exit(f"py_query_vectors: {out} exists; give a new directory")
    out.mkdir(parents=True)
    rng = random.Random(SEED)
    build(out / "space", rng)
    space = ObjectSpace(FileStorage(str(out / "space")))
    rows_out = []
    try:
        tr = space.open_database("queries").new_transaction()
        for case_id, root, source_kind, where, order, limit, offset, wrap in cases():
            coll = tr.get_root_object(root)
            source = {"collection": coll, "scan": coll.as_query_plan(),
                      "distinct": Distinct(coll.as_query_plan())}[source_kind]
            plan = plan_query(source, where, order_by=[tuple(k) for k in order] if order else None,
                              limit=limit, offset=offset)
            elements = list(coll.elements())
            if source_kind == "distinct":
                seen, distinct = set(), []
                for e in elements:
                    if ident(e) not in seen:
                        seen.add(ident(e))
                        distinct.append(e)
                elements = distinct
            expr = None if where is None else Expression.compile(where)
            where2 = None
            if wrap == "count":
                plan = Count(plan)
            elif wrap == "distinct":
                plan = Distinct(plan)
            elif wrap == "block_even":
                plan = PythonFilter(plan, lambda e: e.id % 2 == 0, "even id")
            elif isinstance(wrap, list) and wrap[0] == "project":
                plan = Project(plan, list(wrap[1]))
            elif isinstance(wrap, list) and wrap[0] == "project_map":
                plan = Project(plan, {n: p for n, p in wrap[1]})
            elif isinstance(wrap, list) and wrap[0] == "intersect":
                where2 = wrap[1]
                plan = Intersect(plan, plan_query(coll, where2))
            got = list(plan.execute())
            if list(plan.execute()) != got:
                sys.exit(f"py_query_vectors: {case_id}: a second execution differs; nothing written")
            check(case_id, got, oracle(elements, expr, order), order, limit, offset, wrap, elements, where2)
            stored_wrap = wrap if not (isinstance(wrap, list) and wrap[0] == "intersect") else ["intersect", wire_bytes(where2)]
            rows_out.append({"id": case_id, "root": root, "source": source_kind,
                             "where": None if where is None else wire_bytes(where),
                             "order": order, "limit": limit, "offset": offset, "wrap": stored_wrap,
                             "plan": tree(plan), "rows": [row_bytes(r, wrap == "count") for r in got]})
        tr.abort()
    finally:
        space.close()
    blob = msgpack.packb({"tag": TAG, "seed": SEED, "extractor": EXTRACTOR, "cases": rows_out}, use_bin_type=True)
    (out / "queries.msgpack").write_bytes(blob)
    files = sorted([out / "queries.msgpack"] + [p for p in (out / "space").rglob("*") if p.is_file()])
    manifest = "".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(out).as_posix()}\n" for p in files)
    (out / "manifest.sha256").write_text(manifest)
    names = Counter(name for case in rows_out for name in _names(case["plan"]))
    print(f"wrote {len(rows_out)} cases to {out}; plan nodes {dict(sorted(names.items()))}")


def _names(node):
    yield msgpack.unpackb(node["node"], raw=False, strict_map_key=False)["plan"]
    for child in node["children"]:
        yield from _names(child)


if __name__ == "__main__":
    main()
