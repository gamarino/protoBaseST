#!/usr/bin/env bash
# The oracle of the real-process tests checked on its own (Task 27 review M2): no process runs.
# A synthetic run directory holds the outcome files _node.st writes (<id>.attempt, .acked,
# .unknown, killed<s>) and the verifier's (v.present, v.result) for three workers: n0 killed
# (killed1) with one token in flight that the space holds, n1 with an unknown token the space does
# not hold, n2 killed (killed2) with one token in flight the space does not hold. The base case
# passes with counter 8 = 7 acknowledged + 1 unknown present, so the unknown arm of the rule runs.
# Each mutant changes one file and must fail cluster_verify with its own message.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_cluster.sh
source "$HERE/_cluster.sh"

# base <dir>: the synthetic run, with its out/ files.
base() {
    local o="$1/out"
    mkdir -p "$o"
    printf '%s\n' n0-1 n0-2 n0-3 > "$o/n0.attempt"; printf '%s\n' n0-1 n0-2 > "$o/n0.acked"; : > "$o/n0.unknown"
    printf '%s\n' n1-1 n1-2 n1-3 > "$o/n1.attempt"; printf '%s\n' n1-1 n1-2 > "$o/n1.acked"; echo n1-3 > "$o/n1.unknown"
    printf '%s\n' n2-1 n2-2 n2-3 n2-4 > "$o/n2.attempt"; printf '%s\n' n2-1 n2-2 n2-3 > "$o/n2.acked"; : > "$o/n2.unknown"
    echo n0 > "$o/killed1"; echo n2 > "$o/killed2"
    printf '%s\n' n0-1 n0-2 n0-3 n1-1 n1-2 n2-1 n2-2 n2-3 > "$o/v.present"
    echo "counter 8 count 8" > "$o/v.result"
}

checked=0
# expect <name> <expected text|PASS> <shell edit run in out/>
expect() {
    local name="$1" want="$2" edit="$3" dir="$TMP/$1" got
    base "$dir"
    (cd "$dir/out" && eval "$edit") || fail "$name: the edit failed"
    got="$( (cluster_verify "$dir" v n0 n1 n2) 2>&1 | grep -E '^(FAIL|NOTE): ' | tail -n 1)"
    if [[ "$want" == PASS ]]; then
        [[ "$got" == "NOTE: $name: counter 8 = 7 acknowledged + 1 of 3 unknown present; n0 n2 killed with kill -9" ]] \
            || fail "$name: expected the base case to pass, got [$got]"
    else
        [[ "$got" == "FAIL: "*"$want"* ]] || fail "$name: expected a FAIL containing [$want], got [$got]"
    fi
    checked=$((checked + 1))
}

expect base PASS 'true'
expect acked-missing 'acknowledged tokens are missing: n1-2' 'sed -i /^n1-2$/d v.present; echo "counter 7 count 7" > v.result'
expect counter-not-count 'counter 9 but 8 tokens' 'echo "counter 9 count 8" > v.result'
expect attempted-twice 'a token was attempted twice' 'echo n1-1 >> n2.attempt; echo n1-1 >> n2.acked'
expect unresolved-alive 'n1 left tokens unresolved without being killed: n1-4' 'echo n1-4 >> n1.attempt'
expect unknown-not-counted 'counter 8 != acked 7 + unknown present 0' 'sed -i /^n0-3$/d v.present'
expect phantom 'counter 9 != acked 7 + unknown present 1' 'echo "counter 9 count 9" > v.result'
expect two-in-flight 'n0, killed, left more than one token unresolved' 'echo n0-4 >> n0.attempt'
expect acked-and-unknown 'a token is both acked and unknown' 'echo n1-1 >> n1.unknown'
expect never-attempted 'n2 resolved a token it never attempted' 'echo n2-9 >> n2.acked'
expect second-kill-list 'n2 left tokens unresolved without being killed: n2-4' 'mv killed2 ../killed2.dropped'
echo "verify rules ok ($checked cases)"
