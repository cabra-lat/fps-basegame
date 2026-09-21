# res://src/meta/meta_profile.gd
class_name MetaProfile
extends PlayerProfile
## Persistent player profile. Extends the range's PlayerProfile (faction, team,
## currency, key-item inventory) so extraction gates keep working unchanged —
## this is the same profile object, not a fork. Adds what survives a restart:
## the stash, the equipped loadout, progression placeholders, counters and the
## last raid report.

## Save format version. v2 = `faction` is a String id into the faction pack; v1
## stored the index of a two-value enum. Old saves are converted by `migrate()`,
## so the bump is an explicit, tested conversion instead of a read-time guess.
## `ProfileStore` never quarantines a save it can migrate.
const VERSION := 2

var version: int = VERSION
var stash: Stash
## slot_name -> Array[Dictionary] (ItemCodec encoding). Items in "body" state
## while a raid runs; restored on survival, forfeited on death. This is the kit of
## the ACTIVE faction (`faction`); every other faction's kit lives in `roles`.
var loadout: Dictionary = {}
## Per-faction state, keyed by the faction id (the same axis `faction` and
## `ExtractionPoint.allowed_factions` use — one axis, not a second "role" concept):
##   { faction_id: { "kit": Dictionary, "karma": int,
##                   "raids": int, "survived": int, "kia": int,
##                   "starter_granted": bool } }
## ADDITIVE key: an older save (v2) loads with `roles` empty and behaves exactly as
## before, so this needs NO version bump — `from_dict` defaults it.
var roles: Dictionary = {}
## Reserved for later phases; shape lives in the save from day one.
var progress: Dictionary = {"skills": {}, "quests": {}, "traders": {}, "insurance": {}, "flea": {}}
var total_exp: int = 0
var raids: int = 0
var survived: int = 0
var kia: int = 0
var last_report: Dictionary = {}
var skills: SkillSet
var quests: QuestLog
var market: Market
var insurance: Insurance
var flea: FleaMarket

## 1 character level per XP_PER_LEVEL total XP (kept simple; the trader loyalty
## gate only needs a monotonic level from the XP the profile already tracks).
const XP_PER_LEVEL := 1000
const MAX_CHARACTER_LEVEL := 50

func _init() -> void:
	stash = Stash.new()
	skills = SkillSet.new()
	quests = QuestLog.new()
	market = Market.new()
	market.setup(self)
	insurance = Insurance.new()
	flea = FleaMarket.new()
	flea.setup(self)

func character_level() -> int:
	return clampi(1 + int(total_exp / XP_PER_LEVEL), 1, MAX_CHARACTER_LEVEL)

# ─── PER-FACTION STATE (one axis: the faction id is the key) ───

## State of `faction_id` (defaults to the active faction), created on first use so
## callers never have to deal with a missing key.
func role_state(faction_id: String = "") -> Dictionary:
	var id := faction_id if faction_id != "" else faction
	if id == "":
		id = PlayerProfile.DEFAULT_FACTION
	if not roles.has(id) or not (roles[id] is Dictionary):
		roles[id] = _fresh_role_state()
	return roles[id]

static func _fresh_role_state() -> Dictionary:
	return {"kit": {}, "karma": 0, "raids": 0, "survived": 0, "kia": 0, "starter_granted": false}

## The kit of `faction_id`: the LIVE `loadout` when it is the active faction, else
## its stored kit. Keeping exactly one copy is what makes the switch conservative
## (nothing is duplicated into both a role slot and the active slot).
func role_kit(faction_id: String) -> Dictionary:
	if faction_id == faction:
		return loadout
	return role_state(faction_id)["kit"] as Dictionary

## Switch the active faction BETWEEN raids. The two kits are SWAPPED, never copied:
## the active kit is stored in the outgoing faction's slot and the incoming
## faction's kit becomes active. Mass over `stash + loadout + all role kits` is
## therefore identical before and after.
## The caller is responsible for the "between raids" part (MetaService.set_active_role
## refuses while a raid is prepared/running).
func switch_faction(target_id: String) -> Dictionary:
	if target_id == "":
		return {"ok": false, "reason": "faccao invalida"}
	if target_id == faction:
		return {"ok": false, "reason": "ja e' a faccao ativa"}
	role_state(faction)["kit"] = loadout.duplicate(true)
	var incoming: Dictionary = role_state(target_id)["kit"]
	loadout = incoming.duplicate(true)
	faction = target_id
	return {"ok": true, "reason": ""}

## Push the live skill/quest/market/insurance objects into the raw progress dict
## before saving.
func sync_progress() -> void:
	if skills != null:
		progress["skills"] = skills.to_dict()
	if quests != null:
		progress["quests"] = quests.to_dict()
	if market != null:
		progress["traders"] = market.to_dict()
	if insurance != null:
		progress["insurance"] = insurance.to_dict()
	if flea != null:
		progress["flea"] = flea.to_dict()

func stash_item_count() -> int:
	return stash.count_items() if stash != null else 0

func to_dict() -> Dictionary:
	sync_progress()
	return {
		"version": VERSION,
		# [range 2026-09-21] faction became a String id (faction pack, "faction is
		# content, not an enum"). The save-format side is the meta lane's: v2 stores
		# the id, and ProfileStore migrates a v1 save through MetaProfile.migrate()
		# instead of quarantining it (see the VERSION docs at the top of this file).
		"faction": faction,
		"team": team,
		"currency": currency,
		"inventory": inventory,
		"raids": raids,
		"survived": survived,
		"kia": kia,
		"total_exp": total_exp,
		"progress": progress,
		"last_report": last_report,
		"stash": {
			"width": stash.grid_width,
			"height": stash.grid_height,
			"max_weight": stash.max_weight,
			"items": ItemCodec.encode_container(stash),
		},
		"loadout": loadout,
		# ADDITIVE (no version bump): an older v2 save has no `roles` and loads with
		# it empty, behaving exactly as before. See the `roles` docs on the var.
		"roles": roles,
	}

static func from_dict(data: Dictionary) -> MetaProfile:
	var p := MetaProfile.new()
	# [range 2026-09-21] accepts both shapes: a String id (current) and the legacy
	# numeric index of the old two-value enum (migrated loudly in faction_from_saved).
	p.faction = PlayerProfile.faction_from_saved(data.get("faction", p.faction))
	p.team = int(data.get("team", 0))
	p.currency = int(data.get("currency", p.currency))
	var inv = data.get("inventory", {})
	if inv is Dictionary:
		p.inventory = inv
	p.raids = int(data.get("raids", 0))
	p.survived = int(data.get("survived", 0))
	p.kia = int(data.get("kia", 0))
	p.total_exp = int(data.get("total_exp", 0))
	var prog = data.get("progress", null)
	if prog is Dictionary:
		p.progress = prog
	# Skills are self-contained; quest definitions live outside the save and
	# their saved progress is re-applied after the quest pack is loaded.
	p.skills = SkillSet.from_dict(prog.get("skills", {}) if prog is Dictionary else {})
	if prog is Dictionary:
		p.insurance.apply_state(prog.get("insurance", {}))
		p.flea.apply_state(prog.get("flea", {}))
	# Trader definitions are loaded later; their saved state is re-applied then.
	var lr = data.get("last_report", {})
	if lr is Dictionary:
		p.last_report = lr
	_restore_stash(p, data.get("stash", {}))
	var lo = data.get("loadout", {})
	if lo is Dictionary:
		p.loadout = lo
	var rl = data.get("roles", {})
	if rl is Dictionary:
		p.roles = rl
	if not data.has("roles"):
		# Legacy save (written before per-faction state). "Already has gear" means
		# "already granted", so a migrated profile cannot claim a second starter kit
		# for its active faction — the old guard was exactly this test.
		if not p.loadout.is_empty() or p.stash_item_count() > 0:
			p.role_state()["starter_granted"] = true
	return p

static func _restore_stash(p: MetaProfile, sd) -> void:
	if not (sd is Dictionary):
		return
	var s := sd as Dictionary
	p.stash = Stash.new()
	p.stash.grid_width = maxi(int(s.get("width", Stash.DEFAULT_WIDTH)), 1)
	p.stash.grid_height = maxi(int(s.get("height", Stash.DEFAULT_HEIGHT)), 1)
	p.stash.max_weight = float(s.get("max_weight", Stash.DEFAULT_MAX_WEIGHT))
	var g := p.stash.grid
	g.width = p.stash.grid_width
	g.height = p.stash.grid_height
	g._reset_grid()
	for item_data in s.get("items", []):
		var item := ItemCodec.decode_item(item_data)
		if item == null:
			continue
		if not p.stash.add_item(item, item.position):
			p.stash.add_item(item, Vector2i(-1, -1))

# ─── MIGRATION ──────────────────────────────────────

## Convert an older save dictionary up to VERSION, one explicit step at a time.
## Each step is a pure function on the dict that bumps `version`; the chain runs
## from the save's version to VERSION. A missing step is a HARD STOP — the caller
## (`ProfileStore.load_profile`) quarantines rather than loading a half-converted
## save. Returns the input unchanged if no step applies.
static func migrate(data: Dictionary) -> Dictionary:
	var out := data
	var v := int(out.get("version", -1))
	var steps := 0
	while v < VERSION:
		steps += 1
		if steps > 64:
			push_error("MetaProfile.migrate: loop guard tripped at v%d" % v)
			return out
		match v:
			1:
				out = _migrate_1_to_2(out)
			_:
				push_error("MetaProfile.migrate: no migration step from v%d" % v)
				return out
		var next_v := int(out.get("version", v))
		if next_v <= v:
			push_error("MetaProfile.migrate: step from v%d did not advance the version" % v)
			return out
		v = next_v
	return out

## v1 -> v2: `faction` stopped being an index into the old two-value enum and
## became a String id into the faction pack. The index is translated explicitly
## (never guessed) and the save is rewritten in the new shape on the next save.
static func _migrate_1_to_2(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	out["faction"] = PlayerProfile.faction_from_saved(out.get("faction", PlayerProfile.DEFAULT_FACTION))
	out["version"] = 2
	return out
