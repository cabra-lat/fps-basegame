#!/usr/bin/env node
// fix-uids.mjs — REPORT-AND-PATCH for missing .uid files.
//
// WHY THIS EXISTS AND WHY IT DOES NOT COMMIT. The uid_tracking gate in
// verify-all.mjs keys on TRACKED files: it lists HEAD and asks which scripts
// lack a tracked .uid. That is the right question, and it is the reason a
// working tree can look complete while the gate is red — Godot writes the .uid
// on import, so the file sits on disk, untracked, and the gate correctly does
// not see it. Reading "the file exists" as "the file is tracked" is how nine
// real instances of the defect class went reported as resolved.
//
// This tool therefore never commits. AGENTS.md reserves commits in
// addons/*  for the addon owner, and a tool that both finds and fixes would
// let a repository acquire a commit its maintainer did not make. It prints
// the exact git add lines and stops. Run it, read the output, and let the
// owning lane run them.
//
// THE THREE STATES, which are not one operation. A script whose .uid is on
// disk but untracked needs `git add`. A script whose .uid is absent entirely
// needs a Godot import run first, because you cannot add a file that does not
// exist — reporting those as "missing" alongside the addable ones is how a
// fixer ends up looking like it worked. And a tracked .uid whose target is
// gone is an orphan, which is a question about deletion and is reported, never
// removed: deciding a file is dead is a human judgement.
//
// THE SCRIPT SET IS DELIBERATELY NARROWER THAN THE RESOURCE SET, and this
// asymmetry is load-bearing, not an oversight. Forward, only scripts get a
// generated .uid. Reverse, a .uid belongs to any resource — .gdextension,
// .tscn, .tres all have one — so the reverse question is "does this uid's
// target exist", which is a different question and has a different answer.
// Collapsing the two is what made the libik descriptor's own uid read as
// orphaned the first time a GDExtension was tracked. A gate that reports
// false positives trains people to ignore the gate.
//
// REPOS ARE DERIVED, NEVER LISTED. The gate's original two-entry array was
// diagnosed as its root cause, independently, by two separate measurements. A
// fixer carrying its own hardcoded list would reintroduce that exact defect
// while appearing to be the tool that fixes it.
//
// bin/ IS REFUSED. An untracked bin/ sitting beside other untracked files is
// the shape an adjacent `git add` swallows, and this project's recorded
// decision is not to commit the platform binaries under addons/libik/bin. A
// uid tool has no business being the reason that decision is quietly reversed.
//
// Usage:  node tools/fix-uids.mjs            # report only, changes nothing
//         node tools/fix-uids.mjs --list     # also print copy-pasteable git adds
// Exit 0 when nothing is actionable, 1 when there is, so CI can gate on it.

import { execFileSync } from 'node:child_process';
import { realpathSync } from 'node:fs';
import { resolve } from 'node:path';

const SCRIPT_RE = /\.(gd|gdshader|gdshaderinc)$/;
const DOT = (p) => p.split('/').some((part) => part.startsWith('.'));

function git(cwd, args) {
  try {
    return execFileSync('git', args, { cwd, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  } catch {
    return null;
  }
}

// A repo that is actually this checkout, not a parent that merely contains it.
function repoRoot(cwd) {
  const top = git(cwd, ['rev-parse', '--show-toplevel']);
  if (!top) return null;
  return realpathSync(top.trim()) === realpathSync(resolve(cwd)) ? resolve(cwd) : null;
}

function submodules() {
  const raw = git('.', ['config', '-f', '.gitmodules', '--get-regexp', '^submodule\..*\.path$']);
  if (!raw) return [];
  return ['.', ...raw.split(/\r?\n/).filter(Boolean).map((line) => line.trim().split(/\s+/).pop())];
}

const bucket = { addable: [], needsImport: [], ignored: [], orphan: [], checked: [], skipped: [] };

for (const rel of submodules()) {
  const root = repoRoot(rel);
  if (!root) {
    // Not a checkout of its own — a gitlink with no populated worktree, or a
    // path that is not a repo at all. Reported rather than silently dropped,
    // because a silent skip is indistinguishable from a clean result.
    bucket.skipped.push(rel);
    continue;
  }
  const head = git(root, ['ls-tree', '-r', '--name-only', 'HEAD']);
  if (!head) {
    bucket.skipped.push(rel);
    continue;
  }
  const files = head.split(/\r?\n/).filter(Boolean).filter((f) => !DOT(f));
  const tracked = new Set(files);
  bucket.checked.push(rel);

  const scripts = files.filter((f) => SCRIPT_RE.test(f));
  for (const script of scripts) {
    const uid = `${script}.uid`;
    if (tracked.has(uid)) continue;
    // The distinction this whole tool exists for: on disk is not tracked.
    // But there is a THIRD reason a file can be absent from the index, and it
    // is not an oversight in anyone's worktree: an IGNORE RULE. Three of the
    // addon repositories ship .gitignore with `*.uid` on line 1, so their .uid
    // files are present on disk, untracked, AND deliberately excluded. A fixer
    // that only asks "untracked?" files those under "needs an import" and sends
    // the reader to run Godot for no reason, while the real fix is a policy
    // conflict between a per-repo ignore rule and the project's uid_tracking
    // gate. That is a decision for a human, so it gets its own bucket and is
    // never presented as something to add.
    const untracked = git(root, ['ls-files', '--others', '--exclude-standard', '--', uid]);
    if (untracked && untracked.trim() === uid) {
      bucket.addable.push({ rel, uid });
    } else if (git(root, ['check-ignore', '-q', '--', uid]) !== null) {
      const rule = git(root, ['check-ignore', '-v', '--', uid]);
      bucket.ignored.push({ rel, uid, rule: (rule || '').trim() });
    } else {
      bucket.needsImport.push({ rel, uid });
    }
  }

  // Reverse: a tracked .uid whose target is gone. Reported, never removed.
  for (const file of files.filter((f) => f.endsWith('.uid'))) {
    const target = file.slice(0, -4);
    if (!tracked.has(target)) bucket.orphan.push({ rel, uid: file, target });
  }
}

const n = (a) => a.length;
console.log(`uid report — ${bucket.checked.length} repo(s) checked, ${bucket.skipped.length} skipped`);
for (const rel of bucket.skipped) console.log(`  SKIP  ${rel}  (not a populated checkout of its own)`);

console.log(`\naddable now (on disk, untracked) — ${n(bucket.addable)}`);
for (const { rel, uid } of bucket.addable) console.log(`  ${uid}   [${rel}]`);

console.log(`\nneeds a Godot import first (no .uid anywhere) — ${n(bucket.needsImport)}`);
for (const { rel, uid } of bucket.needsImport) console.log(`  ${uid}   [${rel}]`);
if (n(bucket.needsImport)) {
  console.log('  -> run the project import through the lock wrapper, then re-run this tool.');
  console.log('     tools/godot-lock.sh --headless --path . --import');
}

console.log(`\nEXCLUDED BY AN IGNORE RULE (on disk, untracked, and deliberately so) — ${n(bucket.ignored)}`);
for (const { rel, uid, rule } of bucket.ignored) console.log(`  ${uid}   [${rel}]\n      ${rule}`);
if (n(bucket.ignored)) {
  console.log('  -> a per-repository .gitignore excludes these, so `git add` will not take them');
  console.log('     and running an import will not help. This is a POLICY CONFLICT between that');
  console.log('     repositories ignore rule and the projects uid_tracking gate: either the');
  console.log('     ignore rule changes, or the gate stops covering that repository. It is a');
  console.log('     decision, not a fix, so this tool will not resolve it either way.');
}

console.log(`\norphaned uid (tracked, target gone) — ${n(bucket.orphan)}`);
for (const { rel, uid, target } of bucket.orphan) console.log(`  ${uid} -> missing ${target}   [${rel}]`);
if (n(bucket.orphan)) console.log('  -> report only. Deciding a resource is dead is a human judgement.');

if (process.argv.includes('--list') && n(bucket.addable)) {
  console.log('\ncopy-pasteable — run these from the repo root, one per repository:');
  for (const rel of bucket.checked) {
    const uids = bucket.addable.filter((x) => x.rel === rel).map((x) => x.uid);
    if (uids.length) console.log(`  git -C ${rel === '.' ? '.' : rel} add -- ${uids.join(' ')}`);
  }
  console.log('  (this tool does not run these, and never commits)');
}

const actionable = n(bucket.addable) + n(bucket.needsImport) + n(bucket.ignored) + n(bucket.orphan);
console.log(`\nRESULT: ${actionable ? `FAIL ${actionable} item(s)` : 'PASS nothing actionable'}`);
process.exit(actionable ? 1 : 0);
