#!/usr/bin/env node
// DO-DONE ARTIFACTS GATE
//
// A card is done when a worktree, a branch and a commit exist. This makes that bar MECHANICAL,
// because the failure it prevents is a well-reasoned close: a rule that lives in prose is
// defeated by the same reasoning that breaks it.
//
// It answers exactly one question - does this artifact exist - and it is allowed to be wrong in
// exactly one direction: refusing a card it should have accepted. A false refusal costs one card
// a second look. A false pass lets an unbuilt feature be reported as shipped, which is the
// failure that made the bar necessary.
//
// It does not merge, does not resolve conflicts, does not judge whether a commit is good, and
// decides nothing about a feature. It resolves SHAs.
//
// Exit 0 when every done card passes. Exit 1 when any done card fails. The failure report is the
// product: a list of done cards whose evidence does not resolve.

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const REPO_ROOT = process.argv[2] ? path.resolve(process.argv[2]) : process.cwd();
const AM_ROOT = process.env.AM_ROOT || path.join(REPO_ROOT, ".agent-mail");

// A proof must NAME its repository. "game:" or "addon:". The prefix is not decoration: a SHA is
// only meaningful against a repository, and the session's central evidence failure was a commit
// reported against a checkout nobody could see. Requiring the prefix makes "which repo" part of
// the claim instead of something the verifier guesses.
const REPO_PREFIX = /\b(game|addon):\s*([^\s,;]+)/gi;
// 6 characters, not 7, because git permits 6 and cf9448 in the red-control specimen is one. At 7
// alone the verifier silently skipped a SHA that exists nowhere. The lookarounds keep a token from
// being half of an identifier: without them f0f289, out of task_1790536717287_f0f289, reads as a
// commit. A SHA is a STANDALONE token.
const SHA_RE = /(?<![A-Za-z0-9_-])([0-9a-f]{6,40})(?![A-Za-z0-9_-])/g;
// Evidence that is a report rather than an artifact. Listed so the refusal says WHY, not just
// that a card failed - a gate that cannot explain itself gets ignored, which is worse than none.
const NARRATIVE_ONLY = [
  /\bno commit\b/i, /\bnarrative\b/i, /\bon the strength of\b/i, /\bnot (?:independently )?verified\b/i,
  /\breport(?:ed)?\b/i, /\bpromis(?:e|ed)\b/i, /\bgreen (?:gate|pin|test)\b/i,
];
// THE CONVENTION IS NEW, and that is the whole reason the live run is red without this line.
// `game:` / `addon:` was specified in card f0f289 at 19:18Z on 2026-09-27, and this line is the
// MINUTE it was specified - not midnight, which would hold 19 hours of cards to a rule that did
// not exist when they were written. A gate that measures when a card was written is measuring the
// wrong thing, and picking midnight because it is a rounder number is exactly that mistake with a
// tidier justification. No card written before that could satisfy it,
// so requiring it of them measures WHEN A CARD WAS WRITTEN, not whether its evidence resolves.
// That is a named, reviewed boundary and not amnesty: a card written after this instant is held
// to the full bar, and a legacy card is still COUNTED and NAMED in the report.
const CONVENTION_FROM = "2026-09-27T19:18:00.000Z";

const LOCAL_UNPUSHED = /local(?:ly)?\s+and\s+unpushed|unpushed|local only|not pushed/i;

/** A git fact, or null. Never throws: an unresolvable repo is a refusal, not a crash. */
function git(repoDir, args) {
  try {
    return execFileSync("git", args, { cwd: repoDir, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
  } catch {
    return null;
  }
}

function readCards(amRoot = AM_ROOT) {
  const bus = path.join(amRoot, "bus");
  if (!fs.existsSync(bus)) return [];
  const out = [];
  for (const stage of fs.readdirSync(bus)) {
    const dir = path.join(bus, stage);
    if (!fs.statSync(dir).isDirectory()) continue;
    for (const f of fs.readdirSync(dir)) {
      if (!f.endsWith(".md")) continue;
      const text = fs.readFileSync(path.join(dir, f), "utf8");
      const m = text.match(/^---\n([\s\S]*?)\n---/);
      if (!m) continue;
      // The board frontmatter is YAML-STYLE `key: value`, not JSON. JSON.parse threw on every
      // card and the scan silently reported 0 of 484 - a gate that measures nothing while
      // reporting a clean result is the exact failure this project keeps paying for.
      const meta = {};
      for (const line of m[1].split("\n")) {
        const kv = line.match(/^([a-z_]+):\s*(.*)$/);
        if (!kv) continue;
        let v = kv[2].trim();
        if ((v.startsWith("\"") && v.endsWith("\"")) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
        if (v === "null" || v === "~" || v === "") v = null;
        meta[kv[1]] = v;
      }
      if (!meta.id) continue;
      out.push({ stage, text, ...meta });
    }
  }
  return out;
}

const shaExists = (repoDir, sha) => git(repoDir, ["cat-file", "-e", `${sha}^{commit}`]) !== null || (() => {
  try { execFileSync("git", ["cat-file", "-e", `${sha}^{commit}`], { cwd: repoDir, stdio: "ignore" }); return true; } catch { return false; }
})();

/**
 * Verify one done card. Returns { ok, failures[] }.
 *
 * Each failure names the DEFECT it corresponds to, because this gate was built from four real
 * ones and a reader who cannot tell which one fired will assume it is noise.
 */
/**
 * IS THE COMMIT ACTUALLY SHIPPED? Returns "yes" | "no" | "unknown".
 *
 * THE GAP THIS CLOSES. Resolving a SHA and finding its branch is NOT delivery. On 2026-09-27
 * thirteen commits sat on local main, the owner main-menu fix among them, and every check available
 * passed: the SHA resolved, the branch existed, the diff was non-empty, the tree was correct. The
 * feature was in no other clone.
 *
 * "unknown" IS A REAL ANSWER, not a shrug. A verifier that cannot read the remote has no evidence
 * either way and must NOT pass by default: a check that reports "fine" because it could not look
 * is believed, and belief is what makes an instrument dangerous.
 *
 * The boundary is a REMOTE ref read through ls-remote, never a local ref. A branch that tracks
 * nothing is a commit that exists, not one that ships.
 */
export function shippedState(repoDir, sha) {
  if (!fs.existsSync(repoDir)) return { state: "unknown", detail: "repository is not present here" };
  const remoteUrl = git(repoDir, ["config", "--get", "remote.origin.url"]);
  if (!remoteUrl) return { state: "unknown", detail: "no origin remote is configured" };

  let tips;
  try {
    tips = execFileSync("git", ["ls-remote", "origin"], { cwd: repoDir, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  } catch {
    return { state: "unknown", detail: "the remote could not be read, so shipping is unknown - NOT a pass" };
  }

  const remoteRefs = new Map();
  for (const line of tips.split("\n")) {
    const [sha2, ref] = line.trim().split(/\s+/);
    if (!sha2 || !ref || ref === "HEAD") continue;
    remoteRefs.set(ref.replace(/^refs\/remotes\//, "").replace(/^refs\/heads\//, ""), sha2);
  }
  if (remoteRefs.size === 0) return { state: "unknown", detail: "the remote reported no refs" };

  // A remote-tracking ref is evidence ONLY if it matches what the remote reports NOW. A tracking
  // ref that lags answers a question about the past, and answering a past question is exactly how
  // this check would go green on an unpushed commit.
  const isFresh = (name, tipSha) => git(repoDir, ["rev-parse", "--verify", `refs/remotes/origin/${name}`]) === tipSha;
  if (![...remoteRefs].some(([n, t]) => isFresh(n, t))) {
    try {
      execFileSync("git", ["fetch", "--quiet", "origin"], { cwd: repoDir, stdio: "ignore" });
    } catch {
      return { state: "unknown", detail: "no fresh remote-tracking ref and the fetch failed" };
    }
  }

  // PROBE ONLY THE REMOTE-TRACKING NAMESPACE. The first version also probed the BARE ref name,
  // which resolved to the LOCAL branch: thirteen unpushed commits came back as "reachable from the
  // remote ref main" and the control went green on the exact failure it exists to catch. The bare
  // name is the local line of work; the tracking name is the remote. Conflating them is the bug.
  for (const [name, tipSha] of remoteRefs) {
    if (!isFresh(name, tipSha)) continue;
    try {
      execFileSync("git", ["merge-base", "--is-ancestor", sha, `refs/remotes/origin/${name}`], { cwd: repoDir, stdio: "ignore" });
      return { state: "yes", detail: `reachable from the remote ref origin/${name}` };
    } catch { /* not an ancestor of this remote ref; try the next */ }
  }
  const names = [...remoteRefs.keys()];
  return {
    state: "no",
    detail: `the commit resolves locally but is behind every remote ref (${names.slice(0, 5).join(", ")}${names.length > 5 ? `, and ${names.length - 5} more` : ""})`,
  };
}

export function verifyCard(card, repos, knownIds = new Set()) {
  const failures = [];
  const proof = typeof card.proof === "string" ? card.proof : "";
  // DELIVERY IS AN EXPLICIT TOKEN, NOT A KEYWORD. An earlier version asked whether the proof
  // contained "merged" or "shipped", and it failed this project own proof - which discusses what
  // shipped and unbuilt means and states merged=false - for claiming to have shipped something.
  // That is a gate failing an honest proof for using a word, and the fix is worse than the bug: it
  // teaches authors to write less evidence. Keyword matching cannot tell a CLAIM from a
  // DISCUSSION, so the claim is now stated. A done card says "shipped: yes" or "shipped: no".
  const claimMatch = proof.match(/\bshipped\s*[:=]\s*\**\s*(yes|no|true|false)\b/i);
  const shippedClaim = claimMatch ? /^(yes|true)$/i.test(claimMatch[1]) : null;
  // A card is cited by the six-to-eight character tail of its id. Those tails are all-hex and the
  // right length, so 87ab63 standing alone in a sentence is indistinguishable from a short SHA by
  // shape. Only the bus knows which names are cards, so the bus is asked.
  const selfTail = String(card.id || "").match(/([0-9a-f]{6,8})$/i);
  if (selfTail) knownIds.add(selfTail[1]);
  if (card.id) knownIds.add(String(card.id));
  const where = card.id;

  if (!proof.trim()) {
    failures.push({ defect: "no evidence at all", detail: "the card is done and carries no proof" });
    return { ok: false, failures };
  }

  // (1) THE REPOSITORY MUST BE NAMED. A SHA with no repository is the 0ea763a failure: a commit
  // reported against a checkout nobody could reach.
  const named = [...proof.matchAll(REPO_PREFIX)].map((m) => ({ kind: m[1].toLowerCase(), value: m[2] }));
  if (named.length === 0) {
    failures.push({
      defect: "proof names no repository",
      detail: "a commit is only meaningful against a repository; the proof must say `game:` or `addon:`",
    });
  }

  // (2) NARRATIVE EVIDENCE IS NOT AN ARTIFACT. Named first because it is the most common way a
  // sound close ends up with nothing behind it.
  const narrative = NARRATIVE_ONLY.filter((re) => re.test(proof)).map((re) => re.source);
  const shas = (proof.match(SHA_RE) || []).filter((s) => !/^(game|addon)$/i.test(s) && !knownIds.has(s));

  if (shas.length === 0) {
    failures.push({
      defect: "evidence is narrative, not an artifact",
      detail: `no commit SHA appears in the proof${narrative.length ? `; it reads as a report (${narrative.slice(0, 2).join(", ")})` : ""}`,
    });
    return { ok: false, failures };
  }

  // (3) EVERY CITED SHA MUST RESOLVE in the repository it is cited against, and the branch must
  // still exist. Resolved by rev-parse in the repo - by the card's word is the failure.
  let resolvedAny = false;
  const namedBranchesHere = [];
  for (const sha of shas) {
    let checked = false;
    for (const n of named.length ? named : [{ kind: "game", value: "" }]) {
      const dir = repos[n.kind];
      if (!dir) continue;
      if (shaExists(dir, sha)) {
        checked = true; resolvedAny = true;
        // (5) A COMMIT CLAIMED AS ON-MAIN MUST BE AN ANCESTOR OF MAIN, or a side-branch commit
        // passes as shipped.
        // Only an EXPLICIT "shipped: yes" demands the remote boundary. A card that says
        // "shipped: no" has told the truth about a local commit and is not penalised for it: the
        // failure this check exists to catch is a card REPORTING delivery that did not happen, not
        // a card declining to claim one. The on-main ancestor test it replaces was necessary but
        // not sufficient - a resolvable local commit passes it every time.
        if (shippedClaim === true) {
          const ship = shippedState(dir, sha);
          if (ship.state === "no") {
            failures.push({ defect: "commit resolves locally but is not on any remote", detail: `${sha}: ${ship.detail} - a commit that exists is not a commit that ships` });
          } else if (ship.state === "unknown") {
            failures.push({ defect: "shipping could not be established", detail: `${sha}: ${ship.detail}` });
          }
        }        // THE BRANCHES ARE COLLECTED FIRST, because the fraction check below needs them and
        // the existence check that used to gather them runs after it. On the first attempt the
        // list was still empty when the check read it, so the check passed everything - the same
        // failure shape as a check that cannot fail.
        namedBranchesHere.length = 0;
        for (const m of proof.matchAll(/\b(?:branch|on)\s+(?:branch\s+)?([A-Za-z0-9._-]+(?:\/[A-Za-z0-9._/-]+)?)/g)) {
          const ref = m[1];
          // TWO BUGS WERE LIVE HERE AT ONCE, and both made a check inert rather than wrong.
          // The pattern matched the words "on branch" and captured the word "branch" as the ref
          // name, so "on branch main" yielded a ref called "branch" and main was never read - the
          // branch-existence check had been passing everything. And the first version required a
          // slash, which also excluded "main", the most common branch name there is.
          //
          // THE REPOSITORY DECIDES WHAT A BRANCH IS, NOT THE SHAPE OF THE WORD. A bare word is a
          // branch if refs/heads/<word> exists and prose if it does not, so "it" and "surface"
          // stay prose without a shape rule, and "main" is a branch.
          if (!git(dir, ["rev-parse", "--verify", `refs/heads/${ref}`])
            && !git(dir, ["rev-parse", "--verify", `refs/remotes/origin/${ref}`])) continue;
          namedBranchesHere.push(ref);
        }

        // THE FRACTION CHECK, and it is the gap the coordinator named with 87ab63 as its first
        // live specimen. A card cites ONE commit. Its branch may hold two more that were never
        // named, and the gate confirms exactly the citation, so both the author and the gate are
        // honest while the work is half done. inventory-ux reported 4f96c64 as the durable half
        // of a done card whose cited commits were already pushed.
        //
        // So the BRANCH TIP must be on a remote, not merely the cited SHA. A cited commit that is
        // pushed while its branch tip is not means the card named the part that happened to
        // travel.
        if (shippedClaim === true) {
          for (const ref of namedBranchesHere) {
            const tip = git(dir, ["rev-parse", "--verify", `refs/heads/${ref}`]) || git(dir, ["rev-parse", "--verify", `refs/remotes/origin/${ref}`]);
            if (!tip) continue;                       // existence is the branch check's job
            const tipShip = shippedState(dir, tip);
            if (tipShip.state !== "yes") {
              failures.push({
                defect: "the named branch has commits that are on no remote",
                detail: `${ref} points at ${tip.slice(0, 8)} and it is ${tipShip.state} - a card names one commit, and a branch can hold more than the card named`,
              });
            }
          }
        }

        // (4) A BRANCH NAMED ALONGSIDE MUST STILL EXIST - but ONLY a branch the proof
        // actually names as one. My first version scraped a token from anywhere near the SHA and
        // reported "named branch no longer exists: it" and ": surface" - English words read as
        // branch names, and the red control caught it refusing a WELL-EVIDENCED card over a
        // technicality. A gate that fails correct work for a wrong reason gets routed around
        // within a day, so the check is narrow: an explicit "branch <ref>" or "on <ref>", and
        // only a ref-shaped token.
        for (const ref of namedBranchesHere) {
          if (git(dir, ["rev-parse", "--verify", `refs/heads/${ref}`])) continue;
          if (git(dir, ["rev-parse", "--verify", `refs/remotes/origin/${ref}`])) continue;
          failures.push({ defect: "named branch no longer exists", detail: `${ref} (cited alongside ${sha})` });
        }
      }
    }
    if (!checked) {
      failures.push({
        defect: named.length ? "cited commit does not resolve" : "cited commit cannot be resolved",
        detail: named.length
          ? `${sha} is not a commit in ${named.map((n) => n.kind).join("/")}`
          : `${sha} is cited with no repository, so there is nowhere to resolve it - a commit is only meaningful against a repository`,
      });
    }
  }

  // (6) A CARD CLOSED ON A LOCAL, UNPUSHED COMMIT REPORTS A FEATURE NOBODY CAN PULL. This is not
  // a failure of the evidence - the work may be real - but it is a failure of the CLAIM, and the
  // verifier is allowed to refuse in exactly this direction.
  if (LOCAL_UNPUSHED.test(proof)) {
    if (!resolvedAny) {
      failures.push({
        defect: "closed on a local and unpushed commit",
        detail: "the proof says the work is local and unpushed, so it reports a feature nobody can pull",
      });
    }
  }

  // A done card must SAY whether it shipped. Silence is not a pass: thirteen commits were local
  // tonight and every card behind them looked fine to any check that did not ask the question.
  if (shippedClaim === null) {
    failures.push({ defect: "no shipping claim", detail: 'the proof must state "shipped: yes" or "shipped: no"' });
  }

  return { ok: failures.length === 0, failures };
}

export function verifyAll(repoRoot = REPO_ROOT, amRoot = AM_ROOT) {
  const repos = {
    game: repoRoot,
    addon: path.join(repoRoot, "addons", "cabra.lat_shooters"),
  };
  const done = readCards(amRoot).filter((c) => String(c.status || "").replace(/-/g, "_") === "done");
  // LEGACY IS NOT A VIOLATION. 160 of the done cards predate the proof field and carry none at
  // all. Failing them permanently is how a checker gets ignored: the gate would be red before
  // anyone shipped anything, so the next real failure would be dismissed as noise from "the old
  // ones". They are counted and named, and they do not fail the run. Only a card that CLAIMS
  // evidence and cannot produce it is a violation - which is the asymmetry that matters.
  // No proof field at all: the card predates proof being a thing. Reported, never failed.
  const legacy = done.filter((c) => !("proof" in c) || c.proof === null || c.proof === "");
  // Carries a proof, but written before the `game:`/`addon:` convention existed. Reported, never
  // failed. This is the line that stops the gate measuring WHEN A CARD WAS WRITTEN.
  const inPlace = (c) => Date.parse(c.created || 0) >= Date.parse(CONVENTION_FROM);
  const legacyShaped = done.filter((c) => !legacy.includes(c) && !inPlace(c));
  const evaluated = done.filter((c) => !legacy.includes(c) && inPlace(c));
  // Every id the bus knows, so a card tail in a proof is never read as a commit.
  const knownIds = new Set();
  for (const c of done) {
    const m = String(c.id || "").match(/([0-9a-f]{6,8})$/i);
    if (m) knownIds.add(m[1]);
  }
  const results = evaluated.map((c) => ({ id: c.id, ...verifyCard(c, repos, knownIds) }));
  return {
    scanned: done.length,
    evaluatedCount: evaluated.length,
    legacy: legacy.length + legacyShaped.length,
    legacyIds: [...legacy, ...legacyShaped].map((c) => c.id),
    passed: results.filter((r) => r.ok).length,
    failed: results.filter((r) => !r.ok),
  };
}


if (import.meta.url === `file://${process.argv[1]}`) {
  const { scanned, evaluatedCount, legacy, passed, failed } = verifyAll(REPO_ROOT, AM_ROOT);
  console.log(`done cards scanned: ${scanned}`);
  console.log(`evaluated (carry a proof, written under the convention): ${evaluatedCount}`);
  console.log(`legacy (no proof field, reported NOT failed): ${legacy}`);
  console.log(`passed: ${passed}`);
  console.log(`FAILED: ${failed.length}`);
  for (const f of failed) {
    console.log(`\n  ${f.id}`);
    for (const x of f.failures) console.log(`    - ${x.defect}: ${x.detail}`);
  }
  process.exit(failed.length ? 1 : 0);
}
