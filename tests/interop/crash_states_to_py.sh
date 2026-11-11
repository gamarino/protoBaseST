#!/usr/bin/env bash
# Crash states handed to both readers (plan Task 17 review, I3). For each state, protoST
# writes a space (_st_write_space.st create, epoch 2) and then leaves the state a crash leaves,
# through the seams of tests/unit/_seams.st (a prefix written, then the write fails): a torn
# record, a torn segment header, a torn space.root.tmp, an unsynced tail of unpublished
# records. Then ProtoBase's verifier must exit 0 and ProtoBase must read the space at epoch 2
# as written; ProtoBase commits on top, protoST commits on top of that, the verifier exits 0
# again and its dump equals protoST's; ProtoBase reads both commits. Exit 77 without the
# interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src:$REPO/tests/unit${STPATH:+:$STPATH}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

for state in record header roottmp tail; do
    SPACE="$TMP/$state"
    (cd "$HERE" && "$PROTOST" _st_write_space.st create "$SPACE" "$TMP/$state-create.json" > /dev/null) \
        || fail "$state: _st_write_space.st create exited $?"
    (cd "$HERE" && "$PROTOST" _st_write_space.st "crash-$state" "$SPACE" > /dev/null) \
        || fail "$state: _st_write_space.st crash-$state exited $?"
    case $state in
        roottmp) [[ -s "$SPACE/space.root.tmp" ]] || fail "$state: no torn space.root.tmp on disk" ;;
        header) find "$SPACE" -name '*.seg' -size 11c | grep -q . || fail "$state: no torn segment header on disk" ;;
    esac
    "$PY" -m proto_db.tools.verify "$SPACE" > /dev/null || fail "$state: ProtoBase's verifier exited $? on the crash state"
    "$PY" "$HERE/py_extend_st_space.py" check-create "$SPACE" || fail "$state: ProtoBase reads the space at epoch 2"
    "$PY" "$HERE/py_extend_st_space.py" commit "$SPACE" || fail "$state: ProtoBase commits on top"
    (cd "$HERE" && "$PROTOST" _st_write_space.st extend "$SPACE" "$TMP/st-$state.json" > /dev/null) \
        || fail "$state: protoST commits on top"
    "$PY" -m proto_db.tools.verify "$SPACE" --out "$TMP/py-$state.json" > /dev/null || fail "$state: ProtoBase's verifier exited $? after the commits"
    "$PY" "$HERE/compare_dumps.py" "$TMP/py-$state.json" "$TMP/st-$state.json" --exact > /dev/null || fail "$state: the dumps differ"
    "$PY" "$HERE/py_extend_st_space.py" check-extend "$SPACE" || fail "$state: ProtoBase reads both commits"
    echo "$state: both readers recover"
done
echo "crash states ok"
