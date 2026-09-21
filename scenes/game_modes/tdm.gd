class_name TDMMode
extends GameMode
## Team deathmatch: 2 teams, score per team, first team to score_limit wins.
## Team is derived from the participant index (alternating), so the level can
## assign teams without extra bookkeeping. Friendly fire is off by default:
## a kill on your own team scores nothing.

func _init() -> void:
	mode_name = "TDM"
	team_count = 2
	score_limit = 30
	time_limit = 0.0
	respawn_delay = 4.0
	friendly_fire = false

func on_kill(killer_id: int, victim_id: int, victim_team: int) -> void:
	if _over or killer_id < 0 or killer_id == victim_id:
		return
	var killer_team: int = assign_team(killer_id)
	if killer_team == victim_team and not friendly_fire:
		return # teamkill ignored (no score, no penalty)
	_scores[killer_team] = int(_scores.get(killer_team, 0)) + 1
	if int(_scores[killer_team]) >= score_limit:
		_over = true

func assign_team(index: int) -> int:
	return index % 2

func team_name(team: int) -> String:
	return "TIME %s" % ("ALPHA" if team == 0 else "BRAVO")

## Winning team, or -1 for a draw / not over.
func winning_team() -> int:
	if not _over:
		return -1
	var best := -1
	var best_score := -1
	var tie := false
	for t in range(maxi(team_count, 1)):
		var s := int(_scores.get(t, 0))
		if s > best_score:
			best_score = s
			best = t
			tie = false
		elif s == best_score:
			tie = true
	return -1 if tie else best
