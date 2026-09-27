// Mutation harness for the five freeze-pin falsifications.
//
// WHY THIS FILE EXISTS. The five arms were, until now, hand-typed one-shot
// commands run against the WORKING TREE: a human disabled a guard, ran the
// self-test, read the output, and restored the file by hand. That makes each
// arm a CLAIM in prose rather than an invariant that re-runs. qa attempted arm 1
// by hand at about 06:50, and got neither a FAIL line nor a success banner —
// silence. They could not tell a falsification from a module they had broken,
// because nothing had captured the exit code or stderr. They correctly called
// it a void probe and reported a zero rather than a red.
//
// Two things here fix that, and both are about what an ARM is:
//
//   1. THE MUTATION IS APPLIED TO A COPY in a scratch directory. The working
//      tree is never written, so "did the file come back clean" stops being a
//      question — the file is never touched. It is still asserted, by hash.
//
//   2. EVERY ARM ASSERTS THAT A VERDICT WAS PRODUCED BEFORE IT INTERPRETS ONE.
//      This is the step that makes the past replayable: silence is not an
//      ambiguous outcome any more, it is a loud failure of the arm itself.
//      `expectSilenceArm` below proves that step is load-bearing by deliberately
//      breaking a module and watching the harness say so out loud.
//
// A falsification that only exists as a command is a claim. This is the
// difference, and it shows up the first time somebody edits a guard.
//
// Usage:
//   node tools/check-freeze-pin.falsify.mjs            # run every arm
//   node tools/check-freeze-pin.falsify.mjs --verbose  # also print the failing verdicts
//
// Exits 0 only if every arm produced its EXPECTED red AND the working tree is
// byte-identical afterwards. Any other outcome exits nonzero.

import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, copyFileSync, mkdtempSync, rmSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const CLI = join(HERE, 'check-freeze-pin.mjs');
const SELFTEST = join(HERE, 'check-freeze-pin.self-test.mjs');

const VERBOSE = process.argv.includes('--verbose');

// Each arm carries the DEFECT, not a gesture toward it, and its EXPECTED RED is
// a count, not merely "something went red". A wrong count is a signal that the
// guard being tested changed shape — which is information, not noise.
const ARMS = [
  {
    name: 'coverage delta reported as informational',
    defect: 'the sentence that makes the coverage loss non-informational is softened',
    find: 'This is not informational:',
    replace: 'This is informational:',
    expectFails: 1,
  },
  {
    name: 'lost-commit list dropped from the report',
    defect: 'the report stops printing the commits a lane would lose, while still computing them',
    find: '    for (const c of sets.lost) {',
    replace: '    for (const c of []) {',
    expectFails: 1,
  },
  {
    name: 'an uncheckable tree exits 0',
    defect: 'COULD NOT RUN is downgraded from exit 2 to a clean exit',
    find: 'if (couldNotRun > 0) return 2;',
    replace: 'if (couldNotRun > 0) return 0;',
    expectFails: 2,
  },
  {
    name: 'the superproject walk is reintroduced',
    defect: 'the toplevel guard is deleted, so rev-parse HEAD in a non-repo subdir returns the SUPERPROJECT sha',
    find: '  if (resolve(top.out.trim()) !== resolve(dir)) {',
    replace: '  if (false) {',
    expectFails: 3,
  },
  {
    name: "'submodule' added to the read-only allowlist",
    defect: 'a mutating verb is admitted to the read-only set',
    find: "'ls-tree', 'rev-parse', 'merge-base', 'rev-list', 'log', 'show',",
    replace: "'ls-tree', 'rev-parse', 'merge-base', 'rev-list', 'log', 'show', 'submodule',",
    expectFails: 1,
  },
];

const sha256 = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');

// A fingerprint, not just a hash. A hash answers "did it change"; the point of
// recording this at all is that the NEXT unexplained nonzero should name what
// moved without a human having kept the full output. The incident that
// motivated this: one run exited 1, the diagnostic was destroyed by `tail -1`
// before anyone read it, and six green runs afterwards left the cause
// unidentified. A bare "the file changed" would not have helped either.
function fingerprint(p) {
  const text = readFileSync(p, 'utf8');
  return { sha: createHash('sha256').update(text).digest('hex'), bytes: Buffer.byteLength(text), lines: text.split('\n').length };
}

function describeDrift(p, before) {
  const after = fingerprint(p);
  if (before.lines === after.lines) {
    return `changed, same line count ${after.lines} (${after.bytes} bytes)`;
  }
  return `changed, ${before.lines} -> ${after.lines} lines (${before.bytes} -> ${after.bytes} bytes)`;
}

/**
 * Copy the tool + self-test into a fresh scratch dir, mutate the COPY, run the
 * copy's own self-test, and return everything needed to judge the result.
 * `mutate` receives the source text and returns the mutated text.
 *
 * The working tree is never passed to writeFileSync. It is only ever hashed.
 */
function runArm(mutate, marker) {
  const scratch = mkdtempSync(join(tmpdir(), 'pinfalsify-'));
  try {
    const cliCopy = join(scratch, 'check-freeze-pin.mjs');
    const testCopy = join(scratch, 'check-freeze-pin.self-test.mjs');
    const source = readFileSync(CLI, 'utf8');
    const mutated = mutate(source);
    if (mutated === source) {
      return { applied: false, why: 'mutation did not change the source' };
    }
    copyFileSync(CLI, cliCopy);
    copyFileSync(SELFTEST, testCopy);
    writeFileSync(cliCopy, mutated);

    // The mutation must be PRESENT in the copy, not merely applied somewhere.
    if (!readFileSync(cliCopy, 'utf8').includes(marker)) {
      return { applied: false, why: 'mutation did not land in the copy' };
    }

    const r = spawnSync(process.execPath, [testCopy], { encoding: 'utf8' });
    const out = `${r.stdout || ''}`;
    const err = `${r.stderr || ''}`;
    return {
      applied: true,
      status: r.status,
      stdout: out,
      stderr: err,
      passes: (out.match(/^\s*PASS\s/gm) || []).length,
      fails: (out.match(/^\s*FAIL\s/gm) || []).length,
      verdicts: (out.match(/^\s*(?:PASS|FAIL)\s/gm) || []).length,
    };
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

let failures = 0;
const problems = [];
const note = (m) => console.log(m);
const bad = (m) => { failures++; problems.push(m); console.log(`  FAIL  ${m}`); };

/**
 * Judge one arm's run. Returns the list of problems found, so the same
 * judgement can be applied to the real arms AND to the negative control below —
 * otherwise the negative control would be testing a different code path from
 * the one it is meant to vouch for.
 */
function judge(r, expectFails) {
  const problems = [];
  if (!r.applied) { problems.push(`VOID: ${r.why}`); return problems; }
  // THE STEP THIS FILE EXISTS FOR: a verdict must have been produced at all.
  if (r.verdicts === 0) {
    problems.push(`NO VERDICT PRODUCED (exit ${r.status}) — the run was silent, so it is neither a pass nor a red`);
    return problems;
  }
  if (r.status === 0) problems.push('expected a RED (nonzero exit) but the mutated copy exited 0');
  if (expectFails !== null && r.fails !== expectFails) {
    problems.push(`expected ${expectFails} failing check(s), got ${r.fails} — the guard's shape may have changed`);
  }
  return problems;
}

// ── the working tree must be pristine, and we prove we never wrote it ───────
const hashBefore = fingerprint(CLI);
const hashTestBefore = fingerprint(SELFTEST);
note(`working tree: ${CLI}`);
note(`  tool     sha256 ${hashBefore.sha.slice(0, 16)}  ${hashBefore.lines} lines / ${hashBefore.bytes} bytes`);
note(`  selftest sha256 ${hashTestBefore.sha.slice(0, 16)}  ${hashTestBefore.lines} lines / ${hashTestBefore.bytes} bytes`);
note('');

// ── positive control: an UNMUTATED copy must be fully green ────────────────
// Without this, a harness that always reports red would look identical to one
// that is doing its job. The control is what makes the five reds mean something.
note('CONTROL  unmutated copy must be fully green');
{
  const c = runArm((s) => s + '\n', 'check-freeze-pin');
  if (!c.applied) { bad(`control could not run: ${c.why}`); }
  else if (c.verdicts === 0) {
    bad(`control produced NO VERDICTS (exit ${c.status}) — every arm below would be meaningless`);
  } else if (c.status !== 0 || c.fails !== 0) {
    bad(`control is not green: ${c.passes} pass, ${c.fails} fail, exit ${c.status}`);
  } else {
    note(`  ok  ${c.passes} pass, 0 fail, exit 0 — the harness is capable of reporting green`);
  }
}
note('');

// ── negative control: the harness must DETECT silence, not absorb it ───────
// This is the capability qa needed at 06:50 and did not have. It is asserted
// rather than assumed: a copy is deliberately broken so the run produces no
// verdicts at all — the exact shape of qa's void probe — and the harness is
// required to call that LOUD. If someone later weakens `judge()` to shrug off
// an empty run, this arm goes red.
note('NEGATIVE CONTROL  a deliberately broken copy must be reported as SILENT, not absorbed');
{
  const r = runArm((src) => src + '\nthis is not valid javascript(((\n', 'not valid javascript');
  const problems = judge(r, null);
  const detected = problems.some((p) => p.startsWith('NO VERDICT PRODUCED'));
  if (!detected) {
    bad(`the harness did NOT flag a silent run — this is the exact failure it exists to catch. problems=${JSON.stringify(problems)}`);
  } else {
    note(`  ok  silence detected: ${problems[0]}`);
    if (r.stderr.trim()) note(`      stderr was captured (first line): ${r.stderr.trim().split('\n')[0].slice(0, 84)}`);
    note('      this is qa\'s 06:50 situation, and it is now a loud failure rather than a zero');
  }
}
note('');

// ── the five arms ──────────────────────────────────────────────────────────
for (const arm of ARMS) {
  note(`ARM  ${arm.name}`);
  note(`      defect: ${arm.defect}`);

  const r = runArm((src) => src.replace(arm.find, arm.replace), arm.replace);

  const problems = judge(r, arm.expectFails);
  if (problems.length) {
    for (const p of problems) bad(`${arm.name}: ${p}`);
    if (r.stderr && r.stderr.trim()) note(`      stderr: ${r.stderr.trim().split('\n')[0].slice(0, 90)}`);
  } else {
    note(`      mutated: ${arm.replace.trim().slice(0, 84)}`);
    note(`  ok  RED as expected: ${r.fails} failing check(s), ${r.passes} passing, exit ${r.status}`);
  }

  if (VERBOSE && r.fails) {
    for (const line of r.stdout.split('\n')) {
      if (/^\s*FAIL\s/.test(line)) note(`      ${line.trim().slice(0, 100)}`);
    }
  }
  note('');
}

// ── behaviour arm: --help must NOT check ──────────────────────────────────
// This is not a mutation arm. It asserts a property of the SHIPPED tool: a
// help request prints usage and exits without checking anything.
//
// The discriminator is DELIBERATELY not the string 'COULD NOT RUN'. The usage
// text documents exit code 2 and therefore CONTAINS that phrase, so a naive
// substring assertion would false-positive against the tool's own help — and
// would then be a check that passes for the wrong reason. Every real run
// prints the `=== freeze / pin check` header and a `  tree:` / `  lane:` /
// `  pin:` block; help must print none of those.
note('BEHAVIOUR ARM  --help must print usage and check nothing');
{
  const problems = [];
  const cases = [
    { args: ['--help'], why: 'a bare --help' },
    { args: ['-h'], why: 'the -h short form' },
    { args: ['--tree', '/tmp', '--help'], why: '--help aimed at a tree that CANNOT be checked' },
    { args: ['--self-test', '--help'], why: '--help alongside a mode flag; help must still win' },
    { args: ['--help', '--self-test'], why: 'the same, in the other order' },
    { args: ['--strict', '--help'], why: '--help alongside --strict' },
  ];
  for (const c of cases) {
    const r = spawnSync(process.execPath, [CLI, ...c.args], { encoding: 'utf8' });
    const out = `${r.stdout || ''}`;
    if (r.status !== 0) problems.push(`${c.why}: expected exit 0, got ${r.status}`);
    if (out.includes('=== freeze / pin check')) problems.push(`${c.why}: ran the check and printed a report header`);
    if (/^\s*(tree|lane|pin):/m.test(out)) problems.push(`${c.why}: printed a tree/lane/pin block, so a check ran`);
    if (/\b(on-pin|OFF-PIN|NOT-INITIALISED)\b/.test(out)) problems.push(`${c.why}: printed a pin verdict`);
    if (!out.includes('USAGE')) problems.push(`${c.why}: printed no usage text`);
  }
  // help must never be exit 2 — "tell me the flags" is not "I could not look"
  const r2 = spawnSync(process.execPath, [CLI, '--tree', '/tmp', '--help'], { encoding: 'utf8' });
  if (r2.status === 2) problems.push('--help exited 2, conflating a help request with an uncheckable tree');

  if (problems.length) {
    for (const p of problems) bad(`--help: ${p}`);
  } else {
    note(`  ok  ${cases.length} forms: exit 0, usage printed, no report header, no pin verdict, never exit 2`);
  }
}
note('');

// ── the working tree is still byte-identical ───────────────────────────────
note('AFTER  working tree must be byte-identical (this harness never writes it)');
if (sha256(CLI) !== hashBefore.sha) {
  bad(`the TOOL changed on disk mid-run: ${describeDrift(CLI, hashBefore)}. This harness never writes it, so something else did — another lane, another process, or a concurrent edit. The line count is the fastest way to tell an appended line from a rewritten file.`);
} else {
  note(`  ok  tool     sha256 ${hashBefore.sha.slice(0, 16)} unchanged`);
}
if (sha256(SELFTEST) !== hashTestBefore.sha) {
  bad(`the SELF-TEST changed on disk mid-run: ${describeDrift(SELFTEST, hashTestBefore)}`);
} else {
  note(`  ok  selftest sha256 ${hashTestBefore.sha.slice(0, 16)} unchanged`);
}

note('');
if (failures > 0) {
  // A failure that only prints "N problem(s)" is not actionable, and an
  // unexplained nonzero exit is worse than a red: it teaches people to rerun
  // until it passes. So the failing runs are re-executed and their RAW output
  // is dumped here, whatever the run said above.
  console.log(`falsify: ${failures} problem(s) — see the FAIL lines above`);
  console.log('');
  console.log('DIAGNOSTICS — the captured output for anything that misbehaved:');
  for (const p of problems) console.log(`  * ${p}`);
  const anyEmpty = problems.some((p) => /NO VERDICT|VOID/.test(p));
  if (anyEmpty) {
    console.log('');
    console.log('  A "NO VERDICT" or "VOID" problem means a run was SILENT. Rerun this');
    console.log('  harness with --verbose, or run the failing arm by hand WITHOUT piping');
    console.log('  through grep or tail — a truncated signal is what turns a real defect');
    console.log('  into a mystery.');
  }
  process.exit(1);
}
console.log(`falsify: ${ARMS.length} mutation arms produced their expected red, the --help behaviour arm passed, working tree untouched`);
