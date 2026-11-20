#!/usr/bin/env bash
# Vectors phase V5 (Addendum V 2.10, 2.11 and 5.2): collections holding vector indexes are written
# and merged node for node as proto_db's, at the collection level (as index_ops_identical.sh is
# for key-group indexes). py_vector_replay.py writes the spaces with proto_db, numpy and hnswlib
# blocked: main (60 records whose 'vec' is a 3-vector of every numeric form or not one, and a
# seeded operation sequence per kind, PBList, PBDictionary, PBHashDictionary, PBSet and
# PBCountedSet: an ivf_flat index added to the empty collection first, so the sequence trains it
# and crosses its retrain threshold again and again, then each mutator of the kind in turn, with
# addIndex: of an exact and an hnsw index after 25 operations and of a second ivf_flat index over
# the elements held after 55 (build: trains it once), slices (which rebuild every index), and
# removeIndex: of the exact one) and a copy of proto_db's format-3 conformance space (legacy). Each
# side replays the sequences on its own copy of the spaces, rebases a blind write (element writes,
# removals, addIndex: of a new ivf_flat index, a temporary index added and removed, a redefinition)
# onto the replayed dictionary, hash dictionary and counted set (vector-indexed currents, the
# replayed adds maintaining their indexes), changes the legacy root 'vectors' (a blind extend: of
# nothing keeps its format-3 index; the first change rebuilds it, rebuilt_stale), and prints every
# resulting collection atom by atom (the content trees, the index set and every index tree, the
# store and invalid trees, the centroids, the encoded bytes of every state): the two outputs must
# be equal line for line, so every list number and every set of centroids proto_db's pure-Python
# k-means computes (on the host libm's pow, deviation DV3) is protoBaseST's. Each side then commits
# its results; proto_db's verifier must accept protoBaseST's space (every record decoded and
# canonical, collection.validate() on every collection, its vector indexes included), validate()
# must accept the committed legacy 'vectors' with its rebuilt index, and the verifier's dump of
# protoBaseST's space must equal its dump of proto_db's own (compare_dumps.py --exact).
# Everything goes to a new directory under $VECTOR_OPS_OUT (default tests/interop/out/vector_ops,
# ignored by git); nothing is removed. Exit 77 without the interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src:$REPO/tests/unit${STPATH:+:$STPATH}"
fail() { echo "FAIL: $*"; exit 1; }
OUT="${VECTOR_OPS_OUT:-$HERE/out/vector_ops}/run-$$-$(date +%s%N)"
mkdir -p "$OUT" || fail "cannot create $OUT"

mkdir -p "$OUT/made" && "$PY" "$HERE/py_vector_replay.py" make "$OUT/made" 2> "$OUT/py.meta" || {
    cat "$OUT/py.meta"; fail "py_vector_replay.py make exited non-zero"; }
cp -r "$OUT/made" "$OUT/py" && cp -r "$OUT/made" "$OUT/st" || fail "cannot copy the spaces"
"$PY" "$HERE/py_vector_replay.py" replay "$OUT/py" > "$OUT/py.txt" 2>> "$OUT/py.meta" || {
    cat "$OUT/py.meta"; fail "py_vector_replay.py replay exited non-zero"; }
(cd "$HERE" && "$PROTOST" _st_vector_ops.st replay "$OUT/st" > "$OUT/st.txt" 2>&1) || {
    tail -n 5 "$OUT/st.txt"; fail "_st_vector_ops.st replay exited non-zero"; }
[[ "$(tail -n 1 "$OUT/py.txt")" == "end" && "$(tail -n 1 "$OUT/st.txt")" == "end" ]] || fail "a replay did not finish ($OUT)"
collections=$(grep -c '^collection ' "$OUT/py.txt")
[[ "$collections" -eq 9 ]] || fail "expected 9 collection dumps, proto_db printed $collections"
cmp -s "$OUT/py.txt" "$OUT/st.txt" || {
    diff "$OUT/py.txt" "$OUT/st.txt" | head -n 6 | cut -c1-300
    fail "the collections or their vector index trees differ from proto_db's ($OUT)"; }
"$PY" "$HERE/py_vector_replay.py" check "$OUT/st" 2>> "$OUT/py.meta" || {
    tail -n 5 "$OUT/py.meta"; fail "proto_db's verifier or validate() refused protoBaseST's spaces"; }
"$PY" "$HERE/py_vector_replay.py" check "$OUT/py" 2>> "$OUT/py.meta" || {
    tail -n 5 "$OUT/py.meta"; fail "proto_db's verifier or validate() refused its own spaces"; }
"$PY" "$HERE/compare_dumps.py" "$OUT/py/verify.json" "$OUT/st/verify.json" --exact || fail "the dumps differ"
centroids=$(grep -c ' proto_db.indexing.VectorIndex ' "$OUT/py.txt")
echo "NOTE: proto_db ran with $(head -n 1 "$OUT/py.meta")"
echo "vector-indexed collections identical to proto_db: $collections collections, $centroids vector index states, $(grep -vc '^collection \|^end' "$OUT/py.txt") atoms; verifier ok"
