class_name NpcDebug
extends RefCounted
## ImmediateMesh debug renderer for NpcBot (src/npcs lane).
##
## Pure presentation: builds the vision cone, hearing circle, chosen cover and
## squad-shared target. bot.gd owns the state and passes a params Dictionary;
## this keeps the drawing maths out of the bot file.

## Create the debug MeshInstance3D child; returns [mesh_instance, immediate_mesh].
static func setup(parent: Node3D, eye_height: float) -> Array:
	var mesh := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.name = "PerceptionDebug"
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.mesh = mesh
	mi.material_override = m
	mi.position = Vector3(0, eye_height, 0)
	parent.add_child(mi)
	return [mi, mesh]


## Rebuild the debug geometry. Recognised params (all optional):
##   fov_degrees, sight_range, noise_radius_scale, hearing_loudness, eye_height,
##   cone_color, hearing_color, cover (world), cover_color, cover_line_color,
##   squad_has, squad_pos, squad_color.
static func draw(mi: MeshInstance3D, mesh: ImmediateMesh, p: Dictionary) -> void:
	if mi == null or mesh == null:
		return
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var eye := float(p.get("eye_height", 1.5))
	var half := deg_to_rad(float(p.get("fov_degrees", 110.0))) * 0.5
	var r := float(p.get("sight_range", 60.0))
	var col: Color = p.get("cone_color", Color(0.9, 0.9, 0.9, 0.6))
	_line(mesh, Vector3.ZERO, _arc(-half, r), col)
	_line(mesh, Vector3.ZERO, _arc(half, r), col)
	var seg := 24
	for i in seg:
		var a0 := -half + 2.0 * half * float(i) / float(seg)
		var a1 := -half + 2.0 * half * float(i + 1) / float(seg)
		_line(mesh, _arc(a0, r), _arc(a1, r), col)
	# Hearing radius for the reference loudness, drawn on the ground.
	var h := float(p.get("noise_radius_scale", 30.0)) \
		* float(p.get("hearing_loudness", 1.0))
	var gy := -eye + 0.05
	var hc: Color = p.get("hearing_color", Color(0.2, 0.7, 1.0, 0.5))
	var seg2 := 36
	for i in seg2:
		var b0 := TAU * float(i) / float(seg2)
		var b1 := TAU * float(i + 1) / float(seg2)
		_line(mesh, Vector3(cos(b0) * h, gy, sin(b0) * h),
			Vector3(cos(b1) * h, gy, sin(b1) * h), hc)
	# Chosen cover point + line to it.
	var cover: Vector3 = p.get("cover", Vector3.ZERO)
	if cover != Vector3.ZERO:
		var cl := mi.to_local(cover)
		_marker(mesh, cl, 0.5, p.get("cover_color", Color(0.2, 1.0, 0.4, 0.9)))
		_line(mesh, Vector3.ZERO, cl,
			p.get("cover_line_color", Color(0.2, 1.0, 0.4, 0.6)))
	# Squad-shared target (teammate's last known contact).
	if p.get("squad_has", false):
		_marker(mesh, mi.to_local(p.get("squad_pos", Vector3.ZERO)), 0.6,
			p.get("squad_color", Color(1.0, 0.2, 1.0, 0.9)))
	mesh.surface_end()


## Small ground square outline (cheap marker).
static func _marker(mesh: ImmediateMesh, p: Vector3, s: float, c: Color) -> void:
	var a := p + Vector3(-s, 0, -s)
	var b := p + Vector3(s, 0, -s)
	var d := p + Vector3(s, 0, s)
	var e := p + Vector3(-s, 0, s)
	_line(mesh, a, b, c)
	_line(mesh, b, d, c)
	_line(mesh, d, e, c)
	_line(mesh, e, a, c)


static func _arc(angle: float, r: float) -> Vector3:
	return Vector3(sin(angle) * r, 0.0, -cos(angle) * r)


static func _line(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Color) -> void:
	mesh.surface_set_color(c)
	mesh.surface_add_vertex(a)
	mesh.surface_set_color(c)
	mesh.surface_add_vertex(b)
