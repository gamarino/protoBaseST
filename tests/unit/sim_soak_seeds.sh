#!/usr/bin/env bash
# The soak knob of the simulator families (CC14, _sim.st PBSimSoak): PBST_SIM_SEEDS=n raises the
# seed list of every product-rule family to n seeds, keeping a family split over files split, and
# leaves the default run unchanged; a value that is not a positive integer fails. Every sim_*.st
# file is classified: it takes the knob (it names PBSimSoak), or it is listed below as exempt with
# its reason, so a new simulator file cannot silently stay out of the soak.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTOST="${PROTOST:-protost}"
export STPATH="$HERE/../../src${STPATH:+:$STPATH}"
fail=0
probe_file="$(mktemp --suffix=.st -p "${TMPDIR:-/tmp}")"
trap 'rm -f "$probe_file"' EXIT
probe() {   # probe <PBST_SIM_SEEDS value or "-"> <expression>: the output of the expression (its value last)
    printf "Import from: 'protobase'.\nImport from: '_sim'.\n%s\n" "$2" > "$probe_file"
    if [[ "$1" == - ]]; then
        (cd "$HERE" && env -u PBST_SIM_SEEDS "$PROTOST" --print-last "$probe_file" 2>&1)
    else
        (cd "$HERE" && PBST_SIM_SEEDS="$1" "$PROTOST" --print-last "$probe_file" 2>&1)
    fi
}
expect() {  # expect <label> <output> <wanted last line>
    if [[ "$(printf '%s\n' "$2" | tail -n 1)" == "$3" ]]; then echo "ok: $1"; else echo "FAILED: $1: got [$2], wanted [$3]"; fail=1; fi
}
expect 'without the variable a list is unchanged' \
    "$(probe - '(PBSimSoak seeds: (101 to: 200)) size printString , (PBSimSoak seeds: #(1 2)) printString , PBSimSoak count printString')" \
    '100#(1 2)nil'
expect 'with n = 3, a list starting at 1 is 1..3' "$(probe 3 '(PBSimSoak seeds: (1 to: 8)) printString')" '#(1 2 3)'
expect 'with n = 3, the second half of a split family is 4..6' "$(probe 3 '(PBSimSoak seeds: (101 to: 200)) printString')" '#(4 5 6)'
expect 'with n = 3, a single seed 2 is 4..6' "$(probe 3 '(PBSimSoak seeds: #(2)) printString')" '#(4 5 6)'
expect 'same:over: answers the one answer of every seed' "$(probe 3 '(PBSimSoak same: [:n | n > 0] over: #(1)) printString')" 'true'
expect 'same:over: names the seeds that differ' "$(probe 3 '(PBSimSoak same: [:n | n odd] over: #(1)) printString')" '#(#differs true #(#(2 false)))'
got="$(probe 12x 'PBSimSoak count printString')"
[[ "$got" == *"PBST_SIM_SEEDS must be a positive integer"* ]] && echo "ok: a malformed value fails" || { echo "FAILED: a malformed value: [$got]"; fail=1; }
got="$(probe 0 'PBSimSoak count printString')"
[[ "$got" == *"PBST_SIM_SEEDS must be a positive integer"* ]] && echo "ok: 0 fails" || { echo "FAILED: 0: [$got]"; fail=1; }

# Exempt simulator files, each with its reason.
declare -A exempt=(
    [sim_checker_plants.st]='planted defects of the checker: each is caught on its own schedule'
    [sim_leases_plants.st]='planted wrong rules only: a plant is caught on its own seeds'
    [sim_lessons.st]='one fixed schedule per lesson (L5 to L29), each its own seed by design'
    [sim_timer_audit.st]='the timer audit index: its runs are seeds 1-30 per part with measured floors'
)
for f in "$HERE"/sim_*.st; do
    b="$(basename "$f")"
    if [[ -n "${exempt[$b]:-}" ]]; then
        grep -q PBSimSoak "$f" && { echo "FAILED: $b is listed exempt but takes the knob"; fail=1; }
    elif ! grep -q 'PBSimSoak' "$f"; then
        echo "FAILED: $b neither takes PBST_SIM_SEEDS (PBSimSoak) nor is listed exempt"; fail=1
    fi
done
for b in "${!exempt[@]}"; do
    [[ -e "$HERE/$b" ]] || { echo "FAILED: exempt $b does not exist"; fail=1; }
done
exit $fail
