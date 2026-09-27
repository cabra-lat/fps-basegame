# res://scenes/validate_hub_loadout_wiring.gd
extends SceneTree
## Does the hub actually SHOW what LoadoutView knows? (card 0ed569)
##
## THE GAP THIS EXISTS TO PIN. LoadoutView computes five specific deploy-refusal
## reasons. The hub modelled loadout validity as a coarse EMPTY/VALID/INVALID
## tri-state driven by `option.get("valid", true)`, so before this wiring a player
## whose loadout was refused could only be told "invalid" -- and LoadoutView's
## five reasons, forty-one green checks, and the whole point of the loadout screen
## reached nobody. A view that is correct and unwired is not a feature.
##
## WHAT IT DOES NOT CLAIM. It proves the reasons reach the status label as
## TRANSLATED KEYS and that a stale reason cannot outlive its loadout. It does not
## prove the screen looks right in pt-BR, because the five msgstrs are still empty
## in the catalogue -- a fact this harness asserts rather than works around, since
## a test that quietly skipped the untranslated case would be the vacuous version.

const HUB_SCENE := "res://scenes/operations_hub.tscn"
const HUB := "res://scenes/operations_hub.gd"

var _pass := 0
var _fail := 0
var _fail_lines: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _quit(code: int) -> void:
	quit(code)


func _hub() -> Node:
	var h = load(HUB_SCENE).instantiate()
	get_root().add_child(h)
	get_root().size = Vector2i(1280, 720)
	return h


## An option the hub will treat as invalid, plus a valid one, so the two branches
## are distinguishable. A single-fixture version of this would pass whether or not
## the INVALID branch ever rendered.
func _options() -> Array:
	return [
		{"id": "heavy", "valid": false, "summary": "Heavy"},
		{"id": "ok", "valid": true, "summary": "Fine"},
	]


func _run() -> void:
	await process_frame
	var h = _hub()
	await process_frame
	_check(h != null and h.get("status_label") != null, "the hub builds a status label to render into")

	# ── the INVALID branch now names the reason ────────────────────────────
	h.set_loadouts(_options())
	h.set_selected_loadout("heavy")
	await process_frame
	var status: Label = h.get("status_label")
	var invalid_text: String = status.text if status != null else ""
	_check(invalid_text == h.get("invalid_loadout_text"),
		"BASELINE: with no reasons supplied the hub still shows the generic message, so the fallback is real and not a stub")

	h.set_loadout_reasons(["LOADOUT_REASON_OVER_MASS"])
	await process_frame
	_check(status.text != h.get("invalid_loadout_text"),
		"a supplied reason REPLACES the generic message, so the wiring visibly changes what the player reads")
	_check(not status.text.is_empty(), "the reason line is never blank when reasons exist")

	# ── keys, not sentences: the label renders through the catalogue ─────────
	var over: String = TranslationServer.translate("LOADOUT_REASON_OVER_MASS")
	_check(over == "LOADOUT_REASON_OVER_MASS",
		"the reason is currently UNTRANSLATED, and the label shows the key itself rather than a composed sentence")
	_check(status.text.contains(over), "the label shows exactly what the catalogue resolves the key to")

	# ── the hygiene the API promises ───────────────────────────────────────
	h.set_loadout_reasons(["", "   ", 42, null, "LOADOUT_REASON_GRID_OVERLAP"])
	await process_frame
	_check(status.text.count("\n") == 0 and status.text.contains("LOADOUT_REASON_GRID_OVERLAP"),
		"blank, whitespace and non-string entries are dropped, so only real keys render")

	# ── A STALE REASON MUST NOT SURVIVE A LOADOUT CHANGE. This is the failure
	# that would make the feature worse than nothing: being told your new loadout
	# is too heavy when it is not.
	h.set_selected_loadout("ok")
	await process_frame
	_check(not status.text.contains("LOADOUT_REASON"),
		"switching to a VALID loadout clears the reason, so a valid loadout is never labelled with an old failure")

	h.set_selected_loadout("heavy")
	h.set_loadout_reasons(["LOADOUT_REASON_CONTAINER_CYCLE"])
	await process_frame
	h.set_loadouts(_options())
	await process_frame
	_check(not status.text.contains("LOADOUT_REASON_CONTAINER_CYCLE"),
		"re-supplying the option list drops the previous loadout's reasons")

	# ── reasons must not fake validity ─────────────────────────────────────
	h.set_loadouts(_options())
	h.set_selected_loadout("ok")
	h.set_loadout_reasons(["LOADOUT_REASON_OVER_MASS"])
	await process_frame
	_check(h.can_deploy() == true,
		"reasons do not BLOCK a valid loadout: can_deploy() still reads the option's own validity, so a reason left over cannot disable deploy")

	# ── the reason set is exactly the five the view produces ───────────────
	var view_src := FileAccess.get_file_as_string("res://src/meta/loadout_view.gd")
	var five := 0
	for k in ["OVER_MASS", "CONTAINER_CYCLE", "SLOT_NOT_COMPATIBLE", "GRID_OVERLAP", "OUT_OF_BOUNDS"]:
		if view_src.contains("LOADOUT_REASON_%s" % k):
			five += 1
	_check(five == 5, "all five reasons the view produces are named (found %d)" % five)

	# ── the hub owns no copy of the reason text ────────────────────────────
	var hub_src := FileAccess.get_file_as_string(HUB)
	_check(hub_src.contains("set_loadout_reasons") and hub_src.contains("_reasons_text"),
		"the hub renders through the reason helper rather than inline")
	var leaks := 0
	for k in ["OVER_MASS", "CONTAINER_CYCLE", "SLOT_NOT_COMPATIBLE", "GRID_OVERLAP", "OUT_OF_BOUNDS"]:
		if hub_src.contains("LOADOUT_REASON_%s" % k):
			leaks += 1
	_check(leaks == 0,
		"the hub does NOT hardcode any of the five reason keys or their text (%d found): it is handed keys and renders them" % leaks)

	h.queue_free()
	_free_items_marking()
	_finish()


func _finish() -> void:
	print("")
	print("=== validate_hub_loadout_wiring summary ===")
	print("  checks passed  %d" % _pass)
	print("  FAILURES       %d" % _fail)
	var code := 0
	if _fail > 0:
		for l in _fail_lines:
			print("  FAIL  " + l)
		print("RESULT: FAIL")
		code = 1
	else:
		print("RESULT: PASS")
	call_deferred("_quit", code)


## 87ab63: the free-items MARKING, and that it is data rather than a branch.
##
## The option is offered only when the player genuinely owns nothing, and the set
## comes from the StarterLoadout resource. The last check is the one that matters
## for the card's design constraint: a hardcoded fallback in the controller is
## how the hub got a hardcoded Portuguese catalogue, and a string search for a
## weapon NAME in the controller is the check that would catch the next one. It is
## deliberately not satisfied by the resource merely existing -- the name must
## appear in the CONTROLLER for the check to fail, and it does not.
func _free_items_marking() -> void:
	_check(FileAccess.file_exists("res://scenes/operations_hub_controller.gd"), "the hub controller exists")
	var src: String = FileAccess.get_file_as_string("res://scenes/operations_hub_controller.gd")
	_check(src.contains("_free_starter_option"), "and it has the free-starter projection")
	_check(src.contains("starter_loadout.tres"),
		"which reads the starter set from the RESOURCE, not from a literal list")
	_check(src.contains("FreeItemsView"),
		"and asks FreeItemsView whether the player owns nothing, so the hub and the hideout cannot disagree about that")
	# THE DATA CHECK: no shipped weapon or item NAME appears in the controller at
	# all. Strip comments first, or the prose documenting the constraint would
	# satisfy the search for the thing the constraint forbids.
	#
	# WHOLE-WORD, and that detail is the one that matters. The first version
	# searched for the id in quotes or followed by ".tres", and a red arm that
	# hardcoded "Free M4_Carbine starter kit" -- the name embedded INSIDE a larger
	# string, which is exactly how a hardcoded label looks in practice -- passed
	# 19/19. A quoted search finds only the convenient shape of the mistake.
	var code := ""
	for line in src.split("\n"):
		if not String(line).strip_edges().begins_with("#"):
			code += line + "\n"
	var leaked := ""
	for id in ItemNames.KEYS:
		if _contains_word(code, String(id)):
			leaked += id + " "
	_check(leaked.is_empty(),
		"and hardcodes NO item name at all (a hardcoded fallback is how the hub got a hardcoded catalogue) [leaked: %s]" % leaked)
	# And the marking is a MARKING, not a grant: the controller must not call the
	# grant, because a screen that hands out gear on click is the faucet.
	_check(not code.contains("grant_starter_loadout"),
		"and it MARKS the option rather than granting it -- the controller must not call the faucet")

## Does `text` contain `word` as a WHOLE identifier token?
##
## Not a substring test and not a quoted test: a hardcoded item name is almost
## never a standalone string, it is a name inside a sentence like "Free M4_Carbine
## starter kit", and a quoted search misses precisely that. Boundaries are
## non-identifier characters, so `_M4` and `M4X` do not match while `M4_Carbine`
## inside prose does.
func _contains_word(text: String, word: String) -> bool:
	if word.is_empty():
		return false
	var at := text.find(word)
	while at >= 0:
		var before := "" if at == 0 else text[at - 1]
		var after := "" if at + word.length() >= text.length() else text[at + word.length()]
		var ok_before := before == "" or not (before == "_" or before.to_lower() != before.to_upper())
		var ok_after := after == "" or not (after == "_" or after.to_lower() != after.to_upper())
		if ok_before and ok_after:
			return true
		at = text.find(word, at + 1)
	return false


func _check(ok: bool, message: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % message)
	else:
		_fail += 1
		_fail_lines.append(message)
		print("ERROR: FAIL: %s" % message)
