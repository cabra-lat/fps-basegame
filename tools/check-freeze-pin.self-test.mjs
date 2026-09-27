// Self-test for tools/check-freeze-pin.mjs. Separate file so the tool's own
// body stays readable; the functions under test are passed in, so these check
// the REAL implementations rather than copies of them.
//
// The bias throughout is the same one that bit this project twice tonight: a
// check that is true of an internal field and invisible in the report is not a
// check. So most of what follows asserts on RENDERED TEXT and on EXIT CODES.

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';

const HERE = dirname(fileURLToPath(import.meta.url));
const CLI = join(HERE, 'check-freeze-pin.mjs');

export function selfTest(api) {
  const { classifySeverity, renderTreeReport, renderFreezeReport, commandLog, READ_ONLY, exitCodeFor } = api;
  let failures = 0;
  const check = (ok, label, extra = '') => {
    console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`);
    if (!ok) failures += 1;
  };

  // ── severity: the two classes that fail SILENTLY ─────────────────────────
  check(classifySeverity('fix(ik): repoint pole_bone_constraint to its real path').cls === 'FIX',
    'a commit whose subject reads as a FIX is classed FIX');
  check(classifySeverity('fix(ik): repoint pole_bone_constraint').silent === true,
    'and is flagged as failing SILENTLY — a reverted fix breaks nothing at build time');
  check(classifySeverity('invariants: promote the INV-37 family (detached-bot null receivers)').cls === 'INVARIANT/COVERAGE',
    'an INVARIANT/COVERAGE promotion is classed as such');
  check(classifySeverity('invariants: promote the INV-37 family').silent === true,
    'and is flagged as failing silently — the gate keeps passing, with fewer checks');
  check(classifySeverity('refactor: split the resolver').cls === 'COSMETIC',
    'a refactor is classed COSMETIC, so a freeze costing one is legible as cheap');
  check(classifySeverity('wibble the sprocket').cls === 'UNCLASSIFIED' && classifySeverity('wibble the sprocket').silent === true,
    'an unrecognised subject is UNCLASSIFIED and treated as possibly silent, not as harmless');
  check(classifySeverity('refactor: split the resolver').silent === false,
    'the cosmetic class is the only one that is NOT flagged silent — silence is the default, not the exception');

  // ── the coverage case is never a footnote ────────────────────────────────
  // This is the requirement the card calls out, and it is the one a naive
  // implementation gets wrong: reporting a coverage delta as informational
  // reproduces the defect inside the report.
  const t = {
    tree: '/some/wt', lane: 'agent/player-rig', head: '2bf08f7',
    subpath: 'addons/cabra.lat_shooters',
    pin: { sha: 'af09788218f45d352ede9f5cda629749f7efcd23' },
    checkedOut: { state: 'checked-out', sha: 'af09788218f45d352ede9f5cda629749f7efcd23' },
    freezeName: '76266eb',
    freezeNameSha: '76266eb0000000000000000000000000000000ab',
  };
  const rel = {
    kind: 'divergent',
    plain: 'the freeze name is NEITHER an ancestor nor a descendant of the pin — divergent branches',
    mergeBase: '6aa6ffd643f6685e0aedc48be433b9ce33a3c454', behind: '3', ahead: '13',
  };
  const sets = {
    lost: [
      { sha: 'af09788218f4', subject: 'fix(ik): repoint pole_bone_constraint to its real path', author: 'qa' },
      { sha: '3f91b05aaaaaa', subject: 'invariants: promote the INV-37 family (detached-bot null receivers)', author: 'testkit' },
    ],
    gained: [{ sha: '76266ebbbbbbb', subject: 'feat(player): make movement states authorable', author: 'player-rig' }],
  };
  const coverage = [
    { file: 'test/validate_invariants.gd', atPin: 1951, atName: 1804, delta: 147, note: null },
  ];
  const out = renderFreezeReport(t, rel, sets, coverage).join('\n');

  check(/FREEZE NAME: 76266eb/.test(out) && /DECLARED PIN: af09788218f4/.test(out),
    'both spellings are printed verbatim: the freeze name AND the declared pin');
  check(/NEITHER an ancestor nor a descendant/.test(out), 'the relation is stated, not implied');
  check(/merge base:\s+6aa6ffd6/.test(out), 'the merge base is reported — "off since when", not just "off by how much"');
  check(/COMMITS LOST BY HONOURING THE NAME: 2/.test(out), 'the commits a lane would LOSE are counted');
  check(/fix\(ik\): repoint pole_bone_constraint/.test(out) && /\[FIX\] — FAILS SILENTLY/.test(out),
    'a lost fix is marked FAILS SILENTLY, with its subject');
  check(/3 commit\(s\) on the pin only, 13 on the name only/.test(out), 'the divergence is quantified');

  // The coverage requirement, asserted on the rendered text.
  check(/COVERAGE IMPACT — READ THIS BEFORE DECIDING/.test(out), 'the coverage impact is a headline, not a footnote');
  check(/not informational/i.test(out), 'and the report says out loud that it is not informational');
  check(/THE LANE LOSES 147 LINE\(S\) OF ASSERTIONS/.test(out), 'the 147-line coverage loss is stated as a loss, with the number');
  check(/keeps PASSING/.test(out) && /lower check count/.test(out),
    'and it names the symptom a lane would actually observe: a passing gate with a lower count');

  // The gains must not be filed under losses — a different risk entirely.
  check(/COMMITS THE NAME ADDS \(not on the pin\): 1/.test(out), 'commits the name adds are listed separately');
  check(!/LOST[\s\S]*feat\(player\): make movement states authorable/.test(out.split('COMMITS THE NAME ADDS')[0]),
    'a gained commit is never reported as a loss');

  // A gained commit that CLAIMS to be a fix is the other silent class: the pin
  // does not have it, so nobody has reviewed it against the pin, and a wrong fix
  // breaks nothing at build time. Calling that "a gain" and moving on was wrong
  // when 9 of 13 commits on a disputed name carried fix subjects.
  const gFix = { ...t, freezeNameSha: '76266eb0000000000000000000000000000000ab' };
  const outG = renderFreezeReport(gFix, rel, {
    lost: [],
    gained: [
      { sha: 'aaaaaa1', subject: 'fix(player): MEASURED INERT -- do not ship as a fix', author: 'player-rig' },
      { sha: 'bbbbbb2', subject: 'feat(player): something', author: 'player-rig' },
    ],
  }, []).join('\n');
  check(/1 of them carry a FIX subject/.test(outG), 'gained commits with FIX subjects are called out by count');
  check(/aaaaaa1 {2}fix\(player\): MEASURED INERT/.test(outG), 'and listed, so a self-declared inert fix cannot hide in a count');
  check(/nobody has reviewed against the pin/.test(outG), 'and the report says why an unreviewed gain is not free');

  // A freeze that MATCHES the pin must say so plainly, with no invented findings.
  const same = { ...t, freezeNameSha: t.pin.sha };
  const outSame = renderFreezeReport(same, { kind: 'ancestor', plain: 'same' }, { lost: [], gained: [] }, []).join('\n');
  check(/the freeze name IS the declared pin/.test(outSame) && !/LOSE/.test(outSame),
    'a freeze that matches the pin reports that, and invents nothing');

  // ── the three states of a checkout stay distinct ─────────────────────────
  const onPin = renderTreeReport({ ...t }).join('\n');
  const offPin = renderTreeReport({ ...t, checkedOut: { state: 'checked-out', sha: 'deadbeef' } }).join('\n');
  const uninit = renderTreeReport({ ...t, checkedOut: { state: 'not-initialised', detail: 'directory absent' } }).join('\n');
  check(/on-pin\./.test(onPin), 'a tree on its pin says on-pin');
  check(/OFF-PIN/.test(offPin), 'a tree off its pin says OFF-PIN');
  check(/NOT-INITIALISED/.test(uninit) && /CANNOT BE ASKED/.test(uninit),
    'an uninitialised submodule is neither on-pin nor off-pin: the question cannot be asked');
  check(!/on-pin\./.test(uninit), 'and it is never reported as on-pin');
  check(/lane:    agent\/player-rig/.test(onPin) && /tree:    \/some\/wt/.test(onPin),
    'the report NAMES the lane and the worktree path, so a tree is never a bare reference');

  // ── the superproject walk, against a REAL throwaway repo ────────────────
  // The bug this pins: `git -C <submodule dir> rev-parse HEAD` answers with the
  // SUPERPROJECT's commit when the directory is not a repository of its own,
  // because git walks up. The tool was reporting addons/cabra.lat_shooters as
  // "checked out at f6d4a17" — the GAME repo's HEAD — which is a confident,
  // plausible, wrong SHA, and appeared in the first real run across 53 worktrees.
  //
  // The test writes into a temp directory it created and deletes afterwards.
  // That is the TEST's scratch, not the check touching a lane's tree: the
  // read-only guarantee is about runGit() inside the tool, and the commands
  // below are the test's own, run with cwd inside the temp dir.
  const scratch = mkdtempSync(join(tmpdir(), 'pincheck-'));
  const g = (args) => spawnSync('git', ['-C', scratch, ...args], { encoding: 'utf8' });
  spawnSync('git', ['init', '-q', scratch], { encoding: 'utf8' });
  mkdirSync(join(scratch, 'addons', 'cabra.lat_shooters'), { recursive: true });
  writeFileSync(join(scratch, 'addons', 'cabra.lat_shooters', 'a.gd'), '# not a repo\n');
  g(['add', '-A']);
  g(['-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-q', '-m', 'x']);
  const parentHead = g(['rev-parse', 'HEAD']).stdout.trim();
  const walked = spawnSync('git', ['-C', join(scratch, 'addons', 'cabra.lat_shooters'), 'rev-parse', 'HEAD'], { encoding: 'utf8' });
  check(walked.status === 0 && walked.stdout.trim() === parentHead,
    'precondition: plain rev-parse in a non-repo subdirectory DOES return the superproject HEAD (the trap is real)',
    `parentHead=${parentHead.slice(0, 7)} got=${(walked.stdout || '').trim().slice(0, 7)}`);
  const co = api.checkedOut(scratch, 'addons/cabra.lat_shooters');
  check(co.state === 'not-initialised',
    'checkedOut() reports NOT-INITIALISED for a directory that is not its own repository', `state=${co.state}`);
  check(/SUPERPROJECT/.test(co.detail || ''),
    'and says WHY, so the reader is not left to wonder whether it is on-pin or off-pin');
  check(co.sha === undefined, 'and it reports no SHA at all rather than the parent repo commit');
  rmSync(scratch, { recursive: true, force: true });

  // ── exit codes: could-not-look is not found-nothing ──────────────────────
  check(exitCodeFor(0, 0, false) === 0 && exitCodeFor(0, 0, true) === 0, 'a clean run is 0, strict or not');
  check(exitCodeFor(0, 2, true) === 1 && exitCodeFor(0, 2, false) === 0,
    'findings are advisory by default and fail only under --strict');
  check(exitCodeFor(1, 0, false) === 2 && exitCodeFor(1, 5, true) === 2,
    'a tree that COULD NOT BE CHECKED is 2 even with no findings and even under --strict');

  // ── the read-only claim, checked rather than asserted ────────────────────
  // Every git verb this process actually ran must be read-only. If someone adds
  // `submodule update` to the tool, this goes red instead of the card's
  // out-of-scope rule quietly being violated at runtime.
  const mutating = commandLog.filter((c) => !READ_ONLY.has(c.split(' ')[2]));
  check(mutating.length === 0, 'no mutating git verb was run', mutating.join(' | '));
  for (const forbidden of ['submodule', 'checkout', 'fetch', 'pull', 'merge', 'rebase', 'reset', 'commit', 'push']) {
    check(!READ_ONLY.has(forbidden), `'${forbidden}' is not in the read-only allowlist`);
  }

  // ── end to end, through the real CLI ─────────────────────────────────────
  // The lint shipped an inverted ternary that made it scan nothing, and 24 green
  // checks missed it because none of them went through the entry point. These go
  // through the entry point.
  const run = (args) => spawnSync(process.execPath, [CLI, ...args], { encoding: 'utf8' });
  const bad = run(['--tree', '/definitely/not/a/tree']);
  check(bad.status === 2, 'CLI: a tree that is not a repository exits 2, not 0', `status=${bad.status}`);
  check(/COULD NOT RUN/.test(bad.stdout), 'CLI: and says COULD NOT RUN rather than reporting a verdict');
  check(!/nothing needs a human/.test(bad.stdout), 'CLI: and does NOT print the all-clear for a run that never happened');

  console.log(failures ? `\n  self-test: ${failures} FAILED` : '\n  self-test: all checks passed');
  return failures === 0;
}
