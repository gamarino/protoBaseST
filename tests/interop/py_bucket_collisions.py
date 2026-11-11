"""ProtoBase's side of bucket_collisions_identical.sh (Task 16 review M2).

Usage: python py_bucket_collisions.py

Runs the fixed operation sequences below on a HashDictionary and a Set whose _bucket_hash
files every key under 7 (ProtoBase's seam for forcing collisions) and prints, after each
operation, '<kind> <op> <args> => count <n> node <hash or none> bucket <hex or none>', where
the bucket is the msgpack bytes of codec.encode_value of the bucket tuple. _st_bucket_collisions.st
prints the same lines for protoBaseST's _bucketHash: seam; the shell script requires them identical.
"""
import msgpack

from proto_db.collections.hash_dictionaries import HashDictionary
from proto_db.collections.sets import Set
from proto_db.core import codec


class CollidingHashDictionary(HashDictionary):
    def _bucket_hash(self, key):
        return 7


class CollidingSet(Set):
    def _bucket_hash(self, element):
        return 7


DICT_OPS = [("set", "a", 1), ("set", "b", 2), ("set", "c", 3), ("set", "b", 20), ("set", 1, "x"),
            ("set", 1.0, "y"), ("remove", "b"), ("remove", "zz"), ("remove", "c"), ("remove", "a"),
            ("remove", 1)]
SET_OPS = [("add", "a"), ("add", "b"), ("add", "c"), ("add", 1), ("add", 1.0), ("remove", "b"),
           ("remove", "zz"), ("remove", "a"), ("remove", "c"), ("remove", 1)]


def arg(value):
    return f"f{value!r}" if isinstance(value, float) else repr(value)


def show(kind, op, coll):
    root = coll.root
    node = "none" if root is None else str(root.key)
    bucket = "none" if root is None else msgpack.packb(codec.encode_value(root.value, None)).hex()
    args = " ".join(arg(a) for a in op[1:])
    print(f"{kind} {op[0]} {args} => count {coll.count} node {node} bucket {bucket}")


d = CollidingHashDictionary()
for op in DICT_OPS:
    d = d.set_at(op[1], op[2]) if op[0] == "set" else d.remove_at(op[1])
    show("dict", op, d)
s = CollidingSet()
for op in SET_OPS:
    s = s.add(op[1]) if op[0] == "add" else s.remove(op[1])
    show("set", op, s)
