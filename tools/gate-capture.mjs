#!/usr/bin/env node
// RUN THE GATE AND REPORT IT, SO THAT NOBODY EVER TRANSCRIBES IT AGAIN.
//
// Three lanes reproduced the same defect tonight, each in their own reporting, and the gate itself
// was correct in all three cases:
//
//   ballistics   raw capture said RESULT 4 with six FAIL rows beside it; published "4"
//   verifier     raw aggregates re-derived clean (RESULT 7 = 7 rows); summary said "five" while
//                naming SIX rows
//   the gate     RESULT 7, seven FAIL rows, one run - it agrees with itself
//
// The instrument is not the problem. The TRANSCRIPTION is: a RESULT line carried forward beside rows
// from a different run, or a row count taken from one run and a number typed from another. Both are
// invisible - the paste looks perfectly plausible, and every lane here was cited for it.
//
// So the fix is not to be more careful. It is to stop doing the thing. Run the gate, keep the raw
// output, and derive BOTH numbers from that one file. A number you can only obtain by typing it is
// a number you can get wrong, and three of us proved that tonight independently.
//
// USAGE
//   node tools/gate-capture.mjs            # full gate, writes a capture and prints the summary
//   node tools/gate-capture.mjs --quick    # parse gate only
//   node tools/gate-capture.mjs --from FILE   # re-derive from an existing capture, running nothing
//
// The --from mode is the important one: given a capture, it re-derives both numbers and checks
// them against each other, so an inconsistent paste is caught rather than believed.

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const GATE = path.join(ROOT, "tools", "verify-all.mjs");

/**
 * Derive BOTH numbers from ONE capture, and say whether they agree.
 *
 * Every count here is a mechanical match against the file. Nothing is tallied by hand and nothing
 * is carried in from a previous run - that discipline is the entire point of this file, and it is
 * worth stating because the alternative is the defect three lanes just published.
 */
export function summarise(raw) {
  const resultLine = (raw.match(/^RESULT:.*$/m) || ["(no RESULT line)"])[0];
  const resultCount = (resultLine.match(/FAIL \((\d+) hard gate/) || [])[1];

  // Rows are matched from the capture's own leading spaces, which is how the gate prints them.
  const rows = [...raw.matchAll(/^ {2}(PASS|FAIL|WARN|SKIP)\s+(\S+)/gm)].map((m) => ({ status: m[1], name: m[2] }));
  const byStatus = (s) => rows.filter((r) => r.status === s).length;
  const failRows = byStatus("FAIL");

  const problems = [];
  if (resultCount === undefined) {
    problems.push('no RESULT line in the capture - the run may not have finished, or the output was truncated');
  } else if (Number(resultCount) !== failRows) {
    problems.push(
      `the RESULT line says ${resultCount} and the capture holds ${failRows} FAIL rows. ` +
      "These cannot both describe this run: the gate counts hardFails from the rows it prints, so " +
      "either the capture mixes two runs or rows were added by hand. Do not quote either number.",
    );
  }
  // The classic: a capture cut by head -N, which drops the RESULT line and the last rows together.
  if (resultCount !== undefined && failRows > 0 && !/^RESULT:/m.test(raw.slice(0, 4000)) && /RESULT:/.test(raw)) {
    problems.push("the RESULT line appears far from the top of the capture, so this looks truncated");
  }

  return {
    resultLine,
    resultCount: resultCount === undefined ? null : Number(resultCount),
    counts: { pass: byStatus("PASS"), fail: failRows, warn: byStatus("WARN"), skip: byStatus("SKIP") },
    failing: rows.filter((r) => r.status === "FAIL").map((r) => r.name),
    agreeing: problems.length === 0,
    problems,
  };
}

function main(argv) {
  const from = argv.indexOf("--from");
  if (from >= 0) {
    const file = argv[from + 1];
    if (!file) { console.error("Usage: node tools/gate-capture.mjs --from <file>"); return 2; }
    report(fs.readFileSync(file, "utf8"), file);
    return 0;
  }

  const quick = argv.includes("--quick");
  const args = [GATE, ...(quick ? ["--quick"] : [])];
  const outFile = path.join(ROOT, `gate-capture-${quick ? "quick" : "full"}-${process.pid}.txt`);
  console.log(`running: node ${path.relative(ROOT, GATE)}${quick ? " --quick" : ""}`);
  const r = spawnSync(process.execPath, args, { cwd: ROOT, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  const raw = `${r.stdout || ""}${r.stderr || ""}`;
  fs.writeFileSync(outFile, raw);
  console.log(`capture: ${path.relative(ROOT, outFile)}\n`);
  report(raw, outFile);
  return report(raw, outFile).agreeing ? 0 : 1;
}

function report(raw, file) {
  const s = summarise(raw);
  console.log("── reported from that one capture, not from memory ──");
  console.log(`  ${s.resultLine}`);
  console.log(`  rows in the capture: PASS ${s.counts.pass}  FAIL ${s.counts.fail}  WARN ${s.counts.warn}  SKIP ${s.counts.skip}`);
  if (s.failing.length) {
    console.log("  failing gates:");
    for (const n of s.failing) console.log(`    - ${n}`);
  }
  console.log("");
  if (s.agreeing) {
    console.log("  CONSISTENT: the RESULT line and the row list describe the same run.");
    console.log("  Quote the numbers above, or re-run with --from. Do not retype either.");
  } else {
    console.log("  INCONSISTENT - do not quote any number from this capture:");
    for (const p of s.problems) console.log(`    ! ${p}`);
  }
  return s;
}

if (import.meta.url === `file://${process.argv[1]}`) process.exit(main(process.argv.slice(2)));
