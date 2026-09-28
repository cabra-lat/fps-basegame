#!/usr/bin/env node
// WHICH validate_*.gd ARE RUNNABLE BUT NEVER REGISTERED?
//
// This exists because a set you cannot regenerate is a number that goes stale. ballistics ran the
// same enumeration on two mains an hour apart and got the same nine, which is the only honest way
// to report a set: as something that can be recomputed rather than as a list someone pasted.
//
// It reads a REF, not the working tree, so it can be run against origin/main from anywhere and
// cannot be confused with whatever happens to be checked out.
//
// WHY IT MATTERS ENOUGH TO KEEP. The manifest states the principle itself, at :188 - "an
// unregistered harness is not parked, it is a test that silently rots, and a rot test reads as
// coverage" - while citing validate_ui_wiring, which this tool reports as one of the unregistered.
// The comment and this check are the same argument, and the check is the one that notices when the
// set changes.
//
// WHAT IT DELIBERATELY DOES NOT DO. It does not register anything and it does not exit non-zero by
// default, because whether each of these is MEANT to run headless in an aggregate gate is a question
// about what the gate is for, and four of them live under scenes/ where a UI or behaviour check may
// have been written to be run by hand. Enumeration tells you the SIZE of the unrun set. It does not
// tell you the set is wrong, and that difference is the difference between a finding and an opinion.
// Pass --strict to make it a gate, which is a decision someone should take rather than inherit.
//
//   node tools/unregistered-harnesses.mjs                # against origin/main
//   node tools/unregistered-harnesses.mjs HEAD           # against the checked-out commit
//   node tools/unregistered-harnesses.mjs --strict        # exit 1 when any are unregistered

import { execFileSync } from "node:child_process";

const argv = process.argv.slice(2);
const strict = argv.includes("--strict");
const REF = argv.find((a) => !a.startsWith("--")) || "origin/main";

const git = (...args) =>
  execFileSync("git", args, { encoding: "utf8", maxBuffer: 128 * 1024 * 1024 });

/** Exported for the tests: the whole derivation, with no I/O assumptions beyond `read`. */
export function classify(files, manifest, read) {
  const registered = [];
  const unregistered = [];
  const notHarness = [];
  for (const file of files) {
    const src = read(file);
    const ext = (src.match(/^extends\s+(\w+)/m) || [])[1];
    // A harness is something the gate can RUN. A RefCounted helper named validate_* is not one,
    // and counting it would put a tenth item in a set of nine - a difference that is a fact about
    // the file rather than a judgement about the count.
    if (ext !== "SceneTree") { notHarness.push({ file, ext: ext || "?" }); continue; }
    const esc = file.replace(/[./]/g, (m) => `\\${m}`);
    new RegExp(`\\[\\s*'[^,]*',\\s*'res://${esc}'`).test(manifest) ? registered.push(file) : unregistered.push(file);
  }
  return { registered, unregistered, notHarness };
}

export function run(ref) {
  const manifest = git("show", `${ref}:tools/verify-all.mjs`);
  const files = git("ls-tree", "-r", "--name-only", ref)
    .split("\n")
    .filter((f) => /(^|\/)validate_[a-z0-9_]+\.gd$/.test(f));
  const result = classify(files, manifest, (f) => git("show", `${ref}:${f}`));
  return { ref, total: files.length, ...result };
}

function report(r) {
  const out = [];
  out.push(`ref ${r.ref}`);
  out.push(`  validate_*.gd tracked       : ${r.total}`);
  out.push(`  extends SceneTree (runnable) : ${r.total - r.notHarness.length}`);
  out.push(`  named by a registry row      : ${r.registered.length}`);
  out.push(`  PRESENT BUT UNREGISTERED     : ${r.unregistered.length}`);
  out.push(`  excluded (not a harness)     : ${r.notHarness.length}${r.notHarness.length ? "  " + r.notHarness.map((n) => `${n.file} (${n.ext})`).join(", ") : ""}`);
  for (const f of [...r.unregistered].sort()) out.push(`    ${f}`);
  if (r.unregistered.length) {
    out.push("");
    out.push("  These do not run. That is a statement about the set, not a claim that every one of");
    out.push("  them is meant to - four live under scenes/ and may be written to be run by hand.");
  }
  return out.join("\n");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const r = run(REF);
  console.log(report(r));
  if (strict && r.unregistered.length) {
    console.error(`\n--strict: ${r.unregistered.length} runnable harness(es) are not in the manifest.`);
    process.exit(1);
  }
}
