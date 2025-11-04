extends MeshInstance3D

class_name TerrainChunk

var has_collision = false
var collision_body: StaticBody3D = null
var chunk_position: Vector2

func setup_chunk(size: Vector3, position: Vector3, height_tex: Texture2D,
                material_template: ShaderMaterial, height: float, render_dist: float):

    chunk_position = Vector2(position.x / size.x, position.z / size.z)

    var plane_mesh = PlaneMesh.new()
    plane_mesh.size = Vector2(size.x, size.z)
    plane_mesh.subdivide_width = 63
    plane_mesh.subdivide_depth = 63
    plane_mesh.orientation = PlaneMesh.FACE_Y

    self.mesh = plane_mesh
    self.global_position = position

    # Visibility settings
    self.visibility_range_begin = 0
    self.visibility_range_end = render_dist
    self.visibility_range_end_margin = 200
    self.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

    # Material
    var chunk_material = material_template.duplicate()

    var uv_scale = Vector2(
        size.x / 36000.0,
        size.z / 36000.0
    )
    var uv_offset = Vector2(
        position.x / 36000.0,
        position.z / 36000.0
    )

    chunk_material.set_shader_parameter("uv_scale", uv_scale)
    chunk_material.set_shader_parameter("uv_offset", uv_offset)
    chunk_material.set_shader_parameter("height_texture", height_tex)
    chunk_material.set_shader_parameter("displacement_strength", height)

    self.material_override = chunk_material

func add_collision(height_tex: Texture2D, terrain_size: Vector2, max_height: float):
    if has_collision:
        return

    var image = height_tex.get_image()
    var start_x = int((global_position.x / terrain_size.x) * image.get_width())
    var start_z = int((global_position.z / terrain_size.y) * image.get_height())
    var chunk_width = int((mesh.size.x / terrain_size.x) * image.get_width())
    var chunk_depth = int((mesh.size.y / terrain_size.y) * image.get_height())

    # Ensure we don't go out of bounds
    start_x = clamp(start_x, 0, image.get_width() - chunk_width)
    start_z = clamp(start_z, 0, image.get_height() - chunk_depth)
    chunk_width = min(chunk_width, image.get_width() - start_x)
    chunk_depth = min(chunk_depth, image.get_height() - start_z)

    # Extract height data for this specific chunk
    var height_data = PackedFloat32Array()
    height_data.resize(chunk_width * chunk_depth)

    for z in range(chunk_depth):
        for x in range(chunk_width):
            var pixel = image.get_pixel(start_x + x, start_z + z)
            height_data[z * chunk_width + x] = pixel.r * max_height

    # Create collision shape
    var heightmap_shape = HeightMapShape3D.new()
    heightmap_shape.map_width = chunk_width
    heightmap_shape.map_depth = chunk_depth
    heightmap_shape.map_data = height_data

    # Create static body
    collision_body = StaticBody3D.new()
    var collision_shape = CollisionShape3D.new()
    collision_shape.shape = heightmap_shape
    collision_shape.scale = Vector3(image.get_width(), max_height, image.get_height())

    collision_body.add_child(collision_shape)

    # Position the collision body to match the visual mesh
    collision_body.global_position = global_position

    add_child(collision_body)
    has_collision = true

    print("Collision added to chunk: ", chunk_position, " (", chunk_width, "x", chunk_depth, ")")

func remove_collision():
    if collision_body:
        collision_body.queue_free()
        collision_body = null
    has_collision = false

func get_chunk_position() -> Vector2:
    return chunk_position

func _exit_tree():
    remove_collision()
