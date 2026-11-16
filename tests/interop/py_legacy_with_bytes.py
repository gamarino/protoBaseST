"""The fixture of tests/unit/object_with.st (cluster Task 22a, fix m2): the bytes proto_db
v2.0.0rc4 writes for a new version (with_) of a format-4 DBObject record holding the legacy
fields parents and with_parents (R157). Prints the state order, then the payload hex with the
oid replaced by 00 01 .. 0f (re-packing is checked to keep the bytes).

Not a test (tests/run_tests.sh runs no .py file). It needs the rc4 venv's proto_db and
protoBase's tests/support helpers (DirectContext), which the venv does not hold:
  mkdir <dir> && git -C "$PROTOBASE_REPO" archive v2.0.0rc4 tests/__init__.py tests/support | tar -x -C <dir>
  PYTHONPATH=tests/interop/.venv/protobase:<dir> tests/interop/.venv/bin/python tests/interop/py_legacy_with_bytes.py
"""
import sys, uuid, msgpack
from proto_db.core.atom import type_tag
from proto_db.core.dbobject import DBObject
from proto_db.storage.format import RecordKind
from proto_db.storage.memory import MemoryStorage
from tests.support.persistence import DirectContext

DBOBJECT_TAG = 19  # the alias of proto_db.core.dbobject.DBObject
storage = MemoryStorage()
state = {"parents": "p", "with_parents": 3, "n": 1}
ptr = storage.push_atom({"t": DBOBJECT_TAG, "oid": uuid.UUID(int=9).bytes, "s": dict(state)})
ctx = DirectContext(storage)
o = ctx.load(ptr, DBObject.__type_name__)
newer = o.with_(n=2)
saved = ctx.save(newer)
raw = storage._fetch(saved, RecordKind.ATOM)
payload = msgpack.unpackb(raw, raw=False)
assert msgpack.packb(payload, use_bin_type=True) == raw, "re-packing changes the bytes"
print("state order", list(payload["s"]))
payload["oid"] = bytes(range(16))
print(msgpack.packb(payload, use_bin_type=True).hex())
