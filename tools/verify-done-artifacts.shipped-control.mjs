#!/usr/bin/env node
// RED CONTROL #2: A RESOLVABLE LOCAL COMMIT IS NOT A SHIPPED ONE
//
// The specimen is real, dated, and named by the coordinator: 61fd195 and the twelve commits behind
// it sat on LOCAL main on 2026-09-27 while origin/main stood at 8cad44b. Thirteen cards were
// candidates for passing the first version of this gate as shipped, because a resolvable commit
// and a shipped commit look identical to anything that does not read a remote. The owner opened
// the game and saw no menu.
//
// THE STATE IS NOT RE-CREATED IN THE REAL REPOSITORY. origin/main is now f66eeca - the coordinator
// has since pushed - and moving that ref back in a shared checkout would break every other lane
// for the sake of a test. So the boundary is reproduced in a throwaway bare origin plus a clone,
// which is the same topology and costs nobody their work.
//
// THREE ARMS, because a two-arm test cannot see the failure this check exists to prevent:
//   1. local main ahead of origin  -> MUST report NOT shipped
//   2. after pushing               -> MUST report shipped
//   3. remote unreadable           -> MUST report unknown, and unknown must NOT pass
// Arm 3 is the one that is easy to leave out and the one that matters most: a verifier that reports
// "fine" because it could not look is believed, and belief is what makes an instrument dangerous.
//
// Run: node tools/verify-done-artifacts.shipped-control.mjs

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { shippedState, verifyCard } from "./verify-done-artifacts.mjs";

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "shipped-control-"));
const origin = path.join(tmp, "origin.git");
const work = path.join(tmp, "work");
const run = (dir, ...a) => execFileSync("git", a, { cwd: dir, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();

let bad = 0;
const check = (name, ok, detail) => {
  console.log(`  ${ok ? "PASS" : "FAIL"}  ${name}${detail ? ` - ${detail}` : ""}`);
  if (!ok) bad++;
};

try {
  // The bare remote and a clone of it: origin/main at 8cad44b, then thirteen local commits.
  run(tmp, "init", "--bare", "-q", origin);
  run(tmp, "clone", "-q", origin, work);
  run(work, "config", "user.email", "control@example.invalid");
  run(work, "config", "user.name", "Control");
  run(work, "checkout", "-q", "-b", "main");
  run(work, "commit", "-q", "--allow-empty", "-m", "base 8cad44b");
  const base = run(work, "rev-parse", "HEAD");
  run(work, "push", "-q", "-u", "origin", "main");
  const pushed = [];

  for (let i = 0; i < 13; i++) {
    run(work, "commit", "-q", "--allow-empty", "-m", `local commit ${i + 1}`);
    pushed.push(run(work, "rev-parse", "HEAD"));
  }
  const tip = pushed[pushed.length - 1];
  const oldest = pushed[0];
  console.log(`fixture: base ${base.slice(0, 7)}, 13 local commits, oldest ${oldest.slice(0, 7)}`);
  console.log(`origin/main is still at ${run(work, "rev-parse", "--short", "refs/remotes/origin/main").slice(0, 7)} while local main is at ${tip.slice(0, 7)}\n`);

  console.log("ARM 1 - local main ahead of origin, exactly the 2026-09-27 state:");
  const localOnly = shippedState(work, tip);
  check("the tip is reported NOT shipped", localOnly.state === "no", localOnly.detail);
  const oldestResult = shippedState(work, oldest);
  check("the OLDEST of the 13 is also not shipped", oldestResult.state === "no", oldestResult.detail);
  // The old gate's verdict on the same state - the thing that let the owner's fix through.
  const card = { id: "control", status: "done", proof: `landed in game: at ${work} commit ${tip} on branch main, shipped: yes` };
  const v = verifyCard(card, { game: work, addon: work });
  check("the done-artifacts gate REFUSES the card", !v.ok, v.failures.map((f) => f.defect).join("; "));
  check("it names the remote boundary as the reason", v.failures.some((f) => /not on any remote/.test(f.defect)), v.failures.map((f) => f.defect).join(" | "));

  console.log("\nARM 2 - after pushing, the same commit must pass:");
  run(work, "push", "-q", "origin", "main");
  const after = shippedState(work, tip);
  check("the tip is reported shipped", after.state === "yes", after.detail);
  const v2 = verifyCard({ id: "control2", status: "done", proof: `landed in game: at ${work} commit ${tip} on branch main, shipped: yes` }, { game: work, addon: work });
  check("the gate now ACCEPTS the same card", v2.ok, v2.failures.map((f) => f.defect).join("; "));

  console.log("\nARM 3 - a remote that cannot be read is UNKNOWN, and unknown must not pass:");
  run(work, "remote", "set-url", "origin", path.join(tmp, "gone.git"));
  const gone = shippedState(work, tip);
  check("state is unknown, not yes", gone.state === "unknown", gone.detail);
  check("the word 'not' is in the detail: it is not a pass", /not a pass/i.test(gone.detail || ""), gone.detail);
  const v3 = verifyCard({ id: "control3", status: "done", proof: `landed in game: at ${work} commit ${tip} on branch main, shipped: yes` }, { game: work, addon: work });
  check("the gate REFUSES a card it cannot verify", !v3.ok, v3.failures.map((f) => f.defect).join("; "));
  check("it reports the unknown, not a clean pass", v3.failures.some((f) => /could not be established/.test(f.defect)), v3.failures.map((f) => f.defect).join(" | "));

  console.log(`\nRED CONTROL #2: ${bad === 0 ? "PASS - a local commit cannot pass as shipped" : `FAIL - ${bad} arm(s) wrong`}`);
  process.exit(bad === 0 ? 0 : 1);
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
