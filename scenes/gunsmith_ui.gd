class_name GunsmithUI
extends CanvasLayer
## In-raid weapon modding screen: 3D preview of the weapon with its mounted
## attachments, one row per mount point, click to add/remove. Every change is a
## TIMED action (ACTION_TIME) — you are vulnerable while the work is done, the
## raid keeps running. Operates on the live equipped Weapon; the Meta layer
## persists it (ItemCodec encodes mounted attachments) on extraction.
##
## SINGLE ENTRY POINT: `open_for_weapon(w)`, driven by the inventory context menu
## ("Modificar" on a weapon item -> player-rig hook -> the arena). There is
## deliberately no "open whatever is equipped" path and no pause-menu screen:
## opening without an item showed a weapon the player had not picked.
##
## GUIDE-LINES UX (PARKED DESIGN):
## The proposal to draw visual leader lines from locked 2D slot rows to 3D marker
## positions is PARKED. Rationale: rows live in a 2D CanvasLayer column while markers
## live in a rotating SubViewport 3D world; projecting 3D positions to 2D screen coords
## per frame, tracking camera rotation, drawing Line2D overlays, and handling hover/drag
## raycasts adds substantial per-frame complexity and performance overhead. If prioritized
## in the future, recommended implementation is a Line2D overlay node atop the preview,
## sampling preview_view.get_camera_3d().unproject_position(marker.global_position).

signal closed

const ACTION_TIME := 2.5
const ATTACH_DIR := "res://resources/attachments"

## Mount point -> readable name.
const MOUNT_NAMES := {
	Weapon.AttachmentPoint.MUZZLE: "MUZZLE",
	Weapon.AttachmentPoint.LEFT_RAIL: "LEFT RAIL",
	Weapon.AttachmentPoint.RIGHT_RAIL: "RIGHT RAIL",
	Weapon.AttachmentPoint.TOP_RAIL: "TOP RAIL",
	Weapon.AttachmentPoint.UNDER: "UNDERBARREL",
}
# The 3D art is NOT mapped here any more: it comes from the resource itself
# (`Attachment.model_scene` + `model_transform`), the same fields the in-hands
# rigs use, and the marker names come from `Weapon3D.marker_names_for_point`.
# A hardcoded name->scene map meant an attachment with a resource but no entry
# silently showed no model (the "attachments have no model" report).

var audio: GameAudio
var weapon: Weapon

var panel: PanelContainer
var title: Label
var rows: VBoxContainer
var message: Label
var progress: ProgressBar
var preview_holder: Node3D
var preview_view: SubViewport
var close_btn: Button

var _pending: Array = [] # [{kind:"attach"/"detach", point:int, att:Attachment, origin:Dictionary}]
var _active: Dictionary = {}
var _mounted_origins: Dictionary = {} # current weapon point:int -> {"stash_item": InventoryItem, "source": Variant, "position": Vector2i}
var _mounted_origins_by_weapon: Dictionary = {} # weapon instance id -> {"weapon_ref": WeakRef, "origins": Dictionary}
var _t := 0.0

func bind(p_audio: GameAudio) -> void:
	audio = p_audio

func _ready() -> void:
	layer = 20
	visible = false
	_build()

func is_open() -> bool:
	return visible

## The one entry point: the inventory asks for a specific weapon item to be
## edited (player-rig hook). A null weapon is a no-op — never "open anyway".
func open_for_weapon(w: Weapon) -> void:
	if w == null:
		return
	weapon = w
	_activate_origin_map(w)
	_prune_origin_map()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	_rebuild_preview()

func close() -> void:
	visible = false
	_pending.clear()
	_active = {}
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()

# ─── BUILD ───

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	root.add_child(dim)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-470, -260)
	panel.size = Vector2(940, 520)
	panel.add_theme_stylebox_override("panel", HudStyle.panel())
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 14)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(split)
	_build_preview(split)
	_build_side(split)

## Left column: a SubViewport rendering the weapon (rotated in _physics_process).
func _build_preview(parent: Control) -> void:
	preview_view = SubViewport.new()
	preview_view.size = Vector2i(520, 380)
	preview_view.own_world_3d = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.08, 0.1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.82, 0.9)
	e.ambient_light_energy = 0.6
	env.environment = e
	preview_view.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.2
	preview_view.add_child(sun)
	preview_holder = Node3D.new()
	preview_view.add_child(preview_holder)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.12, 1.0)
	cam.rotation_degrees = Vector3(-8, 0, 0)
	cam.fov = 45
	preview_view.add_child(cam)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(520, 380)
	svc.add_child(preview_view)
	parent.add_child(svc)

## Right column: mount rows, progress bar, message, close.
func _build_side(parent: Control) -> void:
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	parent.add_child(right)
	rows = VBoxContainer.new()
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	right.add_child(rows)
	progress = ProgressBar.new()
	progress.min_value = 0.0
	progress.max_value = 1.0
	progress.value = 0.0
	progress.custom_minimum_size = Vector2(0, 14)
	right.add_child(progress)
	message = Label.new()
	message.add_theme_font_size_override("font_size", HudStyle.FONT_HINT)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(message)
	close_btn = Button.new()
	close_btn.text = "Fechar (M/Esc)"
	close_btn.pressed.connect(close)
	right.add_child(close_btn)

func _exit_tree() -> void:
	# Persistent connections that outlive a refresh are torn down here; the
	# per-row buttons die with their own node, so only close_btn needs this.
	if close_btn != null and is_instance_valid(close_btn) and close_btn.pressed.is_connected(close):
		close_btn.pressed.disconnect(close)

# ─── REFRESH ───

func _refresh() -> void:
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	if weapon == null:
		title.text = "SEM ARMA"
		return
	title.text = "%s  —  mounts: %s" % [weapon.name, _mounted_summary()]
	var points: Array[int] = [
		Weapon.AttachmentPoint.MUZZLE, Weapon.AttachmentPoint.TOP_RAIL,
		Weapon.AttachmentPoint.LEFT_RAIL, Weapon.AttachmentPoint.RIGHT_RAIL,
		Weapon.AttachmentPoint.UNDER,
	]
	for p in points:
		if not (weapon.attach_points & p):
			continue
		rows.add_child(_row_for(p))

func _mounted_summary() -> String:
	var n := 0
	for p in weapon.attachments:
		n += 1
	return "%d montado(s)" % n

func _row_for(point: int) -> Control:
	var row := MountRow.new()
	row.ui = self
	row.point = point
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override("separation", 8)
	var name_lbl := Label.new()
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.custom_minimum_size = Vector2(110, 0)
	name_lbl.text = String(MOUNT_NAMES.get(point, str(point)))
	name_lbl.add_theme_font_size_override("font_size", HudStyle.FONT_HINT)
	row.add_child(name_lbl)
	var att := weapon.get_attachment(point)
	var info := Label.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_font_size_override("font_size", HudStyle.FONT_HINT)
	info.text = _att_line(att)
	row.add_child(info)
	if att == null:
		var add := Button.new()
		add.text = "Add"
		add.disabled = not _active.is_empty()
		add.pressed.connect(_request_attach.bind(point))
		row.add_child(add)
	else:
		var rem := Button.new()
		rem.text = "Remove"
		rem.disabled = not _active.is_empty()
		rem.pressed.connect(_request_detach.bind(point))
		row.add_child(rem)
	return row

func _att_line(att: Attachment) -> String:
	if att == null:
		return "(vazio)"
	return "%s  [recoil %.2f | ergo %.2f | mag %.1fx]" % [
		att.name, att.recoil_modifier, att.ergonomics_modifier, att.magnification]

# ─── ACTIONS (timed) ───

func _request_attach(point: int) -> void:
	var options := _compatible_attachments(point)
	if options.is_empty():
		message.text = "Nenhum attachment compativel para %s" % MOUNT_NAMES.get(point, point)
		return
	# Minimal picker: buttons for each option.
	_open_picker(point, options)

func _compatible_attachments(point: int) -> Array[Attachment]:
	var out: Array[Attachment] = []
	var dir := DirAccess.open(ATTACH_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var att := load(ATTACH_DIR + "/" + f) as Attachment
		if att == null:
			continue
		if att.attachment_point != point:
			continue
		# Mirrors Attachment._is_compatible (private): mount exists + whitelist.
		if not (weapon.attach_points & point):
			continue
		if not att.compatible_weapons.is_empty() and not (weapon.name in att.compatible_weapons):
			continue
		out.append(att)
	return out

func _open_picker(point: int, options: Array[Attachment]) -> void:
	var picker := AcceptDialog.new()
	picker.title = "Adicionar em %s" % MOUNT_NAMES.get(point, point)
	var vb := VBoxContainer.new()
	for att in options:
		var b := Button.new()
		b.text = _att_line(att)
		b.pressed.connect(_on_picker_option.bind(picker, point, att), CONNECT_ONE_SHOT)
		vb.add_child(b)
	picker.add_child(vb)
	add_child(picker)
	picker.popup_centered(Vector2i(520, 60 + options.size() * 40))
	picker.confirmed.connect(picker.queue_free, CONNECT_ONE_SHOT)
	picker.canceled.connect(picker.queue_free, CONNECT_ONE_SHOT)

## Named (not a lambda) so the connection is explicit and one-shot.
func _on_picker_option(picker: AcceptDialog, point: int, att: Attachment) -> void:
	if is_instance_valid(picker):
		picker.hide()
	_queue_attach(point, att)

func _activate_origin_map(w: Weapon) -> void:
	_prune_origin_weapon_entries()
	var weapon_id := w.get_instance_id()
	var entry = _mounted_origins_by_weapon.get(weapon_id, null)
	if entry is Dictionary:
		var ref = entry.get("weapon_ref", null)
		var origins = entry.get("origins", null)
		if ref is WeakRef and ref.get_ref() is Weapon and origins is Dictionary and not origins.is_empty():
			_mounted_origins = origins
			return
	# Do not retain an entry for a weapon until it actually owns a source
	# origin. This keeps opening arbitrary weapons bounded.
	_mounted_origins = {}

func _ensure_current_origin_entry() -> void:
	if weapon == null:
		return
	var weapon_id := weapon.get_instance_id()
	var entry = _mounted_origins_by_weapon.get(weapon_id, null)
	if entry is Dictionary:
		var ref = entry.get("weapon_ref", null)
		var origins = entry.get("origins", null)
		if ref is WeakRef and ref.get_ref() is Weapon and origins is Dictionary:
			_mounted_origins = origins
			return
	_mounted_origins_by_weapon[weapon_id] = {
		"weapon_ref": weakref(weapon),
		"origins": _mounted_origins,
	}

func _prune_origin_weapon_entries() -> void:
	for weapon_id in _mounted_origins_by_weapon.keys():
		var entry = _mounted_origins_by_weapon[weapon_id]
		if not (entry is Dictionary):
			_mounted_origins_by_weapon.erase(weapon_id)
			continue
		var ref = entry.get("weapon_ref", null)
		var live_weapon = ref.get_ref() if ref is WeakRef else null
		var origins = entry.get("origins", null)
		var has_origins = origins is Dictionary and not origins.is_empty()
		if not (live_weapon is Weapon) or not has_origins:
			_mounted_origins_by_weapon.erase(weapon_id)

func _prune_origin_map() -> void:
	if weapon == null:
		return
	for point in _mounted_origins.keys():
		if weapon.get_attachment(int(point)) == null:
			_mounted_origins.erase(point)
	_erase_current_weapon_entry_if_empty()

func _erase_current_weapon_entry_if_empty() -> void:
	if weapon == null or not _mounted_origins.is_empty():
		return
	_mounted_origins_by_weapon.erase(weapon.get_instance_id())

func _erase_origin(point: int) -> void:
	_mounted_origins.erase(point)
	_erase_current_weapon_entry_if_empty()

func _can_drop_on_row(point: int, data: Variant) -> bool:
	if not (data is Dictionary and data.has("item")):
		return false
	var item = data.get("item")
	if item == null:
		return false
	var att = item.get("extra") as Attachment
	if att == null:
		return false
	if att.attachment_point != point:
		return false
	if weapon == null or not (weapon.attach_points & point):
		return false
	if not att.compatible_weapons.is_empty() and not (weapon.name in att.compatible_weapons):
		return false
	if weapon.get_attachment(point) != null:
		return false
	if _is_point_busy(point):
		return false
	return true

func _is_point_busy(point: int) -> bool:
	if not _active.is_empty() and _active.get("point") == point:
		return true
	for p in _pending:
		if p.get("point") == point:
			return true
	return false

func _drop_on_row(point: int, data: Variant) -> void:
	if not _can_drop_on_row(point, data):
		return
	var item = data.get("item")
	var att: Attachment = item.extra as Attachment
	var source = data.get("source")
	var pos: Vector2i = item.position if item != null and "position" in item else Vector2i(-1, -1)
	var origin: Dictionary = {
		"stash_item": item,
		"source": source,
		"position": pos,
	}
	_queue_attach(point, att, origin)

func _request_detach(point: int) -> void:
	_queue_detach(point)

func _queue_attach(point: int, att: Attachment, origin: Dictionary = {}) -> void:
	_pending.append({"kind": "attach", "point": point, "att": att, "origin": origin})
	message.text = "Na fila: montar %s" % att.name
	_refresh()

func _queue_detach(point: int) -> void:
	var origin: Dictionary = _mounted_origins.get(point, {})
	_pending.append({"kind": "detach", "point": point, "att": weapon.get_attachment(point), "origin": origin})
	message.text = "Na fila: remover"
	_refresh()

func _physics_process(delta: float) -> void:
	_prune_origin_weapon_entries()
	if not visible:
		return
	if preview_holder != null:
		preview_holder.rotate_y(delta * 0.5)
		# Re-assert "posed, not simulated": a scene's deferred _ready() (scope
		# grab()) or its own physics timer can re-enable a body after mounting.
		_neutralize_descendants(preview_holder)
	if _active.is_empty():
		if _pending.is_empty():
			return
		_active = _pending.pop_front()
		_t = 0.0
		progress.value = 0.0
		message.text = "Trabalhando... (%s)" % _active.get("kind", "")
	_t += delta
	progress.value = clampf(_t / ACTION_TIME, 0.0, 1.0)
	message.text = "%s em %s... %d/%ds" % [
		"Montando" if _active.get("kind") == "attach" else "Removendo",
		MOUNT_NAMES.get(_active.get("point", 0), "?"), int(_t), int(ACTION_TIME)]
	if _t >= ACTION_TIME:
		_apply(_active)
		_active = {}
		progress.value = 0.0
		if audio != null:
			audio.play_reload()
		_refresh()
		_rebuild_preview()

func _apply(a: Dictionary) -> void:
	if weapon == null:
		return
	var point: int = a.get("point", 0)
	var origin: Dictionary = a.get("origin", {})
	if a.get("kind") == "attach":
		var att: Attachment = a.get("att")
		if att == null or not weapon.attach_attachment(point, att):
			message.text = "Falhou ao montar"
			return
		# Mount first, then take ownership from the source. If the source moved
		# while the timed action was running, roll the mount back instead of
		# leaving a duplicated attachment behind.
		if not origin.is_empty():
			var stash_item = origin.get("stash_item")
			var source = origin.get("source")
			if not _remove_stash_item(source, stash_item):
				weapon.detach_attachment(point)
				message.text = "Falhou ao retirar da origem"
				return
			_ensure_current_origin_entry()
			_mounted_origins[point] = origin
		else:
			_erase_origin(point)
		message.text = "Montado: %s" % att.name
	else:
		var mounted_att: Attachment = weapon.get_attachment(point)
		if not weapon.detach_attachment(point):
			message.text = "Nada para remover"
			return
		if not origin.is_empty():
			var stash_item = origin.get("stash_item")
			var source = origin.get("source")
			var pos: Vector2i = origin.get("position", Vector2i(-1, -1))
			if not _return_stash_item(source, stash_item, pos):
				# A detach is transactional too: if the source cannot take the
				# wrapper back, keep it mounted so the player can retry after
				# freeing space rather than silently losing the item.
				var restored := mounted_att != null and weapon.attach_attachment(point, mounted_att)
				message.text = "Falhou ao devolver; %s" % ("montagem mantida" if restored else "montagem nao restaurada")
				return
		_erase_origin(point)
		message.text = "Removido"

func _remove_stash_item(source: Variant, item: Variant) -> bool:
	if source == null or item == null:
		return false
	if source is InventoryContainer:
		var c := source as InventoryContainer
		if item in c.items:
			return c.remove_item(item)
	elif source is Equipment:
		var eq := source as Equipment
		for slot_name in eq.slots:
			var slot = eq.slots[slot_name]
			if item in slot.items:
				return slot.remove_item(item)
	elif source.has_method("remove_item"):
		return source.remove_item(item)
	return false

func _return_stash_item(source: Variant, item: Variant, preferred_pos: Vector2i = Vector2i(-1, -1)) -> bool:
	if source == null or item == null:
		return false
	if source is InventoryContainer:
		var c := source as InventoryContainer
		if preferred_pos != Vector2i(-1, -1) and c.grid != null and c.grid.is_area_free(preferred_pos, item.dimensions):
			return c.add_item(item, preferred_pos)
		return c.add_item(item, Vector2i(-1, -1))
	elif source is Equipment:
		var eq := source as Equipment
		for slot_name in eq.slots:
			var slot = eq.slots[slot_name]
			if slot.can_add_item(item):
				return slot.add_item(item)
	elif source.has_method("add_item"):
		return source.add_item(item)
	return false

# ─── 3D PREVIEW ───

func _rebuild_preview() -> void:
	for c in preview_holder.get_children():
		preview_holder.remove_child(c)
		c.queue_free()
	if weapon == null or weapon.view_model == null:
		return
	var vm := weapon.view_model.instantiate() as Node3D
	vm.freeze = true
	vm.set_physics_process(false)
	if vm is CollisionObject3D:
		(vm as CollisionObject3D).collision_layer = 0
		(vm as CollisionObject3D).collision_mask = 0
	preview_holder.add_child(vm)
	# The view_model itself ships baked-in optics (authoring convention: the
	# weapon's default sight is part of its scene), and their own _ready() calls
	# grab() — which re-enables physics AFTER a deferred frame. Nothing inside the
	# preview may simulate (AGENTS rule 5), so neutralize the whole subtree now and
	# re-assert every physics frame (see _physics_process).
	_neutralize_descendants(vm)
	# Mount the art the RESOURCE declares — `Attachment.model_scene`, placed by
	# `model_transform` on the marker `Weapon3D.marker_names_for_point` resolves:
	# the exact convention the in-hands rigs use, so the preview shows what the
	# player sees, and a new attachment needs no edit here.
	for point in weapon.attachments:
		var att := weapon.attachments[point] as Attachment
		if att == null or att.model_scene == null:
			continue
		var marker := _preview_marker(vm, point)
		if marker == null:
			continue
		var vis := att.model_scene.instantiate() as Node3D
		if vis == null:
			continue
		marker.add_child(vis)
		vis.transform = att.model_transform
		# Tag the mounted instance: a weapon scene may ship a BAKED instance of the
		# very same scene under the marker, so "the mounted one" is identified by
		# this meta, not by scene path (and not by child order).
		vis.set_meta("gunsmith_mount_point", point)
		_hide_marker_siblings(marker, vis)
		_neutralize_descendants(vis)


## The weapon scene ships its default optic BAKED under the marker (authoring
## convention: `weapon_ar15.tscn` has a red dot, `weapon_aglc.tscn` a sniper
## scope). Mounting an attachment must not show two optics: the baked siblings of
## the marker are hidden while an attachment owns the point — the same rule the
## in-hands rigs apply, so preview and hands stay identical. Nothing needs to be
## restored: the preview rebuilds the weapon from scratch on every refresh.
func _hide_marker_siblings(marker: Node3D, keep: Node3D) -> void:
	for c in marker.get_children():
		if c != keep and c is Node3D:
			(c as Node3D).visible = false


## Poses a body: frozen, out of the collision world and ungrabbed — the same
## convention the in-hands rigs use (viewmodel_rig._freeze_body,
## weapon_3d._mount_attachment). A body left "grabbed" keeps its grab spring
## alive and re-enables its own physics.
func _neutralize_body(rb: RigidBody3D) -> void:
	rb.freeze = true
	rb.contact_monitor = false
	rb.collision_layer = 0
	rb.collision_mask = 0
	if rb.get("is_grabbed") != null:
		rb.set("is_grabbed", false)


## Every rigid body in the preview is posed, never simulated.
func _neutralize_descendants(node: Node) -> void:
	if node is RigidBody3D:
		_neutralize_body(node as RigidBody3D)
	elif node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	for c in node.get_children():
		_neutralize_descendants(c)


## Marker for a mount point inside the previewed view_model: the addon's own
## candidate list, most specific first, with the weapon root as the last resort
## (same fallback the in-hands rigs use, so a mismatch is visible, not hidden).
## `Weapon.MAGAZINE_POINT` resolves to the weapon's MagazinePoint marker, like
## the in-hands path; a point the addon knows nothing about resolves to null
## rather than dumping its art on the weapon root.
func _preview_marker(vm: Node3D, point: int) -> Node3D:
	var names := Weapon3D.marker_names_for_point(point)
	if names.is_empty():
		return null
	for marker_name in names:
		var n := vm.get_node_or_null(String(marker_name))
		if n is Node3D:
			return n
	return vm


## Mount row control: receives dragged inventory attachment items and routes
## them through GunsmithUI drop validation and action queuing.
class MountRow extends HBoxContainer:
	var ui: GunsmithUI
	var point: int

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return ui != null and ui._can_drop_on_row(point, data)

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if ui != null:
			ui._drop_on_row(point, data)
