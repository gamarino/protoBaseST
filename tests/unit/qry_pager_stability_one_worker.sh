#!/usr/bin/env bash
# qry_pager_stability.st with a pool of one worker (PROTOST_WORKERS=1). The first version of that
# test hung whenever a wait nested in a block ran, on top of itself, an actor message that never
# ended: its writer and reader actors each looped until the readers were done, so a reader whose
# wait ran a writer's loop could never resume, and the writer looped until that reader was done.
# With the default pool, an idle worker usually took the messages first and the hang was rare
# (once in a full-suite run on protoST 0.14.1; in soaks of 100 runs, 0 on 0.14.1, 1 on 0.14.2,
# 3 on 0.16.0); with one worker no other worker can take them, and the old test hung in every run
# tried (11 of 11 on 0.14.1, 0.14.2 and 0.16.0). The test now drives every reader
# step and every commit as its own finite message from the program thread, so a message run on top
# of a wait always ends; with one worker it must pass as it does with any pool. A run still waiting
# after 300 s is reported as the hang it is (the test takes about 20 s).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTOST="${PROTOST:-protost}"
export STPATH="$HERE/../../src${STPATH:+:$STPATH}"
out="$(cd "$HERE" && PROTOST_WORKERS=1 timeout 300 "$PROTOST" --print-last qry_pager_stability.st </dev/null 2>&1)"
rc=$?
last="$(printf '%s\n' "$out" | grep -v '^$' | tail -n 1)"
if [[ $rc -eq 124 ]]; then
    echo "FAILED: qry_pager_stability.st with one worker still running after 300 s (a hang)"
    exit 1
fi
if [[ $rc -ne 0 || "$last" != ok ]]; then
    echo "FAILED: qry_pager_stability.st with one worker: exit $rc, output:"
    printf '%s\n' "$out"
    exit 1
fi
echo "NOTE: one worker: $(printf '%s\n' "$out" | grep '^commits ' | tail -n 1)"
exit 0
