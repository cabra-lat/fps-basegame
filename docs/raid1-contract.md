# RAID-1 contract evidence

RAID-1 is a bounded first-clear collect-and-extract scenario for the existing
arena: three existing bots, a 600-second timer, one public **Marked Intel**
pickup, and two visible destinations.

- **Open Lane** is always open.
- **Signal Gate** is visibly gated by Marked Intel and is available during the
  120–540 second window.
- A successful extraction keeps only the marked objective in the raid backpack.
- Falling back without the objective, timing out, or dying fails the scenario;
  the existing MetaService resolution discards raid loot and forfeitures the
  deployed kit.

## Product decision: Option A — TARGET / UNIMPLEMENTED IN e9883e6

The coordinator selected Option A: preserve the 600-second / 8–12 minute
RAID-1 scenario and add a distinct scenario-clear outcome. The ordinary
`RUN_THROUGH` rule remains unchanged for non-RAID-1 raids.

This is the acceptance target that was missing from `e9883e6`; it is not a
claim that the first candidate commit implemented the behavior. The historical
`e9883e6` gaps were:

- `Raid.Outcome.SCENARIO_CLEARED` did not exist.
- RAID-1 still used generic `Raid.extract()`, so a 600-second clear was
  classified by the ordinary `RUN_THROUGH`/`SURVIVED` thresholds.
- The fallback could terminate through generic extraction while the scenario
  remained ACTIVE when Marked Intel was missing.
- MetaService settlement, progression, and result HUD had no distinct
  scenario-clear outcome handling.

### Follow-up status

`a9c6031` is **PARTIAL/BLOCKED**, not implementation-complete. It added the
named outcome and settlement plumbing, but its fallback routing still allowed
the always-open point to reach generic success without the objective. The
isolated scenario probe reported 17/17 because it manually called
`scenario.fail()`; it did not drive the production `_on_extracted` callback.
That production routing was therefore untested/broken at the `a9c6031` gate.

The corrected target requires the real `_on_extracted` callback to test
`objective_collected` first, call `scenario.fail()` and discard carry, and end
`LEFT_BEHIND` before any success settlement. A focused regression must invoke
that callback rather than manually invoking the failure method. The later
`35d4326` follow-up is the scoped routing correction under QA review.

### Named outcome

`Raid.Outcome.SCENARIO_CLEARED` is the finite outcome for a successful RAID-1
extraction. It is distinct from both `RUN_THROUGH` and the generic `SURVIVED`
result, so a 600-second first clear cannot be misclassified by the existing
`<420s AND EXP<200` rule.

### Integration contract

- Add a RAID-1-specific completion path (for example,
  `Raid.complete_scenario(point)`) that emits the same extraction event and
  ends with `SCENARIO_CLEARED`. Generic `Raid.extract(point)` must retain its
  current `RUN_THROUGH`/`SURVIVED` behavior.
- `MetaService.resolve_raid()` treats `SCENARIO_CLEARED` as a successful raid
  for persistence and settlement, but reports the distinct outcome and banks
  only the marked objective already filtered by the RAID-1 backpack contract.
  The scenario-clear settlement uses the normal survival reward; it does not
  silently become a RUN THROUGH reward.
- Progression counts scenario completion as a successful extraction and keeps
  the exact outcome available to quests. Consumers must not infer RUN THROUGH
  from elapsed time or EXP.
- Result HUD/feed text uses `SCENARIO CLEARED` (or the product-approved display
  spelling) rather than `SURVIVED` or `RUN THROUGH`.
- Regression tests must cover: 600-second RAID-1 clear → `SCENARIO_CLEARED`,
  ordinary fast/low-EXP extraction → `RUN_THROUGH`, ordinary slow/high-EXP
  extraction → `SURVIVED`, and failure → existing discard/kit-forfeiture path.

This is an integration contract, not a request to alter the already-landed
candidate's generic raid thresholds.

Focused evidence is recorded by `scenes/validate_raid1_scenario.gd`. The
isolated scenario portion passed 17/17 before the real-manager callback was
added; the callback portion is blocked in this worktree by absent ignored
assets during arena preload. The full parse gate remains environment-blocked
by pre-existing missing ignored generated/weapon assets in this worktree.
