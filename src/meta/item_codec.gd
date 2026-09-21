# res://src/meta/item_codec.gd
class_name ItemCodec
extends RefCounted
## JSON-safe encode/decode for InventoryItems, so the stash and loadout can be
## written to disk and rebuilt. Reconstructs the full carried state where it
## matters for the loop: a weapon keeps its magazine (round-by-round) and
## mounted attachments, a container keeps its nested grid, ammo keeps its stack.
##
## Runtime-duplicated resources (the arena `.duplicate(true)`s weapon and ammo
## templates) lose `resource_path`. For those we fall back to an explicit
## `base_path` meta tag, then to an identity scan of the resource directory.

const WEAPON_DIR := "res://resources/weapons"
const AMMO_DIR := "res://resources/ammo"
const ATTACH_DIR := "res://resources/attachments"

# ─── ENCODE ─────────────────────────────────────────

static func encode_item(item: InventoryItem) -> Dictionary:
	if item == null:
		return {}
	var d := {
		"name": item.name,
		"stack": maxi(item.stack_count, 1),
		"dim": [item.dimensions.x, item.dimensions.y],
		"pos": [item.position.x, item.position.y],
		"mass": item.get_mass(),
	}
	var content: Resource = item.extra
	if content is Weapon:
		_encode_weapon(d, content as Weapon)
	elif content is AmmoFeed:
		d["kind"] = "ammofeed"
		d["feed"] = _encode_feed(content as AmmoFeed)
	elif content is InventoryContainer:
		d["kind"] = "container"
		d["path"] = content.resource_path
		d["nested"] = encode_container(content as InventoryContainer)
	elif content is Item:
		d["kind"] = "item"
		d["path"] = content.resource_path
	else:
		d["kind"] = "empty"
		d["path"] = ""
	return d

static func encode_container(c: InventoryContainer) -> Array:
	var out: Array = []
	if c == null:
		return out
	for item in c.items:
		var data := encode_item(item)
		if not data.is_empty():
			out.append(data)
	return out

static func encode_equipment(eq: Equipment) -> Dictionary:
	var out := {}
	if eq == null:
		return out
	for slot_name in eq.slots:
		var slot: EquipmentSlot = eq.slots[slot_name]
		var arr: Array = []
		for item in slot.items:
			var data := encode_item(item)
			if not data.is_empty():
				arr.append(data)
		if not arr.is_empty():
			out[slot_name] = arr
	return out

## Flatten an encode_equipment() result into a plain list of item dictionaries.
static func flatten_equipment(data: Dictionary) -> Array:
	var out: Array = []
	for slot_name in data:
		for item_data in data[slot_name]:
			out.append(item_data)
	return out

static func _encode_weapon(d: Dictionary, w: Weapon) -> void:
	d["kind"] = "weapon"
	d["path"] = _base_path(w, WEAPON_DIR)
	d["firemode"] = w.firemode
	d["durability"] = w.current_durability
	d["feed"] = _encode_feed(w.ammo_feed)
	var atts: Array = []
	for point in w.attachments:
		var att = w.attachments[point]
		if att is Attachment:
			atts.append({
				"path": _base_path(att as Resource, ATTACH_DIR),
				"point": int(point),
			})
	d["attachments"] = atts

static func _encode_feed(feed: AmmoFeed) -> Dictionary:
	if feed == null:
		return {}
	var rounds: Array = []
	for c in feed.contents:
		if c is Ammo:
			rounds.append(_encode_round(c as Ammo))
	var calibers: Array = []
	for cal in feed.compatible_calibers:
		calibers.append(String(cal))
	return {
		"cap": feed.max_capacity,
		"calibers": calibers,
		"empty_mass": feed.empty_mass,
		"type": int(feed.type),
		"strict": feed.strict_mode,
		"bore": feed.bore_tolerance,
		"case": feed.case_tolerance,
		"rounds": rounds,
	}

static func _encode_round(a: Ammo) -> Dictionary:
	return {
		"path": _round_path(a),
		"caliber": a.caliber,
		"mass": a.cartridge_mass,
		"mv": a.muzzle_velocity,
	}

# ─── DECODE ─────────────────────────────────────────

static func decode_item(d: Dictionary) -> InventoryItem:
	if d.is_empty():
		return null
	var kind := String(d.get("kind", "item"))
	var item: InventoryItem = null
	match kind:
		"weapon":
			item = _decode_weapon(d)
		"ammofeed":
			item = _decode_feed_item(d)
		"container":
			item = _decode_container(d)
		"empty":
			item = InventoryItem.new()
		_:
			item = _decode_plain(d)
	if item == null:
		return null
	item.name = String(d.get("name", item.name))
	item.stack_count = maxi(int(d.get("stack", 1)), 1)
	var dim = d.get("dim", null)
	if dim is Array and dim.size() == 2:
		item.dimensions = Vector2i(int(dim[0]), int(dim[1]))
	var pos = d.get("pos", null)
	if pos is Array and pos.size() == 2:
		item.position = Vector2i(int(pos[0]), int(pos[1]))
	return item

static func decode_into_equipment(eq: Equipment, data: Dictionary) -> int:
	var moved := 0
	if eq == null:
		return moved
	for slot_name in data:
		if not eq.slots.has(slot_name):
			continue
		for item_data in data[slot_name]:
			var item := decode_item(item_data)
			if item == null:
				continue
			if eq.equip(item, slot_name):
				moved += 1
	return moved

static func _decode_plain(d: Dictionary) -> InventoryItem:
	var path := String(d.get("path", ""))
	if path == "":
		push_warning("ItemCodec: item without path dropped (%s)" % String(d.get("name", "?")))
		return null
	var res := load(path)
	if not (res is Item):
		push_warning("ItemCodec: could not load item %s" % path)
		return null
	return InventorySystem.create_inventory_item(res as Item, int(d.get("stack", 1)))

static func _decode_weapon(d: Dictionary) -> InventoryItem:
	var path := String(d.get("path", ""))
	var base := load(path) as Weapon if path != "" else null
	if base == null:
		push_warning("ItemCodec: weapon base missing (%s)" % path)
		return null
	var w := base.duplicate(true) as Weapon
	w.firemode = int(d.get("firemode", w.firemode))
	w.current_durability = float(d.get("durability", w.current_durability))
	var fd = d.get("feed", {})
	if fd is Dictionary and not fd.is_empty():
		w.ammo_feed = _build_feed(fd)
	for a in d.get("attachments", []):
		if not (a is Dictionary):
			continue
		var ap := String(a.get("path", ""))
		var att := load(ap) as Attachment if ap != "" else null
		if att is Attachment:
			w.attach_attachment(int(a.get("point", 0)), att)
	return InventorySystem.create_inventory_item(w)

static func _decode_feed_item(d: Dictionary) -> InventoryItem:
	var fd = d.get("feed", {})
	var feed: AmmoFeed = _build_feed(fd) if fd is Dictionary else AmmoFeed.new()
	return InventorySystem.create_inventory_item(feed)

static func _decode_container(d: Dictionary) -> InventoryItem:
	var path := String(d.get("path", ""))
	# An encoded container may legitimately carry no base path (a bare Backpack built
	# at runtime). load("") logs `Resource file not found: res://` + a backtrace, which
	# reads like a real failure; skip the load and fall through to Backpack.new().
	var base: Resource = load(path) if path != "" else null
	var cont: InventoryContainer
	if base is InventoryContainer:
		cont = (base as InventoryContainer).duplicate(true)
	else:
		cont = Backpack.new()
	for nd in d.get("nested", []):
		if not (nd is Dictionary):
			continue
		var item := decode_item(nd)
		if item == null:
			continue
		if not cont.add_item(item, item.position):
			cont.add_item(item, Vector2i(-1, -1))
	return InventorySystem.create_inventory_item(cont)

static func _build_feed(fd: Dictionary) -> AmmoFeed:
	var feed := AmmoFeed.new()
	feed.max_capacity = maxi(int(fd.get("cap", 30)), 1)
	var ps := PackedStringArray()
	for cal in fd.get("calibers", []):
		ps.append(String(cal))
	feed.compatible_calibers = ps
	feed.empty_mass = float(fd.get("empty_mass", 0.0))
	feed.type = int(fd.get("type", AmmoFeed.Type.INTERNAL))
	feed.strict_mode = bool(fd.get("strict", false))
	feed.bore_tolerance = float(fd.get("bore", 0.1))
	feed.case_tolerance = float(fd.get("case", 1.0))
	for r in fd.get("rounds", []):
		var ammo := _resolve_round(r)
		if ammo != null:
			feed.insert(ammo)
	return feed

static func _resolve_round(r) -> Ammo:
	if r is String:
		if String(r) == "":
			return null
		return load(String(r)) as Ammo
	if not (r is Dictionary):
		return null
	var path := String(r.get("path", ""))
	if path != "":
		var a := load(path) as Ammo
		if a != null:
			return a
	return _scan_ammo(String(r.get("caliber", "")), float(r.get("mass", -1.0)), float(r.get("mv", -1.0)))

# ─── PATH RESOLUTION ────────────────────────────────

## Build a fresh inventory item straight from a resource path. Runtime state is
## isolated per item by duplicating stateful resources; the original path is
## tagged as `base_path` so re-encoding survives the lost `resource_path`.
static func item_from_path(path: String, stack_count: int = 1) -> InventoryItem:
	if path == "":
		return null
	var res := load(path)
	if res == null or not (res is Item):
		push_warning("ItemCodec: item_from_path failed: %s" % path)
		return null
	var content := res as Item
	if content is Weapon or content is AmmoFeed or content is InventoryContainer:
		content = content.duplicate(true)
	content.set_meta("base_path", path)
	var item := InventorySystem.create_inventory_item(content, stack_count)
	if item != null and content is AmmoFeed:
		item.dimensions = Vector2i(1, 2)
	return item

## Public: the resource path identifying an item's content (base_path-aware),
## used by the market to match stash items against trader offers.
static func content_path(item: InventoryItem) -> String:
	if item == null or item.extra == null:
		return ""
	var content := item.extra
	if content is Weapon:
		return _base_path(content, WEAPON_DIR)
	if content is Attachment:
		return _base_path(content, ATTACH_DIR)
	if content.resource_path != "":
		return content.resource_path
	return String(content.get_meta("base_path", ""))

static func _base_path(res: Resource, dir: String) -> String:
	if res == null:
		return ""
	if res.resource_path != "":
		return res.resource_path
	var meta_path := String(res.get_meta("base_path", ""))
	if meta_path != "":
		return meta_path
	return _scan_for_name(dir, res.name)

static func _round_path(a: Ammo) -> String:
	if a.resource_path != "":
		return a.resource_path
	var meta_path := String(a.get_meta("base_path", ""))
	if meta_path != "":
		return meta_path
	return ""

static func _scan_for_name(dir: String, target: String) -> String:
	if target == "":
		return ""
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	for f in d.get_files():
		if not f.ends_with(".tres"):
			continue
		var p := dir + "/" + f
		var r := load(p)
		if r is Resource and (r as Resource).name == target:
			return p
	return ""

static func _scan_ammo(caliber: String, mass: float, mv: float) -> Ammo:
	if caliber == "":
		return null
	var d := DirAccess.open(AMMO_DIR)
	if d == null:
		return null
	for f in d.get_files():
		if not f.ends_with(".tres"):
			continue
		var a := load(AMMO_DIR + "/" + f) as Ammo
		if a == null or a.caliber != caliber:
			continue
		if mass >= 0.0 and not is_equal_approx(a.cartridge_mass, mass):
			continue
		if mv >= 0.0 and not is_equal_approx(a.muzzle_velocity, mv):
			continue
		return a
	return null
