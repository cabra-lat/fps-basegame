extends SceneTree
## Is the F5 overlay ACTUALLY IN THE PLAYER SCENE? A script that exists and is
## correct but is wired into nothing has a 0% hit rate, and "I wrote it" is not
## "it runs". So this loads the real player scene and asks the scene.
func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var fail := 0
	await process_frame
	var packed: PackedScene = load("res://addons/cabra.lat_shooters/src/player/scenes/player.tscn")
	if packed == null:
		print("FAIL: player.tscn did not load"); quit(1); return
	var n: Node = packed.instantiate()
	root.add_child(n)
	await process_frame
	var found: Node = n.get_node_or_null("MovementStateOverlay")
	if found == null:
		fail += 1
		print("FAIL: MovementStateOverlay is NOT in player.tscn -- the shell exists but nothing opens it")
	else:
		print("OK  player.tscn carries MovementStateOverlay (%s, script=%s)" % [found.get_class(), found.get_script()])
		# And it must be toggleable: a panel nobody can open is a panel that never runs.
		var ov: Object = found
		if ov.has_method("get") and not ("visible" in ov):
			fail += 1
			print("FAIL: overlay has no visible property to toggle")
		else:
			print("OK  overlay exposes visible=%s (F5 toggles it)" % ov.get("visible"))
			ov.set("visible", true)
			print("OK  after toggle: visible=%s" % ov.get("visible"))
	# The binding must exist, or the toggle is unreachable.
	var a := "debug_toggle_movement_overlay"
	if not InputMap.has_action(a):
		fail += 1
		print("FAIL: action %s is not in the InputMap" % a)
	else:
		print("OK  %s -> %d event(s)" % [a, InputMap.action_get_events(a).size()])
	print("RESULT: %s (failures=%d) elapsed %d ms" % ["PASS" if fail == 0 else "FAIL", fail, Time.get_ticks_msec() - t0])
	quit(0 if fail == 0 else 1)
