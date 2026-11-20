#!/usr/bin/env bash
# Vectors phase V3 (Addendum V, 2.11 and 5.2): protoBaseST's vector indexes are node for node
# proto_db's, at the index level. py_vector_index.py writes one space with proto_db (numpy and
# hnswlib blocked; records and plain values whose keys are valid 3-vectors of every numeric form,
# or not vectors at all, equal values with other tokens, unorderable values, and 700 records over
# 125 vectors), so both sides index the same atoms with the same oids. On that space, for the
# exact backend (l2, and cosine with numpy false) and the hnsw backend (ip with M and seed, and
# cosine), over the path 'vec' and the element key specs, and for dims 1 and 16 over the three
# metrics, proto_db's build and protoBaseST's build: are dumped atom by atom (the index state,
# every node of the store and invalid trees, the encoded bytes of each), and so are the indexes a
# seeded sequence of with_added / with_removed / with_replaced (withAdded:, withRemoved:,
# withReplaced:with:) derives from the build over each set's first half, and the three
# invalid-tree histories (a build with invalid elements given another one keeps its KeyNode tree;
# a build without grows a CountedKeyNode tree; a build whose invalid tree is emptied, then grown
# again, grows a CountedKeyNode tree). Then both print the text of 59 refusals: definitions,
# removals of what the index does not hold, and validate: of tampered indexes (proto_db's texts,
# the values in them rendered as Python's repr; a total or a component equal under Python's ==
# accepted). Every line must be equal. No collection is written: collections holding a vector
# index refuse changes until V5. The space and the dumps go to a new directory under $VECTOR_INDEX_OUT (default
# tests/interop/out/vector_index, ignored by git); nothing is removed. Exit 77 without the interop
# venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src:$REPO/tests/unit${STPATH:+:$STPATH}"
fail() { echo "FAIL: $*"; exit 1; }
OUT="${VECTOR_INDEX_OUT:-$HERE/out/vector_index}/run-$$-$(date +%s%N)"
mkdir -p "$OUT" || fail "cannot create $OUT"

"$PY" "$HERE/py_vector_index.py" make "$OUT/space" || fail "py_vector_index.py make exited $?"
"$PY" "$HERE/py_vector_index.py" dump "$OUT/space" > "$OUT/py.txt" 2> "$OUT/py.meta" || {
    cat "$OUT/py.meta"; fail "py_vector_index.py dump exited non-zero"; }
(cd "$HERE" && "$PROTOST" _st_vector_index.st "$OUT/space" > "$OUT/st.txt" 2>&1) || {
    tail -n 5 "$OUT/st.txt"; fail "_st_vector_index.st exited non-zero"; }
[[ "$(tail -n 1 "$OUT/py.txt")" == "end" && "$(tail -n 1 "$OUT/st.txt")" == "end" ]] || fail "a dump did not finish ($OUT)"
indexes=$(grep -c '^index ' "$OUT/py.txt")
[[ "$indexes" -eq 48 ]] || fail "expected 48 index dumps, proto_db printed $indexes"
refusals=$(grep -c '^refusal ' "$OUT/py.txt")
[[ "$refusals" -eq 59 ]] || fail "expected 59 refusals, proto_db printed $refusals"
cmp -s "$OUT/py.txt" "$OUT/st.txt" || {
    diff "$OUT/py.txt" "$OUT/st.txt" | head -n 6 | cut -c1-300
    fail "the vector index trees differ from proto_db's ($OUT)"; }
echo "NOTE: proto_db ran with $(head -n 1 "$OUT/py.meta")"
echo "vector index trees identical to proto_db: $indexes indexes, $(grep -vc '^index \|^end\|^refusal ' "$OUT/py.txt") atoms, $refusals refusal texts"
