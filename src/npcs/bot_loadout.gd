class_name NpcLoadout
extends RefCounted
## Data-backed loadout and corpse inventory support for NpcBot.
##
## NpcBot keeps its public state fields for scene compatibility; this helper owns
## the resource duplication, synthetic magazine bookkeeping, and the visual
## proxy so the bot controller remains focused on perception and movement.

const DEFAULT_WEAPON_PATH := "res://resources/weapons/M4_Carbine.tres"
const DEFAULT_AMMO_PATH := "res://resources/ammo/5_56_45mm_SS109_VPAM_PM7.tres"
const WEAPON_HAND_BONE := "hand.R_034"

var _body: Node3D
var _width: int = 6
var _height: int = 4
var _max_weight: float = 30.0
var _weapon_enabled: bool = true
var _weapon_template: Weapon
var _magazine_rounds: int = 6
var _spare_magazines: int = 1
var _weapon_installed: bool = false
var _weapon_spares_added: bool = false
var _mag_size: int = 0
var _rounds_remaining: int = 0
var _visual: MeshInstance3D = null


func configure(body: Node3D, width: int, height: int, max_weight: float,
		weapon_enabled: bool, template: Weapon, magazine_rounds: int,
		spare_magazines: int) -> void:
	_body = body
	_width = width
	_height = height
	_max_weight = max_weight
	_weapon_enabled = weapon_enabled
	_weapon_template = template
	_magazine_rounds = magazine_rounds
	_spare_magazines = spare_magazines


func ensure_inventory() -> void:
	if _body == null:
		return
	var inventory: InventoryContainer = _body.get("inventory")
	if inventory == null:
		inventory = InventoryContainer.new()
		inventory.name = "NPC inventory"
		inventory.grid_width = maxi(1, _width)
		inventory.grid_height = maxi(1, _height)
		inventory.max_weight = maxf(1.0, _max_weight)
		_body.set("inventory", inventory)
	inventory.is_open = true
	_body.set_meta("npc_inventory", inventory)


func install_weapon(source: Weapon) -> void:
	if source == null:
		return
	if _body == null:
		_weapon_template = source
		return
	var inventory: InventoryContainer = _body.get("inventory")
	var weapon_item: InventoryItem = _body.get("weapon_item")
	if weapon_item != null and inventory != null and weapon_item in inventory.items:
		inventory.remove_item(weapon_item)
	var duplicate := source.duplicate(true) as Weapon
	if duplicate == null:
		return
	duplicate.name = source.name
	_body.set("weapon", duplicate)
	_weapon_installed = true
	_weapon_spares_added = false
	prepare_weapon_rounds(duplicate)
	_add_weapon_to_inventory()
	_add_spare_magazines()
	if inventory != null:
		_weapon_spares_added = true
	if _body.get_node_or_null("Skeleton3D") != null:
		ensure_weapon_visual()


func ensure_weapon() -> void:
	if not _weapon_enabled:
		_body.set("weapon", null)
		_weapon_installed = false
		return
	var weapon: Weapon = _body.get("weapon")
	if weapon != null and _weapon_installed:
		_add_weapon_to_inventory()
		if not _weapon_spares_added:
			_add_spare_magazines()
			_weapon_spares_added = true
		if _body.get_node_or_null("Skeleton3D") != null:
			ensure_weapon_visual()
		return
	var source := _weapon_template
	if source == null:
		source = load(DEFAULT_WEAPON_PATH) as Weapon
	if source != null:
		install_weapon(source)


func has_weapon() -> bool:
	return _weapon_enabled and _body != null and _body.get("weapon") != null


func weapon() -> Weapon:
	return _body.get("weapon") as Weapon if has_weapon() else null


func rounds_remaining() -> int:
	return _rounds_remaining


func consume_round() -> bool:
	var weapon: Weapon = _body.get("weapon")
	if weapon == null:
		return true
	if _rounds_remaining <= 0:
		_body.call("start_reload")
		return false
	_rounds_remaining -= 1
	if weapon.ammo_feed != null and not weapon.ammo_feed.is_empty():
		weapon.ammo_feed.eject()
	return true


func ensure_weapon_visual() -> void:
	if not has_weapon() or is_instance_valid(_visual):
		return
	var rig := _body.get_node_or_null("Skeleton3D") as HumanoidRig
	var host: Node3D = _body
	if rig != null:
		if rig.find_bone(WEAPON_HAND_BONE) >= 0:
			var mount := BoneAttachment3D.new()
			mount.name = "NpcWeaponMount"
			mount.bone_name = WEAPON_HAND_BONE
			rig.add_child(mount)
			host = mount
		else:
			host = rig
	var mesh := MeshInstance3D.new()
	mesh.name = "NpcWeaponProxy"
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.12, 0.62)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.18, 0.20, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.25
	mat.roughness = 0.78
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = Vector3(0.0, -0.04, -0.22) if host != _body \
		else Vector3(0.22, 1.12, -0.28)
	mesh.set_meta("npc_weapon_proxy", true)
	host.add_child(mesh)
	_visual = mesh


func set_visual_alpha(alpha: float) -> void:
	if not is_instance_valid(_visual):
		return
	var mat := _visual.material_override as StandardMaterial3D
	if mat == null:
		return
	var color := mat.albedo_color
	color.a = clampf(alpha, 0.0, 1.0)
	mat.albedo_color = color


func _add_weapon_to_inventory() -> void:
	var inventory: InventoryContainer = _body.get("inventory")
	var weapon: Weapon = _body.get("weapon")
	var weapon_item: InventoryItem = _body.get("weapon_item")
	if inventory == null or weapon == null or weapon_item != null:
		return
	for item in inventory.items:
		if item != null and item.extra == weapon:
			_body.set("weapon_item", item)
			return
	weapon_item = InventoryItem.slurp(weapon)
	weapon_item.max_stack = 1
	weapon_item.stack_count = 1
	weapon_item.dimensions = Vector2i(3, 2)
	weapon_item.set_meta("npc_weapon", true)
	if inventory.add_item(weapon_item, Vector2i(-1, -1)):
		_body.set("weapon_item", weapon_item)
	else:
		_body.set("weapon_item", null)


func _add_spare_magazines() -> void:
	var inventory: InventoryContainer = _body.get("inventory")
	var weapon: Weapon = _body.get("weapon")
	if inventory == null or weapon == null or weapon.ammo_feed == null:
		return
	for _i in maxi(_spare_magazines, 0):
		var feed := weapon.ammo_feed.duplicate(true) as AmmoFeed
		if feed == null:
			continue
		var item := InventoryItem.slurp(feed)
		item.max_stack = 1
		item.stack_count = 1
		item.dimensions = Vector2i(1, 2)
		item.set_meta("npc_spare_magazine", true)
		inventory.add_item(item, Vector2i(-1, -1))


func prepare_weapon_rounds(w: Weapon) -> void:
	if w == null:
		_mag_size = 0
		_rounds_remaining = 0
		return
	var capacity := 30
	if w.ammo_feed != null:
		capacity = maxi(1, w.ammo_feed.max_capacity)
	_mag_size = clampi(_magazine_rounds, 1, capacity)
	_rounds_remaining = _mag_size
	if w.ammo_feed == null:
		return
	var ammo := load(DEFAULT_AMMO_PATH) as Ammo
	if ammo == null or not w.ammo_feed.is_compatible(ammo):
		var available := w.ammo_feed.capacity
		_rounds_remaining = _mag_size if available == 0 else mini(_mag_size, available)
		return
	w.ammo_feed.contents.clear()
	for _i in _mag_size:
		if not w.ammo_feed.insert(ammo.duplicate(true)):
			break
