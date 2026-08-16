#!/bin/sh
# FUENTE ÚNICA: verifica que los hooks versionados en .githooks/ del repo QUE
# INVOCA estén bien instalados — modo ejecutable (100755) en el índice de git
# + core.hooksPath activo tras scripts/setup-hooks.sh.
#
# Repos hermanos que solo consumen este script (no lo modifican) pueden
# resolverlo por git-common-dir vía un shim liviano (patrón shim-vendorizado).
# Opera sobre la CWD, así que sirve igual invocado localmente o desde un shim
# de otro repo. POSIX sh puro, sin dependencias de stack (Node/Python/Go) —
# con UNA excepción acotada por guard: el gate anti-empates de `priority` del
# final invoca node, y SOLO donde existe `harness/feature_list.json` (o sea:
# solo en el repo de tooling ejecutable del harness).
#
# Generaliza el check_mode() por-hook: valida pre-push SIEMPRE (debe existir) y
# cualquier otro hook versionado (pre-commit si el repo lo tiene). Sustituye el
# chequeo inline de un solo hook y el duplicado literal.
set -e

check_mode() {
  hook="$1"
  mode=$(git ls-files -s "$hook" | awk '{print $1}')
  if [ "$mode" != "100755" ]; then
    echo "✋ $hook no es ejecutable en el índice de git (modo: ${mode:-ausente}, esperado: 100755)." >&2
    echo "   Corregir con: git update-index --chmod=+x $hook" >&2
    exit 1
  fi
}

# pre-push es obligatorio en todos los repos (fricción/gate del puente).
if ! git ls-files --error-unmatch .githooks/pre-push >/dev/null 2>&1; then
  echo "✋ falta .githooks/pre-push versionado en este repo." >&2
  exit 1
fi

# Valida el modo de TODO hook versionado en .githooks/ (pre-push + pre-commit + …).
checked=''
for hook in $(git ls-files .githooks/); do
  check_mode "$hook"
  checked="$checked $hook"
done

sh scripts/setup-hooks.sh

HOOKS_PATH=$(git config --get core.hooksPath || true)
if [ "$HOOKS_PATH" != ".githooks" ]; then
  echo "✋ core.hooksPath quedó en '${HOOKS_PATH:-(vacío)}', esperado '.githooks'." >&2
  exit 1
fi

# Gate anti-empates de `priority` entre features ACTIVAS del harness. Va acá
# porque este script ES (o alimenta) el gate pre-push del repo de tooling
# ejecutable del harness (.githooks/pre-push corre `sh scripts/check-hook.sh`).
# Un empate deja de poder llegar a main.
#
# EL GUARD ES EL REQUISITO, no una optimización: este mismo archivo corre por
# shim vendorizado en repos hermanos donde `harness/feature_list.json` no
# existe. Sin el guard, su gate pre-push se rompería por un archivo del
# harness que no les incumbe. Con el guard, allá ni siquiera se invoca a node.
if [ -f harness/feature_list.json ]; then
  node "$(dirname "$0")/check-priority-ties.mjs" harness/feature_list.json || exit 1
fi

echo "✅ hooks operativos:${checked}, core.hooksPath=.githooks"
exit 0
