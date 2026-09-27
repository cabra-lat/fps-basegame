#!/usr/bin/env node
// tools/lint-repeated-flags.mjs — ADVISORY lint for the repeated-single-valued-flag class.
//
// THE CLASS. A flag that is single-valued is given more than once, and MORE THAN
// ONE PARTY reads the argv. Each party is locally reasonable; only the
// disagreement is wrong, which is why every instance of this passed human
// review and was found only by a probe or by someone running the thing.
//
//   --attach  the CLI read the FIRST occurrence and dropped the rest; something
//             downstream consumed the whole list. Three messages, one sent.
//   --path    the guard read the FIRST and validated it; Godot honours the LAST.
//             A foreign project tree went through a guard that had already
//             printed an accurate, reassuring message.
//
// WHAT THIS LINT IS, and what it is not.
//
// It is a STRUCTURAL lint: it finds scripts that read argv in more than one
// place AND mention the same flag in more than one of those places. That is the
// shape the bug takes, and it is checkable without running anything.
//
// It is NOT a runtime repetition detector. It cannot see an actual command line.
// If a script has one argv reader, or reads argv twice but mentions the flag in
// only one of them, this lint stays silent — and a silent lint that is read as
// "no repeated flags" is the failure this whole session has been about, so the
// summary states its coverage explicitly, including the files it did NOT
// understand. Partial coverage is reported as partial coverage.
//
// DECLARATIONS, so list flags are not false positives. A repeated list flag
// (--include, --tag, …) is the normal case and a lint that flags those trains
// people to ignore it. Declare the difference explicitly, in the script:
//
//   # lint:flags-single --path --clean-tmp      (or // lint:flags-single …)
//   # lint:flags-list   --include --tag
//   # lint:flags-refused --path
//
// lint:flags-refused is for a single-valued flag that is handled by more than
// one reader ON PURPOSE, because the script refuses on the ambiguity rather than
// choosing a winner (what tools/godot-lock.sh does for --path). Without it the
// lint flags a fixed file forever, and a lint that always cries wolf is a lint
// people stop reading — which is how the next real instance gets missed.
//
// An exemption is printed with its justification. Nothing is silenced silently,
// because a silent exemption and a passing check look identical from outside.
//
// ADVISORY BY DEFAULT: exits 0 whatever it finds, because a human decides. Pass
// --strict to exit 1 on any finding, for whoever wants it in a gate.
//
// Usage:  node tools/lint-repeated-flags.mjs [--strict] [--self-test] [paths…]

import { readFileSync, readdirSync, statSync, mkdtempSync, writeFileSync, mkdirSync, rmSync, existsSync } from 'node:fs';
import { join, relative, extname } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';

const SCAN_EXT = new Set(['.sh', '.mjs', '.js', '.py', '.bash']);
const SCAN_DIRS = ['tools', 'src/dev', 'scenes', '.github'];
// This file is excluded from its own scan. Its self-test fixtures contain
// deliberately wrong code (a contested --path, a list-flag exemption, two
// loops with different flags), and a lint that reports its own test data as
// findings is indistinguishable from a lint that does not understand itself.
const SELF = 'lint-repeated-flags.mjs';

// Each entry is a way a script CONSUMES argv. Every HIT is a separate party,
// not every kind: godot-lock.sh has three `"$@"` loops that disagree about
// --path, and counting them as one "kind" would have missed the exact instance
// that motivated this lint. A kind with several hits is several readers.
const READERS = [
  { id: 'shell $@', re: /"\$@"|'\$\@'|\$\{@\}/g },
  { id: 'shell $*', re: /"\$\*"|'\$\*'|\$\{\*\}/g },
  { id: 'append-to-passthrough-array', re: /\b[A-Za-z_]*ARGS?\s*\+=\s*\(?|\bargs\.push\(|\b_ARGS\+=/g },
  { id: 'node process.argv', re: /process\.argv/g },
  { id: 'python sys.argv', re: /sys\.argv/g },
  { id: 'shift-based', re: /\bshift\b/g },
];

// How much of the script counts as "this reader deals with this flag".
//
// The first version used a +-240 CHARACTER window around each hit and it was
// wrong in the direction that matters: on a short script every flag is within
// 240 characters of every reader, so two loops mentioning DIFFERENT flags were
// reported as a disagreement. The self-test caught it, which is the only reason
// it is not still in there.
//
// A reader deals with the flags in its own STATEMENT: from the hit forward
// until the block closes. That is the honest unit — a `for ... in "$@"` loop
// reads the flags it handles inside itself, not 200 characters away in a
// neighbouring statement. The terminators below are shell/GDScript/Python
// shapes, and the line cap keeps an unterminated block from swallowing the rest
// of the file. This is still crude and still disclosed as crude: it is a lint
// whose coverage a human can reason about, not one that is clever.
const MAX_STATEMENT_LINES = 8;
const BLOCK_TERMINATORS = /\b(done|esac|fi|elif|else)\b|[};]\s*$/;

const FLAG_TOKEN = /--[a-zA-Z][a-zA-Z0-9-]*/g;

function stripComments(text) {
  // Keep declaration comments; drop the rest so a flag mentioned in prose is
  // not counted as one the script consumes.
  return text
    .split('\n')
    .map((line) => (/lint:flags-(single|list)/.test(line) ? line : line.replace(/(^|\s)(#|\/\/).*$/, '$1')))
    .join('\n');
}

function readDeclarations(text) {
  const single = new Set();
  const list = new Set();
  const refused = new Set();
  for (const line of text.split('\n')) {
    const m = line.match(/lint:flags-(single|list|refused)\s+(.*)$/m);
    if (!m) continue;
    const target = m[1] === 'single' ? single : m[1] === 'list' ? list : refused;
    for (const flag of m[2].trim().split(/\s+/)) {
      if (flag.startsWith('--')) target.add(flag);
    }
  }
  return { single, list, refused };
}

// Byte offset of the start of each line, so a hit can be mapped to its line.
function lineStarts(code) {
  const starts = [0];
  for (let i = 0; i < code.length; i += 1) if (code[i] === '\n') starts.push(i + 1);
  return starts;
}

// The text of the statement a hit belongs to: its own line, extended forward
// while the block continues.
function statementAt(code, starts, pos) {
  let line = 0;
  while (line + 1 < starts.length && starts[line + 1] <= pos) line += 1;
  const lineText = (i) => {
    const end = code.indexOf('\n', starts[i]);
    return code.slice(starts[i], end === -1 ? code.length : end);
  };
  const first = lineText(line);
  // The hit's OWN line is tested for a terminator too. It was not, at first,
  // and a one-line `for ...; done` therefore ran on and swallowed the line
  // after it — so a loop mentioning --alpha appeared to handle --beta as well,
  // and two loops with genuinely different flags read as a disagreement. The
  // self-test caught it; the reason it is written down is that the bug is
  // invisible in the output, which just looks like a false positive.
  if (BLOCK_TERMINATORS.test(first.trim())) return first;
  const parts = [first];
  for (let i = line + 1; i < Math.min(line + MAX_STATEMENT_LINES, starts.length); i += 1) {
    const text = lineText(i);
    parts.push(text);
    if (BLOCK_TERMINATORS.test(text.trim())) break;
  }
  return parts.join('\n');
}

function analyseFile(path, text) {
  const code = stripComments(text);
  const declarations = readDeclarations(text);
  const starts = lineStarts(code);

  // One entry per HIT, so three `"$@"` loops are three parties that can disagree.
  const sites = [];
  for (const reader of READERS) {
    for (const hit of code.matchAll(reader.re)) {
      sites.push({ id: reader.id, pos: hit.index });
    }
  }

  // Which flags does each site deal with?
  const flagsBySite = sites.map((site, index) => {
    const flags = new Set();
    const statement = statementAt(code, starts, site.pos);
    for (const m of statement.matchAll(FLAG_TOKEN)) flags.add(m[0]);
    return { id: `${site.id}#${index + 1}`, flags };
  });

  // A flag dealt with by MORE THAN ONE site is the disagreement shape.
  const seen = new Map();
  for (const r of flagsBySite) {
    for (const flag of r.flags) {
      if (!seen.has(flag)) seen.set(flag, []);
      seen.get(flag).push(r.id);
    }
  }
  const contested = [...seen.entries()]
    .filter(([, sitesFor]) => sitesFor.length > 1)
    .map(([flag, sitesFor]) => ({ flag, readers: sitesFor }))
    .filter(({ flag }) => !declarations.list.has(flag));

  // Split the survivors by whether the file says it refuses on the ambiguity.
  // A shape with a refusal is a DELIBERATE state and belongs in the report as
  // acknowledged; a shape without one is the thing to act on.
  const acknowledged = contested.filter(({ flag }) => declarations.refused.has(flag));
  const actionable = contested.filter(({ flag }) => !declarations.refused.has(flag));

  // UNVALIDATED PASS-THROUGH. A weaker, separate signal, and the reason this
  // lint still has one: the contested-flag check fires on the SHAPE that
  // appears once a wrapper validates something, which means it does NOT fire
  // on the original bug. On origin/main, tools/godot-lock.sh has a single argv
  // loop, forwards every unrecognised argument to Godot, and validates nothing
  // — one reader, no disagreement, nothing to report. The live bug is a wrapper
  // that hands argv to a consumer it does not control while declaring no flags
  // of its own, so that is what this reports. Advisory and deliberately weaker:
  // most wrappers forward argv legitimately.
  const forwards = /\bARGS\+=\(|\bargs\.push\(|exec\s+"?\$[A-Z_]+"?\s+"?\$\{?ARGS/.test(code);
  const declaresNothing = !declarations.single.size && !declarations.list.size && !declarations.refused.size;

  return {
    path,
    readers: sites.map((s, i) => `${s.id}#${i + 1}`),
    readerCount: sites.length,
    declarations,
    contested,
    actionable,
    acknowledged,
    exempted: [...declarations.list].filter((flag) => seen.has(flag)),
    unvalidatedPassthrough: forwards && declaresNothing,
  };
}

function walk(input, seenDirs = new Set()) {
  // Accepts a path or a list of them. Called both ways: the roots are a list,
  // recursion passes a single joined path. Getting that wrong recursed into
  // garbage until the stack blew, which is a silly way to learn it.
  const paths = Array.isArray(input) ? input : [input];
  const files = [];
  for (const p of paths) {
    if (!exists(p)) continue;
    const real = p;
    if (statSync(real).isDirectory()) {
      if (seenDirs.has(real)) continue; // symlink loop guard
      seenDirs.add(real);
      for (const entry of readdirSync(real, { withFileTypes: true })) {
        if (entry.name === 'node_modules' || entry.name.startsWith('.')) continue;
        files.push(...walk(join(real, entry.name), seenDirs));
      }
    } else if (SCAN_EXT.has(extname(real))) {
      if (real.endsWith(SELF)) continue;
      files.push(real);
    }
  }
  return files;
}

function exists(p) {
  try { statSync(p); return true; } catch { return false; }
}

// ── SELF-TEST ──────────────────────────────────────────────────────────────
// The card's hard requirement: the lint must treat `--path X --path Y` and
// `--path=X --path=Y` as ONE flag given twice. A grep for a repeated literal
// finds the first form and misses the second, and a lint that reports partial
// coverage as coverage is worse than no lint. So the forms are proven here, and
// if a future edit breaks the equivalence the self-test fails loudly.
function selfTest() {
  const dir = mkdtempSync(join(tmpdir(), 'lint-flags-selftest.'));
  let failures = 0;
  const check = (name, ok, detail = '') => {
    if (!ok) failures += 1;
    console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name}${ok || !detail ? '' : ` — ${detail}`}`);
  };

  // The helper returns the CONTENTS, not the path. It returned the path at
  // first, which made three checks pass VACUOUSLY: analyseFile found no argv
  // readers in a path string, reported nothing contested, and the assertions
  // "not reported" / "no disagreement" all succeeded on an empty analysis. A
  // green that means "the lint looked at nothing" is the failure this whole
  // session has been about, and it is exactly what a self-test exists to catch.
  const write = (name, body) => {
    const p = join(dir, name);
    writeFileSync(p, body);
    return body;
  };

  // Both spellings of one flag, each in its own `"$@"` loop. Two loops of the
  // SAME kind are still two parties: that is the godot-lock.sh shape, and a lint
  // that counted by kind would call this one reader and miss it.
  const both = analyseFile('both.sh', write('both.sh', [
    'for a in "$@"; do case "$a" in --path) want=1 ;; esac; done',
    'for b in "$@"; do case "$b" in --path=*) want=2 ;; esac; done',
  ].join('\n')));
  check('the two spellings of one flag are treated as ONE flag', both.contested.some((c) => c.flag === '--path'),
    `contested=${both.contested.map((c) => c.flag).join(',') || 'none'}`);
  check('two loops of the SAME reader kind count as two parties', both.readerCount === 2,
    `readerCount=${both.readerCount}`);

  // A list flag declared as a list is exempt, and the exemption is visible.
  const listFlag = analyseFile('list.sh', write('list.sh', [
    '# lint:flags-list --include',
    'for a in "$@"; do case "$a" in --include) ARGS+=("$a") ;; esac; done',
    'for b in "$@"; do echo "$b" --include; done',
  ].join('\n')));
  check('a declared list flag is not reported', !listFlag.contested.some((c) => c.flag === '--include'));
  check('but the exemption is reported, not silent', listFlag.exempted.includes('--include'),
    `exempted=${listFlag.exempted.join(',') || 'none'}`);

  // One reader only: not the class, so not reported — and it really did find
  // its reader, so the pass is not vacuous.
  const single = analyseFile('single.sh', write('single.sh', 'for a in "$@"; do echo "$a" --path; done\n'));
  check('a script with ONE argv reader is not reported', single.contested.length === 0 && single.readerCount === 1,
    `readerCount=${single.readerCount}`);

  // ── A / B / C: the three cases that were INDISTINGUISHABLE ───────────────
  // Coordinator extracted 40f0372 and ran this: a script that reads no argv, a
  // genuinely clean script, and a path that does not exist ALL printed the same
  // confident headline and ALL exited 0. The third is the finding — a run that
  // read nothing was certifying "no unremediated shape found in the scripts I
  // understood", and it had understood nothing at all.
  //
  // The guard this replaces was `empty.readerCount === 0 && empty.contested.length
  // === 0`, and coordinator's diagnosis of why it could not fail is correct and
  // worth keeping verbatim: `contested.length === 0` is the CLEAN file's own
  // value, so the assertion was true of a clean analysis and was being applied
  // to the empty one. It verified a field was zero. It never verified that a
  // reader or a CI log could tell the two situations apart — a vacuous pass, one
  // layer up from the vacuous pass it was written to prevent.
  //
  // So these assert on RENDERED OUTPUT and on EXIT CODE, through the same
  // render()/exitCodeFor() the CLI uses, not through a reimplementation.
  const aFile = write('a.sh', 'echo hello\nls -l\n');
  const bFile = write('b.sh', 'for a in "$@"; do case "$a" in --clean-tmp) X=1 ;; esac; done\n');
  const A = analyseFile('a.sh', aFile);
  const B = analyseFile('b.sh', bFile);
  const outA = render([A], ['.']).join('\n');
  const outB = render([B], ['.']).join('\n');
  const outC = render([], ['no/such/path'], ['no/such/path']).join('\n');
  const codeA = exitCodeFor([A], [], false);
  const codeB = exitCodeFor([B], [], false);
  const codeC = exitCodeFor([], ['no/such/path'], false);

  check('A: a file with NO argv reader says so on its OWN line', /a\.sh[\s\S]*NOTHING TO CLASSIFY/.test(outA));
  check('A: a CLEAN file does NOT claim it had nothing to classify', !/NOTHING TO CLASSIFY/.test(outB));
  check('A and B render differently from each other', outA !== outB);
  check('A and B are distinguishable per-file, not only in a count',
    /per-file verdict/.test(outA) && /per-file verdict/.test(outB));

  check('C: scanning NOTHING is not reported as a clean result',
    /NOTHING WAS SCANNED/.test(outC) && !/no unremediated shape/i.test(outC),
    'the "no unremediated shape found" headline must not appear when no file was read');
  check('C: the missing root is NAMED, not just counted', /no\/such\/path/.test(outC));
  check('C: nothing scanned exits NONZERO, so a wrong path cannot pass as clean', codeC !== 0, `exit=${codeC}`);
  check('C differs from B in BOTH output and exit code', outC !== outB && codeC !== codeB, `codes: C=${codeC} B=${codeB}`);

  // A still exits 0: a script that legitimately reads no argv is not a failure.
  // What it must not do is be indistinguishable from B, and it is not.
  check('A still exits 0 (no-argv-reader is not itself a failure)', codeA === 0, `exit=${codeA}`);
  check('A and B share an exit code but NOT an output', codeA === codeB && outA !== outB);

  // A finding is visible as a FINDING on the file's own line, not only in a
  // section further down. This is also what makes the pass-through signal
  // observable, which was the other thing coordinator could not settle.
  const passFile = analyseFile('f.sh', write('f.sh', 'ARGS+=("$a")\nexec "$BIN" "${ARGS[@]}"\n'));
  const outF = render([passFile], ['.']).join('\n');
  check('an unvalidated pass-through is marked FINDING on its own per-file line',
    /f\.sh[\s\S]*FINDING — unvalidated pass-through/.test(outF));

  const contestedFile = analyseFile('c2.sh', write('c2.sh', [
    'for a in "$@"; do case "$a" in --path) n=1 ;; esac; done',
    'for b in "$@"; do case "$b" in --path=*) n=2 ;; esac; done',
  ].join('\n')));
  const outC2 = render([contestedFile], ['.']).join('\n');
  check('a contested flag is marked FINDING on its own per-file line',
    /c2\.sh[\s\S]*FINDING — --path read by more than one party/.test(outC2));
  check('and --strict exits 1 on a contested flag', exitCodeFor([contestedFile], [], true) === 1);
  check('and --strict exits 1 on a pass-through finding too', exitCodeFor([passFile], [], true) === 1);

  // The old field-level assertion, kept as a check so it cannot come back in a
  // form that cannot fail. It is still true; it is simply no longer load-bearing.
  const empty = analyseFile('empty.sh', write('empty.sh', 'echo hello\n'));
  check('the old field-level assertion is still true, and is no longer load-bearing',
    empty.readerCount === 0 && empty.contested.length === 0);

  // ── THE CLI ITSELF, end to end ───────────────────────────────────────────
  // Everything above calls analyseFile() directly. That left walk() and main()
  // untested, which is how an inverted ternary shipped in main that made the
  // tool scan NOTHING whenever every root was present — including for a plain
  // file argument — and report it as a clean-looking failure. 24 green checks
  // did not notice, because none of them went through the entry point a person
  // actually uses. So these spawn the real CLI and check its real exit codes.
  const cli = (args, cwd) => spawnSync(process.execPath, [process.argv[1], ...args], { cwd, encoding: 'utf8' });
  const e2e = mkdtempSync(join(tmpdir(), 'lint-e2e-'));
  mkdirSync(join(e2e, 'tools'), { recursive: true });
  writeFileSync(join(e2e, 'tools', 'a.sh'), 'echo hello\nls -l\n');
  writeFileSync(join(e2e, 'tools', 'b.sh'), 'for a in "$@"; do case "$a" in --clean-tmp) X=1 ;; esac; done\n');

  const runA = cli(['tools/a.sh'], e2e);
  check('CLI: a file argument IS scanned (the walk path, not just analyseFile)', runA.status === 0 && /per-file verdict/.test(runA.stdout),
    `status=${runA.status}`);
  check('CLI: that file with no argv reader is reported as NOTHING TO CLASSIFY',
    /NOTHING TO CLASSIFY/.test(runA.stdout));

  const runB = cli(['tools/b.sh'], e2e);
  check('CLI: a clean file exits 0 and is reported as ok', runB.status === 0 && /ok — one argv reader/.test(runB.stdout),
    `status=${runB.status}`);
  check('CLI: A and B differ on stdout as well as in the unit checks',
    runA.stdout !== runB.stdout);

  const runC = cli(['tools/nope'], e2e);
  check('CLI: a path that does not exist exits 2, not 0', runC.status === 2, `status=${runC.status}`);
  check('CLI: and says NOTHING WAS SCANNED rather than reporting a verdict',
    /NOTHING WAS SCANNED/.test(runC.stdout) && !/no contested flag is reported/.test(runC.stdout));

  const runDir = cli(['tools'], e2e);
  check('CLI: a directory argument is walked', runDir.status === 0 && /scanned 2 file\(s\)/.test(runDir.stdout), `status=${runDir.status}`);
  rmSync(e2e, { recursive: true, force: true });

  // Several readers, disjoint flags: not a disagreement.
  const disjoint = analyseFile('disjoint.sh', write('disjoint.sh', [
    'for a in "$@"; do echo "$a" --alpha; done',
    'for b in "$@"; do echo "$b" --beta; done',
  ].join('\n')));
  check('two readers mentioning DIFFERENT flags is not a disagreement', disjoint.contested.length === 0 && disjoint.readerCount === 2,
    `readerCount=${disjoint.readerCount} contested=${disjoint.contested.map((c) => c.flag).join(',')}`);

  // A flag handled by two readers, where the file DECLARES it refuses on the
  // ambiguity: reported, but as acknowledged rather than actionable.
  const refused = analyseFile('refused.sh', write('refused.sh', [
    '# lint:flags-refused --path',
    'for a in "$@"; do case "$a" in --path) n=1 ;; esac; done',
    'for b in "$@"; do case "$b" in --path=*) n=2 ;; esac; done',
  ].join('\n')));
  check('a declared refusal is reported as acknowledged, not actionable',
    refused.acknowledged.some((c) => c.flag === '--path') && refused.actionable.length === 0,
    `acknowledged=${refused.acknowledged.map((c) => c.flag).join(',')} actionable=${refused.actionable.map((c) => c.flag).join(',')}`);
  check('and the acknowledgement is still VISIBLE, not silent', refused.acknowledged.length > 0);

  // A flag mentioned only in prose must not count: comments are stripped.
  const prose = analyseFile('prose.sh', write('prose.sh', [
    'for a in "$@"; do echo "$a" --alpha; done',
    'for b in "$@"; do echo "$b" --beta; done',
    '# and --gamma is only ever mentioned in this comment',
  ].join('\n')));
  check('a flag mentioned only in a comment is not counted', !prose.contested.some((c) => c.flag === '--gamma'));

  rmSync(dir, { recursive: true, force: true });
  console.log(failures ? `\n  self-test: ${failures} FAILED` : '\n  self-test: all checks passed');
  return failures === 0;
}


// ── PER-FILE VERDICT ───────────────────────────────────────────────────────

// One line per file, stating what happened to THAT file.
//
// This exists because the previous report folded the states into aggregate
// counts. Three real cases — a script with no argv reader, a genuinely clean
// script, and a path that does not exist — all printed the same confident
// headline and all exited 0, so "no unremediated shape found in the scripts I
// understood" was printed by a run that had understood nothing. A per-file line
// makes each state visible on its own, which is the only level at which the
// difference is observable to a reader.
function verdictFor(a) {
  if (a.readerCount === 0) {
    return 'NOTHING TO CLASSIFY — no argv reader detected in this file';
  }
  if (a.actionable.length) {
    return `FINDING — ${a.actionable.map((c) => c.flag).join(', ')} read by more than one party`;
  }
  if (a.unvalidatedPassthrough) {
    return 'FINDING — unvalidated pass-through: forwards argv to a consumer it does not control, declaring no flags of its own';
  }
  if (a.readerCount === 1) {
    return 'ok — one argv reader, so no disagreement between parties is possible';
  }
  return `ok — ${a.readerCount} argv readers, no flag contested`;
}

// Exit code, as a function of the run, so the self-test asserts on the SAME
// logic the CLI uses rather than on a reimplementation of it.
//
//   0 — ran, and found nothing actionable
//   1 — actionable findings, and --strict was asked for
//   2 — NOTHING WAS SCANNED. Not a clean result: a run that read no file has
//       certified nothing, and returning 0 for it is the single most dangerous
//       thing this tool could do. A typo in a path, a moved directory or a wrong
//       working directory all land here.
function exitCodeFor(analysed, missingRoots, strict) {
  if (analysed.length === 0) return 2;
  if (!strict) return 0;
  const findings = analysed.flatMap((a) => a.actionable).length
    + analysed.filter((a) => a.unvalidatedPassthrough).length;
  return findings ? 1 : 0;
}

// Render the whole report as an array of lines.
//
// Returns lines rather than printing them so the SELF-TEST asserts on the exact
// text a reader sees. This is not tidiness: the bug this file keeps hitting is a
// check that is true of a field and invisible in the report, and the only way to
// catch that class is to assert on the report.
function render(analysed, roots, missingRoots = []) {
  const L = [];
  L.push('=== repeated single-valued flag lint (advisory) ===');

  // Case C, first and loudest. Before anything else, because a reader who sees a
  // confident verdict below must not have to notice that nothing was scanned.
  if (analysed.length === 0) {
    L.push('');
    L.push('NOTHING WAS SCANNED — this is NOT a clean result, and no verdict below means anything.');
    L.push(`  root(s) given: ${roots.join(', ') || '(none)'}`);
    if (missingRoots.length) {
      L.push('  root(s) that do not exist:');
      for (const m of missingRoots) L.push(`    ${m}`);
    }
    L.push('  A wrong path, a moved directory or a wrong working directory all land here, and');
    L.push('  a lint that read nothing must not be able to say it found nothing to fix.');
    return L;
  }

  const multiReader = analysed.filter((a) => a.readerCount > 1);
  const noReader = analysed.filter((a) => a.readerCount === 0);
  const actionable = multiReader.flatMap((a) => a.actionable.map((c) => ({ file: a.path, ...c })));
  const acknowledged = multiReader.flatMap((a) => a.acknowledged.map((c) => ({ file: a.path, ...c })));
  const declared = analysed.filter((a) => a.declarations.single.size || a.declarations.list.size || a.declarations.refused.size);
  const exemptions = analysed.flatMap((a) => a.exempted.map((f) => ({ file: a.path, flag: f })));
  const passthrough = analysed.filter((a) => a.unvalidatedPassthrough);

  L.push(`scanned ${analysed.length} file(s) under ${roots.join(', ')}`);
  if (missingRoots.length) {
    L.push(`  WARNING: ${missingRoots.length} root(s) did not exist and contributed NOTHING: ${missingRoots.join(', ')}`);
  }

  L.push('');
  L.push('per-file verdict — one line per file, so no state is folded into a count:');
  for (const a of analysed) L.push(`  ${a.path}\n      ${verdictFor(a)}`);

  const byState = (v) => analysed.filter((a) => verdictFor(a).startsWith(v)).length;
  L.push('');
  L.push(`  ${byState('ok')} ok, ${byState('FINDING')} FINDING, ${byState('NOTHING')} nothing-to-classify, of ${analysed.length} file(s)`);
  L.push(`  ${multiReader.length} read argv in more than one place (the precondition for the class)`);
  L.push(`  ${declared.length} declare lint:flags-single / lint:flags-list / lint:flags-refused`);

  if (actionable.length) {
    L.push('');
    L.push(`${actionable.length} contested flag(s) with no declared refusal on the ambiguity:`);
    for (const f of actionable) L.push(`  ${f.file}\n    ${f.flag}  read by: ${f.readers.join(' + ')}`);
    L.push('\nWhat to do about one: do NOT let a lint pick a winner. Either refuse on the');
    L.push('ambiguity (what tools/godot-lock.sh does for --path, declared lint:flags-refused),');
    L.push('or make every reader agree on which occurrence wins AND record that the choice is');
    L.push('a contract, not an accident of the current consumer. Refusing is safer when the');
    L.push('consumer is undocumented.');
  } else {
    L.push('');
    L.push('no contested flag is reported as a finding. Read that as "no unremediated shape found');
    L.push('in the scripts I understood", not as "no repeated flags exist" — this lint cannot see');
    L.push('an actual command line, only the structure that makes repetition dangerous. The');
    L.push('per-file lines above say which files were understood and which were not.');
  }

  if (passthrough.length) {
    L.push('');
    L.push(`FINDINGS — unvalidated pass-through: ${passthrough.length} script(s) hand argv to a consumer`);
    L.push('they do not control while declaring no flags of their own, so any single-valued flag they');
    L.push('forward unchecked is unguarded BY CONSTRUCTION rather than by disagreement. Each is also');
    L.push('marked FINDING on its own per-file line above:');
    for (const p of passthrough) L.push(`  ${p.path}  readers: ${p.readers.join(' + ')}`);
  }

  if (acknowledged.length) {
    L.push('\nacknowledged (shape present, refusal declared — visible, not silent):');
    for (const a of acknowledged) L.push(`  ${a.file}  ${a.flag}  read by: ${a.readers.join(' + ')}`);
  }

  if (exemptions.length) {
    L.push('\nexemptions in force (visible on purpose):');
    for (const e of exemptions) L.push(`  ${e.file}  ${e.flag}  (declared lint:flags-list)`);
  }

  if (noReader.length) {
    L.push('');
    L.push(`${noReader.length} file(s) had NO argv reader — nothing to classify there. Most scripts are`);
    L.push('in this group legitimately. If one of these DOES read flags, by a form this lint does not');
    L.push('detect, it is silently clean, and that is a detection gap in me, not a pass. Each is marked');
    L.push('NOTHING TO CLASSIFY on its own per-file line above.');
  }

  // Coverage gap for scripts that read argv in several places but classify
  // nothing. A pass-through file is not repeated here: it is already a finding,
  // and printing the same line twice made one observation read as two.
  const undeclared = analysed.filter((a) => a.readerCount > 1
    && !a.declarations.single.size && !a.declarations.list.size && !a.declarations.refused.size
    && !a.unvalidatedPassthrough);
  if (undeclared.length) {
    L.push('');
    L.push(`coverage gap, stated rather than implied: ${undeclared.length} multi-reader script(s) declare nothing,`);
    L.push('so their flags cannot be classified as single-valued, list-valued or refused:');
    for (const a of undeclared) L.push(`  ${a.path}  readers: ${a.readers.join(' + ')}`);
  }

  return L;
}

// ── MAIN ───────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
if (argv.includes('--self-test')) {
  process.exit(selfTest() ? 0 : 1);
}

const strict = argv.includes('--strict');
const explicit = argv.filter((a) => !a.startsWith('--'));
const roots = explicit.length ? explicit : SCAN_DIRS;
const missingRoots = roots.filter((r) => !existsSync(r));
// Walk the roots that exist. This was `missingRoots.length ? walk(...) : []` —
// inverted, and it meant the lint scanned NOTHING whenever every root was
// present, including for a plain file argument, and reported it as
// "NOTHING WAS SCANNED" with exit 2. The most ordinary invocation of the tool
// was the one that failed, and the self-test did not catch it because the
// self-test calls analyseFile() directly and never goes near walk() or main.
const files = walk(roots.filter((r) => existsSync(r))).sort();

const analysed = files.map((f) => analyseFile(f, readFileSync(f, 'utf8')));
for (const line of render(analysed, roots, missingRoots)) console.log(line);
process.exit(exitCodeFor(analysed, missingRoots, strict));
