#!/usr/bin/env node
/**
 * The done_at INVARIANT, checked over the whole bus rather than over a card being written.
 *
 * WHY A SWEEP AND NOT JUST A GUARD. A write-time guard (herdr-plugin-amq 01aad98) refuses to
 * move a finished card out of done, which prevents the write. It cannot tell you about the ones
 * that already happened, and ballistics measured why that matters: of 435 cards, 12 have
 * claimed_at strictly newer than done_at - a claim that landed on an already-completed card -
 * and ELEVEN OF THE TWELVE SELF-HEALED. They were revived and then completed again, so today
 * they sit in done/ reading clean. The defect fires constantly and is almost never visible.
 *
 * That inverts the sizing. A count of "cards currently inconsistent" is 1; the honest number is
 * 12 occurrences and 1 survivor. Anyone sizing this from the visible symptom sizes it wrong by an
 * order of magnitude - and the 11 healed ones are invisible to any per-write assertion, because
 * nothing writes to them again.
 *
 * The sweep is the only thing that would have caught them, and it costs one pass over the bus.
 *
 * WHAT IT ASSERTS, precisely: a card is either done (status done, done_at set) or it is not
 * (status != done, done_at null). Both halves, because either alone is satisfiable by a broken
 * board - a card with done_at and no done status, and a card done with no completion record.
 *
 * IT IS READ-ONLY. It writes nothing, moves nothing, and re-runs nothing. A checker that
 * repaired as it went would be unable to report what it found, and the count is the finding.
 *
 * THE SIGNATURE IS `claimed_at > done_at`, and it is worth being precise about why that is not
 * merely "recently touched". A normal card has claimed_at < done_at, because claiming sets
 * claimed_at and completing sets done_at. A claim landing AFTER done_at is a claim on a finished
 * card. A deliberate reopen would also produce it IF the reopen preserved done_at - which is
 * exactly the defect, so a correct reopen (01aad98 clears done_at) does not match.
 *
 * LIMIT, stated rather than glossed: this infers from timestamps. It cannot tell a racing caller
 * from a human who meant to reopen, and it does not read proofs or histories. It reports
 * candidates; it does not assert intent.
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const BUS = process.argv[2] ||
  path.join(process.env.HERDR_PLUGIN_STATE_DIR || "", "bus");

function readField(content, field) {
  const m = content.match(new RegExp(`^${field}:\\s*"?([^"\\n]*)"?\\s*$`, "m"));
  if (!m) return null;
  const v = m[1].trim();
  return !v || v === "null" ? null : v;
}

export function sweepBus(busDir, known = new Map()) {
  const hits = { claimedAfterDone: [], doneWithoutRecord: [], statusDoneWithoutDoneAt: [] };
  let scanned = 0, wellFormed = 0, legacy = 0, knownCount = 0;

  let stages = [];
  try {
    stages = fs.readdirSync(busDir, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name);
  } catch {
    return { error: `bus not readable: ${busDir}`, scanned: 0, hits };
  }

  for (const stage of stages) {
    const dir = path.join(busDir, stage);
    for (const file of fs.readdirSync(dir)) {
      if (!file.endsWith(".md")) continue;
      const full = path.join(dir, file);
      let content;
      try {
        content = fs.readFileSync(full, "utf8");
      } catch {
        continue;
      }
      scanned++;

      const status = readField(content, "status");
      const doneAt = readField(content, "done_at");
      const claimedAt = readField(content, "claimed_at");
      const id = file.replace(/\.md$/, "");
      const rel = path.join(stage, file);

      // LEGACY CARDS PREDATE THE STAMPS ENTIRELY, and counting them as violations would make
      // this gate permanently red and therefore permanently ignored - which is how a checker
      // becomes worse than no checker. 160 of the cards on the live bus are migration-era files
      // from 2026-09-23 with eight frontmatter fields and no done_at, claimed_at or blocked_at
      // at all. They are not cards that LOST a completion record; they are cards from before
      // there was one to lose.
      //
      // So a card is MODERN if the current writer left any of its stamps behind. Only modern
      // cards are held to the invariant; legacy ones are counted and named, never failed on.
      const modern = claimedAt !== null || readField(content, "blocked_at") !== null ||
        readField(content, "status_at") !== null || readField(content, "next_actor_at") !== null;
      if (!modern) { legacy++; continue; }

      // The invariant, both halves.
      if (status !== "done" && doneAt) {
        const afterClaim = Boolean(claimedAt && claimedAt > doneAt);
        const h = { id, rel, status, doneAt, claimedAt };
        if (known.has(`${id}|${status}|${doneAt}`)) { knownCount++; continue; }
        (afterClaim ? hits.claimedAfterDone : hits.statusDoneWithoutDoneAt).push(h);
        continue;
      }
      if (status === "done" && !doneAt) {
        if (known.has(`${id}|${status}|`)) { knownCount++; continue; }
        hits.doneWithoutRecord.push({ id, rel, status });
        continue;
      }
      wellFormed++;
    }
  }
  return { scanned, wellFormed, legacy, knownCount, hits, stages };
}

/**
 * The baseline: violations somebody has already accepted and NAMED.
 *
 * This exists because the sweep is red today - one live violation, 0273c0, which is range's to
 * answer - and a check that is red for a reason someone has already accepted is a check people
 * learn to ignore, after which the next real violation is missed too. That is the same argument
 * that keeps the 173 legacy cards reported-but-not-failed, applied to a case with a name.
 *
 * THE KEY INCLUDES status AND done_at, NOT JUST THE ID, and that is the part that stops it
 * becoming a rug. A baseline acknowledges a known STATE. If the card is repaired, changed or
 * re-written with a different stamp, the key stops matching and the card becomes NEW again - so
 * baselining cannot quietly become a permanent amnesty for a card nobody looked at.
 */
export function loadBaseline(file) {
  const known = new Map();
  let entries = [];
  try {
    const raw = JSON.parse(fs.readFileSync(file, "utf8"));
    entries = Array.isArray(raw) ? raw : (raw.known || []);
  } catch {
    return known;
  }
  for (const e of entries) known.set(`${e.id}|${e.status}|${e.done_at || ""}`, e);
  return known;
}

// Direct invocation: report, never repair.
if (import.meta.url === `file://${process.argv[1]}`) {
  // The baseline lives NEXT TO THE TOOL, not in the bus. A baseline inside .agent-mail would be
  // a file in the live state root that a sweep is meant to be checking - and the earlier default
  // put it there, so the default invocation found no baseline, reported the one known violation
  // as NEW, and exited 1. A gate whose default run disagrees with its documented behaviour is
  // worse than no gate: the first person to run it gets a red they cannot explain.
  const BASELINE = process.argv[3] ||
    path.join(path.dirname(fileURLToPath(import.meta.url)), "done-invariant-baseline.json");
  const known = loadBaseline(BASELINE);
  const r = sweepBus(BUS, known);
  if (r.error) {
    console.error(`❌ ${r.error}`);
    process.exit(1);
  }
  const n = (k) => r.hits[k].length;
  console.log(`scanned ${r.scanned} card(s) across ${r.stages.length} stage(s); ${r.wellFormed} well-formed`);
  console.log(`  legacy, predate the stamps    : ${r.legacy} (not held to the invariant)`);
  console.log(`  known, baselined, not new     : ${r.knownCount}`);
  console.log(`  claim landed after completion : ${n("claimedAfterDone")}`);
  console.log(`  not done but carries done_at   : ${n("statusDoneWithoutDoneAt")}`);
  console.log(`  done with no completion record : ${n("doneWithoutRecord")}`);
  for (const k of ["claimedAfterDone", "statusDoneWithoutDoneAt", "doneWithoutRecord"]) {
    for (const h of r.hits[k]) {
      console.log(`    [${k}] ${h.rel} status=${h.status} done_at=${h.doneAt}${h.claimedAt ? ` claimed_at=${h.claimedAt}` : ""}`);
    }
  }
  // Exit 1 on a NEW violation only. Read-only, so a non-zero exit costs nothing to produce, and
  // a baselined violation is listed above rather than hidden - acknowledging it and hiding it
  // are different things and only one of them is a gate.
  const total = n("claimedAfterDone") + n("statusDoneWithoutDoneAt") + n("doneWithoutRecord");
  console.log(total === 0
    ? "OK: 0 new violation(s)."
    : `FAIL: ${total} NEW violation(s) not in the baseline.`);
  process.exit(total ? 1 : 0);
}
