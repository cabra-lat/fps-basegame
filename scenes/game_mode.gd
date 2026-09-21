class_name GameMode
extends Resource
## Pluggable match rules — the "framework" seam of the game.
##
## FROZEN CONTRACT (npc-body consumes this; do not change without an AMQ
## heads-up to npc-body + coordinator):
##   mode_name: String
##   team_count: int            # 1 = FFA (every player is their own team)
##   score_limit: int
##   time_limit: float          # seconds, 0 = no limit
##   respawn_delay: float
##   friendly_fire: bool
##   on_kill(killer_id, victim_id, victim_team) -> void
##   is_match_over() -> bool
##   get_scores() -> Dictionary
##   assign_team(index) -> int
##   get_spawn(team) -> Vector3
##
## The level injects spawn points through setup(); get_spawn(team) must always
## return a safe point for that team. Subclasses: FFAMode, TDMMode.

@export var mode_name: String = "GAME MODE"
@export var team_count: int = 1
@export var score_limit: int = 25
@export var time_limit: float = 0.0
@export var respawn_delay: float = 3.0
@export var friendly_fire: bool = false

## Spawn points injected by the level (arena markers). Not part of the frozen
## contract's signature, but get_spawn() needs them.
var spawn_points: Array[Vector3] = []

## team -> next offset inside that team's slice (FFA shares one cursor). Reset by
## setup(), so a round always starts from the same deterministic order.
var _spawn_cursor: Dictionary = {}

var _scores: Dictionary = {}
var _elapsed: float = 0.0
var _over: bool = false

## Called by the level before the match starts. Resets scores/clock.
func setup(points: Array[Vector3]) -> void:
	spawn_points = points.duplicate()
	_spawn_cursor.clear()
	_scores.clear()
	_over = false
	_elapsed = 0.0
	var teams: int = maxi(team_count, 1)
	for t in range(teams):
		_scores[t] = 0

## Called every physics frame by the level (drives time_limit).
func tick(delta: float) -> void:
	if _over:
		return
	_elapsed += delta
	if time_limit > 0.0 and _elapsed >= time_limit:
		_over = true

# ─── FROZEN CONTRACT ───

## killer_id < 0 means "unknown killer" (e.g. environment): no score.
func on_kill(_killer_id: int, _victim_id: int, _victim_team: int) -> void:
	pass

func is_match_over() -> bool:
	return _over

func get_scores() -> Dictionary:
	return _scores.duplicate()

func assign_team(index: int) -> int:
	return 0

func get_spawn(team: int) -> Vector3:
	return _pick_spawn(team)

# ─── SHARED HELPERS (not part of the frozen contract) ───

func get_team_score(team: int) -> int:
	return int(_scores.get(team, 0))

func elapsed() -> float:
	return _elapsed

func team_name(team: int) -> String:
	return "TIME %d" % (team + 1)

## Score for one participant id (FFA uses ids as teams).
func get_score_of(participant_id: int) -> int:
	return int(_scores.get(participant_id, 0))

func reset() -> void:
	setup(spawn_points)

## Team-aware spawn pick. DETERMINISTIC per round: a per-team cursor walks that
## team's slice, so two participants never get the same point until the slice
## wraps. This used to be `randi()`, which handed the same point to two bots
## often enough to matter: two CharacterBody3D created on one point in one frame
## are depenetrated UPWARDS and launched (npc-body measured 2/2 bots at y~100
## after 120 frames). A cursor also makes spawns reproducible for tests.
func _pick_spawn(team: int) -> Vector3:
	if spawn_points.is_empty():
		return Vector3.ZERO
	var start := 0
	var count := spawn_points.size()
	var key := 0 # FFA: one shared cursor over every point
	if team_count > 1:
		var teams: int = maxi(team_count, 1)
		var per: int = maxi(1, spawn_points.size() / teams)
		var t: int = clampi(team, 0, teams - 1)
		start = t * per
		count = maxi(1, mini(per, spawn_points.size() - start))
		key = t # TDM: each team walks its own slice
	var offset: int = int(_spawn_cursor.get(key, 0))
	_spawn_cursor[key] = offset + 1
	return spawn_points[start + (offset % count)]
