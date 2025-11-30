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

// ─────────────────────────────────────────────────────────────────────────────
// DECAL PROJECTION SYSTEM (Runtime-switchable)
// ─────────────────────────────────────────────────────────────────────────────

#ifndef NO_TEXTURE
uniform sampler2D albedoTex : source_color, filter_nearest, repeat_enable;

// UV Controls (global, used by both UV and decal modes)
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform vec2 uv_pan_velocity = vec2(0.0);

// Decal Settings
uniform bool use_decal = false;          // Enable decal projection
uniform float decal_scale = 1.0;         // Base scale multiplier

// PROJECTION DIRECTION
// 0 = Front (-Z) | 1 = Back (+Z) | 2 = Top (+Y) | 3 = Bottom (-Y) | 4 = Right (+X) | 5 = Left (-X)
uniform int decal_axis : hint_range(0, 5) = 0;

// DEPTH MASKING: Only render within this distance along projection axis
// This is like the "thickness" of the projection volume
uniform float decal_depth_threshold = 0.05; // 0.05 = 5cm thickness (adjust as needed)

// Origin point for depth calculation (in model or world space)
uniform vec3 decal_origin = vec3(0.0);

// Space: false = model's axes, true = world axes
uniform bool decal_world_space = false;

varying vec3 v_decal_pos;
varying vec3 v_decal_normal;
#endif

uniform bool texture_repeat = false; // IMPORTANT: Set to FALSE for decals

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
    snapped_pos.xyz /= base_pos.w;
    vec2 snap_res = get_snap_resolution(aspect_ratio);
    snapped_pos.x = floor(snap_res.x * snapped_pos.x) / snap_res.x;
    snapped_pos.y = floor(snap_res.y * snapped_pos.y) / snap_res.y;
    snapped_pos.xyz *= base_pos.w;
    return snapped_pos;
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: Apply repeat/clamp
// ─────────────────────────────────────────────────────────────────────────────
vec2 apply_repeat_settings(vec2 uv) {
    if (texture_repeat) {
        return fract(uv);
    } else {
        return clamp(uv, 0.0, 1.0);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: Single-direction decal with depth masking
// ─────────────────────────────────────────────────────────────────────────────
#ifndef NO_TEXTURE
vec4 texture_decal(sampler2D tex, vec3 pos, vec3 normal, float scale, vec2 uv_pan, int axis) {
    // Generate planar coordinates
    vec2 uv_xy = pos.xy * scale;
    vec2 uv_xz = pos.xz * scale;
    vec2 uv_yz = pos.yz * scale;
    
    // Apply UV controls (using globals)
    uv_xy = uv_xy * uv_scale + uv_offset + uv_pan;
    uv_xz = uv_xz * uv_scale + uv_offset + uv_pan;
    uv_yz = uv_yz * uv_scale + uv_offset + uv_pan;
    uv_xy = apply_repeat_settings(uv_xy);
    uv_xz = apply_repeat_settings(uv_xz);
    uv_yz = apply_repeat_settings(uv_yz);
    
    // SELECT PROJECTION DIRECTION
    vec2 final_uv;
    float facing;
    float depth_distance; // Distance along projection axis
    
    if (axis == 0) { // FRONT (-Z)
        final_uv = uv_xy;
        facing = -normal.z;
        depth_distance = abs(pos.z - decal_origin.z); // Distance along Z axis
    }
    else if (axis == 1) { // BACK (+Z)
        final_uv = uv_xy;
        facing = normal.z;
        depth_distance = abs(pos.z - decal_origin.z);
    }
    else if (axis == 2) { // TOP (+Y)
        final_uv = uv_xz;
        facing = normal.y;
        depth_distance = abs(pos.y - decal_origin.y);
    }
    else if (axis == 3) { // BOTTOM (-Y)
        final_uv = uv_xz;
        facing = -normal.y;
        depth_distance = abs(pos.y - decal_origin.y);
    }
    else if (axis == 4) { // RIGHT (+X)
        final_uv = uv_yz;
        facing = normal.x;
        depth_distance = abs(pos.x - decal_origin.x);
    }
    else { // LEFT (-X)
        final_uv = uv_yz;
        facing = -normal.x;
        depth_distance = abs(pos.x - decal_origin.x);
    }
    
    // CULL BACKFACES
    if (facing <= 0.0) {
        return vec4(0.0);
    }
    
    // DEPTH MASKING: Only render if within threshold along projection axis
    // This prevents hands/arms from getting the decal!
    float depth_fade = smoothstep(0.0, decal_depth_threshold, depth_distance);
    depth_fade = 1.0 - depth_fade; // Invert: center = 1.0, edges = 0.0
    
    if (depth_fade <= 0.0) {
        return vec4(0.0); // Too far from origin along projection axis
    }
    
    // Sample texture with depth mask
    return texture(tex, final_uv) * depth_fade;
}
#endif

void vertex() {
    float aspect_ratio = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
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

#ifndef NO_TEXTURE
    // Calculate decal data
    if (decal_world_space) {
        v_decal_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
        v_decal_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    } else {
        v_decal_pos = VERTEX;
        v_decal_normal = NORMAL;
    }
#endif

    POSITION = get_snapped_pos(world_position, aspect_ratio);
}

void fragment() {
    vec4 color_base = COLOR * modulate_color;
    vec4 texture_color = vec4(1.0);

#if !defined(NO_TEXTURE)
    vec2 uv_pan = uv_pan_velocity * TIME;
    
    if (use_decal) {
        texture_color = texture_decal(albedoTex, v_decal_pos, v_decal_normal, 
                                     decal_scale, uv_pan, decal_axis);
    } else {
        vec2 texture_uv;
        #ifdef METAL
            texture_uv = vec2(NORMAL.x / 2.0 + 0.5, (-NORMAL.y) / 2.0 + 0.5);
        #else
            texture_uv = UV;
        #endif
        
        texture_uv = texture_uv * uv_scale + uv_offset + uv_pan;
        texture_uv = apply_repeat_settings(texture_uv);
        texture_color = texture(albedoTex, texture_uv);
    }
#endif

    ALBEDO = color_base.rgb * texture_color.rgb;

#ifdef LIGHT_VOLUME
    ALPHA = 1.0 - UV.y;
#elif defined(ALPHA_BLEND) || defined(ALPHA_SCISSOR)
    ALPHA = texture_color.a * color_base.a;
#endif

#ifdef ALPHA_SCISSOR
    ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
#endif
}