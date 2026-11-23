"""Chapter 20's recall block (examples/tutorial/20_vector_search.st), ported to proto_db v2.0.0rc4.

Usage: python py_chapter20_recall.py <directory that does not exist yet>

The same path as the chapter's program: the 600 documents and the short vector committed to a
database, then, for each nprobe, an IVF-Flat index (nlist 16) grown by appending the stored
documents one by one in a transaction, and the 40 queries of the block against a brute force.
Every run gives the records fresh oids. Prints the hits out of 400 at nprobe 1, 4 and 16 on one
line. Run with the reference venv (tests/interop/.venv, numpy absent) and with
tests/interop/.venv-numpy for proto_db's default mode; docs/tutorial/20-vector-search.md
("IVF-Flat") records what both gave. Not a test: it asserts nothing.
"""
import math
import sys

from proto_db import F, FileStorage, ObjectSpace, VectorIndex, from_collection

topics = ["sports", "music", "science"]
seed = 7


def nxt():
    global seed
    seed = seed * 16807 % 2147483647
    return seed / 2147483647.0 * 2.0 - 1.0


docs_data = [(i, topics[i % 3], [nxt() for _ in range(8)]) for i in range(600)]
space = ObjectSpace(FileStorage(sys.argv[1]))
db = space.new_database("docs")
with db.new_transaction() as t:
    coll = t.new_list().add_index(VectorIndex("by_vec", "vec", dim=8, metric="cosine"))
    for i, topic, vec in docs_data:
        coll = coll.append_last(t.new_object(i=i, topic=topic, vec=vec))
    coll = coll.append_last(t.new_object(i=600, topic="music", vec=[1.0, 2.0]))
    t.set_root_object("docs", coll)
docs = db.new_transaction().get_root_object("docs")
all_docs = list(docs)


def dot(a, b):
    s = 0.0
    for j in range(len(a)):
        s = s + a[j] * b[j]
    return s


def cosine(a, b):
    return dot(a, b) / (math.sqrt(dot(a, a)) * math.sqrt(dot(b, b)))


target = list(next(d for d in all_docs if d.i == 42).vec)
ranked = sorted([d for d in all_docs if len(d.vec) == 8], key=lambda d: -cosine(target, d.vec))


def recall(nprobe):
    with db.new_transaction() as t:
        ivf = t.new_list().add_index(VectorIndex("ivf", "vec", dim=8, metric="cosine", backend="ivf_flat",
                                                 nlist=16, nprobe=nprobe))
        for d in docs:
            ivf = ivf.append_last(d)
        t.set_root_object("ivf", ivf)
    coll = db.new_transaction().get_root_object("ivf")
    hits = 0
    for q in range(40):
        vec = next(d for d in ranked if d.i == q * 13).vec
        truth = {d.i for d in sorted(ranked, key=lambda d: -cosine(vec, d.vec))[:10]}
        found = {d.i for d in from_collection(coll).where(F.vec.near(list(vec), k=10))}
        hits += len(truth & found)
    return hits


print(" ".join(str(recall(n)) for n in (1, 4, 16)))
space.close()
