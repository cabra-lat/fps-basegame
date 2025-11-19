@tool
extends EditorScript
const MARKER_SIZE = 0.005

## Vertex Marker Tool for Godot 4.5
## Places markers on all mesh vertices and allows vertex deletion via marker deletion

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
        print("🔄 Updating mesh based on deleted markers...")
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
        print("✅ Created vertex markers. Delete markers to remove vertices, then run script again to update mesh.")

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

    # Build a set of vertices that still have markers (should be kept)
    var vertices_to_keep = {}

    for marker in existing_markers:
        if is_instance_valid(marker):
            var surface_idx = marker.get_meta("surface_index")
            var vertex_idx = marker.get_meta("vertex_index")

            if not vertices_to_keep.has(surface_idx):
                vertices_to_keep[surface_idx] = []
            vertices_to_keep[surface_idx].append(vertex_idx)

    # Create a new mesh with only the kept vertices
    var new_mesh = ArrayMesh.new()

    for surface_idx in range(mesh.get_surface_count()):
        var arrays = mesh.surface_get_arrays(surface_idx)
        var material = mesh.surface_get_material(surface_idx)

        if vertices_to_keep.has(surface_idx):
            # Remove vertices that don't have markers (were deleted by user)
            var new_arrays = remove_unmarked_vertices(arrays, vertices_to_keep[surface_idx])
            if new_arrays:
                new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
                if material:
                    new_mesh.surface_set_material(new_mesh.get_surface_count() - 1, material)
        else:
            # Keep entire surface if no markers were deleted from it
            new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
            if material:
                new_mesh.surface_set_material(new_mesh.get_surface_count() - 1, material)

    # Apply the new mesh
    mesh_instance.mesh = new_mesh

func remove_unmarked_vertices(arrays: Array, vertices_to_keep: Array) -> Array:
    # Sort and make sure we have valid indices
    vertices_to_keep.sort()

    var new_arrays = []
    new_arrays.resize(Mesh.ARRAY_MAX)

    var vertices = arrays[Mesh.ARRAY_VERTEX]
    var indices = arrays[Mesh.ARRAY_INDEX]

    if not vertices:
        return arrays

    # Create mapping from old index to new index
    var index_remap = {}
    for new_idx in range(vertices_to_keep.size()):
        var old_idx = vertices_to_keep[new_idx]
        index_remap[old_idx] = new_idx

    # Build new vertex arrays with only kept vertices
    for attr in range(Mesh.ARRAY_MAX):
        if arrays[attr] and arrays[attr].size() > 0:
            var old_data = arrays[attr]
            var new_data

            if attr == Mesh.ARRAY_VERTEX:
                new_data = PackedVector3Array()
                for old_idx in vertices_to_keep:
                    new_data.append(old_data[old_idx])
            elif attr == Mesh.ARRAY_NORMAL and arrays[Mesh.ARRAY_NORMAL].size() == vertices.size():
                new_data = PackedVector3Array()
                for old_idx in vertices_to_keep:
                    new_data.append(old_data[old_idx])
            elif attr == Mesh.ARRAY_TEX_UV and arrays[Mesh.ARRAY_TEX_UV].size() == vertices.size():
                new_data = PackedVector2Array()
                for old_idx in vertices_to_keep:
                    new_data.append(old_data[old_idx])
            elif attr == Mesh.ARRAY_TEX_UV2 and arrays[Mesh.ARRAY_TEX_UV2].size() == vertices.size():
                new_data = PackedVector2Array()
                for old_idx in vertices_to_keep:
                    new_data.append(old_data[old_idx])
            elif attr == Mesh.ARRAY_COLOR and arrays[Mesh.ARRAY_COLOR].size() == vertices.size():
                new_data = PackedColorArray()
                for old_idx in vertices_to_keep:
                    new_data.append(old_data[old_idx])
            elif attr == Mesh.ARRAY_TANGENT and arrays[Mesh.ARRAY_TANGENT].size() == vertices.size() * 4:
                new_data = PackedFloat32Array()
                for old_idx in vertices_to_keep:
                    var base_idx = old_idx * 4
                    new_data.append(old_data[base_idx])
                    new_data.append(old_data[base_idx + 1])
                    new_data.append(old_data[base_idx + 2])
                    new_data.append(old_data[base_idx + 3])
            elif attr == Mesh.ARRAY_INDEX:
                # Handle index array separately
                continue
            else:
                # Copy other arrays as-is (they might not be per-vertex)
                new_data = old_data.duplicate()

            new_arrays[attr] = new_data

    # Update indices - only keep triangles where all vertices are kept
    if indices and indices.size() > 0:
        var new_indices = PackedInt32Array()

        for i in range(0, indices.size(), 3):
            var a = indices[i]
            var b = indices[i + 1]
            var c = indices[i + 2]

            # Only keep triangles where all three vertices are in the keep list
            if index_remap.has(a) and index_remap.has(b) and index_remap.has(c):
                new_indices.append(index_remap[a])
                new_indices.append(index_remap[b])
                new_indices.append(index_remap[c])

        new_arrays[Mesh.ARRAY_INDEX] = new_indices

    return new_arrays

func clear_all_markers(mesh_instance: MeshInstance3D):
    # Remove any existing markers
    for child in mesh_instance.get_children():
        if child.has_meta("is_vertex_marker"):
            child.queue_free()
    vertex_markers.clear()
