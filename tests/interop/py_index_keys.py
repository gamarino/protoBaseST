"""Write the key vectors of the indexed queries (plan Task 2, spec 6.1.1) with proto_db at v2.0.0rc4.

Usage: python py_index_keys.py <out directory>

Writes <out>/keys.msgpack and regenerates <out>/manifest.sha256 (the SHA-256 of every .msgpack
file of the directory, sorted by name, in sha256sum's format). It refuses to run unless the imported proto_db is the commit
tests/interop/setup_venv.sh pins (the venv's .commit file). Run it through the interop venv (tests/interop/env.sh sets PYTHONPATH);
the vendored copy is tests/conformance/vectors-index-keys/, read by
tests/conformance/index_keys.st, which requires protoBaseST's PBMemberKeys and PBKeys to give
the same answers for every case.

keys.msgpack is one msgpack map: 'tag' (the proto_db tag), 'seed', 'limits' (proto_db's
element_depth_limits() and MAX_VALUE_DEPTH) and 'cases', an array of maps, one per value:

  id                 a name for the case
  value              the msgpack bytes of the value's wire form (codec.encode_value), each atom
                     written as {'@ref': [oid bytes, 0, type tag]}: the atom's oid is the segment
  orderable          values.is_orderable
  surrogate_depth    value_depth(keyed.surrogate(value))
  surrogate          the msgpack bytes of the surrogate's wire form, or nil when it nests deeper
                     than MAX_VALUE_DEPTH (it cannot be encoded)
  refusal            nil, or the text of keyed.check_member_key's ProtoValidationError for an
                     EqualityIndex named 'by_key' on the element
  member_key_depth   value_depth(keyed.member_key(value))
  member_key         the msgpack bytes of the member key's wire form, nil when refused
  low_below          for the cases whose member key nests at most SHALLOW containers: how many
  high_below         of those cases' member keys order below keyed.equal_members_bounds(value)'s
                     low and high bound (strictly); nil for the deeper cases, whose order keys
                     Python's recursive tuple comparison cannot compare

The values: every rank of the order (MISSING, None, booleans, numbers of each kind, str, bytes,
date, the times and datetimes, timedelta, uuid, tuples, atoms, mutable handles), the
unorderables (NaNs, lists, maps, tuples holding one), equal values that are not identical (1,
1.0, Decimal 1 and 1.00, -0.0 and 0.0), seeded random values (random.Random(SEED)), and
elements at the depth limits of member keys and one container past each.
"""
import hashlib
import random
import sys
import uuid
from datetime import date, datetime, time, timedelta, timezone
from decimal import Decimal
from pathlib import Path
from zoneinfo import ZoneInfo

import msgpack

from proto_db.core import codec
from proto_db.core.atom import AtomPointer
from proto_db.core.dbobject import DBObject
from proto_db.errors import ProtoValidationError
from proto_db.indexing import EqualityIndex, KeySpec
from proto_db.indexing import keyed
from proto_db.values import MAX_VALUE_DEPTH, MISSING, MutableObject, canonical, is_orderable, order_key, value_depth

TAG = "v2.0.0rc4"
SEED = 20261118
SHALLOW = 64


def atom(oid_hex: str, **attrs) -> DBObject:
    a = DBObject(**attrs)
    object.__setattr__(a, "oid", uuid.UUID(hex=oid_hex))
    return a


ATOM_A = atom("00000000000040008000000000000a01", city="Rome")
ATOM_B = atom("ffffffffffff4fffbfffffffffffff02", city="Oslo")


def wire_bytes(value) -> bytes:
    """The msgpack bytes of value's wire form, an atom's reference holding its oid as the segment."""
    return msgpack.packb(codec.encode_value(value, lambda a: AtomPointer(a.oid, 0)), use_bin_type=True)


def nested_lists(levels: int, leaf):
    v = leaf
    for _ in range(levels):
        v = [v]
    return v


def nested_maps(levels: int, leaf):
    v = leaf
    for _ in range(levels):
        v = {"k": v}
    return v


def nested_tuples(levels: int, leaf):
    v = leaf
    for _ in range(levels):
        v = (v,)
    return v


def fixed_cases():
    rome = ZoneInfo("Europe/Rome")
    plus2 = timezone(timedelta(hours=2), "CEST")
    return [
        ("missing", MISSING), ("nil", None), ("false", False), ("true", True),
        ("int 0", 0), ("int 1", 1), ("int -7", -7), ("int 2^64", 2 ** 64), ("int -2^63-1", -2 ** 63 - 1),
        ("float 1.0", 1.0), ("float 0.0", 0.0), ("float -0.0", -0.0), ("float 2.5", 2.5),
        ("float inf", float("inf")), ("float -inf", float("-inf")), ("float nan", float("nan")),
        ("decimal 1", Decimal("1")), ("decimal 1.00", Decimal("1.00")), ("decimal -3.25", Decimal("-3.25")),
        ("decimal inf", Decimal("Infinity")), ("decimal nan", Decimal("NaN")),
        ("str empty", ""), ("str a", "a"), ("str b", "b"), ("str unicode", "été 中"),
        ("bytes empty", b""), ("bytes 00ff", b"\x00\xff"),
        ("date", date(2026, 11, 18)), ("time naive", time(12, 30, 5, 7)),
        ("time fixed", time(12, 30, 5, 7, tzinfo=plus2)),
        ("datetime naive", datetime(2026, 11, 18, 9, 15)),
        ("datetime fixed", datetime(2026, 11, 18, 9, 15, tzinfo=plus2)),
        ("datetime utc", datetime(2026, 11, 18, 7, 15, tzinfo=timezone.utc)),
        ("datetime zone", datetime(2026, 11, 18, 8, 15, tzinfo=rome)),
        ("timedelta", timedelta(days=3, seconds=7, microseconds=11)),
        ("uuid", uuid.UUID("12345678-1234-5678-1234-567812345678")),
        ("tuple empty", ()), ("tuple (1, 'a')", (1, "a")), ("tuple (1.0, 'a')", (1.0, "a")),
        ("tuple nested", (1, (2, (None, MISSING)))),
        ("tuple holding a list", (1, [2, 3])), ("tuple holding a nan", (float("nan"),)),
        ("tuple holding a map", ({"a": 1},)),
        ("atom a", ATOM_A), ("atom b", ATOM_B), ("tuple (atom a, 1)", (ATOM_A, 1)),
        ("mutable", MutableObject("cell")),
        ("list empty", []), ("list [1, 2]", [1, 2]), ("list [1.0, 2]", [1.0, 2]), ("list [2, 1]", [2, 1]),
        ("list [nan]", [float("nan")]), ("list [[1], [2]]", [[1], [2]]), ("list [atom a]", [ATOM_A]),
        ("list [missing, nil]", [MISSING, None]),
        ("map empty", {}), ("map {a: 1, b: 2}", {"a": 1, "b": 2}), ("map {b: 2, a: 1}", {"b": 2, "a": 1}),
        ("map {1: x, 's': y}", {1: "x", "s": "y"}), ("map {(1, 2): [3]}", {(1, 2): [3]}),
        ("map {k: atom b}", {"k": ATOM_B}),
    ]


def depth_cases():
    limits = keyed.element_depth_limits()
    lists, maps, room = limits["lists"], limits["maps"], limits["orderable"]
    return [
        (f"lists {lists}", nested_lists(lists, 1)),
        (f"lists {lists + 1}", nested_lists(lists + 1, 1)),
        (f"lists {lists} around an atom", nested_lists(lists, ATOM_A)),
        (f"lists {lists - 1} around an atom", nested_lists(lists - 1, ATOM_A)),
        (f"maps {maps}", nested_maps(maps, 1)),
        (f"maps {maps + 1}", nested_maps(maps + 1, 1)),
        (f"tuples {room // 2}", nested_tuples(room // 2, 1)),
        (f"tuples {room // 2 + 1}", nested_tuples(room // 2 + 1, 1)),
        (f"tuples {room // 2 - 1} around a list", nested_tuples(room // 2 - 1, [1])),
        (f"lists {MAX_VALUE_DEPTH}", nested_lists(MAX_VALUE_DEPTH, 1)),
    ]


def random_value(rng: random.Random, depth: int):
    kinds = ["int", "float", "str", "bytes", "bool", "nil", "decimal", "date", "uuid", "missing", "atom"]
    if depth < 3:
        kinds += ["list", "tuple", "map", "list", "tuple"]
    kind = rng.choice(kinds)
    if kind == "int":
        return rng.randint(-1000, 1000) if rng.random() < 0.8 else rng.randint(-2 ** 70, 2 ** 70)
    if kind == "float":
        return rng.choice([float(rng.randint(-5, 5)), rng.uniform(-1e6, 1e6), float("nan")])
    if kind == "str":
        return "".join(rng.choice("abcxyzé") for _ in range(rng.randint(0, 4)))
    if kind == "bytes":
        return bytes(rng.randint(0, 255) for _ in range(rng.randint(0, 3)))
    if kind == "bool":
        return rng.random() < 0.5
    if kind == "nil":
        return None
    if kind == "decimal":
        return Decimal(rng.randint(-999, 999)).scaleb(-rng.randint(0, 3))
    if kind == "date":
        return date(2000, 1, 1) + timedelta(days=rng.randint(0, 20000))
    if kind == "uuid":
        return uuid.UUID(int=rng.getrandbits(128))
    if kind == "missing":
        return MISSING
    if kind == "atom":
        return rng.choice([ATOM_A, ATOM_B])
    n = rng.randint(0, 3)
    if kind == "list":
        return [random_value(rng, depth + 1) for _ in range(n)]
    if kind == "tuple":
        return tuple(random_value(rng, depth + 1) for _ in range(n))
    keys = []
    while len(keys) < n:
        k = rng.choice([rng.randint(0, 9), "k" + str(rng.randint(0, 9))])
        if k not in keys:
            keys.append(k)
    return {k: random_value(rng, depth + 1) for k in keys}


def check_pinned() -> None:
    """Refuse to run unless the imported proto_db is the commit setup_venv.sh pins (TAG_COMMIT):
    the .commit file next to the proto_db package the venv holds must name it."""
    import proto_db
    setup = Path(__file__).resolve().parent / "setup_venv.sh"
    pinned = next((line.split('"')[1] for line in setup.read_text().splitlines()
                   if line.startswith('TAG_COMMIT="')), None)
    held_file = Path(proto_db.__file__).resolve().parent.parent / ".commit"
    held = held_file.read_text().strip() if held_file.is_file() else None
    if not pinned or not held or not held.startswith(pinned):
        sys.exit(f"py_index_keys: proto_db at {Path(proto_db.__file__).parent} is commit {held or 'unknown'}, "
                 f"not the pinned {pinned} of setup_venv.sh ({TAG}); run it through the interop venv")


def main() -> None:
    check_pinned()
    out = Path(sys.argv[1])
    rng = random.Random(SEED)
    cases = fixed_cases() + [(f"random {i}", random_value(rng, 0)) for i in range(200)] + depth_cases()
    index = EqualityIndex("by_key", KeySpec.element())
    rows = []
    for name, raw in cases:
        value = canonical(raw)
        sur = keyed.surrogate(value)
        key = keyed.member_key(value)
        refusal = None
        try:
            keyed.check_member_key(index, value, key)
        except ProtoValidationError as e:
            refusal = str(e)
        sur_depth = value_depth(sur)
        key_depth = value_depth(key)
        rows.append({"id": name, "value": value, "row": {
            "id": name,
            "value": wire_bytes(value),
            "orderable": is_orderable(value),
            "surrogate_depth": sur_depth,
            "surrogate": wire_bytes(sur) if sur_depth <= MAX_VALUE_DEPTH else None,
            "refusal": refusal,
            "member_key_depth": key_depth,
            "member_key": None if refusal is not None else wire_bytes(key),
            "low_below": None,
            "high_below": None}})
    shallow = [r for r in rows if r["row"]["member_key_depth"] <= SHALLOW]
    okeys = [order_key(keyed.member_key(r["value"])) for r in shallow]
    for r in shallow:
        low, high = keyed.equal_members_bounds(r["value"])
        r["row"]["low_below"] = sum(1 for k in okeys if k < low)
        r["row"]["high_below"] = sum(1 for k in okeys if k < high)
    data = {"tag": TAG, "seed": SEED, "shallow": SHALLOW,
            "limits": dict(keyed.element_depth_limits(), max_value_depth=MAX_VALUE_DEPTH),
            "cases": [r["row"] for r in rows]}
    out.mkdir(parents=True, exist_ok=True)
    blob = msgpack.packb(data, use_bin_type=True)
    (out / "keys.msgpack").write_bytes(blob)
    # One manifest per vector directory (pre-flight F8): every .msgpack file of it, sorted by name, so
    # this generator and tests/interop/py_term_cases.py keep each other's lines.
    (out / "manifest.sha256").write_text("".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n"
                                                 for p in sorted(out.glob("*.msgpack"))))
    print(f"wrote {len(rows)} cases, {sum(1 for r in rows if r['row']['refusal'])} refusals, "
          f"{len(shallow)} with bounds, to {out}")


if __name__ == "__main__":
    main()
