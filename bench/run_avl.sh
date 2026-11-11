#!/usr/bin/env bash
# Runs bench/avl_workload.st on one or more protost binaries, each against a protoBaseST source
# tree, and bench/py_avl_workload.py on ProtoBase (the interop venv), and prints, per operation,
# the minimum and the median microseconds per operation of each implementation and the ratio of
# its minimum to ProtoBase's.
#
# Usage: bench/run_avl.sh label=/path/to/protost[@/path/to/protoBaseST/src] ...
#
# Without @src, the source tree is this checkout's src. The workload file is always this
# checkout's bench/avl_workload.st, so a before/after of the library runs the same work: put the
# "before" tree in a git worktree (git worktree add <dir> <rev>) and pass <dir>/src. The runs
# interleave: RUNS rounds (default 5), each running every implementation once, in order, so a
# change of machine load spreads over all of them. Every run must end with 'avl_workload ok', and
# every implementation must report the same operations and checksums; anything else is a failure
# (exit 1). Timings are reported, never asserted.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
RUNS="${RUNS:-5}"
[[ $# -ge 1 ]] || { echo "usage: $0 label=/path/to/protost[@/path/to/src] ..." >&2; exit 2; }
# shellcheck source=../tests/interop/env.sh
source "$REPO/tests/interop/env.sh" || exit 1
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

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

for ((r = 1; r <= RUNS; r++)); do
    for ((i = 0; i < ${#labels[@]}; i++)); do
        label="${labels[$i]}"; out="$TMP/$label.$r"
        if [[ $i -eq 0 ]]; then
            (cd "$HERE" && "$PY" py_avl_workload.py) > "$out" 2>&1
        else
            (cd "$HERE" && STPATH="${srcs[$i]}" "${bins[$i]}" avl_workload.st) > "$out" 2>&1
        fi || { cat "$out"; fail "$label run $r exited non-zero"; }
        [[ "$(tail -n 1 "$out")" == "avl_workload ok" ]] || { cat "$out"; fail "$label run $r did not finish"; }
        grep '^op' "$out" | cut -f2,3,5 > "$out.work"
        cmp -s "$out.work" "$TMP/ProtoBase.1.work" || fail "$label run $r: operations or checksums differ from ProtoBase"
    done
done

echo "RUNS=$RUNS interleaved; microseconds per operation, min / median; ratio = min / ProtoBase min"
echo "Python: $("$PY" --version 2>&1); load average: $(cut -d' ' -f1-3 /proc/loadavg)"
for ((i = 1; i < ${#labels[@]}; i++)); do echo "${labels[$i]}: ${bins[$i]} @ ${srcs[$i]}"; done
for label in "${labels[@]}"; do
    cat "$TMP/$label".[0-9]* | grep '^op' | awk -F'\t' -v l="$label" '{ print l "\t" $2 "\t" $3 "\t" $4 }'
done > "$TMP/all"
awk -F'\t' '
    { key = $1 SUBSEP $2; n[key]++; v[key, n[key]] = $4 + 0
      if (!($2 in ops)) { order[++k] = $2; ops[$2] = $3 }
      if (!($1 in seen)) { seen[$1] = 1; lab[++m] = $1 } }
    function stat(key,   c, i, j, t, a) {
        c = n[key]; for (i = 1; i <= c; i++) a[i] = v[key, i]
        for (i = 2; i <= c; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t }
        mn = a[1]; md = (c % 2) ? a[(c + 1) / 2] : (a[c / 2] + a[c / 2 + 1]) / 2
    }
    END {
        printf "| operation | ops |"; for (j = 1; j <= m; j++) printf " %s |", lab[j]
        for (j = 2; j <= m; j++) printf " ratio %s |", lab[j]; printf "\n|---|---|"
        for (j = 1; j < 2 * m; j++) printf "---|"; printf "\n"
        for (i = 1; i <= k; i++) { op = order[i]; printf "| %s | %s |", op, ops[op]
            for (j = 1; j <= m; j++) { stat(lab[j] SUBSEP op); mins[j] = mn; printf " %.1f / %.1f |", mn, md }
            for (j = 2; j <= m; j++) printf " %.0fx |", mins[j] / mins[1]; printf "\n" }
    }' "$TMP/all"
