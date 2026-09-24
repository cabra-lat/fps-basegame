extends SceneTree
## Focused headless probe for the RAID-1 collect/extract contract.

const Raid1ScenarioScript = preload("res://scenes/raid1_scenario.gd")
const Raid1ArenaDecisionScript = preload("res://scenes/raid1_arena_decision.gd")

var _checks := 0
var _passed := 0

func _initialize() -> void:
	var raid := Raid.new()
	var profile := PlayerProfile.new()
	var fallback := ExtractionPoint.new()
	var gated := ExtractionPoint.new()
	root.add_child(raid)
	root.add_child(fallback)
	root.add_child(gated)
	var scenario := Raid1ScenarioScript.new()
	scenario.begin(raid, profile, fallback, gated)
	_check(scenario.state == Raid1ScenarioScript.State.ACTIVE, "scenario starts active")
	_check(scenario.can_extract(fallback), "fallback is always open")
	_check(not scenario.can_extract(gated), "gated destination starts closed")
	_check(not scenario.collect("bandage"), "unmarked loot is not the objective")
	_check(scenario.collect(Raid1ScenarioScript.OBJECTIVE_ID), "marked intel is collectable once")
	_check(not scenario.collect(Raid1ScenarioScript.OBJECTIVE_ID), "objective cannot be duplicated")
	_check(scenario.can_extract(gated), "objective visibly unlocks the alternative")
	_check(profile.has_item(Raid1ScenarioScript.OBJECTIVE_ID), "gate item is available to the extraction contract")
	scenario.complete(gated)
	_check(scenario.state == Raid1ScenarioScript.State.SUCCESS, "complete marks success")
	_check(scenario.carried_item_id == Raid1ScenarioScript.OBJECTIVE_ID, "success carries marked intel")

	# Helper-only regression: real RAID types, no manager preloads or stubs.
	var decision_raid := Raid.new()
	var decision_point := ExtractionPoint.new()
	var decision_scenario := Raid1ScenarioScript.new()
	decision_scenario.begin(decision_raid, profile, decision_point, decision_point)
	_check(Raid1ArenaDecisionScript.preparation_succeeded({"ok": true}), "decision accepts successful preparation")
	_check(not Raid1ArenaDecisionScript.preparation_succeeded({"ok": false}), "decision rejects failed preparation")
	_check(Raid1ArenaDecisionScript.fallback_requires_failure(decision_scenario), "decision routes objective-less fallback to failure")
	_check(not Raid1ArenaDecisionScript.scenario_completion_allowed(decision_raid, decision_scenario, decision_point), "decision forbids completion without objective")
	decision_raid.begin()
	_check(decision_raid.state == Raid.State.RAID, "completion fixture is ACTIVE before success predicate")
	_check(decision_scenario.state == Raid1ScenarioScript.State.ACTIVE, "completion scenario is ACTIVE before success predicate")
	decision_scenario.collect(Raid1ScenarioScript.OBJECTIVE_ID)
	_check(not Raid1ArenaDecisionScript.fallback_requires_failure(decision_scenario), "decision does not fail objective-complete fallback")
	_check(Raid1ArenaDecisionScript.scenario_completion_allowed(decision_raid, decision_scenario, decision_point), "decision allows objective-complete scenario")

	var manager_source := FileAccess.get_file_as_string("res://scenes/arena_manager_core.gd")
	_check(manager_source.contains("Raid1ArenaDecisionScript.preparation_succeeded(result)"), "manager delegates preparation predicate")
	_check(manager_source.contains("Raid1ArenaDecisionScript.fallback_requires_failure(scenario)"), "manager delegates fallback predicate")
	_check(manager_source.contains("Raid1ArenaDecisionScript.scenario_completion_allowed(raid, scenario, point)"), "manager delegates completion predicate")
	_check(manager_source.contains("_raid_over = true"), "manager source preserves prepare-abort state")
	_check(manager_source.contains("if not _prepare_raid_or_abort():"), "manager source gates setup on preparation")
	_check(not manager_source.contains("const BotScene:"), "manager has no eager BotScene preload")
	_check(manager_source.contains("var BotScene: PackedScene"), "manager BotScene is nullable runtime state")
	_check(not manager_source.contains("@onready var ammo_template"), "manager has no eager ammo preload")
	_check(not manager_source.contains("@onready var weapon_template"), "manager has no eager weapon preload")
	_check(manager_source.contains("ResourceLoader.exists(path)"), "manager checks dependency paths before load")
	_check(manager_source.contains("BOT_SCENE_PATH") and manager_source.contains("PRIMARY_AMMO_PATH") and manager_source.contains("PRIMARY_WEAPON_PATH") and manager_source.contains("SECONDARY_AMMO_PATH") and manager_source.contains("SECONDARY_WEAPON_PATH"), "manager names all five runtime dependencies")
	_check(manager_source.contains("BotScene.can_instantiate()"), "manager validates bot scene instantiation")
	_check(manager_source.contains("set_process(false)"), "manager disables process on dependency failure")
	_check(manager_source.contains("set_physics_process(false)"), "manager disables physics on dependency failure")
	var dependency_loader_pos := manager_source.find("if not _load_arena_dependencies():")
	var view_setup_pos := manager_source.find("ViewSetup.configure_fps(player)")
	var raid_setup_pos := manager_source.find("\t_setup_raid()")
	var equip_pos := manager_source.find("call(\"_equip_loadout\"")
	var bot_spawn_pos := manager_source.find("call(\"_spawn_bots\"")
	_check(dependency_loader_pos >= 0 and dependency_loader_pos < view_setup_pos and dependency_loader_pos < equip_pos and dependency_loader_pos < raid_setup_pos and dependency_loader_pos < bot_spawn_pos, "dependency loader runs before setup, loadout, and spawn")

	var clear_raid := Raid.new()
	root.add_child(clear_raid)
	clear_raid.begin()
	clear_raid.elapsed = Raid1ScenarioScript.DURATION_SECONDS
	var clear_outcome: int = clear_raid.complete_scenario(gated)
	_check(clear_outcome == Raid.Outcome.SCENARIO_CLEARED, "600s RAID-1 completion has distinct outcome")
	_check(clear_raid.outcome_name() == "SCENARIO CLEARED", "scenario outcome has explicit display name")

	var fallback_raid := Raid.new()
	root.add_child(fallback_raid)
	fallback_raid.begin()
	var fallback_scenario := Raid1ScenarioScript.new()
	fallback_scenario.begin(fallback_raid, profile, fallback, gated)
	_check(fallback_scenario.can_extract(fallback), "fallback remains physically open")
	fallback_scenario.fail("marked intel not extracted")
	fallback_raid.end(Raid.Outcome.LEFT_BEHIND)
	_check(fallback_scenario.state == Raid1ScenarioScript.State.FAILURE, "fallback without objective fails scenario")
	_check(fallback_raid.outcome == Raid.Outcome.LEFT_BEHIND, "fallback failure ends before generic success")

	# The actual ArenaManagerScript probe remains blocked by its eager
	# weapon/ammo/bot/audio dependencies; this section is helper-only.
	var preactive_raid := Raid.new()
	var preactive_scenario := Raid1ScenarioScript.new()
	var preactive_point := ExtractionPoint.new()
	preactive_scenario.begin(preactive_raid, null, preactive_point, preactive_point)
	_check(preactive_raid.state == Raid.State.PREP, "fallback fixture starts in PREP")
	_check(not preactive_raid.is_active(), "pre-ACTIVE raid is not active")
	_check(Raid1ArenaDecisionScript.fallback_requires_failure(preactive_scenario), "pre-ACTIVE fallback requires failure")
	_check(not Raid1ArenaDecisionScript.scenario_completion_allowed(preactive_raid, preactive_scenario, preactive_point), "pre-ACTIVE completion is forbidden")
	preactive_raid.begin()
	preactive_raid.end(Raid.Outcome.LEFT_BEHIND)
	_check(preactive_raid.state == Raid.State.RESOLVE, "failed fallback ends in RESOLVE")
	_check(preactive_raid.outcome != Raid.Outcome.SCENARIO_CLEARED, "failed fallback never clears scenario")
	_check(preactive_scenario.destination == "", "failed fallback has empty destination")
	_check(not Raid1ArenaDecisionScript.scenario_completion_allowed(preactive_raid, preactive_scenario, preactive_point), "post-RESOLVE completion is forbidden")

	var failed := Raid1ScenarioScript.new()
	failed.begin(raid, profile, fallback, gated)
	failed.collect(Raid1ScenarioScript.OBJECTIVE_ID)
	failed.fail("timer")
	_check(failed.state == Raid1ScenarioScript.State.FAILURE, "timer failure marks failure")
	_check(failed.carried_item_id == "", "failure carries no raid loot")
	print("RAID-1 scenario probe: checks=%d passed=%d" % [_checks, _passed])
	quit(0 if _passed == _checks else 1)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		_passed += 1
	else:
		push_error("FAIL: " + label)
