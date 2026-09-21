# res://src/meta/validate_meta_market.gd
#
# Headless gate for traders + economy + insurance. Proves:
#   [A] buy refused by balance and by loyalty (clear reasons)
#   [B] buy debits + delivers to stash + decrements stock; sell credits + removes
#   [C] reputation rises with a sale and unlocks the next loyalty level
#   [D] barter offer consumes the required items (refused when missing)
#   [E] stock resets on the raid counter
#   [F] insurance returns the non-looted item on the next raid, and pays NOTHING
#       on a no-return map or for a killer-looted item
#   [G] market state + pending insurance survive close/reopen
#
# Run:
#   godot --headless --path . --script res://src/meta/validate_meta_market.gd
# Exit code: 0 = all checks passed, 1 = at least one failure.
extends SceneTree

const TEST_DIR := "user://meta_market_test"
const SAVE := "user://meta_market_test/profile.save"

const AMMO := "res://resources/ammo/5_56_45mm_SS109_VPAM_PM7.tres"
const BANDAGE := "res://resources/medical/army_bandage.tres"
const TOURNIQUET := "res://resources/medical/cat_hemostatic_tourniquet.tres"
const M4 := "res://resources/weapons/M4_Carbine.tres"

var v: ValidateUtil
var profile: MetaProfile

func _check(cond: bool, msg: String) -> void:
	v.check(cond, msg)

func _initialize() -> void:
	v = ValidateUtil.new("validate_meta_market")
	v.begin()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	_cleanup()

	profile = MetaProfile.new()
	var loaded := profile.market.load_dir()
	_check(loaded == 3, "3 traders loaded (got %d)" % loaded)
	_check(profile.market.get_trader("quartermaster") != null, "quartermaster present")
	_check(profile.market.get_trader("field_surgeon") != null, "field_surgeon present")
	_check(profile.market.get_trader("gunsmith") != null, "gunsmith present")
	var lines := profile.market.report_lines("quartermaster")
	_check(lines.size() >= 2 and lines[1].contains("Comprar"), "report_lines() builds the HUD line (%s)" % (lines[1] if lines.size() > 1 else "none"))

	_scenario_buy_refusals()
	_scenario_buy_sell_ok()
	_scenario_reputation_unlocks()
	_scenario_barter()
	_scenario_stock_reset()
	_scenario_insurance()
	_scenario_persistence()

	quit(v.finish())

# ─── SCENARIOS ──────────────────────────────────────

func _scenario_buy_refusals() -> void:
	print("\n[A] buy refused by balance and loyalty")
	profile.currency = 100
	var r := profile.market.buy("field_surgeon", 1) # salewa 12000
	_check(not r.get("ok", false) and String(r.get("reason", "")).contains("saldo"), "refused: saldo (%s)" % r.get("reason", ""))
	profile.currency = 25000
	var r2 := profile.market.buy("quartermaster", 2) # M4, min LL2
	_check(not r2.get("ok", false) and String(r2.get("reason", "")).contains("loyalty"), "refused: loyalty (%s)" % r2.get("reason", ""))

func _scenario_buy_sell_ok() -> void:
	print("\n[B] buy debits/delivers/stock, sell credits/removes")
	var cur := profile.currency
	var rb := profile.market.buy("quartermaster", 1) # bandage 800
	_check(rb.get("ok", false), "buy bandage ok")
	_check(profile.currency == cur - 800, "currency debited 800 (got %d)" % (cur - profile.currency))
	_check(profile.market.count_in_stash(BANDAGE) == 1, "bandage in stash")
	_check(profile.market.stock_of("quartermaster", 1) == 19, "stock decremented to 19 (got %d)" % profile.market.stock_of("quartermaster", 1))
	var rep0 := profile.market.reputation("quartermaster")
	var rs := profile.market.sell("quartermaster", 1)
	_check(rs.get("ok", false), "sell bandage ok")
	_check(profile.currency == cur - 800 + 300, "currency credited 300 (got %d)" % (cur - 800 + 300))
	_check(profile.market.count_in_stash(BANDAGE) == 0, "bandage removed from stash")
	_check(profile.market.reputation("quartermaster") > rep0, "reputation rose with sale (%d -> %d)" % [rep0, profile.market.reputation("quartermaster")])

func _scenario_reputation_unlocks() -> void:
	print("\n[C] reputation + level unlock the next LL")
	profile.total_exp = 2000 # character level 3
	profile.market.add_reputation("quartermaster", 25)
	_check(profile.market.loyalty_level("quartermaster") >= 2, "quartermaster LL2 unlocked (LL%d)" % profile.market.loyalty_level("quartermaster"))
	profile.currency = 100000
	var rm := profile.market.buy("quartermaster", 2) # M4 45000, LL2
	_check(rm.get("ok", false), "LL2 M4 buy now ok (%s)" % rm.get("reason", ""))
	_check(profile.currency == 55000, "M4 debited 45000 (got %d)" % profile.currency)
	_check(profile.market.count_in_stash(M4) == 1, "M4 delivered to stash")

func _scenario_barter() -> void:
	print("\n[D] barter consumes required items")
	var r0 := profile.market.buy("field_surgeon", 2) # tourniquet needs 2 bandages
	_check(not r0.get("ok", false) and String(r0.get("reason", "")).contains("barter"), "refused: barter (%s)" % r0.get("reason", ""))
	for i in range(2):
		profile.stash.deposit(ItemCodec.item_from_path(BANDAGE))
	_check(profile.market.count_in_stash(BANDAGE) == 2, "2 bandages in stash")
	var r1 := profile.market.buy("field_surgeon", 2)
	_check(r1.get("ok", false), "barter buy ok (%s)" % r1.get("reason", ""))
	_check(profile.market.count_in_stash(BANDAGE) == 0, "bandages consumed by barter")
	_check(profile.market.count_in_stash(TOURNIQUET) == 1, "tourniquet delivered")

func _scenario_stock_reset() -> void:
	print("\n[E] stock resets on the raid counter")
	var before := profile.market.stock_of("quartermaster", 1)
	for i in range(5):
		profile.market.on_raid_resolved()
	_check(profile.market.stock_of("quartermaster", 1) == 20, "quartermaster bandage stock reset to 20 (was %d, now %d)" % [before, profile.market.stock_of("quartermaster", 1)])

func _scenario_insurance() -> void:
	print("\n[F] insurance returns non-looted gear; no-return/killer-looted excluded")
	var service := MetaService.new()
	service.save_path = SAVE
	service.use_profile(profile, SAVE)
	_check(profile.insurance.pending_count() == 0, "no pending claim at start")

	var m4_before := profile.market.count_in_stash(M4)
	var eq := Equipment.new()
	var bag := Backpack.new()
	eq.equip(InventorySystem.create_inventory_item(load(M4)), "primary")
	service.bind_carrier(eq, bag)
	service.insure_manifest()
	var report := service.resolve_raid(Raid.Outcome.KIA, 0)
	_check(report.insured == 1, "1 item insured (got %d)" % report.insured)
	_check(profile.insurance.pending_count() == 1, "claim pending after KIA")
	_check(service.report_text() != "", "report_text() exposes the last raid summary")

	# Next raid delivers it (not looted).
	var eq2 := Equipment.new()
	var bag2 := Backpack.new()
	service.bind_carrier(eq2, bag2)
	service.resolve_raid(Raid.Outcome.KIA, 0)
	_check(profile.insurance.pending_count() == 0, "claim delivered on the next raid")
	_check(profile.market.count_in_stash(M4) == m4_before + 1, "insured M4 returned to stash (%d -> %d)" % [m4_before, profile.market.count_in_stash(M4)])

	# No-return map pays nothing.
	var raid := Raid.new()
	service.bind_raid(raid)
	raid.set_meta("no_return", true)
	var eq3 := Equipment.new()
	var bag3 := Backpack.new()
	eq3.equip(InventorySystem.create_inventory_item(load(M4)), "primary")
	service.bind_carrier(eq3, bag3)
	service.insure_manifest()
	var r3 := service.resolve_raid(Raid.Outcome.KIA, 0)
	_check(r3.insured == 0, "no-return map insures nothing (got %d)" % r3.insured)
	_check(profile.insurance.pending_count() == 0, "no claim on a no-return map")
	raid.set_meta("no_return", false)

	# Killer-looted item excluded.
	service.enemy_looted_paths = [M4]
	var eq4 := Equipment.new()
	var bag4 := Backpack.new()
	eq4.equip(InventorySystem.create_inventory_item(load(M4)), "primary")
	service.bind_carrier(eq4, bag4)
	service.insure_manifest()
	var r4 := service.resolve_raid(Raid.Outcome.KIA, 0)
	_check(r4.insured == 0, "killer-looted item not insured (got %d)" % r4.insured)
	service.enemy_looted_paths = []

func _scenario_persistence() -> void:
	print("\n[G] market state + pending insurance survive close/reopen")
	var service := MetaService.new()
	service.save_path = SAVE
	service.use_profile(profile, SAVE)
	var eq := Equipment.new()
	var bag := Backpack.new()
	eq.equip(InventorySystem.create_inventory_item(load(M4)), "primary")
	service.bind_carrier(eq, bag)
	service.insure_manifest()
	service.resolve_raid(Raid.Outcome.KIA, 0)
	_check(profile.insurance.pending_count() == 1, "a claim is pending before saving")

	# MetaService pre-flight wrappers the HUD/arena will call.
	var saved_currency := profile.currency
	profile.currency = 0
	_check(not service.can_buy("field_surgeon", 1).get("ok", false), "Meta.can_buy reports the refusal")
	profile.currency = saved_currency
	_check(service.can_sell("field_surgeon", 1).has("ok"), "Meta.can_sell returns a verdict")
	_check(service.trader_report_lines("quartermaster").size() >= 2, "Meta.trader_report_lines() non-empty")

	var loaded := ProfileStore.load_profile(SAVE)
	_check(loaded != null, "profile reloads")
	_check(loaded.insurance.pending_count() == 1, "pending insurance persisted (%d)" % loaded.insurance.pending_count())
	loaded.market.load_dir()
	loaded.market.apply_state(loaded.progress.get("traders", {}))
	_check(loaded.market.reputation("quartermaster") == profile.market.reputation("quartermaster"), "reputation persisted (%d)" % loaded.market.reputation("quartermaster"))
	_check(loaded.market.stock_of("quartermaster", 1) == profile.market.stock_of("quartermaster", 1), "stock persisted (%d)" % loaded.market.stock_of("quartermaster", 1))
	_check(loaded.currency == profile.currency, "currency persisted (%d)" % loaded.currency)
	_check(loaded.total_exp == profile.total_exp, "EXP persisted (%d)" % loaded.total_exp)
	_check(loaded.character_level() == profile.character_level(), "character level persisted (%d)" % loaded.character_level())

# ─── HELPERS ────────────────────────────────────────

func _cleanup() -> void:
	var d := DirAccess.open(TEST_DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
