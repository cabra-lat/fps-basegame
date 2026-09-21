class_name NpcVisuals
extends RefCounted
## Body look helpers for NpcBot (src/npcs lane): per-bot tint variation, team
## tint and the corpse fade — all applied through the SHARED HumanoidRig
## (player-rig lane), never on a parallel mesh.
##
## The rig owns the per-instance material (it duplicates the body ShaderMaterial
## and swaps in the body fork that declares `flash_amount`), so this file only
## decides WHAT colour/alpha to push: `HumanoidRig.set_tint()` /
## `set_flash()` do the writing. Hard rule (M4): one bot tinting or flashing
## must never touch the shared material or the player.

## Team tint palette (index = team); extra teams fall back to a hue ramp.
const TEAM_COLORS: Array[Color] = [
	Color(0.85, 0.16, 0.12, 1.0), # 0 red
	Color(0.16, 0.35, 0.90, 1.0), # 1 blue
	Color(0.18, 0.72, 0.28, 1.0), # 2 green
	Color(0.92, 0.78, 0.12, 1.0), # 3 yellow
]


## Subtle per-bot identity tint: `modulate_color` multiplies the character
## texture, so this stays near white (a strong tint would dye the whole body).
static func varied_tint(base: Color = Color.WHITE) -> Color:
	var c := base
	c.r = clampf(c.r + randf_range(-0.10, 0.10), 0.0, 1.0)
	c.g = clampf(c.g + randf_range(-0.10, 0.10), 0.0, 1.0)
	c.b = clampf(c.b + randf_range(-0.10, 0.10), 0.0, 1.0)
	c.a = 1.0
	return c


static func team_color(t: int) -> Color:
	if t >= 0 and t < TEAM_COLORS.size():
		return TEAM_COLORS[t]
	return Color.from_hsv(fposmod(float(t) * 0.37, 1.0), 0.75, 0.85)


## Corpse fade: `modulate_color.a` on the rig's per-instance materials.
## The body shader is alpha-scissor (`ALPHA_SCISSOR_THRESHOLD`), so an opaque
## texel would pop out at the threshold instead of fading — the first call
## drops `alpha_scissor` to 0 so the alpha actually blends (the material has
## blend_mix + depth_prepass_alpha). Only the instance copies are touched.
static func corpse_alpha(rig: HumanoidRig, tint: Color, alpha: float) -> void:
	if rig == null:
		return
	for mat in rig.own_materials():
		if mat.get_shader_parameter("alpha_scissor") != null \
				and float(mat.get_shader_parameter("alpha_scissor")) > 0.0:
			mat.set_shader_parameter("alpha_scissor", 0.0)
		mat.set_shader_parameter("modulate_color",
			Color(tint.r, tint.g, tint.b, clampf(alpha, 0.0, 1.0)))
