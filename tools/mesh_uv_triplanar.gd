@tool
extends EditorScript

func _run():
    # Get the selected MeshInstance3D
    var selected = EditorInterface.get_selection().get_selected_nodes()
    if selected.size() == 0:
        push_error("No node selected!")
        return

    var mesh_instance = selected[0]
    if not mesh_instance is MeshInstance3D:
        push_error("Selected node is not a MeshInstance3D!")
        return

    var mesh = mesh_instance.mesh
    if mesh == null:
        push_error("MeshInstance3D has no mesh!")
        return

    # Create a copy of the mesh to modify
    var new_mesh = ArrayMesh.new()

    # Process each surface
    for surface_idx in range(mesh.get_surface_count()):
        var arrays = mesh.surface_get_arrays(surface_idx)
        var material = mesh.surface_get_material(surface_idx)

        # Get the arrays we need
        var vertices = arrays[Mesh.ARRAY_VERTEX]
        var normals = arrays[Mesh.ARRAY_NORMAL]
        var new_uvs = PackedVector2Array()

        if vertices == null or normals == null:
            push_error("Mesh doesn't have vertices or normals!")
            continue

        # Create new UVs based on vertex positions and normals
        for i in range(vertices.size()):
            var vertex = vertices[i]
            var normal = normals[i]

            # Determine which face this vertex belongs to based on normal
            var abs_normal = normal.abs()
            var max_axis = 0
            var max_value = abs_normal.x

            if abs_normal.y > max_value:
                max_axis = 1
                max_value = abs_normal.y
            if abs_normal.z > max_value:
                max_axis = 2

            var uv = Vector2()

            if max_axis == 2:  # Z axis (front/back)
                if normal.z > 0:  # Front face
                    # Front texture region: (0,0) to (0.5, 0.5)
                    uv.x = remap(vertex.x, -1.0, 1.0, 0.0, 0.5)
                    uv.y = remap(vertex.y, -1.0, 1.0, 0.0, 0.5)
                else:  # Back face
                    # Back texture region: (0.5, 0) to (1.0, 0.5)
                    uv.x = remap(vertex.x, -1.0, 1.0, 0.5, 1.0)
                    uv.y = remap(vertex.y, -1.0, 1.0, 0.0, 0.5)
            else:  # X or Y axis (sides)
                # Side texture region: (0, 0.5) to (1.0, 1.0)
                if max_axis == 0:  # X axis
                    uv.x = remap(vertex.z, -1.0, 1.0, 0.0, 1.0)
                    uv.y = remap(vertex.y, -1.0, 1.0, 0.5, 1.0)
                else:  # Y axis (top/bottom)
                    uv.x = remap(vertex.x, -1.0, 1.0, 0.0, 1.0)
                    uv.y = remap(vertex.z, -1.0, 1.0, 0.5, 1.0)

            new_uvs.append(uv)

        # Update the UV array
        arrays[Mesh.ARRAY_TEX_UV] = new_uvs

        # Add the surface to the new mesh
        new_mesh.add_surface_from_arrays(
            mesh.surface_get_primitive_type(surface_idx),
            arrays
        )

        # Apply the material
        if material != null:
            new_mesh.surface_set_material(surface_idx, material)

    # Replace the original mesh
    mesh_instance.mesh = new_mesh

    print("Mesh UVs successfully updated with texture atlas mapping!")
    print("Texture regions:")
    print("Front: (0,0) to (0.5, 0.5)")
    print("Back: (0.5, 0) to (1.0, 0.5)")
    print("Sides: (0, 0.5) to (1.0, 1.0)")

# Helper function to remap values from one range to another
func remap(value: float, from_min: float, from_max: float, to_min: float, to_max: float) -> float:
    return (value - from_min) / (from_max - from_min) * (to_max - to_min) + to_min
