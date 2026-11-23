#!/usr/bin/env bash
# Corre cada ejercicio y compara su salida con esperado/NN.out.
# Las líneas que empiezan con "~" son mediciones (tiempos, reintentos, caminos) y no se comparan.
# Un ejercicio que termina con 77 se saltea (el 6 sin el venv de Python).
# Uso: ./verificar.sh                      (usa el protost del PATH)
#      PROTOST=/ruta/protost ./verificar.sh
# Las bases de los ejercicios quedan en $TALLER_DIR (por omisión, un directorio nuevo de mktemp).
set -u
cd "$(dirname "$0")"
PROTOST="${PROTOST:-protost}"
export PROTOST
REPO="$(cd ../../../.. && pwd)"
export STPATH="$REPO/src${STPATH:+:$STPATH}"
export TALLER_DIR="${TALLER_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/taller-protobasest-XXXXXX")}"
mkdir -p "$TALLER_DIR"
"$PROTOST" --version
echo "bases en $TALLER_DIR"
fallas=0
salteados=0
for f in [0-9][0-9]-*.st [0-9][0-9]-*.sh; do
  [ -e "$f" ] || continue
  n="${f%%-*}"
  case "$f" in
    *.st) got="$("$PROTOST" "$f" 2>&1)"; st=$? ;;
    *.sh) got="$(./"$f" 2>&1)"; st=$? ;;
  esac
  if [ "$st" -eq 77 ]; then
    echo "salteado $f: $(echo "$got" | tail -n 1)"
    salteados=$((salteados + 1))
    continue
  fi
  got="$(echo "$got" | grep -v '^~' | tr -d '\r')"
  if [ "$st" -eq 0 ] && [ "$got" == "$(tr -d '\r' < "esperado/$n.out")" ]; then
    echo "ok       $f"
  else
    echo "DIFIERE  $f (salida $st)"
    diff <(echo "$got") <(tr -d '\r' < "esperado/$n.out") | head -20
    fallas=$((fallas + 1))
  fi
done
if [ "$fallas" -eq 0 ]; then
  echo "todos los ejercicios dan lo esperado ($salteados salteados)"
else
  echo "$fallas ejercicio(s) difieren"
fi
exit "$fallas"
