#!/usr/bin/env bash
# cluster_transport_tcp_burial.st with a pool of one worker (PROTOST_WORKERS=1): every wait nested
# in a block then shares the one worker, so any transport turn that does not end keeps the actors
# under it buried. The transport of protoBaseST 0.2.0 to 0.3.0 (an endless accept loop and an
# endless read loop per connection) hung this run every time; every turn of the transport now
# ends, and the run must pass as it does with the default pool. The test has no deadline of its
# own: protost replaces this script's shell (exec), so the runner's timeout ends protost itself and
# reports a hang as the failure it is. The test exits 1 when a check fails.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTOST="${PROTOST:-protost}"
export STPATH="$HERE/../../src${STPATH:+:$STPATH}"
cd "$HERE" || exit 1
PROTOST_WORKERS=1 exec "$PROTOST" --print-last cluster_transport_tcp_burial.st </dev/null
