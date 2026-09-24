class_name ArenaResultAdapter
extends RefCounted
## Arena-specific kill attribution and result interpretation. GameMode remains the
## score/friendly-fire authority; raid events, EXP, feed and respawn stay managed
## by arena_manager.

## Converts the bot's optional attacker field into the arena's historical policy:
## a recorded non-negative bot id wins; unknown/player-authored hits fall back to
## the configured player id. Returns the result consumed by arena_manager.
func record_bot_death(mode: GameMode, bot: Node, player_id: int) -> Dictionary:
	var attacker: Variant = bot.get("last_attacker_id")
	var killer_id := player_id
	if attacker is int and int(attacker) >= 0:
		killer_id = int(attacker)
	var victim_id := int(bot.get_meta("id", 0))
	var victim_team := int(bot.get_meta("team", 0))
	return record_kill(mode, player_id, killer_id, victim_id, victim_team, String(bot.name))


## Applies exactly one mode kill and returns a plain data bundle for the scene's
## downstream raid/event/feed presentation. No filtering happens here: TDM may
## ignore a friendly-fire score while the raid still records the event, as before.
func record_kill(
		mode: GameMode,
		player_id: int,
		killer_id: int,
		victim_id: int,
		victim_team: int,
		victim_name: String,
) -> Dictionary:
	var killer_team := mode.assign_team(killer_id) if killer_id >= 0 else -1
	mode.on_kill(killer_id, victim_id, victim_team)
	return {
		"killer_id": killer_id,
		"killer_team": killer_team,
		"victim_id": victim_id,
		"victim_team": victim_team,
		"victim_name": victim_name,
		"feed_text": _feed_text(mode, player_id, killer_id, victim_name, killer_team, victim_team),
	}


func winner_text(mode: GameMode, player_id: int) -> String:
	if mode is TDMMode:
		var winning_team: int = (mode as TDMMode).winning_team()
		return "empate" if winning_team < 0 else "%s vence" % mode.team_name(winning_team)
	var best_id := -1
	var best_score := -1
	var scores := mode.get_scores()
	for key in scores:
		var score := int(scores[key])
		if score > best_score:
			best_score = score
			best_id = int(key)
	return "Você vence" if best_id == player_id else "Bot %d vence" % best_id


func _feed_text(
		mode: GameMode,
		player_id: int,
		killer_id: int,
		victim_name: String,
		killer_team: int,
		victim_team: int,
) -> String:
	if killer_id == player_id:
		return "Você eliminou %s [%s]" % [victim_name, mode.team_name(killer_team)]
	if mode.team_count > 1 and killer_team == victim_team:
		return "Fogo amigo: %s" % victim_name
	return "%s abateu %s" % [mode.team_name(killer_team), victim_name]
