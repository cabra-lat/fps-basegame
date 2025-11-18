extends Control
class_name DynamicTerrainMinimap

@export_category("Minimap Settings")
@export var terrain_loader: DynamicTerrainLoader
@export var player_node: Node3D
@export var overlay_size: Vector2 = Vector2(300, 300)
@export var update_interval: float = 0.2
@export var max_tile_display_size: float = 80.0  # Max pixels for a tile

@export_category("Visual Settings")
@export var background_color: Color = Color(0, 0, 0, 0.7)
@export var loaded_tile_color: Color = Color(0, 1, 0, 0.5)
@export var current_tile_color: Color = Color(1, 1, 0, 0.7)
@export var player_color: Color = Color(1, 0, 0, 1.0)
@export var compass_color: Color = Color(0.8, 0.8, 1.0, 0.8)

# Internal state
var player_world_pos: Vector2 = Vector2.ZERO
var player_rotation: float = 0.0
var update_timer: Timer

func _ready():
    custom_minimum_size = overlay_size
    size = overlay_size

    # Update timer
    update_timer = Timer.new()
    update_timer.wait_time = update_interval
    update_timer.timeout.connect(update_minimap_data)
    add_child(update_timer)
    update_timer.start()

    # Make sure we're on top
    z_index = 100

    print("Dynamic Terrain Minimap Ready")

func _draw():
    # Draw background
    draw_rect(Rect2(Vector2.ZERO, size), background_color)

    if not terrain_loader:
        draw_string(SystemFont.new(), Vector2(10, 20), "No Terrain Loader")
        return

    # Draw the minimap content
    draw_minimap_content()

    # Draw debug info
    draw_debug_info()

    # Draw legend
    draw_legend()

func draw_minimap_content():
    # Use a fixed scale for tiles regardless of actual size
    var center = Vector2(size.x / 2, size.y / 2)

    # Draw loaded tiles with fixed size
    #draw_loaded_tiles_fixed(center)

    # Draw current tile with fixed size
    #draw_current_tile_fixed(center)

    # Draw player position (always at center)
    draw_player_position(center)

    # Draw view distance circle
    draw_view_distance_circle(center)

#func draw_loaded_tiles_fixed(center: Vector2):
    #if not terrain_loader:
        #return
    #var loaded_tiles = terrain_loader.loaded_textures.get("heightmap",[])
#
    #for tile_key in loaded_tiles:
        #var tile_data = loaded_tiles[tile_key]
        #var tile_coords = tile_data["coords"]
        #var zoom = tile_data["zoom"]
#
        ## Calculate position based on tile coordinates relative to current tile
        #var current_coords = terrain_loader.current_tile_coords
        #var offset_x = (tile_coords.x - current_coords.x) * max_tile_display_size
        #var offset_y = (tile_coords.y - current_coords.y) * max_tile_display_size
#
        #var tile_pos = center + Vector2(offset_x, offset_y)
        #var tile_size = Vector2(max_tile_display_size, max_tile_display_size)
#
        ## Draw tile rectangle
        #var tile_rect = Rect2(tile_pos - tile_size / 2, tile_size)
        #draw_rect(tile_rect, loaded_tile_color)
        #draw_rect(tile_rect, Color(1, 1, 1, 0.5), false, 1.0)
#
        ## Draw tile coordinates
        #var font = SystemFont.new()
        #var coord_text = "%d,%d\nz%d" % [tile_coords.x, tile_coords.y, zoom]
        #var text_size = font.get_string_size(coord_text)
        #if text_size.x < tile_size.x * 0.8:
            #draw_string(font, tile_pos - text_size / 2, coord_text)

#func draw_current_tile_fixed(center: Vector2):
    #if not terrain_loader:
        #return
#
    #var current_coords = terrain_loader.current_tile_coords
    #var current_zoom = terrain_loader.current_zoom
#
    ## Current tile is always at center
    #var tile_size = Vector2(max_tile_display_size, max_tile_display_size)
    #var tile_rect = Rect2(center - tile_size / 2, tile_size)
#
    ## Draw current tile highlight
    #draw_rect(tile_rect, current_tile_color)
    #draw_rect(tile_rect, Color(1, 1, 0, 0.8), false, 3.0)
#
    ## Draw "Current" label
    #var font = SystemFont.new()
    #var label_text = "Current (z%d)" % current_zoom
    #var text_size = font.get_string_size(label_text)
    #draw_string(font, center + Vector2(-text_size.x / 2, -tile_size.y / 2 - 10), label_text)

func draw_view_distance_circle(center: Vector2):
    # Calculate circle radius based on view distance and tile size
    var view_radius_pixels = terrain_loader.max_view_distance / get_meters_per_pixel()
    view_radius_pixels = min(view_radius_pixels, size.x * 0.4)  # Limit to 40% of minimap

    draw_arc(center, view_radius_pixels, 0, TAU, 32, Color(1, 1, 1, 0.3), 2.0)

    # Label the view distance
    var font = SystemFont.new()
    var view_text = "View: %dm" % terrain_loader.max_view_distance
    var text_size = font.get_string_size(view_text)
    draw_string(font, center + Vector2(-text_size.x / 2, -view_radius_pixels - 15), view_text)

func get_meters_per_pixel() -> float:
    var base_tile_size_meters = CoordinateConverter.get_tile_size_meters(15)
    return base_tile_size_meters / max_tile_display_size

func draw_player_position(center: Vector2):
    # Player is always at center of minimap
    draw_circle(center, 6, player_color)

    # Draw player direction indicator
    var compass_size = 15.0
    var direction_vector = Vector2(0, -1).rotated(player_rotation) * compass_size
    draw_line(center, center + direction_vector, compass_color, 3.0)

    # Draw crosshair
    draw_line(center - Vector2(8, 0), center + Vector2(8, 0), Color(1, 1, 1, 0.8), 1.0)
    draw_line(center - Vector2(0, 8), center + Vector2(0, 8), Color(1, 1, 1, 0.8), 1.0)

func draw_debug_info():
    var font = SystemFont.new()
    var y_offset = 20

    # Title
    draw_string(font, Vector2(10, y_offset), "DYNAMIC TERRAIN MINIMAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
    y_offset += 25

    # Player coordinates
    var coord_text = "World Pos: %.1f, %.1f m" % [player_world_pos.x, player_world_pos.y]
    draw_string(font, Vector2(10, y_offset), coord_text)
    y_offset += 20

    var lat_lon = CoordinateConverter.world_to_lat_lon(player_node.global_position, terrain_loader.start_latitude, terrain_loader.start_longitude)
    var globe_text = "Globe Pos: %.4f º, %.4f º" % [lat_lon.x, lat_lon.y]
    draw_string(font, Vector2(10, y_offset), globe_text)
    y_offset += 20

    # Current tile and zoom
    if terrain_loader:
        var tile_text = "Current Tile: %s at z%d" % [terrain_loader.current_tile_coords, 15]
        draw_string(font, Vector2(10, y_offset), tile_text)
        y_offset += 20

        # Loaded tiles count
        var queue_count = terrain_loader.tile_manager.download_queue.size()

        var queue_text = "Download Queue: %d" % queue_count
        draw_string(font, Vector2(10, y_offset), queue_text)
        y_offset += 20

        # Cache info
        var cache_text = "Tile Cache: %d/%d" % [terrain_loader.tile_manager.tile_cache.size(), terrain_loader.cache_size]
        draw_string(font, Vector2(10, y_offset), cache_text)

        # Altitude and dynamic zoom
        var altitude = player_node.global_position.y if player_node else 0.0
        #var dynamic_zoom = terrain_loader.current_zoom
        var zoom_text = "Altitude: %.1fm" % altitude # -> z%d" % [altitude, dynamic_zoom]
        draw_string(font, Vector2(10, y_offset + 20), zoom_text)

func draw_legend():
    var font = SystemFont.new()
    var start_y = size.y - 120

    # Legend background
    draw_rect(Rect2(Vector2(10, start_y), Vector2(140, 110)), Color(0, 0, 0, 0.5))

    var y_offset = start_y + 20

    # Title
    draw_string(font, Vector2(20, y_offset), "LEGEND", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
    y_offset += 20

    # Loaded Tile
    draw_rect(Rect2(20, y_offset, 10, 10), loaded_tile_color)
    draw_string(font, Vector2(35, y_offset + 8), "Loaded")
    y_offset += 20

    # Current Tile
    draw_rect(Rect2(20, y_offset, 10, 10), current_tile_color)
    draw_string(font, Vector2(35, y_offset + 8), "Current")
    y_offset += 20

    # Player
    draw_circle(Vector2(25, y_offset + 5), 4, player_color)
    draw_string(font, Vector2(35, y_offset + 8), "Player")
    y_offset += 20

    # Compass
    var compass_pos = Vector2(20, y_offset + 5)
    draw_line(compass_pos, compass_pos + Vector2(0, -6), compass_color, 2.0)
    draw_string(font, Vector2(35, y_offset + 8), "Heading")

func update_minimap_data():
    if not terrain_loader or not player_node:
        return

    # Get player position in world coordinates
    var player_global_pos = player_node.global_position
    player_world_pos = Vector2(player_global_pos.x, player_global_pos.z)

    # Get player rotation
    player_rotation = player_node.global_rotation.y

    # Force redraw
    queue_redraw()

# Optional: Add input handling for toggling minimap
func _input(event):
    if event.is_action_pressed("toggle_minimap"):
        visible = !visible
    #elif event.is_action_pressed("increase_tile_size"):
        #max_tile_display_size = min(max_tile_display_size + 10, 150)
    #elif event.is_action_pressed("decrease_tile_size"):
        #max_tile_display_size = max(max_tile_display_size - 10, 20)
