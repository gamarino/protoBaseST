#!/usr/bin/env bash
# Design spec 10.3, protoST to Python, for the file storage's write side (plan Task 17), and
# the shared directory both ways. protoST writes a space through PBFileStorage (its own
# segment, the root published under the root lock); ProtoBase's verifier must accept it (exit
# 0: every record decoded, canonical and valid) and dump what protoST dumps. ProtoBase then
# commits on top of it (its own segment), protoST commits on top of that, and the verifier
# runs again. Last, the root lock: while ProtoBase holds it, protoST's tryLockRoot answers
# false; once released, true. Every step is ordered by the processes' own output, never by
# time. Exit 77 without the interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
TMP="$(mktemp -d)"
HOLDER_PID=""
cleanup() {
    [[ -n "$HOLDER_PID" ]] && kill "$HOLDER_PID" 2>/dev/null
    rm -rf "$TMP"
}
trap cleanup EXIT
fail() { echo "FAIL: $*"; exit 1; }
SPACE="$TMP/space"

verify_and_compare() {  # $1: a label
    "$PY" -m proto_db.tools.verify "$SPACE" --out "$TMP/py-$1.json" || fail "$1: ProtoBase's verifier exited $?"
    "$PY" "$HERE/compare_dumps.py" "$TMP/py-$1.json" "$TMP/st-$1.json" --exact || fail "$1: the dumps differ"
}

(cd "$HERE" && "$PROTOST" _st_write_space.st create "$SPACE" "$TMP/st-create.json") || fail "_st_write_space.st create exited $?"
verify_and_compare create
"$PY" "$HERE/py_extend_st_space.py" check-create "$SPACE" || fail "ProtoBase reads protoST's space"

"$PY" "$HERE/py_extend_st_space.py" commit "$SPACE" || fail "ProtoBase commits on protoST's space"
(cd "$HERE" && "$PROTOST" _st_write_space.st extend "$SPACE" "$TMP/st-extend.json") || fail "_st_write_space.st extend exited $?"
verify_and_compare extend
"$PY" "$HERE/py_extend_st_space.py" check-extend "$SPACE" || fail "ProtoBase reads protoST's commit on top of its own"
segments=$(find "$SPACE" -name '*.seg' | wc -l)
[[ "$segments" -eq 3 ]] || fail "expected 3 segments (protoST, ProtoBase, protoST), found $segments"

# The root lock: ProtoBase holds it until its stdin closes.
mkfifo "$TMP/hold-in" "$TMP/hold-out"
"$PY" "$HERE/py_extend_st_space.py" hold-lock "$SPACE" < "$TMP/hold-in" > "$TMP/hold-out" &
HOLDER_PID=$!
exec 3> "$TMP/hold-in"
read -r line < "$TMP/hold-out"
[[ "$line" == "locked" ]] || fail "the lock holder printed [$line]"
got="$(cd "$HERE" && "$PROTOST" _st_write_space.st trylock "$SPACE" | tail -n 1)"
[[ "$got" == "false" ]] || fail "tryLockRoot while ProtoBase holds the lock answered [$got]"
exec 3>&-
wait "$HOLDER_PID" || fail "the lock holder exited $?"
HOLDER_PID=""
got="$(cd "$HERE" && "$PROTOST" _st_write_space.st trylock "$SPACE" | tail -n 1)"
[[ "$got" == "true" ]] || fail "tryLockRoot after ProtoBase released the lock answered [$got]"
echo "protoST to Python ok"
