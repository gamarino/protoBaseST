#!/usr/bin/env bash
# Plan Task 27: real processes, kill -9 of the owner and of a voter. Every member is a protost
# process of its own (_node.st); the learner v joins only once the workload is done and verifies
# it (_cluster.sh cluster_verify: every acknowledged token is present; the counter equals the
# size of 'tokens' and the acknowledged tokens plus the unknown tokens present, a killed member's
# one unresolved token counting as unknown).
#
# Run kill-owner, three voters (n0, n1, n2): each worker commits 30 increments; the worker that
# serves the current term after its K1-th acknowledgement takes mark1 (_node.st stage 'owner')
# and goes on committing; the test kills it with kill -9 while it commits. The two others then
# commit 10 more each, which needs a term won by a living member: their newest committed label
# must be above the dead owner's term (terms only grow).
#
# Run kill-voter, five workers (voters n0, n1, n2; learners n3, n4): a voter that does not serve
# the term takes mark1 after K1 acknowledgements and is killed the same way while the owner stays
# up; two of three voters remain, and the four other workers commit 10 more each.
#
# Run kill-two-owners, five voters (n0..n4, majority 3): the owner is killed after K1
# acknowledgements (4 of 5 remain); the survivors commit on, and the owner of the new term, which
# is not the dead one, takes mark2 after K2 acknowledgements counted from the first kill and is
# killed too: exactly 3 of 5 remain, and they commit 10 more each. The new owner's term is above
# the first one, and the survivors' newest committed label is above the second.
#
# K1 (10..19) and K2 (1..5) are drawn per run from a seed printed in a NOTE (KILL_SEED sets it,
# to replay a run). Every step waits on a marker file; no duration is asserted, the runner's
# timeout is the only deadline.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_cluster.sh
source "$HERE/_cluster.sh"

SEED="${KILL_SEED:-$RANDOM}"
[[ "$SEED" =~ ^[0-9]+$ ]] || fail "KILL_SEED must be a non-negative integer, not $SEED"
echo "NOTE: KILL_SEED=$SEED"
K1=$((10 + SEED % 10))
K2=$((1 + (SEED / 10) % 5))

# kill_run <name> <voters> <marks> <worker>...: <marks> as _node.st takes it ('owner:K' or
# 'voter:K', comma-separated stages); stage s is mark<s> and killed<s>.
kill_run() {
    local name="$1" voters="$2" marks="$3"; shift 3
    local run id stage mode k victim term acked_now deadline victims="" prev_term=0 others=() dones=()
    local -a specs
    IFS=, read -r -a specs <<< "$marks"
    run="$(cluster_run "$name")"; [[ -n "$run" ]] || fail "no run directory"
    for id in "$@"; do cluster_worker "$run" "$id" 30 10 "$marks"; done
    cluster_verifier "$run" v
    cluster_peers "$run" "$voters" "$@" v
    for stage in $(seq 1 "${#specs[@]}"); do
        mode="${specs[stage-1]%%:*}"; k="${specs[stage-1]##*:}"
        cluster_wait "$run" "mark$stage"
        # The mark file is created, then written and synced: wait for its line.
        deadline=$((SECONDS + WAIT_SECONDS))
        until read -r victim term < "$run/out/mark$stage" 2>/dev/null \
                && [[ -n "$victim" && "$term" =~ ^[0-9]+$ ]]; do
            (( SECONDS > deadline )) && fail_run "$run" "mark$stage names nobody"
            sleep 0.1
        done
        [[ " $* " == *" $victim "* ]] || fail_run "$run" "mark$stage names $victim, not a worker"
        [[ " $victims " == *" $victim "* ]] && fail_run "$run" "mark$stage names $victim, killed already"
        acked_now="$(wc -l < "$run/out/$victim.acked")"
        (( acked_now >= k )) || fail_run "$run" "$victim took mark$stage with $acked_now acknowledgements, K is $k"
        if [[ "$mode" == voter ]]; then
            [[ " $voters " == *" $victim "* ]] || fail_run "$run" "mark$stage names $victim, not a voter"
        else
            (( term > prev_term )) \
                || fail_run "$run" "$victim serves term $term at mark$stage, not above the dead owner's $prev_term"
            prev_term=$term
        fi
        cluster_kill "$run" "$victim" "killed$stage"
        victims+=" $victim"
        echo "NOTE: $name: killed $victim (stage $stage, $mode, K=$k, term $term) after $acked_now acknowledgements"
    done
    for id in "$@"; do
        [[ " $victims " == *" $id "* ]] || { others+=("$id"); dones+=("$id.done"); }
    done
    cluster_wait "$run" "${dones[@]}"
    cluster_finish "$run" v
    cluster_verify "$run" v "$@"
    # The survivors' last commits came after the last kill: under a term a living member won,
    # above the term the last killed owner served (terms only grow).
    local label top=0
    for id in "${others[@]}"; do
        label="$(sed -n 's/.* committed_label \([0-9][0-9]*\)\( .*\)\{0,1\}$/\1/p' "$run/out/$id.done")"
        [[ -n "$label" ]] || fail_run "$run" "$id.done: $(cat "$run/out/$id.done")"
        (( label > top )) && top=$label
    done
    (( top > prev_term )) \
        || fail_run "$run" "the survivors know no root committed above the dead owner's term $prev_term (newest label $top)"
    echo "NOTE: $name: ${others[*]} finished; newest committed label known to the survivors $top"
}

kill_run kill-owner "n0 n1 n2" "owner:$K1" n0 n1 n2
kill_run kill-voter "n0 n1 n2" "voter:$K1" n0 n1 n2 n3 n4
kill_run kill-two-owners "n0 n1 n2 n3 n4" "owner:$K1,owner:$K2" n0 n1 n2 n3 n4
echo "real kill owner ok"
