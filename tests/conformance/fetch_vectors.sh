#!/usr/bin/env bash
# Vendors ProtoBase's conformance vectors (plan call C8).
#
# Extracts tests/conformance/ of $PROTOBASE_REPO (default ../ProtoBase) at the tag v2.0.0rc1
# into this directory, keeping manifest.json, vectors.sha256, vectors/**, README.md and
# .gitattributes. The Python files (generate.py, test_conformance.py, model.py, typed.py,
# __init__.py) are not vendored. Refuses unless sha256sum of vectors.sha256 equals the pinned
# digest and every listed file matches, and no vector file is unlisted.
set -euo pipefail

TAG="v2.0.0rc1"
PINNED="5f86eb09ed1683aa9f048051c64cca68d23b9fb753e87416cb1ecf11ed406df0"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${PROTOBASE_REPO:-$HERE/../../../ProtoBase}"

die() { echo "fetch_vectors: $*" >&2; exit 1; }

[[ -d "$SRC" ]] || die "ProtoBase repository not found: $SRC (set PROTOBASE_REPO)"
git -C "$SRC" rev-parse --verify --quiet "$TAG^{commit}" >/dev/null || die "tag $TAG not found in $SRC"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
git -C "$SRC" archive "$TAG" tests/conformance | tar -x -C "$STAGE"
CONF="$STAGE/tests/conformance"

actual="$(sha256sum "$CONF/vectors.sha256" | cut -d' ' -f1)"
[[ "$actual" == "$PINNED" ]] || die "vectors.sha256 digest is $actual, expected $PINNED"
(cd "$CONF/vectors" && sha256sum --quiet -c ../vectors.sha256) || die "a vector file does not match vectors.sha256"
listed="$(cut -c67- "$CONF/vectors.sha256" | grep -vx "../manifest.json" | sort)"
present="$(cd "$CONF/vectors" && find . -type f | sed 's|^\./||' | sort)"
[[ "$listed" == "$present" ]] || die "vectors/ and vectors.sha256 list different files"

rm -rf "$HERE/vectors"
cp -p "$CONF/manifest.json" "$CONF/vectors.sha256" "$CONF/README.md" "$CONF/.gitattributes" "$HERE/"
cp -rp "$CONF/vectors" "$HERE/vectors"
echo "digest ok ($(echo "$present" | wc -l) vector files)"
