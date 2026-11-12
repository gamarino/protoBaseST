#!/usr/bin/env bash
# Helper (never run as a test): ProtoBase's verifier (py_verify.py, the ERP types registered)
# over the space in $1; its exit status is this script's. Exit 77 without the interop venv
# (tests/interop/env.sh).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ $# -eq 1 ]] || { echo "usage: _verify_space.sh <directory>" >&2; exit 1; }
# shellcheck source=env.sh
source "$HERE/env.sh"
"$PY" "$HERE/py_verify.py" "$1"
