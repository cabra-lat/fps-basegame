# res://src/meta/stash_view.gd
class_name StashView
extends RefCounted
## The stash / home screen's data: what is stored, what a death would spare, and
## what is still on its way back.
##
## WHY THIS IS NOT A FOURTH INVENTORY IMPLEMENTATION. This tranche already has
## `LoadoutView` and `FreeItemsView`, and the failure mode for a "home screen" is
## to re-derive capacity, mass and occupancy locally and then disagree with the
## raid screen about whether a container is full. So this view reads and labels.
## It never sums a mass, never counts free cells, and never asks "is this cell
## taken" with anything other than the grid's own answer:
##   - capacity and free cells   Stash (an InventoryContainer), get_free_space()
##   - mass                      total_weight / max_weight on the container
##   - occupancy                  InventoryGrid.occupant_at(), NOT the UI's
##                                get_slot_by_grid_position(), which is a linear
##                                O(N) scan (container.gd:148) that bypasses the
##                                grid entirely. Measured at 2.9 ms for a 225-cell
##                                container; routing new code through it would
##                                have made the screen the bottleneck.
##
## THE THREE POPULATIONS, because they answer different questions and a home
## screen that merges them misleads:
##   STORED       in the stash right now, and the player owns it
##   SAFE_POCKET  spared by DeathPolicy.keeps() -- owned, and survives a death
##   RECOVERABLE  insured, lost, not yet returned (delegated to Insurance)
## A pending claim is NOT storage. `owns_nothing()` deliberately excludes it, the
## same way FreeItemsView does, because counting items on their way back as owned
## makes the "I own nothing" state unreachable in exactly the window it describes.
##
## IDENTITY, per the tranche's bar: the id comes from ItemNames via the resource
## path -- never the codec's stored "name", never a display string. An unregistered
## row is marked untranslated rather than rendered as English.
##
## STATE IS A KEY, never a composed sentence. This file contains no player-facing
## literals and no Portuguese, which is how "Comprou marked intel" once leaked
## into a translated frame.

enum Population {
	STORED,      ## sitting in the stash now
	SAFE_POCKET, ## kept on death by the death policy
	RECOVERABLE, ## insured, lost, and due back on a later raid
}

const POPULATION_KEYS := {
	Population.STORED: "STASH_POPULATION_STORED",
	Population.SAFE_POCKET: "STASH_POPULATION_SAFE_POCKET",
	Population.RECOVERABLE: "STASH_POPULATION_RECOVERABLE",
}

const REASON_FULL_KEY := "STASH_REASON_FULL"
const REASON_UNREGISTERED_KEY := "STASH_REASON_UNREGISTERED"

var _profile: MetaProfile = null
var _stash: Stash = null
var _insurance: Insurance = null
var _death_policy: DeathPolicy = null


func _init(profile: MetaProfile = null, death_policy: DeathPolicy = null) -> void:
	_profile = profile
	if _profile != null:
		_stash = _profile.stash
		_insurance = _profile.insurance
	_death_policy = death_policy


## One row per stored item, with its grid footprint and identity. Data, not layout.
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _stash == null:
		return out
	for item in _stash.items:
		if item == null:
			continue
		# NOT item.get("resource_path"): an InventoryItem is an Object, whose get()
		# takes one argument, and identity is owned by the codec regardless.
		var path := ItemCodec.content_path(item)
		out.append({
			"id": ItemNames.id_for_path(path),
			"path": path,
			"translated": ItemNames.is_translated_path(path),
			"population": Population.STORED,
			"key": POPULATION_KEYS[Population.STORED],
			"position": item.position,
			"dimensions": item.dimensions,
			"stack": maxi(item.stack_count, 1),
		})
	return out


## What a death would spare, asked of the death policy rather than reimplemented.
## The policy owns that decision; this view only reports it. An empty list with a
## null policy is a legitimate answer and is NOT treated as an error.
func safe_pocket_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _death_policy == null or _profile == null:
		return out
	for data in _policy_kept_paths():
		var path := String(data.get("path", ""))
		out.append({
			"id": ItemNames.id_for_path(path),
			"path": path,
			"translated": ItemNames.is_translated_path(path),
			"population": Population.SAFE_POCKET,
			"key": POPULATION_KEYS[Population.SAFE_POCKET],
		})
	return out


## Insured items lost and not yet returned, delegated to Insurance. Same rows as
## FreeItemsView by design -- two screens disagreeing about what is on its way is
## the exact bug this tranche is trying to prevent.
func recoverable_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _insurance == null:
		return out
	for claim in _insurance.pending:
		var due_raid := int(claim.get("due_raid", 0))
		for data in claim.get("items", []):
			if not (data is Dictionary):
				continue
			var path := String(data.get("path", ""))
			out.append({
				"id": ItemNames.id_for_path(path),
				"path": path,
				"translated": ItemNames.is_translated_path(path),
				"population": Population.RECOVERABLE,
				"key": POPULATION_KEYS[Population.RECOVERABLE],
				"due_raid": due_raid,
				"raids_until": maxi(due_raid - (_profile.raids if _profile != null else 0), 0),
			})
	return out


## Capacity, delegated. N here is the number the GPU question was asked about:
## a stash is 10x20 = 200 cells and a raid container 15x15 = 225, with no upgrade
## path, so this screen's work is bounded and small.
func capacity() -> int:
	return _stash.grid_width * _stash.grid_height if _stash != null else 0


func free_cells() -> int:
	return _stash.get_free_space() if _stash != null else 0


func used_cells() -> int:
	return maxi(capacity() - free_cells(), 0)


func stored_weight() -> float:
	return _stash.total_weight if _stash != null else 0.0


func weight_limit() -> float:
	return _stash.max_weight if _stash != null else 0.0


## The preserved role KIT for a faction, as rows with the same identity rules as
## every other population.
##
## MY FIRST VERSION ASKED THE WRONG QUESTION. It took a faction id and tried to
## resolve a role's display_name_key, which assumes a faction->role mapping. There
## is none: FactionNames.KEYS is contractor/drifter/raider and the only role
## resource on disk is field_scout, so that lookup returns "" for every real
## faction and the check asserting it was non-empty could never have passed. The
## preserved kit is reachable through `role_kit()`, which is the real API, so that
## is what this uses.
func preserved_role_kit_rows(faction_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _profile == null or faction_id == "":
		return out
	var kit: Dictionary = _profile.role_kit(faction_id)
	for slot in kit.keys():
		for data in kit[slot]:
			if not (data is Dictionary):
				continue
			var path := String(data.get("path", ""))
			out.append({
				"id": ItemNames.id_for_path(path),
				"path": path,
				"translated": ItemNames.is_translated_path(path),
				"population": Population.SAFE_POCKET,
				"key": POPULATION_KEYS[Population.SAFE_POCKET],
				"slot": String(slot),
			})
	return out


## A ROLE'S display name, resolved from a role id through its own resource, never
## through ItemNames. A role is not an item and the two namespaces must not cross.
## Kept as a separate function precisely because the faction->role mapping does not
## exist, so a caller must already have a ROLE id to use it.
func role_display_name_key(role_id: String) -> String:
	if role_id == "":
		return ""
	var res := load("res://resources/meta/roles/%s.tres" % role_id) as RoleDefinition
	return res.display_name_key if res != null else ""


## True when the player holds nothing stored AND nothing equipped. A pending claim
## is excluded: those items are on their way, not in hand.
func owns_nothing() -> bool:
	if _profile == null:
		return false
	return _profile.stash_item_count() == 0 and _profile.loadout.is_empty()


## Why a row cannot be shown yet, as a KEY. A row with no registry entry is the
## one the player is most likely to be looking at, so it is marked rather than
## silently rendered as English.
func reason_key_for(path: String) -> String:
	if ItemNames.id_for_path(path) == "":
		return REASON_UNREGISTERED_KEY
	if used_cells() >= capacity() and capacity() > 0:
		return REASON_FULL_KEY
	return ""


## Is this item spared by the death policy? Delegated to `keeps()` rather than
## re-deriving the pocket rule, and the answer is a bool the screen renders.
func is_kept_on_death(item_path: String, item: Variant = null) -> bool:
	if _death_policy == null:
		return false
	return _death_policy.keeps(item_path, item)


## Every population at once, for a screen that renders one list.
func all_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(rows())
	out.append_array(safe_pocket_rows())
	out.append_array(recoverable_rows())
	return out


func has_any_content() -> bool:
	return not all_rows().is_empty()


## The paths the policy keeps, from the policy's own partition of the loadout.
## Asked once and reused, so a screen cannot show the pocket twice by iterating it
## per row.
##
## THE SHAPE IS `{lost: Array, kept: {slot: Array}}`, keyed by SLOT and then by
## entry. My first version treated the top-level dict as the kept entries, so it
## would have iterated the two keys "lost" and "kept" and produced two garbage
## rows with an empty path -- a screen showing two blank safe-pocket items. The
## harness's registered/translated/unregistered fixture is what makes that
## visible, because a garbage row has path "" and takes the unregistered branch.
func _policy_kept_paths() -> Array:
	if _death_policy == null or _profile == null:
		return []
	var result: Dictionary = _death_policy.partition(_profile.loadout)
	if not result.has("kept"):
		return []
	var out: Array = []
	for slot in result["kept"].keys():
		for entry in result["kept"][slot]:
			if entry is Dictionary:
				out.append(entry)
	return out


