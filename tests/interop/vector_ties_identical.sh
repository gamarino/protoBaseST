#!/usr/bin/env bash
# Vectors phase V8, fix round 2 (Addendum V, 2.4 and 2.5): ties in an exact vector search are
# broken by the member key's order key in both implementations, and an atom's member key orders by
# its oid. py_vector_ties.py (proto_db, numpy and hnswlib blocked) and _st_vector_ties.st build the
# same 200 records of dim 4 under an exact index, ip and cosine, and search a zero query (every
# score 0.0, so the tie rule alone decides). With the random version-4 oids a new atom draws on
# first need (both implementations, ProtoBase D21) each side must answer the ten records of least
# order key in its own process (the lists differ from process to process, in both); with injected
# oids both must print the same lines, and the injected answer must be the ten records with oids 1
# to 10 in oid order, [0, 173, 146, 119, 92, 65, 38, 11, 184, 157]. Outputs go to a new directory
# under $VECTOR_TIES_OUT (default tests/interop/out/vector_ties, ignored by git); nothing is
# removed. Exit 77 without the interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
fail() { echo "FAIL: $*"; exit 1; }
OUT="${VECTOR_TIES_OUT:-$HERE/out/vector_ties}/run-$$-$(date +%s%N)"
mkdir -p "$OUT" || fail "cannot create $OUT"

"$PY" "$HERE/py_vector_ties.py" > "$OUT/py.txt" 2>&1 || { tail -n 5 "$OUT/py.txt"; fail "py_vector_ties.py exited non-zero"; }
(cd "$HERE" && "$PROTOST" _st_vector_ties.st > "$OUT/st.txt" 2>&1) || { tail -n 5 "$OUT/st.txt"; fail "_st_vector_ties.st exited non-zero"; }
expected="[0, 173, 146, 119, 92, 65, 38, 11, 184, 157]"
for side in py st; do
    f="$OUT/$side.txt"
    [[ "$(tail -n 1 "$f")" == "end" ]] || { cat "$f"; fail "$side did not finish ($OUT)"; }
    for m in ip cosine; do
        grep -qxF "random-oids $m answer-is-oid-order True" "$f" || { cat "$f"; fail "$side: with random oids the $m ties are not in oid order"; }
        grep -qxF "injected-oids $m $expected" "$f" || { cat "$f"; fail "$side: with injected oids the $m answer is not $expected"; }
    done
done
diff <(grep '^injected' "$OUT/py.txt") <(grep '^injected' "$OUT/st.txt") > /dev/null || fail "the injected-oid answers differ ($OUT)"
echo "vector ties identical to proto_db: ip and cosine, zero query over 200 atoms; random oids in oid order on both sides; injected oids $expected"
