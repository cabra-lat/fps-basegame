# res://src/meta/item_names.gd
class_name ItemNames
extends RefCounted
## Registry from a machine item id to its translation key.
##
## The id is the machine key everywhere else: profiles, quests, save files and
## the extraction gates all compare ids (`has_item`, `consume_item`). The
## human-readable text is NOT stored on the id and NOT hardcoded in code: the
## registry maps the id to an English source string, which is the msgid in
## locale/game.po, and `tr()` resolves it at runtime.
##
## This is deliberately a registry and not a load-and-scan: the id has no
## canonical resource path in the save format, so resolving names from the
## .tres files would make the display text depend on what is checked out. The
## resource path is still the right key for the UI surfaces that hold a PATH
## rather than an id (trader offers, the market feed), and `id_for_path` derives
## the id from it with the one convention this repo already uses: an id IS the
## resource file's basename. `validate_i18n.gd` asserts that convention for
## every registered entry and asserts that every item a trader can sell resolves,
## so the convention cannot rot silently as entries are added.

## id -> English source string (the tr() key, i.e. the PO msgid).
##
## One entry per item the UI can render by name. Kept in step with the PO: the
## invariant fails if an id here has no catalogue entry, and fails if a trader
## offers an item that is missing from here.
const KEYS := {
	"5_56_45mm_SS109_VPAM_PM7": "5.56x45mm Ammo",
	"Sweden_R1": "Red Dot Sight",
	"USA_FH": "Muzzle Suppressor",
	"M4_Carbine": "M4 Carbine",
	"army_bandage": "Army Bandage",
	"cat_hemostatic_tourniquet": "CAT Hemostatic Tourniquet",
	"salewa_first_aid_kit": "First Aid Kit",
	"marked_intel": "Marked Intel",
}


## Item id for a resource path, or "" when the id is not registered.
## The id is the file's basename, which is the convention every id in this
## registry already follows and which the invariant enforces.
static func id_for_path(path: String) -> String:
	if path == "":
		return ""
	var id := path.get_file().get_basename()
	return id if KEYS.has(id) else ""


## Localized display name for a resource path, or "" when it is not registered.
static func display_name_for_path(path: String) -> String:
	return display_name(id_for_path(path))


## Localized display name for whatever the caller is holding, or "" when
## unregistered. Two shapes reach here and they are NOT interchangeable, which
## cost a real bug: a purchase returns an `InventoryItem` WRAPPER, and
## `InventoryItem.resource_path` is EMPTY, so resolving by the wrapper's own path
## returned "" and the caller fell back to the .tres name — the leak survived the
## fix that removed it. A wrapper's identity lives in `ItemCodec.content_path`.
static func display_name_for_item(item: Variant) -> String:
	if item == null:
		return ""
	if item is InventoryItem:
		return display_name_for_path(ItemCodec.content_path(item))
	if item is Resource:
		return display_name_for_path((item as Resource).resource_path)
	return ""


## Translation key for an item id, or "" when the id is not registered.
static func key_for(item_id: String) -> String:
	return String(KEYS.get(item_id, ""))


## Localized display name for an item id, or "" when the id is not registered.
## Callers decide their own fallback: a gate shows a generic phrase, an
## inventory row shows the item's own name. Static, so the key resolves through
## TranslationServer rather than the instance-bound tr().
static func display_name(item_id: String) -> String:
	var key := key_for(item_id)
	return TranslationServer.translate(key) if key != "" else ""


## Every registered id, for harnesses that must cover the whole registry.
static func registered_ids() -> Array[String]:
	var out: Array[String] = []
	for id in KEYS:
		out.append(String(id))
	return out
