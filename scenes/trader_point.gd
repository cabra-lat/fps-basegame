class_name TraderPoint
extends Area3D
## Reachable market marker. Interact (the existing `interact` action) opens the
## trader panel; the arena manager owns the UI and calls Meta.buy/sell.
## Put it in group "traders" with a `trader_id` matching resources/meta/traders.

signal requested(trader_id: String)

@export var trader_id: String = "quartermaster"
@export var display_name: String = "Trader"

func _ready() -> void:
	if not is_in_group("traders"):
		add_to_group("traders")

## Called by the arena's interact handler (duck-typed).
func interact(_who: Node) -> bool:
	requested.emit(trader_id)
	return true

func summary() -> String:
	return "%s [%s]" % [display_name, trader_id]
