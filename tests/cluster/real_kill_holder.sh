#!/usr/bin/env bash
# Plan Task 28: real processes, a permission holder killed mid-round, restarted on its disk, then
# the whole cluster crashed and restarted on its disks. Every member is a protost process of its
# own (_node.st); three voters, n0, n1 and n2, commit 30 increments each, then 10 more after each
# kill (_node.st <after>), recording their tokens.
#
# Three stages, one per point of the commit round (_node_seams.st): 'built' (the root built and
# saved, nothing of it sent), 'replicate' (its replicate sent) and 'done' (the permission's done
# sent with #committed, the commit acknowledged to the round, not yet recorded by the worker).
# From its K-th acknowledgement of the stage (K1 from its start, then K2 and K3 counted from the
# previous kill), a worker arms the seam; the first round of a commit of a worker that reaches the
# point takes mark<s>, naming the token it carries, and holds; the test kills that holder with
# kill -9, checks that the token the mark names is the killed worker's one token in flight, and
# restarts the member on its disk: the same node id, acceptor log and port, the default startup
# grace (5 s at a 3000 ms lease; L17 refuses a shorter one over a log that is not empty), a new
# incarnation '<id>.<k>' (_cluster.sh) with tokens of its own, which commits 10 and takes part in
# the later stages without arming a seam: each stage kills a member never killed before, so n0,
# n1 and n2 are each killed and restarted once (rc4's node restart restarts every node in turn).
# The holder may be the owner of the term. A restart keeps its log, so it never rejoins: each
# restarted incarnation reports rejoin_ballots 0 (the control of real_restart_rejoin.sh's >= 1).
#
# Every worker runs with its persister off (NODE_PERSISTER=off: never started, so space.root is
# never written, however long the run; rc4's store outage): once every worker is done, the whole
# cluster is killed with kill -9, every commit unpersisted (space.root, read with no node, holds
# no 'shop'), held only in the acceptor logs. Then the three
# members restart on their disks (proto_db test_cluster_crash.py _verify, and the whole-cluster
# restart of test_cluster_persistence.py), as verifiers with the default persister, beside the
# learner v; each commits its barriers, then reads 'shop' and syncs it (_cluster.sh
# cluster_finish). The rules:
#   cluster_verify: every acknowledged token is present; the counter equals the size of 'tokens'
#     and the acknowledged tokens plus the unknown tokens present (each killed incarnation's one
#     token in flight counting as unknown);
#   cluster_verify_same: the four members read the same tokens and counter (a token whose outcome
#     is unknown is present on every node or on none);
#   cluster_verify_persisted: space.root, read with no node after sync:, holds exactly the tokens
#     and the counter read (every acknowledged one among them), applied whole, none twice;
#   per stage: the 'built' token is absent; every token the 'done' mark names is present (its
#     in-flight one is unknown and present: the unknown arm of the rule runs in every run); the
#     'replicate' token is present or absent, the same on every node.
#
# K1 (5..14), K2 and K3 (1..5) are drawn per run from a seed printed in a NOTE (KILL_SEED sets it,
# to replay a run). Every step waits on a marker file; no duration is asserted, the runner's
# timeout is the only deadline.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_cluster.sh
source "$HERE/_cluster.sh"

SEED="${KILL_SEED:-$RANDOM}"
[[ "$SEED" =~ ^[0-9]+$ ]] || fail "KILL_SEED must be a non-negative integer, not $SEED"
echo "NOTE: KILL_SEED=$SEED"
KINDS=(built replicate done)
KS=($((5 + SEED % 10)) $((1 + (SEED / 10) % 5)) $((1 + (SEED / 50) % 5)))
MARKS="built:${KS[0]},replicate:${KS[1]},done:${KS[2]}"
IDS=(n0 n1 n2)

run="$(cluster_run kill-holder)"; [[ -n "$run" ]] || fail "no run directory"
o="$run/out"
export NODE_PERSISTER=off
declare -A CUR=() INC=()
LOGS=()
for id in "${IDS[@]}"; do
    cluster_worker "$run" "$id" 30 10 "$MARKS"
    CUR[$id]=$id; INC[$id]=1; LOGS+=("$id")
done
cluster_verifier "$run" v
cluster_peers "$run" "${IDS[*]}" "${IDS[@]}" v

ABSENT=""; PRESENT=""; EITHER=""
for stage in 1 2 3; do
    kind="${KINDS[stage-1]}"
    cluster_wait "$run" "mark$stage"
    # The mark file is created, then written and synced: wait for its line.
    deadline=$((SECONDS + WAIT_SECONDS))
    until read -r victim mkind tokens < "$o/mark$stage" 2>/dev/null \
            && [[ -n "$victim" && "$mkind" == "$kind" && -n "${tokens:-}" ]]; do
        (( SECONDS > deadline )) && fail_run "$run" "mark$stage holds [$(cat "$o/mark$stage")], not '<log> $kind <token>...'"
        sleep 0.1
    done
    id="${victim%%.*}"
    [[ -n "${CUR[$id]:-}" && "${CUR[$id]}" == "$victim" ]] \
        || fail_run "$run" "mark$stage names $victim, not a running worker"
    cluster_kill "$run" "$victim" "killed$stage"
    # The token the mark names last is the killed worker's one token in flight.
    touch "$o/$victim.acked" "$o/$victim.unknown"
    inflight="$(comm -23 <(sort "$o/$victim.attempt") <(sort -u "$o/$victim.acked" "$o/$victim.unknown") | tr '\n' ' ')"
    last="${tokens##* }"
    [[ "$inflight" == "$last " ]] \
        || fail_run "$run" "$victim, killed at $kind, has [$inflight] in flight, the mark names $last"
    case "$kind" in
        built) ABSENT+=" $last" ;;
        replicate) EITHER+=" $last" ;;
        done) PRESENT+=" $tokens" ;;
    esac
    echo "NOTE: kill-holder: killed $victim at $kind (stage $stage, K=${KS[stage-1]}) with $last in flight after $(wc -l < "$o/$victim.acked") acknowledgements"
    # Restarted on its disk: a new incarnation of the same member.
    INC[$id]=$((INC[$id] + 1))
    CUR[$id]="$id.${INC[$id]}"
    LOGS+=("${CUR[$id]}")
    cluster_worker "$run" "$id" 10 10 "$MARKS" "${CUR[$id]}"
done

dones=()
for id in "${IDS[@]}"; do dones+=("${CUR[$id]}.done"); done
cluster_wait "$run" "${dones[@]}"

# Each member was killed once, at its own stage; each restart kept its log and never rejoined.
victims="$(for s in 1 2 3; do cut -d. -f1 < "$o/killed$s"; done | sort -u | tr '\n' ' ')"
[[ "$victims" == "n0 n1 n2 " ]] || fail_run "$run" "the stages killed [$(cat "$o"/killed* | tr '\n' ' ')], not each member once"
for id in "${IDS[@]}"; do
    ballots="$(sed -n 's/.* rejoin_ballots \([0-9][0-9]*\)$/\1/p' "$o/${CUR[$id]}.done")"
    [[ "$ballots" == 0 ]] || fail_run "$run" "${CUR[$id]}, restarted on its log, reports rejoin_ballots [$ballots]"
done
echo "NOTE: kill-holder: each of $victims killed once; ${CUR[n0]} ${CUR[n1]} ${CUR[n2]} report rejoin_ballots 0"

# The whole cluster crashes, every commit unpersisted.
cluster_crash "$run" "${CUR[n0]}" "${CUR[n1]}" "${CUR[n2]}" v
cluster_persisted "$run" crashed
before="$(cat "$o/crashed.result")"
[[ "$before" == none ]] || fail_run "$run" "space.root holds [$before] with every worker's persister off"

# Restarted on its disks, every member reads; then space.root is read with no node.
unset NODE_PERSISTER
readers=()
for id in "${IDS[@]}"; do cluster_verifier "$run" "$id" "$id.r"; readers+=("$id.r"); done
cluster_verifier "$run" v v.r
cluster_finish "$run" v.r "${readers[@]}"
cluster_verify "$run" v.r "${LOGS[@]}"
cluster_verify_same "$run" v.r "${readers[@]}"
cluster_persisted "$run" persisted
cluster_verify_persisted "$run" persisted v.r

read -r _ counter _ < "$o/v.r.result"
echo "NOTE: kill-holder: space.root at the crash: $before; after the restart: counter $counter"

v="$o/.verify"
for t in $ABSENT; do
    grep -qxF "$t" "$v/present" && fail_run "$run" "$t, killed at built, is present"
done
for t in $PRESENT; do
    grep -qxF "$t" "$v/present" || fail_run "$run" "$t, committed under the done sent before the kill, is missing"
done
for t in $EITHER; do
    if grep -qxF "$t" "$v/present"; then state=present; else state=absent; fi
    echo "NOTE: kill-holder: $t, killed at replicate, is $state on every node"
done
cluster_check 'a holder killed with kill -9 at built, replicate and done, each restarted on its disk, loses no acknowledged commit'
cluster_check 'the whole cluster killed with kill -9 before its commits were persisted restarts on its acceptor logs and loses no acknowledged commit'
cluster_check 'the whole cluster restarted on its disks reads the same tokens on every member, and space.root holds them after sync:'
echo "real kill holder ok"
