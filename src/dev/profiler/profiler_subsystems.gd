# res://src/dev/profiler/profiler_subsystems.gd
#
# THE SUBSYSTEM REGISTRY — the single list of everything the profiler claims to
# measure, and where each measurement comes from.
#
# Why this list is data and not a pile of call sites: a profiler that decides at
# runtime what it measured cannot tell you what it did not. Every subsystem is
# declared here up front with an explicit Source, so an unmeasured subsystem is
# a declared property of the instrument rather than a silent gap in a report.
#
# THE RULE THIS FILE ENFORCES. A subsystem with zero samples reports
# `"state": "not_sampled"` and carries NO `"value"` key at all — the key is
# absent, not zero. "Never measured" and "genuinely instant" are
# indistinguishable in a number, and this session already paid for that
# confusion: a gate that passed on zero checks, a check count that printed as
# the string "?", and a harness truncated to 83 of 102 by an unfinished import
# while printing RESULT: PASS. A profiler that reports 0.0 ms for something it
# never looked at is worse than no profiler, because it will be believed.
# Absence is the honest encoding, and it is why "sampled" is decided by a
# sample COUNT rather than by whether the value happens to be non-zero.
#
# The rule is not decoration. `physics_step` — the first thing the card asks for
# — cannot be measured in this engine version, and it is declared not_sampled
# rather than approximated. The first honest report this instrument can produce
# therefore contains gaps on purpose, which is the point.
extends RefCounted
class_name ProfilerSubsystems

## Where a measurement comes from. UNAVAILABLE is a first-class, permanent
## state, not an error: it means this instrument cannot measure that subsystem
## at all, and it will say so in every dump until someone builds a real source.
enum Source {
	ENGINE_MONITOR, ## read from a Performance monitor (engine-owned timing)
	SCOPE, ## accumulated by explicit begin/end calls at the call site
	UNAVAILABLE, ## cannot be measured here; always reported as not_sampled
}

## One declared subsystem.
class Entry extends RefCounted:
	var id: StringName
	var label: String
	var source: Source
	var origin: String
	## For engine monitors whose value is NOT a work time (latency, counts), this
	## names what was actually measured so nobody reads a latency as a duration.
	var metric: String = "time"
	## Why UNAVAILABLE is the truth, in words a reader can act on.
	var reason: String = ""

	func _init(p_id: StringName, p_label: String, p_source: Source, p_origin: String, p_metric: String = "time", p_reason: String = "") -> void:
		id = p_id
		label = p_label
		source = p_source
		origin = p_origin
		metric = p_metric
		reason = p_reason

	## True when this subsystem can ever produce a number.
	func measurable() -> bool:
		return source != Source.UNAVAILABLE

	## The Performance monitor this subsystem reads, or -1 when there is none.
	##
	## Resolved by NAME at runtime through ClassDB rather than written as a hard
	## enum constant. Two reasons, both learned the hard way: a constant that
	## does not exist in this engine version is a PARSE ERROR that fails the whole
	## project's script compilation, i.e. one wrong name takes down every gate;
	## and a name that is wrong at runtime can degrade to a visible "not sampled"
	## instead, which is what this whole instrument is about.
	func monitor_name() -> String:
		match id:
			&"process_total": return "TIME_PROCESS"
			&"physics_process_total": return "TIME_PHYSICS_PROCESS"
			&"audio": return "AUDIO_OUTPUT_LATENCY"
			&"render_draw_calls": return "RENDER_TOTAL_DRAW_CALLS_IN_FRAME"
		return ""

	## Integer value of monitor_name(), or -1 if this engine has no such monitor.
	func monitor() -> int:
		var want := monitor_name()
		if want == "":
			return -1
		var constants := ClassDB.class_get_enum_constants("Performance", "Monitor")
		var idx := constants.find(want)
		return idx

## Everything the card requires, plus the two we can name but cannot measure.
## Order here is the order used in the overlay and in JSON, so the report reads
## like the frame does: engine totals first, then the work inside them.
static func entries() -> Array[Entry]:
	var list: Array[Entry] = []
	# The card asks for "the physics step as a whole". This engine cannot answer
	# that, and the answer must be a gap rather than a plausible number: see
	# physics_step below. physics_process_total is the script half of it, not the
	# same thing, and labelling it as the whole step would be a lie in a field
	# name.
	list.append(new_id(&"physics_step", "physics step (whole)", Source.UNAVAILABLE, "", "time",
		"Godot 4.7 exposes NO monitor for the whole physics step. Verified against all 60 "
		+ "Performance.Monitor constants: TIME_PHYSICS_STEP and TIME_TOTAL do not exist. The nearest "
		+ "real measurement is physics_process_total, which times script _physics_process callbacks "
		+ "only and excludes the physics server, broadphase and solving. Frame-total minus script time "
		+ "would be an inference rather than a measurement, so no number is reported here."))
	list.append(new_id(&"process_total", "_process total (all scripts)", Source.ENGINE_MONITOR, "Performance.TIME_PROCESS"))
	list.append(new_id(&"physics_process_total", "_physics_process total (scripts only)", Source.ENGINE_MONITOR, "Performance.TIME_PHYSICS_PROCESS"))
	list.append(new_id(&"bot_ai", "bot AI update", Source.SCOPE, "src/npcs/bot/bot.gd::_physics_process (after the corpse early-return)"))
	list.append(new_id(&"bot_animation_skeleton", "bot animation + skeleton", Source.SCOPE,
		"src/npcs/bot/bot.gd::_tick_anim + _tick_lod (per-frame). NOT covered: the one-shot rig.play() "
		+ "calls at _ready and on attack, and the player viewmodel rig (addon-owned, see player_rig_anim)."))
	list.append(new_id(&"physics_queries", "physics queries (raycast)", Source.SCOPE,
		"scenes/shot_resolver.gd::resolve intersect_ray only. NOT covered: the direct intersect_ray calls "
		+ "in scenes/arena_manager_gameplay.gd and src/npcs/bot/bot_cover.gd, so treat this as a lower bound."))
	list.append(new_id(&"world_managers", "world managers", Source.SCOPE,
		"scenes/arena_manager_core.gd::_physics_process (after the paused guard) and scenes/raid.gd::tick. "
		+ "wave_spawner.gd and extraction_point.gd are timer/event-driven with no per-tick entry point."))
	list.append(new_id(&"ui_layout", "UI build + HUD refresh (script-side)", Source.SCOPE,
		"scenes/main_menu.gd::_setup_settings, scenes/gunsmith_ui.gd::_build, "
		+ "scenes/arena_manager_core.gd::_refresh_raid_hud. NOT covered: engine-side container layout "
		+ "(that is inside process_total and is not script-scopable) and scenes/operations_hub.gd::_build_ui, "
		+ "whose early returns make a whole-function scope unsafe."))
	# Latency, not work. Named so the distinction survives the JSON.
	list.append(new_id(&"audio", "audio", Source.ENGINE_MONITOR, "Performance.AUDIO_OUTPUT_LATENCY", "output_latency_ms"))
	list.append(new_id(&"render_draw_calls", "render draw calls", Source.ENGINE_MONITOR, "Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME", "count_per_second"))
	# The two we refuse to fake.
	list.append(new_id(&"render_submit", "render submit", Source.UNAVAILABLE, "", "time",
		"Godot 4.7 exposes no render-submit TIME monitor. A frame total minus script time would be an "
		+ "inference, not a measurement, so this instrument deliberately reports no number for it. "
		+ "Wire an engine-level hook or accept it as unmeasured."))
	list.append(new_id(&"player_rig_anim", "player viewmodel anim + IK", Source.UNAVAILABLE, "", "time",
		"Driven inside addons/cabra.lat_shooters, a separate repository that this card does not modify. "
		+ "The game-repo profiler cannot scope calls it does not own, so it reports not_sampled rather "
		+ "than borrowing a number from a different subsystem."))
	return list

## Convenience: `new_id(...)` typed as Entry so the list above stays readable.
static func new_id(id: StringName, label: String, source: Source, origin: String, metric: String = "time", reason: String = "") -> Entry:
	return Entry.new(id, label, source, origin, metric, reason)

## Ids of everything that can never be sampled, by declaration.
static func unmeasurable_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for e in entries():
		if not e.measurable():
			out.append(e.id)
	return out
