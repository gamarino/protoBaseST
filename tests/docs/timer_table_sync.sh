#!/usr/bin/env bash
# The timer table of docs/reference.md is generated from PBClusterConfig timerTable: the lines
# between "<!-- timer-table: begin -->" and "<!-- timer-table: end -->" must be exactly what
# `tests/docs/timer_table_sync.sh --print` prints, a Markdown table with one row per timer
# (name, default, what it drives), printed by tests/docs/_timer_table.st. A timer changed in cluster/config.st without the reference, or
# the reverse, fails here. Run with --print to regenerate the table.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
PROTOST="${PROTOST:-protost}"
command -v "$PROTOST" >/dev/null 2>&1 || [[ -x "$PROTOST" ]] || { echo "FAIL: no protost binary (set PROTOST)"; exit 1; }
table="$(cd "$HERE" && STPATH="$REPO/src" "$PROTOST" _timer_table.st)" || { echo "FAIL: protost could not print PBClusterConfig timerTable"; exit 1; }
if [[ "${1:-}" == --print ]]; then printf '%s\n' "$table"; exit 0; fi
doc="$(sed -n '/<!-- timer-table: begin -->/,/<!-- timer-table: end -->/p' "$REPO/docs/reference.md" | sed '1d;$d')"
[[ -n "$doc" ]] || { echo "FAIL: docs/reference.md has no timer-table markers"; exit 1; }
if [[ "$doc" != "$table" ]]; then
    echo "FAIL: the timer table of docs/reference.md differs from PBClusterConfig timerTable:"
    diff <(printf '%s\n' "$doc") <(printf '%s\n' "$table")
    exit 1
fi
echo "docs/reference.md: the timer table matches PBClusterConfig timerTable ($(printf '%s\n' "$table" | tail -n +3 | wc -l) rows)"
