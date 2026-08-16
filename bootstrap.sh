#!/usr/bin/env bash
# bootstrap.sh <app> — genera el harness parametrizado de este repo
# (harness-core) en un repo cliente nuevo, SIN dejar dependencia de
# submódulo: copia + sustituye variables (`scripts/render.sh`), una sola
# vez, en el directorio de trabajo actual. Forma de consumo aprobada
# (TPL-F0/scout: `infra/plans/2026-08-16-tpl-scout-harness-core.md`, opción
# (b)) — un fix posterior al runner se reaplica a mano por proyecto, nunca
# se sincroniza solo.
#
# Uso: bash bootstrap.sh <app> [directorio destino, default: cwd]
# Config opcional por variable de entorno (todas con default derivado de
# <app> — ver PARAMS.md para el significado de cada una): PROJECT_NAME,
# WORKSPACE_ENV_VAR, WORKSPACE_DEFAULT, INFRA_REPO, TOOLING_REPO,
# APP_REPOS, APP_REPO_FULL_CMDS, LOOP_MODEL, VERIFIER_MODEL, TODAY.
# Nunca lee de stdin: corre no-interactivo siempre, para poder invocarse
# desde un test de sandbox sin bloquearse.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP="${1:?uso: bootstrap.sh <app> [directorio destino]}"
DEST="${2:-$(pwd)}"

APP_UPPER="$(printf '%s' "$APP" | tr '[:lower:]-' '[:upper:]_')"

PROJECT_NAME="${PROJECT_NAME:-$APP}"
WORKSPACE_ENV_VAR="${WORKSPACE_ENV_VAR:-${APP_UPPER}_WORKSPACE}"
WORKSPACE_DEFAULT="${WORKSPACE_DEFAULT:-\$HOME/$APP}"
INFRA_REPO="${INFRA_REPO:-infra}"
TOOLING_REPO="${TOOLING_REPO:-${APP}_tooling}"
APP_REPOS="${APP_REPOS:-}"
APP_REPO_FULL_CMDS="${APP_REPO_FULL_CMDS:-}"
LOOP_MODEL="${LOOP_MODEL:-sonnet}"
VERIFIER_MODEL="${VERIFIER_MODEL:-sonnet}"
TODAY="${TODAY:-$(date +%Y-%m-%d)}"

RENDER_ARGS=(
  "PROJECT_NAME=$PROJECT_NAME"
  "WORKSPACE_ENV_VAR=$WORKSPACE_ENV_VAR"
  "WORKSPACE_DEFAULT=$WORKSPACE_DEFAULT"
  "INFRA_REPO=$INFRA_REPO"
  "TOOLING_REPO=$TOOLING_REPO"
  "APP_REPOS=$APP_REPOS"
  "APP_REPO_FULL_CMDS=$APP_REPO_FULL_CMDS"
  "LOOP_MODEL=$LOOP_MODEL"
  "VERIFIER_MODEL=$VERIFIER_MODEL"
  "TODAY=$TODAY"
)

TOOLING="$DEST/$TOOLING_REPO"
INFRA="$DEST/$INFRA_REPO"

say() { printf '==> %s\n' "$*"; }

say "Generando harness de $PROJECT_NAME en $DEST ($TOOLING_REPO/ + $INFRA_REPO/)"

mkdir -p "$TOOLING/harness/logs" "$TOOLING/scripts" "$TOOLING/.githooks" \
         "$INFRA/harness/prompts"

# render_file: renderiza UN archivo fuente al destino final, usando
# scripts/render.sh (que trabaja sobre árboles) sobre un directorio
# temporal de un solo archivo.
render_file() {
  local src="$1" dst="$2"
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "$tmp/d" "$(dirname "$dst")"
  cp "$src" "$tmp/d/$(basename "$src")"
  bash "$HERE/scripts/render.sh" "$tmp/d" "$tmp/out" "${RENDER_ARGS[@]}"
  cp "$tmp/out/$(basename "$src")" "$dst"
  rm -rf "$tmp"
}

# ---- 2. <app>_tooling/harness/init.sh, loop.sh, loop-status.sh ------------
render_file "$HERE/harness/init.sh" "$TOOLING/harness/init.sh"
render_file "$HERE/harness/loop.sh" "$TOOLING/harness/loop.sh"
cp "$HERE/harness/loop-status.sh" "$TOOLING/harness/loop-status.sh"
chmod +x "$TOOLING/harness/init.sh" "$TOOLING/harness/loop.sh" "$TOOLING/harness/loop-status.sh"

# ---- 4. scripts GENÉRICOS, copiados sin sustitución ------------------------
cp "$HERE/scripts/check-hook.sh" "$TOOLING/scripts/check-hook.sh"
cp "$HERE/scripts/check-priority-ties.mjs" "$TOOLING/scripts/check-priority-ties.mjs"
cp "$HERE/scripts/inflight.mjs" "$TOOLING/scripts/inflight.mjs"
cp "$HERE/scripts/setup-hooks.sh" "$TOOLING/scripts/setup-hooks.sh"
chmod +x "$TOOLING/scripts/"*.sh
cp "$HERE/.githooks/pre-push" "$TOOLING/.githooks/pre-push"
chmod +x "$TOOLING/.githooks/pre-push"

# ---- 5. feature_list.json inicial, vacío -----------------------------------
render_file "$HERE/harness/feature_list.template.json" "$TOOLING/harness/feature_list.json"

# ---- 6-9. skeleton de infra/harness/ (memoria durable, a completar) -------
render_file "$HERE/harness/GOAL.template.md" "$INFRA/harness/GOAL.md"
render_file "$HERE/harness/claude-progress.template.md" "$INFRA/harness/claude-progress.md"
render_file "$HERE/harness/session-handoff.md" "$INFRA/harness/session-handoff.md"
render_file "$HERE/harness/clean-state-checklist.md" "$INFRA/harness/clean-state-checklist.md"
render_file "$HERE/harness/evaluator-rubric.template.md" "$INFRA/harness/evaluator-rubric.md"
render_file "$HERE/harness/como-sembrar-features.template.md" "$INFRA/harness/como-sembrar-features.md"
render_file "$HERE/harness/patterns.template.md" "$INFRA/harness/patterns.md"
render_file "$HERE/harness/CLAUDE.workspace.template.md" "$INFRA/harness/CLAUDE.workspace.md"
render_file "$HERE/harness/prompts/implementer.md" "$INFRA/harness/prompts/implementer.md"
render_file "$HERE/harness/prompts/verifier.md" "$INFRA/harness/prompts/verifier.md"

# ---- 10. resumen imprimible ------------------------------------------------
cat <<SUMMARY

==> Harness de $PROJECT_NAME generado en $DEST.

Generado:
  $TOOLING_REPO/harness/{init.sh,loop.sh,loop-status.sh,feature_list.json,logs/}
  $TOOLING_REPO/scripts/{check-hook.sh,check-priority-ties.mjs,inflight.mjs,setup-hooks.sh}
  $TOOLING_REPO/.githooks/pre-push
  $INFRA_REPO/harness/{GOAL.md,claude-progress.md,session-handoff.md,clean-state-checklist.md,evaluator-rubric.md,como-sembrar-features.md,patterns.md,CLAUDE.workspace.md}
  $INFRA_REPO/harness/prompts/{implementer.md,verifier.md}

Pendiente de completar A MANO antes de encender el loop (bootstrap NO lo
adivina por vos):
  - $INFRA_REPO/harness/GOAL.md: el goal real de la corrida, el catálogo de
    consolas/acciones PROHIBIDAS del negocio, la política de costo, y pasar
    ESTADO de OFF a ON cuando corresponda.
  - $TOOLING_REPO/harness/feature_list.json: sembrar las features reales
    (arranca con features: [] — ver $INFRA_REPO/harness/como-sembrar-features.md).
  - El CLAUDE.md de cada repo de apps nuevo (uno por repo, reglas locales).
  - $INFRA_REPO/harness/CLAUDE.workspace.md § «Lanzamiento del loop»: el
    detalle real de la máquina que va a correr el loop.
  - Si $TOOLING_REPO o $INFRA_REPO todavía no son repos git: \`git init -b main\`
    en cada uno, y activar los hooks con
    \`sh $TOOLING_REPO/scripts/setup-hooks.sh\`.

Primer comando a correr una vez completado lo de arriba:
  bash $TOOLING_REPO/harness/init.sh
SUMMARY
