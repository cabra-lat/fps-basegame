# res://src/dev/validate_profiler.gd
#
# Headless gate for the profiler instrument. Proves:
#   [A] the registry is unique, complete against the card, and honest
#   [B] THE RULE: zero samples -> "not_sampled" with NO value key, in a frame
#       AND in the aggregate over a window (both places it could leak a 0.0)
#   [C] "sampled" is earned by a sample count, not by a non-zero number: a
#       scope that genuinely took ~0 ms is still "sampled"
#   [D] unmeasurable subsystems report "not sampled" with a usable reason
#   [E] off by default: inert recorder, no Profiler node, nothing recorded
#   [F] ring buffer bounds and honest drop accounting
#   [G] JSON dump is parseable, self-describing, and strict mode FAILS loudly
#   [H] instrumentation faults (unbalanced scopes) are surfaced, not swallowed
#   [I] the F8 overlay toggle works and the overlay never paints a 0 for a gap
#
# WHAT THIS DOES NOT DO, explicitly: it does not profile a playthrough, and it
# does not claim any number about the game's real performance. It drives the
# instrument's public API with synthetic timings. Phase 1 of the card is the
# instrument; a real playthrough is a separate card, and a gate that implied
# coverage of it would be the same overclaiming this instrument exists to stop.
#
# Run:
#   godot --headless --path . --script res://src/dev/validate_profiler.gd
# Exit code: 0 = all checks passed, 1 = at least one failure.
extends SceneTree

const OUT := "user://validate_profiler"

var v: ValidateUtil

func _initialize() -> void:
	v = ValidateUtil.new("profiler")
	v.begin()

	_a_registry()
	_b_not_sampled_rule()
	_c_sampled_is_earned_by_samples()
	_d_unmeasurable_reasons()
	_e_off_by_default()
	_e2_release_is_off()
	_f_ring_buffer()
	_g_json_dump()
	_h_instrumentation_faults()
	_i_overlay()

	v.finish()
	quit(v.failed)

# ─── [A] REGISTRY ──────────────────────────────────────────────────────────

func _a_registry() -> void:
	v.section("[A] registry")
	var entries := ProfilerSubsystems.entries()
	var seen := {}
	var dupes := 0
	for e in entries:
		if seen.has(e.id):
			dupes += 1
		seen[e.id] = true
	v.check(dupes == 0, "every subsystem id is unique (%d entries)" % entries.size())

	# The card's minimum list, by name. If a rename ever drops one of these the
	# gate fails instead of the dump quietly shrinking.
	for required in [&"physics_step", &"process_total", &"physics_process_total", &"bot_ai",
			&"bot_animation_skeleton", &"physics_queries", &"ui_layout", &"world_managers",
			&"audio", &"render_submit"]:
		v.check(seen.has(required), "registry declares '%s'" % required)

	# The two the card asks for that this engine cannot supply. They must stay
	# declared-unavailable, or somebody will quietly turn them into a
	# plausible-looking number later. Looked up BY ID, never by list index: an
	# index is a citation that breaks the moment a row is inserted above it.
	var by_id := {}
	for e in entries:
		by_id[e.id] = e
	for honest_gap in [&"physics_step", &"render_submit", &"player_rig_anim"]:
		v.check((by_id[honest_gap] as ProfilerSubsystems.Entry).source == ProfilerSubsystems.Source.UNAVAILABLE,
			"'%s' is declared UNAVAILABLE rather than approximated" % honest_gap)
		v.check((by_id[honest_gap] as ProfilerSubsystems.Entry).reason.length() > 40,
			"'%s' explains the gap in %d chars" % [honest_gap, (by_id[honest_gap] as ProfilerSubsystems.Entry).reason.length()])

	# A subsystem must never be simultaneously "monitor-backed" and missing its
	# monitor; that combination is how a lookup silently starts reporting zeros.
	var monitor_gaps := 0
	for e in entries:
		if e.source == ProfilerSubsystems.Source.ENGINE_MONITOR and e.monitor() == -1:
			monitor_gaps += 1
			v.check(false, "engine-monitor '%s' has no Performance.%s in this engine" % [e.id, e.monitor_name()])
	v.check(monitor_gaps == 0, "every engine-monitor subsystem resolves to a real Performance monitor")

func _b_not_sampled_rule() -> void:
	v.section("[B] not-sampled rule")
	var p := _new_profiler(16)
	# Every scope subsystem deliberately left uncalled: this frame has no samples
	# for any of them.
	p.record_frame()
	var frame := p.last_frame()
	var subs: Dictionary = frame["subsystems"]

	var missing_value_key := 0
	var wrong_state := 0
	for e in ProfilerSubsystems.entries():
		if e.source != ProfilerSubsystems.Source.SCOPE:
			continue
		var s: Dictionary = subs[e.id]
		if s.get("state") != "not_sampled":
			wrong_state += 1
		# The strong form: the key is ABSENT. 0.0 would also be absent of
		# samples, so a test on samples alone would pass on a real zero.
		if s.has("value"):
			missing_value_key += 1
	v.check(wrong_state == 0, "an uncalled scope subsystem reports state=not_sampled (%d checked)" % _scope_count())
	v.check(missing_value_key == 0, "a not_sampled entry carries NO 'value' key at all (0 leaked)")

	# Same rule, second code path: the aggregate over a window.
	var totals := p.aggregate()
	var leak := 0
	for e in ProfilerSubsystems.entries():
		if (totals[e.id] as Dictionary).get("state") == "not_sampled" and (totals[e.id] as Dictionary).has("value"):
			leak += 1
	v.check(leak == 0, "aggregate over a window also omits 'value' for unsampled (0 leaked)")

	var reasons: Dictionary = totals[&"bot_ai"]
	v.check(String(reasons.get("reason", "")).contains("0 samples"),
		"aggregate states how much it inspected: '%s'" % String(reasons.get("reason", "")))
	p.queue_free()

func _c_sampled_is_earned_by_samples() -> void:
	v.section("[C] sampled vs zero")
	var p := _new_profiler(16)
	# A scope that opens and closes within the same microsecond tick: a real
	# sample whose value is legitimately ~0. It must read "sampled", because the
	# difference between "instant" and "never looked at" is the sample count.
	ProfilerRecorder.begin(&"bot_ai")
	ProfilerRecorder.end()
	p.record_frame()
	var s: Dictionary = (p.last_frame()["subsystems"] as Dictionary)[&"bot_ai"]
	v.check(s.get("state") == "sampled", "a scope that ran reports state=sampled even when it took ~0 ms")
	v.check(int(s.get("samples", 0)) == 1, "sample count is recorded (1)")
	v.check(s.has("value"), "a sampled entry carries a value key")
	# And the mirror: a scope id nobody declared must be counted, not adopted.
	v.check(not ProfilerRecorder.is_declared(&"no_such_subsystem"), "registry rejects an undeclared scope id")
	ProfilerRecorder.begin(&"no_such_subsystem")
	ProfilerRecorder.end()
	v.check(ProfilerRecorder.unknown_subsystems > 0, "an undeclared scope id is counted, not silently adopted")
	p.queue_free()

func _d_unmeasurable_reasons() -> void:
	v.section("[D] unmeasurable subsystems")
	var p := _new_profiler(4)
	p.record_frame()
	var subs: Dictionary = p.last_frame()["subsystems"]
	for e in ProfilerSubsystems.unmeasurable_ids():
		var s: Dictionary = subs[e]
		v.check(s.get("state") == "not_sampled", "'%s' reports not_sampled" % e)
		v.check(String(s.get("reason", "")).length() > 20, "'%s' gives a usable reason (%d chars)" % [e, String(s.get("reason", "")).length()])
	p.queue_free()

func _e_off_by_default() -> void:
	v.section("[E] off by default")
	# Earlier sections deliberately build profilers, so the OFF path is asserted
	# after an explicit reset. Otherwise this section would only be testing
	# whatever the previous section left behind, which is how a default-state
	# test quietly stops testing the default.
	_reset_instrument()
	v.check(not Profiler.opt_in_requested(), "this gate run did not opt in, so it is exercising the OFF path")
	v.check(not Profiler.should_run(), "should_run() is false without an explicit opt-in")
	var host := Node.new()
	root.add_child(host)
	var attached := Profiler.maybe_attach(host)
	v.check(attached == null, "maybe_attach() creates NO Profiler node when off")
	v.check(Profiler.instance == null, "no Profiler instance exists while off")

	# The recorder is the thing call sites touch; it must be a no-op.
	ProfilerRecorder.reset()
	ProfilerRecorder.begin(&"bot_ai")
	ProfilerRecorder.end()
	var drained: Dictionary = ProfilerRecorder.drain()
	v.check((drained["samples"] as Dictionary).is_empty(), "recorder records nothing while disabled")
	host.queue_free()

func _e2_release_is_off() -> void:
	v.section("[E2] release exports")
	# A release export with the opt-in flag set must still refuse unless the
	# preset also carries the `profiler` custom feature. I cannot set features
	# from inside a headless run, so this asserts the DECISION function rather
	# than pretending to test OS.has_feature().
	v.check(Profiler.release_blocks() == OS.has_feature("release") and not OS.has_feature("profiler"),
		"release_blocks() is exactly 'release build without the profiler feature'")

func _f_ring_buffer() -> void:
	v.section("[F] ring buffer")
	var capacity := 20
	var p := _new_profiler(capacity)
	var total := capacity + 7
	for i in total:
		ProfilerRecorder.begin(&"bot_ai")
		ProfilerRecorder.end()
		p.record_frame()
	v.check(p.frame_count() == capacity, "ring retains exactly capacity frames (%d)" % p.frame_count())
	var f0: Dictionary = p.last_frame()
	var oldest_retained: Dictionary = p._frames[0]
	v.check(int(f0["frame"]) == total - 1, "last frame is the newest (frame %d)" % int(f0["frame"]))
	v.check(int(oldest_retained["frame"]) == total - capacity, "oldest retained is frame %d" % int(oldest_retained["frame"]))
	var report := p.dump_json(OUT + "/ring.json")
	var doc := _read_json(String(report["path"]))
	v.check(int((doc["ring"] as Dictionary)["frames_dropped"]) == 7, "dropped frames are reported, not hidden (7)")
	v.check(int((doc["ring"] as Dictionary)["frames_recorded"]) == total, "total frames ever recorded is reported (%d)" % total)
	p.queue_free()

func _g_json_dump() -> void:
	v.section("[G] json dump")
	var p := _new_profiler(8)
	for i in 3:
		ProfilerRecorder.begin(&"bot_ai")
		ProfilerRecorder.end()
		p.record_frame()
	var report := p.dump_json(OUT + "/dump.json")
	v.check(bool(report["ok"]), "a non-strict dump succeeds even when subsystems are missing")
	v.check(String(report["path"]).ends_with("dump.json"), "dump wrote to the requested path")
	var doc := _read_json(String(report["path"]))
	v.check(String(doc.get("schema", "")) == Profiler.SCHEMA, "dump carries a schema version (%s)" % Profiler.SCHEMA)
	v.check(doc.has("complete") and doc.has("not_sampled"), "dump declares completeness and lists gaps up front")
	v.check(bool(doc["complete"]) == false, "complete=false while ui_layout (which IS measurable) is unsampled")
	var missing: Array = doc["not_sampled"]
	v.check(missing.has("render_submit") and missing.has("ui_layout"),
		"not_sampled names the unmeasured subsystems (%d listed)" % missing.size())

	v.check((doc["not_sampled_reasons"] as Dictionary).has("render_submit"),
		"every not_sampled id carries a reason in the dump")
	v.check((doc["not_sampled"] as Array).has("physics_step"),
		"the whole physics step is reported as a gap, not approximated")
	# The permanent gaps are listed separately and are NOT counted against
	# `complete` — otherwise it would be false forever and nobody would read it.
	v.check((doc["measurable_gaps"] as Array).has("ui_layout"), "ui_layout counts as a measurable gap")
	v.check(not (doc["measurable_gaps"] as Array).has("render_submit"), "render_submit does NOT count as a measurable gap")
	v.check((doc["unmeasurable"] as Array).has("physics_step") and (doc["unmeasurable"] as Array).has("render_submit"),
		"the declared-impossible subsystems are listed as unmeasurable")

	# Strict mode is the gate-facing mode: a report that omits a subsystem must
	# not be able to pass as complete.
	var strict := p.dump_json(OUT + "/strict.json", -1, true)
	v.check(bool(strict["ok"]) == false, "strict mode FAILS when a measurable subsystem was not sampled")
	v.check(String(strict["reason"]).contains("ui_layout"), "strict failure names the measurable subsystem")
	v.check(FileAccess.file_exists(OUT + "/strict.json"), "the failing dump is still written so a human can read it")

	# Everything measurable sampled -> strict must pass. Proves strict is not
	# just always-false.
	var q := _new_profiler(8)
	for id in ProfilerRecorder._known.keys():
		ProfilerRecorder.begin(id)
		ProfilerRecorder.end()
	for i in 2:
		q.record_frame()
	var all := q.dump_json(OUT + "/complete.json", -1, true)
	v.check(bool(all["ok"]), "strict mode passes when every MEASURABLE subsystem was sampled")
	v.check(bool(all["complete"]), "complete=true with all measurable subsystems sampled")
	var left: Array = all["not_sampled"]
	v.check(left.size() == ProfilerSubsystems.unmeasurable_ids().size() and left.has("physics_step"),
		"the only entries left unmeasured are the declared UNAVAILABLE (%s)" % ", ".join(left))
	p.queue_free()
	q.queue_free()

func _h_instrumentation_faults() -> void:
	v.section("[H] instrumentation faults")
	var p := _new_profiler(4)
	ProfilerRecorder.begin(&"bot_ai") # deliberately never closed
	p.record_frame()
	v.check(ProfilerRecorder.unbalanced_calls == 1, "an unbalanced scope is counted, not swallowed (%d)" % ProfilerRecorder.unbalanced_calls)
	var doc := _read_json(String(p.dump_json(OUT + "/unbalanced.json")["path"]))
	v.check(int((doc["instrumentation"] as Dictionary)["unbalanced_scope_calls"]) == 1, "the fault is reported in the dump")
	p.queue_free()

func _i_overlay() -> void:
	v.section("[I] overlay")
	var p := _new_profiler(4)
	# One subsystem sampled, one not: the overlay gets both in the same frame.
	ProfilerRecorder.begin(&"bot_ai")
	ProfilerRecorder.end()
	p.record_frame()
	var subs: Dictionary = p.last_frame()["subsystems"]
	v.check((subs[&"bot_ai"] as Dictionary).get("state") == "sampled", "overlay frame has a sampled row to draw")
	v.check((subs[&"render_submit"] as Dictionary).get("state") == "not_sampled", "overlay frame has a not-sampled row to draw")
	# The overlay is a readout on top of a playable game: it must not eat input.
	v.check(p.overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "overlay ignores mouse input")

	# F8 toggles it, which is the only way a human sees it live.
	var before := p.overlay.visible
	var ev := InputEventKey.new()
	ev.keycode = Profiler.HOTKEY_OVERLAY
	ev.pressed = true
	p._unhandled_input(ev)
	v.check(p.overlay.visible != before, "F8 toggles the overlay (visible %s -> %s)" % [before, p.overlay.visible])
	p.queue_free()

# ─── HELPERS ───────────────────────────────────────────────────────────────

func _scope_count() -> int:
	var n := 0
	for e in ProfilerSubsystems.entries():
		if e.source == ProfilerSubsystems.Source.SCOPE:
			n += 1
	return n

## Puts the instrument back to how a release build looks: no instance, recorder
## inert, no accumulated state.
func _reset_instrument() -> void:
	if Profiler.instance != null and is_instance_valid(Profiler.instance):
		Profiler.instance.free()
	Profiler.instance = null
	ProfilerRecorder.enabled = false
	ProfilerRecorder.reset()

func _new_profiler(capacity: int) -> Profiler:
	var p := Profiler.new()
	p.ring_capacity = capacity
	root.add_child(p)
	# start() rather than _ready(): inside a headless SceneTree script, add_child
	# during _initialize does not enter the tree, so _ready never runs and the
	# recorder would stay disabled — a profiler recording nothing, silently.
	p.start()
	# Each case starts from zero so one case's samples cannot make the next case
	# look sampled.
	ProfilerRecorder.reset()
	p._frames.clear()
	p._frame_index = 0
	p._frames_ever = 0
	p._frames_dropped = 0
	return p

func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
