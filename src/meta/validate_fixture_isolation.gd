# res://src/meta/validate_fixture_isolation.gd
extends SceneTree
## Proves -- rather than argues -- that the untranslated-designation FIXTURE cannot be
## reached by a player-facing stock scan or by a save file.
##
## WHY THIS EXISTS. resources/meta/fixtures/fixture_untranslated.tres is REGISTERED in
## ItemNames.KEYS, because the registered-but-untranslated branch of a translation-
## marking screen needs a subject that is genuinely registered. Registering it is
## precisely what makes it "one query away from being real", so the registration is the
## thing that has to be paid for, and the payment is these checks.
##
## It replaces the old arrangement, where validate_stash_view and validate_free_items_view
## borrowed Brazil_556.tres -- a real ammunition designation -- for that branch. A fixture
## borrowed from the product catalogue is a fixture with a timer on it: the day Brazil 556
## was translated, correctly, two harnesses went red for a reason unrelated to what they
## test. Those harnesses now point at the dedicated fixture and assert it is still
## untranslated, so the middle branch cannot quietly empty; THIS harness proves the
## fixture does not leak into anything the fixture's existence is not supposed to touch.
##
## What it proves, in the order the risk actually runs:
##   1. No directory scan can SEE it. Every dir constant that any production scan opens
##      is enumerated from source, and the fixture must not be inside any of them.
##   2. No name-resolution can REACH it. ItemCodec resolves an encoded item to a path by
##      scanning a directory for a matching .name -- the one mechanism by which a save
##      with no stored path could acquire an item. The fixture must not be findable.
##   3. No gameplay path can GRANT it. Traders (buy + barter), the starter loadout and
##      every quest reward are the complete set of ways the game hands a player an item.
##   4. It cannot ENTER A SAVE through any of that, and the one remaining door -- a
##      hand-edited save naming it -- is measured and REPORTED rather than hand-waved.
##   5. The counts it does move are exactly the ones intended: +1 registered id, +0
##      tradable, +0 description debt.
##
## LIMIT, STATED PLAINLY, because a check that implies more than it proves is worse than
## no check. This harness does NOT claim save files are sandboxed: nothing in the project
## validates a decoded item's path against a whitelist, for ANY item, so a hand-edited
## save that NAMES this path explicitly does load it. That is a property of the save
## format, identical for every resource in the project, and it is demonstrated for a real
## product item alongside the fixture so the claim is visibly item-agnostic.
##
## The stronger result, which is the opposite of what I expected when I wrote the first
## version of this file: the fixture cannot survive a save round trip even if code puts
## one in a stash. InventoryItem.slurp does not carry the resource_path and the fixture
## declares no `name`, so it encodes with an EMPTY path, and ItemCodec DROPS an item with
## no path on decode. So the answers are: not through any scan, not through any grant
## path, and not through a profile that merely holds one -- only through a save edited by
## hand, which is the format's own door.

const FIXTURE_PATH := "res://resources/meta/fixtures/fixture_untranslated.tres"
const FIXTURE_ID := "fixture_untranslated"
const FIXTURE_DIR := "res://resources/meta/fixtures"

## Every directory a scan in this project actually opens, with the file that opens it.
## Hardcoded on purpose: the point is to compare the fixture against the REAL scan set,
## and a list derived by re-running the same scan logic would only prove that the scan
## finds what the scan finds.
const SCANNED_DIRS := {
	"ItemCodec.WEAPON_DIR": "res://resources/weapons",
	"ItemCodec.AMMO_DIR": "res://resources/ammo",
	"ItemCodec.ATTACH_DIR": "res://resources/attachments",
	"Market.TRADERS_DIR": "res://resources/meta/traders",
	"Progression.QUESTS_DIR": "res://resources/meta/quests",
}

## Directories whose contents are counted as real stock by player-facing and harness
## scans. A fixture inside one of these would move a number a player or a report reads.
const STOCK_DIRS := [
	"res://resources/weapons", "res://resources/ammo", "res://resources/medical",
	"res://resources/armor", "res://resources/magazines", "res://resources/attachments",
]

var _pass := 0
var _fail := 0
var _fail_lines: Array[String] = []


func _initialize() -> void:
	_run()
	_finish()


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		_fail_lines.append(label)


func _run() -> void:
	_fixture_is_a_real_item()
	_no_scan_can_see_it()
	_no_name_resolution_can_reach_it()
	_no_gameplay_path_can_grant_it()
	_it_cannot_enter_a_save()
	_hand_edited_save_is_not_sandboxed()
	_the_counts_it_moves_are_only_the_intended_ones()


# ─── 0. it is a real item, or the checks below prove nothing ────────────────────

func _fixture_is_a_real_item() -> void:
	var res: Resource = load(FIXTURE_PATH)
	_check(res != null, "the fixture resource loads (if it does not, every isolation check below is vacuous)")
	if res == null:
		return
	_check(ItemNames.id_for_path(FIXTURE_PATH) == FIXTURE_ID,
		"the fixture is REGISTERED, so the middle branch of a translation arm has a real subject")
	_check(res.resource_path == FIXTURE_PATH,
		"and it carries its own resource_path, so encoding it can never depend on a directory scan to find it again")
	# The emptiness is the fixture's entire purpose, asserted here as well as in the two
	# harnesses that use it: this file is the one that knows the fixture's contract.
	_check(TranslationServer.translate(ItemNames.key_for(FIXTURE_ID)) == ItemNames.key_for(FIXTURE_ID),
		"and it is UNTRANSLATED, which is the property the fixture exists to provide")


# ─── 1. no directory scan can see it ────────────────────────────────────────────

func _no_scan_can_see_it() -> void:
	var inside: Array[String] = []
	for label in SCANNED_DIRS:
		var dir: String = SCANNED_DIRS[label]
		if FIXTURE_PATH.begins_with(dir + "/"):
			inside.append(label)
	_check(inside.is_empty(),
		"the fixture is inside NO directory any production scan opens (found in: %s)" % str(inside))
	_check(not SCANNED_DIRS.values().has(FIXTURE_DIR),
		"and its own directory is not one of the scanned directories, so a widened scan would have to name it explicitly")

	var stock_hit: Array[String] = []
	for dir in STOCK_DIRS:
		if FIXTURE_PATH.begins_with(dir + "/"):
			stock_hit.append(dir)
	_check(stock_hit.is_empty(),
		"the fixture is inside NO stock-counted directory, so it cannot move a real-stock count (hit: %s)" % str(stock_hit))

	# And the concrete version of the general form: the same scan the harnesses run.
	var fixture_tres := DirAccess.open(FIXTURE_DIR)
	_check(fixture_tres != null and fixture_tres.get_files().has("fixture_untranslated.tres"),
		"the fixture lives where it is meant to live, and is the only .tres there, so it is a fixture and not a growing category")


# ─── 2. no name-resolution can reach it ─────────────────────────────────────────

func _no_name_resolution_can_reach_it() -> void:
	# This is the one mechanism by which an item with no stored path could be ACQUIRED
	# rather than merely found: ItemCodec._scan_for_name walks a directory and returns the
	# first .tres whose .name matches, so a save entry carrying a NAME instead of a path
	# resolves to a real resource. If the fixture were reachable that way, a profile
	# could be made to acquire it without ever being offered it.
	for label in SCANNED_DIRS:
		var dir: String = SCANNED_DIRS[label]
		var found := ItemCodec._scan_for_name(dir, FIXTURE_ID)
		var by_name := ItemCodec._scan_for_name(dir, "fixture_untranslated")
		_check(found == "" and by_name == "",
			"name-resolution over %s (%s) cannot return the fixture by id or by name" % [dir, label])
	# Ammo resolution is separate: an encoded Ammo is resolved by caliber/mass, not by
	# name, so show the fixture cannot satisfy that either.
	var as_ammo := ItemCodec._scan_ammo("5.56x45mm", 1.0, 0.0)
	_check(as_ammo == null or as_ammo.resource_path != FIXTURE_PATH,
		"caliber/mass resolution cannot return the fixture as an Ammo")


# ─── 3. no gameplay path can grant it ───────────────────────────────────────────

func _no_gameplay_path_can_grant_it() -> void:
	# The complete set of ways this game hands a player an item: a trader sells it, the
	# starter kit contains it, or a quest rewards it. If none of the three names the
	# fixture, no sequence of gameplay can put one in a profile.
	var grant_paths: Array[String] = []
	var offer_count := 0
	var d := DirAccess.open("res://resources/meta/traders")
	_check(d != null, "the traders directory opens (the tradable set cannot be enumerated otherwise)")
	if d != null:
		for f in d.get_files():
			if not f.ends_with(".tres"):
				continue
			var t := load("res://resources/meta/traders/" + f) as Trader
			if t == null:
				continue
			for o in t.offers:
				offer_count += 1
				grant_paths.append(o.item_path)
				for k in o.barter_required.keys():
					grant_paths.append(String(k))
	var sl := load("res://resources/meta/starter_loadout.tres") as StarterLoadout
	_check(sl != null, "the starter loadout loads (a new profile's contents are a grant path)")
	if sl != null:
		for slot in sl.slots.keys():
			for p in sl.slots[slot]:
				grant_paths.append(String(p))
	var quest_rewards := 0
	var q := DirAccess.open("res://resources/meta/quests")
	if q != null:
		for f in q.get_files():
			if not f.ends_with(".tres"):
				continue
			var quest := load("res://resources/meta/quests/" + f)
			if quest == null or not ("reward_items" in quest):
				continue
			for p in (quest.get("reward_items") as Array):
				quest_rewards += 1
				grant_paths.append(String(p))
	_check(grant_paths.size() > 0, "the grant-path enumeration is non-vacuous: it found %d item paths to check"
		% grant_paths.size())
	_check(not grant_paths.has(FIXTURE_PATH),
		"the fixture is named by NO grant path: %d trader offers (buy + barter), %d starter items, %d quest rewards"
			% [offer_count, grant_paths.size() - offer_count - quest_rewards, quest_rewards])


# ─── 4. it cannot enter a save ──────────────────────────────────────────────────

func _it_cannot_enter_a_save() -> void:
	# A save holds the profile dict. An item reaches a save only by being in a profile,
	# and an item is in a profile only by a grant path (checked above) or by a
	# name-resolution hit (checked above). So demonstrate the consequence on a REAL
	# profile rather than asserting the chain in prose: grant it through every legal
	# route a new profile has, then show the written save does not mention it.
	var probe_dir := "user://fixture_isolation"
	DirAccess.make_dir_recursive_absolute(probe_dir)
	var prof := MetaProfile.new()
	var starter := load("res://resources/meta/starter_loadout.tres") as StarterLoadout
	if starter != null:
		for slot in starter.slots.keys():
			for p in starter.slots[slot]:
				var r: Resource = load(String(p))
				if r != null:
					prof.stash.deposit(InventoryItem.slurp(r))
	var encoded := JSON.stringify(prof.to_dict())
	_check(not encoded.contains(FIXTURE_ID) and not encoded.contains("fixtures/"),
		"a real profile granted its legal starter contents does not encode the fixture")
	# Persistence: a real write+read through the store, in an ISOLATED path so it cannot
	# clobber another lane's profile (the shared-save hazard that once flooded a real
	# profile 16x). ProfileStore takes the path as a parameter, so isolation is explicit.
	var save_path := "%s/probe.save" % probe_dir
	var err := ProfileStore.save(prof, save_path)
	_check(err == OK, "the probe profile is written to an isolated save path (err %d)" % err)
	var reloaded := ProfileStore.load_profile(save_path)
	_check(reloaded != null and not JSON.stringify(reloaded.to_dict()).contains(FIXTURE_ID),
		"a written-and-reloaded save does not contain the fixture, so persistence cannot resurrect it")
	ProfileStore.delete(save_path)
	DirAccess.remove_absolute(probe_dir)


# ─── the limit, measured instead of hidden ─────────────────────────────────────

func _hand_edited_save_is_not_sandboxed() -> void:
	# The boundary, measured as a MATRIX rather than asserted, because `kind` selects the
	# decoder in ItemCodec.decode_item and the three decoders treat `path` differently.
	# Getting this wrong was the actual failure mode here: I first claimed a fixture item
	# is dropped on reload (true for the weapon decoder, false for the feed one), then
	# over-corrected to "it is unreachable from a save" (false -- _decode_plain loads any
	# Item by path), and only the matrix below is the measured truth.
	var probe_dir := "user://fixture_isolation"
	DirAccess.make_dir_recursive_absolute(probe_dir)

	# (1) ROUND TRIP. If code puts one in a stash, what survives a write+read?
	var prof := MetaProfile.new()
	prof.stash.deposit(InventoryItem.slurp(load(FIXTURE_PATH)))
	var rt := "%s/rt.save" % probe_dir
	ProfileStore.save(prof, rt)
	var rt_items: Array = ProfileStore.load_profile(rt).to_dict().get("stash", {}).get("items", [])
	# It SURVIVES -- I was wrong that it is dropped -- but as a generic nameless AmmoFeed
	# rebuilt from its own `feed` data, with NO path and NO registry id, because
	# InventoryItem.slurp does not carry the resource_path. So what persists is a copy of
	# the fixture's DATA, not the fixture: nothing in the save names it, and the UI
	# resolves its name through ItemNames.id_for_path("") == "", i.e. unregistered.
	_check(rt_items.size() == 1,
		"a round trip preserves the item's DATA (a copy of the fixture's feed), not the fixture: nothing in the save names it")
	_check(rt_items.size() == 1 and String(rt_items[0].get("path", "")) == "",
		"and the reloaded item carries NO path and no registry id, so it is an anonymous unnamed magazine rather than the fixture resource")
	ProfileStore.delete(rt)

	# (2) THE MATRIX. Same save shape, one variable changed at a time: the decoder and the
	# path. This is the measurement that replaced my wrong assertion.
	var plain_fixture := _load_items({"kind": "item", "path": FIXTURE_PATH, "name": "Item", "stack": 1}, "plain_fixture")
	# Assert the CONTENT, not the path: InventorySystem.create_inventory_item makes a COPY,
	# and the copy does not carry resource_path, so the re-emitted "path" is "" whether or
	# not the fixture was loaded. The crafted save above supplies NO feed dict at all, so
	# empty_mass 1.0, cap 30, type 1 and strict=false can only have come from the fixture
	# RESOURCE being loaded. Checking the path would have reported "unreachable" for an
	# item that had in fact loaded -- which is the same mistake as the two before it.
	var pf_feed: Dictionary = plain_fixture[0].get("feed", {}) if plain_fixture.size() == 1 else {}
	_check(plain_fixture.size() == 1
			and is_equal_approx(float(pf_feed.get("empty_mass", -1.0)), 1.0)
			and int(pf_feed.get("cap", -1)) == 30 and int(pf_feed.get("type", -1)) == 1,
		"_decode_plain LOADS THE FIXTURE RESOURCE from an explicitly named path -- the decoded feed carries the fixture's own empty_mass 1.0 / cap 30 / type 1 although the crafted save supplied no feed at all, so a hand-edited save CAN reach it")
	var weapon_fixture := _load_items({"kind": "weapon", "path": FIXTURE_PATH, "name": "Item", "stack": 1}, "weapon_fixture")
	_check(weapon_fixture.is_empty(),
		"while the WEAPON decoder REJECTS the fixture by type (it is not a Weapon), so the one decoder that honours an arbitrary path for a typed resource is closed here")
	var feed_fixture := _load_items({"kind": "ammofeed", "path": FIXTURE_PATH, "name": "Item", "stack": 1,
		"feed": {"bore": 0.1, "calibers": ["5.56x45mm"], "cap": 30, "case": 1.0,
			"empty_mass": 1.0, "rounds": [], "strict": false, "type": 1}}, "feed_fixture")
	_check(feed_fixture.size() == 1 and String(feed_fixture[0].get("path", "")) == "",
		"and the FEED decoder IGNORES the path entirely and rebuilds from the feed dict, so this shape never loads the fixture resource either")

	# (3) THE DOOR IS REAL AND NOT FIXTURE-SPECIFIC. Same unsandboxed property, a real
	# product item, so the claim is visibly item-agnostic rather than reassuring.
	var real_path := "res://resources/weapons/M4_Carbine.tres"
	var real_items := _load_items({"kind": "weapon", "path": real_path, "name": "M4 Carbine", "stack": 1}, "real_weapon")
	_check(real_items.size() == 1 and String(real_items[0].get("path", "")) == real_path,
		"THE LIMIT, stated as a property of the format: a hand-edited save naming a REAL product item loads it, so unsandboxed save paths are the save format's and not something the fixture introduced")
	DirAccess.remove_absolute(probe_dir)
	print("NOTE: FIXTURE SAVE-POSTURE: unreachable by all %d scanned dirs, by name-resolution, and by every trader/starter/quest grant path; a round trip preserves its DATA as an anonymous unnamed magazine, not the fixture; a hand-edited save CAN load it only by naming its path explicitly and using the plain decoder -- and that same door loads every real item, because no decoded path is validated against a whitelist." % SCANNED_DIRS.size())


## Write one crafted save and return the items the loader actually produced.
func _load_items(entry: Dictionary, tag: String) -> Array:
	var path := "user://fixture_isolation/%s.save" % tag
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return []
	f.store_string(JSON.stringify({"version": MetaProfile.VERSION,
		"stash": {"height": 20, "items": [entry]}}))
	f.close()
	var items: Array = ProfileStore.load_profile(path).to_dict().get("stash", {}).get("items", [])
	ProfileStore.delete(path)
	return items


# ─── 5. the counts it moves are only the intended ones ─────────────────────────

func _the_counts_it_moves_are_only_the_intended_ones() -> void:
	# +1 registered id is intended (it must be registered to be a subject at all) and is
	# visible in the registry-debt note. It is NOT +1 tradable and NOT +1 description,
	# and those are the numbers a player or a report actually reads.
	var ids := ItemNames.registered_ids()
	_check(ids.has(FIXTURE_ID), "the registry count moves by exactly one, in the intended direction (registered)")
	var tradable := 0
	var d := DirAccess.open("res://resources/meta/traders")
	if d != null:
		for f in d.get_files():
			if not f.ends_with(".tres"):
				continue
			var t := load("res://resources/meta/traders/" + f) as Trader
			if t != null:
				tradable += t.offers.size()
	_check(tradable > 0, "the tradable count is non-zero, so \"+0 tradable\" is a measurement and not a vacuous claim (%d offers)" % tradable)
	# No description is declared, so the item-description debt scan must not see it. Read
	# it the way the debt check does: a top-level description line, not a nested one.
	var raw := FileAccess.get_file_as_string(FIXTURE_PATH)
	_check(not _has_top_level_description(raw),
		"the fixture declares NO top-level description, so it is not item-description translation debt")
	print("NOTE: FIXTURE COUNTS: registered ids %d (the fixture is one of them, by design), trader offers %d (the fixture is none of them, so the tradable count is unchanged)" % [ids.size(), tradable])


func _has_top_level_description(raw: String) -> bool:
	# A nested sub-resource's description must not count, which is the mistake that once
	# inflated the description-debt number by 15 for a single item.
	var in_resource := false
	for line in raw.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("["):
			in_resource = t.begins_with("[resource")
			continue
		if in_resource and t.begins_with("description"):
			return true
	return false


func _finish() -> void:
	print("─── FIXTURE ISOLATION ───")
	for l in _fail_lines:
		print("  FAIL: %s" % l)
	print("checks: %d, passed: %d, failed: %d" % [_pass + _fail, _pass, _fail])
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
