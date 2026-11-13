"""ProtoBase's side of st_every_record_to_py.sh: reads every record listed in <list> (one
'segment-hex offset' per line) from the space <dir> and decodes every value of its state.
Exit 0 when every record reads; prints each failure and exits 1 otherwise."""
import sys
import uuid
from proto_db.storage.file import FileStorage
from proto_db.core.codec import decode_value
from proto_db.core.atom import AtomPointer

space, listing = sys.argv[1], sys.argv[2]
st = FileStorage(space)
failures, count = [], 0
try:
    with open(listing) as f:
        for line in f:
            hexseg, off = line.split()
            ptr = AtomPointer(uuid.UUID(hexseg), int(off))
            try:
                payload = st.get_atom(ptr)
                for name, wire in payload["s"].items():
                    decode_value(wire, lambda *a: None)
                count += 1
            except Exception as e:  # noqa: BLE001 - every failure is reported
                failures.append(f"{ptr}: {type(e).__name__}: {e}")
finally:
    st.close()
for failure in failures:
    print("FAIL:", failure)
print(f"records read: {count}, failures: {len(failures)}")
sys.exit(1 if failures or count == 0 else 0)
