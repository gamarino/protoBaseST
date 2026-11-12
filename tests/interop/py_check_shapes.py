"""ProtoBase's reader of the space protoST wrote (tests/interop/st_to_py.sh, design spec 10.3).

Usage: python py_check_shapes.py <directory>

Reads database 'erp' as written by _st_write_shapes.st and asserts, with ProtoBase's own API:

* the three versions, the records (demo.erp.Invoice and Customer), the mutable cells, and
  the paid invoice and renamed customer of version 3;
* the CountedSet 'bag' at version 2 and after the blind adds of version 3, merged by the
  counter transform (D26), with the element object written first kept;
* plan Review Focus 4: the integer boundaries 2^63-1, 2^63, 2^64-1, 2^64, -2^63, -2^63-1
  (and 2^64+1) survive as values and as Dictionary keys, are found by their value, are
  ordered as numbers, and 1.8446744073709552e19 (2^64 exactly) finds the key 2^64;
* plan Review Focus 2: of the strings of 254, 255, 256 and 300 code points, those of 254 and
  255 (two bytes per code point) are stored in their nodes, and those of 256 and 300 in a
  ValueBox; all four read back equal to what protoST wrote.

Exit 0 when every check holds, 1 otherwise (each failed check is printed).
"""
import sys
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "examples" / "erp"))

import erp_model  # noqa: E402,F401  (registers demo.erp.*)
from proto_db import FileStorage, ObjectSpace  # noqa: E402
from proto_db.collections.avl import ValueBox  # noqa: E402

FAILURES = []


def check(label, actual, expected):
    if actual != expected:
        FAILURES.append(f"{label}: expected {expected!r}, got {actual!r}")


def stored_values(node):
    """The values the nodes of a positional tree hold, as stored (a ValueBox stays a box)."""
    if node is None:
        return
    yield from stored_values(node.left)
    yield node.value
    yield from stored_values(node.right)


def main(directory):
    space = ObjectSpace(FileStorage(directory))
    try:
        db = space.open_database("erp")
        check("versions", [e.version for e in db.history()], [3, 2, 1, 0])
        tx = db.new_transaction()

        invoices = tx.get_root_object("invoices")
        check("invoice numbers", list(invoices.keys()), [1001, 1002])
        paid = invoices.get_at(1001)
        check("invoice 1001", (paid.number, paid.total, str(paid.paidOn)), (1001, Decimal("1250.00"), "2026-11-20"))
        check("invoice 1001 is paid", paid.is_paid(), True)
        check("invoice 1002 is not paid", invoices.get_at(1002).is_paid(), False)
        check("the customer cell", tx.get_mutable("customer:acme").name, "ACME Argentina S.A.")
        check("the sequence cell", tx.get_mutable("sequence"), 1003)
        settings = tx.get_root_object("settings")
        check("settings", (settings.currency, settings.decimals, str(settings.started)), ("ARS", 2, "2026-01-01"))
        check("tags", list(tx.get_root_object("tags").elements()), ["urgent", 2, 3.5, None, b"\x00\x01", (1, "x")])
        check("rates", dict(tx.get_root_object("rates").items()),
              {"ARS": Decimal("1.00"), "USD": Decimal("1450.25")})
        check("hash", dict(tx.get_root_object("hash").items()), {"k": "v", 2: __import__("datetime").date(2026, 1, 1)})
        check("set", {e for e in tx.get_root_object("set").elements()}, {1, "a", (1, 2)})
        bag = tx.get_root_object("bag")
        check("bag (version 2, then the blind adds of version 3 merged, D26)",
              (sorted(bag.items(), key=repr), bag.count, bag.total_count), ([("a", 2), (1, 2), (2, 1)], 3, 5))
        check("bag's stored element 1 is the int written first", [type(e) for e, _ in bag.items() if e == 1], [int])
        bag2 = db.snapshot_at(db.history()[1]).get_root_object("bag")
        check("bag at version 2", (sorted(bag2.items(), key=repr), bag2.count, bag2.total_count), ([("a", 1), (1, 2)], 2, 3))

        # Review Focus 4.
        boundaries = [-2**63 - 1, -2**63, 2**63 - 1, 2**63, 2**64 - 1, 2**64, 2**64 + 1]
        bounds = tx.get_root_object("bounds")
        check("boundary keys, in numeric order", list(bounds.keys()), boundaries)
        check("boundary values", [bounds.get_at(k) for k in boundaries], [str(k) for k in boundaries])
        check("boundary key found by its value", [bounds.has(k) for k in boundaries], [True] * 7)
        check("1.8446744073709552e19 is the key 2^64", bounds.get_at(1.8446744073709552e19), str(2**64))
        check("2^63 as a float is the key 2^63", bounds.get_at(float(2**63)), str(2**63))
        check("the neighbours of 2^64 are other keys", bounds.has(2**64 - 2), False)
        check("boundary list values, in the order written", list(tx.get_root_object("bound_values").elements()),
              [2**63 - 1, 2**63, 2**64 - 1, 2**64, -2**63, -2**63 - 1, 2**64 + 1])

        # Review Focus 2.
        strings = tx.get_root_object("strings")
        expected = ["é" * 254, "é" * 255, "é" * 256, "x" * 300]
        check("strings read back", list(strings.elements()), expected)
        check("a string is boxed from 256 code points, not from 256 bytes",
              [type(v) is ValueBox for v in stored_values(strings.root)], [False, False, True, True])
        tx.abort()
    finally:
        space.close()
    for failure in FAILURES:
        print(f"py_check_shapes: FAIL {failure}")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
