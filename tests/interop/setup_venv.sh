#!/usr/bin/env bash
# Creates the Python side of the interop tests (plan call C9). Idempotent.
#
#   tests/interop/.venv/            venv made with --system-site-packages
#   tests/interop/.venv/protobase/  proto_db extracted with `git archive v2.0.0rc4`
#
# msgpack==1.2.4 is installed only when the import is missing or another version: ProtoBase
# v2.0.0rc4 (as since v2.0.0rc2) needs msgpack >= 1.2.0 (its packer writes the 1024 containers of a record holding a
# value of MAX_VALUE_DEPTH; format spec, 'Value nesting depth') and runs with msgpack's C
# extension (its pure-Python fallback recurses per container). That is the only use of the
# network. proto_db v2.0.0rc4 requires Python 3.12 or newer. Environment: PYTHON (default
# python3), PROTOBASE_REPO (default ../ProtoBase).
set -euo pipefail

TAG="v2.0.0rc4"
TAG_COMMIT="8e6127f"
MSGPACK_VERSION="1.2.4"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${PROTOBASE_REPO:-$HERE/../../../ProtoBase}"
VENV="$HERE/.venv"
PYTHON="${PYTHON:-python3}"

die() { echo "setup_venv: $*" >&2; exit 1; }

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

if ! "$PY" -c "import msgpack, sys; sys.exit(0 if msgpack.version == tuple(int(p) for p in '$MSGPACK_VERSION'.split('.')) else 1)" 2>/dev/null; then
    "$PY" -m pip install --quiet "msgpack==$MSGPACK_VERSION"
fi

if [[ "$(cat "$VENV/protobase/.commit" 2>/dev/null || true)" != "$full" ]]; then
    rm -rf "$VENV/protobase"
    mkdir -p "$VENV/protobase"
    git -C "$SRC" archive "$TAG" proto_db | tar -x -C "$VENV/protobase"
    echo "$full" > "$VENV/protobase/.commit"
fi

"$PY" -c "import msgpack._cmsgpack" 2>/dev/null || die "msgpack's C extension does not import (ProtoBase needs it)"
PYTHONPATH="$VENV/protobase" "$PY" -c "import proto_db, msgpack; print('venv ok: msgpack', msgpack.version, 'proto_db from', proto_db.__file__)"
