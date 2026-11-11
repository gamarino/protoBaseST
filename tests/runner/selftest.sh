#!/usr/bin/env bash
# Self-test of tests/run_tests.sh: the runner must fail on a wrong error, a bare EXPECT-ERROR, a
# broken import, a parse error, a missing path and an empty tree, and pass the right cases; it must
# show the SKIP lines a passing test prints.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$HERE/../run_tests.sh"
FIX="$HERE/fixtures"
EMPTY="$(mktemp -d)"; trap 'rmdir "$EMPTY"' EXIT
bad=0
expect() {  # expect <pass|fail> <description> <runner args...>
    local want="$1" what="$2" rc; shift 2
    "$RUNNER" "$@" >/dev/null 2>&1; rc=$?
    if { [[ $want == pass ]] && [[ $rc -eq 0 ]]; } || { [[ $want == fail ]] && [[ $rc -ne 0 ]]; }; then
        echo "ok: $what"
    else
        echo "WRONG: $what (wanted $want, exit $rc)"; bad=1
    fi
}
expect pass "EXPECT passes"                    "$FIX/pass.st"
expect pass "EXPECT-ERROR with the right text" "$FIX/right_error.st"
expect fail "EXPECT-ERROR with the wrong error" "$FIX/wrong_error.st"
expect fail "bare EXPECT-ERROR"                "$FIX/bare_error.st"
expect fail "broken import"                    "$FIX/broken_import.st"
expect fail "parse error"                      "$FIX/parse_error.st"
expect fail "missing path"                     "$HERE/no_such_path"
expect fail "empty tree finds no test"         "$EMPTY"
# A passing test's per-item skips are shown under its PASS line.
if "$RUNNER" "$FIX/inner_skip.st" 2>&1 | grep -q '^    SKIP: item one: a justified reason$'; then
    echo "ok: a passing test's SKIP lines are shown"
else
    echo "WRONG: a passing test's SKIP lines are not shown"; bad=1
fi
exit $bad
