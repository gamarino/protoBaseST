#!/usr/bin/env bash
# qry_pager_racing.st with a pool of one worker (PROTOST_WORKERS=1). Its writers' waits (the
# commit's wait for the round runner and the back-off between retries) are nested in blocks, so
# they run other actors' messages on top of themselves; with one worker no other worker can take
# those messages, so a message that never ended would hang this run. Every message of the test is
# finite, so it must pass as it does with any pool. A run still waiting after 300 s is reported as
# the hang it is (the test takes about 10 s).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTOST="${PROTOST:-protost}"
export STPATH="$HERE/../../src${STPATH:+:$STPATH}"
out="$(cd "$HERE" && PROTOST_WORKERS=1 timeout 300 "$PROTOST" --print-last qry_pager_racing.st </dev/null 2>&1)"
rc=$?
last="$(printf '%s\n' "$out" | grep -v '^$' | tail -n 1)"
if [[ $rc -eq 124 ]]; then
    echo "FAILED: qry_pager_racing.st with one worker still running after 300 s (a hang)"
    exit 1
fi
if [[ $rc -ne 0 || "$last" != ok ]]; then
    echo "FAILED: qry_pager_racing.st with one worker: exit $rc, output:"
    printf '%s\n' "$out"
    exit 1
fi
echo "NOTE: one worker: $(printf '%s\n' "$out" | grep '^commits ' | tail -n 1)"
exit 0
