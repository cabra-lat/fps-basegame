class_name ChunkedTerrain
extends Node3D

@export var terrain_size: Vector2 = Vector2(36000, 36000)
@export var chunk_size: Vector3 = Vector3(1000, 0, 1000)
@export var render_distance: float = 3000.0
@export var collision_distance: float = 1500.0  # Closer than render distance
@export var max_height: float = 100.0
@export var height_texture: Texture2D
@export var material: ShaderMaterial

var chunks = {}
var camera: Camera3D
var player_node: Node3D
var chunk_load_timer: Timer

# Track chunk states
enum ChunkState { UNLOADED, VISUAL_ONLY, WITH_COLLISION }
var chunk_states = {}

func _ready():
    setup_terrain()
    start_chunk_management()

func setup_terrain():
    camera = get_viewport().get_camera_3d()
    player_node = get_tree().get_first_node_in_group("player")
    if not player_node:
        player_node = self

    chunk_load_timer = Timer.new()
    chunk_load_timer.wait_time = 0.3  # More frequent updates for collision
    chunk_load_timer.timeout.connect(update_chunks)
    add_child(chunk_load_timer)

func start_chunk_management():
    update_chunks()
    chunk_load_timer.start()

func update_chunks():
    if not camera and not player_node:
        return

    var player_pos = player_node.global_position
    var current_chunk_x = int(player_pos.x / chunk_size.x)
    var current_chunk_z = int(player_pos.z / chunk_size.z)

    var visual_chunks_to_keep = {}
    var collision_chunks_to_keep = {}

    var visual_radius = ceil(render_distance / chunk_size.x)
    var collision_radius = ceil(collision_distance / chunk_size.x)

    # Determine which chunks should have what
    for x in range(current_chunk_x - visual_radius, current_chunk_x + visual_radius + 1):
        for z in range(current_chunk_z - visual_radius, current_chunk_z + visual_radius + 1):
            var chunk_pos = Vector2(x, z)
            var chunk_world_pos = Vector3(x * chunk_size.x, 0, z * chunk_size.z)
            var distance = player_pos.distance_to(chunk_world_pos)

            if distance <= render_distance:
                visual_chunks_to_keep[chunk_pos] = true

                if distance <= collision_distance:
                    collision_chunks_to_keep[chunk_pos] = true

                    # Load with collision
                    if not chunks.has(chunk_pos) or chunk_states.get(chunk_pos) != ChunkState.WITH_COLLISION:
                        load_chunk(chunk_pos, true)
                else:
                    # Load visual only
                    if not chunks.has(chunk_pos) or chunk_states.get(chunk_pos) != ChunkState.VISUAL_ONLY:
                        load_chunk(chunk_pos, false)

    # Update existing chunks' collision states
    for chunk_pos in chunks.keys():
        if collision_chunks_to_keep.has(chunk_pos):
            if chunk_states.get(chunk_pos) != ChunkState.WITH_COLLISION:
                add_collision_to_chunk(chunks[chunk_pos])
        else:
            if chunk_states.get(chunk_pos) == ChunkState.WITH_COLLISION:
                remove_collision_from_chunk(chunks[chunk_pos])

    # Remove chunks that are too far
    for chunk_pos in chunks.keys():
        if not visual_chunks_to_keep.has(chunk_pos):
            remove_chunk(chunk_pos)

func load_chunk(chunk_pos: Vector2, with_collision: bool):
    if chunks.has(chunk_pos):
        # Chunk exists, just update collision
        if with_collision and chunk_states.get(chunk_pos) != ChunkState.WITH_COLLISION:
            add_collision_to_chunk(chunks[chunk_pos])
        elif not with_collision and chunk_states.get(chunk_pos) == ChunkState.WITH_COLLISION:
            remove_collision_from_chunk(chunks[chunk_pos])
        return

    var chunk = TerrainChunk.new()
    chunk.setup_chunk(
        chunk_size,
        Vector3(chunk_pos.x * chunk_size.x, 0, chunk_pos.y * chunk_size.z),
        height_texture,
        material,
        max_height,
        render_distance
    )

    add_child(chunk)
    chunks[chunk_pos] = chunk

    if with_collision:
        add_collision_to_chunk(chunk)
        chunk_states[chunk_pos] = ChunkState.WITH_COLLISION
    else:
        chunk_states[chunk_pos] = ChunkState.VISUAL_ONLY

    print("Loaded chunk: ", chunk_pos, " with collision: ", with_collision)

func add_collision_to_chunk(chunk: TerrainChunk):
    if chunk.has_collision:
        return

    chunk.add_collision(height_texture, terrain_size, max_height)
    chunk_states[chunk.get_chunk_position()] = ChunkState.WITH_COLLISION
    print("Added collision to chunk at ", chunk.global_position)

func remove_collision_from_chunk(chunk: TerrainChunk):
    if not chunk.has_collision:
        return

    chunk.remove_collision()
    chunk_states[chunk.get_chunk_position()] = ChunkState.VISUAL_ONLY
    print("Removed collision from chunk at ", chunk.global_position)

func remove_chunk(chunk_pos: Vector2):
    if chunks.has(chunk_pos):
        var chunk = chunks[chunk_pos]
        chunk.queue_free()
        chunks.erase(chunk_pos)
        chunk_states.erase(chunk_pos)
        print("Removed chunk: ", chunk_pos)
