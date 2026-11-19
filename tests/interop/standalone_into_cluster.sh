#!/usr/bin/env bash
# Final review I3: an existing standalone space is brought into a protoBaseST cluster, for a space
# written by protoBaseST and one written by proto_db (py_standalone_space.py write). For each:
# proto_db reads the pointer of the plain root (label 0, no predecessor); _st_into_cluster.st
# convert opens the directory on three in-process nodes with clusterPath:, reads the old data on
# every node, commits on n1 and sync:s; then proto_db's verifier accepts the directory and
# py_standalone_space.py check reads it: space.root is a cluster root whose cluster_previous chain
# ends at that plain root, and the data holds the commit and the old token. The one-way refusal of
# PBFileStorage path: is in tests/unit/cluster_standalone_into_cluster.st. Every step is ordered
# by the processes' own output, never by time. Exit 77 without the interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

# convert <case> <expected token>: the space $TMP/<case> is standalone; it is converted and checked.
convert() {
    local space="$TMP/$1" plain out
    plain="$("$PY" "$HERE/py_standalone_space.py" pointer "$space")" || fail "$1: proto_db could not read the standalone root: $plain"
    out="$(cd "$HERE" && "$PROTOST" _st_into_cluster.st convert "$space" 2>&1)" || fail "$1: _st_into_cluster.st convert: $out"
    [[ "$(printf '%s\n' "$out" | tail -n 1)" == "converted $2" ]] || fail "$1: the cluster read another token: $out"
    "$PY" "$HERE/py_verify.py" "$space" --out "$TMP/$1.json" > /dev/null || fail "$1: proto_db's verifier exited $?"
    "$PY" "$HERE/py_standalone_space.py" check "$space" "$plain" "$2" || fail "$1: proto_db's reading of the converted space"
}

out="$(cd "$HERE" && "$PROTOST" _st_into_cluster.st write-standalone "$TMP/st" 2>&1)" || fail "write-standalone: $out"
convert st standalone
"$PY" "$HERE/py_standalone_space.py" write "$TMP/py" || fail "py_standalone_space.py write exited $?"
convert py proto_db
echo "standalone into cluster ok"
