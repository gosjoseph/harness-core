# Evaluator Rubric (Lecture 11) — la completa SOLO el verifier

Usar después de la implementación y antes de la aceptación final.
Umbral duro: cualquier categoría en 0 = sprint fallido (no se promedia).
Todo rechazo cita evidencia específica (archivo, comando, salida).

Generado vacío por `bootstrap.sh` el __TODAY__ — cada sesión verifier copia
este esqueleto de categorías al tope de su propia entrada en
`claude-progress.md` (o a un archivo separado si el proyecto lo prefiere) y
la completa con evidencia real, nunca a mano alzada.

**Paso 0 — ¿hay un loop vivo?** `bash __TOOLING_REPO__/harness/loop-status.sh`
→ pegar la salida completa y la lectura del rc acá.

## Categorías

### 1. Verificación re-ejecutada (no confiar en evidencia pegada)

El verifier corre de nuevo, desde cero, cada comando de `verification` de
la feature — no reutiliza la salida que dejó el implementer.

### 2. `init.sh` verde (restartable)

`bash __TOOLING_REPO__/harness/init.sh` da BASELINE VERDE sobre el HEAD que
se está evaluando.

### 3. Sin debug code / temporales / tests debilitados

Sin `console.log`/`print`/`debugger` de depuración, sin archivos
temporales versionados, sin tests borrados o su umbral bajado para pasar.

### 4. Scope

El diff toca solo lo que la feature declara — nada de refactors o
"aprovecho y arreglo" fuera de scope.

### 5. `clean-state-checklist.md`

Los ítems del checklist, uno por uno, con evidencia de cada uno.

### 6. "Infra en caliente" (docs actualizados en la misma pasada)

Si la feature tocó comportamiento, el doc de `__INFRA_REPO__` correspondiente
está actualizado en el mismo commit/pasada — no en una sesión futura.

### 7. Evidencia auditable (ruta de artefacto citada)

Cada bullet de `evidence` cita comando + salida esencial + la ruta del
artefacto (log del loop o sección de `claude-progress.md` si fue
standalone).

### 8. Nada sin publicar

`main == origin/main` en cada repo tocado, verificado DESPUÉS del último
commit.

## Observaciones (no cambian el veredicto)

(completar si aplica)

## Veredicto final

**Accept / Revise / Block** — con la razón puntual si no es Accept.
