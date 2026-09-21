class_name FFAMode
extends GameMode
## Free-for-all: team_count = 1, every participant scores for themselves.
## First to score_limit wins. Killer id doubles as the team key.

func _init() -> void:
	mode_name = "FFA"
	team_count = 1
	score_limit = 25
	time_limit = 0.0
	respawn_delay = 3.0
	friendly_fire = false

func on_kill(killer_id: int, victim_id: int, _victim_team: int) -> void:
	if _over or killer_id < 0 or killer_id == victim_id:
		return
	_scores[killer_id] = int(_scores.get(killer_id, 0)) + 1
	if int(_scores[killer_id]) >= score_limit:
		_over = true

## Each participant is their own team in FFA.
func assign_team(index: int) -> int:
	return index
