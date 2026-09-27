// scope_glass.gdshader — turns a SubViewport texture into glass.
//
// The scope scenes already own the expensive half: Camera3D -> SubViewport ->
// ViewportTexture. This is the cheap half: one fullscreen draw over that texture,
// no additional render pass. Budget is the whole design constraint.
//
// Draw on a ColorRect / fullscreen quad sized to the SubViewport, NOT on the 3D
// geometry, so the scope's own body mesh is never shaded by this.
//
// Feeds the existing SubViewportTexture. Reticle and holdover are NOT drawn here:
// they come from the ballistics layer (reticle_holdover_marks), because a
// reticle baked into a shader is a reticle that cannot be zeroed.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D scope_tex : source_color, filter_linear_mipmap;

// ── Exit pupil ──────────────────────────────────────────────────────────────
// The circle of glass you can actually see through. Slightly under 0.5 so the
// pupil sits inside the optic's body and the rim reads as barrel, not as a
// sprite edge.
uniform float pupil_radius : hint_range(0.30, 0.50) = 0.46;
// Softness of the rim in UV units. Small = crisp, large = foggy cheap glass.
uniform float pupil_softness : hint_range(0.0005, 0.05) = 0.004;

// ── Parallax ────────────────────────────────────────────────────────────────
// THIS is what sells it as glass rather than a decal, and it is the whole reason
// a scope reads as a tube: the view through the glass shifts as your head moves,
// more at the edge than the centre, exactly like a real tube. Sample the texture
// with the view ray rotated by eye direction. Fed from the camera basis each
// frame; cost is two subtractions and a dot product.
uniform vec2 parallax_offset = vec2(0.0);
// Extra offset scaled by radius, so the pupil edge parallaxes more than the
// centre. This radial term is what makes it read as a cylinder and not a
// sliding window.
uniform float parallax_radial = 0.004;

// ── Chromatic aberration ────────────────────────────────────────────────────
// Real glass disperses, and the error grows with distance from the optical axis.
// Strength is driven by radius, so the centre stays clean and the rim fringes.
uniform float aberration : hint_range(0.0, 0.02) = 0.0045;

// ── Vignette / barrel shadow ────────────────────────────────────────────────
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.85;

// ── Glass tint ──────────────────────────────────────────────────────────────
// Slight green-blue like a coated optic. Kept desaturated on purpose: this is
// "coated", not "swamp", and it must not fight the scene it is looking at.
uniform vec4 glass_tint : source_color = vec4(0.86, 0.93, 0.90, 1.0);

// ── Surface imperfection ────────────────────────────────────────────────────
// Cheap and the reason it reads as a real optic: a faint static smear and dust.
// Static, not animated — animated dirt at this scale is noise, not detail.
uniform float dirt_strength : hint_range(0.0, 1.0) = 0.10;
uniform float dust_strength : hint_range(0.0, 1.0) = 0.06;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Parallax: uniform shift plus a radial term, so the pupil behaves like a
	// tube rather than a window sliding across the screen.
	vec2 from_center = uv - vec2(0.5);
	float r = length(from_center);
	uv += parallax_offset + from_center * parallax_radial;

	// Chromatic aberration. Per-channel radial scale, so dispersion is zero on
	// the optical axis and grows toward the rim.
	vec2 dir = r > 0.0001 ? from_center / r : vec2(0.0);
	float disp = aberration * r * r;
	vec3 col;
	col.r = texture(scope_tex, uv + dir * disp).r;
	col.g = texture(scope_tex, uv).g;
	col.b = texture(scope_tex, uv - dir * disp).b;

	// Glass tint.
	col *= glass_tint.rgb;

	// Imperfection. Two octaves of static value noise, and a sparse dust
	// threshold. Both are cheap and both are what stop a clean render from
	// looking like a screenshot pasted into a circle.
	float smear = hash21(floor(SCREEN_UV * 240.0)) * 0.5 + hash21(floor(SCREEN_UV * 61.0)) * 0.5;
	col -= smear * dirt_strength * 0.12;
	float dust = step(0.9965, hash21(floor(SCREEN_UV * 380.0)));
	col += dust * dust_strength;

	// Vignette toward the rim.
	col *= 1.0 - vignette_strength * smoothstep(0.25, pupil_radius, r);

	// Exit pupil. Crisp outer edge, soft inner falloff so the barrel has a
	// little thickness instead of a hard vector edge.
	float pupil = 1.0 - smoothstep(pupil_radius - pupil_softness, pupil_radius, r);
	// Rim darkening just inside the pupil, where the barrel wall shades the glass.
	col *= 1.0 - 0.55 * smoothstep(pupil_radius - pupil_softness * 6.0, pupil_radius, r);

	COLOR = vec4(col, pupil * glass_tint.a);
}
