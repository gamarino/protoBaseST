"""Replay protoBaseST's seeded AVL operation sequence in ProtoBase and compare the trees (plan Task 14).

Usage: python py_avl_replay.py <pos|key|counted|list|pos-large|key-large> <file>

<file> is the output of _st_avl_ops.st: 'op <words>' lines, and at each checkpoint a
'dump <n>' line followed by 'node <line>' lines that describe protoBaseST's tree. This
script applies every operation with proto_db.collections.avl (pos_insert, pos_set,
pos_remove, key_put, key_remove; for 'list', the List messages of plan Task 15) and, at each checkpoint, dumps its own tree the same way
(tests/unit/_avl_ops.st, AvlOps dump:): one line per atom (node or value box) in pre-order,
a node before its box, '<number> <type name> <hex>', where <hex> is the msgpack of the
state ProtoBase encodes (codec.encode_state) with each reference written as the pointer
(fixed segment, the atom's number). The lines must be equal: the same shape, heights,
counts, weights, keys, values, boxes, and encoded bytes. Exit 0 when every checkpoint
matches, 1 at the first difference.
"""
import sys
import uuid

import msgpack

from proto_db.collections import avl
from proto_db.collections.lists import List
from proto_db.core import codec
from proto_db.core.atom import AtomPointer

SEGMENT = uuid.UUID(bytes=bytes.fromhex("0123456789abcdef0123456789abcdef"))


def value_of(token):
    kind, body = token[0], token[2:]
    if kind == "i":
        return int(body)
    if kind == "g":
        return float(int(body))
    if kind == "h":
        return float(int(body)) + 0.5
    if kind == "s":
        return body
    if kind == "E":
        return "é" * int(body)
    if kind == "B":
        return b"\xab" * int(body)
    if kind == "t":
        payload, count = body.split(":")
        return (int(payload), int(count))
    raise ValueError(f"unknown token {token!r}")


def dump(root):
    lines = {}
    if root is not None:
        _dump(root, 0, lines)
    return [lines[i] for i in range(len(lines))]


def _dump(node, number, lines):
    box = node.value if type(node.value) is avl.ValueBox else None
    left_start = number + 1 + (0 if box is None else 1)
    right_start = left_start if node.left is None else _dump(node.left, left_start, lines)
    nxt = right_start if node.right is None else _dump(node.right, right_start, lines)
    numbers = [(node.left, left_start), (node.right, right_start), (box, number + 1)]
    lines[number] = _line(node, number, numbers)
    if box is not None:
        lines[number + 1] = _line(box, number + 1, [])
    return nxt


def _line(atom, number, numbers):
    def save_child(child):
        for candidate, n in numbers:
            if candidate is child:
                return AtomPointer(SEGMENT, n)
        raise AssertionError("an unexpected reference")
    encoded = codec.encode_state(atom._state(), save_child)
    return f"{number} {type(atom).__type_name__} {msgpack.packb(encoded).hex()}"


def bound(word):
    return None if word == "nil" else int(word)


def apply_list(lst, words):
    """``lst`` after one PBList operation of AvlOps nextListOpFor: (plan Task 15)."""
    op = words[0]
    if op == "insertAt":
        return lst.insert_at(int(words[1]), value_of(words[2]))
    if op == "appendFirst":
        return lst.append_first(value_of(words[1]))
    if op == "appendLast":
        return lst.append_last(value_of(words[1]))
    if op == "setAt":
        return lst.set_at(int(words[1]), value_of(words[2]))
    if op == "removeAt":
        return lst.remove_at(int(words[1]))
    if op == "extend":
        values = [value_of(w) for w in words[2:]]
        if len(values) != int(words[1]):
            raise ValueError(f"extend: {words[1]} values announced, {len(values)} given")
        return lst.extend(values)
    if op == "sliceFrom":
        return lst.slice(bound(words[1]), bound(words[2]))
    if op == "head":
        return lst.head(int(words[1]))
    if op == "tail":
        return lst.tail(int(words[1]))
    raise ValueError(f"unknown list operation {words!r}")


def apply(kind, root, words):
    op = words[0]
    kind = kind.split("-")[0]
    if kind == "pos":
        if op == "insert":
            return avl.pos_insert(root, int(words[1]), value_of(words[2]))
        if op == "append":
            return avl.pos_insert(root, avl.pos_count(root), value_of(words[2]))
        if op == "set":
            return avl.pos_set(root, int(words[1]), value_of(words[2]))
        if op == "remove":
            return avl.pos_remove(root, int(words[1]))
    else:
        node_class = avl.KeyNode if kind == "key" else avl.CountedKeyNode
        if op == "put":
            return avl.key_put(root, value_of(words[1]), value_of(words[2]), node_class=node_class)[0]
        if op == "delete":
            return avl.key_remove(root, value_of(words[1]))[0]
    raise ValueError(f"unknown operation {words!r}")


def main(kind, path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    if not lines or lines[-1] != "end":
        print(f"FAIL: {path} does not end with 'end': the protoST run did not finish")
        return 1
    root = None
    lst = List() if kind == "list" else None
    ops = checkpoints = 0
    i = 0
    while i < len(lines):
        line = lines[i]
        i += 1
        if line.startswith("op "):
            if lst is not None:
                lst = apply_list(lst, line[3:].split(" "))
                root = lst.root
            else:
                root = apply(kind, root, line[3:].split(" "))
            avl.check_invariants(root)
            ops += 1
        elif line.startswith("dump "):
            theirs = []
            while i < len(lines) and lines[i].startswith("node "):
                theirs.append(lines[i][5:])
                i += 1
            ours = dump(root)
            if ours != theirs:
                for n, (a, b) in enumerate(zip(ours, theirs)):
                    if a != b:
                        print(f"FAIL: {kind} {line}: atom {n} differs\n  ProtoBase  {a}\n  protoST    {b}")
                        return 1
                print(f"FAIL: {kind} {line}: ProtoBase has {len(ours)} atoms, protoST {len(theirs)}")
                return 1
            checkpoints += 1
        elif line != "end":
            print(f"FAIL: unexpected line {line!r}")
            return 1
    if ops == 0 or checkpoints == 0:
        print(f"FAIL: {kind}: nothing compared ({ops} operations, {checkpoints} checkpoints)")
        return 1
    print(f"{kind}: {ops} operations, {checkpoints} checkpoints identical")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("pos", "key", "counted", "list", "pos-large", "key-large"):
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
