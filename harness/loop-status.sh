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
set -uo pipefail

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK="${LOOP_LOCK:-$HARNESS/.loop.lock}"

lock_start_time() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//; s/ *$//'; }
lock_field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1; }

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

FALLBACK="$(pgrep_fallback)"
FALLBACK_N=0
[ -n "$FALLBACK" ] && FALLBACK_N="$(printf '%s\n' "$FALLBACK" | wc -l | tr -d ' ')"

RC=1
if [ ! -f "$LOCK" ]; then
  echo "lock: ausente ($LOCK) — ningún loop lo tomó"
else
  OWNER="$(lock_field "$LOCK" pid)"
  OWNER_START="$(lock_field "$LOCK" pid_start_time)"
  if [ -z "$OWNER" ] || [ -z "$OWNER_START" ]; then
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

echo "fallback (ps|grep, ancla al intérprete): $FALLBACK_N proceso(s)"
[ -n "$FALLBACK" ] && printf '  %s\n' "$FALLBACK"

# Discrepancia: el fallback ve un runner que el lock no explica. Puede ser un
# loop lanzado con el `loop.sh` previo a HIG-F2, o un lockfile borrado a mano.
# Se reporta y se toma la respuesta CONSERVADORA (hay loop vivo).
if [ "$RC" -ne 0 ] && [ "$FALLBACK_N" -gt 0 ]; then
  echo "⚠️  DISCREPANCIA: el lock no marca dueño vivo pero hay $FALLBACK_N proceso(s) que parecen un runner."
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
