#!/usr/bin/env node
// check-priority-ties.mjs — gate duro anti-empates de `priority` entre las
// features ACTIVAS del harness.
//
// POR QUÉ EXISTE. El loop elige trabajo por `priority` ascendente entre las
// features `not_started`/`in_progress`/`blocked`. La regla de
// harness/como-sembrar-features.md prohíbe el empate, pero sin un gate
// automático la prohibición solo rige si alguien se acuerda de chequearla a
// mano — y con el tiempo alguien no se acuerda.
//
// ALCANCE REAL, sin sobrevender: este script corre en el gate PRE-PUSH del
// repo de tooling ejecutable del harness (`scripts/check-hook.sh`, invocado
// por `.githooks/pre-push`) y en el baseline (`harness/init.sh`). O sea: un
// empate entre features activas NO llega a main y NO deja empezar a
// trabajar. Lo que SÍ sigue pudiendo pasar es un commit local con el empate
// adentro — no hay hook pre-commit que corra este chequeo, y el gate lo
// frena recién al pushear.
//
// EL FILTRO POR ESTADO ES EL GATE, no un detalle de implementación. Solo
// compiten por la cola las features activas; una `passing` o `superseded`
// está retirada y puede repetir el número de otra retirada — eso NO es una
// violación. Un chequeo sin filtrar nace rojo por historial legítimo y se
// desactiva a la semana.
//
// INERTE DONDE NO HAY HARNESS. `scripts/check-hook.sh` puede correr por shim
// vendorizado en repos hermanos donde `harness/feature_list.json` no existe:
// sin archivo, este script sale rc 0 sin ruido. Romper el gate pre-push de
// repos que no tienen nada que ver con el harness sería una regresión.
//
// Uso:  node scripts/check-priority-ties.mjs [<ruta al feature_list.json>]
//       (sin argumento: `harness/feature_list.json` relativo a la CWD, que es
//       como lo invoca check-hook.sh — opera sobre la CWD del repo que llama).
// Salida: rc 0 sin empates (o sin archivo); rc 1 nombrando los ids empatados y
//       el número repetido.

import fs from 'node:fs';

// Los tres estados que compiten por la cola del loop (regla de
// como-sembrar-features.md). `awaiting_verifier` terminó y espera sello, no
// compite; `passing`/`superseded` están retiradas.
const ACTIVOS = ['not_started', 'in_progress', 'blocked'];

const file = process.argv[2] || 'harness/feature_list.json';

// Inerte: este repo no tiene harness. Sin ruido, sin rc de error.
if (!fs.existsSync(file)) process.exit(0);

let features;
try {
  const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
  features = parsed.features;
  if (!Array.isArray(features)) throw new Error('`features` no es un array');
} catch (e) {
  console.error(`✋ ${file} no parsea: ${e.message.split('\n')[0]}`);
  process.exit(1);
}

const porPrioridad = new Map();
for (const f of features) {
  if (!ACTIVOS.includes(f.status)) continue;
  if (!porPrioridad.has(f.priority)) porPrioridad.set(f.priority, []);
  porPrioridad.get(f.priority).push(f.id);
}

const empates = [...porPrioridad.entries()]
  .filter(([, ids]) => ids.length > 1)
  .sort((a, b) => a[0] - b[0]);

if (empates.length > 0) {
  console.error(`✋ empate de priority entre features ACTIVAS (${ACTIVOS.join('/')}) en ${file}:`);
  for (const [prioridad, ids] of empates) {
    console.error(`   priority ${prioridad}: ${ids.join(', ')}`);
  }
  console.error('   Regla de harness/como-sembrar-features.md: cada feature activa lleva');
  console.error('   un priority entero único. No hay regla de desempate — se renumera.');
  console.error('   La renumeración la hace la sesión de siembra, nunca una feature del loop.');
  process.exit(1);
}

process.exit(0);
