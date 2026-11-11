#!/usr/bin/env bash
# Week-0 check (Spec 9, plan call C6): protoST's BinaryFile tryLock and ProtoBase's
# FileStorage root lock exclude each other on space.lock.
#
# A Python peer takes fcntl.flock(LOCK_EX | LOCK_NB) on space.lock and holds it until its stdin
# reaches end of file. The shell feeds the peer's stdin from a FIFO it keeps open and reads the
# peer's stdout from a second FIFO. The order of events comes from the "locked" line and from
# closing the stdin FIFO, never from a sleep.
#
# Exit codes: 0 pass, 77 skip, anything else fail.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTOST="${PROTOST:-protost}"
PY="${PY:-python3}"

if ! command -v "$PY" >/dev/null 2>&1; then
    echo "SKIP: no python3 for the lock peer"
    exit 77
fi
if ! command -v "$PROTOST" >/dev/null 2>&1; then
    echo "FAIL: protost not found: $PROTOST"
    exit 1
fi

WORK="$(mktemp -d)"
PEER_PID=""
cleanup() {
    exec 3>&- 2>/dev/null
    exec 4<&- 2>/dev/null
    [[ -n "$PEER_PID" ]] && kill "$PEER_PID" 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT

mkfifo "$WORK/in" "$WORK/out"
LOCK="$WORK/space.lock"

cat > "$WORK/held.st" <<ST
| f r |
f := BinaryFile open: '$LOCK' options: #(#read #write #create).
r := f tryLock.
f close.
r ifTrue: [Error signal: 'tryLock answered true while the Python peer holds the lock'].
'held ok' displayNl
ST
cat > "$WORK/free.st" <<ST
| f r |
f := BinaryFile open: '$LOCK' options: #(#read #write #create).
r := f tryLock.
f close.
r ifFalse: [Error signal: 'tryLock answered false after the Python peer exited'].
'free ok' displayNl
ST

# Start the peer; its redirections rendezvous with the two exec lines below.
"$PY" "$HERE/_lock_peer.py" "$WORK" < "$WORK/in" > "$WORK/out" &
PEER_PID=$!
exec 3> "$WORK/in"
exec 4< "$WORK/out"

if ! read -r -t 30 line <&4 || [[ "$line" != "locked" ]]; then
    echo "FAIL: the peer did not report 'locked' (got: ${line:-nothing})"
    exit 1
fi

out="$(cd "$WORK" && timeout 60 "$PROTOST" --print-last held.st </dev/null 2>&1)"
rc=$?
if [[ $rc -ne 0 || "$(printf '%s\n' "$out" | tail -n 1)" != "held ok" ]]; then
    echo "FAIL: while the peer held the lock (rc=$rc): $out"
    exit 1
fi

# Release: close the FIFO so the peer's stdin reaches end of file, then wait for it to exit.
exec 3>&-
wait "$PEER_PID"
peer_rc=$?
PEER_PID=""
if [[ $peer_rc -ne 0 ]]; then
    echo "FAIL: the peer exited with $peer_rc"
    exit 1
fi

out="$(cd "$WORK" && timeout 60 "$PROTOST" --print-last free.st </dev/null 2>&1)"
rc=$?
if [[ $rc -ne 0 || "$(printf '%s\n' "$out" | tail -n 1)" != "free ok" ]]; then
    echo "FAIL: after the peer exited (rc=$rc): $out"
    exit 1
fi
echo "lock excludes: held false, free true"
exit 0
