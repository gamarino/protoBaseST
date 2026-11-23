#!/usr/bin/env bash
# cluster_transport_tcp_slow_reader.st with a pool of one worker (PROTOST_WORKERS=1): the actors
# waiting in blocks (check 3) and the sender writing to a peer that never reads share the one
# worker, so a sender's turn that did not end while its peer was slow would keep them buried. The
# test has no deadline of its own: protost replaces this script's shell (exec), so the runner's
# timeout ends protost itself and reports a hang as the failure it is. The test exits 1 when a
# check fails.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTOST="${PROTOST:-protost}"
export STPATH="$HERE/../../src${STPATH:+:$STPATH}"
cd "$HERE" || exit 1
PROTOST_WORKERS=1 exec "$PROTOST" --print-last cluster_transport_tcp_slow_reader.st </dev/null
