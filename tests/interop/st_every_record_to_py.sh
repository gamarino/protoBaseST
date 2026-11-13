#!/usr/bin/env bash
# Every record protoST writes is readable by ProtoBase (review C1 of the commit performance
# work): protoST commits a broad workload over several segments, and its saves refuse the values
# a reader accepts but a writer must refuse (a format-3 zone datetime, an instant within a day of
# year 1) when they are copied forward from records written raw by a format-3 writer. ProtoBase
# then reads and decodes every record of every segment but those two raw ones (no
# ProtoCorruptionError, nothing else raised), and its verifier accepts the space. Exit 77
# without the interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
SPACE="$TMP/space"

out="$(cd "$HERE" && "$PROTOST" _st_every_record.st "$SPACE" "$TMP/records.txt")" || fail "_st_every_record.st exited $?: $out"
[[ "$out" == "written" ]] || fail "_st_every_record.st printed: $out"
[[ "$(find "$SPACE" -name '*.seg' | wc -l)" -gt 1 ]] || fail "the space should span several segments"
"$PY" "$HERE/py_every_record.py" "$SPACE" "$TMP/records.txt" || fail "ProtoBase cannot read every record protoST wrote"
"$PY" -m proto_db.tools.verify "$SPACE" --out "$TMP/verify.json" > /dev/null || fail "ProtoBase's verifier rejects the space"
exit 0
