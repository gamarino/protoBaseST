# Sourced by the real-process cluster tests (tests/cluster/real_*.sh): starts protost processes
# that run _node.st, kills them, waits for their marker files and verifies what a verifier read.
#
# Processes: every process is started here, in the background, and its PID recorded from $!; only
# those PIDs are ever signalled (never pkill, killall or a kill by pattern). The EXIT trap kills
# and reaps every one still running, on every exit path (TERM and INT exit through it too), so no
# protost process outlives the test; then it removes the test's directory (kept with KEEP_TMP=1).
#
# Timing: nothing here asserts a duration. Every wait is a loop over a condition bounded by
# WAIT_SECONDS (default 400), which turns a hang into a FAIL naming the file; the runner's timeout
# is the outer deadline. While it waits, a process that should be running and has exited fails
# the test at once, with the end of its log.
#
# A run lives in a directory <run>: <run>/space is the cluster space every member shares,
# <run>/out holds the marker files of _node.st (its header lists them) and each process's
# stderr, <run>/out/<id>.log.
set -u
CLUSTER_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_REPO="$(cd "$CLUSTER_HERE/../.." && pwd)"
export STPATH="$CLUSTER_REPO/src${STPATH:+:$STPATH}"
export PROTOST="${PROTOST:-protost}"
WAIT_SECONDS="${WAIT_SECONDS:-400}"
TMP="$(mktemp -d)"

declare -A PID_OF=()      # id -> pid, per run (keys are "<run>/<id>")
declare -A RUN_OF=()      # pid -> "<run>/<id>"
LIVE=()                   # pids expected to be running
ALL=()                    # every pid started

# Whether <pid> is still a child of this shell: a PID already reaped may belong to another
# process by now, so nothing is signalled without this check.
_is_child() {
    [[ "$(ps -o ppid= -p "$1" 2>/dev/null | tr -d ' ')" == "$$" ]]
}

# Drops <pid> from LIVE and ALL once it has been waited for (it is never signalled again).
_forget() {
    local pid="$1" p keep=()
    for p in "${LIVE[@]}"; do [[ "$p" == "$pid" ]] || keep+=("$p"); done
    LIVE=("${keep[@]}")
    keep=()
    for p in "${ALL[@]}"; do [[ "$p" == "$pid" ]] || keep+=("$p"); done
    ALL=("${keep[@]}")
}

cluster_cleanup() {
    local pid
    for pid in "${ALL[@]}"; do
        _is_child "$pid" && kill -9 "$pid" 2>/dev/null
    done
    for pid in "${ALL[@]}"; do
        wait "$pid" 2>/dev/null
    done
    ALL=(); LIVE=()
    if [[ "${KEEP_TMP:-}" == 1 ]]; then
        echo "NOTE: kept $TMP"
    else
        rm -rf "$TMP"
    fi
}
trap cluster_cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# The end of every log of <run>, for a failure message.
cluster_logs() {
    local f
    for f in "$1"/out/*.log; do
        [[ -e "$f" ]] || continue
        echo "--- $(basename "$f") (last lines)"
        tail -n 15 "$f"
    done
}

fail() { echo "FAIL: $*"; exit 1; }
fail_run() { local run="$1"; shift; cluster_logs "$run"; echo "FAIL: $*"; exit 1; }

# cluster_run <name>: a fresh run directory; prints its path.
cluster_run() {
    local run="$TMP/$1"
    mkdir -p "$run/out" "$run/space" || fail "cannot create $run"
    printf '%s\n' "$run"
}

_start() {
    local run="$1" id="$2"; shift 2
    (cd "$CLUSTER_HERE" && exec "$PROTOST" _node.st "$@" </dev/null >"$run/out/$id.stdout" 2>"$run/out/$id.log") &
    local pid=$!
    PID_OF["$run/$id"]=$pid
    RUN_OF[$pid]="$run/$id"
    LIVE+=("$pid")
    ALL+=("$pid")
}

# cluster_worker <run> <id> <n> <after> <marks> (as _node.st takes them); cluster_verifier <run> <id>.
cluster_worker() { _start "$1" "$2" worker "$2" "$1/out" "$1/space" "$3" "$4" "$5"; }
cluster_verifier() { _start "$1" "$2" verifier "$2" "$1/out" "$1/space"; }

# Fails the test when a process of LIVE has exited (with the end of its log).
_check_live() {
    local run="$1" pid
    for pid in "${LIVE[@]}"; do
        if ! _is_child "$pid" || [[ "$(ps -o stat= -p "$pid" 2>/dev/null)" == Z* ]]; then
            wait "$pid"; local rc=$?
            _forget "$pid"
            fail_run "$run" "process ${RUN_OF[$pid]#"$run"/} (pid $pid) exited $rc before its time"
        fi
    done
}

# cluster_wait <run> <file>...: waits until every <run>/out/<file> exists.
cluster_wait() {
    local run="$1"; shift
    local deadline=$((SECONDS + WAIT_SECONDS)) f missing
    while :; do
        missing=""
        for f in "$@"; do
            [[ -e "$run/out/$f" ]] || { missing="$f"; break; }
        done
        [[ -z "$missing" ]] && return 0
        _check_live "$run"
        (( SECONDS > deadline )) && fail_run "$run" "no $missing within $WAIT_SECONDS s"
        sleep 0.1
    done
}

# cluster_peers <run> <voters> <id>...: waits for every member's port, then writes <run>/out/peers
# (a .tmp file renamed over it): 'voters <voters>' and '<id> <port>' per member.
cluster_peers() {
    local run="$1" voters="$2"; shift 2
    local id port ports=()
    for id in "$@"; do ports+=("$id.port"); done
    cluster_wait "$run" "${ports[@]}"
    {
        echo "voters $voters"
        for id in "$@"; do
            port="$(tr -d '[:space:]' < "$run/out/$id.port")"
            [[ "$port" =~ ^[1-9][0-9]*$ ]] || fail_run "$run" "$id wrote the port [$port]"
            echo "$id $port"
        done
    } > "$run/out/peers.tmp"
    mv "$run/out/peers.tmp" "$run/out/peers"
}

# cluster_kill <run> <id> <killed file>: kill -9 of that member's recorded PID (checked to be
# this shell's running child), reaped; then <run>/out/<killed file> names it.
cluster_kill() {
    local run="$1" id="$2" file="$3" pid
    pid="${PID_OF["$run/$id"]:-}"
    [[ -n "$pid" ]] || fail_run "$run" "no process for $id"
    _is_child "$pid" || fail_run "$run" "$id (pid $pid) is not running when it should be killed"
    kill -9 "$pid"
    wait "$pid" 2>/dev/null
    _forget "$pid"
    echo "$id" > "$run/out/$file"
}

# cluster_finish <run> <verifier>: once every worker is done, the verifier joins and reads the
# space (<run>/out/verify), then every member stops (<run>/out/stop); each must exit 0 within
# WAIT_SECONDS, or the test fails naming the member that hung.
cluster_finish() {
    local run="$1" verifier="$2" pid rc deadline
    : > "$run/out/verify"
    cluster_wait "$run" "$verifier.result"
    : > "$run/out/stop"
    deadline=$((SECONDS + WAIT_SECONDS))
    for pid in "${LIVE[@]}"; do
        while _is_child "$pid" && [[ "$(ps -o stat= -p "$pid" 2>/dev/null)" != Z* ]]; do
            (( SECONDS > deadline )) \
                && fail_run "$run" "${RUN_OF[$pid]#"$run"/} (pid $pid) did not exit within $WAIT_SECONDS s of stop"
            sleep 0.1
        done
        wait "$pid"; rc=$?
        _forget "$pid"
        [[ $rc -eq 0 ]] || fail_run "$run" "${RUN_OF[$pid]#"$run"/} exited $rc"
    done
}

# cluster_verify <run> <verifier> <worker>...: the correctness rules over the tokens. A worker
# named in a <run>/out/killed* file may have left a token attempted and never resolved, at most
# one (a worker commits one token at a time; proto_db asserts len(in_flight) <= 1): it counts as
# unknown. Any other worker resolved every token it attempted. Then: no token is both acked and
# unknown, and none is attempted twice; every acknowledged token is present; the counter equals
# the size of 'tokens' (no commit applied twice) and equals the acknowledged tokens plus the
# unknown tokens present (no token present that was not committed).
cluster_verify() {
    local run="$1" verifier="$2"; shift 2
    local o="$run/out" killed="" id counter count acked unknown present unk_present
    local kf
    for kf in "$o"/killed*; do
        [[ -e "$kf" ]] && killed+=" $(tr -d '[:space:]' < "$kf")"
    done
    killed="${killed# }"
    local v="$o/.verify"; mkdir -p "$v"
    : > "$v/attempt"; : > "$v/acked"; : > "$v/unknown"
    for id in "$@"; do
        local a="$o/$id.attempt" k="$o/$id.acked" u="$o/$id.unknown"
        [[ -e "$a" ]] || fail_run "$run" "$id attempted no commit"
        touch "$k" "$u"
        cat "$a" >> "$v/attempt"; cat "$k" >> "$v/acked"
        sort -u "$k" "$u" > "$v/resolved.$id"
        sort "$a" > "$v/attempt.$id"
        comm -13 "$v/attempt.$id" "$v/resolved.$id" | grep -q . \
            && fail_run "$run" "$id resolved a token it never attempted"
        if [[ " $killed " == *" $id "* ]]; then
            cat "$u" >> "$v/unknown"
            (( $(comm -23 "$v/attempt.$id" "$v/resolved.$id" | wc -l) <= 1 )) \
                || fail_run "$run" "$id, killed, left more than one token unresolved: $(comm -23 "$v/attempt.$id" "$v/resolved.$id" | tr '\n' ' ')"
            comm -23 "$v/attempt.$id" "$v/resolved.$id" >> "$v/unknown"
        else
            cat "$u" >> "$v/unknown"
            comm -23 "$v/attempt.$id" "$v/resolved.$id" | grep -q . \
                && fail_run "$run" "$id left tokens unresolved without being killed: $(comm -23 "$v/attempt.$id" "$v/resolved.$id" | tr '\n' ' ')"
        fi
    done
    [[ -z "$(sort "$v/attempt" | uniq -d)" ]] || fail_run "$run" "a token was attempted twice"
    sort -o "$v/acked" "$v/acked"; sort -o "$v/unknown" "$v/unknown"
    [[ -z "$(comm -12 "$v/acked" "$v/unknown")" ]] || fail_run "$run" "a token is both acked and unknown"
    read -r _ counter _ count < "$o/$verifier.result" || fail_run "$run" "unreadable $verifier.result"
    [[ "$counter" =~ ^[0-9]+$ && "$count" =~ ^[0-9]+$ ]] || fail_run "$run" "$verifier.result: $(cat "$o/$verifier.result")"
    sort "$o/$verifier.present" > "$v/present"
    local missing; missing="$(comm -23 "$v/acked" "$v/present" | tr '\n' ' ')"
    [[ -z "$missing" ]] || fail_run "$run" "acknowledged tokens are missing: $missing"
    acked="$(wc -l < "$v/acked")"; unknown="$(wc -l < "$v/unknown")"
    unk_present="$(comm -12 "$v/unknown" "$v/present" | wc -l)"
    present="$(wc -l < "$v/present")"
    [[ "$counter" -eq "$count" ]] || fail_run "$run" "counter $counter but $count tokens: a commit applied twice or lost"
    [[ "$counter" -eq $((acked + unk_present)) ]] \
        || fail_run "$run" "counter $counter != acked $acked + unknown present $unk_present ($present attempted tokens present)"
    echo "NOTE: $(basename "$run"): counter $counter = $acked acknowledged + $unk_present of $unknown unknown present${killed:+; $killed killed with kill -9}"
}
