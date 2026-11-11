"""Record what ProtoBase's List does with each position case of plan Review Focus 5 (Task 15).

Usage: python py_list_positions.py

Builds List [10, 20, 30, 40, 50] with the interop venv's ProtoBase and prints one line per case:
'<case> => <result>', where <result> is the list's elements after the operation
(space-separated, '[]' when empty), the element read, or 'error <class name>'. The lines
were pasted as literals into tests/unit/list_positions.st, which requires protoBaseST's
PBList to give the same results; rerun this script to check them (recorded with v2.0.0rc1,
and unchanged at v2.0.0rc2). A slice bound written
'nil' is Python's None.
"""
from proto_db.collections.lists import List

BASE = [10, 20, 30, 40, 50]


def show(value):
    if isinstance(value, List):
        items = list(value.elements())
        return " ".join(str(v) for v in items) if items else "[]"
    return str(value)


def run(name, op):
    try:
        result = show(op(List.from_iterable(BASE)))
    except Exception as e:  # the class of the refusal is the recorded result
        result = f"error {type(e).__name__}"
    print(f"{name} => {result}")


def b(text):
    return None if text == "nil" else int(text)


CASES = []
for i in ["0", "4", "5", "-1", "-5", "-6", "'a'", "true", "1.0"]:
    arg = {"'a'": "a", "true": True, "1.0": 1.0}.get(i, None)
    arg = int(i) if arg is None else arg
    CASES.append((f"getAt: {i}", (lambda a: lambda l: l.get_at(a))(arg)))
for i in ["0", "4", "5", "-1", "-5", "-6"]:
    CASES.append((f"setAt: {i} value: 99", (lambda a: lambda l: l.set_at(a, 99))(int(i))))
for i in ["0", "4", "5", "6", "-1", "-5", "-6"]:
    CASES.append((f"insertAt: {i} value: 99", (lambda a: lambda l: l.insert_at(a, 99))(int(i))))
for i in ["0", "4", "5", "-1", "-5", "-6"]:
    CASES.append((f"removeAt: {i}", (lambda a: lambda l: l.remove_at(a))(int(i))))
for lo, hi in [("nil", "nil"), ("1", "3"), ("-2", "nil"), ("nil", "-2"), ("3", "1"), ("-10", "10"),
               ("10", "20"), ("2", "2"), ("-3", "-1"), ("0", "5")]:
    CASES.append((f"sliceFrom: {lo} to: {hi}", (lambda a, z: lambda l: l.slice(a, z))(b(lo), b(hi))))
# Slice bounds that are not Integers or None. ProtoBase hands them to Python's
# slice.indices, which takes True as 1 and raises TypeError for the others; protoBaseST
# refuses all three with PBValidationError (an intended deviation: a Boolean is not a
# number in Smalltalk, and ProtoBase's own _position refuses bool). list_positions.st
# records both answers.
for word, arg in [("true", True), ("'a'", "a"), ("1.0", 1.0)]:
    CASES.append((f"sliceFrom: {word} to: nil", (lambda a: lambda l: l.slice(a, None))(arg)))
for n in ["0", "2", "-1", "5", "10", "-10"]:
    CASES.append((f"head: {n}", (lambda a: lambda l: l.head(a))(int(n))))
    CASES.append((f"tail: {n}", (lambda a: lambda l: l.tail(a))(int(n))))
CASES.append(("appendFirst: 99", lambda l: l.append_first(99)))
CASES.append(("appendLast: 99", lambda l: l.append_last(99)))
CASES.append(("extend: 1 2 3", lambda l: l.extend([1, 2, 3])))
CASES.append(("extend: empty", lambda l: l.extend([])))

for name, op in CASES:
    run(name, op)
