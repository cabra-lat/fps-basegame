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
#   [J] the opt-in shutdown dump: off by default, hooked only when asked, and
#       schema-identical to the F9 path with the not_sampled rule intact
#   [K] the mon == -1 exit of the not-sampled rule: an engine monitor that does
#       not resolve must degrade to a NAMED hole, never to a number
#   [L] every ENGINE_MONITOR id is a PER-FRAME duration, pinned by measurement so
#       a cumulative clock can never be published as a cost again
#
# [J] PROVES THE AFFORDANCE'S CONTRACT, NOT THE ENGINE'S DELIVERY. It calls the
# shutdown handler directly and checks the file it writes. That the engine
# actually delivers root.tree_exiting at process shutdown — and does NOT on a
# scene switch — was measured separately with a real engine in both directions;
# a gate that asserted engine delivery would be asserting something it does not
# control. Stating the boundary is the point of this comment.
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

var _l_probe: ProfilerSemantics = null
var _l_pub: Profiler = null
var v: ValidateUtil
var _deferred = false

func _initialize() -> void:
	v = ValidateUtil.new("profiler")
	v.begin()

	_a_registry()
	_b_not_sampled_rule()
	_c_sampled_is_earned_by_samples()
	_d_unmeasurable_reasons()
	_e_off_by_default()
	_e2_release_is_off()

	# E3 and everything after it need a host that is actually inside the tree:
	# maybe_attach() walks host.get_tree().root, and during _initialize the
	# SceneTree's root Window is not parented yet (measured: `Parameter
	# "data.tree" is null` at profiler.gd:83). Running it here would produce a
	# red arm that is red for the wrong reason — a harness error masquerading as
	# evidence about the accessor — which is worse than no red arm at all.
	_deferred = true

# Runs once the tree is up. Sections [E3]..[I] need a live tree; [A]..[E2] do not.
func _process(_delta: float) -> bool:
	# false, not true, on BOTH exits.
	#
	# Before setup: keep the tree alive.
	# After setup: keep the tree alive so [L]'s probe gets its frames.
	#
	# This guard used to `return true`, which was correct when _process was a
	# one-shot: the sections ran on frame 1, called quit(), done. [L] needs live
	# frames, and `return true` ended the tree on the SECOND frame — the frame
	# after the one-shot had already cleared _deferred — so the probe died part
	# way through with no output, no summary, and rc=0. A gate that ends
	# silently and successfully is the worst failure mode in this file, and it
	# is why the exit code alone is not evidence that a section ran.
	if not _deferred:
		return false
	_deferred = false
	_e3_accessor_published_before_start()
	_f_ring_buffer()
	_g_json_dump()
	_h_instrumentation_faults()
	_i_overlay()
	_j_dump_on_exit()
	_k_monitor_miss_is_a_hole()
	# [L] needs live frames, and this is the FIRST section in the file that does.
	# It is driven by a CALLBACK, not by await, and that is not a style choice:
	# a function containing `await` is a coroutine, and under `--script` on a
	# SceneTree the engine discards an unawaited coroutine — so calling it
	# without `await` runs a third of the section AFTER RESULT: PASS has already
	# been printed, and awaiting it instead suspends _initialize() so the tree
	# never reaches quit(). Both were tried; both lie. The callback keeps the
	# main loop driving, samples every frame, and runs the assertions BEFORE
	# finish(), which is the only ordering that is actually true.
	_l_start()
	# false, not true: _finish_gate() is what ends the run, once the probe has
	# its frames. Returning true here would stop the tree on the first frame and
	# the probe would never be sampled.
	return false

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

# [E3] THE STATIC ACCESSOR MUST BE USABLE THE MOMENT ATTACH RETURNS.
#
# Red arm, and the order matters: every assertion here is made BEFORE start() has
# run. If the only green state of this check were "after start()", the fix would
# not have been shown to fix anything, because that is the state the instrument
# was already in.
#
# Why it matters: maybe_attach() is the public entry point and the instrument's
# documented primary consumer is a capture harness running OUTSIDE the scene,
# whose only supported route to the instrument is the static accessor. A null
# returned there does not mean "not opted in" — it means "attached, but you
# cannot see it yet", which is a null that means something other than what it
# appears to mean.
func _e3_accessor_published_before_start() -> void:
	v.section("[E3] accessor published by attach, not by start")
	# Scope the opt-in to this section: the rest of the gate asserts the OFF
	# path, and a globally opted-in run would invalidate those.
	OS.set_environment("FPS_PROFILE", "1")
	var attached: Profiler = Profiler.maybe_attach(root)
	var accessor: Profiler = Profiler.instance
	var recording_had_started: bool = ProfilerRecorder.enabled

	v.check(attached != null, "opted in, maybe_attach() hands back the profiler")
	v.check(accessor != null,
		"Profiler.instance is ALREADY non-null before start() ran — a null here would say 'not started' while meaning 'not reachable'")
	v.check(attached != null and accessor == attached,
		"the accessor returns the SAME profiler maybe_attach() returned, not a second one")
	v.check(not recording_had_started,
		"and this really is BEFORE start(): recording has not begun (so the accessor is not just observing a started profiler)")

	# Put the world back exactly as it was: the opt-in off, no stray instance,
	# no leaked node. Later sections assert the off path.
	OS.set_environment("FPS_PROFILE", "")
	Profiler.instance = null
	ProfilerRecorder.enabled = false
	if attached != null and is_instance_valid(attached):
		attached.queue_free()
	v.check(Profiler.should_run() == false, "the opt-in is restored, so the off path still holds after this section")

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

## [J] The opt-in shutdown dump.
##
## The bug this closes: maybe_attach() is documented as the entry point for a
## consumer running OUTSIDE the scene, and that consumer had no supported way to
## ask for a dump at all — the single F9 keystroke assumed a human at a
## keyboard. So the instrument was unusable for its own stated primary consumer,
## which is the same shape as the accessor that used to return null.
func _j_dump_on_exit() -> void:
	var saved_env := OS.get_environment(Profiler.ENV_DUMP_ON_EXIT)
	var saved_optin := OS.get_environment("FPS_PROFILE")
	var dir_path := "%s/j" % OUT
	DirAccess.make_dir_recursive_absolute(dir_path)

	# ── the env var's meaning ────────────────────────────────────────────────
	OS.set_environment(Profiler.ENV_DUMP_ON_EXIT, "")
	v.check(not Profiler.dump_on_exit_requested(), "with the env var absent, a shutdown dump is not requested")
	OS.set_environment(Profiler.ENV_DUMP_ON_EXIT, "1")
	v.check(Profiler.dump_on_exit_requested(), "with the env var set to 1, a shutdown dump is requested")
	OS.set_environment(Profiler.ENV_DUMP_ON_EXIT, "0")
	v.check(not Profiler.dump_on_exit_requested(), "any other value is not a request (not '0 means on')")

	# It is not an opt-IN: it says WHEN to dump, not whether the instrument exists.
	# Asking only for a shutdown dump must not bring up a profiler nobody asked to
	# profile — otherwise the affordance is a second way to switch the instrument
	# on, which is the one thing an opt-in must not be.
	_reset_instrument()
	OS.set_environment("FPS_PROFILE", "")
	v.check(Profiler.maybe_attach(root) == null,
		"the dump env var alone does NOT opt in — it is not a second way to switch the instrument on")
	_reset_instrument()

	# ── the hook ─────────────────────────────────────────────────────────────
	# Built in-tree on purpose. maybe_attach() adds its node DEFERRED, so a
	# profiler it returns is not inside the tree yet and get_tree() is null — the
	# hook correctly declines to install there and _ready() installs it a frame
	# later. Asserting the connection on that node would be asserting something
	# about the deferred add, not about the hook.
	var quiet: Profiler = Profiler.new()
	quiet.name = "ProfilerQuiet"
	root.add_child(quiet)
	OS.set_environment(Profiler.ENV_DUMP_ON_EXIT, "")
	quiet._install_exit_hook()
	v.check(not root.tree_exiting.is_connected(quiet._on_tree_exiting),
		"with the env var absent, NOTHING is connected to the shutdown signal")
	quiet.queue_free()

	OS.set_environment(Profiler.ENV_DUMP_ON_EXIT, "1")
	OS.set_environment("FPS_PROFILE", "1")
	var p: Profiler = Profiler.new()
	p.name = "ProfilerExitDump"
	root.add_child(p)
	p._install_exit_hook()
	v.check(root.tree_exiting.is_connected(p._on_tree_exiting),
		"with the env var set, the shutdown signal is connected")
	p._install_exit_hook()
	var conns := root.tree_exiting.get_connections().filter(func(c): return c["callable"] == p._on_tree_exiting)
	v.check(conns.size() == 1, "installing twice does not double-connect (a shutdown would dump twice)")

	# ── the dump it writes ───────────────────────────────────────────────────
	# Give it frames with samples, so this is a real dump rather than a shell of
	# not_sampled entries — an all-not_sampled dump would pass a shape check while
	# proving nothing about the numbers.
	p.start()
	for i in 3:
		ProfilerRecorder.begin(&"bot_ai")
		ProfilerRecorder.end()
		p.record_frame()

	# The reference goes through dump_json() — literally the function the F9
	# branch calls — so "schema identical" is a comparison against the real thing
	# rather than against a description of it.
	var ref_path := "%s/j_f9_reference.json" % dir_path
	if FileAccess.file_exists(ref_path):
		DirAccess.remove_absolute(ref_path)
	p.dump_json(ref_path)
	var report := p._on_tree_exiting()

	v.check(report.get("ok") != null, "the shutdown handler returns its report, so a consumer learns where the dump went")
	var exit_path := String(report.get("path", ""))
	v.check(FileAccess.file_exists(exit_path), "the shutdown handler wrote a file (path=%s)" % exit_path)
	var ref := _read_json(ref_path)
	var auto := _read_json(exit_path)
	v.check(ref.get("schema") == Profiler.SCHEMA, "the F9-path reference dump parses as %s (got %s)" % [Profiler.SCHEMA, str(ref.get("schema"))])
	v.check(auto.get("schema") == Profiler.SCHEMA, "the shutdown dump parses as %s (got %s)" % [Profiler.SCHEMA, str(auto.get("schema"))])
	if not auto.is_empty() and not ref.is_empty():
		var ref_keys: Array = (ref.keys() as Array).map(func(k): return String(k))
		var auto_keys: Array = (auto.keys() as Array).map(func(k): return String(k))
		ref_keys.sort()
		auto_keys.sort()
		v.check(auto_keys == ref_keys, "the shutdown dump has the SAME top-level keys as the F9 path (auto=%s ref=%s)" % [str(auto_keys), str(ref_keys)])

		# THE NON-NEGOTIABLE, re-asserted on the file this affordance writes, and
		# on BOTH places a value could leak: the aggregate (built by aggregate())
		# and the per-frame records (built by _entry_for()). Checking only the
		# aggregate would have missed a leak in the frame records — which is what
		# happened when this check was first written and then sabotaged.
		var leaked: Array = []
		for e in (auto.get("totals", {}) as Dictionary).values():
			if (e as Dictionary).get("state") == "not_sampled" and (e as Dictionary).has("value"):
				leaked.append("totals")
		for fr in (auto.get("frames", []) as Array):
			for e in ((fr as Dictionary).get("subsystems", {}) as Dictionary).values():
				if (e as Dictionary).get("state") == "not_sampled" and (e as Dictionary).has("value"):
					leaked.append("frames")
		v.check(leaked.is_empty(), "the shutdown dump leaks NO value next to a never-measured subsystem (leaked in: %s)" % (", ".join(leaked) if leaked.size() else "none"))
		v.check((auto.get("not_sampled", []) as Array).size() > 0,
			"the shutdown dump still reports not_sampled rather than defaulting to numbers")
		var sampled: int = 0
		for e in (auto.get("totals", {}) as Dictionary).values():
			if (e as Dictionary).get("state") == "sampled":
				sampled += 1
		v.check(sampled > 0, "and it is a real dump: at least one subsystem is genuinely sampled (sampled=%d)" % sampled)
		v.check((auto.get("ring", {}) as Dictionary).get("frames_retained", 0) > 0,
			"the dump carries the frames that were recorded, so shutdown did not lose the window")

	OS.set_environment(Profiler.ENV_DUMP_ON_EXIT, saved_env)
	OS.set_environment("FPS_PROFILE", saved_optin)
	_reset_instrument()
	if is_instance_valid(p):
		p.queue_free()
	if is_instance_valid(quiet):
		quiet.queue_free()
## [K] The mon == -1 exit of the not-sampled rule.
##
## QA found this by breaking the branch and observing that the gate still
## reported the same count and PASS. The rule was correct on that exit and
## nothing reached it — the fourth hole tonight of the shape "no assertion
## reaches it". It is reachable in production for a reason that is not
## hypothetical: monitor names are resolved by NAME through ClassDB at runtime
## precisely so that a rename or removal in a future engine degrades to a
## visible "not sampled" instead of a parse error. If that degradation is the
## designed behaviour, the behaviour needs a test.
##
## Both directions are asserted, because asserting only the not_sampled side
## would pass just as happily if _entry_for() returned not_sampled for
## everything.
func _k_monitor_miss_is_a_hole() -> void:
	_reset_instrument()
	# Plain construction, never attached: [K] is about _entry_for()'s return value
	# and needs no SceneTree, no opt-in and no accumulated state, so this section
	# cannot be affected by how the profiler was brought up.
	var p: Profiler = Profiler.new()
	_k_missing_monitor_is_a_hole(p)
	_k_resolvable_monitor_still_samples(p)
	_reset_instrument()

## The hole side of [K], split from its sibling so that neither half is a
## 79-line function — the size at which a reader stops checking a test against
## the thing it claims to test.
func _k_missing_monitor_is_a_hole(p: Profiler) -> void:
	# A monitor name this engine does not have. Any id outside monitor_name()'s
	# match list resolves to "", and "" to -1, which is the branch under test.
	var missing := ProfilerSubsystems.Entry.new(
		&"no_such_monitor", "a monitor this engine does not have",
		ProfilerSubsystems.Source.ENGINE_MONITOR, "Performance.TIME_NOT_A_REAL_MONITOR")
	v.check(missing.monitor_name() == "" and missing.monitor() == -1,
		"precondition: an unresolvable monitor name yields -1, so this exercises the real branch (name='%s')" % missing.monitor_name())

	var e := p._entry_for(missing, {})
	v.check(e.get("state") == "not_sampled",
		"an engine monitor that does not resolve reports not_sampled (got '%s')" % str(e.get("state")))
	v.check(not e.has("value"),
		"and carries NO value key — a missing monitor is a hole, not a 0.0 (keys: %s)" % str(e.keys()))
	v.check(not e.has("mean"), "and no mean either, which is how a zero would arrive wearing a hat")
	v.check(String(e.get("reason", "")).contains("no_such_monitor"),
		"and the reason NAMES the subsystem, so the hole says which hole it is (reason: %s)" % str(e.get("reason")))

## The other direction: an id that DOES resolve must still produce a number.
## Without this, the checks in _k_missing_monitor_is_a_hole would be satisfied by
## a _entry_for() that reports not_sampled unconditionally.
func _k_resolvable_monitor_still_samples(p: Profiler) -> void:
	var real_id := &"process_total"
	var real_entry: ProfilerSubsystems.Entry = null
	for x in ProfilerSubsystems.entries():
		if x.id == real_id:
			real_entry = x
			break
	v.check(real_entry != null, "the registry still contains a resolvable engine-monitor id")
	if real_entry == null:
		return
	v.check(real_entry.monitor() != -1, "and it resolves in THIS engine (%s)" % real_entry.monitor_name())
	var r := p._entry_for(real_entry, {})
	v.check(r.get("state") == "sampled",
		"a resolvable monitor still reports sampled (got '%s')" % str(r.get("state")))
	v.check(r.has("value") and typeof(r["value"]) in [TYPE_FLOAT, TYPE_INT],
		"with a numeric value, so [K] is not satisfied by blanket not_sampled")

## [L] Every ENGINE_MONITOR id is a per-frame duration, and the profiler
## publishes it as one.
##
## A capture read physics_process_total as 17.8 ms early and 3567 ms late with
## almost no decreases, and was diagnosed as a cumulative clock published as a
## per-frame cost. The proposed fix was to demote the entry to a hole. That
## diagnosis was wrong, and the way to stop it being re-derived is to MEASURE
## the semantics in the gate rather than argue about them in review.
##
## The measuring is done by ProfilerSemantics (src/dev/profiler/
## semantics_probe.gd) because it is an instrument, not a verdict. The verdicts
## stay here, in one place, where a reviewer can read what is and is not claimed.
func _l_start() -> void:
	# The detector is pinned FIRST, on data where the answer is not in doubt. A
	# "nothing looks wrong" assertion is satisfied by a detector that never
	# fires, so the detector is itself under test before it is trusted.
	#
	# ⚠️ THESE THREE ARE LOAD-BEARING. DO NOT DELETE THEM AS REDUNDANCY.
	#
	# Measured, not assumed: neutering ProfilerSemantics.falls() to `return 1`
	# takes the gate from 120/0 PASS to 119/1 FAIL — and the ONE failure is the
	# first check below, NOT the live measurement in _l_report(). Because a
	# neutered falls() returns 1, the live assertion `swings >= 1` is trivially
	# satisfied and passes. So the live checks CANNOT detect their own neutering;
	# only these synthetic series can, because the answer is known in advance.
	#
	# That is not a redundancy to be tidied away. It looks like one — three
	# checks on hardcoded arrays, sitting next to a real measurement that
	# arguably covers the same ground — and the next person to clean that up
	# will delete them and leave the live checks unfalsifiable. If these are ever
	# removed, the claim "a cumulative clock can never be published as a cost"
	# stops being tested, silently, and the gate keeps reporting green.
	v.check(ProfilerSemantics.looks_cumulative(PackedFloat64Array([1.0, 2.0, 3.0, 10.0, 40.0, 400.0])),
		"[L] detector: a series that only rises, fast, is recognised as a running total")
	v.check(not ProfilerSemantics.looks_cumulative(PackedFloat64Array([10.0, 3.0, 11.0, 2.0, 9.0, 4.0])),
		"[L] detector: a series that rises and falls is not")
	v.check(not ProfilerSemantics.looks_cumulative(PackedFloat64Array([5.0, 5.0, 5.0, 5.0])),
		"[L] detector: a flat series is not — 0 draw calls headless is not a leak")

	var ids: Array[StringName] = []
	for e in ProfilerSubsystems.entries():
		if e.source == ProfilerSubsystems.Source.ENGINE_MONITOR:
			ids.append(e.id)
	v.check(ids.size() >= 3,
		"precondition: there are engine-monitor ids to check (found %d)" % ids.size())
	if ids.is_empty():
		_finish_gate()
		return
	_l_probe = ProfilerSemantics.new()
	_l_pub = Profiler.new()
	_l_probe.start(root, ids, _l_pub, _l_report)
	# Deliberately no finish()/quit() here: this returns to _process, which
	# returns to the engine, and the tree keeps iterating until the probe calls
	# back into _l_report().

func _l_report(probe: ProfilerSemantics) -> void:
	v.check(probe.frames >= 2,
		"the probe ran live frames rather than exiting at once (%d)" % probe.frames)
	for id in probe.raw.keys():
		_l_check_series("engine monitor '%s'" % id, probe.raw[id], false)
	for id in probe.published.keys():
		_l_check_series("published '%s'" % id, probe.published[id], true)

	# The positive form, which is the assertion that can actually CATCH a running
	# total rather than merely fail to notice one. The probe alternates the
	# physics load 1x / 48x once per FRAME, so a monitor reporting a per-frame
	# cost has to fall on the way back down; a running total physically cannot.
	# This distinguishes the two behaviours rather than merely noticing that a
	# number changed — a test that only asserted "not the old value" would pass
	# just as happily on a different wrong number.
	#
	# The 1.25 below is deliberately low, and the reason is worth keeping next to
	# it. It is not asserting that the swing is dramatic — it is asserting only
	# that the series is NOT CONSTANT, so that the fall above is signal rather
	# than jitter. The load itself is what carries the weight: at 1x/240x the
	# measured swing is roughly 7x (e.g. 867 ms against 114 ms), so the check is
	# not balanced on a knife edge. An earlier version injected 48x, which showed
	# only ~1.8x, and under the full gate's load that compressed far enough to
	# produce zero falls in 9 samples — a red arm for the wrong reason, on
	# correct code. Fixing it by raising the injected load rather than by
	# lowering the bar is the whole point.
	var pp: PackedFloat64Array = probe.published.get(&"physics_process_total", PackedFloat64Array())
	if pp.size() >= 4:
		var swings := ProfilerSemantics.falls(pp)
		# This assertion has teeth of its own, and that was measured rather than
		# assumed: making the PUBLISHER accumulate — with falls() and the
		# detector self-checks left completely untouched, verified by checksum —
		# drives this to 0 falls and reds it, alongside the cumulative-signature
		# check, with all three self-checks still green. 120/0 -> 118/2.
		#
		# The converse is the trap: neutering falls() does NOT red this line,
		# because returning 1 satisfies it. See the warning in _l_start().
		v.check(swings >= 1,
			"under a 1x/240x per-frame load swing, the published physics cost FALLS at least once (%d falls in %d samples) — a running total could not"
				% [swings, pp.size()])
		v.check(ProfilerSemantics.max_of(pp) > ProfilerSemantics.min_nonzero(pp) * 1.25,
			"and the swing is actually visible in the data, so the fall above is not noise (max=%.4f, smallest non-zero=%.4f)"
				% [ProfilerSemantics.max_of(pp), ProfilerSemantics.min_nonzero(pp)])
	_finish_gate()

func _l_check_series(what: String, s: PackedFloat64Array, is_published: bool) -> void:
	var tail := "" if s.size() < 2 else ", first=%.4f last=%.4f" % [s[0], s[s.size() - 1]]
	v.check(s.size() >= 2, "%s was sampled more than once (%d samples)" % [what, s.size()])
	if s.size() < 2:
		return
	var n := ProfilerSemantics.falls(s)
	var claim := "a running total presented as a per-frame cost" if is_published \
		else "a running total published as a cost"
	v.check(not ProfilerSemantics.looks_cumulative(s),
		"%s is not %s (%d samples, %d falls%s)" % [what, claim, s.size(), n, tail])

## The one place the gate is allowed to end, so a section that needs live frames
## and one that does not cannot disagree about who prints the summary.
func _finish_gate() -> void:
	v.finish()
	quit(v.failed)
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
