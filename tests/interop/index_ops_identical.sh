#!/usr/bin/env bash
# Indexed queries, plan Task 4a (spec 6.1.2): every mutator of every collection kind maintains the
# indexes node for node as ProtoBase's does. py_index_replay.py writes the spaces: main (60 records
# and a seeded operation sequence per kind, PBList, PBDictionary, PBHashDictionary, PBSet and
# PBCountedSet, each mutator in turn, with addIndex: of an equality index on the path 'v' and of
# range indexes on an extractor and on 'v', then removeIndex:) and, in a space of its own, a
# Dictionary holding a format-3 index. Each side replays the sequences on its own copy of the
# spaces, plus a blind write and a first change on the format-3 index (kept, then rebuilt), and
# prints every resulting collection atom by atom (the content trees, the index set and every index
# tree, the encoded bytes of every state): the two
# outputs must be equal line for line. Each side then commits its results; ProtoBase's verifier
# (run with the extractor registered: py_index_replay.py check) must accept protoBaseST's space
# (every record decoded and canonical, collection.validate() on every collection, its indexes
# included), validate() must accept the committed format-3 dictionary, now rebuilt (it lives in a
# space of its own, since the verifier also validates the old version, which does not validate),
# and the verifier's dump of protoBaseST's space must equal its dump of ProtoBase's own
# (compare_dumps.py --exact).
# Everything goes to a new directory under $INDEX_OPS_OUT (default tests/interop/out/index_ops,
# ignored by git); nothing is removed. Exit 77 without the interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src:$REPO/tests/unit${STPATH:+:$STPATH}"
fail() { echo "FAIL: $*"; exit 1; }
OUT="${INDEX_OPS_OUT:-$HERE/out/index_ops}/run-$$-$(date +%s%N)"
mkdir -p "$OUT" || fail "cannot create $OUT"

mkdir -p "$OUT/made" && "$PY" "$HERE/py_index_replay.py" make "$OUT/made" || fail "py_index_replay.py make exited $?"
cp -r "$OUT/made" "$OUT/py" && cp -r "$OUT/made" "$OUT/st" || fail "cannot copy the space"
"$PY" "$HERE/py_index_replay.py" replay "$OUT/py" > "$OUT/py.txt" || fail "py_index_replay.py replay exited $?"
(cd "$HERE" && "$PROTOST" _st_index_ops.st "$OUT/st" > "$OUT/st.txt" 2>&1) || {
    tail -n 5 "$OUT/st.txt"; fail "_st_index_ops.st exited non-zero"; }
[[ "$(tail -n 1 "$OUT/py.txt")" == "end" && "$(tail -n 1 "$OUT/st.txt")" == "end" ]] || fail "a replay did not finish ($OUT)"
collections=$(grep -c '^collection ' "$OUT/py.txt")
[[ "$collections" -eq 6 ]] || fail "expected 6 collection dumps, ProtoBase printed $collections"
cmp -s "$OUT/py.txt" "$OUT/st.txt" || {
    diff "$OUT/py.txt" "$OUT/st.txt" | head -n 6 | cut -c1-300
    fail "the collections or their index trees differ from ProtoBase's ($OUT)"; }
"$PY" "$HERE/py_index_replay.py" check "$OUT/st" || fail "ProtoBase's verifier or validate() refused protoBaseST's spaces"
"$PY" "$HERE/py_index_replay.py" check "$OUT/py" || fail "ProtoBase's verifier or validate() refused its own spaces"
"$PY" "$HERE/compare_dumps.py" "$OUT/py/verify.json" "$OUT/st/verify.json" --exact || fail "the dumps differ"
echo "index maintenance identical to ProtoBase: $collections collections, $(grep -vc '^collection \|^end' "$OUT/py.txt") atoms; verifier ok"
