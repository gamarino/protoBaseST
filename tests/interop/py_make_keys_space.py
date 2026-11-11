"""Write the space of Review Focus 1 (cross-kind keys), read by tests/unit/read_cross_kind_keys.st.

Usage: python py_make_keys_space.py <directory>

One database 'keys' whose roots are a Dictionary ('d'), a HashDictionary ('h'), a Set ('s')
and a CountedSet ('cs'), all keyed by the int 1, the int 10**16 + 1 and the float 1.0e16.
ProtoBase's order keys make 1, 1.0 and Decimal('1.00') one key, True another, and
10**16 + 1 and 1.0e16 two keys (1.0e16 is exactly 10**16).

The roots that pin the lookup rules (review I2 of plan Task 12):
  'td', 'th', 'ts', 'tcs'  the four collections keyed by the tuple (1, 'x'): (1.0, 'x') and
                           (Decimal('1.00'), 'x') are the same key by order key, though not
                           equal by protoST's = (a bucket compared with = would miss them)
  'dd', 'dh', 'ds', 'dcs'  a stored Decimal('1.00') ('dec'; counted twice), found by 1, 1.0
                           and Decimal 1
  'bd', 'bh'               True ('true') next to 1 ('one'): two keys

Run with the interop venv
(tests/interop/env.sh): ProtoBase v2.0.0rc1 on PYTHONPATH.
"""
import sys
from decimal import Decimal

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

        t = (1, "x")
        tx.set_root_object("td", tx.new_dictionary().set_at(t, "tuple"))
        tx.set_root_object("th", tx.new_hash_dictionary().set_at(t, "tuple"))
        tx.set_root_object("ts", tx.new_set().add(t))
        tx.set_root_object("tcs", tx.new_counted_set().add(t).add(t))

        dec = Decimal("1.00")
        tx.set_root_object("dd", tx.new_dictionary().set_at(dec, "dec"))
        tx.set_root_object("dh", tx.new_hash_dictionary().set_at(dec, "dec"))
        tx.set_root_object("ds", tx.new_set().add(dec))
        tx.set_root_object("dcs", tx.new_counted_set().add(dec).add(dec))

        bd = tx.new_dictionary().set_at(True, "true").set_at(1, "one")
        bh = tx.new_hash_dictionary().set_at(True, "true").set_at(1, "one")
        assert bd.count == 2 and bh.count == 2 and bd.get_at(True) == "true" and bh.get_at(1) == "one"
        tx.set_root_object("bd", bd)
        tx.set_root_object("bh", bh)
        tx.commit()
    finally:
        space.close()


if __name__ == "__main__":
    main(sys.argv[1])
