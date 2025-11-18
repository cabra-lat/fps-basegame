@tool
extends EditorScript

## Mesh Splitting Tool for Godot 4.5
## Splits meshes using a selected BoxMesh as an AABB mask.
##
## HOW TO USE:
## 1. Create a BoxMesh and position it to enclose the part you want to separate (e.g., the scope)
## 2. Make the mask slightly LARGER than the target part to avoid cutting through connecting geometry
## 3. Select the mask MeshInstance3D in the scene tree
## 4. Press Ctrl+Shift+X or click Run in the script editor
## 5. Original mesh will be hidden, and two new meshes created: "Inside_" and "Outside_"
## 6. Delete whichever part you don't need

@export var create_instances: bool = true
@export var aggressive_extraction: bool = false  ## If true, straddling faces go to INSIDE mesh (better for extraction)

var mask_object: MeshInstance3D
var mask_aabb: AABB
var mask_transform: Transform3D

func _run():
  var selection = EditorInterface.get_selection().get_selected_nodes()
  if selection.is_empty():
    printerr("❌ No mask selected. Please select a MeshInstance3D with a BoxMesh.")
    return

  mask_object = selection[0]
  if not mask_object is MeshInstance3D or not mask_object.mesh:
    printerr("❌ Selected node must be a MeshInstance3D with a mesh assigned.")
    return

  print("🔍 Using '%s' as mask..." % mask_object.name)
  update_mask_aabb()
  process_all_meshes()
  print("✅ Splitting complete! Original meshes hidden. Delete unwanted parts.")

func update_mask_aabb():
  mask_transform = mask_object.global_transform
  var mesh = mask_object.mesh
  if mesh:
    mask_aabb = mesh.get_aabb()
    mask_aabb = mask_transform * mask_aabb
    print("📐 Mask AABB: %s" % mask_aabb)
  else:
    mask_aabb = mask_object.get_aabb()

func process_all_meshes():
  var root = EditorInterface.get_edited_scene_root()
  if not root:
    return

  var mesh_instances = root.find_children("*", "MeshInstance3D", true, false)
  var processed = 0

  for mi in mesh_instances:
    if mi == mask_object or not mi.mesh:
      continue
    split_mesh(mi)
    processed += 1

  if processed == 0:
    print("⚠ No other MeshInstance3D nodes found to split.")
  else:
    print("✓ Processed %d meshes." % processed)

# Robustly copies all available vertex attributes
func build_attribute_arrays(arrays: Array, old_indices: Array) -> Dictionary:
  var result = {}

  # Normals
  if arrays.size() > Mesh.ARRAY_NORMAL and arrays[Mesh.ARRAY_NORMAL] and arrays[Mesh.ARRAY_NORMAL].size() > 0:
    var old_data = arrays[Mesh.ARRAY_NORMAL]
    var new_data = PackedVector3Array()
    for idx in old_indices:
      new_data.append(old_data[idx])
    result[Mesh.ARRAY_NORMAL] = new_data

  # UV0
  if arrays.size() > Mesh.ARRAY_TEX_UV and arrays[Mesh.ARRAY_TEX_UV] and arrays[Mesh.ARRAY_TEX_UV].size() > 0:
    var old_data = arrays[Mesh.ARRAY_TEX_UV]
    var new_data = PackedVector2Array()
    for idx in old_indices:
      new_data.append(old_data[idx])
    result[Mesh.ARRAY_TEX_UV] = new_data

  # UV1 (less common, check size explicitly)
  if arrays.size() > Mesh.ARRAY_TEX_UV2 and arrays[Mesh.ARRAY_TEX_UV2] and arrays[Mesh.ARRAY_TEX_UV2].size() > 0:
    var old_data = arrays[Mesh.ARRAY_TEX_UV2]
    var new_data = PackedVector2Array()
    for idx in old_indices:
      new_data.append(old_data[idx])
    result[Mesh.ARRAY_TEX_UV2] = new_data

  # Vertex Colors
  if arrays.size() > Mesh.ARRAY_COLOR and arrays[Mesh.ARRAY_COLOR] and arrays[Mesh.ARRAY_COLOR].size() > 0:
    var old_data = arrays[Mesh.ARRAY_COLOR]
    var new_data = PackedColorArray()
    for idx in old_indices:
      new_data.append(old_data[idx])
    result[Mesh.ARRAY_COLOR] = new_data

  # Tangents (4 floats per vertex)
  if arrays.size() > Mesh.ARRAY_TANGENT and arrays[Mesh.ARRAY_TANGENT] and arrays[Mesh.ARRAY_TANGENT].size() > 0:
    var old_data = arrays[Mesh.ARRAY_TANGENT]
    var new_data = PackedFloat32Array()
    for idx in old_indices:
      new_data.append(old_data[idx * 4 + 0])
      new_data.append(old_data[idx * 4 + 1])
      new_data.append(old_data[idx * 4 + 2])
      new_data.append(old_data[idx * 4 + 3])
    result[Mesh.ARRAY_TANGENT] = new_data

  return result

func split_mesh(mesh_instance: MeshInstance3D):
  var original_mesh = mesh_instance.mesh
  if not original_mesh:
    return

  var parent = mesh_instance.get_parent()
  var world_transform = mesh_instance.global_transform
  var has_any_inside = false
  var has_any_outside = false

  var inside_mesh = ArrayMesh.new()
  var outside_mesh = ArrayMesh.new()

  # Process ALL surfaces
  for surface_idx in range(original_mesh.get_surface_count()):
    var arrays = original_mesh.surface_get_arrays(surface_idx)
    var vertices = arrays[Mesh.ARRAY_VERTEX]
    var indices = arrays[Mesh.ARRAY_INDEX]

    if not indices or indices.size() % 3 != 0:
      print("⚠ Surface %d of mesh '%s' has no valid indices. Skipping." % [surface_idx, mesh_instance.name])
      continue

    # Get material for this surface
    var surface_material = original_mesh.surface_get_material(surface_idx)

    # Convert vertices to world space for classification
    var world_vertices = PackedVector3Array()
    for v in vertices:
      world_vertices.append(world_transform * v)

    # Classify each vertex as inside or outside
    var is_inside = {}  # Original index -> bool
    var inside_indices = []  # List of original indices that are inside
    var outside_indices = []  # List of original indices that are outside

    for i in range(vertices.size()):
      if mask_aabb.has_point(world_vertices[i]):
        is_inside[i] = true
        inside_indices.append(i)
      else:
        is_inside[i] = false
        outside_indices.append(i)

    # Handle completely inside/outside surfaces
    if inside_indices.is_empty():
      print("  ℹ Surface %d is completely outside mask. Adding to outside mesh." % surface_idx)
      outside_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
      if surface_material:
        outside_mesh.surface_set_material(outside_mesh.get_surface_count() - 1, surface_material)
      has_any_outside = true
      continue
    elif outside_indices.is_empty():
      print("  ℹ Surface %d is completely inside mask. Adding to inside mesh." % surface_idx)
      inside_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
      if surface_material:
        inside_mesh.surface_set_material(inside_mesh.get_surface_count() - 1, surface_material)
      has_any_inside = true
      continue

    # Build new vertex arrays (reordered)
    var inside_vertices = PackedVector3Array()
    var outside_vertices = PackedVector3Array()

    for idx in inside_indices:
      inside_vertices.append(vertices[idx])
    for idx in outside_indices:
      outside_vertices.append(vertices[idx])

    # Build index remapping: Original Index -> New Index
    var inside_remap = {}
    var outside_remap = {}
    for new_idx in range(inside_indices.size()):
      inside_remap[inside_indices[new_idx]] = new_idx
    for new_idx in range(outside_indices.size()):
      outside_remap[outside_indices[new_idx]] = new_idx

    # Separate triangles - ONLY keep faces wholly on one side
    var inside_triangles = PackedInt32Array()
    var outside_triangles = PackedInt32Array()
    var discarded_faces = 0

    for i in range(0, indices.size(), 3):
      var a = indices[i]
      var b = indices[i + 1]
      var c = indices[i + 2]

      var a_in = is_inside.get(a, false)
      var b_in = is_inside.get(b, false)
      var c_in = is_inside.get(c, false)

      if a_in and b_in and c_in:
        # All vertices inside - SAFE to remap
        inside_triangles.append(inside_remap[a])
        inside_triangles.append(inside_remap[b])
        inside_triangles.append(inside_remap[c])
      elif (not a_in) and (not b_in) and (not c_in):
        # All vertices outside - SAFE to remap
        outside_triangles.append(outside_remap[a])
        outside_triangles.append(outside_remap[b])
        outside_triangles.append(outside_remap[c])
      else:
        # Face straddles boundary - can't safely remap, so discard
        discarded_faces += 1
        continue

    if discarded_faces > 0:
      print("  ⚠ Surface %d: Discarded %d faces that crossed mask boundary" % [surface_idx, discarded_faces])
      print("    → TIP: If this removes important parts, enlarge your mask slightly")

    # Build final mesh arrays for INSIDE part
    if inside_vertices.size() > 0 and inside_triangles.size() > 0:
      var inside_arrays = []
      inside_arrays.resize(Mesh.ARRAY_MAX)
      inside_arrays[Mesh.ARRAY_VERTEX] = inside_vertices
      inside_arrays[Mesh.ARRAY_INDEX] = inside_triangles

      # Copy all available attributes (normals, UVs, etc.)
      var inside_attrs = build_attribute_arrays(arrays, inside_indices)
      for attr_type in inside_attrs:
        inside_arrays[attr_type] = inside_attrs[attr_type]

      inside_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, inside_arrays)
      if surface_material:
        inside_mesh.surface_set_material(inside_mesh.get_surface_count() - 1, surface_material)
      has_any_inside = true

    # Build final mesh arrays for OUTSIDE part
    if outside_vertices.size() > 0 and outside_triangles.size() > 0:
      var outside_arrays = []
      outside_arrays.resize(Mesh.ARRAY_MAX)
      outside_arrays[Mesh.ARRAY_VERTEX] = outside_vertices
      outside_arrays[Mesh.ARRAY_INDEX] = outside_triangles

      # Copy all available attributes (normals, UVs, etc.)
      var outside_attrs = build_attribute_arrays(arrays, outside_indices)
      for attr_type in outside_attrs:
        outside_arrays[attr_type] = outside_attrs[attr_type]

      outside_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, outside_arrays)
      if surface_material:
        outside_mesh.surface_set_material(outside_mesh.get_surface_count() - 1, surface_material)
      has_any_outside = true

  # Create new nodes in the scene
  if create_instances and (has_any_inside or has_any_outside):
    if has_any_inside:
      var inside_node = MeshInstance3D.new()
      inside_node.mesh = inside_mesh
      inside_node.name = "Inside_%s" % mesh_instance.name
      parent.add_child(inside_node, true)  # Keep global transform
      inside_node.owner = get_scene()  # Make sure it's saved

    if has_any_outside:
      var outside_node = MeshInstance3D.new()
      outside_node.mesh = outside_mesh
      outside_node.name = "Outside_%s" % mesh_instance.name
      parent.add_child(outside_node, true)
      outside_node.owner = get_scene()

    mesh_instance.hide()
    print("  ✓ Successfully split '%s' → Inside_%s & Outside_%s" % [mesh_instance.name, mesh_instance.name, mesh_instance.name])
