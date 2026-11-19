#!/usr/bin/env bash
# Measures the cells an atom and an index node cost (plan Tasks 11 and 12), with
# bench/atom_weight/probe.st on $PROTOST and this checkout's src (or $AW_SRC):
#
#   retained  cells kept live per object: n objects kept, then churn; the median of the live
#             counts (L=, PROTOCORE_HEAP_TRACE=1) of the GC cycles after it, minus kind none's
#             median, over n. The spread printed beside it is the run's own interquartile range
#             over n (the empty run's is printed in the header): the quartiles of two runs are
#             not subtracted position by position, which would mix two independent spreads
#   alloc     cells allocated per object: protoCore's cell allocator (proto::Cell::operator new)
#             counted under gdb between the probe's markers (count.py), last of three rounds, over n
#
#   For the kinds loaded and loadedcache (Task 12) the objects are the nodes of a stored tree
#   of n nodes, written first by a process of its own (the probe's mode write) into a new
#   directory AW_OUT/store.<n>.<pid>.<random> (left in place), then loaded by the measured process:
#   retained is per loaded node (loadedcache: with its atom cache entry), allocated is per
#   record load (loadedcache: a load the cache serves). oiddraw is one _PBOidPool next.
#
# Usage: bench/run_atom_weight.sh [kinds...]
#   kinds: tuple2 tupletrusted atomshell nodeshell nodeown nodeoid build oiddraw loaded
#   loadedcache (default: all; tupletrusted needs PBTuple _trustedOn:, Task 11). AW_KEEP_N (default 100000) objects
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
kinds=("${@:-tuple2 tupletrusted atomshell nodeshell nodeown nodeoid build oiddraw loaded loadedcache}")
kinds=(${kinds[*]})

# store <n>: writes a tree of n nodes for a loaded kind into a new directory (each keep and
# alloc run of a loaded kind gets its own) and exports AW_STORE and AW_PTR for the probe.
store() {
    local dir="$OUT/store.$1.$$.$RANDOM" out="$OUT/write.$1"
    (cd "$HERE/atom_weight" && STPATH="$SRC" AW_STORE="$dir" "$PROTOST" probe.st loaded "$1" write) > "$out" 2>&1 \
        || { tail -n 5 "$out"; fail "write $1 exited non-zero"; }
    grep -q "^WORK loaded $1 " "$out" && grep -q "^atom_weight ok" "$out" \
        || { tail -n 5 "$out"; fail "write $1 did not verify its work"; }
    export AW_STORE="$dir" AW_PTR="$(sed -n 's/^PTR //p' "$out")"
}

# keep <kind>: runs the probe in keep mode; prints "q1 median q3 cycles" of L= after CHURN.
keep() {
    local out="$OUT/keep.$1.$KEEP_N"
    if [[ "$1" == loaded* ]]; then store "$KEEP_N" || return 1; fi
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
    if [[ "$1" == loaded* ]]; then store "$ALLOC_N" || return 1; fi
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
awk -v n="$KEEP_N" -v b1="$b1" -v b3="$b3" -v c="$bc" \
    'BEGIN { printf "empty run: %d cycles, interquartile range %.2f cells per object\n", c, (b3-b1)/n }'
echo "| kind | retained per object (median) | interquartile range per object | allocated per object |"
echo "|---|---|---|---|"
for k in "${kinds[@]}"; do
    r="$(keep "$k")" || { echo "$r"; exit 1; }
    read -r q1 md q3 c <<< "$r"
    a="$(alloc "$k")" || { echo "$a"; exit 1; }
    awk -v k="$k" -v n="$KEEP_N" -v an="$ALLOC_N" -v q1="$q1" -v md="$md" -v q3="$q3" -v b2="$b2" -v a="$a" \
        'BEGIN { printf "| %s | %.2f | %.2f | %.1f |\n", k, (md-b2)/n, (q3-q1)/n, a/an }'
done
echo "load average after: $(cut -d' ' -f1-3 /proc/loadavg)"
