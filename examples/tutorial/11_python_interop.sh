#!/usr/bin/env bash
# Lesson 11: one directory, two languages. Tutorial chapter: docs/tutorial/11-python-interop.md
#
# What it teaches: the files protoBaseST writes are proto_db's files. protoST creates a
# database (_interop_write.st); Python's proto_db reads it, asserts every value, and commits a
# record, a cell change and a blind tag (11_python_side.py); proto_db's own verifier accepts
# the directory; protoST reads Python's commit and merges a tag of its own (_interop_read.st).
#
# Needs the pinned proto_db in tests/interop/.venv (tests/interop/setup_venv.sh). Without it
# the lesson is skipped (exit 77), as the interop tests are.
# Run it: PROTOST=<the protost binary> examples/tutorial/11_python_interop.sh
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=../../tests/interop/env.sh
source "$REPO/tests/interop/env.sh"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$HERE"

"$PROTOST" _interop_write.st "$WORK/space"
"$PY" 11_python_side.py "$WORK/space"
"$PY" -m proto_db.tools.verify "$WORK/space" > "$WORK/verify.txt" \
    || { echo "FAIL: proto_db's verifier refused the directory"; cat "$WORK/verify.txt"; exit 1; }
echo "proto_db's verifier accepts the directory"
out="$("$PROTOST" _interop_read.st "$WORK/space")"
printf '%s\n' "$out"
[[ "$(printf '%s\n' "$out" | tail -n 1)" == "11 python interop ok (8 checks)" ]] || exit 1
