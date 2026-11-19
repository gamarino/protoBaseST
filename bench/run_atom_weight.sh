#!/usr/bin/env bash
# Measures the cells an atom and an index node cost (plan Tasks 11 and 12), with
# bench/atom_weight/probe.st on $PROTOST and this checkout's src (or $AW_SRC):
#
#   retained  cells kept live per object: n objects kept, then churn; the median of the live
#             counts (L=, PROTOCORE_HEAP_TRACE=1) of the GC cycles after it, minus kind none's,
#             over n (the quartiles are printed too)
#   alloc     cells allocated per object: protoCore's cell allocator (proto::Cell::operator new)
#             counted under gdb between the probe's markers (count.py), last of three rounds, over n
#
# Usage: bench/run_atom_weight.sh [kinds...]
#   kinds: tuple2 tupletrusted atomshell nodeshell nodeown nodeoid build (default: all;
#   tupletrusted needs PBTuple _trustedOn:, Task 11). AW_KEEP_N (default 100000) objects
#   per retained run, AW_ALLOC_N (default 200) per alloc run. Each run is a process of its own, run
#   one after another, with the heap budget PROTOCORE_HEAP_LIMIT_CELLS (AW_HEAP_LIMIT_CELLS, default
#   32000000, about 2 GB). The budget also fixes the collector's policy: without one, protoCore's
#   adaptive heap may raise its target after the first cycles and run none after the churn, so a
#   retained run would have no figure. The churn makes AW_CHURN (default 10000000) short-lived
#   Arrays, several heaps' worth. Every run must print the probe's WORK line and 'atom_weight ok'
#   (the probe checks its objects); anything else is a failure (exit 1). The raw outputs go to
#   AW_OUT (default bench/out/atom_weight, ignored by git), overwritten by each run. Cell counts
#   are deterministic up to the GC's timing (retained) and are reported, never asserted.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SRC="${AW_SRC:-$REPO/src}"
OUT="${AW_OUT:-$HERE/out/atom_weight}"
KEEP_N="${AW_KEEP_N:-100000}"
ALLOC_N="${AW_ALLOC_N:-200}"
CHURN="${AW_CHURN:-10000000}"
export PROTOCORE_HEAP_LIMIT_CELLS="${AW_HEAP_LIMIT_CELLS:-32000000}"
fail() { echo "FAIL: $*"; exit 1; }
[[ -n "${PROTOST:-}" && -x "$PROTOST" ]] || fail "PROTOST is not an executable protost: ${PROTOST:-unset}"
command -v gdb > /dev/null || fail "gdb is needed for the allocation counts"
[[ -f "$SRC/protobase.st" ]] || fail "not a protoBaseST source tree: $SRC"
mkdir -p "$OUT" || fail "cannot create $OUT"
kinds=("${@:-tuple2 tupletrusted atomshell nodeshell nodeown nodeoid build}")
kinds=(${kinds[*]})

# keep <kind>: runs the probe in keep mode; prints "q1 median q3 cycles" of L= after CHURN.
keep() {
    local out="$OUT/keep.$1.$KEEP_N"
    (cd "$HERE/atom_weight" && STPATH="$SRC" PROTOCORE_HEAP_TRACE=1 "$PROTOST" probe.st "$1" "$KEEP_N" keep "$CHURN") > "$out" 2>&1 \
        || { tail -n 5 "$out"; fail "keep $1 exited non-zero"; }
    grep -q "^WORK $1 $KEEP_N " "$out" && grep -q "^atom_weight ok" "$out" \
        || { tail -n 5 "$out"; fail "keep $1 did not verify its work"; }
    awk '/^CHURN/{c=1;next} c&&/L=/{match($0,/L=[0-9]+/); a[m++]=substr($0,RSTART+2,RLENGTH-2)+0}
         END{if (m < 5) exit 1; asort(a); printf "%d %d %d %d\n", a[int(m/4)+1], a[int(m/2)+1], a[int(3*m/4)+1], m}' "$out" \
        || fail "keep $1: fewer than 5 GC cycles after the churn"
}

# alloc <kind>: prints the cells allocated in the last round.
alloc() {
    local out="$OUT/alloc.$1.$ALLOC_N"
    (cd "$HERE/atom_weight" && STPATH="$SRC" gdb -q -batch -x count.py --args "$PROTOST" probe.st "$1" "$ALLOC_N" alloc) > "$out" 2>&1 \
        || { tail -n 5 "$out"; fail "alloc $1: gdb exited non-zero"; }
    grep -q "^WORK $1 $ALLOC_N " "$out" && grep -q "^atom_weight ok" "$out" \
        || { tail -n 5 "$out"; fail "alloc $1 did not verify its work"; }
    local n
    n="$(grep -c '^AWCOUNT' "$out")"
    [[ "$n" == 3 ]] || fail "alloc $1: $n marker pairs counted, 3 expected"
    grep '^AWCOUNT' "$out" | tail -n 1 | sed 's/.*cells=//'
}

echo "atom_weight: protost $PROTOST; src $SRC"
echo "src commit: $(git -C "$SRC" rev-parse --short HEAD 2>/dev/null) $(git -C "$SRC" status --porcelain -- . 2>/dev/null | grep -q . && echo modified || echo clean)"
echo "load average: $(cut -d' ' -f1-3 /proc/loadavg); keep n=$KEEP_N, alloc n=$ALLOC_N; churn $CHURN; heap limit $PROTOCORE_HEAP_LIMIT_CELLS cells"
r="$(keep none)" || { echo "$r"; exit 1; }
read -r b1 b2 b3 bc <<< "$r"
echo "| kind | retained per object (q1 / median / q3) | allocated per object |"
echo "|---|---|---|"
for k in "${kinds[@]}"; do
    r="$(keep "$k")" || { echo "$r"; exit 1; }
    read -r q1 md q3 c <<< "$r"
    a="$(alloc "$k")" || { echo "$a"; exit 1; }
    awk -v k="$k" -v n="$KEEP_N" -v an="$ALLOC_N" -v q1="$q1" -v md="$md" -v q3="$q3" -v b1="$b1" -v b2="$b2" -v b3="$b3" -v a="$a" \
        'BEGIN { printf "| %s | %.2f / %.2f / %.2f | %.1f |\n", k, (q1-b1)/n, (md-b2)/n, (q3-b3)/n, a/an }'
done
echo "load average after: $(cut -d' ' -f1-3 /proc/loadavg)"
