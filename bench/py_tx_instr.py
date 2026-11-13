"""ProtoBase's side of run_tx_instr.sh: py_tx_instr.py runs PROFILE for N transactions, as tx_instr.st."""
import os
from proto_db import FileStorage, ObjectSpace

profile, n = os.environ["PROFILE"], int(os.environ["N"])
space = ObjectSpace(FileStorage(os.environ["TX_DIR"]))
try:
    db = space.new_database("bench")
    with db.new_transaction() as tr:
        d = tr.new_dictionary()
        if profile == "small-record":
            for k in range(100):
                d = d.set_at(k, tr.new_object(name=f"account {k}", balance=0, hits=0, stamp=0))
        tr.set_root_object("kv", d)

    def tiny(tr, i):
        tr.set_root_object("kv", tr.get_root_object("kv").set_at(i, i % 1000))

    def small(tr, i):
        recs = tr.get_root_object("kv")
        rec = recs.get_at(i % 100)
        rec = rec.with_(balance=rec.balance + i, hits=rec.hits + 1, stamp=i)
        tr.set_root_object("kv", recs.set_at(i % 100, rec))

    def batch(tr, i):
        d = tr.get_root_object("kv")
        for k in range((i - 1) * 100 + 1, i * 100 + 1):
            d = d.set_at(k, k % 97)
        tr.set_root_object("kv", d)
    body = {"tiny": tiny, "small-record": small, "batch-100": batch}[profile]
    for i in range(1, n + 1):
        db.run(lambda tr, i=i: body(tr, i))
finally:
    space.close()
