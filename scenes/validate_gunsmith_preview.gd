# res://scenes/validate_gunsmith_preview.gd
#
# Headless gate for the in-raid gunsmith preview (scenes/gunsmith_ui.gd). Guards
# defects that shipped silently:
#
#   [1] the preview used a hardcoded name->scene map (6 names), so an attachment
#       whose RESOURCE carried `model_scene` still showed no model ("attachments
#       have no model"). It must read the resource — one source of truth.
#   [2] the mounted art was left physics-simulated. A scope scene calls grab() in
#       its own _ready(), which re-enables physics one frame later, so a one-shot
#       freeze at mount time was undone (AGENTS rule 5: a held/worn item is never
#       simulated; the preview poses, it does not simulate).
#   [3] the weapon scene ships a BAKED default optic under the marker, so mounting
#       an attachment showed two optics. The baked siblings must yield (same rule
#       the in-hands rigs apply).
#
# Checks:
#   - every compatible attachment mounts, on a marker from
#     Weapon3D.marker_names_for_point(point), with the resource model_transform
#     (both an AR15-style "Scope" marker and an AK-style "ScopePoint" one)
#   - every rigid body in the preview is frozen/ungrabbed/collision-free,
#     including the baked optics, and STILL is after frames (no drift)
#   - the baked optic is the default look with nothing mounted, and is hidden
#     (never two optics) once an attachment owns that marker
#   - a magazine (Weapon.MAGAZINE_POINT) mounts on the MagazinePoint marker
#
# The mounted instance is located by the meta `gunsmith_mount_point` the preview
# sets on it, NOT by scene path: a weapon scene can ship a baked instance of the
# very same scene (weapon_ar15.tscn bakes a red dot), which would match a
# path-based lookup first.
#
# Run:
#   tools/godot-lock.sh --headless --path . --script res://scenes/validate_gunsmith_preview.gd
# Exit code: 0 = every check passed, 1 = at least one failure.
extends SceneTree

const ATTACH_DIR := "res://resources/attachments"
const M4 := "res://resources/weapons/M4_Carbine.tres"
const AK := "res://resources/weapons/AK_47.tres"
const MOUNT_META := "gunsmith_mount_point"
const DRIFT_FRAMES := 6

var v: ValidateUtil
var _ui
var _frame := 0
var _done := false
var _held: Node = null
var _held_name := ""
var _held_start := Vector3.ZERO


func _initialize() -> void:
	v = ValidateUtil.new("validate_gunsmith_preview")
	# GunsmithUI is loaded at RUNTIME: referencing its global class name at compile
	# time pulls PlayerController, whose `Debug` autoload is not registered yet in
	# `--script` mode (the harness would fail to compile at startup).
	_ui = (load("res://scenes/gunsmith_ui.gd") as GDScript).new()
	get_root().add_child(_ui)


## The checks need the tree up (add_child must run a scene's _ready) and a few
## frames to catch a body that re-enables its own physics.
func _process(_delta: float) -> bool:
	if _done:
		return true
	_frame += 1
	if _frame == 1:
		v.begin()
		var files := _attachment_files()
		v.check(files.size() >= 10, "attachment pack has %d resources" % files.size())
		_check_weapon(M4, files)
		_check_weapon(AK, files)
		_check_magazine()
		_check_baked_optics()
		_check_baked_optic_toggle()
		_leave_risky_mounted()
		return false
	if _frame >= DRIFT_FRAMES:
		_done = true
		_check_no_drift()
		quit(v.finish())
		return true
	return false


func _attachment_files() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(ATTACH_DIR)
	if d == null:
		return out
	var names := d.get_files()
	names.sort()
	for f in names:
		if f.ends_with(".tres"):
			out.append(ATTACH_DIR + "/" + f)
	return out


## Every attachment this weapon accepts must appear in the preview, under a marker
## the addon knows for that point, with the resource's own transform.
func _check_weapon(weapon_path: String, files: Array[String]) -> void:
	var weapon := load(weapon_path) as Weapon
	v.section("[%s]" % weapon.name)
	var mounted := 0
	var expected := 0
	for f in files:
		var att := load(f) as Attachment
		if att == null or att.model_scene == null:
			continue
		var point: int = att.attachment_point
		if point == 0 or (point & (point - 1)) != 0:
			continue # magazine key or a multi-point attachment: not a rail row
		if not (weapon.attach_points & point):
			continue
		expected += 1
		weapon.attachments = {}
		weapon.attachments[point] = att
		_ui.open_for_weapon(weapon)
		var found := _find_mounted(_ui.preview_holder, point)
		if found == null:
			v.check(false, "%s: '%s' mounted from its own model_scene" % [weapon.name, att.name])
			continue
		mounted += 1
		var candidates: Array = Weapon3D.marker_names_for_point(point)
		v.check(String(found.get_parent().name) in candidates,
			"%s: '%s' lands on a marker of point %d (parent='%s')"
			% [weapon.name, att.name, point, found.get_parent().name])
		v.check((found as Node3D).transform == att.model_transform,
			"%s: '%s' uses the resource model_transform" % [weapon.name, att.name])
		v.check(found.scene_file_path == att.model_scene.resource_path,
			"%s: '%s' mounts the scene the resource declares" % [weapon.name, att.name])
		if found is RigidBody3D:
			v.check(_is_posed(found as RigidBody3D),
				"%s: '%s' (RigidBody3D) mounted posed: frozen, ungrabbed, no collision"
				% [weapon.name, att.name])
	v.check(mounted == expected and expected >= 4,
		"%s: mounted %d/%d compatible attachments (a hardcoded name map capped this at 6 TOTAL)"
		% [weapon.name, mounted, expected])


## A magazine lives under Weapon.MAGAZINE_POINT: like the in-hands path, its art
## goes on the weapon's MagazinePoint marker.
func _check_magazine() -> void:
	v.section("[MAGAZINE_POINT]")
	var weapon := load(M4) as Weapon
	var mag: Attachment = null
	for f in _attachment_files():
		var att := load(f) as Attachment
		if att != null and att.model_scene != null and att.attachment_point == 0:
			mag = att
			break
	if mag == null:
		v.check(false, "a magazine resource with model_scene exists")
		return
	weapon.attachments = {}
	weapon.attachments[Weapon.MAGAZINE_POINT] = mag
	_ui.open_for_weapon(weapon)
	var found := _find_mounted(_ui.preview_holder, Weapon.MAGAZINE_POINT)
	v.check(found != null, "'%s' art IS mounted (from the resource)" % mag.name)
	if found != null:
		v.check(String(found.get_parent().name) == "MagazinePoint",
			"'%s' lands on the MagazinePoint marker (parent='%s')" % [mag.name, found.get_parent().name])


## The weapon scene ships baked-in optics whose _ready() grabs itself and
## re-enables physics a frame later: nothing in the preview may simulate.
func _check_baked_optics() -> void:
	v.section("[BAKED OPTICS / RULE 5]")
	var weapon := load(M4) as Weapon
	weapon.attachments = {}
	_ui.open_for_weapon(weapon)
	var bodies := _all_rigid_bodies(_ui.preview_holder)
	var bad := 0
	for rb in bodies:
		if not _is_posed(rb as RigidBody3D):
			bad += 1
	v.check(bodies.size() > 0, "the weapon view_model ships %d rigid body(ies) (baked optics)" % bodies.size())
	v.check(bad == 0, "every baked body is posed, not simulated (%d bad of %d)" % [bad, bodies.size()])


## The baked optic IS the default look; with an attachment on that marker it must
## yield, so the player never sees two optics stacked.
func _check_baked_optic_toggle() -> void:
	v.section("[BAKED OPTIC TOGGLE]")
	var weapon := load(M4) as Weapon
	var point := Weapon.AttachmentPoint.TOP_RAIL
	weapon.attachments = {}
	_ui.open_for_weapon(weapon)
	var baked := _visible_children(_top_marker(_ui.preview_holder), null)
	v.check(baked > 0, "no attachment mounted -> the baked optic is the default look (%d visible)" % baked)
	var att := _first_attachment_for(point)
	if att == null:
		v.check(false, "a top-rail attachment exists for the toggle check")
		return
	weapon.attachments = {}
	weapon.attachments[point] = att
	_ui.open_for_weapon(weapon)
	var found := _find_mounted(_ui.preview_holder, point)
	if found == null:
		v.check(false, "'%s' mounted for the toggle check" % att.name)
		return
	v.check((found as Node3D).visible, "'%s' is visible once mounted" % att.name)
	var left := _visible_children(found.get_parent(), found)
	v.check(left == 0, "no baked optic stays visible next to the mounted one (%d)" % left)


## Leaves an optic mounted (a RigidBody3D that grabs itself in _ready) so the
## drift check can see whether it stays put across frames.
func _leave_risky_mounted() -> void:
	v.section("[DRIFT SETUP]")
	var weapon := load(M4) as Weapon
	var att: Attachment = null
	for f in _attachment_files():
		var candidate := load(f) as Attachment
		if candidate == null or candidate.model_scene == null:
			continue
		if candidate.attachment_point != Weapon.AttachmentPoint.TOP_RAIL:
			continue
		weapon.attachments = {}
		weapon.attachments[Weapon.AttachmentPoint.TOP_RAIL] = candidate
		_ui.open_for_weapon(weapon)
		var root := _find_mounted(_ui.preview_holder, Weapon.AttachmentPoint.TOP_RAIL)
		if root is RigidBody3D:
			att = candidate
			_held = root
			break
	if att == null or _held == null:
		v.check(false, "an optic (RigidBody3D) mounts for the drift check")
		return
	_held_name = att.name
	_held_start = (_held as Node3D).global_position
	v.check(true, "'%s' is the risky case (RigidBody3D optic)" % _held_name)


func _check_no_drift() -> void:
	v.section("[DRIFT after %d frames]" % (_frame - 1))
	if _held == null or not is_instance_valid(_held):
		v.check(false, "the mounted optic still exists after frames")
		return
	var rb := _held as RigidBody3D
	v.check(_is_posed(rb), "'%s' is STILL posed after frames (re-asserted each physics frame)" % _held_name)
	var moved := (_held as Node3D).global_position.distance_to(_held_start)
	v.check(moved < 0.001, "'%s' did not drift (moved %.4f m)" % [_held_name, moved])


## A body the preview may keep: frozen, out of the collision world, ungrabbed.
func _is_posed(rb: RigidBody3D) -> bool:
	return rb != null and rb.freeze and not rb.is_grabbed \
		and rb.collision_layer == 0 and rb.collision_mask == 0


func _first_attachment_for(point: int) -> Attachment:
	for f in _attachment_files():
		var att := load(f) as Attachment
		if att != null and att.model_scene != null and att.attachment_point == point:
			return att
	return null


## The instance the preview mounted, found by the meta it sets (not by scene path).
func _find_mounted(root: Node, point: int) -> Node:
	if root.has_meta(MOUNT_META) and int(root.get_meta(MOUNT_META)) == point:
		return root
	for c in root.get_children():
		var r := _find_mounted(c, point)
		if r != null:
			return r
	return null


## The top-rail marker of the previewed weapon (first candidate the addon knows).
func _top_marker(root: Node) -> Node3D:
	var vm := root.get_child(0)
	if vm == null:
		return null
	for marker_name in Weapon3D.marker_names_for_point(Weapon.AttachmentPoint.TOP_RAIL):
		var n := vm.get_node_or_null(String(marker_name))
		if n is Node3D:
			return n
	return null


## Visible Node3D children of a node, ignoring one (the mounted instance).
func _visible_children(parent: Node, keep: Node) -> int:
	if parent == null:
		return 0
	var n := 0
	for c in parent.get_children():
		if c != keep and c is Node3D and (c as Node3D).visible:
			n += 1
	return n


func _all_rigid_bodies(node: Node, out: Array = []) -> Array:
	if node is RigidBody3D:
		out.append(node)
	for c in node.get_children():
		_all_rigid_bodies(c, out)
	return out
