#!/usr/bin/env node
// THE RED CONTROL FOR tools/verify-done-artifacts.mjs
//
// A gate that has never gone red is not a gate. The specimen is 87ab63 AS THE COORDINATOR CLOSED
// IT, quoted from the card's own proof - sound reasoning, a decision the owner actually made, and
// no reachable commit behind the work it names.
//
// The card has since been REOPENED, so this cannot be run against the live bus as a done card.
// The proof text is reproduced verbatim from the reopened card and is the specimen the card asked
// for. It must be REFUSED. If this suite passes 87ab63-as-closed, the verifier is measuring the
// wrong thing and must be reworked - exactly as the rig proxy was reworked when can_go_red=true
// turned out to be a false pass.
//
// Run: node tools/verify-done-artifacts.red-control.mjs   -> exits 1 when the gate is working.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { verifyCard } from "./verify-done-artifacts.mjs";

const GAME = process.argv[2] ? path.resolve(process.argv[2]) : process.cwd();

// VERBATIM from task_1790427588229_87ab63, the proof the coordinator closed it on.
const PROOF_87AB63 = `THE DECISION THIS CARD WAITED FOR WAS MADE, AND IT WAS MADE BY THE OWNER, NOT BY A LANE AND NOT BY ME. The owner said "so do it" and then "fix it" when asked whether the free-items screen should be built.
SUPERSEDED BY cf9448, which delivered the hideout surface and the insurance behaviour. inventory-ux reported it as two commits on agent/inventory-ux: e3c8256, the surface and routes, nine files, +442, and a7df50f, the end-to-end claim resolve, +126.
VERIFICATION GAP, stated rather than papered over. I could not confirm those files from the shared base checkout. The two commits are LOCAL AND UNPUSHED on agent/inventory-ux in the owning lane's worktree, so from where I sit they are a well-evidenced report and not an artifact I have read. I am therefore closing this card on the strength of the owner decision, which is sufficient on its own, and NOT on the strength of the delivery, which I have not independently verified.`;

const repos = { game: GAME, addon: path.join(GAME, "addons", "cabra.lat_shooters") };
const card = { id: "task_1790427588229_87ab63", status: "done", proof: PROOF_87AB63 };

const r = verifyCard(card, repos);
const defects = r.failures.map((f) => f.defect);

console.log(`specimen: 87ab63 as the coordinator closed it`);
console.log(`accepted: ${r.ok}`);
console.log(`defects reported:`);
for (const f of r.failures) console.log(`  - ${f.defect}: ${f.detail}`);

// The refusal must be for the RIGHT reasons, not merely any refusal. A gate that fails a
// well-evidenced card for an unrelated technicality teaches its reader to route around it.
// ONLY THE DEFECTS THAT ARE STILL TRUE TODAY. Two of the four checks cannot be demonstrated on
// this specimen any more, and saying so is part of the control rather than a shortfall in it:
//
//   e3c8256 and a7df50f were LOCAL AND UNPUSHED when the coordinator closed the card, and they are
//   ON MAIN today (verified: merge-base --is-ancestor is true for both). So "does not resolve" and
//   "closed on a local commit" were true at close time and are now moot. A control asserting them
//   would be asserting a fact about the past, and it would have to be deleted the moment the work
//   landed - which is a test that erodes itself. What survives is what the close got WRONG and
//   cannot be undone: it never named a repository, and it cited cf9448, which exists in no
//   checkout at all.
//
// That asymmetry is the finding. The defect that outlives the mistake is the unresolvable claim,
// not the unpushed one - and a gate built only from the session failures would have checked the
// push state and missed the missing commit.
const EXPECTED = [
  ["proof names no repository", "the commit was cited with no repository, so nothing could be resolved against one"],
  ["cited commit cannot be resolved", "cf9448 is cited as the superseding work and exists in no checkout the verifier can reach"],
];
let bad = 0;
for (const [defect, why] of EXPECTED) {
  const hit = defects.includes(defect);
  if (!hit) { bad++; console.log(`\nMISSING EXPECTED DEFECT: ${defect} (${why})`); }
}

// And the control on the control: a genuinely well-evidenced card MUST be accepted, or the gate is
// simply refusing everything and would be ignored within a day.
const good = verifyCard({
  id: "control", status: "done",
  proof: `landed in addon: at ${GAME} commit 69ebb9a on branch main, shipped: yes`,
}, repos);
console.log(`\npositive control (a resolvable on-main commit): accepted=${good.ok}`);
if (!good.ok) console.log(`  unexpected: ${good.failures.map((f) => f.defect).join("; ")}`);

const gateWorks = !r.ok && bad === 0 && good.ok;
console.log(`\nRED CONTROL: ${gateWorks ? "PASS - the gate refuses the known-bad card for the right reasons" : "FAIL - the gate is not measuring the right thing"}`);
process.exit(gateWorks ? 0 : 1);
