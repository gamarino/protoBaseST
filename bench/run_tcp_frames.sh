#!/usr/bin/env bash
# Runs the TCP frame-size bench (final review M4): bench/tcp_frames.st (the transport as it is,
# bodies read 1 KiB at a time) and bench/tcp_frames_whole_body.st (each body in one read, as in
# 0.3.0), alternately, ROUNDS times (default 3), one fresh process each, so a change of machine
# load spreads over both. Each process prints one line per frame size (see bench/_tcp_frame_bench.st)
# and a done line; a process that fails, or prints no done line, fails the run (exit 1).
# Environment: PROTOST (the binary), ROUNDS, FRAME_SIZES, FRAMES. Timings are indicative.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
ROUNDS="${ROUNDS:-3}"
PROTOST="${PROTOST:-}"
[[ -n "$PROTOST" && -x "$PROTOST" ]] || { echo "FAIL: PROTOST must name the protost binary"; exit 1; }
echo "protost: $("$PROTOST" --version 2>&1 | head -1); rounds $ROUNDS; $(date -u +%Y-%m-%dT%H:%MZ); load $(cut -d' ' -f1-3 /proc/loadavg)"
for round in $(seq 1 "$ROUNDS"); do
    for variant in tcp_frames tcp_frames_whole_body; do
        out="$(cd "$HERE" && STPATH="$REPO/src:$HERE" "$PROTOST" "$variant.st" 2>&1)"
        status=$?
        if [[ $status -ne 0 ]] || ! grep -q '^done: ' <<<"$out"; then
            echo "FAIL: round $round $variant (exit $status)"; echo "$out"; exit 1
        fi
        sed "s/^/round $round $variant: /" <<<"$out"
    done
done
