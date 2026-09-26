extends SceneTree
## Slice 2a acceptance: DEATH_SPIRE + UNREACHABLE.
## Every scenario is fed SYNTHETICALLY, so each arm is decidable rather than
## dependent on an arena run that sometimes happens to produce the condition.
## Three of the arms are the OPPOSITE of the condition, because a detector that
## only ever sees the bad case is a detector nobody has shown to be quiet.
const D := preload("res://addons/cabra.lat_shooters/test/frustration_detectors.gd")

var _fail := 0

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	await process_frame
	var target := Vector3(100, 0, 100)

	print("=== DEATH_SPIRE ===")
	# 1. three deaths in three DIFFERENT places -> no spire. This is the arm that
	#    would fire on a naive "3 deaths" counter.
	var spread: Array = [D.death(10, Vector3(0,0,0)), D.death(20, Vector3(400,0,0)), D.death(30, Vector3(0,0,400))]
	var r1: Dictionary = D.death_spire(spread, [])
	print("  spread  -> %s" % r1["verdict"]); _expect(r1["verdict"] == "NO_SPIRE", "3 deaths 400 m apart must NOT be a spire")

	# 2. three deaths within 10 m, at three different spots -> SPIRE.
	var cluster: Array = [D.death(10, Vector3(0,0,0)), D.death(25, Vector3(6,0,4)), D.death(40, Vector3(-5,0,7))]
	var r2: Dictionary = D.death_spire(cluster)
	print("  cluster -> %s (count=%d, radius=%.0f m)" % [r2["verdict"], r2["count"], r2["radius_m"]])
	_expect(r2["verdict"] == "DEATH_SPIRE", "3 deaths within 10 m IS a spire")

	# 3. THE GUARD. Same three deaths, but the arena respawns the player there.
	var r3: Dictionary = D.death_spire(cluster, [{"pos": Vector3(0,0,0), "authored": false}])
	print("  guard   -> %s" % r3["verdict"])
	print("            %s" % r3["reason"])
	_expect(r3["verdict"] == "RESPAWN_GEOMETRY", "a cluster on the respawn point is the spawn solver, not the player")
	_expect(r3["verdict"] != "DEATH_SPIRE", "RESPAWN_GEOMETRY must REPLACE the player-facing verdict")

	# 4. the radius is a CHOICE and changes the answer -> both must be printable.
	var r4: Dictionary = D.death_spire(spread, [])
	_expect(float(r4["radius_m"]) == 15.0, "the radius must be reported so a reader can check it")

	# 5. two deaths is not three.
	var r5: Dictionary = D.death_spire([D.death(1, Vector3.ZERO), D.death(2, Vector3(1,0,0))], [])
	print("  two     -> %s" % r5["verdict"]); _expect(r5["verdict"] == "NO_SPIRE", "2 deaths is below the count")

	print("")
	print("=== UNREACHABLE ===")
	# 6. walks straight at it and arrives -> ARRIVED, never UNREACHABLE.
	var walk: Array = []
	for i in 28: walk.append({"t": float(i), "pos": Vector3(float(i)*3.7, 0, float(i)*3.7)})
	var u1: Dictionary = D.unreachable(walk, target)
	print("  arrive  -> %s (%.1f s, closest %.2f m)" % [u1["verdict"], u1["seconds"], u1["closest_m"]])
	_expect(u1["verdict"] == "ARRIVED", "walking to the objective must read ARRIVED")

	# 7. RED ARM: approaches, then stalls 30 m short for 25 s -> UNREACHABLE.
	var stall: Array = []
	for i in 10: stall.append({"t": float(i), "pos": Vector3(50,0,50)})
	for i in 35: stall.append({"t": 10.0+float(i), "pos": Vector3(70,0,70)})
	var u2: Dictionary = D.unreachable(stall, target)
	print("  stall   -> %s" % u2["verdict"]); print("            %s" % u2["reason"])
	_expect(u2["verdict"] == "UNREACHABLE", "30 m short and static for 25 s IS unreachable")
	_expect(u2["still_improving"] == false, "a stalled bot must not be reported as still improving")

	# 8. SLOW_PROGRESS is its own verdict: still closing, so not a wall.
	var slow: Array = []
	for i in 40: slow.append({"t": float(i), "pos": Vector3(float(i)*0.9, 0, float(i)*0.9)})
	var u3: Dictionary = D.unreachable(slow, target)
	print("  slow    -> %s (closed %.2f m)" % [u3["verdict"], u3["closed_m"]])
	_expect(u3["verdict"] == "SLOW_PROGRESS", "still closing is a slow path, not a wall")

	# 9. RED ARM: too few samples -> VOID, not REACHED. A bot that produced no
	#    data has not arrived at anything.
	var u4: Dictionary = D.unreachable([{"t": 0.0, "pos": Vector3.ZERO}], target)
	print("  one     -> %s" % u4["verdict"]); print("            %s" % u4["reason"])
	_expect(u4["verdict"] == "VOID", "one sample is VOID and must never read as REACHED")

	# 10. a verdict must CITE its parameters.
	var line: String = D.report_line("DEATH_SPIRE", r2)
	print("  cite    -> %s" % line)
	_expect(line.contains("radius=15") and line.contains("min_count=3"), "the verdict must print the parameters that produced it")

	print("")
	print("=== SLOW_CONTACT, labelled DAMAGE_CONTACT (never hostile) ===")
	# SYNTHETIC EMISSION, and this is the arm coordinator asked for: a signal that is
	# connected but never emitted reads exactly like a signal that does not exist,
	# so the detector must be shown DECIDING on fed data.
	var c1: Dictionary = D.slow_contact(0.0, 650.0, 650.0)
	print("  damage at 650 s -> %s (%.1f s)" % [c1["verdict"], c1["contact_s"]])
	_expect(c1["verdict"] == "SLOW_CONTACT", "damage at the 600 s mark is SLOW_CONTACT")
	_expect(c1["label"] == "DAMAGE_CONTACT", "the label must be DAMAGE_CONTACT")
	_expect(not c1.has("hostile"), "the verdict must never claim hostility")
	var c2: Dictionary = D.slow_contact(0.0, 30.0, 30.0)
	print("  damage at  30 s -> %s (%.1f s)" % [c2["verdict"], c2["contact_s"]])
	_expect(c2["verdict"] == "NO_CONTACT", "damage early in the raid is not slow contact")

	print("")
	print("=== RESPAWN EXCLUSION ON THE RUNTIME POINT (2.1 m spread inside) ===")
	# A solver-spread cluster: the deaths sit around the point the bot ACTUALLY
	# respawned at, spread over more than the 0 m a constant-anchor check allows.
	var spread_cluster: Array = [D.death(10, Vector3(1.8,0,0.9)), D.death(25, Vector3(-1.5,0,1.2)), D.death(40, Vector3(0.6,0,-1.9))]
	var runtime_pt: Array = [{"pos": Vector3(0,0,0), "authored": false}]
	var g1: Dictionary = D.death_spire(spread_cluster, runtime_pt)
	print("  on the RUNTIME respawn point -> %s" % g1["verdict"])
	print("      %s" % g1["reason"])
	_expect(g1["verdict"] == "RESPAWN_GEOMETRY", "a solver-spread cluster on the runtime point must be RESPAWN_GEOMETRY")
	# An AUTHORED fallback point is a different terminal, and it is EXCLUDED.
	var g2: Dictionary = D.death_spire(spread_cluster, [{"pos": Vector3(0,0,0), "authored": true}])
	print("  on an AUTHORED fallback   -> %s" % g2["verdict"])
	_expect(g2["verdict"] == "RESPAWN_AMBIGUOUS", "an authored fallback point is RESPAWN_AMBIGUOUS, not player-caused")
	# And the safe error: a real spire far from any respawn point must survive.
	var far: Array = [D.death(10, Vector3(900,0,0)), D.death(25, Vector3(906,0,4)), D.death(40, Vector3(895,0,7))]
	var g3: Dictionary = D.death_spire(far, runtime_pt)
	print("  far from any respawn     -> %s (excluded %d)" % [g3["verdict"], int(g3.get("excluded", 0))])
	_expect(g3["verdict"] == "DEATH_SPIRE", "a genuine spire away from respawns must still be reported")

	print("")
	print("RESULT: %s (failures=%d)  elapsed %d ms" % ["PASS" if _fail == 0 else "FAIL", _fail, Time.get_ticks_msec() - t0])
	quit(0 if _fail == 0 else 1)

func _expect(ok: bool, why: String) -> void:
	if not ok:
		_fail += 1
		print("    FAIL: %s" % why)
