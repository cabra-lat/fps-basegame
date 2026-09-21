# res://scenes/validate_factions.gd
#
# Headless proof for the project rule "mechanics may be an enum, content must be
# data" applied to factions (and for the identity rule that follows from it:
# no commercial-game faction names in shipped content).
#
#   [1] the pack loads N factions from resources/meta/factions/*.tres, ids are
#       unique/non-empty, display names are data (never a code literal)
#   [2] registry API is a real registry: lookup, count, playable subset and a
#       corrupted pack (duplicate/empty id) is rejected instead of half-loaded
#   [3] the count is NOT hardcoded to two: an in-memory pack of five factions
#       works with zero code change (the property the enum could not have)
#   [4] PlayerProfile.faction is a String id; the display name is mounted from
#       the pack; an NPC-only faction and an unknown id fail validation
#   [5] ExtractionPoint.allowed_factions: EMPTY accepts any faction; a restricted
#       point accepts its own and REFUSES every other one (reason names the pack)
#   [6] legacy v1 numeric saves are migrated explicitly, and no shipped scene
#       still carries the old faction proper nouns (regression guard)
#
# Run:
#   godot --headless --path . --script res://scenes/validate_factions.gd
# Exit code: 0 = every check passed, 1 = at least one failure.
extends SceneTree

const PACK_DIR := "res://resources/meta/factions"

var v: ValidateUtil


func _initialize() -> void:
	v = ValidateUtil.new("validate_factions")
	v.begin()
	_scenario_pack()
	_scenario_generalizes_to_n()
	_scenario_profile()
	_scenario_extraction_gate()
	_scenario_legacy_and_compliance()
	quit(v.finish())


# ─── [1][2] THE SHIPPED PACK ────────────────────────

func _scenario_pack() -> void:
	v.section("[1/2] faction pack: data, unique ids, honest rejects")
	var reg := FactionRegistry.new()
	var n := reg.load_dir(PACK_DIR)
	v.check(n >= 3, "pack loads at least 3 factions (got %d)" % n)
	v.check(reg.count() == n, "count() matches what load_dir() added (%d)" % reg.count())

	var seen := {}
	for f in reg.all():
		v.check(f.id != "", "faction '%s' has a non-empty id" % f.resource_path)
		v.check(not seen.has(f.id), "faction id '%s' is unique" % f.id)
		seen[f.id] = true
		v.check(f.resolved_name() != "", "faction '%s' resolves a display name" % f.id)
		# Data, not a literal: the name comes from the .tres, and the pack is the
		# only place a name may live. Proves the registry mounts pack data.
		var from_disk := (load(f.resource_path) as Faction).display_name
		v.check(f.display_name == from_disk, "faction '%s' name is read from its .tres" % f.id)

	var playable := reg.playable()
	v.check(playable.size() >= 1, "pack has at least one playable faction (%d)" % playable.size())
	v.check(playable.size() < reg.count(), "pack proves playable != all: an NPC-only faction exists")
	for f in playable:
		v.check(f.playable, "playable() only yields playable factions ('%s')" % f.id)

	v.check(reg.has(reg.ids()[0]), "has() is true for a packed id")
	v.check(not reg.has("no_such_faction"), "has() is false for an unknown id")
	v.check(reg.get_faction("no_such_faction") == null, "get_faction() returns null for an unknown id")
	v.check(reg.require("no_such_faction") == null, "require() returns null for an unknown id (and reports)")
	v.check(reg.display_name(reg.ids()[0]) == reg.get_faction(reg.ids()[0]).resolved_name(),
		"display_name() mounts the pack name for a valid id")

	# A bad pack must not half-load: duplicate and empty ids are refused.
	var before := reg.count()
	var dup := reg.get_faction(reg.ids()[0]).duplicate() as Faction
	v.check(not reg.add(dup), "duplicate id is refused")
	var blank := Faction.new()
	v.check(not reg.add(blank), "faction with an empty id is refused")
	v.check(reg.count() == before, "refused factions did not enter the pack (%d)" % reg.count())


# ─── [3] N FACTIONS, NOT TWO ────────────────────────

func _scenario_generalizes_to_n() -> void:
	v.section("[3] the same code holds N factions (the enum could not)")
	var reg := FactionRegistry.new()
	for i in range(5):
		var f := Faction.new()
		f.id = "faction_%d" % i
		f.display_name = "Faction %d" % i
		f.playable = i % 2 == 0
		f.color = Color(float(i) / 5.0, 0.5, 1.0, 1.0)
		v.check(reg.add(f), "in-memory faction %d registered from data alone" % i)
	v.check(reg.count() == 5, "registry holds 5 factions (got %d)" % reg.count())
	v.check(reg.playable().size() == 3, "playable subset is data-driven (3 of 5)")
	v.check(reg.ids() == ["faction_0", "faction_1", "faction_2", "faction_3", "faction_4"],
		"ids() keeps a stable order for UI listing")

	# A gate restricted to THREE ids, over a five-faction pack.
	var profile := PlayerProfile.new()
	var ep := ExtractionPoint.new()
	var allowed: Array[String] = ["faction_1", "faction_3", "faction_4"]
	ep.allowed_factions = allowed
	ep.bind(profile, null, reg)
	profile.faction = "faction_3"
	v.check(ep.can_use().get("ok", false), "restricted gate accepts a faction inside its list")
	profile.faction = "faction_0"
	var res := ep.can_use()
	v.check(not res.get("ok", false), "restricted gate refuses a faction outside its list")
	v.check(String(res.get("reason", "")) == "apenas Faction 1, Faction 3, Faction 4",
		"refusal names exactly the allowed factions (got '%s')" % String(res.get("reason", "")))
	ep.free()


# ─── [4] THE PROFILE CARRIES AN ID, NOT AN ENUM ─────

func _scenario_profile() -> void:
	v.section("[4] PlayerProfile.faction is a String id from the pack")
	var reg := FactionRegistry.default_registry()
	var p := PlayerProfile.new()
	v.check(p.faction is String, "faction is a String at rest (got %s)" % type_string(typeof(p.faction)))
	v.check(reg.has(p.faction), "the default faction id exists in the pack ('%s')" % p.faction)

	p.faction = "drifter"
	v.check(p.faction_name(reg) == reg.display_name("drifter"), "faction_name() mounts the pack name")
	v.check(p.faction_name(reg) != p.faction, "the mounted name is not the raw id ('%s' vs '%s')" % [p.faction_name(reg), p.faction])
	v.check(p.faction_color(reg) == reg.color("drifter"), "faction_color() mounts the pack colour")
	v.check(p.validate_faction(reg), "a packed, playable faction validates")

	if reg.playable().size() < reg.count():
		var npc_only := ""
		for f in reg.all():
			if not f.playable:
				npc_only = f.id
		p.faction = npc_only
		v.check(not p.validate_faction(reg), "NPC-only faction fails validate_faction() ('%s')" % npc_only)
		p.faction = "ghost_faction"
		v.check(not p.validate_faction(reg), "unknown faction id fails validate_faction()")
		# Also proves the lookup path a player profile uses does not invent one.
		var missing := reg.get_faction("ghost_faction")
		v.check(missing == null, "unknown id resolves to null, never a default faction")


# ─── [5] THE EXTRACTION GATE ────────────────────────

func _scenario_extraction_gate() -> void:
	v.section("[5] ExtractionPoint.allowed_factions gates with data")
	var reg := FactionRegistry.default_registry()
	var p := PlayerProfile.new()

	var open := ExtractionPoint.new()
	open.bind(p, null, reg)
	v.check(open.allowed_factions.is_empty(), "a fresh point defaults to open (empty list)")
	for f in reg.all():
		p.faction = f.id
		v.check(open.can_use().get("ok", false), "empty allowed_factions accepts '%s'" % f.id)
	v.check(open.faction_gate_text() == "", "an open point renders no faction restriction")
	open.free()

	var restricted := ExtractionPoint.new()
	var allowed: Array[String] = ["contractor"]
	restricted.allowed_factions = allowed
	restricted.bind(p, null, reg)
	p.faction = "contractor"
	v.check(restricted.can_use().get("ok", false), "point restricted to contractor accepts contractor")
	v.check(restricted.faction_gate_text() == "apenas Contractor",
		"gate text is mounted from the pack (got '%s')" % restricted.faction_gate_text())
	for blocked in ["drifter", "raider"]:
		p.faction = blocked
		var res := restricted.can_use()
		v.check(not res.get("ok", false), "point restricted to contractor REFUSES '%s'" % blocked)
		v.check(String(res.get("reason", "")) == "apenas Contractor",
			"refusal for '%s' names the allowed faction (got '%s')" % [blocked, String(res.get("reason", ""))])
	restricted.free()


# ─── [6] LEGACY SAVES + IDENTITY REGRESSION GUARD ───

func _scenario_legacy_and_compliance() -> void:
	v.section("[6] legacy save migration + no old proper nouns in the pack or scenes")
	var reg := FactionRegistry.default_registry()
	var migrated := PlayerProfile.faction_from_saved(0)
	v.check(migrated == "contractor", "legacy numeric 0 migrates to the pack's first faction")
	v.check(reg.has(migrated), "the migrated id exists in the pack")
	v.check(PlayerProfile.faction_from_saved(1) == "drifter", "legacy numeric 1 migrates to the second")
	v.check(PlayerProfile.faction_from_saved(99) == PlayerProfile.DEFAULT_FACTION,
		"an out-of-range legacy number reports and falls back to the default")
	v.check(PlayerProfile.faction_from_saved("drifter") == "drifter", "a String id round-trips untouched")

	# Terms are assembled here so this guard does not match its own source.
	var banned: Array[String] = ["P" + "MC", "SC" + "AV", "roub" + "les"]
	var offenders: Array[String] = []
	for dir in ["res://scenes", "res://resources/meta/factions"]:
		_scan(dir, banned, offenders)
	v.check(offenders.is_empty(), "no old faction/currency proper nouns in shipped scenes/pack (%s)"
		% (", ".join(PackedStringArray(offenders)) if not offenders.is_empty() else "clean"))


func _scan(dir: String, banned: Array[String], offenders: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if not (f.ends_with(".gd") or f.ends_with(".tscn") or f.ends_with(".tres")):
			continue
		var text := FileAccess.get_file_as_string(dir + "/" + f)
		for term in banned:
			if text.contains(term):
				offenders.append("%s/%s:%s" % [dir, f, term])
	for sub in d.get_directories():
		_scan(dir + "/" + sub, banned, offenders)
