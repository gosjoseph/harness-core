#!/usr/bin/env bash
# render.sh — sustituye las variables __NOMBRE__ de PARAMS.md en un árbol de
# archivos. Es la simulación mínima de lo que hará bootstrap.sh (repo aparte,
# TPL-F2): copia src -> dst y aplica sed con el mapa de variables recibido
# como pares NOMBRE=valor en argv. Uso interno de tests/run-tests.sh, pero
# vive en su propio archivo para no mezclar "cómo se genera" con "qué se
# prueba".
set -euo pipefail

src="$1"; dst="$2"; shift 2

mkdir -p "$dst"
cp -a "$src/." "$dst/"

for pair in "$@"; do
  name="${pair%%=*}"
  value="${pair#*=}"
  # -print0/xargs para no romper con nombres de archivo con espacios (no los
  # hay en este repo, pero el patrón es correcto igual).
  find "$dst" -type f -print0 | xargs -0 sed -i "s#__${name}__#${value}#g"
done
