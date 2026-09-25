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
## This is deliberately a registry and not a load-and-scan: an id has no
## canonical resource path, so resolving names from the .tres files would make
## the display text depend on what happens to be checked out.

## id -> English source string (the tr() key, i.e. the PO msgid).
const KEYS := {
	"marked_intel": "Marked Intel",
}


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
