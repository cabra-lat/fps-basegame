class_name Raid1ArenaDecision
extends RefCounted
## Side-effect-free predicates for the RAID-1 caller boundary.
## The arena manager owns persistence calls, raid state changes, HUD updates,
## and feed messages; this helper only classifies already-observed state.

## True only when MetaService's checked preparation result is successful.
static func preparation_succeeded(result: Dictionary) -> bool:
	return bool(result.get("ok", false))


## Open Lane is a failure when a first-clear scenario lacks its objective.
static func fallback_requires_failure(scenario: Raid1Scenario) -> bool:
	return scenario != null and not scenario.objective_collected


## A scenario completion is valid only for a real active raid and destination.
static func scenario_completion_allowed(raid: Raid, scenario: Raid1Scenario, point: ExtractionPoint) -> bool:
	return raid != null and raid.is_active() and scenario != null and scenario.state == Raid1Scenario.State.ACTIVE and point != null and scenario.objective_collected
