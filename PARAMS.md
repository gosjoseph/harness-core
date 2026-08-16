# Variables de parametrización — declaración única

Este archivo es la fuente única de qué variables sustituye `bootstrap.sh` (o
quien genere un proyecto nuevo a partir de este template) en los artefactos
de `harness/` y `scripts/`. Una variable por línea, formato `__NOMBRE__ —
descripción corta`. La tabla de `README.md` tiene que listar exactamente las
mismas (mismo conteo, mismos nombres) — es la verificación de
`TPL-F1`/`TPL-F0`: un archivo declara, el otro documenta con su default, y
tienen que coincidir.

__PROJECT_NAME__ — nombre humano del proyecto (ej. "Gosjoseph").
__WORKSPACE_ENV_VAR__ — nombre de la env var que apunta a la raíz del workspace (ej. "GOSJOSEPH_WORKSPACE").
__WORKSPACE_DEFAULT__ — path default cuando esa env var no está seteada (ej. "$HOME/gosjoseph").
__INFRA_REPO__ — nombre del directorio del repo docs-only (memoria durable del harness).
__TOOLING_REPO__ — nombre del directorio del repo de tooling ejecutable (init.sh/loop.sh/feature_list.json).
__APP_REPOS__ — lista espaciada de nombres de directorio de los repos de apps del proyecto (puede ir vacía).
__APP_REPO_FULL_CMDS__ — lista espaciada, mismo orden que __APP_REPOS__, de comandos de verificación completa por repo (usados solo bajo INIT_FULL=1).
__LOOP_MODEL__ — modelo default para las sesiones implementer del loop.
__VERIFIER_MODEL__ — modelo default para las sesiones verifier del loop.
__TODAY__ — fecha ISO (YYYY-MM-DD) de generación, sustituida una sola vez al correr el bootstrap.
