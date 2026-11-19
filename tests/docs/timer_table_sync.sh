#!/usr/bin/env bash
# The timer table of docs/reference.md is generated from PBClusterConfig timerTable: the lines
# between "<!-- timer-table: begin -->" and "<!-- timer-table: end -->" must be exactly what
# `tests/docs/timer_table_sync.sh --print` prints, a Markdown table with one row per timer
# (name, default, what it drives), printed by tests/docs/_timer_table.st. A timer changed in cluster/config.st without the reference, or
# the reverse, fails here. Run with --print to regenerate the table. Chapter 16's own timer table
# is checked too: its Timer and Default columns (below).
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
# docs/tutorial/16-operating-a-cluster.md has its own timer table (Timer, Set by, Default, Drives):
# its Timer and Default columns, in order, must be the generated table's first two.
want="$(printf '%s\n' "$table" | tail -n +3 | awk -F'|' '{ gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $3); print $2 "|" $3 }')"
chapter="$(awk '/^\| Timer \| Set by \| Default \|/ { on = 1; getline; next } on && /^\| / { print; next } on { exit }' \
    "$REPO/docs/tutorial/16-operating-a-cluster.md" | awk -F'|' '{ gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $4); print $2 "|" $4 }')"
[[ -n "$chapter" ]] || { echo "FAIL: docs/tutorial/16-operating-a-cluster.md has no timer table (| Timer | Set by | Default | ...)"; exit 1; }
if [[ "$chapter" != "$want" ]]; then
    echo "FAIL: the Timer and Default columns of chapter 16's timer table differ from PBClusterConfig timerTable:"
    diff <(printf '%s\n' "$chapter") <(printf '%s\n' "$want")
    exit 1
fi
echo "docs/reference.md and chapter 16: the timer tables match PBClusterConfig timerTable ($(printf '%s\n' "$table" | tail -n +3 | wc -l) rows)"
