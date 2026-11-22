#!/usr/bin/env bash
# Runs bench/query_workload.st (protoBaseST, on $PROTOST) and bench/py_query_workload.py (proto_db,
# the interop venv) on the same workloads, verifies the work and prints the timings (spec 7.3).
#
# Usage: bench/run_query.sh [ids...]          (default: M1 M2 M3; the planner workloads P1 P2 P3, the query workloads Q1-Q5
#                                              and the vector workloads VB0 to VB5 by name)
#
# A workload is split into units, <id>:<size>:<plan> (M1: 600:idx0, 600:idx1, 600:idx3; M2: <n>:build
# and <n>:fold for each size of QUERY_M2_SIZES, default "100 1000 10000 100000"), and every unit runs
# M3: 600:idx0, 600:idx1, 600:idx3 standalone, and 600:idx0-c3, 600:idx1-c3, 600:idx3-c3 in a
# three-member cluster; P1: <conjuncts>:idx<k> for 1, 8 and 32 conjuncts and 0, 2 and 8 indexes; P2:
# 2000:<point>-index and 2000:<point>-scan for each point; P3: 2000:intersect and 2000:filter; see
# bench/_query_bench.st PlannerBench; Q1: <n>:index and <n>:scan for each size of QUERY_Q1_SIZES, default
# "100 1000 10000" (10^5 is not run by default: protoST's indexed build of it took over 5 CPU minutes
# and 5 GB before its first query); Q2, Q3, Q4: 2000:<point>-index and 2000:<point>-scan, see QueryUnits; Q5: <n>:page-rank, <n>:page-mat, <n>:page-skip,
# <n>:count-index and <n>:count-scan for each size of QUERY_Q5_SIZES, default "2000 10000") and every unit runs
# in a process of its own, so one size's live set never weighs on another's and the peak memory of
# each process is its own. Each implementation prints, per unit, a WORK line (plan call IP10: id,
# impl, size, rows, queries, plan, checksum) and a TIME line (us). The runs interleave: RUNS rounds
# (default 5), each running every unit with proto_db, then protoBaseST, so a change of machine load
# spreads over both. Every run must end with 'query_workload ok', and every run of either
# implementation must report the same work (rows, queries, plan and checksum) as proto_db's first
# run of the unit; the build and fold units of one M2 size must report the same rows, queries and
# checksum, and so must the two forced plans of a P2 point, P3's two plans, the three page plans of a Q5 size and its two counts; P units also carry
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
# VB0, the vector math kernel (vectors phase task V1, Addendum V 5.5, an input to ruling VQ2): units
# VB0:<n>:d<dim>-<op> for n = QUERY_VB0_SIZE (default 10000), each dim of QUERY_VB0_DIMS (default
# "8 32 128") and op products, naive, fsum, ip, l2, cosine, and ip-scorer, l2-scorer, cosine-scorer
# (the same scores through scorerFor:query:, task V8 fix round 1; bench/vector_workload.st states them),
# run by bench/vector_workload.st and bench/py_vector_workload.py instead of the query workloads.
# Their data, proto_db's clustered benchmark set, is written once per dim and run of this script by
# bench/py_vector_data.py to a new MessagePack file under QUERY_OUT/data, which both sides read
# (QUERY_VECTOR_DATA). proto_db runs in its reference mode (numpy and hnswlib blocked: every score is
# its pure-Python function, every IVF training its pure-Python k-means), the only mode whose work
# protoBaseST reproduces to the bit (deviation DV3: with numpy, proto_db's centroids are numpy's), so
# the only one VB0 can verify. VB0's checksums are CRC-32s of the results' bytes, so
# 'verified' means every sum, score and product equals proto_db's to the bit.
#
# VB3 and VB5, vector index maintenance (vectors phase task V5, Addendum V 5.5;
# bench/vector_workload.st states them, bench/_vector_bench.st their data and checksum): VB3:<n>:d8-
# <plan> for n of QUERY_VB3_SIZES (default "600 5000") and plan none, exact, ivf, each committing
# QUERY_VB3_COMMITS (default 200) appends; VB5:600:d8-exact and VB5:600:d8-ivf, QUERY_VB5_COMMITS
# (default 120) blind writes merged onto the vector-indexed current, and VB5:600:d8-exact-c3 and
# VB5:600:d8-ivf-c3, the same 120 in a three-member cluster (profiles vb5-exact and vb5-ivf of
# bench/cluster_workload.st, run as M3's cluster units below). Their data file holds n + the
# commits vectors of dim 8. VB3's checksum covers the elements, the counts and every IVF centroid;
# VB5's the content and the counts, not the centroids, which in a cluster depend on the commit
# order. Both refuse a run whose IVF index never retrained. VB5:600:d8-ivf-c3 runs with a lease of
# QUERY_VB5_IVF_LEASE_MS (default 90000 ms, a write permission believed for 30 s; the members' startup
# grace, untimed, grows with it to 150 s), not proto_db's
# default 2000 ms: a retrain is k-means in the round's build, under the permission, and protoBaseST's
# retrain over ~650 vectors of dim 8 takes about 1.6 to 1.9 s on protoST 0.16.0 (its `build:` about
# 3 s on 0.15.0 and 8 s on 0.14.1; one fresh process each, indicative), beyond the 667 ms a default permission is
# believed, so with the default lease a retraining merge cannot commit: its build outlasts the
# permission at every attempt (measured with retrain_growth 1.05: with the default lease no member finished its 40 commits
# in 1700 s, against 15 s for the exact unit; docs/deviations.md, "Vectors").
#
# VB1 and VB2, vector search (vectors phase task V6; bench/vector_workload.st states them): VB1:<n>:d<dim>-
# <metric> for n of QUERY_VB1_SIZES (default "1000 10000"), dim 8 and 32, metric cosine and l2, exact
# kNN with k 10, timed as '-first' (the first query) and '-knn' (the data file's 10 queries);
# VB2:10000:d32-ivf, an ivf_flat index of nlist 100 timed as '-build', then '-nprobe1', '-nprobe4' and
# '-nprobe100' (the 10 queries each), each with a RECALL line against the exact answer, printed at
# the end. A unit prints a TIME line per timing and the table a row per timing. VB1's answers are
# verified in both of proto_db's modes; VB2's in its reference mode (answers and centroids), its
# numpy mode reported by recall and verified by its COUNTS lines only (DV3).
#
# VB4, filtered kNN (vectors phase task V7; bench/vector_workload.st states it): VB4:10000:d8-s01,
# -s10 and -s50, near(k = 10) AND a condition that 1, 10 and 50 percent of the 10^4 records satisfy,
# over an exact l2 index, timed as '-filtered' (the planner's VectorSearch with the condition as
# its where, ruling R27) and '-post' (the obvious post-filter of the 10 nearest), the data file's 10
# queries each; the rows each answers are the WORK lines' rows, printed with the work. Verified in
# proto_db's reference mode (an exact answer does not depend on numpy, so its numpy mode adds
# nothing here and is not run).
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
            Q5) for n in ${QUERY_Q5_SIZES:-2000 10000}; do
                    for p in page-rank page-mat page-skip count-index count-scan; do units+=("Q5:$n:$p"); done; done ;;
            VB0) for d in ${QUERY_VB0_DIMS:-8 32 128}; do
                    for p in products naive fsum ip l2 cosine ip-scorer l2-scorer cosine-scorer; do units+=("VB0:${QUERY_VB0_SIZE:-10000}:d$d-$p"); done; done ;;
            VB3) for n in ${QUERY_VB3_SIZES:-600 5000}; do
                    for p in none exact ivf; do units+=("VB3:$n:d8-$p"); done; done ;;
            VB5) units+=(VB5:600:d8-exact VB5:600:d8-ivf VB5:600:d8-exact-c3 VB5:600:d8-ivf-c3) ;;
            VB1) for n in ${QUERY_VB1_SIZES:-1000 10000}; do
                    for d in 8 32; do for m in cosine l2; do units+=("VB1:$n:d$d-$m"); done; done; done ;;
            VB2) units+=(VB2:10000:d32-ivf) ;;
            VB4) for p in s01 s10 s50; do units+=("VB4:10000:d8-$p"); done ;;
            *) fail "unknown workload $one" ;;
        esac
    done
done

# value <file> <key>: the value of key=value in a line of key=value pairs.
value() { tr ' ' '\n' < "$1" | sed -n "s/^$2=//p"; }

# cluster_unit <unit> <round>: one run of an M3 or VB5 cluster unit, written as a protoBaseST run of
# it ($dir/st.<round>, .work, .rss), its work checked against proto_db's standalone unit of the plan.
cluster_unit() {
    local unit="$1" r="$2" id plan dir ref expected tmp run t0 t1 rss f out att com rows queries checksum profile
    id="${unit%%:*}"; plan="${unit##*:}"; plan="${plan%-c3}"
    dir="$OUT/${unit//:/_}"; out="$dir/st.$r"
    ref="$OUT/${id}_600_$plan/py.1.work"
    [[ -f "$ref" ]] || fail "$unit needs proto_db's standalone $id $plan run first"
    expected="$(value "$ref" rows):$(value "$ref" queries):$(value "$ref" checksum)"
    tmp="$OUT/data/${unit//:/_}-$r-$$-$(date +%s%N)"
    mkdir -p "$tmp" || fail "cannot create $tmp"
    lease=()
    case "$id" in
        M3) profile="m3-$plan" ;;
        VB5) profile="vb5-${plan#d8-}"; [[ "$plan" == *-ivf ]] && lease=(CLUSTER_LEASE_MS="$VB5_IVF_LEASE_MS") ;;
        *) fail "no cluster profile for $unit" ;;
    esac
    (cd "$HERE" && env "${lease[@]}" CLUSTER_M3_EXPECTED="$expected" CLUSTER_VB5_EXPECTED="$expected" \
        QUERY_VECTOR_DATA="$( [[ "$id" == VB5 ]] && vector_data "$unit")" \
        PROTOCORE_HEAP_LIMIT_CELLS="$CLUSTER_HEAP" KEEP_TMP=1 \
        CLUSTER_TMPDIR="$tmp" RUNS=1 PROFILES="$profile" MODES=3 CLUSTER_SCALE=1 PROTOST="$PROTOST" \
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
    { echo "WORK id=$id impl=st size=600 rows=$rows queries=$queries plan=$plan checksum=$checksum"
      echo "TIME id=$id impl=st size=600 plan=$plan-c3 us=$((t1 - t0))"
      echo "RETRIES id=$id plan=$plan-c3 retries=$((att - com))"
      echo "query_workload ok"; } > "$out"
    echo "$rss" > "$out.rss"
    grep '^WORK ' "$out" | sed 's/ impl=[a-z]*//' > "$out.work"
    cmp -s "$out.work" "$ref" || { diff "$ref" "$out.work"; fail "st $unit run $r: the work differs from proto_db's"; }
}
CLUSTER_HEAP="${QUERY_CLUSTER_HEAP_LIMIT_CELLS:-32000000}"
VB5_IVF_LEASE_MS="${QUERY_VB5_IVF_LEASE_MS:-90000}"
# proto_db's default mode, numpy importable (Addendum V 5.5, review M3 of task V5): with
# tests/interop/.venv-numpy (tests/interop/setup_venv_numpy.sh, the pinned proto_db), every
# standalone VB1, VB2, VB3 and VB5 unit also runs py_vector_workload.py with QUERY_PY_NUMPY=1, impl pyn, its
# times a column of the table. Its centroids are numpy's, not comparable with the pure path's
# (deviation DV3), so its verification is the COUNTS line (contents, members, invalid occurrences,
# trained size, centroid count: equal to the reference mode's) and the WORK line where no centroid
# is checksummed (every unit but VB3's ivf). Without the venv the mode is skipped and says so.
NUMPY_VENV="$REPO/tests/interop/.venv-numpy"
numpy_mode=0
if [[ -x "$NUMPY_VENV/bin/python" && -d "$NUMPY_VENV/protobase/proto_db" ]]; then
    pinned="$(sed -n 's/^TAG_COMMIT="\(.*\)"$/\1/p' "$REPO/tests/interop/setup_venv_numpy.sh")"
    held="$(cat "$NUMPY_VENV/protobase/.commit" 2>/dev/null || true)"
    [[ -n "$pinned" && "$held" == "$pinned"* ]] || fail "tests/interop/.venv-numpy holds proto_db ${held:-of unknown commit}, not $pinned (run tests/interop/setup_venv_numpy.sh)"
    numpy_mode=1
fi
PYN=(env PYTHONPATH="$NUMPY_VENV/protobase" QUERY_PY_NUMPY=1 "$NUMPY_VENV/bin/python")

# vector_data <unit>: the data file of a VB unit (one per count and dim, written once per run of this
# script): n vectors for VB0, n + the commits for VB3 and VB5 (the vectors their commits add).
VECTOR_DATA_DIR="$OUT/data/vectors-$$-$(date +%s%N)"
vector_data() {
    local unit="$1" n plan dim file
    n="$(cut -d: -f2 <<< "$unit")"; plan="$(cut -d: -f3 <<< "$unit")"; dim="${plan%%-*}"; dim="${dim#d}"
    case "$unit" in
        VB3:*) n=$((n + ${QUERY_VB3_COMMITS:-200})) ;;
        VB5:*) n=$((n + ${QUERY_VB5_COMMITS:-120})) ;;
    esac
    file="$VECTOR_DATA_DIR/n$n-d$dim.msgpack"
    [[ -f "$file" ]] || "$PY" "$HERE/py_vector_data.py" "$n" "$dim" "$file" || fail "py_vector_data.py $n $dim failed"
    echo "$file"
}
for unit in "${units[@]}"; do [[ "$unit" == VB* ]] && { vector_data "$unit" > /dev/null || fail "cannot write the data of $unit"; }; done

load_before="$(cut -d' ' -f1-3 /proc/loadavg)"
for ((r = 1; r <= RUNS; r++)); do
    for unit in "${units[@]}"; do
        dir="$OUT/${unit//:/_}"
        mkdir -p "$dir" || fail "cannot create $dir"
        if [[ "$unit" == *-c3 ]]; then cluster_unit "$unit" "$r"; continue; fi
        impls=(py st)
        [[ $numpy_mode == 1 && "$unit" == VB[1235]:* ]] && impls=(py pyn st)
        for impl in "${impls[@]}"; do
            out="$dir/$impl.$r"
            data="$OUT/data/${unit//:/_}-$impl-$r-$$-$(date +%s%N)"
            if [[ "$unit" == VB* ]]; then
                vdata="$(vector_data "$unit")"
                if [[ $impl == py ]]; then
                    (cd "$HERE" && QUERY_VECTOR_DATA="$vdata" QUERY_DATA="$data" /usr/bin/time -f '%M' -o "$out.rss" \
                        "$PY" py_vector_workload.py "$unit") > "$out" 2>&1
                elif [[ $impl == pyn ]]; then
                    (cd "$HERE" && QUERY_VECTOR_DATA="$vdata" QUERY_DATA="$data" /usr/bin/time -f '%M' -o "$out.rss" \
                        "${PYN[@]}" py_vector_workload.py "$unit") > "$out" 2>&1
                else
                    (cd "$HERE" && QUERY_VECTOR_DATA="$vdata" QUERY_DATA="$data" STPATH="$REPO/src" /usr/bin/time -f '%M' -o "$out.rss" \
                        "$PROTOST" vector_workload.st "$unit") > "$out" 2>&1
                fi
            elif [[ $impl == py ]]; then
                (cd "$HERE" && QUERY_DATA="$data" /usr/bin/time -f '%M' -o "$out.rss" \
                    "$PY" py_query_workload.py "$unit") > "$out" 2>&1
            else
                (cd "$HERE" && QUERY_DATA="$data" STPATH="$REPO/src" /usr/bin/time -f '%M' -o "$out.rss" \
                    "$PROTOST" query_workload.st "$unit") > "$out" 2>&1
            fi || { tail -n 5 "$out"; echo "peak RSS: $(tail -n 1 "$out.rss" 2>/dev/null) KB"; fail "$impl $unit run $r exited non-zero"; }
            [[ "$(tail -n 1 "$out")" == "query_workload ok" ]] || { cat "$out"; fail "$impl $unit run $r did not finish"; }
            grep '^WORK ' "$out" | sed 's/ impl=[a-z]*//' > "$out.work"
            [[ -s "$out.work" ]] || fail "$impl $unit run $r reported no work"
            if [[ $impl == py* && "$unit" == VB[235]:* ]]; then
                grep '^COUNTS ' "$out" | sed 's/ impl=[a-z]*//' > "$out.counts"
                [[ -s "$out.counts" ]] || fail "$impl $unit run $r reported no counts"
                cmp -s "$out.counts" "$dir/py.1.counts" || {
                    diff "$dir/py.1.counts" "$out.counts"; fail "$impl $unit run $r: the counts differ from proto_db's reference mode"; }
                # DV3: numpy's centroids are its own; VB3's ivf WORK checksum covers them.
                [[ $impl == pyn && ( "$unit" == VB3:*-ivf || "$unit" == VB2:* ) ]] && continue
            fi
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
# Q5: the three ways to page a size report the same rows, pages and checksum, and so do its two counts.
for unit in "${units[@]}"; do
    case "$unit" in Q5:*:page-rank) others=("${unit%rank}mat" "${unit%rank}skip") ;; Q5:*:count-index) others=("${unit%index}scan") ;; *) continue ;; esac
    for other in "${others[@]}"; do
        a="$OUT/${unit//:/_}/py.1.work"; b="$OUT/${other//:/_}/py.1.work"
        [[ -f "$a" && -f "$b" ]] || continue
        [[ "$(sed 's/ plan=[a-z0-9-]*//; s/ model=.*//' "$a")" == "$(sed 's/ plan=[a-z0-9-]*//; s/ model=.*//' "$b")" ]] || fail "$unit and $other report different work"
    done
done
echo "verified: $RUNS runs of each implementation report the same work (rows, queries, plan, checksum)"
echo "RUNS=$RUNS interleaved, one process per unit; load average before: $load_before, after: $(cut -d' ' -f1-3 /proc/loadavg)"
echo "protost: $PROTOST (PROTOCORE_HEAP_LIMIT_CELLS=$PROTOCORE_HEAP_LIMIT_CELLS; cluster members $CLUSTER_HEAP); Python: $("$PY" --version 2>&1)"
[[ " ${units[*]}" == *"VB5:600:d8-ivf-c3"* ]] && echo "VB5 ivf cluster unit: lease $VB5_IVF_LEASE_MS ms (proto_db's default 2000 ms for every other cluster unit)"
if [[ " ${units[*]}" == *" VB"* ]]; then
    echo "proto_db mode (vector units): reference, numpy: blocked, hnswlib: blocked; libc $("$PY" -c 'import platform; print(*platform.libc_ver())')"
    if [[ $numpy_mode == 1 ]]; then
        echo "proto_db default mode (VB1, VB2, VB3 and VB5, column numpy): numpy $("${PYN[@]}" -c 'import numpy; print(numpy.__version__)'), $("$NUMPY_VENV/bin/python" --version 2>&1); its centroids are numpy's (DV3), not comparable: counts verified, and the work where no centroid is checksummed"
    else
        echo "SKIP: proto_db's default mode (numpy): tests/interop/.venv-numpy is absent"
    fi
fi
commit="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo '?')"
[[ -z "$(git -C "$REPO" status --porcelain -- src bench 2>/dev/null)" ]] || commit="$commit (src or bench modified or untracked)"
echo "$(date -u +%Y-%m-%dT%H:%MZ); protoBaseST $commit; $("$PROTOST" --version 2>&1 | head -n 1)"
echo "Machine: $(lscpu | sed -n 's/^\(Model name\|Nombre del modelo\): *//p' | head -n 1), $(nproc) CPUs, Linux $(uname -r)"
for unit in "${units[@]}"; do [[ "$unit" == *-c3 ]] || cat "$OUT/${unit//:/_}/py.1.work"; done
for unit in "${units[@]}"; do [[ "$unit" == P[23]:* ]] && grep -h '^MODEL ' "$OUT/${unit//:/_}/py.1" "$OUT/${unit//:/_}/st.1"; done
for unit in "${units[@]}"; do
    [[ "$unit" == VB2:* ]] || continue
    for impl in py pyn st; do [[ -f "$OUT/${unit//:/_}/$impl.1" ]] && grep -h '^RECALL ' "$OUT/${unit//:/_}/$impl.1"; done
done
for unit in "${units[@]}"; do
    [[ "$unit" == *-c3 ]] || continue
    echo "$unit retries per run (block runs beyond one per commit): $(for ((r = 1; r <= RUNS; r++)); do sed -n 's/^RETRIES .*retries=//p' "$OUT/${unit//:/_}/st.$r"; done | tr '\n' ' ')"
done
echo "| id | size | plan | proto_db us min / median | protoBaseST us min / median | ratio st/py (min) | peak RSS MB py / st | proto_db numpy us min / median |"
echo "|---|---|---|---|---|---|---|---|"
for unit in "${units[@]}"; do
    dir="$OUT/${unit//:/_}"
    files=(); rss_py=0; rss_st=0
    for ((r = 1; r <= RUNS; r++)); do
        [[ -f "$dir/py.$r" ]] && files+=("$dir/py.$r")
        [[ -f "$dir/pyn.$r" ]] && files+=("$dir/pyn.$r")
        files+=("$dir/st.$r")
        [[ -f "$dir/py.$r.rss" ]] && { k=$(tail -n 1 "$dir/py.$r.rss"); ((k > rss_py)) && rss_py=$k; }
        k=$(tail -n 1 "$dir/st.$r.rss"); ((k > rss_st)) && rss_st=$k
    done
    cat "${files[@]}" | grep '^TIME ' | awk -v rp="$rss_py" -v rs="$rss_st" '
        { for (i = 2; i <= NF; i++) { split($i, kv, "="); f[kv[1]] = kv[2] }
          id = f["id"]; size = f["size"]; plan = f["plan"]; impl = f["impl"]
          if (!(plan in seen)) { seen[plan] = 1; plans[++np] = plan }
          n[plan, impl]++; v[plan, impl, n[plan, impl]] = f["us"] + 0 }
        function stat(plan, impl,   c, i, j, t, a) {
            c = n[plan, impl]; for (i = 1; i <= c; i++) a[i] = v[plan, impl, i]
            for (i = 2; i <= c; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t }
            mn = a[1]; md = (c % 2) ? a[(c + 1) / 2] : (a[c / 2] + a[c / 2 + 1]) / 2 }
        END {
            for (p = 1; p <= np; p++) {
                plan = plans[p]
                if (n[plan, "py"] == 0) {
                    stat(plan, "st")
                    printf "| %s | %s | %s | - | %d / %d | - | - / %d (largest member) | - |\n", id, size, plan, mn, md, rs / 1024
                    continue
                }
                numpy = "-"
                if (n[plan, "pyn"] > 0) { stat(plan, "pyn"); numpy = sprintf("%d / %d", mn, md) }
                stat(plan, "py"); pm = mn; pd = md; stat(plan, "st")
                printf "| %s | %s | %s | %d / %d | %d / %d | %.1fx | %d / %d | %s |\n", id, size, plan, pm, pd, mn, md, mn / pm, rp / 1024, rs / 1024, numpy
            }
        }'
done
