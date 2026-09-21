# res://src/meta/trader_loyalty.gd
class_name TraderLoyalty
extends Resource
## One loyalty tier of a trader. Reaching it needs BOTH a character level and a
## reputation with that trader (the genre's two-gate rule).

@export var level: int = 1
@export var required_character_level: int = 1
@export var required_reputation: int = 0

func met(character_level: int, reputation: int) -> bool:
	return character_level >= required_character_level and reputation >= required_reputation

func describe() -> String:
	return "LL%d (nivel %d, rep %d)" % [level, required_character_level, required_reputation]
