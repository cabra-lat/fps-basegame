extends Node3D
## Playable debug shooting range manager: hitscan resolver with real
## ballistics, knock-down targets, score overlay, infinite reserve mags.
## No addon changes needed. Controls: WASD move, mouse aim (click captures),
## LMB fire, R reload.

const SHOT_RANGE := 300.0
const MAG_SIZE := 10

@onready var ammo_template: Ammo = preload("res://resources/ammo/5_56_45mm_SS109_VPAM_PM7.tres")
@onready var weapon_template: Weapon = preload("res://resources/weapons/M4_Carbine.tres")
@onready var player: PlayerController = $Player

var weapon: Weapon
var plate_mat: BallisticMaterial
var audio: GameAudio
var shots := 0
var hits := 0
var overlay: Label
var _step_acc := 0.0
var _flash_mesh: SphereMesh
var _flash_mat: StandardMaterial3D

func _ready() -> void:
	plate_mat = BallisticMaterial.new()
	plate_mat.name = "Range Steel"
	plate_mat.type = BallisticMaterial.Type.METAL_MEDIUM
	plate_mat.hardness = 300.0
	_setup_fps_view()
	_equip_fresh_gun()
	player.insert_ammo_feed.connect(_on_reserve_mag)
	# Audio parity with the arena (P0): the range used to be silent on purpose.
	audio = GameAudio.new()
	audio.name = "GameAudio"
	add_child(audio)
	audio.start_ambient()
	player.reloaded.connect(func(_p: PlayerController) -> void: audio.play_reload())
	for path in ["Target15m", "Target30m", "Target50m"]:
		var t = get_node_or_null(path) as RangeTarget
		if t:
			t.target_down.connect(_on_target_down)
			t.target_up.connect(_on_target_up)
	var layer := CanvasLayer.new()
	layer.name = "RangeOverlay"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "OverlayPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(-330, 8)
	panel.size = Vector2(660, 40)
	panel.add_theme_stylebox_override("panel", HudStyle.panel())
	layer.add_child(panel)
	overlay = Label.new()
	overlay.set_anchors_preset(Control.PRESET_CENTER_TOP)
	overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_theme_font_size_override("font_size", HudStyle.FONT_TITLE)
	panel.add_child(overlay)
	_refresh_overlay("WASD move - click captures mouse - R reloads")

func _physics_process(delta: float) -> void:
	# Skill rule: physics queries live in _physics_process, never _process.
	for pending in _pending_shots:
		_resolve_shot(pending[0], pending[1])
	_pending_shots.clear()
	_tick_footsteps(delta)

## Footsteps by distance timer while walking (same rule as the arena).
func _tick_footsteps(delta: float) -> void:
	if audio == null or player == null:
		return
	var v := player.velocity
	v.y = 0.0
	if not player.is_on_floor() or v.length() < 1.5:
		_step_acc = 0.0
		return
	_step_acc += v.length() * delta
	if _step_acc >= 2.4:
		_step_acc = 0.0
		audio.play_step(false)

var _pending_shots: Array = []

const BODY_HIDE_LAYER := 4 # layer 3: hidden from the FPS camera only

func _setup_fps_view() -> void:
	# Collapse the third-person arm into the head and hide the body mesh
	# from the main camera (PiP debug views keep showing it).
	var spring = player.get_node_or_null("SpringArm3D") as SpringArm3D
	if spring:
		spring.spring_length = 0.1
	var cam: Camera3D = player.camera
	if cam:
		cam.cull_mask &= ~BODY_HIDE_LAYER
	_hide_body_recursive(player)

func _hide_body_recursive(n: Node) -> void:
	if n is MeshInstance3D:
		# MOVE to the hide-layer (not add: layer membership is a match-any mask).
		(n as MeshInstance3D).layers = BODY_HIDE_LAYER
	for child in n.get_children():
		_hide_body_recursive(child)

func _make_mag() -> AmmoFeed:
	var magazine = weapon_template.ammo_feed.duplicate(true)
	for i in range(MAG_SIZE):
		var cartridge = ammo_template.duplicate(true)
		cartridge.name = ammo_template.caliber + " Round " + str(i)
		magazine.insert(cartridge)
	return magazine

func _equip_fresh_gun() -> void:
	weapon = weapon_template.duplicate(true) as Weapon
	weapon.ammo_feed = _make_mag()
	var weapon_item = InventorySystem.create_inventory_item(weapon)
	player.equipment.equip(weapon_item, "primary")
	player.equipment.equipped.connect(_on_player_equipped)
	var primary = player.equipment.get_equipped("primary")
	if not primary.is_empty():
		var equipped_weapon = primary[0].extra as Weapon
		if equipped_weapon:
			weapon = equipped_weapon
			if not weapon.cartridge_fired.is_connected(_on_cartridge_fired):
				weapon.cartridge_fired.connect(_on_cartridge_fired)
			if not weapon.ammo_feed_empty.is_connected(_on_mag_empty):
				weapon.ammo_feed_empty.connect(_on_mag_empty)
	if OS.is_debug_build(): print("DEBUG RANGE READY: %s with %d rounds" % [weapon.name, MAG_SIZE])
	ShotRay.register(self)

func _on_player_equipped(item: Item, _slot_name: String) -> void:
	if item is Weapon:
		if OS.is_debug_build(): print("DEBUG RANGE: weapon equipped: ", item.name)

func _on_cartridge_fired(fired_weapon: Weapon, round: Ammo) -> void:
	_pending_shots.append([fired_weapon, round])
	if audio:
		audio.play_shot()

## RIDs the resolver ray must never hit: player body + EVERY viewmodel body
## (held gun, attachments, and any ghost leaked on switch). See ShotRay.
func _shot_excludes() -> Array[RID]:
	return ShotRay.collect(player, self, shots % 16 == 0)

func _resolve_shot(fired_weapon: Weapon, round: Ammo) -> void:
	shots += 1
	var cam: Camera3D = player.camera
	var space := get_world_3d().direct_space_state
	var center := get_viewport().get_visible_rect().size / 2.0
	var origin := cam.project_ray_origin(center)
	var end := origin + cam.project_ray_normal(center) * SHOT_RANGE
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	# ADS self-hit: exclude the held viewmodel subtree by RID (see arena).
	query.exclude = _shot_excludes()
	query.collide_with_areas = false
	var result := space.intersect_ray(query)
	if result.is_empty():
		_refresh_overlay("miss")
		return
	var dist: float = origin.distance_to(result.position)
	var dir: Vector3 = (result.position - origin).normalized()
	var ang := rad_to_deg(acos(clampf(-dir.dot(result.normal), -1.0, 1.0)))
	var impact := BallisticsCalculator.calculate_impact(round, plate_mat, 3.0, dist, ang)
	_spawn_hit_flash(result.position)
	var collider: Object = result.collider
	if collider and collider.has_method("range_hit"):
		collider.range_hit(impact, round)
		if audio:
			if collider is NpcBot:
				audio.play_hit_flesh(result.position)
			else:
				audio.play_hit_steel(result.position)
	_refresh_overlay("HIT %.0fm %.0fJ" % [dist, impact.hit_energy])

func _spawn_hit_flash(pos: Vector3) -> void:
	# Shared mesh/material (P0 perf): no per-hit resource allocation.
	# One-shot tween -> queue_free is intentional (self-freeing transient FX).
	if _flash_mesh == null:
		_flash_mesh = SphereMesh.new()
		_flash_mesh.radius = 0.06
		_flash_mesh.height = 0.12
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.albedo_color = Color(1.0, 0.9, 0.5)
	var mi := MeshInstance3D.new()
	mi.mesh = _flash_mesh
	mi.material_override = _flash_mat
	add_child(mi)
	mi.global_position = pos
	var tween := create_tween()
	tween.tween_property(mi, "scale", Vector3.ONE * 2.5, 0.18)
	tween.tween_callback(mi.queue_free)

func _on_target_down(t: RangeTarget) -> void:
	hits += 1
	_refresh_overlay("STEEL DOWN (%s)" % t.name)
	if OS.is_debug_build(): print("RANGE: %s down, hits=%d/%d" % [t.name, hits, shots])

func _on_target_up(_t: RangeTarget) -> void:
	_refresh_overlay("target back up")

func _on_mag_empty(_w: Weapon, _feed: AmmoFeed) -> void:
	_refresh_overlay("MAG EMPTY - press R")

func _on_reserve_mag(_p: PlayerController) -> void:
	if weapon == null:
		return
	if WeaponSystem.change_magazine(weapon, _make_mag()):
		_refresh_overlay("reloaded")
		if OS.is_debug_build(): print("RANGE: fresh mag loaded")

func _rounds_left() -> String:
	if weapon == null or weapon.ammo_feed == null:
		return "MAG ?"
	var s := "%d/%d" % [weapon.ammo_feed.capacity, MAG_SIZE]
	if weapon.chambered_round:
		s += "+1"
	return "MAG " + s

func _refresh_overlay(msg: String) -> void:
	if overlay:
		overlay.text = "HITS %d | SHOTS %d | %s   -- %s" % [hits, shots, _rounds_left(), msg]
