#!/usr/bin/env bash
# The ERP demo: Python and protoST on one database directory (design spec 10.8).
# Runs the four steps in order on a fresh temporary directory, checks that both languages
# print the report in expected_report.txt, and prints 'demo ok'. Skipped (exit 77) without
# the interop venv (tests/interop/setup_venv.sh). Environment: PROTOST (default: protost).
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=../../tests/interop/env.sh
source "$REPO/tests/interop/env.sh"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
export PY PROTOST
WORK="$(mktemp -d)"
DB="$WORK/space"
trap 'rm -rf "$WORK"' EXIT
cd "$HERE"

"$PY" 1_create.py "$DB"
"$PROTOST" 2_payments.st "$DB"
"$PROTOST" 3_tag.st "$DB"
"$PY" 4_report.py "$DB" > "$WORK/py.txt"
"$PROTOST" 4_report.st "$DB" > "$WORK/st.txt"

diff -u expected_report.txt "$WORK/py.txt" || { echo "FAIL: the Python report differs from expected_report.txt" >&2; exit 1; }
diff -u expected_report.txt "$WORK/st.txt" || { echo "FAIL: the protoST report differs from expected_report.txt" >&2; exit 1; }
echo "demo ok"
