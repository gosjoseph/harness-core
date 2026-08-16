#!/usr/bin/env bash
# render.sh — sustituye las variables __NOMBRE__ de PARAMS.md en un árbol de
# archivos: copia src -> dst y aplica sed con el mapa de variables recibido
# como pares NOMBRE=valor en argv. GENÉRICO, sin dependencia de ningún
# proyecto concreto. Lo usan tanto `bootstrap.sh` (generación real) como
# `tests/run-tests.sh` (sandbox de prueba) — vive en `scripts/` en vez de
# `tests/` justamente porque no es exclusivo del test suite.
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
