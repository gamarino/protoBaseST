#!/usr/bin/env bash
# Values at the nesting limit, protoST to Python (format spec v2.0.0rc2, "Value nesting depth";
# plan Tasks 13 and 17b). protoST writes a space whose records hold attribute values exactly
# MAX_VALUE_DEPTH = 1022 containers deep (DBObject fields, a map key path, and the nodes of a
# List, a Dictionary, a Set and a HashDictionary at their effective limits), checking first that
# its writer refuses one container more; ProtoBase's verifier accepts the space (exit 0), and
# ProtoBase reads every value back with Python's default recursion limit, refuses a record
# holding 1023 (ProtoCorruptionError) and refuses to write 1023 (ProtoValidationError)
# (py_read_deep.py). Exit 77 without the interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src:$REPO/tests/unit${STPATH:+:$STPATH}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

(cd "$HERE" && "$PROTOST" _st_deep_space.st "$TMP") || fail "_st_deep_space.st exited $?"
"$PY" -m proto_db.tools.verify "$TMP/space" --out "$TMP/py.json" || fail "ProtoBase's verifier exited $? on protoST's space"
"$PY" "$HERE/py_read_deep.py" "$TMP" || fail "py_read_deep.py"
echo "values at the nesting limit read back by ProtoBase"
