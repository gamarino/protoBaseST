"""Write the space of design spec 10.2 (Python to protoST) with ProtoBase's public API.

Usage: python py_write_space.py <directory>

One database 'erp', written in three commits (versions 1 to 3 after the creation's 0):

1. the mutable cell 'customer:acme' (a demo.erp.Customer); the indexed collection
   'invoices' (a Dictionary from number to demo.erp.Invoice, with an EqualityIndex on
   'number'); 'audit', a demo.erp.AuditNote (a type only Python knows);
2. every non-indexed collection: 'tags' (List), 'rates' (Dictionary), 'hash'
   (HashDictionary), 'set' (Set), 'bag' (CountedSet), 'multi' (RepeatedKeysDictionary);
   'settings' (a plain DBObject); 'notes' (a List of AuditNotes);
3. invoice 1001 paid (a new version made with with_), the customer renamed through its
   mutable cell, and a second cell 'sequence'.

Run with the interop venv (tests/interop/env.sh): ProtoBase v2.0.0rc1 on PYTHONPATH.
"""
import datetime
import sys
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "examples" / "erp"))

from erp_model import AuditNote, Customer, Invoice  # noqa: E402
from proto_db import (CountedSet, DBObject, Dictionary, EqualityIndex, FileStorage, HashDictionary,  # noqa: E402
                      List, MutableObject, ObjectSpace, RepeatedKeysDictionary, Set)

UTC = datetime.timezone.utc


def main(directory: str) -> None:
    space = ObjectSpace(FileStorage(directory))
    try:
        db = space.new_database("erp")

        tx = db.new_transaction()
        acme = tx.new_mutable("customer:acme", Customer(name="ACME S.A.", taxId="30-12345678-9"))
        invoices = Dictionary().add_index(EqualityIndex("by_number", "number"))
        invoices = invoices.set_at(1001, Invoice(number=1001, customer=acme, total=Decimal("1250.00")))
        invoices = invoices.set_at(1002, Invoice(number=1002, customer=acme, total=Decimal("99.90")))
        tx.set_root_object("invoices", invoices)
        tx.set_root_object("audit", AuditNote(text="created", at=datetime.datetime(2026, 11, 10, 9, 0, tzinfo=UTC)))
        tx.commit()

        tx = db.new_transaction()
        tx.set_root_object("tags", List.from_iterable(["urgent", 2, 3.5, None, b"\x00\x01", (1, "x")]))
        tx.set_root_object("rates", Dictionary().set_at("ARS", Decimal("1.00")).set_at("USD", Decimal("1450.25")))
        tx.set_root_object("hash", HashDictionary().set_at("k", "v").set_at(2, datetime.date(2026, 1, 1)))
        tx.set_root_object("set", Set.from_iterable([1, "a", (1, 2)]))
        tx.set_root_object("bag", CountedSet.from_iterable([1, 1, 2]))
        tx.set_root_object("multi", RepeatedKeysDictionary().set_at("x", DBObject(n=1)).set_at("x", DBObject(n=2)))
        tx.set_root_object("settings", DBObject(currency="ARS", decimals=2, started=datetime.date(2026, 1, 1)))
        tx.set_root_object("notes", List.from_iterable([AuditNote(text="first"), AuditNote(text="second")]))
        tx.commit()

        tx = db.new_transaction()
        invoices = tx.get_root_object("invoices")
        paid = invoices.get_at(1001).with_(paidOn=datetime.date(2026, 11, 20))
        tx.set_root_object("invoices", invoices.set_at(1001, paid))
        customer = MutableObject("customer:acme")
        customer.set(tx, customer.get(tx).with_(name="ACME Argentina S.A."))
        tx.new_mutable("sequence", 1003)
        tx.commit()

        assert [entry.version for entry in db.history()] == [3, 2, 1, 0]
        check = db.new_transaction()
        assert check.get_root_object("invoices").get_at(1001).is_paid()
        assert not check.get_root_object("invoices").get_at(1002).is_paid()
        assert check.get_mutable("customer:acme").name == "ACME Argentina S.A."
        check.abort()
    finally:
        space.close()


if __name__ == "__main__":
    main(sys.argv[1])
