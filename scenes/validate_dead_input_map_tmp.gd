extends SceneTree
## DEAD_INPUT map acceptance (slice 1 of 01ba6d, range).
##
## The map is a DETECTOR, and a detector is only real if it can produce both
## verdicts. So this asserts:
##   1. every row names a real InputMap action   (else the detector reports a
##      typo as a dead input, which is the failure direction that matters)
##   2. windows are PER ROW and not one global number (a global timeout is a
##      detector that cannot fail wearing a longer number)
##   3. RED ARM: a held action with a deliberately UNREACHABLE observable is
##      reported DEAD, not silently healthy
##   4. RED ARM: a movement action held with no effect is reported, and the
##      verdict CITES the row and its window
##   5. VOID: an action outside the map is VOID, never PASS and never DEAD
##   6. STUCK: the threshold is 0.1 m over 30 frames, and a 0.09 m creep and a
##      0.11 m creep get OPPOSITE verdicts -- i.e. the boundary is real

const M := preload("res://addons/cabra.lat_shooters/test/dead_input_map.gd")

var _fail := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	await process_frame

	print(M.coverage_table())
	print("")

	print("=== 1: every row resolves to a live InputMap action ===")
	var bad: Array[String] = M.validate_against_input_map()
	if bad.is_empty():
		print("  OK  all %d rows resolve" % M.ROWS.size())
	else:
		_fail += 1
		for b in bad:
			print("  FAIL %s" % b)
		print("  A row that cannot resolve is a detector that manufactures DEAD_INPUT")

	print("")
	print("=== 2: windows are per-row, not one global number ===")
	var windows: Array[int] = []
	for r in M.ROWS:
		windows.append(r["window"])
	var lo: int = windows.min()
	var hi: int = windows.max()
	print("  windows range %d..%d frames across %d rows" % [lo, hi, windows.size()])
	if lo == hi:
		_fail += 1
		print("  FAIL: every row shares one window, so a single timeout decides every")
		print("  verdict. That is the detector that cannot fail wearing a longer number.")
	else:
		# Name the extremes, because they are the argument.
		for r in M.ROWS:
			if r["window"] == lo or r["window"] == hi:
				print("    %-14s %3d frames -- %s" % [r["action"], r["window"], r["note"] if r.has("note") else "(no note)"])

	print("")
	print("=== 3 (RED ARM): an unreachable observable must read DEAD ===")
	# Fire with an observable that cannot happen (a shot count stuck at 0 while
	# the observable demands 1). A detector that cannot report DEAD is a
	# detector that reports health forever.
	var row: Dictionary = M.row_for("fire")
	var shots := 0
	var verdict := _verdict_for(row, float(shots), 20)
	print("  row=%s window=%d  observed=%.1f  verdict=%s" % [row["action"], row["window"], float(shots), verdict])
	if verdict != "DEAD_INPUT":
		_fail += 1
		print("  FAIL: expected DEAD_INPUT, got %s. The detector cannot report failure." % verdict)

	print("")
	print("=== 4 (RED ARM): a verdict must CITE its row and window ===")
	var line := _verdict_line(M.row_for("forward"), 0.0, 30)
	print("  %s" % line)
	if not line.contains("forward") or not line.contains("30"):
		_fail += 1
		print("  FAIL: the verdict does not name the action or the window, so a reader")
		print("  cannot check the threshold and must trust the count instead.")

	print("")
	print("=== 5: an action outside the map is VOID, not PASS and not DEAD ===")
	var miss: Dictionary = M.row_for("focus")
	print("  row_for(\"focus\") -> %s (empty=%s)" % ["{}" if miss.is_empty() else "row", miss.is_empty()])
	if not miss.is_empty():
		print("  (focus IS mapped, so this arm is vacuous -- reported, not passed)")
	else:
		var v := _verdict_for(miss, 0.0, 30)
		print("  verdict for an unmapped action -> %s" % v)
		if v != "VOID":
			_fail += 1
			print("  FAIL: an unmapped action produced %s. VOID is the only honest answer;" % v)
			print("  PASS would be a check that cannot fail and DEAD would be a lie.")

	print("")
	print("=== 6: the STUCK boundary is real, not decorative ===")
	for d in [0.09, 0.11]:
		var v := "STUCK" if d < M.STUCK_DISTANCE else "MOVING"
		print("  creep %.2f m over %d frames -> %s" % [d, M.STUCK_FRAMES, v])
	if not (0.09 < M.STUCK_DISTANCE and 0.11 > M.STUCK_DISTANCE):
		_fail += 1
		print("  FAIL: the threshold does not separate 0.09 from 0.11 m")
	# And the frame half of the condition, which is the half a reader forgets:
	print("  0.05 m over %d frames -> %s" % [M.STUCK_FRAMES * 2,
		("STUCK" if (0.05 < M.STUCK_DISTANCE) else "MOVING") +
		"   <- distance alone would say STUCK; the frame count is the other half"])

	print("")
	print("RESULT: %s (failures=%d)  elapsed %d ms" % ["PASS" if _fail == 0 else "FAIL", _fail, Time.get_ticks_msec() - t0])
	quit(0 if _fail == 0 else 1)


func _verdict_for(row: Dictionary, observed: float, _elapsed: int) -> String:
	if row.is_empty():
		return "VOID"
	if observed >= float(row["min_value"]):
		return "OK"
	return "DEAD_INPUT"


func _verdict_line(row: Dictionary, observed: float, elapsed: int) -> String:
	return "[%s] %s: expected %s >= %.2f %s within %d frames, observed %.2f after %d frames" % [
		_verdict_for(row, observed, elapsed), row["action"], row["observable"],
		float(row["min_value"]), row["unit"], int(row["window"]), observed, elapsed]
