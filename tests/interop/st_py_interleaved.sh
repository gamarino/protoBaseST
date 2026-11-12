#!/usr/bin/env bash
# Interleaved commits across the two languages (plan Task 18, fix round 1, review M2; design
# spec 7.3, last paragraph, and 10.4): a commit by either language is validated against the
# newest root at the moment it is built. The interleaving is the nested run of plan call C12:
# the side owning transaction A starts A (which reads x) and B (a blind write of 'tags'), runs
# the other language's one-shot commit as a subprocess (it changes x and writes 'tags' blindly),
# then commits A, which must conflict, and B, which must merge. Both assignments run: protoST
# first, then ProtoBase first, on one space. Exit 77 without the interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
export PY PROTOST
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
SPACE="$TMP/space"

out="$(cd "$HERE" && "$PROTOST" _st_interleave.st setup "$SPACE")" || fail "setup exited $?"
[[ "$out" == "setup" ]] || fail "setup printed: $out"
out="$(cd "$HERE" && "$PROTOST" _st_interleave.st st-first "$SPACE")" || fail "protoST first: exited $? ($out)"
[[ "$out" == "ok" ]] || fail "protoST first printed: $out"
(cd "$HERE" && "$PY" py_interleave.py py-first "$SPACE") || fail "ProtoBase first"
"$PY" -m proto_db.tools.verify "$SPACE" --out "$TMP/verify.json" > /dev/null || fail "ProtoBase's verifier rejects the space"
exit 0
