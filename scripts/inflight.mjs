#!/usr/bin/env node
// inflight.mjs — registro proactivo de trabajo en vuelo entre sesiones de
// Claude Code concurrentes (infra/pending.md ítem (k)). Gemelo conceptual de
// wt-gc.mjs: ambos son "todo mecanismo que crea recursos necesita un
// recolector" (infra/platform/gotchas.md) aplicado a un recurso distinto.
//
// Registro fuera de git, en <workspace>/.inflight/<session_id>.json — un
// archivo por sesión. Liveness = proceso vivo con el mismo lstart (evita
// falsos positivos por reciclaje de PID) + TTL backstop de 24h.
//
// Subcomandos:
//   claim <repo> <tema> <path...>   crea/actualiza el claim de esta sesión
//   release                         borra el claim propio
//   list                            tabla de claims (vivos y stale)
//   check <repo> <path...>          exit 1 si hay colisión con claim ajeno vivo;
//                                    en infra, además exit 1 si falta claim propio
//   gc                              archiva (no borra) claims stale a _gc/
//
// `check` corre `gc` primero siempre — el recolector es parte del gate, no un
// cron aparte.

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ponytail: default relativo al propio repo (el repo de tooling ejecutable vive bajo <workspace>/<tooling-repo>),
// override total vía env var si el layout cambia (mismo patrón que wt-gc.mjs).
const WORKSPACE_ROOT = process.env.WORKSPACE_ROOT || path.resolve(__dirname, '../..');
const INFLIGHT_DIR = process.env.INFLIGHT_DIR || path.join(WORKSPACE_ROOT, '.inflight');
const GC_DIR = path.join(INFLIGHT_DIR, '_gc');
const TTL_MS = 24 * 60 * 60 * 1000;

function sh(args) {
  return execFileSync(args[0], args.slice(1), { encoding: 'utf8' });
}
function shOk(args) {
  try { return { ok: true, out: sh(args) }; } catch (e) { return { ok: false, out: e.stdout || e.message }; }
}

function claimPath(sessionId) {
  return path.join(INFLIGHT_DIR, `${sessionId}.json`);
}

function requireEnv() {
  const sessionId = process.env.CLAUDE_CODE_SESSION_ID;
  const pid = process.env.CLAUDE_PID;
  if (!sessionId || !pid) {
    console.error('✋ Falta CLAUDE_CODE_SESSION_ID o CLAUDE_PID en el entorno.');
    console.error('   Este comando corre dentro de una sesión de Claude Code, no a mano.');
    process.exit(1);
  }
  return { sessionId, pid: Number(pid) };
}

function pidStartTime(pid) {
  if (process.platform === 'win32') {
    // El ps.exe de Git Bash no soporta `-o lstart=`; en Windows la fecha de
    // arranque sale de PowerShell. ToFileTimeUtc() da un entero estable
    // (independiente de locale) — mismo rol que lstart: detectar PID reciclado.
    const res = shOk(['powershell.exe', '-NoProfile', '-Command',
      `(Get-Process -Id ${Number(pid)}).StartTime.ToFileTimeUtc()`]);
    if (!res.ok) return null;
    return res.out.trim() || null;
  }
  const res = shOk(['ps', '-o', 'lstart=', '-p', String(pid)]);
  if (!res.ok) return null;
  return res.out.trim();
}

function isAlive(claim) {
  if (!claim || !claim.pid || !claim.pid_start_time) return false;
  const lstart = pidStartTime(claim.pid);
  if (lstart === null || lstart !== claim.pid_start_time) return false; // muerto o PID reciclado
  const age = Date.now() - new Date(claim.updated_at).getTime();
  if (!(age <= TTL_MS)) return false; // TTL backstop (incluye NaN si updated_at es inválido)
  return true;
}

// Glob mínimo: `**` = cualquier cosa incl. `/`, `*` = cualquier cosa salvo `/`.
function globToRegExp(glob) {
  let re = '';
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === '*') {
      if (glob[i + 1] === '*') { re += '.*'; i++; } else re += '[^/]*';
    } else if ('.+^${}()|[]\\'.includes(c)) {
      re += `\\${c}`;
    } else {
      re += c;
    }
  }
  return new RegExp(`^${re}$`);
}
function pathMatchesGlob(filePath, glob) {
  return globToRegExp(glob).test(filePath);
}

function detectWorktree(repo) {
  const res = shOk(['git', 'rev-parse', '--show-toplevel']);
  if (!res.ok) return null;
  const top = path.resolve(res.out.trim());
  const canonical = path.resolve(path.join(WORKSPACE_ROOT, repo));
  return top === canonical ? null : top;
}

function loadAllClaims() {
  if (!fs.existsSync(INFLIGHT_DIR)) return [];
  const claims = [];
  for (const f of fs.readdirSync(INFLIGHT_DIR)) {
    if (!f.endsWith('.json')) continue;
    const full = path.join(INFLIGHT_DIR, f);
    try {
      claims.push({ file: full, ...JSON.parse(fs.readFileSync(full, 'utf8')) });
    } catch {
      claims.push({ file: full, session_id: f.replace(/\.json$/, ''), _corrupt: true });
    }
  }
  return claims;
}

// --- claim ---
function cmdClaim(repo, tema, paths) {
  const { sessionId, pid } = requireEnv();
  if (!repo || !tema || paths.length === 0) {
    console.error('Uso: inflight.mjs claim <repo> <tema> <path...>');
    process.exit(1);
  }
  fs.mkdirSync(INFLIGHT_DIR, { recursive: true });
  const file = claimPath(sessionId);
  let existing = null;
  if (fs.existsSync(file)) {
    try { existing = JSON.parse(fs.readFileSync(file, 'utf8')); } catch { /* claim previo corrupto, se pisa */ }
  }
  const now = new Date().toISOString();
  const claim = {
    session_id: sessionId,
    pid,
    pid_start_time: pidStartTime(pid),
    created_at: existing?.created_at || now,
    updated_at: now,
    repo,
    paths,
    tema,
    worktree: detectWorktree(repo),
  };
  fs.writeFileSync(file, JSON.stringify(claim, null, 2) + '\n');
  console.log(`✅ claim actualizado (${repo}): ${file}`);
  console.log(`   paths: ${paths.join(', ')}`);
}

// --- release ---
function cmdRelease() {
  const sessionId = process.env.CLAUDE_CODE_SESSION_ID;
  if (!sessionId) {
    console.error('✋ Falta CLAUDE_CODE_SESSION_ID en el entorno.');
    process.exit(1);
  }
  const file = claimPath(sessionId);
  if (fs.existsSync(file)) {
    fs.unlinkSync(file);
    console.log(`✅ claim liberado: ${file}`);
  } else {
    console.log('(sin claim propio para liberar)');
  }
}

// --- list ---
function cmdList() {
  const claims = loadAllClaims();
  if (claims.length === 0) {
    console.log('Sin claims registrados.');
    return;
  }
  console.log('estado | repo | session_id | tema | paths');
  console.log('-------|------|------------|------|------');
  for (const c of claims) {
    const estado = c._corrupt ? 'CORRUPTO' : isAlive(c) ? 'vivo' : 'stale';
    console.log(`${estado} | ${c.repo ?? '-'} | ${c.session_id} | ${c.tema ?? '-'} | ${(c.paths ?? []).join(', ')}`);
  }
}

// --- gc: archiva (nunca borra) claims stale ---
function cmdGc({ silent = false } = {}) {
  fs.mkdirSync(INFLIGHT_DIR, { recursive: true });
  const claims = loadAllClaims();
  let archived = 0;
  for (const c of claims) {
    if (c._corrupt || !isAlive(c)) {
      fs.mkdirSync(GC_DIR, { recursive: true });
      const stamp = new Date().toISOString().replace(/[:.]/g, '-');
      const dest = path.join(GC_DIR, `${stamp}-${path.basename(c.file)}`);
      fs.renameSync(c.file, dest);
      archived++;
      if (!silent) console.log(`🗑️  archivado (stale): ${path.basename(c.file)} → ${path.relative(INFLIGHT_DIR, dest)}`);
    }
  }
  return archived;
}

// --- check ---
function cmdCheck(repo, paths) {
  if (!repo || paths.length === 0) {
    console.error('Uso: inflight.mjs check <repo> <path...>');
    process.exit(1);
  }
  cmdGc({ silent: false });

  const ownSessionId = process.env.CLAUDE_CODE_SESSION_ID;
  const claims = loadAllClaims().filter((c) => !c._corrupt && isAlive(c));
  const foreign = claims.filter((c) => c.repo === repo && c.session_id !== ownSessionId);

  const collisions = [];
  for (const p of paths) {
    for (const c of foreign) {
      if ((c.paths ?? []).some((g) => pathMatchesGlob(p, g))) collisions.push({ path: p, claim: c });
    }
  }
  if (collisions.length > 0) {
    console.error('✋ Colisión con trabajo en vuelo de otra sesión:');
    for (const { path: p, claim } of collisions) {
      console.error(`   ${p} — claimeado por sesión ${claim.session_id} ("${claim.tema}")`);
    }
    process.exit(1);
  }

  if (repo === 'infra') {
    const own = ownSessionId ? claims.find((c) => c.repo === repo && c.session_id === ownSessionId) : null;
    const uncovered = paths.filter((p) => !own || !(own.paths ?? []).some((g) => pathMatchesGlob(p, g)));
    if (uncovered.length > 0) {
      console.error('✋ Falta claim propio que cubra estos paths en infra:');
      for (const p of uncovered) console.error(`   ${p}`);
      console.error('   Correr: node scripts/inflight.mjs claim infra "<tema>" ' + uncovered.join(' '));
      process.exit(1);
    }
  }

  console.log('✅ sin colisiones — claim propio cubre los paths (si aplica).');
}

// --- main ---
const [cmd, ...rest] = process.argv.slice(2);

switch (cmd) {
  case 'claim':
    cmdClaim(rest[0], rest[1], rest.slice(2));
    break;
  case 'release':
    cmdRelease();
    break;
  case 'list':
    cmdList();
    break;
  case 'gc':
    { const n = cmdGc({ silent: false }); console.log(`gc: ${n} claim(s) archivado(s).`); }
    break;
  case 'check':
    cmdCheck(rest[0], rest.slice(1));
    break;
  default:
    console.error('Uso: inflight.mjs <claim|release|list|check|gc> ...');
    process.exit(1);
}
