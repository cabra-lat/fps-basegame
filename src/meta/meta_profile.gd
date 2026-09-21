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
## while a raid runs; restored on survival, forfeited on death.
var loadout: Dictionary = {}
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
