# res://src/meta/quest.gd
class_name Quest
extends Resource
## Data-driven quest. The resource is immutable data; live progress lives in
## QuestLog so several profiles can share one quest resource.

@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export var objectives: Array[QuestObjective] = []
@export var reward_currency: int = 0
@export var reward_exp: int = 0
## Resource paths deposited into the stash on completion.
@export var reward_items: Array[String] = []
## skill_id -> xp granted on completion.
@export var reward_skill_xp: Dictionary = {}
## trader_id -> reputation granted on completion.
@export var reward_reputation: Dictionary = {}
## Prerequisite quest ids that must be CLAIMED first.
@export var requires: Array[String] = []
## Grant rewards immediately on completion (no claim UI needed).
@export var auto_claim: bool = true
## Show in the HUD/report line while active.
@export var hud_tracked: bool = true

func display_title() -> String:
	return title if title != "" else id

func reward_text() -> String:
	var parts: Array[String] = []
	if reward_currency > 0:
		parts.append("₽%d" % reward_currency)
	if reward_exp > 0:
		parts.append("%d EXP" % reward_exp)
	if not reward_items.is_empty():
		parts.append("%d item(ns)" % reward_items.size())
	if not reward_skill_xp.is_empty():
		for skill_id in reward_skill_xp:
			parts.append("+%d %s" % [int(reward_skill_xp[skill_id]), skill_id])
	if not reward_reputation.is_empty():
		for trader_id in reward_reputation:
			parts.append("+%d rep %s" % [int(reward_reputation[trader_id]), trader_id])
	return ", ".join(parts) if not parts.is_empty() else "—"
