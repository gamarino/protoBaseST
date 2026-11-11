"""Write the space of Review Focus 1 (cross-kind keys), read by tests/unit/read_cross_kind_keys.st.

Usage: python py_make_keys_space.py <directory>

One database 'keys' whose roots are a Dictionary ('d'), a HashDictionary ('h'), a Set ('s')
and a CountedSet ('cs'), all keyed by the int 1, the int 10**16 + 1 and the float 1.0e16.
ProtoBase's order keys make 1, 1.0 and Decimal('1.00') one key, True another, and
10**16 + 1 and 1.0e16 two keys (1.0e16 is exactly 10**16). Run with the interop venv
(tests/interop/env.sh): ProtoBase v2.0.0rc1 on PYTHONPATH.
"""
import sys

from proto_db import FileStorage, ObjectSpace


def main(directory: str) -> None:
    space = ObjectSpace(FileStorage(directory))
    try:
        db = space.new_database("keys")
        tx = db.new_transaction()
        d = tx.new_dictionary().set_at(1, "one").set_at(10**16 + 1, "big int").set_at(1.0e16, "big float")
        h = tx.new_hash_dictionary().set_at(1, "one").set_at(10**16 + 1, "big int").set_at(1.0e16, "big float")
        s = tx.new_set().add(1).add(10**16 + 1).add(1.0e16)
        cs = tx.new_counted_set().add(1).add(1).add(1.0e16)
        assert d.get_at(1.0) == "one" and d.get_at(True) is None and d.count == 3
        tx.set_root_object("d", d)
        tx.set_root_object("h", h)
        tx.set_root_object("s", s)
        tx.set_root_object("cs", cs)
        tx.commit()
    finally:
        space.close()


if __name__ == "__main__":
    main(sys.argv[1])
