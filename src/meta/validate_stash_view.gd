# res://src/meta/validate_stash_view.gd
extends SceneTree
## Harness for StashView (card e48dd5, stash/home screen).
##
## WHAT IT DELIBERATELY DOES NOT CLAIM. It proves the view DELEGATES: that its
## capacity, free cells, mass and occupancy agree with the container and the grid
## that own them, and that a death-pocket answer comes from DeathPolicy rather
## than from a rule restated here. It does not prove the screen LOOKS right --
## that needs the running-game pass, which is not what this card is doing yet.

## REGISTERED AND TRANSLATED. Measured, not assumed: 8 of the 50 registered ids
## actually translate. My first fixture was 7_62_39mm_PS_GOST_BR4, which is NOT in
## the registry at all, so the "translated" branch was never reachable and the
## three-branch check silently degenerated into 0/1/2.
const AMMO := preload("res://resources/weapons/M4_Carbine.tres")                ## registered + translated
const BRAZIL := preload("res://resources/weapons/Brazil_556.tres")            ## registered, untranslated
const BUCKSHOT := preload("res://resources/ammo/12_70_8.5mm_Magnum_buckshot.tres")  ## deliberately unregistered

var _pass := 0
var _fail := 0
var _fail_lines: Array[String] = []


func _initialize() -> void:
	_run()


func _finish() -> void:
	print("")
	print("=== validate_stash_view summary ===")
	print("  checks passed  %d" % _pass)
	print("  FAILURES       %d" % _fail)
	var code := 0
	if _fail > 0:
		for line in _fail_lines:
			print("  FAIL  " + line)
		print("RESULT: FAIL")
		code = 1
	else:
		print("RESULT: PASS")
	call_deferred("_quit", code)


func _quit(code: int) -> void:
	quit(code)


func _profile() -> MetaProfile:
	var p := MetaProfile.new()
	var service := MetaService.new()
	service.use_profile(p, "")
	return p


func _put(p: MetaProfile, res: Resource, stack: int = 1) -> void:
	var it := InventoryItem.slurp(res)
	it.stack_count = stack
	p.stash.deposit(it)


func _run() -> void:
	var p := _profile()
	var view := StashView.new(p)
	var stash := p.stash

	# ── capacity is DELEGATED, and the N is the one measured this session ───
	_check(view.capacity() == stash.grid_width * stash.grid_height,
		"capacity() is the container's own product, not a constant (%d)" % view.capacity())
	_check(view.capacity() == 200,
		"the real stash is 10x20 = 200 cells, matching every save on disk (not a guessed N)")
	_check(view.free_cells() == stash.get_free_space(),
		"free_cells() is delegated to the owner's get_free_space(), not recomputed")
	_check(view.used_cells() + view.free_cells() == view.capacity(),
		"used + free == capacity, so the screen cannot show an impossible pair")
	_check(is_equal_approx(view.weight_limit(), stash.max_weight),
		"the mass ceiling is the container's, not a duplicated literal")
	_check(is_zero_approx(view.stored_weight()) and view.free_cells() == 200,
		"a fresh profile starts empty, so the fixture below is measuring real deposits")

	# ── stored rows carry registry identity, never a display string ─────────
	_put(p, AMMO, 3)
	_put(p, BRAZIL)
	_put(p, BUCKSHOT)
	var rows := view.rows()
	_check(rows.size() == 3, "one row per stored item (got %d)" % rows.size())
	_check(rows[0]["id"] == "M4_Carbine",
		"identity comes from ItemNames via the resource path (got '%s')" % rows[0]["id"])
	# Located BY ID, not by index. rows[0] is whichever item the grid accepted
	# first, so asserting stack==3 on position 0 was asserting an accident of
	# deposit order rather than about stacking at all.
	var m4 := {}
	for r in rows:
		if String(r["id"]) == "M4_Carbine":
			m4 = r
	# AND THE VALUE IS 1, NOT 3, AND THAT IS CORRECT. `stack_count` clamps to
	# `max_stack`, `max_stack` defaults to 1, and NO .tres in the project sets it
	# -- so nothing shipped is stackable and a stack of 3 was never reachable.
	# My original assertion wanted 3 and was wrong about the content.
	_check(not m4.is_empty() and int(m4["stack"]) == 1,
		"a non-stackable item reports a stack of 1 (got %s), matching max_stack rather than the request" % str(m4.get("stack", "<no row>")))
	var unstackable := 0
	for d in ["res://resources/weapons", "res://resources/ammo", "res://resources/medical", "res://resources/armor"]:
		unstackable += _count_with_max_stack(d)
	_check(unstackable == 0,
		"no shipped item declares max_stack, so every stack is 1 (%d declare one) -- recorded because a stack-aware screen is a no-op today" % unstackable)
	_check(rows[0]["position"] is Vector2i and rows[0]["dimensions"] is Vector2i,
		"a stored row carries its grid footprint, so the screen can lay it out")

	# THE THREE TRANSLATION BRANCHES. A fixture that only hits one of them is
	# vacuous -- that exact defect made the free-items marking arm prove nothing.
	var translated := 0
	var untranslated := 0
	var unregistered := 0
	for r in rows:
		if String(r["id"]) == "":
			unregistered += 1
		elif r["translated"]:
			translated += 1
		else:
			untranslated += 1
	_check(unregistered == 1 and untranslated == 1 and translated == 1,
		"all THREE identity branches are exercised: %d translated, %d registered-but-untranslated, %d unregistered"
			% [translated, untranslated, unregistered])
	_check(ItemNames.id_for_path(BUCKSHOT.resource_path) == "",
		"the buckshot fixture is confirmed UNREGISTERED, so its branch is real")
	_check(view.reason_key_for(BUCKSHOT.resource_path) == StashView.REASON_UNREGISTERED_KEY,
		"an unregistered path is MARKED with a key, never rendered as English")

	# ── a death pocket is the POLICY's answer, not a rule restated here ──────
	_check(view.safe_pocket_rows().is_empty() and view.is_kept_on_death(AMMO.resource_path) == false,
		"the shipped CONSUME policy keeps nothing by default, and the view agrees")
	# A pocket-populated, recoverable policy: this is the case where BOTH of the
	# policy's own entry points must agree, and the disagreement is the finding.
	var pocket := DeathPolicy.new()
	pocket.recoverable = true
	pocket.safe_pocket = [AMMO.resource_path]
	var p2 := _profile()
	p2.loadout = {"primary": [{"path": AMMO.resource_path}]}
	var keep_view := StashView.new(p2, pocket)
	_check(keep_view.is_kept_on_death(AMMO.resource_path) == true,
		"keeps() says a pocket item is spared (got %s)" % keep_view.is_kept_on_death(AMMO.resource_path))
	_check(keep_view.safe_pocket_rows().size() == 1,
		"and partition() puts the same item in the pocket (got %d rows)" % keep_view.safe_pocket_rows().size())
	_check(keep_view.safe_pocket_rows()[0]["id"] == "M4_Carbine",
		"the pocket row carries registry identity too (got '%s')" % String(keep_view.safe_pocket_rows()[0]["id"]))

	# A GENUINE DIVERGENCE BETWEEN TWO APIs IN THE SAME CLASS, pinned rather than
	# worked around. Under CONSUME_KEEP_ALL, partition() keeps every carried
	# entry while keeps() does not:
	#   - keeps()      death_policy.gd:68-73 -- consults `recoverable` and
	#                  `safe_pocket` and NEVER reads `loss`.
	#   - partition()  death_policy.gd:86 -- `if loss == Loss.CONSUME_KEEP_ALL or
	#                  _kept_by_policy(data)`, i.e. the loss mode is tested FIRST.
	# So for any carried item not literally in the pocket the two disagree.
	# is_kept_on_death() delegates to keeps(), so this view reports "not spared"
	# for an item the loss sweep would hand back.
	#
	# NOT PATCHED HERE, DELIBERATELY, AND NOT BECAUSE IT IS UNCLEAR. The
	# coordinator determined the direction on 2026-09-27: CONSUME_KEEP_ALL
	# declares that every carried item is kept, partition() implements exactly
	# that, and keeps() can never produce that answer -- so keeps() is what must
	# change, and the symmetric "fix" of making partition() drop items would be
	# wrong. The FIX IS ROUTED TO META, because src/meta/ is meta's file and two
	# lanes touching death_policy.gd in one night coupled their staging before.
	# The view is not compensating: no loss check here, no reimplementation of
	# partition's rules in the view, because a view that second-guesses its
	# dependency is a second place for the policy to rot.
	#
	# *** WHEN THIS CHECK FAILS, THAT IS THE FIX LANDING, NOT A REGRESSION. ***
	# Once keeps() honours the loss switch, `keeps` becomes true here and this
	# assertion fails. That failure is the evidence the fix landed, and it must
	# be INVERTED in the same commit -- assert that the two AGREE, rather than
	# softened to tolerate both outcomes. Softening it would throw away the only
	# thing this finding produced: a test that can tell the bug from the fix.
	var keep_all := DeathPolicy.new()
	keep_all.loss = DeathPolicy.Loss.CONSUME_KEEP_ALL
	keep_all.recoverable = true
	var p_keep := _profile()
	p_keep.loadout = {"primary": [{"path": BRAZIL.resource_path}]}
	var keep_all_view := StashView.new(p_keep, keep_all)
	var partition_keeps: bool = keep_all.partition(p_keep.loadout)["lost"].is_empty()
	var keeps_now: bool = keep_all_view.is_kept_on_death(BRAZIL.resource_path)
	_check(partition_keeps == true and keeps_now == false,
		"KNOWN DIVERGENCE, pinned: under KEEP_ALL partition() returns the item but keeps() does not (partition=%s keeps=%s). IF THIS FAILS, keeps() now honours the loss switch and the fix landed -- INVERT this assertion to assert agreement, in the same commit. Do not soften it." % [partition_keeps, keeps_now])

	# ── recoverable items are INSURANCE's, and a claim is not ownership ─────
	var p3 := _profile()
	var rec := StashView.new(p3)
	_check(rec.recoverable_rows().is_empty() and rec.has_any_content() == false,
		"an empty profile shows no content at all, so a blank home screen is a valid state")
	_check(rec.owns_nothing() == true, "a fresh profile owns nothing")
	p3.insurance.register_loss([{"path": AMMO.resource_path}], p3, false, [], 1)
	var rec2 := StashView.new(p3)
	_check(rec2.recoverable_rows().size() == 1, "a registered loss produces one recoverable row")
	_check(rec2.owns_nothing() == true,
		"a PENDING CLAIM IS NOT OWNERSHIP: the player still owns nothing while an item is on its way")
	_check(rec2.recoverable_rows()[0]["population"] == StashView.Population.RECOVERABLE,
		"the row is labelled recoverable, so it cannot be confused with a stored one")
	_check(rec2.has_any_content() == true, "content exists even while the player owns nothing")

	# ── population separation: the three lists never bleed into each other ──
	_check(rec2.rows().is_empty() and rec2.safe_pocket_rows().is_empty(),
		"registering a loss puts nothing in the stash and nothing in the pocket")
	_check(view.all_rows().size() == 3,
		"all_rows() is the union of the populations, counted once each (got %d)" % view.all_rows().size())

	# ── a ROLE is not an ITEM: its name never comes from ItemNames ─────────
	# AND the mapping that would connect a faction to a role DOES NOT EXIST.
	# FactionNames.KEYS is contractor/drifter/raider; the only role resource is
	# field_scout. So no faction id can ever resolve to a role, and the view is
	# not allowed to pretend otherwise.
	_check(view.role_display_name_key("field_scout") == "Field scout",
		"a role's display name comes from its OWN resource (got '%s')" % view.role_display_name_key("field_scout"))
	_check(view.role_display_name_key("contractor") == "",
		"a FACTION id resolves to no role, because no faction->role mapping exists")
	for fid in FactionNames.KEYS.keys():
		_check(FactionNames.key_for(String(fid)) != "" and String(fid) != "field_scout",
			"faction '%s' is registered and is NOT a role id, so the namespaces are disjoint" % String(fid))
	_check(view.preserved_role_kit_rows("contractor").is_empty(),
		"a fresh profile's preserved kit is empty rather than invented")
	var pk := _profile()
	pk.roles["drifter"] = {"kit": {"primary": [{"path": AMMO.resource_path}]}, "karma": 0,
		"raids": 0, "survived": 0, "kia": 0, "starter_granted": true}
	var pk_rows := StashView.new(pk).preserved_role_kit_rows("drifter")
	_check(pk_rows.size() == 1, "a populated role kit yields exactly one row (got %d)" % pk_rows.size())
	_check(pk_rows[0]["id"] == "M4_Carbine",
		"preserved-kit identity also resolves through the registry (got '%s')" % String(pk_rows[0]["id"]))
	_check(pk_rows[0]["slot"] == "primary", "the row names the slot it came from")

	# ── no player-facing literals leaked into the view ─────────────────────
	# Stripping COMMENTS FIRST, because the first version of this check matched
	# the word "Comprou" inside the comment that documents that very leak. A check
	# that fails on its own documentation is not a check.
	var src := FileAccess.get_file_as_string("res://src/meta/stash_view.gd")
	var code_lines: Array[String] = []
	for line in src.split("\n"):
		if not String(line).strip_edges().begins_with("#"):
			code_lines.append(line)
	var code := "\n".join(code_lines)
	_check(not code.contains("Comprou") and not code.contains("Bolsa") and not code.contains("Carteira"),
		"no Portuguese UI literal appears in the view's CODE (comments excluded)")
	_check(src.contains("STASH_POPULATION_STORED") and src.count("STASH_") >= 3,
		"population and reason text are catalogue KEYS")

	_finish()


func _count_with_max_stack(dir_path: String) -> int:
	var d := DirAccess.open(dir_path)
	if d == null:
		return 0
	var n := 0
	d.list_dir_begin()
	var e := d.get_next()
	while e != "":
		if not d.current_is_dir() and e.ends_with(".tres"):
			if FileAccess.get_file_as_string(dir_path + "/" + e).contains("max_stack"):
				n += 1
		e = d.get_next()
	d.list_dir_end()
	return n


func _check(ok: bool, message: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % message)
	else:
		_fail += 1
		_fail_lines.append(message)
		print("ERROR: FAIL: %s" % message)
