class_name HudStyle
extends RefCounted
## Single source of truth for the in-game HUD look, so debug_range and the
## arena cannot drift apart (P0 visual consistency).

const FONT_TITLE := 20
const FONT_MSG := 18
const FONT_HINT := 15

static func panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.10, 0.72)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_right = 6
	sb.corner_radius_bottom_left = 6
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb
