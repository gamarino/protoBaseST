#!/usr/bin/env bash
# Values at the nesting limit, Python to protoST (format spec v2.0.0rc2, "Value nesting depth";
# plan Task 17b). ProtoBase writes a space whose records hold attribute values exactly
# MAX_VALUE_DEPTH = 1022 containers deep, the shapes st_deep_to_py.sh writes the other way
# (py_write_deep.py); protoST reads every value back and re-encodes every record it checks to
# ProtoBase's bytes (_st_read_deep.st). The refusals of 1023 on both sides, when written and when
# read, are in st_deep_to_py.sh and tests/unit/tx_atom_depth.st. Exit 77 without the interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

"$PY" "$HERE/py_write_deep.py" "$TMP/space" || fail "py_write_deep.py exited $?"
(cd "$HERE" && "$PROTOST" _st_read_deep.st "$TMP/space") || fail "_st_read_deep.st exited $?"
echo "values at the nesting limit read back by protoST"
