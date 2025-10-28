@tool
extends EditorScript

func _run():
    var scene_root = get_editor_interface().get_edited_scene_root()
    if scene_root == null:
        push_error("No scene open in editor!")
        return

    # Find all MeshInstance3D nodes
    var mesh_instances = find_mesh_instances(scene_root)

    if mesh_instances.is_empty():
        push_warning("No MeshInstance3D nodes found in the scene.")
        return

    print("Found %d MeshInstance3D nodes" % mesh_instances.size())

    # Process each mesh instance
    for mesh_instance in mesh_instances:
        setup_skin_for_mesh_instance(mesh_instance)

func find_mesh_instances(node: Node) -> Array:
    var mesh_instances = []

    if node is MeshInstance3D:
        mesh_instances.append(node)

    for child in node.get_children():
        mesh_instances.append_array(find_mesh_instances(child))

    return mesh_instances

func setup_skin_for_mesh_instance(mesh_instance: MeshInstance3D):
    print("Processing mesh: %s" % mesh_instance.name)

    var mesh = mesh_instance.mesh
    if mesh == null or not (mesh is ArrayMesh):
        push_warning("MeshInstance3D '%s' has no valid ArrayMesh" % mesh_instance.name)
        return

    # Find skeleton in the scene
    var skeleton = find_skeleton(mesh_instance)
    if skeleton == null:
        push_warning("No Skeleton3D found for mesh: %s" % mesh_instance.name)
        return

    print("Found skeleton: %s with %d bones" % [skeleton.name, skeleton.get_bone_count()])

    # Create a new skin resource
    var skin = Skin.new()

    # Set up the skin with all bones from skeleton
    var bone_count = skeleton.get_bone_count()
    for bone_idx in range(bone_count):
        var bone_name = skeleton.get_bone_name(bone_idx)
        var bone_rest = skeleton.get_bone_rest(bone_idx)

        # Add bone to skin with inverse bind pose
        skin.add_bind(bone_idx, bone_rest.affine_inverse())

    # Apply the skin to the mesh instance
    mesh_instance.skin = skin
    mesh_instance.skeleton = NodePath("../" + skeleton.name)

    print("Applied skin and skeleton to mesh instance")

    # For each surface, create better weights
    for surface_idx in range(mesh.get_surface_count()):
        create_better_weights(mesh_instance, mesh, surface_idx, skeleton)

    print("Successfully set up skin for: %s" % mesh_instance.name)

func find_skeleton(node: Node) -> Skeleton3D:
    # First, check if the mesh instance has a direct skeleton child
    for child in node.get_children():
        if child is Skeleton3D:
            return child

    # If not, search upwards in the hierarchy
    var parent = node.get_parent()
    while parent != null:
        for child in parent.get_children():
            if child is Skeleton3D:
                return child
        parent = parent.get_parent()

    # Finally, search the entire scene
    var scene_root = node
    while scene_root.get_parent() != null:
        scene_root = scene_root.get_parent()

    return find_skeleton_in_children(scene_root)

func find_skeleton_in_children(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node

    for child in node.get_children():
        var result = find_skeleton_in_children(child)
        if result != null:
            return result

    return null

func create_better_weights(mesh_instance: MeshInstance3D, mesh: ArrayMesh, surface_idx: int, skeleton: Skeleton3D):
    # Get all surface data
    var surface_arrays = mesh.surface_get_arrays(surface_idx)

    var vertices = surface_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
    if vertices == null or vertices.size() == 0:
        push_warning("Surface %d has no vertices" % surface_idx)
        return

    print("Processing surface %d with %d vertices" % [surface_idx, vertices.size()])

    # Create new bone and weight arrays
    var MAX_INFLUENCES = 4
    var new_bones = PackedInt32Array()
    var new_weights = PackedFloat32Array()
    new_bones.resize(vertices.size() * MAX_INFLUENCES)
    new_weights.resize(vertices.size() * MAX_INFLUENCES)

    # Initialize with zeros
    for i in range(vertices.size() * MAX_INFLUENCES):
        new_bones[i] = 0
        new_weights[i] = 0.0

    # Calculate weights for each vertex based on body regions
    for vertex_idx in range(vertices.size()):
        var vertex_pos = vertices[vertex_idx]
        var bone_weights = assign_weights_simple(vertex_pos, skeleton)

        # Apply to arrays
        for i in range(min(MAX_INFLUENCES, bone_weights.size())):
            var array_idx = vertex_idx * MAX_INFLUENCES + i
            new_bones[array_idx] = bone_weights[i].bone_idx
            new_weights[array_idx] = bone_weights[i].weight

    # Update the surface arrays with new bone weights
    surface_arrays[Mesh.ARRAY_BONES] = new_bones
    surface_arrays[Mesh.ARRAY_WEIGHTS] = new_weights

    # Create a new mesh to avoid modifying the original directly
    var new_mesh = ArrayMesh.new()

    # Copy all surfaces to the new mesh
    for i in range(mesh.get_surface_count()):
        var orig_arrays = mesh.surface_get_arrays(i)
        var orig_primitive = mesh.surface_get_primitive_type(i)
        var orig_blend_shapes = mesh.surface_get_blend_shape_arrays(i)
        var orig_format = mesh.surface_get_format(i)
        var orig_material = mesh.surface_get_material(i)
        var orig_name = mesh.surface_get_name(i)

        # For the current surface, use our modified arrays
        if i == surface_idx:
            new_mesh.add_surface_from_arrays(orig_primitive, surface_arrays, orig_blend_shapes, {}, orig_format)
        else:
            new_mesh.add_surface_from_arrays(orig_primitive, orig_arrays, orig_blend_shapes, {}, orig_format)

        # Set material and name
        var new_surface_idx = new_mesh.get_surface_count() - 1
        if orig_material != null:
            new_mesh.surface_set_material(new_surface_idx, orig_material)
        if orig_name != "":
            new_mesh.surface_set_name(new_surface_idx, orig_name)

    # Replace the mesh
    mesh_instance.mesh = new_mesh

# Simpler version - assign to major bones only
func assign_weights_simple(vertex_pos: Vector3, skeleton: Skeleton3D) -> Array:
    var bone_weights = []

    # Get bone indices by name
    var hips_idx = find_bone_by_name(skeleton, "Hips")
    var spine_idx = find_bone_by_name(skeleton, "Spine")
    var spine1_idx = find_bone_by_name(skeleton, "Spine1")
    var spine2_idx = find_bone_by_name(skeleton, "Spine2")
    var neck_idx = find_bone_by_name(skeleton, "Neck")
    var head_idx = find_bone_by_name(skeleton, "Head")

    var height = vertex_pos.y

    if height > 1.2:  # Head
        if head_idx != -1:
            bone_weights.append({"bone_idx": head_idx, "weight": 1.0})
    elif height > 0.8:  # Upper spine/neck
        if neck_idx != -1:
            bone_weights.append({"bone_idx": neck_idx, "weight": 1.0})
    elif height > 0.5:  # Mid spine
        if spine2_idx != -1:
            bone_weights.append({"bone_idx": spine2_idx, "weight": 1.0})
    elif height > 0.3:  # Lower spine
        if spine1_idx != -1:
            bone_weights.append({"bone_idx": spine1_idx, "weight": 1.0})
    elif height > 0.1:  # Hips
        if spine_idx != -1:
            bone_weights.append({"bone_idx": spine_idx, "weight": 1.0})
    else:  # Root
        if hips_idx != -1:
            bone_weights.append({"bone_idx": hips_idx, "weight": 1.0})

    return bone_weights

func find_bone_by_name(skeleton: Skeleton3D, bone_name: String) -> int:
    for i in range(skeleton.get_bone_count()):
        if skeleton.get_bone_name(i) == bone_name:
            return i
    return -1

func find_closest_bones(vertex_pos: Vector3, skeleton: Skeleton3D) -> Array:
    var bone_weights = []
    var bone_count = skeleton.get_bone_count()

    # Find distances to all bones
    for bone_idx in range(bone_count):
        var bone_rest = skeleton.get_bone_rest(bone_idx)
        var bone_pos = bone_rest.origin

        # Calculate distance to bone
        var distance = vertex_pos.distance_to(bone_pos)

        bone_weights.append({
            "bone_idx": bone_idx,
            "distance": distance
        })

    # Sort by distance (closest first)
    bone_weights.sort_custom(func(a, b): return a.distance < b.distance)

    # Take the closest few bones
    var closest_bones = bone_weights.slice(0, min(4, bone_weights.size()))

    # Convert distances to weights (closer = higher weight)
    var total_inv_distance = 0.0
    for bone in closest_bones:
        # Avoid division by zero
        var inv_distance = 1.0 / (bone.distance + 0.001)
        total_inv_distance += inv_distance
        bone.weight = inv_distance

    # Normalize weights
    if total_inv_distance > 0:
        for bone in closest_bones:
            bone.weight /= total_inv_distance
    else:
        # Fallback: assign everything to the first bone
        if closest_bones.size() > 0:
            closest_bones[0].weight = 1.0
            for i in range(1, closest_bones.size()):
                closest_bones[i].weight = 0.0

    return closest_bones
