#ifndef EXTERNAL
#define LIT diffuse_lambert, vertex_lighting
#define CULL cull_back
#define DEPTH depth_draw_opaque
#define BLEND blend_mix
#else
render_mode LIT, CULL, shadows_disabled, DEPTH, BLEND, specular_disabled;
#endif

global uniform float precision_multiplier : hint_range(0.0, 1.0) = 1.0;
uniform vec4 modulate_color : source_color = vec4(1.0);

#ifndef NO_TEXTURE
uniform sampler2D albedoTex : source_color, filter_nearest, repeat_enable;
#endif

#if !defined(NO_TEXTURE) && !defined(METAL)
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform vec2 uv_pan_velocity = vec2(0.0);
#endif

#ifdef ALPHA_SCISSOR
uniform bool billboard = false;
uniform bool y_billboard = false;
uniform float alpha_scissor : hint_range(0, 1) = 0.1;
#endif

const vec2 base_snap_res = vec2(160.0, 120.0);

vec2 get_snap_resolution(float aspect_ratio) {
    vec2 snap_res = base_snap_res * precision_multiplier;
    snap_res.x = snap_res.x * aspect_ratio;
    return floor(snap_res);
}

vec4 get_snapped_pos(vec4 base_pos, float aspect_ratio) {
    vec4 snapped_pos = base_pos;
    snapped_pos.xyz /= base_pos.w; // Convert to NDC
    vec2 snap_res = get_snap_resolution(aspect_ratio);
    snapped_pos.x = floor(snap_res.x * snapped_pos.x) / snap_res.x;
    snapped_pos.y = floor(snap_res.y * snapped_pos.y) / snap_res.y;
    snapped_pos.xyz *= base_pos.w; // Convert back to projection-space
    return snapped_pos;
}

void vertex() {
	float aspect_ratio = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
#if !defined(NO_TEXTURE) && !defined(METAL)  // METAL doesn't use UV, so no need to pan UVs
	UV = UV * uv_scale + uv_offset;
	UV += uv_pan_velocity * TIME;
#endif

    vec4 world_position = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);

#ifdef ALPHA_SCISSOR
    if (y_billboard) {
        MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
            INV_VIEW_MATRIX[0],
            MODEL_MATRIX[1],
            vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, MODEL_MATRIX[1].xyz)), 0.0),
            MODEL_MATRIX[3]
        );
    } else if (billboard) {
        MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
            INV_VIEW_MATRIX[0],
            INV_VIEW_MATRIX[1],
            INV_VIEW_MATRIX[2],
            MODEL_MATRIX[3]
        );
    }
#endif

    POSITION = get_snapped_pos(world_position, aspect_ratio); // Snap position to grid
}

void fragment() {
#ifdef METAL
    vec2 texture_uv = vec2(NORMAL.x / 2.0 + 0.5, (-NORMAL.y) / 2.0 + 0.5);
#elif !defined(NO_TEXTURE)
    vec2 texture_uv = UV;
#endif

    vec4 color_base = COLOR * modulate_color;

#ifdef NO_TEXTURE
    ALBEDO = color_base.rgb;
#else
    vec4 texture_color = texture(albedoTex, texture_uv);
    ALBEDO = (color_base * texture_color).rgb;
#endif

#ifdef LIGHT_VOLUME
    ALPHA = 1.0 - UV.y;
#elif defined(ALPHA_BLEND) || defined(ALPHA_SCISSOR)
    ALPHA = texture_color.a * color_base.a;
#endif

#ifdef ALPHA_SCISSOR
    ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
#endif
}