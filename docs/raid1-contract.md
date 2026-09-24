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

## Outcome-policy decision still open

The implementation deliberately does not call the existing **RUN THROUGH**
classification for a 600-second scenario. `Raid.extract()` currently returns
`SURVIVED` at 600 seconds because RUN THROUGH requires elapsed time under 420
seconds and EXP under 200.

Product must choose one contract before integration:

1. Keep the 8–12 minute scenario and add an explicit scenario-clear outcome,
   including its reward and progression semantics; or
2. Approve a shorter scenario and an explicit EXP policy so the existing
   `RUN THROUGH` classification applies.

Until that decision, the current candidate retains the bounded 600-second
implementation and its existing failure semantics without silently selecting
option 1 or 2.

Focused evidence is recorded by `scenes/validate_raid1_scenario.gd` (12/12 in
the current worktree). The full parse gate remains environment-blocked by
pre-existing missing ignored generated/weapon assets in this worktree.
