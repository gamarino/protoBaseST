#!/usr/bin/env bash
# Runs avl_workload.st on one or more protost binaries and py_avl_workload.py on ProtoBase
# (the interop venv), RUNS times each (default 3), and prints, per operation, the fastest
# microseconds per operation of each implementation and its ratio to ProtoBase.
#
# Usage: bench/run_avl.sh label=/path/to/protost [label=/path/to/protost ...]
#
# Every run must end with 'avl_workload ok', and every implementation must report the same
# operations with the same checksums; anything else is a failure (exit 1). Timings are
# reported, never asserted.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
RUNS="${RUNS:-3}"
[[ $# -ge 1 ]] || { echo "usage: $0 label=/path/to/protost ..." >&2; exit 2; }
# shellcheck source=../tests/interop/env.sh
source "$REPO/tests/interop/env.sh" || exit 1
export STPATH="$REPO/src${STPATH:+:$STPATH}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

labels=()
run_impl() {  # label command...
    local label="$1"; shift
    labels+=("$label")
    for ((r = 1; r <= RUNS; r++)); do
        (cd "$HERE" && "$@") > "$TMP/$label.$r" 2>&1 || { cat "$TMP/$label.$r"; fail "$label run $r exited non-zero"; }
        [[ "$(tail -n 1 "$TMP/$label.$r")" == "avl_workload ok" ]] || { cat "$TMP/$label.$r"; fail "$label run $r did not finish"; }
        grep '^op' "$TMP/$label.$r" | cut -f2,3,5 > "$TMP/$label.$r.work"
        cmp -s "$TMP/$label.$r.work" "$TMP/${labels[0]}.1.work" || fail "$label run $r: operations or checksums differ from ${labels[0]}"
    done
}

run_impl ProtoBase "$PY" py_avl_workload.py
for spec in "$@"; do
    label="${spec%%=*}"; bin="${spec#*=}"
    [[ -x "$bin" ]] || fail "not executable: $bin"
    bin="$(cd "$(dirname "$bin")" && pwd)/$(basename "$bin")"
    run_impl "$label" "$bin" avl_workload.st
done

echo "RUNS=$RUNS; microseconds per operation (fastest run); ratio = protoBaseST / ProtoBase"
echo "Python: $("$PY" --version 2>&1); load average: $(cut -d' ' -f1-3 /proc/loadavg)"
for label in "${labels[@]}"; do
    cat "$TMP/$label".[0-9]* | grep '^op' | awk -F'\t' -v l="$label" '
        { if (!($2 in best) || $4 + 0 < best[$2]) best[$2] = $4 + 0; if (!($2 in ops)) { order[++k] = $2; ops[$2] = $3 } }
        END { for (i = 1; i <= k; i++) printf "%s\t%s\t%s\t%.2f\n", l, order[i], ops[order[i]], best[order[i]] }'
done > "$TMP/best"
awk -F'\t' '
    $1 == "ProtoBase" { base[$2] = $4; order[++k] = $2; ops[$2] = $3 }
    { v[$1, $2] = $4; if (!($1 in seen)) { seen[$1] = 1; lab[++m] = $1 } }
    END {
        printf "| operation | ops |"; for (j = 1; j <= m; j++) printf " %s |", lab[j];
        for (j = 2; j <= m; j++) printf " ratio %s |", lab[j]; printf "\n|---|---|";
        for (j = 1; j < 2 * m; j++) printf "---|"; printf "\n";
        for (i = 1; i <= k; i++) { op = order[i]; printf "| %s | %s |", op, ops[op];
            for (j = 1; j <= m; j++) printf " %.1f |", v[lab[j], op];
            for (j = 2; j <= m; j++) printf " %.0fx |", v[lab[j], op] / base[op]; printf "\n" }
    }' "$TMP/best"
