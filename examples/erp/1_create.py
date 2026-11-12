"""Step 1, Python: create the ERP database with three customers and 24 invoices.

Usage: python 1_create.py <directory>

One commit (version 1): every customer is a mutable cell (`customer:acme`, ...), every
invoice a record that names its customer's cell, and `tags` an empty dictionary that step 3
will fill from both languages.
"""
import sys
from decimal import Decimal

from erp_model import Customer, Invoice
from proto_db import Dictionary, FileStorage, MutableObject, ObjectSpace

CUSTOMERS = [
    ("customer:acme", "ACME S.A.", "30-12345678-9"),
    ("customer:globex", "Globex S.R.L.", "30-87654321-0"),
    ("customer:initech", "Initech S.A.", "30-11223344-5"),
]


def main(directory: str) -> None:
    space = ObjectSpace(FileStorage(directory))
    try:
        db = space.new_database("erp")
        tx = db.new_transaction()
        cells = [tx.new_mutable(cell, Customer(name=name, taxId=tax_id)) for cell, name, tax_id in CUSTOMERS]
        invoices = Dictionary()
        for i in range(1, 25):
            total = Decimal(f"{100 + i * 37 % 400}.{i * 13 % 100:02d}")
            invoices = invoices.set_at(1000 + i, Invoice(number=1000 + i, customer=cells[(i - 1) % 3], total=total))
        tx.set_root_object("invoices", invoices)
        tx.set_root_object("tags", Dictionary())
        tx.commit()
    finally:
        space.close()


if __name__ == "__main__":
    main(sys.argv[1])
