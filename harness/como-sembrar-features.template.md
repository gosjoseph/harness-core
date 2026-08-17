# Cómo sembrar features sin pisar al loop

Procedimiento para cualquier sesión que agrega entradas nuevas a
[`__TOOLING_REPO__/harness/feature_list.json`](../../__TOOLING_REPO__/harness/feature_list.json).

1. **`git pull` primero.** Antes de editar `feature_list.json`, actualizá tu
   copia (`__TOOLING_REPO__` y, si vas a citar estado, `__INFRA_REPO__`).
   Sembrar sobre una copia vieja pisa features que otra sesión ya agregó o
   cambió de estado.
2. **Prioridad única, sin empates entre features activas — lo bloquea un
   gate automático.** Cada feature nueva recibe un `priority` entero que no
   repite el de ninguna otra `not_started`/`in_progress`/`blocked`
   existente. El loop toma la de menor número sin blocker.
   `scripts/check-priority-ties.mjs`, invocado por el gate pre-push
   (`scripts/check-hook.sh`) y por el baseline (`harness/init.sh`), frena un
   empate entre features activas antes de que llegue a `main` o conviva con
   un baseline verde. Una `passing`/`superseded` sí puede repetir el número
   de una activa o de otra retirada — no compiten. No hay regla de
   desempate implícito por orden del archivo: el gate frena antes de main,
   punto.
3. **`done` machine-checkable en `verification`.** Cada ítem de
   `verification` tiene que ser un comando o chequeo que corre y da un
   resultado binario (exit code, conteo de tests, diff vacío). Nada de
   "revisar que se vea bien". Si la feature exige una consola de terceros o
   una acción irreversible en producción, marcala con el prefijo
   `[MANUAL — <dueño>]` en el título en vez de escribir una verificación
   que un agente no puede correr solo — `active_feature()` en
   `harness/loop.sh` saltea toda feature cuyo `title` empiece con ese
   prefijo, en las tres ramas de la elección (`awaiting_verifier`,
   `in_progress`, `not_started`), con una línea `[manual] <id>: …` en el
   log. Ojo con el patrón **ouroboros**: si el ítem depende de "que una
   corrida del loop termine sin error", nombrá un artefacto ya persistido
   de una corrida ANTERIOR, no la corrida que spawneó a la sesión que
   verifica — ver
   [`patterns.md`](patterns.md#ouroboros-del-verifier-ninguna-verification-puede-depender-del-desenlace-del-proceso-que-la-spawnea).
4. **`blocked` siempre con la condición exacta de desbloqueo.** Si sembrás
   una feature que ya sabés bloqueada (depende de otra, de una decisión
   humana, o de una acción manual), status `blocked` desde el alta y la
   condición concreta en `notes` — no `not_started` con la esperanza de que
   alguien la descubra bloqueada recién al intentarla.
5. **Commit con el gate del repo verde.** `__TOOLING_REPO__` es código
   ejecutable: el alta pasa por el mismo gate pre-push que cualquier otro
   cambio del repo. No se pushea `feature_list.json` con el gate en rojo ni
   con `--no-verify`.
6. **Nunca tocar la feature `in_progress` ajena.** Si al sembrar ves una
   feature ya `in_progress`, no le cambiés el `status`, la `evidence` ni el
   `verification` — es de la sesión que la tomó. Agregá la tuya con su
   propio `priority` y seguí.
7. **`self_modifying: true` si la feature toca el harness mismo.** Si sus
   paths de destino incluyen `__TOOLING_REPO__/harness/loop.sh`, `init.sh`,
   `__HARNESS_DIR__/prompts/*.md` o el esquema de
   `feature_list.json`, marcala `self_modifying: true` al sembrarla: el
   loop la saltea (log «requiere sesión standalone») y se ejecuta
   —implementer y verifier— fuera del loop, con el loop apagado. El loop
   no trabaja sobre sí mismo; protocolo completo en
   [`patterns.md`](patterns.md#el-loop-no-trabaja-sobre-sí-mismo-protocolo-de-auto-modificación-del-harness).

   `self_modifying` es el PRIMER mecanismo de skip del loop; el SEGUNDO es
   el prefijo `[MANUAL — <dueño>]` en el `title`. Los dos viven en la misma
   función —`active_feature()` de `harness/loop.sh`— y tienen la misma
   forma: filtro en las tres ramas de la elección más una línea explícita
   en el log. Lo que los distingue es quién destraba: una `self_modifying`
   la toma una sesión standalone con el loop apagado; una
   `[MANUAL — <dueño>]` la ejecuta el humano dueño del proyecto, y ninguna
   sesión headless la reemplaza. Si lo único que queda sin blocker cae en
   cualquiera de las dos categorías, la selección vuelve vacía y la
   corrida cierra por la stopping condition (a) de [`GOAL.md`](GOAL.md) —
   es el resultado correcto, no una falla: ese trabajo no es del loop.

Esto es un procedimiento de siembra, no reemplaza el resto del harness: la
elección de CUÁL feature trabajar en una sesión sigue siendo la de mayor
prioridad sin blocker (`__HARNESS_DIR__/CLAUDE.workspace.md`,
Startup Workflow).

## Schema de una feature (10 campos)

Toda entrada de `features[]` en `feature_list.json` tiene **exactamente
estos 10 campos**, ni uno más ni uno menos:

1. **`id`** (string) — identificador único (convención libre por tema;
   lo único obligatorio es que no se repita).
2. **`priority`** (number, entero) — orden de ejecución; el loop toma la
   de MENOR número sin blocker. Sin empates entre features **activas**
   (regla 2 de arriba).
3. **`area`** (string) — componente(s) que toca, texto libre.
4. **`tema`** (string) — puntero al tema/doc dueño (spec, ADR, handoff);
   nunca copia el contenido de ese doc, solo referencia dónde vive.
5. **`title`** (string) — título corto. Campo con semántica ejecutable: el
   prefijo `[MANUAL — <dueño>]` lo lee `active_feature()` de `loop.sh` y
   saltea la feature en las tres ramas de la elección.
6. **`user_visible_behavior`** (string) — efecto observable para un
   humano; `"Ninguno"` es un valor literal válido para scouts read-only o
   cambios internos del propio harness.
7. **`status`** (string, enum) — uno de `not_started | in_progress |
   awaiting_verifier | blocked | passing | superseded`. Ver
   `status_legend` en la raíz del `feature_list.json` para qué pone cada
   transición y quién la pone (el implementer nunca escribe `passing`).
8. **`verification`** (array de string) — cada elemento es un chequeo
   machine-checkable: comando + resultado esperado y binario.
9. **`evidence`** (array) — `[]` (vacío) al sembrar, siempre. Lo llena el
   implementer/verifier al ejecutar.
10. **`notes`** (string, nunca vacío/null) — texto libre: condición exacta
    de `blocked`, follow-ups no bloqueantes, razón del `priority` elegido,
    cross-refs a otras features por id.

`init.sh` asierta el campo 9 (`evidence`): si alguna feature no tiene la
clave, el baseline queda **ROJO**.

**El archivo NO tiene, y no debe tener, un campo `blocked_by`.** Las
dependencias entre features se escriben como condición LITERAL en `notes`
(campo 10), citando feature-ids reales que ya existen, nunca un
placeholder tipo "cuando se siembre X".

## Checklist pre-commit (correlo antes de cada commit que siembra)

1. **JSON válido**: `jq . harness/feature_list.json > /dev/null` — sin
   salida, exit 0.
2. **IDs sin duplicados**: `jq '[.features[].id] | group_by(.) |
   map(select(length>1)) | length' harness/feature_list.json` → `0`.
3. **Prioridades sin duplicados entre features activas** — gate
   automático (`sh scripts/check-hook.sh` / `bash harness/init.sh`). A
   mano: `node scripts/check-priority-ties.mjs` → rc 0 y sin salida.
4. **Toda feature tiene `evidence`** (aunque sea `[]`): `jq '[.features[] |
   select(has("evidence") | not)] | length' harness/feature_list.json` →
   `0`.
5. **Conteo antes/después**: `jq '.features | length'
   harness/feature_list.json` corrido antes de sembrar y después — tiene
   que subir exactamente en la cantidad de features nuevas.
6. **Distribución de `status` idéntica salvo lo sembrado**: `jq -c
   '[.features[].status] | group_by(.) | map({(.[0]): length}) | add'
   harness/feature_list.json` antes/después — el único delta esperado es
   el de las features nuevas (todas `not_started` o `blocked`).
7. **Diff acotado**: `git show --numstat <sha>` → un solo archivo
   (`feature_list.json`), y el diff es ADITIVO salvo cambios a propósito
   (ej. bump de `last_updated`).
