#!/usr/bin/env bash
# Ejercicio 6 — Un directorio, dos lenguajes.
#
# protoST crea una base (_06-escribir.st); proto_db, en Python, la lee, consulta por el índice
# que hizo protoST y confirma un socio y una etiqueta (_06-python.py); el verificador de proto_db
# acepta el directorio; protoST lee lo de Python y combina una etiqueta propia (_06-leer.st).
# Antes de correrlo, anoten:
#   a) ¿qué plan usa Python para buscar los socios de Córdoba, si el índice lo escribió protoST?
#   b) ¿de qué clase es, en protoST, el socio que creó Python?
#   c) las dos etiquetas se escribieron a ciegas, una en cada lenguaje: ¿quedan las dos?
#
# Necesita el proto_db fijado en tests/interop/.venv del repositorio (tests/interop/setup_venv.sh,
# con PROTOBASE_REPO apuntando a un clon de github.com/gamarino/ProtoDB). Sin él, el ejercicio se
# saltea (salida 77), como los tests de interoperación.
# Uso: PROTOST=/ruta/protost ./06-python-y-smalltalk.sh
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
# shellcheck source=../../../../tests/interop/env.sh
source "$REPO/tests/interop/env.sh"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
BASE="${TALLER_DIR:-${TMPDIR:-/tmp}}"
mkdir -p "$BASE"
WORK="$(mktemp -d "$BASE/taller-06-XXXXXX")"
cd "$HERE"

"$PROTOST" _06-escribir.st "$WORK/espacio"
"$PY" _06-python.py "$WORK/espacio"
if "$PY" -m proto_db.tools.verify "$WORK/espacio" > "$WORK/verificador.txt" 2>&1; then
    echo "el verificador de proto_db acepta el directorio"
else
    echo "el verificador de proto_db rechazó el directorio:"; cat "$WORK/verificador.txt"; exit 1
fi
"$PROTOST" _06-leer.st "$WORK/espacio"
echo "~ el directorio queda en $WORK"
