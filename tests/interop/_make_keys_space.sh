#!/usr/bin/env bash
# Helper (never run as a test): writes the cross-kind keys space with ProtoBase into $1.
# Exit 77 without the interop venv (tests/interop/env.sh), 0 when written, 1 otherwise.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ $# -eq 1 ]] || { echo "usage: _make_keys_space.sh <directory>" >&2; exit 1; }
# shellcheck source=env.sh
source "$HERE/env.sh"
rm -rf "$1"
"$PY" "$HERE/py_make_keys_space.py" "$1"
