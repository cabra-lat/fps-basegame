class_name NpcBot
extends CharacterBody3D
## NPC bot — perception, teams, cover, squad support, looting and tiers
## (all in the src/npcs lane).
##
## Perception (Fase 2):
##  - Vision: target seen only inside `fov_degrees` (110) AND within effective
##    `sight_range` (60 m, reduced for crouched/still targets, restored while a
##    noise keeps `noise_boost_time` hot) AND with clean LOS (target body or any
##    descendant collider, e.g. the player's TorsoAttachment).
##  - Hearing: `NpcBot.emit_noise(position, loudness)`; radius-gated clue.
##  - Alert states: IDLE -> SUSPICIOUS -> ENGAGED -> SEARCH -> IDLE.
##
## Depth (Fase 2 cont):
##  - Cover: when reloading / low health / under fire without visual contact,
##    probes ring points and walks to one that blocks LOS to the threat
##    (`use_cover`, `current_cover`).
##  - Squad: same-team bots share last known contact via NpcSquad; teammates
##    move in support (flanking) respecting friendly-fire.
##  - Loot: when idle with no threat for a while, walks to nearby group "loot"
##    items or corpses and marks them consumed (signal `loot_consumed`).
##  - Tiers: RECRUIT/REGULAR/VETERAN (NpcTier) change reaction time, shot
##    dispersion, aggression, cover use and weapon cadence.
##  - Debug: `debug_perception` draws cone, hearing circle, chosen cover and the
##    squad-shared target.
##
## Combat contract kept intact: GameMode teams, friendly-fire, died(bot) +
## died_with_team(bot, team), range_hit(impact, ammo, killer_id), death corpse
## 10 s + fade + white hit flash.

signal died(bot: NpcBot)
signal died_with_team(bot: NpcBot, team: int)
signal loot_consumed(loot: Node)

enum AlertState { IDLE, SUSPICIOUS, ENGAGED, SEARCH }

@export_group("Movement")
@export var waypoints: Array = [] ## Array[Vector3] patrol points (world space).
@export var patrol_speed: float = 2.0
@export var chase_speed: float = 3.5

@export_group("Perception")
@export var fov_degrees: float = 110.0 ## Horizontal vision cone width.
@export var sight_range: float = 60.0 ## Max perception distance (m).
@export var engage_range: float = 25.0 ## Inside this, reaction time is shortened.
@export var notice_time: float = 0.8 ## Fallback reaction gate (used if tier off).
@export var search_duration: float = 4.0 ## Look-around time in SUSPICIOUS/SEARCH.
@export var crouch_detection_factor: float = 0.6 ## Sight multiplier vs crouched.
@export var still_detection_factor: float = 0.75 ## Sight multiplier vs still.
@export var noise_radius_scale: float = 30.0 ## Metres per unit of loudness.
@export var noise_boost_time: float = 1.5 ## Noise keeps attention hot (s).

@export_group("Combat")
@export var attack_range: float = 2.2
@export var attack_cooldown: float = 1.5
@export var attack_energy: float = 25.0 ## Joules of the synthetic impact.

@export_group("Teams")
@export var team: int = -1 ## From GameMode.assign_team(); -1 = unassigned.
@export var npc_id: int = -1 ## Participant id for GameMode.on_kill(); -1 = none.
@export var friendly_fire: bool = false ## false: same-team bots are non-hostile.
@export var squad_info_ttl: float = 5.0 ## Seconds a team contact stays fresh.

@export_group("Cover")
@export var use_cover: bool = true
@export var cover_search_radius: float = 6.0
@export var cover_rays: int = 8
@export var cover_probe_interval: float = 0.4
@export var cover_arrive_radius: float = 0.7
@export var low_health_ratio: float = 0.4
@export var under_fire_time: float = 3.0 ## Seconds after damage we still want cover.

@export_group("Loot")
@export var loot_enabled: bool = true
@export var loot_radius: float = 12.0
@export var loot_pick_range: float = 1.2
@export var loot_idle_delay: float = 3.0 ## Threat-free time before looting.

@export_group("Tier")
@export var tier: int = NpcTier.Tier.REGULAR

@export_group("Visuals")
@export var eye_height: float = 1.5
@export var despawn_delay: float = 10.0 ## Corpse lifetime after death (s).
@export var corpse_fade_time: float = 2.0 ## Fade-out at the end of corpse life (s).
@export var visual_variation: bool = true ## Per-bot tint/scale variety at spawn.
@export var debug_perception: bool = false ## Draw perception/cover/squad debug.
@export var debug_hearing_loudness: float = 1.0 ## Reference loudness for circle.

var health: Health
## Participant id of the last attacker (set by range_hit/other bots); -1 unknown.
var last_attacker_id: int = -1
## Current alert state (AlertState enum); read-only for HUD/debug consumers.
var alert_state: int = AlertState.IDLE
## Chosen cover point this frame (Vector3.ZERO = none).
var current_cover: Vector3 = Vector3.ZERO
## Last aim error applied by the tier dispersion (degrees), for tests/HUD.
var last_shot_error_deg: float = 0.0

# Tier-derived tuning (see _apply_tier).
var reaction_time: float = 0.7
var shot_dispersion_deg: float = 3.0
var aggression: float = 1.0
var cover_use: float = 0.85
var burst_shots: int = 4
var reload_time: float = 2.0

var _wp_index: int = 0
# Duck-typed target ref (any CharacterBody3D exposing `health: Health`).
var _target: Node3D = null
var _target_visible: bool = false
var _retarget_t: float = 0.0
var _notice_t: float = 0.0
var _attack_t: float = 0.0
var _search_t: float = 0.0
var _investigate_pos: Vector3 = Vector3.ZERO
var _last_known_pos: Vector3 = Vector3.ZERO
var _last_noise_pos: Vector3 = Vector3.ZERO
var _noise_boost_t: float = 0.0
var _under_fire_t: float = 0.0
var _threat_pos: Vector3 = Vector3.ZERO
var _cover_t: float = 0.0
var _reloading: bool = false
var _reload_t: float = 0.0
var _shots_in_burst: int = 0
var _idle_t: float = 0.0
var _loot_target: Node3D = null
var _loot_t: float = 0.0
var _looted: Dictionary = {}
var _squad_pos: Vector3 = Vector3.ZERO
var _squad_has: bool = false
var _dead: bool = false
var _despawn_t: float = 0.0
var _fall_t: float = 0.0
var _base_basis: Basis
# ── hit feedback + corpse visuals ──
const HIT_FLASH_TIME: float = 0.12
const HIT_FLASH_ENERGY: float = 3.0
const RETARGET_INTERVAL: float = 0.5 ## Seconds between enemy rescans.
const SEARCH_ARRIVE_RADIUS: float = 0.8
const SEARCH_LOOK_SPEED: float = 1.8 ## rad/s while sweeping a clue.
const CLOSE_REACTION_SCALE: float = 0.35 ## Reaction gate inside engage_range.
const LOOT_RESCAN_INTERVAL: float = 1.0
const DEBUG_REFRESH_HZ: float = 10.0
var _hit_flash_t: float = 0.0
var _mat: StandardMaterial3D = null ## Per-instance body material (tint/flash/fade).
var _base_albedo: Color = Color(0.8, 0.1, 0.1, 1.0)
var _debug_mi: MeshInstance3D = null
var _debug_mesh: ImmediateMesh = null
var _debug_t: float = 0.0


func _ready() -> void:
	add_to_group("bots")
	_ensure_own_material()
	if visual_variation:
		_apply_visual_variation()
	if team >= 0:
		_apply_team_tint()
	_apply_tier()
	_base_basis = global_transform.basis
	if health == null:
		health = Health.new()
	if not health.player_died.is_connected(_die):
		health.player_died.connect(_die)
	if not health.health_changed.is_connected(_on_damaged):
		health.health_changed.connect(_on_damaged)
	set_up_direction(Vector3.UP)
	set_floor_snap_length(0.3)
	_setup_debug()


func setup(p_waypoints: Array) -> void:
	waypoints = p_waypoints.duplicate()
	_wp_index = 0


func is_alive() -> bool:
	return not _dead


## Debug/HUD hook: current alert state as text.
func alert_state_name() -> String:
	match alert_state:
		AlertState.SUSPICIOUS: return "SUSPICIOUS"
		AlertState.ENGAGED: return "ENGAGED"
		AlertState.SEARCH: return "SEARCH"
		_: return "IDLE"


func tier_name() -> String:
	return NpcTier.tier_name(tier)


func is_reloading() -> bool:
	return _reloading


## Debug/HUD hook (no in-repo caller yet; kept as API).
func is_target_visible() -> bool:
	return _target_visible


## Debug/HUD hook: current investigate point.
func has_clue() -> Vector3:
	return _investigate_pos


## Debug/spotter hook: chosen cover point this frame.
func cover_position() -> Vector3:
	return current_cover


## Debug/spotter hook: team-shared contact (ZERO when none).
func squad_target() -> Vector3:
	return _squad_pos if _squad_has else Vector3.ZERO


## Public API: assign a difficulty tier (NpcTier.enum); spawner/level may call
## this per bot. Safe at runtime.
func set_tier(t: int) -> void:
	tier = t
	_apply_tier()


func _apply_tier() -> void:
	var c: Dictionary = NpcTier.config(tier)
	reaction_time = c.get("reaction_time", 0.7)
	shot_dispersion_deg = c.get("shot_dispersion_deg", 3.0)
	aggression = c.get("aggression", 1.0)
	cover_use = c.get("cover_use", 0.85)
	burst_shots = int(c.get("burst_shots", burst_shots))
	reload_time = c.get("reload_time", reload_time)


## Begin a reload window (also entered automatically after a burst).
func start_reload() -> void:
	if _reloading or _dead:
		return
	_reloading = true
	_reload_t = reload_time


# ─── HEARING API (called by the game) ───

## Broadcast a world noise. The game calls e.g.
##   NpcBot.emit_noise(shooter.global_position, 2.0)   # gunshot
##   NpcBot.emit_noise(feet.global_position, 0.4)      # crouch-walk
## loudness is in "units": radius = loudness * noise_radius_scale (default 30 m).
static func emit_noise(position: Vector3, loudness: float) -> void:
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree):
		return
	for n in (ml as SceneTree).get_nodes_in_group("bots"):
		if n is NpcBot:
			(n as NpcBot).hear_noise(position, loudness)


## One bot receiving a noise. Radius-gated; inside it the clue is approximate
## (jitter grows with distance). Engaged bots only refresh attention.
func hear_noise(position: Vector3, loudness: float) -> void:
	if _dead or loudness <= 0.0:
		return
	var d := global_position.distance_to(position)
	if d > loudness * noise_radius_scale:
		return
	_noise_boost_t = noise_boost_time
	_last_noise_pos = _approximate_noise(position, d)
	if alert_state == AlertState.ENGAGED:
		return
	_enter(AlertState.SUSPICIOUS)
	_investigate_pos = _last_noise_pos
	_search_t = search_duration


func _approximate_noise(position: Vector3, d: float) -> Vector3:
	var err := minf(d * 0.15, 3.0)
	if err <= 0.0:
		return position
	return position + Vector3(
		randf_range(-err, err), 0.0, randf_range(-err, err))


# ─── TEAM / DAMAGE (Fase B contract) ───

## Team assignment from GameMode.assign_team(index): applies the team tint and
## makes died_with_team report it. -1 clears the tint back to the varied body.
func set_team(t: int) -> void:
	team = t
	_apply_team_tint()


func participant_id() -> int:
	return npc_id


## Called by another bot before landing a melee hit (kill attribution).
func set_attacker(id: int) -> void:
	if id >= 0:
		last_attacker_id = id


## Tell the bot roughly where incoming fire came from (cover + squad reaction).
func report_threat(pos: Vector3) -> void:
	if _dead:
		return
	_threat_pos = pos
	_under_fire_t = under_fire_time


## Called by the range resolver (same duck-type as RangeTarget). Optional
## killer_id lets the resolver attribute the kill to the player participant.
func range_hit(impact: BallisticsImpact, ammo: Ammo, killer_id: int = -1) -> void:
	if _dead:
		return
	set_attacker(killer_id)
	_threat_from_killer(killer_id)
	var res: Dictionary = health.take_ballistic_damage(
		impact, BodyPart.Type.UPPER_CHEST, ammo)
	if res.get("fatal", false):
		_die("shot")
	elif not res.is_empty():
		_hit_flash_t = HIT_FLASH_TIME
		_apply_flash()


func _threat_from_killer(killer_id: int) -> void:
	if killer_id < 0 or not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("bots"):
		if n is NpcBot and n != self \
				and (n as NpcBot).npc_id == killer_id:
			report_threat((n as NpcBot).global_position)
			return


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 9.8 * 4.0 * delta
	else:
		velocity.y = -0.5
	if _dead:
		_tick_death(delta)
		return
	_tick_flash(delta)
	_attack_t = maxf(0.0, _attack_t - delta)
	_noise_boost_t = maxf(0.0, _noise_boost_t - delta)
	_under_fire_t = maxf(0.0, _under_fire_t - delta)
	if _reloading:
		_reload_t -= delta
		if _reload_t <= 0.0:
			_reloading = false
	_perceive(delta)
	_update_cover(delta)
	_tick_debug(delta)
	var move_dir := Vector3.ZERO
	var speed := patrol_speed * aggression
	if _wants_cover() and current_cover != Vector3.ZERO:
		var to_cover := current_cover - global_position
		to_cover.y = 0.0
		if to_cover.length() > cover_arrive_radius:
			move_dir = to_cover.normalized()
			speed = patrol_speed * 1.4
		else:
			var to_threat := _threat_position() - global_position
			to_threat.y = 0.0
			if to_threat.length_squared() > 0.0001:
				_face(to_threat.normalized(), delta)
	elif alert_state == AlertState.ENGAGED and _is_valid_target(_target):
		var to_target := _target.global_position - global_position
		to_target.y = 0.0
		var dist := to_target.length()
		if dist <= attack_range:
			_face(to_target.normalized(), delta)
			_try_attack()
		else:
			move_dir = to_target.normalized()
			speed = chase_speed * aggression
	elif alert_state == AlertState.SUSPICIOUS or alert_state == AlertState.SEARCH:
		_search_t -= delta
		if _search_t <= 0.0:
			_enter(AlertState.IDLE)
		else:
			var to_clue := _investigate_pos - global_position
			to_clue.y = 0.0
			if to_clue.length() > SEARCH_ARRIVE_RADIUS:
				move_dir = to_clue.normalized()
				speed = patrol_speed * 1.5
			else:
				rotation.y += delta * SEARCH_LOOK_SPEED
	elif alert_state == AlertState.IDLE and loot_enabled \
			and _idle_t >= loot_idle_delay:
		_tick_loot(delta)
		if is_instance_valid(_loot_target):
			var to_loot := _loot_target.global_position - global_position
			to_loot.y = 0.0
			if to_loot.length() > loot_pick_range:
				move_dir = to_loot.normalized()
			else:
				_consume_loot(_loot_target)
	elif not waypoints.is_empty():
		var target: Vector3 = waypoints[_wp_index]
		var to_wp := target - global_position
		to_wp.y = 0.0
		if to_wp.length() < 0.6:
			_wp_index = (_wp_index + 1) % waypoints.size()
		else:
			move_dir = to_wp.normalized()
	if move_dir != Vector3.ZERO:
		_face(move_dir, delta)
		velocity.x = move_dir.x * speed
		velocity.z = move_dir.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * delta)
	move_and_slide()


func _face(dir: Vector3, _delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, 0.15)


# ─── PERCEPTION ───

func _perceive(delta: float) -> void:
	_retarget_t -= delta
	if _retarget_t <= 0.0 or not _is_valid_target(_target):
		_acquire_target()
		_retarget_t = RETARGET_INTERVAL
	var seen := _can_see_target()
	_target_visible = seen
	if seen:
		_last_known_pos = _target.global_position
		_notice_t += delta
		var dist := global_position.distance_to(_target.global_position)
		var need := reaction_time if reaction_time > 0.0 else notice_time
		if dist <= _engage_range():
			need *= CLOSE_REACTION_SCALE
		if alert_state == AlertState.ENGAGED or _notice_t >= need:
			_enter(AlertState.ENGAGED)
		else:
			_enter(AlertState.SUSPICIOUS)
			_investigate_pos = _target.global_position
			_search_t = search_duration
		if team >= 0:
			NpcSquad.publish(team, _last_known_pos, alert_state, npc_id)
	else:
		_notice_t = 0.0
		if alert_state == AlertState.ENGAGED:
			_investigate_pos = _last_known_pos
			_enter(AlertState.SEARCH)
	_share_squad(seen)
	if alert_state == AlertState.IDLE:
		_idle_t += delta
	else:
		_idle_t = 0.0


## Same-team support: move toward a teammate's fresh contact (flanking) unless
## we are already engaging ourselves.
func _share_squad(seen: bool) -> void:
	_squad_has = false
	if team < 0 or seen or alert_state == AlertState.ENGAGED:
		return
	var info := NpcSquad.get_info(team, squad_info_ttl)
	if info.is_empty():
		return
	_squad_pos = info.get("pos", Vector3.ZERO)
	_squad_has = true
	if alert_state == AlertState.IDLE:
		_enter(AlertState.SUSPICIOUS)
	if alert_state == AlertState.SUSPICIOUS or alert_state == AlertState.SEARCH:
		_investigate_pos = _squad_pos
		_search_t = search_duration


func _enter(new_state: int) -> void:
	if new_state == alert_state:
		return
	alert_state = new_state
	match alert_state:
		AlertState.SUSPICIOUS, AlertState.SEARCH:
			_search_t = search_duration
		AlertState.ENGAGED:
			_notice_t = 0.0


## Cone + effective range + LOS against the current candidate.
func _can_see_target() -> bool:
	if not _is_valid_target(_target):
		return false
	var eye := global_position + Vector3.UP * eye_height
	var to_target: Vector3 = _target.global_position + Vector3.UP * 1.2 - eye
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	var dist := flat.length()
	var eff := NpcPerception.effective_sight_range(
		_target, sight_range, crouch_detection_factor, still_detection_factor,
		_noise_boost_t > 0.0)
	if dist > eff:
		return false
	if not NpcPerception.in_cone(self, flat, fov_degrees):
		return false
	return _has_los()


func _engage_range() -> float:
	return engage_range * aggression


## Nearest hostile CharacterBody3D with health; rescanned on a short interval.
func _acquire_target() -> void:
	_target = NpcTargeting.acquire(
		self, get_tree().current_scene, team, friendly_fire)


func _is_valid_target(n) -> bool:
	return NpcTargeting.is_valid_target(self, n, team, friendly_fire)


## Friendly-fire rule: with friendly_fire off, a bot never treats its own team
## as hostile (see NpcTargeting.is_hostile).
func _is_hostile(n: Node) -> bool:
	return NpcTargeting.is_hostile(n, team, friendly_fire)


## Physics-frame-only raycast (AGENTS.md rule 4): eye -> target chest.
func _has_los() -> bool:
	if not is_instance_valid(_target):
		return false
	var from := global_position + Vector3.UP * eye_height
	var to: Vector3 = _target.global_position + Vector3.UP * 1.2
	var hit := NpcCover.raycast(self, from, to)
	if hit.is_empty():
		return true
	return NpcCover.collider_belongs_to(_target, hit.collider)


# ─── COVER ───

func _wants_cover() -> bool:
	if not use_cover or cover_use <= 0.0 or _dead:
		return false
	if alert_state == AlertState.ENGAGED:
		return false
	if _reloading:
		return true
	if health != null and health.health_percentage < low_health_ratio:
		return true
	if _under_fire_t > 0.0:
		return true
	return false


func _threat_position() -> Vector3:
	if _is_valid_target(_target):
		return _target.global_position
	if _last_known_pos != Vector3.ZERO:
		return _last_known_pos
	if _squad_has:
		return _squad_pos
	if _last_noise_pos != Vector3.ZERO:
		return _last_noise_pos
	if _under_fire_t > 0.0:
		return _threat_pos
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	return global_position + fwd.normalized() * 10.0


func _update_cover(delta: float) -> void:
	if not _wants_cover():
		current_cover = Vector3.ZERO
		return
	_cover_t -= delta
	if current_cover != Vector3.ZERO and _cover_t > 0.0:
		return
	_cover_t = cover_probe_interval
	var radius := cover_search_radius * (0.6 + 0.4 * clampf(cover_use, 0.0, 1.0))
	current_cover = NpcCover.find_cover(
		self, _threat_position(), radius, cover_rays, eye_height, _threat_node())


## Best-effort node for the current threat (used for descendant LOS).
func _threat_node() -> Node:
	if _is_valid_target(_target):
		return _target
	return null


# ─── LOOT ───

func _tick_loot(delta: float) -> void:
	if is_instance_valid(_loot_target) \
			and not _looted.has(_loot_target.get_instance_id()):
		return
	_loot_t -= delta
	if _loot_t > 0.0:
		return
	_loot_t = LOOT_RESCAN_INTERVAL
	_loot_target = NpcLoot.find_nearest(self, loot_radius, _looted)


func _consume_loot(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	_looted[node.get_instance_id()] = true
	node.set_meta("consumed", true)
	node.set_meta("consumed_by", npc_id)
	_loot_target = null
	loot_consumed.emit(node)


# ─── COMBAT ───

func _try_attack() -> void:
	if _attack_t > 0.0 or _reloading:
		return
	if not _is_valid_target(_target):
		return
	var h: Health = _target.get("health") as Health
	if h == null:
		return
	_attack_t = attack_cooldown
	# Tier dispersion: rotate the shot direction by a random error.
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() > 0.0001:
		var dir := to_target.normalized()
		last_shot_error_deg = 0.0
		if shot_dispersion_deg > 0.0:
			last_shot_error_deg = randf_range(
				-shot_dispersion_deg, shot_dispersion_deg)
			dir = dir.rotated(Vector3.UP, deg_to_rad(last_shot_error_deg))
		_face(dir, 0.0)
	if _target is NpcBot:
		(_target as NpcBot).set_attacker(npc_id)
		(_target as NpcBot).report_threat(global_position)
	var impact := BallisticsImpact.new()
	impact.hit_energy = attack_energy
	impact.thickness = 0.0
	impact.angle = 0.0
	h.take_ballistic_damage(impact, BodyPart.Type.UPPER_CHEST, null)
	_shots_in_burst += 1
	if burst_shots > 0 and _shots_in_burst >= burst_shots:
		_shots_in_burst = 0
		start_reload()


func _die(_cause: String = "") -> void:
	if _dead:
		return
	_dead = true
	_despawn_t = despawn_delay
	_fall_t = 0.0
	velocity = Vector3.ZERO
	set_collision_layer(0)
	set_collision_mask(0)
	if _mat != null:
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	died.emit(self)
	died_with_team.emit(self, team)


func _tick_death(delta: float) -> void:
	if _fall_t < 1.0:
		_fall_t = minf(1.0, _fall_t + delta * 2.5)
		var rot := Basis(Vector3.RIGHT, _fall_t * deg_to_rad(85.0))
		global_transform = Transform3D(
			_base_basis * rot, global_position)
		move_and_slide()
	_despawn_t -= delta
	if _mat != null and corpse_fade_time > 0.0 \
			and _despawn_t <= corpse_fade_time:
		var a := clampf(_despawn_t / corpse_fade_time, 0.0, 1.0)
		var c := _base_albedo
		c.a = a
		_mat.albedo_color = c
	if _despawn_t <= 0.0:
		queue_free()


# ─── DEBUG DRAW (cone, hearing, cover, squad target) ───

## Debug/spotter hook: toggle the perception/cover/squad overlay at runtime.
func set_debug_perception(enabled: bool) -> void:
	debug_perception = enabled
	if enabled:
		if _debug_mesh == null:
			_setup_debug()
	elif _debug_mi != null:
		_debug_mi.queue_free()
		_debug_mi = null
		_debug_mesh = null


func _setup_debug() -> void:
	if not debug_perception or _debug_mesh != null:
		return
	var parts := NpcDebug.setup(self, eye_height)
	_debug_mi = parts[0]
	_debug_mesh = parts[1]


func _tick_debug(delta: float) -> void:
	if _debug_mesh == null:
		return
	_debug_t -= delta
	if _debug_t > 0.0:
		return
	_debug_t = 1.0 / DEBUG_REFRESH_HZ
	_redraw_debug()


func _redraw_debug() -> void:
	NpcDebug.draw(_debug_mi, _debug_mesh, {
		"fov_degrees": fov_degrees,
		"sight_range": sight_range,
		"noise_radius_scale": noise_radius_scale,
		"hearing_loudness": debug_hearing_loudness,
		"eye_height": eye_height,
		"cone_color": _state_debug_color(),
		"cover": current_cover,
		"squad_has": _squad_has,
		"squad_pos": _squad_pos,
	})


func _state_debug_color() -> Color:
	match alert_state:
		AlertState.SUSPICIOUS: return Color(1.0, 0.85, 0.1, 0.8)
		AlertState.ENGAGED: return Color(1.0, 0.2, 0.15, 0.9)
		AlertState.SEARCH: return Color(1.0, 0.55, 0.1, 0.8)
		_: return Color(0.9, 0.9, 0.9, 0.6)


# ─── visuals: own material, variation, team tint, hit flash ───

## Duplicate the shared tscn material so tint/flash/fade stay per-bot.
func _ensure_own_material() -> void:
	_mat = NpcVisuals.own_material(
		get_node_or_null("MeshInstance3D") as MeshInstance3D)
	if _mat != null:
		_base_albedo = _mat.albedo_color


## Slight per-bot identity: body scale + reddish tint jitter. Runs before
## _base_basis capture so the corpse keeps its scale.
func _apply_visual_variation() -> void:
	scale = Vector3.ONE * randf_range(0.94, 1.06)
	if _mat != null:
		_base_albedo = NpcVisuals.varied_albedo(_base_albedo)
		_mat.albedo_color = _base_albedo


## Team tint reuses the per-instance material; keeps the varied scale.
func _apply_team_tint() -> void:
	if _mat == null or _dead or team < 0:
		return
	var c := NpcVisuals.team_color(team)
	_base_albedo = Color(c.r, c.g, c.b, 1.0)
	_mat.albedo_color = _base_albedo


## Any non-fatal Health damage path flashes and marks the bot under fire.
func _on_damaged(_part: BodyPart, _old_health: float, _new_health: float) -> void:
	if _dead:
		return
	_hit_flash_t = HIT_FLASH_TIME
	_under_fire_t = under_fire_time
	_apply_flash()


func _tick_flash(delta: float) -> void:
	if _hit_flash_t <= 0.0:
		return
	_hit_flash_t = maxf(0.0, _hit_flash_t - delta)
	_apply_flash()


func _apply_flash() -> void:
	NpcVisuals.apply_flash(_mat, _hit_flash_t, HIT_FLASH_TIME, HIT_FLASH_ENERGY)
