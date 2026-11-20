#!/usr/bin/env bash
# Vendors the query vectors (indexed queries, plan Task 7, plan call IP11): runs
# tests/interop/py_query_vectors.py with proto_db at v2.0.0rc4 (the interop venv) into a new directory
# under tests/conformance/out/query-vectors (ignored by git), checks its manifest, and copies it to
# tests/conformance/vectors-queries/ (space/, queries.msgpack, manifest.sha256).
#
# The vectors are vendored once: proto_db draws random oids, so a second generation is equivalent
# but not byte-identical. When vectors-queries/ exists the script refuses and leaves both copies; to
# regenerate, move vectors-queries/ aside by hand first. Nothing is removed. Exit 77 without the
# interop venv (tests/interop/env.sh). Not a test: the runner never runs it.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=../interop/env.sh
source "$REPO/tests/interop/env.sh"
fail() { echo "fetch_query_vectors: $*" >&2; exit 1; }

DEST="$HERE/vectors-queries"
[[ -e "$DEST" ]] && fail "$DEST exists; the vectors are vendored once (move it aside by hand to regenerate)"
STAGE="$HERE/out/query-vectors/run-$$-$(date +%s%N)"
mkdir -p "$(dirname "$STAGE")" || fail "cannot create $(dirname "$STAGE")"
"$PY" "$REPO/tests/interop/py_query_vectors.py" "$STAGE" || fail "py_query_vectors.py failed"
(cd "$STAGE" && sha256sum --quiet -c manifest.sha256) || fail "the generated files do not match their manifest"
listed="$(cut -c67- "$STAGE/manifest.sha256" | sort)"
present="$(cd "$STAGE" && find . -type f ! -name manifest.sha256 | sed 's|^\./||' | sort)"
[[ "$listed" == "$present" ]] || fail "the manifest and the generated directory list different files"
cp -rp "$STAGE" "$DEST" || fail "cannot copy $STAGE to $DEST"
(cd "$DEST" && sha256sum --quiet -c manifest.sha256) || fail "the vendored copy does not match its manifest"
echo "vendored $(echo "$present" | wc -l) files to $DEST"
