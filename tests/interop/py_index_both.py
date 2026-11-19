"""Indexed collections written by one implementation and changed by the other, ProtoBase's side
(indexed queries, plan Task 4b, spec 6.1.3; tests/interop/index_both_directions.sh; protoBaseST's
side is _st_index_both.st, which runs the same steps).

Usage: python py_index_both.py make <directory>      a new space with the indexed roots
       python py_index_both.py change <directory>    every mutator, index definitions and merges
       python py_index_both.py check <directory>     validate(), then index lookups against scans
       python py_index_both.py content <directory>   the content of every root, one line each

The records: record(i) is a DBObject with n = i, w = i % 4 and v = i % 5 (i % 4 = 0), 's<i % 3>'
(i % 4 = 1), None (i % 4 = 2), absent (i % 4 = 3). The index definitions: 'eq_v' (EqualityIndex
on the path 'v'), 'rg_w' (RangeIndex on the extractor 'interop.both.w', the path 'w'), 'rg_n'
(RangeIndex on the path 'n'); the changes add 'eq_w' (EqualityIndex on 'w') and 'eq_v2'
(EqualityIndex on 'v'), and remove 'rg_n'.

make: one transaction on a new database 'both' writes the roots 'list' (List of records 0..19),
'dict' and 'hash' (Dictionary and HashDictionary, key i -> record i), 'set' (Set of the records)
and 'bag' (CountedSet, the even records twice), each with the three indexes added after the
content.

change: transaction 1 reads every root and runs every mutator of its kind (an element of the
loaded content is found by its n, never by its position in hash order, which depends on oids),
adds 'eq_w' and removes 'rg_n'; then two transactions, A and B, blind-write 'dict', 'hash', 'set'
and 'bag' (new collections, the roots never read; B also adds 'eq_v2' to 'dict'), B committed
first, then A: both merge onto the indexed current values (D33, base.py rebase_onto).

check: validate() on every root (structure and every index against the elements), then every
index answers like a scan: for every key among the elements, the plan of Term(path, '==', key)
returns exactly the elements whose key equals it, and for a range index the plan of
Term(path, '>=', k) too for every orderable key k (tests/concurrency/test_indexed_roots.py
assert_index_matches_scan). Prints one summary line per root.

content: per root, its kind, count, index names and the sorted (n, occurrences) of its elements
(by key for the dictionaries): what both implementations and both directions must agree on.
"""
import sys

from proto_db import FileStorage, ObjectSpace
from proto_db.collections.dictionaries import Dictionary
from proto_db.collections.hash_dictionaries import HashDictionary
from proto_db.collections.lists import List
from proto_db.collections.sets import CountedSet, Set
from proto_db.core.dbobject import DBObject
from proto_db.indexing import EqualityIndex, KeySpec, RangeIndex, register_extractor
from proto_db.values import MISSING
from proto_db.query.terms import Term, is_orderable

EXTRACTOR = "interop.both.w"
ROOTS = ["list", "dict", "hash", "set", "bag"]


def register():
    register_extractor(EXTRACTOR, lambda e: KeySpec.path("w").extract(e), version="1")


def record(i):
    attrs = {"n": i, "w": i % 4}
    if i % 4 == 0:
        attrs["v"] = i % 5
    elif i % 4 == 1:
        attrs["v"] = f"s{i % 3}"
    elif i % 4 == 2:
        attrs["v"] = None
    return DBObject(**attrs)


def definitions():
    return [EqualityIndex("eq_v", KeySpec.path("v")), RangeIndex("rg_w", KeySpec.extractor(EXTRACTOR)),
            RangeIndex("rg_n", KeySpec.path("n"))]


def with_indexes(coll):
    for index in definitions():
        coll = coll.add_index(index)
    return coll


def make(directory):
    register()
    space = ObjectSpace(FileStorage(directory))
    try:
        db = space.new_database("both")
        tr = db.new_transaction()
        records = [record(i) for i in range(20)]
        lst, d, h, s, bag = tr.new_list(), tr.new_dictionary(), tr.new_hash_dictionary(), tr.new_set(), tr.new_counted_set()
        for r in records:
            lst = lst.append_last(r)
            d = d.set_at(r.n, r)
            h = h.set_at(r.n, r)
            s = s.add(r)
            bag = bag.add(r)
            if r.n % 2 == 0:
                bag = bag.add(r)
        for name, coll in zip(ROOTS, [lst, d, h, s, bag]):
            tr.set_root_object(name, with_indexes(coll))
        tr.commit()
    finally:
        space.close()


def find(coll, n):
    """The element of coll whose n is n."""
    for e in coll.elements():
        if e.n == n:
            return e
    raise SystemExit(f"py_index_both.py: no element with n {n}")


def change(directory):
    register()
    space = ObjectSpace(FileStorage(directory))
    try:
        db = space.open_database("both")
        r = {i: record(i) for i in range(20, 40)}
        eq_w = EqualityIndex("eq_w", KeySpec.path("w"))
        tr = db.new_transaction()
        lst = tr.get_root_object("list")
        lst = lst.insert_at(2, r[20]).append_first(r[21]).append_last(r[22]).set_at(5, r[23]).remove_at(7)
        lst = lst.extend([r[24], r[25]]).slice(1, 21).head(19).tail(2)
        tr.set_root_object("list", lst.add_index(eq_w).remove_index("rg_n"))
        for name in ("dict", "hash"):
            d = tr.get_root_object(name)
            d = d.set_at(20, r[26]).set_at(3, r[27]).remove_at(4).remove_at(99)
            tr.set_root_object(name, d.add_index(eq_w).remove_index("rg_n"))
        s = tr.get_root_object("set")
        s = s.add(r[28]).add(find(s, 3)).remove(find(s, 5)).remove(r[39]).union([r[29], r[30]])
        s = s.intersection([e for e in s.elements() if e.n != 6]).difference([r[29]])
        tr.set_root_object("set", s.add_index(eq_w).remove_index("rg_n"))
        bag = tr.get_root_object("bag")
        bag = bag.add(r[31]).add(find(bag, 2)).remove(find(bag, 4)).remove(find(bag, 1))
        tr.set_root_object("bag", bag.add_index(eq_w).remove_index("rg_n"))
        tr.commit()
        a = db.new_transaction()
        b = db.new_transaction()
        a.set_root_object("dict", a.new_dictionary().set_at(40, r[32]))
        b.set_root_object("dict", b.new_dictionary().set_at(41, r[33]).remove_at(20)
                          .add_index(EqualityIndex("eq_v2", KeySpec.path("v"))))
        a.set_root_object("hash", a.new_hash_dictionary().set_at(40, r[32]))
        b.set_root_object("hash", b.new_hash_dictionary().set_at(41, r[33]).remove_at(3))
        a.set_root_object("set", a.new_set().add(r[34]))
        b.set_root_object("set", b.new_set().add(r[35]).remove(r[28]))
        a.set_root_object("bag", a.new_counted_set().add(r[36]).add(r[36]))
        b.set_root_object("bag", b.new_counted_set().add(r[37]).remove(r[31]))
        b.commit()
        a.commit()
    finally:
        space.close()


def term_path(index):
    return index.key_spec.term_path


def check(directory):
    register()
    space = ObjectSpace(FileStorage(directory))
    try:
        tr = space.open_database("both").new_transaction()
        for name in ROOTS:
            coll = tr.get_root_object(name)
            coll.validate()
            elements = list(coll.elements())
            lookups = 0
            for index_name in coll.index_names():
                index = coll.get_index(index_name)
                spec, path = index.key_spec, term_path(index)
                keys = []
                for e in elements:
                    k = spec.extract(e)
                    if k is not MISSING and all(not (type(k) is type(x) and k == x) for x in keys):
                        keys.append(k)
                terms = [Term(path, "==", k) for k in keys]
                if isinstance(index, RangeIndex):
                    terms += [Term(path, ">=", k) for k in keys if is_orderable(k)]
                for term in terms:
                    planned = sorted(e.n for e in index.plan(term).execute())
                    scanned = sorted(e.n for e in elements if term.matches(e))
                    if planned != scanned:
                        raise SystemExit(f"py_index_both.py: {name}.{index_name}: {term} planned {planned}, scanned {scanned}")
                    lookups += 1
            print(f"checked {name}: {coll.count} elements, indexes {','.join(coll.index_names())}, {lookups} lookups equal to scans")
        tr.abort()
    finally:
        space.close()


def content(directory):
    register()
    space = ObjectSpace(FileStorage(directory))
    try:
        tr = space.open_database("both").new_transaction()
        for name in ROOTS:
            coll = tr.get_root_object(name)
            if isinstance(coll, (Dictionary, HashDictionary)):
                items = sorted((k, v.n) for k, v in coll.items())
            elif isinstance(coll, CountedSet):
                items = sorted((e.n, n) for e, n in coll.items())
            elif isinstance(coll, List):
                items = [e.n for e in coll.elements()]
            else:
                items = sorted(e.n for e in coll.elements())
            print(f"{name} {type(coll).__name__} count={coll.count} indexes={','.join(coll.index_names())} {items}")
        tr.abort()
    finally:
        space.close()


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("make", "change", "check", "content"):
        raise SystemExit("usage: py_index_both.py make|change|check|content <directory>")
    {"make": make, "change": change, "check": check, "content": content}[sys.argv[1]](sys.argv[2])
