# res://scenes/validate_ui_wiring.gd
extends SceneTree
## Is every UI request signal actually WIRED to something that implements it?
##
## WHY THIS EXISTS. The gunsmith was reported unreachable, and the diagnosis turned
## out to be the opposite in one direction and worse in another: the modify route
## was complete and wired, while THREE neighbouring context-menu signals --
## request_unload_magazine, request_extract_rounds and request_cycle_action -- were
## emitted by the inventory UI and connected to NOTHING anywhere in the tree. The
## menu offers the items, the emit fires, and no handler exists in the player
## controller, the arena manager or the gunsmith. A player clicking "remove
## magazine" gets silence, which is exactly what was reported.
##
## The existing 83-check gunsmith harness could not catch that, because it tests the
## gunsmith's internals and never asks whether anything can reach it. This one asks
## the wiring question, which is the one that was unasked.
##
## THE HONEST LIMIT OF A SOURCE-LEVEL CHECK, stated rather than hidden. Deciding
## "is this signal connected" by reading source is a text scan, and text scans are
## how this project's description debt produced four wrong numbers in one evening. It
## is used here because a headless run cannot build the full inventory tree without
## a scene, and because the alternative -- instantiating the UI -- would pass whether
## or not the shipped scenes wire it, which is the failure this harness exists to
## catch. So the scan is paired with a POSITIVE CONTROL that fails if the scan stops
## working at all, and every signal must be either wired or explicitly declared
## unimplemented. Nothing is allowed to be quietly unconnected.

const BASE_UI := "res://addons/cabra.lat_shooters/src/ui/inventory/base.gd"
## THE FILE THE CONNECTIONS ACTUALLY LIVE IN. My first version scanned only
## base.gd (which DECLARES and EMITS) plus the arena, and so reported
## request_modify_weapon and request_use_item as unconnected when both are connected
## right here. The positive control is what caught it -- without that check the
## first version would have "passed" by declaring two working signals dead and
## moving them into the unimplemented list, which would have been worse than no
## harness at all.
const INVENTORY_MAIN := "res://addons/cabra.lat_shooters/src/ui/inventory/main.gd"
const ARENA_CORE := "res://scenes/arena_manager_core.gd"
const ARENA := "res://scenes/arena_manager.gd"
const MAIN_MENU := "res://scenes/main_menu.gd"

## Signals that are emitted and intentionally have no handler YET. Each one is
## listed with the reason, because an entry without a reason is indistinguishable
## from an oversight and this project's whole argument is that the two must not look
## the same. An empty map is the goal, not the starting state.
const KNOWN_UNIMPLEMENTED := {
	"request_unload_magazine": "remove-magazine: no handler exists in the player controller or the arena manager; the context menu offers it anyway",
	"request_extract_rounds": "extract-rounds: no handler exists; the context menu offers it anyway",
	"request_cycle_action": "cycle-action: no handler exists; the context menu offers it anyway",
}

var checks := 0
var failures := 0


func _initialize() -> void:
	_run()
	print("ui wiring: checks=%d passed=%d" % [checks, checks - failures])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _run() -> void:
	var base_src := FileAccess.get_file_as_string(BASE_UI)
	var core_src := FileAccess.get_file_as_string(ARENA_CORE)
	var arena_src := FileAccess.get_file_as_string(ARENA)
	var menu_src := FileAccess.get_file_as_string(MAIN_MENU)
	_check(not base_src.is_empty() and not core_src.is_empty(),
		"the inventory UI and the arena core are readable, so this is not a vacuous scan of missing files")

	# ── every request signal is wired or declared unimplemented ───────────────
	var declared := _declared_signals(base_src)
	_check(declared.size() >= 6, "the inventory UI declares its request signals (found %d)" % declared.size())

	var unhandled: Array[String] = []
	for sig in declared:
		if not sig.begins_with("request_"):
			continue
		if _is_connected_anywhere(sig, [BASE_UI, INVENTORY_MAIN, ARENA_CORE, ARENA]):
			continue
		if KNOWN_UNIMPLEMENTED.has(sig):
			continue
		unhandled.append(sig)
	_check(unhandled.is_empty(),
		"NO request signal is emitted into the void: every one is either connected or declared unimplemented with a reason (unaccounted: %s)"
			% ", ".join(unhandled))

	# THE POSITIVE CONTROL. If the scan silently stopped matching -- a renamed
	# method, a different connect style -- every signal would look unconnected and
	# this check would either pass vacuously or fail for the wrong reason. So at
	# least one signal must be found CONNECTED, proving the scan can tell the two
	# states apart. Without this the previous check could not distinguish "wired"
	# from "scan is broken".
	var connected_somewhere: Array[String] = []
	for sig in declared:
		if sig.begins_with("request_") and _is_connected_anywhere(sig, [BASE_UI, INVENTORY_MAIN, ARENA_CORE, ARENA]):
			connected_somewhere.append(sig)
	_check(not connected_somewhere.is_empty(),
		"POSITIVE CONTROL: the scan can find a real connection (%s), so 'connected' is not an unreachable verdict"
			% ", ".join(connected_somewhere))

	# ── the modify route, asserted as a ROUTE and not as internals ───────────
	# Each hop is checked separately so a failure names WHICH hop is missing, rather
	# than the whole route being reported absent because one end is.
	_check(core_src.contains("GunsmithUI.new()"),
		"hop 1: the arena CONSTRUCTS the gunsmith in code (so the absent .tscn is not a defect)")
	_check(core_src.contains("weapon_modify_requested.connect"),
		"hop 2: the arena LISTENS for the player's modify request")
	_check(arena_src.contains("gunsmith.open_for_weapon("),
		"hop 3: the listener OPENS the gunsmith with the weapon that was clicked")
	_check(menu_src.contains("arena_blockout"),
		"hop 4: the main menu navigates to the arena scene that hosts all of the above")
	_check(_emits(base_src, "request_modify_weapon"),
		"hop 5: the inventory context menu actually EMITS the modify request")
	_check(not FileAccess.file_exists("res://scenes/gunsmith_ui.tscn"),
		"and the absent gunsmith_ui.tscn is confirmed absent, which is expected because the class is constructed rather than scene-instanced")

	# ── the known-unimplemented list must not become a dumping ground ─────────
	for sig in KNOWN_UNIMPLEMENTED:
		_check(String(KNOWN_UNIMPLEMENTED[sig]).strip_edges() != "",
			"the unimplemented entry for '%s' carries a reason, so it cannot be mistaken for an oversight" % sig)
		_check(_emits(base_src, sig),
			"and '%s' is genuinely emitted, so the entry describes a real dead end rather than a typo" % sig)


## Signals declared by the base UI, parsed from its `signal` lines. A tiny regex
## rather than a class scan, because the addon is a separate repository whose class
## cache this harness does not depend on.
func _declared_signals(src: String) -> Array[String]:
	var out: Array[String] = []
	for line in src.split("\n"):
		var stripped := String(line).strip_edges()
		if not stripped.begins_with("signal "):
			continue
		var name := stripped.substr(7).split("(")[0].strip_edges()
		if name != "":
			out.append(name)
	return out


func _is_connected_anywhere(sig: String, paths: Array) -> bool:
	for p in paths:
		if FileAccess.get_file_as_string(p).contains("%s.connect" % sig):
			return true
	return false


func _emits(src: String, sig: String) -> bool:
	return src.contains("%s.emit" % sig)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("  PASS  %s" % message)
	else:
		failures += 1
		print("ERROR: FAIL: %s" % message)
