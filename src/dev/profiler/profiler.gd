# res://src/dev/profiler/profiler.gd
#
# THE INSTRUMENT — opt-in, additive, per-subsystem frame timing with a ring
# buffer, a JSON dump and a hotkey overlay.
#
# OFF BY DEFAULT, STRUCTURALLY. Nothing here is an autoload and nothing is
# registered in project.godot. A call site only ever touches
# `ProfilerRecorder`, which is inert until a Profiler node exists, and a
# Profiler node is only created when a scene asks for one AND the opt-in is
# present. A plain release export has no opt-in, so it has no profiler, no
# overlay, no hotkeys and no per-frame work at all. Turning it on changes what
# the game does by adding time and nothing else.
#
# MEASURED VALUES ARE ABOUT THE PREVIOUS FRAME. Godot's Performance monitors
# report the frame that just finished, so a frame record assembled during frame N
# describes frame N-1. That is stated here so nobody reads it as an off-by-one
# bug; scope timings are the exception, since they are drained in the frame they
# were taken in.
#
# A NOTE ON UNITS. Time-based subsystems report "unit": "ms". Two of the engine
# monitors do not measure time at all — audio reports output latency and render
# reports a draw-call count — so they carry their own "unit" and the registry
# names the metric. Forcing everything into "ms" would have made those two lie
# by formatting, which is the same class of error as reporting an unmeasured
# subsystem as 0.0.
class_name Profiler
extends CanvasLayer

## Above the game UI, below nothing: this is a developer overlay and it should
## never be hidden by the thing it is measuring.
const LAYER := 100
const RING_DEFAULT := 300 ## frames kept (5s at 60fps, 10s at 30fps)
const SCHEMA := "fps-basegame.profiler/1"
const HOTKEY_OVERLAY := KEY_F8
const HOTKEY_DUMP := KEY_F9
const DUMP_DIR := "user://profiler"

## Frames retained, oldest dropped.
var ring_capacity: int = RING_DEFAULT
## Newest frames first is friendlier to read, but oldest-first keeps `frames[0]`
## meaning "oldest retained" and makes the array self-evidently a window.
var _frames: Array = []
var _frame_index: int = 0
var _frames_ever: int = 0
var _frames_dropped: int = 0

var overlay: ProfilerOverlay = null
var _overlay_visible: bool = true
var _last_dump: String = ""

static var instance: Profiler = null

# ─── OPT-IN ────────────────────────────────────────────────────────────────

## True when someone explicitly asked for the profiler. Deliberately narrow:
## a flag, an env var, or the `profiler` custom feature on an export preset.
static func opt_in_requested() -> bool:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a == "--profile" or a == "--profiler":
			return true
	return OS.get_environment("FPS_PROFILE") == "1"

## A release export that did not ask for the `profiler` custom feature is off,
## even if FPS_PROFILE leaked into its environment. An opt-in that cannot
## distinguish "someone asked" from "something inherited an env var" is not an
## opt-in for release builds.
static func release_blocks() -> bool:
	return OS.has_feature("release") and not OS.has_feature("profiler")

static func should_run() -> bool:
	return opt_in_requested() and not release_blocks()

## Creates the profiler if the opt-in is present. Returns null otherwise, so a
## call site can write `Profiler.maybe_attach(self)` and forget about it.
static func maybe_attach(host: Node, capacity: int = RING_DEFAULT) -> Profiler:
	if not should_run():
		return null
	if instance != null and is_instance_valid(instance):
		return instance
	var p := Profiler.new()
	p.ring_capacity = capacity
	p.name = "Profiler"
	host.get_tree().root.call_deferred("add_child", p)
	return p

# ─── LIFECYCLE ─────────────────────────────────────────────────────────────

## Enables recording and builds the overlay. Called by _ready, and callable
## directly on purpose: inside a headless SceneTree script, `add_child` during
## `_initialize` does NOT enter the tree (measured: `is_inside_tree()` is false
## immediately after add_child in a `--script` run), so _ready never fires there
## and a profiler built that way would silently record nothing.
func start() -> void:
	layer = LAYER
	instance = self
	ProfilerRecorder.enabled = true
	ProfilerRecorder.reset()
	if overlay == null:
		overlay = ProfilerOverlay.new()
		overlay.name = "ProfilerOverlay"
		add_child(overlay)

func _ready() -> void:
	start()

func _exit_tree() -> void:
	ProfilerRecorder.enabled = false
	if instance == self:
		instance = null

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		HOTKEY_OVERLAY:
			_overlay_visible = not _overlay_visible
			overlay.visible = _overlay_visible
		HOTKEY_DUMP:
			var report := dump_json()
			print("[profiler] JSON dump -> %s (%s)" % [report["path"], "ok" if report["ok"] else "INCOMPLETE: " + report["reason"]])

# ─── RECORDING ─────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	record_frame()

## Builds one frame record. Split out from _process so the headless gate can
## drive it deterministically without a SceneTree callback.
func record_frame() -> Dictionary:
	var scopes: Dictionary = ProfilerRecorder.drain()
	var frame: Dictionary = {"frame": _frame_index, "at_usec": Time.get_ticks_usec(), "subsystems": {}}
	frame["fps"] = Engine.get_frames_per_second()
	for e in ProfilerSubsystems.entries():
		frame["subsystems"][e.id] = _entry_for(e, scopes)
	_frame_index += 1
	_frames_ever += 1
	_frames.push_back(frame)
	while _frames.size() > ring_capacity:
		_frames.pop_front()
		_frames_dropped += 1
	if overlay != null:
		overlay.show_frame(frame)
	return frame

## The rule, in one function: no samples means no value, ever.
func _entry_for(entry: ProfilerSubsystems.Entry, scopes: Dictionary) -> Dictionary:
	if entry.source == ProfilerSubsystems.Source.UNAVAILABLE:
		return {"state": "not_sampled", "reason": entry.reason, "samples": 0}
	if entry.source == ProfilerSubsystems.Source.ENGINE_MONITOR:
		var mon := entry.monitor()
		if mon == -1:
			return {"state": "not_sampled", "reason": "registry declares no monitor for this id", "samples": 0}
		var raw: float = float(Performance.get_monitor(mon))
		# Engine monitors are seconds; counts and latencies keep their own unit.
		var value := raw if entry.metric != "time" else raw * 1000.0
		return {"state": "sampled", "value": value, "unit": entry.metric, "samples": 1}
	var samples: int = int((scopes["samples"] as Dictionary).get(entry.id, 0))
	if samples == 0:
		return {"state": "not_sampled", "reason": "no scope call in this frame", "samples": 0}
	var usec: int = int((scopes["usec"] as Dictionary).get(entry.id, 0))
	return {"state": "sampled", "value": float(usec) / 1000.0, "unit": "ms", "samples": samples}

# ─── AGGREGATE + DUMP ──────────────────────────────────────────────────────

## Aggregates a window of frames. Returns { id: entry }, where each entry obeys
## the same rule: aggregated zero samples -> "not_sampled" with NO "value".
func aggregate(window: int = -1) -> Dictionary:
	var frames := _window(window)
	var out := {}
	for e in ProfilerSubsystems.entries():
		if not e.measurable():
			out[e.id] = {"state": "not_sampled", "reason": e.reason, "samples": 0}
			continue
		var total_samples := 0
		var total_value := 0.0
		for f in frames:
			var s: Dictionary = (f["subsystems"] as Dictionary)[e.id]
			if s.get("state") == "sampled":
				total_samples += int(s["samples"])
				total_value += float(s["value"])
		if total_samples == 0:
			# The loud part: say how much was inspected, so "not sampled" is a
			# statement about a window rather than a shrug.
			out[e.id] = {"state": "not_sampled", "reason": "0 samples across %d recorded frame(s)" % frames.size(), "samples": 0}
		else:
			out[e.id] = {
				"state": "sampled",
				"value": total_value,
				"unit": e.metric,
				"samples": total_samples,
				"mean": total_value / float(total_samples),
			}
	return out

func _window(window: int) -> Array:
	if window <= 0 or window >= _frames.size():
		return _frames.duplicate()
	return _frames.slice(_frames.size() - window)

## Writes the dump. `strict` turns "something measurable was not measured" into a
## failure verdict instead of a note — that is the mode the CI gate uses, so a
## report that quietly omits a subsystem cannot pass review.
##
## TWO KINDS OF GAP, and keeping them apart is the difference between a useful
## flag and a permanently-red one. `unmeasurable` is the declared-impossible set
## (no engine monitor, or owned by another repo); it is listed in every dump and
## never goes away, so if it counted against `complete` then `complete` would be
## false forever and every reader would learn to ignore it. `measurable_gaps` is
## what `complete` and `strict` actually mean: something this instrument COULD
## have measured and did not. That is the fault worth failing on.
## Returns {ok, path, not_sampled, measurable_gaps, complete, reason}.
func dump_json(path: String = "", window: int = -1, strict: bool = false) -> Dictionary:
	var totals := aggregate(window)
	var unmeasurable := []
	for id in ProfilerSubsystems.unmeasurable_ids():
		unmeasurable.append(String(id))
	var not_sampled: Array = []
	var measurable_gaps: Array = []
	for e in ProfilerSubsystems.entries():
		if (totals[e.id] as Dictionary).get("state") == "not_sampled":
			not_sampled.append(String(e.id))
			if e.measurable():
				measurable_gaps.append(String(e.id))
	var complete := measurable_gaps.is_empty()
	var target := path
	if target == "":
		target = "%s/profile_%d.json" % [DUMP_DIR, Time.get_ticks_usec()]
	# Always ensure the parent exists, not only for the default path: the gate
	# passes an explicit user:// path, and a dump that cannot be written is a
	# silent failure that looks exactly like a passing one.
	var dir := target.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var doc := {
		"schema": SCHEMA,
		"generated_utc": Time.get_datetime_string_from_system(true, true),
		# complete == nothing measurable was skipped. NOT "this engine can
		# measure everything": see the unmeasurable list below.
		"complete": complete,
		"not_sampled": not_sampled,
		"measurable_gaps": measurable_gaps,
		"unmeasurable": unmeasurable,
		"not_sampled_reasons": _reasons(totals),
		"ring": {
			"capacity": ring_capacity,
			"frames_recorded": _frames_ever,
			"frames_retained": _frames.size(),
			"frames_dropped": _frames_dropped,
			"window_frames": _window(window).size(),
		},
		"instrumentation": {
			"unbalanced_scope_calls": ProfilerRecorder.unbalanced_calls,
			"unknown_subsystems": ProfilerRecorder.unknown_subsystems,
		},
		"totals": totals,
		"frames": _window(window),
	}
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "path": target, "not_sampled": not_sampled, "measurable_gaps": measurable_gaps, "complete": complete, "reason": "cannot write %s" % target}
	f.store_string(JSON.stringify(doc, "  "))
	f.close()
	_last_dump = target
	var reason := ""
	var ok := true
	if not complete:
		reason = "%d measurable subsystem(s) not sampled: %s" % [measurable_gaps.size(), ", ".join(measurable_gaps)]
		if strict:
			ok = false
	if not ok:
		# Loud on purpose. A dump that failed a strict check still gets written,
		# so a human can see exactly which subsystem is missing.
		push_error("[profiler] INCOMPLETE DUMP: %s" % reason)
	return {"ok": ok, "path": target, "not_sampled": not_sampled, "measurable_gaps": measurable_gaps, "complete": complete, "reason": reason}

func _reasons(totals: Dictionary) -> Dictionary:
	var out := {}
	for e in ProfilerSubsystems.entries():
		var s: Dictionary = totals[e.id]
		if s.get("state") == "not_sampled":
			out[e.id] = s.get("reason", "")
	return out

## For tests and the overlay: the most recent frame, or {} if none.
func last_frame() -> Dictionary:
	return _frames.back() if not _frames.is_empty() else {}

func frame_count() -> int:
	return _frames.size()
