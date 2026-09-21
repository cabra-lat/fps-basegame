# res://src/meta/starter_loadout.gd
class_name StarterLoadout
extends Resource
## Data-driven "what a fresh profile enters with". Kept as a resource so the
## range/menu can tune the starting kit without code. Only seeds a profile when
## it has no loadout and an empty stash.

@export var currency: int = 25000
## slot_name -> Array[String] of resource paths (weapons, armor, backpack...).
@export var slots: Dictionary = {}
