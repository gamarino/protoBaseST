"""Compare ProtoBase's verifier dump with protoBaseST's (plan call C11).

Usage: python compare_dumps.py <py.json> <st.json> [--exact]

The dumps are compared on the keys 'databases' and 'opaque_types' (atom counts depend on
the walk). demo.erp.AuditNote is deliberately unknown to protoST: an {"opaque": T} on the
protoST side equals {"object": T} on the Python side for that type only, and protoST lists
it in opaque_types where Python does not. Every other difference fails, and so does a pair
of dumps in which the AuditNote rule is never used (the opaque path must be exercised).
With --exact (a space that holds no Python-only type, such as one protoST wrote), no
normalisation is made: 'databases' and 'opaque_types' must be equal as they are.
Exit 0 when equal, 1 otherwise (the first differing path is printed).
"""
import json
import sys

PYTHON_ONLY = "demo.erp.AuditNote"


def normalise(value, counter):
    """protoST's dump with every opaque AuditNote described as Python describes it."""
    if isinstance(value, dict):
        if value.get("opaque") == PYTHON_ONLY:
            counter[0] += 1
            rest = {k: v for k, v in value.items() if k != "opaque"}
            return {"object": PYTHON_ONLY, **{k: normalise(v, counter) for k, v in rest.items()}}
        return {k: normalise(v, counter) for k, v in value.items()}
    if isinstance(value, list):
        return [normalise(v, counter) for v in value]
    return value


def first_difference(a, b, path="$"):
    if type(a) is not type(b):
        return f"{path}: {type(a).__name__} != {type(b).__name__}"
    if isinstance(a, dict):
        if list(a) != list(b) and sorted(a) != sorted(b):
            return f"{path}: keys {sorted(a)} != {sorted(b)}"
        for k in a:
            d = first_difference(a[k], b[k], f"{path}.{k}")
            if d:
                return d
        return None
    if isinstance(a, list):
        if len(a) != len(b):
            return f"{path}: length {len(a)} != {len(b)}"
        for i, (x, y) in enumerate(zip(a, b)):
            d = first_difference(x, y, f"{path}[{i}]")
            if d:
                return d
        return None
    return None if a == b else f"{path}: {a!r} != {b!r}"


def main(py_path: str, st_path: str, exact: bool = False) -> int:
    with open(py_path, encoding="utf-8") as f:
        py = json.load(f)
    with open(st_path, encoding="utf-8") as f:
        st = json.load(f)
    if exact:
        for label in ("opaque_types", "databases"):
            d = first_difference(py[label], st[label], label)
            if d:
                print(f"compare_dumps: differ at {d}")
                return 1
        print(f"compare_dumps: equal ({len(py['databases'])} databases, exact)")
        return 0
    counter = [0]
    st_databases = normalise(st["databases"], counter)
    if counter[0] == 0:
        print(f"compare_dumps: no opaque {PYTHON_ONLY} in protoST's dump: the opaque path was not exercised")
        return 1
    st_opaque = [t for t in st["opaque_types"] if t != PYTHON_ONLY]
    if PYTHON_ONLY not in st["opaque_types"]:
        print(f"compare_dumps: protoST's opaque_types lacks {PYTHON_ONLY}: {st['opaque_types']}")
        return 1
    for label, a, b in (("opaque_types", py["opaque_types"], st_opaque), ("databases", py["databases"], st_databases)):
        d = first_difference(a, b, label)
        if d:
            print(f"compare_dumps: differ at {d}")
            return 1
    print(f"compare_dumps: equal ({len(py['databases'])} databases, {counter[0]} opaque {PYTHON_ONLY} records)")
    return 0


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--exact"]
    if len(args) != 2:
        print("usage: compare_dumps.py <py.json> <st.json> [--exact]")
        sys.exit(2)
    sys.exit(main(args[0], args[1], exact="--exact" in sys.argv[1:]))
