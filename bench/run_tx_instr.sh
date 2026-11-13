#!/usr/bin/env bash
# Instructions per committed transaction (perf stat -e instructions:u, user space, every thread
# of the process, the GC's included) of tx_instr.st on protost and py_tx_instr.py on ProtoBase,
# for the profiles tiny, small-record and batch-100. Each is the difference between a run of N2
# and a run of N1 transactions divided by N2 - N1, so the start, the setup and the exit cancel.
# Instruction counts hardly move with the machine's load, unlike times, so a change of the code
# can be measured on a busy machine; the task-clock per transaction is printed beside them.
#
# Usage: bench/run_tx_instr.sh /path/to/protost [src]     (N1, N2 default 10 and 40)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
BIN="${1:?usage: $0 /path/to/protost [src]}"
SRC="${2:-$REPO/src}"
N1="${N1:-10}"; N2="${N2:-40}"
TX_TMPDIR="${TX_TMPDIR:-/var/tmp}"
# shellcheck source=../tests/interop/env.sh
source "$REPO/tests/interop/env.sh" || exit 1
command -v perf > /dev/null || { echo "FAIL: perf is not installed"; exit 1; }

# count <impl> <profile> <n>: "instructions task-clock-ms"
count() {
    local dir out
    dir="$(mktemp -d -p "$TX_TMPDIR" pbst-instr.XXXXXX)" || exit 1
    if [[ "$1" == py ]]; then
        out="$(cd "$HERE" && TX_DIR="$dir" PROFILE="$2" N="$3" LC_ALL=C perf stat -x, -e instructions:u,task-clock "$PY" py_tx_instr.py 2>&1 >/dev/null)"
    else
        out="$(cd "$HERE" && TX_DIR="$dir" PROFILE="$2" N="$3" STPATH="$SRC" LC_ALL=C perf stat -x, -e instructions:u,task-clock "$BIN" tx_instr.st 2>&1 >/dev/null)"
    fi
    local rc=$?
    rm -rf "$dir"
    [[ $rc -eq 0 ]] || { echo "$out" >&2; echo "FAIL: $1 $2 N=$3 exited $rc" >&2; exit 1; }
    awk -F, '$3 ~ /instructions/ { i = $1 } $3 ~ /task-clock/ { t = $1 } END { print i, t }' <<< "$out"
}

echo "load average before: $(cut -d' ' -f1-3 /proc/loadavg); N1=$N1 N2=$N2; protost: $BIN @ $SRC"
echo "| profile | ProtoBase instructions/tx | protoBaseST instructions/tx | ratio | ProtoBase CPU ms/tx | protoBaseST CPU ms/tx |"
echo "|---|---|---|---|---|---|"
for profile in tiny small-record batch-100; do
    read -r pi1 pt1 <<< "$(count py "$profile" "$N1")"; read -r pi2 pt2 <<< "$(count py "$profile" "$N2")"
    read -r si1 st1 <<< "$(count st "$profile" "$N1")"; read -r si2 st2 <<< "$(count st "$profile" "$N2")"
    awk -v p="$profile" -v d="$((N2 - N1))" -v a="$pi1" -v b="$pi2" -v c="$si1" -v e="$si2" -v f="$pt1" -v g="$pt2" -v h="$st1" -v k="$st2" 'BEGIN {
        py = (b - a) / d; st = (e - c) / d
        printf "| %s | %.2f M | %.2f M | %.1fx | %.2f | %.2f |\n", p, py / 1e6, st / 1e6, st / py, (g - f) / d, (k - h) / d }'
done
echo "load average after: $(cut -d' ' -f1-3 /proc/loadavg)"
