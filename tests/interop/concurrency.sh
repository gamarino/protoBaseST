#!/usr/bin/env bash
# The concurrency table across languages (design spec 10.4, plan Task 21 and call C12). For every
# case of concurrency_cases.json, each on a new space made by py_case.py setup:
#   1. reference: py_case.py both runs A and B in ProtoBase (start A, start B, commit B, commit A);
#      its outcome line and dump must be the ones the JSON records;
#   2. protoST as A: _st_case.st a starts A, runs py_case.py b to completion as a subprocess, then
#      commits A; ProtoBase's own dump of the space must equal the one protoST printed;
#   3. Python as A: py_case.py a starts A, runs _st_case.st b to completion, then commits A;
#      protoST's dump of the space must equal the one Python printed.
# Runs 2 and 3 must print the reference too, except where the case records protoBaseST's
# documented refusal (its 'protobasest' entry: a blind write onto an indexed root, design spec
# 7.4), whose difference is asserted exactly and printed as a NOTE. py_case.py expected refuses a
# 'protobasest' entry on any other case, or one whose outcomes are not PBNotSupportedError. Every step is a process run to
# completion, so nothing depends on timing. Exit 77 without the interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
export PY PROTOST
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Failures go to stderr, so that one inside a command substitution is still shown.
fail() { echo "FAIL: $*" >&2; exit 1; }
cd "$HERE" || fail "no directory $HERE"

# Runs one step, failing the test when it exits non-zero; prints its output.
step() {
    local out
    out="$("$@" 2>&1)" || fail "$* exited $?: $out"
    printf '%s' "$out"
}
# The output of a run without its first line (the outcome line): its dump.
dump_of() { printf '%s\n' "$1" | tail -n +2; }

ids="$(step "$PY" -c 'import json; print(" ".join(c["id"] for c in json.load(open("concurrency_cases.json"))["cases"]))')" || exit 1
count=0
for id in $ids; do
    reference="$(step "$PY" py_case.py expected "$id" reference)" || exit 1
    want_st="$(step "$PY" py_case.py expected "$id" st_as_a)" || exit 1
    want_py="$(step "$PY" py_case.py expected "$id" py_as_a)" || exit 1

    space="$TMP/$id-reference"
    step "$PY" py_case.py setup "$id" "$space" > /dev/null
    out="$(step "$PY" py_case.py both "$id" "$space")" || exit 1
    [[ "$out" == "$reference" ]] || fail "$id: ProtoBase's outcome is not the one recorded:"$'\n'"$out"$'\n'"recorded:"$'\n'"$reference"

    space="$TMP/$id-st-as-a"
    step "$PY" py_case.py setup "$id" "$space" > /dev/null
    out="$(step "$PROTOST" _st_case.st a "$id" "$space")" || exit 1
    [[ "$out" == "$want_st" ]] || fail "$id, protoST as A:"$'\n'"$out"$'\n'"expected:"$'\n'"$want_st"
    other="$(step "$PY" py_case.py dump "$id" "$space")" || exit 1
    [[ "$other" == "$(dump_of "$out")" ]] || fail "$id, protoST as A: ProtoBase reads"$'\n'"$other"

    space="$TMP/$id-py-as-a"
    step "$PY" py_case.py setup "$id" "$space" > /dev/null
    out="$(step "$PY" py_case.py a "$id" "$space")" || exit 1
    [[ "$out" == "$want_py" ]] || fail "$id, Python as A:"$'\n'"$out"$'\n'"expected:"$'\n'"$want_py"
    other="$(step "$PROTOST" _st_case.st dump "$id" "$space")" || exit 1
    [[ "$other" == "$(dump_of "$out")" ]] || fail "$id, Python as A: protoBaseST reads"$'\n'"$other"

    if [[ "$want_st" != "$reference" || "$want_py" != "$reference" ]]; then
        echo "NOTE: $id: ProtoBase $(head -n 1 <<< "$reference"); protoBaseST refuses as documented" \
            "(design spec 7.4): protoST as A $(head -n 1 <<< "$want_st"), Python as A $(head -n 1 <<< "$want_py")"
    fi
    count=$((count + 1))
done
# The 13 rows of design spec 10.4, and row 7 with its roles swapped (fix round 1).
[[ "$count" -eq 14 ]] || fail "expected the 13 rows of design spec 10.4 and the swapped row 7, ran $count"
echo "concurrency table: $count cases, ProtoBase's outcomes in both assignments"
