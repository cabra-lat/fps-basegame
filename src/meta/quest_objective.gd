# res://src/meta/quest_objective.gd
class_name QuestObjective
extends Resource
## One objective inside a Quest. Data-driven (.tres), evaluated by the quest log
## against raid-bus events.

enum Kind {
	KILL,           # kill N hostiles (player kills only)
	LOOT_ITEM,      # obtain N matching items
	EXTRACT_AT,     # extract from a named point (RUN_THROUGH does not count)
	SURVIVE_EXTRACT # survive and extract (RUN_THROUGH does not count)
}

@export var kind: Kind = Kind.KILL
@export var amount: int = 1
## KILL: optional substring of the weapon name.
@export var weapon_filter: String = ""
## LOOT_ITEM: optional substring of item name (or "medical" tag via tag_filter).
@export var item_filter: String = ""
## LOOT_ITEM: tag selector. Only "medical" is meaningful today.
@export var tag_filter: String = ""
## EXTRACT_AT: substring of the extraction point display name.
@export var point_filter: String = ""

func matches_kill(weapon: String) -> bool:
	if weapon_filter == "":
		return true
	return weapon.to_lower().contains(weapon_filter.to_lower())

func matches_item(item: Resource) -> bool:
	if item == null:
		return false
	if tag_filter == "medical" and not (item is MedicalItem):
		return false
	if item_filter != "":
		var name := String(item.get("name"))
		if not name.to_lower().contains(item_filter.to_lower()):
			return false
	return tag_filter != "" or item_filter != ""

func matches_point(point_name: String) -> bool:
	if point_filter == "":
		return true
	return point_name.to_lower().contains(point_filter.to_lower())

func describe() -> String:
	match kind:
		Kind.KILL:
			var w := "" if weapon_filter == "" else " com %s" % weapon_filter
			return "matar %d%s" % [amount, w]
		Kind.LOOT_ITEM:
			var what := tag_filter if tag_filter != "" else item_filter
			return "obter %d x %s" % [amount, what]
		Kind.EXTRACT_AT:
			return "extrair por %s" % (point_filter if point_filter != "" else "qualquer ponto")
		Kind.SURVIVE_EXTRACT:
			return "sobreviver e extrair"
	return "?"
