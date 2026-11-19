#!/usr/bin/env bash
# Indexed queries, plan Task 4b (spec 6.1.3): indexed collections written by one implementation are
# changed by the other with every mutator, index definitions and merges onto the indexed current
# values, and read back by both. py_index_both.py (ProtoBase) and _st_index_both.st (protoBaseST)
# run the same steps; py_index_both.py's docstring states them.
#   1. ProtoBase writes the space (make); protoBaseST changes it (change); ProtoBase's check
#      (validate() on every root, then every index lookup against a scan) and protoBaseST's (validate,
#      then every key's countOfKey: against a scan) both pass.
#   2. The reverse: protoBaseST writes, ProtoBase changes, both checks pass.
#   3. The content of every root (kind, count, index names, the elements) printed by both
#      implementations is the same in each direction, and the same in both directions.
# Everything goes to a new directory under $INDEX_BOTH_OUT (default tests/interop/out/index_both,
# ignored by git); nothing is removed. Exit 77 without the interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
fail() { echo "FAIL: $*"; exit 1; }
OUT="${INDEX_BOTH_OUT:-$HERE/out/index_both}/run-$$-$(date +%s%N)"
mkdir -p "$OUT" || fail "cannot create $OUT"

py() { "$PY" "$HERE/py_index_both.py" "$@" || fail "py_index_both.py $* exited $?"; }
st() { (cd "$HERE" && "$PROTOST" _st_index_both.st "$@") || fail "_st_index_both.st $* exited $?"; }

# direction <name> <writer> <changer>: one direction in $OUT/<name>; its content lines in
# $OUT/<name>.content.
direction() {
    local name="$1" writer="$2" changer="$3" space="$OUT/$1/space"
    mkdir -p "$OUT/$name" || fail "cannot create $OUT/$name"
    "$writer" make "$space" > "$OUT/$name/make.txt" 2>&1
    "$changer" change "$space" > "$OUT/$name/change.txt" 2>&1
    py check "$space" > "$OUT/$name/py-check.txt" 2>&1
    st check "$space" > "$OUT/$name/st-check.txt" 2>&1
    [[ "$(grep -c '^checked ' "$OUT/$name/py-check.txt")" -eq 5 && "$(grep -c '^checked ' "$OUT/$name/st-check.txt")" -eq 5 ]] \
        || fail "$name: a check did not cover the 5 roots ($OUT/$name)"
    py content "$space" > "$OUT/$name/py-content.txt"
    st content "$space" > "$OUT/$name/st-content.txt"
    cmp -s "$OUT/$name/py-content.txt" "$OUT/$name/st-content.txt" || {
        diff "$OUT/$name/py-content.txt" "$OUT/$name/st-content.txt" | head -n 6 | cut -c1-300
        fail "$name: ProtoBase and protoBaseST read different contents"; }
    cp "$OUT/$name/py-content.txt" "$OUT/$name.content"
    sed 's/^/  /' "$OUT/$name/py-check.txt"
}

direction py-writes-st-changes py st
direction st-writes-py-changes st py
cmp -s "$OUT/py-writes-st-changes.content" "$OUT/st-writes-py-changes.content" || {
    diff "$OUT/py-writes-st-changes.content" "$OUT/st-writes-py-changes.content" | head -n 6 | cut -c1-300
    fail "the two directions end with different contents"; }
echo "indexed collections changed by the other implementation in both directions: 5 roots each, both checks pass, contents equal"
