#!/usr/bin/env bash
# Plan Task 26: proto_db reads a cluster space protoBaseST wrote. _st_cluster_space.st write runs
# three in-process nodes on one directory, commits the ERP-shaped workload of _st_write_space.st
# through the coordinator (each commit on another node), sync:s and stops. proto_db's verifier
# (py_verify.py) must accept the directory (exit 0: every record decoded, canonical and valid) and
# dump what protoBaseST dumps (compare_dumps.py --exact). The SpaceRoot of space.root must carry
# cluster_term, cluster_epoch and cluster_previous as proto_db reads them: proto_db's
# cluster_fields of the storage root, then the chain of cluster_previous, equal to the chain
# protoBaseST read (term and epoch of each SpaceRoot). The chain is checked to hold the five
# commits at least (newDatabase: and four run:s), down to epoch 1. Every step is
# ordered by the processes' own output, never by time. Exit 77 without the interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
SPACE="$TMP/space"

(cd "$HERE" && "$PROTOST" _st_cluster_space.st write "$SPACE" "$TMP/st.json" "$TMP/st-fields.txt") \
    || fail "_st_cluster_space.st write exited $?"
[[ -d "$SPACE/cluster" ]] || fail "the space has no cluster/ directory"
"$PY" "$HERE/py_verify.py" "$SPACE" --out "$TMP/py.json" || fail "proto_db's verifier exited $?"
"$PY" "$HERE/compare_dumps.py" "$TMP/py.json" "$TMP/st.json" --exact || fail "the dumps differ"

"$PY" - "$SPACE" > "$TMP/py-fields.txt" <<'EOF' || fail "proto_db could not read the cluster fields"
import sys
from proto_db.cluster.persister import cluster_fields
from proto_db.storage.file import FileStorage

storage = FileStorage(sys.argv[1])
try:
    record = storage.read_root()
    label, epoch, previous = cluster_fields(storage, record)
    if label == 0:
        sys.exit("space.root holds a root written outside cluster mode (no cluster_epoch)")
    print(label, epoch)
    while previous is not None:
        print(previous.cluster_term, previous.cluster_epoch)
        previous = previous.cluster_previous
    print("end")
finally:
    storage.close()
EOF
diff "$TMP/py-fields.txt" "$TMP/st-fields.txt" || fail "proto_db reads other cluster fields than protoBaseST (< proto_db, > protoBaseST)"
# The chain, newest first: every term non-zero and never above the one after it, the epochs
# strictly decreasing down to 1 (the first commit). A term may change between commits (a lease
# can lapse on a loaded machine), so no count of terms is asserted.
awk 'BEGIN { ok = 1 }
     $1 == "end" { done = 1; next }
     { if ($1 !~ /^[1-9][0-9]*$/ || $2 !~ /^[1-9][0-9]*$/) ok = 0
       if (NR > 1 && !(length($1) < length(t) || (length($1) == length(t) && $1 <= t))) ok = 0
       if (NR > 1 && $2 + 0 >= e + 0) ok = 0
       t = $1; e = $2; n++ }
     END { exit !(ok && done && n >= 5 && e == 1) }' "$TMP/py-fields.txt" \
    || fail "the cluster_previous chain is not a chain of cluster commits down to epoch 1: $(tr '\n' ' ' < "$TMP/py-fields.txt")"
echo "cluster space to proto_db ok"
