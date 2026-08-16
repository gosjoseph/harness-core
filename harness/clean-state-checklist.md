# Clean State Checklist (Lecture 12) — pasar en TODO clock out

- [ ] El startup estándar sigue funcionando (`__TOOLING_REPO__/harness/init.sh` verde).
- [ ] La verificación estándar corre (gates pre-push por repo; gate de docs del repo de docs).
- [ ] El progreso quedó registrado en `claude-progress.md`.
- [ ] `feature_list.json` refleja lo que REALMENTE pasa vs lo no verificado.
- [ ] Sin debug code (console.log/debugger/prints) ni temporales (los efímeros van a un directorio de scratch, no versionado como memoria).
- [ ] Ningún paso a medias sin documentar (blocker anotado con causa).
- [ ] Worktrees: los del sprint removidos tras merge; `git worktree list` = 1 línea por repo.
- [ ] Sin claims inflight colgados a nombre de esta sesión.
- [ ] Todo lo commiteado está PUBLICADO — `main == origin/main` en cada repo
      tocado, verificado DESPUÉS del último commit:
      `git fetch -q origin main && [ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ]`.
      Trabajo sellado que vive solo en commits locales es invisible para el
      ratchet de `init.sh` (compara contra HEAD local) y para cualquier otra
      sesión o máquina, y termina publicado por arrastre del push de otro
      commit sin relación — mejor evitarlo desde el vamos.
- [ ] La próxima sesión puede continuar sin reparación manual.

Sesión completa = verificación de la feature pasa **Y** este checklist pasa.
