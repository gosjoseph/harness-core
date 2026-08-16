# GOAL.md — Loop auto-alimentado (Lecture 13, nivel 4) — __PROJECT_NAME__

**ESTADO: OFF.** Esqueleto generado por `bootstrap.sh` — completar antes de
encender. El encendido (pasar a ON) es decisión explícita del dueño del
proyecto, registrada acá con fecha; ninguna sesión se auto-declara el derecho
a encender el loop ni a seguir corriendo.

## Goal de la corrida

**(completar)** — objetivo verificable, en términos de estado final, no de
actividad. Ejemplo de forma: "cerrar el checklist de Gate 1: N ítems
verificables, cada uno con su verificación y dueño".

## Los 3 componentes obligatorios del loop

1. **Goal**: estado final buscado, no una lista de tareas.
2. **Verificación machine-checkable**: el campo `verification` de cada
   feature de `__TOOLING_REPO__/harness/feature_list.json` + los gates
   pre-push por repo + cualquier gate de docs del repo `__INFRA_REPO__`.
   Nada de "looks good".
3. **Stopping conditions**: abajo. La salida NUNCA la decide el implementer.

## Alcance permitido (lo que el loop PUEDE hacer solo)

**(completar)** — por ejemplo: escribir código y tests en los repos de apps;
pushear a `main` con el gate pre-push local verde; deployar por el mecanismo
de deploy ya existente, con verificación post-deploy; escribir docs en
`__INFRA_REPO__` vía claim inflight.

## PROHIBIDO (sin excepción, sin "pero era obvio")

Esta lista rige al **LOOP** (`loop.sh`, sesiones implementer/verifier auto-
alimentadas sin humano mirando en vivo) — es lo que el loop NUNCA hace solo.
Completar los placeholders con el catálogo real del proyecto antes de
encender el loop.

- **Acciones destructivas en producción**: borrar datos, clientes, recursos.
- **Cambios de DNS** en cualquier zona.
- **Consolas de terceros**: `(completar catálogo — ej. AWS, Cloudflare,
  proveedor de pagos, proveedor de email transaccional, registrar de
  dominios, configuración del repo en GitHub/GitLab)`. Si una feature exige
  una consola, es `[MANUAL]`.
- **Cualquier cosa que cueste dinero**, hasta que el proyecto decida lo
  contrario: `(completar política de costo del proyecto)`.
- **Tocar features `blocked` o `[MANUAL]`**. Ni ejecutarlas, ni
  desbloquearlas, ni "adelantar un pedacito".
- **`--no-verify`**, debilitar tests, borrar tests, o bajar un umbral para
  que pase el gate.
- Marcar `passing` desde el implementer: ese sello es solo del verifier.

## Regla "infra en caliente" (parte del done, no un extra)

Cada feature actualiza sus docs de `__INFRA_REPO__` en la misma pasada — no
hay cierre batch por conversación separada. El verifier lo chequea como
parte del done: una feature con el código verde y el doc de infra sin tocar
es un `Revise`, no un `Accept`.

## Iteración (patrón ratchet, 9 pasos del curso)

1. Leer estado externo: `claude-progress.md` + `feature_list.json`.
2. Si hay alguna `awaiting_verifier`, drenarla primero (la de mayor
   prioridad) por el paso 8 directo — no abre trabajo nuevo mientras haya
   una terminada esperando sello. Si no hay ninguna: elegir la próxima
   `not_started` de mayor prioridad.
3. Implementar con `prompts/implementer.md` (worktree propio si toca
   código).
4. Correr la verificación machine-checkable de la feature.
5. Loggear resultado en `claude-progress.md`.
6. Éxito → merge/commit a main (gate pre-push; FRENÁ si rojo); la feature
   queda `awaiting_verifier`, no `in_progress`.
7. Fallo → rollback del worktree; feature → `blocked` con causa.
8. `passing` lo declara SOLO el verifier (`prompts/verifier.md`, sesión
   independiente, rúbrica) sobre una `awaiting_verifier`; si encuentra un
   gap, la devuelve a `in_progress`.
9. Actualizar memoria externa y repetir o parar según stopping conditions.

## Stopping conditions (duras)

- **(a) Todas las features desbloqueadas en `passing`** → clock-out final:
  `claude-progress.md` + `clean-state-checklist.md` + reporte. El loop no
  "busca más trabajo": las `blocked` no son trabajo disponible.
- **(b) Blocker que requiere decisión o acción del dueño del proyecto** →
  documentarlo en `claude-progress.md` con la pregunta exacta, frenar
  **ESA** feature (a `blocked`), y seguir con la siguiente por prioridad.
  No se para el loop.
- **(c) 3 intentos fallidos consecutivos en la misma feature** → `blocked`
  con el diagnóstico de los 3 intentos, y seguir. Un cuarto intento es
  terquedad, no ingeniería.
- **(d) Un deploy a prod falla** → rollback inmediato, feature a `blocked`,
  y **NUNCA reintentar deploys en loop**. Un deploy que falla dos veces
  igual es un incidente, no un retry.
- **(e) Gates en rojo que el loop NO causó** (baseline roto al arrancar,
  gate ajeno rojo, violación de gate detectada) → **FRENAR TODO**. No es
  una feature bloqueada: es el piso podrido, y apilar trabajo encima lo
  empeora.

Cualquier violación de gate (`--no-verify`, tests tocados, push sin gate) es
incidente: para el loop entero y se reporta.

## Reglas duras del loop

- Nunca la misma entidad escribe y califica (regla no negociable del
  curso).
- Compaction desde el primer loop: el estado vive en estos archivos, no en
  el contexto.
- Revisar el output del loop periódicamente (mitigación de comprehension
  rot).
- Política de costo: `(completar)` — el scheduler corre local; nada pago
  sin decisión explícita.
