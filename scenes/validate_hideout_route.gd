# res://scenes/validate_hideout_route.gd
extends SceneTree
## cf9448 acceptance, in the shape that actually catches this class of failure.
##
## THE CLASS: a thing that is structurally complete and behaviourally unreachable,
## with its own green harness. Found three times in one day -- the gunsmith's
## request signals, the profiler gate with no floor, the starter grant with no
## caller. In every case the checks were about the part that exists.
##
## So this harness deliberately asserts almost NOTHING about the hideout's
## internals. It does not care that the rows render or that the collect button
## works, because a harness that instantiates the screen directly passes whether
## or not any player can reach it -- which is precisely how a green suite can sit
## on an orphan. It checks the edges IN and the edge OUT, and it instantiates the
## real scene so "the scene loads" is not a string match.
##
## Every claim here names the file it is about, so a failure points at the edge
## rather than at a boolean.

const HIDEOUT_SCENE := "res://scenes/hideout.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const MENU_SCRIPT := "res://scenes/main_menu.gd"

## This harness. Excluded from its own navigator search, or the file that quotes
## the path would satisfy the "something navigates here" check on its own and the
## check could never fail.
const SELF := "res://scenes/validate_hideout_route.gd"

var checks := 0
var failures := 0


func _check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("  PASS  %s" % message)
	else:
		failures += 1
		print("  FAIL  %s" % message)


func _initialize() -> void:
	# ── the screen exists and genuinely loads ─────────────────────────────────
	_check(FileAccess.file_exists(HIDEOUT_SCENE),
		"the hideout scene file exists at scenes/hideout.tscn")
	var packed: PackedScene = load(HIDEOUT_SCENE) as PackedScene
	_check(packed != null and packed.can_instantiate(),
		"and it is a loadable, instantiable scene (not a stub path)")
	var inst: Node = packed.instantiate() if packed != null else null
	_check(inst != null, "and it instantiates without a script or resource error")
	if inst != null:
		inst.free()

	# ── THE ROUTE IN, which is the whole point ───────────────────────────────
	# A scene with no edge pointing at it is an orphan, however complete it is.
	var navigators := _files_navigating_to(HIDEOUT_SCENE)
	_check(not navigators.is_empty(),
		"something in the game NAVIGATES to the hideout (found: %s) -- an orphan scene with a green harness is the failure this card exists to prevent"
			% (", ".join(navigators) if not navigators.is_empty() else "NOTHING"))
	_check(navigators.has("res://scenes/main_menu.gd"),
		"and the main menu is one of them, so the hideout is reachable from the game's front door (main_menu.gd)")

	# A scene constant is not a route. The constant has to be USED.
	var menu_src := FileAccess.get_file_as_string(MENU_SCENE)
	var menu_script := FileAccess.get_file_as_string(MENU_SCRIPT)
	_check(menu_src.contains("BtnHideout") or menu_script.contains("BtnHideout"),
		"the menu has a control that leads to it (BtnHideout in main_menu.tscn/gd), not just a string constant")
	_check(menu_script.contains("change_scene_to_file") and menu_script.contains("HIDEOUT_SCENE"),
		"and pressing it actually changes scene to the hideout (change_scene_to_file(HIDEOUT_SCENE))")
	# ...and the binding must exist, or the button is decoration.
	_check(menu_script.contains("_on_hideout") and menu_script.contains("BtnHideout as Button"),
		"and the button is CONNECTED to that handler, not merely present in the scene tree")

	# ── THE ROUTE OUT. A screen you cannot leave is a different orphan. ───────
	# Declared here, where the route-out checks begin: the first version of this
	# edit deleted a declaration further down that this block already used, which
	# is how a "one variable" fix turned into an unbalanced-parens parse error.
	var ctrl_src := FileAccess.get_file_as_string("res://scenes/hideout_controller.gd")
	_check(ctrl_src.contains("change_scene_to_file") and ctrl_src.contains("MAIN_MENU_SCENE"),
		"the hideout has a way back out to the main menu, so entering it is not a one-way trap")

	# ── THE SURFACE IS NOT A HARODDLED ROSTER ────────────────────────────────
	# The genre rule: a framework cannot hardcode what the game decides. Rows
	# must come from the claim data, so adding content is a .tres and not an edit.
	var ui := FileAccess.get_file_as_string("res://scenes/hideout_ui.gd")
	_check(ui.contains("FreeItemsView") or ui.contains("free_items_view"),
		"the recovered-goods list renders the existing FreeItemsView seam rather than reimplementing what is pending")
	_check(not ui.contains("for id in") and not ui.contains("match id"),
		"and it hardcodes no item roster, so content stays data")

	# ── THE ROUTE OUT, which is the half that was never tested and was broken ─
	# The hideout had a BtnBack that resolved as %BtnBack, was rendered, took the
	# click, and was connected to NOTHING; and return_to_menu() existed from the
	# first commit with ZERO callers. The player could enter the hideout and could
	# not leave it. Everything above passed, because every one of those checks was
	# about the route IN -- which was true -- and a route OUT is a different claim.
	var scene := FileAccess.get_file_as_string(HIDEOUT_SCENE)

	_check(scene.contains("BtnBack"), "route out: the scene HAS a Back button")
	_check(ui.contains("_back.pressed.connect"),
		"route out: and the surface actually CONNECTS it -- a resolved @onready that is never connected is the most expensive kind of dead UI, because it renders, it takes the click, and nothing happens anywhere")
	_check(ui.contains("signal back_requested"),
		"route out: emitting an intent rather than navigating itself, because the controller owns navigation")
	_check(ctrl_src.contains("back_requested.connect(return_to_menu)"),
		"route out: and the controller subscribes return_to_menu, which previously had no callers at all")
	# Existence is not wiring. This is the specific false negative: a source search
	# for "return_to_menu" FOUND the function, so the route out looked present.
	_check(not (ctrl_src.contains("func return_to_menu") and not ctrl_src.contains("back_requested.connect(return_to_menu)")),
		"route out: a defined-but-uncalled return_to_menu fails here, because its existence is not its wiring")
	_check(ctrl_src.contains("ActionLog.reached(\"Hideout/BtnBack\""),
		"route out: and pressing Back records a REACHED before it navigates, so a route that starts and does not land is visible")
	_check(ctrl_src.contains("ActionLog.no_op(reach, \"no_scene_tree\""),
		"route out: with a NO-OP and a reason when there is no tree, rather than the silent return it used to be")

	# ── THE STASH HALF ──────────────────────────────────────────────────────
	# The hideout showed claims only, so a player asking "what have I actually
	# got" got the recovered-goods list and nothing else.
	_check(ui.contains("StashView.new("),
		"stash: the hideout also shows what is STORED, delegated to StashView rather than reimplementing an answer that already exists")
	_check(ui.contains("_stash.used_cells(), _stash.capacity()"),
		"stash: including its capacity, because a stash with no limit is one the player cannot tell is full")

	print("hideout route: checks=%d passed=%d" % [checks, checks - failures])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


## Which project files actually NAVIGATE to this scene.
##
## Scans BOTH repositories, because a zero from a search that was never shown to
## match is not an absence -- that mistake produced the false "four missing weapon
## textures" claim earlier in this session.
##
## A file that merely CONTAINS the path is NOT a route, and counting one was the
## first version of this check's bug: it found the harness itself (which quotes the
## path) and the controller (which only DECLARES the constant), so it passed no
## matter what. Two things are therefore required -- the file must not be this
## harness, and the path must appear inside an actual navigation call rather than
## a constant assignment. A declared-but-unused constant is precisely the "no
## caller" failure that has been found three times tonight.
func _files_navigating_to(scene_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for root in ["res://scenes", "res://src", "res://addons"]:
		_scan_for_navigation(root, scene_path, out)
	return out


func _scan_for_navigation(dir_path: String, scene_path: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var p := dir_path.path_join(name)
		if d.current_is_dir():
			if not name.begins_with(".") and name != "imported":
				_scan_for_navigation(p, scene_path, out)
		elif name.ends_with(".gd") or name.ends_with(".tscn"):
			if p != scene_path and p != SELF and _navigates_to(FileAccess.get_file_as_string(p), scene_path):
				out.append(p)
		name = d.get_next()
	d.list_dir_end()


## Does this source ACTUALLY change scene to the target?
## Matches a navigation call whose argument is the target, either directly
## (`change_scene_to_file("res://...")`) or through a constant that is then passed
## to it. A `const X := "<path>"` with no call does not count.
func _navigates_to(src: String, scene_path: String) -> bool:
	if src.contains("change_scene_to_file(%s)" % scene_path) \
			or src.contains("change_scene_to_file(\"%s\")" % scene_path):
		return true
	# Indirect: the path is held in a constant that is used as a navigation target.
	if not src.contains("const") or not src.contains(scene_path):
		return false
	for line in src.split("\n"):
		var const_name := _const_name_declaring(line, scene_path)
		if const_name != "" and src.contains("change_scene_to_file(%s)" % const_name):
			return true
	return false


## The name of a constant whose declaration holds this path, or "".
## Handles both GDScript spellings, and the `:=` form is the one that matters
## here: `const NAME := "res://..."` splits on spaces as
## ["const", "NAME", ":=", "\"res://...\""], so a naive token[2] yields ":=" and
## the lookup silently matches nothing. That is the same shape as the vacuous
## check this replaced -- a comparison that cannot fail, mistaken for a pass.
func _const_name_declaring(line: String, scene_path: String) -> String:
	var trimmed := String(line).strip_edges()
	if not trimmed.begins_with("const ") or not trimmed.contains(scene_path):
		return ""
	# Cut at the first ':' or '=' that follows the name, then take the last token.
	var cut := trimmed.substr(6)
	var stop := cut.length()
	for i in cut.length():
		var ch := cut[i]
		if ch == ":" or ch == "=":
			stop = i
			break
	var name_part := cut.substr(0, stop).strip_edges()
	if name_part.is_empty():
		return ""
	return name_part.split(" ")[name_part.split(" ").size() - 1]
