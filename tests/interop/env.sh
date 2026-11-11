# Sourced by interop tests. Sets PY, PYTHONPATH and PROTOST, or skips (exit 77) without the venv;
# a venv that holds another ProtoBase than setup_venv.sh pins fails (exit 1).
_interop_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -x "$_interop_dir/.venv/bin/python" || ! -d "$_interop_dir/.venv/protobase/proto_db" ]]; then
    echo "SKIP: venv missing (run tests/interop/setup_venv.sh)"
    exit 77
fi
# The venv must hold the ProtoBase that setup_venv.sh pins: a stale one fails, never runs silently.
_pinned="$(sed -n 's/^TAG_COMMIT="\(.*\)"$/\1/p' "$_interop_dir/setup_venv.sh")"
_held="$(cat "$_interop_dir/.venv/protobase/.commit" 2>/dev/null || true)"
if [[ -z "$_pinned" || "$_held" != "$_pinned"* ]]; then
    echo "FAIL: the interop venv holds ProtoBase ${_held:-of unknown commit}, not $_pinned (run tests/interop/setup_venv.sh)"
    exit 1
fi
unset _pinned _held
export PY="$_interop_dir/.venv/bin/python"
export PYTHONPATH="$_interop_dir/.venv/protobase${PYTHONPATH:+:$PYTHONPATH}"
export PROTOST="${PROTOST:-protost}"
unset _interop_dir
