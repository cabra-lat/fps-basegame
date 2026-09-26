extends SceneTree
## F5 movement-state debug shell (deliverable 1 of e5ba17) -- acceptance.
##
## The deliverable's whole point is that the BINDING KEY is visible, so the
## acceptance is not "the overlay draws". It is that the key printed is the key
## the InputMap actually holds, resolvable at runtime, and that a missing
## binding is VISIBLE rather than absent.
##
## Arms, in the order they are reported:
##   1. live resolution    -- real actions print their real bound keys
##   2. multi-binding      -- a two-key action prints both, not just the first
##   3. UNBOUND            -- an action with zero events prints UNBOUND, and
##                            the shell does NOT print an empty cell
##   4. no-such-action     -- an action absent from the map is named as such
##   5. no-subject         -- with no PlayerInput, the shell says so instead of
##                            drawing a header-only panel that looks healthy
##
## Arm 3 and arm 5 are the red arms. A panel that silently drops a row is the
## failure mode that makes a debug shell worse than no shell, so both are
## asserted rather than assumed.

const T := preload("res://addons/cabra.lat_shooters/src/player/debug/movement_state_overlay.gd")

var _fail := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	# InputMap only exists once the project settings are loaded, which a
	# SceneTree script gets, but the actions are lazily registered -- so this is
	# read AFTER the tree is up rather than at parse time.
	await process_frame

	print("=== ARM 1: live resolution from the real InputMap ===")
	# Resolve exactly the rows the shell ships, so a row whose action is
	# missing from the map shows up here rather than only on screen.
	for row in T.ROWS:
		var act: String = row["action"]
		var txt: String = T.binding_text(act)
		var label: String = act if act != "" else "(axis)"
		print("  %-16s %-5s %s" % [label, row["kind"], txt])
		if act == "":
			continue
		if txt == "UNBOUND" or txt == "NO SUCH ACTION" or txt == "UNMAPPED EVENT":
			_fail += 1
			print("      FAIL: a SHIPPED row has no live binding (%s). A row that can" % txt)
			print("      never resolve is a row that always looks 'off' to the reader.")

	print("")
	print("=== ARM 2: multi-binding is not truncated ===")
	# crouch has a primary and a secondary in this project's input map; if the
	# resolver returned only the first, every rebind would be invisible.
	var multi := _actions_with_multiple_events()
	if multi.is_empty():
		print("  (no multi-key action in this map -- arm is vacuous, NOT a pass)")
		_fail += 1
		print("      FAIL: the multi-binding arm could not produce a subject, so the")
		print("      shell's handling of a second key is untested and unknown.")
	else:
		for a in multi:
			var txt: String = T.binding_text(a)
			print("  %-16s %s" % [a, txt])
			if not txt.contains("/"):
				_fail += 1
				print("      FAIL: %s has %d events but the resolver printed one key." % [a, InputMap.action_get_events(a).size()])

	print("")
	print("=== ARM 3 (RED ARM): UNBOUND must be VISIBLE ===")
	InputMap.add_action("range_tmp_unbound_probe")
	var got: String = T.binding_text("range_tmp_unbound_probe")
	print("  action with zero events -> '%s'" % got)
	if got != "UNBOUND":
		_fail += 1
		print("      FAIL: an action with no events printed '%s'." % got)
		print("      A blank or invented key here is how a debug shell starts lying.")
	InputMap.erase_action("range_tmp_unbound_probe")

	print("")
	print("=== ARM 4 (RED ARM): a missing action must be NAMED ===")
	var got2: String = T.binding_text("range_tmp_never_defined")
	print("  action absent from the map -> '%s'" % got2)
	if got2 != "NO SUCH ACTION":
		_fail += 1
		print("      FAIL: printed '%s' for an action that does not exist." % got2)

	print("")
	print("=== ARM 5 (RED ARM): no subject must be announced ===")
	# The shell finds PlayerInput by walking the current scene. Headless with no
	# scene loaded there is none, so the shell must SAY that rather than render
	# an empty table. This arm asserts the guard exists by checking the source
	# text, which is honest about being a weaker check: it proves the branch is
	# present, not that it fires in a live session.
	var src: String = FileAccess.get_file_as_string(
		"res://addons/cabra.lat_shooters/src/player/debug/movement_state_overlay.gd")
	var announces := src.contains("PlayerInput NOT FOUND")
	print("  shell announces a missing subject: %s" % announces)
	if not announces:
		_fail += 1
		print("      FAIL: no 'subject not found' branch, so with no player the panel")
		print("      renders header-only and every row reads as 'off'.")
	if not src.contains("UNBOUND"):
		_fail += 1
		print("      FAIL: the UNBOUND arm is gone from the shell.")

	print("")
	print("=== TOGGLE ACTION: F5 must be bound, or the deliverable is unreachable ===")
	var tog: String = T.binding_text(T.TOGGLE_ACTION)
	print("  %-32s -> %s" % [T.TOGGLE_ACTION, tog])
	if tog == "UNBOUND" or tog == "NO SUCH ACTION":
		_fail += 1
		print("      FAIL: the F5 toggle has no binding in project.godot. The shell")
		print("      exists but cannot be opened, which is the one failure the")
		print("      deliverable cannot have.")

	print("")
	print("RESULT: %s (failures=%d)  elapsed %d ms" % ["PASS" if _fail == 0 else "FAIL", _fail, Time.get_ticks_msec() - t0])
	quit(0 if _fail == 0 else 1)


func _actions_with_multiple_events() -> Array[String]:
	var out: Array[String] = []
	for a in InputMap.get_actions():
		if InputMap.action_get_events(a).size() > 1:
			out.append(a)
	return out
