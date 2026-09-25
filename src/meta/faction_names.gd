# res://src/meta/faction_names.gd
class_name FactionNames
extends RefCounted
## Registry from a faction id to its translation key.
##
## The shape is deliberately identical to ItemNames, and for the same reason:
## factions are DATA (a .tres per faction plus a registry), so the display text
## cannot be hardcoded in the UI and cannot be derived by scanning whatever
## happens to be checked out. The id is the machine key everywhere else -- saves,
## gates, team tints -- and this maps it to an English source string that is the
## msgid in locale/game.po.
##
## This is not a second translation MECHANISM. There is one mechanism, the PO
## layer; this is the second registry of the same kind, because items and
## factions are two different data kinds and one id namespace cannot hold both
## without collisions. `validate_i18n.gd` asserts this registry against the
## faction .tres files in both directions, so a new faction cannot ship
## untranslated and a stale id cannot linger unnoticed.

## id -> English source string (the tr() key, i.e. the PO msgid).
const KEYS := {
	"contractor": "Contractor",
	"drifter": "Drifter",
	"raider": "Raider",
}


## Translation key for a faction id, or "" when the id is not registered.
static func key_for(faction_id: String) -> String:
	return String(KEYS.get(faction_id, ""))


## Localized display name for a faction id, or "" when unregistered, so callers
## choose their own fallback rather than silently showing an id. Static, so the
## key resolves through TranslationServer rather than the instance-bound tr().
static func display_name(faction_id: String) -> String:
	var key := key_for(faction_id)
	return TranslationServer.translate(key) if key != "" else ""


## Localized display name, or the id itself when unregistered. For surfaces that
## must render something (a HUD line) rather than render nothing. The id is the
## safer fallback than a .tres name: it is machine truth and cannot be mistaken
## for finished copy.
static func display_name_for_id(faction_id: String) -> String:
	return display_name(faction_id) if KEYS.has(faction_id) else faction_id


## Every registered id, for harnesses that must cover the whole registry.
static func registered_ids() -> Array[String]:
	var out: Array[String] = []
	for id in KEYS:
		out.append(String(id))
	return out
