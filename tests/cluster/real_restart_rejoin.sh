#!/usr/bin/env bash
# Plan Task 28: real processes, a voter crashed with its acceptor log lost, restarted: it rejoins
# by ballot (proto_db test_cluster_persistence.py test_losing_a_minority_loses_nothing: a disk
# lost before anything was persisted, wipe = crash + rmtree). Every member is a protost process of
# its own (_node.st); three voters, n0, n1 and n2, commit 40 increments each, recording their
# tokens, with their persisters off (NODE_PERSISTER=off: space.root is never written, the store
# outage of rc4), so the commits live only in the acceptor logs.
#
# Once the victim (a voter drawn from the seed, the owner of the term possibly) has K
# acknowledgements, the test kills it with kill -9 (killed1: its one token in flight counts as
# unknown). Its acceptor log, <space>/cluster/<id>.roots, is renamed aside (the disk lost, as
# Task 25 stands in for a wiped disk; nothing is deleted). The two others go on: a majority of the
# voters, whose own logs are all that holds the commits. The member then restarts, the same node
# id and port on an empty log, as a new incarnation '<id>.2' with tokens of its own: a voter
# without its log rejoins before it grants or acknowledges anything, through the ballot round
# (cluster/rejoin.st: two witnesses, both other voters, promise its ballot durably); this
# process's stats count it (rejoin_ballots >= 1, written to its .done; a restart that keeps its
# log reports 0, real_kill_holder.sh), and its new log is not empty. It then commits 20
# increments. Once every worker is done, space.root still holds no 'shop' (read with no node); the
# learner v, whose persister runs, joins and verifies (cluster_verify: every acknowledged token
# present; the counter equals the size of 'tokens' and the acknowledged tokens plus the unknown
# tokens present), then syncs, and space.root, read with no node, holds what v read
# (cluster_verify_persisted).
#
# K (5..14) and the victim are drawn per run from a seed printed in a NOTE (KILL_SEED sets it, to
# replay a run, or to choose the victim: n<(KILL_SEED / 10) % 3>). Every step waits on a marker
# file; no duration is asserted, the runner's timeout is the only deadline.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_cluster.sh
source "$HERE/_cluster.sh"

SEED="${KILL_SEED:-$RANDOM}"
[[ "$SEED" =~ ^[0-9]+$ ]] || fail "KILL_SEED must be a non-negative integer, not $SEED"
K=$((5 + SEED % 10))
VICTIM="n$(( (SEED / 10) % 3 ))"
echo "NOTE: KILL_SEED=$SEED (victim $VICTIM, K=$K)"
IDS=(n0 n1 n2)

run="$(cluster_run restart-rejoin)"; [[ -n "$run" ]] || fail "no run directory"
o="$run/out"
export NODE_PERSISTER=off
for id in "${IDS[@]}"; do cluster_worker "$run" "$id" 40 0 none; done
cluster_verifier "$run" v
cluster_peers "$run" "${IDS[*]}" "${IDS[@]}" v

# The victim's K-th acknowledgement, then kill -9.
deadline=$((SECONDS + WAIT_SECONDS))
until [[ -e "$o/$VICTIM.acked" ]] && (( $(wc -l < "$o/$VICTIM.acked") >= K )); do
    _check_live "$run"
    (( SECONDS > deadline )) && fail_run "$run" "$VICTIM has no $K acknowledgements within $WAIT_SECONDS s"
    sleep 0.1
done
cluster_kill "$run" "$VICTIM" killed1
[[ -e "$o/$VICTIM.done" ]] && fail_run "$run" "$VICTIM finished its commits before it was killed"
echo "NOTE: restart-rejoin: killed $VICTIM with kill -9 after $(wc -l < "$o/$VICTIM.acked") acknowledgements"

# Its disk lost: the acceptor log renamed aside, then the member restarts on an empty log.
log="$run/space/cluster/$VICTIM.roots"
[[ -e "$log" ]] || fail_run "$run" "no acceptor log $log"
mv "$log" "$log.lost" || fail_run "$run" "cannot rename $log"
[[ ! -e "$log" ]] || fail_run "$run" "$log is still there"
cluster_worker "$run" "$VICTIM" 20 0 none "$VICTIM.2"

dones=()
for id in "${IDS[@]}"; do [[ "$id" == "$VICTIM" ]] || dones+=("$id.done"); done
cluster_wait "$run" "${dones[@]}" "$VICTIM.2.done"
ballots="$(sed -n 's/.* rejoin_ballots \([0-9][0-9]*\)$/\1/p' "$o/$VICTIM.2.done")"
[[ -n "$ballots" ]] || fail_run "$run" "$VICTIM.2.done: $(cat "$o/$VICTIM.2.done")"
(( ballots >= 1 )) || fail_run "$run" "$VICTIM rejoined with rejoin_ballots $ballots: not by ballot"
[[ -s "$log" ]] || fail_run "$run" "$VICTIM rejoined without writing its new acceptor log"
echo "NOTE: restart-rejoin: $VICTIM.2 rejoined on an empty log, rejoin_ballots $ballots, new log $(wc -c < "$log") bytes"

# Nothing persisted: the majority's acceptor logs alone held the commits.
cluster_persisted "$run" before
[[ "$(cat "$o/before.result")" == none ]] \
    || fail_run "$run" "space.root holds [$(cat "$o/before.result")] with every worker's persister off"
echo "NOTE: restart-rejoin: space.root holds no 'shop' once the workers are done"

unset NODE_PERSISTER
cluster_finish "$run" v
cluster_verify "$run" v "${IDS[@]}" "$VICTIM.2"
cluster_persisted "$run" persisted
cluster_verify_persisted "$run" persisted v
cluster_check 'a voter that lost its acceptor log rejoins by ballot, and the majority that kept theirs loses no acknowledged commit'
echo "real restart rejoin ok"
