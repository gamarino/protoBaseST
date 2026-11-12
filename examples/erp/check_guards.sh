#!/usr/bin/env bash
# The two guards of the as-of reports (4_report.py and 4_report.st), exercised in both languages
# on spaces whose commit times are scripted (the clock of ProtoBase is replaced while they are
# written; the reports are not touched):
#   ties      versions 2 and 3 carry the same committedAt: the moments cannot be told apart
#   mismatch  versions 3 and 4 carry the same committedAt: the moment of version 3 resolves to
#             version 4, and the report refuses to print it as version 3
# Each report must fail with its message. Exit 77 without the interop venv.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=../../tests/interop/env.sh
source "$REPO/tests/interop/env.sh"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
export PY PROTOST
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$HERE"

# Writes a space whose commits 1, 2, 3, 4 are stamped with the given seconds (after 2026-11-10 09:00:00 UTC).
make_space() {
    "$PY" - "$1" "$2" "$3" "$4" "$5" <<'PYEOF'
import datetime
import sys

import proto_db.transactions as transactions
from proto_db import FileStorage, ObjectSpace

import importlib.util
spec = importlib.util.spec_from_file_location("create", "1_create.py")
create = importlib.util.module_from_spec(spec)
spec.loader.exec_module(create)

directory, *seconds = sys.argv[1], *map(int, sys.argv[2:])
now = [datetime.datetime(2026, 11, 10, 9, 0, 0, tzinfo=datetime.timezone.utc)]
transactions._utc_now = lambda: now[0]
at = lambda s: datetime.datetime(2026, 11, 10, 9, 0, s, tzinfo=datetime.timezone.utc)

now[0] = at(seconds[0])
create.main(directory)                      # version 1 (and the creation, version 0)
space = ObjectSpace(FileStorage(directory))
db = space.open_database("erp")
for n, s in enumerate(seconds[1:], start=2):
    now[0] = at(s)
    tx = db.new_transaction()
    tx.set_root_object("tags", tx.new_dictionary().set_at(n, "x"))
    tx.commit()
space.close()
PYEOF
}

# Runs a report on a space and requires a non-zero exit and the message on its output.
expect_refusal() {
    local label="$1" message="$2"; shift 2
    local out
    if out="$("$@" 2>&1)"; then echo "FAIL: $label: the report succeeded" >&2; exit 1; fi
    [[ "$out" == *"$message"* ]] || { echo "FAIL: $label: expected [$message], got: $out" >&2; exit 1; }
}

make_space "$WORK/ties" 1 2 2 3
expect_refusal "ties, Python" "two demo commits share a timestamp" "$PY" 4_report.py "$WORK/ties"
expect_refusal "ties, protoST" "two demo commits share a timestamp" "$PROTOST" 4_report.st "$WORK/ties"

make_space "$WORK/mismatch" 1 2 3 3
expect_refusal "mismatch, Python" "as_of found version 4, not 3" "$PY" 4_report.py "$WORK/mismatch"
expect_refusal "mismatch, protoST" "asOf found version 4, not 3" "$PROTOST" 4_report.st "$WORK/mismatch"
echo "guards ok"
