#!/usr/bin/env bash
# loop-status.sh — ¿hay un `loop.sh` VIVO en este workspace?
#
# ESTE ES EL COMANDO CANÓNICO. Toda sesión que necesite saber si el loop está
# corriendo —antes de tomar una feature `self_modifying`, antes de lanzar el
# loop, antes de editar `feature_list.json` a mano— pregunta acá:
#
#     bash <tooling-repo>/harness/loop-status.sh
#
# rc 0 = HAY un loop vivo.   rc 1 = NO hay.   (rc 2 = no se puede decidir.)
#
# POR QUÉ NO `pgrep`. El comando que se usaba antes,
# `pgrep -af "harness/loop[.]sh"`, matchea la línea de comando de cualquier
# proceso que CONTENGA esa cadena — incluida una sesión `claude -p` cuyo prompt
# la nombra como texto. Tres falsos positivos documentados (Sessions 186,
# 161-165 y 253; la última sin proceso padre: el patrón matcheó el prompt de la
# propia sesión que lo corría, que entonces frenó por un loop inexistente).
# La fuente de verdad es el lockfile que `loop.sh` toma al arrancar (D-HIG-2 del
# ADR infra/decisions/2026-08-10-higiene-harness-prio-loops.md, feature HIG-F2):
# un archivo que solo escribe el runner no se confunde con texto de un prompt.
#
# ESTE SCRIPT NO ARRANCA NADA. Es de solo lectura a propósito: el comando que
# las sesiones van a pegar cientos de veces no puede ser uno que, tipeado mal,
# lance un scheduler.
#
# EL `pgrep` SIGUE, COMO FALLBACK CRUZADO. Un loop lanzado con el `loop.sh`
# ANTERIOR a HIG-F2 no tiene lockfile, y un lockfile borrado a mano tampoco.
# Por eso acá se miden las DOS vías y se reporta la discrepancia en vez de
# esconderla. El patrón del fallback ancla al intérprete (`bash … loop.sh`) y
# descarta las líneas `claude`, que son sesiones, nunca el runner.
#
# LA PREGUNTA ES POR ESTE WORKSPACE, NO POR LA MÁQUINA (TPL-F6). Desde que hay
# una plantilla (`harness-core`), una misma máquina corre VARIOS loops, uno por
# app (`~/gosjoseph`, `~/kayzen`, …). El lock ya era por workspace, pero el
# fallback matcheaba cualquier `bash …/loop.sh` del host: con un solo loop vivo
# en Gosjoseph, la sesión de Kayzen leía «hay loop vivo» y no podía tomar
# features `self_modifying`. Ahora las DOS vías se anclan al workspace:
#   - el lock tiene que declarar `workspace=` igual a ESTE workspace;
#   - cada candidato del fallback se atribuye a un workspace por su argv
#     absoluto o, si el argv es relativo (el caso normal), por el **cwd** del
#     proceso (`/proc/<pid>/cwd` en Linux, `lsof -d cwd` como respaldo) —
#     `loop.sh` hace `cd "$WORKSPACE"` antes de nada, así que su cwd ES el
#     workspace.
# Un candidato cuyo workspace NO se puede determinar (sin `/proc`, sin `lsof`,
# proceso de otro usuario) NO se descarta: se cuenta y se reporta aparte. La
# respuesta conservadora sigue existiendo donde falta información; lo que deja
# de existir es la conservadora ante información que SÍ distingue.
set -uo pipefail

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK="${LOOP_LOCK:-$HARNESS/.loop.lock}"

# Raíz del workspace de ESTE harness: <WS>/<app>_tooling/harness/loop-status.sh
# → dos niveles arriba del directorio del script. Se resuelve por la UBICACIÓN
# del script y no por el CWD de quien lo corre (una sesión puede invocarlo
# desde cualquier subdirectorio), y se canonicaliza con `pwd -P` para que la
# comparación contra el `workspace=` del lock y contra el cwd de un runner sea
# exacta y no dependa de symlinks.
SELF_WS="${LOOP_WORKSPACE:-$(cd "$HARNESS/../.." && pwd -P)}"

lock_start_time() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//; s/ *$//'; }
lock_field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1; }

canon() { [ -n "$1" ] && (cd "$1" 2>/dev/null && pwd -P); }

# ¿El path pertenece a este workspace? Igualdad o descendiente, nunca substring.
is_self_ws() {
  case "$1" in
    "$SELF_WS"|"$SELF_WS"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# cwd de un proceso ajeno. Linux: /proc. macOS / sin /proc legible: lsof.
# Devuelve vacío si no se puede saber — el llamador NO lo interpreta como
# "ajeno", lo trata como no atribuible.
proc_cwd() {
  local pid="$1" c=""
  c="$(readlink -f "/proc/$pid/cwd" 2>/dev/null)"
  if [ -z "$c" ] && command -v lsof >/dev/null 2>&1; then
    c="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1)"
  fi
  printf '%s' "$c"
}

# Workspace deducido del argv, cuando el runner fue lanzado con path ABSOLUTO
# (`bash /home/x/ws/app_tooling/harness/loop.sh`): tres niveles arriba del .sh.
argv_ws() {
  local tok
  for tok in $1; do
    case "$tok" in
      /*loop.sh) canon "$(dirname "$tok")/../.."; return ;;
    esac
  done
}

# Fallback: procesos cuyo argv es un intérprete corriendo un .../loop.sh. El
# `[.]` evita que el propio grep se matchee a sí mismo; el filtro `claude` saca
# las sesiones headless cuyo PROMPT nombra el archivo.
pgrep_fallback() {
  ps -eo pid=,args= 2>/dev/null \
    | grep -E '(^|/| )(ba)?sh( +-[^ ]+)* +[^ ]*loop[.]sh( |$)' \
    | grep -v 'claude' \
    | grep -v 'loop-status[.]sh' \
    | sed 's/^ *//'
}

# Clasificación de los candidatos por workspace: propios / de otro workspace /
# no atribuibles. Solo los dos primeros grupos se pueden decidir; el tercero se
# cuenta como propio por conservadurismo y se reporta como tal.
FALLBACK_MINE=""
FALLBACK_OTHER=""
FALLBACK_UNKNOWN=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  cand_pid="${line%% *}"
  cand_args="${line#* }"
  cand_ws="$(argv_ws "$cand_args")"
  [ -z "$cand_ws" ] && cand_ws="$(proc_cwd "$cand_pid")"
  if [ -z "$cand_ws" ]; then
    FALLBACK_UNKNOWN="$FALLBACK_UNKNOWN$line"$'\n'
  elif is_self_ws "$cand_ws"; then
    FALLBACK_MINE="$FALLBACK_MINE$line"$'\n'
  else
    FALLBACK_OTHER="$FALLBACK_OTHER$line   [workspace: $cand_ws]"$'\n'
  fi
done <<EOF
$(pgrep_fallback)
EOF

count_lines() { [ -n "$1" ] && printf '%s' "$1" | grep -c '' || echo 0; }
MINE_N="$(count_lines "$FALLBACK_MINE")"
OTHER_N="$(count_lines "$FALLBACK_OTHER")"
UNKNOWN_N="$(count_lines "$FALLBACK_UNKNOWN")"
FALLBACK_N=$((MINE_N + UNKNOWN_N))

RC=1
if [ ! -f "$LOCK" ]; then
  echo "lock: ausente ($LOCK) — ningún loop lo tomó"
else
  LOCK_WS="$(lock_field "$LOCK" workspace)"
  OWNER="$(lock_field "$LOCK" pid)"
  OWNER_START="$(lock_field "$LOCK" pid_start_time)"
  # Un lock SIN campo `workspace=` es un lock previo a TPL-F6: se asume propio
  # (está dentro de este harness) en vez de descartarlo — degradar a "ajeno"
  # convertiría un loop viejo realmente vivo en invisible.
  if [ -n "$LOCK_WS" ] && ! is_self_ws "$LOCK_WS"; then
    # Lock de OTRO workspace (p. ej. un LOOP_LOCK apuntado a mano, o un
    # harness mal copiado): no dice nada sobre el loop de ESTE workspace.
    echo "lock: de OTRO workspace ($LOCK declara workspace=$LOCK_WS, este es $SELF_WS) — no cuenta acá"
  elif [ -z "$OWNER" ] || [ -z "$OWNER_START" ]; then
    echo "lock: ILEGIBLE o incompleto ($LOCK) — no se puede decidir; revisalo a mano"
    RC=2
  else
    NOW="$(lock_start_time "$OWNER")"
    if [ -n "$NOW" ] && [ "$NOW" = "$OWNER_START" ]; then
      echo "lock: VIVO — PID $OWNER (arrancado $OWNER_START)"
      echo "      started_at=$(lock_field "$LOCK" started_at)  log=$(lock_field "$LOCK" log)"
      RC=0
    else
      # Huérfano: el próximo `loop.sh` lo descarta solo, no hay que limpiarlo.
      echo "lock: HUÉRFANO — PID $OWNER ya no existe (o el PID fue reciclado); no bloquea"
    fi
  fi
fi

echo "fallback (ps|grep, anclado a ESTE workspace $SELF_WS): $FALLBACK_N proceso(s)"
[ -n "$FALLBACK_MINE" ] && printf '%s' "$FALLBACK_MINE" | sed 's/^/  /'
if [ -n "$FALLBACK_UNKNOWN" ]; then
  echo "  no atribuibles a ningún workspace (sin /proc ni lsof, u otro usuario) — contados como propios:"
  printf '%s' "$FALLBACK_UNKNOWN" | sed 's/^/    /'
fi
if [ -n "$FALLBACK_OTHER" ]; then
  echo "  descartados: $OTHER_N runner(s) de OTRO workspace (no dicen nada sobre este):"
  printf '%s' "$FALLBACK_OTHER" | sed 's/^/    /'
fi

# Discrepancia: el fallback ve un runner DE ESTE WORKSPACE que el lock no
# explica. Puede ser un loop lanzado con el `loop.sh` previo a HIG-F2, o un
# lockfile borrado a mano. Se reporta y se toma la respuesta CONSERVADORA.
if [ "$RC" -ne 0 ] && [ "$FALLBACK_N" -gt 0 ]; then
  echo "⚠️  DISCREPANCIA: el lock no marca dueño vivo pero hay $FALLBACK_N proceso(s) de este workspace que parecen un runner."
  echo "   Causas típicas: loop lanzado con el loop.sh anterior a HIG-F2 (sin lock), o lockfile borrado a mano."
  echo "   Se asume LOOP VIVO (respuesta conservadora). Verificá el PID de arriba antes de arrancar nada."
  RC=0
fi

case "$RC" in
  0) echo "→ HAY un loop vivo. NO lances otro; NO tomes features self_modifying." ;;
  1) echo "→ NO hay loop vivo." ;;
  *) echo "→ INDECIDIBLE. Tratalo como 'hay loop vivo' hasta resolverlo a mano." ;;
esac
exit "$RC"
