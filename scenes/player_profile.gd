class_name PlayerProfile
extends Resource
## Minimal raid profile: faction id + currency + a tiny inventory for key items.
## Deliberately NOT a full economy (Fase 2) — just enough for V-Ex charging
## and required-item gates.
##
## `faction` is a String id into the faction pack (`FactionRegistry`), never an
## enum: factions are content, the game defines how many exist and their names.

## Used only when a profile is created from nothing. Any real profile carries an
## id chosen by the game (see `resources/meta/factions/`).
const DEFAULT_FACTION := "contractor"
## v1 saves stored the faction as an index into the old two-value enum, in this
## order. Read only to migrate an old save; nothing writes a number any more.
const LEGACY_FACTION_ORDER: Array[String] = ["contractor", "drifter"]

@export var faction: String = DEFAULT_FACTION
@export var team: int = 0 ## used by COOP gates / GameMode integration
@export var currency: int = 25000 # credits; V-Ex is ~20k
@export var inventory: Dictionary = {} # item_id -> count


## Accepts what a save may hold. A String is the current shape; a number is a
## v1 save and is translated explicitly (never guessed); anything else reports.
static func faction_from_saved(value) -> String:
	if value is String:
		return value
	if value is int or value is float:
		var i := int(value)
		if i >= 0 and i < LEGACY_FACTION_ORDER.size():
			push_warning("PlayerProfile: migrating legacy numeric faction %d -> \"%s\"" % [i, LEGACY_FACTION_ORDER[i]])
			return LEGACY_FACTION_ORDER[i]
		push_error("PlayerProfile: legacy numeric faction %d is out of range (0..%d)" % [i, LEGACY_FACTION_ORDER.size() - 1])
		return DEFAULT_FACTION
	push_error("PlayerProfile: unsupported saved faction value %s" % [value])
	return DEFAULT_FACTION


## Display name mounted from the pack. An unknown id is an error in the data or
## the save, so it reports and shows the raw id instead of inventing a faction.
func faction_name(registry: FactionRegistry = null) -> String:
	var reg := registry if registry != null else FactionRegistry.default_registry()
	var f := reg.get_faction(faction)
	if f == null:
		push_error("PlayerProfile: unknown faction id \"%s\" (pack has %d: %s)" % [faction, reg.count(), ", ".join(PackedStringArray(reg.ids()))])
		return faction
	return f.resolved_name()


## Team-tint colour for this profile's faction (HUD/markers).
func faction_color(registry: FactionRegistry = null) -> Color:
	var reg := registry if registry != null else FactionRegistry.default_registry()
	var f := reg.get_faction(faction)
	if f == null:
		push_error("PlayerProfile: unknown faction id \"%s\" (no colour; pack has %d)" % [faction, reg.count()])
		return Color.WHITE
	return f.color


## Gate for a profile about to enter a raid: the id must exist in the pack and
## be playable. Returns false and reports — a bad faction is never quietly kept.
func validate_faction(registry: FactionRegistry = null) -> bool:
	var reg := registry if registry != null else FactionRegistry.default_registry()
	var f := reg.get_faction(faction)
	if f == null:
		push_error("PlayerProfile: faction \"%s\" is not in the pack (%d loaded)" % [faction, reg.count()])
		return false
	if not f.playable:
		push_error("PlayerProfile: faction \"%s\" is NPC-only (playable=false)" % faction)
		return false
	return true


func can_afford(cost: int) -> bool:
	return cost <= 0 or currency >= cost


func spend(cost: int) -> bool:
	if cost <= 0:
		return true
	if currency < cost:
		return false
	currency -= cost
	return true


func earn_currency(amount: int) -> void:
	currency += maxi(amount, 0)


func has_item(item_id: String) -> bool:
	return item_id == "" or int(inventory.get(item_id, 0)) > 0


func consume_item(item_id: String) -> bool:
	if item_id == "":
		return true
	if not has_item(item_id):
		return false
	inventory[item_id] = int(inventory[item_id]) - 1
	return true
