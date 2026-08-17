# Patrones del harness — diseño reusable del loop

Patrones de **diseño del harness** "para siempre": defectos estructurales que
un harness de este patrón (loop autónomo + verificador independiente) tiende
a redescubrir a los golpes si no quedan escritos. Separado del Session Log
narrativo (`claude-progress.md`, que cuenta CUÁNDO pasó algo) — acá vive SOLO
el patrón, sin el detalle operativo del incidente puntual que lo originó (eso
va en el Session Log, con un puntero de vuelta desde acá cuando exista).

## Índice

- [Ouroboros del verifier: ninguna `verification` puede depender del desenlace del proceso que la spawnea](#ouroboros-del-verifier-ninguna-verification-puede-depender-del-desenlace-del-proceso-que-la-spawnea)
- [El loop no trabaja sobre sí mismo: protocolo de auto-modificación del harness](#el-loop-no-trabaja-sobre-sí-mismo-protocolo-de-auto-modificación-del-harness)

## Ouroboros del verifier: ninguna `verification` puede depender del desenlace del proceso que la spawnea

> Caso particular de la clase más general
> [El loop no trabaja sobre sí mismo](#el-loop-no-trabaja-sobre-sí-mismo-protocolo-de-auto-modificación-del-harness),
> aplicado a las `verification`.

**Cuándo aplica.** Vas a escribir (o revisar) un ítem de `verification` en
`feature_list.json` que pide algo como "una corrida real termine sin error" —
típicamente del propio `loop.sh`, pero el patrón generaliza a cualquier
proceso que spawnea sesiones hijas (`claude -p`) para hacer su propio
trabajo: implementer, verifier, o cualquier futuro rol del harness.

**La trampa.** `loop.sh` corre `impl-<feature>` y `verif-<feature>` como
sesiones HIJAS, y recién escribe la línea final de la corrida (`STOP(...)`)
DESPUÉS de que la última sesión hija termina. Si la `verification` de una
feature exige "leer esa línea final", la sesión que la ejecuta —sea
implementer o verifier— **no puede verla nunca**: para que la línea exista,
ella misma tiene que haber terminado primero. El reflejo natural
("re-correr el loop para verla") no arregla nada: reproduce la misma trampa
un nivel más adentro, y además quema un intento de la stopping condition (c)
de `GOAL.md` cada vez que se intenta.

**La regla (evidencia por artefacto persistido, no por skip en `loop.sh`).**
Ninguna `verification` puede depender del **estado o desenlace del proceso
que spawnea a la sesión que verifica**. La evidencia siempre tiene que ser
un **artefacto ya persistido** — un archivo o una línea de log de una
corrida ANTERIOR, ya completa antes de que la sesión verificadora arrancara
— nunca "esperá a que termine lo que me lanzó". Un artefacto persistido lo
puede leer y confirmar CUALQUIER sesión, incluida una que resulte ser hija
del propio proceso que lo generó, porque no depende de que ese proceso
termine primero: solo depende de que el archivo ya exista en disco al
momento de leerlo.

Se prefirió esta opción sobre "`loop.sh` detecta el caso y saltea el
verifier": requeriría que el runner entienda semánticamente el contenido de
cada `verification` para decidir si es auto-referencial, lo cual no es
mecánico. Exigir un artefacto persistido sí lo es — se audita con `grep`
sobre el texto del ítem, sin tocar `loop.sh`.

**Receta mínima al escribir el ítem de `verification`:**

1. Nombrá el artefacto persistido exacto (`harness/logs/loop-YYYYMMDD.log`,
   no "la corrida" en abstracto), y el criterio textual sobre su contenido
   (última línea, ausencia de un patrón de error).
2. Explicitá que puede ser de una corrida previa, ya terminada — nunca la
   corrida que spawneó la sesión que verifica.
3. Evitá frases como "termine sin error" o "corra y confirme" sin nombrar el
   artefacto: eso es exactamente lo que reintroduce la trampa, porque suena a
   "observá que pase", no a "leé lo que ya quedó escrito".

**Trade-off.** Una feature que de verdad necesita observar una corrida EN
VIVO (no solo su resultado persistido) no puede verificarse por una sesión
nacida de esa misma corrida — necesita una sesión standalone, lanzada por el
dueño del proyecto o por una corrida POSTERIOR del loop, nunca por la
corrida bajo prueba. Si eso es exactamente lo que hace falta, decilo así en
`notes` de la feature en vez de forzar una `verification` que ningún agente
puede satisfacer solo.

**Evidencia real**: agregá acá el puntero a la sesión de `claude-progress.md`
la primera vez que este patrón se descubra a los golpes en este proyecto —
el esqueleto no trae ninguna todavía.

## El loop no trabaja sobre sí mismo: protocolo de auto-modificación del harness

**Cuándo aplica.** Una feature cuyos paths de destino incluyen ejecutables o
prompts del harness: `__TOOLING_REPO__/harness/loop.sh`, `init.sh`,
`__HARNESS_DIR__/prompts/*.md`, o el esquema de
`__TOOLING_REPO__/harness/feature_list.json`. También cualquier sesión que,
sin ser una feature, vaya a editar esos archivos con un loop vivo.

**La clase del defecto.** El harness trabajando sobre sí mismo mientras
corre. Tres formas conocidas, cada una con cara distinta y la misma raíz:

1. **Ouroboros del verifier**: una `verification` que depende del desenlace
   del proceso que spawnea a la sesión que verifica. Regla propia arriba en
   este mismo doc — es esta clase aplicada a las `verification`.
2. **Edición en caliente del runner**: el implementer edita `loop.sh`
   in-place mientras un loop lo ejecuta. bash lee el script por offset de
   byte: una edición in-place desplaza los offsets y el intérprete puede
   saltar a mitad de línea — comportamiento indefinido, no solo "código
   viejo".
3. **Stale code de la corrida larga**: una corrida implementa un fix al
   propio `loop.sh` en una iteración temprana y sigue horas con las
   funciones pre-fix ya parseadas en memoria, evaluando stopping conditions
   con lógica vieja.

**La regla.** El loop NO trabaja sobre sí mismo:

- Toda feature así se siembra con `self_modifying: true` en
  `feature_list.json` (campo documentado en su bloque `rules`; el marcado
  es manual al sembrar, regla 7 de
  [`como-sembrar-features.md`](como-sembrar-features.md)).
- `active_feature()` de `loop.sh` la saltea en TODAS las ramas
  (`not_started`, `in_progress`, `awaiting_verifier`) logueando
  `[selfmod] <id>: requiere sesión standalone`. Si solo queda trabajo
  self_modifying, la selección vuelve vacía y la corrida cierra por la
  stopping condition (a): correcto — ese trabajo no es del loop.
- Implementer Y verifier de una feature `self_modifying` corren como
  sesiones standalone (mismo mecanismo que el drenaje manual de
  verifiers), con el loop APAGADO — confirmarlo con el comando canónico
  `bash __TOOLING_REPO__/harness/loop-status.sh` antes de arrancar (rc 0 =
  hay loop vivo, rc 1 = no hay; ver § «¿Hay un loop vivo?» abajo).
- Toda edición de un ejecutable del harness se escribe a archivo temporal y
  se aplica con `mv`/rename sobre el destino: el rename apunta el nombre a
  un inode nuevo y el bash en ejecución conserva el archivo viejo íntegro.
  NUNCA edición in-place. Complemento en runtime: `loop.sh` captura el hash
  sha256 de su propio archivo al arrancar y lo recomputa al tope de CADA
  iteración, antes de evaluar stopping conditions; si difiere, frena con
  `STOP(reload)` (rc 7) y mensaje explícito de relanzar. NUNCA re-exec —
  re-ejecutarse arriesga repetir la iteración en curso y ensuciar el
  estado; el loop está diseñado para relanzarse barato.
- **Tercera protección del runner: `loop.sh` es single-instance por
  lockfile.** Al arrancar toma `__TOOLING_REPO__/harness/.loop.lock` (fuera
  de git); si detecta otro loop VIVO sale con **rc 8** nombrando el PID del
  dueño, **sin esperar, sin matar y sin tocar nada**. Un lock huérfano
  —dueño muerto o PID reciclado— no bloquea: se descarta y el loop nuevo
  arranca normal. Un pidfile ilegible tampoco se asume libre: sale por rc 8
  pidiendo revisión, porque arrancar de más es el defecto que la protección
  existe para evitar. Las tres protecciones cubren cosas distintas y
  ninguna sustituye a otra: el self-hash detecta que el runner **cambió**
  mientras corría, el temp+`mv` hace que ese cambio sea **seguro**, y el
  lock impide que haya **dos** runners.

**Evidencia real**: agregá acá el puntero a `claude-progress.md` la primera
vez que este patrón se dispare en este proyecto.

## ¿Hay un loop vivo? El lockfile es la fuente de verdad

**El comando canónico**, desde la raíz del workspace:

```bash
bash __TOOLING_REPO__/harness/loop-status.sh
```

`rc 0` = hay un loop vivo (no lances otro, no tomes features
`self_modifying`). `rc 1` = no hay. `rc 2` = indecidible (lockfile
ilegible), que se trata como "hay loop vivo" hasta resolverlo a mano. El
script es de **solo lectura**: no puede arrancar un loop ni por accidente,
que es justamente por qué la pregunta no se le hace a `loop.sh`.

**Por qué NO se pregunta con `pgrep -af "harness/loop[.]sh"`.** Ese patrón
matchea la línea de comando de cualquier proceso que **contenga esa
cadena** — y una sesión headless es `claude -p <prompt>`, así que un prompt
que nombra `harness/loop.sh` como texto se matchea a sí mismo. Un archivo
que **solo escribe el runner** no se confunde con el texto de un prompt.
Esa es toda la diferencia.

**El `pgrep` queda como fallback, y `loop-status.sh` ya lo cruza solo.** Un
loop lanzado con un `loop.sh` sin lockfile, o un lockfile borrado a mano,
hacen que el script mida también los procesos y **reporte la discrepancia**
en vez de esconderla, tomando la respuesta conservadora (hay loop vivo). A
mano, el fallback se ancla al **intérprete**, nunca a la ruta:

```bash
pgrep -af "bash.*loop\.sh"
```

y aun así: un match cuya línea de comando sea `claude -p` **es una
sesión**, nunca el runner.

### Ya no se reinventa por sesión: es el paso 0 de los dos prompts

`__HARNESS_DIR__/prompts/implementer.md` y
`__HARNESS_DIR__/prompts/verifier.md` arrancan con este comando y
con la lectura de los tres rc escrita.

Lo que ese paso 0 agrega, y que el comando por sí solo no da: **`rc 0` no
significa «frená»**. Una sesión que el loop spawneó ve `rc 0` **por
construcción** —su propio padre tiene el lock—, así que el paso 0 bifurca
por **ancestría**: si el PID dueño del lock es un ancestro de la sesión,
ese loop es su padre y se sigue normal; si no lo es, hay un loop **ajeno**
sobre el mismo working tree (no lanzar otro, ediciones de
`feature_list.json` atómicas). En los dos casos, las features
`self_modifying` quedan fuera. `rc 1` es el único rc que las habilita, y
`rc 2` el único que corta la sesión (stopping condition (e)).
