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
const POLICY_PATH := "res://resources/meta/death_policy.tres"
const ROLE_PATH := "res://resources/meta/roles/field_scout.tres"
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
	await _scenario_death_policy_is_data()
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

## INV-39 -- the death policy is DATA and the shipped .tres means what it says.
## Promoted from the dead-end work (task_1790377289975_a7fc59 / 020326) and QA's
## review discipline: every claim here is paired with the arm that would make it
## vacuous, because a policy check that only ever sees the shipped default
## proves nothing about the values a game would change.
func _scenario_death_policy_is_data() -> void:
	v.section("[3] death policy: the shipped .tres, and each value it can take")
	var path := TEST_DIR + "/policy.save"
	var shipped: DeathPolicy = load(POLICY_PATH)
	_check(shipped != null, "death_policy.tres loads")
	if shipped == null:
		return
	_check(shipped.validate().is_empty(),
		"the shipped policy has no configuration problems (%s)" % ", ".join(shipped.validate()))
	_check(shipped.loss == DeathPolicy.Loss.CONSUME,
		"the shipped policy is CONSUME: the human's answer, derived rather than chosen")
	_check(not shipped.safe_pocket.is_empty(),
		"the safe pocket ships POPULATED (a pocket with nothing in it is a word in a design doc)")
	for entry in shipped.safe_pocket:
		_check(ResourceLoader.exists(entry), "safe pocket entry loads: %s" % entry)

	# The pocket has to actually keep something, or `partition` is a no-op dressed
	# as a feature. Drive a real death with a pocketed item in the manifest.
	# The value arms live in their own function: this one asserts what the
	# shipped data SAYS, that one asserts what each value DOES. The split is
	# what keeps both inside the 60-line audit limit.
	_policy_value_arms()
	# and the role's declarations, which are a separate claim

## The value arms: every claim the shipped .tres does not make on its own,
## each paired with the case that would make it vacuous. Extracted from
## _scenario_death_policy_is_data purely for the audit's long-function limit;
## same checks, same order, same messages.
func _policy_value_arms() -> void:
	# The armed item is the weapon, because an item that never equips was never
	# at risk: `_resolve_loss` has always returned un-equipped entries as
	# leftovers, so a bandage in `secondary` comes back under ANY policy and would
	# make every arm here pass without the policy doing anything. The first
	# version of this test used the bandage and reported a green that measured
	# nothing -- the tell was that the "pocket keeps it" arm passed even with
	# `recoverable = false`.
	var armed := DeathPolicy.new()
	armed.loss = DeathPolicy.Loss.CONSUME
	armed.recoverable = true
	armed.safe_pocket = [M4]
	var pocketed := _death_with_policy(armed)
	_check(pocketed.get("kept_paths", []).has(M4),
		"an ARMED item in the safe pocket SURVIVES a death (kept=%s)" % str(pocketed.get("kept_paths", [])))
	_check(not pocketed.get("lost_paths", []).has(M4),
		"an armed item in the safe pocket is NOT reported lost (lost=%s)" % str(pocketed.get("lost_paths", [])))
	_check(pocketed.get("lost_paths", []).has(AK) and not pocketed.get("kept_paths", []).has(AK),
		"an armed item NOT in the safe pocket is still lost -- the pocket is a subset, not an amnesty")
	_keep_on_death_arms(armed)

	# The switch the original request called "probably a setting".
	var no_recovery := DeathPolicy.new()
	no_recovery.recoverable = false
	no_recovery.safe_pocket = [M4]
	var hard := _death_with_policy(no_recovery)
	_check(hard.get("lost_paths", []).has(M4) and not hard.get("kept_paths", []).has(M4),
		"recoverable = false forfeits even a pocketed armed item (kept=%s lost=%s)" % [str(hard.get("kept_paths", [])), str(hard.get("lost_paths", []))])

	# The opposite extreme, so the enum is exercised at both ends.
	var keep_all := DeathPolicy.new()
	keep_all.loss = DeathPolicy.Loss.CONSUME_KEEP_ALL
	var all_kept := _death_with_policy(keep_all)
	_check(all_kept.get("lost_paths", []).is_empty() and not all_kept.get("kept_paths", []).is_empty(),
		"CONSUME_KEEP_ALL returns the whole kit (lost=%s kept=%s)" % [str(all_kept.get("lost_paths", [])), str(all_kept.get("kept_paths", []))])

	# REGRANT: the kit is lost AND a starter comes back, which is the value a
	# game would pick instead of CONSUME.
	var regrant := DeathPolicy.new()
	regrant.loss = DeathPolicy.Loss.REGRANT
	regrant.starter = load("res://resources/meta/starter_loadout.tres")
	_check(regrant.validate().is_empty(), "a REGRANT policy with a starter is a valid configuration")
	var re_granted := _death_with_policy(regrant)
	_check(not re_granted.get("kept_paths", []).is_empty(),
		"REGRANT leaves the player a deployable kit (kept=%s)" % str(re_granted.get("kept_paths", [])))

	# A REGRANT policy with no starter cannot mean what it says, and says so.
	var broken := DeathPolicy.new()
	broken.loss = DeathPolicy.Loss.REGRANT
	_check(not broken.validate().is_empty(),
		"a REGRANT policy with no starter is reported as a configuration error")

	_role_declaration_arms()

## The role arms. Split out for the same reason as _policy_value_arms.
func _role_declaration_arms() -> void:
	# The role is a declaration, and a declaration with no name is not one.
	var role: RoleDefinition = load(ROLE_PATH)
	_check(role != null, "field_scout.tres loads")
	if role != null:
		_check(not String(role.id).is_empty() and role.display_name_key != "" and role.grants != null,
			"the role declares an id, a display name key and a kit")
		_check(role.validate().is_empty(),
			"the role has no configuration problems (%s)" % ", ".join(role.validate()))
		_check(role.should_grant(false) and not role.should_grant(true),
			"GRANT_ONCE grants to a fresh profile and not to one already granted")
		var always := RoleDefinition.new()
		always.on_entry = RoleDefinition.EntryPolicy.GRANT_ALWAYS
		always.grants = load("res://resources/meta/starter_loadout.tres")
		_check(always.should_grant(true),
			"GRANT_ALWAYS grants even to a profile that already has the kit")

## Resolve one death under `policy` and report which item paths came back and
## which were destroyed. Reads the real settlement: this is the code path a
## player loses a kit on, not `partition` called in isolation.
func _death_with_policy(policy: DeathPolicy) -> Dictionary:
	var service := MetaService.new()
	service.use_profile(MetaProfile.new(), TEST_DIR + ("policy_%d_%d.save" % [int(policy.loss), 1 if policy.recoverable else 0]))
	service.death_policy = policy
	var second := ItemCodec.item_from_path(AK)
	var weapon := ItemCodec.item_from_path(M4)
	if second == null or weapon == null:
		return {"kept_paths": [], "lost_paths": [], "error": "item missing"}
	service.profile.loadout = {
		"primary": [ItemCodec.encode_item(weapon)],
		"secondary": [ItemCodec.encode_item(second)],
	}
	service.bind_raid(Raid.new())
	service.bind_carrier(Equipment.new(), Backpack.new())
	service.prepare_raid_checked()
	var report := service.resolve_raid(Raid.Outcome.KIA, 0)
	if report == null:
		return {"kept_paths": [], "lost_paths": [], "error": "no report"}
	var kept: Array[String] = []
	for slot in service.profile.loadout:
		for data in service.profile.loadout[slot]:
			kept.append(String((data as Dictionary).get("path", "")))
	var lost: Array[String] = []
	for brief in report.lost:
		lost.append(String((brief as Dictionary).get("path", "")))
	return {"kept_paths": kept, "lost_paths": lost}

## The per-item death-safe flag, and the claim that made it into fe42546's commit
## message: "the day the addon's export lands, the population moves to per-item
## flags with no code change here". QA vetoed that sentence and was right, for
## three reasons -- the encoded dictionary never carried the key, a GDScript
## export is a property rather than metadata so get_meta() could not see it, and
## the meta was consulted OUTSIDE any pocket-membership test, so the item rather
## than the policy decided who survives a death.
##
## Rather than delete the claim, these arms make it true:
##   - the flag is read (metadata, from the resource or its content)
##   - it is carried through encode_item, the way no_transfer already is
##   - and an item that declares itself safe WITHOUT the policy agreeing is
##     reported, not honoured -- a declared item is not a second authority.
##
## The missing arm QA named is the last one, and it is the only case where the
## policy's derivation could be wrong.
func _keep_on_death_arms(shaped: DeathPolicy) -> void:
	var declaring: Resource = load(M4)
	declaring.set_meta(DeathPolicy.KEEP_ON_DEATH_META, true)

	_check(shaped.keep_on_death_declared(M4),
		"an item that declares keep_on_death is READ as declaring it")
	_check(shaped.pocket_entries_from_items([M4]).is_empty(),
		"a declaring item that the policy also lists is already ratified, not pending")

	# An empty pocket plus a declaring item: the exact shape QA said nothing
	# tested. The flag must NOT be a way to survive a death on its own.
	var lone := DeathPolicy.new()
	lone.recoverable = true
	var reported := lone.pocket_entries_from_items([M4])
	_check(reported.size() == 1 and String(reported[0]) == M4,
		"a declaring item the policy does NOT list is REPORTED as awaiting ratification (got %s)" % str(reported))
	_check(not lone.keeps(M4, declaring),
		"a declaring item the policy does NOT list does not survive a death -- the pocket is the only authority")
	var lone_death := _death_with_policy(lone)
	_check(lone_death.get("lost_paths", []).has(M4) and not lone_death.get("kept_paths", []).has(M4),
		"a death under a policy that never ratified the flag still loses the item (kept=%s)" % str(lone_death.get("kept_paths", [])))
	_check(lone.validate().is_empty(),
		"validate() does not complain about a policy that simply lists nothing (%s)" % str(lone.validate()))

	# And the flag survives encoding, which is what makes the migration to
	# per-item authoring possible at all. These two arms encode a real
	# InventoryItem: the first version passed `load(M4)`, a Weapon, into a
	# parameter typed InventoryItem, which is a RUNTIME error -- so both arms
	# below the call never executed and the harness still reported a green. Six
	# of eight checks ran and the two that were skipped were exactly the ones
	# covering the copy. Nothing in a counter distinguishes "passed" from "never
	# reached".
	var carrying: InventoryItem = ItemCodec.item_from_path(M4)
	carrying.set_meta(DeathPolicy.KEEP_ON_DEATH_META, true)
	var encoded: Dictionary = ItemCodec.encode_item(carrying)
	_check(bool(encoded.get("keep_on_death", false)),
		"encode_item carries keep_on_death, as it already carries no_transfer")
	var plain: InventoryItem = ItemCodec.item_from_path(AK)
	var plain_encoded: Dictionary = ItemCodec.encode_item(plain)
	_check(not plain_encoded.has("keep_on_death"),
		"encode_item does not invent the flag for an item that never declared it (keys=%s)" % str(plain_encoded.keys()))
