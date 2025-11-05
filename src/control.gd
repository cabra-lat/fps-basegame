extends Control
class_name TerrainDebugOverlay

@export var terrain_manager: ChunkedTerrain
@export var overlay_size: Vector2 = Vector2(400, 400)
@export var background_color: Color = Color(0, 0, 0, 0.7)
@export var grid_color: Color = Color(1, 1, 1, 0.3)

# Add these properties for background texture
@export var background_texture: Texture2D
@export var background_texture_scale: float = 1.0
@export var background_texture_opacity: float = 0.7

# Chunk state colors
@export var unloaded_color: Color = Color(0.3, 0.3, 0.3, 0.5)
@export var visual_only_color: Color = Color(1, 1, 0, 0.7)
@export var with_collision_color: Color = Color(0, 1, 0, 0.8)
@export var player_color: Color = Color(1, 0, 0, 1.0)
@export var current_tile_color: Color = Color(1, 0.5, 0, 1.0)  # Orange for current tile

var player_position: Vector2 = Vector2.ZERO
var current_tile: Vector2i = Vector2i.ZERO  # Track current tile position
var update_timer: Timer
var background_texture_rect: TextureRect

func _ready():
    # Set size
    custom_minimum_size = overlay_size
    size = overlay_size

    # Create background texture if provided
    if background_texture:
        setup_background_texture()

    # Create update timer
    update_timer = Timer.new()
    update_timer.wait_time = 0.2
    update_timer.timeout.connect(update)
    add_child(update_timer)
    update_timer.start()

    # Make sure we're on top
    z_index = 100

    print("Terrain Debug Overlay Ready")

func setup_background_texture():
    background_texture_rect = TextureRect.new()
    background_texture_rect.texture = background_texture
    background_texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
    background_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    background_texture_rect.size = size
    background_texture_rect.modulate = Color(1, 1, 1, background_texture_opacity)

    # Make sure background is behind everything
    background_texture_rect.z_index = -1

    add_child(background_texture_rect)

func _draw():
    # If we have a background texture, we don't need the solid background
    if not background_texture:
        draw_rect(Rect2(Vector2.ZERO, size), background_color)

    if not terrain_manager:
        draw_string(SystemFont.new(), Vector2(10, 20), "No Terrain Manager Connected")
        return

    # Calculate scale to fit terrain in overlay - FIXED FOR CENTERED PLAYER
    var tile_size_m = terrain_manager.tile_size_km * 1000.0
    var terrain_size = Vector2(
        terrain_manager.tiles_number.x * tile_size_m.x,
        terrain_manager.tiles_number.y * tile_size_m.y
    )
    var scale_x = size.x / terrain_size.x
    var scale_z = size.y / terrain_size.y
    var scale_factor = min(scale_x, scale_z)

    # Calculate offset to center the player
    var center_offset = Vector2(
        size.x / 2 - player_position.x * scale_factor,
        size.y / 2 - player_position.y * scale_factor
    )

    # Draw grid
    draw_grid(scale_factor, center_offset)

    # Draw chunks
    draw_chunks(scale_factor, center_offset)

    # Draw current tile highlight
    draw_current_tile(scale_factor, center_offset)

    # Draw player indicator (instead of player_position)
    draw_player_indicator()

    # Draw player position (always at center)
    draw_player_position()

    # Draw legend
    draw_legend()

    # Draw coordinate info
    draw_coordinate_info()

func draw_grid(scale_factor: float, offset: Vector2):
    if not terrain_manager:
        return

    var tile_size_m = terrain_manager.tile_size_km * 1000.0  # Convert to meters

    # Calculate visible range based on player position
    var visible_radius_x = size.x / (2 * scale_factor)
    var visible_radius_y = size.y / (2 * scale_factor)

    # Calculate tile indices to draw
    var min_tile_x = floor((player_position.x - visible_radius_x) / tile_size_m.x)
    var max_tile_x = ceil((player_position.x + visible_radius_x) / tile_size_m.x)
    var min_tile_z = floor((player_position.y - visible_radius_y) / tile_size_m.y)
    var max_tile_z = ceil((player_position.y + visible_radius_y) / tile_size_m.y)

    # Vertical grid lines (tile boundaries)
    for x in range(int(min_tile_x), int(max_tile_x) + 1):
        var world_x = x * tile_size_m.x
        var screen_x = world_x * scale_factor + offset.x
        if screen_x >= 0 and screen_x <= size.x:
            draw_line(
                Vector2(screen_x, 0),
                Vector2(screen_x, size.y),
                grid_color,
                1.0
            )

    # Horizontal grid lines (tile boundaries)
    for z in range(int(min_tile_z), int(max_tile_z) + 1):
        var world_z = z * tile_size_m.y
        var screen_z = world_z * scale_factor + offset.y
        if screen_z >= 0 and screen_z <= size.y:
            draw_line(
                Vector2(0, screen_z),
                Vector2(size.x, screen_z),
                grid_color,
                1.0
            )

func draw_chunks(scale_factor: float, offset: Vector2):
    if not terrain_manager or not terrain_manager.tiles:
        return

    var chunk_size_m = terrain_manager.chunk_size_m  # Use the computed chunk size

    # Iterate through all tiles and their chunks
    for tile_pos in terrain_manager.tiles:
        var tile_chunks = terrain_manager.tiles[tile_pos]

        for chunk_pos in tile_chunks:
            var chunk = tile_chunks[chunk_pos]

            # Calculate chunk position and size on overlay
            var overlay_pos = Vector2(
                chunk.global_position.x * scale_factor + offset.x,
                chunk.global_position.z * scale_factor + offset.y
            )
            var overlay_size = Vector2(
                chunk_size_m.x * scale_factor,
                chunk_size_m.y * scale_factor
            )

            # Only draw if chunk is visible in overlay
            if (overlay_pos.x + overlay_size.x >= 0 and overlay_pos.x <= size.x and
                overlay_pos.y + overlay_size.y >= 0 and overlay_pos.y <= size.y):

                # Determine color based on state
                var color = unloaded_color
                if chunk.chunk_state == "VISUAL_ONLY":
                    color = visual_only_color
                elif chunk.chunk_state == "WITH_COLLISION":
                    color = with_collision_color

                # Draw chunk rectangle
                draw_rect(Rect2(overlay_pos, overlay_size), color)

                # Draw chunk border
                draw_rect(Rect2(overlay_pos, overlay_size), grid_color, false, 1.0)

                # Draw chunk coordinates (only if chunk is big enough)
                if overlay_size.x > 40 and overlay_size.y > 40:
                    var coord_text = "%d,%d" % [chunk_pos.x, chunk_pos.y]
                    var font = SystemFont.new()
                    var text_size = font.get_string_size(coord_text)
                    var text_pos = overlay_pos + (overlay_size - text_size) / 2
                    draw_string(font, text_pos, coord_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)

func draw_current_tile(scale_factor: float, offset: Vector2):
    # Calculate the current tile position based on player position
    var tile_size_m = terrain_manager.tile_size_km * 1000.0
    var current_tile_i = int(player_position.y / tile_size_m.y)  # Note: z-coordinate maps to i
    var current_tile_j = int(player_position.x / tile_size_m.x)  # x-coordinate maps to j

    # Update current_tile
    current_tile = Vector2i(current_tile_i, current_tile_j)

    # Calculate tile position and size on overlay
    var overlay_pos = Vector2(
        current_tile_j * tile_size_m.x * scale_factor + offset.x,
        current_tile_i * tile_size_m.y * scale_factor + offset.y
    )
    var overlay_size = Vector2(
        tile_size_m.x * scale_factor,
        tile_size_m.y * scale_factor
    )

    # Only draw if tile is visible in overlay
    if (overlay_pos.x + overlay_size.x >= 0 and overlay_pos.x <= size.x and
        overlay_pos.y + overlay_size.y >= 0 and overlay_pos.y <= size.y):

        # Draw highlighted border for current tile
        draw_rect(Rect2(overlay_pos, overlay_size), current_tile_color, false, 3.0)

        # Draw a subtle fill to make it more visible
        var fill_color = Color(current_tile_color.r, current_tile_color.g, current_tile_color.b, 0.2)
        draw_rect(Rect2(overlay_pos, overlay_size), fill_color)

func draw_player_position():
    # Player is always at center of overlay
    var center = size / 2

    # Draw player as a red circle
    draw_circle(center, 6, player_color)

    # Draw a crosshair
    draw_line(
        center - Vector2(12, 0),
        center + Vector2(12, 0),
        Color(1, 1, 1, 1),
        2.0
    )
    draw_line(
        center - Vector2(0, 12),
        center + Vector2(0, 12),
        Color(1, 1, 1, 1),
        2.0
    )

func draw_legend():
    var font = SystemFont.new()
    var y_offset = 10

    # Title
    draw_string(font, Vector2(10, y_offset), "Terrain Chunk Debug", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
    y_offset += 20

    # Count loaded tiles and chunks
    if terrain_manager:
        var tile_count = terrain_manager.tiles.size()
        var chunk_count = 0
        for tile in terrain_manager.tiles.values():
            chunk_count += tile.size()

        draw_string(font, Vector2(10, y_offset), "Loaded Tiles: %d" % tile_count)
        y_offset += 16
        draw_string(font, Vector2(10, y_offset), "Loaded Chunks: %d" % chunk_count)
        y_offset += 16

    # Player position
    draw_string(font, Vector2(10, y_offset), "Player: %.0f, %.0f" % [player_position.x, player_position.y])
    y_offset += 16

    # Current tile
    draw_string(font, Vector2(10, y_offset), "Current Tile: %d, %d" % [current_tile.x, current_tile.y])
    y_offset += 16

    # Legend items
    y_offset += 10

    # Unloaded
    draw_rect(Rect2(10, y_offset, 15, 15), unloaded_color)
    draw_string(font, Vector2(30, y_offset + 12), "Unloaded")
    y_offset += 20

    # Visual Only
    draw_rect(Rect2(10, y_offset, 15, 15), visual_only_color)
    draw_string(font, Vector2(30, y_offset + 12), "Visual Only")
    y_offset += 20

    # With Collision
    draw_rect(Rect2(10, y_offset, 15, 15), with_collision_color)
    draw_string(font, Vector2(30, y_offset + 12), "With Collision")
    y_offset += 20

    # Current Tile
    draw_rect(Rect2(10, y_offset, 15, 15), current_tile_color)
    draw_string(font, Vector2(30, y_offset + 12), "Current Tile")
    y_offset += 20

func draw_coordinate_info():
    var font = SystemFont.new()
    var bottom_right = Vector2(size.x - 150, size.y - 60)

    # Draw coordinate system info
    draw_string(font, bottom_right, "Player at center", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
    draw_string(font, bottom_right + Vector2(0, 15), "Coordinates: World X,Z", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)

    # Draw scale info
    var tile_size_m = terrain_manager.tile_size_km * 1000.0
    var terrain_size = Vector2(
        terrain_manager.tiles_number.x * tile_size_m.x,
        terrain_manager.tiles_number.y * tile_size_m.y
    )
    var scale_factor = min(size.x / terrain_size.x, size.y / terrain_size.y)
    var visible_radius_x = size.x / (2 * scale_factor)
    var visible_radius_y = size.y / (2 * scale_factor)
    draw_string(font, bottom_right + Vector2(0, 30), "View: ±%.0fm" % max(visible_radius_x, visible_radius_y), HORIZONTAL_ALIGNMENT_LEFT, -1, 12)

func update():
    if not terrain_manager:
        return

    # Get player position
    var current_camera = get_viewport().get_camera_3d()
    var player_node = terrain_manager.player_node

    if current_camera:
        # Adjust for terrain offset
        var adjusted_position = current_camera.global_position - terrain_manager.global_position
        player_position = Vector2(adjusted_position.x, adjusted_position.z)
    elif player_node:
        var adjusted_position = player_node.global_position - terrain_manager.global_position
        player_position = Vector2(adjusted_position.x, adjusted_position.z)

    # Force redraw
    queue_redraw()

func draw_player_indicator():
    var center = size / 2

    # Get player/camera rotation
    var camera = get_viewport().get_camera_3d()
    var rotation_angle = 0.0

    if camera:
        # Get the camera's Y rotation (around the vertical axis)
        rotation_angle = camera.global_rotation.y

    # Crosshair size
    var cross_size = 15

    # Draw crosshair arms (rotated based on player direction)
    var dir_vector = Vector2(0, -1).rotated(rotation_angle) * cross_size

    # Main direction arm (longer)
    draw_line(
        center,
        center + dir_vector * 1.5,
        Color(1, 0, 0, 1),  # Red
        3.0
    )

    # Perpendicular arms (shorter)
    var perp_vector = Vector2(-dir_vector.y, dir_vector.x).normalized() * cross_size * 0.7
    draw_line(
        center - perp_vector,
        center + perp_vector,
        Color(1, 1, 1, 1),  # White
        2.0
    )

    # Center dot
    draw_circle(center, 3, Color(1, 0, 0, 1))

# Optional: Handle window resize
func _notification(what):
    if what == NOTIFICATION_RESIZED:
        queue_redraw()
