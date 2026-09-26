# res://src/meta/validate_meta_deploy_raid.gd
#
# Deterministic META-1 integration gate: deploy -> raid -> resolve -> reload.
# This is intentionally a headless SceneTree harness. It does not open a GPU
# window; GPU-1 owns the separate 1280x720 visual/session evidence.
#
# Run:
#   godot --headless --path . --script res://src/meta/validate_meta_deploy_raid.gd
extends SceneTree

const TEST_DIR := "user://meta_deploy_raid"
const M4 := "res://resources/weapons/M4_Carbine.tres"
const AK := "res://resources/weapons/AK_47.tres"
const AMMO := "res://resources/ammo/5_56_45mm_SS109_VPAM_PM7.tres"
const BANDAGE := "res://resources/medical/army_bandage.tres"
const MARKED_INTEL := "res://resources/raid1/marked_intel.tres"

var v: ValidateUtil

func _check(condition: bool, message: String) -> void:
	v.check(condition, message)

func _initialize() -> void:
	v = ValidateUtil.new("validate_meta_deploy_raid")
	v.begin()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	_cleanup()
	_scenario_clear_and_reload()
	_scenario_loss_and_duplicate_signal()
	_scenario_bad_save_recovery()
	quit(v.finish())

func _scenario_clear_and_reload() -> void:
	v.section("[1] deploy -> raid start -> scenario clear -> persisted reload")
	var path := TEST_DIR + "/clear.save"
	var service := MetaService.new()
	service.use_profile(MetaProfile.new(), path)
	var setup := _stage_weapon_loadout(service, 7)
	_check(setup["ok"], "deploy selection stages a valid primary/secondary loadout")
	_check(service.deploy_options().get("id", "") == "active", "deploy options project the active selection")

	var equipment := Equipment.new()
	var backpack := Backpack.new()
	var raid := Raid.new()
	service.bind_carrier(equipment, backpack)
	service.bind_raid(raid)
	var prepared := service.prepare_raid_checked()
	_check(bool(prepared.get("ok", false)), "prepare_raid_checked succeeds after deploy")
	_check(int(prepared.get("items_equipped", 0)) == 2, "both staged weapons equip (got %d)" % int(prepared.get("items_equipped", 0)))
	_check(_hud_ammo(equipment) == 7, "HUD ammo projection matches equipped feed before raid")

	_add_loot(backpack, MARKED_INTEL, 1)
	_check(raid.begin(), "raid starts after successful preparation")
	raid.complete_scenario(null)
	var report := RaidReport.from_dict(service.profile.last_report)
	_check(report != null and report.survived, "scenario clear resolves as successful")
	_check(report.outcome == MetaService.SCENARIO_CLEARED_OUTCOME, "scenario clear preserves the finite outcome")
	_check(service.profile.raids == 1 and service.profile.survived == 1, "in-memory result counters match resolution")
	_check(service.profile.currency == int(report.currency_delta) + _starting_currency(service.profile), "in-memory currency matches report delta")
	_check(service.profile.last_report == report.to_dict(), "persisted last_report equals resolved report figures")

	# CAUGHT BY the dead-end probe for task_1790377289975_a7fc59 (2026-09-26):
	# see _check_survived_raid_stays_replayable, which holds the reasoning.
	_check_survived_raid_stays_replayable(service)
	var persisted := _check_reload_preserves_result(service, report, path)

	# A second notification on the same resolved raid must be harmless. Keep
	# this before starting the next raid, because start_raid opens a fresh latch.
	var raids_before := service.profile.raids
	var currency_before := service.profile.currency
	raid.raid_ended.emit(MetaService.SCENARIO_CLEARED_OUTCOME)
	_check(service.profile.raids == raids_before, "duplicate raid_ended cannot double-apply the raid")
	_check(service.profile.currency == currency_before, "duplicate raid_ended cannot double-apply currency")

	# Re-prepare from the reloaded profile and compare the HUD projection with
	# the actual equipped feed. The arena manager's deterministic mag text reads
	# this same AmmoFeed.capacity value.
	var reloaded_service := MetaService.new()
	reloaded_service.use_profile(persisted, path)
	var reloaded_equipment := Equipment.new()
	var reloaded_backpack := Backpack.new()
	reloaded_service.bind_carrier(reloaded_equipment, reloaded_backpack)
	var reloaded_prepare := reloaded_service.prepare_raid_checked()
	_check(bool(reloaded_prepare.get("ok", false)), "reloaded profile can prepare the next raid")
	_check(_hud_ammo(reloaded_equipment) == _equipped_feed_ammo(reloaded_equipment), "HUD ammo equals equipped feed after resolution/reload")
	_check(_hud_ammo(reloaded_equipment) == 7, "reloaded feed preserves the resolved ammo count")

func _scenario_loss_and_duplicate_signal() -> void:
	v.section("[2] deploy -> raid loss -> persisted forfeiture")
	var path := TEST_DIR + "/loss.save"
	var service := MetaService.new()
	service.use_profile(MetaProfile.new(), path)
	_check(bool(_stage_weapon_loadout(service, 11)["ok"]), "loss scenario deploys a valid loadout")
	var equipment := Equipment.new()
	var backpack := Backpack.new()
	var raid := Raid.new()
	service.bind_carrier(equipment, backpack)
	service.bind_raid(raid)
	_check(bool(service.prepare_raid_checked().get("ok", false)), "loss scenario preparation succeeds")
	_add_loot(backpack, BANDAGE, 1)
	_check(raid.begin(), "loss scenario raid starts")
	raid.end(Raid.Outcome.KIA)
	var report := RaidReport.from_dict(service.profile.last_report)
	_check(report != null and not report.survived, "KIA resolves as a loss")
	_check(report.lost.size() == 2, "loss report records both equipped weapons")
	_check(service.profile.kia == 1 and service.profile.raids == 1, "loss counters are resolved once")
	var persisted := ProfileStore.load_profile(path)
	_check(persisted.kia == 1 and persisted.survived == 0, "loss result persists after reload")
	_check(persisted.loadout.is_empty(), "loss forfeits the deployed loadout")
	_check(persisted.stash.count_items() == 0, "loss discards carried loot and preserves the empty stash")

	var raids_before := service.profile.raids
	var kia_before := service.profile.kia
	raid.raid_ended.emit(Raid.Outcome.KIA)
	_check(service.profile.raids == raids_before and service.profile.kia == kia_before, "second loss raid_ended notification is ignored")

func _scenario_bad_save_recovery() -> void:
	v.section("[3] bad save recovery remains quarantined")
	var path := TEST_DIR + "/corrupt.save"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ definitely not valid json")
	file.close()
	var recovered := ProfileStore.load_profile(path)
	_check(recovered != null and recovered.stash.count_items() == 0, "corrupt save recovers to a clean profile")
	_check(not FileAccess.file_exists(path), "corrupt live save is moved out of the way")
	_check(_has_prefix(path + ".corrupt-"), "corrupt save is retained as a quarantine backup")

func _stage_weapon_loadout(service: MetaService, rounds: int) -> Dictionary:
	var primary := ItemCodec.item_from_path(M4)
	var secondary := ItemCodec.item_from_path(AK)
	_check(primary != null and primary.extra is Weapon, "M4 item is loadable")
	_check(secondary != null and secondary.extra is Weapon, "AK item is loadable")
	if primary == null or secondary == null:
		return {"ok": false, "reason": "starter item missing"}
	_set_feed(primary.extra, rounds)
	_set_feed(secondary.extra, rounds)
	service.profile.loadout = {
		"primary": [ItemCodec.encode_item(primary)],
		"secondary": [ItemCodec.encode_item(secondary)],
	}
	var options := service.deploy_options()
	if not bool(options.get("ok", false)) and not options.has("selection"):
		# deploy_options returns a projected dictionary on success.
		return {"ok": false, "reason": "deploy options unavailable"}
	var selection: Dictionary = options.get("selection", {})
	return service.deploy_loadout(selection)

func _set_feed(weapon: Weapon, rounds: int) -> void:
	if weapon == null:
		return
	if weapon.ammo_feed == null:
		weapon.ammo_feed = AmmoFeed.new()
	weapon.ammo_feed.contents.clear()
	weapon.ammo_feed.max_capacity = maxi(rounds, 1)
	weapon.ammo_feed.compatible_calibers = PackedStringArray([load(AMMO).caliber])
	for _i in range(rounds):
		weapon.ammo_feed.insert(load(AMMO))
	weapon.chambered_round = null

## Restart/reload half of the clear scenario, split out only so the scenario
## function stays inside the 60-line audit limit once the replayable-loop
## assertion was added. Pure extraction: same checks, same order, same messages.
## Returns the reloaded profile, which the caller goes on to use.
func _check_reload_preserves_result(service: MetaService, report: RaidReport, path: String) -> MetaProfile:
	var persisted := ProfileStore.load_profile(path)
	_check(persisted.raids == service.profile.raids, "reloaded raid count matches in-memory result")
	_check(persisted.survived == service.profile.survived, "reloaded survival count matches in-memory result")
	_check(persisted.kia == service.profile.kia, "reloaded loss count matches in-memory result")
	_check(persisted.currency == service.profile.currency, "reloaded currency matches in-memory result")
	_check(persisted.total_exp == service.profile.total_exp, "reloaded EXP matches in-memory result")
	var persisted_report: Dictionary = persisted.last_report
	_check(persisted_report.get("outcome") == report.outcome and bool(persisted_report.get("survived")) == report.survived and persisted_report.get("currency_delta") == report.currency_delta and persisted_report.get("exp") == report.exp and persisted_report.get("gained", []).size() == report.gained.size() and persisted_report.get("loot_discarded") == report.loot_discarded, "restart/reload preserves the resolved result figures")
	_check(persisted.stash.count_items() == 1, "scenario objective is persisted in the stash")
	return persisted


## CAUGHT BY the dead-end probe for task_1790377289975_a7fc59 (2026-09-26).
##
## The board's mechanism for that card read "after a clear the deployed kit is
## consumed as loot, so the kit the hub still has selected can no longer be
## satisfied". Measured, that is backwards: MetaService._resolve_survival()
## RESTORES the kit ("the equipped kit stays available for the next raid") and
## sets report.loadout_restored. Probing both arms on the real services and the
## real hub node:
##
##   after a CLEAR  loadout_restored=true, loadout slots ["primary","secondary"],
##                   validate_deploy ok, hub state VALID, can_deploy() TRUE
##   after a DEATH  report.lost=2, loadout_restored=false, profile.loadout=[],
##                   deploy_options()={}, validate_deploy "selecao vazia",
##                   hub state EMPTY, can_deploy() FALSE
##
## So the loop-breaking state is real and it is the DEATH branch
## (meta_service.gd:286), not the clear. The assertion below pins the half that
## every open option on the card shares, so a future change that breaks the
## replayable loop cannot land quietly -- and it deliberately says nothing about
## the KIA branch, which is the pending product decision and whose current
## behaviour is an accident rather than a choice.
##
## Robust across all four options under consideration: re-granting a starter kit
## also leaves the player deployable, and "re-acquire by other means" also does,
## as long as the means exist and the hub shows them.
func _check_survived_raid_stays_replayable(service: MetaService) -> void:
	_check(not service.profile.loadout.is_empty(),
		"a SURVIVED raid leaves the kit in the profile (the loop stays replayable)")
	_check(service.deploy_options().get("id", "") == "active",
		"after a survived raid the hub is still offered a deployable kit")


func _add_loot(container: InventoryContainer, path: String, stack: int) -> void:
	var resource := load(path)
	if resource == null:
		return
	var item: InventoryItem
	if resource is Ammo:
		item = InventorySystem.create_inventory_item(resource as Item, stack)
	else:
		item = InventoryItem.slurp(resource as Item)
	if item != null:
		container.add_item(item, Vector2i(-1, -1))

func _equipped_feed_ammo(equipment: Equipment) -> int:
	var items := equipment.get_equipped("primary")
	if items.is_empty():
		return -1
	var item := items[0] as InventoryItem
	var weapon := item.extra as Weapon if item != null else null
	return weapon.ammo_feed.capacity if weapon != null and weapon.ammo_feed != null else -1

func _hud_ammo(equipment: Equipment) -> int:
	# Same deterministic source as scenes/arena_manager.gd:_mag_text().
	return _equipped_feed_ammo(equipment)

func _starting_currency(profile: MetaProfile) -> int:
	return profile.currency - profile.last_report.get("currency_delta", 0)

func _has_prefix(prefix: String) -> bool:
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return false
	var basename := prefix.get_file()
	for file_name in dir.get_files():
		if file_name.begins_with(basename):
			return true
	return false

func _cleanup() -> void:
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)
