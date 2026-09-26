# res://src/dev/profiler/profiler_overlay.gd
#
# THE OVERLAY — a human watching a real playthrough. Toggle with F8.
#
# One rule inherited from the data model, enforced here in pixels: a subsystem
# with no samples prints the WORDS "not sampled", in a colour that cannot be
# mistaken for a measurement, and never prints a number in the value column. An
# overlay that rendered "0.00" for a subsystem it never looked at would look
# exactly like a fast subsystem, and that is the whole failure this card exists
# to prevent. The value column is left blank, not filled with a zero.
class_name ProfilerOverlay
extends Control

const MARGIN := 8.0
const ROW_H := 16.0
const COL_LABEL := 250.0
const COL_STATE := 108.0
const COL_VALUE := 96.0
const BG := Color(0.05, 0.05, 0.07, 0.82)
const FG := Color(0.88, 0.90, 0.94)
const DIM := Color(0.62, 0.65, 0.72)
const OK := Color(0.55, 0.85, 0.55)
## Deliberately not grey and not green: unmeasured must not read as "fine".
const NOT_SAMPLED := Color(0.98, 0.62, 0.25)
const HEADER := Color(0.95, 0.85, 0.45)

var _frame: Dictionary = {}
var _font: Font = null
var _font_size: int = 13

func _init() -> void:
	# Never eat a click, and set it here rather than in _ready: a Control whose
	# _ready has not run (an unentered tree, a headless gate) must still not
	# intercept input, because "harmless until it is added" is how a debug
	# overlay ends up eating a click in the one place nobody tested.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(MARGIN, MARGIN)
	size = Vector2(COL_LABEL + COL_STATE + COL_VALUE + MARGIN * 2, 420)

func show_frame(frame: Dictionary) -> void:
	_frame = frame
	queue_redraw()

func _draw() -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	var rows: int = ProfilerSubsystems.entries().size()
	var h := MARGIN * 2 + ROW_H * (rows + 3)
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, h)), BG)
	var y := MARGIN
	var fps := int(_frame.get("fps", 0))
	var not_sampled := 0
	var subs: Dictionary = _frame.get("subsystems", {})
	for e in ProfilerSubsystems.entries():
		if (subs.get(e.id, {}) as Dictionary).get("state") == "not_sampled":
			not_sampled += 1
	_text("fps %d   frame %d   not sampled %d/%d   [F8] hide  [F9] dump JSON" % [
		fps, int(_frame.get("frame", 0)), not_sampled, rows], Vector2(MARGIN, y + ROW_H), HEADER)
	y += ROW_H * 2
	_text("subsystem", Vector2(MARGIN, y), DIM)
	_text("state", Vector2(MARGIN + COL_LABEL, y), DIM)
	_text("value", Vector2(MARGIN + COL_LABEL + COL_STATE, y), DIM)
	y += ROW_H
	for e in ProfilerSubsystems.entries():
		var entry: Dictionary = subs.get(e.id, {"state": "not_sampled", "reason": "no data", "samples": 0})
		if entry.get("state") == "sampled":
			_text(e.label, Vector2(MARGIN, y), FG)
			_text("sampled", Vector2(MARGIN + COL_LABEL, y), OK)
			# Show the sample count: a scope called twice in a frame is not the
			# same evidence as one called once, and the count is what tells them.
			_text("%s  n=%d" % [_fmt(entry), int(entry.get("samples", 0))], Vector2(MARGIN + COL_LABEL + COL_STATE, y), OK)
		else:
			_text(e.label, Vector2(MARGIN, y), DIM)
			_text("not sampled", Vector2(MARGIN + COL_LABEL, y), NOT_SAMPLED)
			# The value column stays EMPTY. Not 0, not 0.00, not a dash that
			# could be read as a measurement — nothing.
		y += ROW_H

func _fmt(entry: Dictionary) -> String:
	var v := float(entry.get("value", 0.0))
	var unit := String(entry.get("unit", "ms"))
	if unit == "ms":
		return "%.3f ms" % v
	if unit == "count_per_second":
		return "%d/s" % int(v)
	return "%.2f %s" % [v, unit]

func _text(s: String, pos: Vector2, colour: Color) -> void:
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, colour)
