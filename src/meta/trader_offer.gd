# res://src/meta/trader_offer.gd
class_name TraderOffer
extends Resource
## One tradable line. Currency price and/or a barter requirement. Mutable stock
## lives in Market state, not on the resource (resources are shared data).

@export var item_path: String = ""
## What the player pays to buy one unit. 0 with a barter requirement = barter only.
@export var buy_price: int = 0
## What the player receives when selling one unit. 0 = trader does not buy it.
@export var sell_price: int = 0
## Starting/max stock per reset. -1 = unlimited.
@export var stock_max: int = 1
## Minimum loyalty level required to see/buy the offer.
@export var min_loyalty: int = 1
## item_path -> count required instead of (or on top of) currency. Empty = no barter.
@export var barter_required: Dictionary = {}

func is_barter() -> bool:
	return not barter_required.is_empty()

func item_name() -> String:
	if item_path == "":
		return "?"
	var res := load(item_path)
	return String(res.name) if res != null else item_path.get_file()

func price_text() -> String:
	if is_barter():
		var parts: Array[String] = []
		for path in barter_required:
			parts.append("%d x %s" % [int(barter_required[path]), _short_name(String(path))])
		var extra := "" if buy_price <= 0 else " + ₽%d" % buy_price
		return " + ".join(parts) + extra
	return "₽%d" % buy_price

func sell_text() -> String:
	return "—" if sell_price <= 0 else "₽%d" % sell_price

func _short_name(path: String) -> String:
	var res := load(path)
	return String(res.name) if res != null else path.get_file()
