#!/usr/bin/env bash
# Indexed queries, plan Task 3: protoBaseST's key-group indexes are node for node ProtoBase's.
# py_index_build.py writes one space with ProtoBase (element sets with duplicates, 1 / 1.0 /
# Decimal 1 / Decimal 1.00, NaN, lists and maps, absent and nil keys, equal instants in different
# offsets, and 3000 records over about 40 keys for groups and member trees several levels deep),
# so both sides index the same atoms with the same oids. On that space, for EqualityIndex and
# RangeIndex over KeySpec.path, KeySpec.element and an extractor spec, ProtoBase's build and
# protoBaseST's build: are dumped atom by atom (shape, heights, counts, weights, keys, values,
# value boxes and the encoded bytes of every state), and so are the indexes a seeded sequence of
# with_added / with_removed / with_replaced (withAdded:, withRemoved:, withReplaced:with:)
# derives from the build over each set's first half. Every line must be equal.
# The space and the dumps go to a new directory under $INDEX_BUILD_OUT (default
# tests/interop/out/index_build, ignored by git); nothing is removed. Exit 77 without the
# interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src:$REPO/tests/unit${STPATH:+:$STPATH}"
fail() { echo "FAIL: $*"; exit 1; }
OUT="${INDEX_BUILD_OUT:-$HERE/out/index_build}/run-$$-$(date +%s%N)"
mkdir -p "$OUT" || fail "cannot create $OUT"

"$PY" "$HERE/py_index_build.py" make "$OUT/space" || fail "py_index_build.py make exited $?"
"$PY" "$HERE/py_index_build.py" dump "$OUT/space" > "$OUT/py.txt" || fail "py_index_build.py dump exited $?"
(cd "$HERE" && "$PROTOST" _st_index_build.st "$OUT/space" > "$OUT/st.txt" 2>&1) || {
    tail -n 5 "$OUT/st.txt"; fail "_st_index_build.st exited non-zero"; }
[[ "$(tail -n 1 "$OUT/py.txt")" == "end" && "$(tail -n 1 "$OUT/st.txt")" == "end" ]] || fail "a dump did not finish ($OUT)"
indexes=$(grep -c '^index ' "$OUT/py.txt")
[[ "$indexes" -eq 16 ]] || fail "expected 16 index dumps, ProtoBase printed $indexes"
cmp -s "$OUT/py.txt" "$OUT/st.txt" || {
    diff "$OUT/py.txt" "$OUT/st.txt" | head -n 6 | cut -c1-300
    fail "the index trees differ from ProtoBase's ($OUT)"; }
echo "index trees identical to ProtoBase: $indexes indexes, $(grep -vc '^index \|^end' "$OUT/py.txt") atoms"
