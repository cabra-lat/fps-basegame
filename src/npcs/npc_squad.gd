class_name NpcSquad
extends RefCounted
## Per-team blackboard — same-team bots share the last known enemy position and
## alert state (Fase 2 cont, src/npcs lane).
##
## Static, process-wide, no autoload and no networking: bots of the same team
## publish the freshest contact and read teammates' contacts to move in support
## (flanking) while friendly-fire rules stay enforced by NpcBot itself.
##
## Usage from NpcBot:
##   NpcSquad.publish(team, last_known_pos, alert_state, npc_id)
##   var info := NpcSquad.get_info(team, squad_info_ttl)  # {} when stale
## Tests/tools can reset with NpcSquad.clear().

static var _boards: Dictionary = {}


## Publish (or refresh) a team's contact. team < 0 is ignored (unteamed bots).
static func publish(team: int, pos: Vector3, state: int, source_id: int) -> void:
	if team < 0:
		return
	_boards[team] = {
		"pos": pos,
		"state": state,
		"source": source_id,
		"time": Time.get_ticks_msec() / 1000.0,
	}


## Fresh board for a team, or {} when missing/stale (older than ttl seconds).
static func get_info(team: int, ttl: float) -> Dictionary:
	if team < 0:
		return {}
	var info: Dictionary = _boards.get(team, {})
	if info.is_empty():
		return {}
	var age := Time.get_ticks_msec() / 1000.0 - float(info.get("time", 0.0))
	if age > ttl:
		return {}
	return info


## Age in seconds of a team's board, or INF when absent.
static func age(team: int) -> float:
	var info: Dictionary = _boards.get(team, {})
	if info.is_empty():
		return INF
	return Time.get_ticks_msec() / 1000.0 - float(info.get("time", 0.0))


static func clear() -> void:
	_boards.clear()


static func clear_team(team: int) -> void:
	_boards.erase(team)
