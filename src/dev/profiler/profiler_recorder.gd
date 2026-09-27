# res://src/dev/profiler/profiler_recorder.gd
#
# THE SCOPE API — the cheapest thing that can be called from hot code.
#
# Contract for call sites: two lines around the work, and nothing else changes.
#   ProfilerRecorder.begin(&"bot_ai")
#   ... the code that used to run here, unchanged ...
#   ProfilerRecorder.end()
#
# Cost when the profiler is OFF (the default, including every release export):
# `begin` and `end` each return on the first `if not enabled` test. No
# allocation, no dictionary lookup, no node. That is the whole reason the
# enabled flag lives in a static rather than being read off a node — a call site
# must not have to find the profiler to find out whether to do nothing.
#
# Cost when ON: a push/pop of a two-element Array per scope. Allocation-free
# enough to be honest about, and deliberately not clever: this measures the
# game, it does not get optimised.
#
# Nesting is supported (bot_ai contains bot_animation_skeleton) and UNBALANCED
# calls are counted, not swallowed. An unbalanced `end` is an instrumentation
# bug, and an instrumentation bug that silently distorts a frame total is the
# failure mode this whole card is about, so it surfaces in the dump.
class_name ProfilerRecorder
extends RefCounted

## Mirrors the profiler's enabled state. Set by Profiler, read by call sites.
static var enabled: bool = false

## [subsystem] -> accumulated microseconds for the frame being recorded.
static var _usec: Dictionary = {}
## [subsystem] -> number of completed samples in the frame being recorded.
static var _samples: Dictionary = {}
## Stack of [StringName, int start_usec].
static var _stack: Array = []
## Instrumentation faults, surfaced in every dump. Should always be 0.
static var unbalanced_calls: int = 0
static var unknown_subsystems: int = 0

## Known ids, so a typo in a scope name is caught instead of inventing a new
## row in the report that nobody declared.
static var _known: Dictionary = {}

static func _ensure_known() -> void:
	if not _known.is_empty():
		return
	for e in ProfilerSubsystems.entries():
		_known[e.id] = true

## True when `subsystem` is declared in the registry.
static func is_declared(subsystem: StringName) -> bool:
	_ensure_known()
	return _known.has(subsystem)

static func begin(subsystem: StringName) -> void:
	if not enabled:
		return
	_ensure_known()
	if not _known.has(subsystem):
		# A scope on an undeclared id would create a row nobody reviewed. Count
		# it, keep the timing (it may still be useful), and let the dump show it.
		unknown_subsystems += 1
	_stack.push_back([subsystem, Time.get_ticks_usec()])

static func end() -> void:
	if not enabled:
		return
	if _stack.is_empty():
		unbalanced_calls += 1
		return
	var top: Array = _stack.pop_back()
	var elapsed: int = Time.get_ticks_usec() - int(top[1])
	_usec[top[0]] = int(_usec.get(top[0], 0)) + elapsed
	_samples[top[0]] = int(_samples.get(top[0], 0)) + 1

## Call once per frame, after every scope has closed. Drops the accumulators
## into the profiler's ring buffer and starts the next frame clean.
static func drain() -> Dictionary:
	# Anything still open at frame end is an unbalanced scope, not a fast frame.
	if not _stack.is_empty():
		unbalanced_calls += _stack.size()
		_stack.clear()
	var out := {"usec": _usec.duplicate(), "samples": _samples.duplicate()}
	_usec = {}
	_samples = {}
	return out

## Wipes all recording state. Used by the headless gate between cases.
static func reset() -> void:
	_usec = {}
	_samples = {}
	_stack = []
	unbalanced_calls = 0
	unknown_subsystems = 0
