#!/usr/bin/env bash
# Design spec 10.7, plan call C13: a Python helper (hold_lock.py) takes the space's lock with
# ProtoBase's own storage and, while it holds it, runs protoST's one-shot commit
# (_st_commit_once.st) with a lockTimeout of 50 ms: the commit must end in PBTimeoutError, an
# outcome that holds for any duration because the lock is not released until protoST's process
# has exited. Then the helper releases the lock and runs the script again with 30000 ms: it
# must print 'committed'. Exit 77 without the interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

out="$("$PY" "$HERE/hold_lock.py" "$PROTOST" "$TMP/space")" || fail "hold_lock.py exited $?: $out"
[[ "$out" == *"lock timeout ok" ]] || fail "hold_lock.py printed: $out"
echo "lock timeout ok"
