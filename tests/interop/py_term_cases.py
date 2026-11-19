"""Write the term vectors of the indexed queries (plan Task 5) with proto_db at v2.0.0rc4.

Usage: python py_term_cases.py <out directory>

Needs PROTOST (the protost binary). It runs tests/interop/_st_term_values.st, which prints the
values of protoBaseST's ``QData values: COUNT seed: SEED`` (tests/unit/_queries.st, the port of
proto_db's ``index_contract.mixed_value``), decodes them with proto_db's codec (each atom becomes a
DBObject with the oid and the attribute ``r`` the helper reported), and evaluates every case below
on them with proto_db's Term and Expression. It writes <out>/terms.msgpack and regenerates
<out>/manifest.sha256 over every .msgpack file of the directory (one manifest per vector
directory, pre-flight F8), in sha256sum's format, sorted by name. It refuses to run unless the
imported proto_db is the commit tests/interop/setup_venv.sh pins (the venv's .commit file). Run it
through the interop venv (tests/interop/env.sh sets PYTHONPATH). The vendored copy is
tests/conformance/vectors-index-keys/, read by tests/unit/qry_terms.st.

terms.msgpack is one msgpack map: 'tag', 'count', 'seed', 'values' (the wire form of each value, as
the helper printed it: the test checks that QData still draws them) and 'cases', an array of maps:

  id         a name for the case
  tokens     the wire form (codec.encode_value) of the 0.1 prefix list given to
             Expression.compile, each atom written {'@ref': [oid, 0, type tag]}
  error      nil, or the class name of the error Expression.compile raised
             ('ProtoValidationError', 'ProtoNotSupportedError')
  answers    nil, or one boolean per value: proto_db's evaluate(expression, value)
  match_error nil, or the class name of the error evaluate raised on whichever value failed
             first (the values are evaluated in order and the first error stops the case)
  to_list    nil, or the wire form of expression.to_list() (nil for near[], whose list holds a
             NearQuery, which has no wire form)
  describe   nil, or the msgpack bytes of expression.describe()

The cases: every operator with operands of several ranks (numbers of each type, strings, nil,
booleans, bytes, dates, instants, tuples, an atom), the degenerate terms of the plan's Review
Focus 4 (an empty 'in', between 5 and 3, 'in' with duplicates and mixed types, a 1000-value 'in',
a path with an empty segment, a path starting with '@', a path that is not a String), refused
operands, and expressions in the prefix syntax ('&', '|', '!', implicit AND, nested lists).
"""
import hashlib
import os
import subprocess
import sys
import uuid
from datetime import date, datetime, time, timedelta, timezone
from decimal import Decimal
from pathlib import Path

import msgpack

from proto_db.core import codec
from proto_db.core.atom import AtomPointer
from proto_db.core.dbobject import DBObject
from proto_db.errors import ProtoNotSupportedError, ProtoValidationError
from proto_db.query.expressions import Expression, evaluate

TAG = "v2.0.0rc4"
COUNT = 160
SEED = 5
HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent


def check_pinned() -> None:
    """Refuse to run unless the imported proto_db is the commit setup_venv.sh pins (TAG_COMMIT)."""
    import proto_db
    setup = HERE / "setup_venv.sh"
    pinned = next((line.split('"')[1] for line in setup.read_text().splitlines()
                   if line.startswith('TAG_COMMIT="')), None)
    held_file = Path(proto_db.__file__).resolve().parent.parent / ".commit"
    held = held_file.read_text().strip() if held_file.is_file() else None
    if not pinned or not held or not held.startswith(pinned):
        sys.exit(f"py_term_cases: proto_db at {Path(proto_db.__file__).parent} is commit {held or 'unknown'}, "
                 f"not the pinned {pinned} of setup_venv.sh ({TAG}); run it through the interop venv")


def st_values():
    """The wire forms and atoms of QData values: COUNT seed: SEED, as protoBaseST prints them."""
    protost = os.environ.get("PROTOST")
    if not protost:
        sys.exit("py_term_cases: set PROTOST to the protost binary")
    env = dict(os.environ, STPATH=f"{REPO / 'src'}:{REPO / 'tests' / 'unit'}")
    run = subprocess.run([protost, "_st_term_values.st", str(COUNT), str(SEED)], cwd=HERE, env=env,
                         capture_output=True, text=True, timeout=600)
    if run.returncode != 0:
        sys.exit(f"py_term_cases: _st_term_values.st exited {run.returncode}: {run.stderr[-500:]}")
    lines = [line for line in run.stdout.splitlines() if line.strip()]
    return msgpack.unpackb(bytes.fromhex(lines[-1]), raw=False, strict_map_key=False)


def make_atom(oid: bytes, r) -> DBObject:
    a = DBObject(r=r)
    object.__setattr__(a, "oid", uuid.UUID(bytes=oid))
    return a


def wire_bytes(value) -> bytes:
    """The msgpack bytes of value's wire form, an atom's reference holding its oid as the segment."""
    return msgpack.packb(codec.encode_value(value, lambda a: AtomPointer(a.oid, 0)), use_bin_type=True)


def cases(an_atom):
    plus1 = timezone(timedelta(hours=1))
    instant = datetime(2026, 1, 1, 13, tzinfo=plus1)
    naive = datetime(2026, 1, 1, 12, 30, 5, 7)
    d2 = date(2026, 1, 2)
    scalars = [("int 1", 1), ("float 1.0", 1.0), ("decimal 1.00", Decimal("1.00")), ("int 0", 0),
               ("float -0.0", -0.0), ("float 2.5", 2.5), ("decimal 0.5", Decimal("0.5")), ("str s2", "s2"),
               ("str empty", ""), ("nil", None), ("true", True), ("false", False), ("bytes 01", b"\x01"),
               ("date", d2), ("instant +1", instant), ("tuple (1, 't0')", (1, "t0")), ("atom", an_atom),
               ("float inf", float("inf")), ("int 2^62", 2 ** 62)]
    out = []
    for op in ("==", "!=", "<", "<=", ">", ">="):
        for name, v in scalars:
            out.append((f"{op} {name}", [None, op, v]))
    for op in ("?N", "?!N", "?T", "?!T"):
        out.append((op, [None, op]))
        out.append((f"{op} on r", ["r", op]))
    for name, v in (("int 2", 2), ("str s", "s"), ("str empty", ""), ("bytes 01", b"\x01"), ("float 1.0", 1.0),
                    ("true", True), ("str k", "k"), ("str a", "a"), ("nil", None)):
        out.append((f"contains {name}", [None, "contains", v]))
    for op in ("between[]", "between()", "between(]", "between[)"):
        out.append((f"{op} 0 2", [None, op, 0, 2]))
        out.append((f"{op} 0.5 Decimal 2", [None, op, 0.5, Decimal("2")]))
        out.append((f"{op} s0 s3", [None, op, "s0", "s3"]))
        out.append((f"{op} dates", [None, op, date(2026, 1, 1), d2]))
        out.append((f"{op} 5 3 (degenerate)", [None, op, 5, 3]))
        out.append((f"{op} equal bounds", [None, op, 1, 1.0]))
    out += [
        ("in mixed", [None, "in", [1, "s1", None, True, b"\x02", (0, "t1")]]),
        ("in empty (degenerate)", [None, "in", []]),
        ("in duplicates and mixed types (degenerate)", [None, "in", [1, 1.0, Decimal("1"), True, "s1", None, 1]]),
        ("in 1000 values (degenerate)", [None, "in", list(range(-500, 500))]),
        ("in a tuple", [None, "in", [(1, "t0"), (2, "t1")]]),
        ("in instants", [None, "in", [instant, datetime(2026, 1, 1, 9, tzinfo=timezone(timedelta(hours=-3)))]]),
        ("in naive and time", [None, "in", [naive, time(12, 30), timedelta(days=-1, seconds=5)]]),
        ("in decimals", [None, "in", [Decimal("0E-3"), Decimal("1E+2"), Decimal("-0")]]),
        ("in uuid", [None, "in", [uuid.UUID("12345678-1234-5678-1234-567812345678")]]),
        ("== on r", ["r", "==", 2]),
        ("== on k", ["k", "==", 1]),
        ("< on k.x", ["k.x", "<", 1]),
        ("== on a dotted path through records", ["r.x", "==", 1]),
        # refused terms (the same error class as proto_db)
        ("path with an empty segment (degenerate)", ["a..b", "==", 1]),
        ("empty path", ["", "==", 1]),
        ("path '@' (degenerate)", ["@", "==", 1]),
        ("path '@x y' (degenerate)", ["@x y", "==", 1]),
        ("path '@' unregistered extractor (degenerate)", ["@tests.terms.unregistered", "==", 1]),
        ("path not a String (degenerate)", [3, "==", 1]),
        ("unknown operator", [None, "=~", 1]),
        ("near[] refused", ["v", "near[]", {"vector": [1.0, 0.0], "k": 2}]),
        ("== a list", [None, "==", [1]]),
        ("== a map", [None, "==", {"a": 1}]),
        ("< nan", [None, "<", float("nan")]),
        ("in a scalar", [None, "in", 5]),
        ("in a string", [None, "in", "abc"]),
        ("in holding a list", [None, "in", [[1]]]),
        ("between of two ranks", [None, "between[]", 1, "z"]),
        ("between without the upper bound", [None, "between[]", 1]),
        ("?N with a value", [None, "?N", 3]),
        ("== without a value", [None, "=="]),
        ("contains a list", [None, "contains", [1]]),
        # expressions in the prefix syntax
        ("& two terms", ["&", None, ">", 0, None, "<", 3]),
        ("| two terms", ["|", None, "==", "s1", None, "?N"]),
        ("! a term", ["!", None, "<", 5]),
        ("! ! a term", ["!", "!", None, "<", 5]),
        ("implicit and of three", [None, ">=", 0, None, "<=", 2, None, "!=", 1]),
        ("nested lists", ["|", [None, "==", 1], ["&", [None, "?!N"], [None, "contains", 1]]]),
        ("& binary then implicit and", ["&", None, ">", -2, None, "<", 4, None, "!=", 0]),
        ("& of | (degenerate nesting)", ["&", "|", None, "==", 0, None, "==", 1, "!", None, "==", 1.0]),
        ("& missing an operand", ["&", None, "==", 1]),
        ("! missing an operand", ["!"]),
        ("a path missing its operator", ["r"]),
        ("a stray integer", [[None, "==", 1], 7]),
    ]
    return out


def outcome(tokens, values):
    row = {"tokens": wire_bytes(tokens), "error": None, "answers": None, "match_error": None,
           "to_list": None, "describe": None}
    try:
        expr = Expression.compile(tokens)
    except (ProtoValidationError, ProtoNotSupportedError) as e:
        row["error"] = type(e).__name__
        return row
    try:
        row["to_list"] = wire_bytes(expr.to_list())
    except ProtoValidationError:  # a near[] term lists its NearQuery, which has no wire form
        row["to_list"] = None
    row["describe"] = msgpack.packb(expr.describe(), use_bin_type=True)
    try:
        row["answers"] = [evaluate(expr, v) for v in values]
    except (ProtoValidationError, ProtoNotSupportedError) as e:
        row["match_error"] = type(e).__name__
    return row


def main() -> None:
    check_pinned()
    out = Path(sys.argv[1])
    dumped = st_values()
    atoms = {bytes(oid): make_atom(bytes(oid), r) for oid, r in dumped["atoms"]}
    values = [codec.decode_value(w, lambda ptr, tag: atoms[ptr.segment.bytes]) for w in dumped["values"]]
    an_atom = next(v for v in values if isinstance(v, DBObject))
    rows = []
    for name, tokens in cases(an_atom):
        row = outcome(tokens, values)
        row["id"] = name
        rows.append(row)
    data = {"tag": TAG, "count": COUNT, "seed": SEED,
            "values": [wire_bytes(v) for v in values], "cases": rows}
    out.mkdir(parents=True, exist_ok=True)
    blob = msgpack.packb(data, use_bin_type=True)
    (out / "terms.msgpack").write_bytes(blob)
    manifest = "".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n"
                       for p in sorted(out.glob("*.msgpack")))
    (out / "manifest.sha256").write_text(manifest)
    print(f"wrote {len(rows)} cases ({sum(1 for r in rows if r['error'])} refused, "
          f"{sum(1 for r in rows if r['match_error'])} refused when evaluated) over {len(values)} values to {out}")


if __name__ == "__main__":
    main()
