#!/usr/bin/env bash
# loop.sh — runner del loop autónomo del harness __PROJECT_NAME__ (Lecture 13, nivel 4).
#
# QUÉ HACE UNA ITERACIÓN:
#   1. init.sh (baseline)  2. claude -p con prompts/implementer.md (sesión FRESCA)
#   3. claude -p con prompts/verifier.md (sesión FRESCA, independiente)
#   4. relee feature_list.json y evalúa las stopping conditions de GOAL.md.
#
# POR QUÉ SESIÓN FRESCA POR PASO: la regla no negociable del curso es que nunca
# la misma entidad escribe y califica. Dos `claude -p` separados son dos
# contextos distintos; un solo proceso largo no lo sería. El estado vive en
# feature_list.json y claude-progress.md, no en el contexto.
#
# EL RUNNER NO EDITA feature_list.json. Solo lo lee. Mover estados es trabajo
# de los agentes bajo sus prompts (y `passing` solo lo da el verifier).
#
# COSTO CERO: es bash + el CLI ya instalado. No hay scheduler pago.
#
# SINGLE-INSTANCE: un solo loop por workspace, garantizado por lockfile.
# Lanzarlo dos veces hace que el SEGUNDO salga con rc 8 sin tocar nada. Ese
# lockfile es también la fuente de verdad para cualquier sesión que necesite
# saber si el loop está vivo: `bash harness/loop-status.sh`.
set -uo pipefail

WORKSPACE="${__WORKSPACE_ENV_VAR__:-__WORKSPACE_DEFAULT__}"
TOOLING_REPO_NAME="__TOOLING_REPO__"
# Memoria durable del harness, RELATIVA a la raíz del workspace (default:
# "<INFRA_REPO>/harness"). Anidada por app cuando varias comparten el mismo
# repo docs-only. Ya viene sustituida por bootstrap.sh.
HARNESS_DIR="__HARNESS_DIR__"
HARNESS="$WORKSPACE/$TOOLING_REPO_NAME/harness"
FEATURES="$HARNESS/feature_list.json"
PROMPTS="$WORKSPACE/$HARNESS_DIR/prompts"
PROGRESS="$WORKSPACE/$HARNESS_DIR/claude-progress.md"
LOG_DIR="$HARNESS/logs"
LOG="$LOG_DIR/loop-$(date +%Y%m%d).log"

# Una tarea que termina en push a main NO va a un modelo barato/rápido sin
# criterio propio (ver GOAL.md del proyecto). El runner lo hace cumplir en vez
# de confiar en la memoria de cada sesión.
LOOP_MODEL="${LOOP_MODEL:-__LOOP_MODEL__}"
VERIFIER_MODEL="${VERIFIER_MODEL:-__VERIFIER_MODEL__}"
# Corre desatendido: sin bypass, la primera pregunta de permisos cuelga la
# corrida entera. El guardrail real no es el prompt de permisos, son las
# prohibiciones escritas en GOAL.md + los gates pre-push, que el bypass NO
# desactiva.
PERM_MODE="${LOOP_PERMISSION_MODE:-bypassPermissions}"
MAX_ITER="${LOOP_MAX_ITER:-40}"          # backstop de fuga, no un objetivo
RETRY_SLEEP="${LOOP_RETRY_SLEEP:-900}"   # ante rate limit / error de API
MAX_RETRY="${LOOP_MAX_RETRY:-4}"

mkdir -p "$LOG_DIR"

log() { printf '%s | %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
die() { log "STOP($1): $2"; exit "$3"; }

command -v claude >/dev/null 2>&1 || { echo "✋ falta el CLI 'claude' en el PATH" >&2; exit 64; }
[ -f "$FEATURES" ] || { echo "✋ falta $FEATURES" >&2; exit 64; }

cd "$WORKSPACE" || exit 64
# Canonicalización: a partir de acá `$WORKSPACE` es un path ABSOLUTO y sin
# symlinks. Es lo que se escribe en el `workspace=` del lock, y es contra eso
# que `loop-status.sh` decide si un lock (o un runner que ve `ps`) es de ESTE
# workspace o de otro loop de la misma máquina (TPL-F6).
WORKSPACE="$(pwd -P)"

# ---- lock single-instance ---------------------------------------------------
# POR QUÉ EXISTE. Sin lock, dos schedulers vivos sobre el mismo working tree
# pueden correr la misma feature en carrera y trabarse en un empate estable,
# cada sesión esperando el claim inflight de la sesión del OTRO loop. Las
# demás protecciones del harness (claims inflight, WIP=1, self-hash del
# runner) están diseñadas para sesiones cooperantes bajo UN scheduler: con
# dos, degradan a espera mutua en vez de a exclusión.
#
# ESTE ARCHIVO ES LA FUENTE DE VERDAD de «¿hay un loop vivo?». Un `pgrep` que
# matchea la línea de comando de CUALQUIER proceso que contenga la cadena
# `loop.sh` da falsos positivos (incluida una sesión `claude -p` cuyo PROMPT
# la nombra como texto). Un archivo que solo escribe el runner no puede
# confundirse con el texto de un prompt. Lectura desde afuera —el comando
# canónico para cualquier sesión— es `bash harness/loop-status.sh`.
#
# ANTI-RECICLAJE DE PID. El pidfile guarda `pid` + `pid_start_time` (el
# `lstart` de `ps`), el MISMO par que usa `scripts/inflight.mjs` en
# `isAlive()`. Un PID reutilizado por otro proceso no se confunde con el
# dueño vivo: su hora de arranque difiere.
#
# UN LOCK HUÉRFANO NO BLOQUEA. Si el dueño está muerto (o el PID fue
# reciclado), el pidfile se descarta y este loop arranca normal.
#
# SI NO SE PUEDE DECIDIR, NO SE ARRANCA. Un pidfile ilegible o incompleto sale
# por rc 8 pidiendo revisión, en vez de asumir que está libre.
#
# NO ESPERA, NO MATA, NO TOCA NADA. Un scheduler haciendo cola con otro
# scheduler son dos schedulers igual, con la carrera diferida.
LOCK="${LOOP_LOCK:-$HARNESS/.loop.lock}"
LOCK_HELD=0

lock_start_time() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//; s/ *$//'; }
lock_field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1; }

release_lock() {
  [ "$LOCK_HELD" -eq 1 ] || return 0
  # Solo borra el lock propio: si otro loop ya hizo takeover de un lock que
  # creímos nuestro, borrarlo lo dejaría desprotegido.
  [ "$(lock_field "$LOCK" pid)" = "$$" ] && rm -f "$LOCK"
  LOCK_HELD=0
}

# O_EXCL vía noclobber: la CREACIÓN del archivo es atómica, así que de dos
# loops arrancando a la vez gana exactamente uno. El contenido se escribe en
# el MISMO redirect — no hay ventana con el lock creado y vacío.
write_lock() {
  ( set -o noclobber
    {
      printf 'pid=%s\n' "$$"
      printf 'pid_start_time=%s\n' "$LOCK_START"
      printf 'started_at=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
      printf 'workspace=%s\n' "$WORKSPACE"
      printf 'log=%s\n' "$LOG"
    } > "$LOCK"
  ) 2>/dev/null
}

acquire_lock() {
  LOCK_START="$(lock_start_time "$$")"
  local try owner owner_start owner_now
  for try in 1 2 3; do
    if write_lock; then LOCK_HELD=1; trap release_lock EXIT; return 0; fi
    owner="$(lock_field "$LOCK" pid)"
    owner_start="$(lock_field "$LOCK" pid_start_time)"
    if [ -z "$owner" ] || [ -z "$owner_start" ]; then
      log "lockfile ilegible o incompleto: $LOCK — no puedo distinguir 'libre' de 'otro loop vivo'"
      log "revisalo con 'bash $HARNESS/loop-status.sh' y borralo si no tiene dueño"
      return 8
    fi
    owner_now="$(lock_start_time "$owner")"
    if [ -n "$owner_now" ] && [ "$owner_now" = "$owner_start" ]; then
      log "ya hay un loop.sh VIVO en este workspace: PID $owner (arrancado $owner_start)"
      log "lockfile: $LOCK — este proceso no toca nada y sale (rc 8)"
      log "si de verdad querés relanzar: 'kill $owner' y volvé a lanzar"
      return 8
    fi
    # Dueño muerto o PID reciclado: el lock es huérfano. Se descarta y se
    # reintenta. Si otro loop gana la carrera del takeover, la vuelta
    # siguiente lo ve vivo y sale por la rama de arriba.
    log "lock huérfano (PID $owner ya no existe, o el PID fue reciclado) — descartado, arranco normal"
    rm -f "$LOCK"
  done
  log "no pude tomar el lock tras 3 intentos: $LOCK"
  return 8
}

acquire_lock || { log "STOP(lock): no se arranca un segundo scheduler"; exit 8; }

# Una corrida larga NO sobrevive a un deploy del propio harness — bash
# conserva en memoria las funciones ya parseadas, así que un loop.sh cambiado
# en disco significa que este proceso corre código viejo. Hash al arranque,
# recomputado al tope de cada iteración; si difiere → STOP(reload) explícito.
# NO re-exec: arriesga repetir la iteración en curso y ensuciar el estado; el
# loop se relanza barato. Protocolo: harness/patterns.md § "El loop no
# trabaja sobre sí mismo".
SELF="$HARNESS/loop.sh"
SELF_HASH="$(sha256sum "$SELF" | cut -d" " -f1)"

# ---- clock out limpio ante señal ------------------------------------------
# No commitea: el pre-commit del repo de docs exige un claim inflight de una
# SESIÓN de Claude Code, y este runner no lo es. Deja la entrada escrita y
# avisa que queda sin commitear, que es lo que la próxima sesión necesita saber.
CHILD=""
on_signal() {
  log "SEÑAL recibida — clock out limpio"
  [ -n "$CHILD" ] && kill "$CHILD" 2>/dev/null
  {
    printf '\n### Loop interrumpido por señal — %s\n\n' "$(date '+%Y-%m-%d %H:%M')"
    printf -- '- Iteración en curso al momento de la señal: %s (feature activa: %s).\n' "${ITER:-0}" "${ACTIVE:-ninguna}"
    printf -- '- Log de la corrida: `%s`.\n' "$LOG"
    printf -- '- Esta entrada NO está commiteada: el runner no puede tomar un claim inflight.\n'
    printf -- '  Próxima sesión: verificar el estado real contra `feature_list.json` antes de creerle.\n'
  } >> "$PROGRESS"
  log "clock out escrito en claude-progress.md (SIN commitear)"
  exit 130
}
trap on_signal INT TERM

# ---- helpers ---------------------------------------------------------------
# Devuelve "id|kind" de la feature activa. Prioridad de elección: 1) la
# awaiting_verifier de mayor prioridad — drena la cola del propio loop
# (terminada, esperando sello) ANTES de abrir trabajo nuevo, así el
# implementer nunca la vuelve a tocar y el verifier la recibe sin demora;
# 2) la in_progress (WIP=1 real, alguien la está trabajando); 3) la
# not_started de mayor prioridad. Vacío = no queda trabajo desbloqueado
# (stopping condition (a)). Devuelve rc≠0 si el JSON no parsea: un
# feature_list ilegible NO es "no queda trabajo".
# Segundo mecanismo de skip: el prefijo `[MANUAL — ADRI]` (o el catálogo
# equivalente que fije el GOAL.md del proyecto) en el `title` se saltea en
# TODAS las ramas, con línea explícita en el log.
# Tercer mecanismo de skip: toda feature marcada `self_modifying` (sus paths
# de destino tocan loop.sh, init.sh, los prompts o el esquema del feature
# list) se saltea en TODAS las ramas de la elección, con línea explícita en
# el log, y se ejecuta como sesión standalone fuera del loop — protocolo:
# harness/patterns.md § "El loop no trabaja sobre sí mismo". Si solo quedan
# self_modifying (o solo [MANUAL]), la selección vuelve vacía y la corrida
# cierra por (a): correcto — ese trabajo no es del loop.
active_feature() {
  node -e '
    const all = require(process.argv[1]).features;
    if (!Array.isArray(all)) throw new Error("features no es un array");
    const ACTIVAS = ["awaiting_verifier", "in_progress", "not_started"];
    const manual = x => /^\s*\[(MANUAL — ADRI|MANUAL - ADRI)\]/.test(x.title || "");
    for (const s of all.filter(x => x.self_modifying === true && ACTIVAS.includes(x.status)))
      console.error("[selfmod] " + s.id + ": requiere sesión standalone (self_modifying) — salteada, el loop no trabaja sobre sí mismo");
    for (const s of all.filter(x => manual(x) && ACTIVAS.includes(x.status)))
      console.error("[manual] " + s.id + ": título [MANUAL — ADRI] — salteada, solo un humano puede ejecutarla");
    const f = all.filter(x => x.self_modifying !== true && !manual(x));
    const av = f.filter(x => x.status === "awaiting_verifier").sort((a,b) => a.priority - b.priority)[0];
    if (av) { process.stdout.write(av.id + "|verify"); process.exit(0); }
    const wip = f.find(x => x.status === "in_progress");
    const next = f.filter(x => x.status === "not_started").sort((a,b) => a.priority - b.priority)[0];
    const pick = wip || next;
    process.stdout.write(pick ? pick.id + "|impl" : "");
  ' "$FEATURES" 2>>"$LOG"
}

counts() {
  node -e '
    const f = require(process.argv[1]).features;
    const n = s => f.filter(x => x.status === s).length;
    process.stdout.write(`passing=${n("passing")} awaiting_verifier=${n("awaiting_verifier")} in_progress=${n("in_progress")} not_started=${n("not_started")} blocked=${n("blocked")}`);
  ' "$FEATURES"
}

# Corre un prompt en sesión fresca. Reintenta SOLO ante fallo de
# infraestructura (rate limit / error de API): un fallo de la tarea no se
# arregla repitiéndola.
run_agent() {
  local label="$1" prompt_file="$2" model="$3" extra="${4:-}"
  local try=1 out rc
  while :; do
    log "[$label] intento $try/$MAX_RETRY (model=$model)"
    out="$LOG_DIR/$label-$(date +%Y%m%d-%H%M%S).out"
    ( claude -p "$(cat "$prompt_file")${extra:+

$extra}" --model "$model" --permission-mode "$PERM_MODE" >"$out" 2>&1 ) &
    CHILD=$!
    wait "$CHILD"; rc=$?
    CHILD=""
    tail -n 40 "$out" >> "$LOG"
    if [ "$rc" -eq 0 ]; then log "[$label] OK (rc=0, salida en $out)"; return 0; fi
    if grep -qiE 'rate limit|429|overloaded|api error|503|502|connection error|timeout' "$out"; then
      [ "$try" -ge "$MAX_RETRY" ] && { log "[$label] rate limit/API tras $MAX_RETRY intentos"; return 70; }
      log "[$label] rate limit / error de API (rc=$rc) — durmiendo ${RETRY_SLEEP}s"
      sleep "$RETRY_SLEEP"; try=$((try+1)); continue
    fi
    log "[$label] falló por la tarea, no por la API (rc=$rc) — no se reintenta"
    return "$rc"
  done
}

# ---- arranque --------------------------------------------------------------
log "=== LOOP ON — $(date '+%Y-%m-%d %H:%M:%S') — model=$LOOP_MODEL verifier=$VERIFIER_MODEL perm=$PERM_MODE"
log "goal: ver $HARNESS_DIR/GOAL.md. Estado inicial: $(counts)"

# Stopping condition (e): un baseline rojo ANTES de la primera iteración no lo
# causó el loop. Se frena todo; apilar trabajo sobre piso podrido lo empeora.
bash "$HARNESS/init.sh" >>"$LOG" 2>&1 || die "e" "baseline ROJO al arrancar — el loop no lo causó. Arreglar a mano." 3

ITER=0; LAST=""; SAME=0; RECOVERING=0
while :; do
  ITER=$((ITER+1))
  # ¿Cambió loop.sh en disco desde el arranque? Antes de evaluar cualquier
  # stopping condition — este proceso ya corre código viejo y no puede
  # confiar en su propia lógica de cierre.
  [ "$(sha256sum "$SELF" | cut -d" " -f1)" != "$SELF_HASH" ] && \
    die "reload" "loop.sh cambió en disco durante la corrida — relanzá (este proceso sigue con el código viejo en memoria; protocolo self_modifying)" 7
  [ "$ITER" -gt "$MAX_ITER" ] && die "max_iter" "tope de $MAX_ITER iteraciones (backstop de fuga)" 5

  RESULT="$(active_feature)" || die "json" "feature_list.json NO parsea (traza arriba en el log). Eso NO es 'no queda trabajo': es el estado del harness corrupto. Arreglar a mano." 6
  [ -z "$RESULT" ] && { log "(a) no quedan features desbloqueadas: $(counts)"; break; }
  ACTIVE="${RESULT%%|*}"; KIND="${RESULT##*|}"

  if [ "$ACTIVE" = "$LAST" ]; then SAME=$((SAME+1)); else SAME=1; fi
  LAST="$ACTIVE"
  log "--- iteración $ITER — feature activa: $ACTIVE (kind=$KIND, intento $SAME) — $(counts)"

  # Stopping condition (c): 3 intentos consecutivos sobre la misma feature. No
  # se abandona en silencio: una sesión corta la marca blocked CON
  # diagnóstico y el loop sigue por la siguiente. Un 4º intento es
  # terquedad, no ingeniería.
  if [ "$SAME" -gt 3 ]; then
    log "(c) $ACTIVE lleva 3 intentos fallidos — marcándola blocked con diagnóstico"
    run_agent "block-$ACTIVE" "$PROMPTS/implementer.md" "$LOOP_MODEL" \
"STOPPING CONDITION (c) de $HARNESS_DIR/GOAL.md: la feature $ACTIVE lleva 3 iteraciones consecutivas sin llegar a passing. NO la implementes de nuevo. Tu única tarea: marcarla \"blocked\" en $TOOLING_REPO_NAME/harness/feature_list.json con un diagnóstico en notes que diga qué se intentó en cada pasada y con qué salida (leé claude-progress.md y harness/logs/), commitear ese cambio, y terminar. Después el loop sigue con la siguiente feature por prioridad."
    LAST=""; SAME=0; continue
  fi

  if [ "$KIND" = "verify" ]; then
    # Drena primero: ya está awaiting_verifier, terminada por un implementer
    # de una iteración previa (o de otra sesión). Directo al verifier, sin
    # volver a pasar por el implementer.
    run_agent "verif-$ACTIVE" "$PROMPTS/verifier.md" "$VERIFIER_MODEL"
    rc=$?
    [ "$rc" -eq 70 ] && die "api" "rate limit / error de API tras $MAX_RETRY reintentos de 15 min" 4
  else
    run_agent "impl-$ACTIVE" "$PROMPTS/implementer.md" "$LOOP_MODEL"
    rc=$?
    [ "$rc" -eq 70 ] && die "api" "rate limit / error de API tras $MAX_RETRY reintentos de 15 min" 4
    if [ "$rc" -ne 0 ]; then
      log "[impl-$ACTIVE] terminó con rc=$rc — se salta el verifier, no hay trabajo que verificar (cuenta como intento $SAME de la stopping condition (c))"
      continue
    fi

    run_agent "verif-$ACTIVE" "$PROMPTS/verifier.md" "$VERIFIER_MODEL"
    rc=$?
    [ "$rc" -eq 70 ] && die "api" "rate limit / error de API tras $MAX_RETRY reintentos de 15 min" 4
  fi

  # Stopping condition (e) mid-run. Rojo después de una iteración es, con
  # alta probabilidad, obra del loop: se le da UNA iteración de recuperación
  # (el implementer arregla el baseline, paso 2 de su prompt). Si sigue
  # rojo, para.
  if ! bash "$HARNESS/init.sh" >>"$LOG" 2>&1; then
    [ "$RECOVERING" -eq 1 ] && die "e" "baseline ROJO tras la iteración de recuperación — FRENAR TODO" 3
    log "(e) baseline ROJO tras la iteración — próxima pasada es de recuperación"
    RECOVERING=1; LAST=""; SAME=0; continue
  fi
  RECOVERING=0
done

log "=== LOOP OFF — $(counts) — revisá $HARNESS_DIR/claude-progress.md y el log: $LOG"
exit 0
