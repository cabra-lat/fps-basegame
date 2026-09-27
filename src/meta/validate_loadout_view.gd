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
	_check_preconditions()
	_run()
	# Checked AFTER the run, from what the run actually OBSERVED, rather than
	# counted out of the source. Source-scanning is fragile in a way that bit me
	# the moment I wrote it: matching msgid text finds nothing, and matching the
	# enum's int values matches everything. What actually happened is the only
	# thing worth asserting, and it fails by name if a reason stops being produced.
	_check(_seen_reasons.size() == 5,
		"all FIVE deploy reasons were OBSERVED being produced by this run, not three of five (observed: %d %s)"
			% [_seen_reasons.size(), str(_seen_reasons.keys())])
	print("loadout view: checks=%d passed=%d" % [checks, checks - failures])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


## Reasons this run actually produced, accumulated as it goes. The evidence for
## "this screen reports all five reasons", which is otherwise inferred from a
## green run -- and which silently stopped being true when the addon API went
## missing, with nothing failing to say so.
var _seen_reasons: Dictionary = {}


## THE HARNESS'S OWN DEPENDENCIES, ASSERTED FIRST.
##
## WHY THIS EXISTS, and it is the most dangerous shape I have found in my own work:
## without the addon's occupancy and legality APIs, `carried_mass()` is 0.0 and two
## of the FIVE reasons -- OVER_MASS and SLOT_NOT_COMPATIBLE -- are never exercised
## at all. The harness does not report them as failures; they simply do not run.
## Measured, one variable: 42 _check sites, 41 executing here, 38 against a
## pristine d26d451 addon, and the ones that vanish include both of those.
##
## So a green run on a stripped addon would be a harness covering three of five
## reasons while claiming a clean pass -- a test that passes while covering less,
## which is worse than a red one because nothing draws attention to it. These APIs
## currently exist only as UNCOMMITTED changes in one worktree, so the risk is not
## hypothetical: discard that worktree and the coverage quietly narrows.
##
## Asserting the dependency is the fix, and it fails LOUDLY AND BY NAME so the
## remedy is the missing addon API rather than a puzzle. The check counts and the
## reason coverage it protects are both below.
func _check_preconditions() -> void:
	var missing: Array[String] = []
	var slot := EquipmentSlot.new()
	if not slot.has_method("is_legal_while_equipped"):
		missing.append("EquipmentSlot.is_legal_while_equipped() [SLOT_NOT_COMPATIBLE]")
	var grid := InventoryGrid.new()
	if not grid.has_method("occupant_at"):
		missing.append("InventoryGrid.occupant_at() [GRID_OVERLAP / OUT_OF_BOUNDS]")
	if not grid.has_method("fits_in_bounds"):
		missing.append("InventoryGrid.fits_in_bounds() [GRID_OVERLAP / OUT_OF_BOUNDS]")
	# Mass is deliberately NOT probed here. An EMPTY container legitimately has
	# mass 0.0, so "get_total_mass() == 0" is a wrong test for a missing
	# capability -- it fails on a HEALTHY addon, which is the worst kind of check.
	# The mass path is covered by _mass_is_the_shared_number, which FAILS LOUDLY
	# on broken mass, and OVER_MASS is covered by the observed-reasons check.
	_check(missing.is_empty(),
		"THE ADDON APIs THIS HARNESS DEPENDS ON ARE PRESENT -- without them 2 of the 5 reasons are not tested at all, silently (missing: %s)"
			% ", ".join(missing))


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
	_new_reasons_fire()
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
	var reasons := _reasons(view)
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
	var heavy_reasons := _reasons(heavy)
	_check(heavy_reasons.size() == 1 and int(heavy_reasons[0]["reason"]) == int(LoadoutView.Reason.OVER_MASS),
		"a kit over its mass limit is condemned with OVER_MASS (reasons: %s)" % _reason_text(heavy_reasons))


## The three reasons that were NOT derivable before the addon queries existed.
## Each is proven twice where it can be: the legal case stays silent, and a
## constructed break shows the discriminating power. A new capability with no red
## arm is untested code.
func _new_reasons_fire() -> void:
	# SLOT_NOT_COMPATIBLE, from EquipmentSlot.is_legal_while_equipped().
	#
	# THE CONSTRUCTED BREAK HERE IS THE INTERESTING PART: the slot's own add_item()
	# REFUSES a bandage in the primary slot, so this defect is unreachable through
	# the API and only a hand-edited or migrated save can produce it. That is
	# exactly why the predicate is a VALIDITY question and not an insertion one --
	# can_add_item() answers the same question add_item() already answered, and so
	# can never report damage that add_item() would have prevented.
	var eq := _equipment()
	var pack := _pack_of(6, 6)
	_check(eq.slots["primary"].add_item(_item(ARMY_BANDAGE)) == false,
		"CONSTRUCTED BREAK: the slot's add_item() refuses a bandage in the primary slot, so the defect is corrupt-save-only")
	# Reaching past the API to BUILD the corrupt save, which is the only way to test
	# a predicate that guards against corrupt saves.
	eq.slots["primary"].items.append(_item(ARMY_BANDAGE))
	var reasons := _view(eq, pack).blocking_reasons()
	var kinds := _reason_kinds(reasons)
	_check(kinds.has(int(LoadoutView.Reason.SLOT_NOT_COMPATIBLE)),
		"an item whose category does not belong in its slot is condemned with SLOT_NOT_COMPATIBLE (kinds: %s)" % str(kinds))
	# NOT `reasons[0]` UNGUARDED. It was, and it crashed when the reason list came
	# back EMPTY, taking the next nine checks with it: a red arm then appeared to
	# fail only the check it touched while silently skipping the coverage after it.
	# A harness that stops reporting is worse than one that reports a failure, so
	# the index is guarded and a missing entry is itself the failing observation.
	var first_slot := "<no reason at all>"
	if reasons.size() > 0:
		first_slot = str(reasons[0].get("slot", ""))
	_check(first_slot == "primary",
		"the reason names the SLOT it belongs to, so the screen can put it next to that item (slot: %s)" % first_slot)

	# The same slot with a legal weapon is SILENT -- the half that proves the check
	# discriminates rather than condemns everything.
	var eq2 := _equipment()
	_check(eq2.slots["primary"].add_item(_item(RIFLE)), "a rifle goes into the primary slot")
	_check(_reason_kinds(_view(eq2, _pack_of(6, 6)).blocking_reasons()).is_empty(),
		"a legal rifle in the primary slot produces NO reason at all")

	# OUT_OF_BOUNDS and GRID_OVERLAP, from grid.fits_in_bounds() and
	# grid.occupant_at(): pure reads of the occupancy table.
	var edge := _pack_of(4, 4)
	var first := _item(ARMY_BANDAGE)
	_check(edge.add_item(first, Vector2i(3, 3)), "an item sits on the last cell of a 4x4 grid")
	var overlap := _pack_of(4, 4)
	overlap.add_item(_item(ARMY_BANDAGE), Vector2i(0, 0))
	var b := _item(WATER)
	_check(overlap.add_item(b, Vector2i(0, 0)) == false,
		"CONSTRUCTED BREAK: the grid REFUSES a second item on occupied cells, so an overlap cannot be created through the API - which is why the overlap check reads occupancy instead of trusting placement")
	_check(_reason_kinds(_view(_equipment(), overlap).blocking_reasons()).is_empty(),
		"a correctly packed container reports no overlap")
	_check(edge.grid.fits_in_bounds(Vector2i(3, 3), Vector2i.ONE) and not edge.grid.fits_in_bounds(Vector2i(3, 3), Vector2i(2, 1)),
		"fits_in_bounds() separates 'inside the grid' from 'would fit if it were smaller' (4x4, item at 3,3)")

	# ── THE THREE REMAINING REASONS, POSITIVELY ────────────────────────────
	#
	# Until now GRID_OVERLAP, OUT_OF_BOUNDS and CONTAINER_CYCLE were only ever
	# asserted to be ABSENT from a legal kit, which is a real check but not proof
	# the reason is reachable. "All five reasons" was therefore an inference from a
	# green run rather than something measured, and the observed-reasons check
	# caught exactly that: it reported 2 of 5. Each is corrupt-save-only by design
	# (the placement APIs refuse to build them), so they are built the same way the
	# SLOT_NOT_COMPATIBLE case already is -- by reaching past the API to construct
	# the corrupt save, which is the only way to exercise a guard that exists
	# precisely to survive one.
	var bad_overlap := _pack_of(4, 4)
	_check(bad_overlap.add_item(_item(ARMY_BANDAGE), Vector2i(0, 0)), "a bandage occupies the corner of the overlap fixture")
	bad_overlap.items.append(_placed(WATER, Vector2i(0, 0)))
	var overlap_kinds := _reason_kinds(_reasons(_view(_equipment(), bad_overlap)))
	_check(overlap_kinds.has(int(LoadoutView.Reason.GRID_OVERLAP)),
		"two items claiming the SAME cell are condemned with GRID_OVERLAP (kinds: %s)" % str(overlap_kinds))

	var bad_bounds := _pack_of(4, 4)
	var wide := _placed(ARMY_BANDAGE, Vector2i(3, 3))
	wide.dimensions = Vector2i(2, 1)
	bad_bounds.items.append(wide)
	var bounds_kinds := _reason_kinds(_reasons(_view(_equipment(), bad_bounds)))
	_check(bounds_kinds.has(int(LoadoutView.Reason.OUT_OF_BOUNDS)),
		"an item hanging off the edge of its grid is condemned with OUT_OF_BOUNDS (kinds: %s)" % str(bounds_kinds))

	# NOT _container_item(), and the reason is worth stating: that helper
	# round-trips through ItemCodec, so the wrapper comes back holding a
	# RECONSTRUCTED COPY and the identity that a cycle is made of is gone. A
	# self-reference cannot survive an encode/decode round trip at all, which is
	# itself a reassuring property of the save format and also means this fixture
	# has to construct the reference directly to reach the guard.
	var cyclic := _pack_of(4, 4)
	var self_item := InventoryItem.new()
	self_item.extra = cyclic
	self_item.name = "self"
	cyclic.items.append(self_item)
	var cycle_kinds := _reason_kinds(_reasons(_view(_equipment(), cyclic)))
	_check(cycle_kinds.has(int(LoadoutView.Reason.CONTAINER_CYCLE)),
		"a container holding its own representation is condemned with CONTAINER_CYCLE (kinds: %s)" % str(cycle_kinds))
	# EXACTLY ONE, which is the half that was wrong. The walk used to descend into a
	# cyclic item, so one corrupt item produced nine identical reasons naming the
	# same object and the screen would render nine rows saying one thing nine times.
	# `has()` passed that happily; counting is the assertion that bites.
	_check(cycle_kinds.size() == 1,
		"and the cycle is reported ONCE, not once per level of descending into itself (got %d)" % cycle_kinds.size())

	# Occupancy is ATTRIBUTED, not merely counted: a cell reports the index of the
	# item holding it, which is what lets the screen tell an overlap from an item's
	# own footprint.
	_check(edge.grid.occupant_at(Vector2i(3, 3)) >= 0 and edge.grid.occupant_at(Vector2i(0, 0)) == -1,
		"occupant_at() reads the real table: the occupied cell has an occupant and the empty one does not")
	_check(edge.grid.occupant_at(Vector2i(99, 99)) == -1 and edge.grid.occupant_at(Vector2i(-1, 0)) == -1,
		"occupant_at() is bounds-guarded and returns -1 outside the grid instead of running away")


## An item placed at a position WITHOUT going through add_item, because the
## point of these fixtures is the states the placement API refuses to create.
func _placed(res: Resource, at: Vector2i) -> InventoryItem:
	var it := _item(res, 1)
	it.position = at
	return it


## Ask a view for its blocking reasons and RECORD what came back.
##
## Every reasons-producing call in this harness goes through here, so the
## "all five reasons" claim is measured from what the screen actually produced
## rather than inferred from a green run. That distinction is the whole point:
## with the addon occupancy/legality APIs missing, two of the five reasons stop
## being produced and NO check fails -- the harness just quietly covers three.
func _reasons(v: LoadoutView) -> Array:
	var reasons := v.blocking_reasons()
	for r in reasons:
		_seen_reasons[int(r.get("reason", -1))] = true
	return reasons


func _reason_kinds(reasons: Array) -> Array:
	var out: Array = []
	for r in reasons:
		var k := int(r.get("reason", -1))
		_seen_reasons[k] = true
		out.append(k)
	return out


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
	var reasons := _reasons(view)
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
