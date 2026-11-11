#!/usr/bin/env bash
# The deepest attribute value protoBaseST writes inside an atom record (509 nested lists,
# plan Task 13) is read back by ProtoBase. Exit 77 without the interop venv. ProtoBase needs a
# raised Python recursion limit for it until ask B12 lands (v2.0.0rc2); py_read_deep.py says so
# in a NOTE line on every run and fails once B12 makes the workaround unnecessary.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src:$REPO/tests/unit${STPATH:+:$STPATH}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

(cd "$HERE" && "$PROTOST" _st_deep_space.st "$TMP/space") || fail "_st_deep_space.st exited $?"
"$PY" "$HERE/py_read_deep.py" "$TMP/space" || fail "py_read_deep.py"
echo "deep attribute read back by ProtoBase"
