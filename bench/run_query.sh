#!/usr/bin/env bash
# Runs bench/query_workload.st (protoBaseST, on $PROTOST) and bench/py_query_workload.py (proto_db,
# the interop venv) on the same workloads, verifies the work and prints the timings (spec 7.3).
#
# Usage: bench/run_query.sh [ids...]          (default: every workload; today M2)
#
# Each implementation prints, per measured run, a WORK line (plan call IP10: id, impl, size, rows,
# queries, plan, checksum) and a TIME line (us). The runs interleave: RUNS rounds (default 5), each
# running proto_db, then protoBaseST, so a change of machine load spreads over both. Every run must
# end with 'query_workload ok', and every run of either implementation must report the same work
# (rows, queries, plan and checksum per id, size and plan) as proto_db's first run; anything else is
# a failure (exit 1) and the runner prints 'verified' only when all agree. Timings are reported as
# the minimum and the median over the runs, never asserted. The run outputs are written to
# QUERY_OUT (default bench/out/query, ignored by git), overwritten by each run; nothing is removed.
# QUERY_M2_SIZES (default "100 1000 10000 100000") chooses M2's sizes for both implementations.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
RUNS="${RUNS:-5}"
OUT="${QUERY_OUT:-$HERE/out/query}"
# shellcheck source=../tests/interop/env.sh
source "$REPO/tests/interop/env.sh" || exit 1
fail() { echo "FAIL: $*"; exit 1; }
[[ -x "$PROTOST" || -x "$(command -v "$PROTOST")" ]] || fail "PROTOST is not executable: $PROTOST"
mkdir -p "$OUT" || fail "cannot create $OUT"

load_before="$(cut -d' ' -f1-3 /proc/loadavg)"
for ((r = 1; r <= RUNS; r++)); do
    for impl in py st; do
        out="$OUT/$impl.$r"
        if [[ $impl == py ]]; then
            (cd "$HERE" && "$PY" py_query_workload.py "$@") > "$out" 2>&1
        else
            (cd "$HERE" && STPATH="$REPO/src" "$PROTOST" query_workload.st "$@") > "$out" 2>&1
        fi || { cat "$out"; fail "$impl run $r exited non-zero"; }
        [[ "$(tail -n 1 "$out")" == "query_workload ok" ]] || { cat "$out"; fail "$impl run $r did not finish"; }
        grep '^WORK ' "$out" | sed 's/ impl=[a-z]*//' > "$out.work"
        [[ -s "$out.work" ]] || fail "$impl run $r reported no work"
        cmp -s "$out.work" "$OUT/py.1.work" || {
            diff "$OUT/py.1.work" "$out.work"; fail "$impl run $r: the work differs from proto_db's"; }
    done
done
echo "verified: $RUNS runs of each implementation report the same work (rows, queries, plan, checksum)"
echo "RUNS=$RUNS interleaved; load average before: $load_before, after: $(cut -d' ' -f1-3 /proc/loadavg)"
echo "protost: $PROTOST; Python: $("$PY" --version 2>&1)"
grep -h '^WORK ' "$OUT/py.1" | sed 's/ impl=py//'
cat "$OUT"/py.[0-9]* "$OUT"/st.[0-9]* | grep '^TIME ' | awk '
    { for (i = 2; i <= NF; i++) { split($i, kv, "="); f[kv[1]] = kv[2] }
      key = f["id"] SUBSEP f["size"] SUBSEP f["plan"]; impl = f["impl"]
      n[key, impl]++; v[key, impl, n[key, impl]] = f["us"] + 0
      if (!(key in seen)) { seen[key] = 1; order[++k] = key } }
    function stat(key, impl,   c, i, j, t, a) {
        c = n[key, impl]; for (i = 1; i <= c; i++) a[i] = v[key, impl, i]
        for (i = 2; i <= c; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t }
        mn = a[1]; md = (c % 2) ? a[(c + 1) / 2] : (a[c / 2] + a[c / 2 + 1]) / 2 }
    END {
        print "| id | size | plan | proto_db us min / median | protoBaseST us min / median | ratio st/py (min) |"
        print "|---|---|---|---|---|---|"
        for (i = 1; i <= k; i++) { split(order[i], p, SUBSEP)
            stat(order[i], "py"); pm = mn; pd = md; stat(order[i], "st")
            printf "| %s | %s | %s | %d / %d | %d / %d | %.1fx |\n", p[1], p[2], p[3], pm, pd, mn, md, mn / pm }
    }'
