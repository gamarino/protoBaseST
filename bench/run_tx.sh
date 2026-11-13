#!/usr/bin/env bash
# Runs bench/tx_workload.st on one or more protost binaries, each against a protoBaseST source
# tree, and bench/py_tx_workload.py on ProtoBase (the interop venv), and prints, per profile, the
# committed transactions per second of each implementation (from the minimum and from the median
# wall time), the retries (minimum to maximum over the runs) and the ratio of its best rate to
# ProtoBase's.
#
# Usage: bench/run_tx.sh label=/path/to/protost[@/path/to/protoBaseST/src] ...
#
# Without @src, the source tree is this checkout's src; the workload files are always this
# checkout's (see run_avl.sh for a before/after with a git worktree). Every run gets a new
# directory under TX_TMPDIR (default /var/tmp: /tmp is often tmpfs, where fsync costs nothing),
# removed when the run ends. TX_SCALE (default 1) multiplies the transactions of every profile.
# The runs interleave: RUNS rounds (default 5), each running every implementation once, in order,
# so a change of machine load spreads over all of them. Every run must end with 'tx_workload ok',
# and every implementation must report the same profiles, transactions and checksums; anything
# else is a failure (exit 1). Timings and retries are reported, never asserted.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
RUNS="${RUNS:-5}"
TX_SCALE="${TX_SCALE:-1}"
TX_TMPDIR="${TX_TMPDIR:-/var/tmp}"
[[ $# -ge 1 ]] || { echo "usage: $0 label=/path/to/protost[@/path/to/src] ..." >&2; exit 2; }
# shellcheck source=../tests/interop/env.sh
source "$REPO/tests/interop/env.sh" || exit 1
TMP="$(mktemp -d)"
DATA=""
trap 'rm -rf "$TMP"; [[ -n "$DATA" ]] && rm -rf "$DATA"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
[[ -d "$TX_TMPDIR" && -w "$TX_TMPDIR" ]] || fail "TX_TMPDIR is not a writable directory: $TX_TMPDIR"

labels=(ProtoBase)
bins=("")
srcs=("")
for spec in "$@"; do
    label="${spec%%=*}"; rest="${spec#*=}"
    bin="${rest%%@*}"; src="$REPO/src"
    [[ "$rest" == *@* ]] && src="${rest#*@}"
    [[ "$label" != "$spec" && -n "$label" ]] || fail "not label=binary[@src]: $spec"
    [[ -x "$bin" ]] || fail "not executable: $bin"
    [[ -f "$src/protobase.st" ]] || fail "not a protoBaseST source tree: $src"
    labels+=("$label")
    bins+=("$(cd "$(dirname "$bin")" && pwd)/$(basename "$bin")")
    srcs+=("$(cd "$src" && pwd)")
done

load_before="$(cut -d' ' -f1-3 /proc/loadavg)"
for ((r = 1; r <= RUNS; r++)); do
    for ((i = 0; i < ${#labels[@]}; i++)); do
        label="${labels[$i]}"; out="$TMP/$label.$r"
        DATA="$(mktemp -d -p "$TX_TMPDIR" pbst-tx.XXXXXX)" || fail "cannot create a directory in $TX_TMPDIR"
        if [[ $i -eq 0 ]]; then
            (cd "$HERE" && TX_DIR="$DATA" TX_SCALE="$TX_SCALE" "$PY" py_tx_workload.py) > "$out" 2>&1
        else
            (cd "$HERE" && TX_DIR="$DATA" TX_SCALE="$TX_SCALE" STPATH="${srcs[$i]}" "${bins[$i]}" tx_workload.st) > "$out" 2>&1
        fi || { cat "$out"; fail "$label run $r exited non-zero"; }
        rm -rf "$DATA"; DATA=""
        [[ "$(tail -n 1 "$out")" == "tx_workload ok" ]] || { cat "$out"; fail "$label run $r did not finish"; }
        grep '^op' "$out" | cut -f2,3,6 > "$out.work"
        cmp -s "$out.work" "$TMP/ProtoBase.1.work" || fail "$label run $r: profiles, transactions or checksums differ from ProtoBase"
    done
done

fstype="$(stat -f -c %T "$TX_TMPDIR")"
source_dev="$(findmnt -n -o SOURCE --target "$TX_TMPDIR" 2>/dev/null || echo '?')"
zfs_props=""
if [[ "$fstype" == zfs ]] && command -v zfs > /dev/null; then
    zfs_props=" ($(zfs get -H -o property,value sync,compression,recordsize "$source_dev" 2>/dev/null | tr '\t\n' '= ' | sed 's/ $//'))"
fi
echo "RUNS=$RUNS interleaved, TX_SCALE=$TX_SCALE; commits per second from the min / median wall time;"
echo "retries = block runs beyond one per transaction, min-max over the runs; ratio = best rate / ProtoBase best rate"
echo "Storage: $TX_TMPDIR on $fstype $source_dev$zfs_props; durability fsync on both sides (protoBaseST has no other mode)"
echo "Python: $("$PY" --version 2>&1); load average before: $load_before, after: $(cut -d' ' -f1-3 /proc/loadavg)"
for ((i = 1; i < ${#labels[@]}; i++)); do echo "${labels[$i]}: ${bins[$i]} @ ${srcs[$i]}"; done
for label in "${labels[@]}"; do
    grep -h '^skip' "$TMP/$label.1" | sed "s/^/$label: /" >> "$TMP/skips"
    cat "$TMP/$label".[0-9]* | grep '^op' | awk -F'\t' -v l="$label" '{ print l "\t" $2 "\t" $3 "\t" $4 "\t" $5 }'
done > "$TMP/all"
[[ -s "$TMP/skips" ]] && cat "$TMP/skips"
awk -F'\t' '
    { key = $1 SUBSEP $2; c = ++n[key]; v[key, c] = $4 + 0; rt = $5 + 0
      if (c == 1 || rt < rmin[key]) rmin[key] = rt
      if (c == 1 || rt > rmax[key]) rmax[key] = rt
      if (!($2 in txns)) { order[++k] = $2; txns[$2] = $3 }
      if (!($1 in seen)) { seen[$1] = 1; lab[++m] = $1 } }
    function stat(key,   c, i, j, t, a) {
        c = n[key]; for (i = 1; i <= c; i++) a[i] = v[key, i]
        for (i = 2; i <= c; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t }
        mn = a[1]; md = (c % 2) ? a[(c + 1) / 2] : (a[c / 2] + a[c / 2 + 1]) / 2
    }
    END {
        printf "| profile | transactions |"
        for (j = 1; j <= m; j++) printf " %s commits/s | %s retries |", lab[j], lab[j]
        for (j = 2; j <= m; j++) printf " ratio %s |", lab[j]; printf "\n|---|---|"
        for (j = 1; j < 3 * m; j++) printf "---|"; printf "\n"
        for (i = 1; i <= k; i++) { p = order[i]; printf "| %s | %s |", p, txns[p]
            for (j = 1; j <= m; j++) { key = lab[j] SUBSEP p; stat(key); best[j] = txns[p] / mn
                printf " %.1f / %.1f | %d-%d |", txns[p] / mn, txns[p] / md, rmin[key], rmax[key] }
            for (j = 2; j <= m; j++) printf " %.3fx |", best[j] / best[1]; printf "\n" }
    }' "$TMP/all"
