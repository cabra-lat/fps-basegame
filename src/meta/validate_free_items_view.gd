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
	# THREE rows in one claim list, one per branch of _is_translated(), so the
	# marking is shown to DISCRIMINATE and not merely to exist. A fixture with one
	# item passes whether the flag is computed or hardcoded.
	#
	# THE THIRD ROW EXISTS BECAUSE A RED ARM PROVED THE FIRST TWO INSUFFICIENT.
	# Arming the translate comparison to `return true` left the harness 25/25, and
	# the reason is that an UNREGISTERED item returns early at the `id == ""` guard
	# and never reaches that line at all. The fixture therefore exercised only the
	# unregistered branch, and the registered-but-untranslated branch -- 42 of the
	# 50 registered ids, and the one that matters at scale -- was never tested.
	# Brazil_556 is registered, has a real .tres, and has no msgid.
	var registered_untranslated := preload("res://resources/weapons/Brazil_556.tres")
	_check(ItemNames.id_for_path(registered_untranslated.resource_path) == "Brazil_556",
		"Brazil_556 is confirmed REGISTERED, so it reaches the translate comparison the previous fixture skipped")
	_check(TranslationServer.translate(ItemNames.key_for("Brazil_556")) == ItemNames.key_for("Brazil_556"),
		"and confirmed UNTRANSLATED, so the mark below is a real branch rather than a coincidence")
	ins.register_loss([ItemCodec.encode_item(_item(registered_untranslated))], profile)
	# And one that is not registered at all: 12_70_8.5mm_Magnum_buckshot is one of
	# the 69 items deliberately left out (its id is truncated).
	var unregistered := preload("res://resources/ammo/12_70_8.5mm_Magnum_buckshot.tres")
	_check(ItemNames.id_for_path(unregistered.resource_path) == "",
		"the buckshot is confirmed UNREGISTERED, so its mark comes from the id=='' branch")
	ins.register_loss([ItemCodec.encode_item(_item(unregistered))], profile)
	rows = view.rows()
	_check(rows.size() == view.pending_item_count(), "every claim is listed (%d rows, %d pending)" % [rows.size(), view.pending_item_count()])

	var untranslated := 0
	var translated := 0
	for row in rows:
		if bool(row.get("translated", false)):
			translated += 1
		else:
			untranslated += 1
	print("NOTE: FREE-ITEMS TRANSLATION DEBT: %d of %d pending rows are untranslated and will be MARKED rather than rendered as English"
		% [untranslated, rows.size()])
	_check(untranslated == 2 and translated == 1,
		"the mark DISCRIMINATES across all three branches: %d unmarked (registered+translated), %d marked (one registered-untranslated, one unregistered)"
			% [translated, untranslated])

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
