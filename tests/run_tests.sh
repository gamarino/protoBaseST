#!/usr/bin/env bash
# protoBaseST test runner.
#
# Usage: tests/run_tests.sh [path...]     (default: tests/ and examples/)
#
# Environment:
#   PROTOST         the protost binary (default: protost)
#   PROTOBASE_REPO  a ProtoBase checkout (default: ../ProtoBase), used by the vector fetch
#   RUN_TIMEOUT     seconds allowed per test (default 120)
#
# Each *.st file is a protoST program run with its own directory as the working directory and
# STPATH=<repo>/src. Its first line (second after a "#!" line) is a directive:
#   "EXPECT: <text>"        exit 0, and the last non-empty stdout line equals <text>
#   "EXPECT-ERROR: <text>"  non-zero exit, and the error output contains <text> (text optional)
# A successful run whose last line starts with "SKIP: " counts as skipped. A passing test may also
# print justified per-item skips (lines starting with "SKIP: " before its last line, such as the
# cluster vectors of tests/conformance/cluster.st): they are shown under its PASS line, so a skip is
# always visible where the run is read.
# Each *.sh file passes with exit 0, is skipped with exit 77, and fails otherwise. The lines of a
# passing *.sh file's output that start with "NOTE: " or "SKIP: " are shown under its PASS line (a workaround
# a test relies on is stated where the run is read, never hidden).
# "EXPECT-ERROR" needs a text (an error class or message): the bare form is a test failure, and so
# is a module parse error that the text does not name, so a broken import cannot pass.
# A path argument that does not exist, or a run that finds no test, fails.
# Files whose name starts with "_" are helpers. The tooling scripts tests/run_tests.sh,
# tests/interop/env.sh, tests/interop/setup_venv.sh and tests/conformance/fetch_vectors.sh (exact
# paths) and the directories .venv, out and fixtures are never run as tests. So are the step
# scripts of the ERP demo, examples/erp/{2_payments,3_tag,4_report}.st: they take the database
# directory as an argument and run, in order, under examples/erp/run_demo.sh (which is the test).
# The lessons of examples/tutorial are ordinary tests (each .st ends with '<lesson> ok (N checks)',
# its EXPECT line); their helpers start with "_", and lesson 11 is a .sh test.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROTOST="${PROTOST:-protost}"
case "$PROTOST" in
    */*) PROTOST="$(cd "$(dirname "$PROTOST")" && pwd)/$(basename "$PROTOST")" ;;
    *) PROTOST="$(command -v "$PROTOST" || echo "$PROTOST")" ;;
esac
if [[ ! -x "$PROTOST" ]]; then
    echo "FAIL: protost binary not executable: $PROTOST" >&2
    exit 1
fi
export PROTOST
export PROTOBASE_REPO="${PROTOBASE_REPO:-$REPO/../ProtoBase}"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
TIMEOUT="${RUN_TIMEOUT:-120}"

if [[ $# -eq 0 ]]; then
    set -- "$REPO/tests"
    [[ -d "$REPO/examples" ]] && set -- "$@" "$REPO/examples"
fi

files=()
missing=0
for p in "$@"; do
    if [[ ! -e "$p" ]]; then
        echo "FAIL: no such path: $p"; missing=$((missing + 1)); continue
    fi
    p="$(cd "$(dirname "$p")" && pwd)/$(basename "$p")"
    if [[ -d "$p" ]]; then
        while IFS= read -r f; do files+=("$f"); done < <(
            find "$p" \( -name .venv -o -name out -o -name fixtures \) -prune -o -type f \
                \( -name '*.st' -o -name '*.sh' \) ! -name '_*' \
                -print | sort)
    else
        files+=("$p")
    fi
done
TOOLING=" tests/run_tests.sh tests/interop/env.sh tests/interop/setup_venv.sh tests/conformance/fetch_vectors.sh examples/erp/2_payments.st examples/erp/3_tag.st examples/erp/4_report.st "
kept=()
for f in "${files[@]}"; do
    [[ "$TOOLING" == *" ${f#"$REPO"/} "* ]] || kept+=("$f")
done
files=("${kept[@]}")

passed=0; failed=0; skipped=0
rel() { printf '%s' "${1#"$REPO"/}"; }

run_st() {
    local file="$1" dir base line directive mode expected out err rc last
    dir="$(dirname "$file")"; base="$(basename "$file")"
    line="$(head -n 1 "$file")"
    [[ "$line" == '#!'* ]] && line="$(sed -n 2p "$file")"
    directive="${line#\"}"; directive="${directive%\"}"
    directive="${directive#"${directive%%[![:space:]]*}"}"
    directive="${directive%"${directive##*[![:space:]]}"}"
    case "$directive" in
        EXPECT-ERROR:*) mode=error; expected="${directive#EXPECT-ERROR:}"; expected="${expected# }"
            if [[ -z "$expected" ]]; then
                echo "FAIL: $(rel "$file"): EXPECT-ERROR needs the expected error text"; return 1
            fi ;;
        EXPECT-ERROR)   echo "FAIL: $(rel "$file"): EXPECT-ERROR needs the expected error text"; return 1 ;;
        EXPECT:*)       mode=value; expected="${directive#EXPECT:}"; expected="${expected# }" ;;
        *) echo "FAIL: $(rel "$file"): no directive on the first line"; return 1 ;;
    esac
    err="$(mktemp)"
    out="$(cd "$dir" && timeout "$TIMEOUT" "$PROTOST" --print-last "$base" </dev/null 2>"$err")"
    rc=$?
    local errtext; errtext="$(tr -d '\000' < "$err")"; rm -f "$err"
    last="$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -n 1)"
    if [[ $rc -eq 0 && "$last" == "SKIP: "* ]]; then
        echo "SKIP: $(rel "$file"): ${last#SKIP: }"; return 77
    fi
    if [[ $mode == value ]]; then
        if [[ $rc -eq 0 && "$last" == "$expected" ]]; then
            echo "PASS: $(rel "$file")"
            printf '%s\n' "$out" | grep '^SKIP: ' | sed 's/^/    /'
            return 0
        fi
        echo "FAIL: $(rel "$file"): expected [$expected], got exit=$rc last=[$last] stderr=[$errtext]"
        return 1
    fi
    if [[ $rc -ge 124 ]]; then
        echo "FAIL: $(rel "$file"): crashed or timed out (exit=$rc)"; return 1
    fi
    if [[ "$errtext" == *"module parse errors"* && "$expected" != *"parse error"* ]]; then
        echo "FAIL: $(rel "$file"): a module parse error, not the expected error [$expected]: $errtext"; return 1
    fi
    if [[ $rc -ne 0 && "$errtext" == *"$expected"* ]]; then
        echo "PASS: $(rel "$file")"; return 0
    fi
    echo "FAIL: $(rel "$file"): expected an error containing [$expected], got exit=$rc stderr=[$errtext]"
    return 1
}

run_sh() {
    local file="$1" out rc
    out="$(cd "$(dirname "$file")" && timeout "$TIMEOUT" bash "$file" </dev/null 2>&1)"
    rc=$?
    case $rc in
        0)  echo "PASS: $(rel "$file")"
            printf '%s\n' "$out" | grep -E '^(NOTE|SKIP): ' | sed 's/^/    /'
            return 0 ;;
        77) echo "SKIP: $(rel "$file"): $(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -n 1)"; return 77 ;;
        *)  echo "FAIL: $(rel "$file"): exit=$rc: $(printf '%s\n' "$out" | tail -n 3 | tr '\n' ' ')"; return 1 ;;
    esac
}

for f in "${files[@]}"; do
    case "$f" in
        *.st) run_st "$f" ;;
        *.sh) run_sh "$f" ;;
    esac
    case $? in
        0) passed=$((passed + 1)) ;;
        77) skipped=$((skipped + 1)) ;;
        *) failed=$((failed + 1)) ;;
    esac
done

failed=$((failed + missing))
if [[ $((passed + failed + skipped)) -eq 0 ]]; then
    echo "FAIL: no tests found"; failed=1
fi
echo "passed $passed, failed $failed, skipped $skipped"
[[ $failed -eq 0 ]]
