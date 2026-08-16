#!/usr/bin/env bash
# run-tests.sh — suite de sandbox del harness-core.
#
# TODO corre contra un workspace TEMPORAL (mktemp -d), NUNCA contra un
# workspace real: nada acá lee ni escribe fuera de $SANDBOX y $BIN_DIR
# (ambos bajo mktemp, borrados al salir por el trap). No hay ninguna ruta
# hardcodeada a un proyecto concreto — los valores de sustitución de abajo
# son arbitrarios, elegidos para el test, no los de ningún cliente real.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

PASS=0
FAIL=0

ok() { PASS=$((PASS+1)); printf '✅ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '❌ %s\n' "$1"; }

SANDBOX="$(mktemp -d)"
BIN_DIR="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX" "$BIN_DIR"; }
trap cleanup EXIT

# ---- fixture de sustitución (valores arbitrarios de test) -----------------
WORKSPACE_ENV_VAR="HC_TEST_WORKSPACE_$$"
export "$WORKSPACE_ENV_VAR=$SANDBOX"

RENDER_ARGS=(
  "PROJECT_NAME=Sandbox"
  "WORKSPACE_ENV_VAR=$WORKSPACE_ENV_VAR"
  "WORKSPACE_DEFAULT=/no/deberia/usarse"
  "INFRA_REPO=infra"
  "TOOLING_REPO=tooling"
  "APP_REPOS="
  "APP_REPO_FULL_CMDS="
  "LOOP_MODEL=sonnet"
  "VERIFIER_MODEL=sonnet"
  "TODAY=2026-01-01"
)

# ---- 1. render de los templates parametrizados al sandbox ------------------
TOOLING="$SANDBOX/tooling"
INFRA="$SANDBOX/infra"
mkdir -p "$TOOLING/harness/logs" "$TOOLING/scripts" "$TOOLING/.githooks" \
         "$INFRA/harness/prompts"

# render.sh trabaja sobre árboles, no archivos sueltos — envolvemos cada
# archivo fuente en su propio directorio temporal de render y lo copiamos al
# destino final, para no reimplementar dos veces la sustitución.
render_file() {
  local src="$1" dst="$2"
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "$tmp/d"
  cp "$src" "$tmp/d/$(basename "$src")"
  bash "$HERE/render.sh" "$tmp/d" "$tmp/out" "${RENDER_ARGS[@]}"
  cp "$tmp/out/$(basename "$src")" "$dst"
  rm -rf "$tmp"
}

render_file "$ROOT/harness/init.sh" "$TOOLING/harness/init.sh"
render_file "$ROOT/harness/loop.sh" "$TOOLING/harness/loop.sh"
cp "$ROOT/harness/loop-status.sh" "$TOOLING/harness/loop-status.sh"
chmod +x "$TOOLING/harness/init.sh" "$TOOLING/harness/loop.sh" "$TOOLING/harness/loop-status.sh"

cp "$ROOT/scripts/check-hook.sh" "$TOOLING/scripts/check-hook.sh"
cp "$ROOT/scripts/check-priority-ties.mjs" "$TOOLING/scripts/check-priority-ties.mjs"
cp "$ROOT/scripts/inflight.mjs" "$TOOLING/scripts/inflight.mjs"
cp "$ROOT/scripts/setup-hooks.sh" "$TOOLING/scripts/setup-hooks.sh"
chmod +x "$TOOLING/scripts/"*.sh
cp "$ROOT/.githooks/pre-push" "$TOOLING/.githooks/pre-push"
chmod +x "$TOOLING/.githooks/pre-push"

render_file "$ROOT/harness/prompts/implementer.md" "$INFRA/harness/prompts/implementer.md"
render_file "$ROOT/harness/prompts/verifier.md" "$INFRA/harness/prompts/verifier.md"
: > "$INFRA/harness/claude-progress.md"

# feature_list.json inicial: UNA feature not_started que el fake `claude` de
# abajo nunca va a mover — así el loop no se queda sin trabajo antes de pegar
# contra MAX_ITER.
cat > "$TOOLING/harness/feature_list.json" <<'JSON'
{
  "project": "sandbox",
  "last_updated": "2026-01-01",
  "rules": {},
  "status_legend": {},
  "features": [
    {
      "id": "SANDBOX-1",
      "priority": 1,
      "area": "test",
      "tema": "test",
      "title": "feature de prueba del sandbox",
      "user_visible_behavior": "ninguno — fixture",
      "status": "not_started",
      "verification": ["true"],
      "evidence": [],
      "notes": ""
    }
  ]
}
JSON

# ---- 2. git init de los dos repos (init.sh exige .git + worktree=1 + main) -
init_repo() {
  local dir="$1"
  ( cd "$dir" \
    && git init -q -b main \
    && git config user.email test@example.invalid \
    && git config user.name "harness-core tests" \
    && git add -A \
    && git commit -q -m "fixture inicial" )
}
init_repo "$TOOLING"
init_repo "$INFRA"
# core.hooksPath + modo ejecutable en el índice, como pide check-hook.sh —
# git add ya capturó el bit +x de arriba, pero core.hooksPath se activa recién
# acá porque setup-hooks.sh corre `git config`, que necesita el repo ya init.
( cd "$TOOLING" && sh scripts/setup-hooks.sh >/dev/null )

# ---- 3. fake `claude` CLI — sin red, sin costo, no hace nada al feature_list
cat > "$BIN_DIR/claude" <<'SH'
#!/usr/bin/env bash
# Fake CLI de test: consume los mismos flags que el real (-p <prompt> --model
# --permission-mode) y no toca nada — así SANDBOX-1 se queda not_started para
# siempre y el loop real llega a MAX_ITER en vez de terminar por (a).
echo "[fake claude] invocado con: $*"
exit 0
SH
chmod +x "$BIN_DIR/claude"

# ---- Test 1: init.sh sobre el sandbox da BASELINE VERDE --------------------
OUT1="$(cd "$SANDBOX" && bash "$TOOLING/harness/init.sh" 2>&1)"
RC1=$?
if [ "$RC1" -eq 0 ] && printf '%s' "$OUT1" | grep -q "BASELINE VERDE"; then
  ok "init.sh renderizado da BASELINE VERDE sobre el sandbox (rc=0)"
else
  bad "init.sh renderizado NO dio baseline verde (rc=$RC1): $(printf '%s' "$OUT1" | tail -5)"
fi

# ---- Test 2: check-priority-ties.mjs detecta empate y lo deja pasar sin empate
TIE_FILE="$(mktemp)"
cat > "$TIE_FILE" <<'JSON'
{"features":[{"id":"A","priority":5,"status":"not_started"},{"id":"B","priority":5,"status":"in_progress"}]}
JSON
if ! node "$TOOLING/scripts/check-priority-ties.mjs" "$TIE_FILE" >/dev/null 2>&1; then
  ok "check-priority-ties.mjs rc≠0 ante empate real entre features activas"
else
  bad "check-priority-ties.mjs NO detectó un empate real"
fi
NOTIE_FILE="$(mktemp)"
cat > "$NOTIE_FILE" <<'JSON'
{"features":[{"id":"A","priority":5,"status":"not_started"},{"id":"B","priority":6,"status":"in_progress"},{"id":"C","priority":5,"status":"passing"}]}
JSON
if node "$TOOLING/scripts/check-priority-ties.mjs" "$NOTIE_FILE" >/dev/null 2>&1; then
  ok "check-priority-ties.mjs rc=0 sin empate activo (passing puede repetir número)"
else
  bad "check-priority-ties.mjs dio falso positivo sin empate activo"
fi
rm -f "$TIE_FILE" "$NOTIE_FILE"

# ---- Test 3: inflight.mjs — ciclo claim/list/check/release -----------------
INFLIGHT_SANDBOX="$(mktemp -d)"
(
  export WORKSPACE_ROOT="$INFLIGHT_SANDBOX"
  export CLAUDE_CODE_SESSION_ID="sess-test-$$"
  export CLAUDE_PID="$$"
  cd "$TOOLING"
  node "$TOOLING/scripts/inflight.mjs" claim tooling "test" "harness/feature_list.json" >/dev/null
  node "$TOOLING/scripts/inflight.mjs" check tooling "harness/feature_list.json" >/dev/null
  node "$TOOLING/scripts/inflight.mjs" check tooling "otro/path/sin/relacion.md"
)
RC3=$?
rm -rf "$INFLIGHT_SANDBOX"
if [ "$RC3" -eq 0 ]; then
  ok "inflight.mjs: claim propio no colisiona con paths que no cubre (check limpio)"
else
  bad "inflight.mjs: ciclo claim/check dio rc=$RC3 inesperado"
fi

# ---- Test 4 (EL REQUERIDO): loop.sh con LOOP_MAX_ITER=1 llega a STOP(max_iter)/rc5
OUT4="$(cd "$SANDBOX" && PATH="$BIN_DIR:$PATH" LOOP_MAX_ITER=1 LOOP_PERMISSION_MODE=bypassPermissions \
  bash "$TOOLING/harness/loop.sh" 2>&1)"
RC4=$?
if [ "$RC4" -eq 5 ] && printf '%s' "$OUT4" | grep -q "STOP(max_iter)"; then
  ok "loop.sh real, LOOP_MAX_ITER=1 sobre el sandbox → STOP(max_iter), rc=5"
else
  bad "loop.sh NO dio STOP(max_iter)/rc=5 (rc=$RC4): $(printf '%s' "$OUT4" | tail -15)"
fi

# ---- Test 5: loop-status.sh con un lock que apunta a un PID VIVO real -----
# NO se prueba acá el camino "sin ningún loop vivo" (rc=1): loop-status.sh
# tiene un fallback `pgrep` deliberado que escanea TODO el sistema (no solo
# el sandbox) para no confiarse ciegamente de un lockfile — así que en una
# máquina de desarrollo con un loop.sh ajeno real corriendo, ese camino no es
# aislable desde un test de sandbox sin mockear `ps` a nivel de sistema, y
# mockear eso sería probar el mock, no el script. Lo que SÍ es aislable y se
# prueba acá: un lock que apunta a un PID vivo (el propio proceso del test)
# se reporta como VIVO con el PID correcto — el camino "lock legible, dueño
# vivo" del script.
FAKE_LOCK="$(mktemp)"
{
  printf 'pid=%s\n' "$$"
  printf 'pid_start_time=%s\n' "$(ps -o lstart= -p "$$" | sed 's/^ *//; s/ *$//')"
  printf 'started_at=test\n'
  printf 'log=/dev/null\n'
} > "$FAKE_LOCK"
OUT5="$(LOOP_LOCK="$FAKE_LOCK" bash "$TOOLING/harness/loop-status.sh" 2>&1)"
RC5=$?
rm -f "$FAKE_LOCK"
if [ "$RC5" -eq 0 ] && printf '%s' "$OUT5" | grep -q "PID $$"; then
  ok "loop-status.sh con lock apuntando a PID vivo ($$) → rc=0, PID correcto reportado"
else
  bad "loop-status.sh NO reportó VIVO para un lock con PID realmente vivo (rc=$RC5): $OUT5"
fi

echo
echo "=== resultado: $PASS/$((PASS+FAIL)) tests OK ==="
[ "$FAIL" -eq 0 ]
