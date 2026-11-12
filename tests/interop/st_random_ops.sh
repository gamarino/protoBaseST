#!/usr/bin/env bash
# Design spec 10.6, plan Task 20: seeded random operations on every collection protoBaseST can
# write (PBList, PBDictionary, PBHashDictionary, PBSet, PBCountedSet; the seeds are recorded in
# _st_random_ops.st), 20 commits, each followed by PBAvl check: and a comparison with a model.
# At the end ProtoBase's verifier runs over the whole space (exit 0: every record decoded,
# canonical and valid, every tree's invariants checked), and its dump must equal protoST's.
# Exit 77 without the interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src:$REPO/tests/unit${STPATH:+:$STPATH}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

out="$(cd "$HERE" && "$PROTOST" _st_random_ops.st "$TMP/space" "$TMP/st.json")" || fail "_st_random_ops.st exited $?: $out"
[[ "$out" == written\ list=* ]] || fail "_st_random_ops.st printed: $out"
"$PY" -m proto_db.tools.verify "$TMP/space" --out "$TMP/py.json" || fail "ProtoBase's verifier exited $? on protoST's space"
"$PY" "$HERE/compare_dumps.py" "$TMP/py.json" "$TMP/st.json" --exact || fail "the dumps differ"
echo "random structures ok ($out)"
