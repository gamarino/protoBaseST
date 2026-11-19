#!/usr/bin/env bash
# Plan Task 27: real processes. Three members (n0, n1, n2, the voters), each a protost process of
# its own (_node.st over PBTcpTransport on 127.0.0.1, one shared cluster space), commit 30
# increments each, concurrently, every commit recording its token (_node.st's header). Then a
# fresh member, the learner v, which took no part in the workload, reads the space through the
# cluster after two barriers. The rules (_cluster.sh cluster_verify): every acknowledged token is
# present; the counter equals the size of 'tokens' and the acknowledged tokens plus the unknown
# tokens present. Every step waits on a marker file; no duration is asserted.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_cluster.sh
source "$HERE/_cluster.sh"

run="$(cluster_run commits)"; [[ -n "$run" ]] || fail "no run directory"
for id in n0 n1 n2; do cluster_worker "$run" "$id" 30 0 none; done
cluster_verifier "$run" v
cluster_peers "$run" "n0 n1 n2" n0 n1 n2 v
cluster_wait "$run" n0.done n1.done n2.done
cluster_finish "$run" v
cluster_verify "$run" v n0 n1 n2
echo "real commits ok"
