# Sourced by interop tests. Sets PY, PYTHONPATH and PROTOST, or skips (exit 77) without the venv.
_interop_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -x "$_interop_dir/.venv/bin/python" || ! -d "$_interop_dir/.venv/protobase/proto_db" ]]; then
    echo "SKIP: venv missing (run tests/interop/setup_venv.sh)"
    exit 77
fi
export PY="$_interop_dir/.venv/bin/python"
export PYTHONPATH="$_interop_dir/.venv/protobase${PYTHONPATH:+:$PYTHONPATH}"
export PROTOST="${PROTOST:-protost}"
unset _interop_dir
