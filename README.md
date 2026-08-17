# harness-core

Harness genérico y parametrizado para el patrón "loop autónomo + verificador
independiente" (Lecture 13, nivel 4): `feature_list.json` como máquina de
estados, `init.sh` como baseline machine-checkable, `loop.sh` como runner de
sesiones frescas implementer/verifier, y prompts que nunca dejan que la misma
entidad escriba y califique.

Este repo es una PLANTILLA, no un proyecto corriendo: los artefactos de
`harness/` y `scripts/` traen placeholders `__NOMBRE__` en vez de nombres de
proyecto concretos. Consumirlo es correr `bootstrap.sh <app>` (generación por
copia+sustitución, sin dependencia de submódulo) desde el directorio destino
— ver «Cómo generar un harness nuevo» abajo.

## Qué hay acá

- `bootstrap.sh <app> [destino]` — genera el harness completo (tooling +
  skeleton de infra) en el directorio destino (default: cwd), sin dejar
  dependencia de submódulo. Ver «Cómo generar un harness nuevo» abajo.
- `scripts/` — scripts GENÉRICOS, portables sin cambios: `check-hook.sh`
  (gate de hooks instalados + anti-empates de `priority`), `check-priority-ties.mjs`
  (algoritmo del gate anti-empates), `inflight.mjs` (registro de claims de
  trabajo en vuelo entre sesiones concurrentes), `setup-hooks.sh` (activa
  `core.hooksPath=.githooks`, idempotente), y `render.sh` (sustituye
  variables `__NOMBRE__` sobre un árbol de archivos — lo usan `bootstrap.sh`
  y `tests/run-tests.sh`).
- `harness/init.sh`, `harness/loop.sh` — el baseline y el runner del loop,
  PARAMETRIZADOS vía las variables de `PARAMS.md`.
- `harness/loop-status.sh` — lectura de solo lectura de si hay un loop vivo
  (lockfile + fallback `pgrep` anclado al intérprete), GENÉRICO.
- `harness/session-handoff.md`, `harness/clean-state-checklist.md` — templates
  de clock-out, PARAMETRIZADOS solo en las rutas que citan.
- `harness/GOAL.template.md`, `harness/claude-progress.template.md`,
  `harness/evaluator-rubric.template.md`, `harness/como-sembrar-features.template.md`,
  `harness/patterns.template.md`, `harness/CLAUDE.workspace.template.md` —
  skeletons de la memoria durable de `infra/harness/` que genera
  `bootstrap.sh`: procedimiento y estructura reusables, con el contenido
  narrativo/de negocio (goal real, catálogo de consolas prohibidas,
  veredictos, sesiones) removido a propósito — lo completa cada proyecto
  cliente.
- `harness/prompts/implementer.md`, `harness/prompts/verifier.md` — los dos
  roles del patrón "nunca la misma entidad escribe y califica",
  PARAMETRIZADOS en rutas y nombre del proyecto.
- `harness/feature_list.template.json` — el schema de 10 campos por feature
  (`id/priority/area/tema/title/user_visible_behavior/status/verification/evidence/notes`)
  con `features: []` — un proyecto nuevo arranca de acá, no del contenido real
  de ningún proyecto existente.
- `.githooks/pre-push` — el gate "puente sin CI" que corre `scripts/check-hook.sh`
  antes de dejar pasar un push a `main`.
- `tests/` — suite de sandbox: renderiza los templates con variables de
  prueba en un workspace temporal (`mktemp -d`) y ejercita
  `init.sh`/`loop.sh`/`bootstrap.sh` ahí, nunca contra un workspace real.
  Incluye un test MULTI-LOOP: dos harnesses bootstrapeados en sandboxes
  separados corren `loop.sh` a la vez sin colisión de locks, logs ni
  commits.

Lo que a propósito NO está acá (contenido real, específico de cada
proyecto): el `GOAL.md` completo (objetivo y catálogo de restricciones del
negocio), las sesiones reales de `claude-progress.md`, los veredictos reales
de `evaluator-rubric.md`, los ejemplos numéricos de
`como-sembrar-features.md`/`patterns.md`, y el contenido real de cualquier
`feature_list.json`. Esos los escribe y mantiene cada proyecto cliente sobre
el skeleton que genera `bootstrap.sh`.

## Cómo generar un harness nuevo

```bash
mkdir mi-proyecto-nuevo && cd mi-proyecto-nuevo
bash /ruta/a/harness-core/bootstrap.sh mi-proyecto-nuevo
```

Genera `mi-proyecto-nuevo_tooling/` (ejecutable + `feature_list.json` vacío)
y `infra/` (skeleton de `harness/`) en el directorio actual. Variables de
config opcionales por entorno (`PROJECT_NAME`, `WORKSPACE_ENV_VAR`,
`TOOLING_REPO`, `APP_REPOS`, etc. — ver `PARAMS.md`); sin ellas, `bootstrap.sh`
deriva defaults razonables del nombre del proyecto y nunca lee de stdin. El
script termina imprimiendo qué generó y qué queda pendiente de completar a
mano (el `GOAL.md` real, el catálogo de restricciones del negocio, sembrar
`feature_list.json`).

### Varias apps sobre el MISMO repo docs-only: `HARNESS_DIR`

Por default la memoria durable del harness va a `<__INFRA_REPO__>/harness/`
(o sea `infra/harness/` con los defaults). Dos apps que comparten el mismo
repo `infra` se pisarían ahí. `HARNESS_DIR` —relativo a la raíz del
workspace, no al repo— la anida por app:

```bash
HARNESS_DIR=infra/harness/kayzen bash /ruta/a/harness-core/bootstrap.sh kayzen
```

Genera la memoria en `infra/harness/kayzen/` (`GOAL.md`,
`claude-progress.md`, `prompts/`, …) y deja `infra/harness/` raíz intacto
para la otra app. El `init.sh` y el `loop.sh` generados resuelven sus rutas
desde esa variable, ya sustituida: no hay nada que exportar en runtime.
Sin la variable, el comportamiento es exactamente el de siempre.

## Variables de parametrización

Declaración única en `PARAMS.md` (una por línea, `__NOMBRE__` + descripción).
Esta tabla documenta cada una con su default sugerido — incidentalmente,
`PARAMS.md` y esta tabla tienen que listar exactamente las mismas variables
(mismo conteo, mismos nombres); es parte de la verificación de este repo.

| variable | default sugerido | qué sustituye |
|---|---|---|
| `__PROJECT_NAME__` | (nombre del proyecto) | nombre humano usado en comentarios/prompts |
| `__WORKSPACE_ENV_VAR__` | `<PROYECTO>_WORKSPACE` | nombre de la env var de la raíz del workspace |
| `__WORKSPACE_DEFAULT__` | `$HOME/<proyecto>` | path default si esa env var no está seteada |
| `__INFRA_REPO__` | `infra` | directorio del repo docs-only (memoria durable) |
| `__HARNESS_DIR__` | `<__INFRA_REPO__>/harness` | directorio de la memoria durable del harness, relativo a la raíz del workspace; anidarlo (`infra/harness/<app>`) deja que varias apps compartan un mismo repo docs-only |
| `__TOOLING_REPO__` | `<proyecto>_tooling` | directorio del repo de tooling ejecutable |
| `__APP_REPOS__` | (vacío o lista espaciada) | repos de apps del proyecto |
| `__APP_REPO_FULL_CMDS__` | (vacío o lista espaciada) | comando de suite completa por repo de `__APP_REPOS__`, mismo orden |
| `__LOOP_MODEL__` | `sonnet` | modelo default de las sesiones implementer |
| `__VERIFIER_MODEL__` | `sonnet` | modelo default de las sesiones verifier |
| `__TODAY__` | (fecha ISO del día de generación) | `last_updated` del `feature_list.json` inicial |

Verificación de que las dos listas coinciden:

```bash
diff <(grep -oP '^__[A-Z_]+__' PARAMS.md | sort -u) \
     <(grep -oP '^\|\s*`\K__[A-Z_]+__' README.md | sort -u)
```

## Cómo correr los tests de sandbox

```bash
bash tests/run-tests.sh
```

Nunca toca `$__WORKSPACE_ENV_VAR__` real: todo corre en un `mktemp -d`
descartable. Ver `tests/run-tests.sh` para el detalle de qué renderiza y qué
asierta (incluye 1 test que corre `loop.sh` real con `LOOP_MAX_ITER=1` sobre
el sandbox y confirma la salida `STOP(max_iter)` / rc 5 — el backstop de fuga
diseñado, no un error).

## Gate de push

`.githooks/pre-push` corre `sh scripts/check-hook.sh` antes de cualquier push
a `main`. Activar tras clonar: `sh scripts/setup-hooks.sh`.
