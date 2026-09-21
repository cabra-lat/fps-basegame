class_name FactionRegistry
extends RefCounted
## Loads the faction pack (data) and answers id lookups.
##
## Factions are content: the pack defines 1..N of them and nothing here assumes
## a count. Same shape as the other content registries (`Market.load_dir`,
## `QuestLog.load_dir`), so a game drops its own `.tres` files in the directory
## and gets them without a code change.
##
## Bad data fails loud: an empty id, a duplicate id or an unknown lookup is a
## `push_error`, never a silent fallback to a default faction.

const FACTIONS_DIR := "res://resources/meta/factions"

var _by_id: Dictionary = {} # id -> Faction
var _order: Array[String] = [] # pack order, stable for UI listing

static var _default: FactionRegistry = null


## Process-wide pack, loaded once from FACTIONS_DIR. Scenes/harnesses that want
## an isolated pack build their own registry and pass it explicitly.
static func default_registry() -> FactionRegistry:
	if _default == null:
		_default = FactionRegistry.new()
		_default.load_dir()
	return _default


## Load every `.tres` in `dir` (filename order, so `all()`/`ids()` are stable
## for UI listing). Returns how many factions were added.
func load_dir(dir: String = FACTIONS_DIR) -> int:
	var loaded := 0
	var d := DirAccess.open(dir)
	if d == null:
		push_error("FactionRegistry: cannot open faction pack %s" % dir)
		return loaded
	var files := d.get_files()
	files.sort()
	for f in files:
		if not f.ends_with(".tres"):
			continue
		var faction := load(dir + "/" + f) as Faction
		if faction == null:
			push_error("FactionRegistry: %s/%s is not a Faction resource" % [dir, f])
			continue
		if add(faction):
			loaded += 1
	return loaded


## Registers one faction. Rejects (loudly) a missing or duplicate id.
func add(faction: Faction) -> bool:
	if faction == null:
		push_error("FactionRegistry: refusing to add a null faction")
		return false
	if faction.id == "":
		push_error("FactionRegistry: faction with an empty id refused (%s)" % faction.resource_path)
		return false
	if _by_id.has(faction.id):
		push_error("FactionRegistry: duplicate faction id \"%s\" (%s)" % [faction.id, faction.resource_path])
		return false
	_by_id[faction.id] = faction
	_order.append(faction.id)
	return true


func has(id: String) -> bool:
	return _by_id.has(id)


## Lookup that returns null for an unknown id (callers that must not continue
## should use require()).
func get_faction(id: String) -> Faction:
	return _by_id.get(id, null)


## Lookup for a path that cannot degrade: an unknown id is an error in the data
## or in the save, so it always reports instead of guessing.
func require(id: String) -> Faction:
	var f := get_faction(id)
	if f == null:
		push_error("FactionRegistry: unknown faction id \"%s\" (pack has %d: %s)" % [id, count(), ", ".join(PackedStringArray(ids()))])
	return f


func all() -> Array[Faction]:
	var out: Array[Faction] = []
	for id in _order:
		out.append(_by_id[id])
	return out


func ids() -> Array[String]:
	return _order.duplicate()


func count() -> int:
	return _order.size()


## Factions a player profile may use (NPC-only factions are excluded).
func playable() -> Array[Faction]:
	var out: Array[Faction] = []
	for f in all():
		if f.playable:
			out.append(f)
	return out


func display_name(id: String) -> String:
	var f := require(id)
	return f.resolved_name() if f != null else id


func color(id: String) -> Color:
	var f := require(id)
	return f.color if f != null else Color.WHITE
