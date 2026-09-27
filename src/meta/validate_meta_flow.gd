# res://src/meta/validate_meta_flow.gd
#
# Headless FLOW gate: main menu -> hub -> deploy candidates -> arena routing.
# It covers the player-visible dead end found on 2026-09-26: Play bypassed the
# hub, the hub had no stash projection, and an unarmed profile could not deploy.
#
# Run:
#   tools/godot-lock.sh --headless --path . --script res://src/meta/validate_meta_flow.gd
extends SceneTree

const TEST_DIR := "user://meta_flow"
const SAVE := TEST_DIR + "/profile.save"
const HUB_SCENE := "res://scenes/operations_hub.tscn"
const STARTER := "res://resources/meta/starter_loadout.tres"
const M4 := "res://resources/weapons/M4_Carbine.tres"

var v: ValidateUtil


func _check(condition: bool, message: String) -> void:
	v.check(condition, message)


func _initialize() -> void:
	v = ValidateUtil.new("validate_meta_flow")
	v.begin()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	_cleanup()
	_scenario_menu_routes_through_hub()
	_scenario_empty_profile_is_armed_and_deployable()
	_scenario_stash_is_visible_and_deployable()
	_cleanup()
	quit(v.finish())


func _scenario_menu_routes_through_hub() -> void:
	v.section("[1] main menu Play enters the hub, not the arena")
	var menu_script := load("res://scenes/main_menu.gd") as Script
	var constants: Dictionary = menu_script.get_script_constant_map()
	_check(constants.get("HUB_SCENE", "") == HUB_SCENE, "main menu publishes the hub as its Play destination")
	var project := ConfigFile.new()
	_check(project.load("res://project.godot") == OK, "project settings load")
	_check(String(project.get_value("autoload", "OperationsHubRoute", "")) == "*res://scenes/operations_hub_controller.tscn",
		"persistent hub route keeps deploy/report ownership alive across scenes")


func _scenario_empty_profile_is_armed_and_deployable() -> void:
	v.section("[2] an unarmed profile receives free playable gear")
	var service := MetaService.new()
	service.use_profile(MetaProfile.new(), SAVE)
	var hub := OperationsHubUI.new()
	hub.name = "FlowHub"
	root.add_child(hub)
	# SceneTree._initialize runs before the root window enters the tree, so _ready
	# has not fired yet; build the same visual shell explicitly for this gate.
	hub.call("_build_ui")
	var route := OperationsHubController.new()
	route.auto_route = false
	route.set_meta_service(service)
	route.bind_hub(hub)

	_check(service.profile.loadout.size() == 2, "empty profile is armed in both weapon slots")
	_check(service.profile.currency > 0, "empty profile receives starting credits")
	_check(hub.loadout_options.size() == 1, "hub projects the active kit")
	_check(hub.can_deploy(), "armed profile can deploy from the hub")
	_check(_find_named(hub, "StashItems") != null, "hub renders a stash section")
	var persisted := ProfileStore.load_profile(SAVE)
	_check(persisted != null and persisted.loadout.size() == 2, "starter rescue is persisted immediately")

	var starter := load(STARTER) as StarterLoadout
	_check(service.ensure_playable_loadout(starter) == 0, "armed profile is not refilled on hub refresh")
	hub.queue_free()
	route.queue_free()


func _scenario_stash_is_visible_and_deployable() -> void:
	v.section("[3] stash weapons are visible and can become the deployed kit")
	var profile := MetaProfile.new()
	var service := MetaService.new()
	service.use_profile(profile, SAVE)
	var starter := load(STARTER) as StarterLoadout
	service.grant_starter_loadout(starter)
	profile.loadout.clear()
	var weapon := InventorySystem.create_inventory_item(load(M4))
	_check(profile.stash.deposit(weapon, weapon.position), "stashed weapon enters the reserve")
	var snapshot := service.hub_stash_snapshot()
	_check(snapshot.size() == 1 and bool(snapshot[0].get("weapon", false)), "stash snapshot marks the weapon")
	var candidates := service.hub_deploy_candidates()
	_check(candidates.size() == 1 and String(candidates[0].get("id", "")).begins_with("stash:"),
		"empty loadout projects the stash weapon as a deploy candidate")
	var selection: Dictionary = candidates[0].get("selection", {})
	_check(service.validate_deploy(selection).get("ok", false), "stash selection passes Meta validation")
	var deployed := service.deploy_loadout(selection)
	_check(deployed.get("ok", false), "stash selection deploys without a prepare round-trip")
	_check(profile.stash_item_count() == 0 and profile.loadout.get("primary", []).size() == 1,
		"deployed weapon leaves the stash and becomes the active primary")

	profile.loadout.clear()
	profile.stash.items.clear()
	_check(service.ensure_playable_loadout(starter) == 2, "a profile that owns no weapons is refilled instead of dead-ending")


func _find_named(node: Node, target: StringName) -> Node:
	if node.name == target:
		return node
	for child in node.get_children():
		var found := _find_named(child, target)
		if found != null:
			return found
	return null


func _cleanup() -> void:
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)
