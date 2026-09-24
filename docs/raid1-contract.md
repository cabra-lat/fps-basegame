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

## Product decision: Option A selected

The coordinator selected Option A: preserve the 600-second / 8–12 minute
RAID-1 scenario and add a distinct scenario-clear outcome. The ordinary
`RUN_THROUGH` rule remains unchanged for non-RAID-1 raids.

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

Focused evidence is recorded by `scenes/validate_raid1_scenario.gd` (12/12 in
the current worktree). The full parse gate remains environment-blocked by
pre-existing missing ignored generated/weapon assets in this worktree.
