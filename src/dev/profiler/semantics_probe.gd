# res://src/dev/profiler/semantics_probe.gd
# res://src/dev/profiler/semantics_probe.gd
#
# Measures whether the engine's Performance monitors are PER-FRAME costs or
# RUNNING TOTALS, under a load whose size is published every frame.
#
# WHY THIS IS A SEPARATE FILE. It began life inline in the profiler gate, which
# pushed that file past the 800-line god-object threshold and turned a correct
# addition into a new MAJOR audit finding. The probe is an instrument, not gate
# logic: it knows how to make a scene do a known amount of work and how to
# record what the engine said. The gate keeps the ASSERTIONS, because a gate
# whose verdicts live in a helper is a gate you cannot read in one place.
#
# WHY GROUND TRUTH MATERS. A capture once showed a physics figure rising from
# 17.8 ms to 3567 ms with almost no decreases, and was read as a cumulative
# clock. Reading a series and guessing what produced it is how that went wrong.
# Here the workload is chosen by the probe and printed, so "did the monitor
# follow the work" has a right answer that does not depend on anyone's patience
# with a graph.
class_name ProfilerSemantics
extends RefCounted

## Rendered frames to sample. Must exceed 4 so a 1x/HIGH alternation completes
## several times: a per-frame cost has to fall on the way back down, and a
## running total cannot fall at all. 15 rather than 9 because the number of
## alternations is what makes the "must fall" assertion robust — at 9 frames
## under the full gate's load the swing was sometimes compressed enough that no
## fall appeared, and a check that only passes when the machine is quiet is a
## flaky check wearing a correctness costume.
const FRAMES := 15
const SPINS := 20000
const LOW := 1
## Large enough that the injected work dominates the project's own per-frame
## cost even on a loaded machine. The first version used 48 and produced a
## visible-but-modest swing; 240 makes the alternation unmistakable rather than
## marginal.
const HIGH := 240

## id -> PackedFloat64Array, as the ENGINE reports it.
var raw := {}
## id -> PackedFloat64Array, as _entry_for() PUBLISHES it. Not the same thing,
## and checking only `raw` is how a cumulative clock ships green: a future
## change that accumulates on the publishing side leaves every engine series
## perfectly healthy.
var published := {}

var frames := 0
var steps := 0

var _ids: Array[StringName] = []
var _mult := LOW
var _profiler: Object = null
var _done := Callable()
var _node: Load = null

## ids: the ENGINE_MONITOR ids to record. profiler: a Profiler instance, used
## only to read what it would publish. done: called with this probe when the run
## ends, from inside a live frame.
func start(root: Node, ids: Array[StringName], profiler: Object, done: Callable) -> void:
	_ids = ids
	_profiler = profiler
	_done = done
	for id in ids:
		raw[id] = PackedFloat64Array()
		published[id] = PackedFloat64Array()
	_node = Load.new()
	_node.probe = self
	root.add_child(_node)

func _on_frame() -> void:
	frames += 1
	# Choose the load for the frame that is about to be simulated.
	_mult = LOW if frames % 2 == 0 else HIGH
	for id in _ids:
		var mon := monitor_of(id)
		if mon == -1:
			continue
		_append(raw, id, float(Performance.get_monitor(mon)))
		if _profiler == null:
			continue
		for e in ProfilerSubsystems.entries():
			if e.id != id:
				continue
			var entry: Dictionary = _profiler._entry_for(e, {})
			if str(entry.get("state", "")) == "sampled":
				_append(published, id, float(entry.get("value", 0.0)))
	if frames >= FRAMES:
		_node.set_process(false)
		_node.set_physics_process(false)
		_done.call(self)

## Packed arrays are VALUE types in GDScript: appending to `raw[id]` mutates a
## temporary and the dictionary never sees it, so every sample is written back.
## Found by the gate going red with 0 samples on its first honest run.
func _append(into: Dictionary, id: StringName, value: float) -> void:
	var acc: PackedFloat64Array = into[id]
	acc.append(value)
	into[id] = acc

static func monitor_of(id: StringName) -> int:
	for e in ProfilerSubsystems.entries():
		if e.id == id:
			return e.monitor()
	return -1

## The cumulative signature: never falls, and grows without bound.
##
## Growth is measured from the first NON-ZERO sample, not from s[0]. A series
## that starts at 0.0 and warms up grows by an unbounded factor, so a ratio test
## against s[0] flags every healthy per-frame duration on its first samples —
## which is exactly what it did, turning a correct instrument red on a real run.
static func looks_cumulative(s: PackedFloat64Array) -> bool:
	if s.size() < 3:
		return false
	if falls(s) > 0:
		return false
	var base := -1.0
	for x in s:
		if x > 0.0:
			base = x
			break
	if base < 0.0:
		return false  # flat at zero is a constant, not a leak
	return s[s.size() - 1] > base * 10.0 + 0.001

static func falls(s: PackedFloat64Array) -> int:
	var n := 0
	for i in range(1, s.size()):
		if s[i] < s[i - 1]:
			n += 1
	return n

static func max_of(s: PackedFloat64Array) -> float:
	var m := 0.0
	for x in s:
		m = max(m, x)
	return m

static func min_nonzero(s: PackedFloat64Array) -> float:
	var m := -1.0
	for x in s:
		if x > 0.0 and (m < 0.0 or x < m):
			m = x
	return m if m > 0.0 else 1.0

## The varying load.
##
## The load is chosen PER FRAME, not per physics step, and that is the whole
## design. Alternating per step, the ~8 physics steps in a frame average each
## other out and the frame's physics total comes out nearly constant — the probe
## then measures a warm-up ramp and learns nothing. Chosen per frame, the total
## genuinely alternates, so the oscillation IS the ground truth and IS the
## discriminator between a per-frame cost and a running total.
class Load extends Node:
	var probe: ProfilerSemantics = null

	func _process(_d: float) -> void:
		if probe != null:
			probe._on_frame()

	func _physics_process(_d: float) -> void:
		var acc := 0
		for i in range(probe._mult * SPINS):
			acc = (acc + i * 31) & 0xFFFF
		probe.steps += 1
		if probe.steps >= 400:
			set_physics_process(false)
