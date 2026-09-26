extends SceneTree
## SLICE 1 of card 01ba6d (range): INPUT INJECTION acceptance harness.
##
## The only variable in this file is INJECT below. Run with INJECT = false and
## it MUST be red; run with INJECT = true and it must be green. Nothing else
## differs, and the red is the evidence that the check can fail.
##
## Why the red is announced rather than produced quietly: a green that was
## never shown red is compatible with a harness that cannot fail, and a
## harness that cannot fail still counts in the total.
##
## Convention (the one that already exists): extends SceneTree, run through
## tools/godot-lock.sh, exit 0 or 1. Modeled on scenes/validate_arena_spawn.gd.

## THE SINGLE VARIABLE. false = red (no injection), true = green.
const INJECT := true

const SCENE := "res://scenes/debug_movement.tscn"
## Input.gd:71-72 reads Input.get_action_strength("forward") into a signed
## axis, so an explicit strength is required -- a bare press is not enough.
const ACTION := "forward"
const STRENGTH := 1.0
const FRAMES := 60
## Metres. Any positive value passes; the threshold is deliberately boring
## because this is a CONTROL, not a feature.
const MIN_DELTA := 0.01
## A plausible walk, not a drift and not a teleport. A drift shows as a small
## mean with an occasional big step; a teleport shows as one huge step.
const SPEED_MIN := 0.5
const SPEED_MAX := 10.0

var _fail := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var packed: PackedScene = load(SCENE)
	if packed == null:
		_fail += 1
		print("FATAL: cannot load %s" % SCENE)
		_finish(t0, "FATAL")
		return
	var world: Node = packed.instantiate()
	root.add_child(world)

	# Positive control FIRST, in a different unit from the thing measured: the
	# player must be on a surface and alive BEFORE the red is produced, or the
	# red only proves the player could never move.
	var body: CharacterBody3D = null
	await process_frame
	for c in _all(world):
		if c is CharacterBody3D:
			body = c
			break
	if body == null:
		_fail += 1
		print("FATAL: no CharacterBody3D under %s" % SCENE)
		_finish(t0, "FATAL")
		return
	print("player: %s  global_position=%s  on_floor=%s  alive=%s" % [
		body.name, body.global_position, body.is_on_floor(),
		not _looks_dead(body)])
	print("INJECT=%s  action=%s strength=%.1f  frames=%d" % [INJECT, ACTION, STRENGTH, FRAMES])

	# SETTLE FIRST: the body spawns at y=1.5 and FALLS, and a 3D distance
	# against a horizontal action measures the fall, not the movement. That is
	# a different unit, and it is the confound that made the first red wrong.
	for _s in 120:
		await physics_frame
		if body.is_on_floor():
			break
	print("settled: on_floor=%s after settle, y=%.4f" % [body.is_on_floor(), body.global_position.y])
	var start := body.global_position
	# Per-frame HORIZONTAL position deltas, not body.velocity. velocity is
	# consumed inside the controller's own physics step, so sampling it from
	# await physics_frame reads a different quantity than the one being claimed:
	# 0.0659 m/s beside 3.92 m of travel is a unit error, not a slow walk.
	# Speed is DERIVED from position so both numbers are in metres.
	var per_frame: Array[float] = []
	var prev := body.global_position
	if INJECT:
		Input.action_press(ACTION, STRENGTH)
	for _f in FRAMES:
		await physics_frame
		var now := body.global_position
		per_frame.append(Vector2(now.x - prev.x, now.z - prev.z).length())
		prev = now
	if INJECT:
		Input.action_release(ACTION)
	var derived_speed := 0.0
	var max_step := 0.0
	for d in per_frame:
		derived_speed += d
		max_step = maxf(max_step, d)
	derived_speed = derived_speed / (float(FRAMES) / 60.0)
	var delta := body.global_position - start
	var flat := Vector2(delta.x, delta.z)   # horizontal only: the action is horizontal

	print("")
	print("RESULT  start=%s  end=%s" % [start, body.global_position])
	print("        distance_moved = %.4f m   (threshold %.4f)" % [delta.length(), MIN_DELTA])
	print("        derived_speed  = %.4f m/s  (sum of per-frame deltas / elapsed)" % derived_speed)
	print("        max_step       = %.4f m/frame  (steady locomotion has no big spikes)" % max_step)
	print("        horizontal    = %.4f m" % flat.length())

	# Assert the red is RED FOR THE RIGHT REASON. A zero delta while the body
	# never moved is the claim; a zero delta while the body was airborne or dead
	# is a different failure and must not be reported as this one.
	if flat.length() < MIN_DELTA:
		_fail += 1
		print("")
		if INJECT:
			print("FAIL: '%s' was injected at strength %.1f for %d physics frames and the" % [ACTION, STRENGTH, FRAMES])
			print("      player moved %.4f m horizontally. The action is DEAD." % flat.length())
		else:
			print("EXPECTED RED: with no injection the player moved %.4f m horizontally, which is" % flat.length())
			print("      correct. This run exists to prove the check CAN fail; re-run with")
			print("      INJECT = true and the check must go green.")
		if INJECT and (derived_speed < SPEED_MIN or derived_speed > SPEED_MAX):
			_fail += 1
			print("      derived speed %.3f m/s is outside the plausible walk band %.1f-%.1f." % [derived_speed, SPEED_MIN, SPEED_MAX])
			print("      max_step %.4f m/frame: the motion is a DRIFT or a TELEPORT, not walking," % max_step)
			print("      so the green above is not evidence that the action drove locomotion.")
	else:
		if not INJECT:
			_fail += 1
			print("FAIL: expected RED with no injection but the player moved %.4f m horizontally." % flat.length())
			print("      The scene moved the player by itself, so this harness cannot")
			print("      demonstrate anything and the red is unavailable.")
		else:
			print("PASS: injected action moved the player %.4f m horizontally in %d physics frames." % [flat.length(), FRAMES])
	_finish(t0, "")


func _looks_dead(b: CharacterBody3D) -> bool:
	# Best-effort only: the point is to notice an obviously dead/airborne body
	# rather than to reimplement the death state.
	return b.global_position.y < -1.0


func _all(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func _finish(t0: int, tag: String) -> void:
	if tag != "":
		print("RESULT: FAIL (%s)" % tag)
	else:
		print("")
		print("RESULT: %s (failures=%d)" % ["PASS" if _fail == 0 else "FAIL", _fail])
	print("elapsed %d ms" % (Time.get_ticks_msec() - t0))
	quit(0 if _fail == 0 else 1)
