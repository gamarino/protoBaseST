#!/usr/bin/env bash
# Plan Task 27: real processes, kill -9 of the owner and of a voter.
#
# Run 1, three voters (n0, n1, n2) and the learner v: each worker commits 30 increments; the
# worker that serves the current term at one of its acknowledgements from the 10th on takes the
# mark (_node.st 'owner') and goes on committing; the test kills it with kill -9 while it commits.
# The two others then commit 10 more each (commits made after the owner's death: a new term is
# won by the surviving majority: the survivors know a root committed under a label above the
# owner's term) and finish. v verifies, the killed owner's unresolved tokens
# counting as unknown.
#
# Run 2, five workers (voters n0, n1, n2; learners n3, n4) and v: a voter that does not serve
# the term takes the mark from its 10th acknowledgement on (_node.st 'voter') and is killed with
# kill -9 while it commits; the remaining majority of voters (two of three) carries the other
# four workers' remaining commits and 10 more each.
#
# Same verification as real_commits.sh. Every step waits on a marker file; no duration is
# asserted, the runner's timeout is the only deadline.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_cluster.sh
source "$HERE/_cluster.sh"

# kill_run <name> <mark> <voters> <worker>...
kill_run() {
    local name="$1" mark="$2" voters="$3"; shift 3
    local run id victim victim_term acked_before others=() dones=()
    run="$(cluster_run "$name")"; [[ -n "$run" ]] || fail "no run directory"
    for id in "$@"; do cluster_worker "$run" "$id" 30 10 "$mark"; done
    cluster_verifier "$run" v
    cluster_peers "$run" "$voters" "$@" v
    cluster_wait "$run" mark
    # The mark file is created, then written and synced: wait for its line.
    local deadline=$((SECONDS + WAIT_SECONDS))
    until read -r victim victim_term < "$run/out/mark" && [[ -n "$victim" && "$victim_term" =~ ^[0-9]+$ ]]; do
        (( SECONDS > deadline )) && fail_run "$run" "the mark names nobody"
        sleep 0.1
    done
    [[ " $* " == *" $victim "* ]] || fail_run "$run" "the mark names $victim, not a worker"
    if [[ "$mark" == voter ]]; then
        [[ " $voters " == *" $victim "* ]] || fail_run "$run" "the mark names $victim, not a voter"
    fi
    acked_before="$(wc -l < "$run/out/$victim.acked")"
    (( acked_before >= 10 )) || fail_run "$run" "$victim took the mark after $acked_before acknowledgements"
    cluster_kill "$run" "$victim"
    for id in "$@"; do [[ "$id" == "$victim" ]] || { others+=("$id"); dones+=("$id.done"); }; done
    cluster_wait "$run" "${dones[@]}"
    cluster_finish "$run" v
    cluster_verify "$run" v "$@"
    # Every commit after the owner's death ran under a term a living member won: a term above
    # the one the owner served when it took the mark (terms only grow), so the survivors know a
    # root committed under a higher label (each one's last commits came after the kill).
    local label top=0
    for id in "${others[@]}"; do
        label="$(sed -n 's/.* committed_label \([0-9][0-9]*\)$/\1/p' "$run/out/$id.done")"
        [[ -n "$label" ]] || fail_run "$run" "$id.done: $(cat "$run/out/$id.done")"
        (( label > top )) && top=$label
    done
    if [[ "$mark" == owner ]]; then
        (( top > victim_term )) \
            || fail_run "$run" "the survivors know no root committed above the dead owner's term $victim_term (newest label $top)"
    fi
    echo "NOTE: $name: killed $victim ($mark) after $acked_before acknowledgements; ${others[*]} finished; owner term at the mark $victim_term, newest committed label known to the survivors $top"
}

kill_run kill-owner owner "n0 n1 n2" n0 n1 n2
kill_run kill-voter voter "n0 n1 n2" n0 n1 n2 n3 n4
echo "real kill owner ok"
