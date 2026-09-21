# res://src/meta/meta_service.gd
class_name MetaService
extends Node
## The consumer the raid event bus was built for. Owns the persistent profile,
## wires the raid bus to end-of-raid resolution and exposes the between-raid
## loadout API. No combat code, no player code, no mandatory UI.
##
## Wiring (one lazy block in a scene manager):
##   var meta := MetaService.new()
##   meta.bind_carrier(player.equipment, player.get_equipped_backpack())
##   meta.bind_raid(raid)
##   meta.prepare_raid()           # before raid.begin()
## Then `raid_ended(outcome)` resolves automatically and saves.

signal profile_loaded(profile: MetaProfile)
signal profile_saved
signal save_failed(err: int)
signal raid_prepared(items_equipped: int)
signal raid_resolved(report: RaidReport)
signal report_ready(summary: String)
## Insurance hook (later phase): fired on KIA/MIA with the forfeited loadout so
## the feature can return gear without reworking resolution.
signal insurance_claim_available(lost: Array)

const SURVIVAL_REWARD := 5000 # credits for getting out alive

var profile: MetaProfile
var raid: Raid
var save_path: String = ProfileStore.PATH
## Skills + quests (lazy). Created by enable_progression().
var progression: Progression
## Compose an insurance manifest from the equipped gear on prepare_raid().
var auto_insure: bool = true
## Content paths an enemy looted off the corpse (excluded from insurance returns).
var enemy_looted_paths: Array[String] = []

var _insured_manifest: Dictionary = {}

var _equipment: Equipment
var _backpack: InventoryContainer
var _prepared := false
var _resolving := false

func _ready() -> void:
	if profile == null:
		profile = ProfileStore.load_profile(save_path)
	load_market()
	profile_loaded.emit(profile)

## Test/headless entry: adopt an in-memory profile, optionally redirect the save.
func use_profile(p: MetaProfile, path: String = "") -> void:
	profile = p
	if path != "":
		save_path = path
	if profile == null:
		profile = MetaProfile.new()
	load_market()
	profile_loaded.emit(profile)
	if progression != null:
		progression.setup(profile, Callable(self, "persist"))
		progression.load_quests()

func bind_raid(p_raid: Raid) -> void:
	if raid == p_raid:
		return
	if raid != null and raid.raid_ended.is_connected(_on_raid_ended):
		raid.raid_ended.disconnect(_on_raid_ended)
	raid = p_raid
	if raid != null and not raid.raid_ended.is_connected(_on_raid_ended):
		raid.raid_ended.connect(_on_raid_ended)

func bind_carrier(equipment: Equipment, backpack: InventoryContainer) -> void:
	_equipment = equipment
	_backpack = backpack

## Create/refresh the skills+quests consumer. `with_save` wires it to this
## service's save path; pass false in tests that own persistence themselves.
func enable_progression(with_save: bool = true, load_quest_pack: bool = true) -> Progression:
	if progression == null:
		progression = Progression.new()
		progression.name = "Progression"
		add_child(progression)
	var cb := Callable(self, "persist") if with_save else Callable()
	progression.setup(profile, cb)
	if load_quest_pack:
		progression.load_quests()
	return progression

## Public save entry (Progression's callback).
func persist() -> void:
	_save()

## Load the trader pack and re-apply saved market state (stock/rep/reset).
## Also restocks the flea with NPC listings when it is empty.
func load_market(dir: String = Market.TRADERS_DIR) -> int:
	if profile == null:
		return 0
	var n := profile.market.load_dir(dir)
	profile.market.apply_state(profile.progress.get("traders", {}))
	if profile.flea.listings.is_empty():
		profile.flea.seed_from_market(profile.market)
	return n

## Economy API for the range/HUD. Both return {ok, reason, ...}.
func buy(trader_id: String, offer_index: int) -> Dictionary:
	return profile.market.buy(trader_id, offer_index) if profile != null else {"ok": false, "reason": "sem perfil"}

func sell(trader_id: String, offer_index: int) -> Dictionary:
	return profile.market.sell(trader_id, offer_index) if profile != null else {"ok": false, "reason": "sem perfil"}

## Pre-flight checks for a UI that must grey out / explain an offer.
func can_buy(trader_id: String, offer_index: int) -> Dictionary:
	return profile.market.can_buy(trader_id, offer_index) if profile != null else {"ok": false, "reason": "sem perfil"}

func can_sell(trader_id: String, offer_index: int) -> Dictionary:
	return profile.market.can_sell(trader_id, offer_index) if profile != null else {"ok": false, "reason": "sem perfil"}

func trader_report_lines(trader_id: String) -> Array[String]:
	return profile.market.report_lines(trader_id) if profile != null else [] as Array[String]

# ─── FLEA MARKET (second sink; same validation path) ───

func list_on_flea(path: String, price: int) -> Dictionary:
	return profile.flea.list_from_stash(path, price) if profile != null else {"ok": false, "reason": "sem perfil"}

func buy_flea(listing_id: int) -> Dictionary:
	return profile.flea.buy(listing_id) if profile != null else {"ok": false, "reason": "sem perfil"}

func cancel_flea(listing_id: int) -> Dictionary:
	return profile.flea.cancel(listing_id) if profile != null else {"ok": false, "reason": "sem perfil"}

## Fee the player pays to list at `price` (show it before confirming).
func flea_listing_fee(price: int) -> int:
	return profile.flea.listing_fee(price) if profile != null else 0

func flea_report_lines(only_active: bool = true) -> Array[String]:
	return profile.flea.report_lines(only_active) if profile != null else [] as Array[String]

## Move the persisted loadout onto the player. Runs before the raid starts.
## Un-decodable entries stay in the profile instead of being silently lost.
func prepare_raid() -> int:
	_prepared = false
	if profile == null or _equipment == null:
		return 0
	var remaining := {}
	var moved := 0
	for slot_name in profile.loadout:
		var pending: Array = []
		for item_data in profile.loadout[slot_name]:
			var item := ItemCodec.decode_item(item_data)
			if item != null and _equipment.equip(item, slot_name):
				moved += 1
			else:
				pending.append(item_data)
		if not pending.is_empty():
			remaining[slot_name] = pending
	profile.loadout = remaining
	_prepared = true
	if auto_insure and _equipment != null:
		insure_manifest()
	raid_prepared.emit(moved)
	return moved

## Snapshot the currently-equipped gear as the insured manifest for this raid.
func insure_manifest() -> Dictionary:
	_insured_manifest = ItemCodec.encode_equipment(_equipment) if _equipment != null else {}
	return _insured_manifest

## The heart: resolve a finished raid against the carrier and persist.
## SURVIVED/RUN_THROUGH -> carried loot to the stash, loadout kept, currency+EXP.
## KIA/MIA/LEFT_BEHIND -> equipment forfeited, loot discarded, stash untouched.
func resolve_raid(outcome: int, exp: int = 0) -> RaidReport:
	if profile == null or _resolving:
		return null
	_resolving = true
	var report := RaidReport.new()
	report.outcome = outcome
	report.outcome_name = _outcome_name(outcome)
	report.survived = outcome == Raid.Outcome.SURVIVED or outcome == Raid.Outcome.RUN_THROUGH
	report.exp = maxi(exp, 0)

	var carried_loadout := ItemCodec.encode_equipment(_equipment)
	var carried_loot := ItemCodec.encode_container(_backpack)

	if report.survived:
		profile.survived += 1
		var value := 0
		for data in carried_loot:
			var item := ItemCodec.decode_item(data)
			if item == null:
				continue
			var value_of := _item_value(item)
			if profile.stash.deposit(item, item.position):
				report.gained.append(_brief(data))
				value += value_of
			else:
				push_warning("MetaService: stash full — %s lost" % item.name)
		# The equipped kit stays available for the next raid. Any loadout entry
		# prepare_raid() could not equip (leftover) is preserved, not lost.
		profile.loadout = _merge_loadout(carried_loadout, profile.loadout) if _prepared else carried_loadout
		report.loadout_restored = true
		report.currency_delta = value + SURVIVAL_REWARD
		profile.earn_currency(report.currency_delta)
	else:
		profile.kia += 1
		for data in ItemCodec.flatten_equipment(carried_loadout):
			report.lost.append(_brief(data))
		report.loot_discarded = carried_loot.size()
		# Equipped gear is forfeited. When prepare_raid() ran, profile.loadout
		# already holds only the leftovers (nothing equipped), so keep them;
		# otherwise the whole persisted loadout is considered deployed and lost.
		if not _prepared:
			profile.loadout = {}
		if not report.lost.is_empty():
			insurance_claim_available.emit(report.lost.duplicate(true))
		# Insurance: the manifest composed at raid entry is what can come back.
		# No-return maps and killer-looted items never do.
		var manifest := _insured_manifest if not _insured_manifest.is_empty() else carried_loadout
		var no_return := false
		if raid != null:
			no_return = bool(raid.get_meta("no_return", false))
		var insured_count := profile.insurance.register_loss(
			ItemCodec.flatten_equipment(manifest), profile, no_return, enemy_looted_paths)
		report.insured = insured_count

	# Due insurance claims are delivered on the NEXT resolved raid (register_loss
	# uses the current raid counter, so process before incrementing it).
	profile.insurance.process_returns(profile)
	profile.raids += 1
	# Per-faction counters (the faction is the axis: `role_state()` is the ACTIVE one).
	var role := profile.role_state()
	role["raids"] = int(role["raids"]) + 1
	if report.survived:
		role["survived"] = int(role["survived"]) + 1
	else:
		role["kia"] = int(role["kia"]) + 1
	profile.total_exp += report.exp
	# Stock reset counter advances on every resolved raid; flea listings expire
	# and fair-priced ones sell on the same raid clock.
	profile.market.on_raid_resolved()
	profile.flea.on_raid_resolved()
	profile.last_report = report.to_dict()
	_prepared = false
	_insured_manifest = {}
	_resolving = false
	_save()
	raid_resolved.emit(report)
	report_ready.emit(report.summary())
	return report

func _merge_loadout(body: Dictionary, leftovers: Dictionary) -> Dictionary:
	var merged := body.duplicate(true)
	for slot_name in leftovers:
		if not merged.has(slot_name):
			merged[slot_name] = (leftovers[slot_name] as Array).duplicate(true)
		else:
			var arr: Array = merged[slot_name]
			for data in leftovers[slot_name]:
				arr.append(data)
	return merged

## Choose the faction the NEXT raid starts as. Legal only BETWEEN raids: a prepared
## or running raid owns the active kit, and switching then would strand it. The
## switch itself is a two-slot SWAP of kits (never a copy) — see
## `MetaProfile.switch_faction`. Returns {ok, reason} like the economy API.
func set_active_role(faction_id: String) -> Dictionary:
	if profile == null:
		return {"ok": false, "reason": "sem perfil"}
	if _prepared or (raid != null and raid.is_active()):
		return {"ok": false, "reason": "raid em andamento"}
	return profile.switch_faction(faction_id)

## Seed a fresh profile with the starting kit (only when truly empty).
## The starter kit is granted ONCE PER FACTION (`roles[id].starter_granted`): with a
## second playable faction, the old "profile is empty" guard would either hand out a
## free kit on every switch or none at all.
func grant_starter_loadout(sl: StarterLoadout) -> int:
	if sl == null or profile == null:
		return 0
	if bool(profile.role_state().get("starter_granted", false)):
		return 0
	var added := 0
	for slot_name in sl.slots:
		var arr: Array = []
		for path in sl.slots[slot_name]:
			var item := ItemCodec.item_from_path(String(path))
			if item == null:
				continue
			arr.append(ItemCodec.encode_item(item))
			added += 1
		if not arr.is_empty():
			profile.loadout[slot_name] = arr
	if profile.currency <= 0:
		profile.currency = sl.currency
	profile.role_state()["starter_granted"] = true
	return added

func reload() -> MetaProfile:
	profile = ProfileStore.load_profile(save_path)
	profile_loaded.emit(profile)
	return profile

func report_text() -> String:
	if profile == null or profile.last_report.is_empty():
		return ""
	return RaidReport.from_dict(profile.last_report).summary()

func _on_raid_ended(outcome: int) -> void:
	if _equipment == null and _backpack == null:
		return # nobody to resolve; stay out of the way
	var exp := raid.exp if raid != null else 0
	resolve_raid(outcome, exp)

func _save() -> void:
	var err := ProfileStore.save(profile, save_path)
	if err != OK:
		push_error("MetaService: profile save failed (err %d)" % err)
		save_failed.emit(err)
	else:
		profile_saved.emit()

func _item_value(item: InventoryItem) -> int:
	var content = item.extra
	if content == null:
		return 0
	if content is Attachment:
		return maxi((content as Attachment).cost, 0)
	var c = content.get("cost")
	if c is int or c is float:
		return maxi(int(c), 0)
	return 0

func _brief(data: Dictionary) -> Dictionary:
	return {
		"name": String(data.get("name", "?")),
		"path": String(data.get("path", "")),
		"stack": int(data.get("stack", 1)),
	}

func _outcome_name(outcome: int) -> String:
	match outcome:
		Raid.Outcome.SURVIVED: return "SURVIVED"
		Raid.Outcome.RUN_THROUGH: return "RUN THROUGH"
		Raid.Outcome.MIA: return "MIA"
		Raid.Outcome.KIA: return "KIA"
		Raid.Outcome.LEFT_BEHIND: return "LEFT BEHIND"
		_: return "—"
