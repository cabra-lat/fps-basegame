@tool
extends EditorScript

func _run():
    # Get the edited scene root
  var scene_root = get_editor_interface().get_edited_scene_root()
  if scene_root == null:
    push_error("No scene open in editor!")
    return

    # Find all MeshInstance3D nodes
  var mesh_instances = find_mesh_instances(scene_root)

  if mesh_instances.is_empty():
    push_warning("No MeshInstance3D nodes found in the scene.")
    return

  print("Processing %d MeshInstance3D nodes..." % mesh_instances.size())

  var processed_count = 0

  for mesh_instance in mesh_instances:
    if apply_transform_to_mesh(mesh_instance):
      processed_count += 1

  print("Successfully applied transforms to %d/%d meshes" % [processed_count, mesh_instances.size()])

func find_mesh_instances(node: Node) -> Array:
  var mesh_instances = []

    # Check if current node is a MeshInstance3D
  if node is MeshInstance3D:
    mesh_instances.append(node)

    # Recursively check children
  for child in node.get_children():
    mesh_instances.append_array(find_mesh_instances(child))

  return mesh_instances

func apply_transform_to_mesh(mesh_instance: MeshInstance3D) -> bool:
  var mesh = mesh_instance.mesh

  if mesh == null:
    push_warning("MeshInstance3D '%s' has no mesh assigned" % mesh_instance.name)
    return false

  if not (mesh is ArrayMesh):
    push_warning("Mesh '%s' is not an ArrayMesh, skipping" % mesh_instance.name)
    return false

  var transform = mesh_instance.transform

    # Skip if transform is identity (no transformation applied)
  if transform == Transform3D.IDENTITY:
    print("MeshInstance3D '%s' has identity transform, skipping" % mesh_instance.name)
    return false

    # Create a transformed version of the mesh
  var transformed_mesh = transform_mesh(mesh, transform)
  if transformed_mesh == null:
    push_error("Failed to transform mesh for '%s'" % mesh_instance.name)
    return false

    # Apply the transformed mesh and reset the transform
  mesh_instance.mesh = transformed_mesh
  mesh_instance.transform = Transform3D.IDENTITY

  print("Applied transform to mesh: %s" % mesh_instance.name)
  return true

func transform_mesh(original_mesh: ArrayMesh, transform: Transform3D) -> ArrayMesh:
  var array_mesh = original_mesh as ArrayMesh

    # Create a new mesh to hold the transformed data
  var new_mesh = ArrayMesh.new()

    # Process each surface
  for surface_index in range(array_mesh.get_surface_count()):
    var surface_arrays = array_mesh.surface_get_arrays(surface_index)
    var surface_format = array_mesh.surface_get_format(surface_index)

    if surface_arrays.is_empty():
      continue

        # Transform vertices
    var vertices = surface_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
    if vertices != null:
      var transformed_vertices = PackedVector3Array()
      for vertex in vertices:
        transformed_vertices.append(transform * vertex)
      surface_arrays[Mesh.ARRAY_VERTEX] = transformed_vertices

        # Transform normals (need to use the basis without translation)
    var normals = surface_arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
    if normals != null:
      var transformed_normals = PackedVector3Array()
      var normal_transform = transform.basis.inverse().transposed()
      for normal in normals:
        transformed_normals.append(normal_transform * normal)
      surface_arrays[Mesh.ARRAY_NORMAL] = transformed_normals

        # Transform tangents
    var tangents = surface_arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array
    if tangents != null and tangents.size() > 0:
      var transformed_tangents = PackedFloat32Array()
      var tangent_basis = transform.basis
      for i in range(0, tangents.size(), 4):
        var tangent = Vector3(tangents[i], tangents[i+1], tangents[i+2])
        var transformed_tangent = tangent_basis * tangent
        transformed_tangents.append(transformed_tangent.x)
        transformed_tangents.append(transformed_tangent.y)
        transformed_tangents.append(transformed_tangent.z)
        transformed_tangents.append(tangents[i+3]) # Keep the handedness
      surface_arrays[Mesh.ARRAY_TANGENT] = transformed_tangents

        # Add the transformed surface to the new mesh
    new_mesh.add_surface_from_arrays(
      array_mesh.surface_get_primitive_type(surface_index),
      surface_arrays,
      [],
      {},
      surface_format
    )

        # Copy surface name and material if they exist
    var surface_name = array_mesh.surface_get_name(surface_index)
    if surface_name != "":
      new_mesh.surface_set_name(surface_index, surface_name)

    var material = array_mesh.surface_get_material(surface_index)
    if material != null:
      new_mesh.surface_set_material(surface_index, material)

  return new_mesh
