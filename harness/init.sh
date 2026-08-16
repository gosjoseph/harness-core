#!/usr/bin/env bash
# init.sh — baseline del workspace __PROJECT_NAME__ (Lecture 06: la init tiene fase propia).
# NO instala nada nuevo (COSTO CERO / máquina ya provisionada).
#
# POR QUÉ VIVE ACÁ Y NO EN EL REPO DE DOCS: el repo de docs (__INFRA_REPO__) es
# docs-only, "sin código ejecutable ni JSON de política" — el harness queda
# partido a propósito: memoria durable (claude-progress, GOAL, checklists,
# prompts, rúbrica) en __INFRA_REPO__/harness/; ejecutable + estado JSON en
# __TOOLING_REPO__/harness/.
#
# QUÉ CORRE ACÁ Y QUÉ NO: baseline liviano (default) = higiene git (un
# `git fetch` por repo del workspace) + gate de docs del repo de docs + el
# `scripts/check-hook.sh` de cada repo de apps. Responde "¿el workspace está
# sano para empezar?" sin cobrar el costo de las suites completas en cada
# clock-in.
#   fuera del baseline, solo en pre-push (el gate real, ver .githooks/pre-push
#   de cada repo): el comando de verificación completo declarado para ese repo.
# Escape hatch: INIT_FULL=1 corre además esos comandos completos acá mismo.

set -uo pipefail
WORKSPACE="${__WORKSPACE_ENV_VAR__:-__WORKSPACE_DEFAULT__}"
INFRA_REPO="__INFRA_REPO__"
TOOLING_REPO="__TOOLING_REPO__"
# Repos de apps del proyecto — lista espaciada, vacía si el proyecto no tiene
# ninguno todavía. Comando de verificación completo por repo, mismo orden que
# APP_REPOS (usado solo bajo INIT_FULL=1); vacío = "sh scripts/check-hook.sh" alcanza.
APP_REPOS=(__APP_REPOS__)
APP_REPO_FULL_CMDS=(__APP_REPO_FULL_CMDS__)
REPOS=("$INFRA_REPO" "$TOOLING_REPO" "${APP_REPOS[@]}")
FAIL=0

say() { printf '==> %s\n' "$*"; }
bad() { printf 'XX  %s\n' "$*"; FAIL=1; }

say "Workspace: $WORKSPACE"
cd "$WORKSPACE" || { echo "Workspace inexistente"; exit 1; }

for r in "${REPOS[@]}"; do
  [ -d "$r/.git" ] || { bad "$r: no es repo git"; continue; }
  # Un solo worktree por repo.
  WT=$(git -C "$r" worktree list | wc -l | tr -d ' ')
  [ "$WT" -eq 1 ] || bad "$r: $WT worktrees (esperado 1) — higiene antes de trabajar"
  # main local no debe divergir hacia atrás de origin/main. Local ADELANTADO
  # de origin (commiteado, todavía sin pushear) pasa VERDE a propósito: es
  # trabajo en vuelo legítimo, no drift — el gate que lo cubre es el
  # pre-push local de ese repo, que corre antes de que ese adelanto llegue a
  # origin/main.
  git -C "$r" fetch -q origin main 2>/dev/null || true
  # --verify -q: sin esto, un origin/main que no resuelve (sin remote
  # `origin`, o remote sin fetch todavía) hace que `git rev-parse` ECOE el
  # argumento tal cual a stdout (comportamiento real de git ante una
  # referencia inválida) en vez de devolver vacío — un `2>/dev/null` sin
  # `--verify -q` no lo tapa, porque el eco va por stdout, no por stderr.
  # Detectado con un repo de sandbox sin remote (tests/run-tests.sh).
  L=$(git -C "$r" rev-parse --verify -q main 2>/dev/null); R=$(git -C "$r" rev-parse --verify -q origin/main 2>/dev/null)
  if [ -n "$L" ] && [ -n "$R" ] && [ "$L" != "$R" ]; then
    git -C "$r" merge-base --is-ancestor "$R" "$L" || bad "$r: main local detrás de origin/main"
  fi
  # working tree sucio = trabajo en vuelo ajeno: se REPORTA, no se toca ni se arregla.
  [ -z "$(git -C "$r" status --porcelain)" ] || say "$r: working tree SUCIO — verificar claims inflight antes de tocar"
done

# Gate de docs del repo de docs (verificador propio del system of record, si existe).
say "check-docs de $INFRA_REPO"
if [ -f "$INFRA_REPO/scripts/check-docs.mjs" ]; then
  ( cd "$INFRA_REPO" && node scripts/check-docs.mjs >/dev/null ) || bad "$INFRA_REPO: check-docs.mjs en rojo"
else
  say "(sin scripts/check-docs.mjs en $INFRA_REPO — gate inerte hasta que el proyecto lo agregue)"
fi

# Los hooks tienen que estar enganchados: sin core.hooksPath no hay gate
# pre-push y el "puente sin CI" deja de existir en silencio.
say "hooks operativos en $TOOLING_REPO y los repos de apps"
for r in "$TOOLING_REPO" "${APP_REPOS[@]}"; do
  ( cd "$r" && sh scripts/check-hook.sh >/dev/null 2>&1 ) || bad "$r: gate de hooks en ROJO (sh scripts/check-hook.sh) — hooks mal instalados, o el gate anti-empates de priority que reporta abajo"
done

# Suites completas: fuera del baseline por costo (ver cabecera). Con
# INIT_FULL=1 corre el comando de verificación completo de cada repo de apps.
if [ "${INIT_FULL:-0}" = "1" ]; then
  say "INIT_FULL=1 — corriendo las suites completas"
  for i in "${!APP_REPOS[@]}"; do
    r="${APP_REPOS[$i]}"; cmd="${APP_REPO_FULL_CMDS[$i]:-}"
    if [ -z "$cmd" ]; then say "$r: sin comando de suite completa configurado, se saltea"; continue; fi
    ( cd "$r" && eval "$cmd" ) || bad "$r: suite completa en rojo ($cmd)"
  done
fi

say "Estado del harness"
FEATURES="$TOOLING_REPO/harness/feature_list.json"
[ -f "$FEATURES" ] || bad "falta $FEATURES"
[ -f "$INFRA_REPO/harness/claude-progress.md" ] || bad "falta $INFRA_REPO/harness/claude-progress.md"
# El feature_list es la máquina de estados del harness: si no PARSEA, el
# baseline es rojo. `awaiting_verifier` (terminada, esperando sello) NO cuenta
# para WIP=1 a propósito: solo alguien activamente implementando cuenta, así
# el loop puede acumular features esperando verifier sin ensuciar el baseline.
WIP=$(node -e '
  try {
    const f = require(require("path").resolve(process.argv[1])).features;
    if (!Array.isArray(f)) throw new Error("features no es un array");
    process.stdout.write(String(f.filter(x => x.status === "in_progress").length));
  } catch (e) { console.error(e.message.split("\n")[0]); process.exit(1); }
' "$FEATURES" 2>&1)
if [ $? -ne 0 ]; then
  bad "feature_list.json NO parsea: $(printf '%s' "$WIP" | head -3 | tr '\n' ' ')"
elif [ "$WIP" -gt 1 ]; then
  bad "WIP=1 violado: $WIP features in_progress"
fi

# Toda feature necesita la clave `evidence` (vacía al sembrar: `"evidence": []`).
SIN_EV=$(node -e '
  const f = require(require("path").resolve(process.argv[1])).features;
  const faltan = f.filter(x => !("evidence" in x)).map(x => x.id);
  process.stdout.write(faltan.length ? faltan.length + ": " + faltan.join(", ") : "0");
' "$FEATURES" 2>/dev/null)
if [ -n "$SIN_EV" ] && [ "$SIN_EV" != "0" ]; then
  bad "feature_list.json: features sin la clave \"evidence\" → $SIN_EV"
fi

# Gate anti-empates de `priority` entre features ACTIVAS
# (`not_started`/`in_progress`/`blocked`). El loop elige por `priority`
# ascendente entre esas tres, así que un empate deja la cola ambigua.
# Las `passing`/`superseded` están retiradas y NO compiten: pueden repetir
# números entre ellas y eso no es una violación — el filtro por estado vive
# dentro del script, no acá.
# El mismo script corre en el gate pre-push del repo de tooling
# ($TOOLING_REPO/scripts/check-hook.sh), así que un empate no llega a main;
# acá cubre el working tree ANTES de empezar a trabajar.
if ! TIES=$(node "$TOOLING_REPO/scripts/check-priority-ties.mjs" "$FEATURES" 2>&1); then
  bad "$TIES"
fi

# Ratchet: `passing` es irreversible salvo decisión humana registrada.
# Compara el working tree contra HEAD — no HEAD~1: lo que importa es lo que
# ya estaba commiteado. Sin commit previo legible del archivo (repo nuevo,
# primer commit todavía no hecho): fallback silencioso a verde.
HEAD_FEATURES=$(mktemp)
git -C "$TOOLING_REPO" show HEAD:harness/feature_list.json >"$HEAD_FEATURES" 2>/dev/null
REGRESSED=$(node -e '
  const fs = require("fs");
  const path = require("path");
  const [, headPath, curPath] = process.argv;
  let headPassing;
  try {
    const raw = fs.readFileSync(headPath, "utf8");
    if (!raw.trim()) throw new Error("sin commit previo del archivo");
    headPassing = new Set(JSON.parse(raw).features.filter(x => x.status === "passing").map(x => x.id));
  } catch (e) {
    process.exit(0);
  }
  const cur = require(path.resolve(curPath)).features;
  const curPassing = new Set(cur.filter(x => x.status === "passing").map(x => x.id));
  const regressed = [...headPassing].filter(id => !curPassing.has(id));
  if (regressed.length) process.stdout.write(regressed.join(", "));
' "$HEAD_FEATURES" "$FEATURES")
rm -f "$HEAD_FEATURES"
if [ -n "$REGRESSED" ]; then
  bad "ratchet violado: salió de \"passing\" sin decisión registrada en claude-progress.md → $REGRESSED"
fi

if [ "$FAIL" -eq 0 ]; then
  say "BASELINE VERDE — leé $INFRA_REPO/harness/claude-progress.md y elegí UNA feature."
else
  say "BASELINE ROJO — arreglá esto ANTES de cualquier feature nueva (Lecture 06)."
fi
exit "$FAIL"
