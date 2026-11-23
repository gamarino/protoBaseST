#!/usr/bin/env bash
# Lesson 11, indexed part: an index added by Python, changed and merged onto by protoST,
# validated by Python. Tutorial chapter: docs/tutorial/11-python-interop.md ("Indexes, from both
# sides").
#
# What it teaches: Python's proto_db writes a collection with an equality and a range index, and
# (0.4.0) a dictionary of documents with a vector index; protoST changes each through its mutators
# (a replaced element, a removed one, a new one) and a blind write of its own merges onto it;
# proto_db then validates every index against a scan, plans the same queries with the same indexes
# (a VectorSearch answering what a brute force answers), and its verifier accepts the directory.
#
# Needs the pinned proto_db in tests/interop/.venv (tests/interop/setup_venv.sh). Without it
# the lesson is skipped (exit 77), as the interop tests are.
# Run it: PROTOST=<the protost binary> examples/tutorial/11_indexed_interop.sh
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=../../tests/interop/env.sh
source "$REPO/tests/interop/env.sh"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$HERE"

"$PY" 11_indexed_python_side.py write "$WORK/space"
out="$("$PROTOST" _indexed_change.st "$WORK/space")"
printf '%s\n' "$out"
[[ "$(printf '%s\n' "$out" | tail -n 1)" == "11 indexed interop ok (12 checks)" ]] || exit 1
"$PY" 11_indexed_python_side.py check "$WORK/space"
"$PY" -m proto_db.tools.verify "$WORK/space" > "$WORK/verify.txt" \
    || { echo "FAIL: proto_db's verifier refused the directory"; cat "$WORK/verify.txt"; exit 1; }
echo "proto_db's verifier accepts the directory"
