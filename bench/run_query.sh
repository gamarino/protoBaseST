#!/usr/bin/env bash
# Runs bench/query_workload.st (protoBaseST, on $PROTOST) and bench/py_query_workload.py (proto_db,
# the interop venv) on the same workloads, verifies the work and prints the timings (spec 7.3).
#
# Usage: bench/run_query.sh [ids...]          (default: every workload: M1 M2)
#
# A workload is split into units, <id>:<size>:<plan> (M1: 600:idx0, 600:idx1, 600:idx3; M2: <n>:build
# and <n>:fold for each size of QUERY_M2_SIZES, default "100 1000 10000 100000"), and every unit runs
# in a process of its own, so one size's live set never weighs on another's and the peak memory of
# each process is its own. Each implementation prints, per unit, a WORK line (plan call IP10: id,
# impl, size, rows, queries, plan, checksum) and a TIME line (us). The runs interleave: RUNS rounds
# (default 5), each running every unit with proto_db, then protoBaseST, so a change of machine load
# spreads over both. Every run must end with 'query_workload ok', and every run of either
# implementation must report the same work (rows, queries, plan and checksum) as proto_db's first
# run of the unit; the build and fold units of one M2 size must report the same rows, queries and
# checksum; anything else is a failure (exit 1), and the runner prints 'verified' only when all
# agree. Timings are reported as the minimum and the median over the runs, never asserted, with
# each implementation's peak resident set (the largest over its runs of the unit, /usr/bin/time).
#
# Memory: every protost process gets an explicit heap budget, PROTOCORE_HEAP_LIMIT_CELLS (protoCore's
# hard limit in 64-byte cells; QUERY_HEAP_LIMIT_CELLS, default 80000000, about 5 GB), so a unit that
# needs more fails in its own process instead of growing until the machine's OOM killer stops it.
# The run outputs go to QUERY_OUT (default bench/out/query, ignored by git): one directory per unit,
# overwritten by each run; M1's spaces go to new directories under QUERY_OUT/data. Nothing is removed.
# QUERY_M1_COMMITS (default 200) sets M1's transactions.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
RUNS="${RUNS:-5}"
OUT="${QUERY_OUT:-$HERE/out/query}"
SIZES="${QUERY_M2_SIZES:-100 1000 10000 100000}"
export PROTOCORE_HEAP_LIMIT_CELLS="${QUERY_HEAP_LIMIT_CELLS:-80000000}"
# shellcheck source=../tests/interop/env.sh
source "$REPO/tests/interop/env.sh" || exit 1
fail() { echo "FAIL: $*"; exit 1; }
[[ -x "$PROTOST" || -x "$(command -v "$PROTOST")" ]] || fail "PROTOST is not executable: $PROTOST"
[[ -x /usr/bin/time ]] || fail "/usr/bin/time is needed for the peak resident set"
mkdir -p "$OUT/data" || fail "cannot create $OUT"

units=()
for id in "${@:-M1 M2}"; do
    for one in $id; do
        case "$one" in
            M1) units+=(M1:600:idx0 M1:600:idx1 M1:600:idx3) ;;
            M2) for n in $SIZES; do units+=("M2:$n:build" "M2:$n:fold"); done ;;
            *) fail "unknown workload $one" ;;
        esac
    done
done

load_before="$(cut -d' ' -f1-3 /proc/loadavg)"
for ((r = 1; r <= RUNS; r++)); do
    for unit in "${units[@]}"; do
        dir="$OUT/${unit//:/_}"
        mkdir -p "$dir" || fail "cannot create $dir"
        for impl in py st; do
            out="$dir/$impl.$r"
            data="$OUT/data/${unit//:/_}-$impl-$r-$$-$(date +%s%N)"
            if [[ $impl == py ]]; then
                (cd "$HERE" && QUERY_DATA="$data" /usr/bin/time -f '%M' -o "$out.rss" \
                    "$PY" py_query_workload.py "$unit") > "$out" 2>&1
            else
                (cd "$HERE" && QUERY_DATA="$data" STPATH="$REPO/src" /usr/bin/time -f '%M' -o "$out.rss" \
                    "$PROTOST" query_workload.st "$unit") > "$out" 2>&1
            fi || { tail -n 5 "$out"; echo "peak RSS: $(tail -n 1 "$out.rss" 2>/dev/null) KB"; fail "$impl $unit run $r exited non-zero"; }
            [[ "$(tail -n 1 "$out")" == "query_workload ok" ]] || { cat "$out"; fail "$impl $unit run $r did not finish"; }
            grep '^WORK ' "$out" | sed 's/ impl=[a-z]*//' > "$out.work"
            [[ -s "$out.work" ]] || fail "$impl $unit run $r reported no work"
            cmp -s "$out.work" "$dir/py.1.work" || {
                diff "$dir/py.1.work" "$out.work"; fail "$impl $unit run $r: the work differs from proto_db's"; }
        done
    done
done
for n in $SIZES; do
    b="$OUT/M2_${n}_build/py.1.work"; f="$OUT/M2_${n}_fold/py.1.work"
    [[ -f "$b" && -f "$f" ]] || continue
    [[ "$(sed 's/ plan=[a-z]*//' "$b")" == "$(sed 's/ plan=[a-z]*//' "$f")" ]] || fail "M2 $n: build and fold report different work"
done
echo "verified: $RUNS runs of each implementation report the same work (rows, queries, plan, checksum)"
echo "RUNS=$RUNS interleaved, one process per unit; load average before: $load_before, after: $(cut -d' ' -f1-3 /proc/loadavg)"
echo "protost: $PROTOST (PROTOCORE_HEAP_LIMIT_CELLS=$PROTOCORE_HEAP_LIMIT_CELLS); Python: $("$PY" --version 2>&1)"
for unit in "${units[@]}"; do cat "$OUT/${unit//:/_}/py.1.work"; done
echo "| id | size | plan | proto_db us min / median | protoBaseST us min / median | ratio st/py (min) | peak RSS MB py / st |"
echo "|---|---|---|---|---|---|---|"
for unit in "${units[@]}"; do
    dir="$OUT/${unit//:/_}"
    files=(); rss_py=0; rss_st=0
    for ((r = 1; r <= RUNS; r++)); do
        files+=("$dir/py.$r" "$dir/st.$r")
        k=$(tail -n 1 "$dir/py.$r.rss"); ((k > rss_py)) && rss_py=$k
        k=$(tail -n 1 "$dir/st.$r.rss"); ((k > rss_st)) && rss_st=$k
    done
    cat "${files[@]}" | grep '^TIME ' | awk -v rp="$rss_py" -v rs="$rss_st" '
        { for (i = 2; i <= NF; i++) { split($i, kv, "="); f[kv[1]] = kv[2] }
          id = f["id"]; size = f["size"]; plan = f["plan"]; impl = f["impl"]
          n[impl]++; v[impl, n[impl]] = f["us"] + 0 }
        function stat(impl,   c, i, j, t, a) {
            c = n[impl]; for (i = 1; i <= c; i++) a[i] = v[impl, i]
            for (i = 2; i <= c; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t }
            mn = a[1]; md = (c % 2) ? a[(c + 1) / 2] : (a[c / 2] + a[c / 2 + 1]) / 2 }
        END {
            stat("py"); pm = mn; pd = md; stat("st")
            printf "| %s | %s | %s | %d / %d | %d / %d | %.1fx | %d / %d |\n", id, size, plan, pm, pd, mn, md, mn / pm, rp / 1024, rs / 1024
        }'
done
