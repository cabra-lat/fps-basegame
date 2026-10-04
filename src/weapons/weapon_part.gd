# res://src/weapons/weapon_part.gd
class_name WeaponPart
extends Resource

## A part that fits a weapon and changes its numbers (f5cac6 successor: the
## frankenstein-weapon card).
##
## WHY A RESOURCE AND NOT A SCENE. The geometry already exists as separate scenes
## under src/weapons/ -- receiver_ar15, barrel_ar15, magazine_ak47, stock_ar15 and
## the rest, 23 tracked files -- and weapon_ar15.tscn already INSTANCES a barrel
## into a Barrel Marker3D and a stock into a Stock Marker3D. So the composition
## exists as scene structure and the gap was never geometry: it is the FIT RULE and
## the STAT, and both of those are data. A part therefore points at a scene rather
## than being one.
##
## WHY THE SOCKET IS A STRING AND NOT AN ENUM. Sockets are named after the Marker3D
## nodes the scenes already use (Barrel, Stock, Scope, MagazinePoint), so a data
## file can name one without this class having to know the vocabulary in advance --
## which is the same discipline as AmmoFeed.Type being an enum but the socket list
## being authored. The cost is that a typo is a typo, so the assembly validator
## checks every socket against the receiver's declared sockets rather than trusting
## the string.
##
## WHY DELTAS AND NOT ABSOLUTE VALUES. Decision 1 is that a build's numbers COME
## FROM its parts, but the base weapon's numbers are already authored on the .tres
## and tuning them is not this card's business. A part therefore contributes a
## DELTA to a stat the base weapon already has, so a part means the same thing on
## two different receivers instead of silently overwriting a hand-tuned value.

## Which socket on the receiver this part occupies. Names the Marker3D the scene
## already authors: "Barrel", "Stock", "Scope", "MagazinePoint", "PistolGrip",
## "Handguard", "Receiver".
@export var socket: StringName = &""

## The receiver id this part is cut for. Empty means it fits any receiver, which
## is a real authoring choice for a generic magazine and not a default -- the
## assembly validator reports an unfitted part by name rather than accepting it.
@export var fits_receiver: StringName = &""

## Calibre this part carries or requires. A barrel imposes it; a magazine must
## match it. Empty means the part does not participate in calibre matching.
@export_enum("5.56", "7.62", "9x19", "12x70", ".300", "any") var calibre: String = "any"

## The scene this part contributes.
@export var scene: NodePath

@export_group("Stat deltas")
## Applied to the base weapon's stats when this part is fitted. ADDITIVE, so the
## sign is the direction: a suppressor has a negative velocity delta and a
## positive recoil delta, and both are readable in the data file.
@export var delta_firerate: float = 0.0
@export var delta_reload_time: float = 0.0
@export var delta_accuracy: float = 0.0
@export var delta_ergonomics: float = 0.0
@export var delta_durability: float = 0.0
@export var delta_recoil_vertical: float = 0.0
@export var delta_recoil_horizontal: float = 0.0
@export var delta_recoil_kick: float = 0.0


## Every delta, keyed by the weapon field it lands on. The keys are the FIELD
## NAMES on Weapon, not labels, because a mistyped key that silently did nothing
## would be exactly the failure this card's acceptance is meant to prevent.
func stat_deltas() -> Dictionary:
	return {
		"firerate": delta_firerate,
		"base_reload_time": delta_reload_time,
		"base_accuracy": delta_accuracy,
		"base_ergonomics": delta_ergonomics,
		"max_durability": delta_durability,
		"base_recoil_vertical": delta_recoil_vertical,
		"base_recoil_horizontal": delta_recoil_horizontal,
		"base_recoil_kick": delta_recoil_kick,
	}


## A stable identity for save files and reasons. The resource PATH when it has
## one, so a saved build reloads against the same authored part rather than
## against whatever happens to be first in a directory listing.
func part_id() -> String:
	return resource_path if not resource_path.is_empty() else String(socket)


## Human-facing name, used in the reason a player reads. Falls back to the id so a
## part with no display_name is still nameable in an error rather than appearing as
## an empty string the player cannot act on.
func display_name() -> String:
	return display_name_override if not display_name_override.is_empty() else part_id().get_file().get_basename()


## Display name. Blank means "derive it from the file", which is what most parts
## want and what keeps the data file from repeating its own filename.
@export var display_name_override: String = ""