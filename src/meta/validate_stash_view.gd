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
const BRAZIL := preload("res://resources/weapons/Brazil_556.tres")            ## registered (translated or not -- no longer load-bearing)
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
	#
	# REWRITTEN TO BE STRUCTURAL. This used to count the three branches across the
	# three fixtures and require one of each, which meant the "registered but
	# untranslated" subject was Brazil_556 staying untranslated. When meta's pt-BR
	# sweep translated it to "Brasil 556", the branch lost its subject and the arm
	# went red -- on GOOD work, from a different lane. That is a check whose
	# fixture is TRANSLATION DEBT: it gets emptied out by finishing the job, and
	# the two available responses are both wrong (hold an item hostage, or soften
	# the check).
	#
	# So the untranslated branch is now tested through ItemNames.is_key_translated
	# with a key no msgid will ever exist for, which is untranslated permanently.
	# Completing the catalogue cannot break it. The "unregistered" branch keeps its
	# real fixture, because "deliberately unregistered" is a property of the
	# REGISTRY rather than of the catalogue, which is the right way to hold a
	# negative case and is why nobody had to leave a translation unwritten for it.
	var translated := 0
	var unregistered := 0
	for r in rows:
		if String(r["id"]) == "":
			unregistered += 1
		elif r["translated"]:
			translated += 1
	_check(unregistered == 1,
		"the UNREGISTERED branch is exercised by a real fixture (%d found)" % unregistered)
	_check(translated >= 1,
		"and at least one real fixture renders a translated name (%d found)" % translated)
	# The two halves, each on a subject that is genuinely REGISTERED.
	_check(ItemNames.is_key_translated("M4_Carbine") == true,
		"a REGISTERED+TRANSLATED key is reported translated")
	var subject_path := _untranslated_subject()
	_check(subject_path != "",
		"a REGISTERED-but-UNTRANSLATED item exists to serve as the third-branch subject (found=%s). IF THIS FAILS THE CATALOGUE IS COMPLETE: redesign this check deliberately. Do NOT soften it and do NOT un-translate a real item to make it pass." % subject_path)
	_check(subject_path != "" and ItemNames.is_key_translated(ItemNames.id_for_path(subject_path)) == false,
		"a REGISTERED key with no msgid is reported untranslated, on a subject discovered at runtime")
	_check(ItemNames.is_key_translated("__probe_key_with_no_msgid__") == false,
		"an id absent from the registry is also untranslated -- a DIFFERENT branch, which is why a synthetic key cannot stand in for a registered one")
	_check(subject_path != "" and ItemNames.is_translated_path(subject_path) == false,
		"and a REGISTERED path with no msgid resolves untranslated through the path-level helper")
	_check(ItemNames.is_translated_path(BUCKSHOT.resource_path) == false,
		"while an unregistered path resolves untranslated too, via the other branch")
	_check(ItemNames.is_translated_path(AMMO.resource_path) == true,
		"and a registered, translated PATH resolves translated -- so the path helper is not simply always-false")
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

	# keeps() AND partition() MUST AGREE. This arm was written the other way round
	# and was deliberately INVERTED rather than softened when the fix landed.
	#
	# THE FINDING, for the next reader. Under CONSUME_KEEP_ALL the two disagreed:
	#   - keeps()      consulted only `recoverable` and `safe_pocket` and never
	#                  read `loss` at all;
	#   - partition()  tested `loss == Loss.CONSUME_KEEP_ALL or _kept_by_policy(...)`
	#                  first, so it kept everything.
	# is_kept_on_death() delegates to keeps(), so the home screen reported "not
	# spared" for items the loss sweep actually returned -- and _resolve_loss
	# builds report.lost and the insurance claim from that same split, so the
	# number a player is SHOWN would have disagreed with the number they are PAID.
	# Reported by me, pinned by this arm, fixed by meta in 42f7cd6 (agent/
	# meta-death-policy), which refactored both entry points onto a single
	# _spared() so the two cannot diverge by omission again.
	#
	# WHY IT IS A MATRIX AND NOT THE ONE ROW THAT FOUND THE BUG. The original arm
	# covered KEEP_ALL + recoverable=true only. Fixing the switch there and
	# nothing else would pass. A regression in any of the five rows below -- or a
	# future switch added to one entry point and not the other -- fails here, which
	# is the whole value of pinning a divergence rather than documenting it.
	#
	# IT MUST STAY ARMED. If this ever fails, one of the two entry points has
	# drifted again; do NOT relax a row to make it pass.
	#
	# THE `expected` TERM IS LOAD-BEARING, AND AN ARM PROVED IT. Removing the
	# loss switch from _spared() makes BOTH entry points return false -- so they
	# AGREE, and a check asserting only `kept == asked` would have PASSED while
	# the policy quietly stopped honouring KEEP_ALL. Agreement is necessary and
	# not sufficient; the third term is what catches both entry points drifting
	# together. Measured, not reasoned: with the switch deleted this row reported
	# partition=false keeps=false, and only `kept == expected` turned it red.
	var _agreements: Array[String] = []
	var _rows := [
		# [loss, recoverable, in_pocket, expected_spared, label]
		[DeathPolicy.Loss.CONSUME_KEEP_ALL, true, false, true, "KEEP_ALL keeps everything"],
		[DeathPolicy.Loss.CONSUME_KEEP_ALL, false, false, true,
			"KEEP_ALL + recoverable=false still keeps (the switch wins; the old keeps() said false here)"],
		[DeathPolicy.Loss.CONSUME, true, true, true, "CONSUME spares a pocket item"],
		[DeathPolicy.Loss.CONSUME, true, false, false, "CONSUME does not spare an unflagged item"],
		[DeathPolicy.Loss.CONSUME, false, true, false,
			"CONSUME + recoverable=false spares nothing, even from a populated pocket"],
	]
	for row in _rows:
		var loss_mode: int = row[0]
		var rec: bool = row[1]
		var in_pocket: bool = row[2]
		var expected: bool = row[3]
		var label: String = row[4]
		var pol := DeathPolicy.new()
		pol.loss = loss_mode
		pol.recoverable = rec
		if in_pocket:
			pol.safe_pocket = [BRAZIL.resource_path]
		var prof := _profile()
		prof.loadout = {"primary": [{"path": BRAZIL.resource_path}]}
		var kept: bool = pol.partition(prof.loadout)["lost"].is_empty()
		var asked: bool = StashView.new(prof, pol).is_kept_on_death(BRAZIL.resource_path)
		_agreements.append("%s: partition=%s keeps=%s want=%s" % [label, kept, asked, expected])
		_check(kept == asked and kept == expected,
			"the two entry points AGREE and both give the right answer -- %s (partition=%s keeps=%s)"
				% [label, kept, asked])
	_check(_agreements.size() == 5, "all five policy configurations are compared, not just the one that found the bug")


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


## A real .tres that is REGISTERED but has no msgstr. Found at RUNTIME, never
## hardcoded: a hardcoded subject is a hostage held against the catalogue, and
## good work in another lane then empties the check out from under us. KEYS is a
## read-only const, so a synthetic key CANNOT be registered and a fake subject is
## not available -- the real one has to come from the catalogue.
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
