#!/usr/bin/env bash
# Runs bench/cluster_workload.st and prints, per profile and per mode, the committed transactions
# per second of protoBaseST in standalone mode and in cluster mode with 1 and 3 members, each
# member a protost process of its own on 127.0.0.1, every process over one shared directory; and
# the split of a cluster commit's cost (design spec 7.2): the root-independent save before the
# permission, the build under it, and the replication.
#
# Usage: PROTOST=/path/to/protost bench/run_cluster.sh
#
# Environment: RUNS (default 5) rounds, interleaved: each round runs every profile in every mode
# once, so a change of machine load spreads over all of them. PROFILES (default 'tiny conc-hot'),
# MODES (default 'standalone 1 3'; a number is a member count), CLUSTER_SCALE (default 1:
# 120 transactions per run in all, split over the members). Every run gets a new directory under
# CLUSTER_TMPDIR (default /var/tmp: /tmp is often tmpfs, where fsync costs nothing), removed when
# the run ends unless KEEP_TMP=1. The protost binary is used as it is: nothing is built here.
#
# Self-reporting (nothing is trusted that was not counted): every process writes the transactions
# it committed, counted as each run: returns (never the number it was asked for), and a verifier reads the space after the run (cluster: n0, after a read barrier,
# through the cluster; standalone: a new space over the closed directory) and writes the
# transactions it found and a checksum it compares with the expected one. A run is refused (exit 1,
# with the log of the process at fault) when a process fails or exits early, when the commits of
# the members do not add up to the run's total, when the verifier's count differs from that sum, or
# when, in a cluster, the commits the coordinators counted (critical_commits) differ from it.
# Timings are reported, never asserted.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
RUNS="${RUNS:-5}"
PROFILES="${PROFILES:-tiny conc-hot}"
MODES="${MODES:-standalone 1 3}"
CLUSTER_SCALE="${CLUSTER_SCALE:-1}"
CLUSTER_TMPDIR="${CLUSTER_TMPDIR:-/var/tmp}"
WAIT_SECONDS="${WAIT_SECONDS:-400}"
PROTOST="${PROTOST:-}"
fail() { echo "FAIL: $*"; exit 1; }
[[ -n "$PROTOST" && -x "$PROTOST" ]] || fail "PROTOST must name the protost binary"
PROTOST="$(cd "$(dirname "$PROTOST")" && pwd)/$(basename "$PROTOST")"
[[ -d "$CLUSTER_TMPDIR" && -w "$CLUSTER_TMPDIR" ]] || fail "CLUSTER_TMPDIR is not a writable directory: $CLUSTER_TMPDIR"
CLUSTER_TMPDIR="$(cd "$CLUSTER_TMPDIR" && pwd)"
TOTAL=$((120 * CLUSTER_SCALE))

PIDS=()
DIRS=()
RESULTS="$(mktemp -d -p "$CLUSTER_TMPDIR" pbst-cluster-results.XXXXXX)" || fail "cannot create a directory in $CLUSTER_TMPDIR"
cleanup() {
    local pid
    for pid in "${PIDS[@]}"; do kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; done
    if [[ "${KEEP_TMP:-0}" != 1 ]]; then
        local d
        for d in "${DIRS[@]}" "$RESULTS"; do rm -rf "$d"; done
    fi
}
trap cleanup EXIT
trap 'exit 1' INT TERM

# run_fail <dir> <text>: the logs of the run, then the failure.
run_fail() {
    local f
    for f in "$1"/out/*.log "$1"/out/*.error; do
        [[ -f "$f" ]] && { echo "--- $f"; tail -n 20 "$f"; }
    done
    fail "$2 (run directory $1)"
}

# await <dir> <file>...: waits until every file exists in <dir>/out; a process of the run that
# exited meanwhile, or WAIT_SECONDS, fails the run.
await() {
    local dir="$1"; shift
    local deadline=$((SECONDS + WAIT_SECONDS)) f missing pid dead
    while :; do
        dead=""
        for pid in "${RUN_PIDS[@]}"; do kill -0 "$pid" 2>/dev/null || dead="$pid"; done
        missing=""
        for f in "$@"; do [[ -e "$dir/out/$f" ]] || missing="$f"; done
        [[ -z "$missing" ]] && return 0
        # Checked before the files: a process that wrote its file and then exited is not a failure.
        [[ -n "$dead" ]] && { wait "$dead"; run_fail "$dir" "a process exited (status $?) before $missing"; }
        (( SECONDS > deadline )) && run_fail "$dir" "no $missing within $WAIT_SECONDS s"
        sleep 0.005
    done
}

# value <file> <key>: the value of key=value in a result file.
value() { tr ' ' '\n' < "$1" | sed -n "s/^$2=//p"; }

# run_one <round> <profile> <mode>: one run; appends a line to $RESULTS/lines.
run_one() {
    local round="$1" profile="$2" mode="$3" dir ids id i n peers pid commits count critical
    dir="$(mktemp -d -p "$CLUSTER_TMPDIR" pbst-cluster.XXXXXX)" || fail "cannot create a directory in $CLUSTER_TMPDIR"
    DIRS+=("$dir")
    mkdir "$dir/out"
    RUN_PIDS=()
    if [[ "$mode" == standalone ]]; then
        ids=(s)
        (cd "$HERE" && STPATH="$REPO/src" CLUSTER_SCALE="$CLUSTER_SCALE" exec "$PROTOST" cluster_workload.st \
            standalone "$dir/out" "$dir/space" "$profile") > "$dir/out/s.log" 2>&1 &
        RUN_PIDS+=($!); PIDS+=($!)
        await "$dir" s.ready
    else
        n="$mode"
        ids=()
        for ((i = 0; i < n; i++)); do ids+=("n$i"); done
        for id in "${ids[@]}"; do
            (cd "$HERE" && STPATH="$REPO/src" CLUSTER_SCALE="$CLUSTER_SCALE" exec "$PROTOST" cluster_workload.st \
                node "$id" "$dir/out" "$dir/space" "$profile" "$n") > "$dir/out/$id.log" 2>&1 &
            RUN_PIDS+=($!); PIDS+=($!)
        done
        await "$dir" "${ids[@]/%/.port}"
        peers=""
        for id in "${ids[@]}"; do peers+="$id $(cat "$dir/out/$id.port")"$'\n'; done
        printf '%s' "$peers" > "$dir/out/peers.tmp" && mv "$dir/out/peers.tmp" "$dir/out/peers"
        await "$dir" "${ids[@]/%/.ready}"
    fi
    touch "$dir/out/go"
    await "$dir" "${ids[@]/%/.result}"
    touch "$dir/out/verify"
    await "$dir" verify.result
    touch "$dir/out/stop"
    for pid in "${RUN_PIDS[@]}"; do
        wait "$pid" || run_fail "$dir" "a process exited with status $?"
    done
    RUN_PIDS=()
    commits=0; critical=0
    for id in "${ids[@]}"; do
        commits=$((commits + $(value "$dir/out/$id.result" commits)))
        [[ "$mode" == standalone ]] || critical=$((critical + $(value "$dir/out/$id.result" critical)))
    done
    count="$(value "$dir/out/verify.result" count)"
    echo "run $round $profile $mode: commits $commits, verifier count $count$([[ "$mode" == standalone ]] || echo ", critical_commits $critical")"
    [[ "$commits" == "$TOTAL" ]] || run_fail "$dir" "the members committed $commits transactions, not $TOTAL"
    [[ "$count" == "$commits" ]] || run_fail "$dir" "the verifier counted $count transactions, the members $commits"
    [[ "$mode" == standalone || "$critical" == "$commits" ]] || run_fail "$dir" "the coordinators counted $critical commits, the members $commits"
    # profile mode commits wall_us retries save_us build_us replication_us reserve_refusals permits
    awk -v p="$profile" -v m="$mode" -v c="$commits" '
        { for (i = 1; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] }
          if (!seen || v["t0"] < t0) t0 = v["t0"]; if (!seen || v["t1"] > t1) t1 = v["t1"]; seen = 1
          att += v["attempts"]; sv += v["save_us"]; bd += v["build_us"]; rp += v["replication_us"]
          rr += v["reserve_refusals"]; pm += v["permits"] }
        END { printf "%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n", p, m, c, t1 - t0, att - c, sv, bd, rp, rr, pm }' \
        $(for id in "${ids[@]}"; do echo "$dir/out/$id.result"; done) >> "$RESULTS/lines"
    if [[ "${KEEP_TMP:-0}" != 1 ]]; then rm -rf "$dir"; fi
}

load_before="$(cut -d' ' -f1-3 /proc/loadavg)"
for ((r = 1; r <= RUNS; r++)); do
    for profile in $PROFILES; do
        for mode in $MODES; do run_one "$r" "$profile" "$mode"; done
    done
done

fstype="$(stat -f -c %T "$CLUSTER_TMPDIR")"
source_dev="$(findmnt -n -o SOURCE --target "$CLUSTER_TMPDIR" 2>/dev/null || echo '?')"
zfs_props=""
if [[ "$fstype" == zfs ]] && command -v zfs > /dev/null; then
    zfs_props=" ($(zfs get -H -o property,value sync,compression,recordsize "$source_dev" 2>/dev/null | tr '\t\n' '= ' | sed 's/ $//'))"
fi
commit="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo '?')"
[[ -z "$(git -C "$REPO" status --porcelain -- src bench 2>/dev/null)" ]] || commit="$commit (src or bench modified or untracked)"
echo
echo "$(date -u +%Y-%m-%dT%H:%MZ); protoBaseST $commit; $("$PROTOST" --version 2>&1 | head -n 1) at $PROTOST"
echo "Machine: $(lscpu | sed -n 's/^\(Model name\|Nombre del modelo\): *//p' | head -n 1), $(nproc) CPUs, Linux $(uname -r)"
echo "Storage: $CLUSTER_TMPDIR on $fstype $source_dev$zfs_props; durability fsync"
echo "RUNS=$RUNS interleaved, $TOTAL transactions per run; load average before: $load_before, after: $(cut -d' ' -f1-3 /proc/loadavg)"
echo "Cluster members are protost processes on 127.0.0.1 with proto_db's default options (2000 ms lease)."
echo "commits/s from the min / median wall time (first start to last end over every process); retries = block"
echo "runs beyond one per transaction, min-max; per commit (median of the runs, microseconds): save = the"
echo "root-independent work before the permission, build = validation, merge, path copy and the new root"
echo "under it, replication = replicate sent to commit settled; permits = permit requests sent to another"
echo "member, per commit (a member that owns the term issues its own permissions without a message)."
awk -F'\t' '
    { key = $1 SUBSEP $2; c = ++n[key]
      wall[key, c] = $4; rt = $5
      sv[key, c] = $6 / $3; bd[key, c] = $7 / $3; rp[key, c] = $8 / $3; pm[key, c] = $10 / $3
      rr[key] += $9; txns[key] = $3
      if (c == 1 || rt < rmin[key]) rmin[key] = rt
      if (c == 1 || rt > rmax[key]) rmax[key] = rt
      if (!(key in seen)) { seen[key] = 1; order[++k] = key } }
    function med(arr, key,   c, i, j, t, a) {
        c = n[key]; for (i = 1; i <= c; i++) a[i] = arr[key, i]
        for (i = 2; i <= c; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t }
        lo = a[1]; return (c % 2) ? a[(c + 1) / 2] : (a[c / 2] + a[c / 2 + 1]) / 2
    }
    END {
        print "| profile | mode | commits/s | retries | save | build | replication | permits | reserve refusals |"
        print "|---|---|---|---|---|---|---|---|---|"
        for (i = 1; i <= k; i++) { key = order[i]; split(key, pm2, SUBSEP)
            md = med(wall, key); mn = lo
            mode = (pm2[2] == "standalone") ? "standalone" : pm2[2] " member" (pm2[2] == 1 ? "" : "s")
            if (pm2[2] == "standalone")
                printf "| %s | %s | %.1f / %.1f | %d-%d | - | - | - | - | - |\n", pm2[1], mode,
                    txns[key] * 1e6 / mn, txns[key] * 1e6 / md, rmin[key], rmax[key]
            else
                printf "| %s | %s | %.1f / %.1f | %d-%d | %.0f | %.0f | %.0f | %.2f | %d |\n", pm2[1], mode,
                    txns[key] * 1e6 / mn, txns[key] * 1e6 / md, rmin[key], rmax[key],
                    med(sv, key), med(bd, key), med(rp, key), med(pm, key), rr[key] }
    }' "$RESULTS/lines"
