import test, { describe } from "node:test";
import assert from "node:assert/strict";
import {
  attentionDue, recordAttention, episodeKey, nextIntervalMs,
  ALERT_INITIAL_INTERVAL_MS, ATTENTION_REPEAT_MIN_MS,
} from "./episode-alert.mjs";

/**
 * The arms, written against the module rather than against the bridge, because the bridge has no
 * test at all - "THERE IS CURRENTLY NO ASSERTION AT ALL in the bridge beyond --dry-run, so the
 * test has to be written, and a test that is written after the change rather than before it is how
 * tonight's false greens happened."
 *
 * Time is always passed in. Nothing here can pass because a real clock moved favourably.
 */

// ─── the model this replaces, so the arms can be shown RED against it ───────────

/**
 * The shipped behaviour: a set of delivered message ids.
 *
 * Reproduced faithfully because the first arm has to be red against it, and the only honest way
 * to get a red arm is to run the real old logic rather than a strawman.
 */
function oldShouldAlert(deliveredIds, messageId) {
  return !deliveredIds.has(messageId);
}

describe("red arm: the delivered-ids set the bridge uses today", () => {
  test("it CANNOT re-raise, so a blocked peer that is never answered goes silent", () => {
    // This is the failure the card exists to fix, stated as a property of the current code.
    // The set can express "already delivered" and nothing else; there is no interval, no nextAt,
    // and no memory that a page ever happened. A lane that blocks, alerts once, and is never
    // heard from again is the SILENT-BLOCK FAILURE, and it is what an over-aggressive dedupe
    // produces. The episode model re-raises forever at a floor; this model raises exactly once.
    const delivered = new Set();
    assert.equal(oldShouldAlert(delivered, "m1"), true, "first alert fires");
    delivered.add("m1");
    assert.equal(oldShouldAlert(delivered, "m1"), false);
    // And it stays false for a year. There is no third state to express.
    assert.equal(oldShouldAlert(delivered, "m1"), false);
    assert.equal(delivered.size, 1, "the entire memory of this card is one boolean");
  });

  test("keying on the message id restarts the alert from scratch on every new message", () => {
    // The LOUD failure, deliberately included because loud failures get found. Each new message
    // is a new id, so each re-alerts at full volume: we manufacture the storm the bridge exists
    // to prevent. Episodes are keyed on the run instead, so one blocked spell is one alert.
    const delivered = new Set(["m1", "m2", "m3"]);
    let alerts = 0;
    for (const id of ["m1", "m2", "m3", "m4"]) if (oldShouldAlert(delivered, id)) alerts++;
    assert.equal(alerts, 1, "the old model re-alerts per message - that is the storm");

    let eps = {};
    for (let i = 0; i < 4; i++) {
      const k = episodeKey("npc-body", "blocked");
      const due = attentionDue(eps, k, i * 1000);
      if (due.alert) { alerts--; eps = recordAttention(eps, k, i * 1000, due.intervalMs); }
    }
    assert.equal(alerts, 0, "one blocked spell, however many messages, is one alert");
  });
});

describe("arm one: two consecutive alert windows for ONE episode produce ONE delivery", () => {
  const key = episodeKey("npc-body", "blocked");

  test("a first sighting always alerts", () => {
    const due = attentionDue({}, key, 0);
    assert.equal(due.alert, true);
    assert.equal(due.first, true);
  });

  test("a second window inside the interval does NOT re-alert", () => {
    let eps = recordAttention({}, key, 0, ALERT_INITIAL_INTERVAL_MS);
    // the stored interval is the HALVED one, so "inside" means inside nextAt, not the initial
    const due = attentionDue(eps, key, eps[key].nextAt - 1);
    assert.equal(due.alert, false, "still inside the interval");
  });

  test("a window AFTER the interval DOES re-alert - once, not never", () => {
    let eps = recordAttention({}, key, 0, ALERT_INITIAL_INTERVAL_MS);
    const due = attentionDue(eps, key, eps[key].nextAt);
    assert.equal(due.alert, true, "the floor's whole purpose: a still-blocked peer stays audible");
  });
});

describe("arm two: three DISTINCT episodes produce three deliveries", () => {
  test("different blocked peers are different episodes", () => {
    const a = episodeKey("npc-body", "blocked");
    const b = episodeKey("verifier", "blocked");
    assert.notEqual(a, b);
    let eps = {};
    let fired = 0;
    for (const k of [a, b, episodeKey("ballistics", "blocked")]) {
      const due = attentionDue(eps, k, 0);
      if (due.alert) { fired++; eps = recordAttention(eps, k, 0, due.intervalMs); }
    }
    assert.equal(fired, 3, "three episodes, three alerts - no cross-episode suppression");
  });

  test("THE COARSE ARM, the quiet one: a re-block after an answer is a NEW episode", () => {
    // The failure this must prevent: a peer blocks on card A, is answered, blocks on card B, and
    // the human is never told about B because a too-coarse key merged the two spells. Each spell
    // is a different run, so a run-keyed episode cannot merge them.
    const first = episodeKey("npc-body", "blocked", "run-A");
    const second = episodeKey("npc-body", "blocked", "run-B");
    assert.notEqual(first, second, "two different blocked spells are two episodes");

    let eps = {};
    let fired = 0;
    for (const k of [first, second]) {
      const due = attentionDue(eps, k, 0);
      if (due.alert) { fired++; eps = recordAttention(eps, k, 0, due.intervalMs); }
    }
    assert.equal(fired, 2, "B must alert, or a human never hears about it");
  });
});

describe("the floor, which is the acceptance and not a detail", () => {
  test("the interval HALVES on each re-raise", () => {
    assert.equal(nextIntervalMs(ALERT_INITIAL_INTERVAL_MS), ALERT_INITIAL_INTERVAL_MS / 2);
  });

  test("and then STOPS at the floor, never below", () => {
    let i = ALERT_INITIAL_INTERVAL_MS;
    const seen = [];
    for (let n = 0; n < 12; n++) { i = nextIntervalMs(i); seen.push(i); }
    assert.equal(i, ATTENTION_REPEAT_MIN_MS, "one hour, and no further");
    assert.ok(seen.every((v) => v >= ATTENTION_REPEAT_MIN_MS),
      `every interval stays at or above the floor, saw ${seen.join(", ")}`);
    assert.ok(seen[seen.length - 1] === ATTENTION_REPEAT_MIN_MS);
  });

  test("a lane blocked for a day is still alerted on, because the floor never silences it", () => {
    const key = episodeKey("npc-body", "blocked");
    let eps = {};
    let now = 0, alerts = 0;
    // 24 hours of hourly ticks.
    for (let t = 0; t < 24; t++) {
      now = t * 60 * 60 * 1000;
      const due = attentionDue(eps, key, now);
      if (due.alert) { alerts++; eps = recordAttention(eps, key, now, due.intervalMs); }
    }
    assert.ok(alerts >= 20, `expected roughly hourly alerts across a day, got ${alerts}`);
    assert.ok(alerts <= 24, "and not more than the number of windows - the backoff is real");
  });
});

describe("state hygiene", () => {
  test("recordAttention does not mutate its input", () => {
    const key = episodeKey("npc-body", "blocked");
    const before = {};
    const after = recordAttention(before, key, 0, ALERT_INITIAL_INTERVAL_MS);
    assert.deepEqual(before, {}, "a caller holding the old state must not be surprised");
    assert.ok(after[key]);
  });

  test("an unknown episode is NOT suppressed by a lingering record for a different one", () => {
    let eps = recordAttention({}, episodeKey("npc-body", "blocked"), 0, ALERT_INITIAL_INTERVAL_MS);
    const due = attentionDue(eps, episodeKey("verifier", "blocked"), 0);
    assert.equal(due.alert, true, "a brand new blocked peer is never silenced by someone else");
  });
});
