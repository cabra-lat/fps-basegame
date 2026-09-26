#!/usr/bin/env node
/**
 * Infrastructure acceptance checks for the AMQ/herdr bridge and Godot lock.
 *
 * These checks are intentionally independent of the game and addons. Run the
 * fast source-contract checks with:
 *
 *   node tools/qa/validate_infrastructure.mjs
 *
 * Add --live-board to also validate the current AGboard JSON shape/state:
 *
 *   node tools/qa/validate_infrastructure.mjs --live-board
 *
 * The live check is optional because a normal Godot gate does not require the
 * coordinator's herdr/AMQ installation. It is useful in the agent workspace and
 * is the acceptance check for board-state consistency.
 */
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const bridgePath = join(ROOT, "tools", "amq-herdr-bridge.mjs");
const verifyPath = join(ROOT, "tools", "verify-all.sh");
const godotLockPath = join(ROOT, "tools", "godot-lock.sh");
const bridge = readFileSync(bridgePath, "utf8");
const verify = readFileSync(verifyPath, "utf8");
const godotLock = readFileSync(godotLockPath, "utf8");
const liveBoard = process.argv.includes("--live-board");
const results = [];

function check(name, fn) {
  try {
    const detail = fn();
    results.push({ name, ok: true, detail: detail || "ok" });
  } catch (error) {
    results.push({ name, ok: false, detail: String(error.message || error) });
  }
}

function requireMatch(text, expression, message) {
  if (!expression.test(text)) throw new Error(message);
}

function lockExpression(text) {
  const match = text.match(/LOCK_FILE="([^\n]*verify-all\.[^\n]*\.lock)"/);
  if (!match) throw new Error("per-repository verify-all lock expression not found");
  return match[1];
}

check("identity propagation", () => {
  requireMatch(bridge, /const AMQ_ROOT = process\.env\.AM_ROOT \|\| path\.join\(REPO_ROOT, "\.agent-mail"\)/, "bridge root is not the repository AMQ root or an explicit AM_ROOT override");
  requireMatch(bridge, /function handles\(\)/, "handle discovery missing");
  requireMatch(bridge, /\(typeof a === "string" \? a : a\.handle\)/, "AMQ handles are not propagated from config");
  for (const fn of ["inbox", "agentState", "healName", "prompt"]) {
    requireMatch(bridge, new RegExp(`function ${fn}\\(handle`), `${fn} does not accept the AMQ handle`);
  }
  return "AMQ handle is used for config, inbox, herdr state, healing, and prompts";
});

check("same-thread action-required reply", () => {
  requireMatch(bridge, /reply to the SENDER on the same/, "doorbell does not require replying to the sender");
  requireMatch(bridge, /thread with amq reply --id <msg_id>/, "doorbell does not include the same-thread reply command");
  requireMatch(bridge, /every action-required message/, "doorbell does not distinguish action-required messages");
  return "doorbell names the sender, same thread, message id, and action-required replies";
});

check("stale-pane detection and recovery", () => {
  requireMatch(bridge, /if \(st === "missing"\)/, "missing herdr state is not detected");
  requireMatch(bridge, /healName\(handle\)/, "missing agent does not attempt pane healing");
  requireMatch(bridge, /terminal_title_stripped \|\| p\.terminal_title/, "pane title fallback is missing");
  requireMatch(bridge, /\["agent", "rename", hit\.pane_id, handle\]/, "pane is not renamed back to the AMQ identity");
  requireMatch(bridge, /after name-heal/, "delivery is not retried after identity healing");
  return "missing identity -> pane-title lookup -> rename -> retry path is present";
});

check("board state consistency (source contract)", () => {
  requireMatch(bridge, /\["list", "--root", AMQ_ROOT/, "bridge does not query the same AMQ root");
  requireMatch(bridge, /newest\.from/, "bridge does not retain sender identity for alerting");
  return "bridge source preserves the AMQ root and sender identity";
});

check("one Godot job per repository", () => {
  const a = lockExpression(verify);
  const b = lockExpression(godotLock);
  if (a !== b) throw new Error(`lock paths differ: verify-all=${a}, godot-lock=${b}`);
  requireMatch(verify, /flock -w 900 9/, "verify-all does not serialize on the shared lock");
  requireMatch(godotLock, /flock -n 9/, "direct Godot wrapper does not probe the shared lock");
  requireMatch(godotLock, /flock -w 900 9/, "direct Godot wrapper does not wait on the shared lock");
  requireMatch(godotLock, /exec "\$GODOT_BIN"/, "wrapper does not exec the requested Godot command");
  return `verify-all and godot-lock use ${a}`;
});

check("board JSON shape and statuses", () => {
  if (!liveBoard) return "SKIP (pass --live-board for current AGboard)";
  let raw;
  try {
    raw = execFileSync("herdr-amq", ["task", "list", "--json"], {
      encoding: "utf8",
      env: { ...process.env, AM_ROOT: process.env.AM_ROOT || join(ROOT, ".agent-mail") },
    });
  } catch (error) {
    throw new Error(`herdr-amq task list --json failed: ${String(error.stderr || error.message).trim()}`);
  }
  const tasks = JSON.parse(raw);
  if (!Array.isArray(tasks)) throw new Error("task list is not an array");
  const ids = new Set();
  const statuses = new Set(["backlog", "in_progress", "blocked", "done"]);
  for (const task of tasks) {
    if (!task || typeof task.id !== "string" || ids.has(task.id)) throw new Error(`duplicate/invalid task id: ${task?.id}`);
    ids.add(task.id);
    if (!statuses.has(task.status)) throw new Error(`${task.id} has invalid status ${task.status}`);
    if (typeof task.owner !== "string" || typeof task.title !== "string") throw new Error(`${task.id} is missing owner/title`);
  }
  return `${tasks.length} tasks have unique ids, valid statuses, owners, and titles`;
});

for (const result of results) {
  console.log(`${result.ok ? "PASS" : "FAIL"} ${result.name}: ${result.detail}`);
}
const failed = results.filter((result) => !result.ok).length;
console.log(`RESULT: ${failed === 0 ? "PASS" : "FAIL"} (${results.length - failed}/${results.length} checks)`);
process.exit(failed === 0 ? 0 : 1);
