@tool
extends EditorScript

func _run():
    var scene_root = get_editor_interface().get_edited_scene_root()
    if scene_root == null:
        push_error("No scene open in editor!")
        return

    # Find all Skeleton3D nodes
    var skeletons = find_skeletons(scene_root)

    if skeletons.is_empty():
        push_warning("No Skeleton3D nodes found in the scene.")
        return

    print("Found %d Skeleton3D nodes" % skeletons.size())

    for skeleton in skeletons:
        symmetrize_skeleton(skeleton)

func find_skeletons(node: Node) -> Array:
    var skeletons = []

    if node is Skeleton3D:
        skeletons.append(node)

    for child in node.get_children():
        skeletons.append_array(find_skeletons(child))

    return skeletons

func symmetrize_skeleton(skeleton: Skeleton3D):
    print("Processing skeleton: %s" % skeleton.name)

    # Get all bone names
    var bone_count = skeleton.get_bone_count()
    if bone_count == 0:
        push_warning("Skeleton '%s' has no bones" % skeleton.name)
        return

    var left_bones = []
    var right_bones = []
    var center_bones = []

    # Categorize bones
    for bone_idx in range(bone_count):
        var bone_name = skeleton.get_bone_name(bone_idx)

        if is_left_bone(bone_name):
            left_bones.append(bone_idx)
        elif is_right_bone(bone_name):
            right_bones.append(bone_idx)
        else:
            center_bones.append(bone_idx)

    print("Found %d left bones, %d right bones, %d center bones" % [
        left_bones.size(), right_bones.size(), center_bones.size()
    ])

    # Process left bones to create/update right bones
    var created_count = 0
    var updated_count = 0

    for left_bone_idx in left_bones:
        var left_bone_name = skeleton.get_bone_name(left_bone_idx)
        var right_bone_name = get_right_bone_name(left_bone_name)

        # Check if right bone already exists
        var right_bone_idx = skeleton.find_bone(right_bone_name)

        if right_bone_idx == -1:
            # Create new bone
            right_bone_idx = create_symmetric_bone(skeleton, left_bone_idx, right_bone_name)
            if right_bone_idx != -1:
                created_count += 1
                print("Created bone: %s" % right_bone_name)
        else:
            # Update existing bone
            if update_bone_symmetry(skeleton, left_bone_idx, right_bone_idx):
                updated_count += 1
                print("Updated bone: %s" % right_bone_name)

    print("Symmetrized skeleton '%s': Created %d bones, Updated %d bones" % [
        skeleton.name, created_count, updated_count
    ])

func is_left_bone(bone_name: String) -> bool:
    var left_indicators = ["Left", "left", "L_", "_L", ".L", "L."]
    for indicator in left_indicators:
        if indicator in bone_name:
            return true
    return false

func is_right_bone(bone_name: String) -> bool:
    var right_indicators = ["Right", "right", "R_", "_R", ".R", "R."]
    for indicator in right_indicators:
        if indicator in bone_name:
            return true
    return false

func get_right_bone_name(left_bone_name: String) -> String:
    var replacements = {
        "Left": "Right",
        "left": "right",
        "L_": "R_",
        "_L": "_R",
        ".L": ".R",
        "L.": "R."
    }

    var right_name = left_bone_name
    for left_pattern in replacements:
        var right_pattern = replacements[left_pattern]
        if left_pattern in right_name:
            right_name = right_name.replace(left_pattern, right_pattern)
            break

    return right_name

func create_symmetric_bone(skeleton: Skeleton3D, source_bone_idx: int, new_bone_name: String) -> int:
    # Get source bone data
    var source_parent_idx = skeleton.get_bone_parent(source_bone_idx)
    var source_rest = skeleton.get_bone_rest(source_bone_idx)
    var source_pose = skeleton.get_bone_pose(source_bone_idx)

    # Create new bone
    var new_bone_idx = skeleton.get_bone_count()
    skeleton.add_bone(new_bone_name)

    # Set parent (if any)
    if source_parent_idx != -1:
        var source_parent_name = skeleton.get_bone_name(source_parent_idx)
        var new_parent_name = get_right_bone_name(source_parent_name)
        var new_parent_idx = skeleton.find_bone(new_parent_name)

        # Use original parent if right parent doesn't exist yet
        if new_parent_idx == -1:
            new_parent_idx = source_parent_idx

        skeleton.set_bone_parent(new_bone_idx, new_parent_idx)

    # Apply symmetric transform
    var symmetric_rest = get_symmetric_transform(source_rest)
    var symmetric_pose = get_symmetric_transform(source_pose)

    skeleton.set_bone_rest(new_bone_idx, symmetric_rest)
    skeleton.set_bone_pose_position(new_bone_idx, symmetric_pose.origin)
    skeleton.set_bone_pose_rotation(new_bone_idx, symmetric_pose.basis.get_rotation_quaternion())
    skeleton.set_bone_pose_scale(new_bone_idx, symmetric_pose.basis.get_scale())

    return new_bone_idx

func update_bone_symmetry(skeleton: Skeleton3D, left_bone_idx: int, right_bone_idx: int) -> bool:
    var left_rest = skeleton.get_bone_rest(left_bone_idx)
    var left_pose = skeleton.get_bone_pose(left_bone_idx)

    var symmetric_rest = get_symmetric_transform(left_rest)
    var symmetric_pose = get_symmetric_transform(left_pose)

    skeleton.set_bone_rest(right_bone_idx, symmetric_rest)
    skeleton.set_bone_pose_position(right_bone_idx, symmetric_pose.origin)
    skeleton.set_bone_pose_rotation(right_bone_idx, symmetric_pose.basis.get_rotation_quaternion())
    skeleton.set_bone_pose_scale(right_bone_idx, symmetric_pose.basis.get_scale())

    return true

func get_symmetric_transform(transform: Transform3D) -> Transform3D:
    # Flip across X-axis (assuming character faces -Z, right is +X)
    var symmetric_basis = transform.basis
    var symmetric_origin = transform.origin

    # Flip X coordinate
    symmetric_origin.x = -symmetric_origin.x

    # For the basis, we need to flip the rotation appropriately
    # This handles the mirroring of rotations
    var rotation = symmetric_basis.get_rotation_quaternion()
    var euler = rotation.get_euler()

    # Flip y and z rotations to maintain symmetry
    euler.y = -euler.y
    euler.z = -euler.z

    symmetric_basis = Basis.from_euler(euler)

    return Transform3D(symmetric_basis, symmetric_origin)
