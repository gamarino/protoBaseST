#!/usr/bin/env bash
# cluster_transport_tcp_starvation.st with a pool of one worker (PROTOST_WORKERS=1): the transport's
# listener and readers, which send themselves their next turn while a connection is open, share the
# one worker with every other actor, and a worker that is not waiting runs every message an actor
# sends itself in the same turn (protoST STATUS D59). Other actors progress only because each
# transport turn blocks in I/O with a timeout, which makes the pool add a worker; a turn that
# re-sent itself without blocking would stop the program here, timers included. The test has no
# deadline of its own: protost replaces this script's shell (exec), so the runner's timeout ends
# protost itself and reports a hang as the failure it is. The test exits 1 when a check fails.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTOST="${PROTOST:-protost}"
export STPATH="$HERE/../../src${STPATH:+:$STPATH}"
cd "$HERE" || exit 1
PROTOST_WORKERS=1 exec "$PROTOST" --print-last cluster_transport_tcp_starvation.st </dev/null
