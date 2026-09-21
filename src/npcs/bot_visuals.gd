class_name NpcVisuals
extends RefCounted
## Body material helpers for NpcBot (src/npcs lane): per-instance material,
## spawn variation, team tint and the white damage flash.

## Team tint palette (index = team); extra teams fall back to a hue ramp.
const TEAM_COLORS: Array[Color] = [
	Color(0.85, 0.16, 0.12, 1.0), # 0 red
	Color(0.16, 0.35, 0.90, 1.0), # 1 blue
	Color(0.18, 0.72, 0.28, 1.0), # 2 green
	Color(0.92, 0.78, 0.12, 1.0), # 3 yellow
]


## Duplicate the mesh's material so tint/flash/fade stay per-bot.
static func own_material(mi: MeshInstance3D) -> StandardMaterial3D:
	if mi == null:
		return null
	var src := mi.get_active_material(0) as StandardMaterial3D
	if src == null:
		return null
	var mat := src.duplicate() as StandardMaterial3D
	mi.set_surface_override_material(0, mat)
	return mat


## Slight per-bot reddish tint jitter (alpha forced opaque).
static func varied_albedo(base: Color) -> Color:
	var c := base
	c.r = clampf(c.r + randf_range(-0.12, 0.12), 0.25, 1.0)
	c.g = clampf(c.g + randf_range(-0.05, 0.15), 0.05, 0.6)
	c.b = clampf(c.b + randf_range(-0.05, 0.15), 0.05, 0.6)
	c.a = 1.0
	return c


static func team_color(t: int) -> Color:
	if t >= 0 and t < TEAM_COLORS.size():
		return TEAM_COLORS[t]
	return Color.from_hsv(fposmod(float(t) * 0.37, 1.0), 0.75, 0.85)


## White emissive pulse; t is remaining flash seconds (0 = off).
static func apply_flash(mat: StandardMaterial3D, t: float,
		flash_time: float, energy: float) -> void:
	if mat == null:
		return
	if t <= 0.0:
		mat.emission_enabled = false
		mat.emission_energy_multiplier = 0.0
		return
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = energy * (t / flash_time)
