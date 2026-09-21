# res://tools/generate_inventory_icons.gd
#
# BUILD TOOL — generates the inventory item icons FROM OUR OWN 3D MODELS.
#
# For every Item resource that owns a usable model (its `view_model`, or the
# project's generic cartridge mesh for ammo) the tool instantiates the model in
# a SubViewport with a FIXED orthographic camera, fixed lights and a transparent
# background, renders it at 128x128 and writes a PNG plus a manifest.
#
# No ripped art, no external icons: the pixels come from `res://src/**` /
# `assets/models/**`. Re-running is deterministic (no random, fixed framing).
#
# It is a two-phase build tool because a freshly written PNG has no `.import`
# yet and `load()` would return null:
#
#   # 1. render (needs a GPU — invisible Xvfb + VirtualGL recipe from AGENTS.md)
#   DISPLAY=:99 nix shell nixpkgs#virtualgl -c vglrun -d :0 \
#     godot --path . --script res://tools/generate_inventory_icons.gd
#   # 2. import the new PNGs
#   godot --headless --path . --import
#   # 3. point every Item.icon at its generated PNG
#   godot --headless --path . --script res://tools/generate_inventory_icons.gd -- --wire
#
# Output (committed):
#   res://assets/ui/inventory/generated/<slug>.png
#   res://assets/ui/inventory/generated/manifest.json
#
# Scratch / diagnostics go to /tmp/shooter/ (never the repo).
extends SceneTree

const OUT_DIR := "res://assets/ui/inventory/generated"
const RES := 128
const SUPERSAMPLE := 2  # render at 256, downscale on CPU: anti-aliasing without
                        # MSAA, whose edge sampling made the PNGs non-deterministic
const FRAME := RES * SUPERSAMPLE
const BBOX_MARGIN := 1.20
const TARGET_FILL := 0.84  # fraction of the frame the visible pixels should span
const VIEW_DIR := Vector3(-0.55, -0.42, 0.72)

# Items whose model is the project's generic mesh (documented, not invented):
# every cartridge resource shares src/ammo/cartridges.tscn.
const GENERIC_CARTRIDGE := "res://src/ammo/cartridges.tscn"

# Raw models in assets/models that are not wired through a `view_model` yet.
# Explicit, reviewed mapping (reviewed with ballistics 2026-09-21): the clear
# name/class matches are rendered as REAL icons. Everything else falls back to
# the per-category placeholders below and is flagged in the manifest.
const MODEL_ALIASES := {
	"res://resources/weapons/AK_74.tres": "res://assets/models/weapon_ak74/PSX_AK-74.glb",
	"res://resources/weapons/Belgium_BR.tres": "res://assets/models/weapon_battle_rifle/PSX_Battle_Rifle.glb",
	"res://resources/weapons/PKM.tres": "res://assets/models/weapon_rpk/rpk.glb",
	"res://resources/weapons/M249.tres": "res://assets/models/weapon_rpk/rpk.glb",
	"res://resources/weapons/USA_Pump.tres": "res://assets/models/weapon_shotgun_benelli/PSX_Benelli.glb",
}

# Existing project scenes used as per-category weapon placeholders. Reviewed
# with ballistics: a category-level placeholder is better than the Godot logo,
# and it is DOCUMENTED (manifest.placeholders), never silent.
const WEAPON_PLACEHOLDER_SCENES := {
	"pistol": "res://src/weapons/weapon_pistol.tscn",
	"shotgun": "res://src/weapons/weapon_shotgun.tscn",
	"sniper": "res://src/weapons/weapon_awp.tscn",
	"rifle": "res://src/weapons/weapon_bengal.tscn",
}

var _vp: SubViewport
var _camera: Camera3D
var _holder: Node3D

var _manifest: Dictionary = {}
var _missing: Array[String] = []
var _rendered: Array[String] = []
var _real: Array[String] = []
var _placeholders: Dictionary = {}
var _failed: Array[String] = []
var _shared_cache: Dictionary = {}
var _only := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if "--wire" in args:
		_wire()
		quit(0)
		return
	for a in args:
		if a.begins_with("--only="):
			_only = a.substr(7)
	_run()

# ─── PHASE 1: RENDER ────────────────────────────────
func _run() -> void:
	print("=== generate_inventory_icons: render ===")
	# The SceneTree root is not inside the tree yet during _initialize(); wait one
	# frame so SubViewport/global transforms are valid.
	await process_frame
	_make_output_dir()
	_clear_output()
	_build_viewport()

	var items := _collect_items()
	print("  item resources found: %d" % items.size())

	# Always emit a neutral generic placeholder so the base Item.icon default can
	# stop pointing at the Godot logo (QA-026, player-rig lane) and so code-built
	# containers (Field Backpack, loot) have a fallback asset to use.
	await _render_node(_build_placeholder("item"), "%s/placeholder_item.png" % OUT_DIR)

	for entry in items:
		var path: String = entry["path"]
		var item: Item = entry["item"]
		if _only != "" and not path.contains(_only):
			continue
		var plan := _plan_for(item, path)
		if plan.is_empty():
			_missing.append(path)
			continue
		var key: String = plan["key"]
		if _shared_cache.has(key):
			_manifest[path] = _shared_cache[key]
			_rendered.append(path)
			if plan["placeholder"]:
				_placeholders[path] = plan["category"]
			else:
				_real.append(path)
			continue
		var out_path := "%s/%s.png" % [OUT_DIR, plan["name"]]
		var node := _instantiate(plan)
		if node != null and await _render_node(node, out_path):
			_manifest[path] = out_path
			_rendered.append(path)
			_shared_cache[key] = out_path
			if plan["placeholder"]:
				_placeholders[path] = plan["category"]
			else:
				_real.append(path)
		else:
			_failed.append(path)

	_write_manifest()
	_report()
	quit(0)

# ─── PHASE 3: WIRE ICONS ────────────────────────────
# Text-level edit, NOT ResourceSaver: saving a Resource rewrites the file and
# silently drops its `uid` and bakes computed properties (weapon mass) into the
# .tres. We only touch the icon ext_resource / icon property and leave every
# other byte (uids, ordering, values) exactly as authored.
func _wire() -> void:
	print("=== generate_inventory_icons: wire ===")
	var m := _read_manifest()
	var items: Dictionary = m.get("items", {})
	var wired := 0
	var unchanged := 0
	var skipped := 0
	for res_path in items.keys():
		var icon_path: String = items[res_path]
		var abs_res := ProjectSettings.globalize_path(res_path)
		if not FileAccess.file_exists(abs_res) or not FileAccess.file_exists(ProjectSettings.globalize_path(icon_path)):
			skipped += 1
			continue
		var icon_uid := _icon_uid(icon_path)
		match _wire_text(abs_res, icon_path, icon_uid):
			0: unchanged += 1
			1: wired += 1
			_: skipped += 1
	print("  wired %d item(s), already correct %d, skipped %d" % [wired, unchanged, skipped])

## uid declared in the PNG's .import sidecar (empty when not imported yet).
func _icon_uid(icon_path: String) -> String:
	var imp := ProjectSettings.globalize_path(icon_path + ".import")
	if not FileAccess.file_exists(imp):
		return ""
	var f := FileAccess.open(imp, FileAccess.READ)
	for line in f.get_as_text().split("\n"):
		if line.begins_with("uid="):
			var v := line.substr(4).strip_edges()
			return v.trim_prefix('"').trim_suffix('"')
	return ""

## 0 = already points at the icon, 1 = rewritten, -1 = malformed.
func _wire_text(abs_path: String, icon_path: String, icon_uid: String) -> int:
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return -1
	var lines := f.get_as_text().split("\n")
	f.close()
	if lines.is_empty() or not lines[0].begins_with("[gd_resource"):
		return -1

	# Only the MAIN [resource] block is the Item; a .tres may embed sub_resources
	# that carry their own `icon` (M4_Carbine's AmmoFeed) — never touch those.
	var resource_line := _find_line(lines, "[resource]")
	if resource_line == -1:
		return -1

	var icon_id := ""
	for i in range(resource_line + 1, lines.size()):
		var s := lines[i].strip_edges()
		if s.begins_with("icon = ExtResource("):
			icon_id = s.trim_prefix("icon = ExtResource(").trim_suffix(")").strip_edges().trim_prefix('"').trim_suffix('"')
			break

	if icon_id != "":
		var ext_line := _find_ext_id(lines, icon_id)
		if ext_line != -1:
			var replacement := _ext_line(icon_uid, icon_path, icon_id)
			if lines[ext_line] == replacement:
				return 0
			lines[ext_line] = replacement
			return _write_lines(abs_path, lines)

	# No icon yet (item used the Item.icon default): add ext_resource + property.
	var new_id := _unique_id(lines, "icon")
	var header := _find_prefix(lines, "[gd_resource")
	var last_ext := _find_last_prefix(lines, "[ext_resource")
	lines.insert(maxi(last_ext, header) + 1, _ext_line(icon_uid, icon_path, new_id))
	lines[header] = _bump_load_steps(lines[header])
	resource_line = _find_line(lines, "[resource]")
	if resource_line == -1:
		return -1
	# Insert AFTER `script =` so the property exists when assigned: a property
	# set before the script is attached is silently dropped (the base Resource
	# has no `icon`), which is why the first insert attempt loaded icon.svg.
	var anchor := resource_line
	for i in range(resource_line + 1, lines.size()):
		if lines[i].strip_edges().begins_with("script = "):
			anchor = i
			break
	lines.insert(anchor + 1, 'icon = ExtResource("%s")' % new_id)
	return _write_lines(abs_path, lines)

func _find_line(lines: PackedStringArray, exact: String) -> int:
	for i in lines.size():
		if lines[i].strip_edges() == exact:
			return i
	return -1

func _find_prefix(lines: PackedStringArray, prefix: String) -> int:
	for i in lines.size():
		if lines[i].begins_with(prefix):
			return i
	return -1

func _find_last_prefix(lines: PackedStringArray, prefix: String) -> int:
	var out := -1
	for i in lines.size():
		if lines[i].begins_with(prefix):
			out = i
	return out

func _find_ext_id(lines: PackedStringArray, id: String) -> int:
	for i in lines.size():
		if lines[i].begins_with("[ext_resource") and lines[i].contains('id="%s"' % id):
			return i
	return -1

func _write_lines(abs_path: String, lines: PackedStringArray) -> int:
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		return -1
	f.store_string("\n".join(lines))
	f.close()
	return 1

func _ext_line(uid: String, path: String, id: String) -> String:
	var uid_attr := ' uid="%s"' % uid if uid != "" else ""
	return '[ext_resource type="Texture2D"%s path="%s" id="%s"]' % [uid_attr, path, id]

func _unique_id(lines: PackedStringArray, base: String) -> String:
	var id := base
	var n := 0
	while true:
		var taken := false
		for line in lines:
			if line.begins_with("[ext_resource") and line.contains('id="%s"' % id):
				taken = true
				break
		if not taken:
			return id
		n += 1
		id = "%s_%d" % [base, n]
	return id

func _bump_load_steps(header: String) -> String:
	var re := RegEx.new()
	re.compile("load_steps=([0-9]+)")
	var result := re.search(header)
	if result == null:
		return header
	var n := int(result.get_string(1)) + 1
	return header.substr(0, result.get_start()) + "load_steps=%d" % n + header.substr(result.get_end())

# ─── VIEWPORT / LIGHTS ──────────────────────────────
func _build_viewport() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(FRAME, FRAME)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	get_root().add_child(_vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(1, 1, 1, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.92, 1.0)
	env.ambient_light_energy = 0.65
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_vp.add_child(_camera)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, -35, 0)
	key.light_energy = 1.35
	key.shadow_enabled = false
	_vp.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 150, 0)
	fill.light_energy = 0.55
	fill.shadow_enabled = false
	_vp.add_child(fill)

	_holder = Node3D.new()
	_holder.name = "ModelHolder"
	_vp.add_child(_holder)

func _render_node(root: Node3D, out_path: String) -> bool:
	if _holder.get_child_count() > 0:
		for c in _holder.get_children():
			c.free()

	if root == null:
		push_error("model is not a Node3D: %s" % out_path)
		return false
	# Sanitize BEFORE entering the tree so `_ready()` of gameplay scripts never
	# runs (an icon is a still render, not a sim).
	_sanitize(root)
	_holder.add_child(root)

	# Flush two frames so the next measured frame belongs to THIS model, not the
	# previous one (the framebuffer lags behind a free+add by one draw).
	await _render_frame()
	await _render_frame()

	var aabb := _model_aabb(root)
	if aabb.size.length() <= 0.000001 and _mesh_count(root) == 0:
		push_error("no meshes for %s" % out_path)
		_holder.remove_child(root)
		root.free()
		return false

	var center := aabb.get_center()
	var max_dim := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if max_dim <= 0.000001:
		max_dim = 1.0
	var dir := VIEW_DIR.normalized()
	_camera.global_position = center - dir * (max_dim * 6.0)
	_camera.look_at(center, Vector3.UP)

	# Auto-fit: the mesh AABB is not always the VISIBLE size (the cartridge is a
	# capsule reshaped inside its shader), so measure the rendered alpha and
	# converge the orthographic size + centering instead of trusting the bounds.
	var ortho := max_dim * BBOX_MARGIN
	var img: Image = null
	var bbox := Rect2i()
	var basis := _camera.global_transform.basis
	for i in 5:
		_camera.size = ortho
		img = await _render_frame()
		if img == null:
			break
		bbox = _alpha_bbox(img)
		if bbox.size.x <= 0 or bbox.size.y <= 0:
			break
		# Re-center the frame on the visible pixels (image +y is down).
		var d := (Vector2(bbox.position) + Vector2(bbox.size) * 0.5) - Vector2(FRAME * 0.5, FRAME * 0.5)
		_camera.global_position += basis.x * (d.x / FRAME * ortho) - basis.y * (d.y / FRAME * ortho)
		var fill := maxf(bbox.size.x, bbox.size.y) / float(FRAME)
		if absf(fill - TARGET_FILL) < 0.03 and d.length() < 1.5:
			break
		ortho *= fill / TARGET_FILL

	_camera.size = ortho
	img = await _render_frame()

	if img == null:
		push_error("no image for %s" % out_path)
		_holder.remove_child(root)
		root.free()
		return false
	img.convert(Image.FORMAT_RGBA8)
	img.resize(RES, RES, Image.INTERPOLATE_LANCZOS)
	var err := img.save_png(ProjectSettings.globalize_path(out_path))
	_holder.remove_child(root)
	root.free()
	if err != OK:
		push_error("save_png failed for %s (err %d)" % [out_path, err])
		return false
	print("  wrote %s  (mesh bbox %.2f x %.2f, ortho %.3f)" % [out_path, aabb.size.x, aabb.size.y, _camera.size])
	return true

func _render_frame() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var tex := _vp.get_texture()
	if tex == null:
		return null
	return tex.get_image()

## Bounding box of the non-transparent pixels (threshold 0.02 alpha).
func _alpha_bbox(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var minx := w
	var miny := h
	var maxx := -1
	var maxy := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.02:
				if x < minx: minx = x
				if y < miny: miny = y
				if x > maxx: maxx = x
				if y > maxy: maxy = y
	if maxx < 0:
		return Rect2i()
	return Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)

func _mesh_count(root: Node3D) -> int:
	return root.find_children("*", "MeshInstance3D", true, false).size()

## Remove gameplay scripts and freeze physics: an icon is a still render, no
## `_ready()` / gravity / spring simulation must run.
func _sanitize(node: Node) -> void:
	if node.get_script() != null:
		node.set_script(null)
	if node is RigidBody3D:
		(node as RigidBody3D).freeze = true
		(node as RigidBody3D).gravity_scale = 0.0
	if node is MeshInstance3D:
		_freeze_time_shaders(node as MeshInstance3D)
	for c in node.get_children():
		_sanitize(c)

## Some item shaders (cartridge tracer / bullet heat) animate on `TIME`, which
## would make the PNG non-deterministic between runs. Disable those uniforms on
## a duplicated material so the re-render is byte-stable and the shared project
## resource is never mutated.
func _freeze_time_shaders(mi: MeshInstance3D) -> void:
	if mi.material_override is ShaderMaterial:
		mi.material_override = _frozen(mi.material_override)
	for i in mi.get_surface_override_material_count():
		var m := mi.get_surface_override_material(i)
		if m is ShaderMaterial:
			mi.set_surface_override_material(i, _frozen(m))
	if mi.mesh != null:
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m is ShaderMaterial:
				mi.set_surface_override_material(i, _frozen(m))

func _frozen(mat: ShaderMaterial) -> ShaderMaterial:
	var dup: ShaderMaterial = mat.duplicate()
	dup.set_shader_parameter("tracer_enable", false)
	dup.set_shader_parameter("bullet_heat_with_distance_enable", false)
	return dup

func _model_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var xf := root.global_transform.affine_inverse()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var meshi := mi as MeshInstance3D
		if meshi.mesh == null or not meshi.is_visible_in_tree():
			continue
		var local := meshi.mesh.get_aabb()
		var xform := xf * meshi.global_transform
		for i in 8:
			var p := xform * local.get_endpoint(i)
			if first:
				out = AABB(p, Vector3.ZERO)
				first = false
			else:
				out = out.expand(p)
	return out

# ─── DISCOVERY ──────────────────────────────────────
func _collect_items() -> Array:
	var found: Array = []
	var files := _walk("res://resources", [".tres"])
	files.sort()
	for path in files:
		if path.ends_with(".import"):
			continue
		var item = load(path)
		if item is Item:
			found.append({"path": path, "item": item})
	return found

## Decide how an item gets its icon. Returns `{}` when nothing is possible.
##   scene  : a PackedScene to instantiate (real model or category scene)
##   builder: a procedural placeholder category to build from primitives
##   key    : render-cache key (shared for generic mesh / per-category placeholder)
##   name   : output file stem
##   placeholder: true when this is a documented placeholder, not a real model
func _plan_for(item: Item, path: String) -> Dictionary:
	if item.view_model != null and item.view_model is PackedScene:
		return {"scene": item.view_model, "key": path, "name": _slug(path), "category": _category_of(item), "placeholder": false}
	if MODEL_ALIASES.has(path):
		var s = load(MODEL_ALIASES[path])
		if s is PackedScene:
			return {"scene": s, "key": path, "name": _slug(path), "category": "weapon", "placeholder": false}
	if path.begins_with("res://resources/ammo/"):
		return {"scene": load(GENERIC_CARTRIDGE), "key": "cartridge", "name": "cartridge", "category": "ammo", "placeholder": false}
	var cat := _category_of(item)
	if item is Weapon:
		var wcat := _weapon_category(path)
		if WEAPON_PLACEHOLDER_SCENES.has(wcat):
			var sc = load(WEAPON_PLACEHOLDER_SCENES[wcat])
			if sc is PackedScene:
				var key := "placeholder_weapon_" + wcat
				return {"scene": sc, "key": key, "name": key, "category": "weapon", "placeholder": true}
	var pkey := "placeholder_" + cat
	return {"builder": cat, "key": pkey, "name": pkey, "category": cat, "placeholder": true}

func _instantiate(plan: Dictionary) -> Node3D:
	if plan.has("scene"):
		var scene: PackedScene = plan["scene"]
		return scene.instantiate() as Node3D
	if plan.has("builder"):
		return _build_placeholder(plan["builder"])
	return null

func _category_of(item: Item) -> String:
	if item is Weapon:
		return "weapon"
	if item is Armor:
		return "armor"
	if item is Attachment:
		return "attachment"
	if item is MedicalItem:
		return "medical"
	if item is AmmoFeed:
		return "magazine"
	if item is Ammo:
		return "ammo"
	return "item"

func _weapon_category(path: String) -> String:
	var n := path.get_file().get_basename().to_lower()
	if n.contains("glock") or n.contains("colt") or n.contains("eagle") or n.contains("uzi") or n.contains("mp5"):
		return "pistol"
	if n.contains("mossberg") or n.contains("saiga"):
		return "shotgun"
	if n.contains("remington") or n.contains("barrett") or n.contains("dragunov") or n.contains("m14"):
		return "sniper"
	return "rifle"

## Neutral, per-category placeholder geometry built from our own primitives
## (documented in manifest.placeholders). Never a ripped/external icon.
func _build_placeholder(category: String) -> Node3D:
	var root := Node3D.new()
	match category:
		"armor":
			_add_box(root, Vector3(0.30, 0.40, 0.06), Vector3.ZERO, Color(0.30, 0.36, 0.44))
			_add_box(root, Vector3(0.26, 0.10, 0.07), Vector3(0, 0.24, 0), Color(0.20, 0.24, 0.30))
		"attachment":
			_add_cylinder(root, 0.035, 0.20, Vector3(0, 0, 0.12), Color(0.18, 0.18, 0.20))
			_add_box(root, Vector3(0.12, 0.05, 0.10), Vector3(0, -0.05, -0.02), Color(0.12, 0.12, 0.14))
		"medical":
			_add_box(root, Vector3(0.26, 0.18, 0.16), Vector3.ZERO, Color(0.88, 0.88, 0.90))
			_add_box(root, Vector3(0.11, 0.11, 0.02), Vector3(0, 0, 0.09), Color(0.80, 0.15, 0.15))
		"magazine":
			_add_box(root, Vector3(0.08, 0.22, 0.06), Vector3.ZERO, Color(0.25, 0.25, 0.28))
		_:
			_add_box(root, Vector3(0.22, 0.22, 0.22), Vector3.ZERO, Color(0.35, 0.35, 0.38))
	return root

func _add_box(root: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _placeholder_material(color)
	root.add_child(mi)

func _add_cylinder(root: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = Vector3(0, 0, 90)  # tube along X, readable in the 3/4 view
	mi.material_override = _placeholder_material(color)
	root.add_child(mi)

func _placeholder_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	mat.metallic = 0.1
	return mat

func _walk(dir_path: String, exts: Array) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			out.append_array(_walk(full, exts))
		else:
			for e in exts:
				if name.ends_with(e):
					out.append(full)
					break
		name = d.get_next()
	d.list_dir_end()
	return out

func _slug(path: String) -> String:
	var rel := path.trim_prefix("res://resources/").trim_suffix(".tres")
	var out := ""
	for i in rel.length():
		var c := rel[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif c >= "A" and c <= "Z":
			out += c.to_lower()
		else:
			out += "_"
	return out

# ─── MANIFEST / REPORT ──────────────────────────────
func _make_output_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

## Remove stale PNGs so a re-run cannot leave an orphan icon behind. The
## `.png.import` sidecars are KEPT: they carry the resource uid that the .tres
## files reference, so deleting them would churn every wired icon on a re-run.
func _clear_output() -> void:
	var d := DirAccess.open(OUT_DIR)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.ends_with(".png") and not d.current_is_dir():
			d.remove(name)
		name = d.get_next()
	d.list_dir_end()

func _write_manifest() -> void:
	var data := {
		"generator": "tools/generate_inventory_icons.gd",
		"size": RES,
		"items": _manifest,
		"real_model": _real,
		"placeholders": _placeholders,
		"missing_model": _missing,
		"failed": _failed,
	}
	var f := FileAccess.open(OUT_DIR + "/manifest.json", FileAccess.WRITE)
	if f == null:
		push_error("cannot write manifest")
		return
	f.store_string(JSON.stringify(data, "  ") + "\n")
	f.close()

func _read_manifest() -> Dictionary:
	if not FileAccess.file_exists(OUT_DIR + "/manifest.json"):
		push_error("no manifest — run the render phase first")
		return {}
	var f := FileAccess.open(OUT_DIR + "/manifest.json", FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

func _report() -> void:
	print("")
	print("=== generate_inventory_icons summary ===")
	print("  rendered (real model)  %d" % _real.size())
	print("  rendered (placeholder) %d" % _placeholders.size())
	print("  no icon at all         %d" % _missing.size())
	print("  failed                 %d" % _failed.size())
	var by_cat := {}
	for p in _placeholders.keys():
		var c: String = _placeholders[p]
		by_cat[c] = by_cat.get(c, 0) + 1
	if by_cat.size() > 0:
		print("  placeholders by category: %s" % by_cat)
	print("  manifest               %s/manifest.json" % OUT_DIR)
	if _missing.size() > 0:
		print("  -- items without a model (no icon generated, NOT faked) --")
		for p in _missing:
			print("     %s" % p)
