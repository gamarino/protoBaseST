#!/usr/bin/env bash
# Plan Task 14: protoBaseST's persistent AVL writes build the same trees as ProtoBase's
# proto_db/collections/avl.py for the same operation sequence. _st_avl_ops.st runs the seeded
# sequences of the unit tests (Random seed: 20261110; positional, keyed and weighted) and
# prints each operation and, every 100 operations, its tree node by node; py_avl_replay.py
# applies the same operations in ProtoBase and requires every node line identical: shape,
# heights, counts, weights, keys, values, value boxes and the encoded bytes of each state.
# Exit 77 without the interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src:$REPO/tests/unit${STPATH:+:$STPATH}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

for spec in pos:1000 key:1000 counted:600; do
    kind="${spec%%:*}"; steps="${spec#*:}"
    (cd "$HERE" && "$PROTOST" _st_avl_ops.st "$kind" "$steps" > "$TMP/$kind.txt") || fail "_st_avl_ops.st $kind exited $?"
    "$PY" "$HERE/py_avl_replay.py" "$kind" "$TMP/$kind.txt" || fail "py_avl_replay.py $kind"
done
echo "AVL trees identical to ProtoBase"
