# CLAUDE.md — Workspace __PROJECT_NAME__ (harness de nivel workspace)

Este workspace está diseñado para trabajo agéntico de larga duración. El
objetivo NO es maximizar código producido: es dejar el workspace en un
estado donde la próxima sesión continúe sin adivinar. (Curso: Lectures
01–03.)

## Mapa del workspace

- Raíz del workspace: **`$__WORKSPACE_ENV_VAR__`, nunca un path literal**.
  Default cuando esa env var no está seteada: `__WORKSPACE_DEFAULT__`. Es
  el padre que resuelve `.inflight/`.
- `__INFRA_REPO__/` — **system of record** (memoria a largo plazo). Todo
  conocimiento durable vive acá, git-tracked.
- Repos de apps del proyecto: `(completar — ej. __APP_REPOS__)`; cada uno
  con su propio `CLAUDE.md` (reglas locales, mandan sobre este archivo en
  su repo).
- **El harness vive partido, a propósito**: `__INFRA_REPO__` es docs-only,
  sin código ejecutable ni JSON de política.
  - `__INFRA_REPO__/harness/` — memoria durable del harness:
    `claude-progress.md`, `GOAL.md`, `clean-state-checklist.md`,
    `session-handoff.md`, `evaluator-rubric.md`, `prompts/`, y la copia
    canónica de este archivo (`CLAUDE.workspace.md`).
  - `__TOOLING_REPO__/harness/` — ejecutable + estado: `init.sh`,
    `loop.sh`, `loop-status.sh` y `feature_list.json`.
- `_scratch/` — reportes de scouts y efímeros (expiran, no son memoria).

## Startup Workflow ("clock in" — toda sesión, sin excepción)

1. `pwd` — confirmar dónde estás (workspace u repo).
2. Leer `__INFRA_REPO__/harness/claude-progress.md` — último estado
   verificado + next step.
3. Leer `__TOOLING_REPO__/harness/feature_list.json` — elegir LA feature
   no terminada de mayor prioridad. UNA sola.
4. `git -C <repo> log --oneline -5` en el/los repos que toque la feature.
5. Correr `__TOOLING_REPO__/harness/init.sh` — baseline de verificación
   del workspace.
6. Si el baseline ya está roto: arreglarlo ANTES de cualquier feature
   nueva.

## Working Rules (hard constraints — máx 15)

1. **WIP = 1**: una sola feature `in_progress` a la vez en todo el
   workspace. `awaiting_verifier` (terminada, esperando sello) no cuenta
   para este límite ni la vuelve a tocar el implementer — el loop la
   drena primero.
2. `passing` SOLO vía comando de verificación exitoso + evidencia
   registrada. Nunca "el código está escrito". **Ratchet**: de `passing`
   solo se sale por decisión explícita registrada en `claude-progress.md`
   — `init.sh` lo detecta y da ROJO si no.
3. **Nunca la misma entidad escribe Y califica**: verificación final por
   sesión/agente verifier independiente (ver `harness/prompts/verifier.md`).
4. No modificar estados del feature list para ocultar trabajo inconcluso;
   no debilitar/borrar tests para "completar".
5. Scout-first: antes de modificar código, scout read-only (sesión
   fresca).
6. Artefactos del repo > resúmenes de chat. Lo que no está commiteado en
   `__INFRA_REPO__` no existe.
7. **Política de costo**: `(completar — ej. COSTO CERO hasta el primer
   cliente pagando)`.
8. Puente sin CI: gate pre-push local obligatorio en los repos de apps
   (`.githooks/pre-push`, solo dispara en push a `main`). **Prohibido
   `--no-verify`. Si el gate falla por CUALQUIER motivo: FRENÁ, no
   pushees, reportá.**
9. Tareas que terminan en push a main van al modelo declarado en
   `harness/GOAL.md`/`PARAMS.md` (`__LOOP_MODEL__`), nunca a un modelo más
   barato sin criterio explícito.
10. Worktrees: máx 3 paralelos, tareas sin archivos compartidos, merge
    secuencial a main con review de diff.
11. Commits en `__INFRA_REPO__` vía claim inflight — el gate es el
    `pre-commit` que exige claim propio y falla ante claim ajeno vivo.
12. Contexto por paths, nunca pegar código; sesión fresca por tarea.
13. `(completar — convenciones propias del stack del proyecto, ej. rutas
    nuevas de backend → doc de arquitectura con gate)`.
14. Recordatorios/fechas SIEMPRE fuera de las conversaciones (tarea
    programada standalone).
15. No refactorizar B mientras implementás A; scope fuera de la feature
    activa = blocker documentado, no trabajo.

## Definition of Done (Lecture 09)

Una feature está done solo si TODO esto es cierto:
- comportamiento objetivo implementado;
- la verificación requerida CORRIÓ (niveles en orden: unit → integration
  → e2e; no avanzar de nivel con el anterior rojo);
- evidencia registrada en `__TOOLING_REPO__/harness/feature_list.json`
  (commit + salida del comando);
- el workspace sigue arrancable por `__TOOLING_REPO__/harness/init.sh`.

## End of Session ("clock out")

1. Actualizar `__INFRA_REPO__/harness/claude-progress.md` (sesión: goal,
   completed, verificación, evidencia, commits, riesgos, next best step).
2. Actualizar `__TOOLING_REPO__/harness/feature_list.json`.
3. Registrar blockers/riesgos no resueltos.
4. Borrar temporales y debug code; build + tests verdes.
5. Commit descriptivo cuando el estado sea seguro.
6. Pasar `__INFRA_REPO__/harness/clean-state-checklist.md`. Sesión
   completa = verificación pasa **Y** clean state pasa.
7. Sesión larga → `__INFRA_REPO__/harness/session-handoff.md`.

## Topic docs (cargar solo cuando aplique)

- `__INFRA_REPO__/README.md` — índice del system of record. | Siempre que
  toques `__INFRA_REPO__`.
- `__INFRA_REPO__/harness/patterns.md` — patrones de diseño del propio
  harness (ouroboros del verifier; protocolo de auto-modificación: el
  loop no trabaja sobre sí mismo, features `self_modifying` en sesión
  standalone). | Antes de escribir una `verification` o tocar
  `loop.sh`/`init.sh`/prompts.
- `__INFRA_REPO__/harness/GOAL.md` — goal + stopping conditions del loop
  autónomo. **Estado vigente (ON/OFF): lo dice GOAL.md, no este archivo.**
  | Solo en modo loop.

## Lanzamiento del loop

Generado por `bootstrap.sh` el __TODAY__ — completar acá el detalle real
de la máquina que corre el loop (SO, cómo se lanza en background, cómo
sobrevive a suspensión/reinicio, dónde viven las credenciales del CLI).

Comando base, adaptar al SO/shell real del proyecto:

```bash
export __WORKSPACE_ENV_VAR__="__WORKSPACE_DEFAULT__"
cd "$__WORKSPACE_ENV_VAR__"
nohup bash __TOOLING_REPO__/harness/loop.sh >> __TOOLING_REPO__/harness/logs/loop-nohup.log 2>&1 &
```

**Antes de lanzar —y antes de tomar cualquier feature `self_modifying`— la
pregunta «¿hay un loop vivo?» tiene UN comando canónico:**

```bash
bash __TOOLING_REPO__/harness/loop-status.sh
```

`rc 0` = hay loop vivo · `rc 1` = no hay · `rc 2` = indecidible (tratalo
como "hay"). No uses `pgrep -af "harness/loop[.]sh"` — matchea el prompt
de cualquier sesión que nombre el archivo (detalle y fallback en
[`patterns.md`](patterns.md) § «¿Hay un loop vivo?»).

- Lanzarlo con otro loop vivo no arranca un segundo scheduler: el segundo
  proceso sale con rc 8 nombrando el PID del dueño, sin tocar nada.
- Corrida acotada de prueba: `LOOP_MAX_ITER=1 bash
  __TOOLING_REPO__/harness/loop.sh` (al agotar el tope el runner sale con
  `STOP(max_iter)`, rc 5 — es el backstop diseñado, no un error).
- Logs por día en `__TOOLING_REPO__/harness/logs/loop-YYYYMMDD.log`;
  salidas de cada agente en `impl-*/verif-*.out` del mismo directorio.
