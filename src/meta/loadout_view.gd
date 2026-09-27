class_name LoadoutView
extends RefCounted

## The loadout screen's CONTENT, with no pixels in it.
##
## WHY A VIEW-MODEL AND NOT A CONTROL. The screen's job is to answer "does another
## magazine still fit", and that is a question about the kit, not about geometry.
## Keeping the answers here means they can be asserted without a rendered frame,
## which is also why this file can hold real invariants: the design pass's harness
## discipline requires an awaited frame and a settled layout before ANY assertion
## reads a position or a size, and a screen whose correctness lives in layout
## cannot be tested at all. Nothing here reads position, size or scroll.
##
## ONE SOURCE OF TRUTH, and this is the rule the whole file exists to keep. The
## raid screen shows mass from PlayerController.get_total_weight() (see
## status_hud.gd:195) and free cells from the container's grid. A loadout screen
## that recomputes either is a second implementation of a value that already has
## one, and the two drift the moment either changes. So every number below is a
## DELEGATION to the function the raid screen already calls, never arithmetic
## over the same data. The harness asserts the delegation by breaking the delegate.
##
## OWNERSHIP REACHABILITY, NOT PANEL STATE (design pass rule 5). Mass is what the
## player can REACH: the equipped slots plus the equipped pack, with a nested
## container summed once. Folding a panel must not change your own mass, so
## nothing in this file depends on a panel being open.

## Slots in the order the design pass reads them: the worn kit, then what is in
## the pack. DATA, not a hardcoded layout: the core Equipment owns this dict and a
## game that ships a different rig does not edit this file.
const SLOT_ORDER := ["head", "torso", "arms", "legs", "primary", "secondary", "back"]

## A blocking reason, as a KEY and never a composed literal (design pass rule 3).
## The screen's job is to say WHICH ITEM is the reason, next to that item; the
## sentence is the catalogue's, not this file's.
enum Reason {
	NONE,
	OVER_MASS,       ## the kit is heavier than the player may carry
	CONTAINER_CYCLE, ## a container holds itself or a descendant; only a corrupt save makes this
	SLOT_NOT_COMPATIBLE, ## an equipped item's category does not belong in its slot
	GRID_OVERLAP,    ## two items claim the same cells
	OUT_OF_BOUNDS,   ## an item hangs off the edge of its container
}

## The reason keys, as the catalogue msgids. Kept here so a missing translation is
## a missing ENTRY in one place and not a hardcoded Portuguese sentence in a
## format string, which is how the market feed once leaked "Comprou marked intel".
const REASON_KEYS := {
	Reason.OVER_MASS: "LOADOUT_REASON_OVER_MASS",
	Reason.CONTAINER_CYCLE: "LOADOUT_REASON_CONTAINER_CYCLE",
	Reason.SLOT_NOT_COMPATIBLE: "LOADOUT_REASON_SLOT_NOT_COMPATIBLE",
	Reason.GRID_OVERLAP: "LOADOUT_REASON_GRID_OVERLAP",
	Reason.OUT_OF_BOUNDS: "LOADOUT_REASON_OUT_OF_BOUNDS",
}

var equipment: Equipment = null
var pack: InventoryContainer = null
var max_mass: float = 0.0


func _init(eq: Equipment = null, pack_container: InventoryContainer = null, mass_limit: float = 0.0) -> void:
	equipment = eq
	pack = pack_container
	max_mass = mass_limit


## The player, when the screen is showing a live rig. Used ONLY to delegate mass to
## the raid screen's own function; a view built from a detached profile has no
## player and takes its numbers from the equipment and pack directly.
var player: Node = null


## ── the two numbers, delegated ────────────────────────────────────────────────

## Carried mass, in the SAME units and from the SAME function the raid HUD shows.
## With a player attached this is literally status_hud.gd's call, so the two
## screens cannot disagree; without one it is equipment + pack, which is what
## get_total_weight() itself does.
func carried_mass() -> float:
	if player != null and player.has_method("get_total_weight"):
		return float(player.get_total_weight())
	var total := 0.0
	if equipment != null:
		total += equipment.get_total_mass()
	if pack != null:
		total += pack.get_total_mass()
	return total


## Free cells in the pack, delegated to the container's own accounting rather than
## counted here. A screen that counted occupied cells itself would be a second
## implementation of the grid's truth.
func free_cells() -> int:
	if pack == null:
		return 0
	return pack.get_free_space()


## Cells the pack holds in total, for the "12 / 90" reading. Delegated as well.
func total_cells() -> int:
	if pack == null:
		return 0
	return pack.grid_width * pack.grid_height


## ── the kit as rows, not as a sentence ────────────────────────────────────────

## One row per slot, each carrying the items the player can see. This is the
## replacement for operations_hub.gd:306 _details_text(), which returned a
## comma-joined caption of a kit. A caption cannot answer whether another magazine
## fits, because a caption has no cells in it.
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if equipment == null:
		return out
	for slot_name in SLOT_ORDER:
		var slot = equipment.slots.get(slot_name)
		if slot == null:
			continue
		var items: Array = slot.items
		out.append({
			"slot": slot_name,
			"items": items,
			# Identity from the id-to-translation-key REGISTRY, never display text.
			# item.name is the internal id and is exactly what leaked once.
			"names": items.map(func(i): return ItemNames.display_name_for_item(i)),
		})
	return out


## The pack's own contents as a row, so the pack is part of the kit the player is
## reading rather than a corner of the screen.
func pack_row() -> Dictionary:
	var items: Array = pack.items if pack != null else []
	return {
		"slot": "pack",
		"items": items,
		"names": items.map(func(i): return ItemNames.display_name_for_item(i)),
	}


## Every item in the kit, in reach order: worn first, then the pack, then anything
## nested inside it. NESTED CONTAINERS ARE SUMMED ONCE and VISITED ONCE, because
## counting a container's contents once per path is how a nested rig reads twice
## its own mass.
func reachable_items() -> Array:
	var out: Array = []
	for row in rows():
		out.append_array(row["items"])
	if pack != null:
		_collect(pack, out, 0)
	return out


func _collect(container: InventoryContainer, out: Array, depth: int) -> void:
	# Depth guard rather than a seen-set: a container cannot contain itself
	# (accepts_item refuses a descendant), so this is belt and braces against a
	# cycle that a hand-edited save could still introduce.
	if depth > 8:
		return
	for item in container.items:
		out.append(item)
		if item != null and item.extra is InventoryContainer:
			_collect(item.extra, out, depth + 1)


## ── deploy validity: a state with a reason, not a greyed button ──────────────
##
## THE DESIGN PASS'S THREE REMAINING REASONS ARE NOW ANSWERABLE, and this comment
## is the record of why they were not before, because the reason was a trap rather
## than a missing feature.
##
##   EquipmentSlot.can_add_item() is an INSERTION predicate: it returns false the
##   moment the slot is occupied, so it answers "may I drop this in" and not "is
##   what is in here legal". A validator built on it condemns every worn slot --
##   the harness demonstrates that, 2 violations on a legal kit. The addon now
##   carries is_legal_while_equipped() for the other question, sharing ONE
##   compatibility implementation with can_add_item so the two cannot drift.
##
##   Overlap and bounds needed a READ of the occupancy table that does not rebuild
##   it, which did not exist; the addon now carries occupant_at() and
##   fits_in_bounds(). A rebuild-per-question would be both a lie about the grid's
##   current state and a cost paid per question.
##
## What this file still does NOT do is re-implement either. It asks.

## Every reason the kit cannot be deployed, each attached to the SLOT it belongs
## to, so the screen can say which item is the reason NEXT TO THAT ITEM instead of
## greying a button and sending the player to hunt.
##
## THE TWO QUERIES THIS ASKS ARE NOT LOCAL TO THIS FILE, and that is the whole
## point. `is_legal_while_equipped()` is the slot's own category rule asked about
## an item that is ALREADY equipped -- deliberately not can_add_item(), which is
## the insertion question and returns false for any occupied slot, so building on
## it condemns every worn slot. `occupant_at()` is a pure read of the grid's
## occupancy table. Both were added to the shooter addon for this screen and both
## delegate rather than re-decide: a second copy of the slot's category match, or
## of the occupancy walk, is how a kit becomes legal in the screen and illegal in
## the game (design pass rule 2).
func blocking_reasons() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if max_mass > 0.0 and carried_mass() > max_mass:
		out.append({"slot": "", "item": null, "reason": Reason.OVER_MASS, "key": REASON_KEYS[Reason.OVER_MASS]})
	if equipment != null:
		for slot_name in SLOT_ORDER:
			var slot = equipment.slots.get(slot_name)
			if slot == null:
				continue
			for item in slot.items:
				if item != null and not slot.is_legal_while_equipped(item):
					out.append({
						"slot": slot_name,
						"item": item,
						"reason": Reason.SLOT_NOT_COMPATIBLE,
						"key": REASON_KEYS[Reason.SLOT_NOT_COMPATIBLE],
					})
	if pack != null:
		out.append_array(_container_reasons(pack, "pack", 0))
	return out


## One walk of the pack, carrying each item's OWN index so occupancy can be
## attributed: a cell held by a different index is an overlap, a cell held by this
## item is simply where the item is.
func _container_reasons(container: InventoryContainer, slot_name: String, depth: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if depth > 8:
		return out
	var grid = container.grid
	for index in container.items.size():
		var item: InventoryItem = container.items[index]
		if item == null:
			continue
		if not grid.fits_in_bounds(item.position, item.dimensions):
			out.append({
				"slot": slot_name, "item": item,
				"reason": Reason.OUT_OF_BOUNDS, "key": REASON_KEYS[Reason.OUT_OF_BOUNDS],
			})
		else:
			var clash := false
			for y in item.dimensions.y:
				for x in item.dimensions.x:
					var occupant: int = grid.occupant_at(item.position + Vector2i(x, y))
					if occupant != -1 and occupant != index:
						clash = true
						break
				if clash:
					break
			if clash:
				out.append({
					"slot": slot_name, "item": item,
					"reason": Reason.GRID_OVERLAP, "key": REASON_KEYS[Reason.GRID_OVERLAP],
				})
		if item.extra is InventoryContainer:
			if not container.accepts_item(item):
				out.append({
					"slot": slot_name, "item": item,
					"reason": Reason.CONTAINER_CYCLE, "key": REASON_KEYS[Reason.CONTAINER_CYCLE],
				})
			out.append_array(_container_reasons(item.extra, slot_name, depth + 1))
	return out


## Deploy validity as a STATE, with the reasons that produced it. A caller that
## only wants the boolean can ask is_deployable(); a caller that renders gets the
## reasons and puts them next to the items.
func deploy_state() -> Dictionary:
	var reasons := blocking_reasons()
	return {
		"deployable": reasons.is_empty(),
		"reasons": reasons,
		"free_cells": free_cells(),
		"carried_mass": carried_mass(),
		"max_mass": max_mass,
	}


func is_deployable() -> bool:
	return blocking_reasons().is_empty()


## MUST NOT SHOW anything about the stash (design pass section 1). This screen
## answers "what do I take in"; "take from stash" is the stash screen's decision,
## and a screen that lists both is answering question 2 while pretending to answer
## question 1. The guard is in the harness, asserted at the SOURCE, because a
## screenshot cannot tell a stash row from a pack row.
##
## There is deliberately no `touches_stash()` accessor here. A function that
## returns a constant is not a guard, it is a comment with a return type, and it
## put the word it was forbidding into the source the harness greps for.
