#!/usr/bin/env bash
# Plan Task 14 (review I4): the AVL trees of protoBaseST and ProtoBase are identical at about
# 2000 nodes (heights 11 to 12), under the sequential patterns of a database: 2000 appends,
# random operations on the large list, removes from the front and from the back (a queue);
# ascending Integer key puts, random mixed-rank operations, descending deletes. Dumps every
# 500 operations (a protoBaseST dump of 2000 nodes takes about 2 s); ProtoBase runs
# check_invariants after every operation (protoBaseST's per-step check: is for the small
# trees of the unit tests). The two sequences run side by side. Exit 77 without the
# interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src:$REPO/tests/unit${STPATH:+:$STPATH}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

run() {
    (cd "$HERE" && "$PROTOST" _st_avl_ops.st "$1" > "$TMP/$1.txt") || { echo "_st_avl_ops.st $1 exited $?"; return 1; }
    "$PY" "$HERE/py_avl_replay.py" "$1" "$TMP/$1.txt"
}
run pos-large > "$TMP/pos.log" 2>&1 & p1=$!
run key-large > "$TMP/key.log" 2>&1 & p2=$!
wait $p1; r1=$?
wait $p2; r2=$?
cat "$TMP/pos.log" "$TMP/key.log"
[[ $r1 -eq 0 ]] || fail "pos-large"
[[ $r2 -eq 0 ]] || fail "key-large"
echo "large AVL trees identical to ProtoBase"
