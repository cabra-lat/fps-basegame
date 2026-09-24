extends SceneTree
## Focused headless probe for the RAID-1 collect/extract contract.

const Raid1ScenarioScript = preload("res://scenes/raid1_scenario.gd")

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
