# res://src/meta/validate_meta_persistence.gd
#
# Headless persistence gate for the meta lane. Proves the extraction loop
# survives closing the game:
#   [1] enter raid -> extract with 2 items -> save -> reload: 2 items in stash,
#       currency up, loadout + EXP + counters persisted
#   [2] die in a raid with 1 item -> reload: stash identical to before the raid
#   [3] weapon + loaded magazine + mounted attachment survive a stash round-trip
#   [4] corrupt save -> clean profile, no crash, bad file quarantined
#   [5] missing save -> clean profile; atomic write leaves no temp and a
#       versioned JSON save
#
# Run:
#   godot --headless --path . --script res://src/meta/validate_meta_persistence.gd
# Exit code: 0 = every check passed, 1 = at least one failure.
extends SceneTree

const TEST_DIR := "user://meta_test"
const SAVE := "user://meta_test/profile.save"
const STARTER := "res://resources/meta/starter_loadout.tres"
const BANDAGE := "res://resources/medical/army_bandage.tres"
const AMMO_9MM := "res://resources/ammo/9_19mm_VPAM_PM2.tres"

var v: ValidateUtil

func _check(cond: bool, msg: String) -> void:
	v.check(cond, msg)

func _initialize() -> void:
	v = ValidateUtil.new("validate_meta_persistence")
	v.begin()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	_cleanup()

	_scenario_survive_roundtrip()
	_scenario_death_preserves_stash()
	_scenario_weapon_state()
	_scenario_corrupt()
	_scenario_missing_and_atomic()
	_scenario_v1_migration()
	_scenario_role_state()
	_scenario_hub_deploy_contract()

	quit(v.finish())

# ─── SCENARIOS ──────────────────────────────────────

func _scenario_survive_roundtrip() -> void:
	print("\n[1] extract with 2 items -> save -> reload")
	var service := MetaService.new()
	service.save_path = SAVE
	var profile := MetaProfile.new()
	service.use_profile(profile, SAVE)

	var starter := load(STARTER) as StarterLoadout
	_check(starter != null, "starter_loadout.tres loads")
	var granted := service.grant_starter_loadout(starter)
	_check(granted == 2, "starter granted 2 loadout items (got %d)" % granted)

	var eq := Equipment.new()
	var bag := Backpack.new()
	service.bind_carrier(eq, bag)
	var moved := service.prepare_raid()
	_check(moved == 2, "prepare_raid equipped 2 items (got %d)" % moved)

	_add_loot(bag, BANDAGE, 1)
	_add_loot(bag, AMMO_9MM, 30)
	var currency_before := profile.currency
	var report := service.resolve_raid(Raid.Outcome.SURVIVED, 250)
	_check(report != null and report.survived, "report marks SURVIVED")
	_check(report.gained.size() == 2, "report recorded 2 gains (got %d)" % report.gained.size())
	_check(profile.currency > currency_before, "currency rose %d -> %d" % [currency_before, profile.currency])

	var loaded := ProfileStore.load_profile(SAVE)
	_check(loaded != null, "reload returns a profile")
	_check(loaded.stash.count_items() == 2, "stash has the 2 extracted items (got %d)" % loaded.stash.count_items())
	_check(loaded.currency == profile.currency, "currency persisted (%d vs %d)" % [loaded.currency, profile.currency])
	_check(not loaded.loadout.is_empty(), "loadout restored for the next raid")
	_check(loaded.total_exp == 250, "EXP persisted (got %d)" % loaded.total_exp)
	_check(loaded.raids == 1 and loaded.survived == 1, "raid counters persisted (raids=%d survived=%d)" % [loaded.raids, loaded.survived])
	_check(loaded.stash.get_total_mass() > 0.0, "stash mass accounted (%.4f kg)" % loaded.stash.get_total_mass())
	_check(loaded.last_report.get("survived", false) == true, "last raid report persisted")

func _scenario_death_preserves_stash() -> void:
	print("\n[2] die in a raid with 1 item -> stash untouched")
	var profile := ProfileStore.load_profile(SAVE)
	var before := _snapshot(profile.stash)
	_check(before != "", "pre-raid stash snapshot is non-empty")

	var service := MetaService.new()
	service.use_profile(profile, SAVE)
	var eq := Equipment.new()
	var bag := Backpack.new()
	service.bind_carrier(eq, bag)
	var moved := service.prepare_raid()
	_check(moved == 2, "loadout equipped from profile (got %d)" % moved)

	_add_loot(bag, BANDAGE, 1)
	var report := service.resolve_raid(Raid.Outcome.KIA, 0)
	_check(report != null and not report.survived, "report marks KIA")
	_check(report.lost.size() == 2, "2 equipped items forfeited (got %d)" % report.lost.size())

	var reloaded := ProfileStore.load_profile(SAVE)
	_check(_snapshot(reloaded.stash) == before, "stash identical to before the raid")
	_check(reloaded.loadout.is_empty(), "equipped loadout forfeited")
	_check(reloaded.kia == 1, "kia counter persisted (got %d)" % reloaded.kia)
	_check(reloaded.stash.count_items() == 2, "stash still holds the previous 2 items")

func _scenario_weapon_state() -> void:
	print("\n[3] weapon + magazine + attachment survive a stash save/reload")
	var wpath := "res://resources/weapons/M4_Carbine.tres"
	var apath := "res://resources/attachments/USA_FH.tres"
	var ammo_path := "res://resources/ammo/5_56_45mm_SS109_VPAM_PM7.tres"
	var item := ItemCodec.item_from_path(wpath)
	var w := item.extra as Weapon if item != null else null
	_check(w != null, "weapon item built from path")
	if w != null:
		var feed := w.ammo_feed
		if feed == null:
			feed = AmmoFeed.new()
			feed.max_capacity = 30
			w.ammo_feed = feed
		feed.contents.clear()
		feed.compatible_calibers = PackedStringArray(["5.56x45mm NATO"])
		for i in range(5):
			feed.insert(load(ammo_path))
		var att := load(apath) as Attachment
		_check(w.attach_attachment(Weapon.AttachmentPoint.MUZZLE, att), "attachment mounted in memory")

	var profile := MetaProfile.new()
	profile.stash.deposit(item)
	var wpath_save := TEST_DIR + "/weapon.save"
	ProfileStore.delete(wpath_save)
	ProfileStore.save(profile, wpath_save)
	var loaded := ProfileStore.load_profile(wpath_save)
	_check(loaded.stash.count_items() == 1, "weapon persisted as one stash entry")
	var decoded: Weapon = null
	if not loaded.stash.items.is_empty():
		var extra = loaded.stash.items[0].extra
		if extra is Weapon:
			decoded = extra
	_check(decoded != null, "weapon decoded from disk")
	if decoded != null:
		_check(decoded.ammo_feed != null and decoded.ammo_feed.capacity == 5, "loaded magazine has 5 rounds (got %s)" % ("null" if decoded.ammo_feed == null else str(decoded.ammo_feed.capacity)))
		_check(decoded.get_attachment(Weapon.AttachmentPoint.MUZZLE) != null, "muzzle attachment restored")

func _scenario_corrupt() -> void:
	print("\n[4] corrupt save")
	var cpath := TEST_DIR + "/corrupt.save"
	var f := FileAccess.open(cpath, FileAccess.WRITE)
	f.store_string("{ this is definitely not json ]")
	f.close()
	var profile := ProfileStore.load_profile(cpath)
	_check(profile != null, "corrupt save does not crash")
	_check(profile.stash.count_items() == 0, "corrupt save falls back to a clean stash")
	_check(profile.currency == PlayerProfile.new().currency, "corrupt save falls back to default currency")
	_check(_has_corrupt_backup(), "corrupt file kept as .corrupt backup")

func _scenario_missing_and_atomic() -> void:
	print("\n[5] missing save + atomic versioned write")
	var mpath := TEST_DIR + "/missing.save"
	ProfileStore.delete(mpath)
	var profile := ProfileStore.load_profile(mpath)
	_check(profile != null and profile.stash.count_items() == 0, "missing save -> clean profile")

	ProfileStore.save(profile, mpath)
	_check(FileAccess.file_exists(mpath), "save file written")
	_check(not FileAccess.file_exists(mpath + ".tmp"), "atomic save leaves no temp file")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(mpath))
	_check(parsed is Dictionary, "save is valid JSON")
	if parsed is Dictionary:
		_check(int(parsed.get("version", -1)) == MetaProfile.VERSION, "save carries version %d" % MetaProfile.VERSION)

	# Future version must not be trusted: clean start + quarantine.
	var fpath := TEST_DIR + "/future.save"
	var f := FileAccess.open(fpath, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": MetaProfile.VERSION + 999, "currency": 1}))
	f.close()
	var future := ProfileStore.load_profile(fpath)
	_check(future.currency == PlayerProfile.new().currency, "future-version save ignored, starts clean")

func _scenario_v1_migration() -> void:
	print("\n[6] a real v1 save migrates to v2 (never quarantined)")
	# Build a realistic CURRENT profile, then rewrite it as a v1 save: version 1 and
	# the faction as the legacy numeric index (index 1 = the second legacy id).
	var src := MetaProfile.new()
	src.stash.deposit(ItemCodec.item_from_path(BANDAGE))
	src.loadout = {"primary": [ItemCodec.encode_item(ItemCodec.item_from_path("res://resources/weapons/M4_Carbine.tres"))]}
	src.currency = 4242
	src.raids = 3
	src.survived = 2
	src.kia = 1
	src.total_exp = 1500
	var legacy_index := 1
	var expected_id: String = PlayerProfile.LEGACY_FACTION_ORDER[legacy_index]

	var v1 := src.to_dict()
	v1["version"] = 1
	v1["faction"] = legacy_index
	# A genuine pre-roles save has no `roles` key at all (it was written before the
	# per-faction state existed) — the fixture must model that, not just an old version.
	v1.erase("roles")
	_check(not v1.has("roles"), "fixture really models a pre-roles save")
	var path := TEST_DIR + "/v1.save"
	_write_json(path, v1)

	var migrated := ProfileStore.load_profile(path)
	_check(migrated != null, "v1 save loads")
	_check(migrated.faction == expected_id, "numeric faction %d migrated to id \"%s\" (got \"%s\")" % [legacy_index, expected_id, migrated.faction])
	_check(migrated.currency == 4242, "currency preserved (%d)" % migrated.currency)
	_check(migrated.stash.count_items() == 1, "stash preserved (%d item)" % migrated.stash.count_items())
	_check(migrated.stash.get_total_mass() > 0.0, "stash mass preserved (%.4f kg)" % migrated.stash.get_total_mass())
	_check(migrated.loadout.size() == 1, "loadout preserved (%d slot)" % migrated.loadout.size())
	_check(migrated.raids == 3 and migrated.survived == 2 and migrated.kia == 1, "counters preserved (raids=%d survived=%d kia=%d)" % [migrated.raids, migrated.survived, migrated.kia])
	_check(migrated.total_exp == 1500, "EXP preserved (%d)" % migrated.total_exp)
	_check(_no_corrupt_backup_for("v1.save"), "a migratable v1 save is NOT quarantined")
	# Legacy save with gear: "already has gear" means "already granted", so a migrated
	# profile cannot claim a second starter kit for its active faction.
	_check(bool(migrated.role_state().get("starter_granted", false)), "a migrated save with gear counts as already granted (no free starter kit)")

	# The migrated profile is written back in the new shape.
	ProfileStore.save(migrated, path)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary and int(parsed.get("version", -1)) == MetaProfile.VERSION, "rewritten save carries version %d" % MetaProfile.VERSION)
	if parsed is Dictionary:
		_check(parsed.get("faction") is String, "faction written as a String id after migration (got %s)" % str(parsed.get("faction")))

	# A legacy index outside the known range must be loud but still load: the
	# migration never guesses silently, and never destroys the save over it.
	var v1_bad := src.to_dict()
	v1_bad["version"] = 1
	v1_bad["faction"] = 99
	var bad_path := TEST_DIR + "/v1_bad.save"
	_write_json(bad_path, v1_bad)
	var from_bad := ProfileStore.load_profile(bad_path)
	_check(from_bad != null and from_bad.faction == PlayerProfile.DEFAULT_FACTION, "out-of-range legacy faction falls back to \"%s\" and still loads (got \"%s\")" % [PlayerProfile.DEFAULT_FACTION, from_bad.faction if from_bad != null else "nil"])
	_check(_no_corrupt_backup_for("v1_bad.save"), "out-of-range legacy faction is not quarantined either")

func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

func _no_corrupt_backup_for(name: String) -> bool:
	var d := DirAccess.open(TEST_DIR)
	if d == null:
		return true
	for f in d.get_files():
		if f.begins_with(name + ".corrupt-"):
			return false
	return true

func _scenario_role_state() -> void:
	print("\n[7] per-faction state: kit swap is conservative, KIA isolates the other kit")
	var profile := MetaProfile.new()
	profile.faction = "contractor"
	# Contractor kit: two items. Drifter kit: one different item.
	profile.loadout = {"primary": [ItemCodec.encode_item(ItemCodec.item_from_path("res://resources/weapons/M4_Carbine.tres"))]}
	profile.stash.deposit(ItemCodec.item_from_path(BANDAGE))
	profile.role_state("drifter")["kit"] = {"primary": [ItemCodec.encode_item(ItemCodec.item_from_path("res://resources/weapons/AK_74.tres"))]}

	# The active faction's kit is the LIVE loadout (one copy, never both).
	_check(profile.role_kit("contractor") == profile.loadout, "active faction's kit IS the live loadout")
	var mass_before := _role_mass(profile)

	# Swap twice; mass must be conserved exactly and each kit must land where it belongs.
	var sw := profile.switch_faction("drifter")
	_check(sw.get("ok", false), "switch to drifter ok (%s)" % sw.get("reason", ""))
	_check(profile.faction == "drifter", "active faction is now drifter")
	_check(profile.loadout.has("primary") and not profile.loadout.is_empty(), "drifter kit is active")
	var drifter_kit_is_ak := String((profile.loadout["primary"] as Array)[0].get("path", "")).contains("AK_74")
	_check(drifter_kit_is_ak, "the ACTIVE kit is the drifter's (AK_74), not the contractor's")
	var back := profile.switch_faction("contractor")
	_check(back.get("ok", false), "switch back to contractor ok (%s)" % back.get("reason", ""))
	var contractor_back := String((profile.loadout["primary"] as Array)[0].get("path", "")).contains("M4_Carbine")
	_check(contractor_back, "the contractor kit came back intact (M4_Carbine)")
	_check(is_equal_approx(_role_mass(profile), mass_before), "mass over stash + all kits conserved across 2 swaps (%.4f -> %.4f)" % [mass_before, _role_mass(profile)])
	_check(not profile.switch_faction("contractor").get("ok", false), "switching to the active faction is refused")
	_check(not profile.switch_faction("").get("ok", false), "switching to an empty id is refused")

	# KIA forfeits ONLY the active kit: the other faction's kit is untouched.
	var service := MetaService.new()
	service.save_path = TEST_DIR + "/roles.save"
	service.use_profile(profile, TEST_DIR + "/roles.save")
	var other_before := (profile.role_kit("drifter") as Dictionary).duplicate(true)
	var eq := Equipment.new()
	var bag := Backpack.new()
	service.bind_carrier(eq, bag)
	service.prepare_raid()
	var report := service.resolve_raid(Raid.Outcome.KIA, 0)
	_check(report != null and not report.survived, "KIA resolved")
	_check(profile.loadout.is_empty(), "the ACTIVE kit was forfeited")
	_check(profile.role_kit("drifter") == other_before, "the INACTIVE faction's kit is byte-identical after the KIA")
	_check(int(profile.role_state("contractor")["kia"]) == 1, "per-faction kia counter incremented (%d)" % int(profile.role_state("contractor")["kia"]))
	_check(int(profile.role_state("drifter")["kia"]) == 0, "the other faction's counter is untouched")

	# A switch is refused while a raid is prepared.
	service.prepare_raid()
	var blocked := service.set_active_role("drifter")
	_check(not blocked.get("ok", false) and String(blocked.get("reason", "")).contains("raid"), "switch refused while a raid is prepared (%s)" % blocked.get("reason", ""))

	# Per-faction persistence round-trip.
	profile.roles["drifter"]["karma"] = 7
	ProfileStore.save(profile, TEST_DIR + "/roles.save")
	var loaded := ProfileStore.load_profile(TEST_DIR + "/roles.save")
	_check(loaded != null, "profile with roles reloads")
	_check(int(loaded.role_state("drifter")["karma"]) == 7, "per-faction karma persisted (%d)" % int(loaded.role_state("drifter")["karma"]))
	_check(loaded.role_kit("drifter").size() == 1, "the inactive faction's kit persisted")
	_check(loaded.faction == profile.faction, "active faction persisted (%s)" % loaded.faction)

func _role_mass(profile: MetaProfile) -> float:
	var total: float = profile.stash.get_total_mass() + _kit_mass(profile.loadout)
	for id in profile.roles:
		if id == profile.faction:
			continue # the active faction's kit IS the live loadout; do not double count
		total += _kit_mass(profile.roles[id].get("kit", {}))
	return total

func _kit_mass(kit: Dictionary) -> float:
	var total := 0.0
	for slot_name in kit:
		for data in kit[slot_name]:
			var item := ItemCodec.decode_item(data)
			if item != null:
				total += item.get_mass()
	return total

func _scenario_hub_deploy_contract() -> void:
	print("\n[8] HUB-1 deploy contract: validate, exact transfer, restart, once-only report")
	var path := TEST_DIR + "/deploy.save"
	ProfileStore.delete(path)
	var service := MetaService.new()
	service.save_path = path
	var profile := MetaProfile.new()
	service.use_profile(profile, path)
	var starter := load(STARTER) as StarterLoadout
	_check(service.grant_starter_loadout(starter) == 2, "starter granted once")
	_check(service.grant_starter_loadout(starter) == 0, "starter grant is idempotent (no duplicate starter)")
	var empty_options := MetaService.new()
	var empty_profile := MetaProfile.new()
	empty_options.use_profile(empty_profile, TEST_DIR + "/empty_projection.save")
	_check(empty_options.deploy_options().is_empty(), "empty profile has no hub deployment option")
	var projection := service.deploy_options()
	_check(String(projection.get("id", "")) == "active", "populated kit exposes the active hub option")
	_check(projection.get("selection", {}) is Dictionary and service.validate_deploy(projection.selection).get("ok", false), "hub projection is canonical and legal")

	var selected := profile.loadout.duplicate(true)
	var selected_sig := _loadout_signature(selected)
	var valid := service.validate_deploy(selected)
	_check(valid.get("ok", false), "selected two-site loadout validates")
	var bad := service.validate_deploy({"primary": [{"kind": "container", "path": ""}]})
	_check(not bad.get("ok", false), "unknown item is rejected safely")
	var empty_primary := service.validate_deploy({"primary": []})
	_check(not empty_primary.get("ok", false), "empty primary selection is rejected")
	_check(profile.loadout == selected, "rejected selection does not mutate profile")

	var deployed := service.deploy_loadout(selected)
	_check(deployed.get("ok", false), "deploy stages the owned two-site loadout")
	_check(_loadout_signature(profile.loadout) == selected_sig, "deploy records exactly the selected kit")
	var eq := Equipment.new()
	var bag := Backpack.new()
	service.bind_carrier(eq, bag)
	_check(service.prepare_raid() == 2, "prepare equips both selected weapons")
	_check(_loadout_signature(profile.loadout) == selected_sig, "deployed manifest survives until raid resolution")
	var restarted := ProfileStore.load_profile(path)
	_check(_loadout_signature(restarted.loadout) == selected_sig, "restart after prepare recovers the deployment manifest")
	var report := service.resolve_raid(Raid.Outcome.SURVIVED, 25)
	_check(report != null, "first raid report is returned")
	_check(service.resolve_raid(Raid.Outcome.SURVIVED, 25) == null, "duplicate resolution returns no second report")
	var after := ProfileStore.load_profile(path)
	_check(_loadout_signature(after.loadout) == selected_sig, "survival persists the deployed kit exactly once")

	# Selecting from the stash removes exactly that item; an unselected old kit
	# item returns to the stash, and failure resolution forfeits only the new kit.
	var second := MetaProfile.new()
	var second_service := MetaService.new()
	var second_path := TEST_DIR + "/deploy_second.save"
	ProfileStore.delete(second_path)
	second_service.save_path = second_path
	second_service.use_profile(second, second_path)
	second_service.grant_starter_loadout(starter)
	var old_primary: Array = second.loadout["primary"]
	var old_secondary: Array = second.loadout["secondary"]
	second.stash.deposit(ItemCodec.decode_item(old_secondary[0]))
	second.loadout = {"primary": old_primary}
	var swap := second_service.deploy_loadout({"primary": [old_secondary[0]]})
	_check(swap.get("ok", false), "a selected stash weapon can be deployed")
	_check(second.stash.count_items() == 1 and second.loadout.size() == 1, "unselected kit returned; selected item removed once")
	var eq2 := Equipment.new()
	var bag2 := Backpack.new()
	second_service.bind_carrier(eq2, bag2)
	_check(second_service.prepare_raid() == 1, "second deployment equips the swapped weapon")
	var lost := second_service.resolve_raid(Raid.Outcome.KIA, 0)
	_check(lost != null and lost.lost.size() == 1, "failed second raid reports only the deployed weapon")
	var second_after := ProfileStore.load_profile(second_path)
	_check(second_after.loadout.is_empty(), "failed second deployment leaves no active loadout")
	_check(second_after.stash.count_items() == 1, "failed second deployment preserves the unselected stash weapon")

	# A persistence failure must not leave the carrier equipped or the service
	# claiming that preparation completed.
	var failed_path := TEST_DIR + "/missing_parent/profile.save"
	var failed_service := MetaService.new()
	failed_service.save_path = failed_path
	var failed_profile := MetaProfile.new()
	failed_service.use_profile(failed_profile, failed_path)
	failed_service.grant_starter_loadout(starter)
	var failed_eq := Equipment.new()
	failed_service.bind_carrier(failed_eq, Backpack.new())
	_check(failed_service.prepare_raid() == 0, "prepare fails closed when persistence fails")
	_check(not failed_eq.is_equipped("primary") and not failed_eq.is_equipped("secondary"), "failed prepare rolls back equipped items")
	_check(failed_profile.loadout.size() == 2, "failed prepare leaves the recovery manifest intact")

	# Force the second selected stash removal to fail. The deploy transaction
	# must restore every selected item, including the one removed by the signal.
	var rollback_profile := MetaProfile.new()
	var rollback_service := MetaService.new()
	var rollback_path := TEST_DIR + "/deploy_rollback.save"
	ProfileStore.delete(rollback_path)
	rollback_service.save_path = rollback_path
	rollback_service.use_profile(rollback_profile, rollback_path)
	var primary_item := ItemCodec.item_from_path("res://resources/weapons/M4_Carbine.tres")
	var secondary_item := ItemCodec.item_from_path("res://resources/weapons/AK_47.tres")
	rollback_profile.stash.deposit(primary_item)
	rollback_profile.stash.deposit(secondary_item)
	primary_item = rollback_profile.stash.items[0]
	secondary_item = rollback_profile.stash.items[1]
	var primary_data := ItemCodec.encode_item(primary_item)
	var secondary_data := ItemCodec.encode_item(secondary_item)
	var callback_state := {"ran": false}
	rollback_profile.stash.item_removed.connect(func(removed_item: InventoryItem) -> void:
		if not callback_state.ran:
			callback_state.ran = true
			if removed_item == primary_item:
				rollback_profile.stash.remove_item(secondary_item)
			else:
				rollback_profile.stash.remove_item(primary_item)
	)
	var rollback := rollback_service.deploy_loadout({"primary": [primary_data], "secondary": [secondary_data]})
	_check(not rollback.get("ok", false), "deploy reports a failed stash removal (reason=%s)" % String(rollback.get("reason", "")))
	_check(callback_state.ran and rollback_profile.stash.count_items() == 2, "failed stash removal restores every selected item (callback=%s count=%d)" % [callback_state.ran, rollback_profile.stash.count_items()])
	_check(rollback_profile.loadout.is_empty(), "failed stash removal restores the old loadout")


func _loadout_signature(kit: Dictionary) -> String:
	var parts: Array[String] = []
	for slot_name in kit:
		for data in kit[slot_name]:
			if data is Dictionary:
				parts.append("%s:%s:%s" % [slot_name, data.get("name", "?"), data.get("path", "")])
	parts.sort()
	return "|".join(parts)


# ─── HELPERS ────────────────────────────────────────

func _add_loot(bag: InventoryContainer, path: String, stack: int) -> void:
	var res := load(path)
	if res == null:
		push_warning("loot resource missing: %s" % path)
		return
	var item: InventoryItem
	if res is Ammo:
		item = InventorySystem.create_inventory_item(res as Item, stack)
	else:
		item = InventoryItem.slurp(res as Item)
	if item == null or not bag.add_item(item, Vector2i(-1, -1)):
		push_warning("could not add loot: %s" % path)

func _snapshot(stash: Stash) -> String:
	var names: Array[String] = []
	for item in stash.items:
		names.append("%s x%d" % [item.name, item.stack_count])
	names.sort()
	return " | ".join(names)

func _has_corrupt_backup() -> bool:
	var d := DirAccess.open(TEST_DIR)
	if d == null:
		return false
	for f in d.get_files():
		if f.begins_with("corrupt.save.corrupt-"):
			return true
	return false

func _cleanup() -> void:
	var d := DirAccess.open(TEST_DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
