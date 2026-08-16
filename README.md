# harness-core

Harness genérico y parametrizado para el patrón "loop autónomo + verificador
independiente" (Lecture 13, nivel 4): `feature_list.json` como máquina de
estados, `init.sh` como baseline machine-checkable, `loop.sh` como runner de
sesiones frescas implementer/verifier, y prompts que nunca dejan que la misma
entidad escriba y califique.

Este repo es una PLANTILLA, no un proyecto corriendo: los artefactos de
`harness/` y `scripts/` traen placeholders `__NOMBRE__` en vez de nombres de
proyecto concretos. Consumirlo (forma de consumo aprobada: `bootstrap.sh
<app>`, generación por copia+sustitución, sin dependencia de submódulo) es
responsabilidad del script bootstrap de un repo cliente — este repo solo
provee el material fuente y su propio test suite de sandbox.

## Qué hay acá

- `scripts/` — 3 scripts GENÉRICOS, portables sin cambios: `check-hook.sh`
  (gate de hooks instalados + anti-empates de `priority`), `check-priority-ties.mjs`
  (algoritmo del gate anti-empates), `inflight.mjs` (registro de claims de
  trabajo en vuelo entre sesiones concurrentes). También `setup-hooks.sh`
  (activa `core.hooksPath=.githooks`, idempotente).
- `harness/init.sh`, `harness/loop.sh` — el baseline y el runner del loop,
  PARAMETRIZADOS vía las variables de `PARAMS.md`.
- `harness/loop-status.sh` — lectura de solo lectura de si hay un loop vivo
  (lockfile + fallback `pgrep` anclado al intérprete), GENÉRICO.
- `harness/session-handoff.md`, `harness/clean-state-checklist.md` — templates
  de clock-out, PARAMETRIZADOS solo en las rutas que citan.
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
  prueba en un workspace temporal (`mktemp -d`) y ejercita `init.sh`/`loop.sh`
  ahí, nunca contra un workspace real.

Lo que a propósito NO está acá (queda `ESPECÍFICO` de cada proyecto, según el
scout de origen — `plans/2026-08-16-tpl-scout-harness-core.md` del repo de
docs del proyecto que generó este template): `GOAL.md` real, `claude-progress.md`
real, `evaluator-rubric.md` con veredictos reales, `como-sembrar-features.md`/
`patterns.md` con ejemplos concretos, y el contenido real de cualquier
`feature_list.json`. Esos los escribe y mantiene cada proyecto cliente.

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
