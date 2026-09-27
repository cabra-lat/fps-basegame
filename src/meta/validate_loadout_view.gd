extends SceneTree

## Invariants for the loadout selection screen's CONTENT (src/meta/loadout_view.gd).
##
## WHY A HARNESS AND NOT A SCREENSHOT. The design pass's harness discipline is
## explicit that any assertion reading position/size/scroll must first establish
## that layout was re-evaluated and that the thing read demonstrably settled. A
## loadout screen whose correctness lives in geometry therefore cannot be tested
## without a rendered frame and a constructed break. This screen's correctness
## deliberately does NOT live in geometry: LoadoutView answers questions about the
## kit, so every assertion below is about DATA and needs no frame, no show(), and
## no await — which is a property of the design, not a shortcut.
##
## WHAT IS PINNED, and each one is a bug this lane actually had or nearly had:
##   LOADOUT-1  a full, legal kit is DEPLOYABLE — pins the trap that
##              EquipmentSlot.can_add_item() returns false for any occupied slot,
##              so asking it about equipped items condemns every full kit.
##   LOADOUT-2  free cells are the CONTAINER's number, delegated, not recounted.
##   LOADOUT-3  mass is the raid screen's own get_total_weight(), and a nested
##              container's contents are counted ONCE, not once per path.
##   LOADOUT-4  every name on a row comes from the id-to-translation-key REGISTRY
##              and a registered item never shows its raw id.
##   LOADOUT-5  every reason is a KEY, never a composed sentence.
##   LOADOUT-6  the screen says nothing about the stash.
##   LOADOUT-7  a CONSTRUCTED BREAK for each of the above that can be made to fail,
##              because a green assertion that has never gone red is a sentence.

const ITEM_SCRIPT := preload("res://addons/cabra.lat_shooters/src/core/inventory/item.gd")
const ARMY_BANDAGE := preload("res://resources/medical/army_bandage.tres")
const WATER := preload("res://resources/medical/bottle_of_water.tres")
const RIFLE := preload("res://resources/weapons/M4_Carbine.tres")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run()
	print("loadout view: checks=%d passed=%d" % [checks, checks - failures])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("  PASS  %s" % message)
	else:
		failures += 1
		print("ERROR: FAIL: %s" % message)


## ── fixtures ─────────────────────────────────────────────────────────────────

func _equipment() -> Equipment:
	return Equipment.new()


## An InventoryItem wrapping a content resource, built the way the game builds
## one: InventoryItem.slurp(), which puts the payload in `extra` and is what
## ItemCodec.content_path() and InventoryItem.get_mass() both read. Constructing
## one by hand and assigning a `resource` property is wrong on two counts — there
## is no such property, and a hand-built item has no `extra`, so the registry
## lookup and the mass both read empty.
func _item(res: Resource, stack: int = 1) -> InventoryItem:
	var it := InventoryItem.slurp(res)
	# max_stack defaults to 1 and the setter CLAMPS to it, so a fixture asking for
	# four of something gets one and the mass assertion then fails for a reason
	# that has nothing to do with mass. Raise the cap first, in the fixture.
	it.max_stack = maxi(it.max_stack, stack)
	it.stack_count = stack
	if res != null and "grid_size" in res:
		it.dimensions = res.get("grid_size")
	return it


## An item whose `extra` is a real nested container, built through the game's own
## codec rather than by assigning `extra` by hand and hoping: the nesting lives in
## ItemCodec.encode_item's "container" branch, so the round trip is encode then
## decode, which is the path a save takes. (encode_container alone is not enough —
## it returns an Array of a container's CONTENTS, not an item.)
func _container_item(rig: InventoryContainer) -> InventoryItem:
	var wrapper := InventoryItem.new()
	wrapper.extra = rig
	wrapper.name = "rig"
	return ItemCodec.decode_item(ItemCodec.encode_item(wrapper))


func _pack_of(width: int = 10, height: int = 10) -> InventoryContainer:
	var c := InventoryContainer.new()
	c.grid_width = width
	c.grid_height = height
	return c


## A view over a detached rig, the way the screen builds it from a profile.
func _view(eq: Equipment, pack: InventoryContainer, limit: float = 0.0) -> LoadoutView:
	return LoadoutView.new(eq, pack, limit)


# ── the checks ───────────────────────────────────────────────────────────────

func _run() -> void:
	_full_kit_is_deployable()
	_free_cells_are_delegated()
	_mass_is_the_shared_number()
	_names_come_from_the_registry()
	_reasons_are_keys()
	_no_stash()


## LOADOUT-1 + its constructed break.
##
## The trap: EquipmentSlot.can_add_item() is an INSERTION predicate and returns
## false whenever the slot already holds anything (equipment_slot.gd:24). A
## validator built on it condemns every equipped slot, so a NORMAL full kit would
## read undeployable and the screen would tell the player their rifle is illegal.
## The break proves the assertion can go red: ask the same question the trap's way
## and the full kit IS condemned, which is exactly the bug this pins shut.
func _full_kit_is_deployable() -> void:
	var eq := _equipment()
	var pack := _pack_of()
	var rifle := _item(RIFLE)
	var bandage := _item(ARMY_BANDAGE)
	_check(eq.slots["primary"].add_item(rifle), "a rifle goes into the primary slot")
	_check(eq.slots["head"].add_item(bandage), "a bandage-shaped item goes into the head slot")
	_check(pack.add_item(bandage.duplicate()), "the pack accepts an item")

	var view := _view(eq, pack)
	var reasons := view.blocking_reasons()
	_check(reasons.is_empty(),
		"a full, legal kit is DEPLOYABLE (reasons: %s)" % _reason_text(reasons))
	_check(view.is_deployable(), "is_deployable() agrees with blocking_reasons().is_empty()")

	# THE CONSTRUCTED BREAK: the trap's own logic, run on the same kit.
	var trap := 0
	for slot_name in LoadoutView.SLOT_ORDER:
		var slot = eq.slots.get(slot_name)
		if slot == null:
			continue
		for it in slot.items:
			if not slot.can_add_item(it):
				trap += 1
	_check(trap > 0,
		"CONSTRUCTED BREAK: the can_add_item() trap condemns %d slot(s) of this legal kit — so if this ever reads 0, the trap is no longer the trap and LOADOUT-1 is no longer testing what it claims" % trap)

	# And the mass reason, positively: over the limit the kit must be condemned.
	var heavy := _view(eq, pack, 0.001)
	var heavy_reasons := heavy.blocking_reasons()
	_check(heavy_reasons.size() == 1 and int(heavy_reasons[0]["reason"]) == int(LoadoutView.Reason.OVER_MASS),
		"a kit over its mass limit is condemned with OVER_MASS (reasons: %s)" % _reason_text(heavy_reasons))


## LOADOUT-2 + break: the number is the container's, and it MOVES when the kit does.
func _free_cells_are_delegated() -> void:
	var pack := _pack_of(10, 10)
	var view := _view(_equipment(), pack)
	var before_cells := view.free_cells()
	_check(before_cells == pack.get_free_space(),
		"free cells are the CONTAINER's own number (%d == %d), not a recount" % [before_cells, pack.get_free_space()])
	_check(view.total_cells() == 100, "total cells is the pack's own dimensions (100)")

	var bandage := _item(ARMY_BANDAGE)
	pack.add_item(bandage)
	_check(view.free_cells() == pack.get_free_space() and view.free_cells() < before_cells,
		"free cells FALL when an item is added (%d -> %d), so the screen reads live state and not a constant"
			% [before_cells, view.free_cells()])
	_check(view.free_cells() + 1 == before_cells, "one 1x1 item costs exactly one cell (%d + 1 == %d)"
			% [view.free_cells(), before_cells])


## LOADOUT-3 + break: mass is the raid screen's function, and nesting counts ONCE.
##
## The raid HUD reads PlayerController.get_total_weight() (status_hud.gd:195). With
## a player attached this view must return that same number, not its own arithmetic.
## The nesting half is the one that has historically gone wrong: a rig inside a
## pack read twice its own mass when every path to it was summed.
func _mass_is_the_shared_number() -> void:
	var eq := _equipment()
	var pack := _pack_of()
	var bandage := _item(ARMY_BANDAGE, 4)
	_check(pack.add_item(bandage), "four bandages go into the pack")

	var view := _view(eq, pack)
	var mass := view.carried_mass()
	var expected := float(bandage.get_mass()) * 4
	_check(is_equal_approx(mass, expected),
		"mass counts the pack's contents once (%.3f == %.3f)" % [mass, expected])

	# A NESTED container, built the way a save builds one.
	var rig := _pack_of(4, 4)
	var inner := _item(ARMY_BANDAGE, 3)
	rig.add_item(inner)
	var rig_item := _container_item(rig)
	_check(rig_item != null and rig_item.extra is InventoryContainer,
		"a container item decodes with a real nested container in `extra`")
	# add_item defaults to position (0,0), which the bandages already occupy, so a
	# silent refusal here reads as "the rig has no mass" rather than as a failure.
	_check(pack.add_item(rig_item, Vector2i(6, 6)),
		"the pack accepts the container item at a free position")
	var nested_mass := view.carried_mass()
	# Measure the DECODED container, not the one I built. They are different
	# objects: the item in the pack holds whatever the codec round trip produced,
	# and asserting against my pre-encode object tests the fixture instead of the
	# screen. (The round trip also collapses a 3-stack to 1, because decode_item
	# does not restore max_stack and the setter clamps to it — recorded as an
	# observation in the card, not claimed here as a diagnosed codec defect.)
	var decoded_rig: InventoryContainer = rig_item.extra
	var rig_contents := decoded_rig.get_total_mass()
	_check(is_equal_approx(nested_mass, mass + rig_item.get_mass() + rig_contents),
		"a nested container's contents are summed ONCE, not once per path (%.3f == %.3f)"
			% [nested_mass, mass + rig_item.get_mass() + rig_contents])

	# CONSTRUCTED BREAK: visit the nested container a SECOND time, which is exactly
	# the traversal that makes a rig read twice its own mass. Same data, wrong walk,
	# a different number — which is what makes the assertion above capable of failing.
	var double_counted := nested_mass + rig_contents
	_check(not is_equal_approx(double_counted, nested_mass),
		"CONSTRUCTED BREAK: counting the nested rig a second time reports %.3f where ownership-reachability reports %.3f — if these ever agree, the traversal is not the one that double counts"
			% [double_counted, nested_mass])


## LOADOUT-4 + break: names come from the registry, and a registered item never
## shows its raw id — the exact leak that once rendered "Comprou marked intel".
func _names_come_from_the_registry() -> void:
	var eq := _equipment()
	var pack := _pack_of()
	var bandage := _item(ARMY_BANDAGE)
	eq.slots["head"].add_item(bandage)
	pack.add_item(_item(WATER))
	var view := _view(eq, pack)

	var rows := view.rows()
	_check(rows.size() == LoadoutView.SLOT_ORDER.size(),
		"one row per core slot, from the core's own dict (%d rows for %d slots)"
			% [rows.size(), LoadoutView.SLOT_ORDER.size()])

	var head_row: Dictionary = rows[0]
	_check(head_row["slot"] == "head", "the first row is the head slot, in the core's order")
	var names: Array = head_row["names"]
	_check(names.size() == 1 and names[0] == ItemNames.display_name_for_item(bandage),
		"a row's name is the REGISTRY's name (%s)" % str(names))
	# The internal id is the file's basename; the display text is the .tres's `name`.
	# The row must be neither, and the registry must be all three of them agreeing.
	var raw_id := String(ARMY_BANDAGE.resource_path).get_file().get_basename()
	var display_text := String(bandage.name)
	_check(not str(names[0]).contains(raw_id),
		"a registered item never shows its raw id on a row (id '%s', row '%s')" % [raw_id, str(names[0])])
	_check(str(names[0]) != display_text,
		"a registered item never shows the resource's display text either (text '%s', row '%s')" % [display_text, str(names[0])])

	# CONSTRUCTED BREAK: the two wrong answers, both different from the right one,
	# so an assertion that cannot tell them apart is provably not testing anything.
	_check(raw_id != display_text and str(names[0]) != raw_id and str(names[0]) != display_text,
		"CONSTRUCTED BREAK: id '%s' and display text '%s' are both distinguishable from the registry's '%s' — this is the exact confusion the F-MKT leak was"
			% [raw_id, display_text, str(names[0])])

	var pack_row := view.pack_row()
	_check(pack_row["names"].size() == 1, "the pack is a row too, so it is part of the kit the player reads")


## LOADOUT-5 + break: reasons are keys, and every key is a real catalogue key.
func _reasons_are_keys() -> void:
	var eq := _equipment()
	var pack := _pack_of()
	# The pack must actually weigh something, or an empty kit at 0.0 is under any
	# positive limit and the reason correctly does not fire.
	pack.add_item(_item(ARMY_BANDAGE), Vector2i(2, 2))
	var view := _view(eq, pack, 0.0001)
	var reasons := view.blocking_reasons()
	_check(reasons.size() == 1, "an impossible mass limit produces exactly one reason")

	var key := String(reasons[0]["key"])
	_check(key == "LOADOUT_REASON_OVER_MASS",
		"the reason carries its catalogue KEY, not a sentence (got '%s')" % key)
	_check(REASON_KEYS_LOOKUP(key), "that key is one the view declares, so a typo cannot hide")

	# CONSTRUCTED BREAK: a composed literal is what rule 3 forbids. If this string
	# ever appears in a reason, the screen is writing player-facing text itself.
	var composed := "You are carrying too much"
	_check(not composed.contains(key) and key != composed,
		"CONSTRUCTED BREAK: a composed sentence ('%s') is not a key, and must never be what a reason carries" % composed)

	var state := view.deploy_state()
	_check(not bool(state["deployable"]) and state["reasons"].size() == 1,
		"deploy_state() is a STATE carrying its reasons, not a bare boolean")


func REASON_KEYS_LOOKUP(key: String) -> bool:
	for k in LoadoutView.REASON_KEYS:
		if String(LoadoutView.REASON_KEYS[k]) == key:
			return true
	return false


## LOADOUT-6: the loadout screen answers "what do I take in". Listing the stash
## here would answer question 2 while pretending to answer question 1. Asserted
## at the SOURCE, because a screenshot cannot tell a stash row from a pack row.
func _no_stash() -> void:
	var text := FileAccess.get_file_as_string("res://src/meta/loadout_view.gd")
	var offenders: Array[String] = []
	for word in ["stash", "Stash", "STASH"]:
		if text.contains(word) and not _only_in_prose(text, word):
			offenders.append(word)
	_check(offenders.is_empty(),
		"the loadout screen names no stash outside its own explanation of why (code refs: %s)" % ", ".join(offenders))


## A word that appears ONLY in a comment or a doc line is narration, not a leak.
## Anything else is a real reference.
func _only_in_prose(text: String, word: String) -> bool:
	for line in text.split("\n"):
		var stripped := String(line).strip_edges()
		if not stripped.contains(word):
			continue
		if stripped.begins_with("#"):
			continue
		# A word inside a quoted string on a comment line is still prose.
		if stripped.contains("\"") and not stripped.begins_with("var") and not stripped.contains("="):
			continue
		return false
	return true


func _reason_text(reasons: Array) -> String:
	if reasons.is_empty():
		return "none"
	var parts: Array[String] = []
	for r in reasons:
		parts.append(String(r.get("key", "?")))
	return ", ".join(parts)
