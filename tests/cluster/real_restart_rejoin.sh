#!/usr/bin/env bash
# Plan Task 28: real processes, a voter stopped, its acceptor log lost, restarted: it rejoins by
# ballot. Every member is a protost process of its own (_node.st); three voters, n0, n1 and n2,
# commit 40 increments each, recording their tokens.
#
# Once the victim (a voter drawn from the seed, the owner of the term possibly) has K
# acknowledgements, the test stops it cleanly (_node.st <log>.halt: it stops committing, every
# token it attempted resolved, closes its space, stops its node and exits 0). Its acceptor log,
# <space>/cluster/<id>.roots, is renamed aside (the disk lost, as Task 25 stands in for a wiped
# disk; nothing is deleted). The two others go on: a majority of the voters. The member then
# restarts, the same node id and port on an empty log, as a new incarnation '<id>.2' with tokens
# of its own: a voter without its log rejoins before it grants or acknowledges anything, through
# the ballot round (cluster/rejoin.st: two witnesses, both other voters, promise its ballot
# durably), and its stats count it (rejoin_ballots >= 1, which it writes to its .done). It then
# commits 20 increments. The learner v joins once every worker is done and verifies, with the
# rules of cluster_verify (every acknowledged token present; the counter equals the size of
# 'tokens' and the acknowledged tokens plus the unknown tokens present), then syncs.
#
# K (5..14) and the victim are drawn per run from a seed printed in a NOTE (KILL_SEED sets it, to
# replay a run). Every step waits on a marker file; no duration is asserted, the runner's timeout
# is the only deadline.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_cluster.sh
source "$HERE/_cluster.sh"

SEED="${KILL_SEED:-$RANDOM}"
[[ "$SEED" =~ ^[0-9]+$ ]] || fail "KILL_SEED must be a non-negative integer, not $SEED"
echo "NOTE: KILL_SEED=$SEED"
K=$((5 + SEED % 10))
VICTIM="n$(( (SEED / 10) % 3 ))"
IDS=(n0 n1 n2)

run="$(cluster_run restart-rejoin)"; [[ -n "$run" ]] || fail "no run directory"
o="$run/out"
for id in "${IDS[@]}"; do cluster_worker "$run" "$id" 40 0 none; done
cluster_verifier "$run" v
cluster_peers "$run" "${IDS[*]}" "${IDS[@]}" v

# The victim's K-th acknowledgement, then its clean stop.
deadline=$((SECONDS + WAIT_SECONDS))
until [[ -e "$o/$VICTIM.acked" ]] && (( $(wc -l < "$o/$VICTIM.acked") >= K )); do
    _check_live "$run"
    (( SECONDS > deadline )) && fail_run "$run" "$VICTIM has no $K acknowledgements within $WAIT_SECONDS s"
    sleep 0.1
done
# The victim exits on its own once halted: reaped (not left to cluster_wait's liveness check).
: > "$o/$VICTIM.halt"
cluster_reap "$run" "$VICTIM"
[[ -e "$o/$VICTIM.done" ]] || fail_run "$run" "$VICTIM exited 0 without its .done"
grep -q ' halted true$' "$o/$VICTIM.done" \
    || fail_run "$run" "$VICTIM finished its commits before it was halted: $(cat "$o/$VICTIM.done")"
echo "NOTE: restart-rejoin: stopped $VICTIM after $(wc -l < "$o/$VICTIM.acked") acknowledgements (K=$K)"

# Its disk lost: the acceptor log renamed aside, then the member restarts on an empty log.
log="$run/space/cluster/$VICTIM.roots"
[[ -e "$log" ]] || fail_run "$run" "no acceptor log $log"
mv "$log" "$log.lost" || fail_run "$run" "cannot rename $log"
[[ ! -e "$log" ]] || fail_run "$run" "$log is still there"
cluster_worker "$run" "$VICTIM" 20 0 none "$VICTIM.2"

dones=()
for id in "${IDS[@]}"; do [[ "$id" == "$VICTIM" ]] || dones+=("$id.done"); done
cluster_wait "$run" "${dones[@]}" "$VICTIM.2.done"
ballots="$(sed -n 's/.* rejoin_ballots \([0-9][0-9]*\) .*/\1/p' "$o/$VICTIM.2.done")"
[[ -n "$ballots" ]] || fail_run "$run" "$VICTIM.2.done: $(cat "$o/$VICTIM.2.done")"
(( ballots >= 1 )) || fail_run "$run" "$VICTIM rejoined with rejoin_ballots $ballots: not by ballot"
[[ -e "$log" ]] || fail_run "$run" "$VICTIM rejoined without writing a new acceptor log"
echo "NOTE: restart-rejoin: $VICTIM.2 rejoined on an empty log, rejoin_ballots $ballots"

cluster_finish "$run" v
cluster_verify "$run" v "${IDS[@]}" "$VICTIM.2"
cluster_check 'a voter that lost its acceptor log rejoins by ballot, and the majority that kept theirs loses no acknowledged commit'
echo "real restart rejoin ok"
