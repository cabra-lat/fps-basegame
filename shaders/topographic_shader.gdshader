shader_type spatial;

uniform sampler2D height_texture;
uniform float displacement_strength = 50.0;

// UV scaling for chunks
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);

// Topographic colors
uniform vec3 deep_water_color = vec3(0.0, 0.1, 0.3);
uniform vec3 shallow_water_color = vec3(0.0, 0.3, 0.6);
uniform vec3 sand_color = vec3(0.76, 0.7, 0.5);
uniform vec3 grass_low_color = vec3(0.2, 0.5, 0.2);
uniform vec3 grass_high_color = vec3(0.3, 0.6, 0.3);
uniform vec3 forest_color = vec3(0.1, 0.4, 0.1);
uniform vec3 rock_color = vec3(0.5, 0.5, 0.5);
uniform vec3 snow_color = vec3(1.0, 1.0, 1.0);

// Height thresholds
uniform float water_level = 0.1;
uniform float sand_level = 0.12;
uniform float grass_level = 0.2;
uniform float forest_level = 0.4;
uniform float rock_level = 0.7;
uniform float snow_level = 0.85;

// Visualization
uniform bool show_contour_lines = true;
uniform float contour_spacing = 0.05;
uniform vec3 contour_color = vec3(0.0, 0.0, 0.0);
uniform float contour_width = 0.002;

void vertex() {
    // Calculate chunk-specific UVs
    vec2 chunk_uv = UV * uv_scale + uv_offset;

    // Sample height at this vertex's UV
    float height = texture(height_texture, chunk_uv).r;

    // Displace in Y direction
    VERTEX.y += height * displacement_strength;
}

void fragment() {
    // Calculate chunk-specific UVs
    vec2 chunk_uv = UV * uv_scale + uv_offset;

    // Get the height value
    float height = texture(height_texture, chunk_uv).r;

    // Initialize color
    vec3 final_color = deep_water_color;

    // Apply topographic coloring based on height
    if (height < water_level) {
        float t = height / water_level;
        final_color = mix(deep_water_color, shallow_water_color, t);
    } else if (height < sand_level) {
        final_color = sand_color;
    } else if (height < grass_level) {
        float t = (height - sand_level) / (grass_level - sand_level);
        final_color = mix(sand_color, grass_low_color, t);
    } else if (height < forest_level) {
        float t = (height - grass_level) / (forest_level - grass_level);
        final_color = mix(grass_high_color, forest_color, t);
    } else if (height < rock_level) {
        float t = (height - forest_level) / (rock_level - forest_level);
        final_color = mix(forest_color, rock_color, t);
    } else if (height < snow_level) {
        float t = (height - rock_level) / (snow_level - rock_level);
        final_color = mix(rock_color, snow_color, t);
    } else {
        final_color = snow_color;
    }

    // Add contour lines
    if (show_contour_lines) {
        float contour_dist = abs(mod(height, contour_spacing) - contour_spacing * 0.5);
        if (contour_dist < contour_width) {
            final_color = mix(contour_color, final_color, 0.3);
        }
    }

    // Slope-based lighting
    vec3 normal = normalize(NORMAL);
    float slope_light = 0.5 + 0.5 * normal.y;
    final_color *= slope_light;

    ALBEDO = final_color;
    METALLIC = 0.0;
    ROUGHNESS = 0.8;
}