# res://src/meta/stash.gd
class_name Stash
extends InventoryContainer
## Persistent out-of-raid storage. Reuses the addon grid container (no second
## inventory implementation): a big grid with a weight ceiling. Items keep their
## grid position, so a save/load round-trip preserves layout.

const DEFAULT_WIDTH := 10
const DEFAULT_HEIGHT := 20
const DEFAULT_MAX_WEIGHT := 200.0

func _init() -> void:
	name = "Stash"
	grid_width = DEFAULT_WIDTH
	grid_height = DEFAULT_HEIGHT
	max_weight = DEFAULT_MAX_WEIGHT
	super._init()

## Place an item, falling back to the first free slot when the requested
## position is taken (or when the caller does not care).
func deposit(item: InventoryItem, position: Vector2i = Vector2i(-1, -1)) -> bool:
	if item == null:
		return false
	if add_item(item, position):
		return true
	if position != Vector2i(-1, -1):
		return add_item(item, Vector2i(-1, -1))
	return false

## Number of grid entries (a stack is one item). Use total_units() for the sum
## of stack counts.
func count_items() -> int:
	return items.size()

func total_units() -> int:
	var total := 0
	for item in items:
		total += maxi(item.stack_count, 1)
	return total
