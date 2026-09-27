# res://src/meta/validate_starter_loadout.gd
extends SceneTree
## 87ab63, fourth of five: "if you dont have any you mark free items and press play".
##
## THE CARD'S OWN ACCEPTANCE, followed exactly: "a save with zero items produces a
## playable loadout whose ids all resolve, asserted against the item registry
## rather than against a screenshot, and the refill cannot become a faucet."
##
## THAT LAST CLAUSE IS THE ONE THAT MATTERS, and it is the reason this is an
## assertion rather than a screen. A free-items marker looks identical whether the
## refill is a legitimate consequence of having lost everything or an infinite
## faucet that mints a rifle per visit. Only the second is a defect and only the
## second is invisible from the UI, so the property is pinned against the grant
## itself: gear is stamped no_transfer at grant time, a second grant adds nothing,
## and a loadout that still has a weapon is never topped up.
##
## ASSERTED AGAINST THE REGISTRY, not a screenshot and not a path. A starter entry
## whose path no longer resolves to a registered id would render as a ghost row the
## player can see and nothing else would notice, so every granted id is round-
## tripped through ItemNames the way the UI resolves it.
##
## THE STARTER SET IS DATA. starter_loadout.tres is read as a resource and its
## paths are resolved through the same ItemCodec path as everything else. There is
## deliberately no literal weapon name in this file, because a hardcoded fallback
## is how the hub got a hardcoded Portuguese catalogue in the first place.

const STARTER := preload("res://resources/meta/starter_loadout.tres")

var checks := 0
var failures := 0


func _check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("  PASS  %s" % message)
	else:
		failures += 1
		print("  FAIL  %s" % message)


func _initialize() -> void:
	# ── the data, resolved rather than assumed ──────────────────────────────
	_check(STARTER is StarterLoadout, "the starter set is a StarterLoadout RESOURCE, not a branch in code")
	_check(not (STARTER.slots as Dictionary).is_empty(),
		"and it declares slots (%d)" % (STARTER.slots as Dictionary).size())
	for slot in (STARTER.slots as Dictionary):
		for path in (STARTER.slots as Dictionary)[slot]:
			var item: Item = ItemCodec.item_from_path(String(path))
			var id: String = ItemNames.id_for_path(String(path))
			_check(item != null, "starter slot '%s' path %s resolves to a real item" % [slot, path.get_file()])
			_check(id != "", "  and to a REGISTRY id, not a bare path (renaming it cannot leave a ghost)")

	# ── the described behaviour: nothing owned -> playable ──────────────────
	var profile := MetaProfile.new()
	_check(profile.stash_item_count() == 0 and profile.loadout.is_empty(),
		"a fresh profile owns nothing in either the loadout or the stash")
	var service := MetaService.new()
	service.profile = profile
	var added: int = service.grant_starter_loadout(STARTER)
	_check(added > 0, "the starter grant filled the empty profile (%d item(s))" % added)
	_check(not profile.loadout.is_empty(), "and the loadout is now playable, not empty")

	# Every granted id must resolve -- this is the acceptance clause.
	#
	# Read from the ENCODED dictionary rather than from a decoded InventoryItem:
	# decode_item returns an Object, and `no_transfer` is carried as a field of the
	# encoded form (item_codec.gd:34 writes it, :169 reads it back onto the item).
	# Asking an InventoryItem for a dict key is a type error, so this reads what is
	# actually persisted -- which is also the thing that has to survive a save.
	var unresolved := 0
	var total := 0
	for slot in profile.loadout:
		for encoded in profile.loadout[slot]:
			total += 1
			if not (encoded is Dictionary):
				unresolved += 1
				continue
			var d: Dictionary = encoded
			if ItemNames.id_for_path(String(d.get("path", ""))) == "":
				unresolved += 1
	_check(total > 0 and unresolved == 0,
		"every granted item resolves through the item registry (%d checked, %d unresolved)"
			% [total, unresolved])

	# ── THE FAUCET CLAUSE, in three parts ───────────────────────────────────
	var marked := 0
	for slot in profile.loadout:
		for encoded in profile.loadout[slot]:
			if (encoded is Dictionary) and bool((encoded as Dictionary).get("no_transfer", false)):
				marked += 1
	_check(marked == total and total > 0,
		"every starter item is stamped no_transfer, so it cannot be laundered into the bank (%d/%d)"
			% [marked, total])

	var again: int = service.grant_starter_loadout(STARTER)
	_check(again == 0, "a SECOND grant adds nothing, so the refill is not a faucet (added=%d)" % again)

	# The check above is satisfied by the SLOT guard, not by the once-per-faction
	# flag -- and I only know that because a red arm which deleted the flag guard
	# (`if bool(starter_granted)`) still passed 14/14. A guard tested through a
	# stronger guard beside it is not tested at all.
	#
	# So the flag is isolated: EMPTY the loadout, which is exactly the state the
	# card describes ("you have nothing"), and leave starter_granted set. The slot
	# guard now has nothing to protect, so the ONLY thing that can refuse is the
	# flag. If the once-per-faction gate is removed, this is the check that fails.
	var emptied := MetaProfile.new()
	var service3 := MetaService.new()
	service3.profile = emptied
	service3.grant_starter_loadout(STARTER)
	emptied.loadout.clear()
	_check(emptied.loadout.is_empty(), "and the profile now genuinely owns nothing, the state the card describes")
	var refilled: int = service3.grant_starter_loadout(STARTER)
	_check(refilled == 0 and emptied.loadout.is_empty(),
		"an EMPTY loadout is still not refilled when the faction has already granted a starter "
		+ "(added=%d) -- the once-per-faction flag, isolated from the slot guard" % refilled)

	# The clause "requires having lost EVERY weapon": a loadout that still holds a
	# weapon must not be topped up, which is the faucet wearing a plausible costume.
	var partial := MetaProfile.new()
	var service2 := MetaService.new()
	service2.profile = partial
	var full := service2.grant_starter_loadout(STARTER)
	var first_slot: String = (partial.loadout.keys() as Array)[0] as String
	var kept: Array = (partial.loadout[first_slot] as Array).duplicate(true)
	partial.role_state()["starter_granted"] = false   # pretend it was lost in a raid
	var topped: int = service2.grant_starter_loadout(STARTER)
	_check(topped == 0 and (partial.loadout[first_slot] as Array) == kept,
		"even with the grant flag reset, a loadout that still holds a weapon is NOT topped up "
		+ "(added=%d, %d item(s) still in '%s' untouched)" % [topped, kept.size(), first_slot])
	_check(full > 0, "and the first grant on an empty profile did work, so the guard is not just refusing everything")

	print("starter loadout: checks=%d passed=%d" % [checks, checks - failures])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
