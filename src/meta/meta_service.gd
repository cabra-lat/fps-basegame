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
## Scenario-clear is the shared finite Raid outcome, not a numeric mirror.
const SCENARIO_CLEARED_OUTCOME := Raid.Outcome.SCENARIO_CLEARED
const RAID1_MARKED_INTEL_PATH := "res://resources/raid1/marked_intel.tres"
## HUB-1's deliberately small deploy contract. The hub owns selection UI, but
## MetaService remains the only authority for what may be deployed and persisted.
const DEPLOY_SLOTS: Array[String] = ["primary", "secondary"]
const REQUIRED_DEPLOY_SLOT := "primary"

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
## A resolved raid is terminal until the next prepare/deploy. This also makes a
## duplicated raid_ended signal harmless instead of applying a report twice.
var _resolved := false
## Encoded entries that could not be equipped. The selected loadout itself stays
## in the profile as a crash-recovery manifest until the raid resolves.
var _deploy_leftovers: Dictionary = {}

func _ready() -> void:
	if profile == null:
		profile = ProfileStore.load_profile(save_path)
	load_market()
	profile_loaded.emit(profile)

## Test/headless entry: adopt an in-memory profile, optionally redirect the save.
func use_profile(p: MetaProfile, path: String = "") -> void:
	profile = p
	_resolved = false
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
	# Binding a carrier establishes the next raid context. Consecutive raids may
	# resolve without a prepare call (e.g. an insurance claim), so the terminal
	# flag must clear here as well; a duplicate raid_ended on the same carrier
	# still sees _resolved and is ignored.
	_resolved = false
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
## Legacy count API: returns the number equipped, or 0 when preparation fails.
func prepare_raid() -> int:
	var result := _prepare_raid_transaction()
	return int(result.get("items_equipped", 0)) if bool(result.get("ok", false)) else 0


## Fail-closed preparation for callers that must not begin a raid after a
## persistence error. The same transaction is used by legacy prepare_raid().
func prepare_raid_checked() -> Dictionary:
	return _prepare_raid_transaction()


func _prepare_raid_transaction() -> Dictionary:
	_prepared = false
	_resolved = false
	_deploy_leftovers = {}
	# Every preparation attempt starts a new raid-insurance snapshot. This also
	# covers successful preparation with auto_insure disabled and unconfigured
	# callers; neither may inherit a manifest from an earlier raid.
	_insured_manifest = {}
	if profile == null or _equipment == null:
		return {"ok": false, "error": ERR_UNCONFIGURED, "reason": "profile or equipment unavailable", "items_equipped": 0}
	var moved := 0
	var equipped_this_call: Array = []
	for slot_name in profile.loadout:
		var pending: Array = []
		for item_data in profile.loadout[slot_name]:
			var item := ItemCodec.decode_item(item_data)
			if item != null and _equipment.equip(item, slot_name):
				equipped_this_call.append([item, slot_name])
				moved += 1
			else:
				pending.append(item_data)
		if not pending.is_empty():
			_deploy_leftovers[slot_name] = pending
	_prepared = true
	# One persistence boundary for the whole preparation. If it fails, undo
	# every carrier mutation and clear all raid-entry state, including a stale
	# insurance manifest from an earlier attempt.
	var err := _save()
	if err != OK:
		for entry in equipped_this_call:
			_equipment.unequip(entry[0] as InventoryItem, String(entry[1]))
		_prepared = false
		_deploy_leftovers = {}
		_insured_manifest = {}
		return {"ok": false, "error": err, "reason": "profile save failed", "items_equipped": 0}
	if auto_insure and _equipment != null:
		insure_manifest()
	raid_prepared.emit(moved)
	return {"ok": true, "error": OK, "reason": "", "items_equipped": moved}

## Snapshot the currently-equipped gear as the insured manifest for this raid.
func insure_manifest() -> Dictionary:
	_insured_manifest = ItemCodec.encode_equipment(_equipment) if _equipment != null else {}
	return _insured_manifest

## The heart: resolve a finished raid against the carrier and persist.
## SURVIVED/RUN_THROUGH -> carried loot to the stash, loadout kept, currency+EXP.
## KIA/MIA/LEFT_BEHIND -> equipment forfeited, loot discarded, stash untouched.
func resolve_raid(outcome: int, exp: int = 0) -> RaidReport:
	if profile == null or _resolving or _resolved:
		return null
	_resolving = true
	var report := RaidReport.new()
	report.outcome = outcome
	report.outcome_name = _outcome_name(outcome)
	report.survived = outcome == Raid.Outcome.SURVIVED \
		or outcome == Raid.Outcome.RUN_THROUGH \
		or outcome == SCENARIO_CLEARED_OUTCOME
	report.exp = maxi(exp, 0)

	var carried_loadout := ItemCodec.encode_equipment(_equipment)
	var carried_loot := ItemCodec.encode_container(_backpack)
	if report.survived:
		_resolve_survival(report, carried_loadout, carried_loot)
	else:
		_resolve_loss(report, carried_loadout, carried_loot)
	_finalize_raid(report)
	return report

func _resolve_survival(report: RaidReport, carried_loadout: Dictionary, carried_loot: Array) -> void:
	profile.survived += 1
	var value := 0
	if report.outcome == SCENARIO_CLEARED_OUTCOME:
		# The scenario's backpack filter is authoritative. Settlement banks only
		# the marked intel; ordinary medical/world loot is deliberately discarded.
		for data in carried_loot:
			if not _is_marked_intel(data):
				report.loot_discarded += 1
				continue
			var item := ItemCodec.decode_item(data)
			if item == null:
				continue
			var value_of := _item_value(item)
			if profile.stash.deposit(item, item.position):
				report.gained.append(_brief(data))
				value += value_of
			else:
				report.loot_discarded += 1
				push_warning("MetaService: scenario objective could not be stashed — %s lost" % item.name)
	else:
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
	# The equipped kit stays available for the next raid. Only entries that did
	# not equip are merged; the durable manifest is replaced, never duplicated.
	profile.loadout = _merge_loadout(carried_loadout, _deploy_leftovers) if _prepared else carried_loadout
	report.loadout_restored = true
	report.currency_delta = value + SURVIVAL_REWARD
	profile.earn_currency(report.currency_delta)

func _resolve_loss(report: RaidReport, carried_loadout: Dictionary, carried_loot: Array) -> void:
	profile.kia += 1
	for data in ItemCodec.flatten_equipment(carried_loadout):
		report.lost.append(_brief(data))
	report.loot_discarded = carried_loot.size()
	# A prepared manifest is the deployed kit, not an unowned stash copy. On
	# failure, only entries that never equipped remain recoverable.
	profile.loadout = _deploy_leftovers.duplicate(true) if _prepared else {}
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

func _finalize_raid(report: RaidReport) -> void:
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
	_deploy_leftovers = {}
	_insured_manifest = {}
	_resolving = false
	_save()
	_resolved = true
	raid_resolved.emit(report)
	report_ready.emit(report.summary())

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
			# Starter gear is non-transferable: it can be equipped and used, but it must
			# not be laundered into the shared bank (sold to a trader, bartered or listed
			# on the flea) — otherwise the once-per-faction grant is an infinite faucet.
			item.set_meta("no_transfer", true)
			arr.append(ItemCodec.encode_item(item))
			added += 1
		if not arr.is_empty():
			profile.loadout[slot_name] = arr
	if profile.currency <= 0:
		profile.currency = sl.currency
	profile.role_state()["starter_granted"] = true
	return added

## Validate a hub selection without mutating the profile. Selection values are
## ItemCodec dictionaries keyed by the two weapon sites. Each selected item must
## decode to a Weapon and match exactly one owned item in the stash or the current
## active loadout. Unknown slots, duplicate items, malformed data, and an empty
## primary are rejected before any transfer or save.
func validate_deploy(selection: Dictionary) -> Dictionary:
	if profile == null:
		return {"ok": false, "reason": "perfil ausente"}
	if selection.is_empty():
		return {"ok": false, "reason": "selecao vazia"}
	if not selection.has(REQUIRED_DEPLOY_SLOT):
		return {"ok": false, "reason": "primary obrigatorio"}
	var seen: Array[String] = []
	for slot_name in selection:
		if not DEPLOY_SLOTS.has(slot_name):
			return {"ok": false, "reason": "slot invalido: %s" % slot_name}
		var raw: Variant = selection[slot_name]
		if not (raw is Array):
			return {"ok": false, "reason": "%s deve ser uma lista" % slot_name}
		var entries: Array = raw
		if entries.size() > 1:
			return {"ok": false, "reason": "%s aceita no maximo uma arma" % slot_name}
		if entries.is_empty():
			if slot_name == REQUIRED_DEPLOY_SLOT:
				return {"ok": false, "reason": "primary obrigatorio"}
			continue
		if not (entries[0] is Dictionary):
			return {"ok": false, "reason": "%s contem dado invalido" % slot_name}
		var data: Dictionary = entries[0]
		var item := ItemCodec.decode_item(data)
		if item == null or not item.extra is Weapon:
			return {"ok": false, "reason": "%s nao e uma arma valida" % slot_name}
		var key := _selection_key(data)
		if seen.has(key):
			return {"ok": false, "reason": "arma selecionada em dois slots"}
		seen.append(key)
		if not _find_owned_item(data).has("item"):
			return {"ok": false, "reason": "arma nao pertence ao perfil: %s" % String(data.get("name", "?"))}
	return {"ok": true, "reason": "", "slots": selection.keys()}

## Read-only hub projection of the current legal kit. The opaque id is stable
## for the UI; `selection` contains the canonical ItemCodec data that must be
## passed back to validate_deploy()/deploy_loadout(). No starter is granted here.
func deploy_options() -> Dictionary:
	if profile == null:
		return {}
	var selection: Dictionary = {}
	for slot_name in DEPLOY_SLOTS:
		var raw: Variant = profile.loadout.get(slot_name, [])
		if raw is Array and not (raw as Array).is_empty():
			selection[slot_name] = (raw as Array).duplicate(true)
	if not validate_deploy(selection).get("ok", false):
		return {}
	return {
		"id": "active",
		"label": "Active kit",
		"selection": selection,
	}


## Stage the selected kit as the profile's active loadout. Items selected from the
## stash are removed exactly once; unselected items from the old kit are returned
## to the stash. The operation is persisted immediately, then prepare_raid() moves
## the staged kit into the live player carrier and persists that transfer too.
## The hub should call this before changing scene; it never writes a second save.
func deploy_loadout(selection: Dictionary) -> Dictionary:
	var check := validate_deploy(selection)
	if not check.get("ok", false):
		return check
	var old_loadout: Dictionary = profile.loadout.duplicate(true)
	var staged: Dictionary = {}
	var selected_keys: Array[String] = []
	var from_stash: Array[InventoryItem] = []
	for slot_name in selection:
		var entries: Array = selection[slot_name]
		if entries.is_empty():
			continue
		var data: Dictionary = entries[0]
		var match := _find_owned_item(data)
		var item: InventoryItem = match.get("item") as InventoryItem
		staged[slot_name] = [data.duplicate(true)]
		selected_keys.append(_selection_key(data))
		if String(match.get("source", "")) == "stash":
			from_stash.append(item)

	# Preflight the return path. Roll back anything already returned if a later
	# item cannot fit; a failed deploy must never partially rearrange ownership.
	var returned: Array[InventoryItem] = []
	for slot_name in old_loadout:
		var old_entries: Array = old_loadout[slot_name]
		for old_data in old_entries:
			if not (old_data is Dictionary):
				_rollback_deploy(old_loadout, returned, [])
				return {"ok": false, "reason": "loadout salvo contem dado invalido"}
			var old_key := _selection_key(old_data as Dictionary)
			if selected_keys.has(old_key):
				continue
			var old_item := ItemCodec.decode_item(old_data as Dictionary)
			if old_item == null:
				_rollback_deploy(old_loadout, returned, [])
				return {"ok": false, "reason": "loadout salvo contem item invalido"}
			if not profile.stash.deposit(old_item):
				_rollback_deploy(old_loadout, returned, [])
				return {"ok": false, "reason": "stash sem espaco para trocar o kit"}

	var removed_from_stash: Array[InventoryItem] = []
	for item in from_stash:
		if not profile.stash.remove_item(item):
			_rollback_deploy(old_loadout, returned, from_stash)
			return {"ok": false, "reason": "item selecionado nao pode ser retirado do stash"}
		removed_from_stash.append(item)
	profile.loadout = staged
	_resolved = false
	var err := _save()
	if err != OK:
		# Best-effort rollback keeps the same ownership contract if persistence is
		# unavailable; the caller receives the error and can retry or leave the hub.
		_rollback_deploy(old_loadout, returned, from_stash)
		return {"ok": false, "reason": "falha ao salvar kit: %d" % err}
	return {"ok": true, "reason": "", "loadout": staged.duplicate(true)}


func _rollback_deploy(old_loadout: Dictionary, returned: Array[InventoryItem], selected_from_stash: Array[InventoryItem]) -> void:
	for item in selected_from_stash:
		if profile.stash.items.has(item):
			continue
		if not profile.stash.deposit(item):
			push_error("MetaService: rollback could not restore selected stash item %s" % item.name)
	for item in returned:
		profile.stash.remove_item(item)
	profile.loadout = old_loadout


func _is_marked_intel(data: Dictionary) -> bool:
	if String(data.get("path", "")) == RAID1_MARKED_INTEL_PATH:
		return true
	var item := ItemCodec.decode_item(data)
	return item != null and ItemCodec.content_path(item) == RAID1_MARKED_INTEL_PATH


func _selection_key(data: Dictionary) -> String:
	var item := ItemCodec.decode_item(data)
	return JSON.stringify(ItemCodec.encode_item(item)) if item != null else JSON.stringify(data)


func _find_owned_item(data: Dictionary) -> Dictionary:
	if profile == null:
		return {}
	var key := _selection_key(data)
	for item in profile.stash.items:
		if _selection_key(ItemCodec.encode_item(item)) == key:
			return {"item": item, "source": "stash"}
	for slot_name in profile.loadout:
		var entries: Array = profile.loadout[slot_name]
		for old_data in entries:
			if old_data is Dictionary and _selection_key(old_data as Dictionary) == key:
				var old_item := ItemCodec.decode_item(old_data as Dictionary)
				if old_item != null:
					return {"item": old_item, "data": old_data, "source": "loadout"}
	return {}

func reload() -> MetaProfile:
	_resolved = false
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

func _save() -> Error:
	var err := ProfileStore.save(profile, save_path)
	if err != OK:
		push_error("MetaService: profile save failed (err %d)" % err)
		save_failed.emit(err)
	else:
		profile_saved.emit()
	return err

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
		SCENARIO_CLEARED_OUTCOME: return "SCENARIO CLEARED"
		Raid.Outcome.MIA: return "MIA"
		Raid.Outcome.KIA: return "KIA"
		Raid.Outcome.LEFT_BEHIND: return "LEFT BEHIND"
		_: return "—"
