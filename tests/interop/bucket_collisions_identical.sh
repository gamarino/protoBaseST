#!/usr/bin/env bash
# Task 16 review M2: buckets holding several entries are built as ProtoBase builds them. Both
# sides force every key into one bucket through their bucket-hash seam (ProtoBase
# _bucket_hash, protoBaseST _bucketHash:), run the same HashDictionary and Set operations
# (adds, a replace in the middle keeping the stored key, removals from the middle and of the
# last entries) and print, after each one, the count, the node's hash and the bucket tuple's
# encoded bytes. The lines must be identical. Exit 77 without the interop venv.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

(cd "$HERE" && "$PROTOST" _st_bucket_collisions.st > "$TMP/st.txt") || fail "_st_bucket_collisions.st exited $?"
"$PY" "$HERE/py_bucket_collisions.py" > "$TMP/py.txt" || fail "py_bucket_collisions.py exited $?"
[[ $(wc -l < "$TMP/py.txt") -eq 21 ]] || fail "ProtoBase printed $(wc -l < "$TMP/py.txt") lines, not 21"
diff "$TMP/py.txt" "$TMP/st.txt" > "$TMP/diff.txt" || fail "the buckets differ from ProtoBase's: $(head -c 2000 "$TMP/diff.txt")"
echo "buckets identical to ProtoBase"
