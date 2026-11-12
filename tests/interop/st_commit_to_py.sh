#!/usr/bin/env bash
# Design spec 10.3 for the transactions' write side and the publisher (plan Task 18): protoST
# creates a database and commits through PBTransaction and its space's publisher (a blind
# merge, a mutable cell); ProtoBase's verifier must accept the space (exit 0: every record
# decoded, canonical and valid), ProtoBase reads it back, and the DatabaseRoot and SpaceRoot
# records protoST writes hold their fields in ProtoBase's order. ProtoBase then commits a blind
# merge on top, protoST reads it and merges again, and both the verifier and ProtoBase check
# the result. Exit 77 without the interop venv.
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

out="$(cd "$HERE" && "$PROTOST" _st_commit_space.st create "$SPACE")" || fail "_st_commit_space.st create exited $?"
[[ "$out" == "created" ]] || fail "_st_commit_space.st create printed: $out"
"$PY" -m proto_db.tools.verify "$SPACE" --out "$TMP/create.json" > /dev/null || fail "ProtoBase's verifier rejects protoST's commits"
"$PY" "$HERE/py_commit_space.py" check-create "$SPACE" || fail "ProtoBase reads protoST's commits"
"$PY" "$HERE/py_commit_space.py" commit "$SPACE" || fail "ProtoBase commits on protoST's database"
out="$(cd "$HERE" && "$PROTOST" _st_commit_space.st extend "$SPACE")" || fail "_st_commit_space.st extend exited $?"
[[ "$out" == "extended" ]] || fail "_st_commit_space.st extend printed: $out"
"$PY" -m proto_db.tools.verify "$SPACE" --out "$TMP/extend.json" > /dev/null || fail "ProtoBase's verifier rejects protoST's merge"
"$PY" "$HERE/py_commit_space.py" check-extend "$SPACE" || fail "ProtoBase reads protoST's merge on top of its own"
exit 0
