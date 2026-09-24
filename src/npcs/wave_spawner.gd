class_name NpcWaveSpawner
extends Node3D
## Wave-based NpcBot spawner — Fase B (npc-body lane, src/npcs only).
##
## Consumes the frozen GameMode contract (scenes/game_mode.gd):
##   game_mode.team_count        -> fallback team count when no mode
##   game_mode.respawn_delay     -> minimum gap between waves
##   game_mode.friendly_fire     -> forwarded to every spawned bot
##   game_mode.assign_team(index)-> per-bot team
##   game_mode.get_spawn(team)   -> per-bot spawn position
##   game_mode.on_kill(killer, victim, victim_team) -> forwarded on bot death
##
## Each wave spawns `count = base_count + (wave-1)*count_growth` (capped at
## max_count). Difficulty also escalates through the inter-wave gap
## `max(respawn_delay, base_interval * interval_decay^(wave-1))`, floored at
## min_interval. max_waves = 0 means endless. As soon as one wave is dead the
## spawner waits out the gap and launches the next.
##
## Participant indices are handed out monotonically starting at
## `participant_index_start`, so GameMode.assign_team(index) and on_kill()
## attribution stay consistent with the level's own participants (e.g. the
## player is index 0).

signal wave_started(wave: int, count: int)
signal bot_spawned(bot: NpcBot, team: int)
signal all_waves_cleared

const DEFAULT_BOT_SCENE: PackedScene = preload("res://src/npcs/bot/bot.tscn")

@export var bot_scene: PackedScene ## Defaults to bot.tscn when left empty.
@export var game_mode: GameMode = null ## Frozen contract owner (scenes/).
@export var spawn_points: Array[Vector3] = [] ## Local fallback + patrol loops.
@export var participant_index_start: int = 1 ## 0 usually belongs to the player.
@export var auto_start: bool = true
@export var start_delay: float = 1.0
## Optional data-driven loadout. Empty uses NpcBot's neutral default weapon;
## otherwise each wave cycles the supplied resources without hardcoding a
## weapon list in the spawner.
@export var bot_weapon_templates: Array[Weapon] = []

@export_group("Difficulty")
@export var base_count: int = 2
@export var count_growth: int = 1
@export var max_count: int = 8
@export var base_interval: float = 8.0 ## First inter-wave gap (s).
@export var interval_decay: float = 0.85 ## Gap multiplier per wave.
@export var min_interval: float = 2.0 ## Floor for the inter-wave gap.
@export var max_waves: int = 0 ## 0 = endless.

@export_group("Fallback (no game_mode)")
@export var fallback_team_count: int = 2
@export var fallback_friendly_fire: bool = false
@export var fallback_respawn_delay: float = 3.0
## Minimum distance between two bots of the same wave. GameMode.get_spawn() may
## hand out the SAME point twice (FFA picks at random, TDM spreads per team), and
## two overlapping capsules are ejected violently by move_and_slide — bots were
## seen launched ~130 m up. Cheap fix on the consumer side: nudge duplicates.
@export var spawn_separation: float = 0.9

var wave: int = 0
var active_bots: Array[NpcBot] = []

var _participant_index: int = 0
var _spawn_cursor: int = 0
var _running: bool = false
var _group_seq: int = 0
var _used_spawns: Array[Vector3] = []


func _ready() -> void:
	if bot_scene == null:
		bot_scene = DEFAULT_BOT_SCENE
	if auto_start:
		start()


## Begin (or restart) the wave loop.
func start() -> void:
	if _running:
		return
	_running = true
	wave = 0
	_participant_index = participant_index_start
	_schedule_next_wave(start_delay)


## Halt the loop; already-spawned bots are left alive.
func stop() -> void:
	_running = false


## Debug/level API: is the wave loop currently running?
func is_running() -> bool:
	return _running


## Alive bots of the current wave.
func living_count() -> int:
	var n := 0
	for b in active_bots:
		if is_instance_valid(b) and b.is_alive():
			n += 1
	return n


func _schedule_next_wave(delay: float) -> void:
	if not _running or not is_inside_tree():
		return
	await get_tree().create_timer(maxf(delay, 0.0)).timeout
	if not _running or not is_inside_tree():
		return
	_spawn_wave()


func _spawn_wave() -> void:
	if game_mode != null and game_mode.is_match_over():
		_finish()
		return
	wave += 1
	var count := clampi(base_count + (wave - 1) * count_growth, 1, max_count)
	wave_started.emit(wave, count)
	_seed_used_spawns()
	for i in count:
		_spawn_one()
	_wait_wave_end()


func _spawn_one() -> void:
	if bot_scene == null:
		return
	var idx := _participant_index
	_participant_index += 1
	var t := _team_for(idx)
	var pos := _spawn_for(t)
	var bot: NpcBot = bot_scene.instantiate() as NpcBot
	if bot == null:
		return
	_group_seq += 1
	bot.name = "Wave%dBot%d" % [wave, _group_seq]
	if not bot_weapon_templates.is_empty() and bot.has_method("set_weapon_template"):
		var weapon_index := (_group_seq - 1) % bot_weapon_templates.size()
		bot.call("set_weapon_template", bot_weapon_templates[weapon_index])
	bot.set_team(t)
	bot.npc_id = idx
	bot.friendly_fire = _friendly_fire()
	# Place the bot BEFORE it enters the tree: adding it first leaves it at the
	# spawner origin for the rest of the frame, and a whole wave stacked on one
	# point gets ejected violently by move_and_slide (probe: two overlapping
	# capsules were launched to y=100).
	bot.position = global_transform.affine_inverse() * pos
	add_child(bot)
	if not spawn_points.is_empty():
		bot.setup(spawn_points.duplicate())
	if bot.has_signal("died_with_team"):
		var sig: Signal = bot.died_with_team
		if not sig.is_connected(_on_bot_died):
			sig.connect(_on_bot_died)
	elif not bot.died.is_connected(_on_bot_died_legacy):
		bot.died.connect(_on_bot_died_legacy)
	active_bots.append(bot)
	bot_spawned.emit(bot, t)


func _on_bot_died(bot: NpcBot, team: int) -> void:
	active_bots.erase(bot)
	if game_mode != null:
		game_mode.on_kill(bot.last_attacker_id, bot.npc_id, team)


## Fallback for a bot scene that only exposes the legacy died(bot) signal.
func _on_bot_died_legacy(bot: NpcBot) -> void:
	_on_bot_died(bot, bot.team)


func _wait_wave_end() -> void:
	# Active until every bot of this wave is dead (they leave active_bots on
	# died, before the 10 s corpse fade / queue_free).
	while _running and is_inside_tree() and living_count() > 0:
		await get_tree().physics_frame
	if not _running or not is_inside_tree():
		return
	if max_waves > 0 and wave >= max_waves:
		_finish()
		return
	_schedule_next_wave(maxf(_respawn_delay(), _wave_interval(wave)))


func _finish() -> void:
	_running = false
	all_waves_cleared.emit()


# ─── GameMode contract accessors (duck-typed fallbacks when no mode) ───

func _team_for(index: int) -> int:
	if game_mode != null:
		return game_mode.assign_team(index)
	return index % maxi(fallback_team_count, 1)


func _spawn_for(team: int) -> Vector3:
	if game_mode != null:
		var p := game_mode.get_spawn(team)
		# A zero from an unconfigured mode falls back to local points.
		if p != Vector3.ZERO or spawn_points.is_empty():
			return _separated(p)
	if spawn_points.is_empty():
		return global_position
	var p2: Vector3 = spawn_points[_spawn_cursor % spawn_points.size()]
	_spawn_cursor += 1
	return _separated(p2)


## Keep this wave's bots apart: nudge a spawn point that would overlap one
## already used (or a bot still alive from the previous wave).
func _separated(pos: Vector3) -> Vector3:
	var out := pos
	var step := 0
	while _overlaps_used(out) and step < 8:
		step += 1
		# Golden angle: duplicates fan out instead of stacking on one bearing.
		var ang := float(step) * TAU * 0.381966
		var radius := spawn_separation * (1.0 + float(step) / 8.0)
		out = pos + Vector3(cos(ang), 0.0, sin(ang)) * radius
	_used_spawns.append(out)
	return out


func _overlaps_used(p: Vector3) -> bool:
	for u in _used_spawns:
		if Vector2(p.x - u.x, p.z - u.z).length() < spawn_separation:
			return true
	return false


## Fresh wave: remember where the survivors stand so we do not spawn inside them.
func _seed_used_spawns() -> void:
	_used_spawns.clear()
	for b in active_bots:
		if is_instance_valid(b) and b.is_alive():
			_used_spawns.append(b.global_position)


func _respawn_delay() -> float:
	if game_mode != null:
		return game_mode.respawn_delay
	return fallback_respawn_delay


func _friendly_fire() -> bool:
	if game_mode != null:
		return game_mode.friendly_fire
	return fallback_friendly_fire


func _wave_interval(w: int) -> float:
	var decay := pow(interval_decay, maxi(w - 1, 0))
	return maxf(min_interval, base_interval * decay)
