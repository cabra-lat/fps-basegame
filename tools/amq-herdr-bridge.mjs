#!/usr/bin/env node
/**
 * amq-herdr-bridge — close the loop between AMQ (reliable, threaded messages) and
 * herdr (agent lifecycle + terminal control).
 *
 * Why: AMQ queues messages reliably but has no doorbell — an agent only sees mail
 * when it drains. herdr knows exactly which agent is idle/working/blocked/done and
 * can prompt it. Neither is enough alone; together they are a delivered bus.
 *
 * Both systems already use the SAME names (AMQ handle == herdr agent name), so the
 * mapping is free.
 *
 * Behaviour:
 *   - watch each handle's AMQ inbox (amq list --json, local files, cheap)
 *   - when a handle has unread mail:
 *       idle/done  -> prompt it via herdr to drain + reply to the sender
 *       working    -> leave it; it will drain on its next turn
 *       blocked    -> alert once (a blocked agent needs a human answer, not more mail)
 *       unknown    -> log
 *   - never prompt the same message twice (state file), never prompt on your own mail
 *
 * Usage:
 *   node tools/amq-herdr-bridge.mjs [--once] [--dry-run] [--interval 3000]
 *                                   [--handles a,b,c] [--state PATH]
 *   node tools/amq-herdr-bridge.mjs --stop     # kill the daemon via its pidfile
 *
 * Lifecycle: the daemon writes /tmp/shooter/amq-herdr-bridge.pid and removes it on
 * exit. Use `--stop` instead of pgrep — a compound shell line that *mentions* the
 * script path makes `pgrep -f` match its own shell (learned the hard way).
 *
 * Exit codes: 0 ok, 1 config/tooling error.
 */
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");
const AMQ_ROOT = path.join(REPO_ROOT, ".agent-mail");
const DEFAULT_STATE = "/tmp/shooter/amq-herdr-bridge-state.json";
const ALERT_LOG = "/tmp/shooter/blocked-alerts.log";

const argv = process.argv.slice(2);
const has = (f) => argv.includes(f);
const val = (f, d) => {
  const i = argv.indexOf(f);
  return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[i + 1] : d;
};

const ONCE = has("--once");
const DRY = has("--dry-run");
const STOP = has("--stop");
const INTERVAL = parseInt(val("--interval", "3000"), 10);
const STATE_PATH = val("--state", DEFAULT_STATE);
const PID_PATH = "/tmp/shooter/amq-herdr-bridge.pid";

if (STOP) {
  try {
    const pid = parseInt(fs.readFileSync(PID_PATH, "utf8").trim(), 10);
    if (!Number.isInteger(pid) || pid <= 0) throw new Error("bad pidfile");
    process.kill(pid, "SIGTERM");
    console.log(`stopped bridge pid ${pid}`);
    try { fs.unlinkSync(PID_PATH); } catch {}
  } catch (e) {
    console.error(`--stop: ${String(e.message).split("\n")[0]} (pidfile ${PID_PATH})`);
    process.exit(1);
  }
  process.exit(0);
}

const log = (...a) =>
  console.log(`[${new Date().toISOString().slice(11, 19)}] ${a.join(" ")}`);

function run(bin, args) {
  return execFileSync(bin, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, PATH: `${process.env.HOME}/.local/bin:${process.env.PATH}` },
  });
}

function handles() {
  const explicit = val("--handles", null);
  if (explicit) return explicit.split(",").map((s) => s.trim()).filter(Boolean);
  for (const p of [path.join(AMQ_ROOT, "meta", "config.json"), path.join(AMQ_ROOT, "config.json")]) {
    if (fs.existsSync(p)) {
      const cfg = JSON.parse(fs.readFileSync(p, "utf8"));
      return (cfg.agents || [])
        .map((a) => (typeof a === "string" ? a : a.handle))
        .filter(Boolean);
    }
  }
  return [];
}

// ─── AMQ ────────────────────────────────────────────────────────────────────────
function inbox(handle) {
  try {
    const out = run("amq", ["list", "--root", AMQ_ROOT, "--me", handle, "--new", "--json"]);
    const parsed = JSON.parse(out);
    return Array.isArray(parsed) ? parsed : [];
  } catch (e) {
    // `amq list --json` prints an empty array or nothing when the inbox is empty.
    const s = (e.stdout || "").trim();
    if (!s || s === "[]" || /No messages/i.test(s)) return [];
    log(`warn: amq list failed for ${handle}: ${String(e.message).split("\n")[0]}`);
    return [];
  }
}

// ─── herdr ──────────────────────────────────────────────────────────────────────
function agentState(handle) {
  try {
    const out = run("herdr", ["agent", "get", handle]);
    const j = JSON.parse(out);
    return j?.result?.agent?.agent_status ?? "unknown";
  } catch {
    return "missing";
  }
}

/**
 * Self-heal a lost agent name. herdr occasionally drops a pane's agent name (after
 * a modal, a long turn, or terminal churn) — then the handle is unreachable and its
 * mail silently piles up. The pane TITLE still carries the handle (`π - <handle> -
 * <project>`), so we can re-register it from there. This has bitten us ~5 times.
 */
function healName(handle) {
  try {
    const out = run("herdr", ["pane", "list"]);
    const panes = JSON.parse(out)?.result?.panes ?? [];
    const needle = `- ${handle} - `;
    const hit = panes.find((p) => (p.terminal_title_stripped || p.terminal_title || "").includes(needle));
    if (!hit) return false;
    if (DRY) {
      log(`DRY  would heal name: ${handle} <- pane ${hit.pane_id}`);
      return true;
    }
    run("herdr", ["agent", "rename", hit.pane_id, handle]);
    log(`healed  -> renamed pane ${hit.pane_id} back to '${handle}'`);
    return true;
  } catch (e) {
    log(`warn: heal ${handle} failed: ${String(e.message).split("\n")[0]}`);
    return false;
  }
}

function prompt(handle, text) {
  if (DRY) {
    log(`DRY  would prompt ${handle}: ${text.slice(0, 60)}…`);
    return true;
  }
  try {
    run("herdr", ["agent", "prompt", handle, text]);
    return true;
  } catch (e) {
    log(`warn: prompt ${handle} failed: ${String(e.message).split("\n")[0]}`);
    return false;
  }
}

function alert(handle, n, from) {
  const when = new Date().toISOString();
  const body =
    `${when} BLOCKED: agent ${handle} — ${n} unread AMQ message(s)` +
    (from ? ` (newest from ${from})` : "") +
    `. A blocked agent needs a human answer, not more mail. ` +
    `Inspect with: herdr agent read ${handle} --lines 40`;
  // Deliberately NOT posted to the queue: a blocked agent is an action for the
  // human, and mailing it to ourselves would be a self-send (it was one before).
  // It goes to the bridge pane (already logged) and to a file the human reads.
  log(body);
  if (DRY) return;
  try {
    fs.mkdirSync(path.dirname(ALERT_LOG), { recursive: true });
    fs.appendFileSync(ALERT_LOG, body + "\n");
  } catch (e) {
    log(`warn: alert log failed: ${String(e.message).split("\n")[0]}`);
  }
}

// ─── state (delivered ids, so a message is never doorbelled twice) ──────────────
function loadState() {
  try {
    return JSON.parse(fs.readFileSync(STATE_PATH, "utf8"));
  } catch {
    return { delivered: {} };
  }
}
function saveState(s) {
  const ids = Object.keys(s.delivered);
  if (ids.length > 2000) {
    ids.sort();
    for (const id of ids.slice(0, ids.length - 1500)) delete s.delivered[id];
  }
  fs.mkdirSync(path.dirname(STATE_PATH), { recursive: true });
  fs.writeFileSync(STATE_PATH, JSON.stringify(s, null, 1));
}

const doorbell = (handle, msgs) => {
  const senders = [...new Set(msgs.map((m) => m.from))].join(", ");
  const n = msgs.length;
  return (
    `AMQ doorbell: ${n} new message(s) in your inbox (from ${senders}). ` +
    `Run: amq drain --me ${handle} --include-body — then reply to the SENDER on the same ` +
    `thread with amq reply --id <msg_id> (do NOT report to coordinator by default). ` +
    `After replying, resume your current work.`
  );
};

// ─── one pass ───────────────────────────────────────────────────────────────────
const warnedMissing = new Set();
const lastHold = new Map(); // handle -> signature of pending ids (log only on change)

function pass(state) {
  let acted = 0;
  for (const handle of handles()) {
    const msgs = inbox(handle).filter((m) => m.from !== handle);
    if (!msgs.length) {
      lastHold.delete(handle);
      continue;
    }

    const fresh = msgs.filter((m) => !state.delivered[m.id]);
    if (!fresh.length) {
      lastHold.delete(handle);
      continue;
    }

    const st = agentState(handle);
    const newest = fresh[fresh.length - 1];

    if (st === "missing") {
      // Before giving up: the name may have been dropped by herdr. Try to heal it
      // from the pane title, and if that works, deliver this cycle.
      if (healName(handle)) {
        const healed = agentState(handle);
        if (healed === "idle" || healed === "done") {
          if (prompt(handle, doorbell(handle, fresh))) {
            if (!DRY) for (const m of fresh) state.delivered[m.id] = Date.now();
            log(`delivered -> ${handle} (${fresh.length} msg, status=${healed} after name-heal)`);
            acted++;
          }
          continue;
        }
      }
      // Not every AMQ handle is a named herdr agent (e.g. the human's own inbox).
      // Warn once per handle instead of every cycle.
      if (!warnedMissing.has(handle)) {
        warnedMissing.add(handle);
        log(`note    -> ${handle} has no herdr agent; no doorbell possible (${fresh.length} msg queued)`);
      }
      continue;
    }

    if (st === "idle" || st === "done") {
      if (prompt(handle, doorbell(handle, fresh))) {
        if (!DRY) for (const m of fresh) state.delivered[m.id] = Date.now();
        log(`delivered -> ${handle} (${fresh.length} msg, status=${st}, from=${newest.from})`);
        acted++;
      }
    } else if (st === "working") {
      const sig = fresh.map((m) => m.id).sort().join(",");
      if (lastHold.get(handle) !== sig) {
        lastHold.set(handle, sig);
        log(`hold    -> ${handle} is working (${fresh.length} msg queued, from=${newest.from}); will deliver when idle`);
      }
    } else if (st === "blocked") {
      alert(handle, fresh.length, newest.from);
      if (!DRY) for (const m of fresh) state.delivered[m.id] = Date.now();
      log(`alerted -> ${handle} is blocked (${fresh.length} msg)`);
      acted++;
    } else {
      log(`skip    -> ${handle} status=${st} (${fresh.length} msg)`);
    }
  }
  return acted;
}

// ─── main ───────────────────────────────────────────────────────────────────────
if (!fs.existsSync(AMQ_ROOT)) {
  console.error(`amq root not found: ${AMQ_ROOT}`);
  process.exit(1);
}

const state = loadState();
log(`bridge up — root=${AMQ_ROOT} handles=${handles().join(",")} interval=${INTERVAL}ms${DRY ? " (dry-run)" : ""}`);

// pidfile so `--stop` works; never rely on pgrep (it matches the invoking shell).
if (!ONCE && !DRY) {
  try {
    fs.mkdirSync(path.dirname(PID_PATH), { recursive: true });
    fs.writeFileSync(PID_PATH, String(process.pid));
    const cleanup = () => { try { fs.unlinkSync(PID_PATH); } catch {} process.exit(0); };
    process.on("SIGTERM", cleanup);
    process.on("SIGINT", cleanup);
  } catch (e) {
    log(`warn: pidfile failed: ${String(e.message).split("\n")[0]}`);
  }
}

if (ONCE) {
  const n = pass(state);
  saveState(state);
  log(`single pass done — ${n} delivery action(s)`);
  process.exit(0);
}

for (;;) {
  try {
    pass(state);
    saveState(state);
  } catch (e) {
    log(`error: ${String(e.message).split("\n")[0]}`);
  }
  await new Promise((r) => setTimeout(r, INTERVAL));
}
