# res://src/meta/validate_free_items_view.gd
extends SceneTree
## Free-items view: the reachable zero-items state, marked honestly.
##
## The card's acceptance is that a player who owns nothing can SEE what is free and
## why it is not in hand yet. So the assertions are about the two halves of that:
## the rows appear, and the reason is attached to the row rather than to a greyed
## button somewhere else. Each capability is armed in the other direction too,
## because a view that always returns an empty list passes every "is it empty"
## check forever.

const RIFLE := preload("res://resources/weapons/M4_Carbine.tres")
const AMMO := preload("res://resources/ammo/5_56_45mm_M855_MIL_SAPI.tres")

var checks := 0
var failures := 0


func _initialize() -> void:
	# ── the zero-items state is REACHABLE, and reached the real way ────────────
	# Through insurance, not through the starter grant: the coordinator held the
	# starter call site (first deploy) and said not to add it, so a fixture that
	# invents a kit-free profile by hand would be testing a state no player is in.
	# A KIA forfeits the deployed kit and schedules the un-looted insured items,
	# which is the window this card is about.
	var profile := MetaProfile.new()
	var service := MetaService.new()
	service.use_profile(profile, "")
	# The insurance instance is the PROFILE's, created in MetaProfile._init() and
	# reached the same way resolve_raid reaches it. There is no bind_insurance, and
	# inventing one here would have been a second way to own the same object.
	var ins: Insurance = profile.insurance

	var rifle := _item(RIFLE)
	var ammo := _item(AMMO)
	_check(rifle != null and ammo != null, "the fixture items load as real resources")

	# The rifle must be OWNED before it can be deployed, and this is the API being
	# correct rather than the fixture being awkward: a brand-new profile owns
	# nothing, so deploying a rifle out of nowhere is refused. The stash is where
	# owned-but-unequipped kit lives, so the kit starts there.
	_check(profile.stash.deposit(rifle), "the rifle is deposited in the stash, so the player owns it")
	var deployed := service.deploy_loadout({"primary": [ItemCodec.encode_item(rifle)]})
	_check(deployed.get("ok", false), "a rifle deploys from the stash (reason: %s)" % str(deployed.get("reason", "")))
	# prepare_raid equips into a CARRIER, so one must be bound; without it the
	# transaction fails closed and equips nothing, which is correct behaviour and
	# not something to work around in a fixture.
	var eq := Equipment.new()
	var bag := Backpack.new()
	service.bind_carrier(eq, bag)
	var prepared := service.prepare_raid()
	_check(prepared > 0, "prepare equips the deployed kit (%d)" % prepared)
	_check(not profile.loadout.is_empty(), "the player holds the kit before dying")

	# Lose it. This is the zero-items state, produced by the real failure path.
	var lost := service.resolve_raid(Raid.Outcome.KIA, 0)
	_check(lost != null, "the raid resolves as a loss")
	_check(profile.loadout.is_empty() and profile.stash_item_count() == 0,
		"CONSTRUCTED BREAK: after a KIA the player owns NOTHING, so this is a reachable zero-items state and not a fixture")

	# ── what the view says about it ──────────────────────────────────────────
	var view := FreeItemsView.new(profile, ins)
	_check(view.owns_nothing(), "the view agrees the player owns nothing")
	_check(view.pending_item_count() > 0,
		"the insured rifle is PENDING, not gone (pending=%d)" % view.pending_item_count())
	_check(view.has_free_items(), "there are free items to show")

	var rows := view.rows()
	_check(rows.size() == view.pending_item_count(),
		"every pending item has exactly one row (%d rows, %d pending)" % [rows.size(), view.pending_item_count()])

	# ── the reason is ON THE ROW, and it is a KEY ─────────────────────────────
	var r0: Dictionary = rows[0]
	_check(String(r0.get("key", "")) == "FREE_ITEMS_REASON_PENDING_RETURN",
		"a row carries its reason as a catalogue key, not a composed sentence (key=%s)" % str(r0.get("key", "")))
	_check(int(r0.get("reason", -1)) == int(FreeItemsView.Reason.PENDING_RETURN),
		"and as a machine reason as well, so code can branch on it")
	_check(String(r0.get("id", "")) != "", "the row's identity comes from the registry id, resolved from the resource path (id=%s)" % str(r0.get("id", "")))
	_check(String(r0.get("id", "")) != String(r0.get("path", "")),
		"and the id is NOT the path, which is the raw-identity leak this bar exists to catch")

	# ── the delay is stated, because silence here reads as a broken system ───
	_check(int(r0.get("raids_until", -1)) >= 0,
		"a pending row says how many raids until it returns, so the wait is legible (%d)" % int(r0.get("raids_until", -1)))
	_check(view.raids_until_next_return() == int(r0.get("raids_until", -2)),
		"and the per-row figure agrees with the delegated raids_until_next() (%d vs %d)"
			% [int(r0.get("raids_until", -2)), view.raids_until_next_return()])

	# ── the untranslated mark, WHICH IS THE REASON THE REGISTRY MATTERS ──────
	# TWO rows whose state is DURABLE, so completing the catalogue cannot break this:
	# M4_Carbine is registered and translated, buckshot is deliberately UNREGISTERED.
	# The third branch (registered, no msgid) is tested at the PREDICATE level below
	# with a key nobody will ever add a msgid for.
	#
	# WHY NO REAL UNTRANSLATED ITEM ANYMORE: this block used to register Brazil_556
	# and require it to stay untranslated. When meta's pt-BR sweep translated it to
	# "Brasil 556", the fixture lost its subject and this harness went red -- on GOOD
	# work, from another lane. A negative case whose subject is TRANSLATION DEBT is a
	# case that is emptied by finishing the job. Both available responses were wrong:
	# hold Brazil_556 hostage forever, or pick another of the 19 still-untranslated
	# ids and move the hostage one item along. (Choosing a 20th is not a fix; it just
	# buys another sweep.)
	var registered_translated := preload("res://resources/weapons/M4_Carbine.tres")
	_check(ItemNames.id_for_path(registered_translated.resource_path) == "M4_Carbine",
		"M4_Carbine is confirmed REGISTERED, and it is translated, so its row must NOT be marked")
	ins.register_loss([ItemCodec.encode_item(_item(registered_translated))], profile)
	var subject_path := _untranslated_subject()
	_check(subject_path != "",
		"a REGISTERED-but-UNTRANSLATED item exists to serve as the third-branch subject (found=%s). IF THIS FAILS THE CATALOGUE IS COMPLETE: redesign this check deliberately. Do NOT soften it and do NOT un-translate a real item to make it pass." % subject_path)
	if subject_path != "":
		ins.register_loss([ItemCodec.encode_item(_item(load(subject_path)))], profile)
	# 12_70_8.5mm_Magnum_buckshot is one of the 69 items deliberately left out (its
	# id is truncated). "Deliberately unregistered" is a property of the REGISTRY, not
	# of the catalogue, so this subject is permanent -- which is exactly why the
	# registered-but-untranslated case had to be moved off a catalogue item and onto
	# the predicate, where a synthetic key can be.
	var unregistered := preload("res://resources/ammo/12_70_8.5mm_Magnum_buckshot.tres")
	_check(ItemNames.id_for_path(unregistered.resource_path) == "",
		"the buckshot is confirmed UNREGISTERED, so its mark comes from the id=='' branch")
	ins.register_loss([ItemCodec.encode_item(_item(unregistered))], profile)
	rows = view.rows()
	_check(rows.size() == view.pending_item_count(), "every claim is listed (%d rows, %d pending)" % [rows.size(), view.pending_item_count()])

	var m4_translated := false
	var buck_translated := false
	var subject_translated := true
	for row in rows:
		var rid := String(row.get("id", ""))
		if rid == "M4_Carbine":
			m4_translated = bool(row.get("translated", false))
		elif rid == ItemNames.id_for_path(subject_path):
			subject_translated = bool(row.get("translated", false))
		elif rid == "":
			buck_translated = bool(row.get("translated", false))
	print("NOTE: FREE-ITEMS TRANSLATION DEBT: %d of %d pending rows are untranslated and will be MARKED rather than rendered as English"
		% [_count_untranslated(rows), rows.size()])
	_check(m4_translated == true,
		"a registered+translated row is NOT marked, so the mark is computed rather than always-on")
	_check(subject_translated == false,
		"a REGISTERED-but-UNTRANSLATED row IS marked -- this is the branch the early `id == \"\"` guard skips, and the one that matters at scale")
	_check(buck_translated == false,
		"an unregistered row is UNTRANSLATED and therefore marked, so the same flag discriminates across fixtures in one list")
	# The third branch, on a REAL registered subject. A hardcoded `return true` is
	# caught here, which is what the earlier red arm was protecting: the unregistered
	# row returns early at the id == "" guard, so on its own it cannot tell a
	# correct comparison from a hardcoded true.
	_check(ItemNames.is_key_translated("M4_Carbine") == true,
		"a REGISTERED+TRANSLATED key is reported translated")
	_check(subject_path != "" and ItemNames.is_key_translated(ItemNames.id_for_path(subject_path)) == false,
		"a REGISTERED key with no msgid is reported untranslated, on a subject discovered at runtime")
	_check(ItemNames.is_key_translated("no_such_id_at_all") == false,
		"an id absent from the registry is also untranslated -- and that is a DIFFERENT branch, which is why it cannot stand in for the one above")
	_check(ItemNames.is_translated_path(unregistered.resource_path) == false,
		"and an unregistered PATH resolves untranslated through the path-level helper")
	_check(ItemNames.is_translated_path(registered_translated.resource_path) == true,
		"while a registered, translated PATH resolves translated -- so the path helper is not simply always-false")

	# ── a player who still has gear is NOT in the zero state ─────────────────
	var rich := MetaProfile.new()
	rich.loadout["primary"] = [ItemCodec.encode_item(rifle)]
	var rich_view := FreeItemsView.new(rich, ins)
	_check(not rich_view.owns_nothing(),
		"CONSTRUCTED BREAK: a player holding a kit is not in the zero-items state, so the screen cannot claim 'you own nothing' over a full inventory")
	_check(rich_view.rows().size() == view.rows().size(),
		"pending free items are still listed for a player who has gear: the list is about what is CLAIMABLE, not about being empty")

	# ── the empty case must be honestly empty, not fake-populated ────────────
	var clean := MetaProfile.new()
	var empty_ins := Insurance.new()
	var clean_view := FreeItemsView.new(clean, empty_ins)
	_check(clean_view.rows().is_empty() and not clean_view.has_free_items(),
		"with no pending claim the view shows nothing at all, rather than a plausible-looking placeholder row")
	_check(clean_view.pending_item_count() == 0,
		"and the delegated count agrees it is zero")

	print("free items view: checks=%d passed=%d" % [checks, checks - failures])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


## InventoryItem.slurp() is the real factory (ItemCodec.item_from_path takes a PATH,
## and RIFLE/AMMO are preloaded Resources here).
func _item(res: Resource, stack: int = 1) -> InventoryItem:
	var it := InventoryItem.slurp(res)
	it.max_stack = maxi(it.max_stack, stack)
	it.stack_count = stack
	if res != null and "grid_size" in res:
		it.dimensions = res.get("grid_size")
	return it


func _check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("  PASS  %s" % message)
	else:
		failures += 1
		print("ERROR: FAIL: %s" % message)
func _count_untranslated(rows: Array) -> int:
	var n := 0
	for row in rows:
		if not bool(row.get("translated", false)):
			n += 1
	return n


## A real .tres that is REGISTERED but has no msgstr -- the only kind of subject
## that reaches the translate comparison, because "registered" is the property
## under test and a synthetic key cannot be registered (KEYS is a read-only const;
## verified: assigning to it is a parse error, "Cannot assign a new value to a
## constant").
##
## Discovered AT RUNTIME rather than hardcoded, for the reason recorded at the
## call site: a hardcoded subject is a hostage held against the catalogue, and the
## only two responses to that hostage are un-translating a real item forever or
## softening the check. Finding it dynamically means good work elsewhere cannot
## empty this check out from under us.
func _untranslated_subject() -> String:
	for f in _tres_under("res://resources"):
		var id := f.get_file().get_basename()
		if id != "" and ItemNames.KEYS.has(id) and not ItemNames.is_key_translated(id):
			return f
	return ""


func _tres_under(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir():
			if not name.begins_with("."):
				out.append_array(_tres_under(dir_path.path_join(name)))
		elif name.ends_with(".tres"):
			out.append(dir_path.path_join(name))
		name = d.get_next()
	d.list_dir_end()
	return out
