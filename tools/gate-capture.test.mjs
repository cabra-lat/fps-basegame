#!/usr/bin/env node
// A CAPTURE MUST NOT BE ABLE TO LIE ABOUT ITSELF, AND A TRUNCATED ONE MUST SAY SO.
//
// Three lanes reproduced the same defect tonight, each in their own reporting:
//   ballistics  a capture whose RESULT line said 4 with six FAIL rows beside it
//   verifier    clean aggregates (RESULT 7 = 7 rows) with a summary that said "five" over six rows
//   the gate     RESULT 7 with seven FAIL rows, one run - correct every time it was read directly
//
// The instrument was never the problem. The TRANSCRIPTION was: a RESULT line carried forward beside
// rows from another run, or a number typed from one capture and a row list pasted from another.
//
// So these tests are about the arithmetic, not about the gate. They pin that a consistent capture is
// reported as consistent, an inconsistent one is REFUSED with a reason, and a truncated one is
// called out rather than quietly under-counted - which is the head -N case that produced the 4.
//
// Run: node tools/gate-capture.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import { summarise } from "./gate-capture.mjs";

const row = (s, n) => `  ${s.padEnd(4)} ${n.padEnd(17)} detail text here`;

const CONSISTENT = [
  "=== verify-all ===",
  row("PASS", "harness_paths"),
  row("PASS", "import/parse"),
  row("FAIL", "uid_tracking"),
  row("FAIL", "meta_flow"),
  row("WARN", "qa_audit"),
  row("SKIP", "export"),
  "",
  "RESULT: FAIL (2 hard gate(s) failed, 1 warning(s))",
  "",
].join("\n");

test("a consistent capture is reported as consistent, with both numbers from that file", () => {
  const s = summarise(CONSISTENT);
  assert.equal(s.agreeing, true, `expected agreement, got: ${s.problems.join("; ")}`);
  assert.equal(s.resultCount, 2, "the RESULT count");
  assert.equal(s.counts.fail, 2, "and the row count, derived from the same file");
  assert.deepEqual(s.failing, ["uid_tracking", "meta_flow"], "the failing gates are named");
  assert.equal(s.counts.warn, 1);
  assert.equal(s.counts.skip, 1);
});

test("a capture whose RESULT line disagrees with its rows is REFUSED - the ballistics case", () => {
  // RESULT 4 beside six FAIL rows. No judgement, no "which is right": refuse both.
  const lying = [
    row("PASS", "a"), row("FAIL", "b"), row("FAIL", "c"), row("FAIL", "d"),
    row("FAIL", "e"), row("FAIL", "f"), row("FAIL", "g"),
    "RESULT: FAIL (4 hard gate(s) failed)",
  ].join("\n");
  const s = summarise(lying);
  assert.equal(s.agreeing, false, "an inconsistent capture must never be reported as usable");
  assert.equal(s.resultCount, 4);
  assert.equal(s.counts.fail, 6, "both numbers are reported, so the reader can see the gap");
  assert.match(s.problems[0], /RESULT line says 4 and the capture holds 6/);
  assert.match(s.problems[0], /Do not quote either number/, "and it must say what not to do");
});

test("a capture with no RESULT line is refused rather than counted", () => {
  // What head -N leaves when it cuts the tail off: rows without the verdict.
  const truncated = [row("PASS", "a"), row("FAIL", "b"), row("FAIL", "c")].join("\n");
  const s = summarise(truncated);
  assert.equal(s.agreeing, false);
  assert.match(s.problems.join(" "), /no RESULT line|truncated/i);
});

test("a capture truncated by head -N loses the RESULT line AND the last rows together", () => {
  // This is the exact mechanism behind the 4. The cut is not detectable from the row count
  // alone - you cannot tell a short capture from a short run - so the tool has to say that the
  // verdict is missing rather than reporting a confident count.
  const cut = [row("PASS", "a"), row("PASS", "b"), row("FAIL", "c")].join("\n");
  const s = summarise(cut);
  assert.equal(s.agreeing, false, "a capture with no verdict must not read as a clean pass");
  assert.equal(s.resultCount, null, "and must not invent a count from the rows it does have");
});

test("a capture with no gates at all is not a green run", () => {
  const s = summarise("=== verify-all ===\nnothing ran\n");
  assert.equal(s.agreeing, false, "an empty capture must not be reported as consistent");
});

test("the RESULT line is matched only at the start of a line, not inside a row's detail", () => {
  // A harness whose DETAIL text happens to contain the word RESULT must not be counted as the
  // verdict - the same class as a grep that overcounts by matching prose.
  const decoy = [
    row("PASS", "harness_paths"),
    "    detail: RESULT: FAIL (99 hard gate(s) failed) appears in this text",
    row("FAIL", "real_one"),
    "RESULT: FAIL (1 hard gate(s) failed)",
  ].join("\n");
  const s = summarise(decoy);
  assert.equal(s.resultCount, 1, "the verdict is the line-anchored one, not the one inside a detail");
  assert.equal(s.counts.fail, 1);
  assert.equal(s.agreeing, true);
});
