"""Ties among atoms in an exact vector search (vectors phase V8, fix round 2; Addendum V, 2.4 and
2.5): proto_db v2.0.0rc4's side of tests/interop/vector_ties_identical.sh, pure Python (numpy and
hnswlib blocked before proto_db is imported).

200 DBObjects { i, vec } of dim 4 under an exact index (ip, then cosine) and a zero query, k = 10:
every score is 0.0, so the answer is decided by the tie rule alone, (-score, order_key(member
key)) in rank_entries (vector_backends.py:147-167), whose member key of an atom orders by its oid
(values.py order_key: (_R_ATOM, oid.int)). Twice: with the random version-4 oids an atom draws on
first need (D21), where the answer must be the ten records of least order key, ascending, in this
process; then with injected oids (record i gets the UUID integer (37 i mod 200) + 1), where the
answer is the same list in every process and in protoBaseST (_st_vector_ties.st). Prints one line
per check, then 'end'."""
import sys
import uuid

sys.modules["numpy"] = None
sys.modules["hnswlib"] = None
from proto_db import DBObject  # noqa: E402
from proto_db.indexing import KeySpec  # noqa: E402
from proto_db.indexing.vector import VectorIndex  # noqa: E402
from proto_db.query.plans import VectorSearch  # noqa: E402
from proto_db.query.terms import NEAR, NearQuery, Term  # noqa: E402
from proto_db.values import order_key  # noqa: E402

N, DIM = 200, 4
ZERO = tuple(0.0 for _ in range(DIM))


def vec(i):
    return tuple(float(((i * 7 + j * 3) % 11) - 5) + 0.5 for j in range(DIM))


def run(recs, metric):
    idx = VectorIndex("by_vec", KeySpec.path("vec"), DIM, metric, "exact").build(recs)
    return [e.i for e in VectorSearch(idx, Term("vec", NEAR, NearQuery(ZERO, k=10))).execute()]


def main():
    recs = [DBObject(i=i, vec=vec(i)) for i in range(N)]
    for m in ("ip", "cosine"):
        by_oid = [r.i for r in sorted(recs, key=order_key)][:10]
        print(f"random-oids {m} answer-is-oid-order {run(recs, m) == by_oid}")
    recs = [DBObject(i=i, vec=vec(i)) for i in range(N)]
    for r in recs:
        object.__setattr__(r, "oid", uuid.UUID(int=((r.i * 37) % N) + 1))
    for m in ("ip", "cosine"):
        print(f"injected-oids {m} {run(recs, m)}")
    print("end")


if __name__ == "__main__":
    main()
