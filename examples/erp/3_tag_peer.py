"""Step 3, Python's half: tag invoice 1010 in a transaction of its own and commit it.

Usage: python 3_tag_peer.py <directory>

Run by 3_tag.st while its transaction is open. The tag is a blind write: a dictionary built
from empty in this transaction, with a root that was never read.
"""
import sys

from erp_model import Invoice  # noqa: F401  (registers the ERP types)
from proto_db import FileStorage, ObjectSpace

space = ObjectSpace(FileStorage(sys.argv[1]))
try:
    db = space.open_database("erp")
    db.run(lambda tx: tx.set_root_object("tags", tx.new_dictionary().set_at(1010, "urgent")))
finally:
    space.close()
