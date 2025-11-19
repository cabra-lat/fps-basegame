@tool
extends EditorScript
const MARKER_SIZE = 0.005

## Vertex Marker Tool for Godot 4.5
## Places markers on all mesh vertices and allows vertex movement via marker movement

var vertex_markers = {}  # Dictionary to track marker -> vertex mapping

func _run():
    var selection = EditorInterface.get_selection().get_selected_nodes()
    if selection.is_empty():
        printerr("❌ No mesh selected. Please select a MeshInstance3D.")
        return

    var mesh_instance = selection[0]
    if not mesh_instance is MeshInstance3D or not mesh_instance.mesh:
        printerr("❌ Selected node must be a MeshInstance3D with a mesh.")
        return

    var mesh = mesh_instance.mesh
    if not mesh is ArrayMesh:
        printerr("❌ Mesh must be an ArrayMesh for vertex editing.")
        return

    # Check if markers already exist
    var existing_markers = get_existing_markers(mesh_instance)

    if existing_markers.size() > 0:
        print("🔄 Updating mesh based on moved markers...")
        update_mesh_from_markers(mesh_instance, existing_markers)
        clear_all_markers(mesh_instance)
        print("✅ Mesh updated and markers cleared.")
    else:
        print("🔍 Processing mesh '%s'..." % mesh_instance.name)

        # Create a duplicate mesh for editing
        var working_mesh = mesh.duplicate()
        mesh_instance.mesh = working_mesh

        clear_existing_markers(mesh_instance)
        create_vertex_markers(mesh_instance, working_mesh)
        print("✅ Created vertex markers. Move markers to modify vertices, then run script again to update mesh.")

func get_existing_markers(mesh_instance: MeshInstance3D) -> Array:
    var markers = []
    for child in mesh_instance.get_children():
        if child.has_meta("is_vertex_marker"):
            markers.append(child)
    return markers

func clear_existing_markers(mesh_instance: MeshInstance3D):
    # Remove any existing markers from previous runs
    for child in mesh_instance.get_children():
        if child.has_meta("is_vertex_marker"):
            child.queue_free()
    vertex_markers.clear()

func create_vertex_markers(mesh_instance: MeshInstance3D, mesh: ArrayMesh):
    var world_transform = mesh_instance.global_transform

    for surface_idx in range(mesh.get_surface_count()):
        var arrays = mesh.surface_get_arrays(surface_idx)
        var vertices = arrays[Mesh.ARRAY_VERTEX]

        if not vertices:
            continue

        print("📌 Surface %d: Creating %d markers..." % [surface_idx, vertices.size()])

        for vertex_idx in range(vertices.size()):
            var vertex = vertices[vertex_idx]
            # Transform vertex from mesh local space to world space
            var world_pos = world_transform * vertex

            create_marker_at_position(mesh_instance, world_pos, surface_idx, vertex_idx, mesh)

func create_marker_at_position(mesh_instance: MeshInstance3D, position: Vector3, surface_idx: int, vertex_idx: int, mesh: ArrayMesh):
    # Create a small CSGSphere as a visible marker
    var marker = MeshInstance3D.new()
    var sphere = SphereMesh.new()
    sphere.radius = MARKER_SIZE
    sphere.height = 2 * MARKER_SIZE
    sphere.radial_segments = 8
    sphere.rings = 4

    marker.mesh = sphere

    # Create a unique colored material for each surface
    var material = StandardMaterial3D.new()
    var hue = float(surface_idx) / max(1, mesh.get_surface_count())
    material.albedo_color = Color.from_hsv(hue, 0.8, 1.0)
    material.emission_enabled = true
    material.emission = material.albedo_color * 0.3
    material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED

    marker.material_override = material

    # Position the marker in world space
    marker.global_position = position
    marker.name = "VertexMarker_S%d_V%d" % [surface_idx, vertex_idx]

    # Add metadata for identification
    marker.set_meta("is_vertex_marker", true)
    marker.set_meta("surface_index", surface_idx)
    marker.set_meta("vertex_index", vertex_idx)

    # Make sure the marker is editable in the editor
    #marker.set_editable_instance(true)

    # Add to scene as child of mesh instance so they transform together
    mesh_instance.add_child(marker)
    marker.owner = get_scene()

    # Track the marker
    var key = "%d_%d" % [surface_idx, vertex_idx]
    vertex_markers[key] = marker

func update_mesh_from_markers(mesh_instance: MeshInstance3D, existing_markers: Array):
    var mesh = mesh_instance.mesh
    if not mesh is ArrayMesh:
        return

    # We'll create a new mesh with updated vertex positions
    var new_mesh = ArrayMesh.new()
    var world_transform = mesh_instance.global_transform
    var inverse_transform = world_transform.affine_inverse()

    # Track which vertices we've updated
    var updated_vertices = {}

    # First, collect all the updated vertex positions from markers
    for marker in existing_markers:
        if is_instance_valid(marker):
            var surface_idx = marker.get_meta("surface_index")
            var vertex_idx = marker.get_meta("vertex_index")

            # Transform marker position from world space back to mesh local space
            var world_pos = marker.global_position
            var local_pos = inverse_transform * world_pos

            if not updated_vertices.has(surface_idx):
                updated_vertices[surface_idx] = {}
            updated_vertices[surface_idx][vertex_idx] = local_pos

    # Now update each surface
    for surface_idx in range(mesh.get_surface_count()):
        var arrays = mesh.surface_get_arrays(surface_idx)
        var material = mesh.surface_get_material(surface_idx)

        # Create new arrays with updated vertex positions
        var new_arrays = update_vertex_positions(arrays, surface_idx, updated_vertices)

        if new_arrays:
            new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
            if material:
                new_mesh.surface_set_material(new_mesh.get_surface_count() - 1, material)

    # Apply the new mesh
    mesh_instance.mesh = new_mesh

func update_vertex_positions(arrays: Array, surface_idx: int, updated_vertices: Dictionary) -> Array:
    var new_arrays = arrays.duplicate(true)  # Deep copy

    # Check if we have updated vertices for this surface
    if updated_vertices.has(surface_idx):
        var vertices = arrays[Mesh.ARRAY_VERTEX]
        if vertices and vertices.size() > 0:
            var new_vertices = vertices.duplicate()

            # Update vertex positions
            for vertex_idx in updated_vertices[surface_idx]:
                if vertex_idx < new_vertices.size():
                    new_vertices[vertex_idx] = updated_vertices[surface_idx][vertex_idx]

            new_arrays[Mesh.ARRAY_VERTEX] = new_vertices

            # Note: We might need to recalculate normals if the mesh deformation is significant
            # For now, we'll keep the original normals

    return new_arrays

func clear_all_markers(mesh_instance: MeshInstance3D):
    # Remove any existing markers
    for child in mesh_instance.get_children():
        if child.has_meta("is_vertex_marker"):
            child.queue_free()
    vertex_markers.clear()
