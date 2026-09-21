class_name HitFlash
extends RefCounted
## Transient impact spark, shared by arena_manager and debug_range (was
## copy-pasted in both). One cached mesh/material for the whole process — no
## per-hit resource allocation. The one-shot tween -> queue_free is intentional
## (a self-freeing transient FX node).

static var _mesh: SphereMesh
static var _mat: StandardMaterial3D

static func spawn(parent: Node, pos: Vector3) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	if _mesh == null:
		_mesh = SphereMesh.new()
		_mesh.radius = 0.06
		_mesh.height = 0.12
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.albedo_color = Color(1.0, 0.9, 0.5)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = _mat
	parent.add_child(mi)
	mi.global_position = pos
	var tween := parent.create_tween()
	tween.tween_property(mi, "scale", Vector3.ONE * 2.5, 0.18)
	tween.tween_callback(mi.queue_free)
