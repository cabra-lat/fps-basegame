/**
 * Episode-keyed blocked alerts: one alert per EPISODE, with a halving backoff and a floor.
 *
 * WHY THIS REPLACES A SET OF DELIVERED IDS. The bridge kept a set of delivered message ids,
 * which is effectively a single boolean: once an id has been delivered the bridge has nothing
 * left to say. That set cannot express the only case a human needs to see - a blocked peer that
 * is STILL blocked and that nobody came back to. Tonight that produced three blocked_oldest
 * pages on one card whose blocker is a human approval, with no memory that it had already paged,
 * and then a second card the same way. So the defect was a repeat, and the fix that looks obvious
 * - dedupe harder - is what caused it.
 *
 * THE FLOOR IS THE PART THAT MUST NOT BE DROPPED, and it is the reason this is a module rather
 * than a two-line change. A dedupe that is too aggressive means a lane blocks, alerts once, and is
 * never heard from again. That is the SILENT-BLOCK FAILURE OUR PROTOCOL EXISTS TO PREVENT,
 * INTRODUCED BY THE FIX FOR THE NOISY-BLOCK FAILURE. So the interval halves on each re-raise and
 * stops at ATTENTION_REPEAT_MIN_MS. Removing the floor does not make alerting better; it makes
 * the worst outcome more likely while being described as an improvement.
 *
 * WHY THE EPISODE KEY IS `blocked:<runId>` AND NOT A MESSAGE ID. Keying on the message id means a
 * peer that keeps re-blocking after a NEW message re-alerts from scratch every time, and we
 * manufacture the storm the bridge exists to prevent. The loud failure - it would be found.
 *
 * AND WHY THE KEY IS NOT COARSER THAN THE RUN. The quiet failure is the one that matters: a key
 * too coarse merges two genuinely different blocked episodes, a peer blocks on card A, is
 * answered, blocks on card B, and the human is never told about B. A per-RUN key does not merge
 * those, because re-blocking after an answer is a new run. The coarse arm is the easy one to
 * forget, so it is asserted here explicitly.
 *
 * Pure state and pure functions only. No I/O, no clock - `now` is always passed in, so the tests
 * cannot pass because a real clock moved favourably.
 */

// The initial interval must be at least twice the floor or it can never halve into it, and the
// halving would be dead code. An earlier version of this file used 15m against a 1h floor, which
// meant the first `nextIntervalMs` call jumped STRAIGHT to the floor and the backoff never
// happened - caught by the arm that asserts the interval halves, not by reading the constants.
export const ALERT_INITIAL_INTERVAL_MS = 4 * 60 * 60 * 1000; // first repeat after 4h
export const ATTENTION_REPEAT_MIN_MS = 60 * 60 * 1000; // floor: never quieter than 1h

/**
 * The episode key for a blocked run. Deliberately names the state, not the message: several
 * messages can arrive during one blocked spell and they are ONE episode, and one alert.
 */
export function episodeKey(handle, state, runId) {
  // The run/episode discriminator is part of the key, and it is what makes a re-block AFTER an
  // answer a new episode rather than a continuation. Without it, a key of (handle, state) is
  // exactly the too-coarse key the card warns about: a peer blocks on A, is answered, blocks on B,
  // and the human never hears about B because both spells share one key.
  return `blocked:${handle}:${state}${runId ? `:${runId}` : ""}`;
}

/**
 * Halve the interval, floored. The floor is the whole safety property, so it is applied here and
 * nowhere else - a caller cannot accidentally re-raise at 7 seconds by computing its own interval.
 */
export function nextIntervalMs(previous) {
  const halved = Math.floor(previous / 2);
  return Math.max(ATTENTION_REPEAT_MIN_MS, halved);
}

/**
 * Should this episode be alerted now?
 *
 * Returns { alert: true, intervalMs, nextAt } when the episode is due, and { alert: false } when
 * it is not. A FIRST sighting always alerts, whatever the stored state says: an episode with no
 * record is new, and suppressing a new blocked peer because an old record lingers is exactly the
 * silent-block failure.
 */
export function attentionDue(episodes, key, now) {
  const rec = episodes[key];
  if (!rec) return { alert: true, first: true, intervalMs: ALERT_INITIAL_INTERVAL_MS };
  if (now >= rec.nextAt) return { alert: true, first: false, intervalMs: rec.intervalMs };
  return { alert: false, nextAt: rec.nextAt };
}

/**
 * Record that an episode was alerted, halving the interval for next time.
 *
 * Returns a NEW state object rather than mutating, so a caller holding the old state cannot be
 * surprised by it, and so a test can compare before/after without ordering assumptions.
 */
export function recordAttention(episodes, key, now, previousIntervalMs) {
  const prior = episodes[key]?.intervalMs;
  const base = prior ?? previousIntervalMs ?? ALERT_INITIAL_INTERVAL_MS;
  const interval = nextIntervalMs(base);
  return {
    ...episodes,
    [key]: { nextAt: now + interval, intervalMs: interval, alertedAt: now },
  };
}
