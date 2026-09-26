#!/usr/bin/env node
// Canonical local + CI verification orchestrator.
// The shell entry point is retained as a compatibility wrapper only.
//
// PRECONDITION (order matters, and the failure is SILENT, not loud):
// stage the GodotIK runtime BEFORE the first import —
//     tools/build-godotik.sh && node tools/verify-all.mjs
// With addons/libik absent, player_ik.tscn cannot load, yet the harnesses
// still exit 0 and the run reports RESULT: PASS. The orchestrator's
// log-honesty check greps SCRIPT ERROR, and that count is 0, so a missing
// rig is not caught here. DO NOT READ A GREEN RUN AS PROOF THAT libik IS
// STAGED. (Observed on f30e0f9: `verify-all --quick` returned RESULT: PASS
// with addons/libik entirely absent and SCRIPT ERROR count 0. verifier
// reports the loader's missing-ext_resource and GDExtension ERROR lines
// scrolling past in the same state; the honesty check greps SCRIPT ERROR,
// a different string, which is why they pass through.)
// A tree that was never imported is a DIFFERENT fault: global classes stay
// unresolved, scripts fail to compile, and a harness can stall until the
// 600s gate timeout. Import first, then diagnose; do not read that as a
// libik fault. CI satisfies the ordering by construction (build/stage runs
// before verify-all), so CI is protected by ORDERING, not by DETECTION —
// if the stage step ever silently no-ops, CI stays green too.
//
// The audit count is the ONLY signal that distinguishes the two states, and
// it is an ENVIRONMENT-DIQUALIFIED pair, never a single number:
//   libik STAGED -> qa_audit MAJOR=36
//   libik absent -> qa_audit MAJOR=37
// measured on f30e0f9. The delta is exactly one broken-ref row:
//   addons/cabra.lat_shooters/src/player/scenes/player_ik.tscn:5
//     dangling res:// addons/libik/script/pole_bone_constraint.gd
// Both values move as content changes, so quote the PAIR and name which
// side you measured. "37 on an otherwise-green run" is not a content
// regression; it is the signature of a GodotIK build or stage step that did
// not take effect, and it is the one thing that distinguishes a green run
// from a green run with a broken rig. Note that addons/libik is a BUILT
// extension produced by tools/build-godotik.sh, not a checked-out source
// tree: initialising submodules does not stage it.

import { spawn, spawnSync } from 'node:child_process';
import { createWriteStream, existsSync, mkdirSync, readFileSync, realpathSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
process.chdir(ROOT);

const args = process.argv.slice(2);
const locked = args.includes('--locked');
const forwarded = args.filter((arg) => arg !== '--locked');
const quick = forwarded.includes('--quick');
const withExport = forwarded.includes('--with-export');
const noQa = forwarded.includes('--no-qa');
const qaFast = forwarded.includes('--qa-fast');
const qaSoft = forwarded.includes('--qa-soft');
const help = forwarded.includes('-h') || forwarded.includes('--help');
const unknown = forwarded.find((arg) => !['--quick', '--with-export', '--no-qa', '--qa-fast', '--qa-soft', '-h', '--help'].includes(arg));
const godot = process.env.GODOT_BIN || 'godot';
const logDir = process.env.VERIFY_LOG_DIR || `/tmp/shooter/verify.${process.pid}`;
const liveLogs = process.env.VERIFY_LIVE_LOGS === '1';
const timeoutKillMs = 10_000;

if (help) {
  console.log(`Usage: node tools/verify-all.mjs [--quick] [--with-export] [--no-qa] [--qa-fast] [--qa-soft]`);
  process.exit(0);
}
if (unknown) {
  console.error(`verify-all: unknown flag '${unknown}'`);
  process.exit(64);
}

const records = [];
let hardFails = 0;
let warnings = 0;
let activeChild = null;
let stopping = false;

function record(name, status, detail) {
  records.push({ name, status, detail });
  if (status === 'FAIL') hardFails += 1;
  if (status === 'WARN') warnings += 1;
  console.log(`  ${status.padEnd(4)} ${name.padEnd(17)} ${detail}`);
}

function commandExists(command) {
  const result = spawnSync(command, ['--version'], { stdio: 'ignore' });
  return !result.error && result.status !== null;
}

function fatal(message, code = 1) {
  console.error(`verify-all: FATAL: ${message}`);
  process.exit(code);
}

if (!commandExists(godot)) fatal(`godot not found (set GODOT_BIN): ${godot}`, 64);
if (!commandExists('flock')) fatal('flock is required to protect the shared .godot cache', 69);
if (!commandExists('timeout')) fatal('timeout is required to preserve verify-all environment compatibility', 69);

// Worktrees can share .godot through a symlink. Re-exec once under flock so the
// lock is held for the complete verification run, including child processes.
// Keep this as an async child (not spawnSync) so CI cancellation can forward
// SIGTERM/SIGINT to the entire flock process group.
if (!locked) {
  const cache = existsSync('.godot') ? realpathSync('.godot') : join(ROOT, '.godot');
  mkdirSync('/tmp/shooter', { recursive: true });
  const lockFile = `/tmp/shooter/verify-all.${cache.replaceAll('/', '_')}.lock`;
  const lockProcess = spawn('flock', ['-w', '900', lockFile, process.execPath, fileURLToPath(import.meta.url), '--locked', ...forwarded], { stdio: 'inherit', detached: true });
  const relay = () => {
    stopping = true;
    killTree(lockProcess);
    setTimeout(() => process.exit(130), timeoutKillMs).unref();
  };
  process.once('SIGINT', relay);
  process.once('SIGTERM', relay);
  const result = await new Promise((resolveLock) => lockProcess.on('exit', (code) => resolveLock(code)));
  process.exit(stopping ? 130 : (result ?? 1));
}

mkdirSync(logDir, { recursive: true });

// HARNESS REGISTRY — the single source of truth for every script this tool
// runs. Kept at module scope so the existence preflight below and the gates
// that run later check exactly the same list; a second, drifting copy of these
// paths is how the stale res://test/... registration hid in CI.
const HARNESS_SCRIPTS = [
  ['check_scripts', 'res://addons/cabra.lat_shooters/test/check_scripts.gd'],
  ['assets', 'res://addons/cabra.lat_shooters/test/validate_assets.gd'],
  ['ballistics', 'res://addons/cabra.lat_shooters/test/validate_ballistics.gd'],
  ['weapon_mechanics', 'res://addons/cabra.lat_shooters/test/validate_weapon_mechanics.gd'],
  ['inventory_ux', 'res://addons/cabra.lat_shooters/test/validate_inventory_ux.gd'],
  ['meta_persistence', 'res://src/meta/validate_meta_persistence.gd'],
  ['meta_progression', 'res://src/meta/validate_meta_progression.gd'],
  ['meta_market', 'res://src/meta/validate_meta_market.gd'],
  ['meta_flea', 'res://src/meta/validate_meta_flea.gd'],
  ['meta_deploy_raid', 'res://src/meta/validate_meta_deploy_raid.gd'],
  ['i18n', 'res://src/meta/validate_i18n.gd'],
  ['invariants', 'res://addons/cabra.lat_shooters/test/validate_invariants.gd'],
  ['locomotion_orientation', 'res://addons/cabra.lat_shooters/test/validate_locomotion_orientation.gd'],
  ['factions', 'res://scenes/validate_factions.gd'],
  ['raid1_scenario', 'res://scenes/validate_raid1_scenario.gd'],
  ['gunsmith_preview', 'res://scenes/validate_gunsmith_preview.gd'],
  ['arena_spawn', 'res://scenes/validate_arena_spawn.gd'],
];

function harnessScript(name) {
  const entry = HARNESS_SCRIPTS.find(([n]) => n === name);
  if (!entry) fatal(`no registered harness named '${name}' (internal wiring error)`);
  return entry[1];
}

const resToPath = (script) => join(ROOT, script.replace(/^res:\/\//, ''));

// EXISTENCE PREFLIGHT, before the import. A registered path that is not on disk
// is a wiring fault, not a content fault. Left alone it surfaces two different
// wrong ways: the import gate fails on a script that was never there, or the
// gate's own harness reports FAIL for a file that does not exist — which reads
// as a content regression and sends the next person looking at the wrong code.
// Report every missing path at once (fixing them one run at a time is the
// failure mode this replaces) and exit 2, a code distinct from a gate failure.
// This checks EXISTENCE ONLY: a script that exists but cannot be loaded or run
// is a different fault and stays with its own harness gate.
function preflightHarnessPaths() {
  const missing = HARNESS_SCRIPTS.filter(([, script]) => !existsSync(resToPath(script)));
  if (missing.length === 0) {
    record('harness_paths', 'PASS', `${HARNESS_SCRIPTS.length} registered harness scripts present`);
    return true;
  }
  console.error(`verify-all: FATAL: ${missing.length} of ${HARNESS_SCRIPTS.length} registered harness scripts are not on disk:`);
  for (const [name, script] of missing) console.error(`  ${name.padEnd(25)}${script}`);
  const addonDir = join(ROOT, 'addons/cabra.lat_shooters');
  if (!existsSync(addonDir)) {
    console.error('  addons/cabra.lat_shooters is not checked out — initialize the declared submodules:');
    console.error('    git submodule update --init --recursive');
  } else if (!existsSync(join(addonDir, 'test'))) {
    console.error('  addons/cabra.lat_shooters exists but holds no test/ directory, which is what an');
    console.error('  uninitialized submodule looks like — initialize the declared submodules:');
    console.error('    git submodule update --init --recursive');
  }
  console.error('  Fix the registration or stage the missing checkout. A gate pointing at a path');
  console.error('  that is not there is a wiring fault; this run is not evidence about content.');
  return false;
}

if (!preflightHarnessPaths()) process.exit(2);

function killTree(child) {
  if (!child?.pid) return;
  try { process.kill(-child.pid, 'SIGTERM'); } catch { try { child.kill('SIGTERM'); } catch {} }
  setTimeout(() => {
    try { process.kill(-child.pid, 'SIGKILL'); } catch { try { child.kill('SIGKILL'); } catch {} }
  }, timeoutKillMs).unref();
}

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    stopping = true;
    if (activeChild) killTree(activeChild);
    setTimeout(() => process.exit(130), timeoutKillMs).unref();
  });
}

function runLogged(name, command, commandArgs, timeoutMs, opts = {}) {
  const log = join(logDir, `${name}.log`);
  if (stopping) return Promise.resolve({ code: 130, signal: 'SIGTERM', timedOut: false, raised: false, log });
  const output = createWriteStream(log, { flags: 'w' });
  return new Promise((resolveRun) => {
    let timedOut = false;
    let raised = false;
    let timer;
    let watcher;
    const raiseQuietMs = Number(opts.raiseQuietMs) || 0;
    const child = spawn(command, commandArgs, { cwd: ROOT, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
    activeChild = child;
    const write = (chunk) => {
      output.write(chunk);
      if (liveLogs) process.stdout.write(chunk);
    };
    child.stdout.on('data', write);
    child.stderr.on('data', write);
    child.on('error', (error) => {
      output.write(`verify-all: ${error.message}\n`);
      if (liveLogs) process.stdout.write(`verify-all: ${error.message}\n`);
    });
    timer = setTimeout(() => {
      timedOut = true;
      killTree(child);
    }, timeoutMs);
    // A GDScript runtime error does not abort the process: it aborts the function it
    // happened in. When that function is the harness's OWN top-level entry point, the
    // quit() call below it is never reached, so the process lingers until the hard
    // timeout even though it has already finished all the work it will ever do. We
    // detect that as "output went quiet AND a script error is already in the log", and
    // kill it there rather than spending the full budget waiting for a process that is
    // never going to return on its own.
    if (raiseQuietMs) {
      let lastSize = -1;
      let quietSince = Date.now();
      watcher = setInterval(() => {
        let size = 0;
        try {
          size = statSync(log).size;
        } catch {
          return;
        }
        if (size !== lastSize) {
          lastSize = size;
          quietSince = Date.now();
          return;
        }
        if (Date.now() - quietSince < raiseQuietMs) return;
        let text = '';
        try {
          text = readFileSync(log, 'utf8');
        } catch {
          return;
        }
        if (countMatches(text, /SCRIPT ERROR/g) > 0) {
          raised = true;
          clearInterval(watcher);
          killTree(child);
        }
      }, 2000);
    }
    child.on('close', (code, signal) => {
      clearTimeout(timer);
      if (watcher) clearInterval(watcher);
      activeChild = null;
      output.end(() => {
        if (stopping) process.exit(130);
        resolveRun({ code: raised ? 125 : (timedOut ? 124 : (code ?? 1)), signal, timedOut, raised, log });
      });
    });
  });
}

function readLog(log) {
  try { return readFileSync(log, 'utf8'); } catch { return ''; }
}

function countChecks(text) {
  return text.match(/checks passed\s*:?\s*[0-9]+/i)?.[0]?.match(/[0-9]+/)?.[0]
    ?? text.match(/checks:\s*[0-9]+ pass/i)?.[0]?.match(/[0-9]+/)?.[0]
    ?? text.match(/^\s*passed\s+[0-9]+/im)?.[0]?.match(/[0-9]+/)?.[0]
    ?? '?';
}

function countMatches(text, expression) {
  return (text.match(expression) || []).length;
}

function stripAnsi(text) {
  return text.replace(/\x1b\[[0-9;]*m/g, '');
}

function largestReimportLoop(text) {
  const counts = new Map();
  for (const line of stripAnsi(text).split(/\r?\n/)) {
    const match = line.match(/reimport \| (.*)$/);
    if (!match) continue;
    const asset = match[1].trim();
    if (!asset || /^(preparing files to reimport|started \(re\)importing assets|executing pre-reimport operations)/i.test(asset)) continue;
    counts.set(asset, (counts.get(asset) || 0) + 1);
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1])[0] || ['', 0];
}

function hasUidFailure(text) {
  return /Unrecognized UID|Can't find file .* during file reimport/i.test(text);
}

async function importGodot() {
  const importLog = join(logDir, 'import.log');
  for (let attempt = 1; attempt <= 2; attempt += 1) {
    let detected = null;
    const running = runLogged('import', godot, ['--headless', '--path', '.', '--import'], 120_000);
    const watcher = setInterval(() => {
      const liveText = readLog(importLog);
      const [liveAsset, liveRepeats] = largestReimportLoop(liveText);
      if (!detected && (liveRepeats > 50 || hasUidFailure(liveText))) {
        detected = { asset: liveAsset, repeats: liveRepeats };
        if (activeChild) killTree(activeChild);
      }
    }, 250);
    const result = await running;
    clearInterval(watcher);
    const text = readLog(importLog);
    const [asset, repeats] = largestReimportLoop(text);
    if (detected || repeats > 50 || hasUidFailure(text)) {
      const failure = detected || { asset, repeats };
      record('import/parse', 'FAIL', `import reimport loop/UID failure: '${failure.asset}' repeated ${failure.repeats} times (see ${importLog})`);
      return false;
    }
    if (result.code !== 124) {
      const errors = countMatches(text, /SCRIPT ERROR|Parse Error|Failed to load|Cannot open|Failed to compile/g);
      const scripts = await runLogged('check_scripts', godot, ['--headless', '--path', '.', '--script', harnessScript('check_scripts')], 600_000, { raiseQuietMs: 20_000 });
      if (scripts.raised) {
        // Same shape as the gateHarness case, and for the same reason: check_scripts is a
        // GDScript harness, so a raise in its own top-level function skips quit(), it never
        // returns, and without this the 600s budget expires and the reader is told to suspect
        // the import cache -- which is exactly the misdirection the raise-watch exists to stop.
        const raiseErrors = countMatches(readLog(scripts.log), /^SCRIPT ERROR/gm);
        record('import/parse', 'FAIL', `check_scripts raised and stopped reporting — ${raiseErrors} script error(s) and no summary. A raise in the harness's OWN top-level function aborts it before quit(), so it never returns; the cause is in its own output, NOT in .godot and NOT in a scene that failed to boot (see ${scripts.log})`);
        return false;
      }
      const scriptText = readLog(scripts.log);
      const compiled = scriptText.match(/scripts compiled:\s*([0-9]+)/i)?.[1] || '?';
      const failures = scriptText.match(/failures:\s*([0-9]+)/i)?.[1] || '?';
      if (result.code !== 0 || errors > 0 || scripts.code !== 0) {
        record('import/parse', 'FAIL', `import rc=${result.code} errors=${errors}; scripts rc=${scripts.code} failures=${failures}`);
        return false;
      } else {
        record('import/parse', 'PASS', `0 parse errors, ${compiled} scripts compiled`);
      }
      return true;
    }
    if (attempt < 2) {
      console.error('verify-all: import timed out; waiting 5s + retry once');
      await new Promise((resolveSleep) => setTimeout(resolveSleep, 5000));
    }
  }
  record('import/parse', 'FAIL', `import TIMED OUT (120s x2) (see ${importLog})`);
  return false;
}

function gitOutput(repo, gitArgs) {
  const result = spawnSync('git', ['-C', repo, ...gitArgs], { cwd: ROOT, encoding: 'utf8' });
  return result.status === 0 ? result.stdout : null;
}

function gateUidTracking() {
  const list = join(logDir, 'uid_missing.log');
  writeFileSync(list, '');
  let total = 0;
  let checked = 0;
  let skipped = [];
  let details = [];
  for (const repo of ['.', 'addons/cabra.lat_shooters']) {
    const absolute = resolve(repo);
    const top = gitOutput(repo, ['rev-parse', '--show-toplevel']);
    if (!top || realpathSync(top.trim()) !== realpathSync(absolute)) {
      skipped.push(repo);
      continue;
    }
    const head = gitOutput(repo, ['ls-tree', '-r', '--name-only', 'HEAD']);
    if (!head) {
      skipped.push(repo);
      continue;
    }
    checked += 1;
    const files = head.split(/\r?\n/).filter(Boolean);
    const scripts = files.filter((file) => /\.(gd|gdshader|gdshaderinc)$/.test(file) && !file.split('/').some((part) => part.startsWith('.')));
    const uids = new Set(files.filter((file) => /\.uid$/.test(file) && !file.split('/').some((part) => part.startsWith('.'))));
    const missing = scripts.map((file) => `${file}.uid`).filter((file) => !uids.has(file));
    const scriptSet = new Set(scripts);
    const orphan = [...uids].filter((file) => !scriptSet.has(file.replace(/\.uid$/, '')));
    const count = missing.length + orphan.length;
    total += count;
    if (count) {
      details.push(`${repo}:${count}`);
      for (const file of missing) writeFileSync(list, `${repo}/${file.replace(/\.uid$/, '')} (script without .uid)\n`, { flag: 'a' });
      for (const file of orphan) writeFileSync(list, `${repo}/${file} (uid without script)\n`, { flag: 'a' });
    }
  }
  const skipNote = skipped.length ? `; SKIPPED (no git checkout): ${skipped.join(' ')}` : '';
  if (!checked) record('uid_tracking', 'SKIP', `no git checkout to check (skipped: ${skipped.join(' ') || 'none'})`);
  else if (total) record('uid_tracking', 'FAIL', `${total} tracked script(s) without a tracked .uid (${details.join(' ')}) — list in ${list}${skipNote}`);
  else record('uid_tracking', 'PASS', `every tracked script in ${checked} repo(s) has a tracked .uid${skipNote}`);
}

async function reimportAfterHarness(name) {
  const result = await runLogged(`reimport.${name}`, godot, ['--headless', '--path', '.', '--import'], 120_000);
  const text = readLog(result.log);
  const [asset, repeats] = largestReimportLoop(text);
  return { ...result, asset, repeats, uidFailure: hasUidFailure(text) };
}

async function gateHarness(name, script) {
  const budgetMs = 600_000;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    const result = await runLogged(name, godot, ['--headless', '--path', '.', '--script', script], budgetMs, { raiseQuietMs: 20_000 });
    const raisedErrors = result.raised ? countMatches(readLog(result.log), /^SCRIPT ERROR/gm) : 0;
    if (result.raised) {
      record(name, 'FAIL', `harness raised and stopped reporting — ${raisedErrors} script error(s) and no RESULT line. A raise in the harness's OWN top-level function aborts it before quit(), so it never returns; the cause is in its own output, NOT in .godot and NOT in a scene that failed to boot (see ${result.log})`);
      return;
    }
    if (result.code === 124) {
      // Reached the budget. Read the log before blaming the cache: a harness that raised
      // and kept its error to a trailing line can still time out, and telling the next
      // reader to clear .godot when the log names the script is the misdirection this
      // message exists to stop.
      const timedOutErrors = countMatches(readLog(result.log), /^SCRIPT ERROR/gm);
      record(name, 'FAIL', timedOutErrors > 0
        ? `harness TIMED OUT (${Math.round(budgetMs / 1000)}s) — but its own log has ${timedOutErrors} script error(s), so it raised rather than hung; look there first, not in .godot (see ${result.log})`
        : `harness TIMED OUT (${Math.round(budgetMs / 1000)}s) — hung with no script error in its output; suspect stale .godot or a scene that never boots (see ${result.log})`);
      return;
    }
    const text = readLog(result.log);
    const loadErrors = countMatches(text, /referenced non-existent resource|Resource file not found/g);
    const scriptErrors = countMatches(text, /SCRIPT ERROR/g);
    const invalidUid = countMatches(text, /invalid UID/g);
    if (result.code === 0 && /RESULT: PASS/.test(text) && loadErrors === 0 && scriptErrors === 0) {
      record(name, 'PASS', `${countChecks(text)} checks${invalidUid ? ` (${invalidUid} invalid-UID warning(s))` : ''}${attempt > 1 ? ' (retried after re-import)' : ''}`);
      return;
    }
    if (attempt >= 3) {
      record(name, 'FAIL', `${countChecks(text)} checks; rc=${result.code}, ${loadErrors} load, ${scriptErrors} script error(s) after ${attempt} attempts (see ${result.log})`);
      return;
    }
    console.error(`verify-all: ${name} failed (rc=${result.code}, load=${loadErrors} script=${scriptErrors}) — bounded re-import + retry (attempt ${attempt + 1}/3)`);
    const refresh = await reimportAfterHarness(name);
    if (refresh.code === 124 || refresh.repeats > 50 || refresh.uidFailure) {
      record(name, 'FAIL', `re-import hit a UID/import loop or timeout (rc=${refresh.code}, repeats=${refresh.repeats}, asset=${refresh.asset || 'unknown'}; see ${refresh.log})`);
      return;
    }
  }
}

async function gateQa() {
  const qaArgs = ['tools/qa/audit.mjs', '--check', '--no-import'];
  if (qaFast) qaArgs.push('--no-verify');
  const result = await runLogged('qa_audit', process.execPath, qaArgs, 900_000);
  const text = readLog(result.log);
  if (result.code === 124) {
    record('qa_audit', 'WARN', `TIMED OUT (900s) (see ${result.log})`);
    return;
  }
  const counts = text.match(/BLOCKER=\d+ MAJOR=\d+ MINOR=\d+ NIT=\d+/)?.[0] || `rc=${result.code}`;
  if (result.code === 0) record('qa_audit', 'PASS', counts);
  else if (result.code === 1 && qaSoft) record('qa_audit', 'WARN', `BLOCKER present (soft): ${counts}`);
  else if (result.code === 1) record('qa_audit', 'FAIL', `BLOCKER present: ${counts}`);
  else if (result.code === 2) record('qa_audit', 'WARN', `MAJOR regressed vs baseline (informative): ${counts}`);
  else record('qa_audit', 'FAIL', `audit error rc=${result.code}`);
}

async function gateExport() {
  const version = spawnSync(godot, ['--version'], { cwd: ROOT, encoding: 'utf8' }).stdout.trim();
  const templateDir = join(process.env.HOME || '', '.local/share/godot/export_templates', version.replace(/^([0-9]+\.[0-9]+\.[0-9]+\.[a-z]+).*/, '$1'));
  if (!existsSync(templateDir)) {
    record('export', 'SKIP', `export templates not installed (${version})`);
    return;
  }
  const out = join(logDir, 'export');
  mkdirSync(out, { recursive: true });
  const linux = await runLogged('export', godot, ['--headless', '--path', '.', '--export-release', 'Linux/X11', join(out, 'fps-basegame.x86_64')], 600_000);
  if (linux.code !== 0) return record('export', 'FAIL', `Linux/X11 export rc=${linux.code} (see ${linux.log})`);
  const windows = await runLogged('export', godot, ['--headless', '--path', '.', '--export-release', 'Windows Desktop', join(out, 'fps-basegame.exe')], 600_000);
  if (windows.code !== 0) return record('export', 'FAIL', `Windows export rc=${windows.code} (see ${windows.log})`);
  record('export', 'PASS', 'Linux/X11 + Windows Desktop');
}

async function main() {
  console.log(`=== verify-all ===  root=${ROOT}  godot=${spawnSync(godot, ['--version'], { encoding: 'utf8' }).stdout.trim()}`);
  console.log(`logs: ${logDir}\n`);
  const importOk = await importGodot();
  gateUidTracking();
  if (!importOk) {
    record('harnesses', 'SKIP', 'import/parse failed; downstream Godot gates would use an invalid cache');
  } else if (quick) {
    await gateHarness('assets', harnessScript('assets'));
  } else {
    for (const [name, script] of HARNESS_SCRIPTS) {
      if (name === 'check_scripts') continue; // runs as the import/parse gate
      await gateHarness(name, script);
    }
    if (noQa) record('qa_audit', 'SKIP', '--no-qa'); else await gateQa();
    if (withExport) await gateExport(); else record('export', 'SKIP', 'pass --with-export to include');
  }
  console.log('\n=== verify-all summary ===');
  if (hardFails) {
    console.log(`\nRESULT: FAIL (${hardFails} hard gate(s) failed, ${warnings} warning(s))`);
    process.exitCode = 1;
  } else {
    console.log(`\nRESULT: PASS${warnings ? ` (${warnings} non-blocking warning(s))` : ''}`);
  }
}

await main();
