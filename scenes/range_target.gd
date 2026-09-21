class_name RangeTarget
extends StaticBody3D
## Knock-down steel popper for the debug shooting range.
## Falls flat when hit hard enough, pops back up after reset_delay.

signal target_down(target: RangeTarget)
signal target_up(target: RangeTarget)

@export var reset_delay: float = 4.0
@export var hit_energy_threshold: float = 150.0  # Joules

var hits: int = 0
var is_down: bool = false

var _fall_t: float = 0.0
var _fall_target: float = 0.0
var _reset_timer: float = 0.0
var _flash: float = 0.0
var _base_origin: Vector3
var _base_basis: Basis
var _hinge: Vector3
var _mat: StandardMaterial3D

func _ready() -> void:
	_base_origin = global_position
	_base_basis = global_transform.basis
	_hinge = _base_origin + Vector3(0, 0.05, 0.1)
	var mi = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mi and mi.get_active_material(0) is StandardMaterial3D:
		_mat = (mi.get_active_material(0) as StandardMaterial3D).duplicate()
		_mat.emission_enabled = true
		_mat.emission = Color.WHITE
		_mat.emission_energy_multiplier = 0.0
		mi.material_override = _mat

func range_hit(impact: BallisticsImpact, _ammo: Ammo) -> void:
	_flash = 1.0
	if is_down:
		return
	if impact.hit_energy < hit_energy_threshold:
		return
	hits += 1
	is_down = true
	_fall_target = 1.0
	_reset_timer = reset_delay
	target_down.emit(self)

func _process(delta: float) -> void:
	if _fall_t != _fall_target:
		_fall_t = move_toward(_fall_t, _fall_target, delta * 6.0)
		var rot := Basis(Vector3.RIGHT, _fall_t * deg_to_rad(85.0))
		global_transform = Transform3D(rot * _base_basis, _hinge + rot * (_base_origin - _hinge))
	if is_down and _fall_target > 0.0:
		_reset_timer -= delta
		if _reset_timer <= 0.0:
			_fall_target = 0.0
			is_down = false
			target_up.emit(self)
	if _flash > 0.0:
		_flash = move_toward(_flash, 0.0, delta * 5.0)
		if _mat:
			_mat.emission_energy_multiplier = _flash * 3.0
