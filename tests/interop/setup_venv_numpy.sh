#!/usr/bin/env bash
# Creates the second Python environment of the interop tests, proto_db in its default mode (vectors
# phase V5, Addendum V 5.2). Idempotent.
#
#   tests/interop/.venv-numpy/            venv made with --system-site-packages, as .venv is
#   tests/interop/.venv-numpy/protobase/  proto_db extracted with `git archive v2.0.0rc4`
#
# It differs from the reference venv (setup_venv.sh) by one package: numpy==2.3.5, a release with
# CPython 3.14 wheels, installed when the import is missing or another version. With numpy
# importable, proto_db takes its numpy paths (numpy_module(), vector_backends.py:278-287): IVF
# training by numpy's k-means and numpy screening in exact search. Scripts that need proto_db's
# default mode (tests/interop/vector_both_directions.sh; the default mode of the vector
# benchmarks) use it; every other interop script uses the reference venv, where the generators
# block numpy anyway. hnswlib is not installed: protoBaseST refuses hnsw search (deviation DV1),
# and maintaining an hnsw index never imports it. msgpack==1.2.4 is installed as setup_venv.sh
# installs it. Those two packages are the only use of the network. Nothing is ever deleted: a
# proto_db extraction of another commit is moved aside (protobase.replaced-<time>) before the new
# one is written. proto_db v2.0.0rc4 requires Python 3.12 or newer. Environment: PYTHON (default
# python3), PROTOBASE_REPO (default ../ProtoBase).
set -euo pipefail

TAG="v2.0.0rc4"
TAG_COMMIT="8e6127f"
MSGPACK_VERSION="1.2.4"
NUMPY_VERSION="2.3.5"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${PROTOBASE_REPO:-$HERE/../../../ProtoBase}"
VENV="$HERE/.venv-numpy"
PYTHON="${PYTHON:-python3}"

die() { echo "setup_venv_numpy: $*" >&2; exit 1; }

command -v "$PYTHON" >/dev/null 2>&1 || die "Python not found: $PYTHON (set PYTHON)"
"$PYTHON" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)' \
    || die "Python 3.12 or newer is required ($("$PYTHON" -V 2>&1))"

[[ -d "$SRC" ]] || die "ProtoBase repository not found: $SRC (set PROTOBASE_REPO)"
full="$(git -C "$SRC" rev-parse --verify --quiet "$TAG^{commit}")" || die "tag $TAG not found in $SRC"
[[ "$full" == "$TAG_COMMIT"* ]] || die "$TAG resolves to ${full:0:7}, expected $TAG_COMMIT"

if [[ ! -x "$VENV/bin/python" ]]; then
    "$PYTHON" -m venv --system-site-packages "$VENV"
fi
PY="$VENV/bin/python"

version_is() {
    "$PY" -c "import $1, sys; sys.exit(0 if tuple(int(p) for p in str($1.$2).split('.')[:3]) == tuple(int(p) for p in '$3'.split('.')) else 1)" 2>/dev/null
}
version_is msgpack version "$MSGPACK_VERSION" || "$PY" -m pip install --quiet "msgpack==$MSGPACK_VERSION"
version_is numpy __version__ "$NUMPY_VERSION" || "$PY" -m pip install --quiet "numpy==$NUMPY_VERSION"

if [[ "$(cat "$VENV/protobase/.commit" 2>/dev/null || true)" != "$full" ]]; then
    if [[ -e "$VENV/protobase" ]]; then
        mv "$VENV/protobase" "$VENV/protobase.replaced-$(date +%s%N)"
    fi
    mkdir -p "$VENV/protobase"
    git -C "$SRC" archive "$TAG" proto_db | tar -x -C "$VENV/protobase"
    echo "$full" > "$VENV/protobase/.commit"
fi

"$PY" -c "import msgpack._cmsgpack" 2>/dev/null || die "msgpack's C extension does not import (proto_db needs it)"
PYTHONPATH="$VENV/protobase" "$PY" -c "
import msgpack, numpy, proto_db
from proto_db.indexing.vector_backends import numpy_module
assert numpy_module() is not None, 'proto_db does not see numpy'
print('venv-numpy ok: msgpack', msgpack.version, 'numpy', numpy.__version__, 'proto_db from', proto_db.__file__)"
