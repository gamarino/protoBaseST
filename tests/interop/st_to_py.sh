#!/usr/bin/env bash
# Design spec 10.3, protoST to Python, for the shapes of 10.2 (plan Task 20): protoST writes
# a space through protoBaseST (_st_write_shapes.st: three versions of the database 'erp', every
# collection it can write, a mutable cell, demo.erp records, the integer boundaries of plan
# Review Focus 4 and the boxing threshold of Review Focus 2) and dumps it as st.json.
# ProtoBase's verifier (py_verify.py, with the ERP types registered) must exit 0, its JSON
# must equal protoST's exactly (the space holds no Python-only type), and a ProtoBase reader
# (py_check_shapes.py) asserts the boundary keys and which strings are boxed. Exit 77 without
# the interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src:$REPO/examples/erp${STPATH:+:$STPATH}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

out="$(cd "$HERE" && "$PROTOST" _st_write_shapes.st "$TMP/space" "$TMP/st.json")" || fail "_st_write_shapes.st exited $?"
[[ "$out" == "written" ]] || fail "_st_write_shapes.st printed: $out"
"$PY" "$HERE/py_verify.py" "$TMP/space" --out "$TMP/py.json" || fail "ProtoBase's verifier exited $? on protoST's space"
"$PY" "$HERE/compare_dumps.py" "$TMP/py.json" "$TMP/st.json" --exact || fail "the dumps differ"
"$PY" "$HERE/py_check_shapes.py" "$TMP/space" || fail "ProtoBase's reader disagrees with what protoST wrote"
echo "protoST to Python ok"
