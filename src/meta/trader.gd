# res://src/meta/trader.gd
class_name Trader
extends Resource
## Data-driven trader: name, currency, loyalty ladder and an offer list.
## Live state (stock, reputation, unlocked LL, reset counter) lives in Market.

@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""
@export var currency: String = "CR"
@export var offers: Array[TraderOffer] = []
@export var loyalty: Array[TraderLoyalty] = []
## Stock resets every N resolved raids (simple counter; 0 = never).
@export var reset_every_raids: int = 5
## Reputation gained per completed trade, on top of any per-offer scaling.
@export var reputation_per_trade: int = 1

func display_name() -> String:
	return name if name != "" else id

## Highest loyalty level whose requirements are met.
func loyalty_level_for(character_level: int, reputation: int) -> int:
	var lvl := 1
	for l in loyalty:
		if l.met(character_level, reputation):
			lvl = maxi(lvl, l.level)
	return lvl
