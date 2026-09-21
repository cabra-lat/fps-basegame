class_name PlayerProfile
extends Resource
## Minimal raid profile: faction + currency + a tiny inventory for key items.
## Deliberately NOT a full economy (Fase 2) — just enough for V-Ex charging
## and required-item gates.

enum Faction { PMC, SCAV }

@export var faction: Faction = Faction.PMC
@export var team: int = 0 ## used by COOP gates / GameMode integration
@export var currency: int = 25000 # roubles; V-Ex is ~20k
@export var inventory: Dictionary = {} # item_id -> count

func faction_name() -> String:
	return "PMC" if faction == Faction.PMC else "SCAV"

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
