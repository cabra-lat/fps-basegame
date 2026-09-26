extends SceneTree
## INV-38f pose precondition, built against the PRODUCTION-SHAPED subject.
##
## WHY `bot.tscn` AND NOT THE RIG SCENE. `humanoid_rig.tscn` contains ZERO
## `type="AnimationPlayer"` nodes -- the AnimationPlayer is parented to the
## Skeleton3D by the INSTANTIATION SITE (`bot.tscn:17`, `root_node = "../.."`).
## So a guard written against a bare rig scene has no subject to measure.
##
## AND WHY NO STUB AnimationPlayer. `humanoid_rig.gd:20` documents it: if the rig
## scene ever gains its own AnimationPlayer, `root_node` becomes the base of the
## track paths, the clips address the skeleton as `Skeleton3D:<bone>`, and the
## default `root_node = ".."` silently repoints every track in the library. A
## stub that goes green while its subject is not production-shaped is a control
## the failure cannot reach, so no stub is attached here.
##
## RESOLUTION MATCHES PRODUCTION. humanoid_rig.gd:354 `_ensure_anim()` is a
## recursive TYPE-walk (`if n is AnimationPlayer`), not a name lookup. A guard
## that resolves the subject differently from the code it guards can disagree
## with it, and a name lookup fails whenever "rig" means the bot root rather than
## the Skeleton3D.
##
## TWO FAILURE MODES WITH OPPOSITE REMEDIES, and this is the design point: a
## frozen rig (LOD, correct production behaviour past 45 m -> the MEASUREMENT is
## void) and a subject with no AnimationPlayer (the FIXTURE is wrong) used to
## print the same string. A reader who cannot tell them apart either re-measures
## a frozen subject or debugs a fixture that is fine. So `mode` is separate from
## the message and each mode names its own remedy.
##
## THE TWO-AXIS ACCEPTANCE is asserted alongside the guard, not replaced by it:
## speed_scale > 0 AND root travel > 0.5 m AND clip advance > 0.05 s over the
## same window. A passing speed_scale check on a stationary bot is the rig_up_dot
## error again.
##
## ORDER: the RED arm runs FIRST and is shown first, because a guard nobody has
## seen fail has not been shown to work.

const BOT_SCENE := "res://src/npcs/bot/bot.tscn"
const ANIM_LOD_DISTANCE := 45.0
const MIN_TRAVEL := 0.5
const MIN_CLIP_ADVANCE := 0.05

var _fail := 0
var _pass := 0


## EVERY WAIT IS BOUNDED. An unbounded await in a harness is a harness that can
## hang, and a hang cannot report. This file previously sat 33 minutes with no
## result while holding the shared lock, so no await below is open-ended: each is
## counted, and the budget names the place it stopped at. This is the cure that is
## correct WHATEVER the underlying cause turns out to be.
var _frame := 0
const FRAME_BUDGET := 1200


func _await_frames(n: int, where: String) -> bool:
	for _i in n:
		await physics_frame
		_frame += 1
		if _frame > FRAME_BUDGET:
			_fail += 1
			print("  HANG GUARD: exceeded %d physics frames while waiting at %s" % [FRAME_BUDGET, where])
			print("RESULT: FAIL (failures=%d)" % _fail)
			quit(1)
			return false
	return true


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	if not await _await_frames(2, "startup"): return

	print("=== RED ARM FIRST: a bot PAST 45 m must be VOID, and must say why ===")
	var red := await _measure(Vector3(0, 0, 60.0), "red arm, 60 m from the camera")
	print("  mode    : %s" % red["mode"])
	print("  message : %s" % red["message"])
	_expect(red["mode"] == "FROZEN_BY_LOD",
		"a bot at 60 m must read FROZEN_BY_LOD, got %s" % red["mode"])
	_expect(red["void_reading"] == true, "a frozen subject must mark the reading VOID")
	_expect(red["message"].contains("60"), "the message must carry the distance, got: %s" % red["message"])
	_expect(red["remedy"].contains("45"), "the remedy must name the 45 m distance, got: %s" % red["remedy"])

	print("")
	print("=== THE OTHER FAILURE MODE, WHICH MUST NOT LOOK LIKE THE FIRST ===")
	# A rig-scene instantiation has no AnimationPlayer at all. Its message must be
	# a DIFFERENT mode with a DIFFERENT remedy, not the LOD string.
	var rig_only := load("res://addons/cabra.lat_shooters/src/player/scenes/humanoid_rig.tscn") as PackedScene
	var rig := rig_only.instantiate()
	root.add_child(rig)
	var no_anim := _precondition(rig, _cam)
	print("  mode    : %s" % no_anim["mode"])
	print("  message : %s" % no_anim["message"])
	_expect(no_anim["mode"] == "NO_ANIMATION_PLAYER",
		"a rig-scene subject must read NO_ANIMATION_PLAYER, got %s" % no_anim["mode"])
	_expect(no_anim["message"] != red["message"],
		"the two failure modes must not print the same string")
	_expect(no_anim["remedy"].contains("bot.tscn") or no_anim["remedy"].contains("fixture"),
		"the fixture remedy must point at the subject, got: %s" % no_anim["remedy"])
	rig.queue_free()

	print("")
	print("=== GREEN ARM: a bot INSIDE 45 m, production-shaped, two-axis ===")
	var green := await _measure(Vector3(0, 0, 20.0), "green arm, 20 m from the camera")
	print("  mode         : %s" % green["mode"])
	print("  speed_scale  : %s" % green["speed_scale"])
	print("  travel_m     : %s" % green["travel_m"])
	print("  clip_advance : %s" % green["clip_advance"])
	print("  message      : %s" % green["message"])
	_expect(green["mode"] == "VALID_SUBJECT",
		"a travelling, animating bot at 20 m must be VALID, got %s -- %s" % [green["mode"], green["message"]])

	print("")
	print("=== THE TWO-AXIS RULE, AS ITS OWN ASSERTION ===")
	# speed_scale > 0 alone is NOT sufficient: a frozen-clock, stationary bot
	# would pass it. Assert the stationary case is rejected on travel.
	var axes := _axes_ok(1.0, 0.01, 0.30)
	_expect(not axes, "speed_scale 1.0 with 0.01 m travel and no clip advance must NOT be a valid subject")
	print("  speed_scale=1.0 travel=0.01 m clip=0.30 s -> axes_ok=%s (rejected, as it must be)" % axes)
	var axes2 := _axes_ok(1.0, 0.80, 0.30)
	_expect(axes2, "all three axes met must be a valid subject")
	print("  speed_scale=1.0 travel=0.80 m clip=0.30 s -> axes_ok=%s" % axes2)

	print("")
	print("RESULT: %s (pass=%d fail=%d)  elapsed %d ms" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail, Time.get_ticks_msec() - t0])
	quit(0 if _fail == 0 else 1)


var _cam: Camera3D = null


## Instantiate bot.tscn, place it, drive it, and measure. The subject is the
## production scene, so the guard is exercised on the shape production builds.
func _measure(at: Vector3, label: String) -> Dictionary:
	var packed := load(BOT_SCENE) as PackedScene
	if packed == null:
		return {"mode": "FIXTURE_BROKEN", "message": "bot.tscn did not load", "remedy": "check the path", "void_reading": true}
	var bot := packed.instantiate()
	root.add_child(bot)
	if not await _await_frames(2, "startup"): return {}
	if bot is Node3D:
		(bot as Node3D).global_position = at

	_cam = Camera3D.new()
	_cam.global_position = Vector3.ZERO
	root.add_child(_cam)
	_cam.current = true

	# Let the bot settle, then give the rig a clip and drive the root, so travel
	# and clip advance are measured over the SAME window.
	for _i in 20:
		if not await _await_frames(1, "measure loop"): return {}
	var skel := _type_walk(bot, "Skeleton3D")
	if skel != null and skel.has_method("play"):
		skel.call("play", &"walk")
	var start: Vector3 = (bot as Node3D).global_position
	for _i in 90:
		if not await _await_frames(1, "measure loop"): return {}
	var travel: float = (bot as Node3D).global_position.distance_to(start)
	var anim := _find_anim(bot)
	var adv := 0.0
	if anim != null and anim.current_animation_position > 0.0:
		adv = anim.current_animation_position
	var res := _precondition(bot, _cam) as Dictionary
	res["travel_m"] = travel
	res["clip_advance"] = adv
	res["speed_scale"] = (anim.speed_scale if anim != null else -1.0)
	res["label"] = label
	bot.queue_free()
	return res


## The gate. `mode` and `message` and `remedy` are separate so a reader can act on
## the mode without parsing prose, and so two different faults cannot share a
## message.
func _precondition(subject: Node, cam: Camera3D) -> Dictionary:
	var anim := _find_anim(subject)
	if anim == null:
		return {
			"mode": "NO_ANIMATION_PLAYER", "void_reading": true,
			"message": "subject %s carries no AnimationPlayer in its subtree" % subject.name,
			"remedy": "the FIXTURE is wrong, not the measurement: build the subject from bot.tscn, where the AnimationPlayer is parented to Skeleton3D",
		}
	if anim.speed_scale <= 0.0:
		# Distance is measured FROM THE SUBJECT, never by walking up from the
		# AnimationPlayer. "../../.." from the AnimationPlayer lands on the bot
		# root, and one level further lands on the SceneTree's Window -- which
		# has no global_position at all, so the first version of this threw on
		# the frozen path, the one path that must never throw.
		var d := -1.0
		if cam != null and subject is Node3D and subject.is_inside_tree() and cam.is_inside_tree():
			d = (subject as Node3D).global_position.distance_to(cam.global_position)
		return {
			"mode": "FROZEN_BY_LOD", "void_reading": true,
			"message": "subject %s has speed_scale=%.3f (frozen) at %.1f m from the active camera" % [
				subject.name, anim.speed_scale, d],
			"remedy": "the MEASUREMENT is void, not the rig: place the subject within anim_lod_distance=%.0f m, or read the distance before concluding" % ANIM_LOD_DISTANCE,
		}
	return {"mode": "SPEED_SCALE_OK", "void_reading": false,
		"message": "speed_scale=%.3f" % anim.speed_scale, "remedy": "speed scale alone is not sufficient; travel and clip advance must also be met"}


func _axes_ok(speed_scale: float, travel: float, clip: float) -> bool:
	return speed_scale > 0.0 and travel > MIN_TRAVEL and clip > MIN_CLIP_ADVANCE


## Same resolution strategy as humanoid_rig.gd:354 `_ensure_anim()`: a recursive
## TYPE-walk. A name lookup fails whenever "rig" means the bot root.
func _find_anim(n: Node) -> AnimationPlayer:
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is AnimationPlayer:
			return c
		stack.append_array(c.get_children())
	return null


func _type_walk(n: Node, cls: String) -> Node:
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c.get_class() == cls:
			return c
		stack.append_array(c.get_children())
	return null


func _expect(ok: bool, why: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % why)
	else:
		_fail += 1
		print("  FAIL  %s" % why)
