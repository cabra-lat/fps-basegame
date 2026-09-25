#!/usr/bin/env node
// tools/qa/audit.mjs — headless code-quality audit for fps-basegame.
//
// Produces objective metrics + a severity-classified report. No dependencies.
// Owned by the `qa` agent; findings are work orders, never auto-fixes.
//
// Usage:
//   node tools/qa/audit.mjs                 # scan only (does not write a report)
//   node tools/qa/audit.mjs --report <path> # write the report to an explicit path
//   node tools/qa/audit.mjs --write-report  # explicitly write docs/qa-report.md
//   node tools/qa/audit.mjs --no-import     # skip the godot import gate (fast)
//   node tools/qa/audit.mjs --check         # read-only CI mode: exit 1 on BLOCKER,
//                                           # exit 2 on MAJOR > baseline
//   node tools/qa/audit.mjs --update-baseline
//   node tools/qa/audit.mjs --json          # dump findings as JSON to stdout
//
// Exit codes: 0 ok | 1 BLOCKER present | 2 MAJOR regressed vs baseline | 3 usage/scan error.

import { readFileSync, writeFileSync, readdirSync, statSync, existsSync, mkdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const TOOL_VERSION = '2.1.0';
const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..');
const REPORT_PATH = join(ROOT, 'docs', 'qa-report.md');
const BASELINE_PATH = join(ROOT, 'docs', 'qa-baseline.json');
// Human review pass (contract violations, semantics) that static parsing cannot
// prove. Maintained by the `qa` agent; merged into the same severity counts so
// CI catches regressions there too.
const MANUAL_PATH = join(HERE, 'manual-findings.json');
// Owner-confirmed false positives / intentional hooks. Each entry needs a
// reason; the tool reports how many findings an entry suppressed.
const IGNORE_PATH = join(HERE, 'ignore.json');
const SCRATCH = '/tmp/shooter';

// Shipping source roots audited for metrics. `test/` trees are indexed for
// reference-counting but never reported as findings (they are allowed to print).
const SCAN_DIRS = ['addons/cabra.lat_shooters/src', 'src', 'scenes'];
// Only declared code/data roots can be live consumers. A whole-repo walk made
// documentation, agent instructions, and vendored third-party source suppress
// dead-API findings merely by mentioning a symbol. Keep this list explicit and
// path-based so optional checkouts cannot change the result.
const REFERENCE_EXTS = ['.gd', '.tscn', '.tres', '.godot', '.cfg'];
const REFERENCE_ROOTS = [
  'addons/cabra.lat_shooters/src',
  'addons/cabra.lat_shooters/test',
  'src',
  'scenes',
  'resources',
  'test',
  'tools',
];

function isReferencePath(rel) {
  if (!REFERENCE_EXTS.some((ext) => rel.endsWith(ext))) return false;
  return REFERENCE_ROOTS.some((root) => rel === root || rel.startsWith(`${root}/`));
}

// Full vocabulary of rule names the tool can emit (scanner + manual findings).
// The baseline stores this so `--check` can tell a real rule-set change from a
// rule that merely stopped/started FIRING because its findings were fixed or
// added. Comparing the currently-firing set instead made a reappearing rule
// (e.g. `duplication` at 0) look like a taxonomy change and excuse its MAJOR rise.
const RULE_VOCABULARY = [
  'broken-ref', 'case-mismatch', 'competing-truth', 'connect-leak', 'dead-api',
  'dead-branch', 'debug-print', 'deep-nesting', 'dev-comment', 'duplicate-logic',
  'duplicate-mass', 'duplication', 'frame-not-delta', 'god-object', 'ignored-config',
  'indent-mixed', 'invisible-debt', 'ip-name', 'ip-tarkov', 'lambda-leak',
  'long-function', 'mag-alias', 'magic-number', 'node-churn', 'noop-call',
  'not-docstring', 'null-guard', 'order-of-init', 'pending-consumer', 'reused-asset',
  'rule5-held-sim', 'signal-decay', 'signal-spam', 'silent-zero-armor', 'stale-comment',
  'unused-field', 'unused-func', 'unused-wrong', 'write-only',
].sort();

const GOD_OBJECT_LINES = 800;
const LONG_FUNCTION_LINES = 60;
const DEEP_NESTING = 5;
const DUP_WINDOW = 8;
const FUNC_MIN_LINES = 2; // function must be at least this long to be counted

// AGENTS.md "Identity rule": shipped content must not carry commercial-game
// proper nouns. Technical standards/authors (GOST, NIJ, VPAM, STANAG, RHA,
// Recht-Ipson, Poncelet) are public references and deliberately NOT listed.
// `ambiguous: true` terms are common English words, matched case-SENSITIVELY so
// `factory.gd` / "reserve capacity" do not fire; distinctive names match
// case-insensitively.
const IP_NAMES = [
  { re: /Escape from Tarkov/i, label: 'Escape from Tarkov', alwaysBlocker: true },
  { re: /\bPrapor\b/i, label: 'Prapor' },
  { re: /\bTherapist\b/i, label: 'Therapist' },
  { re: /\bSkier\b/i, label: 'Skier' },
  { re: /\bPeacekeeper\b/i, label: 'Peacekeeper' },
  { re: /\bMechanic\b/, label: 'Mechanic', ambiguous: true },
  { re: /\bRagman\b/i, label: 'Ragman' },
  { re: /\bJaeger\b/i, label: 'Jaeger' },
  { re: /\bFence\b/, label: 'Fence', ambiguous: true },
  { re: /\bReshala\b/i, label: 'Reshala' },
  { re: /\bKilla\b/i, label: 'Killa' },
  { re: /\bGlukhar\b/i, label: 'Glukhar' },
  { re: /\bShturman\b/i, label: 'Shturman' },
  { re: /\bTagilla\b/i, label: 'Tagilla' },
  { re: /\bCultist\b/, label: 'Cultist', ambiguous: true },
  { re: /\bCustoms\b/i, label: 'Customs' },
  { re: /\bInterchange\b/i, label: 'Interchange' },
  { re: /\bShoreline\b/i, label: 'Shoreline' },
  { re: /\bReserve\b/, label: 'Reserve', ambiguous: true },
  { re: /\bLighthouse\b/, label: 'Lighthouse', ambiguous: true },
  { re: /Ground Zero/i, label: 'Ground Zero' },
  { re: /Streets of Tarkov/i, label: 'Streets of Tarkov' },
  { re: /\bFactory\b/, label: 'Factory', ambiguous: true },
  { re: /\bLab\b/, label: 'Lab', ambiguous: true },
  { re: /\bLabyrinth\b/i, label: 'Labyrinth' },
  { re: /\bIcebreaker\b/i, label: 'Icebreaker' },
  { re: /\bTarkov\b/, label: 'Tarkov', ambiguous: true, generic: true },
];

// Real firearm / accessory manufacturer + product names. NOT commercial-game
// proper nouns, but AGENTS.md requires shipped item/resource names to be neutral
// placeholders invented here, and a public repo must not ship real brands in
// resource names, filenames or player-facing strings. `ambiguous: true` terms
// are common words/surnames matched case-SENSITIVELY to cut false positives.
// NOTE: boundaries use lookarounds that treat `_`/`-`/`.` as separators, NOT
// `\b` — in `Vortex_Razor`, `weapons_fn_fal.png` or `beretta_m9` the `_` is a
// word char, so `\bBrand\b` would MISS the brand entirely.
const B0 = '(?<![A-Za-z0-9])';
const B1 = '(?![A-Za-z0-9])';
const brand = (word, extra = {}) => ({ re: new RegExp(`${B0}${word}${B1}`, 'i'), label: word, brand: true, ...extra });
const brandCS = (word, extra = {}) => ({ re: new RegExp(`${B0}${word}${B1}`), label: word, brand: true, ambiguous: true, ...extra });
const IP_BRANDS = [
  brand('Glock'),
  brand('Magpul'),
  brandCS('Surefire'),
  brand('Aimpoint'),
  brand('EOTech'),
  brandCS('Vortex'),
  brand('Steiner'),
  brandCS('Harris'),
  brand('BCM'),
  brand('JP Enterprises'),
  brand('Trijicon'),
  brand('ACOG'),
  brand('Imbel'),
  brand('FN'),
  brand('HK'),
  brand('Uzi'),
  brand('Saiga'),
  brand('Desert Eagle'),
  brand('Remington'),
  brand('Mossberg'),
  brand('Barrett'),
  brandCS('Colt'),
  brand('Beretta'),
  brand('Taurus'),
  brand('Rossi'),
  brand('Kalashnikov'),
  brand('Izhmash'),
  brand('Dragunov'),
];

// Paths that may legitimately cite sources / carry research names.
function isIpExempt(rel) {
  return rel.startsWith('docs/') || rel.endsWith('.md') || rel.startsWith('../tarkov-wiki');
}

// Best-effort routing: which agent handle owns a file. Ordered (specific first).
// It is a hint for triage, not authority — the coordinator owns the roster.
const OWNER_RULES = [
  [/^src\/meta\//, 'meta'],
  [/^src\/npcs\//, 'npc-body'],
  [/^scenes\//, 'range'],
  [/^src\//, 'range'],
  [/^addons\/cabra\.lat_shooters\/src\/player\//, 'player-rig'],
  [/^addons\/cabra\.lat_shooters\/src\/ui\/hud\//, 'player-rig'],
  [/^addons\/cabra\.lat_shooters\/src\/world\/(weapon_3d|magazine_3d|cartridge_3d|item_3d|attachment_scope_3d)\.gd$/, 'player-rig'],
  [/^addons\/cabra\.lat_shooters\/src\/core\/inventory\//, 'player-rig'],
  [/^addons\/cabra\.lat_shooters\/src\/gameplay\//, 'player-rig'],
  [/^addons\/cabra\.lat_shooters\/src\/core\//, 'ballistics'],
  [/^addons\/cabra\.lat_shooters\/src\/systems\//, 'ballistics'],
  [/^addons\/cabra\.lat_shooters\/src\/ui\/inventory\//, 'ballistics'],
  [/^addons\/cabra\.lat_shooters\/src\/world\//, 'ballistics'],
  [/^addons\/cabra\.lat_shooters\/src\/effects\//, 'ballistics'],
];

function ownerFor(rel) {
  for (const [re, o] of OWNER_RULES) if (re.test(rel)) return o;
  return 'unassigned';
}

const SEVERITY_ORDER = ['BLOCKER', 'MAJOR', 'MINOR', 'NIT'];

const args = new Set(process.argv.slice(2));
const flag = (name) => args.has(name);

// Report output is opt-in. A scan is a read-only observation unless the caller
// names a destination; this keeps `--check` and evidence scans from dirtying a
// tracked report in every lane's worktree.
const reportFlagIndex = process.argv.indexOf('--report');
const reportFlagPath = reportFlagIndex >= 0 ? process.argv[reportFlagIndex + 1] : null;
if (reportFlagIndex >= 0 && (!reportFlagPath || reportFlagPath.startsWith('--'))) {
  console.error('audit: --report requires an output path (for example /tmp/shooter/qa-report.md)');
  process.exit(3);
}
const reportPath = reportFlagPath ? resolve(ROOT, reportFlagPath) : null;

// ────────────────────────────────────────────────────────────── helpers ──

function walk(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (entry === '.git' || entry === '.godot' || entry === '.agent-mail') continue;
    const st = statSync(full);
    if (st.isDirectory()) walk(full, out);
    else out.push(full);
  }
  return out;
}

function readText(path) {
  try {
    return readFileSync(path, 'utf8');
  } catch {
    return '';
  }
}

// Normalized indent width (tabs -> 4). -1 for blank / comment-only lines.
function indentWidth(line) {
  const m = line.match(/^([ \t]*)/);
  let w = 0;
  for (const ch of m[1]) w += ch === '\t' ? 4 : 1;
  const rest = line.trim();
  if (rest === '' || rest.startsWith('#')) return -1;
  return w;
}

function lineIndents(lines) {
  return lines.map(indentWidth);
}

// Harnesses that live under src/ but are tests: their prints are intentional.
function isTestPath(rel) {
  return /(^|\/)(validate_[^/]*|[^/]*_validate|test_[^/]*|\.tmp)\.gd$/.test(rel) || /(^|\/)test\//.test(rel);
}

// Top-level owner root of a scanned path.
function rootOf(rel) {
  if (rel.startsWith('addons/')) return 'addons (core)';
  if (rel.startsWith('src/')) return 'src/ (game)';
  if (rel.startsWith('scenes/')) return 'scenes/ (game)';
  return 'other';
}

function stripComment(line) {
  let inStr = false;
  let quote = '';
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (inStr) {
      if (c === '\\') i++;
      else if (c === quote) inStr = false;
    } else if (c === '"' || c === "'") {
      inStr = true;
      quote = c;
    } else if (c === '#') {
      return line.slice(0, i);
    }
  }
  return line;
}

function normLine(line) {
  return stripComment(line).replace(/\s+/g, ' ').trim();
}

const NON_TRIVIAL = new Set(['{', '}', '(', ')', '[', ']', 'else:', 'return', 'pass']);
function isTrivial(n) {
  if (n === '') return true;
  if (NON_TRIVIAL.has(n)) return true;
  if (/^[)\]}]+$/.test(n)) return true;
  return false;
}

// Enclosing function of a 1-based line number.
function enclosingFunc(funcs, line) {
  let best = null;
  for (const f of funcs) {
    if (f.start <= line && (best === null || f.start > best.start)) best = f;
  }
  return best;
}

// ─────────────────────────────── manual-finding verification ──
//
// A hand-reviewed finding can age into a lie: the owner fixes the bug but the
// JSON stays red and people learn to ignore the gate. Each entry may carry a
// `probe` command that prints `QA_RESULT=RESOLVED` or `QA_RESULT=PRESENT`.
// `--verify-manual` runs it and flips `status` between `resolved` and `active`
// (writing the file only when the status actually changes). Entries without a
// probe stay `unverified` and are reported, not hidden.
function verifyManualFindings(writeChanges = true) {
  if (!existsSync(MANUAL_PATH)) return { ran: 0, resolved: 0, active: 0, unverified: 0, errors: 0 };
  let list;
  try {
    list = JSON.parse(readFileSync(MANUAL_PATH, 'utf8'));
  } catch (e) {
    console.error(`warn: could not parse ${MANUAL_PATH}: ${e.message}`);
    return { ran: 0, resolved: 0, active: 0, unverified: 0, errors: 0 };
  }
  let changed = false;
  const stats = { ran: 0, resolved: 0, active: 0, unverified: 0, errors: 0 };
  for (const m of list) {
    if (!m.probe) {
      stats.unverified++;
      continue;
    }
    let out = '';
    try {
      out = execFileSync('bash', ['-lc', m.probe], {
        // The probe runs Godot through tools/godot-lock.sh, which may wait up to
        // 900s for the shared .godot lock; the exec timeout must cover that.
        cwd: ROOT, encoding: 'utf8', timeout: 1200000, stdio: ['ignore', 'pipe', 'pipe'],
      });
    } catch (e) {
      out = `${e.stdout || ''}\n${e.stderr || ''}`;
    }
    stats.ran++;
    const resolved = /QA_RESULT=RESOLVED/.test(out);
    const present = /QA_RESULT=PRESENT/.test(out);
    if (!resolved && !present) {
      // No explicit result: the probe errored, timed out, or was killed while
      // waiting on the lock. Absence of evidence is NOT evidence the bug is
      // back -> keep the stored status and flag it for a re-run.
      stats.errors++;
      continue;
    }
    const status = resolved ? 'resolved' : 'active';
    if (resolved) stats.resolved++;
    else stats.active++;
    if (m.status !== status) {
      m.status = status;
      m.verified_at = new Date().toISOString();
      changed = true;
    }
  }
  if (changed && writeChanges) writeFileSync(MANUAL_PATH, JSON.stringify(list, null, 2) + '\n');
  return stats;
}

// ─────────────────────────────────────────────── per-file parse ──

// A print is debug-only (and therefore not a shipping-path debug-print) when it
// sits on, or inside, an `if OS.is_debug_build():` guard. Accepted convention:
// `if OS.is_debug_build(): print(...)` (same line) or a guarded block.
function isDebugBuildGuarded(lines, indents, idx) {
  const guardRe = /(^|[\s(:,])if\s+OS\.is_debug_build\s*\(/;
  const notGuardRe = /not\s+OS\.is_debug_build/;
  // same line: `if OS.is_debug_build(): print(...)`
  if (guardRe.test(lines[idx]) && !notGuardRe.test(lines[idx])) return true;
  // enclosing block: walk up the indentation ancestor chain
  let curIndent = indents[idx];
  for (let j = idx - 1; j >= 0; j--) {
    const tj = lines[j].trim();
    if (tj === '' || tj.startsWith('#')) continue;
    const ij = indents[j];
    if (ij >= curIndent) continue; // deeper line / sibling block, not an ancestor
    if (guardRe.test(lines[j]) && !notGuardRe.test(lines[j])) return true;
    curIndent = ij; // this header is the parent block; keep walking up
  }
  return false;
}

// Comment text attached to a declaration: the trailing comment on the line plus
// the contiguous `##`/`#` block directly above it. Used to recognise an
// owner-documented intentional hook (`hook`, `no caller yet`, ...) so a planned
// consumer is not reported as dead API.
function docComment(lines, idx) {
  const parts = [];
  const tm = lines[idx].match(/#(.*)$/);
  if (tm) parts.push(tm[1]);
  for (let j = idx - 1; j >= 0 && j >= idx - 12; j--) {
    const t = lines[j].trim();
    if (t.startsWith('#')) { parts.push(t.replace(/^#+\s?/, '')); continue; }
    if (t === '') continue;
    // Keep walking past sibling declarations: consecutive consts/vars often
    // share one `##` doc block that documents them all as hooks.
    if (/^(const|static\s+var|var|@export)\b/.test(t)) continue;
    break;
  }
  return parts.join(' ');
}

function analyzeGd(path, rel) {
  const raw = readText(path);
  const lines = raw.split('\n');
  const indents = lineIndents(lines);

  const info = {
    path: rel,
    lines: lines.length,
    blankLines: 0,
    indent: { tabLines: 0, spaceLines: 0, dominant: 'none', mixed: false },
    prints: [], // {line, text}
    todos: [], // {line, text}
    funcs: [], // {name, start, end, length, isPublic}
    maxDepth: 0,
    connects: [], // {line, lambda, oneShot, connectedTo}
    disconnects: [],
    addChild: 0,
    queueFree: 0,
    fields: [], // {name, line, exported}
    parseErrorHints: [],
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const ln = i + 1;
    const trimmed = line.trim();
    if (trimmed === '') info.blankLines++;

    // indentation census (only indented, non-blank, non-comment lines)
    if (indents[i] > 0) {
      if (/^[ \t]*\t/.test(line)) info.indent.tabLines++;
      else info.indent.spaceLines++;
    }

    // prints (skip comment-only and intentional test harnesses, and prints
    // guarded by `if OS.is_debug_build():` — those only run in debug builds)
    if (!trimmed.startsWith('#') && !isTestPath(rel)) {
      if ((/\bprint(_[a-z]+)?\s*\(/.test(line) || /\bprinterr\s*\(/.test(line)) &&
          !isDebugBuildGuarded(lines, indents, i)) {
        info.prints.push({ line: ln, text: trimmed.slice(0, 100) });
      }
    }

    // TODO / FIXME / HACK / XXX
    if (/\b(TODO|FIXME|HACK|XXX)\b/.test(stripComment(line))) {
      info.todos.push({ line: ln, text: trimmed.slice(0, 120) });
    }

    // connect / disconnect
    const cm = line.match(/\.connect\s*\(\s*(.*)/);
    if (cm) {
      const rest = cm[1];
      info.connects.push({
        line: ln,
        lambda: /func\s*\(/.test(rest),
        oneShot: /CONNECT_ONE_SHOT/.test(rest),
      });
    }
    if (/\.disconnect\s*\(/.test(line)) info.disconnects.push({ line: ln });

    if (/\badd_child\s*\(|\badd_sibling\s*\(/.test(line)) info.addChild++;
    if (/\bqueue_free\s*\(|\bfree\s*\(/.test(line)) info.queueFree++;

    // fields declared at file scope (indent 0)
    if (indents[i] === 0) {
      const em = line.match(/^@export[^\n]*?\bvar\s+([A-Za-z_]\w*)/);
      const vm = line.match(/^var\s+([A-Za-z_]\w*)\s*(?::|=|$)/);
      const km = line.match(/^const\s+([A-Za-z_]\w*)\s*(?::|=|$)/);
      if (em) info.fields.push({ name: em[1], line: ln, exported: true, doc: docComment(lines, i) });
      else if (vm) info.fields.push({ name: vm[1], line: ln, exported: false, doc: docComment(lines, i) });
      else if (km) info.fields.push({ name: km[1], line: ln, exported: false, const: true, doc: docComment(lines, i) });
      // computed property: `var x: T:` (getter on the next line) or `...: get = ...`
      const pm = line.match(/^var\s+([A-Za-z_]\w*)\s*:[^:=]+:/) || line.match(/^var\s+([A-Za-z_]\w*)\s*:.*\bget\b/);
      if (pm) {
        info.fields.push({ name: pm[1], line: ln, exported: false, computed: true, doc: docComment(lines, i) });
      }
    }

    if (/\bSCRIPT ERROR\b|\bParse Error\b/.test(line)) info.parseErrorHints.push(ln);
  }

  // functions + body lengths
  const funcRe = /^([ \t]*)func\s+([A-Za-z_]\w*)\s*\(/;
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(funcRe);
    if (!m) continue;
    const startIndent = indentWidth(lines[i]);
    let end = i;
    for (let j = i + 1; j < lines.length; j++) {
      const d = indents[j];
      if (d >= 0 && d <= startIndent) break;
      end = j;
    }
    const name = m[2];
    const length = end - i + 1;
    const body = lines.slice(i, end + 1).join('\n');
    info.funcs.push({
      name,
      start: i + 1,
      end: end + 1,
      length,
      isPublic: !name.startsWith('_'),
      returnsValue: /\breturn\b\s+\S/.test(body),
      doc: docComment(lines, i),
    });
    if (length >= FUNC_MIN_LINES) {
      const bodyDepth = Math.floor(Math.max(...indents.slice(i + 1, end + 1), 0) / 4);
      info.maxDepth = Math.max(info.maxDepth, bodyDepth);
    }
  }

  info.indent.dominant = info.indent.tabLines >= info.indent.spaceLines ? 'tab' : 'space';
  info.indent.mixed = info.indent.tabLines > 0 && info.indent.spaceLines > 0;
  return info;
}

// ───────────────────────────────────────────── aggregate indexes ──

// Blank out string-literal contents so a property name appearing only inside a
// string ("return key name") is not mistaken for a reference to the symbol.
function stripStrings(text) {
  // Per line: a lone apostrophe in a comment must never swallow code across
  // newlines (GDScript string literals are single-line in this codebase).
  return text
    .split('\n')
    .map((l) => l.replace(/"(?:[^"\\]|\\.)*"/g, '""').replace(/'(?:[^'\\]|\\.)*'/g, "''"))
    .join('\n');
}

function escapeRe(name) {
  return name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function countWordRefs(corpus, name) {
  const re = new RegExp(`(?<![A-Za-z0-9_])${escapeRe(name)}(?![A-Za-z0-9_])`, 'g');
  let n = 0;
  for (const text of corpus.values()) {
    const found = text.match(re);
    if (found) n += found.length;
  }
  return n;
}

// Count references where the symbol is READ (not just assigned). Approximate:
// a match followed by `=`/`:=`/compound-assign is a write; the declaration
// (`var name`, `@export var name`) is neither. String literals are stripped.
function countReadRefs(corpus, name) {
  const re = new RegExp(`(?<![A-Za-z0-9_])${escapeRe(name)}(?![A-Za-z0-9_])`, 'g');
  let reads = 0;
  for (const raw of corpus.values()) {
    const text = stripStrings(raw);
    for (const line of text.split('\n')) {
      re.lastIndex = 0;
      let m;
      while ((m = re.exec(line)) !== null) {
        const before = line.slice(0, m.index);
        if (/^\s*(@\w+[^\n]*?)?(var|const)\s+$/.test(before)) continue; // declaration
        const after = line.slice(m.index + name.length);
        if (/^\s*(:[^=]|\+|-|\*|\/|%|&|\||\^)?=/.test(after) && !/^\s*==/.test(after)) continue; // write
        reads++;
      }
    }
  }
  return reads;
}

function findDuplication(files) {
  const normalizedByFile = new Map();
  for (const f of files) {
    const lines = readText(join(ROOT, f)).split('\n');
    normalizedByFile.set(f, lines.map(normLine));
  }

  const index = new Map(); // hash -> [{file, i}]
  for (const [file, norm] of normalizedByFile) {
    const usable = [];
    for (let i = 0; i < norm.length; i++) {
      if (isTrivial(norm[i])) continue;
      usable.push({ i, n: norm[i] });
    }
    for (let w = 0; w + DUP_WINDOW <= usable.length; w++) {
      const slice = usable.slice(w, w + DUP_WINDOW);
      const text = slice.map((s) => s.n).join('\n');
      if (text.length < 120) continue;
      if (new Set(slice.map((s) => s.n)).size < 5) continue;
      const hash = createHash('sha1').update(text).digest('hex');
      if (!index.has(hash)) index.set(hash, []);
      index.get(hash).push({ file, i: slice[0].i });
    }
  }

  // For every hashed window that appears in >=2 places, expand each pair into
  // the maximal matching run, then keep only maximal non-contained runs.
  const runsByPair = new Map();
  const normOf = (file) => normalizedByFile.get(file);
  const eq = (fa, ia, fb, ib) => {
    const a = normOf(fa)[ia];
    const b = normOf(fb)[ib];
    return a !== undefined && b !== undefined && a === b;
  };

  for (const occ of index.values()) {
    if (occ.length < 2) continue;
    const capped = occ.slice(0, 12);
    for (let x = 0; x < capped.length; x++) {
      for (let y = x + 1; y < capped.length; y++) {
        const a = capped[x];
        const b = capped[y];
        const same = a.file === b.file;
        // skip near-overlapping occurrences (same region, sliding window)
        if (same && Math.abs(a.i - b.i) < DUP_WINDOW) continue;
        let left = 0;
        while (
          a.i - left - 1 >= 0 &&
          b.i - left - 1 >= 0 &&
          (!same || Math.abs(a.i - left - 1 - (b.i - left - 1)) >= 1) &&
          eq(a.file, a.i - left - 1, b.file, b.i - left - 1)
        ) left++;
        let right = 0;
        const maxRight = same ? Math.abs(a.i - b.i) - DUP_WINDOW : Infinity;
        while (
          right < maxRight &&
          a.i + DUP_WINDOW + right < normOf(a.file).length &&
          b.i + DUP_WINDOW + right < normOf(b.file).length &&
          eq(a.file, a.i + DUP_WINDOW + right, b.file, b.i + DUP_WINDOW + right)
        ) right++;
        const startA = a.i - left;
        const startB = b.i - left;
        const len = left + DUP_WINDOW + right;
        const runText = normOf(a.file).slice(startA, startA + len).filter((n) => n !== '').join('\n');
        if (new Set(runText.split('\n')).size < 5) continue;
        const key = `${a.file}:${startA}|${b.file}:${startB}`;
        const prev = runsByPair.get(key);
        if (!prev || len > prev.len) {
          runsByPair.set(key, { fileA: a.file, lineA: startA + 1, fileB: b.file, lineB: startB + 1, len });
        }
      }
    }
  }

  // Drop runs entirely contained in a larger run covering the same file pair
  // (in either orientation).
  const all = [...runsByPair.values()];
  const keep = [];
  for (const r of all) {
    const contained = all.some(
      (o) =>
        o !== r &&
        o.len > r.len &&
        ((o.fileA === r.fileA && o.lineA <= r.lineA && o.fileB === r.fileB && o.lineB <= r.lineB) ||
          (o.fileA === r.fileB && o.fileB === r.fileA))
    );
    if (!contained) keep.push(r);
  }
  keep.sort((a, b) => b.len - a.len);
  return keep.slice(0, 30).map((r) => ({
    lines: r.len,
    locations: [
      { file: r.fileA, line: r.lineA },
      { file: r.fileB, line: r.lineB },
    ],
  }));
}

// ───────────────────────────────────────────────── import gate ──

function runImportGate() {
  mkdirSync(SCRATCH, { recursive: true });
  const logPath = join(SCRATCH, 'qa-import.log');
  // `.godot/` is a SHARED per-repo cache. Run Godot through tools/godot-lock.sh
  // (the same flock verify-all uses) so a direct import can never race the gate
  // and hang on `reimport | ...` (AGENTS: direct Godot only via the wrapper).
  const lockScript = join(ROOT, 'tools', 'godot-lock.sh');
  const useLock = existsSync(lockScript);
  const cmd = useLock ? 'bash' : (process.env.GODOT_BIN || 'godot');
  const args = useLock
    ? [lockScript, '--headless', '--path', ROOT, '--import']
    : ['--headless', '--path', ROOT, '--import'];
  let out = '';
  let code = 0;
  try {
    out = execFileSync(cmd, args, {
      encoding: 'utf8',
      timeout: 1200000,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (e) {
    code = typeof e.status === 'number' ? e.status : 1;
    out = `${e.stdout || ''}\n${e.stderr || ''}`;
  }
  writeFileSync(logPath, out);

  const errorLines = out
    .split('\n')
    .filter((l) => /SCRIPT ERROR|Parse Error|Failed to load|Cannot open/.test(l));
  const errors = out.split('\n').filter((l) => /^\s*ERROR:/.test(l));
  return { code, logPath, errorLines, errorCount: errors.length };
}

// ───────────────────────────────────────────────────── findings ──

function buildFindings(scans, refCorpus, refCorpusRaw, importGate, openTasksText = '') {
  const findings = [];
  const add = (severity, rule, file, line, message, evidence, owner = '') =>
    findings.push({ severity, rule, file, line, message, evidence, owner });
  // A value-returning API named in an open task/claim (STATUS.md) is a pending
  // consumer (work in flight), not real debt.
  const mentionedOpen = (name) =>
    new RegExp(`(?<![A-Za-z0-9_])${escapeRe(name)}(?![A-Za-z0-9_])`).test(openTasksText);
  // Owner-documented intentional hook (planned consumer), e.g.
  // `## ... No caller yet.` / `## ... documented hooks until M7 is wired.`
  // Deliberately explicit phrases, NOT bare "hook": `hook` is common in this
  // codebase (skill/event hooks) and would reclassify real dead API.
  const isHookDoc = (doc) => /no caller yet|pending consumer|consumidor-pendente|documented hook/i.test(doc || '');

  // BLOCKER: import gate
  if (importGate && (importGate.code !== 0 || importGate.errorLines.length > 0)) {
    add(
      'BLOCKER',
      'import-gate',
      'project.godot',
      0,
      `godot --import exited ${importGate.code} with ${importGate.errorLines.length} parse/script error line(s)`,
      importGate.errorLines.slice(0, 8).join(' || ') || `see ${importGate.logPath}`
    );
  }

  for (const s of scans) {
    // MAJOR: god object
    if (s.lines > GOD_OBJECT_LINES) {
      add('MAJOR', 'god-object', s.path, 1, `file has ${s.lines} lines (> ${GOD_OBJECT_LINES})`, `${s.funcs.length} functions`, 'per-owner');
    }

    // MAJOR: duplicated logic (attached once per duplicate group)
    // handled separately below in buildDuplicationFindings

    // MINOR: long functions
    for (const f of s.funcs) {
      if (f.length > LONG_FUNCTION_LINES) {
        add('MINOR', 'long-function', s.path, f.start, `${f.name}() is ${f.length} lines (> ${LONG_FUNCTION_LINES})`, `ends line ${f.end}`);
      }
    }

    // MINOR: deep nesting
    if (s.maxDepth >= DEEP_NESTING) {
      add('MINOR', 'deep-nesting', s.path, 1, `max block nesting depth ${s.maxDepth} (>= ${DEEP_NESTING})`, `measured from function bodies`);
    }

    // MINOR: debug prints in shipping paths
    if (s.prints.length > 0) {
      add('MINOR', 'debug-print', s.path, s.prints[0].line, `${s.prints.length} print()/printerr() call(s) in shipping source`, s.prints.slice(0, 4).map((p) => `${p.line}: ${p.text}`).join(' || '));
    }

    // MINOR: connection leak risk
    const conn = s.connects.length;
    const disc = s.disconnects.length;
    if (conn >= 3 && disc === 0) {
      add('MINOR', 'connect-leak', s.path, s.connects[0].line, `${conn} .connect() and 0 .disconnect() in file`, `no teardown in _exit_tree`);
    }
    const lambdaLeaks = s.connects.filter((c) => c.lambda && !c.oneShot);
    if (lambdaLeaks.length > 0) {
      add('MINOR', 'lambda-leak', s.path, lambdaLeaks[0].line, `${lambdaLeaks.length} lambda .connect() without CONNECT_ONE_SHOT or stored Callable`, lambdaLeaks.slice(0, 3).map((c) => String(c.line)).join(','));
    }

    // MINOR: node churn without teardown
    if (s.addChild >= 5 && s.queueFree === 0) {
      add('MINOR', 'node-churn', s.path, 1, `${s.addChild} add_child()/add_sibling() and 0 queue_free()/free()`, `unbounded growth risk`);
    }

    // MINOR: TODOs carried as live debt
    if (s.todos.length > 0) {
      add('MINOR', 'invisible-debt', s.path, s.todos[0].line, `${s.todos.length} TODO/FIXME/HACK in shipping source`, s.todos.slice(0, 3).map((t) => `${t.line}: ${t.text}`).join(' || '));
    }

    // NIT: mixed indentation
    if (s.indent.mixed) {
      add('NIT', 'indent-mixed', s.path, 1, `mixed indentation (${s.indent.tabLines} tab / ${s.indent.spaceLines} space lines; dominant ${s.indent.dominant})`, 'convention: see docs/qa-report.md');
    }

    // MAJOR: dead API carried as live (qa.md: "dead code carried as live").
    // (a) public functions/getters with no callers anywhere in the repo.
    // Reference counting for methods uses the RAW corpus so every call shape is
    // covered: <inst>.<name>(, .<name>.connect(, .tscn/.tres signal
    // connections/properties, and Callable("<name>") strings. Only value-
    // returning functions are real debt; a void hook with no consumer yet is
    // informational (pending-consumer), never MAJOR.
    for (const f of s.funcs) {
      if (!f.isPublic) continue;
      const refs = countWordRefs(refCorpusRaw, f.name);
      if (refs <= 1) {
        if (f.returnsValue && !mentionedOpen(f.name) && !isHookDoc(f.doc)) {
          add('MAJOR', 'unused-func', s.path, f.start,
            `dead API: ${f.name}() computes a value but no caller consumes it (grep-based; confirm it is not an engine/duck-typed hook)`,
            `refs=${refs}`);
        } else {
          add('NIT', 'pending-consumer', s.path, f.start,
            `pending consumer: ${f.name}() has no caller yet (wire it up or delete it; informational, not debt)`,
            `refs=${refs}`);
        }
      }
    }
    // (b) fields declared and never referenced, (c) computed props / write-only
    for (const fld of s.fields) {
      const refs = countWordRefs(refCorpus, fld.name);
      if (fld.computed) {
        if (refs <= 1) {
          add('MAJOR', 'dead-api', s.path, fld.line,
            `dead API: computed property ${fld.name} is calculated but nothing consumes it`,
            `refs=${refs}`);
        }
        continue;
      }
      if (refs <= 1 && isHookDoc(fld.doc)) {
        add('NIT', 'pending-consumer', s.path, fld.line,
          `pending consumer: ${fld.name} is a documented hook with no caller yet (informational, not debt)`,
          `refs=${refs}`);
      } else if (refs <= 1) {
        const kind = fld.exported ? '@export var' : fld.const ? 'const' : 'var';
        add('MAJOR', 'unused-field', s.path, fld.line,
          `dead API: ${kind} ${fld.name} never referenced anywhere (grep-based, confirm it is not read by a scene/resource)`,
          `refs=${refs}`);
      } else if (!fld.exported && !fld.const) {
        const reads = countReadRefs(refCorpus, fld.name);
        if (reads === 0) {
          add('MAJOR', 'dead-api', s.path, fld.line,
            `dead API: field ${fld.name} is written but never read`,
            `refs=${refs} reads=0`);
        }
      }
    }
  }
  return findings;
}

function buildDuplicationFindings(dupes) {
  return dupes.map((d) => ({
    severity: 'MAJOR',
    rule: 'duplication',
    file: d.locations[0].file,
    line: d.locations[0].line,
    message: `${d.locations.length}x duplicated ${d.lines}-line block`,
    evidence: d.locations.map((l) => `${l.file}:${l.line}`).join(' === '),
  }));
}

// ───────────────────────────────────── shipped-content checks ──

// Dangling res:// references: ext_resource paths, preload()/load() literals,
// autoload/icon settings. A missing path is a latent export/shader failure.
function checkBrokenReferences() {
  const findings = [];
  const files = [join(ROOT, 'project.godot')];
  // Shipped trees only: tools/, .opencode/ skills and unrelated addons carry
  // illustrative res:// paths that are not part of the game build.
  for (const r of ['resources', 'src', 'scenes', 'addons/cabra.lat_shooters']) {
    for (const full of walk(join(ROOT, r))) {
      if (/\.(tscn|tres|gd|gdshader)$/.test(full)) files.push(full);
    }
  }
  const seen = new Set();
  for (const full of files) {
    const rel = relative(ROOT, full);
    const lines = readText(full).split('\n');
    for (let i = 0; i < lines.length; i++) {
      let line = lines[i];
      // comments in .gd often show illustrative res:// paths; not a real ref
      if (rel.endsWith('.gd')) line = stripComment(line);
      const re = /res:\/\/([A-Za-z0-9_\-./%]+)/g;
      let m;
      while ((m = re.exec(line)) !== null) {
        let p = m[1].replace(/[.,;:")'\]]+$/, '');
        if (p.includes('%') || p.endsWith('/')) continue;
        const key = `${rel}:${i + 1}:${p}`;
        if (seen.has(key)) continue;
        seen.add(key);
        const abs = join(ROOT, p);
        if (existsSync(abs)) continue;
        const dir = dirname(abs);
        const base = p.split('/').pop();
        let caseMatch = null;
        if (existsSync(dir)) {
          const real = readdirSync(dir).find((n) => n.toLowerCase() === base.toLowerCase());
          if (real && real !== base) caseMatch = real;
        }
        if (caseMatch) {
          findings.push({
            severity: 'MINOR', rule: 'case-mismatch', file: rel, line: i + 1,
            message: `res:// path case mismatch: "${p}" (on disk "${caseMatch}")`,
            evidence: 'breaks case-sensitive exports/builds',
          });
        } else {
          findings.push({
            severity: 'MAJOR', rule: 'broken-ref', file: rel, line: i + 1,
            message: `dangling res:// reference: "${p}" does not exist`,
            evidence: 'latent export/shader failure',
          });
        }
      }
    }
  }
  return findings;
}

// AGENTS.md "Identity rule": shipped content must not carry commercial-game
// proper nouns. docs/ and *.md are research material and are exempt.
function checkIpNames() {
  const findings = [];
  const roots = ['resources', 'src', 'scenes', 'addons/cabra.lat_shooters/src'];
  const files = [join(ROOT, 'project.godot')];
  const pathFiles = [];
  for (const r of roots) {
    for (const full of walk(join(ROOT, r))) {
      pathFiles.push(full);
      if (/\.(gd|tscn|tres|cfg|godot|txt|json)$/.test(full)) files.push(full);
    }
  }
  // Shipped art/models carry brand names in their filenames too; content is
  // binary so only the path is scanned. `.import`/`.uid` are generated metadata
  // next to the real file -> skipped to avoid duplicate findings.
  for (const full of walk(join(ROOT, 'assets'))) pathFiles.push(full);

  // (a) brand in a shipped FILENAME. A resource/scene filename IS the resource
  // name -> BLOCKER; a script/art filename -> MAJOR (identity-rule severity).
  for (const full of pathFiles) {
    const rel = relative(ROOT, full);
    if (isIpExempt(rel) || /\.(import|uid)$/.test(rel)) continue;
    for (const term of IP_BRANDS) {
      if (term.re.global) term.re.lastIndex = 0;
      if (!term.re.test(rel)) continue;
      findings.push({
        severity: /\.(tres|tscn)$/.test(rel) ? 'BLOCKER' : 'MAJOR',
        rule: 'ip-name', file: rel, line: 1,
        message: `real firearm/accessory brand "${term.label}" in a shipped filename (neutral-placeholder rule)`,
        evidence: 'in path',
      });
    }
  }

  // (b) content scan (game names + brands) over text files.
  const tarkovByFile = new Map();
  for (const full of files) {
    const rel = relative(ROOT, full);
    if (isIpExempt(rel)) continue;
    const lines = readText(full).split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const isComment = rel.endsWith('.gd') && /^\s*#/.test(line);
      // Blank out packed binary arrays (vertex/mesh blobs) — short brand tokens
      // like HK/FN/BCM match random base64 data otherwise (false positive).
      const scanLine = line.replace(/Packed\w+Array\("[^"]*"\)/g, 'PackedArray("")');
      for (const term of IP_NAMES.concat(IP_BRANDS)) {
        if (term.re.global) term.re.lastIndex = 0;
        if (!term.re.test(scanLine)) continue;
        if (term.generic) {
          tarkovByFile.set(rel, (tarkovByFile.get(rel) || []).concat(i + 1));
          continue;
        }
        const nameCtx = /"?\b(name|id|title|label)\b"?\s*[:=]\s*"/.test(scanLine);
        const uiCtx = /\b(text|placeholder_text|tooltip_text|display_name)\s*=/.test(scanLine)
          || /set_text\s*\(|_set_center\s*\(|\.text\s*=/.test(scanLine);
        const sev = term.alwaysBlocker || nameCtx || uiCtx ? 'BLOCKER' : 'MAJOR';
        const what = term.brand
          ? `real firearm/accessory brand "${term.label}" (neutral-placeholder rule)`
          : `commercial-game proper noun "${term.label}" (Identity rule)`;
        findings.push({
          severity: sev, rule: 'ip-name', file: rel, line: i + 1,
          message: what,
          evidence: isComment ? 'in comment' : 'in code/string',
        });
      }
    }
  }
  for (const [rel, lns] of tarkovByFile) {
    findings.push({
      severity: 'MAJOR', rule: 'ip-tarkov', file: rel, line: lns[0],
      message: `"Tarkov" appears ${lns.length}x in shipped source; it may be a mechanical reference but must never be shipped content`,
      evidence: `lines ${lns.slice(0, 10).join(',')}${lns.length > 10 ? ',...' : ''}`,
    });
  }
  return findings;
}

// ─────────────────────────────────────────────────────── report ──

// Drop findings an owner has triaged as intentional (debug/HUD/engine hooks).
function applyIgnores(findings) {
  if (!existsSync(IGNORE_PATH)) return { findings, ignored: 0, entries: 0 };
  let list;
  try {
    list = JSON.parse(readFileSync(IGNORE_PATH, 'utf8'));
  } catch {
    return { findings, ignored: 0, entries: 0 };
  }
  if (!Array.isArray(list)) return { findings, ignored: 0, entries: 0 };
  const kept = [];
  let ignored = 0;
  let unowned = 0;
  for (const f of findings) {
    const hit = list.find((g) =>
      g.file === f.file && g.rule === f.rule && (!g.name || String(f.message).includes(g.name)));
    if (hit) {
      ignored++;
      if (!hit.confirmed_by) unowned++;
    } else kept.push(f);
  }
  const confirmers = [...new Set(list.map((g) => g.confirmed_by).filter(Boolean))];
  return { findings: kept, ignored, entries: list.length, unowned, confirmers };
}

// Dead-API family by owner: the breakdown the coordinator routes triage from.
function ownerRuleBreakdown(findings) {
  const DEAD = ['unused-func', 'unused-field', 'dead-api', 'pending-consumer'];
  const out = {};
  for (const f of findings) {
    if (!DEAD.includes(f.rule)) continue;
    const o = f.owner || 'unassigned';
    if (!out[o]) out[o] = { 'unused-func': 0, 'unused-field': 0, 'dead-api': 0, 'pending-consumer': 0 };
    out[o][f.rule]++;
  }
  return out;
}

function severityCounts(findings) {
  const c = { BLOCKER: 0, MAJOR: 0, MINOR: 0, NIT: 0 };
  for (const f of findings) c[f.severity] = (c[f.severity] || 0) + 1;
  return c;
}

function ruleCounts(findings) {
  const c = {};
  for (const f of findings) c[f.rule] = (c[f.rule] || 0) + 1;
  return c;
}

function summarizeByFile(findings) {
  const map = new Map();
  for (const f of findings) {
    if (!map.has(f.file)) map.set(f.file, { BLOCKER: 0, MAJOR: 0, MINOR: 0, NIT: 0 });
    map.get(f.file)[f.severity]++;
  }
  return [...map.entries()].sort(
    (a, b) =>
      SEVERITY_ORDER.reduce((s, k) => s + b[1][k] * 1000, 0) -
      SEVERITY_ORDER.reduce((s, k) => s + a[1][k] * 1000, 0)
  );
}

function renderReport(findings, scans, importGate, dupes, manualStats, ignoreResult, ownerBreakdown, acceptedFollowups = []) {
  const counts = severityCounts(findings);
  const byRule = ruleCounts(findings);
  const byFile = summarizeByFile(findings);
  const totalLines = scans.reduce((s, f) => s + f.lines, 0);
  const totalFuncs = scans.reduce((s, f) => s + f.funcs.length, 0);
  const longFuncs = scans.flatMap((s) => s.funcs.filter((f) => f.length > LONG_FUNCTION_LINES));
  const tabFiles = scans.filter((s) => s.indent.dominant === 'tab' && s.indent.tabLines > 0).length;
  const spaceFiles = scans.filter((s) => s.indent.dominant === 'space' && s.indent.spaceLines > 0).length;

  const L = [];
  L.push('# QA report — fps-basegame');
  L.push('');
  L.push(`Generated: ${new Date().toISOString()}  `);
  L.push(`Tool: \`tools/qa/audit.mjs\` v${TOOL_VERSION}  |  scope: \`${SCAN_DIRS.join('`, `')}\``);
  L.push('');
  L.push('> Findings are **work orders**, not fixes. Every row carries a number or a `file:line`.');
  L.push('> Severity scale: BLOCKER / MAJOR / MINOR / NIT (see `.opencode/agents/qa.md`).');
  L.push('');
  L.push('## Summary');
  L.push('');
  L.push('| Severity | Count |');
  L.push('| --- | ---: |');
  for (const s of SEVERITY_ORDER) L.push(`| ${s} | ${counts[s]} |`);
  L.push(`| **Total** | **${findings.length}** |`);
  L.push('');
  L.push(`Scanned ${scans.length} shipping \`.gd\` files, ${totalLines} lines, ${totalFuncs} functions. ` +
    `${longFuncs.length} functions > ${LONG_FUNCTION_LINES} lines. ` +
    `Indent census (dominant): ${tabFiles} tab files / ${spaceFiles} space files.`);
  L.push('');
  L.push('### By rule');
  L.push('');
  L.push('| Rule | Count |');
  L.push('| --- | ---: |');
  for (const [r, n] of Object.entries(byRule).sort((a, b) => b[1] - a[1])) L.push(`| ${r} | ${n} |`);
  L.push('');
  if (importGate) {
    L.push('## Import gate');
    L.push('');
    L.push(`\`${process.env.GODOT_BIN || 'godot'} --headless --path . --import\` → exit **${importGate.code}**, ` +
      `${importGate.errorCount} \`ERROR:\` lines, ${importGate.errorLines.length} parse/script error lines. Log: \`${importGate.logPath}\`.`);
    L.push('');
  }

  L.push('## Baseline & taxonomy');
  L.push('');
  L.push(`Tool version **${TOOL_VERSION}**. Manual findings are re-probed by \`--verify-manual\`; ` +
    `a finding whose probe prints \`QA_RESULT=RESOLVED\` is dropped from the counts so a fixed bug cannot keep CI red.`);
  if (manualStats) {
    L.push(`This run verified **${manualStats.ran}** probe(s): ${manualStats.active} still reproduced, ` +
      `${manualStats.resolved} resolved, ${manualStats.unverified} without a probe (reported as \`unverified\`), ` +
      `${manualStats.errors || 0} errored/no-result (status kept, needs a re-run).`);
  }
  if (ignoreResult && ignoreResult.entries > 0) {
    L.push(`Triage: **${ignoreResult.ignored}** finding(s) suppressed by \`${relative(ROOT, IGNORE_PATH)}\` ` +
      `(${ignoreResult.entries} entries, each with a \`confirmed_by\`: ${ignoreResult.confirmers.join(', ') || 'NONE'})` +
      (ignoreResult.unowned > 0 ? `. **${ignoreResult.unowned} suppression(s) have no confirmer and must be audited.**` : '.'));
  }
  if (ownerBreakdown && Object.keys(ownerBreakdown).length > 0) {
    L.push('');
    L.push('## Dead-API breakdown by owner');
    L.push('');
    L.push('| Owner | unused-func (MAJOR) | unused-field (MAJOR) | dead-api (MAJOR) | pending-consumer (NIT) |');
    L.push('| --- | ---: | ---: | ---: | ---: |');
    for (const [o, c] of Object.entries(ownerBreakdown).sort((a, b) => a[0].localeCompare(b[0]))) {
      L.push(`| ${o} | ${c['unused-func']} | ${c['unused-field']} | ${c['dead-api']} | ${c['pending-consumer']} |`);
    }
  }
  let baseline = null;
  if (existsSync(BASELINE_PATH)) {
    try {
      baseline = JSON.parse(readFileSync(BASELINE_PATH, 'utf8'));
    } catch { baseline = null; }
  }
  if (baseline) {
    const taxChanged = baseline.toolVersion !== TOOL_VERSION ||
      JSON.stringify((baseline.rules || []).slice().sort()) !== JSON.stringify(RULE_VOCABULARY);
    L.push('');
    L.push('| Severity | Baseline | Current |');
    L.push('| --- | ---: | ---: |');
    for (const s of SEVERITY_ORDER) L.push(`| ${s} | ${baseline.counts?.[s] ?? '-'} | ${counts[s]} |`);
    L.push('');
    L.push(`Baseline tool v${baseline.toolVersion || '?'}${taxChanged ? ' — **taxonomy changed** (new/removed rule set): a MAJOR jump is an explained reclassification, and \`--check\` will not fail on it until the baseline is refreshed.' : ''}`);
    if (baseline.toolVersion !== TOOL_VERSION) {
      L.push('');
      L.push(`Taxonomy note (v${baseline.toolVersion || '?'} -> v${TOOL_VERSION}): rule set and/or severity mapping changed. ` +
        'A MAJOR delta across a version change is a reclassification (policy), not automatically a regression; `--check` will not fail on it until the baseline is refreshed.');
    }
  }
  if (acceptedFollowups.length > 0) {
    L.push('');
    L.push('## Accepted follow-up debt (non-gating)');
    L.push('');
    L.push('These findings remain visible for owner follow-up but are intentionally excluded from severity totals and the `--check` regression gate.');
    L.push('');
    L.push('| ID | Severity | Owner | Task | Location | Disposition |');
    L.push('| --- | --- | --- | --- | --- | --- |');
    for (const m of acceptedFollowups) {
      const loc = m.line > 0 ? `\`${m.file || '?'}:${m.line}\`` : `\`${m.file || '?'}\``;
      const msg = String(m.disposition_note || m.message || '').replace(/\|/g, '\\|');
      L.push(`| ${m.id || '?'} | ${m.severity || 'MINOR'} | ${m.owner || ''} | ${m.task || ''} | ${loc} | ${msg} |`);
    }
  }
  L.push('');
  L.push('## Findings');
  L.push('');
  L.push('| Severity | Rule | Owner | Location | Finding | Evidence |');
  L.push('| --- | --- | --- | --- | --- | --- |');
  for (const f of findings.sort((a, b) =>
    SEVERITY_ORDER.indexOf(a.severity) - SEVERITY_ORDER.indexOf(b.severity) ||
    a.file.localeCompare(b.file) || a.line - b.line)) {
    const loc = f.line > 0 ? `\`${f.file}:${f.line}\`` : `\`${f.file}\``;
    const msg = String(f.message).replace(/\|/g, '\\|');
    const ev = String(f.evidence || '').replace(/\|/g, '\\|').slice(0, 220);
    L.push(`| ${f.severity} | ${f.rule} | ${f.owner || ''} | ${loc} | ${msg} | ${ev} |`);
  }
  L.push('');
  L.push('## Top files by finding weight');
  L.push('');
  L.push('| File | BLOCKER | MAJOR | MINOR | NIT |');
  L.push('| --- | ---: | ---: | ---: | ---: |');
  for (const [file, c] of byFile.slice(0, 25)) L.push(`| \`${file}\` | ${c.BLOCKER} | ${c.MAJOR} | ${c.MINOR} | ${c.NIT} |`);
  L.push('');
  L.push('## Duplication (fingerprint, ' + DUP_WINDOW + '-line windows)');
  L.push('');
  if (dupes.length === 0) L.push('_none above threshold_');
  else {
    L.push('| Lines | Locations |');
    L.push('| ---: | --- |');
    for (const d of dupes) {
      L.push(`| ${d.lines} | ${d.locations.map((l) => `\`${l.file}:${l.line}\``).join('<br>')} |`);
    }
  }
  L.push('');
  L.push('## Indentation census (per root)');
  L.push('');
  L.push('| Root | Files | Tab-dominant | Space-dominant | No indentation |');
  L.push('| --- | ---: | ---: | ---: | ---: |');
  const roots = new Map();
  for (const s of scans) {
    const r = rootOf(s.path);
    if (!roots.has(r)) roots.set(r, { files: 0, tab: 0, space: 0, none: 0 });
    const o = roots.get(r);
    o.files++;
    if (s.indent.tabLines === 0 && s.indent.spaceLines === 0) o.none++;
    else if (s.indent.dominant === 'tab') o.tab++;
    else o.space++;
  }
  for (const [r, o] of roots) L.push(`| ${r} | ${o.files} | ${o.tab} | ${o.space} | ${o.none} |`);
  L.push('');
  L.push('## Conventions');
  L.push('');
  L.push('- **Indentation is split by repo, not messy per file.** The addon (`addons/`) is dominantly **4-space**; the game repo (`src/`, `scenes/`) is dominantly **tab**. No shipped file mixes both styles (see census). Proposed rule: keep the addon at 4 spaces and the game repo at tabs; do **not** mass-rewrite either.');
  L.push('- Debug `print()` is forbidden in shipping paths (`src/`, `scenes/`, addon `src/`); test harnesses (`validate_*.gd`, `test/`) may print. Prints on, or inside, an `if OS.is_debug_build():` guard are debug-only and are **not** counted as `debug-print` findings.');
  L.push('- **Dead-API triage (three classes).** `morto-real` = a value-returning function, computed property or field that exists and is never consumed -> **MAJOR debt** (`unused-func`, `unused-field`, `dead-api`). `consumidor-pendente` = a void hook/API with no caller yet -> **NIT, informational, not debt** (`pending-consumer`); a value-returning API/field whose declaration is documented as an intentional hook (doc comment containing `no caller yet`, `pending consumer` or `documented hook`) is also `consumidor-pendente`, so a planned consumer is not misreported as debt. `falso-positivo-de-scan` = the matcher missed a real caller -> **tool bug, never counted**. `falso-positivo-de-scan` = the matcher missed a real caller -> **tool bug, never counted**. The caller matcher covers `<inst>.<name>(`, `.<name>.connect(`, `.tscn`/`.tres` signal connections and properties, and `Callable("<name>")` strings.');
  L.push('- **Identity rule (AGENTS.md):** `ip-name` / `ip-tarkov` scan shipped code+resources for commercial-game proper nouns AND real firearm/accessory brands (`IP_BRANDS`: Glock, Magpul, Surefire, Aimpoint, EOTech, Vortex, Trijicon/ACOG, Beretta, Remington, Barrett, Colt, FN, HK, Kalashnikov, ...). Brands are matched in file contents AND in shipped filenames (`assets/**` included) so a branded `.tres`/`.png`/`.glb` cannot regress. Technical standards and authors (GOST, NIJ, VPAM, STANAG, RHA, HIC, Recht-Ipson, Poncelet) are public references and are NOT findings, and `docs/**` may cite sources. A proper noun/brand in a resource `name`, a `.tres`/`.tscn` filename, or a player-facing string is a BLOCKER; elsewhere (scripts, art filenames) MAJOR.');
  L.push('- **Reference integrity:** `broken-ref` reports `res://` paths that do not exist (latent export/shader failure); `case-mismatch` reports names that only exist with different case (case-sensitive export breakage).');
  L.push('- Contract checks a static tool cannot prove (rule 4 physics queries in `_physics_process`; rule 5 held items never simulated) are hand-reviewed in `tools/qa/manual-findings.json` and merged into the Findings table above (they carry an Owner and a `QA-NNN` id in the evidence).');
  L.push('- CI: `node tools/qa/audit.mjs --check` exits 1 on any BLOCKER and 2 when MAJOR rises above `docs/qa-baseline.json`; `--update-baseline` re-snapshots.');
  L.push('');
  return L.join('\n');
}

// ─────────────────────────────────────────────────────────── main ──

function main() {
  const scans = [];
  for (const dir of SCAN_DIRS) {
    for (const full of walk(join(ROOT, dir))) {
      if (!full.endsWith('.gd')) continue;
      scans.push(analyzeGd(full, relative(ROOT, full)));
    }
  }
  scans.sort((a, b) => a.path.localeCompare(b.path));

  // Reference corpus: every text file in the repo (so scene/tres references count).
  // `refCorpus` blanks string literals (good for field/property names, where a
  // string key is not a reference); `refCorpusRaw` keeps them (good for method
  // names, which GDScript can call via Callable("...") / connect("name", ...)).
  const refCorpus = new Map();
  const refCorpusRaw = new Map();
  for (const dir of ['.']) {
    for (const full of walk(join(ROOT, dir))) {
      const rel = relative(ROOT, full);
      if (!isReferencePath(rel)) continue;
      const raw = readText(full);
      refCorpusRaw.set(rel, raw);
      refCorpus.set(rel, stripStrings(raw));
    }
  }

  const importGate = flag('--no-import') ? null : runImportGate();

  // Re-run manual probes before the gate decides, so a fixed finding cannot
  // keep CI red. Plain report runs keep the stored statuses (no re-probing).
  const doVerify = flag('--verify-manual') || (flag('--check') && !flag('--no-verify'));
  // CI/check is a read-only gate. Probe results may change the in-memory
  // classification, but only an explicit non-check verification may persist
  // MANUAL_PATH; otherwise a scan would dirty a tracked worktree file.
  const manualStats = doVerify ? verifyManualFindings(!flag('--check')) : null;

  // Open claims/tasks: an API named here is "pending consumer", not dead.
  let openTasksText = '';
  const busDirs = [
    join(ROOT, '.agent-mail', 'bus'),
    join(ROOT, '.opencode', 'bus'),
  ];
  for (const bDir of busDirs) {
    if (!existsSync(bDir)) continue;
    for (const sub of ['backlog', 'doing', 'blocked']) {
      const subDir = join(bDir, sub);
      if (existsSync(subDir)) {
        try {
          for (const file of readdirSync(subDir)) {
            if (file.endsWith('.md')) {
              openTasksText += readFileSync(join(subDir, file), 'utf8') + '\n';
            }
          }
        } catch {}
      }
    }
  }

  let findings = buildFindings(scans, refCorpus, refCorpusRaw, importGate, openTasksText);
  const dupes = findDuplication(scans.map((s) => s.path));
  findings = findings.concat(buildDuplicationFindings(dupes));
  findings = findings.concat(checkBrokenReferences());
  findings = findings.concat(checkIpNames());

  // Merge the manual review pass (tools/qa/manual-findings.json). Entries a
  // probe has proven RESOLVED are dropped so a fixed bug cannot keep CI red.
  // Accepted follow-up debt is retained for reporting but is intentionally
  // non-gating until its owner completes the scoped follow-up task.
  const acceptedFollowups = [];
  if (existsSync(MANUAL_PATH)) {
    try {
      const manual = JSON.parse(readFileSync(MANUAL_PATH, 'utf8'));
      if (Array.isArray(manual)) {
        for (const m of manual) {
          if (m.status === 'accepted-follow-up') {
            acceptedFollowups.push(m);
            continue;
          }
          if (m.status === 'resolved') continue;
          const note = m.probe
            ? (m.status === 'active' ? ' [probe: reproduced]' : '')
            : ' [unverified: no probe]';
          findings.push({
            severity: m.severity || 'MINOR',
            rule: m.rule || 'manual',
            file: m.file || '?',
            line: Number(m.line) || 0,
            message: (m.message || '') + note,
            evidence: m.evidence || '',
            owner: m.owner || '',
          });
        }
      }
    } catch (e) {
      console.error(`warn: could not parse ${MANUAL_PATH}: ${e.message}`);
    }
  }

  const ignoreResult = applyIgnores(findings);
  findings = ignoreResult.findings;

  // Routing hint: every finding gets an owner from its path (manual entries
  // keep their explicit owner).
  for (const f of findings) if (!f.owner) f.owner = ownerFor(f.file);

  const counts = severityCounts(findings);
  const byRule = ruleCounts(findings);
  const ownerBreakdown = ownerRuleBreakdown(findings);

  if (flag('--json')) {
    process.stdout.write(JSON.stringify({
      counts, byRule, findings, dupes,
      manual: manualStats,
      acceptedFollowups: acceptedFollowups.map((m) => ({
        id: m.id, severity: m.severity, owner: m.owner, task: m.task,
        file: m.file, line: m.line, disposition: m.disposition,
        message: m.message, evidence: m.evidence,
      })),
      ignored: { count: ignoreResult.ignored, entries: ignoreResult.entries },
      ownerBreakdown,
    }, null, 2) + '\n');
    return;
  }

  const report = renderReport(findings, scans, importGate, dupes, manualStats, ignoreResult, ownerBreakdown, acceptedFollowups);
  const reportTarget = reportPath || (flag('--write-report') ? REPORT_PATH : null);
  if (reportTarget) {
    mkdirSync(dirname(reportTarget), { recursive: true });
    writeFileSync(reportTarget, report + '\n');
  }

  const baselineData = {
    generated: new Date().toISOString(),
    toolVersion: TOOL_VERSION,
    scope: SCAN_DIRS,
    counts,
    byRule,
    rules: RULE_VOCABULARY.slice(),
    snapshot: { files: scans.length, lines: scans.reduce((s, f) => s + f.lines, 0) },
  };

  if (flag('--update-baseline')) {
    writeFileSync(BASELINE_PATH, JSON.stringify(baselineData, null, 2) + '\n');
    console.log(`baseline written: ${relative(ROOT, BASELINE_PATH)}`);
  }

  console.log(`QA audit: BLOCKER=${counts.BLOCKER} MAJOR=${counts.MAJOR} MINOR=${counts.MINOR} NIT=${counts.NIT}`);
  console.log(reportTarget ? `report: ${relative(ROOT, reportTarget)}` : 'report: not written (use --report <path> or --write-report)');
  if (importGate) console.log(`import gate: exit ${importGate.code} (${relative(ROOT, importGate.logPath)})`);

  if (flag('--check')) {
    let baseline = null;
    if (existsSync(BASELINE_PATH)) {
      try {
        baseline = JSON.parse(readFileSync(BASELINE_PATH, 'utf8'));
      } catch {
        baseline = null;
      }
    }
    if (!baseline) {
      // Deliberate act only: CI must never silently re-baseline itself.
      console.error('CI FAIL: no docs/qa-baseline.json. Re-baselining is a decision — run --update-baseline.');
      process.exit(3);
    }
    if (counts.BLOCKER > 0) {
      console.error(`CI FAIL: ${counts.BLOCKER} BLOCKER finding(s)`);
      process.exit(1);
    }
    // A taxonomy change (new rules / new tool version) explains a MAJOR jump;
    // do not fail on an explained reclassification, only on a real regression.
    const baselineRules = (baseline?.rules || []).slice().sort();
    const currentRules = RULE_VOCABULARY.slice();
    const taxonomyChanged = !baseline ||
      baseline.toolVersion !== TOOL_VERSION ||
      JSON.stringify(baselineRules) !== JSON.stringify(currentRules);
    if (baseline && counts.MAJOR > (baseline.counts?.MAJOR ?? 0)) {
      if (taxonomyChanged) {
        console.warn(`MAJOR ${baseline.counts.MAJOR} -> ${counts.MAJOR} but the taxonomy changed ` +
          `(baseline v${baseline.toolVersion || '?'} / ${baselineRules.length} rules vs ` +
          `v${TOOL_VERSION} / ${currentRules.length} rules) — not treated as a regression. ` +
          `Re-run with --update-baseline to re-snapshot.`);
      } else {
        console.error(`CI FAIL: MAJOR regressed ${baseline.counts.MAJOR} -> ${counts.MAJOR} (no taxonomy change)`);
        process.exit(2);
      }
    }
    process.exit(0);
  }
}

main();
