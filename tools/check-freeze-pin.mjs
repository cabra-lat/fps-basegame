// res://tools/check-freeze-pin.mjs
//
// ADVISORY. Reports, never refuses, never rewrites.
//
// WHY THIS EXISTS. A freeze that names a commit can be naming a DRIFTED state.
// One did: it named 76266eb while the tree was pinned to af09788 — divergent
// branches, 13 commits one way and 3 the other. A lane honouring that freeze
// faithfully was being pushed OFF the pin, which is the opposite of what a
// freeze is for. The failure is not that someone forgot a comparison; it is that
// the comparison was left to memory, and memory is not a mechanism.
//
// THE PRINCIPLE, and the reason this tool reports rather than blocks: the
// ambiguity here has a principled resolution. The gitlink in the tree is the
// authority — `git ls-tree HEAD <submodule>` — always. If a written freeze name
// disagrees with the gitlink, the NAME is wrong, not the gitlink. So there is
// nothing to refuse: a human reads the report and fixes the name.
//
// Deliberately NOT in scope, and the reason is the incident this exists to
// prevent: this never runs `git submodule update`, never mutates any tree, never
// picks a winner between two commits, and never edits a freeze. A check that
// edits a freeze is a check that can silently re-point a lane's work.
//
// EVERY git invocation goes through runGit(), which rejects any subcommand that
// is not in READ_ONLY. The self-test asserts that the recorded command list of a
// real run contains no mutating verb, so "this tool is read-only" is a property
// the tool checks about itself rather than a promise in a comment.
//
// Usage:
//   node tools/check-freeze-pin.mjs                      # is this tree on its pin?
//   node tools/check-freeze-pin.mjs --name 76266eb       # ...and what would that cost?
//   node tools/check-freeze-pin.mjs --all-lanes          # every worktree, by lane
//   node tools/check-freeze-pin.mjs --tree /path/to/wt   # a specific worktree
//   node tools/check-freeze-pin.mjs --strict             # exit 1 on a mismatch
//   node tools/check-freeze-pin.mjs --path addons/cabra.lat_shooters --help
//   node tools/check-freeze-pin.mjs --help
//
// Exit codes:
//   0  ran; nothing to report (or advisory default, findings present)
//   1  --strict and something needs a human
//   2  the check could not run — a missing tree, a path that is not a gitlink,
//      or a name that does not exist. Never 0: a check that could not look must
//      not be able to report that it found nothing.

import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join, resolve } from 'node:path';

// Subcommands that only READ. Anything that writes is rejected in runGit(), not
// merely avoided by convention: the point of this card is that a check left to
// convention is a check that eventually gets run in the wrong tree.
const READ_ONLY = new Set([
  'ls-tree', 'rev-parse', 'merge-base', 'rev-list', 'log', 'show',
  'status', 'branch', 'worktree', 'cat-file', 'for-each-ref', 'symbolic-ref',
]);

// Everything this process ran, so the read-only claim is checkable afterwards.
const commandLog = [];

function runGit(tree, args) {
  const sub = args[0];
  if (!READ_ONLY.has(sub)) {
    throw new Error(`refusing to run a non-read-only git subcommand: git ${args.join(' ')}`);
  }
  const argv = ['-C', tree, ...args];
  commandLog.push(argv.join(' '));
  const r = spawnSync('git', argv, { encoding: 'utf8' });
  if (r.status !== 0) return { ok: false, out: (r.stdout || '') + (r.stderr || '') };
  return { ok: true, out: r.stdout };
}

// ── the declared pin: the authority ────────────────────────────────────────

// Reads the gitlink. Returns {sha} or {error}. A path that is not a gitlink is
// an ERROR, not a zero: reporting "no pin declared" for a regular file would be
// a different claim, and a wrong one.
function declaredPin(tree, subpath) {
  const r = runGit(tree, ['ls-tree', 'HEAD', subpath]);
  if (!r.ok) return { error: `cannot read ls-tree HEAD ${subpath}: ${r.out.trim()}` };
  const line = r.out.trim();
  if (!line) return { error: `${subpath} is not in the tree at HEAD — nothing is pinned` };
  const parts = line.split(/\s+/);
  const [mode, type, sha, ...rest] = parts;
  if (mode !== '160000' || type !== 'commit') {
    return { error: `${subpath} is not a gitlink (mode=${mode} type=${type}); this check only understands submodules` };
  }
  return { sha, path: rest.join(' ') };
}

// What is actually checked out, and the three states are kept DISTINCT because
// collapsing them is how a broken tree gets reported as a clean one:
//   on-pin / off-pin / NOT-INITIALISED. An uninitialised submodule is not an
//   off-pin one; it is a tree where the question cannot be asked.
function checkedOut(tree, subpath) {
  const dir = join(tree, subpath);
  if (!existsSync(dir)) return { state: 'not-initialised', detail: 'directory absent' };
  // `git -C <dir> rev-parse HEAD` is NOT enough to ask this question. When the
  // submodule directory is not a repository of its own, git walks UP to the
  // superproject and cheerfully returns the SUPERPROJECT's HEAD. That produced a
  // report claiming addons/cabra.lat_shooters was checked out at the game repo's
  // own commit — a confident, wrong, plausible-looking SHA, which is the worst
  // kind. So the directory's own toplevel is checked first, and a mismatch is
  // reported as what it is: not initialised.
  const top = runGit(dir, ['rev-parse', '--show-toplevel']);
  if (!top.ok) return { state: 'not-initialised', detail: 'present but not a git repository' };
  if (resolve(top.out.trim()) !== resolve(dir)) {
    return {
      state: 'not-initialised',
      detail: `this directory is not its own repository; git resolved it to ${top.out.trim()}, i.e. the SUPERPROJECT. Asking rev-parse HEAD here would return the parent repo's commit.`,
    };
  }
  const r = runGit(dir, ['rev-parse', 'HEAD']);
  if (!r.ok) return { state: 'not-initialised', detail: 'present, is its own repository, but has no HEAD' };
  return { state: 'checked-out', sha: r.out.trim() };
}

// ── relation between a freeze name and the pin ─────────────────────────────

// "off by how much" and "off since when" are different questions, so both are
// answered. Ancestor/descendant/neither is the first; the merge base is the
// second, and it is the one that tells a lane whether this is new or has been
// true for a while.
function relation(addonDir, pin, name) {
  const isAncestor = (a, b) => spawnSync('git', ['-C', addonDir, 'merge-base', '--is-ancestor', a, b]).status === 0;
  if (isAncestor(name, pin)) return { kind: 'ancestor', plain: 'the freeze name is an ANCESTOR of the pin (the name is behind)' };
  if (isAncestor(pin, name)) return { kind: 'descendant', plain: 'the freeze name is a DESCENDANT of the pin (the name is ahead, and carries commits the pin does not)' };
  const mb = runGit(addonDir, ['merge-base', pin, name]);
  const counts = runGit(addonDir, ['rev-list', '--left-right', '--count', `${pin}...${name}`]);
  const [behind = '?', ahead = '?'] = (counts.ok ? counts.out.trim() : '').split(/\s+/);
  return {
    kind: 'divergent',
    plain: 'the freeze name is NEITHER an ancestor nor a descendant of the pin — divergent branches',
    mergeBase: mb.ok ? mb.out.trim() : null,
    behind,
    ahead,
  };
}

// Commits on the PIN that are absent from the name: what a lane LOSES by
// honouring the name instead of the pin. The reverse set is reported too, but
// labelled as a gain, because unvetted commits are a different risk from lost
// fixes and should not be listed under the same heading.
function commitSets(addonDir, pin, name) {
  const fmt = '--format=%H%x09%s%x09%an';
  const lost = runGit(addonDir, ['log', `${name}..${pin}`, fmt]);
  const gained = runGit(addonDir, ['log', `${pin}..${name}`, fmt]);
  const parse = (r) => (r.ok ? r.out.trim() : '').split('\n').filter(Boolean).map((l) => {
    const [sha, subject, author] = l.split('\t');
    return { sha, subject, author };
  });
  return { lost: parse(lost), gained: parse(gained) };
}

// ── per-commit severity, and the coverage case ─────────────────────────────

// SUBJECT-BASED, and therefore a heuristic. It is stated as a heuristic because
// the alternative — parsing diffs to decide what a commit is "for" — is a
// judgement no script should make silently. A misclassification here makes a
// report noisier, not unsafe: the commits and their subjects are printed either
// way, so a human can overrule it.
//
// The two classes that matter most are the ones that FAIL SILENTLY. A commit
// that breaks a build stops the lane. A commit that adds a fix or promotes
// invariants makes the tree quieter, and the lane finds out at the worst time.
const SEVERITY = [
  { re: /\b(fix|bugfix|hotfix)\b|^fix[(:]/i, cls: 'FIX', silent: true, note: 'a fix that would be silently reverted: nothing fails, the bug is simply back' },
  { re: /\b(invariant|coverage|promote)\b|\bINV-\d+/i, cls: 'INVARIANT/COVERAGE', silent: true, note: 'coverage that would be silently lost: the gate keeps passing, with fewer checks' },
  { re: /\b(test|harness|gate|validator|validate)\b/i, cls: 'TEST/GATE', silent: true, note: 'test surface that would be silently dropped' },
  { re: /\b(refactor|cleanup|clean up|rename|reformat|prettier|lint|style)\b/i, cls: 'COSMETIC', silent: false, note: 'cosmetic; a lane is unlikely to notice either way' },
  { re: /\b(doc|docs|readme|comment)\b/i, cls: 'DOCS', silent: false, note: 'documentation only' },
];

function classifySeverity(subject) {
  for (const s of SEVERITY) if (s.re.test(subject)) return { cls: s.cls, silent: s.silent, note: s.note };
  return { cls: 'UNCLASSIFIED', silent: true, note: 'no rule matched — read it yourself, and do not assume it is harmless' };
}

// A path that carries assertions. Losing lines here does not fail a build; it
// makes a gate pass over less. That is why it is worth measuring rather than
// asserting, and why it is never printed as a footnote.
const COVERAGE_PATH = /(^|\/)(test|tests)\/|(^|\/)(validate|check|invariant)[^/]*\.(gd|mjs|js|sh|py)$/i;

function isCoveragePath(p) {
  return COVERAGE_PATH.test(p);
}

function lineCountAt(addonDir, rev, file) {
  const r = spawnSync("git", ["-C", addonDir, "show", `${rev}:${file}`], { encoding: "utf8" });
  if (r.status !== 0) return null;
  return r.stdout.split('\n').length - 1;
}

// Files changed by the commits a lane would LOSE, restricted to assertion
// surfaces, with the line delta measured at the pin against the name.
function coverageImpact(addonDir, pin, name, lostShas) {
  const files = new Set();
  for (const sha of lostShas) {
    const r = spawnSync('git', ['-C', addonDir, 'show', '--name-only', '--format=', sha], { encoding: 'utf8' });
    if (r.status !== 0) continue;
    for (const line of (r.stdout || '').split('\n')) {
      const f = line.trim();
      if (f && isCoveragePath(f)) files.add(f);
    }
  }
  const out = [];
  for (const f of [...files].sort()) {
    const atPin = lineCountAt(addonDir, pin, f);
    const atName = lineCountAt(addonDir, name, f);
    if (atPin === null || atName === null) {
      out.push({ file: f, atPin, atName, delta: null, note: 'present at one end only' });
      continue;
    }
    out.push({ file: f, atPin, atName, delta: atPin - atName, note: null });
  }
  return out;
}

// ── rendering ──────────────────────────────────────────────────────────────

// Every tree gets a verdict, including the boring ones. A report that only
// speaks about the tree that is wrong is a report that cannot be trusted to be
// silent when everything is fine.
function renderTreeReport(t) {
  const L = [];
  L.push(`  tree:    ${t.tree}`);
  L.push(`  lane:    ${t.lane}${t.head ? `  (HEAD ${t.head})` : ''}`);
  L.push(`  pin:     ${t.pin ? t.pin.sha : `UNAVAILABLE — ${t.pin && t.pin.error}`}`);
  L.push(`  ${t.subpath}: ${t.checkedOut.state === 'checked-out' ? t.checkedOut.sha : t.checkedOut.state.toUpperCase()}`);
  if (t.checkedOut.state === 'not-initialised') {
    L.push('           the question "is this tree on its pin?" CANNOT BE ASKED here, which is not the');
    L.push('           same answer as "yes". This tool does not run `git submodule update`; that is a');
    L.push('           mutation and it belongs to whoever owns the tree.');
  } else if (t.pin && t.pin.sha && t.checkedOut.sha !== t.pin.sha) {
    L.push('           OFF-PIN. Read `git submodule status` in THIS tree before trusting it as a');
    L.push('           reference for anything.');
  } else {
    L.push('           on-pin.');
  }
  return L;
}

function renderFreezeReport(t, rel, sets, coverage) {
  const L = [];
  L.push('');
  L.push(`  FREEZE NAME: ${t.freezeName}`);
  L.push(`  DECLARED PIN: ${t.pin ? t.pin.sha : '(unavailable)'}`);
  L.push(`  relation:     ${rel.plain}`);
  if (rel.mergeBase) L.push(`  merge base:   ${rel.mergeBase}   <- "off since when"; the branches diverged here`);
  if (rel.behind !== undefined) L.push(`  divergence:   ${rel.behind} commit(s) on the pin only, ${rel.ahead} on the name only`);

  if (t.pin && t.freezeNameSha && t.pin.sha === t.freezeNameSha) {
    L.push('');
    L.push('  the freeze name IS the declared pin. Nothing to lose.');
    return L;
  }

  L.push('');
  if (!sets.lost.length) {
    L.push('  COMMITS LOST BY HONOURING THE NAME: none.');
  } else {
    L.push(`  COMMITS LOST BY HONOURING THE NAME: ${sets.lost.length}. The gitlink is the authority, so`);
    L.push('  a lane on the name is on a tree the superproject does not declare.');
    for (const c of sets.lost) {
      const s = classifySeverity(c.subject);
      const flag = s.silent ? 'FAILS SILENTLY' : 'visible';
      L.push('');
      L.push(`    ${c.sha.slice(0, 7)}  [${s.cls}] — ${flag}`);
      L.push(`      ${c.subject}`);
      L.push(`      (${c.author})`);
      L.push(`      ${s.note}`);
    }
  }

  if (sets.gained.length) {
    L.push('');
    const gainFixes = sets.gained.filter((c) => classifySeverity(c.subject).cls === 'FIX');
    L.push(`  COMMITS THE NAME ADDS (not on the pin): ${sets.gained.length}. These are unvetted against`);
    L.push('  the pin and are NOT counted as losses above, but they are not free either: a commit the');
    L.push('  pin does not have is work nobody has reviewed against the pin.');
    if (gainFixes.length) {
      L.push('');
      L.push(`  ${gainFixes.length} of them carry a FIX subject, which is the class that fails silently`);
      L.push('  if it turns out to be wrong. Read their subjects before treating the name as a base:');
      for (const c of gainFixes) L.push(`    ${c.sha.slice(0, 7)}  ${c.subject}`);
    }
    L.push('');
    for (const c of sets.gained) L.push(`    ${c.sha.slice(0, 7)}  ${c.subject}`);
  }

  // The coverage case, and it is NOT a footnote. A lane on the name does not get
  // a failure here; it gets a gate that still passes, over fewer assertions, with
  // no error to explain the difference. That is a silent loss dressed as a pass,
  // and printing it as "informational" would reproduce the defect in the report.
  if (coverage.length) {
    L.push('');
    L.push('  COVERAGE IMPACT — READ THIS BEFORE DECIDING. This is not informational:');
    L.push('  a gate that loses assertions keeps PASSING, and the only visible symptom is a');
    L.push('  lower check count that nobody can account for.');
    for (const c of coverage) {
      if (c.delta === null) {
        L.push(`    ${c.file}  ${c.note} (pin=${c.atPin ?? 'absent'}, name=${c.atName ?? 'absent'})`);
      } else if (c.delta > 0) {
        L.push(`    ${c.file}  ${c.atName} lines at the freeze name -> ${c.atPin} at the pin`);
        L.push(`      THE LANE LOSES ${c.delta} LINE(S) OF ASSERTIONS. A gate over the name passes over less.`);
      } else if (c.delta < 0) {
        L.push(`    ${c.file}  the name has ${-c.delta} line(s) MORE than the pin (not a loss)`);
      } else {
        L.push(`    ${c.file}  same length at both ends (${c.atPin} lines)`);
      }
    }
  } else if (sets.lost.length) {
    L.push('');
    L.push('  COVERAGE IMPACT: no assertion surface among the lost commits. Measured, not assumed:');
    L.push('  the lost commits touch no file under test/ and no validate/check/invariant script.');
  }
  return L;
}

// ── main ───────────────────────────────────────────────────────────────────

const argv = process.argv.slice(2);
const flag = (n) => argv.includes(n);
const opt = (n, d = null) => {
  const i = argv.indexOf(n);
  return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : d;
};

const USAGE = `check-freeze-pin — ADVISORY. Reports whether a tree's submodule is on
the pin its SUPERPROJECT GITLINK records. Never mutates, never picks a winner,
never runs \`git submodule update\`, never edits a freeze name.

USAGE
  node tools/check-freeze-pin.mjs [options]

OPTIONS
  --tree <path>    worktree to inspect           (default: cwd)
  --path <path>    submodule path to compare    (default: addons/cabra.lat_shooters)
  --name <sha>     a written freeze name, to price against the gitlink
  --all-lanes      report every worktree found, grouped by lane
  --strict         exit 1 when something needs a human (advisory otherwise)
  --self-test      run this tool's own self-test (48 checks)
  --help, -h       print this and exit WITHOUT checking anything

EXIT CODES
  0  ran; nothing to report (or findings, under the advisory default)
  1  --strict and something needs a human
  2  the check COULD NOT RUN — a missing tree, a non-gitlink path, or a name
     that does not exist. Never 0: a check that could not look is not a check
     that found nothing. --help is NOT this case and never produces it.

This tool is advisory. It is not wired into verify-all and is not in CI.`;

if (flag('--help') || flag('-h')) {
  // A help request is a request for help, not a request to check. It must
  // short-circuit BEFORE any git runs, so it can never print a pin verdict and
  // can never exit 2 — conflating "tell me the flags" with "I could not look"
  // would be a smaller version of the exact defect this tool exists to catch.
  console.log(USAGE);
  process.exit(0);
}

if (flag('--self-test')) {
  const { selfTest } = await import('./check-freeze-pin.self-test.mjs');
  process.exit(selfTest({ classifySeverity, relation, commitSets, renderTreeReport, renderFreezeReport, commandLog, READ_ONLY, declaredPin, checkedOut, exitCodeFor }) ? 0 : 1);
}


const subpath = opt('--path', 'addons/cabra.lat_shooters');
const treeArg = opt('--tree', process.cwd());
const freezeName = opt('--name', null);
const strict = flag('--strict');

function describeTree(tree) {
  // Is this even a git tree? If not, the check CANNOT RUN, which is a different
  // state from "ran and found nothing" and must never share its exit code. A
  // lint pointed at a directory that is not there once reported itself clean;
  // the same mistake here would mean a typo'd --tree silently reporting that
  // every lane is on its pin.
  const probe = runGit(tree, ['rev-parse', '--git-dir']);
  if (!probe.ok) return { tree, unusable: true, reason: 'not a git repository' };
  const lane = runGit(tree, ['rev-parse', '--abbrev-ref', 'HEAD']);
  const head = runGit(tree, ['rev-parse', '--short', 'HEAD']);
  return {
    tree,
    unusable: false,
    lane: lane.ok ? lane.out.trim() : '(unknown)',
    head: head.ok ? head.out.trim() : null,
    subpath,
    pin: declaredPin(tree, subpath),
    checkedOut: checkedOut(tree, subpath),
  };
}

const lines = [];
lines.push('=== freeze / pin check (ADVISORY: reports, never refuses, never rewrites) ===');

const trees = [];
if (flag('--all-lanes')) {
  // Worktree list is how a lane's tree gets found and NAMED, so that "the
  // verifier worktree" can never be read as a current reference by someone who
  // has not measured it.
  const r = runGit(treeArg, ['worktree', 'list', '--porcelain']);
  const entries = r.out.split('\n\n').filter(Boolean);
  for (const e of entries) {
    const wt = (e.match(/^worktree (.+)$/m) || [])[1];
    if (wt && existsSync(wt)) trees.push(describeTree(resolve(wt)));
  }
} else {
  trees.push(describeTree(resolve(treeArg)));
}

let needsHuman = 0;
let couldNotRun = 0;
for (const t of trees) {
  lines.push('');
  if (t.unusable) {
    couldNotRun += 1;
    lines.push(`  tree:    ${t.tree}`);
    lines.push(`  COULD NOT RUN: ${t.reason}. This is NOT a clean result and NOT a lane on its pin.`);
    lines.push('  A wrong --tree path, a directory that is not a checkout, or a typo all land here.');
    if (freezeName) lines.push('  The freeze comparison was NOT performed for this tree.');
    continue;
  }
  lines.push(...renderTreeReport(t));
  if (t.pin.error) needsHuman += 1;
  if (t.checkedOut.state !== 'checked-out') needsHuman += 1;
  else if (t.pin && t.pin.sha && t.checkedOut.sha !== t.pin.sha) needsHuman += 1;

  if (!freezeName) continue;
  const addonDir = join(t.tree, subpath);
  if (!existsSync(addonDir)) {
    lines.push('');
    lines.push(`  cannot compare a freeze name: ${subpath} is not checked out in this tree.`);
    continue;
  }
  const nm = runGit(addonDir, ['rev-parse', freezeName]);
  if (!nm.ok) {
    lines.push('');
    lines.push(`  freeze name '${freezeName}' does not exist in ${subpath} here. That is a finding in`);
    lines.push('  itself: a freeze nobody can resolve is a freeze that cannot be honoured.');
    needsHuman += 1;
    continue;
  }
  t.freezeName = freezeName;
  t.freezeNameSha = nm.out.trim();
  const rel = relation(addonDir, t.pin.sha, t.freezeNameSha);
  const sets = commitSets(addonDir, t.pin.sha, t.freezeNameSha);
  const coverage = coverageImpact(addonDir, t.pin.sha, t.freezeNameSha, sets.lost.map((c) => c.sha));
  lines.push(...renderFreezeReport(t, rel, sets, coverage));
  if (rel.kind !== 'ancestor' && t.pin.sha !== t.freezeNameSha) needsHuman += 1;
  if (coverage.some((c) => c.delta > 0)) needsHuman += 1;
}

lines.push('');
if (couldNotRun > 0) {
  lines.push(`${couldNotRun} tree(s) COULD NOT BE CHECKED. No verdict below applies to them, and this`);
  lines.push('exit code says so: a check that could not look is not a check that found nothing.');
} else if (needsHuman === 0) {
  lines.push('nothing needs a human.');
} else {
  lines.push(`${needsHuman} thing(s) need a human. This tool does not refuse, does not pick a winner,`);
  lines.push('does not run `git submodule update`, and does not edit a freeze: the gitlink is the');
  lines.push('authority, and choosing between two commits is not a decision a script should make.');
}
for (const l of lines) console.log(l);

// The read-only claim, checked rather than asserted.
const mutating = commandLog.filter((c) => !READ_ONLY.has(c.split(' ')[2]));
if (mutating.length) {
  console.error(`INTERNAL: recorded a non-read-only git command: ${mutating.join(' | ')}`);
  process.exit(3);
}

// Exit code, as a function, so the self-test asserts on the same logic rather
// than on a reimplementation of it — the gap that let the lint ship an inverted
// ternary past 24 green checks.
function exitCodeFor(couldNotRun, needsHuman, strict) {
  if (couldNotRun > 0) return 2;
  return strict && needsHuman ? 1 : 0;
}
process.exit(exitCodeFor(couldNotRun, needsHuman, strict));

// probe
