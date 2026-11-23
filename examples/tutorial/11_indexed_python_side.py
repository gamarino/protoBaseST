"""Lesson 11, indexed part, Python's two steps (see 11_indexed_interop.sh).

Usage: python 11_indexed_python_side.py write|check <directory>

Every read is asserted, so a wrong value stops the script with an AssertionError and a non-zero
exit.
"""
import sys

import math

from proto_db import EqualityIndex, F, FileStorage, ObjectSpace, RangeIndex, VectorIndex, from_collection

CITIES = ["Lima", "Oslo", "Paris", "Rome"]
QUERY = [12.25, 3.0, 0.5]


def place(i):
    """Document i's embedding: three components, no two documents at the same distance from QUERY."""
    return [float(i), float(i * i % 11), 0.5]


def write(space):
    """Forty people with two indexes, written by proto_db."""
    db = space.new_database("people")
    with db.new_transaction() as tr:
        people = tr.new_dictionary()
        for i in range(40):
            people = people.set_at(i, tr.new_object(name=f"person{i}", city=CITIES[i % 4], age=18 + i))
        people = people.add_index(EqualityIndex("by_city", "city")).add_index(RangeIndex("by_age", "age"))
        tr.set_root_object("people", people)
        docs = tr.new_dictionary().add_index(VectorIndex("by_vec", "vec", dim=3, metric="l2"))
        for i in range(40):
            docs = docs.set_at(i, tr.new_object(title=f"doc{i}", vec=place(i)))
        tr.set_root_object("docs", docs)
    print("python wrote 40 people with the indexes by_age and by_city, and 40 documents with by_vec")


def check(space):
    """What protoST changed, checked by proto_db: every index against a scan, and a planned query."""
    db = space.open_database("people")
    tr = db.new_transaction()
    people = tr.get_root_object("people")
    people.validate()
    assert people.index_names() == ["by_age", "by_city"], people.index_names()
    oslo = from_collection(people).where(F.city == "Oslo")
    assert oslo.explain()["plan"] == "IndexLookup", oslo.explain()
    assert oslo.count() == 12, oslo.count()
    assert len(people) == 41, len(people)
    docs = tr.get_root_object("docs")
    docs.validate()
    assert docs.index_names() == ["by_vec"], docs.index_names()
    nearest = from_collection(docs).where(F.vec.near(QUERY, k=3))
    assert nearest.explain()["plan"] == "VectorSearch", nearest.explain()
    brute = sorted(docs.values(), key=lambda d: math.dist(QUERY, d.vec))[:3]
    assert [d.title for d in nearest.to_list()] == [d.title for d in brute], nearest.to_list()
    assert [d.title for d in brute[:2]] == ["doc40", "doc41"], [d.title for d in brute]
    assert len(docs) == 41, len(docs)
    tr.abort()
    print("python validated protoST's changes: every index equals a scan, Oslo has 12 people, "
          "and the vector index answers protoST's two documents first")


space = ObjectSpace(FileStorage(sys.argv[2]))
try:
    {"write": write, "check": check}[sys.argv[1]](space)
finally:
    space.close()
