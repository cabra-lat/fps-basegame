@tool
extends EditorScript

func _run():
    var scene_root = get_editor_interface().get_edited_scene_root()
    if not scene_root:
        push_error("No scene open!")
        return

    # Find the skeleton
    var skeleton = find(scene_root, Skeleton3D)
    if not skeleton:
        push_error("No Skeleton3D found in scene!")
        return

    print("Found skeleton: " + skeleton.name)

    # Find ALL MeshInstance3D nodes
    var mesh_instances = find_all(scene_root, MeshInstance3D)
    if mesh_instances.is_empty():
        push_error("No MeshInstance3D nodes found!")
        return

    print("Found %d MeshInstance3D nodes" % mesh_instances.size())

    # Create skin resource once
    var skin = Skin.new()
    for i in range(skeleton.get_bone_count()):
        skin.add_bind(i, skeleton.get_bone_rest(i).affine_inverse())

    # Apply to ALL mesh instances
    for mesh_instance in mesh_instances:
        setup_mesh_skin(mesh_instance, skeleton, skin)

    print("Applied skin to all %d meshes" % mesh_instances.size())

# Your find function for single node
func find(parent, type):
    for child in parent.get_children():
        if is_instance_of(child, type):
            return child
        var grandchild = find(child, type)
        if grandchild != null:
            return grandchild
    return null

# New function to find ALL nodes of a type
func find_all(parent, type):
    var results = []
    for child in parent.get_children():
        if is_instance_of(child, type):
            results.append(child)
        results.append_array(find_all(child, type))
    return results

func setup_mesh_skin(mesh_instance: MeshInstance3D, skeleton: Skeleton3D, skin: Skin):
    print("Setting up skin for: " + mesh_instance.name)

    # Apply the skin to this mesh instance
    mesh_instance.skin = skin
    mesh_instance.skeleton = NodePath("../" + skeleton.name)

    # Set all weights to root bone for this mesh
    set_all_weights_to_bone(mesh_instance, 0)

func set_all_weights_to_bone(mesh_instance: MeshInstance3D, bone_index: int):
    var mesh = mesh_instance.mesh
    if not mesh or not (mesh is ArrayMesh):
        print("  - Skipping: Not an ArrayMesh")
        return

    # Create a duplicate to avoid modifying the original
    var new_mesh = mesh.duplicate()

    # Process each surface
    for surface_idx in range(new_mesh.get_surface_count()):
        set_surface_weights_to_bone(new_mesh, surface_idx, bone_index)

    # Apply the modified mesh
    mesh_instance.mesh = new_mesh
    print("  - Applied weights to bone %d" % bone_index)

func set_surface_weights_to_bone(mesh: ArrayMesh, surface_idx: int, bone_index: int):
    var surface_arrays = mesh.surface_get_arrays(surface_idx)
    var vertices = surface_arrays[Mesh.ARRAY_VERTEX]

    if not vertices or vertices.size() == 0:
        return

    # Create bone weights array (4 influences per vertex)
    var bone_count = 4
    var bones = PackedInt32Array()
    var weights = PackedFloat32Array()

    bones.resize(vertices.size() * bone_count)
    weights.resize(vertices.size() * bone_count)

    # Set all vertices to use the specified bone with 100% weight
    for i in range(vertices.size()):
        for j in range(bone_count):
            var idx = i * bone_count + j
            if j == 0:
                # First influence: our selected bone with 100% weight
                bones[idx] = bone_index
                weights[idx] = 1.0
            else:
                # Other influences: zero weight
                bones[idx] = 0
                weights[idx] = 0.0

    # Update the surface arrays
    surface_arrays[Mesh.ARRAY_BONES] = bones
    surface_arrays[Mesh.ARRAY_WEIGHTS] = weights

    # Get surface properties
    var primitive = mesh.surface_get_primitive_type(surface_idx)
    var blend_shapes = mesh.surface_get_blend_shape_arrays(surface_idx)
    var format = mesh.surface_get_format(surface_idx)
    var material = mesh.surface_get_material(surface_idx)
    var name = mesh.surface_get_name(surface_idx)

    # Remove and recreate the surface
    mesh.surface_remove(surface_idx)
    mesh.add_surface_from_arrays(primitive, surface_arrays, blend_shapes, {}, format)

    # Restore material and name
    var new_idx = mesh.get_surface_count() - 1
    if material:
        mesh.surface_set_material(new_idx, material)
    if name:
        mesh.surface_set_name(new_idx, name)
