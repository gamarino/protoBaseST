#!/usr/bin/env bash
# Plan Task 26: the acceptor logs, both ways.
# (1) protoBaseST to proto_db: _st_cluster_space.st write runs three nodes on one directory; for
#     each cluster/<n>.roots they wrote, proto_db's RootsLog(path).load() (py_rootlog.py load)
#     equals what protoBaseST decodes (load-log): accepted, committed, promise, top, rejoined.
#     Each log is of log format 2 (proto_db writes 3 only for a root of storage format 5).
# (2) proto_db to protoBaseST: py_rootlog.py write appends promises, accepted and committed roots
#     (the empty space among them) and the rejoined marker through proto_db's API; protoBaseST
#     loads the same values. protoBaseST appends the same sequence through PBAcceptorLog's API
#     (write-log), proto_db loads it, and the two files are equal byte for byte.
# (3) The log names: for the five ids of Review Focus 5 ('n0', 'nœud', 'a/b', '..', 65
#     characters), the file proto_db's _node_log names is cluster/<PBSharedTier logName:>.roots.
# Every step is ordered by the processes' own output, never by time. Exit 77 without the venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
st() { (cd "$HERE" && "$PROTOST" _st_cluster_space.st "$@"); }
SPACE="$TMP/space"

# (1)
st write "$SPACE" "$TMP/st.json" "$TMP/st-fields.txt" > /dev/null || fail "_st_cluster_space.st write exited $?"
for n in n0 n1 n2; do
    log="$SPACE/cluster/$n.roots"
    [[ -f "$log" ]] || fail "protoBaseST wrote no $log"
    [[ "$("$PY" "$HERE/py_rootlog.py" format "$log")" == "2" ]] || fail "$n.roots is not of log format 2"
    "$PY" "$HERE/py_rootlog.py" load "$log" > "$TMP/py-$n.txt" || fail "proto_db could not load $n.roots"
    st load-log "$log" > "$TMP/st-$n.txt" || fail "protoBaseST could not load $n.roots"
    diff "$TMP/py-$n.txt" "$TMP/st-$n.txt" || fail "$n.roots: proto_db (<) and protoBaseST (>) load other values"
    grep -qx 'rejoined true' "$TMP/py-$n.txt" || fail "$n.roots holds no rejoined marker"
done
# The holder logs its own commits (acceptor.st, R67): some log holds a committed root. Which
# nodes learnt which roots depends on the run, so nothing more is asserted per node.
cat "$TMP"/py-n?.txt | grep -q '^committed [1-9][0-9]* 4 ' || fail "no acceptor log holds a committed root"

# (2)
"$PY" "$HERE/py_rootlog.py" write "$TMP/py.roots" > /dev/null || fail "py_rootlog.py write exited $?"
st load-log "$TMP/py.roots" > "$TMP/st-of-py.txt" || fail "protoBaseST could not load proto_db's log"
expected='accepted 7 4 f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff 99 6
committed 7 4 000102030405060708090a0b0c0d0e0f 1234 5
promise 9223372036854775809
top 9223372036854775809
rejoined true'
[[ "$(cat "$TMP/st-of-py.txt")" == "$expected" ]] || fail "protoBaseST loads from proto_db's log: $(tr '\n' ' ' < "$TMP/st-of-py.txt")"
"$PY" "$HERE/py_rootlog.py" load "$TMP/py.roots" > "$TMP/py-of-py.txt" || fail "proto_db could not load its own log"
diff "$TMP/py-of-py.txt" "$TMP/st-of-py.txt" || fail "proto_db's log: proto_db (<) and protoBaseST (>) load other values"
st write-log "$TMP/st.roots" > /dev/null || fail "_st_cluster_space.st write-log exited $?"
"$PY" "$HERE/py_rootlog.py" load "$TMP/st.roots" > "$TMP/py-of-st.txt" || fail "proto_db could not load protoBaseST's log"
[[ "$(cat "$TMP/py-of-st.txt")" == "$expected" ]] || fail "proto_db loads from protoBaseST's log: $(tr '\n' ' ' < "$TMP/py-of-st.txt")"
cmp "$TMP/py.roots" "$TMP/st.roots" || fail "the same entry sequence gave other bytes in proto_db and protoBaseST"

# (3) 'nœud' passes as the hex of its UTF-8, so no locale is involved.
ids=(n0 hex:6ec5937564 a/b .. "$(printf 'a%.0s' {1..65})")
"$PY" "$HERE/py_rootlog.py" name "$TMP/names" "${ids[@]}" > "$TMP/py-names.txt" || fail "py_rootlog.py name exited $?"
st name "${ids[@]}" | sed 's|^\(.*\)$|cluster/\1.roots|' > "$TMP/st-names.txt" || fail "_st_cluster_space.st name exited $?"
diff "$TMP/py-names.txt" "$TMP/st-names.txt" || fail "_node_log (<) and PBSharedTier logName: (>) name other files"
[[ "$(wc -l < "$TMP/py-names.txt")" -eq 5 ]] || fail "expected five log names"
echo "acceptor logs both ways ok"
