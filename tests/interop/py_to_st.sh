#!/usr/bin/env bash
# Design spec 10.2, Python to protoST (plan Task 13). ProtoBase writes the space
# (py_write_space.py), its verifier dumps it (py_verify.py, plan call C10), protoBaseST dumps
# it (_st_dump.st, which also reads it through a transaction), and the two dumps must be
# equal (compare_dumps.py, plan call C11). Exit 77 without the interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src:$REPO/examples/erp${STPATH:+:$STPATH}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

"$PY" "$HERE/py_write_space.py" "$TMP/space" || fail "py_write_space.py"
"$PY" "$HERE/py_verify.py" "$TMP/space" --out "$TMP/py.json" || fail "py_verify.py exited $?"
(cd "$HERE" && "$PROTOST" _st_dump.st "$TMP/space" "$TMP/st.json") || fail "_st_dump.st exited $?"
"$PY" "$HERE/compare_dumps.py" "$TMP/py.json" "$TMP/st.json" || fail "the dumps differ"
echo "python to protoST ok"
