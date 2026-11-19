#!/usr/bin/env bash
# Runs bench/query_workload.st (protoBaseST, on $PROTOST) and bench/py_query_workload.py (proto_db,
# the interop venv) on the same workloads, verifies the work and prints the timings (spec 7.3).
#
# Usage: bench/run_query.sh [ids...]          (default: M1 M2 M3; the planner workloads P1 P2 P3 and the query workloads Q1-Q4 by name)
#
# A workload is split into units, <id>:<size>:<plan> (M1: 600:idx0, 600:idx1, 600:idx3; M2: <n>:build
# and <n>:fold for each size of QUERY_M2_SIZES, default "100 1000 10000 100000"), and every unit runs
# M3: 600:idx0, 600:idx1, 600:idx3 standalone, and 600:idx0-c3, 600:idx1-c3, 600:idx3-c3 in a
# three-member cluster; P1: <conjuncts>:idx<k> for 1, 8 and 32 conjuncts and 0, 2 and 8 indexes; P2:
# 2000:<point>-index and 2000:<point>-scan for each point; P3: 2000:intersect and 2000:filter; see
# bench/_query_bench.st PlannerBench; Q1: <n>:index and <n>:scan for each size of QUERY_Q1_SIZES, default
# "100 1000 10000" (10^5 is not run by default: protoST's indexed build of it took over 5 CPU minutes
# and 5 GB before its first query); Q2, Q3, Q4: 2000:<point>-index and 2000:<point>-scan, see QueryUnits) and every unit runs
# in a process of its own, so one size's live set never weighs on another's and the peak memory of
# each process is its own. Each implementation prints, per unit, a WORK line (plan call IP10: id,
# impl, size, rows, queries, plan, checksum) and a TIME line (us). The runs interleave: RUNS rounds
# (default 5), each running every unit with proto_db, then protoBaseST, so a change of machine load
# spreads over both. Every run must end with 'query_workload ok', and every run of either
# implementation must report the same work (rows, queries, plan and checksum) as proto_db's first
# run of the unit; the build and fold units of one M2 size must report the same rows, queries and
# checksum, and so must the two forced plans of a P2 point and P3's two plans; P units also carry
# model= (the plan the planner chooses) in their work, and their MODEL lines (the model costs of the
# plans compared, in thousandths, rounded) must equal proto_db's first run's too, and are printed;
# anything else is a failure (exit 1), and the runner prints 'verified' only when all
# agree. Timings are reported as the minimum and the median over the runs, never asserted, with
# each implementation's peak resident set (the largest over its runs of the unit, /usr/bin/time).
#
# Memory: every protost process gets an explicit heap budget, PROTOCORE_HEAP_LIMIT_CELLS (protoCore's
# hard limit in 64-byte cells; QUERY_HEAP_LIMIT_CELLS, default 80000000, about 5 GB), so a unit that
# needs more fails in its own process instead of growing until the machine's OOM killer stops it.
# The run outputs go to QUERY_OUT (default bench/out/query, ignored by git): one directory per unit,
# overwritten by each run; M1's spaces go to new directories under QUERY_OUT/data. Nothing is removed.
# QUERY_M1_COMMITS (default 200) sets M1's transactions, QUERY_M3_COMMITS (default 120, the cluster
# workload's total) M3's.
#
# M3's cluster units (plan Task 4b) run bench/run_cluster.sh once per round (RUNS=1, MODES=3, the
# profile m3-<plan>, KEEP_TMP=1, CLUSTER_TMPDIR a new directory under QUERY_OUT/data, so nothing
# is removed): three protost member processes, each with the heap budget
# QUERY_CLUSTER_HEAP_LIMIT_CELLS (default 32000000, about 2 GB, so three fit beside the desktop).
# There is no proto_db cluster run: the cluster's work is verified against proto_db's standalone
# unit of the same plan (rows, commits and checksum passed as CLUSTER_M3_EXPECTED, checked by the
# cluster's verifier and again here), which run_cluster.sh's own checks (commits counted by every
# member and by the coordinators) complete. The time is the wall time from the first member's start
# to the last one's end; the peak resident set the largest member's (VmHWM after its commits).
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
for id in "${@:-M1 M2 M3}"; do
    for one in $id; do
        case "$one" in
            M1) units+=(M1:600:idx0 M1:600:idx1 M1:600:idx3) ;;
            M2) for n in $SIZES; do units+=("M2:$n:build" "M2:$n:fold"); done ;;
            M3) units+=(M3:600:idx0 M3:600:idx1 M3:600:idx3 M3:600:idx0-c3 M3:600:idx1-c3 M3:600:idx3-c3) ;;
            P1) for c in 1 8 32; do for k in idx0 idx2 idx8; do units+=("P1:$c:$k"); done; done ;;
            P2) for p in r0001 r0010 r0100 r0500 r0900 r0990 r1000 ne-few ne-many; do
                    units+=("P2:2000:$p-index" "P2:2000:$p-scan"); done ;;
            P3) units+=(P3:2000:intersect P3:2000:filter) ;;
            Q1) for n in ${QUERY_Q1_SIZES:-100 1000 10000}; do units+=("Q1:$n:index" "Q1:$n:scan"); done ;;
            Q2) for p in in1 in10 in100 r0001 r0010 r0100 r0500; do units+=("Q2:2000:$p-index" "Q2:2000:$p-scan"); done ;;
            Q3) for p in and or2 ormix not; do units+=("Q3:2000:$p-index" "Q3:2000:$p-scan"); done ;;
            Q4) for p in all sel unsel; do units+=("Q4:2000:$p-index" "Q4:2000:$p-scan"); done ;;
            *) fail "unknown workload $one" ;;
        esac
    done
done

# value <file> <key>: the value of key=value in a line of key=value pairs.
value() { tr ' ' '\n' < "$1" | sed -n "s/^$2=//p"; }

# cluster_unit <unit> <round>: one run of an M3 cluster unit, written as a protoBaseST run of it
# ($dir/st.<round>, .work, .rss), its work checked against proto_db's standalone unit of the plan.
cluster_unit() {
    local unit="$1" r="$2" plan dir ref expected tmp run t0 t1 rss f out att com rows queries checksum
    plan="${unit##*:}"; plan="${plan%-c3}"
    dir="$OUT/${unit//:/_}"; out="$dir/st.$r"
    ref="$OUT/M3_600_$plan/py.1.work"
    [[ -f "$ref" ]] || fail "$unit needs proto_db's standalone M3 $plan run first"
    expected="$(value "$ref" rows):$(value "$ref" queries):$(value "$ref" checksum)"
    tmp="$OUT/data/${unit//:/_}-$r-$$-$(date +%s%N)"
    mkdir -p "$tmp" || fail "cannot create $tmp"
    (cd "$HERE" && CLUSTER_M3_EXPECTED="$expected" PROTOCORE_HEAP_LIMIT_CELLS="$CLUSTER_HEAP" KEEP_TMP=1 \
        CLUSTER_TMPDIR="$tmp" RUNS=1 PROFILES="m3-$plan" MODES=3 CLUSTER_SCALE=1 PROTOST="$PROTOST" \
        bash run_cluster.sh) > "$out.cluster" 2>&1 || { tail -n 30 "$out.cluster"; fail "st $unit run $r: run_cluster.sh failed"; }
    run="$(ls -d "$tmp"/pbst-cluster.* 2>/dev/null | head -n 1)"
    [[ -n "$run" && -f "$run/out/verify.result" ]] || fail "st $unit run $r: no verify.result under $tmp"
    [[ "$(value "$run/out/verify.result" checksum)" == "$expected" ]] || fail "st $unit run $r: the cluster read $(value "$run/out/verify.result" checksum), proto_db $expected"
    t0=""; t1=""; rss=0; att=0; com=0
    for f in "$run"/out/n*.result; do
        local a b k
        a="$(value "$f" t0)"; b="$(value "$f" t1)"; k="$(value "$f" rss_kb)"
        att=$((att + $(value "$f" attempts))); com=$((com + $(value "$f" commits)))
        [[ -z "$t0" || "$a" -lt "$t0" ]] && t0="$a"
        [[ -z "$t1" || "$b" -gt "$t1" ]] && t1="$b"
        ((k > rss)) && rss=$k
    done
    IFS=: read -r rows queries checksum <<< "$(value "$run/out/verify.result" checksum)"
    { echo "WORK id=M3 impl=st size=600 rows=$rows queries=$queries plan=$plan checksum=$checksum"
      echo "TIME id=M3 impl=st size=600 plan=$plan-c3 us=$((t1 - t0))"
      echo "RETRIES id=M3 plan=$plan-c3 retries=$((att - com))"
      echo "query_workload ok"; } > "$out"
    echo "$rss" > "$out.rss"
    grep '^WORK ' "$out" | sed 's/ impl=[a-z]*//' > "$out.work"
    cmp -s "$out.work" "$ref" || { diff "$ref" "$out.work"; fail "st $unit run $r: the work differs from proto_db's"; }
}
CLUSTER_HEAP="${QUERY_CLUSTER_HEAP_LIMIT_CELLS:-32000000}"

load_before="$(cut -d' ' -f1-3 /proc/loadavg)"
for ((r = 1; r <= RUNS; r++)); do
    for unit in "${units[@]}"; do
        dir="$OUT/${unit//:/_}"
        mkdir -p "$dir" || fail "cannot create $dir"
        if [[ "$unit" == *-c3 ]]; then cluster_unit "$unit" "$r"; continue; fi
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
            grep '^MODEL ' "$out" | sed 's/ impl=[a-z]*//' > "$out.model"
            cmp -s "$out.model" "$dir/py.1.model" || {
                diff "$dir/py.1.model" "$out.model"; fail "$impl $unit run $r: the model costs differ from proto_db's"; }
        done
    done
done
for n in $SIZES; do
    b="$OUT/M2_${n}_build/py.1.work"; f="$OUT/M2_${n}_fold/py.1.work"
    [[ -f "$b" && -f "$f" ]] || continue
    [[ "$(sed 's/ plan=[a-z]*//' "$b")" == "$(sed 's/ plan=[a-z]*//' "$f")" ]] || fail "M2 $n: build and fold report different work"
done
# P2 and P3: the two forced plans of a point (and P3's two plans) must answer the same rows and checksum.
for unit in "${units[@]}"; do
    case "$unit" in P2:*-index) other="${unit%-index}-scan" ;; P3:*:intersect) other="${unit%intersect}filter" ;; *) continue ;; esac
    a="$OUT/${unit//:/_}/py.1.work"; b="$OUT/${other//:/_}/py.1.work"
    [[ -f "$a" && -f "$b" ]] || continue
    [[ "$(sed 's/ plan=[a-z0-9-]*//' "$a")" == "$(sed 's/ plan=[a-z0-9-]*//' "$b")" ]] || fail "$unit and $other report different work"
done
echo "verified: $RUNS runs of each implementation report the same work (rows, queries, plan, checksum)"
echo "RUNS=$RUNS interleaved, one process per unit; load average before: $load_before, after: $(cut -d' ' -f1-3 /proc/loadavg)"
echo "protost: $PROTOST (PROTOCORE_HEAP_LIMIT_CELLS=$PROTOCORE_HEAP_LIMIT_CELLS; cluster members $CLUSTER_HEAP); Python: $("$PY" --version 2>&1)"
commit="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo '?')"
[[ -z "$(git -C "$REPO" status --porcelain -- src bench 2>/dev/null)" ]] || commit="$commit (src or bench modified or untracked)"
echo "$(date -u +%Y-%m-%dT%H:%MZ); protoBaseST $commit; $("$PROTOST" --version 2>&1 | head -n 1)"
echo "Machine: $(lscpu | sed -n 's/^\(Model name\|Nombre del modelo\): *//p' | head -n 1), $(nproc) CPUs, Linux $(uname -r)"
for unit in "${units[@]}"; do [[ "$unit" == *-c3 ]] || cat "$OUT/${unit//:/_}/py.1.work"; done
for unit in "${units[@]}"; do [[ "$unit" == P[23]:* ]] && grep -h '^MODEL ' "$OUT/${unit//:/_}/py.1" "$OUT/${unit//:/_}/st.1"; done
for unit in "${units[@]}"; do
    [[ "$unit" == *-c3 ]] || continue
    echo "$unit retries per run (block runs beyond one per commit): $(for ((r = 1; r <= RUNS; r++)); do sed -n 's/^RETRIES .*retries=//p' "$OUT/${unit//:/_}/st.$r"; done | tr '\n' ' ')"
done
echo "| id | size | plan | proto_db us min / median | protoBaseST us min / median | ratio st/py (min) | peak RSS MB py / st |"
echo "|---|---|---|---|---|---|---|"
for unit in "${units[@]}"; do
    dir="$OUT/${unit//:/_}"
    files=(); rss_py=0; rss_st=0
    for ((r = 1; r <= RUNS; r++)); do
        [[ -f "$dir/py.$r" ]] && files+=("$dir/py.$r")
        files+=("$dir/st.$r")
        [[ -f "$dir/py.$r.rss" ]] && { k=$(tail -n 1 "$dir/py.$r.rss"); ((k > rss_py)) && rss_py=$k; }
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
            if (n["py"] == 0) {
                stat("st")
                printf "| %s | %s | %s | - | %d / %d | - | - / %d (largest member) |\n", id, size, plan, mn, md, rs / 1024
                exit
            }
            stat("py"); pm = mn; pd = md; stat("st")
            printf "| %s | %s | %s | %d / %d | %d / %d | %.1fx | %d / %d |\n", id, size, plan, pm, pd, mn, md, mn / pm, rp / 1024, rs / 1024
        }'
done
