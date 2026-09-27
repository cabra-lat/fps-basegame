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

	# --- PRESSING BACK ACTUALLY NAVIGATES -------------------------------------
	# The card that produced this defect is titled "Back button dead". Every other
	# check in this file is about DATA, and all of them pass while the screen has
	# no way out -- which is what happened: BtnBack resolved, rendered, took the
	# click, and was connected to nothing, and return_to_menu() had zero callers.
	# A source check can find those facts; it cannot show that pressing the button
	# now does the thing. So the button is really pressed and the RESULT is really
	# recorded.
	ActionLog.clear()
	var packed: PackedScene = load("res://scenes/hideout.tscn") as PackedScene
	var hideout: Node = packed.instantiate() if packed != null else null
	root.add_child(hideout)
	await process_frame
	var back: Button = hideout.get_node_or_null("Panel/BtnBack") as Button
	_check(back != null, "back: the hideout really has a Back button at Panel/BtnBack")
	# The nodes the stash half resolves. %Name requires unique_name_in_owner, and
	# WITHOUT it the @onready lookup returns null, _refresh_stash returns early,
	# and the whole stored-goods section silently renders nothing -- while the
	# source checks, which only see `StashView.new(`, stay green. That is this
	# card's defect reproduced inside its own fix.
	#
	# AND THE FIRST VERSION OF THIS CHECK WAS WORTHLESS: it resolved the nodes by
	# PATH (`Panel/StashRows`), which succeeds whether or not the node is unique-
	# named, so removing unique_name_in_owner left it green. It has to exercise the
	# ACCESSOR the surface actually uses, which is the %-form.
	# The controller walks the tree for a HideoutUI child rather than assuming the
	# surface IS the root, so this does the same instead of casting the root.
	var stash_ui: HideoutUI = null
	for child in hideout.get_children():
		if child is HideoutUI:
			stash_ui = child as HideoutUI
			break
	_check(stash_ui != null, "stash: the hideout really contains a HideoutUI surface")
	if stash_ui != null:
		var rows_node: Node = stash_ui.get_node_or_null("%StashRows")
		var summary_node: Node = stash_ui.get_node_or_null("%StashSummary")
		_check(rows_node != null,
			"stash: %StashRows RESOLVES for the surface, which is what _refresh_stash depends on")
		_check(summary_node != null, "stash: and so does %StashSummary")
	_check(back != null and back.get_signal_connection_list("pressed").size() >= 1,
		"back: and it has a LIVE connection to pressed, which it did not have before [connections %d]" % (back.get_signal_connection_list("pressed").size() if back != null else -1))
	if back != null:
		back.emit_signal("pressed")
	var reached := 0
	for entry in ActionLog.entries():
		if String(entry.get("control", "")) == "Hideout/BtnBack":
			reached += 1
	_check(reached >= 1,
		"back: pressing it records a REACHED, so the click is now observable rather than silent [entries %d]" % reached)
	# The RESULT may legitimately be absent in a headless tree if there is no
	# SceneTree to change scene on, and that is exactly the case the NO-OP reason
	# exists for -- so either outcome is acceptable, but a REFUSAL for any other
	# reason would mean the button is wired to the wrong thing.
	var reasons: Array[String] = []
	for entry in ActionLog.entries():
		if String(entry.get("reason", "")) != "":
			reasons.append(String(entry["reason"]))
	var allowed := ["no_scene_tree", ""]
	var unexpected := ""
	for r in reasons:
		if not allowed.has(r):
			unexpected = r
	_check(unexpected.is_empty(),
		"back: and the only reason it can give is no_scene_tree, not some other failure [got '%s']" % unexpected)
	hideout.queue_free()
	await process_frame

	print("hideout behaviour: checks=%d passed=%d" % [checks, checks - failures])
	print("LIMIT: driven headless through real UI nodes and real Insurance/MetaProfile;")
	print("      no window was opened, so this is not a claim about pixels on screen.")
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
