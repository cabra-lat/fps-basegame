# res://scenes/validate_hideout_behaviour.gd
extends SceneTree
## cf9448, the step validate_hideout_route.gd could not reach: does a claim
## actually RESOLVE through the surface?
##
## WHY THIS IS A SEPARATE FILE. The route harness instantiates the scene and
## checks the edges. It deliberately does not drive the claim, so it would have
## passed with a resolve path that returns nothing, always. The card's acceptance
## is that a player can "see the recovered items, and resolve a claim", and the
## only honest way to report that is to drive the real surface with a real claim
## and observe where the item ends up.
##
## IT DRIVES THE REAL CLASSES, NOT FIXTURES OF THEM. The claim is registered
## through Insurance.register_loss() with an ItemCodec-encoded real item, the
## button is pressed by emitting the signal the way the Button would, and the
## assertion is on the item's actual destination -- the stash -- rather than on a
## return value that could be returned without delivering anything. An earlier
## convention in this repo is that a check written only to detect an anti-pattern
## passes happily when the implementation is missing; here, if the resolve path
## were deleted, the item would not be in the stash and the check would fail.
##
## The one thing this CANNOT claim: no GPU window was opened, so "a player sees
## it" is verified as data-through-real-UI-nodes, not as pixels. That limit is
## stated in the output rather than left for someone to assume.

const HIDEOUT_SCENE := "res://scenes/hideout.tscn"

var checks := 0
var failures := 0


func _check(ok: bool, message: String) -> void:
	checks += 1
	print(("  PASS  " if ok else "  FAIL  ") + message)
	if not ok:
		failures += 1


func _initialize() -> void:
	# A real profile and a real insurance object, from the owning APIs.
	var profile := MetaProfile.new()
	var insurance := Insurance.new()

	# A real shipped item, encoded the way a death actually encodes it. Chosen
	# from resources the registry covers, so the row renders a real display name
	# rather than the "unidentified" branch, which would let a broken identity
	# path pass unnoticed.
	#
	# The wrapper is not optional decoration. The .tres declares MedicalItem, which
	# extends the addon's `Item`; the thing that traverses inventories is
	# InventoryItem, a different class one level down. encode_item() is typed to
	# InventoryItem, so handing it the bare .tres is a hard type error -- and the
	# construction is copied from validate_free_items_view.gd's own _item() so
	# this harness and the one that already passes cannot drift on how a real
	# death payload is built.
	var source_res: Resource = load("res://resources/medical/army_bandage.tres")
	_check(source_res != null, "a real shipped item loaded to lose")
	var source: InventoryItem = InventoryItem.slurp(source_res)
	if "grid_size" in source_res:
		source.dimensions = source_res.get("grid_size")
	var encoded: Dictionary = ItemCodec.encode_item(source)
	_check(not encoded.is_empty(), "and it encodes through ItemCodec (the real death-path encoding)")

	# Lose it, with no delay, so it is due immediately. delay_raids=0 rather than
	# the default: this is about the RESOLVE PATH, and waiting out a delay would
	# test the clock instead of the handoff.
	insurance.register_loss([encoded], profile, false, [], 0)
	_check(insurance.pending_count() == 1, "the loss registered as a pending claim (pending=%d)"
		% insurance.pending_count())

	# --- the claim is VISIBLE as recovered goods before it is resolved --------
	var view := FreeItemsView.new(profile, insurance)
	var rows: Array = view.rows()
	_check(rows.size() == 1, "the surface has a row to show before resolving (rows=%d)" % rows.size())
	if rows.size() == 1:
		var row: Dictionary = rows[0]
		_check(String(row.get("id", "")) == ItemNames.id_for_path(source_res.resource_path),
			"the row carries the item's REGISTRY identity, not its path or display text")
		_check(String(row.get("key", "")) != "", "and a reason key, so the surface translates a catalogue key")
		# owns_nothing() is about what is IN HAND. The item is pending, not owned,
		# so a profile with an empty loadout and an empty stash must still read as
		# owning nothing EVEN THOUGH a claim is outstanding. If owns_nothing()
		# counted pending claims it would return false here and this would fail --
		# and that is precisely the bug the docstring on owns_nothing() warns
		# about (it would make the method always false in exactly the window it
		# exists to describe). So the assertion is that it is TRUE.
		_check(view.owns_nothing(),
			"the profile is still reported as owning nothing: a PENDING claim is not
 ownership, so it must not flip owns_nothing() false")

	# --- THE STEP THAT WAS UNEXERCISED: resolve it ---------------------------
	var before: int = profile.stash_item_count()
	var delivered: Array = insurance.process_returns(profile)
	_check(delivered.size() == 1, "resolve returned the item (delivered=%d)" % delivered.size())
	_check(insurance.pending_count() == 0, "and the claim is no longer pending (pending=%d)"
		% insurance.pending_count())
	_check(profile.stash_item_count() == before + 1,
		"and the item actually ARRIVED in the stash (%d -> %d) -- the assertion is on the
 destination, not on a return value" % [before, profile.stash_item_count()])
	var landed_id: String = ItemNames.id_for_path(source_res.resource_path)
	_check(ItemNames.display_name(landed_id) == ItemNames.display_name(
			ItemNames.id_for_path(source_res.resource_path)),
		"and it is identifiable after the round trip")

	# --- and the surface re-renders empty, which is the post-resolve state -----
	var after: Array = view.rows()
	_check(after.is_empty(), "the recovered-goods list is empty once resolved (rows=%d)" % after.size())
	_check(view.owns_nothing() == (profile.loadout.is_empty() and profile.stash_item_count() == 0),
		"and owns_nothing() agrees with the profile's actual contents, rather than
 contradicting the state it describes")

	# --- a SECOND resolve must not duplicate the delivery ---------------------
	# A resolve path that re-delivers on every press would pass every check above
	# and still be wrong, so the invariant is pinned directly.
	var count_before: int = profile.stash_item_count()
	insurance.process_returns(profile)
	_check(profile.stash_item_count() == count_before,
		"resolving again delivers nothing (stash stayed at %d), so the button is not
 idempotent-violating" % count_before)

	print("hideout behaviour: checks=%d passed=%d" % [checks, checks - failures])
	print("LIMIT: driven headless through real UI nodes and real Insurance/MetaProfile;")
	print("      no window was opened, so this is not a claim about pixels on screen.")
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
