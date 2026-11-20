#!/usr/bin/env bash
# Vectors phase V5 (Addendum V 5.2, deviation DV3, risk RV5): collections holding vector indexes
# change hands in both directions with proto_db in its default mode, numpy importable
# (tests/interop/.venv-numpy, made by setup_venv_numpy.sh), so its IVF training is numpy's
# k-means, not the pure-Python path protoBaseST reproduces bit for bit.
#   1. proto_db writes a space (py_vector_replay.py write: records and a List, a Dictionary, a
#      HashDictionary, a Set and a CountedSet, each with an exact, an hnsw and an ivf_flat index,
#      the ivf one trained and retrained by numpy); protoBaseST changes every root with every
#      mutator of its kind, adds an exact index and removes the hnsw one, commits, then commits
#      two blind writes of 'dict' and 'bag' (the second merged by its commit onto the
#      vector-indexed current: a retrain there replaces numpy's centroids by protoBaseST's);
#      proto_db validates every root and answers near queries on the exact index and on the
#      ivf_flat index probed in full, each equal to near_oracle (py_vector_replay.py verify), and
#      protoBaseST validates every root too.
#   2. The reverse: protoBaseST writes the space (its pure-path centroids), proto_db changes and
#      merges it the same way (numpy's retrains), and both validate it, proto_db's queries
#      answering as near_oracle.
# Validation must pass in every direction: the format leaves the centroids to the writer, and
# list numbers are recomputed from the stored centroids by whoever reads them (DV3). The two
# summaries of a space (count, index names, members and invalid occurrences per index) must be
# equal line for line. Every step is a process run to completion. The spaces go to a new directory
# under $VECTOR_BD_OUT (default tests/interop/out/vector_both_directions, ignored by git); nothing
# is removed. Exit 77 without the reference venv or without .venv-numpy (the skip names the
# script that makes it); a .venv-numpy that holds another proto_db, or in which proto_db does not
# see numpy, fails.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
fail() { echo "FAIL: $*"; exit 1; }
NUMPY_VENV="$HERE/.venv-numpy"
if [[ ! -x "$NUMPY_VENV/bin/python" || ! -d "$NUMPY_VENV/protobase/proto_db" ]]; then
    echo "SKIP: tests/interop/.venv-numpy missing (run tests/interop/setup_venv_numpy.sh)"
    exit 77
fi
pinned="$(sed -n 's/^TAG_COMMIT="\(.*\)"$/\1/p' "$HERE/setup_venv_numpy.sh")"
held="$(cat "$NUMPY_VENV/protobase/.commit" 2>/dev/null || true)"
[[ -n "$pinned" && "$held" == "$pinned"* ]] || fail "tests/interop/.venv-numpy holds proto_db ${held:-of unknown commit}, not $pinned (run tests/interop/setup_venv_numpy.sh)"
pyn() { PYTHONPATH="$NUMPY_VENV/protobase" "$NUMPY_VENV/bin/python" "$HERE/py_vector_replay.py" "$@"; }
st() { (cd "$HERE" && "$PROTOST" _st_vector_ops.st "$@"); }
OUT="${VECTOR_BD_OUT:-$HERE/out/vector_both_directions}/run-$$-$(date +%s%N)"
mkdir -p "$OUT" || fail "cannot create $OUT"

# 1. proto_db writes, protoBaseST changes and merges.
pyn write "$OUT/py-first" 2> "$OUT/py-first.meta" || { cat "$OUT/py-first.meta"; fail "proto_db could not write the space"; }
mode="$(head -n 1 "$OUT/py-first.meta")"
[[ "$mode" == "numpy: "[0-9]* ]] || fail "proto_db did not run in its default mode: $mode"
st change "$OUT/py-first" > "$OUT/py-first.change" 2>&1 || { tail -n 5 "$OUT/py-first.change"; fail "protoBaseST could not change proto_db's space"; }
pyn verify "$OUT/py-first" > "$OUT/py-first.py" 2>> "$OUT/py-first.meta" || {
    tail -n 5 "$OUT/py-first.meta"; fail "proto_db refused the space protoBaseST changed"; }
st verify "$OUT/py-first" > "$OUT/py-first.st" 2>&1 || { tail -n 5 "$OUT/py-first.st"; fail "protoBaseST refused its own changes"; }
sed 's/ queries=[0-9]*//' "$OUT/py-first.py" | cmp -s - "$OUT/py-first.st" || {
    diff <(sed 's/ queries=[0-9]*//' "$OUT/py-first.py") "$OUT/py-first.st"; fail "the two readers of the space disagree ($OUT)"; }

# 2. protoBaseST writes, proto_db changes and merges.
st write "$OUT/st-first" > "$OUT/st-first.write" 2>&1 || { tail -n 5 "$OUT/st-first.write"; fail "protoBaseST could not write the space"; }
pyn change "$OUT/st-first" 2> "$OUT/st-first.meta" || { cat "$OUT/st-first.meta"; fail "proto_db could not change protoBaseST's space"; }
st verify "$OUT/st-first" > "$OUT/st-first.st" 2>&1 || { tail -n 5 "$OUT/st-first.st"; fail "protoBaseST refused the space proto_db changed"; }
pyn verify "$OUT/st-first" > "$OUT/st-first.py" 2>> "$OUT/st-first.meta" || {
    tail -n 5 "$OUT/st-first.meta"; fail "proto_db refused its own changes"; }
sed 's/ queries=[0-9]*//' "$OUT/st-first.py" | cmp -s - "$OUT/st-first.st" || {
    diff <(sed 's/ queries=[0-9]*//' "$OUT/st-first.py") "$OUT/st-first.st"; fail "the two readers of the space disagree ($OUT)"; }
[[ "$(wc -l < "$OUT/py-first.st")" -eq 5 && "$(wc -l < "$OUT/st-first.st")" -eq 5 ]] || fail "expected five roots in each space"
queries=$(sed -n 's/.* queries=\([0-9]*\).*/\1/p' "$OUT/py-first.py" "$OUT/st-first.py" | paste -sd+ | bc)
echo "NOTE: proto_db ran with $mode"
echo "vector-indexed collections in both directions with proto_db's default mode: 2 spaces, 10 roots validated by both, $queries near queries answered by proto_db as near_oracle"
